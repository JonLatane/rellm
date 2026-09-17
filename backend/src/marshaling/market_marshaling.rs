//! Marshaling for `protos/market.proto`'s Rellm Marketplace types (`MarketProduct`/
//! `MarketSubscription`/`MarketPurchase`/`MarketPayment`/`MarketRefund`) -- mirrors
//! `ai_provider_marshaling`'s `MarshalableX(db_row, ...related)` wrapper pattern.
//!
//! `details` JSONB columns store only the inner detail message's own fields (no wrapping oneof
//! tag) -- which concrete message to (de)serialize into is always already known from the row's own
//! `product_type` column, so there's no need to tag the JSON itself (unlike
//! `ai_providers.configuration`, which has no separate "provider kind" column to fall back on).

use std::collections::HashMap;

use tonic::Status;

use super::{
    ToProtoAuthor, ToProtoId, ToProtoPurchasePeriod, ToProtoPurchaseType, ToProtoTime, ToStringPurchaseType,
};
use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::*;

#[derive(Debug, Clone)]
pub struct MarshalableMarketProduct(pub models::MarketProduct);

pub trait ToProtoMarshalableMarketProduct {
    fn to_proto(&self) -> MarketProduct;
}
impl ToProtoMarshalableMarketProduct for MarshalableMarketProduct {
    fn to_proto(&self) -> MarketProduct {
        let product = &self.0;
        let purchase_type = product
            .product_type
            .to_owned()
            .to_proto_purchase_type()
            .unwrap_or(PurchaseType::MediaStorage);
        MarketProduct {
            id: product.id.to_proto_id(),
            r#type: purchase_type as i32,
            period: product
                .period
                .to_owned()
                .to_proto_purchase_period()
                .unwrap_or(PurchasePeriod::Indefinite) as i32,
            amount: product.amount as u32,
            currency: product.currency as u32,
            created_at: Some(product.created_at.to_proto()),
            delisted_at: product.delisted_at.map(|t| t.to_proto()),
            details: product_details_to_proto(purchase_type, &product.details),
            available_count: product.available_count as u32,
            sold_count: product.sold_count as u32,
        }
    }
}

#[derive(Debug, Clone)]
pub struct MarshalableMarketPurchase(
    pub models::MarketPurchase,
    pub models::Author,
    pub models::MarketProduct,
    pub Vec<models::MarketPayment>,
);

pub trait ToProtoMarshalableMarketPurchase {
    fn to_proto(&self) -> MarketPurchase;
}
impl ToProtoMarshalableMarketPurchase for MarshalableMarketPurchase {
    fn to_proto(&self) -> MarketPurchase {
        let purchase = &self.0;
        let buyer = &self.1;
        let product = &self.2;
        let payment_rows = &self.3;
        let purchase_type = purchase
            .product_type
            .to_owned()
            .to_proto_purchase_type()
            .unwrap_or(PurchaseType::MediaStorage);

        let market_payments: Vec<MarketPayment> = payment_rows
            .iter()
            .filter(|p| p.amount >= 0)
            .map(|p| MarketPayment {
                amount: p.amount as u32,
                currency: p.currency as u32,
                market_purchase_id: purchase.id.to_proto_id(),
                method: method_json_to_market_payment_method(&p.method),
                created_at: Some(p.created_at.to_proto()),
            })
            .collect();
        let market_refunds: Vec<MarketRefund> = payment_rows
            .iter()
            .filter(|p| p.amount < 0)
            .map(|p| MarketRefund {
                amount: (-p.amount) as u32,
                currency: p.currency as u32,
                market_purchase_id: purchase.id.to_proto_id(),
                method: method_json_to_market_refund_method(&p.method),
                created_at: Some(p.created_at.to_proto()),
            })
            .collect();

        MarketPurchase {
            id: purchase.id.to_proto_id(),
            buyer: Some(buyer.to_proto(None)),
            r#type: purchase_type as i32,
            market_product: Some(MarshalableMarketProduct(product.clone()).to_proto()),
            // Left unset here -- see this module's own doc and
            // `build_subscriptions_for_buyers`, which is the only place a `MarketPurchase` ever
            // ends up embedded inside a `MarketSubscription.billing_history` (this constructor is
            // also used standalone, e.g. by the Stripe webhook, where there's no need for it
            // either).
            market_subscription: None,
            market_payments,
            market_refunds,
            details: purchase_details_to_proto(purchase_type, &purchase.details),
            created_at: Some(purchase.created_at.to_proto()),
        }
    }
}

#[derive(Debug, Clone)]
pub struct MarshalableMarketSubscription(
    pub models::MarketSubscription,
    pub models::Author,
    pub models::MarketProduct,
    pub Vec<MarketPurchase>,
);

pub trait ToProtoMarshalableMarketSubscription {
    fn to_proto(&self) -> MarketSubscription;
}
impl ToProtoMarshalableMarketSubscription for MarshalableMarketSubscription {
    fn to_proto(&self) -> MarketSubscription {
        let subscription = &self.0;
        let buyer = &self.1;
        let product = &self.2;
        let billing_history = &self.3;
        let purchase_type = subscription
            .product_type
            .to_owned()
            .to_proto_purchase_type()
            .unwrap_or(PurchaseType::MediaStorage);

        MarketSubscription {
            id: subscription.id.to_proto_id(),
            buyer: Some(buyer.to_proto(None)),
            r#type: purchase_type as i32,
            period: subscription
                .period
                .to_owned()
                .to_proto_purchase_period()
                .unwrap_or(PurchasePeriod::Indefinite) as i32,
            amount: subscription.amount as u32,
            currency: subscription.currency as u32,
            market_product: Some(MarshalableMarketProduct(product.clone()).to_proto()),
            billing_history: billing_history.clone(),
            details: subscription_details_to_proto(purchase_type, &subscription.details),
            created_at: Some(subscription.created_at.to_proto()),
            renews_at: subscription.renews_at.map(|t| t.to_proto()),
            canceled_at: subscription.canceled_at.map(|t| t.to_proto()),
            service_terminated_at: subscription.service_terminated_at.map(|t| t.to_proto()),
        }
    }
}

/// Builds every `MarketSubscription` (with `billing_history` populated) for each of `buyer_ids` --
/// batched in a fixed number of queries regardless of how many buyers, mirroring
/// `ai_provider_marshaling::build_ai_models_for_users`. Used by both
/// `rpcs::market::get_market_subscriptions` (single-buyer slice) and `user_marshaling`'s
/// `User.market_subscriptions` attachment (many buyers at once, gated self-or-Admin the same way
/// `ai_models`/`sync_sources` are).
pub fn build_subscriptions_for_buyers(
    buyer_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<HashMap<i64, Vec<MarketSubscription>>, Status> {
    let mut result: HashMap<i64, Vec<MarketSubscription>> =
        buyer_ids.iter().map(|id| (*id, vec![])).collect();
    if buyer_ids.is_empty() {
        return Ok(result);
    }

    let subscriptions = models::get_market_subscriptions_for_buyers(buyer_ids, conn)?;
    for (buyer_id, subscription) in build_subscriptions(subscriptions, conn)? {
        result.entry(buyer_id).or_default().push(subscription);
    }
    Ok(result)
}

/// Every `PURCHASE_TYPE_RELLM_HOSTING` `MarketSubscription` across *every* buyer, oldest first --
/// backs `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN` (`/market/fulfillment`). Unlike
/// `build_subscriptions_for_buyers`, this isn't scoped to any particular buyer -- Rellm hosting
/// needs manual setup (see `RellmHostingSubscriptionDetails.fulfilled`'s own doc), so the admin
/// fulfilling orders needs to see everyone's.
pub fn build_fulfillment_subscriptions(conn: &mut PgPooledConnection) -> Result<Vec<MarketSubscription>, Status> {
    let subscriptions = models::get_market_subscriptions_by_product_type(
        &PurchaseType::RellmHosting.to_string_purchase_type(),
        conn,
    )?;
    let mut result: Vec<(i64, MarketSubscription)> = build_subscriptions(subscriptions, conn)?;
    result.sort_by(|(_, a), (_, b)| {
        a.created_at
            .as_ref()
            .map(|t| (t.seconds, t.nanos))
            .cmp(&b.created_at.as_ref().map(|t| (t.seconds, t.nanos)))
    });
    Ok(result.into_iter().map(|(_, s)| s).collect())
}

/// Shared by `build_subscriptions_for_buyers`/`build_fulfillment_subscriptions` -- everything past
/// "I already have the `market_subscriptions` rows I care about" (loading their products/
/// purchases/payments/buyers and assembling each into a full `MarketSubscription` proto, with
/// `billing_history` populated), batched in a fixed number of queries regardless of row count,
/// mirroring `ai_provider_marshaling::build_ai_models_for_users`. Returns `(buyer_id, proto)` pairs
/// rather than a `HashMap` itself, since the two callers group them differently (by buyer vs. not
/// at all).
fn build_subscriptions(
    subscriptions: Vec<models::MarketSubscription>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<(i64, MarketSubscription)>, Status> {
    if subscriptions.is_empty() {
        return Ok(vec![]);
    }
    let subscription_ids: Vec<i64> = subscriptions.iter().map(|s| s.id).collect();
    let mut product_ids: Vec<i64> = subscriptions.iter().map(|s| s.product_id).collect();
    product_ids.sort_unstable();
    product_ids.dedup();
    let mut buyer_ids: Vec<i64> = subscriptions.iter().map(|s| s.buyer_id).collect();
    buyer_ids.sort_unstable();
    buyer_ids.dedup();

    let products_by_id: HashMap<i64, models::MarketProduct> =
        models::get_market_products_by_ids(&product_ids, conn)?
            .into_iter()
            .map(|p| (p.id, p))
            .collect();
    let purchases = models::get_market_purchases_for_subscriptions(&subscription_ids, conn)?;
    let purchase_ids: Vec<i64> = purchases.iter().map(|p| p.id).collect();
    let payments = models::get_market_payments_for_purchases(&purchase_ids, conn)?;
    let mut payments_by_purchase_id: HashMap<i64, Vec<models::MarketPayment>> = HashMap::new();
    for payment in payments {
        payments_by_purchase_id
            .entry(payment.purchase_id)
            .or_default()
            .push(payment);
    }

    let authors_by_id: HashMap<i64, models::Author> = models::get_authors(&buyer_ids, conn)
        .into_iter()
        .map(|a| (a.id, a))
        .collect();

    let mut billing_history_by_subscription_id: HashMap<i64, Vec<MarketPurchase>> = HashMap::new();
    for purchase in purchases {
        let Some(subscription_id) = purchase.subscription_id else {
            continue;
        };
        let Some(product) = products_by_id.get(&purchase.product_id) else {
            continue;
        };
        let Some(buyer) = authors_by_id.get(&purchase.buyer_id) else {
            continue;
        };
        let payment_rows = payments_by_purchase_id
            .remove(&purchase.id)
            .unwrap_or_default();
        let purchase_proto =
            MarshalableMarketPurchase(purchase.clone(), buyer.clone(), product.clone(), payment_rows)
                .to_proto();
        billing_history_by_subscription_id
            .entry(subscription_id)
            .or_default()
            .push(purchase_proto);
    }

    let mut result: Vec<(i64, MarketSubscription)> = Vec::with_capacity(subscriptions.len());
    for subscription in subscriptions {
        let Some(product) = products_by_id.get(&subscription.product_id) else {
            continue;
        };
        let Some(buyer) = authors_by_id.get(&subscription.buyer_id) else {
            continue;
        };
        let billing_history = billing_history_by_subscription_id
            .remove(&subscription.id)
            .unwrap_or_default();
        let buyer_id = subscription.buyer_id;
        let subscription_proto = MarshalableMarketSubscription(
            subscription,
            buyer.clone(),
            product.clone(),
            billing_history,
        )
        .to_proto();
        result.push((buyer_id, subscription_proto));
    }

    Ok(result)
}

/// The reverse of `product_details_to_proto` -- extracts the inner detail message's own fields
/// (no oneof tag) from a `CreateMarketProduct`/`UpdateMarketProduct` request's
/// `MarketProduct.details`.
pub fn product_details_to_json(details: &Option<market_product::Details>) -> serde_json::Value {
    match details {
        Some(market_product::Details::MediaStorageSubscriptionDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        Some(market_product::Details::AiGrantSubscriptionDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        Some(market_product::Details::RellmHostingSubscriptionDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        Some(market_product::Details::PermissionsAccessSubscriptionDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        None => serde_json::json!({}),
    }
}

/// Builds a `MarketProduct.details` oneof from a `market_products.details` JSON blob -- which
/// concrete message to deserialize into is decided by `purchase_type` (the row's own
/// `product_type` column), not anything in the JSON itself (see this module's own doc).
pub fn product_details_to_proto(
    purchase_type: PurchaseType,
    details: &serde_json::Value,
) -> Option<market_product::Details> {
    match purchase_type {
        PurchaseType::MediaStorage => serde_json::from_value::<MediaStorageSubscriptionDetails>(details.clone())
            .ok()
            .map(market_product::Details::MediaStorageSubscriptionDetails),
        PurchaseType::AiGrants => serde_json::from_value::<AiGrantSubscriptionDetails>(details.clone())
            .ok()
            .map(market_product::Details::AiGrantSubscriptionDetails),
        PurchaseType::RellmHosting => serde_json::from_value::<RellmHostingSubscriptionDetails>(details.clone())
            .ok()
            .map(market_product::Details::RellmHostingSubscriptionDetails),
        PurchaseType::PermissionsAccess => {
            serde_json::from_value::<PermissionsAccessSubscriptionDetails>(details.clone())
                .ok()
                .map(market_product::Details::PermissionsAccessSubscriptionDetails)
        }
    }
}

/// `market_subscription::Details` counterpart of `product_details_to_proto` -- same field shapes
/// (the `*SubscriptionDetails` messages are shared between `MarketProduct.details` and
/// `MarketSubscription.details`), just a structurally-identical-but-distinct Rust oneof type.
pub fn subscription_details_to_proto(
    purchase_type: PurchaseType,
    details: &serde_json::Value,
) -> Option<market_subscription::Details> {
    match purchase_type {
        PurchaseType::MediaStorage => serde_json::from_value::<MediaStorageSubscriptionDetails>(details.clone())
            .ok()
            .map(market_subscription::Details::MediaStorageSubscriptionDetails),
        PurchaseType::AiGrants => serde_json::from_value::<AiGrantSubscriptionDetails>(details.clone())
            .ok()
            .map(market_subscription::Details::AiGrantSubscriptionDetails),
        PurchaseType::RellmHosting => serde_json::from_value::<RellmHostingSubscriptionDetails>(details.clone())
            .ok()
            .map(market_subscription::Details::RellmHostingSubscriptionDetails),
        PurchaseType::PermissionsAccess => {
            serde_json::from_value::<PermissionsAccessSubscriptionDetails>(details.clone())
                .ok()
                .map(market_subscription::Details::PermissionsAccessSubscriptionDetails)
        }
    }
}

/// `market_purchase::Details` counterpart -- `MarketPurchase.details` uses its own, separate
/// `MediaStoragePurchaseDetails`/`AiGrantPurchaseDetails`/`RellmHostingPurchaseDetails`/
/// `PermissionsAccessPurchaseDetails` messages (field-for-field identical to the
/// `*SubscriptionDetails` ones, just named differently).
pub fn purchase_details_to_json(details: &Option<market_purchase::Details>) -> serde_json::Value {
    match details {
        Some(market_purchase::Details::MediaStoragePurchaseDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        Some(market_purchase::Details::AiGrantPurchaseDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        Some(market_purchase::Details::RellmHostingPurchaseDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        Some(market_purchase::Details::PermissionsAccessPurchaseDetails(d)) => {
            serde_json::to_value(d).unwrap_or_default()
        }
        None => serde_json::json!({}),
    }
}

pub fn purchase_details_to_proto(
    purchase_type: PurchaseType,
    details: &serde_json::Value,
) -> Option<market_purchase::Details> {
    match purchase_type {
        PurchaseType::MediaStorage => serde_json::from_value::<MediaStoragePurchaseDetails>(details.clone())
            .ok()
            .map(market_purchase::Details::MediaStoragePurchaseDetails),
        PurchaseType::AiGrants => serde_json::from_value::<AiGrantPurchaseDetails>(details.clone())
            .ok()
            .map(market_purchase::Details::AiGrantPurchaseDetails),
        PurchaseType::RellmHosting => serde_json::from_value::<RellmHostingPurchaseDetails>(details.clone())
            .ok()
            .map(market_purchase::Details::RellmHostingPurchaseDetails),
        PurchaseType::PermissionsAccess => {
            serde_json::from_value::<PermissionsAccessPurchaseDetails>(details.clone())
                .ok()
                .map(market_purchase::Details::PermissionsAccessPurchaseDetails)
        }
    }
}

/// Builds the `market_purchases.details`/`market_subscriptions.details` JSON blob straight from a
/// [`RellmHostingPurchaseDetails`] supplied on `MakeMarketPurchaseRequest` -- used when fulfilling
/// a `PURCHASE_TYPE_RELLM_HOSTING` purchase, where the buyer's own request (not the
/// `MarketProduct`'s defaults) carries the actual domain/contact/notes.
pub fn rellm_hosting_details_to_json(details: &RellmHostingPurchaseDetails) -> serde_json::Value {
    serde_json::to_value(details).unwrap_or_default()
}

/// Serializes a `logic::stripe_sync::CardDetails` into `market_payments.method`'s JSON shape
/// (field-for-field the same as `MarketPaymentMethod`/`MarketRefundMethod`, so the `method_json_to_*`
/// functions below can deserialize straight into either).
pub fn card_details_to_json(card: &crate::logic::stripe_sync::CardDetails) -> serde_json::Value {
    serde_json::json!({
        "card_brand": card.brand,
        "card_last4": card.last4,
        "card_exp_month": card.exp_month,
        "card_exp_year": card.exp_year,
    })
}

/// `market_payments.method` -> `MarketPaymentMethod`, for a `MarketPayment` (positive-`amount`
/// row). `None` whenever the row predates this column, or the charge's payment method couldn't be
/// resolved from Stripe at the time -- never an error, just an absent display detail.
pub fn method_json_to_market_payment_method(
    method: &Option<serde_json::Value>,
) -> Option<MarketPaymentMethod> {
    method.as_ref().and_then(|m| serde_json::from_value(m.clone()).ok())
}

/// `market_payments.method` -> `MarketRefundMethod`, for a `MarketRefund` (negative-`amount` row)
/// -- same JSON shape as `method_json_to_market_payment_method`, just the distinct proto type
/// `MarketRefund.method` actually needs.
pub fn method_json_to_market_refund_method(
    method: &Option<serde_json::Value>,
) -> Option<MarketRefundMethod> {
    method.as_ref().and_then(|m| serde_json::from_value(m.clone()).ok())
}

#[cfg(test)]
mod method_json_tests {
    use super::*;
    use crate::logic::stripe_sync::CardDetails;

    fn a_card() -> CardDetails {
        CardDetails {
            brand: "visa".to_string(),
            last4: "4242".to_string(),
            exp_month: 12,
            exp_year: 2030,
        }
    }

    #[test]
    fn card_details_round_trip_to_market_payment_method() {
        let json = card_details_to_json(&a_card());
        let method = method_json_to_market_payment_method(&Some(json)).unwrap();
        assert_eq!(
            method,
            MarketPaymentMethod {
                card_brand: "visa".to_string(),
                card_last4: "4242".to_string(),
                card_exp_month: 12,
                card_exp_year: 2030,
            }
        );
    }

    #[test]
    fn card_details_round_trip_to_market_refund_method() {
        let json = card_details_to_json(&a_card());
        let method = method_json_to_market_refund_method(&Some(json)).unwrap();
        assert_eq!(
            method,
            MarketRefundMethod {
                card_brand: "visa".to_string(),
                card_last4: "4242".to_string(),
                card_exp_month: 12,
                card_exp_year: 2030,
            }
        );
    }

    #[test]
    fn absent_method_json_yields_none_rather_than_erroring() {
        assert_eq!(method_json_to_market_payment_method(&None), None);
        assert_eq!(method_json_to_market_refund_method(&None), None);
    }
}
