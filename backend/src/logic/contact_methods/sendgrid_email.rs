//! Sends email via SendGrid's v3 Mail Send API (`POST {base}/v3/mail/send`,
//! https://www.twilio.com/docs/sendgrid/api-reference/mail-send/mail-send) for `email_sending`'s
//! dispatcher. Success is `202 Accepted` with an empty body.

use tonic::{Code, Status};

use super::email_sending::VerificationEmail;
use crate::logic::http_client::blocking_json_request;
use crate::protos::SendgridConfig;

pub const DEFAULT_BASE_URL: &str = "https://api.sendgrid.com";
pub const EU_BASE_URL: &str = "https://api.eu.sendgrid.com";

/// `sendgrid_region` `eu` -> the EU regional host; anything else -> the global one.
pub fn default_base_url(region: &str) -> &'static str {
    if region.trim().eq_ignore_ascii_case("eu") {
        EU_BASE_URL
    } else {
        DEFAULT_BASE_URL
    }
}

pub fn send_email_at(
    base_url: &str,
    config: &SendgridConfig,
    to: &str,
    email: &VerificationEmail,
) -> Result<(), Status> {
    let api_key = config.sendgrid_api_key.clone();
    let mut from = serde_json::json!({ "email": config.sendgrid_from_address.trim() });
    let from_name = config.sendgrid_from_name.trim();
    if !from_name.is_empty() {
        from["name"] = serde_json::Value::String(from_name.to_string());
    }
    // `text/plain` must come before `text/html` in `content` (SendGrid rejects the reverse order).
    let payload = serde_json::json!({
        "personalizations": [{ "to": [{ "email": to }] }],
        "from": from,
        "subject": email.subject,
        "content": [
            { "type": "text/plain", "value": email.text },
            { "type": "text/html", "value": email.html },
        ],
    });
    let url = format!("{base_url}/v3/mail/send");
    let (status, body) = blocking_json_request(
        move |client| client.post(url).bearer_auth(api_key.clone()).json(&payload),
        "sendgrid_request_failed",
    )?;
    if !status.is_success() {
        log::error!("SendGrid send failed ({}): {:?}", status, crate::logic::log_redaction::summarize(&body));
        return Err(Status::new(Code::FailedPrecondition, "sendgrid_send_failed"));
    }
    Ok(())
}
