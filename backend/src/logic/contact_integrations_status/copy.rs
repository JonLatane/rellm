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
//! type (`TXT`, `CNAME`, `MX`), `name` is the **fully-qualified** host name (lowercase, no trailing
//! dot; the apex is just the bare domain, e.g. `TXT example.com v=spf1 ...`,
//! `TXT _dmarc.example.com v=DMARC1; ...`, `CNAME s1._domainkey.example.com u123.wl.sendgrid.net`) --
//! never relative to anything, because a record can live in a different zone than the sending
//! domain. `value` is everything after the second space (it may contain spaces and semicolons). A line is a record line iff it starts with
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

/// A fully-qualified record name: lowercase, no trailing dot, no surrounding space.
pub fn fqdn(name: &str) -> String {
    name.trim().trim_end_matches('.').to_ascii_lowercase()
}

/// `TYPE fqdn value` -- one exact DNS record, formatted for copying. `name` must already be the
/// full host name (it is only normalized, never made relative).
pub fn record_line(record_type: &str, name: &str, value: &str) -> String {
    format!("{record_type} {} {}", fqdn(name), value.trim())
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

/// Reference parser for one record line of a `fix_hint`: `Some((type, name, value))`.
pub fn parse_record_line(line: &str) -> Option<(&str, &str, &str)> {
    let mut parts = line.splitn(3, ' ');
    let record_type = parts.next()?;
    if !matches!(record_type, "TXT" | "CNAME" | "MX") {
        return None;
    }
    let name = parts.next().filter(|n| !n.is_empty() && *n != "@" && !n.ends_with('.'))?;
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
    fn record_line_round_trips_with_a_fully_qualified_name() {
        let line = record_line("TXT", "_dmarc.example.com", "v=DMARC1; p=none; rua=mailto:postmaster@example.com");
        assert_eq!(line, "TXT _dmarc.example.com v=DMARC1; p=none; rua=mailto:postmaster@example.com");
        assert_eq!(
            parse_record_line(&line),
            Some(("TXT", "_dmarc.example.com", "v=DMARC1; p=none; rua=mailto:postmaster@example.com"))
        );
    }

    #[test]
    fn names_are_normalized_never_relativized() {
        assert_eq!(record_line("TXT", "Example.COM.", "v=spf1 -all"), "TXT example.com v=spf1 -all");
        assert_eq!(
            record_line("CNAME", "s1._domainkey.example.com", "u1.wl.sendgrid.net"),
            "CNAME s1._domainkey.example.com u1.wl.sendgrid.net"
        );
    }

    #[test]
    fn prose_and_relative_names_are_not_record_lines() {
        assert_eq!(parse_record_line("Add this record to example.com:"), None);
        assert_eq!(parse_record_line("TXT"), None);
        assert_eq!(parse_record_line("TXT example.com"), None);
        assert_eq!(parse_record_line("TXT @ v=spf1 -all"), None);
        let hint = with_records("Add this record:", &[record_line("TXT", "example.com", "v=spf1 -all")]);
        assert_eq!(record_lines(&hint), vec![("TXT", "example.com", "v=spf1 -all")]);
    }
}
