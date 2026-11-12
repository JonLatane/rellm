use tonic::Status;

use super::market_subscription_push_access::authorize_market_subscription_push;
use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::*;

/// See `UnregisterMarketSubscriptionPush`'s own RPC doc comment.
pub fn unregister_market_subscription_push(
    request: MarketSubscriptionPushRequest,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let subscription = authorize_market_subscription_push(&request, user, conn)?;
    models::unlink_market_subscription_push_subscription(subscription.id, user.id, &request.endpoint, conn)
}
