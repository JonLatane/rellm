//! Shared logic for revoking a user's SMS `ContactMethod.consent_state` when a Twilio/Telnyx/Bird
//! inbound webhook reports a "STOP" reply -- see `web::contact_integrations_webhook` (the three
//! provider-specific parsers that call into this) and `docs/contact_integrations.md`.

use std::time::SystemTime;

use diesel::dsl::sql;
use diesel::sql_types::{Bool, Text};
use diesel::*;

use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::{ContactConsentChange, ContactConsentState, ContactMethod};
use crate::schema::users;

/// Finds every user whose `phone.value` matches `tel:{e164_number}` and, if their `consent_state`
/// is currently `CONTACT_CONSENT_GRANTED`, revokes it -- appending a server-timestamped
/// `ContactConsentChange` to `consent_history`, same bookkeeping
/// `apply_contact_method_update`'s own grant/revoke path does for a client-driven `UpdateUser`
/// call, just triggered here by an inbound "STOP" instead of the user's own checkbox. A phone
/// already `CONTACT_CONSENT_REVOKED` is left untouched (no duplicate history entry), mirroring
/// that same function's no-op-on-unchanged-state behavior. Multiple users sharing one phone number
/// (unusual, but not `UNIQUE`-constrained) each get revoked independently. Returns the number of
/// users actually updated (0 if no user has this number, or all matches were already revoked).
pub fn revoke_sms_consent_by_phone_number(
    e164_number: &str,
    conn: &mut PgPooledConnection,
) -> Result<usize, tonic::Status> {
    let tel_value = format!("tel:{e164_number}");
    let matching_users = users::table
        .filter(
            users::phone
                .is_not_null()
                .and(sql::<Bool>("users.phone->>'value' = ").bind::<Text, _>(tel_value)),
        )
        .select(models::USER_COLUMNS)
        .load::<models::User>(conn)
        .map_err(|e| {
            log::error!("Failed to look up users by phone number for SMS STOP: {:?}", e);
            tonic::Status::new(tonic::Code::Internal, "db_error")
        })?;

    let mut revoked_count = 0;
    for user in matching_users {
        let Some(mut phone) = user
            .phone
            .clone()
            .and_then(|v| serde_json::from_value::<ContactMethod>(v).ok())
        else {
            continue;
        };
        if phone.consent_state == ContactConsentState::ContactConsentRevoked as i32 {
            continue;
        }
        phone.consent_state = ContactConsentState::ContactConsentRevoked as i32;
        phone.consent_history.push(ContactConsentChange {
            state: ContactConsentState::ContactConsentRevoked as i32,
            changed_at: Some(SystemTime::now().into()),
        });
        diesel::update(users::table)
            .filter(users::id.eq(user.id))
            .set(users::phone.eq(serde_json::to_value(&phone).unwrap()))
            .execute(conn)
            .map_err(|e| {
                log::error!(
                    "Failed to persist SMS STOP consent revocation for user {}: {:?}",
                    user.id,
                    e
                );
                tonic::Status::new(tonic::Code::Internal, "db_error")
            })?;
        revoked_count += 1;
    }
    Ok(revoked_count)
}
