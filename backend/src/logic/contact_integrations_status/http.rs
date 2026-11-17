//! Tiny, timeout-bounded GET helper for the provider status checks. Deliberately separate from
//! `logic::http_client::blocking_json_request`: that helper has no timeout, collapses every failure
//! into one `Status`, and rejects non-JSON bodies -- here we need the HTTP status code of every
//! response (a 401 vs a 403 vs a 404 mean different things on a status page), a hard per-call
//! timeout, and a shared per-provider deadline so one slow provider can't hang the RPC.
//!
//! Nothing in here ever logs or returns a credential: callers pass credentials only through
//! [`Auth`], which is applied as a header, and error strings are built from the *kind* of failure
//! (timeout / connect / HTTP status), never from the request.

use std::time::{Duration, Instant};

use serde_json::Value;

/// Per-call timeout for provider HTTP requests.
pub const CALL_TIMEOUT: Duration = Duration::from_secs(8);
/// Default overall budget for all of one provider's calls.
pub const PROVIDER_BUDGET: Duration = Duration::from_secs(20);

/// Shared by every call one provider's check makes.
#[derive(Clone, Debug)]
pub struct Ctx {
    /// If `Some`, replaces *every* provider host (tests point this at a local mock server).
    pub base_url: Option<String>,
    pub deadline: Instant,
    pub per_call: Duration,
}

impl Ctx {
    pub fn new(base_url: Option<&str>, budget: Duration) -> Ctx {
        Ctx {
            base_url: base_url.map(|u| u.trim_end_matches('/').to_string()),
            deadline: Instant::now() + budget,
            per_call: CALL_TIMEOUT,
        }
    }

    /// `default_host` (e.g. `https://api.twilio.com`) unless overridden by `base_url`.
    pub fn host(&self, default_host: &str) -> String {
        self.base_url
            .clone()
            .unwrap_or_else(|| default_host.trim_end_matches('/').to_string())
    }

    fn timeout(&self) -> Option<Duration> {
        let remaining = self.deadline.checked_duration_since(Instant::now())?;
        if remaining.is_zero() {
            return None;
        }
        Some(remaining.min(self.per_call))
    }
}

#[derive(Clone, Copy)]
pub enum Auth<'a> {
    None,
    Basic(&'a str, &'a str),
    Bearer(&'a str),
    /// A custom header, e.g. `X-Postmark-Server-Token`.
    Header(&'static str, &'a str),
}

#[derive(Debug, Clone)]
pub struct Response {
    pub status: u16,
    /// The body parsed as JSON; `Value::Null` if empty or not JSON.
    pub body: Value,
}

/// Why a call didn't produce a usable 2xx JSON body.
#[derive(Debug, Clone, PartialEq)]
pub enum Fail {
    Unauthorized,
    Forbidden(String),
    NotFound,
    Http(u16, String),
    /// Timeout, connection refused, DNS failure, budget exhausted, ...
    Unreachable(String),
}

impl Fail {
    pub fn describe(&self) -> String {
        match self {
            Fail::Unauthorized => "HTTP 401 (credentials rejected)".to_string(),
            Fail::Forbidden(m) if m.is_empty() => "HTTP 403 (not permitted)".to_string(),
            Fail::Forbidden(m) => format!("HTTP 403 ({m})"),
            Fail::NotFound => "HTTP 404 (not found)".to_string(),
            Fail::Http(code, m) if m.is_empty() => format!("HTTP {code}"),
            Fail::Http(code, m) => format!("HTTP {code} ({m})"),
            Fail::Unreachable(m) => m.clone(),
        }
    }

    pub fn is_unreachable(&self) -> bool {
        matches!(self, Fail::Unreachable(_))
    }

    /// 401 or 403: the request was understood but refused.
    pub fn is_access_denied(&self) -> bool {
        matches!(self, Fail::Unauthorized | Fail::Forbidden(_))
    }
}

/// Issues a GET. `Err` is only ever a short, secret-free description of a transport failure.
pub fn get(
    ctx: &Ctx,
    url: &str,
    auth: Auth,
    headers: &[(&str, &str)],
    query: &[(&str, String)],
) -> Result<Response, String> {
    let timeout = ctx
        .timeout()
        .ok_or_else(|| "ran out of time checking this provider".to_string())?;
    crate::init_crypto();
    let client = reqwest::blocking::Client::builder()
        .timeout(timeout)
        .user_agent("Rellm-status-check")
        .build()
        .map_err(|_| "could not build an HTTP client".to_string())?;
    let mut request = client.get(url).header("Accept", "application/json");
    if !query.is_empty() {
        request = request.query(query);
    }
    for (name, value) in headers {
        request = request.header(*name, *value);
    }
    request = match auth {
        Auth::None => request,
        Auth::Basic(user, pass) => request.basic_auth(user, Some(pass)),
        Auth::Bearer(token) => request.bearer_auth(token),
        Auth::Header(name, value) => request.header(name, value),
    };
    let response = request.send().map_err(|e| {
        if e.is_timeout() {
            "timed out".to_string()
        } else if e.is_connect() {
            "could not connect".to_string()
        } else {
            "request failed".to_string()
        }
    })?;
    let status = response.status().as_u16();
    let text = response.text().unwrap_or_default();
    let body = if text.trim().is_empty() {
        Value::Null
    } else {
        serde_json::from_str(&text).unwrap_or(Value::Null)
    };
    Ok(Response { status, body })
}

/// 2xx -> the JSON body; everything else -> a classified [`Fail`].
pub fn json(result: Result<Response, String>) -> Result<Value, Fail> {
    match result {
        Err(e) => Err(Fail::Unreachable(e)),
        Ok(Response { status, body }) => match status {
            200..=299 => Ok(body),
            401 => Err(Fail::Unauthorized),
            403 => Err(Fail::Forbidden(error_message(&body))),
            404 => Err(Fail::NotFound),
            other => Err(Fail::Http(other, error_message(&body))),
        },
    }
}

/// Convenience: `get` + `json`.
pub fn get_json(
    ctx: &Ctx,
    url: &str,
    auth: Auth,
    headers: &[(&str, &str)],
    query: &[(&str, String)],
) -> Result<Value, Fail> {
    json(get(ctx, url, auth, headers, query))
}

/// Best-effort short error message out of the common provider error shapes.
pub fn error_message(body: &Value) -> String {
    let candidates = [
        body.get("message"),
        body.get("Message"),
        body.get("error"),
        body.get("detail"),
        body.pointer("/errors/0/detail"),
        body.pointer("/errors/0/title"),
        body.pointer("/errors/0/message"),
    ];
    candidates
        .into_iter()
        .flatten()
        .find_map(|v| v.as_str())
        .map(|s| s.chars().take(160).collect::<String>())
        .unwrap_or_default()
}

/// Percent-encodes a value for use as a URL *path segment* (used for phone numbers and domains).
pub fn encode_segment(value: &str) -> String {
    let mut out = String::new();
    for b in value.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

pub fn str_of<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("")
}

/// A JSON number that providers sometimes send as a string (`"12.34"`).
pub fn f64_of(value: &Value) -> Option<f64> {
    match value {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse::<f64>().ok(),
        _ => None,
    }
}

pub fn i64_of(value: &Value) -> i64 {
    f64_of(value).map(|f| f as i64).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn encode_segment_escapes_plus_and_at() {
        assert_eq!(encode_segment("+15551234567"), "%2B15551234567");
        assert_eq!(encode_segment("a@b.com"), "a%40b.com");
        assert_eq!(encode_segment("mg.example.com"), "mg.example.com");
    }

    #[test]
    fn error_message_finds_common_shapes() {
        assert_eq!(error_message(&json!({"message": "bad key"})), "bad key");
        assert_eq!(error_message(&json!({"Message": "Invalid token"})), "Invalid token");
        assert_eq!(
            error_message(&json!({"errors": [{"title": "Authentication failed"}]})),
            "Authentication failed"
        );
        assert_eq!(error_message(&json!({})), "");
    }

    #[test]
    fn json_classifies_statuses() {
        let r = |status| Ok(Response { status, body: json!({"message": "m"}) });
        assert_eq!(json(r(401)), Err(Fail::Unauthorized));
        assert_eq!(json(r(403)), Err(Fail::Forbidden("m".into())));
        assert_eq!(json(r(404)), Err(Fail::NotFound));
        assert_eq!(json(r(500)), Err(Fail::Http(500, "m".into())));
        assert!(json(r(200)).is_ok());
        assert!(json(Err("timed out".to_string())).unwrap_err().is_unreachable());
    }

    #[test]
    fn number_parsing_accepts_strings() {
        assert_eq!(f64_of(&json!("12.5")), Some(12.5));
        assert_eq!(f64_of(&json!(3)), Some(3.0));
        assert_eq!(i64_of(&json!("7")), 7);
        assert_eq!(f64_of(&json!(null)), None);
    }

    #[test]
    fn exhausted_budget_is_unreachable_not_a_panic() {
        let ctx = Ctx::new(None, Duration::ZERO);
        let result = get(&ctx, "http://127.0.0.1:1/", Auth::None, &[], &[]);
        assert!(result.is_err());
    }
}
