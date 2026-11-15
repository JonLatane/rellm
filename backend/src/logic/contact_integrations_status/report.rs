//! Builders and level/summary logic shared by every provider check.

use crate::protos::{StatusCheck, StatusLevel, StatusMetric};

/// A provider-reported fact about one sending domain (e.g. "Postmark: DKIM verified"), merged into
/// that domain's `EmailDomainStatus` by `domain::build_domain_statuses`.
#[derive(Clone, Debug, Default)]
pub struct DomainReport {
    pub domain: String,
    /// Provider id (`postmark`, ...).
    pub provider: String,
    pub checks: Vec<StatusCheck>,
    /// Full DNS names (e.g. `s1._domainkey.example.com`) the provider says carry its DKIM keys.
    pub dkim_hosts: Vec<String>,
}

/// Everything one provider's live check learned.
#[derive(Clone, Debug, Default)]
pub struct ProviderReport {
    pub checks: Vec<StatusCheck>,
    pub metrics: Vec<StatusMetric>,
    pub domains: Vec<DomainReport>,
    /// If set, replaces the generated one-line summary (e.g. "Credentials rejected by Twilio").
    pub headline: Option<String>,
}

impl ProviderReport {
    pub fn check(
        &mut self,
        level: StatusLevel,
        name: &str,
        detail: impl Into<String>,
        fix_hint: Option<&str>,
    ) {
        self.checks.push(make_check(level, name, detail, fix_hint));
    }

    pub fn ok(&mut self, name: &str, detail: impl Into<String>) {
        self.check(StatusLevel::Ok, name, detail, None);
    }

    pub fn info(&mut self, name: &str, detail: impl Into<String>) {
        self.check(StatusLevel::Info, name, detail, None);
    }

    pub fn warn(&mut self, name: &str, detail: impl Into<String>, fix: &str) {
        self.check(StatusLevel::Warning, name, detail, Some(fix));
    }

    pub fn error(&mut self, name: &str, detail: impl Into<String>, fix: &str) {
        self.check(StatusLevel::Error, name, detail, Some(fix));
    }

    pub fn unknown(&mut self, name: &str, detail: impl Into<String>) {
        self.check(StatusLevel::Unknown, name, detail, None);
    }

    pub fn metric(&mut self, label: &str, value: impl Into<String>, detail: Option<&str>) {
        self.metrics.push(StatusMetric {
            label: label.to_string(),
            value: value.into(),
            detail: detail.map(|d| d.to_string()),
        });
    }

    pub fn has_level(&self, level: StatusLevel) -> bool {
        self.checks.iter().any(|c| c.level == level as i32)
    }
}

impl ProviderReport {
    /// Shared bounce/complaint-rate verdict (percentages): bounce >5% warns, >10% errors; spam
    /// complaints >0.1% warn, >0.3% error. Needs at least 20 messages to mean anything.
    pub fn check_rates(&mut self, name: &str, sent: i64, bounce_pct: f64, spam_pct: f64) {
        if sent == 0 {
            self.info(name, "Nothing sent in the last 30 days.");
            return;
        }
        if sent < 20 {
            self.ok(name, format!("Only {sent} sent in the last 30 days, too few to judge bounce rates."));
            return;
        }
        let fix = "Remove addresses that no longer work and only email people who asked for it.";
        if bounce_pct > 10.0 || spam_pct > 0.3 {
            self.error(name, format!("{bounce_pct:.1}% of email bounced and {spam_pct:.2}% was reported as spam (last 30 days)."), fix);
        } else if bounce_pct > 5.0 || spam_pct > 0.1 {
            self.warn(name, format!("{bounce_pct:.1}% of email bounced and {spam_pct:.2}% was reported as spam (last 30 days)."), fix);
        } else {
            self.ok(name, format!("Healthy: {bounce_pct:.1}% bounced and {spam_pct:.2}% reported as spam over {sent} emails."));
        }
    }
}

pub fn make_check(
    level: StatusLevel,
    name: &str,
    detail: impl Into<String>,
    fix_hint: Option<&str>,
) -> StatusCheck {
    StatusCheck {
        name: name.to_string(),
        level: level as i32,
        detail: detail.into(),
        fix_hint: fix_hint.map(|h| h.to_string()),
    }
}

/// The worst of `levels`: ERROR > WARNING > UNKNOWN > OK > INFO. `DISABLED` entries are ignored.
/// An `UNKNOWN` check ("couldn't tell") outranks `OK`, so a provider or domain is never rolled up
/// to "fine" while part of it couldn't be verified; an empty list is `UNKNOWN`.
pub fn worst_level(levels: impl IntoIterator<Item = i32>) -> StatusLevel {
    let mut error = false;
    let mut warning = false;
    let mut unknown = false;
    let mut ok = false;
    let mut info = false;
    for level in levels {
        match StatusLevel::try_from(level).unwrap_or(StatusLevel::Unknown) {
            StatusLevel::Error => error = true,
            StatusLevel::Warning => warning = true,
            StatusLevel::Unknown => unknown = true,
            StatusLevel::Ok => ok = true,
            StatusLevel::Info => info = true,
            StatusLevel::Disabled => {}
        }
    }
    if error {
        StatusLevel::Error
    } else if warning {
        StatusLevel::Warning
    } else if unknown {
        StatusLevel::Unknown
    } else if ok {
        StatusLevel::Ok
    } else if info {
        StatusLevel::Info
    } else {
        StatusLevel::Unknown
    }
}

fn plural(n: usize, singular: &str, plural: &str) -> String {
    if n == 1 {
        format!("1 {singular}")
    } else {
        format!("{n} {plural}")
    }
}

/// The one-line headline for an enabled, configured provider. Never claims "Ready to send" while
/// any check couldn't be completed.
pub fn summarize(display_name: &str, report: &ProviderReport) -> String {
    if let Some(headline) = &report.headline {
        return headline.clone();
    }
    let errors: Vec<&StatusCheck> = report
        .checks
        .iter()
        .filter(|c| c.level == StatusLevel::Error as i32)
        .collect();
    let warnings = report
        .checks
        .iter()
        .filter(|c| c.level == StatusLevel::Warning as i32)
        .count();
    let unknown: Vec<&str> = report
        .checks
        .iter()
        .filter(|c| c.level == StatusLevel::Unknown as i32)
        .map(|c| c.name.as_str())
        .collect();
    let any_ok = report.checks.iter().any(|c| c.level == StatusLevel::Ok as i32);
    let unverified = if unknown.is_empty() {
        String::new()
    } else {
        format!("; couldn't verify: {}", unknown.join(", "))
    };
    if !errors.is_empty() {
        let first = &errors[0].name;
        if errors.len() == 1 {
            format!("Not ready to send - {first} needs fixing{unverified}")
        } else {
            format!(
                "Not ready to send - {} to fix, starting with {first}{unverified}",
                plural(errors.len(), "problem", "problems")
            )
        }
    } else if warnings > 0 {
        format!(
            "Ready to send - {} attention{unverified}",
            plural(warnings, "thing needs", "things need")
        )
    } else if !unknown.is_empty() {
        if any_ok {
            format!("Partly verified - couldn't verify: {}", unknown.join(", "))
        } else {
            format!("Couldn't verify {display_name} right now")
        }
    } else if any_ok {
        "Ready to send".to_string()
    } else {
        format!("Couldn't verify {display_name} right now")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(levels: &[(StatusLevel, &str)]) -> ProviderReport {
        let mut r = ProviderReport::default();
        for (l, n) in levels {
            r.check(*l, n, "d", None);
        }
        r
    }

    #[test]
    fn unknown_outranks_ok_in_rollup() {
        assert_eq!(worst_level([StatusLevel::Ok as i32, StatusLevel::Unknown as i32]), StatusLevel::Unknown);
        assert_eq!(worst_level([StatusLevel::Warning as i32, StatusLevel::Unknown as i32]), StatusLevel::Warning);
        assert_eq!(worst_level([StatusLevel::Ok as i32, StatusLevel::Info as i32]), StatusLevel::Ok);
        assert_eq!(worst_level([]), StatusLevel::Unknown);
    }

    #[test]
    fn ready_to_send_requires_nothing_unverified() {
        assert_eq!(summarize("X", &report(&[(StatusLevel::Ok, "a"), (StatusLevel::Info, "b")])), "Ready to send");
        let partly = summarize("X", &report(&[(StatusLevel::Ok, "API credentials"), (StatusLevel::Unknown, "Sender number")]));
        assert!(!partly.starts_with("Ready"), "{partly}");
        assert!(partly.contains("Sender number"));
        let none = summarize("X", &report(&[(StatusLevel::Unknown, "API credentials")]));
        assert_eq!(none, "Couldn't verify X right now");
        let warn = summarize("X", &report(&[(StatusLevel::Warning, "a"), (StatusLevel::Unknown, "b")]));
        assert!(warn.starts_with("Ready to send - 1 thing needs attention"), "{warn}");
        assert!(warn.contains("couldn't verify: b"));
    }
}
