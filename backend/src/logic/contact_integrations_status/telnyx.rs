//! Live status of the Telnyx SMS integration (Bearer API key).
//!
//! Endpoints (developers.telnyx.com): `GET /v2/balance` (`data.balance`/`available_credit`/
//! `credit_limit`/`currency`, all strings); `GET /v2/phone_numbers?filter[phone_number]=`
//! (`data[].id/phone_number/status/messaging_profile_id/messaging_campaign_id`);
//! `GET /v2/messaging_profiles/{id}` (`data.enabled`, `whitelisted_destinations`);
//! toll-free: `GET /v2/messaging_tollfree/verification/requests?phone_number=&page=&page_size=`
//! (`records[].verificationStatus` Verified|Rejected|Waiting For Vendor|Waiting For Customer|
//! Waiting For Telnyx|In Progress); 10DLC: `GET /v2/10dlc/phone_number_campaigns/{phoneNumber}`
//! (`assignmentStatus` ASSIGNED|PENDING_ASSIGNMENT|FAILED_ASSIGNMENT|...).

use serde_json::Value;

use crate::protos::TelnyxConfig;

use super::http::{encode_segment, f64_of, get_json, str_of, Auth, Ctx, Fail};
use super::report::ProviderReport;
use super::twilio::{is_toll_free, is_us_ca_long_code};

pub const API_HOST: &str = "https://api.telnyx.com";
pub const DASHBOARD_URL: &str = "https://portal.telnyx.com/";

fn digits(s: &str) -> String {
    s.chars().filter(|c| c.is_ascii_digit()).collect()
}

pub fn check(config: &TelnyxConfig, ctx: &Ctx) -> ProviderReport {
    let mut report = ProviderReport::default();
    let key = config.telnyx_api_key.as_str();
    let auth = Auth::Bearer(key);
    let api = ctx.host(API_HOST);
    let from = config.telnyx_from_number.trim();

    let balance = get_json(ctx, &format!("{api}/v2/balance"), auth, &[], &[]);
    let numbers = if from.is_empty() {
        None
    } else {
        Some(get_json(
            ctx,
            &format!("{api}/v2/phone_numbers"),
            auth,
            &[],
            &[("filter[phone_number]", from.to_string()), ("page[size]", "20".to_string())],
        ))
    };

    // Credentials: a 401 anywhere means the key is bad; success anywhere means it's good.
    let results: Vec<&Result<Value, Fail>> = std::iter::once(&balance).chain(numbers.iter()).collect();
    if results.iter().any(|r| matches!(r, Err(Fail::Unauthorized))) {
        report.error(
            "API credentials",
            "Telnyx rejected the API key (HTTP 401).",
            "Create a new v2 API key in the Telnyx Portal (Keys & Credentials) and paste it here.",
        );
        report.headline = Some("Credentials rejected by Telnyx".to_string());
        return report;
    }
    if results.iter().all(|r| matches!(r, Err(Fail::Unreachable(_)))) {
        report.unknown("API credentials", "Couldn't reach Telnyx.");
        report.headline = Some("Couldn't reach Telnyx".to_string());
        return report;
    }
    report.ok("API credentials", "Telnyx accepted the API key.");

    // Balance.
    match &balance {
        Ok(body) => {
            let data = body.get("data").unwrap_or(&Value::Null);
            let currency = str_of(data, "currency");
            let available = f64_of(data.get("available_credit").unwrap_or(&Value::Null));
            let bal = f64_of(data.get("balance").unwrap_or(&Value::Null));
            if let Some(b) = bal {
                report.metric("Balance", format!("{b:.2} {currency}").trim().to_string(), None);
            }
            if let Some(a) = available {
                report.metric("Available credit", format!("{a:.2} {currency}").trim().to_string(), None);
                if a <= 0.0 {
                    report.error("Account balance", format!("No credit available ({a:.2} {currency})."), "Add funds in the Telnyx Portal; sends fail without credit.");
                } else if a < 5.0 {
                    report.warn("Account balance", format!("Available credit is low: {a:.2} {currency}."), "Add funds or enable auto-recharge in the Telnyx Portal.");
                } else {
                    report.ok("Account balance", format!("{a:.2} {currency} available."));
                }
            }
        }
        Err(e) if e.is_access_denied() => {
            report.info("Account balance", "This API key isn't allowed to read the balance.");
        }
        Err(_) => {}
    }

    // Sender number + messaging profile assignment.
    let mut toll_free_or_campaign_checked = false;
    match &numbers {
        None => report.error("Sender number", "No sender number is configured.", "Enter your Telnyx number in E.164 format (+15551234567)."),
        Some(Err(e)) if e.is_access_denied() => report.info("Sender number", "This API key can't list phone numbers, so the sender couldn't be verified."),
        Some(Err(_)) => report.unknown("Sender number", "Couldn't look up the sender number."),
        Some(Ok(body)) => {
            let wanted = digits(from);
            let found = body
                .get("data")
                .and_then(Value::as_array)
                .and_then(|a| a.iter().find(|n| digits(str_of(n, "phone_number")) == wanted));
            match found {
                None => report.error(
                    "Sender number",
                    format!("{from} isn't a number on this Telnyx account."),
                    "Buy/port the number in Telnyx, or correct the number here (E.164 format).",
                ),
                Some(number) => {
                    let status = str_of(number, "status");
                    if status.is_empty() || status == "active" {
                        report.ok("Sender number", format!("{from} is active on this account."));
                    } else {
                        report.warn("Sender number", format!("{from} has status \"{status}\"."), "Wait for the number to become active, or contact Telnyx support.");
                    }
                    let assigned = str_of(number, "messaging_profile_id");
                    let configured = config.telnyx_messaging_profile_id.trim();
                    if assigned.is_empty() {
                        report.error(
                            "Messaging profile assignment",
                            format!("{from} isn't assigned to any messaging profile, so it can't send SMS."),
                            "Assign the number to your messaging profile in the Telnyx Portal (Messaging > Numbers).",
                        );
                    } else if !configured.is_empty() && assigned != configured {
                        report.error(
                            "Messaging profile assignment",
                            format!("{from} is assigned to a different messaging profile ({assigned}) than the one configured here ({configured})."),
                            "Update the Messaging Profile ID here, or reassign the number in the Telnyx Portal.",
                        );
                    } else {
                        report.ok("Messaging profile assignment", "The number is assigned to the configured messaging profile.");
                    }
                    if !str_of(number, "messaging_campaign_id").is_empty() {
                        report.metric("10DLC campaign", str_of(number, "messaging_campaign_id"), None);
                    }
                    toll_free_or_campaign_checked = true;
                }
            }
        }
    }

    // The configured messaging profile itself.
    let profile_id = config.telnyx_messaging_profile_id.trim();
    if profile_id.is_empty() {
        report.error("Messaging profile", "No Messaging Profile ID is configured.", "Telnyx requires a messaging profile to send; copy its ID from Messaging > Messaging Profiles.");
    } else {
        match get_json(ctx, &format!("{api}/v2/messaging_profiles/{}", encode_segment(profile_id)), auth, &[], &[]) {
            Ok(body) => {
                let data = body.get("data").unwrap_or(&Value::Null);
                let name = str_of(data, "name");
                if data.get("enabled").and_then(Value::as_bool) == Some(false) {
                    report.error("Messaging profile", format!("Profile \"{name}\" is disabled."), "Enable the messaging profile in the Telnyx Portal.");
                } else {
                    report.ok("Messaging profile", format!("Profile \"{name}\" is enabled."));
                }
                if let Some(dests) = data.get("whitelisted_destinations").and_then(Value::as_array) {
                    let list: Vec<&str> = dests.iter().filter_map(Value::as_str).collect();
                    if !list.is_empty() {
                        report.metric("Allowed destinations", list.join(", "), None);
                    }
                }
            }
            Err(Fail::NotFound) => report.error("Messaging profile", format!("Messaging profile {profile_id} doesn't exist on this account."), "Correct the Messaging Profile ID."),
            Err(e) if e.is_access_denied() => report.info("Messaging profile", "This API key can't read messaging profiles."),
            Err(_) => report.unknown("Messaging profile", "Couldn't read the messaging profile."),
        }
    }

    // Carrier registration.
    if !from.is_empty() && toll_free_or_campaign_checked {
        compliance(ctx, &api, auth, from, &mut report);
    }
    report
}

fn compliance(ctx: &Ctx, api: &str, auth: Auth, from: &str, report: &mut ProviderReport) {
    const NAME: &str = "Carrier registration";
    if is_toll_free(from) {
        let query = [
            ("phone_number", from.to_string()),
            ("page", "1".to_string()),
            ("page_size", "5".to_string()),
        ];
        match get_json(ctx, &format!("{api}/v2/messaging_tollfree/verification/requests"), auth, &[], &query) {
            Ok(body) => {
                let records = body.get("records").and_then(Value::as_array).cloned().unwrap_or_default();
                let status = records.first().map(|r| str_of(r, "verificationStatus").to_string());
                match status.as_deref() {
                    Some("Verified") => report.ok(NAME, "Toll-free verification approved."),
                    Some("Rejected") => {
                        let reason = records.first().map(|r| str_of(r, "reason").to_string()).unwrap_or_default();
                        report.error(
                            NAME,
                            format!("Toll-free verification was rejected. {reason}").trim().to_string(),
                            "Fix the issues and resubmit the verification in the Telnyx Portal; unverified toll-free numbers are blocked by carriers.",
                        )
                    }
                    Some(s @ ("Waiting For Vendor" | "Waiting For Customer" | "Waiting For Telnyx" | "In Progress")) => report.warn(
                        NAME,
                        format!("Toll-free verification status: {s}."),
                        "Until it's verified, carriers may block or filter messages from this number.",
                    ),
                    Some(other) => report.unknown(NAME, format!("Toll-free verification status: {other}.")),
                    None => report.warn(
                        NAME,
                        "No toll-free verification request found for this number.",
                        "Submit a toll-free verification in the Telnyx Portal; unverified toll-free traffic is blocked.",
                    ),
                }
            }
            Err(e) if e.is_access_denied() => report.info(NAME, "This API key can't read toll-free verification status."),
            Err(_) => report.unknown(NAME, "Couldn't read toll-free verification status."),
        }
    } else if is_us_ca_long_code(from) {
        let url = format!("{api}/v2/10dlc/phone_number_campaigns/{}", encode_segment(from));
        match get_json(ctx, &url, auth, &[], &[]) {
            Ok(body) => {
                let data = body.get("data").unwrap_or(&body);
                let status = str_of(data, "assignmentStatus");
                match status {
                    "ASSIGNED" | "" => report.ok(NAME, "The number is assigned to a 10DLC campaign."),
                    "PENDING_ASSIGNMENT" => report.warn(NAME, "Assignment to a 10DLC campaign is pending.", "Carriers may filter messages until the assignment completes."),
                    "FAILED_ASSIGNMENT" => report.error(
                        NAME,
                        format!("Assignment to the 10DLC campaign failed. {}", str_of(data, "failureReasons")).trim().to_string(),
                        "Fix the campaign/number assignment in the Telnyx Portal (Messaging > 10DLC).",
                    ),
                    other => report.warn(NAME, format!("10DLC assignment status: {other}."), "Check the number's 10DLC campaign in the Telnyx Portal."),
                }
            }
            Err(Fail::NotFound) => report.warn(
                NAME,
                format!("{from} isn't assigned to a 10DLC campaign."),
                "US carriers increasingly block unregistered 10DLC traffic: register a brand and campaign and assign this number (Telnyx Portal > Messaging > 10DLC), or use a verified toll-free number.",
            ),
            Err(e) if e.is_access_denied() => report.info(NAME, "This API key can't read 10DLC campaigns."),
            Err(_) => report.unknown(NAME, "Couldn't read 10DLC campaign status."),
        }
    } else {
        report.info(NAME, "US carrier registration (10DLC / toll-free verification) doesn't apply to this number; check the sender-registration rules for your destination countries.");
    }
}
