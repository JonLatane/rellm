//! Sends outbound SMS via Telnyx's Messaging API, for `logic::contact_verification`'s dispatcher --
//! another Twilio alternative, with a simpler single-API-key auth model like Bird's.
//! `send_sms_at` mirrors `logic::twilio_sync::send_sms_at`/`logic::bird_sync::send_sms_at`'s own
//! `_at`-suffixed testable variants (lets specs point this at a local mock server instead of the
//! real Telnyx API -- see `factories::serve_capturing`).
//!
//! API shape (`developers.telnyx.com`): `POST https://api.telnyx.com/v2/messages`,
//! `Authorization: Bearer {api_key}`, JSON body `{"from", "to", "text", "messaging_profile_id"}`.

use tonic::{Code, Status};

use crate::logic::http_client::blocking_json_request;
use crate::protos::TelnyxConfig;

pub const DEFAULT_BASE_URL: &str = "https://api.telnyx.com";

/// Sends `body` (as the SMS `text`) to `to` (a `tel:` value) via Telnyx's `/v2/messages`
/// single-send endpoint, Bearer-authenticated with `config.telnyx_api_key`.
pub fn send_sms_at(
    base_url: &str,
    config: &TelnyxConfig,
    to: &str,
    body: &str,
) -> Result<(), Status> {
    let api_key = config.telnyx_api_key.clone();
    let from = config.telnyx_from_number.clone();
    let messaging_profile_id = config.telnyx_messaging_profile_id.clone();
    let to = to.trim_start_matches("tel:").to_string();
    let text = body.to_string();

    let url = format!("{base_url}/v2/messages");
    let (status, response_body) = blocking_json_request(
        move |client| {
            client
                .post(&url)
                .header("Authorization", format!("Bearer {api_key}"))
                .json(&serde_json::json!({
                    "from": from,
                    "to": to,
                    "text": text,
                    "messaging_profile_id": messaging_profile_id,
                }))
        },
        "telnyx_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Telnyx SendSms failed ({}): {:?}", status, response_body);
        return Err(Status::new(Code::FailedPrecondition, "telnyx_send_failed"));
    }
    Ok(())
}
