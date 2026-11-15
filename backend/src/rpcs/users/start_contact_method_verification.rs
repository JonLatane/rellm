use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::models;
use crate::protos::*;

/// Starts SMS/email verification of `current_user`'s own `phone`/`email` `ContactMethod` -- see
/// this RPC's own doc in `rellm.proto`. Always operates on `current_user`'s stored value for
/// `request`'s scheme (`tel:` -> phone, `mailto:` -> email); `request` must match it (emails
/// case-insensitively) -- this RPC verifies an already-set contact, it doesn't set a new one;
/// that's `UpdateUser`'s job. Code generation/cooldown/consent are shared with SMS/email login via
/// `logic::contact_login`.
pub fn start_contact_method_verification(
    request: ContactMethod,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<ContactMethod, Status> {
    start_contact_method_verification_at(None, request, current_user, conn)
}

/// Same as `start_contact_method_verification`, but against an arbitrary provider API `base_url`
/// (see `logic::contact_methods::contact_verification::send_verification_sms`'s own `base_url` doc) -- lets specs
/// point whichever provider ends up selected at a local mock server instead of the real Twilio/Bird
/// API (see `factories::serve_capturing`).
pub fn start_contact_method_verification_at(
    base_url: Option<&str>,
    request: ContactMethod,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<ContactMethod, Status> {
    let value = request
        .value
        .as_deref()
        .ok_or_else(|| Status::new(Code::InvalidArgument, "value_required"))?;
    let kind = ContactKind::from_value(value).ok_or_else(|| {
        Status::new(Code::InvalidArgument, "value_must_be_a_tel_or_mailto_url")
    })?;
    let value = normalize_contact_value(kind, value)?;

    let existing = user_contact(current_user, kind)
        .filter(|cm| {
            cm.value
                .as_deref()
                .is_some_and(|v| contact_values_match(kind, v, &value))
        })
        // This RPC only verifies a contact already saved via `UpdateUser` -- it never sets a new
        // one itself.
        .ok_or_else(|| {
            Status::new(
                Code::FailedPrecondition,
                match kind {
                    ContactKind::Phone => "phone_not_set",
                    ContactKind::Email => "email_not_set",
                },
            )
        })?;

    // The verification message is itself an outbound message -- gated by `consent_state` exactly
    // like any other outbound contact (see `docs/contact_integrations.md`), even though the user
    // just requested it themselves.
    if !consent_granted(&existing) {
        return Err(Status::new(
            Code::FailedPrecondition,
            "contact_consent_not_granted",
        ));
    }

    if !contact_protocol_ready(conn, kind) {
        return Err(kind.not_configured_error());
    }

    if cooldown_active(&existing) {
        return Err(Status::new(
            Code::FailedPrecondition,
            "verification_recently_sent",
        ));
    }

    // Don't spend a message on a contact that verification will then refuse.
    ensure_contact_not_verified_elsewhere(conn, kind, &value, Some(current_user.id))?;

    // Send to the stored spelling of the value (case preserved for emails).
    let send_to = existing.value.clone().unwrap_or(value);
    let mut updated = begin_user_contact_verification(
        base_url,
        conn,
        current_user.id,
        kind,
        &existing,
        &send_to,
    )?;

    // Never echo the real code back -- see `ContactMethodVerification.verification_code`'s own
    // doc.
    if let Some(v) = updated.verification_in_progress.as_mut() {
        v.verification_code = String::new();
    }
    Ok(updated)
}
