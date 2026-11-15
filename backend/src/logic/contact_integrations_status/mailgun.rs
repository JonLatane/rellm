//! Live status of the Mailgun email integration (HTTP Basic `api:{key}`; `api.eu.mailgun.net` when
//! `mailgun_region` is `eu`).
//!
//! Endpoints (documentation.mailgun.com): `GET /v4/domains/{name}` (`domain.state`
//! active|unverified|disabled, `domain.type` custom|sandbox, `sending_dns_records[]` with
//! `record_type`, `name`, `valid`) and the (deprecated but still served) `GET /v3/{domain}/stats/total`
//! with repeated `event=` and `duration=30d` (`stats[]`: `accepted.total`, `delivered.total`,
//! `failed.temporary.total`, `failed.permanent.total`). If Mailgun removes the stats endpoint the
//! check degrades to simply not showing statistics.

use serde_json::Value;

use crate::protos::{MailgunConfig, StatusLevel};

use super::http::{encode_segment, get_json, i64_of, str_of, Auth, Ctx, Fail};
use super::report::{make_check, DomainReport, ProviderReport};

pub fn api_host(region: &str) -> &'static str {
    if region.trim().eq_ignore_ascii_case("eu") {
        "https://api.eu.mailgun.net"
    } else {
        "https://api.mailgun.net"
    }
}

pub fn dashboard_url(region: &str) -> &'static str {
    if region.trim().eq_ignore_ascii_case("eu") {
        "https://app.eu.mailgun.com/"
    } else {
        "https://app.mailgun.com/"
    }
}

/// A `sending_dns_records` entry counts as valid if `valid == "valid"` (or `is_active == true`).
fn record_valid(record: &Value) -> bool {
    str_of(record, "valid").eq_ignore_ascii_case("valid")
        || record.get("is_active").and_then(Value::as_bool) == Some(true)
}

pub fn check(config: &MailgunConfig, ctx: &Ctx) -> ProviderReport {
    let mut report = ProviderReport::default();
    let auth = Auth::Basic("api", &config.mailgun_api_key);
    let api = ctx.host(api_host(&config.mailgun_region));
    let domain = config.mailgun_domain.trim().to_ascii_lowercase();
    let mut dr = DomainReport { domain: domain.clone(), provider: "mailgun".to_string(), ..Default::default() };

    match get_json(ctx, &format!("{api}/v4/domains/{}", encode_segment(&domain)), auth, &[], &[]) {
        Err(Fail::Unauthorized) => {
            report.error(
                "API credentials",
                "Mailgun rejected the API key (HTTP 401).",
                "Copy a Private API key (or a domain sending key) from Mailgun, and check the region (US/EU).",
            );
            report.headline = Some("Credentials rejected by Mailgun".to_string());
            return report;
        }
        Err(Fail::Unreachable(e)) => {
            report.unknown("API credentials", format!("Couldn't reach Mailgun ({e})."));
            report.headline = Some("Couldn't reach Mailgun".to_string());
            return report;
        }
        Err(Fail::NotFound) => {
            report.ok("API credentials", "Mailgun accepted the API key.");
            report.error(
                "Sending domain",
                format!("Mailgun has no domain called {domain}."),
                "Add the domain in Mailgun, correct the domain here, or switch the region (US vs EU) if the domain lives in the other one.",
            );
            return report;
        }
        Err(e) if e.is_access_denied() => {
            report.ok("API credentials", "Mailgun accepted the API key.");
            report.info("Sending domain", "This key (e.g. a domain sending key) can't read domain details, so DNS verification isn't shown.");
        }
        Err(other) => {
            report.unknown("API credentials", format!("Unexpected response from Mailgun: {}", other.describe()));
            return report;
        }
        Ok(body) => {
            report.ok("API credentials", "Mailgun accepted the API key.");
            let info = body.get("domain").unwrap_or(&Value::Null);
            let state = str_of(info, "state");
            match state {
                "active" => report.ok("Sending domain", format!("{domain} is active.")),
                "unverified" => report.error(
                    "Sending domain",
                    format!("{domain} is not verified yet."),
                    "Publish the DNS records shown for the domain in Mailgun, then click Verify DNS Settings.",
                ),
                "disabled" => report.error("Sending domain", format!("{domain} is disabled."), "Re-enable the domain in Mailgun or contact Mailgun support."),
                "" => report.unknown("Sending domain", "Mailgun didn't report a domain state."),
                other => report.warn("Sending domain", format!("{domain} has state \"{other}\"."), "Check the domain in the Mailgun dashboard."),
            }
            if str_of(info, "type") == "sandbox" {
                report.warn(
                    "Sandbox domain",
                    "This is a Mailgun sandbox domain: it can only send to authorized recipients.",
                    "Add and verify your own domain in Mailgun.",
                );
            }
            for record in body.get("sending_dns_records").and_then(Value::as_array).into_iter().flatten() {
                let rtype = str_of(record, "record_type");
                let name = str_of(record, "name").trim_end_matches('.').to_ascii_lowercase();
                let value = str_of(record, "value");
                let valid = record_valid(record);
                let (label, critical) = if name.contains("._domainkey") {
                    dr.dkim_hosts.push(name.clone());
                    ("Mailgun: DKIM", true)
                } else if rtype == "TXT" && value.to_ascii_lowercase().starts_with("v=spf1") {
                    ("Mailgun: SPF", true)
                } else {
                    ("Mailgun: tracking CNAME", false)
                };
                dr.checks.push(if valid {
                    make_check(StatusLevel::Ok, label, format!("{rtype} record {name} is verified."), None)
                } else if critical {
                    make_check(
                        StatusLevel::Error,
                        label,
                        format!("Mailgun hasn't verified the {rtype} record at {name}."),
                        Some("Publish the record exactly as shown in Mailgun, then click Verify DNS Settings."),
                    )
                } else {
                    make_check(
                        StatusLevel::Info,
                        label,
                        format!("The optional {rtype} record at {name} isn't verified (only needed for open/click tracking)."),
                        None,
                    )
                });
            }
            if dr.checks.iter().any(|c| c.level == StatusLevel::Error as i32) {
                report.error(
                    "Domain DNS records",
                    "Some of the domain's required DNS records aren't verified.",
                    "See the DNS section of this domain's status below, then re-verify in Mailgun.",
                );
            } else if !dr.checks.is_empty() {
                report.ok("Domain DNS records", "Mailgun reports the domain's SPF/DKIM records as verified.");
            }
        }
    }

    // Stats.
    let query = [
        ("event", "accepted".to_string()),
        ("event", "delivered".to_string()),
        ("event", "failed".to_string()),
        ("duration", "30d".to_string()),
    ];
    match get_json(ctx, &format!("{api}/v3/{}/stats/total", encode_segment(&domain)), auth, &[], &query) {
        Ok(body) => {
            let (mut accepted, mut delivered, mut permanent, mut temporary) = (0, 0, 0, 0);
            for entry in body.get("stats").and_then(Value::as_array).into_iter().flatten() {
                accepted += i64_of(entry.pointer("/accepted/total").unwrap_or(&Value::Null));
                delivered += i64_of(entry.pointer("/delivered/total").unwrap_or(&Value::Null));
                permanent += i64_of(entry.pointer("/failed/permanent/total").unwrap_or(&Value::Null));
                temporary += i64_of(entry.pointer("/failed/temporary/total").unwrap_or(&Value::Null));
            }
            report.metric("Accepted", accepted.to_string(), Some("last 30 days"));
            report.metric("Delivered", delivered.to_string(), Some("last 30 days"));
            report.metric("Failed (permanent)", permanent.to_string(), Some("last 30 days"));
            report.metric("Failed (temporary)", temporary.to_string(), Some("last 30 days"));
            let bounce_pct = if accepted > 0 { permanent as f64 * 100.0 / accepted as f64 } else { 0.0 };
            report.check_rates("Recent delivery", accepted, bounce_pct, 0.0);
        }
        Err(e) if e.is_access_denied() => {
            report.info("Recent delivery", "This key can't read statistics.");
        }
        Err(_) => {}
    }
    report.domains.push(dr);
    report
}
