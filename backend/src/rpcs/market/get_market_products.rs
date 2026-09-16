use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;

/// *Unauthenticated* -- admins additionally see delisted `MarketProduct`s.
pub fn get_market_products(
    _request: GetMarketProductsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetMarketProductsResponse, Status> {
    let is_admin = validate_permission(user, Permission::Admin).is_ok();
    let market_products = models::get_market_products(is_admin, conn)?
        .into_iter()
        .map(|product| MarshalableMarketProduct(product).to_proto())
        .collect();
    Ok(GetMarketProductsResponse { market_products })
}
