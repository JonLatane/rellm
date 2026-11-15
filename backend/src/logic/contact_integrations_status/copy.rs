//! The wording shared by every email-authentication message, in ONE place: a plain-language
//! one-liner per concept (SPF, DKIM, DMARC and its policies, MX) and the single formatter for
//! exact DNS records inside `StatusCheck.fix_hint`.
//!
//! ## `fix_hint` format (UI contract)
//! A `fix_hint` is a short explanatory sentence, optionally followed by exact DNS records, each on
//! **its own line** in the form
//!
//! ```text
//! TYPE name value
//! ```
//!
//! e.g. `TXT _dmarc v=DMARC1; p=none; rua=mailto:postmaster@example.com`. `TYPE` is a DNS record
//! type (`TXT`, `CNAME`, `MX`), `name` is the host to enter in the DNS panel *relative to the
//! domain the sentence names* (`@` means the domain itself), and `value` is everything after the
//! second space (it may contain spaces and semicolons). A line is a record line iff it starts with
//! `TXT `, `CNAME ` or `MX ` -- [`parse_record_line`] is the reference parser. Lines before the
//! first record line are prose.

/// What SPF is, in one sentence.
pub const SPF: &str = "SPF lists which servers may send email for your domain.";
/// What DKIM is, in one sentence.
pub const DKIM: &str = "DKIM adds a digital signature that proves an email really came from your domain.";
/// What DMARC is, in one sentence.
pub const DMARC: &str = "DMARC tells receivers what to do with fake email sent as your domain, and sends you reports about it.";
/// What MX records are, in one sentence.
pub const MX: &str = "MX records say where email sent to your domain is delivered.";

/// What a DMARC policy does, in plain words.
pub fn dmarc_policy(policy: &str) -> &'static str {
    match policy {
        "reject" => "failing mail is rejected",
        "quarantine" => "failing mail goes to spam",
        "none" => "failing mail is still delivered (monitoring only)",
        _ => "no valid policy",
    }
}

/// `TYPE name value` -- one exact DNS record, formatted for copying.
pub fn record_line(record_type: &str, name: &str, value: &str) -> String {
    format!("{record_type} {name} {}", value.trim())
}

/// `sentence` followed by each record on its own line.
pub fn with_records(sentence: &str, records: &[String]) -> String {
    let mut out = sentence.trim().to_string();
    for record in records {
        out.push('\n');
        out.push_str(record);
    }
    out
}

/// A record name relative to `domain`: `@` for the domain itself, `_dmarc` for `_dmarc.<domain>`;
/// names outside the domain are returned unchanged.
pub fn relative_name(full: &str, domain: &str) -> String {
    let full = full.trim().trim_end_matches('.').to_ascii_lowercase();
    let domain = domain.trim().trim_end_matches('.').to_ascii_lowercase();
    if full == domain {
        "@".to_string()
    } else if let Some(prefix) = full.strip_suffix(&format!(".{domain}")) {
        prefix.to_string()
    } else {
        full
    }
}

/// Reference parser for one record line of a `fix_hint`: `Some((type, name, value))`.
pub fn parse_record_line(line: &str) -> Option<(&str, &str, &str)> {
    let mut parts = line.splitn(3, ' ');
    let record_type = parts.next()?;
    if !matches!(record_type, "TXT" | "CNAME" | "MX") {
        return None;
    }
    let name = parts.next().filter(|n| !n.is_empty())?;
    let value = parts.next().filter(|v| !v.is_empty())?;
    Some((record_type, name, value))
}

/// All record lines in a `fix_hint`.
pub fn record_lines(fix_hint: &str) -> Vec<(&str, &str, &str)> {
    fix_hint.lines().filter_map(parse_record_line).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_line_round_trips() {
        let line = record_line("TXT", "_dmarc", "v=DMARC1; p=none; rua=mailto:postmaster@example.com");
        assert_eq!(line, "TXT _dmarc v=DMARC1; p=none; rua=mailto:postmaster@example.com");
        assert_eq!(
            parse_record_line(&line),
            Some(("TXT", "_dmarc", "v=DMARC1; p=none; rua=mailto:postmaster@example.com"))
        );
    }

    #[test]
    fn prose_is_not_a_record_line() {
        assert_eq!(parse_record_line("Add this record to example.com:"), None);
        assert_eq!(parse_record_line("TXT"), None);
        assert_eq!(parse_record_line("TXT @"), None);
        let hint = with_records("Add this record:", &[record_line("TXT", "@", "v=spf1 -all")]);
        assert_eq!(record_lines(&hint), vec![("TXT", "@", "v=spf1 -all")]);
    }

    #[test]
    fn relative_names() {
        assert_eq!(relative_name("example.com", "example.com"), "@");
        assert_eq!(relative_name("_dmarc.example.com.", "example.com"), "_dmarc");
        assert_eq!(relative_name("s1._domainkey.mg.example.com", "mg.example.com"), "s1._domainkey");
        assert_eq!(relative_name("other.net", "example.com"), "other.net");
    }
}
