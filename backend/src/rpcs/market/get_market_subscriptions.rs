use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;

/// *Authenticated*, self-scoped only -- see `GetMarketSubscriptionsRequest`'s own doc.
pub fn get_market_subscriptions(
    _request: GetMarketSubscriptionsRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<GetMarketSubscriptionsResponse, Status> {
    let mut by_buyer = build_subscriptions_for_buyers(&[current_user.id], conn)?;
    let market_subscriptions = by_buyer.remove(&current_user.id).unwrap_or_default();
    Ok(GetMarketSubscriptionsResponse {
        market_subscriptions,
    })
}
