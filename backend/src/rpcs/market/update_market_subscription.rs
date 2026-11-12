use std::sync::Arc;
use std::time::SystemTime;

use diesel::sql_types::Jsonb;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::{PgPool, PgPooledConnection};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::market_subscriptions;

/// *Authenticated*, requires Admin (for now -- see this RPC's own proto doc). Only ever touches a
/// subscription's own `fulfillment_notes` -- of any `PurchaseType`, they all have a chat -- (`fulfillment_status` is
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
    apply_fulfillment_notes(request, current_user, conn).map(|(updated, _new_notes)| updated)
}

/// What the gRPC service actually calls: `update_market_subscription`, then -- only once the notes
/// are safely stored -- pushes a notification per newly-appended note to every device that opted in
/// to this subscription's chat (`web_push::notify_fulfillment_note`; spawned in the background with
/// its own connection from `pool`, never delays or fails the update itself). Kept separate from
/// `update_market_subscription` so the many specs of its validation rules don't all need a pool.
pub fn update_market_subscription_and_notify(
    request: MarketSubscription,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
    pool: Arc<PgPool>,
) -> Result<MarketSubscription, Status> {
    let (updated, new_notes) = apply_fulfillment_notes(request, current_user, conn)?;
    if !new_notes.is_empty() {
        notify_new_notes(&updated, &new_notes, current_user, &pool);
    }
    Ok(updated)
}

fn notify_new_notes(
    updated: &MarketSubscription,
    new_notes: &[FulfillmentNote],
    author: &models::User,
    pool: &Arc<PgPool>,
) {
    let Some(buyer) = updated.buyer.as_ref() else {
        return;
    };
    let (Ok(market_subscription_id), Ok(buyer_id)) =
        (updated.id.to_db_id_or_err("id"), buyer.user_id.to_db_id_or_err("buyer.user_id"))
    else {
        return;
    };
    for note in new_notes {
        crate::web_push::notify_fulfillment_note(
            pool.clone(),
            crate::web_push::FulfillmentNoteNotificationContent {
                market_subscription_id,
                author_user_id: author.id,
                buyer_id,
                buyer_username: buyer.username.clone().unwrap_or_default(),
                note_text: note.note.clone(),
                new_status_label: note_status_change_label(updated, note),
            },
        );
    }
}

/// `Some("<Status>")` only for a note whose status differs from the note before it (a real
/// transition, see `FulfillmentNote.note`'s own doc) -- the notification body falls back to it when
/// the note has no text of its own.
fn note_status_change_label(updated: &MarketSubscription, note: &FulfillmentNote) -> Option<String> {
    let notes = details_fulfillment_notes(&updated.details);
    let index = notes.iter().position(|n| n == note)?;
    let previous_status = if index == 0 {
        FulfillmentStatus::AwaitingHostAdmin as i32
    } else {
        notes[index - 1].fulfillment_status
    };
    (note.fulfillment_status != previous_status).then(|| {
        match FulfillmentStatus::try_from(note.fulfillment_status) {
            Ok(FulfillmentStatus::Fulfilled) => "Fulfilled",
            Ok(FulfillmentStatus::InProgress) => "In Progress",
            _ => "Awaiting Host Admin",
        }
        .to_string()
    })
}

/// The `fulfillment_notes` of whichever `details` variant a subscription carries -- every type has them
/// (see `MediaStorageSubscriptionDetails.fulfillment_notes`).
fn details_fulfillment_notes(details: &Option<market_subscription::Details>) -> Vec<FulfillmentNote> {
    match details {
        Some(market_subscription::Details::MediaStorageSubscriptionDetails(d)) => d.fulfillment_notes.clone(),
        Some(market_subscription::Details::AiGrantSubscriptionDetails(d)) => d.fulfillment_notes.clone(),
        Some(market_subscription::Details::RellmHostingSubscriptionDetails(d)) => d.fulfillment_notes.clone(),
        Some(market_subscription::Details::PermissionsAccessSubscriptionDetails(d)) => d.fulfillment_notes.clone(),
        None => vec![],
    }
}

/// The `PurchaseType` a `details` variant belongs to.
fn details_purchase_type(details: &Option<market_subscription::Details>) -> Option<PurchaseType> {
    match details {
        Some(market_subscription::Details::MediaStorageSubscriptionDetails(_)) => Some(PurchaseType::MediaStorage),
        Some(market_subscription::Details::AiGrantSubscriptionDetails(_)) => Some(PurchaseType::AiGrants),
        Some(market_subscription::Details::RellmHostingSubscriptionDetails(_)) => Some(PurchaseType::RellmHosting),
        Some(market_subscription::Details::PermissionsAccessSubscriptionDetails(_)) => {
            Some(PurchaseType::PermissionsAccess)
        }
        None => None,
    }
}

/// The real work behind `update_market_subscription` -- also returns the newly-appended
/// `FulfillmentNote`s exactly as stored (server-stamped `created_at` included), for the
/// notification path.
fn apply_fulfillment_notes(
    request: MarketSubscription,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(MarketSubscription, Vec<FulfillmentNote>), Status> {
    validate_permission(&Some(current_user), Permission::Admin)?;

    let subscription_id = request.id.to_db_id_or_err("id")?;
    let existing = models::get_market_subscription(subscription_id, conn)?;
    let purchase_type = existing
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);

    // The request carries the subscription's own `details` variant, whose `fulfillment_notes` is the
    // client's view of the whole chat (existing notes verbatim, plus any new ones at the end).
    let Some(incoming_type) = details_purchase_type(&request.details) else {
        return Err(Status::new(Code::InvalidArgument, "subscription_details_required"));
    };
    if incoming_type != purchase_type {
        return Err(Status::new(Code::InvalidArgument, "subscription_details_type_mismatch"));
    }
    let incoming_notes = details_fulfillment_notes(&request.details);

    // Operates on the stored JSON directly, whatever the type: the chat lives at the same
    // `fulfillment_notes`/`fulfillment_status` keys in every `*SubscriptionDetails`.
    let mut stored_notes: Vec<FulfillmentNote> = match existing.details.get("fulfillment_notes") {
        Some(value) if !value.is_null() => serde_json::from_value(value.clone()).map_err(|e| {
            log::error!("Failed to parse fulfillment_notes of subscription {}: {:?}", existing.id, e);
            Status::new(Code::Internal, "invalid_stored_details")
        })?,
        _ => vec![],
    };
    let stored_status = existing
        .details
        .get("fulfillment_status")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
        .unwrap_or(FulfillmentStatus::AwaitingHostAdmin as i32);

    let already_stored = stored_notes.len();
    if incoming_notes.len() < already_stored || incoming_notes[..already_stored] != stored_notes[..] {
        return Err(Status::new(Code::InvalidArgument, "fulfillment_notes_must_only_be_appended"));
    }
    // Tracks what `fulfillment_status` was as of the last note processed so far (old or newly
    // appended) -- starts at whatever it's currently set to (itself always in sync with the last
    // *already-stored* note, or the `AWAITING_HOST_ADMIN` default if there are none yet -- see this
    // field's own proto doc), then advances with each newly appended entry below.
    let mut running_status = stored_status;
    let mut appended_notes: Vec<FulfillmentNote> = vec![];
    for note in &incoming_notes[already_stored..] {
        if note.user_id != current_user.id.to_proto_id() {
            return Err(Status::new(Code::PermissionDenied, "fulfillment_note_user_id_mismatch"));
        }
        let is_status_change = note.fulfillment_status != running_status;
        if !is_status_change && note.note.trim().is_empty() {
            return Err(Status::new(Code::InvalidArgument, "fulfillment_note_text_required"));
        }
        running_status = note.fulfillment_status;
        let stored_note = FulfillmentNote {
            user_id: note.user_id.clone(),
            note: note.note.clone(),
            fulfillment_status: note.fulfillment_status,
            created_at: Some(SystemTime::now().to_proto()),
        };
        appended_notes.push(stored_note.clone());
        stored_notes.push(stored_note);
    }

    let notes_json = serde_json::to_value(&stored_notes).map_err(|e| {
        log::error!("Failed to serialize fulfillment_notes: {:?}", e);
        Status::new(Code::Internal, "failed_to_serialize_details")
    })?;

    // Writes only the two chat keys, in one statement (`jsonb_set`): everything else in `details` --
    // including the buyer's `notes_last_read`, which `MarkFulfillmentNotesRead` may have moved since the
    // row was read above -- is left exactly as it is at write time, so neither writer can put a stale
    // copy back over the other's change.
    let updated = diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(existing.id)))
        .set(
            market_subscriptions::details.eq(diesel::dsl::sql::<Jsonb>(
                "jsonb_set(jsonb_set(market_subscriptions.details, '{fulfillment_notes}', ",
            )
            .bind::<Jsonb, _>(notes_json)
            .sql(", true), '{fulfillment_status}', ")
            .bind::<Jsonb, _>(serde_json::json!(running_status))
            .sql(", true)")),
        )
        .get_result::<models::MarketSubscription>(conn)
        .map_err(|e| {
            log::error!("Failed to update market subscription: {:?}", e);
            Status::new(Code::Internal, "failed_to_update_subscription")
        })?;

    let mut by_buyer = build_subscriptions_for_buyers(&[updated.buyer_id], conn)?;
    let marshaled = by_buyer
        .remove(&updated.buyer_id)
        .unwrap_or_default()
        .into_iter()
        .find(|s| s.id == request.id)
        .ok_or_else(|| Status::new(Code::Internal, "failed_to_load_updated_subscription"))?;
    Ok((marshaled, appended_notes))
}
