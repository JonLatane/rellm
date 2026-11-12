use tonic::Status;

use super::market_subscription_push_access::authorize_market_subscription_push;
use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::*;

/// See `GetMarketSubscriptionPushStatus`'s own RPC doc comment.
pub fn get_market_subscription_push_status(
    request: MarketSubscriptionPushRequest,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<GetMarketSubscriptionPushStatusResponse, Status> {
    let subscription = authorize_market_subscription_push(&request, user, conn)?;
    let registered =
        models::market_subscription_push_subscription_exists(subscription.id, user.id, &request.endpoint, conn)?;
    Ok(GetMarketSubscriptionPushStatusResponse { registered })
}
