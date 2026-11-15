use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;

/// Verifies a code sent by `StartContactMethodVerification` against `current_user`'s own `phone`/
/// `email` `ContactMethod` (chosen by `request.value`'s `tel:`/`mailto:` scheme) -- see this RPC's
/// own doc in `rellm.proto`. TTL/attempt-cap/comparison are `logic::contact_login`'s, shared with
/// SMS/email login. Refuses (`contact_already_verified`) a contact that is already verified on
/// another account.
pub fn verify_contact_method(
    request: VerifyContactMethodRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<ContactMethod, Status> {
    let kind = ContactKind::from_value(&request.value).ok_or_else(|| {
        Status::new(Code::InvalidArgument, "value_must_be_a_tel_or_mailto_url")
    })?;
    let value = normalize_contact_value(kind, &request.value)?;

    let mut contact = user_contact(current_user, kind)
        .filter(|cm| {
            cm.value
                .as_deref()
                .is_some_and(|v| contact_values_match(kind, v, &value))
        })
        .ok_or_else(|| {
            Status::new(
                Code::FailedPrecondition,
                match kind {
                    ContactKind::Phone => "phone_not_set",
                    ContactKind::Email => "email_not_set",
                },
            )
        })?;

    let verdict = check_contact_code(&mut contact, &request.code);
    if verdict == CodeVerdict::NotStarted {
        return Err(verdict_status(verdict));
    }
    if verdict != CodeVerdict::Valid {
        // Expired/exhausted codes are cleared, wrong guesses counted -- persist either way.
        persist_user_contact(conn, current_user.id, kind, &contact)?;
        return Err(verdict_status(verdict));
    }

    // Two accounts can't both hold the same verified contact (it is a login credential).
    ensure_contact_not_verified_elsewhere(conn, kind, &value, Some(current_user.id))?;

    contact.verified_at = Some(std::time::SystemTime::now().to_proto());
    persist_user_contact(conn, current_user.id, kind, &contact)?;

    Ok(contact)
}
