//! The ONE implementation of one-time contact-method codes, shared by every flow that proves
//! control of a phone number or email address:
//!
//! - `StartContactMethodVerification`/`VerifyContactMethod` (an account verifying its own contact
//!   method; the code lives on the user's `ContactMethod.verification_in_progress`),
//! - SMS/email `Login` (same storage -- the account already owns the verified contact method),
//! - `CreateAccount` with a phone/email (no account yet, so the code's hash lives in
//!   `pending_contact_verifications`, see `models::pending_contact_verification_models`).
//!
//! Everything about a code -- generation, hashing, TTL, attempt cap, resend cooldown, constant-time
//! comparison, contact-value normalization, outbound dispatch (`tel:` -> SMS provider, `mailto:`
//! -> email provider), "which verified accounts own this contact" -- is defined here so the flows
//! can't drift apart. See `docs/contact_integrations.md` ("SMS and email login").

use std::time::{Duration, SystemTime};

use diesel::dsl::sql;
use diesel::sql_types::{Bool, Text};
use diesel::*;
use rand::RngExt;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    contact_protocol_supported, email_sending_available, send_verification_email,
    send_verification_sms, verification_available,
};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_model;
use crate::rpcs::validations::{validate_email, validate_phone};
use crate::schema::users;

/// Codes expire this long after being sent -- see `LoginRequest`/`CreateAccountRequest`'s docs.
pub const CODE_TTL: Duration = Duration::from_secs(10 * 60);
/// Wrong guesses allowed against one code. Caps brute force of the 6-digit (1M combinations) code
/// within its TTL -- see `ContactMethodVerification.attempts`'s own doc.
pub const MAX_ATTEMPTS: i32 = 5;
/// Minimum time between two sends to the same contact method -- SMS/email cost money and this is
/// an abuse vector, so this is a hard requirement, not merely a courtesy.
pub const RESEND_COOLDOWN: Duration = Duration::from_secs(60);

/// Which of a user's two contact methods (`users.phone`/`users.email`) -- and hence which
/// `tel:`/`mailto:` scheme and outbound provider -- a flow is dealing with.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ContactKind {
    Phone,
    Email,
}

impl ContactKind {
    /// Kind of a `tel:`/`mailto:` value (by scheme), if it is one.
    pub fn from_value(value: &str) -> Option<ContactKind> {
        if value.starts_with("tel:") {
            Some(ContactKind::Phone)
        } else if value.starts_with("mailto:") {
            Some(ContactKind::Email)
        } else {
            None
        }
    }

    pub fn scheme(self) -> &'static str {
        match self {
            ContactKind::Phone => "tel:",
            ContactKind::Email => "mailto:",
        }
    }

    pub fn protocol(self) -> ContactProtocol {
        match self {
            ContactKind::Phone => ContactProtocol::Tel,
            ContactKind::Email => ContactProtocol::Mailto,
        }
    }

    pub fn login_feature(self) -> AuthenticationFeature {
        match self {
            ContactKind::Phone => AuthenticationFeature::LoginWithSms,
            ContactKind::Email => AuthenticationFeature::LoginWithEmail,
        }
    }

    pub fn create_account_feature(self) -> AuthenticationFeature {
        match self {
            ContactKind::Phone => AuthenticationFeature::CreateAccountWithSms,
            ContactKind::Email => AuthenticationFeature::CreateAccountWithEmail,
        }
    }

    /// The error a flow returns when this kind's provider isn't set up.
    pub fn not_configured_error(self) -> Status {
        Status::new(
            Code::FailedPrecondition,
            match self {
                ContactKind::Phone => "verification_not_configured",
                ContactKind::Email => "email_verification_not_configured",
            },
        )
    }
}

// ---------------------------------------------------------------------------------------------
// Server capabilities
// ---------------------------------------------------------------------------------------------

/// Whether the admin has `feature` in `ServerConfiguration.authentication_features`.
pub fn authentication_feature_enabled(
    conn: &mut PgPooledConnection,
    feature: AuthenticationFeature,
) -> bool {
    get_server_configuration_model(conn)
        .map(|c| c.authentication_features.to_proto_authentication_features())
        .unwrap_or_default()
        .contains(&feature)
}

/// Whether the server can currently send a code to a `kind` contact method (protocol listed in
/// `supported_contact_protocols` *and* a provider enabled).
pub fn contact_protocol_ready(conn: &mut PgPooledConnection, kind: ContactKind) -> bool {
    match kind {
        ContactKind::Phone => verification_available(conn),
        ContactKind::Email => {
            #[cfg(test)]
            if email_capture::enabled() {
                return true;
            }
            email_sending_available(conn)
        }
    }
}

/// Whether `kind` is supported for `supported_by_server` purposes (kept next to
/// `contact_protocol_ready` so both agree on what "supported" means for a scheme).
pub fn contact_protocol_listed(conn: &mut PgPooledConnection, kind: ContactKind) -> bool {
    contact_protocol_supported(conn, kind.protocol())
}

/// Sends `code` to `contact_value` (`tel:`/`mailto:`) via the matching provider. `base_url`, if
/// `Some`, overrides the provider's API host so specs can point at a mock server.
pub fn send_verification_code(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    contact_value: &str,
    code: &str,
) -> Result<(), Status> {
    match ContactKind::from_value(contact_value) {
        Some(ContactKind::Phone) => send_verification_sms(base_url, conn, contact_value, code),
        Some(ContactKind::Email) => {
            #[cfg(test)]
            if email_capture::capture(contact_value, code) {
                return Ok(());
            }
            send_verification_email(base_url, conn, contact_value, code)
        }
        None => Err(Status::new(
            Code::InvalidArgument,
            "value_must_be_a_tel_or_mailto_url",
        )),
    }
}

/// Test seam for the email path: while enabled on the current thread, `mailto:` sends are recorded
/// here instead of going to a provider (and email counts as available). Each `#[test]` runs on its
/// own thread and RPCs run synchronously on it, so this is isolated per spec.
#[cfg(test)]
pub mod email_capture {
    use std::cell::RefCell;

    thread_local! {
        static CAPTURED: RefCell<Option<Vec<(String, String)>>> = const { RefCell::new(None) };
    }

    /// Starts capturing on this thread.
    pub fn start() {
        CAPTURED.with(|c| *c.borrow_mut() = Some(Vec::new()));
    }

    pub fn enabled() -> bool {
        CAPTURED.with(|c| c.borrow().is_some())
    }

    pub(super) fn capture(to: &str, code: &str) -> bool {
        CAPTURED.with(|c| match c.borrow_mut().as_mut() {
            Some(v) => {
                v.push((to.to_string(), code.to_string()));
                true
            }
            None => false,
        })
    }

    /// Every `(to, code)` captured so far, oldest first.
    pub fn sent() -> Vec<(String, String)> {
        CAPTURED.with(|c| c.borrow().clone().unwrap_or_default())
    }
}

// ---------------------------------------------------------------------------------------------
// Contact value normalization
// ---------------------------------------------------------------------------------------------

/// Normalizes a client-supplied phone number/email into the canonical stored `tel:`/`mailto:`
/// form (a leading scheme is optional; emails are trimmed and lowercased) and validates it.
pub fn normalize_contact_value(kind: ContactKind, raw: &str) -> Result<String, Status> {
    let raw = raw.trim();
    match kind {
        ContactKind::Phone => {
            let number = raw.strip_prefix("tel:").unwrap_or(raw);
            let value = format!("tel:{number}");
            validate_phone(&Some(value.clone()))?;
            Ok(value)
        }
        ContactKind::Email => {
            let lowered = raw.to_lowercase();
            let address = lowered.strip_prefix("mailto:").unwrap_or(&lowered);
            let value = format!("mailto:{address}");
            validate_email(&Some(value.clone()))?;
            let invalid = || Status::new(Code::InvalidArgument, "email_must_be_a_valid_address");
            let (local, domain) = address.split_once('@').ok_or_else(invalid)?;
            let forbidden = |c: char| c.is_whitespace() || c.is_control() || "<>,;:\"'()[]\\".contains(c);
            if local.is_empty()
                || domain.contains('@')
                || !domain.contains('.')
                || domain.starts_with('.')
                || domain.ends_with('.')
                || address.chars().any(forbidden)
            {
                return Err(invalid());
            }
            Ok(value)
        }
    }
}

/// Whether two stored/normalized contact values are the same contact (emails compare
/// case-insensitively).
pub fn contact_values_match(kind: ContactKind, a: &str, b: &str) -> bool {
    match kind {
        ContactKind::Phone => a == b,
        ContactKind::Email => a.eq_ignore_ascii_case(b),
    }
}

// ---------------------------------------------------------------------------------------------
// Codes
// ---------------------------------------------------------------------------------------------

/// A fresh 6-digit code.
pub fn generate_code() -> String {
    format!("{:06}", rand::rng().random_range(0..1_000_000))
}

/// Hex SHA-256 of `"<contact_value>:<code>"` -- what `pending_contact_verifications.code_hash`
/// stores (never the code itself).
pub fn hash_code(contact_value: &str, code: &str) -> String {
    let digest = ring::digest::digest(
        &ring::digest::SHA256,
        format!("{contact_value}:{code}").as_bytes(),
    );
    digest.as_ref().iter().map(|b| format!("{b:02x}")).collect()
}

/// Constant-time (in the content; only the length can short-circuit) string comparison.
pub fn constant_time_eq(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |diff, (x, y)| diff | (x ^ y)) == 0
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CodeVerdict {
    Valid,
    Expired,
    TooManyAttempts,
    Incorrect,
    /// No code was ever sent (or it was already cleared).
    NotStarted,
}

/// The single decision procedure for a submitted code, given when the code was sent, how many wrong
/// guesses it has taken already, and whether this guess matched.
pub fn judge_code(started_at: SystemTime, attempts: i32, code_matches: bool) -> CodeVerdict {
    if started_at + CODE_TTL < SystemTime::now() {
        CodeVerdict::Expired
    } else if attempts >= MAX_ATTEMPTS {
        CodeVerdict::TooManyAttempts
    } else if code_matches {
        CodeVerdict::Valid
    } else {
        CodeVerdict::Incorrect
    }
}

/// The error a failed verdict maps to in the authenticated verification flow and create-account.
/// (SMS/email *login* collapses every failure into `incorrect_code` -- see `rpcs::login`.)
pub fn verdict_status(verdict: CodeVerdict) -> Status {
    match verdict {
        CodeVerdict::Valid => Status::new(Code::Internal, "valid_code_is_not_an_error"),
        CodeVerdict::Expired => Status::new(Code::FailedPrecondition, "verification_expired"),
        CodeVerdict::TooManyAttempts => {
            Status::new(Code::FailedPrecondition, "too_many_attempts")
        }
        CodeVerdict::Incorrect => Status::new(Code::InvalidArgument, "incorrect_code"),
        CodeVerdict::NotStarted => {
            Status::new(Code::FailedPrecondition, "no_verification_in_progress")
        }
    }
}

/// Judges `submitted` against `contact`'s `verification_in_progress`, updating `contact` in place:
/// cleared on success/expiry/too many attempts, `attempts` bumped on a wrong guess. The caller must
/// persist `contact` afterwards whatever the verdict (and, on `Valid`, apply whatever the success
/// means -- e.g. `verified_at`).
pub fn check_contact_code(contact: &mut ContactMethod, submitted: &str) -> CodeVerdict {
    let Some(mut verification) = contact.verification_in_progress.clone() else {
        return CodeVerdict::NotStarted;
    };
    let started_at: SystemTime = verification
        .verification_started_at
        .as_ref()
        .map(|t| t.to_db())
        .unwrap_or(SystemTime::UNIX_EPOCH);
    let verdict = judge_code(
        started_at,
        verification.attempts,
        constant_time_eq(&verification.verification_code, submitted),
    );
    match verdict {
        CodeVerdict::Incorrect => {
            verification.attempts += 1;
            contact.verification_in_progress = Some(verification);
        }
        _ => contact.verification_in_progress = None,
    }
    verdict
}

/// Whether `contact` was sent a code less than `RESEND_COOLDOWN` ago.
pub fn cooldown_active(contact: &ContactMethod) -> bool {
    contact
        .verification_in_progress
        .as_ref()
        .and_then(|v| v.verification_started_at.as_ref())
        .is_some_and(|t| {
            let started_at: SystemTime = t.to_db();
            started_at + RESEND_COOLDOWN > SystemTime::now()
        })
}

pub fn consent_granted(contact: &ContactMethod) -> bool {
    ContactConsentState::try_from(contact.consent_state).unwrap_or_default()
        == ContactConsentState::ContactConsentGranted
}

/// The `VerificationChallenge` the first phase of a two-phase login/create-account returns.
pub fn verification_challenge(sent_to: Vec<String>) -> VerificationChallenge {
    let now = SystemTime::now();
    VerificationChallenge {
        sent_to,
        expires_at: Some((now + CODE_TTL).to_proto()),
        resend_available_at: Some((now + RESEND_COOLDOWN).to_proto()),
    }
}

// ---------------------------------------------------------------------------------------------
// A user's own contact methods
// ---------------------------------------------------------------------------------------------

/// `user`'s stored `kind` contact method, if it has one that parses.
pub fn user_contact(user: &models::User, kind: ContactKind) -> Option<ContactMethod> {
    match kind {
        ContactKind::Phone => user.phone.clone(),
        ContactKind::Email => user.email.clone(),
    }
    .and_then(|v| serde_json::from_value(v).ok())
}

pub fn persist_user_contact(
    conn: &mut PgPooledConnection,
    user_id: i64,
    kind: ContactKind,
    contact: &ContactMethod,
) -> Result<(), Status> {
    let json = serde_json::to_value(contact).unwrap();
    let target = users::table.filter(users::id.eq(user_id));
    match kind {
        ContactKind::Phone => diesel::update(target)
            .set(users::phone.eq(json))
            .execute(conn),
        ContactKind::Email => diesel::update(target)
            .set(users::email.eq(json))
            .execute(conn),
    }
    .map(|_| ())
    .map_err(|e| {
        log::error!("Failed to persist {:?} contact verification state: {:?}", kind, e);
        Status::new(Code::Internal, "data_error")
    })
}

/// Generates a code, sends it to `contact`'s value, and stores it as `verification_in_progress`
/// on `user_id`'s `kind` contact method. Returns the updated contact method (INCLUDING the real
/// code -- blank it before returning it to a client). Callers gate on consent/cooldown/provider
/// availability themselves (their error handling differs: the authenticated verify RPC reports
/// each, login must not).
pub fn begin_user_contact_verification(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    user_id: i64,
    kind: ContactKind,
    contact: &ContactMethod,
    value: &str,
) -> Result<ContactMethod, Status> {
    let code = generate_code();
    send_verification_code(base_url, conn, value, &code)?;
    let updated = ContactMethod {
        supported_by_server: true,
        verification_in_progress: Some(ContactMethodVerification {
            verification_code: code,
            verification_started_at: Some(SystemTime::now().to_proto()),
            attempts: 0,
        }),
        // Verification never touches consent/verified_at -- carried forward unchanged.
        ..contact.clone()
    };
    persist_user_contact(conn, user_id, kind, &updated)?;
    Ok(updated)
}

/// Every user (by id) with `value` stored as a *verified* `kind` contact method, paired with that
/// contact method. Emails match case-insensitively.
pub fn find_users_with_verified_contact(
    conn: &mut PgPooledConnection,
    kind: ContactKind,
    value: &str,
) -> Result<Vec<(models::User, ContactMethod)>, Status> {
    let lowered = value.to_lowercase();
    let candidates = match kind {
        ContactKind::Phone => users::table
            .filter(
                users::phone
                    .is_not_null()
                    .and(sql::<Bool>("lower(users.phone->>'value') = ").bind::<Text, _>(lowered)),
            )
            .order(users::id.asc())
            .select(models::USER_COLUMNS)
            .load::<models::User>(conn),
        ContactKind::Email => users::table
            .filter(
                users::email
                    .is_not_null()
                    .and(sql::<Bool>("lower(users.email->>'value') = ").bind::<Text, _>(lowered)),
            )
            .order(users::id.asc())
            .select(models::USER_COLUMNS)
            .load::<models::User>(conn),
    }
    .map_err(|e| {
        log::error!("Failed to look up users by {:?} contact: {:?}", kind, e);
        Status::new(Code::Internal, "data_error")
    })?;

    Ok(candidates
        .into_iter()
        .filter_map(|user| {
            let contact = user_contact(&user, kind)?;
            let matches = contact
                .value
                .as_deref()
                .is_some_and(|v| contact_values_match(kind, v, value));
            (matches && contact.verified_at.is_some()).then_some((user, contact))
        })
        .collect())
}

/// `contact_already_verified` unless `value` is free (not verified on any account other than
/// `except_user_id`).
pub fn ensure_contact_not_verified_elsewhere(
    conn: &mut PgPooledConnection,
    kind: ContactKind,
    value: &str,
    except_user_id: Option<i64>,
) -> Result<(), Status> {
    let taken = find_users_with_verified_contact(conn, kind, value)?
        .iter()
        .any(|(user, _)| Some(user.id) != except_user_id);
    if taken {
        Err(Status::new(Code::AlreadyExists, "contact_already_verified"))
    } else {
        Ok(())
    }
}
