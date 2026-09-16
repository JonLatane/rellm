//! Stripe webhook delivery endpoint (`POST /webhooks/stripe`) backing `protos/market.proto`'s
//! Rellm Marketplace -- the *only* place a `MarketPurchase`/`MarketSubscription` is ever created
//! for an initial (non-renewal) purchase. `rpcs::market::make_market_purchase` only ever creates a
//! Stripe Checkout Session and hands back its URL; nothing is recorded in this server's own DB
//! until Stripe confirms payment by calling back here with `checkout.session.completed`. Recurring
//! renewals instead go through `logic::market_renewal`, which creates its own `MarketPurchase`/
//! `MarketPayment` rows directly (no webhook round-trip needed there since the server itself
//! initiates those off-session charges).
//!
//! Every delivery's `Stripe-Signature` header is verified (HMAC-SHA256 over
//! `"{timestamp}.{raw_body}"`, keyed by `StripeConfig.stripe_webhook_signing_secret`, with a 5
//! minute timestamp tolerance) before the body is trusted at all -- mirrors Stripe's own
//! recommended verification scheme (https://stripe.com/docs/webhooks/signatures), implemented by
//! hand via `ring::hmac` (already a dependency) rather than pulling in the Stripe SDK crate, same
//! "plain REST, no SDK" approach as `logic::stripe_sync` itself.

use std::time::{SystemTime, UNIX_EPOCH};

use diesel::*;
use ring::hmac;
use rocket::data::ToByteUnit;
use rocket::http::Status;
use rocket::{routes, Data, Route, State};
use serde_json::Value;

use crate::db_connection::PgPooledConnection;
use crate::logic::{advance_by_period, fulfill_purchase, stripe_sync};
use crate::marshaling::{
    rellm_hosting_details_to_json, ToDbId, ToProtoPurchasePeriod, ToProtoPurchaseType,
};
use crate::models;
use crate::protos::{PurchasePeriod, PurchaseType, RellmHostingPurchaseDetails};
use crate::schema::market_purchases;
use crate::web::headers::StripeSignatureHeader;
use crate::web::RocketState;

lazy_static! {
    pub static ref STRIPE_WEBHOOK_ENDPOINTS: Vec<Route> = routes![stripe_webhook];
}

/// A `Stripe-Signature` older/newer than this many seconds from "now" is rejected outright, even
/// if the HMAC itself matches -- guards against a captured-and-replayed delivery. Stripe's own
/// libraries default to the same 5 minute tolerance.
const SIGNATURE_TOLERANCE_SECONDS: i64 = 300;
const MAX_BODY_SIZE_MIB: u64 = 1;

#[rocket::post("/webhooks/stripe", data = "<body>")]
async fn stripe_webhook(
    body: Data<'_>,
    signature_header: Option<StripeSignatureHeader<'_>>,
    state: &State<RocketState>,
) -> Status {
    let capped_body = match body.open(MAX_BODY_SIZE_MIB.mebibytes()).into_bytes().await {
        Ok(b) if b.is_complete() => b.into_inner(),
        _ => return Status::PayloadTooLarge,
    };
    let raw_body = match String::from_utf8(capped_body) {
        Ok(s) => s,
        Err(_) => return Status::BadRequest,
    };

    let mut conn = match state.pool.get() {
        Ok(conn) => conn,
        Err(_) => return Status::InternalServerError,
    };
    let Some(stripe_config) =
        stripe_sync::server_stripe_config(&mut conn).filter(|c| c.stripe_enabled)
    else {
        log::warn!("Received Stripe webhook, but Stripe isn't configured/enabled -- ignoring");
        return Status::ServiceUnavailable;
    };

    let Some(signature_header) = signature_header else {
        return Status::Unauthorized;
    };
    if !verify_signature(
        signature_header.0,
        &raw_body,
        &stripe_config.stripe_webhook_signing_secret,
    ) {
        log::warn!("Stripe webhook signature verification failed");
        return Status::Unauthorized;
    }

    let event: Value = match serde_json::from_str(&raw_body) {
        Ok(v) => v,
        Err(_) => return Status::BadRequest,
    };
    let event_type = event.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if event_type != "checkout.session.completed" {
        // Nothing else is subscribed to on this endpoint (see this module's own doc) -- 200 so
        // Stripe doesn't keep retrying deliveries this server was never going to act on.
        return Status::Ok;
    }
    let Some(session) = event.pointer("/data/object") else {
        return Status::BadRequest;
    };

    match handle_checkout_session_completed(session, &stripe_config, &mut conn) {
        Ok(()) => Status::Ok,
        Err(e) => {
            log::error!("Failed to handle Stripe checkout.session.completed: {:?}", e);
            Status::InternalServerError
        }
    }
}

fn verify_signature(header_value: &str, raw_body: &str, signing_secret: &str) -> bool {
    let mut timestamp: Option<i64> = None;
    let mut v1_signature: Option<&str> = None;
    for part in header_value.split(',') {
        let mut kv = part.splitn(2, '=');
        match (kv.next(), kv.next()) {
            (Some("t"), Some(v)) => timestamp = v.parse::<i64>().ok(),
            (Some("v1"), Some(v)) => v1_signature = Some(v),
            _ => {}
        }
    }
    let (Some(timestamp), Some(v1_signature)) = (timestamp, v1_signature) else {
        return false;
    };
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    if (now - timestamp).abs() > SIGNATURE_TOLERANCE_SECONDS {
        return false;
    }
    let Some(signature_bytes) = decode_hex(v1_signature) else {
        return false;
    };

    let key = hmac::Key::new(hmac::HMAC_SHA256, signing_secret.as_bytes());
    let signed_payload = format!("{timestamp}.{raw_body}");
    hmac::verify(&key, signed_payload.as_bytes(), &signature_bytes).is_ok()
}

fn decode_hex(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

fn handle_checkout_session_completed(
    session: &Value,
    stripe_config: &crate::protos::StripeConfig,
    conn: &mut PgPooledConnection,
) -> Result<(), tonic::Status> {
    let session_id = session
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| tonic::Status::new(tonic::Code::InvalidArgument, "missing_session_id"))?;

    // Idempotency: Stripe may redeliver the same event -- a `MarketPurchase` already recorded
    // against this Checkout Session means it was already fulfilled.
    let already_processed = market_purchases::table
        .filter(market_purchases::stripe_checkout_session_id.eq(session_id))
        .first::<models::MarketPurchase>(conn)
        .optional()
        .map_err(|e| {
            log::error!("Failed to check for existing market purchase: {:?}", e);
            tonic::Status::new(tonic::Code::Internal, "db_error")
        })?
        .is_some();
    if already_processed {
        log::info!("Stripe checkout session {} already processed -- skipping", session_id);
        return Ok(());
    }

    let metadata = session.get("metadata").cloned().unwrap_or_default();
    let get_meta = |key: &str| -> String {
        metadata
            .get(key)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let buyer_id = get_meta("rellm_user_id").to_db_id_or_err("rellm_user_id")?;
    let product_id = get_meta("rellm_market_product_id").to_db_id_or_err("rellm_market_product_id")?;
    let product = models::get_market_product(product_id, conn)?;
    let purchase_type = product
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);
    let period = product
        .period
        .to_owned()
        .to_proto_purchase_period()
        .unwrap_or(PurchasePeriod::Indefinite);

    let details = if purchase_type == PurchaseType::RellmHosting {
        rellm_hosting_details_to_json(&RellmHostingPurchaseDetails {
            db_size_bytes: 0,
            minio_size_bytes: 0,
            domain: get_meta("rellm_hosting_domain"),
            contact_email: get_meta("rellm_hosting_contact_email"),
            additional_information: get_meta("rellm_hosting_additional_information"),
        })
    } else {
        product.details.clone()
    };

    let customer_id = session.get("customer").and_then(|v| v.as_str()).map(str::to_string);
    let payment_intent_id = session
        .get("payment_intent")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let payment_method_id = payment_intent_id
        .as_ref()
        .and_then(|payment_intent_id| {
            stripe_sync::get_payment_intent_payment_method_at(
                stripe_sync::DEFAULT_BASE_URL,
                &stripe_config.stripe_secret_key,
                payment_intent_id,
            )
            .ok()
            .flatten()
        });

    // `PURCHASE_PERIOD_INDEFINITE` products never create a `MarketSubscription` -- see
    // `PurchasePeriod.PURCHASE_PERIOD_INDEFINITE`'s own doc.
    let subscription_id = if period == PurchasePeriod::Indefinite {
        None
    } else {
        let renews_at = advance_by_period(SystemTime::now(), &product.period);
        let subscription = models::insert_market_subscription(
            &models::NewMarketSubscription {
                buyer_id,
                product_id: product.id,
                product_type: product.product_type.clone(),
                period: product.period.clone(),
                amount: product.amount,
                currency: product.currency,
                details: details.clone(),
                renews_at: Some(renews_at),
                stripe_customer_id: customer_id.clone(),
                stripe_payment_method_id: payment_method_id.clone(),
            },
            conn,
        )?;
        Some(subscription.id)
    };

    let purchase = models::insert_market_purchase(
        &models::NewMarketPurchase {
            buyer_id,
            product_id: product.id,
            subscription_id,
            product_type: product.product_type.clone(),
            details,
            stripe_checkout_session_id: Some(session_id.to_string()),
            stripe_payment_intent_id: payment_intent_id.clone(),
        },
        conn,
    )?;
    models::insert_market_payment(
        &models::NewMarketPayment {
            purchase_id: purchase.id,
            amount: product.amount,
            currency: product.currency,
            stripe_payment_intent_id: payment_intent_id,
            stripe_refund_id: None,
        },
        conn,
    )?;

    fulfill_purchase(purchase_type, buyer_id, &purchase.details, conn)
}
