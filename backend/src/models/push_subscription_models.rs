use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::schema::{market_subscription_push_subscriptions, push_subscriptions};

#[derive(Debug, Queryable, Identifiable, Clone)]
#[diesel(table_name = push_subscriptions)]
pub struct PushSubscription {
    pub id: i64,
    pub user_id: i64,
    pub endpoint: String,
    pub p256dh_key: String,
    pub auth_key: String,
    pub created_at: SystemTime,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = push_subscriptions)]
pub struct NewPushSubscription {
    pub user_id: i64,
    pub endpoint: String,
    pub p256dh_key: String,
    pub auth_key: String,
}

/// Registers `new_subscription`, or -- if `(user_id, endpoint)` is already on file -- updates its
/// keys in place. See `RegisterPushSubscription`'s own RPC doc comment on why re-registration
/// isn't an error.
pub fn upsert_push_subscription(
    new_subscription: &NewPushSubscription,
    conn: &mut PgPooledConnection,
) -> Result<PushSubscription, Status> {
    insert_into(push_subscriptions::table)
        .values(new_subscription)
        .on_conflict((push_subscriptions::user_id, push_subscriptions::endpoint))
        .do_update()
        .set((
            push_subscriptions::p256dh_key.eq(&new_subscription.p256dh_key),
            push_subscriptions::auth_key.eq(&new_subscription.auth_key),
        ))
        .get_result::<PushSubscription>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_registering_push_subscription"))
}

/// Unregisters `user_id`'s subscription to `endpoint`. Not an error if no such row exists -- see
/// `UnregisterPushSubscription`'s own RPC doc comment.
pub fn delete_push_subscription(
    user_id: i64,
    endpoint: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    delete(
        push_subscriptions::table
            .filter(push_subscriptions::user_id.eq(user_id))
            .filter(push_subscriptions::endpoint.eq(endpoint)),
    )
    .execute(conn)
    .map_err(|_| Status::new(Code::Internal, "error_unregistering_push_subscription"))?;
    Ok(())
}

/// Every push subscription belonging to any of `user_ids` -- used to fan a new-Message
/// notification out to every device each recipient has registered (see
/// `web_push::notify_message_recipients`).
pub fn get_push_subscriptions_for_users(
    user_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<Vec<PushSubscription>, Status> {
    if user_ids.is_empty() {
        return Ok(vec![]);
    }
    push_subscriptions::table
        .filter(push_subscriptions::user_id.eq_any(user_ids))
        .load::<PushSubscription>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_push_subscriptions"))
}

/// Whether `user_id` has a `PushSubscription` registered for `endpoint` -- see
/// `GetPushSubscriptionStatus`'s own RPC doc comment on why the frontend needs this at all (a
/// browser subscription's own endpoint says nothing about which locally-known account, if any, is
/// actually registered against it server-side).
pub fn push_subscription_exists(
    user_id: i64,
    endpoint: &str,
    conn: &mut PgPooledConnection,
) -> Result<bool, Status> {
    diesel::select(diesel::dsl::exists(
        push_subscriptions::table
            .filter(push_subscriptions::user_id.eq(user_id))
            .filter(push_subscriptions::endpoint.eq(endpoint)),
    ))
    .get_result(conn)
    .map_err(|_| Status::new(Code::Internal, "error_checking_push_subscription_status"))
}

/// Deletes a subscription by its database id -- used once the push service itself reports one
/// Gone (404/410), so a dead endpoint stops being retried on every future Message. See
/// `web_push::send_push`.
pub fn delete_push_subscription_by_id(id: i64, conn: &mut PgPooledConnection) -> Result<(), Status> {
    delete(push_subscriptions::table.filter(push_subscriptions::id.eq(id)))
        .execute(conn)
        .map_err(|_| Status::new(Code::Internal, "error_pruning_push_subscription"))?;
    Ok(())
}

/// `user_id`'s own `PushSubscription` for `endpoint`, if registered -- what
/// `RegisterMarketSubscriptionPush` links a market subscription to (it never creates one itself).
pub fn get_push_subscription_for_user_endpoint(
    user_id: i64,
    endpoint: &str,
    conn: &mut PgPooledConnection,
) -> Result<Option<PushSubscription>, Status> {
    push_subscriptions::table
        .filter(push_subscriptions::user_id.eq(user_id))
        .filter(push_subscriptions::endpoint.eq(endpoint))
        .first::<PushSubscription>(conn)
        .optional()
        .map_err(|_| Status::new(Code::Internal, "error_loading_push_subscriptions"))
}

/// Opts `push_subscription_id` in to `market_subscription_id`'s fulfillment-chat notifications --
/// idempotent (`ON CONFLICT DO NOTHING` on the table's `UNIQUE` pair).
pub fn link_market_subscription_push_subscription(
    market_subscription_id: i64,
    push_subscription_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    insert_into(market_subscription_push_subscriptions::table)
        .values((
            market_subscription_push_subscriptions::market_subscription_id.eq(market_subscription_id),
            market_subscription_push_subscriptions::push_subscription_id.eq(push_subscription_id),
        ))
        .on_conflict_do_nothing()
        .execute(conn)
        .map_err(|_| Status::new(Code::Internal, "error_registering_market_subscription_push"))?;
    Ok(())
}

/// Reverses `link_market_subscription_push_subscription` for `user_id`'s `endpoint` -- not an error
/// if there was no such link (or no such push subscription at all).
pub fn unlink_market_subscription_push_subscription(
    market_subscription_id: i64,
    user_id: i64,
    endpoint: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let push_subscription_ids = push_subscriptions::table
        .filter(push_subscriptions::user_id.eq(user_id))
        .filter(push_subscriptions::endpoint.eq(endpoint))
        .select(push_subscriptions::id);
    delete(
        market_subscription_push_subscriptions::table
            .filter(market_subscription_push_subscriptions::market_subscription_id.eq(market_subscription_id))
            .filter(market_subscription_push_subscriptions::push_subscription_id.eq_any(push_subscription_ids)),
    )
    .execute(conn)
    .map_err(|_| Status::new(Code::Internal, "error_unregistering_market_subscription_push"))?;
    Ok(())
}

/// Whether `user_id`'s `endpoint` is linked to `market_subscription_id`'s notifications.
pub fn market_subscription_push_subscription_exists(
    market_subscription_id: i64,
    user_id: i64,
    endpoint: &str,
    conn: &mut PgPooledConnection,
) -> Result<bool, Status> {
    diesel::select(diesel::dsl::exists(
        market_subscription_push_subscriptions::table
            .inner_join(push_subscriptions::table)
            .filter(market_subscription_push_subscriptions::market_subscription_id.eq(market_subscription_id))
            .filter(push_subscriptions::user_id.eq(user_id))
            .filter(push_subscriptions::endpoint.eq(endpoint)),
    ))
    .get_result(conn)
    .map_err(|_| Status::new(Code::Internal, "error_checking_market_subscription_push_status"))
}

/// Every push subscription linked to `market_subscription_id` -- the candidate recipients of a new
/// `FulfillmentNote` (see `web_push::notify_fulfillment_note`, which further filters by author and
/// by who may still read the chat).
pub fn get_push_subscriptions_for_market_subscription(
    market_subscription_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<Vec<PushSubscription>, Status> {
    market_subscription_push_subscriptions::table
        .inner_join(push_subscriptions::table)
        .filter(market_subscription_push_subscriptions::market_subscription_id.eq(market_subscription_id))
        .select(push_subscriptions::all_columns)
        .load::<PushSubscription>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_push_subscriptions"))
}
