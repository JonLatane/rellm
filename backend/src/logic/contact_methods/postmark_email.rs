//! Sends email via Postmark's Email API (`POST {base}/email`,
//! https://postmarkapp.com/developer/api/email-api) for `email_sending`'s dispatcher. `send_email_at`
//! mirrors `twilio_sms::send_sms_at` (a `base_url` seam so specs can use `factories::serve_capturing`).

use tonic::{Code, Status};

use super::email_sending::{format_from_header, VerificationEmail};
use crate::logic::http_client::blocking_json_request;
use crate::protos::PostmarkConfig;

pub const DEFAULT_BASE_URL: &str = "https://api.postmarkapp.com";

/// `to` must already be a bare, validated address (see `email_sending::normalize_recipient`).
pub fn send_email_at(
    base_url: &str,
    config: &PostmarkConfig,
    to: &str,
    email: &VerificationEmail,
) -> Result<(), Status> {
    let token = config.postmark_server_token.clone();
    let stream = if config.postmark_message_stream.trim().is_empty() {
        "outbound".to_string()
    } else {
        config.postmark_message_stream.trim().to_string()
    };
    let payload = serde_json::json!({
        "From": format_from_header(&config.postmark_from_name, &config.postmark_from_address),
        "To": to,
        "Subject": email.subject,
        "TextBody": email.text,
        "HtmlBody": email.html,
        "MessageStream": stream,
    });
    let url = format!("{base_url}/email");
    let (status, body) = blocking_json_request(
        move |client| {
            client
                .post(url)
                .header("X-Postmark-Server-Token", token.clone())
                .header("Accept", "application/json")
                .json(&payload)
        },
        "postmark_request_failed",
    )?;
    // A 200 carries `ErrorCode: 0` on success; any non-zero `ErrorCode` is a failure.
    let error_code = body.get("ErrorCode").and_then(|v| v.as_i64()).unwrap_or(0);
    if !status.is_success() || error_code != 0 {
        log::error!("Postmark send failed ({}): {:?}", status, body);
        return Err(Status::new(Code::FailedPrecondition, "postmark_send_failed"));
    }
    Ok(())
}
