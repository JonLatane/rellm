//! A tiny shared `reqwest::blocking` helper for the sync platforms that speak plain REST +
//! HTTP-status-code error signaling (`mastodon_sync`, `bluesky_sync`) -- Facebook/Instagram's Graph
//! API is deliberately *not* routed through this: it signals errors via a nested `{"error": ...}`
//! JSON object even on some 200 responses rather than the HTTP status line, so `facebook_sync`
//! keeps its own `graph_request` with that different error-detection shape. Factoring this much
//! (client construction, the `block_in_place` dance, response-body-to-JSON) still avoids 3 copies
//! of the trickiest part (see below) while leaving each platform's actual error semantics distinct.

use serde_json::Value;
use tonic::{Code, Status};

/// Runs `build` against a fresh `reqwest::blocking::Client`, returning the response's HTTP status
/// and its body parsed as JSON (or `Value::Null` for an empty body). Doesn't interpret the status
/// or body itself -- callers decide what counts as success per their own API's shape.
///
/// See `event_sync::fetch_ics`'s doc comment for why `block_in_place` is used, and only when
/// there's already a Tokio runtime -- plain `#[test]`s and `bin/`s have none, and `block_in_place`
/// panics without one (mirrors `facebook_sync::graph_request`'s identical split).
pub fn blocking_json_request(
    build: impl FnOnce(&reqwest::blocking::Client) -> reqwest::blocking::RequestBuilder + Send,
    request_failed_error: &'static str,
) -> Result<(reqwest::StatusCode, Value), Status> {
    crate::init_crypto();
    let call = move || {
        let client = reqwest::blocking::Client::new();
        let response = build(&client).send().map_err(|e| {
            log::error!("HTTP request failed: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::FailedPrecondition, request_failed_error)
        })?;
        let status = response.status();
        let text = response.text().map_err(|e| {
            log::error!("Failed to read HTTP response body: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::FailedPrecondition, request_failed_error)
        })?;
        let value: Value = if text.trim().is_empty() {
            Value::Null
        } else {
            serde_json::from_str(&text).map_err(|e| {
                log::error!(
                    "Failed to parse HTTP response as JSON: {:?} ({})",
                    crate::logic::log_redaction::safe_error(&e),
                    crate::logic::log_redaction::summarize(&text)
                );
                Status::new(Code::FailedPrecondition, request_failed_error)
            })?
        };
        Ok((status, value))
    };

    run_blocking(call)
}

/// Runs a plain blocking closure (not necessarily a `reqwest` call -- see `mastodon_sync::upload_media`/
/// `bluesky_sync::upload_blob`, which fetch/upload raw media bytes rather than JSON) via
/// `tokio::task::block_in_place` when there's already a Tokio runtime, or directly otherwise (plain
/// `#[test]`s and `bin/`s have none, and `block_in_place` panics without one). Factors out the same
/// split `blocking_json_request`/`facebook_sync::graph_request` each already have their own copy of.
pub fn run_blocking<T: Send>(call: impl FnOnce() -> T + Send) -> T {
    crate::init_crypto();
    if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(call)
    } else {
        call()
    }
}
