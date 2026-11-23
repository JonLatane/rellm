//! Outbound email for `ContactMethod` verification / SMS-style login codes -- the email twin of
//! `contact_verification`'s SMS dispatcher. Providers: Postmark, SendGrid, Mailgun (HTTP APIs) and
//! Stalwart (SMTP submission). Each is configured independently and optional.
//!
//! ## Contract (other modules code against exactly this surface)
//! - `email_sending_available(conn)` -- is at least one provider enabled+configured *and*
//!   `CONTACT_PROTOCOL_MAILTO` listed in `supported_contact_protocols`? (Mirrors
//!   `verification_available` for SMS.)
//! - `send_verification_email(base_url, conn, to, code)` -- `to` is a `mailto:` value; picks the first
//!   provider from the available/preferred order; `base_url`, if `Some`, overrides the provider's API
//!   host so specs can point at a mock server (same convention as `send_verification_sms`).
//!   Fails with `FailedPrecondition("email_verification_not_configured")` if no provider is available.
//!

use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::contact_protocol_supported;
use super::{mailgun_email, postmark_email, sendgrid_email, stalwart_email};
use crate::protos::{
    ContactProtocol, EmailVerificationApi, MailgunConfig, PostmarkConfig, SendgridConfig,
    StalwartConfig,
};
use crate::rpcs::get_server_configuration_model;

/// Loads the stored `PostmarkConfig`, if any, *unscrubbed* (real `postmark_server_token`) -- internal
/// use only, never send back to a client (see `to_proto`'s blanking).
pub fn server_postmark_config(conn: &mut PgPooledConnection) -> Option<PostmarkConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.email_providers().postmark_config)
}

/// Same as `server_postmark_config`, for SendGrid.
pub fn server_sendgrid_config(conn: &mut PgPooledConnection) -> Option<SendgridConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.email_providers().sendgrid_config)
}

/// Same as `server_postmark_config`, for Mailgun.
pub fn server_mailgun_config(conn: &mut PgPooledConnection) -> Option<MailgunConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.email_providers().mailgun_config)
}

/// Same as `server_postmark_config`, for Stalwart (stored in its own `stalwart_config` column).
pub fn server_stalwart_config(conn: &mut PgPooledConnection) -> Option<StalwartConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.stalwart_config)
        .and_then(|c| serde_json::from_value::<StalwartConfig>(c).ok())
}

/// "Configured" = enabled *and* has the minimum needed to actually send: a server token and a `From`
/// address.
pub fn postmark_configured(c: &PostmarkConfig) -> bool {
    c.postmark_enabled
        && !c.postmark_server_token.trim().is_empty()
        && !c.postmark_from_address.trim().is_empty()
}

/// Enabled, with an API key and a `From` address.
pub fn sendgrid_configured(c: &SendgridConfig) -> bool {
    c.sendgrid_enabled
        && !c.sendgrid_api_key.trim().is_empty()
        && !c.sendgrid_from_address.trim().is_empty()
}

/// Enabled, with an API key, a sending domain and a `From` address.
pub fn mailgun_configured(c: &MailgunConfig) -> bool {
    c.mailgun_enabled
        && !c.mailgun_api_key.trim().is_empty()
        && !c.mailgun_domain.trim().is_empty()
        && !c.mailgun_from_address.trim().is_empty()
}

/// Sending enabled, with an SMTP host and a `From` address (credentials are optional: an in-cluster
/// submission listener may not require AUTH).
pub fn stalwart_sending_configured(c: &StalwartConfig) -> bool {
    c.stalwart_sending_enabled
        && !c.stalwart_smtp_host.trim().is_empty()
        && !c.stalwart_from_address.trim().is_empty()
}

/// The server's admin-set `preferred_email_apis`, in stored order (unfiltered).
pub fn preferred_email_apis(conn: &mut PgPooledConnection) -> Vec<EmailVerificationApi> {
    get_server_configuration_model(conn)
        .ok()
        .map(|c| parse_preferred_email_apis(&c.email_providers().preferred_email_apis))
        .unwrap_or_default()
}

/// Parses stored `EmailProvidersJson.preferred_email_apis` names; unknown names are dropped.
pub fn parse_preferred_email_apis(names: &[String]) -> Vec<EmailVerificationApi> {
    names
        .iter()
        .filter_map(|n| EmailVerificationApi::from_str_name(n))
        .collect()
}

/// Orders `available` providers: `preferred` first (filtered to the available ones, deduplicated),
/// then the rest in the fixed fallback order Postmark, SendGrid, Mailgun, Stalwart. Pure, shared by
/// `available_email_apis` and `to_proto`.
pub fn order_email_apis(
    preferred: &[EmailVerificationApi],
    is_available: impl Fn(&EmailVerificationApi) -> bool,
) -> Vec<EmailVerificationApi> {
    let mut result: Vec<EmailVerificationApi> = Vec::new();
    for api in preferred {
        if is_available(api) && !result.contains(api) {
            result.push(*api);
        }
    }
    for api in [
        EmailVerificationApi::Postmark,
        EmailVerificationApi::Sendgrid,
        EmailVerificationApi::Mailgun,
        EmailVerificationApi::Stalwart,
    ] {
        if is_available(&api) && !result.contains(&api) {
            result.push(api);
        }
    }
    result
}

/// The server's currently available (enabled + configured) email providers, in the order they'd be
/// tried -- the email twin of `available_verification_apis`.
pub fn available_email_apis(conn: &mut PgPooledConnection) -> Vec<EmailVerificationApi> {
    let postmark = server_postmark_config(conn).is_some_and(|c| postmark_configured(&c));
    let sendgrid = server_sendgrid_config(conn).is_some_and(|c| sendgrid_configured(&c));
    let mailgun = server_mailgun_config(conn).is_some_and(|c| mailgun_configured(&c));
    let stalwart = server_stalwart_config(conn).is_some_and(|c| stalwart_sending_configured(&c));
    let preferred = preferred_email_apis(conn);
    order_email_apis(&preferred, |api| match api {
        EmailVerificationApi::Postmark => postmark,
        EmailVerificationApi::Sendgrid => sendgrid,
        EmailVerificationApi::Mailgun => mailgun,
        EmailVerificationApi::Stalwart => stalwart,
    })
}

/// Whether email (`mailto:`) contact is currently supported -- the single source of truth for
/// `ContactMethod.supported_by_server` on `mailto:` values. `validate_configuration` guarantees
/// `CONTACT_PROTOCOL_MAILTO` is only stored alongside an enabled provider.
pub fn email_sending_available(conn: &mut PgPooledConnection) -> bool {
    contact_protocol_supported(conn, ContactProtocol::Mailto)
}

/// The rendered verification email -- same content whichever provider sends it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VerificationEmail {
    pub subject: String,
    pub text: String,
    pub html: String,
}

/// Escapes `&<>"'` for safe inclusion in HTML text/attribute context.
pub fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

/// Verification codes expire this many minutes after being sent (see `pending_contact_verifications`
/// / `ContactMethod` verification TTL); keep the wording in sync with the code TTL.
pub const CODE_EXPIRY_MINUTES: u32 = 10;

/// Builds the verification email naming the server (and its frontend host when known). `server_name`,
/// `frontend_host` and `code` are treated as untrusted: they're escaped in the HTML part, and header
/// control characters are stripped from the subject.
pub fn build_verification_email(
    server_name: &str,
    frontend_host: Option<&str>,
    code: &str,
) -> VerificationEmail {
    let strip = |s: &str| s.chars().filter(|c| !c.is_control()).collect::<String>();
    let server_name = strip(server_name);
    let code = strip(code);
    let who_text = match frontend_host {
        Some(host) => format!("{server_name} ({})", strip(host)),
        None => server_name.clone(),
    };
    let who_html = match frontend_host {
        Some(host) => format!(
            "<strong>{}</strong> ({})",
            html_escape(&server_name),
            html_escape(&strip(host))
        ),
        None => format!("<strong>{}</strong>", html_escape(&server_name)),
    };
    let subject = format!("Your {server_name} verification code: {code}");
    let text = format!(
        "Hi!\n\nSomeone (hopefully you) asked to verify this email address with {who_text}.\n\n\
         Your verification code is: {code}\n\n\
         It expires in {CODE_EXPIRY_MINUTES} minutes. Don't share it with anyone.\n\n\
         If you didn't request this, you can safely ignore this email.\n"
    );
    let html = format!(
        "<!DOCTYPE html><html><body style=\"font-family: -apple-system, Segoe UI, Helvetica, Arial, sans-serif; color: #222;\">\
         <p>Hi!</p>\
         <p>Someone (hopefully you) asked to verify this email address with {who_html}.</p>\
         <p>Your verification code is:</p>\
         <p style=\"font-size: 28px; font-weight: bold; letter-spacing: 4px;\">{}</p>\
         <p>It expires in {CODE_EXPIRY_MINUTES} minutes. Don't share it with anyone.</p>\
         <p style=\"color: #666;\">If you didn't request this, you can safely ignore this email.</p>\
         </body></html>",
        html_escape(&code)
    );
    VerificationEmail { subject, text, html }
}

/// Renders the verification email for this server (`server_info.name`, frontend host) via the same
/// identity lookup `verification_sms_body` uses.
fn verification_email(conn: &mut PgPooledConnection, code: &str) -> VerificationEmail {
    let (server_name, frontend_host) = super::contact_verification::server_identity(conn);
    build_verification_email(&server_name, frontend_host.as_deref(), code)
}

/// Turns a `mailto:` value (or bare address) into a single bare address, or `InvalidArgument`
/// (`invalid_email_address`). Drops a `?subject=...` style query, and rejects anything that could
/// smuggle extra recipients or headers: whitespace/control characters, commas, semicolons, angle
/// brackets, quotes, more than one `@`.
pub fn normalize_recipient(to: &str) -> Result<String, Status> {
    let invalid = || Status::new(Code::InvalidArgument, "invalid_email_address");
    let trimmed = to.trim();
    let without_scheme = match trimmed.get(..7) {
        Some(prefix) if prefix.eq_ignore_ascii_case("mailto:") => &trimmed[7..],
        _ => trimmed,
    };
    let address = without_scheme.split('?').next().unwrap_or("").trim();
    let (local, domain) = address.split_once('@').ok_or_else(invalid)?;
    let bad_char = |c: char| {
        c.is_whitespace() || c.is_control() || matches!(c, ',' | ';' | '<' | '>' | '"' | '\'' | '(' | ')' | '\\' | '@')
    };
    if local.is_empty()
        || domain.is_empty()
        || !domain.contains('.')
        || address.len() > 254
        || local.chars().any(bad_char)
        || domain.chars().any(bad_char)
    {
        return Err(invalid());
    }
    Ok(address.to_string())
}

/// A `From` header value: `Name <addr>` (name quoted/escaped, CR/LF stripped), or just `addr`.
pub fn format_from_header(name: &str, address: &str) -> String {
    let address: String = address.chars().filter(|c| !c.is_control()).collect();
    let name: String = name.chars().filter(|c| !c.is_control()).collect();
    let name = name.trim();
    if name.is_empty() {
        address.trim().to_string()
    } else {
        let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
        format!("\"{escaped}\" <{}>", address.trim())
    }
}

/// Sends a verification `code` to `to` (a `mailto:` value) via whichever provider
/// `available_email_apis` ranks first. Fails with `FailedPrecondition("email_verification_not_configured")`
/// if none is available. `base_url`, if `Some`, overrides the selected HTTP provider's API host (specs
/// point it at a mock server); it doesn't apply to Stalwart's SMTP submission.
pub fn send_verification_email(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    to: &str,
    code: &str,
) -> Result<(), Status> {
    let to = normalize_recipient(to)?;
    let email = verification_email(conn, code);
    let not_configured = |what: &'static str| Status::new(Code::FailedPrecondition, what);
    match available_email_apis(conn).first() {
        Some(EmailVerificationApi::Postmark) => {
            let config = server_postmark_config(conn)
                .ok_or_else(|| not_configured("postmark_not_configured"))?;
            let base_url = base_url.unwrap_or(postmark_email::DEFAULT_BASE_URL);
            postmark_email::send_email_at(base_url, &config, &to, &email)
        }
        Some(EmailVerificationApi::Sendgrid) => {
            let config = server_sendgrid_config(conn)
                .ok_or_else(|| not_configured("sendgrid_not_configured"))?;
            let base_url = base_url.unwrap_or_else(|| sendgrid_email::default_base_url(&config.sendgrid_region));
            sendgrid_email::send_email_at(base_url, &config, &to, &email)
        }
        Some(EmailVerificationApi::Mailgun) => {
            let config = server_mailgun_config(conn)
                .ok_or_else(|| not_configured("mailgun_not_configured"))?;
            let base_url = base_url.unwrap_or_else(|| mailgun_email::default_base_url(&config.mailgun_region));
            mailgun_email::send_email_at(base_url, &config, &to, &email)
        }
        Some(EmailVerificationApi::Stalwart) => {
            let config = server_stalwart_config(conn)
                .ok_or_else(|| not_configured("stalwart_not_configured"))?;
            stalwart_email::send_email(&config, &to, &email)
        }
        None => Err(Status::new(
            Code::FailedPrecondition,
            "email_verification_not_configured",
        )),
    }
}
