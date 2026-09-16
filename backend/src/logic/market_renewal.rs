//! Shared logic behind `bin/renew_market_subscriptions.rs`, which loops over all 3 `PurchaseType`s
//! calling `renew_subscriptions_of_type` for each.

use std::time::SystemTime;

use chrono::{DateTime, Months, Utc};
use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::{fulfill_purchase, stripe_sync};
use crate::marshaling::{ToProtoId, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::schema::market_subscriptions;

/// Renews every `market_subscriptions` row of `purchase_type` that's due (`ended_at IS NULL AND
/// renews_at <= NOW()`): charges the saved Stripe Customer/PaymentMethod off-session; on success,
/// records a new `Purchase` + `Payment`, advances `renews_at` by the subscription's own `period`,
/// and re-applies the entitlement via `fulfill_purchase`; on any failure (no saved payment method,
/// unsupported currency, the charge itself failing), ends the subscription (`ended_at = now()`) --
/// no retry/grace-period logic for this MVP -- and moves on to the next one, so one bad
/// subscription never blocks the rest of the batch.
pub fn renew_subscriptions_of_type(
    purchase_type: PurchaseType,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let due = models::get_due_market_subscriptions(&purchase_type.to_string_purchase_type(), conn)?;
    if due.is_empty() {
        return Ok(());
    }

    // `usable_server_stripe_config`, not `get_server_configuration_proto(conn)?.stripe_config` --
    // see `rpcs::market::make_market_purchase`'s identical comment: the proto form always blanks
    // `stripe_secret_key`.
    let Some(stripe_config) = stripe_sync::usable_server_stripe_config(conn) else {
        log::warn!(
            "{} subscriptions due to renew, but Stripe isn't configured -- ending them all",
            due.len()
        );
        for subscription in due {
            end_subscription(subscription.id, conn);
        }
        return Ok(());
    };

    for subscription in due {
        if let Err(e) = renew_one(purchase_type, &subscription, &stripe_config, conn) {
            log::error!(
                "Failed to renew market subscription {} (buyer {}): {:?} -- ending subscription",
                subscription.id,
                subscription.buyer_id,
                e
            );
            end_subscription(subscription.id, conn);
        }
    }
    Ok(())
}

fn renew_one(
    purchase_type: PurchaseType,
    subscription: &models::MarketSubscription,
    stripe_config: &StripeConfig,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let customer_id = subscription
        .stripe_customer_id
        .clone()
        .ok_or_else(|| Status::new(tonic::Code::FailedPrecondition, "no_stripe_customer_on_file"))?;
    let payment_method_id = subscription
        .stripe_payment_method_id
        .clone()
        .ok_or_else(|| Status::new(tonic::Code::FailedPrecondition, "no_stripe_payment_method_on_file"))?;
    let currency = stripe_sync::currency_code(subscription.currency as u32)?;

    let result = stripe_sync::create_off_session_payment_intent_at(
        stripe_sync::DEFAULT_BASE_URL,
        &stripe_config.stripe_secret_key,
        stripe_sync::OffSessionPaymentIntentParams {
            customer_id,
            payment_method_id: payment_method_id.clone(),
            currency,
            amount: subscription.amount as u32,
            metadata: vec![
                ("rellm_subscription_id".to_string(), subscription.id.to_proto_id()),
                ("rellm_user_id".to_string(), subscription.buyer_id.to_proto_id()),
            ],
        },
    )?;
    // Best-effort -- a card lookup failure shouldn't fail an otherwise-successful renewal charge,
    // it just means this MarketPayment's `method` goes unset (same as any other resolution
    // failure -- see `marshaling::method_json_to_market_payment_method`'s own doc).
    let method_json = stripe_sync::get_payment_method_card_at(
        stripe_sync::DEFAULT_BASE_URL,
        &stripe_config.stripe_secret_key,
        &payment_method_id,
    )
    .ok()
    .flatten()
    .map(|card| crate::marshaling::card_details_to_json(&card));

    let purchase = models::insert_market_purchase(
        &models::NewMarketPurchase {
            buyer_id: subscription.buyer_id,
            product_id: subscription.product_id,
            subscription_id: Some(subscription.id),
            product_type: subscription.product_type.clone(),
            // Renewals repeat the same entitlement the subscription was created with.
            details: subscription.details.clone(),
            stripe_checkout_session_id: None,
            stripe_payment_intent_id: Some(result.id.clone()),
        },
        conn,
    )?;
    models::insert_market_payment(
        &models::NewMarketPayment {
            purchase_id: purchase.id,
            amount: subscription.amount,
            currency: subscription.currency,
            stripe_payment_intent_id: Some(result.id),
            stripe_refund_id: None,
            method: method_json,
        },
        conn,
    )?;

    let renews_at = advance_by_period(subscription.renews_at.unwrap_or(SystemTime::now()), &subscription.period);
    diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(subscription.id)))
        .set(market_subscriptions::renews_at.eq(renews_at))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to advance renews_at for subscription {}: {:?}", subscription.id, e);
            Status::new(tonic::Code::Internal, "failed_to_advance_renewal")
        })?;

    fulfill_purchase(purchase_type, subscription.buyer_id, &purchase.details, conn)
}

/// Also used by `web::stripe_webhook` to set the first `renews_at` on a freshly-created
/// `MarketSubscription`.
pub fn advance_by_period(from: SystemTime, period: &str) -> SystemTime {
    let months = if period.eq_ignore_ascii_case("PURCHASE_PERIOD_ANNUAL") {
        12
    } else {
        1
    };
    let from: DateTime<Utc> = from.into();
    from.checked_add_months(Months::new(months))
        .map(SystemTime::from)
        .unwrap_or_else(|| from.into())
}

fn end_subscription(subscription_id: i64, conn: &mut PgPooledConnection) {
    if let Err(e) = diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(subscription_id)))
        .set(market_subscriptions::ended_at.eq(SystemTime::now()))
        .execute(conn)
    {
        log::error!("Failed to end market subscription {}: {:?}", subscription_id, e);
    }
}
