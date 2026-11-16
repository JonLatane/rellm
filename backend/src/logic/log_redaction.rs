//! Helpers for keeping personal data and secrets out of application logs.
//!
//! Rule of thumb for this codebase: **log IDs, counts, status codes and error *codes* -- never
//! usernames, emails, phone numbers, names, message/post text, tokens, codes, passwords, or whole
//! request/response bodies.** Third-party API error bodies are the usual leak: they echo back the
//! phone number or email we sent, tokens we just received, billing details, usernames, ... so log
//! them through [`summarize`] instead of `{:?}`. Error values from HTTP clients embed the request
//! URL (including secret query strings such as private-feed tokens), so log those through
//! [`scrub_urls`]; log URLs through [`redact_url`].

use std::fmt;

/// A string that is already safe to log, printing the same under `{}` and `{:?}` (a plain `String`
/// would be quoted/escaped by `{:?}`, which makes log lines hard to read).
pub struct Safe(pub String);

impl fmt::Display for Safe {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl fmt::Debug for Safe {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Keys whose *scalar* values are safe and useful to log (status/error classification, never free
/// text). A string value is only kept if it looks like an identifier (see [`is_identifier_like`]).
const SAFE_KEYS: &[&str] = &[
    "code",
    "error_code",
    "errorCode",
    "status",
    "type",
    "error_type",
    "error",
    "errors",
    "reason",
    "subcode",
    "error_subcode",
    "fbtrace_id",
];

pub fn is_identifier_like(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | ':' | '-'))
}

/// A one-line structural summary of an API response: the top-level keys, plus the values of
/// classification fields (`code`, `status`, `type`, `error`, ...) when those are numbers/booleans or
/// identifier-like strings. Free text (messages, descriptions), tokens, and every other value are
/// omitted. Works for `serde_json::Value`, and for `String`/`&str` (summarized by length only).
pub fn summarize<T: serde::Serialize + ?Sized>(value: &T) -> Safe {
    let value = serde_json::to_value(value).unwrap_or(serde_json::Value::Null);
    Safe(summarize_value(&value, 0))
}

fn summarize_value(value: &serde_json::Value, depth: usize) -> String {
    use serde_json::Value;
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&str> = map.keys().map(|k| k.as_str()).collect();
            keys.sort_unstable();
            let mut out = format!("object(keys: {})", keys.join(","));
            if depth < 3 {
                let mut facts = Vec::new();
                for key in SAFE_KEYS {
                    if let Some(v) = map.get(*key) {
                        let shown = match v {
                            Value::Number(n) => Some(n.to_string()),
                            Value::Bool(b) => Some(b.to_string()),
                            Value::String(s) if is_identifier_like(s) => Some(s.clone()),
                            Value::Object(_) | Value::Array(_) => Some(summarize_value(v, depth + 1)),
                            _ => None,
                        };
                        if let Some(shown) = shown {
                            facts.push(format!("{key}={shown}"));
                        }
                    }
                }
                if !facts.is_empty() {
                    out.push_str(&format!(" {}", facts.join(" ")));
                }
            }
            out
        }
        Value::Array(items) => {
            if depth < 3 && !items.is_empty() {
                let first = summarize_value(&items[0], depth + 1);
                format!("array({} items, first: {first})", items.len())
            } else {
                format!("array({} items)", items.len())
            }
        }
        Value::String(s) => format!("string({} chars)", s.chars().count()),
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
    }
}

/// `scheme://host` only -- no userinfo, port, path, query or fragment (private iCal/RSS feed URLs and
/// media URLs carry secret tokens in the path or query). Unparseable input is reported as
/// `<url>`.
pub fn redact_url<U: AsRef<str> + ?Sized>(url: &U) -> Safe {
    Safe(redact_one_url(url.as_ref().trim()).unwrap_or_else(|| "<url>".to_string()))
}

fn redact_one_url(url: &str) -> Option<String> {
    let (scheme, rest) = url.split_once("://")?;
    if scheme.is_empty() || !scheme.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    let authority = rest.split(['/', '?', '#']).next()?;
    let host = authority.rsplit('@').next()?;
    let host = host.split(':').next().unwrap_or(host);
    if host.is_empty() {
        return None;
    }
    Some(format!("{scheme}://{host}"))
}

/// Replaces every `http(s)://...` URL embedded in `text` (as HTTP client errors do) with its
/// [`redact_url`] form.
pub fn scrub_urls(text: &str) -> Safe {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(pos) = find_url_start(rest) {
        out.push_str(&rest[..pos]);
        let url_and_after = &rest[pos..];
        let end = url_and_after
            .find(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | ')' | '>' | '<' | ','))
            .unwrap_or(url_and_after.len());
        out.push_str(&redact_url(&url_and_after[..end]).0);
        rest = &url_and_after[end..];
    }
    out.push_str(rest);
    Safe(out)
}

fn find_url_start(text: &str) -> Option<usize> {
    match (text.find("http://"), text.find("https://")) {
        (Some(a), Some(b)) => Some(a.min(b)),
        (a, b) => a.or(b),
    }
}

/// Free-form error text (the `Display` of an error in a `source()` chain) made safe to log:
/// URLs lose their path/query ([`scrub_urls`]), Postgres `Key (column)=(value)` details, anything
/// containing `@` (email addresses) and long digit runs (phone numbers) become `<redacted>`.
pub fn scrub_text(text: &str) -> Safe {
    let text = scrub_urls(text).0;
    let mut out = String::with_capacity(text.len());
    let mut rest = text.as_str();
    while let Some(pos) = rest.find("Key (") {
        out.push_str(&rest[..pos]);
        let after = &rest[pos..];
        // `Key (a, b)=(x, y)` -- drop through the closing paren of the value group.
        let end = after
            .find(")=(")
            .and_then(|i| after[i + 3..].find(')').map(|j| i + 3 + j + 1))
            .unwrap_or(after.len());
        out.push_str("Key <redacted>");
        rest = &after[end..];
    }
    out.push_str(rest);
    let words: Vec<String> = out
        .split(' ')
        .map(|w| {
            let digits = w.chars().filter(|c| c.is_ascii_digit()).count();
            if w.contains('@') || digits >= 7 {
                "<redacted>".to_string()
            } else {
                w.to_string()
            }
        })
        .collect();
    Safe(words.join(" "))
}

/// `{:?}` of an error that is safe to log: Diesel `DatabaseError`s keep only their kind (their
/// payload can contain the offending row's values, e.g. `Key (username)=(...) already exists`), and
/// URLs embedded in HTTP client errors lose their path/query. Use for every `e` in a log call.
pub fn safe_error<E: fmt::Debug + ?Sized>(error: &E) -> Safe {
    let text = format!("{error:?}");
    if let Some(rest) = text.strip_prefix("DatabaseError(") {
        let kind = rest.split(',').next().unwrap_or("Unknown").trim();
        return Safe(format!("DatabaseError({kind})"));
    }
    scrub_urls(&text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn summarize_keeps_codes_and_drops_text_and_secrets() {
        let body = json!({
            "code": 21211,
            "message": "The 'To' number +15551234567 is not a valid phone number.",
            "access_token": "sekrit",
            "status": 400,
            "more_info": "https://www.twilio.com/docs/errors/21211",
        });
        let s = summarize(&body).0;
        assert!(s.contains("code=21211") && s.contains("status=400"), "{s}");
        for leaked in ["+1555", "sekrit", "twilio.com", "valid phone"] {
            assert!(!s.contains(leaked), "{leaked} leaked in {s}");
        }
        // Keys are listed (useful for "response missing X" debugging) but values are not.
        assert!(s.contains("access_token"), "{s}");
    }

    #[test]
    fn summarize_drops_free_text_error_strings_but_keeps_error_ids() {
        assert!(summarize(&json!({"error": "invalid_grant"})).0.contains("error=invalid_grant"));
        let s = summarize(&json!({"error": "Hello jon@example.com, nope"})).0;
        assert!(!s.contains("jon@"), "{s}");
        let s = summarize(&json!({"errors": [{"code": 32, "message": "Could not authenticate jonlatane"}]})).0;
        assert!(s.contains("code=32") && !s.contains("jonlatane"), "{s}");
    }

    #[test]
    fn summarize_handles_strings_and_non_objects() {
        assert_eq!(summarize("hello world").0, "string(11 chars)");
        assert_eq!(summarize(&json!([1, 2, 3])).0, "array(3 items, first: 1)");
    }

    #[test]
    fn redact_url_keeps_only_scheme_and_host() {
        assert_eq!(
            redact_url("https://user:pw@example.com:8443/cal/private-abc123/basic.ics?token=x#frag").0,
            "https://example.com"
        );
        assert_eq!(redact_url("not a url").0, "<url>");
        assert_eq!(redact_url("https://example.com").0, "https://example.com");
    }

    #[test]
    fn safe_error_drops_database_error_payloads() {
        #[derive(Debug)]
        #[allow(dead_code)]
        enum Fake {
            DatabaseError(&'static str, &'static str),
        }
        let e = Fake::DatabaseError("UniqueViolation", "Key (username)=(jonlatane) already exists.");
        let s = safe_error(&e).0;
        assert_eq!(s, "DatabaseError(\"UniqueViolation\")");
        assert!(!s.contains("jonlatane"));
    }

    #[test]
    fn scrub_text_drops_row_values_emails_and_phone_numbers() {
        let s = scrub_text(
            "duplicate key value violates unique constraint \"users_username_key\" Key (username)=(jonlatane) already exists. mail jon@example.com or +15551234567 at https://x.example.com/a?t=secret",
        )
        .0;
        for leaked in ["jonlatane", "jon@", "5551234567", "secret"] {
            assert!(!s.contains(leaked), "{leaked} leaked in {s}");
        }
        assert!(s.contains("violates unique constraint") && s.contains("https://x.example.com"), "{s}");
        assert_eq!(scrub_text("connection refused (os error 111)").0, "connection refused (os error 111)");
    }

    #[test]
    fn scrub_urls_rewrites_embedded_urls() {
        let s = scrub_urls(
            r#"reqwest::Error { kind: Request, url: "https://calendar.example.com/ical/secret-token/basic.ics?x=1", source: timeout }"#,
        )
        .0;
        assert!(s.contains("https://calendar.example.com"), "{s}");
        assert!(!s.contains("secret-token") && !s.contains("x=1"), "{s}");
        assert_eq!(scrub_urls("no urls here").0, "no urls here");
    }
}
