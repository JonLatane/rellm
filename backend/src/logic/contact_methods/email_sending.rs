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
//! TODO(email-providers): skeleton only -- the provider-sending workstream fills this in.

use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;

pub fn email_sending_available(_conn: &mut PgPooledConnection) -> bool {
    false
}

pub fn send_verification_email(
    _base_url: Option<&str>,
    _conn: &mut PgPooledConnection,
    _to: &str,
    _code: &str,
) -> Result<(), Status> {
    Err(Status::new(
        Code::FailedPrecondition,
        "email_verification_not_configured",
    ))
}
