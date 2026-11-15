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

    // Cheap pre-check for a clean `*_not_set` error; the authoritative check happens again under
    // lock below.
    if !user_contact(current_user, kind).is_some_and(|cm| {
        cm.value
            .as_deref()
            .is_some_and(|v| contact_values_match(kind, v, &value))
    }) {
        return Err(not_set(kind));
    }

    // Judge the code, check ownership and save -- all under the contact's advisory lock and a lock
    // on the freshly reloaded user row, so racing requests (same user, or two users claiming the
    // same contact) are serialized: a code can't be redeemed twice, attempts aren't lost, and two
    // accounts can't both end up as the verified owner.
    let outcome = with_locked_user_contact(conn, current_user.id, kind, &value, |conn, contact| {
        let verdict = check_contact_code(contact, &request.code);
        if verdict != CodeVerdict::Valid {
            // Counted guess / cleared-or-exhausted code: saved (Ok), but reported as the error.
            return Ok(Err(verdict));
        }
        // Two accounts can't both hold the same verified contact (it is a login credential).
        // Err => nothing is saved, so the valid code stays redeemable.
        ensure_contact_not_verified_elsewhere(conn, kind, &value, Some(current_user.id))?;
        contact.verified_at = Some(std::time::SystemTime::now().to_proto());
        Ok(Ok(contact.clone()))
    })?
    .ok_or_else(|| not_set(kind))?;

    outcome.map_err(verdict_status)
}

fn not_set(kind: ContactKind) -> Status {
    Status::new(
        Code::FailedPrecondition,
        match kind {
            ContactKind::Phone => "phone_not_set",
            ContactKind::Email => "email_not_set",
        },
    )
}
