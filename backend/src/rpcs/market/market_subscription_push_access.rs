use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;

/// Resolves + authorizes the subscription a `MarketSubscriptionPushRequest` is about: it must exist,
/// be a `PURCHASE_TYPE_RELLM_HOSTING` one (the only type with a fulfillment chat to notify about),
/// and the caller must be its buyer or an Admin -- the same people who can read its notes. Returns
/// the DB row.
pub(super) fn authorize_market_subscription_push(
    request: &MarketSubscriptionPushRequest,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<models::MarketSubscription, Status> {
    let subscription_id = request.market_subscription_id.to_db_id_or_err("market_subscription_id")?;
    let subscription = models::get_market_subscription(subscription_id, conn)?;
    if subscription.buyer_id != user.id {
        validate_permission(&Some(user), Permission::Admin)?;
    }
    let purchase_type = subscription
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);
    if purchase_type != PurchaseType::RellmHosting {
        return Err(Status::new(Code::FailedPrecondition, "not_a_rellm_hosting_subscription"));
    }
    Ok(subscription)
}
