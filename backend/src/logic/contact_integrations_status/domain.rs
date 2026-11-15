//! Per-sending-domain email authentication report: live SPF / DKIM / DMARC / MX lookups (through a
//! [`DnsResolver`]) merged with whatever each provider's API reported about the domain.

use std::collections::BTreeSet;

use crate::protos::{DmarcStatus, EmailDomainStatus, StatusCheck, StatusLevel};

use super::dns::{
    parse_dmarc, parse_spf, suggested_dmarc_record, DnsLookup, DnsResolver, RecordType,
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

/// Looks up the DMARC record for `domain`, falling back to parent domains the way receivers do
/// when a subdomain has none of its own (RFC 7489 §6.6.3). Returns the status plus the name the
/// record was found at (`None` if there is none / the lookup failed).
fn lookup_dmarc(resolver: &dyn DnsResolver, domain: &str) -> (DmarcStatus, Option<String>) {
    let labels: Vec<&str> = domain.split('.').collect();
    let mut failure: Option<String> = None;
    for start in 0..labels.len().saturating_sub(1) {
        let candidate = labels[start..].join(".");
        match resolver.lookup(&format!("_dmarc.{candidate}"), RecordType::Txt) {
            lookup @ DnsLookup::Found(_) => {
                let status = parse_dmarc(&lookup.txt_records());
                if status.record_found {
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

fn spf_check(domain: &str, lookup: &DnsLookup) -> StatusCheck {
    let name = "SPF";
    if let Some(message) = lookup.failed() {
        return make_check(StatusLevel::Unknown, name, format!("Couldn't look up TXT records ({message})."), None);
    }
    let spf = parse_spf(&lookup.txt_records());
    if !spf.found {
        return make_check(
            StatusLevel::Warning,
            name,
            format!("No SPF record (a TXT record starting with v=spf1) at {domain}."),
            Some(&format!(
                "Publish a TXT record at {domain} that authorizes your email provider, e.g. `v=spf1 include:<your provider's SPF host> ~all`. Your provider's domain-authentication page shows the exact value."
            )),
        );
    }
    if spf.multiple {
        return make_check(
            StatusLevel::Error,
            name,
            "More than one SPF record is published; receivers treat that as a permanent error.",
            Some("Merge them into a single TXT record starting with v=spf1."),
        );
    }
    let mut level = StatusLevel::Ok;
    let mut detail = match (spf.all, &spf.redirect) {
        (Some('+'), _) => {
            level = StatusLevel::Error;
            "SPF ends with +all, which lets anyone send mail as this domain.".to_string()
        }
        (Some('?'), _) => {
            level = StatusLevel::Warning;
            "SPF ends with ?all (neutral), which gives receivers no guidance on unlisted senders.".to_string()
        }
        (Some('-'), _) => "SPF is published and rejects unlisted senders (-all).".to_string(),
        (Some('~'), _) => "SPF is published and soft-fails unlisted senders (~all).".to_string(),
        (_, Some(target)) => format!("SPF is delegated to {target} (redirect=)."),
        (_, None) => {
            level = StatusLevel::Warning;
            "SPF has no all mechanism, so unlisted senders are neither accepted nor rejected.".to_string()
        }
    };
    let mut fix: Option<String> = match level {
        StatusLevel::Error => Some("Change +all to ~all (or -all) once all your senders are listed.".to_string()),
        StatusLevel::Warning => Some("End the record with ~all (or -all).".to_string()),
        _ => None,
    };
    if spf.lookups > 10 {
        level = StatusLevel::Warning;
        detail.push_str(&format!(
            " The record already costs {} DNS lookups; SPF allows at most 10, so some receivers will fail it.",
            spf.lookups
        ));
        fix = Some("Remove unused include:/a/mx terms (or flatten the record) to get to 10 lookups or fewer.".to_string());
    }
    make_check(level, name, detail, fix.as_deref())
}

fn mx_check(lookup: &DnsLookup) -> StatusCheck {
    let name = "MX";
    match lookup {
        DnsLookup::Failed(message) => {
            make_check(StatusLevel::Unknown, name, format!("Couldn't look up MX records ({message})."), None)
        }
        DnsLookup::NotFound => make_check(
            StatusLevel::Info,
            name,
            "No MX records: this domain can't receive replies or bounces (fine for send-only domains).",
            None,
        ),
        DnsLookup::Found(answers) => {
            let hosts: Vec<String> = answers
                .iter()
                .filter(|a| a.rtype == super::dns::TYPE_MX)
                .map(|a| a.data.clone())
                .collect();
            make_check(StatusLevel::Info, name, format!("{} MX record(s): {}", hosts.len(), hosts.join(", ")), None)
        }
    }
}

fn dmarc_check(domain: &str, dmarc: &DmarcStatus, found_at: &Option<String>) -> StatusCheck {
    let name = "DMARC";
    let level = StatusLevel::try_from(dmarc.level).unwrap_or(StatusLevel::Unknown);
    let mut detail = dmarc.summary.clone();
    if let Some(parent) = found_at {
        if parent != domain {
            detail = format!("Inherited from {parent}: {detail}");
        }
    }
    let suggestion = suggested_dmarc_record(domain);
    let fix = if !dmarc.record_found && level == StatusLevel::Warning {
        Some(format!(
            "Publish a TXT record at _dmarc.{domain} with the value `{suggestion}` (use a mailbox you read for rua=), then tighten p= to quarantine/reject once reports look clean."
        ))
    } else if dmarc.record_found && dmarc.policy == "none" {
        Some("Once the reports show only legitimate mail passing, change p=none to p=quarantine, then p=reject.".to_string())
    } else if dmarc.record_found && dmarc.percentage < 100 && level == StatusLevel::Warning {
        Some("Raise pct to 100 (or remove it) once you're confident in the policy.".to_string())
    } else if dmarc.record_found && level == StatusLevel::Error {
        Some(format!("Keep exactly one TXT record at _dmarc.{domain}."))
    } else {
        None
    };
    make_check(level, name, detail, fix.as_deref())
}

fn reports_check(dmarc: &DmarcStatus) -> Option<StatusCheck> {
    if dmarc.record_found && dmarc.aggregate_report_uris.is_empty() {
        Some(make_check(
            StatusLevel::Info,
            "DMARC reports",
            "The DMARC record has no rua= address, so you won't receive aggregate reports.",
            Some("Add `rua=mailto:<a mailbox you read>` to the DMARC record to see who is sending as your domain."),
        ))
    } else {
        None
    }
}

fn dkim_check(
    domain: &str,
    probes: &[(String, DnsLookup)],
    provider_reported_dkim_ok: bool,
) -> StatusCheck {
    let name = "DKIM keys in DNS";
    let found: Vec<&str> = probes
        .iter()
        .filter(|(_, l)| l.has_txt_or_cname())
        .map(|(n, _)| n.as_str())
        .collect();
    let probed: Vec<&str> = probes.iter().map(|(n, _)| n.as_str()).collect();
    if !found.is_empty() {
        return make_check(
            StatusLevel::Ok,
            name,
            format!("Found DKIM record(s) at {}.", found.join(", ")),
            None,
        );
    }
    if !probes.is_empty() && probes.iter().all(|(_, l)| l.failed().is_some()) {
        return make_check(StatusLevel::Unknown, name, "Couldn't look up DKIM records (DNS resolver failed).", None);
    }
    if probes.is_empty() {
        return make_check(
            StatusLevel::Unknown,
            name,
            "No DKIM selectors are known for the providers using this domain.",
            None,
        );
    }
    if provider_reported_dkim_ok {
        make_check(
            StatusLevel::Info,
            name,
            format!(
                "Your provider reports DKIM as verified, but none of the probed names resolved ({}); it may use a custom selector.",
                probed.join(", ")
            ),
            None,
        )
    } else {
        make_check(
            StatusLevel::Warning,
            name,
            format!("No DKIM record found at the usual names for {domain} ({}).", probed.join(", ")),
            Some("Publish the DKIM records shown on your email provider's domain-authentication page."),
        )
    }
}

fn status_summary(domain: &str, checks: &[StatusCheck]) -> String {
    let mut bad: Vec<&str> = checks
        .iter()
        .filter(|c| c.level == StatusLevel::Error as i32 || c.level == StatusLevel::Warning as i32)
        .map(|c| c.name.as_str())
        .collect();
    bad.dedup();
    if bad.is_empty() {
        format!("{domain}: SPF, DKIM and DMARC are in place")
    } else {
        format!("{domain}: needs attention - {}", bad.join(", "))
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
        spf_check(domain, &spf_lookup),
        dkim_check(domain, &probes, provider_dkim_ok),
        dmarc_check(domain, &dmarc, &dmarc_at),
    ];
    if let Some(c) = reports_check(&dmarc) {
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
        assert!(status.summary.contains("in place"));
        let dkim = status.checks.iter().find(|c| c.name == "DKIM keys in DNS").unwrap();
        assert!(dkim.detail.contains("s1._domainkey.example.com"));
        assert!(!dkim.detail.contains("s2._domainkey"));
    }

    #[test]
    fn missing_everything_warns_with_fix_hints() {
        let r = FakeResolver::new();
        let status = build_domain_status(&sending("example.com", &["mailgun"]), &[], &r);
        assert_eq!(status.level, StatusLevel::Warning as i32);
        let dmarc = status.checks.iter().find(|c| c.name == "DMARC").unwrap();
        assert!(dmarc.fix_hint.as_ref().unwrap().contains("_dmarc.example.com"));
        assert!(dmarc.fix_hint.as_ref().unwrap().contains("v=DMARC1; p=none"));
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Warning as i32);
        assert_eq!(level_of(&status, "DKIM keys in DNS"), StatusLevel::Warning as i32);
        assert!(status.summary.contains("needs attention"));
        // Mailgun probes `smtp`, `k1`, `mailo`, `krs`.
        let dkim = status.checks.iter().find(|c| c.name == "DKIM keys in DNS").unwrap();
        assert!(dkim.detail.contains("k1._domainkey.example.com"));
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
        assert!(dmarc.detail.contains("Inherited from example.com"));
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
        assert_eq!(level_of(&status, "DKIM keys in DNS"), StatusLevel::Info as i32);
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
        assert_eq!(level_of(&status, "DKIM keys in DNS"), StatusLevel::Ok as i32);
    }

    #[test]
    fn resolver_failure_is_unknown_not_an_error() {
        let mut r = FakeResolver::new();
        r.fail_all = true;
        let status = build_domain_status(&sending("example.com", &["sendgrid"]), &[], &r);
        assert_eq!(level_of(&status, "SPF"), StatusLevel::Unknown as i32);
        assert_eq!(level_of(&status, "DKIM keys in DNS"), StatusLevel::Unknown as i32);
        assert_eq!(status.dmarc.as_ref().unwrap().level, StatusLevel::Unknown as i32);
        assert_ne!(status.level, StatusLevel::Error as i32);
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
