//! DB models backing `protos/market.proto`'s Rellm Marketplace -- see
//! `migrations/2026-09-16-000000_create_market_tables/up.sql`'s own header comment for the overall
//! shape (mirrors `ai_providers`/`ai_provider_grants`' two-table(+JSONB) pattern). Named
//! `Market*` (not bare `Product`/`Subscription`/`Purchase`/`Payment`) to avoid colliding with the
//! identically-named proto types these get marshaled into (see `marshaling::market_marshaling`).

use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::schema::{market_payments, market_products, market_purchases, market_subscriptions};

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(table_name = market_products)]
pub struct MarketProduct {
    pub id: i64,
    /// `PurchaseType.as_str_name()` (e.g. `"PURCHASE_TYPE_MEDIA_STORAGE"`) -- see
    /// `marshaling::market_enum_marshaling`.
    pub product_type: String,
    /// `PurchasePeriod.as_str_name()`.
    pub period: String,
    pub amount: i32,
    pub currency: i32,
    /// `{"<snake_case_variant>": {...fields...}}`, mirroring `ai_providers.configuration` -- see
    /// `marshaling::market_marshaling::product_details_to_proto`/`product_details_to_json`.
    pub details: serde_json::Value,
    pub created_at: SystemTime,
    pub delisted_at: Option<SystemTime>,
    /// Admin-set cap on how many subscriptions/purchases of this product can ever be sold -- `0`
    /// means no cap (every product created before this field existed keeps behaving exactly as
    /// before). See `sold_count`'s own doc.
    pub available_count: i32,
    /// Server-managed -- incremented when a purchase/subscription is created (the Stripe webhook,
    /// on `checkout.session.completed`) and decremented when a subscription is canceled
    /// (`CancelMarketSubscription`), which is what frees a slot for someone else to buy. Never
    /// settable directly by a client (see `rpcs::market::update_market_product`, which silently
    /// ignores any `sold_count` a request sends, same treatment as `type`/`period`).
    pub sold_count: i32,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = market_products)]
pub struct NewMarketProduct {
    pub product_type: String,
    pub period: String,
    pub amount: i32,
    pub currency: i32,
    pub details: serde_json::Value,
    /// `sold_count` isn't included here -- every new product starts at the column's own `DEFAULT 0`.
    pub available_count: i32,
}

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(table_name = market_subscriptions)]
pub struct MarketSubscription {
    pub id: i64,
    pub buyer_id: i64,
    pub product_id: i64,
    pub product_type: String,
    pub period: String,
    pub amount: i32,
    pub currency: i32,
    pub details: serde_json::Value,
    pub created_at: SystemTime,
    pub renews_at: Option<SystemTime>,
    pub canceled_at: Option<SystemTime>,
    /// Stripe bookkeeping only -- never marshaled into a proto type.
    pub stripe_customer_id: Option<String>,
    pub stripe_payment_method_id: Option<String>,
    pub service_terminated_at: Option<SystemTime>,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = market_subscriptions)]
pub struct NewMarketSubscription {
    pub buyer_id: i64,
    pub product_id: i64,
    pub product_type: String,
    pub period: String,
    pub amount: i32,
    pub currency: i32,
    pub details: serde_json::Value,
    pub renews_at: Option<SystemTime>,
    pub stripe_customer_id: Option<String>,
    pub stripe_payment_method_id: Option<String>,
}

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(table_name = market_purchases)]
pub struct MarketPurchase {
    pub id: i64,
    pub buyer_id: i64,
    pub product_id: i64,
    pub subscription_id: Option<i64>,
    pub product_type: String,
    pub details: serde_json::Value,
    pub created_at: SystemTime,
    /// Stripe bookkeeping only -- never marshaled into a proto type.
    pub stripe_checkout_session_id: Option<String>,
    pub stripe_payment_intent_id: Option<String>,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = market_purchases)]
pub struct NewMarketPurchase {
    pub buyer_id: i64,
    pub product_id: i64,
    pub subscription_id: Option<i64>,
    pub product_type: String,
    pub details: serde_json::Value,
    pub stripe_checkout_session_id: Option<String>,
    pub stripe_payment_intent_id: Option<String>,
}

/// Backs both `MarketPayment` and `MarketRefund` (positive `amount` = MarketPayment, negative =
/// MarketRefund) -- see `migrations/2026-09-16-000000_create_market_tables/up.sql`'s own header
/// comment. `method` (added by `migrations/2026-09-16-000300_add_method_to_market_payments`)
/// stores the card summary (brand/last4/expiry) marshaled into `MarketPaymentMethod`/
/// `MarketRefundMethod` -- unlike the `stripe_*` id columns here, its *contents* are meant to
/// reach a client.
#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(table_name = market_payments)]
pub struct MarketPayment {
    pub id: i64,
    pub purchase_id: i64,
    pub amount: i32,
    pub currency: i32,
    pub created_at: SystemTime,
    pub stripe_payment_intent_id: Option<String>,
    pub stripe_refund_id: Option<String>,
    pub method: Option<serde_json::Value>,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = market_payments)]
pub struct NewMarketPayment {
    pub purchase_id: i64,
    pub amount: i32,
    pub currency: i32,
    pub stripe_payment_intent_id: Option<String>,
    pub stripe_refund_id: Option<String>,
    pub method: Option<serde_json::Value>,
}

pub fn get_market_product(id: i64, conn: &mut PgPooledConnection) -> Result<MarketProduct, Status> {
    market_products::table
        .filter(market_products::id.eq(id))
        .first::<MarketProduct>(conn)
        .map_err(|_| Status::new(Code::NotFound, "product_not_found"))
}

/// Called once a purchase/subscription is actually created (`web::stripe_webhook`, on
/// `checkout.session.completed`) -- see `MarketProduct.sold_count`'s own doc. A plain SQL-side
/// `+1` (not a Rust-side read-then-write) so two near-simultaneous webhook deliveries can't lose an
/// increment to a race -- matches this feature's established "no heavier concurrency handling than
/// it needs" MVP philosophy elsewhere (see e.g. `logic::market_renewal`'s own doc).
pub fn increment_market_product_sold_count(product_id: i64, conn: &mut PgPooledConnection) {
    if let Err(e) = diesel::update(market_products::table.filter(market_products::id.eq(product_id)))
        .set(market_products::sold_count.eq(market_products::sold_count + 1))
        .execute(conn)
    {
        log::error!("Failed to increment sold_count for market product {}: {:?}", product_id, e);
    }
}

/// Called once a subscription is canceled (`rpcs::market::cancel_market_subscription`) -- frees the
/// slot it held (see `MarketProduct.sold_count`'s own doc). Clamped at `0` (`GREATEST`, SQL-side)
/// since `sold_count` is a `NOT NULL` `i32`, not a signed count that's meaningful going negative.
pub fn decrement_market_product_sold_count(product_id: i64, conn: &mut PgPooledConnection) {
    if let Err(e) = diesel::update(market_products::table.filter(market_products::id.eq(product_id)))
        .set(
            market_products::sold_count
                .eq(diesel::dsl::sql::<diesel::sql_types::Integer>("GREATEST(sold_count - 1, 0)")),
        )
        .execute(conn)
    {
        log::error!("Failed to decrement sold_count for market product {}: {:?}", product_id, e);
    }
}

/// Every `MarketProduct` -- `include_delisted` false for the public (non-admin) `GetProducts`
/// listing, true for admins (see `rpcs::market::get_products`).
pub fn get_market_products(
    include_delisted: bool,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketProduct>, Status> {
    let mut query = market_products::table.into_boxed();
    if !include_delisted {
        query = query.filter(market_products::delisted_at.is_null());
    }
    query
        .order(market_products::created_at.asc())
        .load::<MarketProduct>(conn)
        .map_err(|e| {
            log::error!("Failed to load market products: {:?}", e);
            Status::new(Code::Internal, "failed_to_load_products")
        })
}

/// Every `MarketProduct` in `ids`, in no particular order -- batched lookup used by
/// `marshaling::market_marshaling::build_subscriptions_for_buyers`.
pub fn get_market_products_by_ids(
    ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketProduct>, Status> {
    if ids.is_empty() {
        return Ok(vec![]);
    }
    market_products::table
        .filter(market_products::id.eq_any(ids))
        .load::<MarketProduct>(conn)
        .map_err(|e| {
            log::error!("Failed to load market products {:?}: {:?}", ids, e);
            Status::new(Code::Internal, "failed_to_load_products")
        })
}

/// The most recently created `stripe_customer_id` on file for `buyer_id`, if any -- looked up from
/// the buyer's own `market_subscriptions` so a repeat purchase reuses the same Stripe Customer
/// (and its saved PaymentMethod) rather than creating a new one every time. Used by
/// `rpcs::market::make_market_purchase`.
pub fn get_market_customer_id_for_buyer(
    buyer_id: i64,
    conn: &mut PgPooledConnection,
) -> Option<String> {
    market_subscriptions::table
        .filter(market_subscriptions::buyer_id.eq(buyer_id))
        .filter(market_subscriptions::stripe_customer_id.is_not_null())
        .order(market_subscriptions::created_at.desc())
        .select(market_subscriptions::stripe_customer_id)
        .first::<Option<String>>(conn)
        .ok()
        .flatten()
}

pub fn get_market_subscription(
    id: i64,
    conn: &mut PgPooledConnection,
) -> Result<MarketSubscription, Status> {
    market_subscriptions::table
        .filter(market_subscriptions::id.eq(id))
        .first::<MarketSubscription>(conn)
        .map_err(|_| Status::new(Code::NotFound, "subscription_not_found"))
}

/// Every `MarketSubscription` belonging to `buyer_id`, most recent first -- backs
/// `GetSubscriptions`' self-scoped listing (see `rpcs::market::get_subscriptions`).
pub fn get_market_subscriptions_for_buyer(
    buyer_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketSubscription>, Status> {
    market_subscriptions::table
        .filter(market_subscriptions::buyer_id.eq(buyer_id))
        .order(market_subscriptions::created_at.desc())
        .load::<MarketSubscription>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load market subscriptions for buyer {}: {:?}",
                buyer_id,
                e
            );
            Status::new(Code::Internal, "failed_to_load_subscriptions")
        })
}

/// Batched variant of `get_market_subscriptions_for_buyer` -- used by `user_marshaling` to attach
/// `User.subscriptions` across many users at once (mirrors `get_ai_provider_grants_for_grantees`).
pub fn get_market_subscriptions_for_buyers(
    buyer_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketSubscription>, Status> {
    if buyer_ids.is_empty() {
        return Ok(vec![]);
    }
    market_subscriptions::table
        .filter(market_subscriptions::buyer_id.eq_any(buyer_ids))
        .order(market_subscriptions::created_at.desc())
        .load::<MarketSubscription>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load market subscriptions for buyers {:?}: {:?}",
                buyer_ids,
                e
            );
            Status::new(Code::Internal, "failed_to_load_subscriptions")
        })
}

/// Every `MarketSubscription` of `product_type`, across every buyer, regardless of
/// canceled/renewal state -- used by `marshaling::market_marshaling::build_fulfillment_subscriptions`
/// (`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`). Unlike `get_due_market_subscriptions`
/// (which only cares about ones still eligible to renew), an admin fulfilling orders needs to see
/// every one ever made, fulfilled or not.
pub fn get_market_subscriptions_by_product_type(
    product_type: &str,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketSubscription>, Status> {
    market_subscriptions::table
        .filter(market_subscriptions::product_type.eq(product_type))
        .load::<MarketSubscription>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load market subscriptions of type {}: {:?}",
                product_type,
                e
            );
            Status::new(Code::Internal, "failed_to_load_subscriptions")
        })
}

/// Every `MarketSubscription` of `product_type` that's due to renew (`canceled_at IS NULL AND
/// renews_at <= NOW()`) -- used by `logic::market_renewal::renew_subscriptions_of_type`.
pub fn get_due_market_subscriptions(
    product_type: &str,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketSubscription>, Status> {
    market_subscriptions::table
        .filter(market_subscriptions::product_type.eq(product_type))
        .filter(market_subscriptions::canceled_at.is_null())
        .filter(market_subscriptions::renews_at.le(diesel::dsl::now))
        .order(market_subscriptions::renews_at.asc())
        .load::<MarketSubscription>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load due market subscriptions of type {}: {:?}",
                product_type,
                e
            );
            Status::new(Code::Internal, "failed_to_load_subscriptions")
        })
}

/// Every `MarketSubscription` of `product_type` that's due to have its entitlement actually
/// revoked (`canceled_at IS NOT NULL AND service_terminated_at IS NULL AND canceled_at <= NOW()
/// AND (renews_at IS NULL OR renews_at <= NOW())`) -- mirrors
/// `idx_market_subscriptions_terminable`'s filter shape (that index doesn't cover `product_type`,
/// so it's applied here as a plain additional filter, same as `get_due_market_subscriptions`
/// does). A `NULL renews_at` is treated as "already past" rather than excluded -- a canceled
/// non-recurring subscription (or any edge case that never got a `renews_at`) should still become
/// terminable rather than being stranded forever. Used by
/// `logic::market_renewal::terminate_subscriptions_of_type`.
pub fn get_terminable_market_subscriptions(
    product_type: &str,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketSubscription>, Status> {
    market_subscriptions::table
        .filter(market_subscriptions::product_type.eq(product_type))
        .filter(market_subscriptions::canceled_at.is_not_null())
        .filter(market_subscriptions::service_terminated_at.is_null())
        .filter(market_subscriptions::canceled_at.le(diesel::dsl::now))
        .filter(
            market_subscriptions::renews_at
                .is_null()
                .or(market_subscriptions::renews_at.le(diesel::dsl::now)),
        )
        .order(market_subscriptions::canceled_at.asc())
        .load::<MarketSubscription>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load terminable market subscriptions of type {}: {:?}",
                product_type,
                e
            );
            Status::new(Code::Internal, "failed_to_load_subscriptions")
        })
}

/// Every `MarketPurchase` for `subscription_id`, most recent first -- backs
/// `Subscription.billing_history`.
pub fn get_market_purchases_for_subscription(
    subscription_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketPurchase>, Status> {
    market_purchases::table
        .filter(market_purchases::subscription_id.eq(subscription_id))
        .order(market_purchases::created_at.desc())
        .load::<MarketPurchase>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load market purchases for subscription {}: {:?}",
                subscription_id,
                e
            );
            Status::new(Code::Internal, "failed_to_load_purchases")
        })
}

/// Batched variant of `get_market_purchases_for_subscription`, across every subscription in
/// `subscription_ids` at once.
pub fn get_market_purchases_for_subscriptions(
    subscription_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketPurchase>, Status> {
    if subscription_ids.is_empty() {
        return Ok(vec![]);
    }
    market_purchases::table
        .filter(market_purchases::subscription_id.eq_any(subscription_ids))
        .order(market_purchases::created_at.desc())
        .load::<MarketPurchase>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load market purchases for subscriptions {:?}: {:?}",
                subscription_ids,
                e
            );
            Status::new(Code::Internal, "failed_to_load_purchases")
        })
}

/// Every `MarketPayment`/`Refund` row for `purchase_ids` at once -- batched the same way
/// `get_market_purchases_for_subscriptions` is.
pub fn get_market_payments_for_purchases(
    purchase_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarketPayment>, Status> {
    if purchase_ids.is_empty() {
        return Ok(vec![]);
    }
    market_payments::table
        .filter(market_payments::purchase_id.eq_any(purchase_ids))
        .order(market_payments::created_at.asc())
        .load::<MarketPayment>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load market payments for purchases {:?}: {:?}",
                purchase_ids,
                e
            );
            Status::new(Code::Internal, "failed_to_load_payments")
        })
}

pub fn insert_market_subscription(
    new_subscription: &NewMarketSubscription,
    conn: &mut PgPooledConnection,
) -> Result<MarketSubscription, Status> {
    insert_into(market_subscriptions::table)
        .values(new_subscription)
        .get_result::<MarketSubscription>(conn)
        .map_err(|e| {
            log::error!("Failed to create market subscription: {:?}", e);
            Status::new(Code::Internal, "failed_to_create_subscription")
        })
}

pub fn insert_market_purchase(
    new_purchase: &NewMarketPurchase,
    conn: &mut PgPooledConnection,
) -> Result<MarketPurchase, Status> {
    insert_into(market_purchases::table)
        .values(new_purchase)
        .get_result::<MarketPurchase>(conn)
        .map_err(|e| {
            log::error!("Failed to create market purchase: {:?}", e);
            Status::new(Code::Internal, "failed_to_create_purchase")
        })
}

pub fn insert_market_payment(
    new_payment: &NewMarketPayment,
    conn: &mut PgPooledConnection,
) -> Result<MarketPayment, Status> {
    insert_into(market_payments::table)
        .values(new_payment)
        .get_result::<MarketPayment>(conn)
        .map_err(|e| {
            log::error!("Failed to create market payment: {:?}", e);
            Status::new(Code::Internal, "failed_to_create_payment")
        })
}
