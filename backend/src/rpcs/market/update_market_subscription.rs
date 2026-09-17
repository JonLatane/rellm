use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::market_subscriptions;

/// *Authenticated*, requires Admin (for now -- see this RPC's own proto doc). Only ever touches a
/// `PURCHASE_TYPE_RELLM_HOSTING` subscription's own `fulfillment_notes` (`fulfillment_status` is
/// never set directly -- see below) -- every other field (`amount`/`currency`/`domain`/
/// `contact_email`/`additional_information`/etc.) is immutable after purchase, same "only the
/// fields this RPC is actually for" treatment `update_market_product.rs` gives `type`/`period`.
///
/// `fulfillment_notes` is append-only: the incoming list must start with exactly the same entries
/// already stored (any fewer, or any that differ, is an error), and every entry *beyond* what's
/// already stored is treated as new -- its `user_id` must match the caller's own (never trusted
/// otherwise, so one admin can't attribute a note to another), and the server stamps its own
/// `created_at`, ignoring whatever the client sent. Each new entry's own `note` text is required
/// *unless* its `fulfillment_status` differs from the previous entry's (or, for the very first
/// note ever, from the implicit `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN` default) -- a real status
/// transition can stand on its own with no text (e.g. the "admin opened this order" transition to
/// `IN_PROGRESS`). The returned subscription's own `RellmHostingSubscriptionDetails.
/// fulfillment_status` is always set to whatever the *last* note (old or newly appended) says --
/// there's no way to change it except by appending a note that says something different.
pub fn update_market_subscription(
    request: MarketSubscription,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MarketSubscription, Status> {
    validate_permission(&Some(current_user), Permission::Admin)?;

    let subscription_id = request.id.to_db_id_or_err("id")?;
    let mut existing = models::get_market_subscription(subscription_id, conn)?;
    let purchase_type = existing
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);
    if purchase_type != PurchaseType::RellmHosting {
        return Err(Status::new(Code::FailedPrecondition, "not_a_rellm_hosting_subscription"));
    }

    let Some(market_subscription::Details::RellmHostingSubscriptionDetails(incoming)) = request.details else {
        return Err(Status::new(Code::InvalidArgument, "rellm_hosting_subscription_details_required"));
    };
    let mut current_details: RellmHostingSubscriptionDetails = serde_json::from_value(existing.details.clone())
        .map_err(|e| {
            log::error!(
                "Failed to parse existing RellmHostingSubscriptionDetails for subscription {}: {:?}",
                existing.id,
                e
            );
            Status::new(Code::Internal, "invalid_stored_details")
        })?;

    let already_stored = current_details.fulfillment_notes.len();
    if incoming.fulfillment_notes.len() < already_stored
        || incoming.fulfillment_notes[..already_stored] != current_details.fulfillment_notes[..]
    {
        return Err(Status::new(Code::InvalidArgument, "fulfillment_notes_must_only_be_appended"));
    }
    // Tracks what `fulfillment_status` was as of the last note processed so far (old or newly
    // appended) -- starts at whatever it's currently set to (itself always in sync with the last
    // *already-stored* note, or the `AWAITING_HOST_ADMIN` default if there are none yet -- see this
    // field's own proto doc), then advances with each newly appended entry below.
    let mut running_status = current_details.fulfillment_status;
    for note in &incoming.fulfillment_notes[already_stored..] {
        if note.user_id != current_user.id.to_proto_id() {
            return Err(Status::new(Code::PermissionDenied, "fulfillment_note_user_id_mismatch"));
        }
        let is_status_change = note.fulfillment_status != running_status;
        if !is_status_change && note.note.trim().is_empty() {
            return Err(Status::new(Code::InvalidArgument, "fulfillment_note_text_required"));
        }
        running_status = note.fulfillment_status;
        current_details.fulfillment_notes.push(FulfillmentNote {
            user_id: note.user_id.clone(),
            note: note.note.clone(),
            fulfillment_status: note.fulfillment_status,
            created_at: Some(SystemTime::now().to_proto()),
        });
    }
    current_details.fulfillment_status = running_status;

    existing.details = serde_json::to_value(&current_details).map_err(|e| {
        log::error!("Failed to serialize RellmHostingSubscriptionDetails: {:?}", e);
        Status::new(Code::Internal, "failed_to_serialize_details")
    })?;

    let updated = diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(existing.id)))
        .set(&existing)
        .get_result::<models::MarketSubscription>(conn)
        .map_err(|e| {
            log::error!("Failed to update market subscription: {:?}", e);
            Status::new(Code::Internal, "failed_to_update_subscription")
        })?;

    let mut by_buyer = build_subscriptions_for_buyers(&[updated.buyer_id], conn)?;
    by_buyer
        .remove(&updated.buyer_id)
        .unwrap_or_default()
        .into_iter()
        .find(|s| s.id == request.id)
        .ok_or_else(|| Status::new(Code::Internal, "failed_to_load_updated_subscription"))
}
