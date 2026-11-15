//! Sends email via Mailgun's Messages API (`POST {base}/v3/{domain}/messages`,
//! https://documentation.mailgun.com/docs/mailgun/api-reference/send/mailgun/messages) for
//! `email_sending`'s dispatcher. Basic auth `api:{key}`; the body is a form.

use tonic::{Code, Status};

use super::email_sending::{format_from_header, VerificationEmail};
use crate::logic::http_client::blocking_json_request;
use crate::protos::MailgunConfig;

pub const DEFAULT_BASE_URL: &str = "https://api.mailgun.net";
pub const EU_BASE_URL: &str = "https://api.eu.mailgun.net";

/// `mailgun_region` `eu` -> the EU host; anything else (`""`/`us`) -> the US one.
pub fn default_base_url(region: &str) -> &'static str {
    if region.trim().eq_ignore_ascii_case("eu") {
        EU_BASE_URL
    } else {
        DEFAULT_BASE_URL
    }
}

pub fn send_email_at(
    base_url: &str,
    config: &MailgunConfig,
    to: &str,
    email: &VerificationEmail,
) -> Result<(), Status> {
    let api_key = config.mailgun_api_key.clone();
    let form: Vec<(&'static str, String)> = vec![
        (
            "from",
            format_from_header(&config.mailgun_from_name, &config.mailgun_from_address),
        ),
        ("to", to.to_string()),
        ("subject", email.subject.clone()),
        ("text", email.text.clone()),
        ("html", email.html.clone()),
    ];
    let url = format!("{base_url}/v3/{}/messages", config.mailgun_domain.trim());
    let (status, body) = blocking_json_request(
        move |client| client.post(url).basic_auth("api", Some(api_key.clone())).form(&form),
        "mailgun_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Mailgun send failed ({}): {:?}", status, body);
        return Err(Status::new(Code::FailedPrecondition, "mailgun_send_failed"));
    }
    Ok(())
}
