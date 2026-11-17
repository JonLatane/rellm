use std::time::SystemTime;

use bcrypt::verify;
use prost_wkt_types::Timestamp;
use diesel::*;
use tonic::{Code, Status};

use crate::auth;
use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::*;
use crate::schema::users::dsl::*;

pub fn login(
    request: LoginRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    login_at(None, request, conn)
}

/// Same as `login`, but sends SMS/email codes via an arbitrary provider API `base_url` (see
/// `send_verification_code`) -- lets specs point at a local mock server.
pub fn login_at(
    base_url: Option<&str>,
    request: LoginRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    match request.request {
        Some(login_request::Request::UsernamePassword(request)) => {
            username_password_login(request, conn)
        }
        Some(login_request::Request::Sms(request)) => contact_login(
            base_url,
            conn,
            ContactKind::Phone,
            request.phone_number,
            request.code,
            request.expires_at,
            request.user_id,
            request.consent_to_contact,
        ),
        Some(login_request::Request::Email(request)) => contact_login(
            base_url,
            conn,
            ContactKind::Email,
            request.email,
            request.code,
            request.expires_at,
            request.user_id,
            request.consent_to_contact,
        ),
        None => Err(Status::new(Code::InvalidArgument, "login_request_required")),
    }
}

/// Builds the tokens + `User` response every successful login returns.
fn login_response(
    user: &models::User,
    expires_at: &Option<Timestamp>,
    conn: &mut PgPooledConnection,
) -> RefreshTokenResponse {
    let avatar: Option<models::MediaReference> = match user.avatar_media_id {
        None => None,
        Some(amid) => models::get_media_reference(amid, conn).ok(),
    };
    let tokens = auth::generate_refresh_and_access_token(user.id, conn, expires_at);
    let lookup = avatar.to_media_lookup();

    let mut proto_user = user.to_proto(&None, &None, lookup.as_ref(), &Some(user), Some(conn));
    crate::rpcs::attach_own_advanced_data(&mut proto_user, user, conn);

    RefreshTokenResponse {
        refresh_token: tokens.refresh_token,
        access_token: tokens.access_token,
        user: Some(proto_user),
        verification_challenge: None,
    }
}

fn username_password_login(
    request: UsernamePasswordLoginRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    validate_username(&request.username)?;
    validate_password(&request.password)?;

    let permission_denied = Status::new(
        Code::PermissionDenied,
        match &request.user_id {
            Some(user_id) if user_id.len() > 0 => "invalid_password",
            _ => "invalid_username_or_password",
        },
    );
    let user_result = match &request.user_id {
        Some(user_id) if user_id.len() > 0 => users
            .select(models::USER_COLUMNS)
            .filter(id.eq(user_id.to_db_id_or_err("user_id")?))
            .first::<models::User>(conn),
        _ => users
            .select(models::USER_COLUMNS)
            .filter(username.eq(&request.username))
            .first::<models::User>(conn),
    };
    let user: models::User = match user_result {
        Err(_) => return Err(permission_denied),
        Ok(user) => user,
    };

    // Passwordless accounts (created via SMS/email only) store a bcrypt hash of random bytes nobody
    // knows, so this never matches for them.
    match verify(request.password, &user.password_salted_hash) {
        Err(_) => return Err(permission_denied),
        Ok(false) => return Err(permission_denied),
        Ok(true) => {}
    };
    let response = login_response(&user, &request.expires_at, conn);

    log::info!("Logged in via password, user_id={}", user.id);

    Ok(response)
}

/// The one error every failed second-phase SMS/email login returns, whatever the cause (unknown
/// contact, unverified contact, no code outstanding, wrong/expired/exhausted code) -- so the
/// response never reveals whether an account exists for the contact.
fn incorrect_code() -> Status {
    Status::new(Code::InvalidArgument, "incorrect_code")
}

/// Two-phase SMS/email login (see `LoginRequest`'s doc). Phase 1 (`code` unset) *always* returns
/// the same challenge, whether or not a code was actually sent (an account must have the contact
/// verified, consent granted *or attested by the request*, and no code sent in the last minute);
/// phase 2 verifies the code and, if the request attested consent the account doesn't have yet,
/// records it -- only then, since a valid code is the proof the requester controls the contact.
fn contact_login(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    kind: ContactKind,
    raw_contact: String,
    code: Option<String>,
    expires_at: Option<Timestamp>,
    requested_user_id: Option<String>,
    consent_to_contact: bool,
) -> Result<RefreshTokenResponse, Status> {
    // Server-wide capability checks -- these say nothing about any particular account.
    if !authentication_feature_enabled(conn, kind.login_feature()) {
        return Err(Status::new(
            Code::FailedPrecondition,
            match kind {
                ContactKind::Phone => "login_with_sms_not_enabled",
                ContactKind::Email => "login_with_email_not_enabled",
            },
        ));
    }
    if !contact_protocol_ready(conn, kind) {
        return Err(kind.not_configured_error());
    }
    let value = normalize_contact_value(kind, &raw_contact)?;
    let requested_user_id = match requested_user_id.as_deref() {
        Some(user_id) if !user_id.is_empty() => Some(user_id.to_string().to_db_id_or_err("user_id")?),
        _ => None,
    };

    // Accounts that have verified this contact *and* use it to sign in. Only if more than one does
    // is `user_id` needed.
    let mut matches = find_users_with_verified_contact(conn, kind, &value)?;
    matches.retain(|(_, contact)| contact.use_for_sign_in == Some(true));
    if matches.len() > 1 {
        match requested_user_id {
            Some(wanted) => matches.retain(|(user, _)| user.id == wanted),
            None => {
                return Err(Status::new(
                    Code::FailedPrecondition,
                    "multiple_accounts_for_contact",
                ));
            }
        }
    } else if let Some(wanted) = requested_user_id {
        matches.retain(|(user, _)| user.id == wanted);
    }
    let matched = matches.into_iter().next();

    match code {
        None => {
            send_login_code(base_url, conn, kind, &value, matched, consent_to_contact);
            Ok(RefreshTokenResponse {
                refresh_token: None,
                access_token: None,
                user: None,
                verification_challenge: Some(verification_challenge(vec![value])),
            })
        }
        Some(code) => {
            let Some((user, contact)) = matched else {
                log::info!("{:?} login code submitted for a contact with no verified account", kind);
                return Err(incorrect_code());
            };
            // Judge + record the guess under a lock on the freshly reloaded contact, so two
            // concurrent submissions can't both redeem one code or lose attempt counts.
            let stored_value = contact.value.clone().unwrap_or_else(|| value.clone());
            // When the sign-in form's consent was given (copied onto the account on redemption).
            let consented_at = models::latest_contact_consent_at(
                &value,
                models::ConsentFlow::Login,
                Some(user.id),
                None,
                conn,
            )
            .unwrap_or_else(SystemTime::now);
            let verdict = with_locked_user_contact(conn, user.id, kind, &stored_value, |_conn, contact| {
                let verdict = check_contact_code(contact, &code);
                // The code proved control of the contact, so the sign-in form's consent attestation
                // can now be recorded (same bookkeeping as `UpdateUser`'s grant). Saved with the
                // cleared code, in the same locked write.
                if verdict == CodeVerdict::Valid && consent_to_contact {
                    grant_consent(contact, consented_at);
                }
                Ok(verdict)
            })?
            .unwrap_or(CodeVerdict::NotStarted);
            if verdict != CodeVerdict::Valid {
                log::info!(
                    "{:?} login code rejected for user_id={}: {:?}",
                    kind,
                    user.id,
                    verdict
                );
                return Err(incorrect_code());
            }
            // Re-read the account: redeeming may have recorded consent, and the response's contact
            // methods come from this value.
            let user = users
                .select(models::USER_COLUMNS)
                .filter(id.eq(user.id))
                .first::<models::User>(conn)
                .unwrap_or(user);
            let response = login_response(&user, &expires_at, conn);
            log::info!("Logged in via {:?} code, user_id={}", kind, user.id);
            Ok(response)
        }
    }
}

/// Phase 1's send: only if there's a matching account whose contact consents to being messaged
/// (stored consent, or `consent_to_contact` on this request -- a one-time attestation that is only
/// recorded once the code is redeemed) and has no code sent in the last minute. Every other outcome (and any send failure) is logged and
/// otherwise invisible to the caller.
fn send_login_code(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    kind: ContactKind,
    value: &str,
    matched: Option<(models::User, ContactMethod)>,
    consent_to_contact: bool,
) {
    let Some((user, contact)) = matched else {
        log::info!("{:?} login code requested for a contact with no verified account", kind);
        return;
    };
    if !consent_granted(&contact) && !consent_to_contact {
        log::info!("{:?} login code not sent for user_id={}: consent not granted", kind, user.id);
        return;
    }
    if cooldown_active(&contact) {
        log::info!("{:?} login code not sent for user_id={}: resend cooldown", kind, user.id);
        return;
    }
    match contact_send_cap_reached(conn, value) {
        Ok(false) => {}
        Ok(true) => {
            log::warn!("{:?} login code not sent for user_id={}: hourly send cap", kind, user.id);
            return;
        }
        Err(e) => {
            log::warn!("{:?} login code not sent for user_id={}: {}", kind, user.id, e.message());
            return;
        }
    }
    // Send to the stored spelling of the value (case preserved for emails).
    let send_to = contact.value.clone().unwrap_or_else(|| value.to_string());
    match begin_user_contact_verification(base_url, conn, user.id, kind, &send_to, consent_to_contact) {
        // (A send on an attested consent already wrote its `contact_consents` row, in the reservation.)
        Ok(_) => {}
        Err(e) => log::warn!(
            "{:?} login code could not be sent for user_id={}: {}",
            kind,
            user.id,
            e.message()
        ),
    }
}
