//! Inbound SMS delivery endpoints -- `POST /contact_integrations/{twilio,telnyx,bird}/receive`.
//! Each provider posts its own inbound-message events to its own URL (registered in that
//! provider's own webhook/portal config -- see `docs/contact_integrations.md`); all three funnel
//! into `handle_stop`, which only ever acts on one thing: a reply of exactly "STOP" (trimmed,
//! case-insensitive) revokes that sender's SMS `ContactMethod.consent_state` via
//! `logic::revoke_sms_consent_by_phone_number`, mirroring the CTIA-mandated opt-out every SMS
//! sender must honor. Every other inbound message/event is acknowledged (`200 OK`, so the provider
//! doesn't keep retrying a delivery this server was never going to act on -- same convention
//! `web::stripe_webhook` uses for events it doesn't subscribe to) but otherwise ignored -- Rellm
//! has no two-way SMS conversation feature to route a reply into.
//!
//! Signature verification is optional per provider, unlike `web::stripe_webhook`'s always-on
//! `Stripe-Signature` check: each of `TwilioConfig.use_twilio_webhook_signing_key`/
//! `TelnyxConfig.use_telnyx_webhook_signing_key`/`BirdConfig.use_bird_webhook_signing_key` is
//! `false` by default, in which case deliveries are accepted unverified. Once an admin sets a
//! signing key *and* flips that provider's "Use Webhook Signing Key" toggle on (see
//! `docs/contact_integrations.md`), that provider's deliveries are verified and an invalid/missing
//! signature is rejected with `401`. This graduated design exists because the only effect an
//! unauthenticated (or spoofed) delivery can have either way is *revoking* consent, never granting
//! it -- the fail-safe direction -- so verification is a hardening option, not a hard requirement.

use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine;
use rocket::data::ToByteUnit;
use rocket::http::Status;
use rocket::{routes, Data, Route, State};
use serde_json::Value;

use crate::db_connection::PgPooledConnection;
use crate::logic::{revoke_sms_consent_by_phone_number, server_bird_config, server_telnyx_config, server_twilio_config};
use crate::web::headers::{BirdWebhookHeaders, HostHeader, TelnyxWebhookHeaders, TwilioSignatureHeader};
use crate::web::RocketState;

lazy_static! {
    pub static ref CONTACT_INTEGRATIONS_WEBHOOK_ENDPOINTS: Vec<Route> =
        routes![twilio_receive, telnyx_receive, bird_receive];
}

const MAX_BODY_SIZE_MIB: u64 = 1;

/// A `telnyx-timestamp`/`webhook-timestamp` older/newer than this many seconds from "now" is
/// rejected outright, even if the signature itself matches -- guards against a captured-and-replayed
/// delivery, mirroring `web::stripe_webhook`'s own `SIGNATURE_TOLERANCE_SECONDS` (and Telnyx's own
/// documented recommendation). Twilio's signature scheme has no timestamp component at all, so
/// there's nothing to check there.
const SIGNATURE_TOLERANCE_SECONDS: i64 = 300;

#[rocket::post("/contact_integrations/twilio/receive", data = "<body>")]
async fn twilio_receive(
    body: Data<'_>,
    signature_header: Option<TwilioSignatureHeader<'_>>,
    host_header: Option<HostHeader<'_>>,
    state: &State<RocketState>,
) -> Status {
    let Some(raw_body) = read_body(body).await else {
        return Status::PayloadTooLarge;
    };

    // Twilio's inbound-message webhook is `application/x-www-form-urlencoded` with (among other
    // fields we don't need) `From` (the sender's E.164 number) and `Body` (the message text).
    let fields: HashMap<String, String> =
        form_urlencoded::parse(raw_body.as_bytes()).into_owned().collect();

    let mut conn = match state.pool.get() {
        Ok(conn) => conn,
        Err(_) => return Status::InternalServerError,
    };
    if let Some(signing_key) = server_twilio_config(&mut conn)
        .filter(|c| c.use_twilio_webhook_signing_key && !c.twilio_webhook_signing_key.is_empty())
        .map(|c| c.twilio_webhook_signing_key)
    {
        let (Some(signature_header), Some(host_header)) = (signature_header, host_header) else {
            return Status::Unauthorized;
        };
        let url = format!("https://{}/contact_integrations/twilio/receive", host_header.0);
        if !verify_twilio_signature(&signing_key, &url, &fields, signature_header.0) {
            log::warn!("Twilio webhook signature verification failed");
            return Status::Unauthorized;
        }
    }

    match (fields.get("From"), fields.get("Body")) {
        (Some(from), Some(text)) => handle_stop(from, text, &mut conn).await,
        _ => Status::Ok,
    }
}

#[rocket::post("/contact_integrations/telnyx/receive", data = "<body>")]
async fn telnyx_receive(
    body: Data<'_>,
    webhook_headers: Option<TelnyxWebhookHeaders<'_>>,
    state: &State<RocketState>,
) -> Status {
    let Some(raw_body) = read_body(body).await else {
        return Status::PayloadTooLarge;
    };

    let mut conn = match state.pool.get() {
        Ok(conn) => conn,
        Err(_) => return Status::InternalServerError,
    };
    if let Some(signing_key) = server_telnyx_config(&mut conn)
        .filter(|c| c.use_telnyx_webhook_signing_key && !c.telnyx_webhook_signing_key.is_empty())
        .map(|c| c.telnyx_webhook_signing_key)
    {
        let Some(webhook_headers) = webhook_headers else {
            return Status::Unauthorized;
        };
        if !verify_telnyx_signature(
            &signing_key,
            webhook_headers.timestamp,
            &raw_body,
            webhook_headers.signature,
        ) {
            log::warn!("Telnyx webhook signature verification failed");
            return Status::Unauthorized;
        }
    }

    let Ok(event) = serde_json::from_str::<Value>(&raw_body) else {
        return Status::BadRequest;
    };

    // Telnyx wraps every messaging webhook (delivery receipts included) in the same envelope --
    // `data.event_type`/`data.payload`. Only `message.received` (an inbound SMS/MMS) matters here;
    // `data.payload.from.phone_number`/`data.payload.text` carry the sender/body.
    if event.pointer("/data/event_type").and_then(Value::as_str) != Some("message.received") {
        return Status::Ok;
    }
    let payload = event.pointer("/data/payload");
    let from = payload.and_then(|p| p.pointer("/from/phone_number")).and_then(Value::as_str);
    let text = payload.and_then(|p| p.get("text")).and_then(Value::as_str);
    match (from, text) {
        (Some(from), Some(text)) => handle_stop(from, text, &mut conn).await,
        _ => Status::Ok,
    }
}

#[rocket::post("/contact_integrations/bird/receive", data = "<body>")]
async fn bird_receive(
    body: Data<'_>,
    webhook_headers: Option<BirdWebhookHeaders<'_>>,
    state: &State<RocketState>,
) -> Status {
    let Some(raw_body) = read_body(body).await else {
        return Status::PayloadTooLarge;
    };

    let mut conn = match state.pool.get() {
        Ok(conn) => conn,
        Err(_) => return Status::InternalServerError,
    };
    if let Some(signing_key) = server_bird_config(&mut conn)
        .filter(|c| c.use_bird_webhook_signing_key && !c.bird_webhook_signing_key.is_empty())
        .map(|c| c.bird_webhook_signing_key)
    {
        let Some(webhook_headers) = webhook_headers else {
            return Status::Unauthorized;
        };
        if !verify_bird_signature(
            &signing_key,
            webhook_headers.id,
            webhook_headers.timestamp,
            &raw_body,
            webhook_headers.signature,
        ) {
            log::warn!("Bird webhook signature verification failed");
            return Status::Unauthorized;
        }
    }

    let Ok(event) = serde_json::from_str::<Value>(&raw_body) else {
        return Status::BadRequest;
    };

    // Bird's webhook envelope is `{"type": "<event>", "data": {...}}`; only `sms.received` (an
    // inbound SMS) matters here. `data.from`/`data.text` mirror the plain `to`/`from`/`text` shape
    // Bird's own SMS Messages API resource uses (see `logic::bird_sync`'s own doc) -- `data.body`
    // is also accepted since Bird's exact inbound field name isn't publicly documented as of this
    // writing.
    if event.get("type").and_then(Value::as_str) != Some("sms.received") {
        return Status::Ok;
    }
    let data = event.get("data");
    let from = data.and_then(|d| d.get("from")).and_then(Value::as_str);
    let text = data
        .and_then(|d| d.get("text").or_else(|| d.get("body")))
        .and_then(Value::as_str);
    match (from, text) {
        (Some(from), Some(text)) => handle_stop(from, text, &mut conn).await,
        _ => Status::Ok,
    }
}

async fn read_body(body: Data<'_>) -> Option<String> {
    let capped_body = body.open(MAX_BODY_SIZE_MIB.mebibytes()).into_bytes().await.ok()?;
    if !capped_body.is_complete() {
        return None;
    }
    String::from_utf8(capped_body.into_inner()).ok()
}

/// Builds the string Twilio itself signs -- the exact URL it was configured to POST to, with every
/// POST parameter's key+value appended in ascending key order, no separators (see
/// https://www.twilio.com/docs/usage/webhooks/webhooks-security). `url` must match character for
/// character what's registered in the Twilio console (scheme + host + path) or every signature
/// will mismatch regardless of the Auth Token's correctness.
fn twilio_signed_string(url: &str, fields: &HashMap<String, String>) -> String {
    let mut keys: Vec<&String> = fields.keys().collect();
    keys.sort();
    let mut result = url.to_string();
    for key in keys {
        result.push_str(key);
        result.push_str(&fields[key]);
    }
    result
}

/// Verifies `signature_b64` (the `X-Twilio-Signature` header) is HMAC-SHA1(`auth_token`,
/// `twilio_signed_string(url, fields)`), base64-encoded -- Twilio's own request validation scheme.
/// No timestamp component exists in this scheme, so (unlike Telnyx/Bird below) there's no replay
/// window to enforce here.
fn verify_twilio_signature(
    auth_token: &str,
    url: &str,
    fields: &HashMap<String, String>,
    signature_b64: &str,
) -> bool {
    let Ok(provided) = base64::engine::general_purpose::STANDARD.decode(signature_b64) else {
        return false;
    };
    let signed_string = twilio_signed_string(url, fields);
    let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA1_FOR_LEGACY_USE_ONLY, auth_token.as_bytes());
    ring::hmac::verify(&key, signed_string.as_bytes(), &provided).is_ok()
}

/// Verifies Telnyx's Ed25519 signature: `signature_b64` (`telnyx-signature-ed25519`) must be a
/// valid signature by `public_key_b64` (Telnyx's account-level public key -- Mission Control
/// Portal -> Keys & Credentials -> Public Key) over `"{timestamp}|{raw_body}"` (see
/// https://developers.telnyx.com/docs/messaging/messages/receiving-webhooks). Also enforces
/// `SIGNATURE_TOLERANCE_SECONDS`, per Telnyx's own documented recommendation.
fn verify_telnyx_signature(public_key_b64: &str, timestamp: &str, raw_body: &str, signature_b64: &str) -> bool {
    if !within_tolerance(timestamp) {
        return false;
    }
    let Ok(public_key_bytes) = base64::engine::general_purpose::STANDARD.decode(public_key_b64) else {
        return false;
    };
    let Ok(signature_bytes) = base64::engine::general_purpose::STANDARD.decode(signature_b64) else {
        return false;
    };
    let signed_payload = format!("{timestamp}|{raw_body}");
    ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, &public_key_bytes)
        .verify(signed_payload.as_bytes(), &signature_bytes)
        .is_ok()
}

/// Verifies Bird's Standard Webhooks signature (see https://www.standardwebhooks.com and
/// `docs/contact_integrations.md`): `secret` (`whsec_...`) is base64-decoded (after stripping the
/// `whsec_` prefix) into an HMAC-SHA256 key, which must produce `"{id}.{timestamp}.{raw_body}"`'s
/// signature matching *any* of the space-delimited `v1,<base64>` entries in `signature_header`
/// (Standard Webhooks sends multiple during secret rotation -- any match is accepted). Also
/// enforces `SIGNATURE_TOLERANCE_SECONDS`.
fn verify_bird_signature(secret: &str, id: &str, timestamp: &str, raw_body: &str, signature_header: &str) -> bool {
    if !within_tolerance(timestamp) {
        return false;
    }
    let Some(secret_b64) = secret.strip_prefix("whsec_") else {
        return false;
    };
    let Ok(key_bytes) = base64::engine::general_purpose::STANDARD.decode(secret_b64) else {
        return false;
    };
    let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, &key_bytes);
    let signed_payload = format!("{id}.{timestamp}.{raw_body}");
    signature_header.split_whitespace().any(|entry| {
        entry
            .strip_prefix("v1,")
            .and_then(|b64| base64::engine::general_purpose::STANDARD.decode(b64).ok())
            .is_some_and(|provided| ring::hmac::verify(&key, signed_payload.as_bytes(), &provided).is_ok())
    })
}

/// Whether `unix_timestamp_str` (seconds, as sent in a `telnyx-timestamp`/`webhook-timestamp`
/// header) is within `SIGNATURE_TOLERANCE_SECONDS` of "now". An unparseable timestamp is treated
/// as out of tolerance (rejected), not skipped.
fn within_tolerance(unix_timestamp_str: &str) -> bool {
    let Ok(timestamp) = unix_timestamp_str.parse::<i64>() else {
        return false;
    };
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    (now - timestamp).abs() <= SIGNATURE_TOLERANCE_SECONDS
}

/// The literal opt-out keyword this endpoint acts on -- just "STOP" (trimmed, case-insensitive),
/// per the feature's own ask, not the full CTIA opt-out keyword list (STOP/STOPALL/UNSUBSCRIBE/
/// CANCEL/END/QUIT) carriers also recognize; see `docs/contact_integrations.md` for the note on
/// extending this if needed.
fn is_stop_keyword(text: &str) -> bool {
    text.trim().eq_ignore_ascii_case("STOP")
}

async fn handle_stop(from: &str, text: &str, conn: &mut PgPooledConnection) -> Status {
    if !is_stop_keyword(text) {
        return Status::Ok;
    }
    match revoke_sms_consent_by_phone_number(from, conn) {
        Ok(revoked_count) => {
            log::info!("SMS STOP received from {from}: revoked consent for {revoked_count} user(s)");
            Status::Ok
        }
        Err(e) => {
            log::error!("Failed to process SMS STOP from {from}: {:?}", e);
            Status::InternalServerError
        }
    }
}

// Pure crypto/parsing specs only -- no DB access, so (unlike `src/tests/stalwart_config_tests.rs`)
// these are safe to keep in this file despite it being compiled into both the lib and (via
// `main.rs`'s own duplicate module tree) the `rellm` bin.
#[cfg(test)]
mod tests {
    use super::*;
    use ring::signature::KeyPair;

    fn now_unix_timestamp_string() -> String {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            .to_string()
    }

    #[test]
    fn is_stop_keyword_is_case_insensitive_and_trims_whitespace() {
        assert!(is_stop_keyword("STOP"));
        assert!(is_stop_keyword(" stop \n"));
        assert!(is_stop_keyword("Stop"));
        assert!(!is_stop_keyword("STOP please"));
        assert!(!is_stop_keyword("start"));
    }

    #[test]
    fn twilio_signed_string_sorts_params_alphabetically_with_no_separators() {
        let mut fields = HashMap::new();
        fields.insert("To".to_string(), "+18005551212".to_string());
        fields.insert("From".to_string(), "+14158675310".to_string());
        fields.insert("Body".to_string(), "STOP".to_string());

        let signed_string = twilio_signed_string("https://example.org/receive", &fields);

        assert_eq!(
            signed_string,
            "https://example.org/receiveBodySTOPFrom+14158675310To+18005551212"
        );
    }

    #[test]
    fn twilio_signature_round_trips_and_rejects_tampering() {
        let mut fields = HashMap::new();
        fields.insert("To".to_string(), "+18005551212".to_string());
        fields.insert("From".to_string(), "+14158675310".to_string());
        fields.insert("Body".to_string(), "STOP".to_string());
        let url = "https://example.org/contact_integrations/twilio/receive";
        let auth_token = "test_auth_token";

        // Independently constructed (not via `twilio_signed_string`) so a bug in that function's
        // own sorting/concatenation would still be caught here.
        let signed_string = format!("{url}BodySTOPFrom+14158675310To+18005551212");
        let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA1_FOR_LEGACY_USE_ONLY, auth_token.as_bytes());
        let signature = ring::hmac::sign(&key, signed_string.as_bytes());
        let signature_b64 = base64::engine::general_purpose::STANDARD.encode(signature.as_ref());

        assert!(verify_twilio_signature(auth_token, url, &fields, &signature_b64));
        assert!(!verify_twilio_signature("wrong_auth_token", url, &fields, &signature_b64));
        assert!(!verify_twilio_signature(auth_token, url, &fields, "not-valid-base64!!"));
        assert!(!verify_twilio_signature(
            auth_token,
            "https://example.org/a-different-path",
            &fields,
            &signature_b64
        ));
    }

    #[test]
    fn telnyx_signature_round_trips_and_rejects_tampering() {
        let rng = ring::rand::SystemRandom::new();
        let pkcs8 = ring::signature::Ed25519KeyPair::generate_pkcs8(&rng).unwrap();
        let key_pair = ring::signature::Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap();
        let public_key_b64 =
            base64::engine::general_purpose::STANDARD.encode(key_pair.public_key().as_ref());

        let timestamp = now_unix_timestamp_string();
        let raw_body = r#"{"data":{"event_type":"message.received"}}"#;
        let signature = key_pair.sign(format!("{timestamp}|{raw_body}").as_bytes());
        let signature_b64 = base64::engine::general_purpose::STANDARD.encode(signature.as_ref());

        assert!(verify_telnyx_signature(&public_key_b64, &timestamp, raw_body, &signature_b64));
        assert!(!verify_telnyx_signature(&public_key_b64, &timestamp, "tampered body", &signature_b64));

        let other_pkcs8 = ring::signature::Ed25519KeyPair::generate_pkcs8(&rng).unwrap();
        let other_key_pair = ring::signature::Ed25519KeyPair::from_pkcs8(other_pkcs8.as_ref()).unwrap();
        let wrong_public_key_b64 =
            base64::engine::general_purpose::STANDARD.encode(other_key_pair.public_key().as_ref());
        assert!(!verify_telnyx_signature(&wrong_public_key_b64, &timestamp, raw_body, &signature_b64));
    }

    #[test]
    fn telnyx_signature_rejects_a_stale_timestamp() {
        let rng = ring::rand::SystemRandom::new();
        let pkcs8 = ring::signature::Ed25519KeyPair::generate_pkcs8(&rng).unwrap();
        let key_pair = ring::signature::Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap();
        let public_key_b64 =
            base64::engine::general_purpose::STANDARD.encode(key_pair.public_key().as_ref());

        let stale_timestamp = "1000000000"; // long past `SIGNATURE_TOLERANCE_SECONDS` of "now"
        let raw_body = "{}";
        let signature = key_pair.sign(format!("{stale_timestamp}|{raw_body}").as_bytes());
        let signature_b64 = base64::engine::general_purpose::STANDARD.encode(signature.as_ref());

        assert!(!verify_telnyx_signature(&public_key_b64, stale_timestamp, raw_body, &signature_b64));
    }

    #[test]
    fn bird_signature_round_trips_and_rejects_tampering() {
        let key_bytes = [7u8; 32];
        let secret = format!("whsec_{}", base64::engine::general_purpose::STANDARD.encode(key_bytes));
        let id = "msg_01";
        let timestamp = now_unix_timestamp_string();
        let raw_body = r#"{"type":"sms.received"}"#;

        let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, &key_bytes);
        let signature = ring::hmac::sign(&key, format!("{id}.{timestamp}.{raw_body}").as_bytes());
        let signature_header =
            format!("v1,{}", base64::engine::general_purpose::STANDARD.encode(signature.as_ref()));

        assert!(verify_bird_signature(&secret, id, &timestamp, raw_body, &signature_header));
        assert!(!verify_bird_signature(&secret, id, &timestamp, "tampered", &signature_header));
        assert!(!verify_bird_signature("whsec_" , id, &timestamp, raw_body, &signature_header));
    }

    #[test]
    fn bird_signature_accepts_any_matching_entry_during_secret_rotation() {
        let key_bytes = [3u8; 32];
        let secret = format!("whsec_{}", base64::engine::general_purpose::STANDARD.encode(key_bytes));
        let id = "msg_02";
        let timestamp = now_unix_timestamp_string();
        let raw_body = "{}";

        let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, &key_bytes);
        let signature = ring::hmac::sign(&key, format!("{id}.{timestamp}.{raw_body}").as_bytes());
        let real_entry =
            format!("v1,{}", base64::engine::general_purpose::STANDARD.encode(signature.as_ref()));
        // A second, unrelated signature (as if signed with a not-yet-rotated-out old secret) --
        // Standard Webhooks sends these space-delimited, and any match should verify.
        let signature_header = format!("v1,bm90LXRoZS1yaWdodC1zaWc= {real_entry}");

        assert!(verify_bird_signature(&secret, id, &timestamp, raw_body, &signature_header));
    }

    #[test]
    fn bird_signature_rejects_a_stale_timestamp() {
        let key_bytes = [9u8; 32];
        let secret = format!("whsec_{}", base64::engine::general_purpose::STANDARD.encode(key_bytes));
        let id = "msg_03";
        let stale_timestamp = "1000000000";
        let raw_body = "{}";

        let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, &key_bytes);
        let signature = ring::hmac::sign(&key, format!("{id}.{stale_timestamp}.{raw_body}").as_bytes());
        let signature_header =
            format!("v1,{}", base64::engine::general_purpose::STANDARD.encode(signature.as_ref()));

        assert!(!verify_bird_signature(&secret, id, stale_timestamp, raw_body, &signature_header));
    }

    #[test]
    fn within_tolerance_accepts_now_and_rejects_far_past_or_future_or_garbage() {
        assert!(within_tolerance(&now_unix_timestamp_string()));
        assert!(!within_tolerance("1000000000"));
        assert!(!within_tolerance("not-a-number"));
    }
}
