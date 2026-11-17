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
    contact_protocol_supported, email_sending_available, normalize_recipient, send_verification_email,
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
        let value = value.trim_start().to_ascii_lowercase();
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
/// `Some`, overrides the provider's API host so specs can point at a mock server. This is ONLY the
/// provider call: the abuse-cap bookkeeping (ledger row, cooldown state) is reserved *before* it by
/// `send_reserved_code`, which every flow (verify RPC, login, signup) goes through.
pub fn send_verification_code(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    contact_value: &str,
    code: &str,
) -> Result<(), Status> {
    match ContactKind::from_value(contact_value) {
        Some(ContactKind::Phone) => send_verification_sms(base_url, conn, contact_value, code)?,
        Some(ContactKind::Email) => {
            #[cfg(test)]
            let captured = email_capture::capture(contact_value, code);
            #[cfg(not(test))]
            let captured = false;
            if !captured {
                send_verification_email(base_url, conn, contact_value, code)?;
            }
        }
        None => {
            return Err(Status::new(
                Code::InvalidArgument,
                "value_must_be_a_tel_or_mailto_url",
            ));
        }
    }
    Ok(())
}

/// Per-contact ceiling on codes sent within an hour, across every flow. (The 60s resend cooldown
/// alone allows 60/hour; this keeps a determined caller from using someone's contact as a spam
/// target.) Login's first phase silently skips the send when it's reached; the other flows report
/// `too_many_verification_requests`.
pub const MAX_SENDS_PER_CONTACT_PER_HOUR: i64 = 10;

/// Whether `contact_value` has already been sent `MAX_SENDS_PER_CONTACT_PER_HOUR` codes in the
/// last hour.
pub fn contact_send_cap_reached(
    conn: &mut PgPooledConnection,
    contact_value: &str,
) -> Result<bool, Status> {
    Ok(models::count_contact_verification_sends_to_within(
        contact_value,
        Duration::from_secs(60 * 60),
        conn,
    )? >= MAX_SENDS_PER_CONTACT_PER_HOUR)
}

/// Test seam for races: a one-shot closure run (on this thread) at the moment a send is "in
/// flight" -- after `send_reserved_code` has committed its reservation, right before the provider
/// is called. A spec uses it to fire a second, concurrent-looking request (or edit the contact)
/// while the first is still mid-send, deterministically.
#[cfg(test)]
pub mod in_flight_hook {
    use std::cell::RefCell;

    use crate::db_connection::PgPooledConnection;

    type Hook = Box<dyn FnOnce(&mut PgPooledConnection)>;

    thread_local! {
        static HOOK: RefCell<Option<Hook>> = const { RefCell::new(None) };
    }

    pub fn set(hook: impl FnOnce(&mut PgPooledConnection) + 'static) {
        HOOK.with(|h| *h.borrow_mut() = Some(Box::new(hook)));
    }

    pub(super) fn run(conn: &mut PgPooledConnection) {
        if let Some(hook) = HOOK.with(|h| h.borrow_mut().take()) {
            hook(conn);
        }
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

/// The ONE canonical form of a contact value, feeding every key (signup, login, verify, the send
/// ledger, pending rows, the users lookup, advisory locks) *and* the delivery address -- so the key
/// a cooldown/cap is tracked under is exactly where the message goes, and no spelling trick
/// (`?x=1`, `#frag`, scheme case, address case) mints a "different" contact. A leading scheme is
/// optional (any case) and dropped; the result is always `tel:+E164digits` or `mailto:<lowercased
/// address>`. Anything extra -- a `?query`/`#fragment`/`;param`, whitespace, a second recipient --
/// is rejected, not stripped, and an email must also pass the strict recipient check the email
/// providers apply before sending (`normalize_recipient`).
pub fn normalize_contact_value(kind: ContactKind, raw: &str) -> Result<String, Status> {
    let raw = raw.trim();
    let strip_scheme = |scheme: &str| -> String {
        match raw.get(..scheme.len()) {
            Some(prefix) if prefix.eq_ignore_ascii_case(scheme) => raw[scheme.len()..].to_string(),
            _ => raw.to_string(),
        }
    };
    match kind {
        ContactKind::Phone => {
            let value = format!("tel:{}", strip_scheme("tel:"));
            validate_phone(&Some(value.clone()))?;
            Ok(value)
        }
        ContactKind::Email => {
            let address = strip_scheme("mailto:").to_lowercase();
            let invalid = || Status::new(Code::InvalidArgument, "email_must_be_a_valid_address");
            validate_email(&Some(format!("mailto:{address}")))?;
            let (local, domain) = address.split_once('@').ok_or_else(invalid)?;
            let forbidden = |c: char| {
                c.is_whitespace() || c.is_control() || "<>,;:?#\"'()[]\\".contains(c)
            };
            if local.is_empty()
                || domain.contains('@')
                || !domain.contains('.')
                || domain.starts_with('.')
                || domain.ends_with('.')
                || address.chars().any(forbidden)
            {
                return Err(invalid());
            }
            // Key == delivery address: what the providers will actually send to must be this very
            // address, not a stripped/reinterpreted form of it.
            if normalize_recipient(&address).map_err(|_| invalid())? != address {
                return Err(invalid());
            }
            Ok(format!("mailto:{address}"))
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
/// cleared on success/expiry, `attempts` bumped on a wrong guess, kept-but-exhausted (see below)
/// once the attempt cap is hit. The caller must
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
        CodeVerdict::TooManyAttempts => {
            // Burn the code but KEEP the record (emptied code, attempts at the cap, original
            // `verification_started_at`): clearing it would let the next request send a fresh
            // code immediately, so five wrong guesses would dodge the 60s resend cooldown.
            // `judge_code` rejects anything against an exhausted record.
            verification.verification_code = String::new();
            verification.attempts = MAX_ATTEMPTS;
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
        log::error!("Failed to persist {:?} contact verification state: {}", kind, safe_db_error(&e));
        Status::new(Code::Internal, "data_error")
    })
}

/// A diesel error described without its payload: `Debug` on a `DatabaseError` can include the
/// offending row's values (`Key (username)=(...) already exists`, contact values), which must not
/// reach logs. Only the error's kind is kept.
pub fn safe_db_error(e: &diesel::result::Error) -> String {
    match e {
        diesel::result::Error::DatabaseError(kind, _) => format!("DatabaseError({kind:?})"),
        diesel::result::Error::NotFound => "NotFound".to_string(),
        other => format!("{:?}", std::mem::discriminant(other)),
    }
}

fn db_error(what: &str, e: diesel::result::Error) -> Status {
    log::error!("Failed to {}: {}", what, safe_db_error(&e));
    Status::new(Code::Internal, "data_error")
}

/// Takes a transaction-scoped advisory lock keyed on `contact_value` (case-insensitive), held until
/// the enclosing transaction ends. Everything that decides "who owns this verified contact" --
/// `VerifyContactMethod`, account creation's second phase -- takes it first, so two requests
/// racing to verify the same contact are serialized and the loser sees the winner. Always take
/// this *before* any row lock (it's the first lock in every path, so no deadlocks).
pub fn lock_contact_value(
    conn: &mut PgPooledConnection,
    contact_value: &str,
) -> Result<(), Status> {
    diesel::sql_query("SELECT pg_advisory_xact_lock(hashtext($1))")
        .bind::<Text, _>(format!("contact:{}", contact_value.to_lowercase()))
        .execute(conn)
        .map(|_| ())
        .map_err(|e| db_error("take contact advisory lock", e))
}

/// Check-and-save on `user_id`'s `kind` contact method under a lock, so concurrent submissions
/// can't both accept the same one-time code, lose attempt increments, or restore a cleared code.
/// In one transaction it takes the contact's advisory lock, locks the user row (`SELECT ... FOR
/// UPDATE`), RELOADS the contact, and -- only if it is still `expected_value` -- hands it to `f`.
/// If `f` returns `Ok` and changed the contact, the contact (and only that column) is saved;
/// `Err` rolls nothing back but saves nothing. Returns `Ok(None)` if the contact is gone/changed.
pub fn with_locked_user_contact<T>(
    conn: &mut PgPooledConnection,
    user_id: i64,
    kind: ContactKind,
    expected_value: &str,
    f: impl FnOnce(&mut PgPooledConnection, &mut ContactMethod) -> Result<T, Status>,
) -> Result<Option<T>, Status> {
    let outcome: Result<Result<Option<T>, Status>, diesel::result::Error> =
        conn.transaction(|conn| {
            if let Err(e) = lock_contact_value(conn, expected_value) {
                return Ok(Err(e));
            }
            let user = users::table
                .filter(users::id.eq(user_id))
                .for_update()
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .optional()?;
            let Some(mut contact) = user
                .as_ref()
                .and_then(|u| user_contact(u, kind))
                .filter(|cm| {
                    cm.value
                        .as_deref()
                        .is_some_and(|v| contact_values_match(kind, v, expected_value))
                })
            else {
                return Ok(Ok(None));
            };
            let before = contact.clone();
            match f(conn, &mut contact) {
                Err(e) => Ok(Err(e)),
                Ok(result) => {
                    if contact != before {
                        if let Err(e) = persist_user_contact(conn, user_id, kind, &contact) {
                            return Ok(Err(e));
                        }
                    }
                    Ok(Ok(Some(result)))
                }
            }
        });
    outcome.map_err(|e| db_error("update contact method", e))?
}

/// Where `send_reserved_code` keeps the sent code's state (and cooldown clock).
#[derive(Clone, Copy, Debug)]
pub enum SendTarget {
    /// `pending_contact_verifications` -- an account being created (no user yet).
    Pending,
    /// `verification_in_progress` on this existing user's `kind` contact method.
    UserContact { user_id: i64, kind: ContactKind },
}

/// What a reservation overwrote, so a failed send can put it back.
enum Previous {
    Pending(Option<models::PendingContactVerification>),
    UserContact(Option<ContactMethodVerification>),
}

/// Sends a fresh code to `send_to` with the abuse limits enforced *atomically with* recording the
/// send, so concurrent requests can't all pass the checks and each pay for a message:
///
/// 1. **Reserve** (short transaction): take the contact's advisory lock (the same key every other
///    ownership decision uses), then -- only when `global_cap` is given -- the global send lock
///    (always second, so no deadlocks). Re-check, under those locks, the resend cooldown, the
///    per-contact hourly cap and the global hourly cap (and, for a user's contact, that it still
///    exists unchanged and still consents). Then write the `contact_verification_sends` ledger row
///    and the new code state (pending row / `verification_in_progress`, `sent_at` = now) and
///    COMMIT. A second request arriving now sees the cooldown and the ledger row and sends nothing.
/// 2. **Send** outside any transaction/lock (never hold a lock across the network call).
/// 3. If the provider fails, **undo the code state** (restore what the reservation overwrote --
///    but only if it's still ours) so the caller isn't stuck behind a cooldown for a code that was
///    never delivered. The ledger row is deliberately KEPT: a provider error can be a timeout on a
///    message that did go out, and the caps (10/contact/hour, `global_cap`/hour) are what bound an
///    abuser looping on a failing or flaky provider.
///
/// `key` is the contact's normalized value (ledger/lock/pending key); `send_to` is where the
/// message goes (a user's stored spelling, same address modulo case). Errors from the checks are
/// `verification_recently_sent` / `too_many_verification_requests` / `contact_changed` /
/// `contact_consent_not_granted`. For `UserContact` returns the stored contact method INCLUDING the
/// real code -- blank it before returning it to a client.
pub fn send_reserved_code(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    key: &str,
    send_to: &str,
    target: SendTarget,
    global_cap: Option<i64>,
) -> Result<Option<ContactMethod>, Status> {
    let code = generate_code();
    let (previous, reserved) = reserve_send(conn, key, target, &code, global_cap)?;

    #[cfg(test)]
    in_flight_hook::run(conn);

    if let Err(e) = send_verification_code(base_url, conn, send_to, &code) {
        if let Err(undo_error) = undo_reservation(conn, key, target, &code, previous) {
            log::error!("Failed to undo a verification reservation: {}", undo_error.message());
        }
        return Err(e);
    }
    Ok(reserved)
}

fn too_many_requests() -> Status {
    Status::new(Code::ResourceExhausted, "too_many_verification_requests")
}

fn reserve_send(
    conn: &mut PgPooledConnection,
    key: &str,
    target: SendTarget,
    code: &str,
    global_cap: Option<i64>,
) -> Result<(Previous, Option<ContactMethod>), Status> {
    let hour = Duration::from_secs(60 * 60);
    let outcome: Result<Result<(Previous, Option<ContactMethod>), Status>, diesel::result::Error> =
        conn.transaction(|conn| {
            // Always per-contact first, then global.
            if let Err(e) = lock_contact_value(conn, key) {
                return Ok(Err(e));
            }
            if global_cap.is_some() {
                if let Err(e) = lock_global_sends(conn) {
                    return Ok(Err(e));
                }
            }
            // The limits shared by every target; run under the locks, after the target's own
            // cooldown check, immediately before the ledger row is written.
            let limits = |conn: &mut PgPooledConnection| -> Result<(), Status> {
                if contact_send_cap_reached(conn, key)? {
                    return Err(too_many_requests());
                }
                if let Some(cap) = global_cap {
                    if models::count_contact_verification_sends_within(hour, conn)? > cap {
                        return Err(too_many_requests());
                    }
                }
                models::record_contact_verification_send(key, conn)
            };
            let result = match target {
                SendTarget::Pending => (|| -> Result<_, Status> {
                    let previous = models::find_pending_contact_verification(key, conn)?;
                    if previous
                        .as_ref()
                        .is_some_and(|p| p.sent_at + RESEND_COOLDOWN > SystemTime::now())
                    {
                        return Err(Status::new(
                            Code::FailedPrecondition,
                            "verification_recently_sent",
                        ));
                    }
                    limits(conn)?;
                    models::upsert_pending_contact_verification(key, &hash_code(key, code), conn)?;
                    Ok((Previous::Pending(previous), None))
                })(),
                SendTarget::UserContact { user_id, kind } => {
                    let mut previous = None;
                    with_locked_user_contact(conn, user_id, kind, key, |conn, contact| {
                        if !consent_granted(contact) {
                            return Err(Status::new(
                                Code::FailedPrecondition,
                                "contact_consent_not_granted",
                            ));
                        }
                        if cooldown_active(contact) {
                            return Err(Status::new(
                                Code::FailedPrecondition,
                                "verification_recently_sent",
                            ));
                        }
                        limits(conn)?;
                        previous = contact.verification_in_progress.clone();
                        contact.supported_by_server = true;
                        contact.verification_in_progress = Some(ContactMethodVerification {
                            verification_code: code.to_string(),
                            verification_started_at: Some(SystemTime::now().to_proto()),
                            attempts: 0,
                        });
                        Ok(contact.clone())
                    })
                    .and_then(|reserved| {
                        reserved
                            .ok_or_else(|| Status::new(Code::FailedPrecondition, "contact_changed"))
                    })
                    .map(|contact| (Previous::UserContact(previous), Some(contact)))
                }
            };
            Ok(result)
        });
    outcome.map_err(|e| db_error("reserve a verification send", e))?
}

fn lock_global_sends(conn: &mut PgPooledConnection) -> Result<(), Status> {
    diesel::sql_query("SELECT pg_advisory_xact_lock(hashtext('contact-verification-global-sends'))")
        .execute(conn)
        .map(|_| ())
        .map_err(|e| db_error("take the global send lock", e))
}

/// Reverts a reservation whose provider call failed -- but only state that is still ours (a newer
/// reservation/redemption since is left alone). The ledger row stays; see `send_reserved_code`.
fn undo_reservation(
    conn: &mut PgPooledConnection,
    key: &str,
    target: SendTarget,
    code: &str,
    previous: Previous,
) -> Result<(), Status> {
    match (target, previous) {
        (SendTarget::Pending, Previous::Pending(previous)) => {
            let outcome: Result<Result<(), Status>, diesel::result::Error> = conn.transaction(|conn| {
                if let Err(e) = lock_contact_value(conn, key) {
                    return Ok(Err(e));
                }
                let ours = models::find_pending_contact_verification(key, conn)
                    .ok()
                    .flatten()
                    .is_some_and(|row| row.code_hash == hash_code(key, code));
                if !ours {
                    return Ok(Ok(()));
                }
                Ok(match previous {
                    Some(previous) => models::restore_pending_contact_verification(&previous, conn),
                    None => models::delete_pending_contact_verification(key, conn),
                })
            });
            outcome.map_err(|e| db_error("undo a pending verification", e))?
        }
        (SendTarget::UserContact { user_id, kind }, Previous::UserContact(previous)) => {
            with_locked_user_contact(conn, user_id, kind, key, |_conn, contact| {
                let ours = contact
                    .verification_in_progress
                    .as_ref()
                    .is_some_and(|v| v.verification_code == code);
                if ours {
                    contact.verification_in_progress = previous;
                }
                Ok(())
            })
            .map(|_| ())
        }
        _ => Ok(()),
    }
}

/// `begin_user_contact_verification` -- sends a code to an existing user's contact method under
/// the reservation protocol (see `send_reserved_code`); `value` is both the key and the delivery
/// address (the stored spelling). Returns the stored contact method INCLUDING the real code --
/// blank it before returning it to a client. Callers gate on consent/provider availability
/// themselves for good error messages (their handling differs: the authenticated verify RPC reports
/// each, login must not); the checks are repeated authoritatively under lock.
pub fn begin_user_contact_verification(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    user_id: i64,
    kind: ContactKind,
    value: &str,
) -> Result<ContactMethod, Status> {
    send_reserved_code(
        base_url,
        conn,
        value,
        value,
        SendTarget::UserContact { user_id, kind },
        None,
    )?
    .ok_or_else(|| Status::new(Code::Internal, "data_error"))
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
        log::error!("Failed to look up users by {:?} contact: {}", kind, safe_db_error(&e));
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
