//! Per-sending-domain email authentication report: live SPF / DKIM / DMARC / MX lookups (through a
//! [`DnsResolver`]) merged with whatever each provider's API reported about the domain.

use std::collections::BTreeSet;

use crate::protos::{DmarcStatus, EmailDomainStatus, StatusCheck, StatusLevel};

use super::copy;
use super::dns::{
    apply_inherited_policy, effective_inherited_policy, parse_dmarc, parse_spf, set_dmarc_tag, suggested_dmarc_record, DnsLookup, DnsResolver, RecordType,
};
use super::report::{make_check, worst_level, DomainReport};

/// A domain providers send from, and which providers (ids) do.
#[derive(Clone, Debug, PartialEq)]
pub struct SendingDomain {
    pub domain: String,
    pub used_by: Vec<String>,
}

/// Well-known DKIM selectors worth probing for each provider (`{selector}._domainkey.{domain}`).
/// Postmark's selector is date-based (`20130519081005pm`) and comes from its Domains API instead;
/// Stalwart's come from its management API when available, else these common defaults.
pub fn dkim_selectors_for(provider: &str) -> &'static [&'static str] {
    match provider {
        "sendgrid" => &["s1", "s2"],
        "mailgun" => &["smtp", "k1", "mailo", "krs"],
        "stalwart" => &["default", "mail", "dkim", "selector1", "selector2", "rsa", "ed"],
        _ => &[],
    }
}

/// The domain part of a `From` address (`Name <a@b.com>` and bare `a@b.com` both work),
/// lowercased; `None` if there isn't a plausible one.
pub fn domain_of_address(address: &str) -> Option<String> {
    let address = address.trim();
    let inner = match (address.rfind('<'), address.rfind('>')) {
        (Some(l), Some(r)) if l < r => &address[l + 1..r],
        _ => address,
    };
    let (_, domain) = inner.trim().rsplit_once('@')?;
    let domain = domain.trim().trim_end_matches('.').to_ascii_lowercase();
    if domain.contains('.') && !domain.contains(char::is_whitespace) {
        Some(domain)
    } else {
        None
    }
}

/// The organizational domain receivers fall back to (RFC 7489 §6.6.3): the registrable domain under
/// the public suffix list (`example.co.uk` for `a.b.example.co.uk`).
fn organizational_domain(domain: &str) -> Option<String> {
    psl::domain_str(domain).map(str::to_string)
}

/// Looks up the DMARC record for `domain` the way receivers do (RFC 7489 §6.6.3): the exact domain
/// first, then -- only if that has none -- its organizational domain. Intermediate parents
/// (`_dmarc.b.example.com` for `a.b.example.com`) are never consulted. Returns the status plus the
/// name the record was found at (`None` if there is none / the lookup failed).
fn lookup_dmarc(resolver: &dyn DnsResolver, domain: &str) -> (DmarcStatus, Option<String>) {
    let mut candidates = vec![domain.to_string()];
    if let Some(org) = organizational_domain(domain).filter(|org| org != domain) {
        candidates.push(org);
    }
    let mut failure: Option<String> = None;
    for candidate in candidates {
        match resolver.lookup(&format!("_dmarc.{candidate}"), RecordType::Txt) {
            lookup @ DnsLookup::Found(_) => {
                let status = parse_dmarc(&lookup.txt_records());
                if status.record_found {
                    // A record on the organizational domain governs this subdomain through its `sp=`.
                    let status = if candidate == domain { status } else { apply_inherited_policy(status) };
                    return (status, Some(candidate));
                }
            }
            DnsLookup::NotFound => {}
            DnsLookup::Failed(message) => {
                failure = Some(message);
                break;
            }
        }
    }
    let mut status = parse_dmarc(&[]);
    if let Some(message) = failure {
        status.level = StatusLevel::Unknown as i32;
        status.summary = format!("Couldn't look up the DMARC record ({message}).");
    }
    (status, None)
}

/// SPF `include:` hosts the providers publish for authorizing their servers.
fn spf_includes_for(used_by: &[String]) -> Vec<&'static str> {
    let mut hosts = vec![];
    for provider in used_by {
        match provider.as_str() {
            "sendgrid" => hosts.push("sendgrid.net"),
            "mailgun" => hosts.push("mailgun.org"),
            "postmark" => hosts.push("spf.mtasv.net"),
            _ => {}
        }
    }
    hosts
}

/// `record` with its `all` mechanism (or lack of one) replaced by `~all`.
fn spf_with_soft_fail(record: &str) -> String {
    let mut terms: Vec<String> = record
        .split_whitespace()
        .filter(|t| {
            let t = t.to_ascii_lowercase();
            !(t == "all" || t == "+all" || t == "?all" || t == "-all" || t == "~all")
        })
        .map(|t| t.to_string())
        .collect();
    terms.push("~all".to_string());
    terms.join(" ")
}

fn spf_check(domain: &str, lookup: &DnsLookup, used_by: &[String]) -> StatusCheck {
    let name = "SPF";
    if lookup.failed().is_some() {
        return make_check(StatusLevel::Unknown, name, "Couldn't look up SPF right now (the DNS lookup failed).", None);
    }
    let spf = parse_spf(&lookup.txt_records());
    if !spf.found {
        let includes = spf_includes_for(used_by);
        let detail = format!("No SPF record found. {}", copy::SPF);
        if includes.is_empty() {
            // We don't know which host(s) send this domain's mail (e.g. a self-hosted Stalwart),
            // so don't present a finished-looking record with a placeholder in it.
            return make_check(
                StatusLevel::Warning,
                name,
                detail,
                Some(&format!(
                    "Add a TXT record at `{domain}` that lists the server(s) allowed to send your mail, ending in `~all`. For a mail server you run yourself that is usually its IP address (`v=spf1 ip4:<server IP> ~all`) or, if it's your MX host, `v=spf1 mx ~all`."
                )),
            );
        }
        let value = format!(
            "v=spf1 {} ~all",
            includes.iter().map(|h| format!("include:{h}")).collect::<Vec<_>>().join(" ")
        );
        return make_check(
            StatusLevel::Warning,
            name,
            detail,
            Some(&copy::with_records(
                &format!("Add this record to `{domain}`:"),
                &[copy::record_line("TXT", domain, &value)],
            )),
        );
    }
    if spf.multiple {
        return make_check(
            StatusLevel::Error,
            name,
            "More than one SPF record exists, so receivers ignore SPF entirely.",
            Some("Combine them into a single TXT record (merge the `include:` parts) and delete the others."),
        );
    }
    let fixed = copy::record_line("TXT", domain, &spf_with_soft_fail(&spf.record));
    let (mut level, mut detail, mut fix) = match (spf.all, &spf.redirect) {
        (Some('+'), _) => (
            StatusLevel::Error,
            "SPF lets anyone send email as your domain (`+all`).".to_string(),
            Some(copy::with_records(
                &format!("Change the ending to `~all` so only listed servers can send. Replace the record on `{domain}` with:"),
                &[fixed.clone()],
            )),
        ),
        (Some('?'), _) => (
            StatusLevel::Warning,
            "SPF doesn't say what to do with unlisted senders (`?all`).".to_string(),
            Some(copy::with_records(
                &format!("Change the ending to `~all`. Replace the record on `{domain}` with:"),
                &[fixed.clone()],
            )),
        ),
        (Some('-'), _) => (StatusLevel::Ok, "SPF is set up; unlisted senders are rejected.".to_string(), None),
        (Some('~'), _) => (StatusLevel::Ok, "SPF is set up; unlisted senders are marked suspicious.".to_string(), None),
        (_, Some(target)) => (StatusLevel::Ok, format!("SPF is set up through {target}."), None),
        (_, None) => (
            StatusLevel::Warning,
            "The SPF record has no ending rule, so unlisted senders aren't handled.".to_string(),
            Some(copy::with_records(
                &format!("Add `~all` to the end. Replace the record on `{domain}` with:"),
                &[fixed],
            )),
        ),
    };
    if spf.lookups > 10 {
        level = StatusLevel::Warning;
        detail = format!(
            "SPF needs {} DNS lookups but the limit is 10, so some receivers will fail it.",
            spf.lookups
        );
        fix = Some("Remove `include:` entries you no longer use, or ask your provider about a flattened record.".to_string());
    }
    make_check(level, name, detail, fix.as_deref())
}

fn mx_check(lookup: &DnsLookup) -> StatusCheck {
    let name = "Incoming mail (MX)";
    match lookup {
        DnsLookup::Failed(_) => make_check(StatusLevel::Unknown, name, "Couldn't look up MX records right now (the DNS lookup failed).", None),
        DnsLookup::NotFound => make_check(
            StatusLevel::Info,
            name,
            "No MX records, so this domain can't receive replies or bounces. That's fine if it only sends email.",
            None,
        ),
        DnsLookup::Found(answers) => {
            let hosts: Vec<String> = answers
                .iter()
                .filter(|a| a.rtype == super::dns::TYPE_MX)
                .map(|a| a.data.clone())
                .collect();
            make_check(StatusLevel::Info, name, format!("Incoming mail is delivered to {}.", hosts.join(", ")), None)
        }
    }
}

fn dmarc_check(domain: &str, dmarc: &DmarcStatus, found_at: &Option<String>) -> StatusCheck {
    let name = "DMARC";
    let level = StatusLevel::try_from(dmarc.level).unwrap_or(StatusLevel::Unknown);
    let parent = found_at.as_ref().filter(|p| p.as_str() != domain);
    let (tag, effective_policy) = match parent {
        Some(_) => effective_inherited_policy(dmarc),
        None => ("p", dmarc.policy.clone()),
    };
    if level == StatusLevel::Unknown {
        return make_check(level, name, "Couldn't look up DMARC right now (the DNS lookup failed).", None);
    }
    let mut detail = dmarc.summary.clone();
    if let Some(parent) = parent {
        detail = format!("Uses the record on {parent} (its `{tag}` applies here). {detail}");
    }
    if !dmarc.record_found && level == StatusLevel::Warning {
        detail = format!("{detail} {}", copy::DMARC);
    }
    let own_raw = if parent.is_none() { dmarc.raw_record.as_str() } else { "" };
    let fix = if !dmarc.record_found && level == StatusLevel::Warning {
        Some(copy::with_records(
            &format!("Start in monitoring mode. Add this record to `{domain}` (replace the address with a mailbox you read; it receives the reports):"),
            &[copy::record_line("TXT", &format!("_dmarc.{domain}"), &suggested_dmarc_record(domain))],
        ))
    } else if dmarc.record_found && level == StatusLevel::Error {
        Some("Keep exactly one DMARC record (a TXT record named `_dmarc`) and delete the others.".to_string())
    } else if dmarc.record_found && effective_policy == "none" && parent.is_some() {
        Some(copy::with_records(
            &format!("This domain is only covered by its parent's monitoring-only policy. Once your reports look clean, give `{domain}` its own record:"),
            &[copy::record_line("TXT", &format!("_dmarc.{domain}"), &set_dmarc_tag(&suggested_dmarc_record(domain), "p", "quarantine"))],
        ))
    } else if dmarc.record_found && effective_policy == "none" {
        Some(copy::with_records(
            &format!("Once your reports show only your own mail passing, tighten the policy. Replace the record at `_dmarc.{domain}` with:"),
            &[copy::record_line("TXT", &format!("_dmarc.{domain}"), &set_dmarc_tag(own_raw, "p", "quarantine"))],
        ))
    } else if dmarc.record_found && dmarc.percentage < 100 && level == StatusLevel::Warning && parent.is_none() {
        Some(copy::with_records(
            &format!("Raise `pct` to 100 once you're confident. Replace the record at `_dmarc.{domain}` with:"),
            &[copy::record_line("TXT", &format!("_dmarc.{domain}"), &set_dmarc_tag(own_raw, "pct", "100"))],
        ))
    } else if dmarc.record_found && level == StatusLevel::Warning && parent.is_none() && dmarc.policy.is_empty() {
        Some(copy::with_records(
            &format!("Add a policy. Replace the record at `_dmarc.{domain}` with:"),
            &[copy::record_line("TXT", &format!("_dmarc.{domain}"), &set_dmarc_tag(own_raw, "p", "none"))],
        ))
    } else {
        None
    };
    make_check(level, name, detail, fix.as_deref())
}

fn reports_check(domain: &str, dmarc: &DmarcStatus, found_at: &Option<String>) -> Option<StatusCheck> {
    let own = found_at.as_deref() == Some(domain);
    if own && dmarc.record_found && dmarc.aggregate_report_uris.is_empty() {
        Some(make_check(
            StatusLevel::Info,
            "DMARC reports",
            "You aren't getting DMARC reports, so you can't see who else sends as your domain.",
            Some(&copy::with_records(
                &format!("Add a `rua` address (a mailbox you read) to the record. Replace the record at `_dmarc.{domain}` with:"),
                &[copy::record_line(
                    "TXT",
                    &format!("_dmarc.{domain}"),
                    &set_dmarc_tag(&dmarc.raw_record, "rua", &format!("mailto:postmaster@{domain}")),
                )],
            )),
        ))
    } else {
        None
    }
}

/// Whether `lookup` resolves to a DKIM record that carries a usable public key: a TXT answer (a
/// CNAME's target counts -- resolvers follow it) with a non-empty `p=` tag. `p=` with nothing after
/// it is how a revoked key is published; a CNAME whose target has no TXT record has no key either.
fn has_usable_dkim_key(lookup: &DnsLookup) -> bool {
    lookup.txt_records().iter().any(|record| {
        record.split(';').any(|tag| {
            tag.split_once('=').is_some_and(|(k, v)| {
                k.trim().eq_ignore_ascii_case("p") && !v.chars().all(char::is_whitespace)
            })
        })
    })
}

fn dkim_check(
    domain: &str,
    probes: &[(String, DnsLookup)],
    provider_reported_dkim_ok: bool,
) -> StatusCheck {
    let name = "DKIM";
    let short = |n: &str| n.strip_suffix(&format!(".{domain}")).unwrap_or(n).to_string();
    let usable: Vec<String> = probes.iter().filter(|(_, l)| has_usable_dkim_key(l)).map(|(n, _)| short(n)).collect();
    let unusable: Vec<String> =
        probes.iter().filter(|(_, l)| l.has_txt_or_cname() && !has_usable_dkim_key(l)).map(|(n, _)| short(n)).collect();
    let probed: Vec<String> = probes.iter().map(|(n, _)| short(n)).collect();
    if !usable.is_empty() {
        return make_check(StatusLevel::Ok, name, format!("Signing key found ({}).", usable.join(", ")), None);
    }
    if !unusable.is_empty() {
        return make_check(
            StatusLevel::Warning,
            name,
            format!(
                "A DKIM record exists at {} but it has no usable key (it was revoked, or it points to something that has no key). {}",
                unusable.join(", "),
                copy::DKIM
            ),
            Some(&format!(
                "Open your email provider's domain-authentication page for `{domain}`, re-add the DKIM records it shows (replacing the old ones), then click Verify there."
            )),
        );
    }
    if probes.is_empty() {
        return make_check(StatusLevel::Unknown, name, "Not sure which DKIM key names to look for with your email provider.", None);
    }
    if probes.iter().all(|(_, l)| l.failed().is_some()) {
        return make_check(StatusLevel::Unknown, name, "Couldn't look up DKIM right now (the DNS lookup failed).", None);
    }
    if provider_reported_dkim_ok {
        make_check(
            StatusLevel::Info,
            name,
            format!(
                "Your provider says DKIM is verified, but we didn't find its key at the usual names ({}). It may use a custom name.",
                probed.join(", ")
            ),
            None,
        )
    } else {
        make_check(
            StatusLevel::Warning,
            name,
            format!("No DKIM signing key found (looked for {}). {}", probed.join(", "), copy::DKIM),
            Some(&format!(
                "Open your email provider's domain-authentication page for `{domain}`, add the DKIM records it shows, then click Verify there."
            )),
        )
    }
}

fn status_summary(domain: &str, checks: &[StatusCheck]) -> String {
    let names = |level: StatusLevel| -> Vec<&str> {
        let mut v: Vec<&str> = checks.iter().filter(|c| c.level == level as i32).map(|c| c.name.as_str()).collect();
        v.dedup();
        v
    };
    let mut bad = names(StatusLevel::Error);
    bad.extend(names(StatusLevel::Warning));
    let unknown = names(StatusLevel::Unknown);
    match (bad.is_empty(), unknown.is_empty()) {
        (false, true) => format!("{domain}: needs attention - {}", bad.join(", ")),
        (false, false) => format!(
            "{domain}: needs attention - {} (couldn't check: {})",
            bad.join(", "),
            unknown.join(", ")
        ),
        (true, false) => format!("{domain}: couldn't fully check - no result for {}", unknown.join(", ")),
        (true, true) => format!("{domain}: SPF, DKIM and DMARC are set up"),
    }
}

/// Builds the full report for one domain. `reports` are the providers' own findings for exactly
/// this domain. All DNS lookups run concurrently.
pub fn build_domain_status(
    sending: &SendingDomain,
    reports: &[&DomainReport],
    resolver: &dyn DnsResolver,
) -> EmailDomainStatus {
    let domain = sending.domain.as_str();

    let mut probe_names: BTreeSet<String> = BTreeSet::new();
    for provider in &sending.used_by {
        for selector in dkim_selectors_for(provider) {
            probe_names.insert(format!("{selector}._domainkey.{domain}"));
        }
    }
    for report in reports {
        for host in &report.dkim_hosts {
            probe_names.insert(host.trim_end_matches('.').to_ascii_lowercase());
        }
    }
    let provider_dkim_ok = reports
        .iter()
        .flat_map(|r| r.checks.iter())
        .any(|c| c.name.contains("DKIM") && c.level == StatusLevel::Ok as i32);

    let (spf_lookup, mx_lookup, (dmarc, dmarc_at), probes) = std::thread::scope(|scope| {
        let spf = scope.spawn(|| resolver.lookup(domain, RecordType::Txt));
        let mx = scope.spawn(|| resolver.lookup(domain, RecordType::Mx));
        let dmarc = scope.spawn(|| lookup_dmarc(resolver, domain));
        let probe_handles: Vec<_> = probe_names
            .iter()
            .map(|name| {
                let name = name.clone();
                scope.spawn(move || {
                    let lookup = resolver.lookup(&name, RecordType::Txt);
                    (name, lookup)
                })
            })
            .collect();
        let fail = |what: &str| DnsLookup::Failed(format!("{what} lookup crashed"));
        (
            spf.join().unwrap_or_else(|_| fail("SPF")),
            mx.join().unwrap_or_else(|_| fail("MX")),
            dmarc.join().unwrap_or_else(|_| {
                let mut s = parse_dmarc(&[]);
                s.level = StatusLevel::Unknown as i32;
                (s, None)
            }),
            probe_handles
                .into_iter()
                .filter_map(|h| h.join().ok())
                .collect::<Vec<_>>(),
        )
    });

    let mut checks = vec![
        spf_check(domain, &spf_lookup, &sending.used_by),
        dkim_check(domain, &probes, provider_dkim_ok),
        dmarc_check(domain, &dmarc, &dmarc_at),
    ];
    if let Some(c) = reports_check(domain, &dmarc, &dmarc_at) {
        checks.push(c);
    }
    checks.push(mx_check(&mx_lookup));
    for report in reports {
        checks.extend(report.checks.iter().cloned());
    }

    let level = worst_level(checks.iter().map(|c| c.level));
    EmailDomainStatus {
        domain: sending.domain.clone(),
        used_by: sending.used_by.clone(),
        level: level as i32,
        summary: status_summary(domain, &checks),
        dmarc: Some(dmarc),
        checks,
    }
}

/// Builds every domain's report, concurrently across domains.
pub fn build_domain_statuses(
    domains: &[SendingDomain],
    reports: &[DomainReport],
    resolver: &dyn DnsResolver,
) -> Vec<EmailDomainStatus> {
    std::thread::scope(|scope| {
        let handles: Vec<_> = domains
            .iter()
            .map(|sending| {
                let mine: Vec<&DomainReport> = reports
                    .iter()
                    .filter(|r| r.domain.eq_ignore_ascii_case(&sending.domain))
                    .collect();
                scope.spawn(move || build_domain_status(sending, &mine, resolver))
            })
            .collect();
        domains
            .iter()
            .zip(handles)
            .map(|(sending, handle)| {
                handle.join().unwrap_or_else(|_| EmailDomainStatus {
                    domain: sending.domain.clone(),
                    used_by: sending.used_by.clone(),
                    level: StatusLevel::Unknown as i32,
                    summary: format!("{}: the check crashed", sending.domain),
                    dmarc: Some(parse_dmarc(&[])),
                    checks: vec![],
                })
            })
            .collect()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::dns::{DnsAnswer, TYPE_TXT};
    use std::collections::HashMap;

    #[test]
    fn missing_spf_for_an_unknown_sender_gives_prose_not_a_placeholder_record() {
        let check = spf_check("example.com", &DnsLookup::NotFound, &["stalwart".to_string()]);
        let hint = check.fix_hint.expect("a fix hint");
        assert!(!hint.contains("<your email provider"), "{hint}");
        assert!(
            !hint.lines().any(|l| l.starts_with("TXT ")),
            "no finished-looking record when the sending host is unknown: {hint}"
        );
        assert!(hint.contains("ip4:") && hint.contains("mx"));
    }

    /// A fake resolver backed by a map of `(name, type)` -> answers; unknown names are NXDOMAIN.
    pub struct FakeResolver {
        pub txt: HashMap<String, Vec<String>>,
        pub mx: HashMap<String, Vec<String>>,
        pub fail_all: bool,
    }

    impl FakeResolver {
        pub fn new() -> Self {
            FakeResolver { txt: HashMap::new(), mx: HashMap::new(), fail_all: false }
        }
    }

    impl DnsResolver for FakeResolver {
        fn lookup(&self, name: &str, record_type: RecordType) -> DnsLookup {
            if self.fail_all {
                return DnsLookup::Failed("boom".to_string());
            }
            let (map, rtype) = match record_type {
                RecordType::Txt => (&self.txt, TYPE_TXT),
                RecordType::Mx => (&self.mx, super::super::dns::TYPE_MX),
            };
            match map.get(name) {
                Some(v) => DnsLookup::Found(
                    v.iter().map(|d| DnsAnswer { rtype, data: d.clone() }).collect(),
                ),
                None => DnsLookup::NotFound,
            }
        }
    }

    fn sending(domain: &str, by: &[&str]) -> SendingDomain {
        SendingDomain {
            domain: domain.to_string(),
            used_by: by.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn level_of(status: &EmailDomainStatus, check: &str) -> i32 {
        status.checks.iter().find(|c| c.name == check).unwrap().level
    }

    #[test]
    fn address_domain_extraction() {
        assert_eq!(domain_of_address("noreply@Example.COM"), Some("example.com".into()));
        assert_eq!(domain_of_address("My App <hi@mg.example.com>"), Some("mg.example.com".into()));
        assert_eq!(domain_of_address("no-at-sign"), None);
        assert_eq!(domain_of_address("a@localhost"), None);
        assert_eq!(domain_of_address(""), None);
    }

    #[test]
    fn fully_configured_domain_is_ok() {
        let mut r = FakeResolver::new();
        r.txt.insert("example.com".into(), vec!["v=spf1 include:sendgrid.net -all".into()]);
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=reject; rua=mailto:d@example.com".into()]);
        r.txt.insert("s1._domainkey.example.com".into(), vec!["v=DKIM1; k=rsa; p=abc".into()]);
        r.mx.insert("example.com".into(), vec!["10 mx.example.com.".into()]);
        let status = build_domain_status(&sending("example.com", &["sendgrid"]), &[], &r);
        assert_eq!(status.level, StatusLevel::Ok as i32, "{:?}", status.checks);
        assert!(status.dmarc.as_ref().unwrap().record_found);
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Ok as i32);
        assert!(status.summary.contains("are set up"));
        let dkim = status.checks.iter().find(|c| c.name == "DKIM").unwrap();
        assert!(dkim.detail.contains("s1._domainkey"));
        assert!(!dkim.detail.contains("s2._domainkey"));
    }

    #[test]
    fn missing_everything_warns_with_fix_hints() {
        let r = FakeResolver::new();
        let status = build_domain_status(&sending("example.com", &["mailgun"]), &[], &r);
        assert_eq!(status.level, StatusLevel::Warning as i32);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert_eq!(
            copy::record_lines(dmarc.fix_hint.as_ref().unwrap()),
            vec![("TXT", "_dmarc.example.com", "v=DMARC1; p=none; rua=mailto:postmaster@example.com")]
        );
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Warning as i32);
        assert_eq!(level_of(&status, "DKIM"), StatusLevel::Warning as i32);
        assert!(status.summary.contains("needs attention"));
        // Mailgun probes `smtp`, `k1`, `mailo`, `krs`.
        let dkim = status.checks.iter().find(|c| c.name == "DKIM").unwrap();
        assert!(dkim.detail.contains("k1._domainkey"));
    }

    #[test]
    fn dmarc_none_and_plus_all_spf() {
        let mut r = FakeResolver::new();
        r.txt.insert("example.com".into(), vec!["v=spf1 +all".into()]);
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=none".into()]);
        let status = build_domain_status(&sending("example.com", &["postmark"]), &[], &r);
        assert_eq!(status.level, StatusLevel::Error as i32);
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Error as i32);
        assert_eq!(level_of(&status, "DMARC"), StatusLevel::Warning as i32);
        // p=none with no rua= also gets the informational reports check.
        assert_eq!(level_of(&status, "DMARC reports"), StatusLevel::Info as i32);
    }

    #[test]
    fn subdomain_inherits_parent_dmarc() {
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=quarantine; rua=mailto:a@example.com".into()]);
        let status = build_domain_status(&sending("mg.example.com", &["mailgun"]), &[], &r);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert_eq!(dmarc.level, StatusLevel::Ok as i32);
        assert!(dmarc.detail.contains("Uses the record on example.com"), "{}", dmarc.detail);
    }

    #[test]
    fn provider_reported_dkim_ok_downgrades_missing_probe_to_info() {
        let r = FakeResolver::new();
        let report = DomainReport {
            domain: "example.com".into(),
            provider: "postmark".into(),
            checks: vec![make_check(StatusLevel::Ok, "Postmark: DKIM", "verified", None)],
            dkim_hosts: vec![],
        };
        let status = build_domain_status(&sending("example.com", &["stalwart"]), &[&report], &r);
        assert_eq!(level_of(&status, "DKIM"), StatusLevel::Info as i32);
        assert!(status.checks.iter().any(|c| c.name == "Postmark: DKIM"));
    }

    #[test]
    fn provider_dkim_hosts_are_probed() {
        let mut r = FakeResolver::new();
        r.txt.insert("20240101pm._domainkey.example.com".into(), vec!["k=rsa; p=zzz".into()]);
        let report = DomainReport {
            domain: "example.com".into(),
            provider: "postmark".into(),
            checks: vec![],
            dkim_hosts: vec!["20240101pm._domainkey.example.com".into()],
        };
        let status = build_domain_status(&sending("example.com", &["postmark"]), &[&report], &r);
        assert_eq!(level_of(&status, "DKIM"), StatusLevel::Ok as i32);
    }

    #[test]
    fn resolver_failure_is_unknown_not_an_error() {
        let mut r = FakeResolver::new();
        r.fail_all = true;
        let status = build_domain_status(&sending("example.com", &["sendgrid"]), &[], &r);
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Unknown as i32);
        assert_eq!(level_of(&status, "DKIM"), StatusLevel::Unknown as i32);
        assert_eq!(status.dmarc.as_ref().unwrap().level, StatusLevel::Unknown as i32);
        assert_ne!(status.level, StatusLevel::Error as i32);
    }

    #[test]
    fn dns_outage_never_reads_as_all_good() {
        let mut r = FakeResolver::new();
        r.fail_all = true;
        let status = build_domain_status(&sending("example.com", &["sendgrid"]), &[], &r);
        assert_eq!(status.level, StatusLevel::Unknown as i32);
        assert!(!status.summary.contains("are set up"), "{}", status.summary);
        assert!(status.summary.contains("couldn't fully check"), "{}", status.summary);
        assert!(status.summary.contains("SPF") && status.summary.contains("DMARC"), "{}", status.summary);
    }

    #[test]
    fn partial_dns_failure_with_a_warning_lists_both() {
        let checks = vec![
            make_check(StatusLevel::Warning, "DMARC", "x", None),
            make_check(StatusLevel::Unknown, "SPF", "y", None),
            make_check(StatusLevel::Ok, "DKIM", "z", None),
        ];
        let s = status_summary("example.com", &checks);
        assert!(s.contains("needs attention - DMARC"), "{s}");
        assert!(s.contains("couldn't check: SPF"), "{s}");
    }

    #[test]
    fn subdomain_inheriting_sp_none_is_monitor_only() {
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=reject; sp=none; rua=mailto:a@example.com".into()]);
        let status = build_domain_status(&sending("mail.example.com", &["mailgun"]), &[], &r);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert_eq!(dmarc.level, StatusLevel::Warning as i32);
        assert!(dmarc.detail.contains("Uses the record on example.com"), "{}", dmarc.detail);
        assert!(dmarc.detail.contains("sp=none"), "{}", dmarc.detail);
        let lines = copy::record_lines(dmarc.fix_hint.as_ref().unwrap());
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].1, "_dmarc.mail.example.com");
        assert!(lines[0].2.contains("p=quarantine"), "{lines:?}");
        assert_eq!(status.dmarc.as_ref().unwrap().level, StatusLevel::Warning as i32);
        // The apex domain itself is still judged by p=.
        let apex = build_domain_status(&sending("example.com", &["mailgun"]), &[], &r);
        assert_eq!(apex.checks.iter().find(|c| c.name == "DMARC").unwrap().level, StatusLevel::Ok as i32);
    }

    #[test]
    fn dmarc_lookup_skips_intermediate_parents_and_uses_the_organizational_domain() {
        // `_dmarc.b.example.com` is not on the receiver's lookup path for a.b.example.com.
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.b.example.com".into(), vec!["v=DMARC1; p=reject; rua=mailto:a@example.com".into()]);
        let status = build_domain_status(&sending("a.b.example.com", &["mailgun"]), &[], &r);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert_ne!(dmarc.level, StatusLevel::Ok as i32, "{}", dmarc.detail);
        assert!(!status.dmarc.as_ref().unwrap().record_found);

        // The organizational domain is used (here under a multi-label public suffix).
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.example.co.uk".into(), vec!["v=DMARC1; p=reject; rua=mailto:a@example.co.uk".into()]);
        let status = build_domain_status(&sending("a.b.example.co.uk", &["mailgun"]), &[], &r);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert!(dmarc.detail.contains("Uses the record on example.co.uk"), "{}", dmarc.detail);
        // ...and `co.uk` itself is never consulted.
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.co.uk".into(), vec!["v=DMARC1; p=reject".into()]);
        let status = build_domain_status(&sending("example.co.uk", &["mailgun"]), &[], &r);
        assert!(!status.dmarc.as_ref().unwrap().record_found);
    }

    #[test]
    fn dkim_records_without_a_usable_key_are_not_healthy() {
        let revoked = |txt: &str| {
            let mut r = FakeResolver::new();
            r.txt.insert("s1._domainkey.example.com".into(), vec![txt.into()]);
            let status = build_domain_status(&sending("example.com", &["sendgrid"]), &[], &r);
            status.checks.iter().find(|c| c.name == "DKIM").unwrap().clone()
        };
        let good = revoked("v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GN");
        assert_eq!(good.level, StatusLevel::Ok as i32, "{}", good.detail);
        for bad in ["v=DKIM1; k=rsa; p=", "v=DKIM1; p= ;", "just some text"] {
            let c = revoked(bad);
            assert_eq!(c.level, StatusLevel::Warning as i32, "{bad}: {}", c.detail);
            assert!(c.detail.contains("no usable key"), "{}", c.detail);
        }
    }

    #[test]
    fn missing_spf_hint_has_a_parseable_record_with_the_providers_include() {
        let r = FakeResolver::new();
        let status = build_domain_status(&sending("example.com", &["sendgrid", "mailgun"]), &[], &r);
        let spf = status.checks.iter().find(|c| c.name == "SPF").unwrap();
        assert_eq!(copy::record_lines(spf.fix_hint.as_ref().unwrap()), vec![("TXT", "example.com", "v=spf1 include:sendgrid.net include:mailgun.org ~all")]);
        assert!(spf.detail.contains(copy::SPF));
    }

    #[test]
    fn spf_plus_all_and_missing_all_hints_replace_the_whole_record() {
        let mut r = FakeResolver::new();
        r.txt.insert("example.com".into(), vec!["v=spf1 include:sendgrid.net +all".into()]);
        let status = build_domain_status(&sending("example.com", &[]), &[], &r);
        let spf = status.checks.iter().find(|c| c.name == "SPF").unwrap();
        assert_eq!(copy::record_lines(spf.fix_hint.as_ref().unwrap()), vec![("TXT", "example.com", "v=spf1 include:sendgrid.net ~all")]);

        let mut r = FakeResolver::new();
        r.txt.insert("example.com".into(), vec!["v=spf1 include:sendgrid.net".into()]);
        let status = build_domain_status(&sending("example.com", &[]), &[], &r);
        let spf = status.checks.iter().find(|c| c.name == "SPF").unwrap();
        assert_eq!(copy::record_lines(spf.fix_hint.as_ref().unwrap()), vec![("TXT", "example.com", "v=spf1 include:sendgrid.net ~all")]);
    }

    #[test]
    fn dmarc_none_hint_tightens_the_existing_record() {
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=none; rua=mailto:r@example.com".into()]);
        let status = build_domain_status(&sending("example.com", &[]), &[], &r);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert!(dmarc.detail.starts_with("Monitoring only"), "{}", dmarc.detail);
        assert_eq!(
            copy::record_lines(dmarc.fix_hint.as_ref().unwrap()),
            vec![("TXT", "_dmarc.example.com", "v=DMARC1; p=quarantine; rua=mailto:r@example.com")]
        );
    }

    #[test]
    fn dmarc_pct_and_missing_rua_hints_are_record_lines() {
        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=reject; pct=50; rua=mailto:r@example.com".into()]);
        let status = build_domain_status(&sending("example.com", &[]), &[], &r);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert_eq!(
            copy::record_lines(dmarc.fix_hint.as_ref().unwrap()),
            vec![("TXT", "_dmarc.example.com", "v=DMARC1; p=reject; pct=100; rua=mailto:r@example.com")]
        );

        let mut r = FakeResolver::new();
        r.txt.insert("_dmarc.example.com".into(), vec!["v=DMARC1; p=reject".into()]);
        let status = build_domain_status(&sending("example.com", &[]), &[], &r);
        let reports = status.checks.iter().find(|c| c.name == "DMARC reports").unwrap();
        assert_eq!(
            copy::record_lines(reports.fix_hint.as_ref().unwrap()),
            vec![("TXT", "_dmarc.example.com", "v=DMARC1; p=reject; rua=mailto:postmaster@example.com")]
        );
    }

    #[test]
    fn every_record_hint_is_prose_then_record_lines_only() {
        // Anything with record lines puts the sentence first and nothing but records after it.
        let r = FakeResolver::new();
        let status = build_domain_status(&sending("example.com", &["postmark"]), &[], &r);
        for c in &status.checks {
            if let Some(h) = &c.fix_hint {
                let lines: Vec<&str> = h.lines().collect();
                let first_record = lines.iter().position(|l| copy::parse_record_line(l).is_some());
                if let Some(i) = first_record {
                    assert!(i >= 1, "{h}");
                    assert!(lines[i..].iter().all(|l| copy::parse_record_line(l).is_some()), "{h}");
                }
            }
        }
    }

    #[test]
    fn spf_too_many_lookups_warns() {
        let mut r = FakeResolver::new();
        let includes: String = (0..11).map(|i| format!("include:s{i}.example.net ")).collect();
        r.txt.insert("example.com".into(), vec![format!("v=spf1 {includes}-all")]);
        let status = build_domain_status(&sending("example.com", &[]), &[], &r);
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Warning as i32);
    }
}
