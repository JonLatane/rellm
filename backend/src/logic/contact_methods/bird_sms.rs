//! Sends outbound SMS via Bird's (bird.com, formerly MessageBird) Messages API, for
//! `logic::contact_methods::contact_verification`'s dispatcher -- a cheaper Twilio alternative with a simpler,
//! single-API-key auth model. `send_sms_at` mirrors `logic::twilio_sms::send_sms_at`/
//! `logic::sync_destinations::x_twitter_sync`'s own `_at`-suffixed testable variants (lets specs point this at a local
//! mock server instead of the real Bird API -- see `factories::serve_capturing`).
//!
//! API shape (`docs.bird.com`): `POST https://{region}.platform.bird.com/v1/sms/messages`,
//! `Authorization: Bearer {access_key}`, JSON body `{"to", "from", "text", "category"}` --
//! `category: "authentication"` is the semantically correct value for a verification code (Bird's
//! other categories -- `transactional`/`marketing`/`service` -- are for other kinds of messages).

use tonic::{Code, Status};

use crate::logic::http_client::blocking_json_request;
use crate::protos::BirdConfig;

/// Bird's regional API host for `config.bird_region` ("us1"/"eu1"); empty/unrecognized defaults to
/// "us1", per that field's own doc.
pub fn default_base_url(region: &str) -> String {
    let region = if region.is_empty() { "us1" } else { region };
    format!("https://{region}.platform.bird.com")
}

/// Sends `body` (as the SMS `text`) to `to` (a `tel:` value) via Bird's `/v1/sms/messages`
/// single-send endpoint, Bearer-authenticated with `config.bird_access_key`.
pub fn send_sms_at(base_url: &str, config: &BirdConfig, to: &str, body: &str) -> Result<(), Status> {
    let access_key = config.bird_access_key.clone();
    let from = config.bird_from.clone();
    let to = to.trim_start_matches("tel:").to_string();
    let text = body.to_string();

    let url = format!("{base_url}/v1/sms/messages");
    let (status, response_body) = blocking_json_request(
        move |client| {
            client
                .post(&url)
                .header("Authorization", format!("Bearer {access_key}"))
                .json(&serde_json::json!({
                    "to": to,
                    "from": from,
                    "text": text,
                    "category": "authentication",
                }))
        },
        "bird_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Bird SendSms failed ({}): {:?}", status, response_body);
        return Err(Status::new(Code::FailedPrecondition, "bird_send_failed"));
    }
    Ok(())
}
