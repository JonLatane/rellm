use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::schema::push_subscriptions;

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
