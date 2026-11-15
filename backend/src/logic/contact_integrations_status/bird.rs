//! Live status of the Bird SMS integration (Bearer workspace key, regional host).
//!
//! Endpoints, all verified against Bird's published OpenAPI document (`bird.com/openapi.json`):
//! `GET /v1/sms/senders` (`data[]`: `id`, `sender`, `sender_type`, `status`
//! active|pending_number_ownership|pending_registrations, `destinations.active|pending|
//! needs_attention`); `GET /v1/sms/senders/{id}/requirements` (`data[]`: `country_code`,
//! `registration_mode` none|optional|required, `program` 10dlc|tfn|alpha|..., `status`, `rejection_reason`);
//! `GET /v1/sms/stats/summary?from=&to=` (`delivery.*`); `GET /v1/organization/billing/wallets`
//! (organization master keys only).

use serde_json::Value;

use crate::protos::{BirdConfig, StatusLevel};

use super::http::{encode_segment, f64_of, get_json, i64_of, str_of, Auth, Ctx, Fail};
use super::report::ProviderReport;

pub const DASHBOARD_URL: &str = "https://app.bird.com/";

fn normalize_sender(s: &str) -> String {
    let t = s.trim();
    if t.chars().any(|c| c.is_ascii_alphabetic()) {
        t.to_ascii_lowercase()
    } else {
        t.chars().filter(|c| c.is_ascii_digit()).collect()
    }
}

pub fn check(config: &BirdConfig, ctx: &Ctx) -> ProviderReport {
    let mut report = ProviderReport::default();
    let auth = Auth::Bearer(&config.bird_access_key);
    let host = ctx.host(&crate::logic::bird_sms::default_base_url(&config.bird_region));
    let from = config.bird_from.trim();

    // Sender list doubles as the credentials check.
    let mut senders: Vec<Value> = vec![];
    let mut cursor: Option<String> = None;
    for _ in 0..3 {
        let mut query = vec![("limit", "100".to_string())];
        if let Some(c) = &cursor {
            query.push(("starting_after", c.clone()));
        }
        match get_json(ctx, &format!("{host}/v1/sms/senders"), auth, &[], &query) {
            Ok(body) => {
                if let Some(page) = body.get("data").and_then(Value::as_array) {
                    senders.extend(page.iter().cloned());
                }
                cursor = body.get("next_cursor").and_then(Value::as_str).map(|s| s.to_string());
                if cursor.is_none() {
                    break;
                }
            }
            Err(Fail::Unauthorized) => {
                report.error(
                    "API credentials",
                    "Bird rejected the access key (HTTP 401).",
                    "Create a workspace access key in Bird (Developers > API access) with SMS permissions, and check the region (us1/eu1).",
                );
                report.headline = Some("Credentials rejected by Bird".to_string());
                return report;
            }
            Err(Fail::Unreachable(e)) => {
                report.unknown("API credentials", format!("Couldn't reach Bird ({e})."));
                report.headline = Some("Couldn't reach Bird".to_string());
                return report;
            }
            Err(Fail::Forbidden(_)) => {
                report.ok("API credentials", "Bird accepted the access key.");
                report.info("Sender", "This access key isn't allowed to list SMS senders, so the sender couldn't be verified.");
                stats(ctx, &host, auth, &mut report);
                return report;
            }
            Err(other) => {
                report.unknown("API credentials", format!("Unexpected response from Bird: {}", other.describe()));
                return report;
            }
        }
    }
    report.ok("API credentials", "Bird accepted the access key.");

    if from.is_empty() {
        report.error("Sender", "No originator is configured.", "Enter a number, short code or alphanumeric sender ID owned by your Bird workspace.");
    } else {
        let wanted = normalize_sender(from);
        match senders.iter().find(|s| normalize_sender(str_of(s, "sender")) == wanted) {
            None => report.error(
                "Sender",
                format!("\"{from}\" isn't one of this workspace's SMS senders."),
                "Add it under SMS > Senders in Bird, or correct the originator here.",
            ),
            Some(sender) => {
                let status = str_of(sender, "status");
                let active: Vec<&str> = sender
                    .pointer("/destinations/active")
                    .and_then(Value::as_array)
                    .map(|a| a.iter().filter_map(Value::as_str).collect())
                    .unwrap_or_default();
                match status {
                    "active" => report.ok("Sender", format!("\"{from}\" is active for: {}.", active.join(", "))),
                    "pending_number_ownership" => report.error(
                        "Sender",
                        format!("\"{from}\" is waiting on number-ownership paperwork; Bird refuses sends from it."),
                        "Complete the ownership steps in Bird (SMS > Senders).",
                    ),
                    "pending_registrations" => report.error(
                        "Sender",
                        format!("\"{from}\" has no active destination yet: its registrations are still pending."),
                        "Finish the sender's registration in Bird (SMS > Senders).",
                    ),
                    other => report.unknown("Sender", format!("Sender status: {other}.")),
                }
                if !active.is_empty() {
                    report.metric("Active destinations", active.join(", "), None);
                }
                requirements(ctx, &host, auth, str_of(sender, "id"), &mut report);
            }
        }
    }

    stats(ctx, &host, auth, &mut report);

    // Wallet balance: only readable with an organization-level key, so skip silently otherwise.
    if let Ok(body) = get_json(ctx, &format!("{host}/v1/organization/billing/wallets"), auth, &[], &[]) {
        if let Some(wallet) = body.get("data").and_then(Value::as_array).and_then(|a| a.first()) {
            let currency = str_of(wallet, "currency_code");
            if let Some(b) = f64_of(wallet.get("balance").unwrap_or(&Value::Null)) {
                report.metric("Wallet balance", format!("{b:.2} {currency}").trim().to_string(), None);
                if b <= 0.0 {
                    report.error("Wallet balance", format!("Wallet is empty ({b:.2} {currency})."), "Top up the wallet in Bird; sends fail with HTTP 402 without balance.");
                } else {
                    report.ok("Wallet balance", format!("{b:.2} {currency}."));
                }
            }
        }
    }
    report
}

fn requirements(ctx: &Ctx, host: &str, auth: Auth, sender_id: &str, report: &mut ProviderReport) {
    const NAME: &str = "Carrier registration";
    if sender_id.is_empty() {
        return;
    }
    let url = format!("{host}/v1/sms/senders/{}/requirements", encode_segment(sender_id));
    let body = match get_json(ctx, &url, auth, &[], &[]) {
        Ok(b) => b,
        Err(e) if e.is_access_denied() => {
            report.info(NAME, "This access key can't read sender registration requirements.");
            return;
        }
        Err(_) => {
            report.unknown(NAME, "Couldn't read the sender's registration requirements.");
            return;
        }
    };
    let rows = body.get("data").and_then(Value::as_array).cloned().unwrap_or_default();
    let mut bad: Vec<String> = vec![];
    let mut pending: Vec<String> = vec![];
    let mut approved = 0;
    for row in &rows {
        let status = str_of(row, "status");
        let required = str_of(row, "registration_mode") == "required"
            || row.get("has_compliance_requirements").and_then(Value::as_bool) == Some(true);
        let label = format!(
            "{} {}",
            str_of(row, "country_code"),
            row.get("program").and_then(Value::as_str).unwrap_or("")
        )
        .trim()
        .to_string();
        match status {
            "approved" => approved += 1,
            "not_required" => {}
            "rejected" | "suspended" | "registration_required" if required => {
                let reason = str_of(row, "rejection_reason");
                bad.push(if reason.is_empty() { format!("{label}: {status}") } else { format!("{label}: {status} ({reason})") });
            }
            "pending" | "under_review" | "bird_approved" | "carrier_pending" if required => {
                pending.push(format!("{label}: {status}"));
            }
            _ => {}
        }
    }
    if !bad.is_empty() {
        report.error(
            NAME,
            format!("Registration needs action: {}.", bad.join("; ")),
            "Open the sender in Bird (SMS > Senders) and complete or resubmit the registration; carriers block unregistered traffic in these countries.",
        );
    } else if !pending.is_empty() {
        report.warn(
            NAME,
            format!("Registration in progress: {}.", pending.join("; ")),
            "Messages to those countries may be blocked until the registration is approved.",
        );
    } else if approved > 0 {
        report.ok(NAME, format!("Registered and approved for {approved} destination(s)."));
    } else {
        report.info(NAME, "No registrations are required for this sender's destinations.");
    }
}

fn stats(ctx: &Ctx, host: &str, auth: Auth, report: &mut ProviderReport) {
    let today = chrono::Utc::now();
    let query = [
        ("from", (today - chrono::Duration::days(30)).format("%Y-%m-%d").to_string()),
        ("to", today.format("%Y-%m-%d").to_string()),
    ];
    let body = match get_json(ctx, &format!("{host}/v1/sms/stats/summary"), auth, &[], &query) {
        Ok(b) => b,
        Err(e) if e.is_access_denied() => {
            report.info("Recent delivery", "This access key can't read SMS statistics.");
            return;
        }
        Err(_) => return,
    };
    let Some(d) = body.get("delivery") else { return };
    let accepted = i64_of(d.get("accepted").unwrap_or(&Value::Null));
    let delivered = i64_of(d.get("delivered").unwrap_or(&Value::Null));
    let failed = i64_of(d.get("failed").unwrap_or(&Value::Null))
        + i64_of(d.get("undelivered").unwrap_or(&Value::Null))
        + i64_of(d.get("rejected").unwrap_or(&Value::Null))
        + i64_of(d.get("expired").unwrap_or(&Value::Null));
    report.metric("Messages accepted", accepted.to_string(), Some("last 30 days"));
    report.metric("Delivered", delivered.to_string(), Some("last 30 days"));
    report.metric("Failed / undelivered", failed.to_string(), Some("last 30 days"));
    if let Some(rate) = d.get("delivery_rate").and_then(Value::as_f64) {
        report.metric("Delivery rate", format!("{:.1}%", rate * 100.0), Some("last 30 days"));
    }
    let finished = delivered + failed;
    if accepted == 0 {
        report.info("Recent delivery", "No outbound messages in the last 30 days.");
    } else if finished >= 10 && failed as f64 * 100.0 / finished as f64 >= 20.0 {
        report.check(
            StatusLevel::Warning,
            "Recent delivery",
            format!("{failed} of {finished} finished messages failed ({:.0}%).", failed as f64 * 100.0 / finished as f64),
            Some("Open the SMS log in Bird to see the error codes."),
        );
    } else {
        report.ok("Recent delivery", format!("{delivered} delivered, {failed} failed out of {accepted} accepted."));
    }
}
