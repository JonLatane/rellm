//! Sends outbound SMS via Twilio's Programmable Messaging REST API, for `logic::contact_verification`'s
//! dispatcher. `send_sms_at` mirrors `logic::x_twitter_sync`'s own `_at`-suffixed testable variants
//! (lets specs point this at a local mock server instead of the real Twilio API -- see
//! `factories::serve_capturing`).

use tonic::{Code, Status};

use crate::logic::http_client::blocking_json_request;
use crate::protos::TwilioConfig;

pub const DEFAULT_BASE_URL: &str = "https://api.twilio.com";

/// Sends `body` to `to` (a `tel:` value) via Twilio's `Messages.json` endpoint
/// (`POST {base_url}/2010-04-01/Accounts/{AccountSid}/Messages.json`). Authenticated with
/// `config`'s API Key SID/Secret -- *not* the Account SID, which appears only in the URL path (see
/// `TwilioConfig`'s own doc for why an API Key, not the account's Auth Token, is required).
pub fn send_sms_at(
    base_url: &str,
    config: &TwilioConfig,
    to: &str,
    body: &str,
) -> Result<(), Status> {
    let account_sid = config.twilio_account_sid.clone();
    let api_key_sid = config.twilio_api_key_sid.clone();
    let api_key_secret = config.twilio_api_key_secret.clone();
    let from_number = config.twilio_from_number.clone();
    let to = to.trim_start_matches("tel:").to_string();
    let body = body.to_string();

    let messages_url = format!("{base_url}/2010-04-01/Accounts/{account_sid}/Messages.json");
    let (status, response_body) = blocking_json_request(
        move |client| {
            client
                .post(messages_url)
                .basic_auth(api_key_sid.clone(), Some(api_key_secret.clone()))
                .form(&[("To", to.clone()), ("From", from_number.clone()), ("Body", body.clone())])
        },
        "twilio_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Twilio SendSms failed ({}): {:?}", status, response_body);
        return Err(Status::new(Code::FailedPrecondition, "twilio_send_failed"));
    }
    Ok(())
}
