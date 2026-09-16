use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::market_products;

/// *Authenticated*, requires `Permission::Admin` directly (no dedicated permission -- see
/// `configure_server.rs`'s identical gating). `type`/`period` are set once here and never
/// changeable afterward (see `UpdateMarketProduct`'s own doc).
pub fn create_market_product(
    request: MarketProduct,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MarketProduct, Status> {
    validate_permission(&Some(current_user), Permission::Admin)?;

    let purchase_type = PurchaseType::try_from(request.r#type)
        .map_err(|_| Status::new(Code::InvalidArgument, "invalid_type"))?;
    let period = PurchasePeriod::try_from(request.period)
        .map_err(|_| Status::new(Code::InvalidArgument, "invalid_period"))?;
    if request.amount == 0 {
        return Err(Status::new(Code::InvalidArgument, "amount_required"));
    }
    if request.currency == 0 {
        return Err(Status::new(Code::InvalidArgument, "currency_required"));
    }
    validate_details_match_type(purchase_type, &request.details)?;

    let inserted = insert_into(market_products::table)
        .values(&models::NewMarketProduct {
            product_type: purchase_type.to_string_purchase_type(),
            period: period.to_string_purchase_period(),
            amount: request.amount as i32,
            currency: request.currency as i32,
            details: product_details_to_json(&request.details),
        })
        .get_result::<models::MarketProduct>(conn)
        .map_err(|e| {
            log::error!("Failed to create market product: {:?}", e);
            Status::new(Code::Internal, "failed_to_create_product")
        })?;

    Ok(MarshalableMarketProduct(inserted).to_proto())
}

/// A `MarketProduct.details` variant must match its own `type` -- e.g. a
/// `PURCHASE_TYPE_MEDIA_STORAGE` product can't carry `ai_grant_subscription_details`. `details`
/// may also be entirely unset (an admin can fill it in later via `UpdateMarketProduct`).
pub(super) fn validate_details_match_type(
    purchase_type: PurchaseType,
    details: &Option<market_product::Details>,
) -> Result<(), Status> {
    let matches = match details {
        None => true,
        Some(market_product::Details::MediaStorageSubscriptionDetails(_)) => {
            purchase_type == PurchaseType::MediaStorage
        }
        Some(market_product::Details::AiGrantSubscriptionDetails(_)) => {
            purchase_type == PurchaseType::AiGrants
        }
        Some(market_product::Details::RellmHostingSubscriptionDetails(_)) => {
            purchase_type == PurchaseType::RellmHosting
        }
    };
    if matches {
        Ok(())
    } else {
        Err(Status::new(Code::InvalidArgument, "details_do_not_match_type"))
    }
}
