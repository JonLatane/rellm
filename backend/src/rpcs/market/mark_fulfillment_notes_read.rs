use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::market_subscriptions;

/// *Authenticated*, buyer only -- see `RellmHostingSubscriptionDetails.notes_last_read`: the marker
/// is the buyer's own, so not even an Admin may move it. Stamps it with now (server clock) and
/// leaves everything else in `details` (notes, status) untouched. Idempotent.
pub fn mark_fulfillment_notes_read(
    request: MarkFulfillmentNotesReadRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MarketSubscription, Status> {
    let subscription_id = request.market_subscription_id.to_db_id_or_err("market_subscription_id")?;
    let existing = models::get_market_subscription(subscription_id, conn)?;
    if existing.buyer_id != current_user.id {
        return Err(Status::new(Code::PermissionDenied, "only_the_buyer_can_mark_notes_read"));
    }
    let purchase_type = existing
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);
    if purchase_type != PurchaseType::RellmHosting {
        return Err(Status::new(Code::FailedPrecondition, "not_a_rellm_hosting_subscription"));
    }
    let mut details: RellmHostingSubscriptionDetails =
        serde_json::from_value(existing.details.clone()).map_err(|e| {
            log::error!("Failed to parse RellmHostingSubscriptionDetails for {}: {:?}", existing.id, e);
            Status::new(Code::Internal, "invalid_stored_details")
        })?;
    details.notes_last_read = Some(SystemTime::now().to_proto());
    let new_details = serde_json::to_value(&details).map_err(|e| {
        log::error!("Failed to serialize RellmHostingSubscriptionDetails: {:?}", e);
        Status::new(Code::Internal, "failed_to_serialize_details")
    })?;
    diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(existing.id)))
        .set(market_subscriptions::details.eq(new_details))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to mark fulfillment notes read: {:?}", e);
            Status::new(Code::Internal, "failed_to_update_subscription")
        })?;
    build_subscription(existing.id, conn)
}
