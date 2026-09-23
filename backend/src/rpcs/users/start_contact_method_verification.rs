use std::time::{Duration, SystemTime};

use diesel::*;
use rand::RngExt;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{send_verification_sms, verification_available};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::validate_phone;
use crate::schema::users;

/// Minimum time between two `StartContactMethodVerification` sends for the same user -- SMS costs
/// money and this is an abuse vector, so this is a hard requirement, not merely a courtesy.
const RESEND_COOLDOWN: Duration = Duration::from_secs(60);

/// Starts SMS verification of `current_user`'s own `phone` `ContactMethod` -- see this RPC's own
/// doc in `rellm.proto`. Always operates on `current_user`'s stored phone; `request` must match it
/// exactly (this RPC verifies an already-set number, it doesn't set a new one -- that's
/// `UpdateUser`'s job).
pub fn start_contact_method_verification(
    request: ContactMethod,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<ContactMethod, Status> {
    start_contact_method_verification_at(None, request, current_user, conn)
}

/// Same as `start_contact_method_verification`, but against an arbitrary provider API `base_url`
/// (see `logic::contact_verification::send_verification_sms`'s own `base_url` doc) -- lets specs
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

    if value.starts_with("mailto:") {
        return Err(Status::new(
            Code::Unimplemented,
            "email_verification_not_implemented",
        ));
    }
    if !value.starts_with("tel:") {
        return Err(Status::new(
            Code::InvalidArgument,
            "value_must_be_a_tel_or_mailto_url",
        ));
    }
    validate_phone(&Some(value.to_string()))?;

    let existing_phone: Option<ContactMethod> = current_user
        .phone
        .to_owned()
        .and_then(|v| serde_json::from_value(v).ok());
    if existing_phone.as_ref().and_then(|cm| cm.value.as_deref()) != Some(value) {
        // This RPC only verifies a phone number already saved via `UpdateUser` -- it never sets a
        // new one itself.
        return Err(Status::new(Code::FailedPrecondition, "phone_not_set"));
    }
    let existing_phone = existing_phone.unwrap();

    // The verification SMS is itself an outbound message via a Twilio/Bird/Telnyx `ContactMethod`
    // -- gated by `consent_state` exactly like any other outbound contact (see
    // `docs/contact_integrations.md`), even though the user just requested it themselves. This is
    // the single choke point every provider's outbound SMS passes through (via
    // `send_verification_sms` below), so it's the only place this needs enforcing.
    if ContactConsentState::try_from(existing_phone.consent_state).unwrap_or_default()
        != ContactConsentState::ContactConsentGranted
    {
        return Err(Status::new(
            Code::FailedPrecondition,
            "contact_consent_not_granted",
        ));
    }

    if !verification_available(conn) {
        return Err(Status::new(
            Code::FailedPrecondition,
            "verification_not_configured",
        ));
    }

    if let Some(started_at) = existing_phone
        .verification_in_progress
        .as_ref()
        .and_then(|v| v.verification_started_at.as_ref())
    {
        let started_at: SystemTime = started_at.to_db();
        if started_at + RESEND_COOLDOWN > SystemTime::now() {
            return Err(Status::new(
                Code::FailedPrecondition,
                "verification_recently_sent",
            ));
        }
    }

    let code = format!("{:06}", rand::rng().random_range(0..1_000_000));
    send_verification_sms(base_url, conn, value, &code)?;

    let now = SystemTime::now();
    let updated_phone = ContactMethod {
        value: existing_phone.value.clone(),
        visibility: existing_phone.visibility,
        supported_by_server: true,
        verified_at: existing_phone.verified_at.clone(),
        verification_in_progress: Some(ContactMethodVerification {
            verification_code: code,
            verification_started_at: Some(now.to_proto()),
            attempts: 0,
        }),
        // Verification never touches consent -- carried forward unchanged.
        consent_state: existing_phone.consent_state,
        consent_history: existing_phone.consent_history.clone(),
    };

    diesel::update(users::table)
        .filter(users::id.eq(current_user.id))
        .set(users::phone.eq(serde_json::to_value(&updated_phone).unwrap()))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to persist phone verification_in_progress: {:?}", e);
            Status::new(Code::Internal, "data_error")
        })?;

    // Never echo the real code back -- see `ContactMethodVerification.verification_code`'s own
    // doc.
    let mut response = updated_phone;
    if let Some(v) = response.verification_in_progress.as_mut() {
        v.verification_code = String::new();
    }
    Ok(response)
}
