//! Live status of the Postmark email integration.
//!
//! Server token (`X-Postmark-Server-Token`): `GET /server` (`Name`, `DeliveryType` Live|Sandbox) and
//! `GET /stats/outbound?fromdate=&todate=&messagestream=` (`Sent`, `Bounced`, `BounceRate`,
//! `SpamComplaints`, `SpamComplaintsRate` -- percentages). Optional Account token
//! (`X-Postmark-Account-Token`): `GET /domains?count=&offset=` + `GET /domains/{id}` (`DKIMVerified`,
//! `WeakDKIM`, `DKIMHost`, `DKIMPendingHost`, `ReturnPathDomain`, `ReturnPathDomainVerified`) and
//! `GET /senders?count=&offset=` (`SenderSignatures[]`: `EmailAddress`, `Domain`, `Confirmed`).

use serde_json::Value;

use crate::protos::{PostmarkConfig, StatusLevel};

use super::copy;
use super::domain::domain_of_address;
use super::http::{encode_segment, f64_of, get_json, i64_of, str_of, Auth, Ctx, Fail};
use super::report::{make_check, DomainReport, ProviderReport};

pub const API_HOST: &str = "https://api.postmarkapp.com";
pub const DASHBOARD_URL: &str = "https://account.postmarkapp.com/";

pub fn check(config: &PostmarkConfig, ctx: &Ctx) -> ProviderReport {
    let mut report = ProviderReport::default();
    let api = ctx.host(API_HOST);
    let server_auth = Auth::Header("X-Postmark-Server-Token", &config.postmark_server_token);

    // 1. Server -- the credentials check.
    match get_json(ctx, &format!("{api}/server"), server_auth, &[], &[]) {
        Ok(body) => {
            let name = str_of(&body, "Name");
            report.ok("API credentials", format!("Authenticated to server \"{name}\"."));
            if !name.is_empty() {
                report.metric("Server", name, None);
            }
            if str_of(&body, "DeliveryType").eq_ignore_ascii_case("sandbox") {
                report.warn(
                    "Server mode",
                    "This is a Sandbox server, so Postmark accepts email but never delivers it.",
                    "Create a Live server in Postmark and paste its Server API Token here.",
                );
            }
        }
        Err(Fail::Unauthorized) | Err(Fail::Http(422, _)) => {
            report.error(
                "API credentials",
                "Postmark didn't accept the Server API token.",
                "Copy the Server API Token from your Postmark server's API Tokens tab and paste it here.",
            );
            report.headline = Some("Credentials rejected by Postmark".to_string());
            return report;
        }
        Err(Fail::Unreachable(e)) => {
            report.unknown("API credentials", format!("Couldn't reach Postmark ({e})."));
            report.headline = Some("Couldn't reach Postmark".to_string());
            return report;
        }
        Err(other) => {
            report.unknown("API credentials", format!("Unexpected response from Postmark: {}", other.describe()));
            return report;
        }
    }

    // 2. Last-30-days stats.
    stats(ctx, &api, server_auth, &config.postmark_message_stream, &mut report);

    // 3. Domain / sender-signature verification (needs the Account token).
    let from = config.postmark_from_address.trim();
    let from_domain = domain_of_address(from);
    if config.postmark_account_token.trim().is_empty() {
        report.info(
            "Sending domain",
            "Add a Postmark Account API token to see whether your sending domain is verified.",
        );
    } else if let Some(domain) = from_domain {
        let account_auth = Auth::Header("X-Postmark-Account-Token", &config.postmark_account_token);
        domain_checks(ctx, &api, account_auth, from, &domain, &mut report);
    } else {
        report.error("Sending domain", format!("\"{from}\" isn't a valid From address."), "Enter an address like noreply@example.com.");
    }
    report
}

fn stats(ctx: &Ctx, api: &str, auth: Auth, stream: &str, report: &mut ProviderReport) {
    let today = chrono::Utc::now();
    let mut query = vec![
        ("fromdate", (today - chrono::Duration::days(30)).format("%Y-%m-%d").to_string()),
        ("todate", today.format("%Y-%m-%d").to_string()),
    ];
    if !stream.trim().is_empty() {
        query.push(("messagestream", stream.trim().to_string()));
    }
    let body = match get_json(ctx, &format!("{api}/stats/outbound"), auth, &[], &query) {
        Ok(b) => b,
        Err(e) if e.is_access_denied() => {
            report.info("Recent delivery", "This token can't read sending statistics.");
            return;
        }
        Err(_) => return,
    };
    let sent = i64_of(body.get("Sent").unwrap_or(&Value::Null));
    let bounced = i64_of(body.get("Bounced").unwrap_or(&Value::Null));
    let spam = i64_of(body.get("SpamComplaints").unwrap_or(&Value::Null));
    let bounce_rate = f64_of(body.get("BounceRate").unwrap_or(&Value::Null)).unwrap_or(0.0);
    let spam_rate = f64_of(body.get("SpamComplaintsRate").unwrap_or(&Value::Null)).unwrap_or(0.0);
    report.metric("Emails sent", sent.to_string(), Some("last 30 days"));
    report.metric("Bounced", format!("{bounced} ({bounce_rate:.2}%)"), Some("last 30 days"));
    report.metric("Spam complaints", format!("{spam} ({spam_rate:.2}%)"), Some("last 30 days"));
    report.check_rates("Recent delivery", sent, bounce_rate, spam_rate);
}

fn domain_checks(ctx: &Ctx, api: &str, auth: Auth, from: &str, domain: &str, report: &mut ProviderReport) {
    const NAME: &str = "Sending domain";
    let query = [("count", "500".to_string()), ("offset", "0".to_string())];
    let domains = match get_json(ctx, &format!("{api}/domains"), auth, &[], &query) {
        Ok(b) => b,
        Err(e) if e.is_access_denied() || matches!(e, Fail::Http(422, _)) => {
            report.warn(NAME, "Postmark didn't accept the Account API token.", "Copy the Account API Token from Postmark (Account > API Tokens) and paste it here.");
            return;
        }
        Err(_) => {
            report.unknown(NAME, "Couldn't read domains from Postmark.");
            return;
        }
    };
    // A domain entry covers its own address space and subdomains.
    let entry = domains
        .get("Domains")
        .and_then(Value::as_array)
        .and_then(|list| {
            list.iter().find(|d| {
                let name = str_of(d, "Name").to_ascii_lowercase();
                domain == name || domain.ends_with(&format!(".{name}"))
            })
        })
        .cloned();
    let mut dr = DomainReport {
        domain: domain.to_string(),
        provider: "postmark".to_string(),
        ..Default::default()
    };
    if let Some(entry) = entry {
        let id = entry.get("ID").map(|v| i64_of(v).to_string()).unwrap_or_default();
        let details = get_json(ctx, &format!("{api}/domains/{}", encode_segment(&id)), auth, &[], &[]).unwrap_or(entry.clone());
        let dkim_ok = details.get("DKIMVerified").and_then(Value::as_bool).unwrap_or(false);
        let dkim_host = str_of(&details, "DKIMHost");
        let pending_host = str_of(&details, "DKIMPendingHost");
        for host in [dkim_host, pending_host] {
            if !host.is_empty() {
                dr.dkim_hosts.push(host.to_string());
            }
        }
        let dkim_value = if !pending_host.is_empty() {
            str_of(&details, "DKIMPendingTextValue")
        } else {
            str_of(&details, "DKIMTextValue")
        };
        let dkim_record_host = if pending_host.is_empty() { dkim_host } else { pending_host };
        if dkim_ok {
            dr.checks.push(make_check(StatusLevel::Ok, "Postmark: DKIM", "Postmark has verified your DKIM signing key.", None));
        } else {
            let records: Vec<String> = if !dkim_record_host.is_empty() && !dkim_value.is_empty() {
                vec![copy::record_line("TXT", &copy::relative_name(dkim_record_host, domain), dkim_value)]
            } else {
                vec![]
            };
            dr.checks.push(make_check(
                StatusLevel::Error,
                "Postmark: DKIM",
                format!("Postmark hasn't verified your DKIM signing key yet. {}", copy::DKIM),
                Some(&copy::with_records(
                    &format!("Add this record to `{domain}`, then click Verify in Postmark (Sender Signatures > Domains):"),
                    &records,
                )),
            ));
        }
        if details.get("WeakDKIM").and_then(Value::as_bool) == Some(true) {
            dr.checks.push(make_check(
                StatusLevel::Warning,
                "Postmark: DKIM key strength",
                "Your DKIM key is an older, weaker size.",
                Some("In Postmark, open Sender Signatures > Domains and choose Rotate DKIM key, then publish the new record it shows."),
            ));
        }
        if !pending_host.is_empty() && dkim_ok {
            dr.checks.push(make_check(
                StatusLevel::Info,
                "Postmark: DKIM rotation",
                "A new DKIM key is waiting to be published.",
                Some(&copy::with_records(
                    &format!("Add this record to `{domain}` to finish the key rotation:"),
                    &[copy::record_line("TXT", &copy::relative_name(pending_host, domain), str_of(&details, "DKIMPendingTextValue"))],
                )),
            ));
        }
        let return_path = str_of(&details, "ReturnPathDomain");
        if return_path.is_empty() {
            dr.checks.push(make_check(
                StatusLevel::Info,
                "Postmark: Return-Path",
                "No custom Return-Path is set. It's optional, but helps SPF line up with your domain.",
                None,
            ));
        } else if details.get("ReturnPathDomainVerified").and_then(Value::as_bool).unwrap_or(false) {
            dr.checks.push(make_check(StatusLevel::Ok, "Postmark: Return-Path", "Your Return-Path domain is verified.", None));
        } else {
            let cname = str_of(&details, "ReturnPathDomainCNAMEValue");
            let records: Vec<String> = if cname.is_empty() {
                vec![]
            } else {
                vec![copy::record_line("CNAME", &copy::relative_name(return_path, domain), cname)]
            };
            dr.checks.push(make_check(
                StatusLevel::Warning,
                "Postmark: Return-Path",
                format!("Postmark hasn't verified your Return-Path domain ({return_path})."),
                Some(&copy::with_records(&format!("Add this record to `{domain}`, then click Verify in Postmark:"), &records)),
            ));
        }
        report.ok(NAME, format!("{domain} is covered by the Postmark domain \"{}\".", str_of(&details, "Name")));
        if !dkim_ok {
            report.error("Domain DKIM", "Postmark hasn't verified your DKIM key yet.", "See the DKIM record to add under your sending domain below.");
        }
    } else {
        // No Domain: fall back to a Sender Signature for exactly this address.
        let sigs = get_json(ctx, &format!("{api}/senders"), auth, &[], &query);
        let signature = sigs.ok().and_then(|b| {
            b.get("SenderSignatures").and_then(Value::as_array).and_then(|list| {
                list.iter()
                    .find(|s| str_of(s, "EmailAddress").eq_ignore_ascii_case(from))
                    .cloned()
            })
        });
        match signature {
            Some(sig) if sig.get("Confirmed").and_then(Value::as_bool).unwrap_or(false) => {
                report.ok(NAME, format!("{from} is a confirmed Sender Signature."));
                dr.checks.push(make_check(
                    StatusLevel::Info,
                    "Postmark: sender signature",
                    "You're sending from one confirmed address. Verifying the whole domain gives better deliverability.",
                    None,
                ));
            }
            Some(_) => report.error(
                NAME,
                format!("The Sender Signature for {from} isn't confirmed."),
                "Click the confirmation link Postmark emailed to that address, or verify the whole domain instead.",
            ),
            None => report.error(
                NAME,
                format!("{from} isn't verified in Postmark."),
                "In Postmark, open Sender Signatures and verify this domain (or just this address).",
            ),
        }
    }
    report.domains.push(dr);
}
