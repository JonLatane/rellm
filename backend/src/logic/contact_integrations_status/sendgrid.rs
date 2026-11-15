//! Live status of the SendGrid email integration (Bearer API key; `api.eu.sendgrid.com` when
//! `sendgrid_region` is `eu`).
//!
//! Endpoints: `GET /v3/scopes` (`scopes[]`, needs no scope: the key-validity + permission check);
//! `GET /v3/user/account` (`type`, `reputation`); `GET /v3/whitelabel/domains` (array of domain
//! authentications: `domain`, `subdomain`, `valid`, `dns.{mail_cname,dkim1,dkim2}.{valid,host,type,data}`);
//! `GET /v3/verified_senders` (`results[]`: `from_email`, `verified`, `locked`);
//! `GET /v3/stats?start_date=&end_date=` (array of `{date, stats:[{metrics:{requests, delivered,
//! bounces, blocks, spam_reports, ...}}]}`). A 401/403 on an optional endpoint means the key lacks
//! that scope and is reported as INFO, not ERROR.

use serde_json::Value;

use crate::protos::{SendgridConfig, StatusLevel};

use super::copy;
use super::domain::domain_of_address;
use super::http::{f64_of, get_json, i64_of, str_of, Auth, Ctx, Fail};
use super::report::{make_check, DomainReport, ProviderReport};

pub const DASHBOARD_URL: &str = "https://app.sendgrid.com/";

pub fn api_host(region: &str) -> &'static str {
    if region.trim().eq_ignore_ascii_case("eu") {
        "https://api.eu.sendgrid.com"
    } else {
        "https://api.sendgrid.com"
    }
}

pub fn check(config: &SendgridConfig, ctx: &Ctx) -> ProviderReport {
    let mut report = ProviderReport::default();
    let auth = Auth::Bearer(&config.sendgrid_api_key);
    let api = ctx.host(api_host(&config.sendgrid_region));

    // 1. Scopes -- credentials + permissions.
    match get_json(ctx, &format!("{api}/v3/scopes"), auth, &[], &[]) {
        Ok(body) => {
            let scopes: Vec<String> = body
                .get("scopes")
                .and_then(Value::as_array)
                .map(|a| a.iter().filter_map(Value::as_str).map(str::to_string).collect())
                .unwrap_or_default();
            if scopes.is_empty() || scopes.iter().any(|s| s == "mail.send") {
                report.ok("API credentials", "SendGrid accepted the API key.");
            } else {
                report.error(
                    "API credentials",
                    "The API key works but isn't allowed to send email.",
                    "In SendGrid, create an API key with Mail Send permission (Settings > API Keys) and paste it here.",
                );
            }
        }
        Err(Fail::Unauthorized) => {
            report.error(
                "API credentials",
                "SendGrid didn't accept the API key.",
                "In SendGrid, create an API key with Mail Send permission (Settings > API Keys) and paste it here.",
            );
            report.headline = Some("Credentials rejected by SendGrid".to_string());
            return report;
        }
        Err(Fail::Unreachable(e)) => {
            report.unknown("API credentials", format!("Couldn't reach SendGrid ({e})."));
            report.headline = Some("Couldn't reach SendGrid".to_string());
            return report;
        }
        Err(Fail::Forbidden(_)) => report.ok("API credentials", "SendGrid accepted the API key."),
        Err(other) => {
            report.unknown("API credentials", format!("Unexpected response from SendGrid: {}", other.describe()));
            return report;
        }
    }

    // 2. Account / reputation.
    match get_json(ctx, &format!("{api}/v3/user/account"), auth, &[], &[]) {
        Ok(body) => {
            let kind = str_of(&body, "type");
            if !kind.is_empty() {
                report.metric("Plan type", kind, None);
            }
            if let Some(rep) = f64_of(body.get("reputation").unwrap_or(&Value::Null)) {
                report.metric("Sender reputation", format!("{rep:.1}"), None);
                if rep < 90.0 {
                    report.warn(
                        "Sender reputation",
                        format!("Your sender reputation is {rep:.1}, which is lowish."),
                        "Check bounces and spam reports in SendGrid and remove addresses that no longer work.",
                    );
                }
            }
        }
        Err(e) if e.is_access_denied() => {
            report.info("Account", "This API key can't read account details, so the plan and reputation aren't shown.");
        }
        Err(_) => {}
    }

    // 3. Domain authentication, then single-sender verification.
    let from = config.sendgrid_from_address.trim();
    let Some(domain) = domain_of_address(from) else {
        report.error("Sending domain", format!("\"{from}\" isn't a valid From address."), "Enter an address like noreply@example.com.");
        stats(ctx, &api, auth, &mut report);
        return report;
    };
    let mut dr = DomainReport { domain: domain.clone(), provider: "sendgrid".to_string(), ..Default::default() };
    let mut domain_ok = false;
    let mut domains_readable = true;
    match get_json(ctx, &format!("{api}/v3/whitelabel/domains"), auth, &[], &[("limit", "200".to_string())]) {
        Ok(body) => {
            let list = body.as_array().cloned().unwrap_or_default();
            let matched = list.iter().find(|d| {
                let name = str_of(d, "domain").to_ascii_lowercase();
                !name.is_empty() && (domain == name || domain.ends_with(&format!(".{name}")))
            });
            if let Some(entry) = matched {
                let auth_domain = str_of(entry, "domain").to_ascii_lowercase();
                let mut invalid: Vec<&str> = vec![];
                let mut records: Vec<String> = vec![];
                for record in ["dkim1", "dkim2", "mail_cname"] {
                    let r = entry.pointer(&format!("/dns/{record}"));
                    if let Some(r) = r {
                        let host = str_of(r, "host");
                        if record.starts_with("dkim") && !host.is_empty() {
                            dr.dkim_hosts.push(host.to_string());
                        }
                        if r.get("valid").and_then(Value::as_bool) == Some(false) {
                            invalid.push(record);
                            let (kind, data) = (str_of(r, "type").to_ascii_uppercase(), str_of(r, "data"));
                            if !host.is_empty() && !data.is_empty() && !kind.is_empty() {
                                records.push(copy::record_line(&kind, &copy::relative_name(host, &auth_domain), data));
                            }
                        }
                    }
                }
                let valid = entry.get("valid").and_then(Value::as_bool).unwrap_or(false) && invalid.is_empty();
                if valid {
                    domain_ok = true;
                    dr.checks.push(make_check(StatusLevel::Ok, "SendGrid: DKIM", "SendGrid has verified your domain authentication (DKIM).", None));
                    report.ok("Domain authentication", format!("{auth_domain} is authenticated."));
                } else {
                    let fix = copy::with_records(
                        &format!("Add these records to `{auth_domain}`, then click Verify in SendGrid (Settings > Sender Authentication):"),
                        &records,
                    );
                    dr.checks.push(make_check(
                        StatusLevel::Error,
                        "SendGrid: DKIM",
                        format!("SendGrid hasn't verified your domain authentication yet. {}", copy::DKIM),
                        Some(&fix),
                    ));
                    report.error("Domain authentication", format!("{auth_domain} isn't fully authenticated in SendGrid."), &fix);
                }
            }
        }
        Err(e) if e.is_access_denied() => {
            domains_readable = false;
            report.info(
                "Domain authentication",
                "This API key can't read domain authentication, so it isn't shown. Add the Domain Authentication read permission to see it.",
            );
        }
        Err(_) => domains_readable = false,
    }
    if !domain_ok && domains_readable {
        // No authenticated domain: a verified Single Sender is the only other way to send.
        match get_json(ctx, &format!("{api}/v3/verified_senders"), auth, &[], &[]) {
            Ok(body) => {
                let sender = body
                    .get("results")
                    .and_then(Value::as_array)
                    .and_then(|l| l.iter().find(|s| str_of(s, "from_email").eq_ignore_ascii_case(from)));
                match sender {
                    Some(s) if s.get("verified").and_then(Value::as_bool).unwrap_or(false) => {
                        report.ok("Sender verification", format!("{from} is a verified Single Sender."));
                        dr.checks.push(make_check(
                            StatusLevel::Info,
                            "SendGrid: sender verification",
                            "You're sending from one verified address. Authenticating the whole domain gives better deliverability.",
                            None,
                        ));
                    }
                    Some(_) => report.error(
                        "Sender verification",
                        format!("{from} isn't verified as a sender yet."),
                        "Click the verification link SendGrid emailed to that address, or authenticate the whole domain.",
                    ),
                    None => report.error(
                        "Sender verification",
                        format!("Neither {from} nor {domain} is verified in SendGrid."),
                        "In SendGrid, authenticate the domain (Settings > Sender Authentication) or verify this address as a Single Sender.",
                    ),
                }
            }
            Err(e) if e.is_access_denied() => {
                report.info("Sender verification", "This API key can't read sender verification, so it isn't shown.");
            }
            Err(_) => {}
        }
    }
    report.domains.push(dr);

    stats(ctx, &api, auth, &mut report);
    report
}

fn stats(ctx: &Ctx, api: &str, auth: Auth, report: &mut ProviderReport) {
    let today = chrono::Utc::now();
    let query = [
        ("start_date", (today - chrono::Duration::days(30)).format("%Y-%m-%d").to_string()),
        ("end_date", today.format("%Y-%m-%d").to_string()),
    ];
    let body = match get_json(ctx, &format!("{api}/v3/stats"), auth, &[], &query) {
        Ok(b) => b,
        Err(e) if e.is_access_denied() => {
            report.info("Recent delivery", "This API key can't read statistics, so delivery numbers aren't shown.");
            return;
        }
        Err(_) => return,
    };
    let mut totals = [0i64; 5]; // requests, delivered, bounces, blocks, spam_reports
    for day in body.as_array().into_iter().flatten() {
        for entry in day.get("stats").and_then(Value::as_array).into_iter().flatten() {
            let m = entry.get("metrics").unwrap_or(&Value::Null);
            for (i, key) in ["requests", "delivered", "bounces", "blocks", "spam_reports"].iter().enumerate() {
                totals[i] += i64_of(m.get(*key).unwrap_or(&Value::Null));
            }
        }
    }
    let [requests, delivered, bounces, blocks, spam] = totals;
    report.metric("Emails requested", requests.to_string(), Some("last 30 days"));
    report.metric("Delivered", delivered.to_string(), Some("last 30 days"));
    report.metric("Bounced", bounces.to_string(), Some("last 30 days"));
    report.metric("Blocked", blocks.to_string(), Some("last 30 days"));
    report.metric("Spam reports", spam.to_string(), Some("last 30 days"));
    let pct = |n: i64| if requests > 0 { n as f64 * 100.0 / requests as f64 } else { 0.0 };
    report.check_rates("Recent delivery", requests, pct(bounces), pct(spam));
}
