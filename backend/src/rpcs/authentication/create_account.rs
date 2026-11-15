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
    ContactConsentChange, ContactMethod, CreateAccountRequest, RefreshTokenResponse,
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
    let redacted_request = CreateAccountRequest {
        password: "<redacted>".to_string(),
        phone_verification_code: request
            .phone_verification_code
            .as_ref()
            .map(|_| "<redacted>".to_string()),
        email_verification_code: request
            .email_verification_code
            .as_ref()
            .map(|_| "<redacted>".to_string()),
        ..request.clone()
    };
    let result = create_account_inner(base_url, request, conn);

    // Never log the response itself -- it carries the new account's tokens.
    log::info!(
        "CreateAccount::request: {:?}, result: {}",
        redacted_request,
        match &result {
            Ok(response) if response.verification_challenge.is_some() => {
                "verification code(s) sent".to_string()
            }
            Ok(response) => format!(
                "created user {:?}",
                response.user.as_ref().map(|u| u.username.clone())
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
            log::error!("Failed to check for existing username: {:?}", e);
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
        verify_codes(&to_verify, conn)?;
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
    if models::count_pending_contact_verifications_sent_within(Duration::from_secs(60 * 60), conn)?
        > MAX_PENDING_SENDS_PER_HOUR
    {
        return Err(Status::new(
            Code::ResourceExhausted,
            "too_many_verification_requests",
        ));
    }

    for c in to_verify {
        let code = generate_code();
        send_verification_code(base_url, conn, &c.value, &code)?;
        models::upsert_pending_contact_verification(&c.value, &hash_code(&c.value, &code), conn)?;
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

/// Second phase: every contact needs its code, and every code must be right.
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
            _ => {
                // Expired or exhausted: a fresh first phase is required.
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
    let contact_json = |kind: ContactKind, supplied: &Option<ContactMethod>| -> Option<serde_json::Value> {
        let supplied = supplied.as_ref()?;
        match verified.iter().find(|c| c.kind == kind) {
            Some(c) => {
                let mut consent_history = c.contact.consent_history.clone();
                consent_history.push(ContactConsentChange {
                    state: c.contact.consent_state,
                    changed_at: Some(now.into()),
                });
                serde_json::to_value(ContactMethod {
                    value: Some(c.value.clone()),
                    visibility: c.contact.visibility,
                    supported_by_server: true,
                    verified_at: Some(now.to_proto()),
                    verification_in_progress: None,
                    consent_state: c.contact.consent_state,
                    consent_history,
                })
                .ok()
            }
            None => serde_json::to_value(supplied).ok(),
        }
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

    // Its own transaction (a savepoint under `test_transaction`) so a failed insert -- the
    // username already exists -- doesn't poison an enclosing transaction.
    let insert_result: Result<models::User, diesel::result::Error> = conn.transaction(|conn| {
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
        Ok(user)
    });

    match insert_result {
        Err(e) => {
            log::warn!("Failed to create account (username already exists?): {:?}", e);
            Err(Status::new(Code::AlreadyExists, "username_already_exists"))
        }
        Ok(user) => {
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
