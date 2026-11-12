use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;

/// *Authenticated*, self-or-`Permission::Admin` -- the subscription's own buyer can cancel it
/// themselves, or an admin can cancel it on their behalf, mirroring `rpcs::users::update_user`'s
/// `self_update`-or-permission gating.
///
/// Idempotent -- canceling an already-canceled subscription is a no-op success (doesn't touch
/// `canceled_at` again, doesn't error) rather than failing on a slow double-click.
///
/// Immediately decrements the product's `sold_count` (see that field's own doc), freeing a slot for
/// someone else to buy -- unlike the entitlement itself, which stays in effect until the subscription
/// is actually terminated (see below). The subscription becomes `SUBSCRIPTION_ACTIVE_BUT_CANCELED`
/// (it can be resumed by buying the product again -- see `make_market_purchase`) until the paid-for
/// period runs out. This only sets `canceled_at`; it does NOT immediately revoke
/// the subscription's entitlement
/// (media storage quota, granted permissions) -- that stays in effect until whichever is later of
/// `renews_at`/`canceled_at` has passed, at which point `logic::market::market_renewal`'s
/// `terminate_subscriptions_of_type` (run from `bin/renew_market_subscriptions.rs`) revokes it via
/// `logic::market::market_fulfillment::terminate_entitlement` and stamps `service_terminated_at`. See
/// `MarketSubscription.canceled_at`/`service_terminated_at`'s own proto docs.
pub fn cancel_market_subscription(
    request: MarketSubscription,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MarketSubscription, Status> {
    let subscription_id = request.id.to_db_id_or_err("id")?;
    let existing = models::get_market_subscription(subscription_id, conn)?;

    let self_cancel = existing.buyer_id == current_user.id;
    if !self_cancel {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    // Only the call that actually flips `canceled_at` frees the slot, atomically with it under the
    // product's row lock -- see `cancel_market_subscription_and_release_slot`. Everything else (already
    // canceled, whether still `SUBSCRIPTION_ACTIVE_BUT_CANCELED` or fully `SUBSCRIPTION_CANCELED`) is the
    // idempotent no-op success described above.
    models::cancel_market_subscription_and_release_slot(existing.id, existing.product_id, conn)?;

    let mut by_buyer = build_subscriptions_for_buyers(&[existing.buyer_id], conn)?;
    by_buyer
        .remove(&existing.buyer_id)
        .unwrap_or_default()
        .into_iter()
        .find(|s| s.id == request.id)
        .ok_or_else(|| Status::new(Code::Internal, "failed_to_load_updated_subscription"))
}
