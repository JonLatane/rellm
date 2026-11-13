use std::time::SystemTime;

use diesel::sql_types::Jsonb;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::market_subscriptions;

/// *Authenticated*, buyer only -- see `MediaStorageSubscriptionDetails.notes_last_read` (the same field on every type's details): the marker
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
    // Any `PurchaseType` has a fulfillment chat; `details` is always a JSON object (see
    // `market_marshaling::subscription_details_to_proto`).
    if !existing.details.is_object() {
        log::error!("Stored details for market subscription {} is not an object", existing.id);
        return Err(Status::new(Code::Internal, "invalid_stored_details"));
    }
    // Write *only* the marker, in one statement (`jsonb_set`), never read-modify-write the whole
    // `details`: a concurrent `UpdateMarketSubscription` appending a note would otherwise be overwritten
    // by this request's stale copy.
    let marker = serde_json::to_value(SystemTime::now().to_proto()).map_err(|e| {
        log::error!("Failed to serialize notes_last_read: {:?}", e);
        Status::new(Code::Internal, "failed_to_serialize_details")
    })?;
    diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(existing.id)))
        .set(
            market_subscriptions::details.eq(diesel::dsl::sql::<Jsonb>("jsonb_set(details, '{notes_last_read}', ")
                .bind::<Jsonb, _>(marker)
                .sql(", true)")),
        )
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to mark fulfillment notes read: {:?}", e);
            Status::new(Code::Internal, "failed_to_update_subscription")
        })?;
    build_subscription(existing.id, conn)
}
