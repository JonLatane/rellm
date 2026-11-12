use tonic::{Code, Status};

use super::market_subscription_push_access::authorize_market_subscription_push;
use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::*;

/// See `RegisterMarketSubscriptionPush`'s own RPC doc comment. Links an *already registered* push
/// subscription (`RegisterPushSubscription`, one per user+browser) to the subscription's fulfillment
/// chat -- it doesn't take keys itself, so there's exactly one place a browser's keys are stored and
/// refreshed.
pub fn register_market_subscription_push(
    request: MarketSubscriptionPushRequest,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let subscription = authorize_market_subscription_push(&request, user, conn)?;
    let push_subscription = models::get_push_subscription_for_user_endpoint(user.id, &request.endpoint, conn)?
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "push_subscription_not_registered"))?;
    models::link_market_subscription_push_subscription(subscription.id, push_subscription.id, conn)
}
