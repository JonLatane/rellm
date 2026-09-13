//! Shared helpers for `ContactMethod` verification (SMS only this iteration -- see `TwilioConfig`/
//! `BirdConfig` in `server_configuration.proto`). Used both by `update_user.rs` (to compute
//! `ContactMethod.supported_by_server`, always server-side/never client-trusted) and by the
//! `StartContactMethodVerification`/`VerifyContactMethod` RPCs (to gate/actually place the call).
//!
//! Two providers exist today (`VerificationApi::Twilio`/`VerificationApi::Bird`), each configured
//! independently and each optional -- an admin may enable either, both, or neither.
//! `preferred_verification_apis` (stored the same way `Permission` lists are -- a JSON array of the
//! enum's string names, so it's directly admin-DB-editable too) lets an admin pick which provider
//! is tried first when both are enabled; whichever *available* (enabled+configured) providers
//! aren't explicitly ordered still get tried, in the fixed default order [Twilio, Bird], after the
//! explicitly preferred ones -- see that field's own doc in `server_configuration.proto`.

use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{bird_sync, twilio_sync};
use crate::marshaling::ToProtoServerConfiguration;
use crate::protos::{BirdConfig, TwilioConfig, VerificationApi};
use crate::rpcs::get_server_configuration_model;

/// Loads the server's stored `TwilioConfig`, if any, *unscrubbed* -- i.e. including the real
/// `twilio_api_key_secret` (the API Key's Secret). Only for internal/server-side use (actually
/// calling Twilio's API); never send this straight back to a client -- see
/// `ToProtoServerConfiguration::to_proto`'s secret-blanking for the client-facing path.
pub fn server_twilio_config(conn: &mut PgPooledConnection) -> Option<TwilioConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.twilio_config)
        .and_then(|c| serde_json::from_value::<TwilioConfig>(c).ok())
}

/// Same as `server_twilio_config`, but for Bird's `bird_access_key`.
pub fn server_bird_config(conn: &mut PgPooledConnection) -> Option<BirdConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.bird_config)
        .and_then(|c| serde_json::from_value::<BirdConfig>(c).ok())
}

pub fn twilio_available(conn: &mut PgPooledConnection) -> bool {
    server_twilio_config(conn).is_some_and(|c| c.twilio_enabled)
}

pub fn bird_available(conn: &mut PgPooledConnection) -> bool {
    server_bird_config(conn).is_some_and(|c| c.bird_enabled)
}

/// Whether the server currently has *any* SMS verification provider enabled. This is the single
/// source of truth `ContactMethod.supported_by_server` (for `tel:` values) is derived from.
pub fn verification_available(conn: &mut PgPooledConnection) -> bool {
    twilio_available(conn) || bird_available(conn)
}

/// The server's admin-set `preferred_verification_apis`, in stored order -- unlike
/// `available_verification_apis` below, this doesn't filter to only *available* providers, or add
/// the fixed-order fallback; it's the raw admin preference as stored.
pub fn preferred_verification_apis(conn: &mut PgPooledConnection) -> Vec<VerificationApi> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.preferred_verification_apis)
        .map(|v| json_to_verification_apis(&v))
        .unwrap_or_default()
}

/// The server's currently *available* (enabled+configured) providers, in the order they'd actually
/// be tried: `preferred_verification_apis` first (filtered to only those that are actually
/// available), then any other available provider in the fixed default order [Twilio, Bird] that
/// wasn't already covered by the preference list. Always in this order regardless of whether
/// `preferred_verification_apis` is admin-visible -- `ServerConfiguration.available_verification_apis`
/// (this function's proto-facing counterpart) is serialized to every caller, unlike
/// `preferred_verification_apis`/`twilio_config`/`bird_config` themselves.
pub fn available_verification_apis(conn: &mut PgPooledConnection) -> Vec<VerificationApi> {
    let twilio_available = twilio_available(conn);
    let bird_available = bird_available(conn);
    let is_available = |api: &VerificationApi| match api {
        VerificationApi::Twilio => twilio_available,
        VerificationApi::Bird => bird_available,
    };

    let mut result: Vec<VerificationApi> = preferred_verification_apis(conn)
        .into_iter()
        .filter(is_available)
        .collect();
    for api in [VerificationApi::Twilio, VerificationApi::Bird] {
        if is_available(&api) && !result.contains(&api) {
            result.push(api);
        }
    }
    result
}

/// Sends a verification `code` to `to` (a `tel:` value) via whichever provider
/// `available_verification_apis` prefers first. Fails with `verification_not_configured` if no
/// provider is available. `base_url`, if `Some`, overrides *whichever* provider ends up selected --
/// lets specs point at a local mock server regardless of which provider they've configured (see
/// `start_contact_method_verification_at`, and `bird_sync`/`twilio_sync`'s own `_at`-suffixed
/// testable variants).
pub fn send_verification_sms(
    base_url: Option<&str>,
    conn: &mut PgPooledConnection,
    to: &str,
    code: &str,
) -> Result<(), Status> {
    let body = verification_sms_body(conn, code);
    match available_verification_apis(conn).first() {
        Some(VerificationApi::Twilio) => {
            let config = server_twilio_config(conn)
                .ok_or_else(|| Status::new(Code::FailedPrecondition, "twilio_not_configured"))?;
            let base_url = base_url.unwrap_or(twilio_sync::DEFAULT_BASE_URL);
            twilio_sync::send_sms_at(base_url, &config, to, &body)
        }
        Some(VerificationApi::Bird) => {
            let config = server_bird_config(conn)
                .ok_or_else(|| Status::new(Code::FailedPrecondition, "bird_not_configured"))?;
            let base_url = base_url
                .map(|u| u.to_string())
                .unwrap_or_else(|| bird_sync::default_base_url(&config.bird_region));
            bird_sync::send_sms_at(&base_url, &config, to, &body)
        }
        None => Err(Status::new(
            Code::FailedPrecondition,
            "verification_not_configured",
        )),
    }
}

/// The actual SMS text sent by `send_verification_sms` -- names the server (`server_info.name`)
/// and, if configured, its public domain (`external_cdn_config.frontend_host`) so a recipient can
/// tell which of possibly many Rellm servers they're hearing from, plus a standard
/// don't-share-this warning. Falls back to just the server name (no parenthetical) if no CDN
/// domain is configured.
fn verification_sms_body(conn: &mut PgPooledConnection, code: &str) -> String {
    let config = get_server_configuration_model(conn)
        .ok()
        .map(|c| c.to_proto());
    let server_name = config
        .as_ref()
        .and_then(|c| c.server_info.as_ref())
        .and_then(|info| info.name.clone())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "Jonline".to_string());
    let frontend_host = config
        .as_ref()
        .and_then(|c| c.external_cdn_config.as_ref())
        .map(|cdn| cdn.frontend_host.clone())
        .filter(|host| !host.is_empty());

    match frontend_host {
        Some(host) => format!(
            "Phone verification requested from {server_name} ({host}). Your code is: {code}. Do not share this code with anyone."
        ),
        None => format!(
            "Phone verification requested from {server_name}. Your code is: {code}. Do not share this code with anyone."
        ),
    }
}

/// Parses a `VerificationApi` list stored the same way `Permission` lists are -- a JSON array of
/// the enum's string names (`ToJsonPermissions`'s own doc explains why: human-readable and
/// directly admin-DB-editable, not an opaque int). Unknown/malformed entries are silently dropped,
/// mirroring `ToProtoPermissions for serde_json::Value`'s own leniency.
pub fn json_to_verification_apis(value: &serde_json::Value) -> Vec<VerificationApi> {
    match value {
        serde_json::Value::Array(apis) => apis
            .iter()
            .filter_map(|v| v.as_str())
            .filter_map(VerificationApi::from_str_name)
            .collect(),
        _ => Vec::new(),
    }
}

/// The inverse of `json_to_verification_apis`.
pub fn verification_apis_to_json(apis: &[VerificationApi]) -> serde_json::Value {
    serde_json::Value::Array(
        apis.iter()
            .map(|a| serde_json::Value::String(a.as_str_name().to_string()))
            .collect(),
    )
}
