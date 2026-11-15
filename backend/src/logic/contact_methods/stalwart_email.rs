//! Sends email through Stalwart's SMTP submission listener (STARTTLS on 587 / implicit TLS on 465,
//! SMTP AUTH PLAIN/LOGIN) via `lettre`, for `email_sending`'s dispatcher. Unlike the HTTP providers
//! there is no `base_url` override -- the host/port come from `StalwartConfig`; specs exercise the
//! message construction (`build_message`) and, through `send_message_with`'s explicit `SmtpTls`, a
//! plaintext in-process SMTP server.

use std::time::Duration;

use lettre::message::{Mailbox, MultiPart};
use lettre::transport::smtp::authentication::Credentials;
use lettre::transport::smtp::client::Tls;
use lettre::{Message, SmtpTransport, Transport};
use tonic::{Code, Status};

use super::email_sending::VerificationEmail;
use crate::logic::http_client::run_blocking;
use crate::protos::StalwartConfig;

/// How the SMTP connection is secured.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SmtpTls {
    /// Connect in plaintext, upgrade with STARTTLS (required) -- the default, port 587.
    Starttls,
    /// TLS from the first byte -- port 465 ("SMTPS").
    Implicit,
    /// No TLS at all. Only for specs against a local fake server; never selected from config.
    #[allow(dead_code)]
    None,
}

/// Port 0 means 587.
pub fn effective_port(config: &StalwartConfig) -> u16 {
    match config.stalwart_smtp_port {
        p if p > 0 && p <= 65535 => p as u16,
        _ => 587,
    }
}

/// 465 -> implicit TLS; everything else -> STARTTLS.
pub fn tls_mode_for_port(port: u16) -> SmtpTls {
    if port == 465 {
        SmtpTls::Implicit
    } else {
        SmtpTls::Starttls
    }
}

fn mailbox(name: &str, address: &str, bad: &'static str) -> Result<Mailbox, Status> {
    let address = address
        .trim()
        .parse()
        .map_err(|_| Status::new(Code::FailedPrecondition, bad))?;
    let name = name.trim();
    Ok(Mailbox::new(
        if name.is_empty() { None } else { Some(name.to_string()) },
        address,
    ))
}

/// Builds the `multipart/alternative` (plain + HTML) message. `to` is a bare validated address.
pub fn build_message(
    config: &StalwartConfig,
    to: &str,
    email: &VerificationEmail,
) -> Result<Message, Status> {
    Message::builder()
        .from(mailbox(
            &config.stalwart_from_name,
            &config.stalwart_from_address,
            "stalwart_invalid_from_address",
        )?)
        .to(mailbox("", to, "invalid_email_address")?)
        .subject(email.subject.clone())
        .multipart(MultiPart::alternative_plain_html(
            email.text.clone(),
            email.html.clone(),
        ))
        .map_err(|e| {
            log::error!("Failed to build Stalwart email: {:?}", e);
            Status::new(Code::Internal, "stalwart_message_build_failed")
        })
}

/// Sends `message` to `host:port` with the given TLS mode, authenticating when
/// `stalwart_smtp_username` is set.
pub fn send_message_with(
    config: &StalwartConfig,
    host: &str,
    port: u16,
    tls: SmtpTls,
    message: Message,
) -> Result<(), Status> {
    let failed = |e: &dyn std::fmt::Debug| {
        log::error!("Stalwart SMTP send failed: {:?}", e);
        Status::new(Code::FailedPrecondition, "stalwart_send_failed")
    };
    run_blocking(move || {
        let builder = match tls {
            SmtpTls::Starttls => SmtpTransport::starttls_relay(host).map_err(|e| failed(&e))?,
            SmtpTls::Implicit => SmtpTransport::relay(host).map_err(|e| failed(&e))?,
            SmtpTls::None => SmtpTransport::builder_dangerous(host).tls(Tls::None),
        };
        let mut builder = builder.port(port).timeout(Some(Duration::from_secs(20)));
        if !config.stalwart_smtp_username.is_empty() {
            builder = builder.credentials(Credentials::new(
                config.stalwart_smtp_username.clone(),
                config.stalwart_smtp_password.clone(),
            ));
        }
        builder.build().send(&message).map(|_| ()).map_err(|e| failed(&e))
    })
}

/// The production entry point: host/port/TLS mode all from `config`.
pub fn send_email(
    config: &StalwartConfig,
    to: &str,
    email: &VerificationEmail,
) -> Result<(), Status> {
    let message = build_message(config, to, email)?;
    let port = effective_port(config);
    send_message_with(
        config,
        config.stalwart_smtp_host.trim(),
        port,
        tls_mode_for_port(port),
        message,
    )
}
