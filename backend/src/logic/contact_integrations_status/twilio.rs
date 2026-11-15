//! Live status of the Twilio SMS integration. Authenticates exactly like sending does (HTTP Basic
//! with the API Key SID/Secret), so a key that works here works for sending.
//!
//! Endpoints (Twilio docs): Account `GET /2010-04-01/Accounts/{sid}.json` (`status`
//! active|suspended|closed, `type` Trial|Full); Balance `GET .../Balance.json`; IncomingPhoneNumbers
//! `GET .../IncomingPhoneNumbers.json?PhoneNumber=` (`capabilities.sms`); Messages
//! `GET .../Messages.json?DateSent>=&From=&PageSize=` (`status`, `error_code`); Toll-Free
//! Verifications `GET https://messaging.twilio.com/v1/Tollfree/Verifications?TollfreePhoneNumberSid=`
//! (`status` PENDING_REVIEW|IN_REVIEW|TWILIO_APPROVED|TWILIO_REJECTED); A2P 10DLC via Messaging
//! Services `GET https://messaging.twilio.com/v1/Services`, `.../Services/{sid}/PhoneNumbers`,
//! `.../Services/{sid}/Compliance/Usa2p` (`campaign_status` PENDING|IN_PROGRESS|FAILED|VERIFIED).

use std::collections::BTreeMap;

use serde_json::Value;

use crate::protos::TwilioConfig;

use super::http::{encode_segment, f64_of, get_json, str_of, Auth, Ctx, Fail};
use super::report::ProviderReport;

pub const API_HOST: &str = "https://api.twilio.com";
pub const MESSAGING_HOST: &str = "https://messaging.twilio.com";
pub const DASHBOARD_URL: &str = "https://console.twilio.com/";

/// US/Canada toll-free area codes (NANP): numbers here need Toll-Free Verification to deliver.
pub fn is_toll_free(e164: &str) -> bool {
    let digits: String = e164.chars().filter(|c| c.is_ascii_digit()).collect();
    digits.len() == 11
        && digits.starts_with('1')
        && matches!(&digits[1..4], "800" | "833" | "844" | "855" | "866" | "877" | "888")
}

pub fn is_us_ca_long_code(e164: &str) -> bool {
    let digits: String = e164.chars().filter(|c| c.is_ascii_digit()).collect();
    digits.len() == 11 && digits.starts_with('1') && !is_toll_free(e164)
}

pub fn check(config: &TwilioConfig, ctx: &Ctx) -> ProviderReport {
    let mut report = ProviderReport::default();
    let account = &config.twilio_account_sid;
    let key = &config.twilio_api_key_sid;
    let secret = &config.twilio_api_key_secret;
    let auth = Auth::Basic(key, secret);
    let api = ctx.host(API_HOST);
    let messaging = ctx.host(MESSAGING_HOST);
    let account_url = format!("{api}/2010-04-01/Accounts/{}", encode_segment(account));

    // 1. Account -- doubles as the credentials check.
    match get_json(ctx, &format!("{account_url}.json"), auth, &[], &[]) {
        Err(Fail::Unauthorized) => {
            report.error(
                "API credentials",
                "Twilio didn't accept the API Key.",
                "Check the Account SID, API Key SID and API Key Secret; the key may have been revoked.",
            );
            report.headline = Some("Credentials rejected by Twilio".to_string());
            return report;
        }
        Err(Fail::NotFound) => {
            report.error(
                "API credentials",
                format!("Twilio doesn't know the account {account} (HTTP 404)."),
                "Check the Account SID (starts with AC).",
            );
            report.headline = Some("Twilio account not found".to_string());
            return report;
        }
        Err(Fail::Unreachable(e)) => {
            report.unknown("API credentials", format!("Couldn't reach Twilio ({e})."));
            report.headline = Some("Couldn't reach Twilio".to_string());
            return report;
        }
        Err(other) => {
            report.unknown("API credentials", format!("Unexpected response from Twilio: {}", other.describe()));
            return report;
        }
        Ok(body) => {
            let status = str_of(&body, "status");
            let kind = str_of(&body, "type");
            let name = str_of(&body, "friendly_name");
            match status {
                "active" | "" => report.ok(
                    "API credentials",
                    format!("Authenticated to account {}.", if name.is_empty() { account.as_str() } else { name }),
                ),
                other => report.error(
                    "API credentials",
                    format!("The Twilio account is {other}."),
                    "Contact Twilio support or reactivate the account in the Twilio Console.",
                ),
            }
            if !kind.is_empty() {
                report.metric("Account type", kind, None);
            }
            if kind.eq_ignore_ascii_case("trial") {
                report.warn(
                    "Account plan",
                    "This is a Twilio trial account. It can only text numbers you've verified, and messages carry a trial notice.",
                    "Upgrade the account in the Twilio Console to text arbitrary users.",
                );
            } else if !kind.is_empty() {
                report.ok("Account plan", format!("{kind} account."));
            }
        }
    }

    // 2. Balance (needs a key allowed to read it).
    match get_json(ctx, &format!("{account_url}/Balance.json"), auth, &[], &[]) {
        Ok(body) => {
            let balance = f64_of(body.get("balance").unwrap_or(&Value::Null));
            let currency = str_of(&body, "currency");
            if let Some(b) = balance {
                report.metric("Balance", format!("{b:.2} {currency}").trim().to_string(), None);
                if b <= 0.0 {
                    report.error("Account balance", format!("Balance is {b:.2} {currency}."), "Add funds in the Twilio Console; sends fail at zero balance.");
                } else if b < 5.0 {
                    report.warn("Account balance", format!("Balance is low: {b:.2} {currency}."), "Add funds or enable auto-recharge in the Twilio Console.");
                } else {
                    report.ok("Account balance", format!("{b:.2} {currency} available."));
                }
            }
        }
        Err(e) if e.is_access_denied() => {
            report.info("Account balance", "This API key isn't allowed to read the balance (restricted key).");
        }
        Err(_) => {}
    }

    // 3. The sender number.
    let from = config.twilio_from_number.trim();
    let mut number_sid: Option<String> = None;
    if from.is_empty() {
        report.error("Sender number", "No sender number is configured.", "Enter your Twilio phone number in E.164 format (+15551234567).");
    } else {
        let query = [("PhoneNumber", from.to_string())];
        match get_json(ctx, &format!("{account_url}/IncomingPhoneNumbers.json"), auth, &[], &query) {
            Ok(body) => {
                let numbers = body
                    .get("incoming_phone_numbers")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                match numbers.first() {
                    None => report.error(
                        "Sender number",
                        format!("{from} isn't one of this account's phone numbers."),
                        "Buy/port the number in Twilio, or correct the number here (E.164 format).",
                    ),
                    Some(number) => {
                        number_sid = Some(str_of(number, "sid").to_string());
                        let sms = number
                            .pointer("/capabilities/sms")
                            .and_then(Value::as_bool)
                            .unwrap_or(true);
                        if sms {
                            report.ok("Sender number", format!("{from} is SMS-capable."));
                        } else {
                            report.error(
                                "Sender number",
                                format!("{from} can't send SMS (no SMS capability)."),
                                "Use an SMS-capable Twilio number.",
                            );
                        }
                    }
                }
            }
            Err(e) if e.is_access_denied() => {
                report.info("Sender number", "This API key can't list phone numbers, so the sender couldn't be verified.");
            }
            Err(Fail::Unreachable(_)) | Err(_) => {
                report.unknown("Sender number", "Couldn't look up the sender number.");
            }
        }
    }

    // 4. Delivery over the last 30 days.
    delivery_stats(ctx, &account_url, auth, from, &mut report);

    // 5. Compliance (toll-free verification / A2P 10DLC).
    if !from.is_empty() {
        compliance(ctx, &messaging, auth, from, number_sid.as_deref(), &mut report);
    }
    report
}

fn delivery_stats(ctx: &Ctx, account_url: &str, auth: Auth, from: &str, report: &mut ProviderReport) {
    let since = (chrono::Utc::now() - chrono::Duration::days(30)).format("%Y-%m-%d").to_string();
    let mut query = vec![("DateSent>", since), ("PageSize", "1000".to_string())];
    if !from.is_empty() {
        query.push(("From", from.to_string()));
    }
    let body = match get_json(ctx, &format!("{account_url}/Messages.json"), auth, &[], &query) {
        Ok(b) => b,
        Err(e) if e.is_access_denied() => {
            report.info("Recent delivery", "This API key can't read message history.");
            return;
        }
        Err(_) => return,
    };
    let messages = body.get("messages").and_then(Value::as_array).cloned().unwrap_or_default();
    let more = body.get("next_page_uri").map(|v| !v.is_null()).unwrap_or(false);
    let mut delivered = 0u32;
    let mut failed = 0u32;
    let mut in_flight = 0u32;
    let mut sent = 0u32;
    let mut errors: BTreeMap<i64, u32> = BTreeMap::new();
    for m in &messages {
        if !str_of(m, "direction").starts_with("outbound") {
            continue;
        }
        sent += 1;
        match str_of(m, "status") {
            "delivered" | "read" => delivered += 1,
            "failed" | "undelivered" => {
                failed += 1;
                if let Some(code) = m.get("error_code").and_then(Value::as_i64) {
                    *errors.entry(code).or_default() += 1;
                }
            }
            "sent" => {}
            _ => in_flight += 1,
        }
    }
    let at_least = if more { "at least " } else { "" };
    report.metric("Messages sent", format!("{at_least}{sent}"), Some("last 30 days"));
    report.metric("Delivered", delivered.to_string(), Some("last 30 days"));
    report.metric("Failed / undelivered", failed.to_string(), Some("last 30 days"));
    if sent == 0 {
        report.info("Recent delivery", "No outbound messages in the last 30 days.");
        return;
    }
    let finished = delivered + failed;
    let failure_pct = if finished > 0 { failed as f64 * 100.0 / finished as f64 } else { 0.0 };
    let top_error = errors.iter().max_by_key(|(_, n)| **n).map(|(c, _)| *c);
    let hint = match top_error {
        Some(30034) => Some("Error 30034: US carriers block texts from unregistered numbers. Register an A2P 10DLC brand and campaign, or use a verified toll-free number."),
        Some(30032) => Some("Error 30032: this toll-free number isn't verified. Submit a Toll-Free Verification in the Twilio Console."),
        Some(30007) => Some("Error 30007: carriers filtered texts as spam. Review the message wording and how people opt in."),
        _ => None,
    };
    let top = top_error.map(|c| format!(" Most common error code: {c}.")).unwrap_or_default();
    if finished >= 10 && failure_pct >= 20.0 {
        report.check(
            crate::protos::StatusLevel::Warning,
            "Recent delivery",
            format!("{failed} of {finished} finished messages failed ({failure_pct:.0}%).{top}"),
            Some(hint.unwrap_or("Open Monitor > Logs > Messaging in the Twilio Console to see why messages fail.")),
        );
    } else {
        report.ok(
            "Recent delivery",
            format!("{delivered} delivered, {failed} failed, {in_flight} in flight out of {sent}.{top}"),
        );
    }
}

fn compliance(
    ctx: &Ctx,
    messaging: &str,
    auth: Auth,
    from: &str,
    number_sid: Option<&str>,
    report: &mut ProviderReport,
) {
    const NAME: &str = "Carrier registration";
    if is_toll_free(from) {
        let Some(sid) = number_sid.filter(|s| !s.is_empty()) else {
            report.info(NAME, "Toll-free verification couldn't be checked because the number wasn't found.");
            return;
        };
        let query = [("TollfreePhoneNumberSid", sid.to_string()), ("PageSize", "5".to_string())];
        match get_json(ctx, &format!("{messaging}/v1/Tollfree/Verifications"), auth, &[], &query) {
            Ok(body) => {
                // The list's array key isn't spelled out in the docs; take the first array that
                // isn't `meta`.
                let records = first_array(&body, &["verifications"]);
                let status = records.first().map(|r| str_of(r, "status").to_string());
                match status.as_deref() {
                    Some("TWILIO_APPROVED") => report.ok(NAME, "Toll-free verification approved."),
                    Some("TWILIO_REJECTED") => {
                        let reason = records.first().map(|r| str_of(r, "rejection_reason").to_string()).unwrap_or_default();
                        report.error(
                            NAME,
                            format!("Toll-free verification was rejected. {reason}").trim().to_string(),
                            "Edit and resubmit it in the Twilio Console. Carriers block unverified toll-free numbers.",
                        )
                    }
                    Some(s @ ("PENDING_REVIEW" | "IN_REVIEW")) => report.warn(
                        NAME,
                        format!("Toll-free verification is {} (review takes days to weeks).", s.to_lowercase().replace('_', " ")),
                        "Until it's approved, carriers may block or heavily filter messages from this number.",
                    ),
                    Some(other) => report.unknown(NAME, format!("Toll-free verification status: {other}.")),
                    None => report.warn(
                        NAME,
                        "No toll-free verification has been submitted for this number.",
                        "Submit a Toll-Free Verification in the Twilio Console (Messaging > Regulatory Compliance). Carriers block unverified toll-free numbers.",
                    ),
                }
            }
            Err(e) if e.is_access_denied() => report.info(NAME, "This API key can't read toll-free verification status."),
            Err(_) => report.unknown(NAME, "Couldn't read toll-free verification status."),
        }
    } else if is_us_ca_long_code(from) {
        let Some(sid) = number_sid.filter(|s| !s.is_empty()) else {
            report.info(NAME, "A2P 10DLC status couldn't be checked because the number wasn't found.");
            return;
        };
        a2p_status(ctx, messaging, auth, from, sid, report);
    } else {
        report.info(NAME, "US carrier registration doesn't apply to this number. Check the sender rules for the countries you text.");
    }
}

/// First array value in `body` (preferring `preferred` keys), skipping `meta`.
fn first_array(body: &Value, preferred: &[&str]) -> Vec<Value> {
    for key in preferred {
        if let Some(a) = body.get(*key).and_then(Value::as_array) {
            return a.clone();
        }
    }
    body.as_object()
        .into_iter()
        .flatten()
        .filter(|(k, _)| k.as_str() != "meta")
        .find_map(|(_, v)| v.as_array().cloned())
        .unwrap_or_default()
}

fn a2p_status(ctx: &Ctx, messaging: &str, auth: Auth, from: &str, number_sid: &str, report: &mut ProviderReport) {
    const NAME: &str = "Carrier registration";
    let services = match get_json(ctx, &format!("{messaging}/v1/Services"), auth, &[], &[("PageSize", "50".to_string())]) {
        Ok(b) => first_array(&b, &["services"]),
        Err(e) if e.is_access_denied() => {
            report.info(NAME, "This API key can't read Messaging Services, so A2P 10DLC status couldn't be checked.");
            return;
        }
        Err(_) => {
            report.unknown(NAME, "Couldn't read Messaging Services to check A2P 10DLC status.");
            return;
        }
    };
    for service in services.iter().take(25) {
        let service_sid = str_of(service, "sid");
        if service_sid.is_empty() {
            continue;
        }
        let numbers_url = format!("{messaging}/v1/Services/{service_sid}/PhoneNumbers");
        let Ok(numbers) = get_json(ctx, &numbers_url, auth, &[], &[("PageSize", "100".to_string())]) else { continue };
        let member = first_array(&numbers, &["phone_numbers"])
            .iter()
            .any(|n| str_of(n, "sid") == number_sid);
        if !member {
            continue;
        }
        let compliance_url = format!("{messaging}/v1/Services/{service_sid}/Compliance/Usa2p");
        match get_json(ctx, &compliance_url, auth, &[], &[]) {
            Ok(body) => {
                let campaigns = first_array(&body, &["compliance"]);
                if campaigns.is_empty() {
                    report.warn(
                        NAME,
                        format!("{from} is in a Messaging Service with no A2P 10DLC campaign."),
                        "Register an A2P 10DLC brand and campaign for the Messaging Service. US carriers block unregistered texts.",
                    );
                    return;
                }
                let verified = campaigns.iter().any(|c| str_of(c, "campaign_status") == "VERIFIED");
                if verified {
                    report.ok(NAME, "A2P 10DLC campaign verified.");
                } else if campaigns.iter().any(|c| matches!(str_of(c, "campaign_status"), "PENDING" | "IN_PROGRESS")) {
                    report.warn(NAME, "A2P 10DLC campaign is still being reviewed.", "Messages may be filtered until the campaign is verified.");
                } else {
                    let status = str_of(&campaigns[0], "campaign_status").to_string();
                    report.error(
                        NAME,
                        format!("A2P 10DLC campaign status: {status}."),
                        "Fix and resubmit the campaign in the Twilio Console (Messaging > Regulatory Compliance).",
                    );
                }
            }
            Err(e) if e.is_access_denied() => report.info(NAME, "This API key can't read A2P 10DLC campaigns."),
            Err(_) => report.unknown(NAME, "Couldn't read the A2P 10DLC campaign."),
        }
        return;
    }
    report.warn(
        NAME,
        format!("{from} isn't in any Messaging Service with an A2P 10DLC campaign."),
        "US carriers block texts from unregistered numbers. Add the number to a Messaging Service with a registered A2P campaign, or use a verified toll-free number.",
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn toll_free_detection() {
        assert!(is_toll_free("+18885551234"));
        assert!(is_toll_free("+1 (844) 555-1234"));
        assert!(!is_toll_free("+15551234567"));
        assert!(!is_toll_free("+448885551234"));
        assert!(is_us_ca_long_code("+15551234567"));
        assert!(!is_us_ca_long_code("+18885551234"));
        assert!(!is_us_ca_long_code("+447911123456"));
    }

    #[test]
    fn first_array_prefers_key_then_skips_meta() {
        let b = serde_json::json!({"meta": {"key": "x", "list": [1]}, "things": [{"a": 1}]});
        assert_eq!(first_array(&b, &["verifications"]).len(), 1);
        assert_eq!(first_array(&b, &["things"]).len(), 1);
    }
}
