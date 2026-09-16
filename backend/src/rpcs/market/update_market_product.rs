use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::market::create_market_product::validate_details_match_type;
use crate::rpcs::validate_permission;
use crate::schema::market_products;

/// *Authenticated*, requires `Permission::Admin`. `type`/`period` are immutable after creation --
/// silently ignored if the request's copy differs from what's already stored (see this RPC's own
/// proto doc) rather than erroring, since a real client always fetches-then-mutates a
/// `MarketProduct` it already has and would otherwise have to carefully avoid touching those two
/// fields itself.
pub fn update_market_product(
    request: MarketProduct,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MarketProduct, Status> {
    validate_permission(&Some(current_user), Permission::Admin)?;

    let product_id = request.id.to_db_id_or_err("id")?;
    let mut existing = models::get_market_product(product_id, conn)?;
    let purchase_type = existing
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);

    if request.amount == 0 {
        return Err(Status::new(Code::InvalidArgument, "amount_required"));
    }
    if request.currency == 0 {
        return Err(Status::new(Code::InvalidArgument, "currency_required"));
    }
    validate_details_match_type(purchase_type, &request.details)?;

    existing.amount = request.amount as i32;
    existing.currency = request.currency as i32;
    existing.details = product_details_to_json(&request.details);
    // Per `MarketProduct.delisted_at`'s own doc: presence, not the client-supplied timestamp, is
    // what matters -- listing/delisting always stamps the server's own current time.
    existing.delisted_at = request.delisted_at.map(|_| SystemTime::now());

    let updated = diesel::update(market_products::table.filter(market_products::id.eq(existing.id)))
        .set(&existing)
        .get_result::<models::MarketProduct>(conn)
        .map_err(|e| {
            log::error!("Failed to update market product: {:?}", e);
            Status::new(Code::Internal, "failed_to_update_product")
        })?;

    Ok(MarshalableMarketProduct(updated).to_proto())
}
