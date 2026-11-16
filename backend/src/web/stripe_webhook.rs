//! Stripe webhook delivery endpoint (`POST /webhooks/stripe`) backing `protos/market.proto`'s
//! Rellm Marketplace -- the *only* place a `MarketPurchase`/`MarketSubscription` is ever created
//! for an initial (non-renewal) purchase. `rpcs::market::make_market_purchase` only ever creates a
//! Stripe Checkout Session and hands back its URL; nothing is recorded in this server's own DB
//! until Stripe confirms payment by calling back here with `checkout.session.completed`. Recurring
//! renewals instead go through `logic::market::market_renewal`, which creates its own `MarketPurchase`/
//! `MarketPayment` rows directly (no webhook round-trip needed there since the server itself
//! initiates those off-session charges).
//!
//! Every delivery's `Stripe-Signature` header is verified (HMAC-SHA256 over
//! `"{timestamp}.{raw_body}"`, keyed by `StripeConfig.stripe_webhook_signing_secret`, with a 5
//! minute timestamp tolerance) before the body is trusted at all -- mirrors Stripe's own
//! recommended verification scheme (https://stripe.com/docs/webhooks/signatures), implemented by
//! hand via `ring::hmac` (already a dependency) rather than pulling in the Stripe SDK crate, same
//! "plain REST, no SDK" approach as `logic::stripe_payments` itself.

use std::time::{SystemTime, UNIX_EPOCH};

use diesel::*;
use ring::hmac;
use rocket::data::ToByteUnit;
use rocket::http::Status;
use rocket::{routes, Data, Route, State};
use serde_json::Value;

use crate::db_connection::PgPooledConnection;
use crate::logic::{advance_by_period, fulfill_purchase, stripe_payments};
use crate::marshaling::{
    rellm_hosting_details_to_json, ToDbId, ToProtoPurchasePeriod, ToProtoPurchaseType,
};
use crate::models;
use crate::protos::{PurchasePeriod, PurchaseType, RellmHostingPurchaseDetails, RellmHostingSubscriptionDetails};
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
        stripe_payments::server_stripe_config(&mut conn).filter(|c| c.stripe_enabled)
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

/// Records a checkout that was refunded instead of fulfilled: a purchase (with no subscription) against the Checkout
/// Session, its payment, and the refund of it. Its existence is what makes a redelivery of the same session a no-op
/// (`process_checkout_session_completed`'s "already processed" check), so it can never grant the product later.
pub(crate) fn record_refunded_checkout(
    conn: &mut PgPooledConnection,
    buyer: &models::User,
    product: &models::MarketProduct,
    session_id: &str,
    payment_intent_id: Option<&str>,
    refund_id: &str,
    paid_amount: i32,
    paid_currency: i32,
) -> Result<(), tonic::Status> {
    let purchase = models::insert_market_purchase(
        &models::NewMarketPurchase {
            buyer_id: buyer.id,
            product_id: product.id,
            subscription_id: None,
            product_type: product.product_type.clone(),
            details: crate::logic::subdomains::subdomain_purchase_details_json_for_label(
                &crate::logic::subdomains::label_for_username(&buyer.username),
            ),
            stripe_checkout_session_id: Some(session_id.to_string()),
            stripe_payment_intent_id: payment_intent_id.map(str::to_string),
        },
        conn,
    )?;
    // What the buyer actually paid (the Checkout Session's own total), not the product's price now -- an admin can change
    // the price while a checkout is open, and the records must match the real Stripe charge.
    for (amount, stripe_refund_id) in [(paid_amount, None), (-paid_amount, Some(refund_id.to_string()))] {
        models::insert_market_payment(
            &models::NewMarketPayment {
                purchase_id: purchase.id,
                amount,
                currency: paid_currency,
                stripe_payment_intent_id: payment_intent_id.map(str::to_string),
                stripe_refund_id,
                method: None,
            },
            conn,
        )?;
    }
    Ok(())
}

/// One delivery at a time per Checkout Session: a transaction-scoped Postgres advisory lock on the session id is held for
/// the whole of `process_checkout_session_completed`, so a concurrent redelivery waits, then sees the purchase the first
/// one recorded (fulfilled *or* refunded -- see the subdomain conflict branch) and does nothing.
fn handle_checkout_session_completed(
    session: &Value,
    stripe_config: &crate::protos::StripeConfig,
    conn: &mut PgPooledConnection,
) -> Result<(), tonic::Status> {
    let session_id = session
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| tonic::Status::new(tonic::Code::InvalidArgument, "missing_session_id"))?
        .to_string();
    conn.transaction::<(), WebhookTxError, _>(|conn| {
        diesel::sql_query("SELECT pg_advisory_xact_lock(hashtext($1))")
            .bind::<diesel::sql_types::Text, _>(session_id.clone())
            .execute(conn)?;
        process_checkout_session_completed(session, stripe_config, conn)?;
        Ok(())
    })
    .map_err(|e| e.0)?;
    // A new (or released) subdomain subscription changes what its host resolves to -- forgotten only *after* the commit,
    // or a request in between could cache the old answer again.
    crate::logic::subdomains::invalidate_cache();
    Ok(())
}

fn process_checkout_session_completed(
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
        // Everything else here comes from the buyer's own checkout-time metadata (see this
        // message's own proto doc), but `additional_description` is admin-authored on the
        // product itself -- carry it over onto the purchase/subscription the same way `db_size_bytes`/
        // `object_storage_size_bytes` would be if the webhook ever started actually populating those (see
        // their own doc on why they're still always `0` here).
        let product_details: RellmHostingSubscriptionDetails =
            serde_json::from_value(product.details.clone()).unwrap_or_default();
        rellm_hosting_details_to_json(&RellmHostingPurchaseDetails {
            db_size_bytes: 0,
            object_storage_size_bytes: 0,
            additional_description: product_details.additional_description,
            domain: get_meta("rellm_hosting_domain"),
            contact_email: get_meta("rellm_hosting_contact_email"),
            additional_information: get_meta("rellm_hosting_additional_information"),
        })
    } else if purchase_type == PurchaseType::Subdomain {
        // The purchase records which label it paid for; the subscription (below) carries the live,
        // buyer-editable settings. `MakeMarketPurchase` checked the label was free when checkout started, but two
        // checkouts can race: free a label whose holder has lapsed, then check again. If it is *still* taken (someone
        // else's paid checkout got there first) nothing is created -- the unique index would refuse it anyway -- and
        // the error is logged with this session's id so the charge can be refunded by hand.
        let buyer = models::get_user(buyer_id, conn)?;
        crate::logic::subdomains::release_lapsed_subdomain_labels(
            &crate::logic::subdomains::label_for_username(&buyer.username),
            conn,
        )?;
        let label = match crate::logic::subdomains::validate_label_available(&buyer, conn) {
            Ok(label) => label,
            // The label can't be had (taken, no longer valid, or the buyer already holds one): nothing is created and
            // the charge is refunded in full. Handled -- acknowledged to Stripe -- only once the refund went
            // through; if it didn't, the error makes Stripe redeliver and we try again (the refund is idempotent).
            Err(e) if e.code() == tonic::Code::FailedPrecondition => {
                let payment_intent_id = session.get("payment_intent").and_then(|v| v.as_str());
                let refund = payment_intent_id
                    .ok_or_else(|| {
                        tonic::Status::new(tonic::Code::Internal, "subdomain_conflict_without_payment_intent")
                    })
                    .and_then(|payment_intent_id| {
                        stripe_payments::refund_payment_intent_at(
                            stripe_payments::DEFAULT_BASE_URL,
                            &stripe_config.stripe_secret_key,
                            payment_intent_id,
                            e.message(),
                        )
                    });
                // The checkout session id and the label (from the username) are identifiers, so neither is logged; the
                // user and product ids identify the order.
                return match refund {
                    Ok(refund_id) => {
                        // Record the outcome -- a purchase (no subscription) with its payment and the refund of it --
                        // before acknowledging, so a redelivery finds this checkout already processed and can never
                        // grant the subdomain later, even if the conflict has since gone away.
                        let paid_amount = session
                            .get("amount_total")
                            .and_then(|v| v.as_i64())
                            .and_then(|v| i32::try_from(v).ok())
                            .unwrap_or(product.amount);
                        let paid_currency = session
                            .get("currency")
                            .and_then(|v| v.as_str())
                            .and_then(stripe_payments::currency_numeric_code)
                            .and_then(|v| i32::try_from(v).ok())
                            .unwrap_or(product.currency);
                        record_refunded_checkout(
                            conn,
                            &buyer,
                            &product,
                            session_id,
                            payment_intent_id,
                            &refund_id,
                            paid_amount,
                            paid_currency,
                        )?;
                        log::warn!(
                            "Refunded a paid subdomain checkout for user {} on product {}: {}",
                            buyer_id,
                            product.id,
                            e.message()
                        );
                        Ok(())
                    }
                    Err(refund_error) => {
                        log::error!(
                            "Paid subdomain checkout for user {} on product {} conflicts ({}) and the automatic refund failed ({}) -- refund by hand",
                            buyer_id,
                            product.id,
                            e.message(),
                            refund_error.message()
                        );
                        Err(refund_error)
                    }
                };
            }
            Err(e) => return Err(e),
        };
        crate::logic::subdomains::subdomain_purchase_details_json_for_label(&label)
    } else {
        product.details.clone()
    };
    let subscription_details = if purchase_type == PurchaseType::Subdomain {
        let buyer = models::get_user(buyer_id, conn)?;
        crate::logic::subdomains::new_subscription_details_json(&buyer)
    } else {
        details.clone()
    };

    let customer_id = session.get("customer").and_then(|v| v.as_str()).map(str::to_string);
    let payment_intent_id = session
        .get("payment_intent")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let payment_method = payment_intent_id.as_ref().and_then(|payment_intent_id| {
        stripe_payments::get_payment_intent_payment_method_at(
            stripe_payments::DEFAULT_BASE_URL,
            &stripe_config.stripe_secret_key,
            payment_intent_id,
        )
        .ok()
    });
    let payment_method_id = payment_method.as_ref().and_then(|pm| pm.payment_method_id.clone());
    let method_json = payment_method
        .as_ref()
        .and_then(|pm| pm.card.as_ref())
        .map(crate::marshaling::card_details_to_json);

    // Every purchase gets a `MarketSubscription`, including a `PURCHASE_PERIOD_INDEFINITE`
    // one-time purchase -- see `PurchasePeriod.PURCHASE_PERIOD_INDEFINITE`'s own doc: it just
    // never gets a `renews_at`, so it's never picked up by `renew_market_subscriptions.rs`'s own
    // "due" query, but it's still cancelable and still carries the same per-type fulfillment
    // tracking every other subscription does.
    let renews_at = if period == PurchasePeriod::Indefinite {
        None
    } else {
        Some(advance_by_period(SystemTime::now(), &product.period))
    };
    // One transaction for everything this checkout records -- subscription, purchase, payment, the sold slot and
    // the entitlement -- so a failure part-way leaves nothing behind and Stripe's retry starts clean (a half-written
    // subscription would otherwise hold its subdomain label against its own retry).
    conn.transaction::<(), WebhookTxError, _>(|conn| {
        let subscription = models::insert_market_subscription(
            &models::NewMarketSubscription {
                buyer_id,
                product_id: product.id,
                product_type: product.product_type.clone(),
                period: product.period.clone(),
                amount: product.amount,
                currency: product.currency,
                details: subscription_details,
                renews_at,
                stripe_customer_id: customer_id.clone(),
                stripe_payment_method_id: payment_method_id.clone(),
            },
            conn,
        )?;
        let subscription_id = Some(subscription.id);

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
                method: method_json,
            },
            conn,
        )?;

        // A newly-fulfilled purchase/subscription consumes one of `product.available_count`'s slots --
        // see `MarketProduct.sold_count`'s own doc.
        models::increment_market_product_sold_count(product.id, conn);

        fulfill_purchase(purchase_type, buyer_id, &purchase.details, conn)?;
        Ok(())
    })
    .map_err(|e| e.0)?;
    Ok(())
}

/// `conn.transaction`'s error type must absorb Diesel's own errors (it rolls back through them) while carrying the
/// `Status` the fulfillment steps return.
struct WebhookTxError(tonic::Status);

impl From<diesel::result::Error> for WebhookTxError {
    fn from(error: diesel::result::Error) -> Self {
        log::error!("Stripe checkout transaction failed: {:?}", error);
        WebhookTxError(tonic::Status::new(tonic::Code::Internal, "db_error"))
    }
}

impl From<tonic::Status> for WebhookTxError {
    fn from(status: tonic::Status) -> Self {
        WebhookTxError(status)
    }
}
