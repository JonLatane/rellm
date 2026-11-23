//! DNS lookups and the pure SPF/DMARC parsers behind the email-domain authentication report.
//!
//! ## Where DNS queries go
//! There is no DNS-client dependency in this crate, so lookups use **DNS-over-HTTPS JSON**
//! (`GET {base}?name=..&type=TXT`, `Accept: application/dns-json`) through the same blocking
//! `reqwest` stack as everything else. By default `base` is Cloudflare's resolver
//! (`https://cloudflare-dns.com/dns-query`), which means **an admin viewing the Contact
//! Integrations status causes this server to send the sending domains' names to Cloudflare**.
//! Set `RELLM_DOH_URL` (any RFC 8484 JSON-API compatible endpoint, e.g. `https://dns.google/resolve`)
//! to use a different resolver. Everything goes through the [`DnsResolver`] trait so tests (and
//! future implementations) can substitute their own.

use std::time::Duration;

use crate::protos::{DmarcStatus, StatusLevel};

use super::copy;
use super::http::{self, Auth, Ctx};

pub const DEFAULT_DOH_URL: &str = "https://cloudflare-dns.com/dns-query";

pub const TYPE_CNAME: u16 = 5;
pub const TYPE_MX: u16 = 15;
pub const TYPE_TXT: u16 = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RecordType {
    Txt,
    Mx,
}

impl RecordType {
    fn name(self) -> &'static str {
        match self {
            RecordType::Txt => "TXT",
            RecordType::Mx => "MX",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct DnsAnswer {
    /// DNS RR type number (16 = TXT, 5 = CNAME, 15 = MX).
    pub rtype: u16,
    /// For TXT, the record's decoded text (multi-string records joined); for MX `"10 mail.example.com."`.
    pub data: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum DnsLookup {
    Found(Vec<DnsAnswer>),
    /// NXDOMAIN or an empty answer.
    NotFound,
    /// The lookup itself failed (resolver unreachable, SERVFAIL, ...).
    Failed(String),
}

impl DnsLookup {
    pub fn txt_records(&self) -> Vec<String> {
        match self {
            DnsLookup::Found(answers) => answers
                .iter()
                .filter(|a| a.rtype == TYPE_TXT)
                .map(|a| a.data.clone())
                .collect(),
            _ => vec![],
        }
    }

    /// Whether the name resolves to a TXT *or* a CNAME (a CNAME to the provider's key is how
    /// SendGrid/Mailgun-style DKIM is published).
    pub fn has_txt_or_cname(&self) -> bool {
        matches!(self, DnsLookup::Found(a) if a.iter().any(|a| a.rtype == TYPE_TXT || a.rtype == TYPE_CNAME))
    }

    pub fn failed(&self) -> Option<&str> {
        match self {
            DnsLookup::Failed(m) => Some(m),
            _ => None,
        }
    }
}

pub trait DnsResolver: Send + Sync {
    fn lookup(&self, name: &str, record_type: RecordType) -> DnsLookup;
}

/// Resolves via a DNS-over-HTTPS JSON API (see the module doc for the privacy implication).
pub struct DohResolver {
    pub base_url: String,
    pub timeout: Duration,
}

impl DohResolver {
    /// Production resolver: `RELLM_DOH_URL` or Cloudflare.
    pub fn from_env() -> DohResolver {
        DohResolver {
            base_url: std::env::var("RELLM_DOH_URL")
                .ok()
                .filter(|u| !u.trim().is_empty())
                .unwrap_or_else(|| DEFAULT_DOH_URL.to_string()),
            timeout: Duration::from_secs(5),
        }
    }

    pub fn at(base_url: &str) -> DohResolver {
        DohResolver {
            base_url: base_url.to_string(),
            timeout: Duration::from_secs(5),
        }
    }
}

impl DnsResolver for DohResolver {
    fn lookup(&self, name: &str, record_type: RecordType) -> DnsLookup {
        let ctx = Ctx::new(None, self.timeout);
        let response = http::get(
            &ctx,
            &self.base_url,
            Auth::None,
            &[("Accept", "application/dns-json")],
            &[("name", name.to_string()), ("type", record_type.name().to_string())],
        );
        match response {
            Err(e) => DnsLookup::Failed(format!("DNS resolver unreachable ({e})")),
            Ok(r) if !(200..300).contains(&r.status) => {
                DnsLookup::Failed(format!("DNS resolver returned HTTP {}", r.status))
            }
            Ok(r) => parse_doh_response(&r.body),
        }
    }
}

/// Parses an `application/dns-json` response body.
pub fn parse_doh_response(body: &serde_json::Value) -> DnsLookup {
    let Some(status) = body.get("Status").and_then(|s| s.as_i64()) else {
        return DnsLookup::Failed("unexpected DNS resolver response".to_string());
    };
    match status {
        0 => {}
        3 => return DnsLookup::NotFound,
        other => return DnsLookup::Failed(format!("DNS lookup failed (rcode {other})")),
    }
    let answers: Vec<DnsAnswer> = body
        .get("Answer")
        .and_then(|a| a.as_array())
        .map(|answers| {
            answers
                .iter()
                .filter_map(|a| {
                    let rtype = a.get("type")?.as_u64()? as u16;
                    let data = a.get("data")?.as_str()?;
                    let data = if rtype == TYPE_TXT {
                        decode_txt_data(data)
                    } else {
                        data.to_string()
                    };
                    Some(DnsAnswer { rtype, data })
                })
                .collect()
        })
        .unwrap_or_default();
    if answers.is_empty() {
        DnsLookup::NotFound
    } else {
        DnsLookup::Found(answers)
    }
}

/// Decodes a TXT record's presentation form. Resolvers return either the bare text or one-or-more
/// double-quoted `<character-string>`s (`"v=spf1 ip4:1.2.3.4" " ~all"`), possibly with `\"`/`\\`
/// escapes and `\DDD` decimal escapes; RFC 7208 §3.3 / RFC 7489 say split strings are concatenated
/// *without* separators.
pub fn decode_txt_data(data: &str) -> String {
    let trimmed = data.trim();
    if !trimmed.starts_with('"') {
        return trimmed.to_string();
    }
    let mut out = String::new();
    let mut chars = trimmed.chars().peekable();
    let mut in_quotes = false;
    while let Some(c) = chars.next() {
        if in_quotes {
            match c {
                '"' => in_quotes = false,
                '\\' => match chars.next() {
                    Some(d) if d.is_ascii_digit() => {
                        let mut digits = String::from(d);
                        for _ in 0..2 {
                            if let Some(n) = chars.peek().copied().filter(|n| n.is_ascii_digit()) {
                                digits.push(n);
                                chars.next();
                            }
                        }
                        if let Ok(code) = digits.parse::<u32>() {
                            if let Some(ch) = char::from_u32(code) {
                                out.push(ch);
                            }
                        }
                    }
                    Some(other) => out.push(other),
                    None => {}
                },
                other => out.push(other),
            }
        } else if c == '"' {
            in_quotes = true;
        }
        // Anything outside quotes (the whitespace between strings) is dropped.
    }
    out
}

// ---------------------------------------------------------------------------------------------
// SPF
// ---------------------------------------------------------------------------------------------

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SpfInfo {
    pub found: bool,
    /// More than one `v=spf1` record exists (a permanent error for receivers).
    pub multiple: bool,
    pub record: String,
    /// The `all` qualifier (`+`, `-`, `~`, `?`), if the record has an `all` mechanism.
    pub all: Option<char>,
    /// A `redirect=` modifier target.
    pub redirect: Option<String>,
    pub includes: Vec<String>,
    /// Mechanisms/modifiers that cost a DNS lookup at the top level (include, a, mx, ptr, exists,
    /// redirect). Nested includes aren't followed, so the real total is at least this.
    pub lookups: usize,
}

fn is_spf_record(txt: &str) -> bool {
    let t = txt.trim_start();
    // `get` (not `[..6]`): TXT data is arbitrary and may have a multibyte char across byte 6, and
    // a slice panic would abort the whole server (`panic = "abort"`).
    match (t.get(..6), t.get(6..)) {
        (Some(prefix), Some(rest)) if prefix.eq_ignore_ascii_case("v=spf1") => {
            rest.is_empty() || rest.starts_with(char::is_whitespace)
        }
        _ => false,
    }
}

/// Picks the SPF record out of a domain's TXT records and analyzes it.
pub fn parse_spf(txt_records: &[String]) -> SpfInfo {
    let spf: Vec<&String> = txt_records.iter().filter(|t| is_spf_record(t)).collect();
    let Some(first) = spf.first() else {
        return SpfInfo::default();
    };
    let record = first.trim().to_string();
    let mut info = SpfInfo {
        found: true,
        multiple: spf.len() > 1,
        record: record.clone(),
        ..Default::default()
    };
    for term in record.split_whitespace().skip(1) {
        let lower = term.to_ascii_lowercase();
        let (qualifier, body) = match lower.chars().next() {
            Some(q @ ('+' | '-' | '~' | '?')) => (Some(q), &lower[1..]),
            _ => (None, lower.as_str()),
        };
        if body == "all" {
            info.all = Some(qualifier.unwrap_or('+'));
        } else if let Some(rest) = lower.strip_prefix("redirect=") {
            info.redirect = Some(rest.to_string());
            info.lookups += 1;
        } else if let Some(rest) = body.strip_prefix("include:") {
            info.includes.push(rest.to_string());
            info.lookups += 1;
        } else if body == "a"
            || body.starts_with("a:")
            || body.starts_with("a/")
            || body == "mx"
            || body.starts_with("mx:")
            || body.starts_with("mx/")
            || body.starts_with("ptr")
            || body.starts_with("exists:")
        {
            info.lookups += 1;
        }
    }
    info
}

// ---------------------------------------------------------------------------------------------
// DMARC
// ---------------------------------------------------------------------------------------------

fn is_dmarc_record(txt: &str) -> bool {
    let first = txt.trim().split(';').next().unwrap_or("");
    let mut kv = first.splitn(2, '=');
    let key = kv.next().unwrap_or("").trim();
    let value = kv.next().unwrap_or("").trim();
    key.eq_ignore_ascii_case("v") && value.eq_ignore_ascii_case("DMARC1")
}

fn split_uris(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(|u| u.trim())
        .filter(|u| !u.is_empty())
        .map(|u| u.to_string())
        .collect()
}

fn alignment(value: Option<&String>) -> String {
    match value.map(|v| v.to_ascii_lowercase()).as_deref() {
        Some("s") | Some("strict") => "strict",
        _ => "relaxed",
    }
    .to_string()
}

/// Level and one-line summary for an effective DMARC `policy` (`none`/`quarantine`/`reject`/other)
/// applied to `percentage`% of failing mail. `tag` is the record tag the policy came from (`p` or
/// `sp`), shown so the admin can find it.
fn evaluate_policy(policy: &str, percentage: i32, tag: &str) -> (StatusLevel, String) {
    let plain = copy::dmarc_policy(policy);
    let (mut level, mut summary) = match policy {
        "reject" | "quarantine" => (
            StatusLevel::Ok,
            format!("Protected: {plain} ({tag}={policy})."),
        ),
        "none" => (
            StatusLevel::Warning,
            format!("Monitoring only: {plain} ({tag}=none)."),
        ),
        "" => (
            StatusLevel::Warning,
            format!("The record has no valid policy ({tag}=), so receivers ignore it."),
        ),
        other => (
            StatusLevel::Warning,
            format!("The policy \"{other}\" isn't valid; use none, quarantine or reject."),
        ),
    };
    if matches!(policy, "reject" | "quarantine") && percentage < 100 {
        level = StatusLevel::Warning;
        summary = format!(
            "Only enforced for {percentage}% of failing mail (pct={percentage}); the rest is still delivered."
        );
    }
    (level, summary)
}

/// The policy that actually governs mail from a subdomain when the record was found on a *parent*
/// domain: its `sp=` when present, else its `p=` (RFC 7489 §6.3).
pub fn effective_inherited_policy(dmarc: &DmarcStatus) -> (&'static str, String) {
    if dmarc.subdomain_policy.is_empty() {
        ("p", dmarc.policy.clone())
    } else {
        ("sp", dmarc.subdomain_policy.clone())
    }
}

/// Re-evaluates `dmarc` (as returned by [`parse_dmarc`] for a record found on a *parent* domain)
/// for the subdomain: the level and summary follow the effective inherited policy (`sp=` if set).
/// A multiple-records error is left alone.
pub fn apply_inherited_policy(mut dmarc: DmarcStatus) -> DmarcStatus {
    if !dmarc.record_found || dmarc.level == StatusLevel::Error as i32 {
        return dmarc;
    }
    let (tag, effective) = effective_inherited_policy(&dmarc);
    let (level, summary) = evaluate_policy(&effective, dmarc.percentage, tag);
    dmarc.level = level as i32;
    dmarc.summary = summary;
    dmarc
}

/// Parses `_dmarc.<domain>` TXT records into a fully populated [`DmarcStatus`], including its
/// `level` and `summary`. `records` are the TXT strings found at that name (already de-quoted);
/// per RFC 7489 §6.6.3 more than one DMARC record means *none* applies.
pub fn parse_dmarc(records: &[String]) -> DmarcStatus {
    let dmarc: Vec<&String> = records.iter().filter(|r| is_dmarc_record(r)).collect();
    if dmarc.is_empty() {
        return DmarcStatus {
            record_found: false,
            raw_record: String::new(),
            policy: String::new(),
            subdomain_policy: String::new(),
            percentage: 0,
            aggregate_report_uris: vec![],
            forensic_report_uris: vec![],
            dkim_alignment: String::new(),
            spf_alignment: String::new(),
            level: StatusLevel::Warning as i32,
            summary: "No DMARC record found.".to_string(),
        };
    }
    let raw = dmarc[0].trim().to_string();
    let mut tags: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    for part in raw.split(';') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let mut kv = part.splitn(2, '=');
        let key = kv.next().unwrap_or("").trim().to_ascii_lowercase();
        let value = kv.next().unwrap_or("").trim().to_string();
        if !key.is_empty() {
            // First occurrence wins, matching how receivers read the record left to right.
            tags.entry(key).or_insert(value);
        }
    }
    let policy = tags.get("p").map(|p| p.to_ascii_lowercase()).unwrap_or_default();
    let subdomain_policy = tags.get("sp").map(|p| p.to_ascii_lowercase()).unwrap_or_default();
    let percentage = tags
        .get("pct")
        .and_then(|p| p.parse::<i32>().ok())
        .map(|p| p.clamp(0, 100))
        .unwrap_or(100);
    let aggregate_report_uris = tags.get("rua").map(|v| split_uris(v)).unwrap_or_default();
    let forensic_report_uris = tags.get("ruf").map(|v| split_uris(v)).unwrap_or_default();
    let dkim_alignment = alignment(tags.get("adkim"));
    let spf_alignment = alignment(tags.get("aspf"));

    let (mut level, mut summary) = evaluate_policy(&policy, percentage, "p");
    if dmarc.len() > 1 {
        level = StatusLevel::Error;
        summary = "More than one DMARC record exists, so receivers ignore all of them.".to_string();
    }

    DmarcStatus {
        record_found: true,
        raw_record: raw,
        policy,
        subdomain_policy,
        percentage,
        aggregate_report_uris,
        forensic_report_uris,
        dkim_alignment,
        spf_alignment,
        level: level as i32,
        summary,
    }
}

/// The exact TXT value to suggest when a domain has no DMARC record: monitor-only (`p=none`) with
/// reports going to a mailbox the admin should replace with one they read.
pub fn suggested_dmarc_record(domain: &str) -> String {
    format!("v=DMARC1; p=none; rua=mailto:postmaster@{domain}")
}

/// `raw` (a DMARC record) with tag `key` set to `value` (replacing it, or appending it if absent);
/// every other tag is kept as written.
pub fn set_dmarc_tag(raw: &str, key: &str, value: &str) -> String {
    let mut found = false;
    let mut parts: Vec<String> = raw
        .split(';')
        .map(|p| p.trim())
        .filter(|p| !p.is_empty())
        .map(|p| {
            let name = p.splitn(2, '=').next().unwrap_or("").trim();
            if name.eq_ignore_ascii_case(key) {
                found = true;
                format!("{key}={value}")
            } else {
                p.to_string()
            }
        })
        .collect();
    if !found {
        parts.push(format!("{key}={value}"));
    }
    parts.join("; ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multibyte_txt_near_the_spf_prefix_does_not_panic() {
        // Byte 6 falls inside the 2-byte `é`; slicing there used to panic (and abort the server).
        for txt in ["aaaaa\u{e9}", "v=spf\u{e9}", "\u{e9}\u{e9}\u{e9}\u{e9}", "v=spf1\u{e9}"] {
            assert!(!parse_spf(&[txt.to_string()]).found, "{txt}");
        }
    }
    use serde_json::json;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    // ---- TXT decoding ----

    #[test]
    fn decode_txt_plain_and_quoted() {
        assert_eq!(decode_txt_data("v=spf1 -all"), "v=spf1 -all");
        assert_eq!(decode_txt_data("\"v=spf1 -all\""), "v=spf1 -all");
    }

    #[test]
    fn decode_txt_joins_split_strings_without_separator() {
        assert_eq!(
            decode_txt_data("\"v=DKIM1; k=rsa; p=MIGf\" \"MA0GCSqGSIb3\""),
            "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3"
        );
    }

    #[test]
    fn decode_txt_handles_escapes() {
        assert_eq!(decode_txt_data(r#""a \"b\" c""#), "a \"b\" c");
        assert_eq!(decode_txt_data(r#""back\\slash""#), "back\\slash");
        assert_eq!(decode_txt_data(r#""semi\059colon""#), "semi;colon");
    }

    // ---- DoH parsing ----

    #[test]
    fn doh_found_nxdomain_and_failures() {
        let found = parse_doh_response(&json!({
            "Status": 0,
            "Answer": [{"name": "x.", "type": 16, "TTL": 60, "data": "\"v=spf1 -all\""}]
        }));
        assert_eq!(found.txt_records(), vec!["v=spf1 -all".to_string()]);
        assert_eq!(parse_doh_response(&json!({"Status": 3})), DnsLookup::NotFound);
        assert_eq!(parse_doh_response(&json!({"Status": 0})), DnsLookup::NotFound);
        assert!(parse_doh_response(&json!({"Status": 2})).failed().is_some());
        assert!(parse_doh_response(&json!({"nope": 1})).failed().is_some());
    }

    #[test]
    fn doh_cname_counts_for_dkim_probe_but_is_not_txt() {
        let lookup = parse_doh_response(&json!({
            "Status": 0,
            "Answer": [{"name": "s1._domainkey.x.", "type": 5, "TTL": 60, "data": "s1.domainkey.u1.wl.sendgrid.net."}]
        }));
        assert!(lookup.has_txt_or_cname());
        assert!(lookup.txt_records().is_empty());
    }

    // ---- SPF ----

    #[test]
    fn spf_missing() {
        let spf = parse_spf(&s(&["google-site-verification=abc", "something else"]));
        assert!(!spf.found);
    }

    #[test]
    fn spf_basic_qualifiers() {
        for (record, expected) in [
            ("v=spf1 include:_spf.google.com -all", '-'),
            ("v=spf1 mx ~all", '~'),
            ("v=spf1 ?all", '?'),
            ("v=spf1 +all", '+'),
            ("v=spf1 all", '+'),
        ] {
            let spf = parse_spf(&s(&[record]));
            assert!(spf.found, "{record}");
            assert_eq!(spf.all, Some(expected), "{record}");
        }
    }

    #[test]
    fn spf_is_case_insensitive_and_whitespace_tolerant() {
        let spf = parse_spf(&s(&["  V=SPF1   INCLUDE:Mailgun.org   ~ALL  "]));
        assert!(spf.found);
        assert_eq!(spf.all, Some('~'));
        assert_eq!(spf.includes, vec!["mailgun.org".to_string()]);
    }

    #[test]
    fn spf_without_all_has_none() {
        let spf = parse_spf(&s(&["v=spf1 include:sendgrid.net"]));
        assert!(spf.found);
        assert_eq!(spf.all, None);
    }

    #[test]
    fn spf_version_prefix_must_be_whole_token() {
        assert!(!parse_spf(&s(&["v=spf10 -all"])).found);
        assert!(parse_spf(&s(&["v=spf1"])).found);
    }

    #[test]
    fn spf_counts_lookup_mechanisms() {
        let spf = parse_spf(&s(&[
            "v=spf1 a mx include:a.com include:b.com exists:%{i}.x.com ptr redirect=c.com ip4:1.2.3.4 -all",
        ]));
        // a, mx, 2 includes, exists, ptr, redirect = 7; ip4 doesn't count.
        assert_eq!(spf.lookups, 7);
        assert_eq!(spf.redirect.as_deref(), Some("c.com"));
    }

    #[test]
    fn spf_flags_multiple_records() {
        let spf = parse_spf(&s(&["v=spf1 -all", "v=spf1 ~all"]));
        assert!(spf.multiple);
    }

    // ---- DMARC ----

    #[test]
    fn dmarc_missing_is_warning_without_record() {
        let d = parse_dmarc(&s(&["some other txt"]));
        assert!(!d.record_found);
        assert_eq!(d.level, StatusLevel::Warning as i32);
        assert!(d.raw_record.is_empty());
    }

    #[test]
    fn dmarc_full_record_parsed() {
        let raw = "v=DMARC1; p=reject; sp=quarantine; pct=50; rua=mailto:a@x.com, mailto:b@x.com; ruf=mailto:f@x.com; adkim=s; aspf=r; fo=1";
        let d = parse_dmarc(&s(&[raw]));
        assert!(d.record_found);
        assert_eq!(d.raw_record, raw);
        assert_eq!(d.policy, "reject");
        assert_eq!(d.subdomain_policy, "quarantine");
        assert_eq!(d.percentage, 50);
        assert_eq!(d.aggregate_report_uris, vec!["mailto:a@x.com", "mailto:b@x.com"]);
        assert_eq!(d.forensic_report_uris, vec!["mailto:f@x.com"]);
        assert_eq!(d.dkim_alignment, "strict");
        assert_eq!(d.spf_alignment, "relaxed");
        // pct < 100 on an enforcing policy is a warning.
        assert_eq!(d.level, StatusLevel::Warning as i32);
    }

    #[test]
    fn dmarc_defaults_and_enforced_ok() {
        let d = parse_dmarc(&s(&["v=DMARC1; p=quarantine"]));
        assert_eq!(d.percentage, 100);
        assert_eq!(d.dkim_alignment, "relaxed");
        assert_eq!(d.spf_alignment, "relaxed");
        assert!(d.aggregate_report_uris.is_empty());
        assert_eq!(d.level, StatusLevel::Ok as i32);
        assert!(d.summary.contains("quarantine"));
    }

    #[test]
    fn dmarc_none_is_monitor_only_warning() {
        let d = parse_dmarc(&s(&["v=DMARC1; p=none; rua=mailto:r@x.com"]));
        assert_eq!(d.policy, "none");
        assert_eq!(d.level, StatusLevel::Warning as i32);
        assert!(d.summary.to_lowercase().contains("monitoring"));
    }

    #[test]
    fn dmarc_is_case_insensitive_and_whitespace_tolerant() {
        let d = parse_dmarc(&s(&["  V=dmarc1 ;  P=ReJect ;PCT = 100 ; RUA=mailto:z@x.com ;; "]));
        assert!(d.record_found);
        assert_eq!(d.policy, "reject");
        assert_eq!(d.percentage, 100);
        assert_eq!(d.aggregate_report_uris, vec!["mailto:z@x.com"]);
        assert_eq!(d.level, StatusLevel::Ok as i32);
    }

    #[test]
    fn dmarc_missing_or_bad_policy_is_warning() {
        assert_eq!(parse_dmarc(&s(&["v=DMARC1; rua=mailto:a@x.com"])).level, StatusLevel::Warning as i32);
        assert_eq!(parse_dmarc(&s(&["v=DMARC1; p=bogus"])).level, StatusLevel::Warning as i32);
    }

    #[test]
    fn dmarc_pct_clamped_and_invalid_defaults() {
        assert_eq!(parse_dmarc(&s(&["v=DMARC1; p=reject; pct=250"])).percentage, 100);
        assert_eq!(parse_dmarc(&s(&["v=DMARC1; p=reject; pct=abc"])).percentage, 100);
        assert_eq!(parse_dmarc(&s(&["v=DMARC1; p=reject; pct=-5"])).percentage, 0);
    }

    #[test]
    fn dmarc_must_start_with_version_tag() {
        // `v=DMARC1` not first -> not a DMARC record.
        assert!(!parse_dmarc(&s(&["p=reject; v=DMARC1"])).record_found);
        assert!(!parse_dmarc(&s(&["v=DMARC2; p=reject"])).record_found);
    }

    #[test]
    fn dmarc_multiple_records_is_error() {
        let d = parse_dmarc(&s(&["v=DMARC1; p=none", "v=DMARC1; p=reject"]));
        assert_eq!(d.level, StatusLevel::Error as i32);
    }

    #[test]
    fn dmarc_split_txt_strings_after_decoding() {
        let decoded = decode_txt_data("\"v=DMARC1; p=reje\" \"ct; rua=mailto:a@x.com\"");
        let d = parse_dmarc(&[decoded]);
        assert_eq!(d.policy, "reject");
        assert_eq!(d.aggregate_report_uris, vec!["mailto:a@x.com"]);
    }

    #[test]
    fn inherited_dmarc_uses_subdomain_policy_when_present() {
        let parent = parse_dmarc(&s(&["v=DMARC1; p=reject; sp=none; rua=mailto:a@x.com"]));
        assert_eq!(parent.level, StatusLevel::Ok as i32);
        let inherited = apply_inherited_policy(parent);
        assert_eq!(inherited.level, StatusLevel::Warning as i32);
        assert!(inherited.summary.contains("sp=none"), "{}", inherited.summary);
        // Fields describing the record itself are untouched.
        assert_eq!(inherited.policy, "reject");
        assert_eq!(inherited.subdomain_policy, "none");
    }

    #[test]
    fn inherited_dmarc_falls_back_to_p_without_sp() {
        let inherited = apply_inherited_policy(parse_dmarc(&s(&["v=DMARC1; p=quarantine"])));
        assert_eq!(inherited.level, StatusLevel::Ok as i32);
        let weak = apply_inherited_policy(parse_dmarc(&s(&["v=DMARC1; p=none"])));
        assert_eq!(weak.level, StatusLevel::Warning as i32);
        assert!(weak.summary.contains("p=none"));
    }

    #[test]
    fn inherited_sp_enforcing_over_p_none_is_ok() {
        let inherited = apply_inherited_policy(parse_dmarc(&s(&["v=DMARC1; p=none; sp=reject"])));
        assert_eq!(inherited.level, StatusLevel::Ok as i32);
        assert!(inherited.summary.contains("reject"));
    }

    #[test]
    fn suggested_record_names_domain() {
        assert_eq!(
            suggested_dmarc_record("example.com"),
            "v=DMARC1; p=none; rua=mailto:postmaster@example.com"
        );
    }

    #[test]
    fn set_dmarc_tag_replaces_or_appends() {
        assert_eq!(set_dmarc_tag("v=DMARC1; p=none; pct=50", "p", "quarantine"), "v=DMARC1; p=quarantine; pct=50");
        assert_eq!(set_dmarc_tag("v=DMARC1; p=reject", "rua", "mailto:a@x.com"), "v=DMARC1; p=reject; rua=mailto:a@x.com");
        assert_eq!(set_dmarc_tag("V=DMARC1;P=none", "p", "reject"), "V=DMARC1; p=reject");
    }
}
