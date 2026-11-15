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
            self.info(name, "No messages sent in the last 30 days.");
            return;
        }
        if sent < 20 {
            self.ok(name, format!("{sent} message(s) sent in the last 30 days; too few to judge bounce rates."));
            return;
        }
        let fix = "Remove invalid addresses, send only to people who asked for the email, and check your suppression list.";
        if bounce_pct > 10.0 || spam_pct > 0.3 {
            self.error(name, format!("Bounce rate {bounce_pct:.2}%, spam complaint rate {spam_pct:.2}% (last 30 days)."), fix);
        } else if bounce_pct > 5.0 || spam_pct > 0.1 {
            self.warn(name, format!("Bounce rate {bounce_pct:.2}%, spam complaint rate {spam_pct:.2}% (last 30 days)."), fix);
        } else {
            self.ok(name, format!("Bounce rate {bounce_pct:.2}%, spam complaint rate {spam_pct:.2}% over {sent} messages."));
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

/// The worst of `levels`: ERROR > WARNING > OK > INFO > UNKNOWN. `DISABLED` entries are ignored.
/// (An `UNKNOWN` check -- "couldn't tell" -- never drags a provider whose other checks passed down
/// to `UNKNOWN`; an empty list is `UNKNOWN`.)
pub fn worst_level(levels: impl IntoIterator<Item = i32>) -> StatusLevel {
    let mut error = false;
    let mut warning = false;
    let mut ok = false;
    let mut info = false;
    for level in levels {
        match StatusLevel::try_from(level).unwrap_or(StatusLevel::Unknown) {
            StatusLevel::Error => error = true,
            StatusLevel::Warning => warning = true,
            StatusLevel::Ok => ok = true,
            StatusLevel::Info => info = true,
            StatusLevel::Unknown | StatusLevel::Disabled => {}
        }
    }
    if error {
        StatusLevel::Error
    } else if warning {
        StatusLevel::Warning
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

/// The one-line headline for an enabled, configured provider.
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
    let any_verdict = report
        .checks
        .iter()
        .any(|c| c.level == StatusLevel::Ok as i32 || c.level == StatusLevel::Warning as i32);
    if !errors.is_empty() {
        let first = &errors[0].name;
        if errors.len() == 1 {
            format!("Not ready to send - {first} needs fixing")
        } else {
            format!(
                "Not ready to send - {} to fix, starting with {first}",
                plural(errors.len(), "problem", "problems")
            )
        }
    } else if warnings > 0 {
        format!(
            "Ready to send - {} attention",
            plural(warnings, "thing needs", "things need")
        )
    } else if any_verdict {
        "Ready to send".to_string()
    } else {
        format!("Couldn't verify {display_name} right now")
    }
}
