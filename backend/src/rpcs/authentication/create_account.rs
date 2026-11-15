use std::time::{Duration, SystemTime};

use bcrypt::{hash, DEFAULT_COST};
use diesel::*;
use rand::RngExt;
use tonic::{Code, Status};

use crate::auth;
use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::marshaling::*;
use crate::models;
use crate::protos::{
    ContactConsentChange, ContactConsentState, ContactMethod, CreateAccountRequest,
    RefreshTokenResponse,
};
use crate::schema::users::dsl::*;

use crate::rpcs::{get_server_configuration_proto, validations::*};

/// Global abuse cap on `CreateAccount` first-phase sends: once more than this many codes have
/// been sent (to any contact) within the last hour, further first phases are refused
/// (`too_many_verification_requests`) until some age out. SMS/email cost money and nothing ties a
/// not-yet-existing account to a caller, so a ceiling on total spend is the backstop behind the
/// per-contact resend cooldown.
const MAX_PENDING_SENDS_PER_HOUR: i64 = 200;

/// A phone/email on a `CreateAccountRequest` that the server requires to be verified (its
/// `CREATE_ACCOUNT_WITH_*` feature is enabled).
struct ContactToVerify {
    kind: ContactKind,
    /// Normalized `tel:`/`mailto:` value.
    value: String,
    contact: ContactMethod,
    code: Option<String>,
}

pub fn create_account(
    request: CreateAccountRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    create_account_at(None, request, conn)
}

/// Same as `create_account`, but sends SMS/email codes via an arbitrary provider API `base_url`
/// (see `send_verification_code`) -- lets specs point at a local mock server.
pub fn create_account_at(
    base_url: Option<&str>,
    request: CreateAccountRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    // Nothing from the request is logged (username, email, phone, password, codes): only that a
    // request happened, which phase it was, and the outcome (the new user's id on success).
    let verified_phase = request.phone_verification_code.is_some() || request.email_verification_code.is_some();
    let result = create_account_inner(base_url, request, conn);

    // Never log the response itself either -- it carries the new account's tokens.
    log::info!(
        "CreateAccount request ({}): {}",
        if verified_phase { "code submitted" } else { "no code" },
        match &result {
            Ok(response) if response.verification_challenge.is_some() => {
                "verification code(s) sent".to_string()
            }
            Ok(response) => format!(
                "created user_id={}",
                response.user.as_ref().map(|u| u.id.as_str()).unwrap_or("?")
            ),
            Err(e) => format!("{:?}: {}", e.code(), e.message()),
        }
    );

    result
}

fn create_account_inner(
    base_url: Option<&str>,
    request: CreateAccountRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    validate_username(&request.username)?;
    if let Some(e) = &request.email {
        validate_email(&e.value)?;
    }
    if let Some(p) = &request.phone {
        validate_phone(&p.value)?;
    }
    let passwordless = request.password.is_empty() && (request.email.is_some() || request.phone.is_some());
    if !passwordless {
        validate_password(&request.password)?;
    }

    // Which supplied contact methods must be verified before the account exists.
    let mut to_verify: Vec<ContactToVerify> = vec![];
    for (kind, supplied, code) in [
        (ContactKind::Phone, &request.phone, &request.phone_verification_code),
        (ContactKind::Email, &request.email, &request.email_verification_code),
    ] {
        let Some(supplied) = supplied else { continue };
        if !authentication_feature_enabled(conn, kind.create_account_feature()) {
            continue;
        }
        let raw_value = supplied
            .value
            .as_deref()
            .filter(|v| !v.is_empty())
            .ok_or_else(|| Status::new(Code::InvalidArgument, "value_required"))?;
        to_verify.push(ContactToVerify {
            kind,
            value: normalize_contact_value(kind, raw_value)?,
            contact: supplied.clone(),
            code: code.clone().filter(|c| !c.is_empty()),
        });
    }
    if passwordless && to_verify.is_empty() {
        // A passwordless account needs *some* way to log in.
        let kind = if request.phone.is_some() { ContactKind::Phone } else { ContactKind::Email };
        return Err(Status::new(
            Code::FailedPrecondition,
            match kind {
                ContactKind::Phone => "create_account_with_sms_not_enabled",
                ContactKind::Email => "create_account_with_email_not_enabled",
            },
        ));
    }

    if passwordless {
        // A passwordless account's only way in is SMS/email login, so at least one of its verified
        // contacts must be loggable-into on this server -- otherwise we'd mint accounts nobody can
        // ever sign in to.
        let mut loginable = false;
        for c in &to_verify {
            loginable |= authentication_feature_enabled(conn, c.kind.login_feature())
                && contact_protocol_ready(conn, c.kind);
        }
        if !loginable {
            return Err(Status::new(
                Code::FailedPrecondition,
                match to_verify[0].kind {
                    ContactKind::Phone => "login_with_sms_not_enabled",
                    ContactKind::Email => "login_with_email_not_enabled",
                },
            ));
        }
    }

    if to_verify.is_empty() {
        return insert_account(request, vec![], conn);
    }

    // Everything below is checked in *both* phases: the first so we don't spend a message on an
    // unusable signup, the second because the world may have changed in the meantime.
    if users
        .filter(username.eq(&request.username))
        .select(id)
        .first::<i64>(conn)
        .optional()
        .map_err(|e| {
            log::error!("Failed to check for existing username: {}", safe_db_error(&e));
            Status::new(Code::Internal, "data_error")
        })?
        .is_some()
    {
        return Err(Status::new(Code::AlreadyExists, "username_already_exists"));
    }
    for c in &to_verify {
        if !consent_granted(&c.contact) {
            return Err(Status::new(
                Code::FailedPrecondition,
                "contact_consent_not_granted",
            ));
        }
        if !contact_protocol_ready(conn, c.kind) {
            return Err(c.kind.not_configured_error());
        }
        ensure_contact_not_verified_elsewhere(conn, c.kind, &c.value, None)?;
    }

    if to_verify.iter().any(|c| c.code.is_some()) {
        insert_account(request, to_verify, conn)
    } else {
        send_codes(base_url, &to_verify, conn)
    }
}

/// First phase: sends a code to each contact and stores its hash.
fn send_codes(
    base_url: Option<&str>,
    to_verify: &[ContactToVerify],
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    for c in to_verify {
        if let Some(pending) = models::find_pending_contact_verification(&c.value, conn)? {
            if pending.sent_at + RESEND_COOLDOWN > SystemTime::now() {
                return Err(Status::new(
                    Code::FailedPrecondition,
                    "verification_recently_sent",
                ));
            }
        }
    }
    for c in to_verify {
        if contact_send_cap_reached(conn, &c.value)? {
            return Err(Status::new(
                Code::ResourceExhausted,
                "too_many_verification_requests",
            ));
        }
    }
    // Global backstop on total spend. Counts the send *ledger* (one row per actual send, any
    // flow), not pending rows -- those are overwritten on resend and deleted on exhaustion/expiry,
    // which would make many sends look like one. (Best-effort fail-fast across *all* contacts
    // before anything is sent; `send_reserved_code` re-checks every limit authoritatively, under
    // locks, per contact.)
    if models::count_contact_verification_sends_within(Duration::from_secs(60 * 60), conn)?
        > MAX_PENDING_SENDS_PER_HOUR
    {
        return Err(Status::new(
            Code::ResourceExhausted,
            "too_many_verification_requests",
        ));
    }

    for c in to_verify {
        // Reserve the send (cooldown, per-contact + global caps, ledger row, pending code) under
        // lock and commit, *then* call the provider -- so concurrent first phases can't all pass
        // the checks and each send a paid message.
        send_reserved_code(
            base_url,
            conn,
            &c.value,
            &c.value,
            SendTarget::Pending,
            Some(MAX_PENDING_SENDS_PER_HOUR),
        )?;
    }

    Ok(RefreshTokenResponse {
        refresh_token: None,
        access_token: None,
        user: None,
        verification_challenge: Some(verification_challenge(
            to_verify.iter().map(|c| c.value.clone()).collect(),
        )),
    })
}

/// Second phase: every contact needs its code, and every code must be right. Must run inside
/// `insert_account`'s transaction with the contacts' advisory locks held.
fn verify_codes(
    to_verify: &[ContactToVerify],
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    for c in to_verify {
        let Some(code) = &c.code else {
            return Err(Status::new(
                Code::InvalidArgument,
                match c.kind {
                    ContactKind::Phone => "phone_verification_code_required",
                    ContactKind::Email => "email_verification_code_required",
                },
            ));
        };
        let pending = models::find_pending_contact_verification(&c.value, conn)?
            .ok_or_else(|| verdict_status(CodeVerdict::NotStarted))?;
        let verdict = judge_code(
            pending.sent_at,
            pending.attempts,
            constant_time_eq(&pending.code_hash, &hash_code(&c.value, code)),
        );
        match verdict {
            CodeVerdict::Valid => {}
            CodeVerdict::Incorrect => {
                models::set_pending_contact_verification_attempts(
                    pending.id,
                    pending.attempts + 1,
                    conn,
                )?;
                return Err(verdict_status(verdict));
            }
            CodeVerdict::TooManyAttempts => {
                // Exhausted: keep the row (its `sent_at` still drives the resend cooldown, so
                // burning guesses can't buy an immediate fresh code) -- `judge_code` rejects
                // everything against it until a new first phase overwrites it.
                return Err(verdict_status(verdict));
            }
            _ => {
                // Expired (long past the resend cooldown): a fresh first phase is required.
                models::delete_pending_contact_verification(&c.value, conn)?;
                return Err(verdict_status(verdict));
            }
        }
    }
    Ok(())
}

/// A bcrypt hash of random bytes nobody knows, for passwordless accounts (`password_salted_hash`
/// is NOT NULL, and this can never match a username/password login).
fn unguessable_password_hash() -> String {
    let secret: String = (0..32)
        .map(|_| format!("{:02x}", rand::rng().random_range(0..=255u8)))
        .collect();
    hash(secret, DEFAULT_COST).unwrap()
}

/// Creates the account (contacts in `verified` get `verified_at = now`, the rest are saved as
/// given) and returns tokens. Deletes the verified contacts' pending rows in the same transaction.
fn insert_account(
    request: CreateAccountRequest,
    verified: Vec<ContactToVerify>,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    let hashed_password = if request.password.is_empty() {
        unguessable_password_hash()
    } else {
        hash(&request.password, DEFAULT_COST).unwrap()
    };

    let now = SystemTime::now();
    // Server-owned fields never come from the client, verified or not: `verified_at` and
    // `verification_in_progress` (a caller-chosen code would make a contact "verified" and
    // login-able without receiving a message, and copying someone's contact would mint a second
    // verified owner), `supported_by_server` (recomputed), and `consent_history` (built here, like
    // `update_user` does). Only `value`, `visibility` and `consent_state` are taken from the
    // request.
    let phone_listed = contact_protocol_listed(conn, ContactKind::Phone);
    let email_listed = contact_protocol_listed(conn, ContactKind::Email);
    let contact_json = |kind: ContactKind, supplied: &Option<ContactMethod>| -> Option<serde_json::Value> {
        let supplied = supplied.as_ref()?;
        let proven = verified.iter().find(|c| c.kind == kind);
        let value = match proven {
            Some(c) => Some(c.value.clone()),
            None => supplied.value.clone(),
        };
        let listed = match kind {
            ContactKind::Phone => phone_listed,
            ContactKind::Email => email_listed,
        };
        let supported_by_server = proven.is_some()
            || (listed && value.as_deref().is_some_and(|v| v.starts_with(kind.scheme())));
        let consent_history = if supplied.consent_state == ContactConsentState::ContactConsentRevoked as i32 {
            vec![]
        } else {
            vec![ContactConsentChange {
                state: supplied.consent_state,
                changed_at: Some(now.into()),
            }]
        };
        serde_json::to_value(ContactMethod {
            value,
            visibility: supplied.visibility,
            supported_by_server,
            verified_at: proven.map(|_| now.to_proto()),
            verification_in_progress: None,
            consent_state: supplied.consent_state,
            consent_history,
        })
        .ok()
    };
    let req_email = contact_json(ContactKind::Email, &request.email);
    let req_phone = contact_json(ContactKind::Phone, &request.phone);

    let server_configuration = get_server_configuration_proto(conn)?;
    // New users get the server's configured default media storage allocation (falls back to 15MB
    // -- see `ToProtoServerConfiguration::to_proto`'s `media_settings` deserialize -- so
    // `media_settings` is always `Some` here). Previously left unset entirely, which means
    // *unlimited* (see `MediaSettings.default_user_media_allocation_bytes`'s own doc) -- the actual bug
    // this fixes.
    let default_user_media_allocation_bytes = server_configuration
        .media_settings
        .as_ref()
        .map(|m| m.default_user_media_allocation_bytes as i64);

    // One transaction does everything that must be atomic. For verified contacts: take each
    // contact's advisory lock (sorted, so concurrent signups can't deadlock), then -- now that no
    // concurrent request can be between "check" and "write" for this contact -- re-check the codes
    // (counting wrong guesses / deleting expired rows, which must be committed even when the signup
    // is rejected), re-check nobody else has verified the contact, insert, and delete the pending
    // rows. Also a savepoint under `test_transaction`, so a failed insert (username taken) doesn't
    // poison an enclosing transaction.
    let insert_result: Result<Outcome, diesel::result::Error> = conn.transaction(|conn| {
        let mut locks: Vec<&str> = verified.iter().map(|c| c.value.as_str()).collect();
        locks.sort();
        for value in locks {
            if let Err(e) = lock_contact_value(conn, value) {
                return Ok(Outcome::Rejected(e));
            }
        }
        if !verified.is_empty() {
            if let Err(e) = verify_codes(&verified, conn) {
                return Ok(Outcome::Rejected(e));
            }
            for c in &verified {
                if let Err(e) = ensure_contact_not_verified_elsewhere(conn, c.kind, &c.value, None) {
                    return Ok(Outcome::Rejected(e));
                }
            }
        }
        let user = insert_into(users)
            .values((
                username.eq(request.username.to_owned()),
                password_salted_hash.eq(hashed_password),
                email.eq(req_email),
                phone.eq(req_phone),
                permissions.eq(server_configuration
                    .default_user_permissions
                    .to_json_permissions()),
                moderation.eq(server_configuration
                    .people_settings
                    .as_ref()
                    .unwrap()
                    .default_moderation
                    .to_string_moderation()),
                visibility.eq(server_configuration
                    .people_settings
                    .as_ref()
                    .unwrap()
                    .default_visibility
                    .to_string_visibility()),
                media_storage_limit_bytes.eq(default_user_media_allocation_bytes),
            ))
            .returning(models::USER_COLUMNS)
            .get_result::<models::User>(conn)?;
        for c in &verified {
            delete(
                crate::schema::pending_contact_verifications::table.filter(
                    crate::schema::pending_contact_verifications::contact_value.eq(&c.value),
                ),
            )
            .execute(conn)?;
        }
        Ok(Outcome::Created(user))
    });

    match insert_result {
        Err(diesel::result::Error::DatabaseError(
            diesel::result::DatabaseErrorKind::UniqueViolation,
            _,
        )) => {
            log::warn!("Failed to create account: username already exists");
            Err(Status::new(Code::AlreadyExists, "username_already_exists"))
        }
        Err(e) => {
            log::error!("Failed to create account: {}", safe_db_error(&e));
            Err(Status::new(Code::Internal, "data_error"))
        }
        Ok(Outcome::Rejected(status)) => Err(status),
        Ok(Outcome::Created(user)) => {
            let tokens =
                auth::generate_refresh_and_access_token(user.id, conn, &request.expires_at);
            let mut proto_user = user.to_proto(&None, &None, None, &Some(&user), Some(conn));
            crate::rpcs::attach_own_advanced_data(&mut proto_user, &user, conn);
            Ok(RefreshTokenResponse {
                refresh_token: tokens.refresh_token,
                access_token: tokens.access_token,
                user: Some(proto_user),
                verification_challenge: None,
            })
        }
    }
}

/// What `insert_account`'s transaction decided. `Rejected` still *commits* (wrong-guess counters
/// and deleted expired rows must persist); only a real DB error rolls back.
enum Outcome {
    Created(models::User),
    Rejected(Status),
}
