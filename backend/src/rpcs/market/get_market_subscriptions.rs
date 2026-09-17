use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;

/// *Authenticated* -- see `GetMarketSubscriptionsRequest`'s own doc.
/// `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_PURCHASE` (the default) is self-scoped only;
/// `GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN` requires Admin and returns every
/// `PURCHASE_TYPE_RELLM_HOSTING` subscription across every buyer.
pub fn get_market_subscriptions(
    request: GetMarketSubscriptionsRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<GetMarketSubscriptionsResponse, Status> {
    let request_type = GetMarketSubscriptionsRequestType::try_from(request.request_type)
        .map_err(|_| Status::new(Code::InvalidArgument, "invalid_request_type"))?;
    let market_subscriptions = match request_type {
        GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForPurchase => {
            let mut by_buyer = build_subscriptions_for_buyers(&[current_user.id], conn)?;
            by_buyer.remove(&current_user.id).unwrap_or_default()
        }
        GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForFulfillmentAdmin => {
            validate_permission(&Some(current_user), Permission::Admin)?;
            build_fulfillment_subscriptions(conn)?
        }
    };
    Ok(GetMarketSubscriptionsResponse {
        market_subscriptions,
    })
}
