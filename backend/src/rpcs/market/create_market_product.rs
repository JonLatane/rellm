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
            available_count: request.available_count as i32,
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
/// may also be entirely unset (an admin can fill it in later via `UpdateMarketProduct`). For
/// `PermissionsAccessSubscriptionDetails` specifically, also validates every listed permission
/// against `PURCHASABLE_PERMISSIONS` -- see that const's own doc.
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
        Some(market_product::Details::PermissionsAccessSubscriptionDetails(permissions_details)) => {
            if purchase_type != PurchaseType::PermissionsAccess {
                false
            } else {
                return validate_permissions_are_purchasable(&permissions_details.permissions);
            }
        }
    };
    if matches {
        Ok(())
    } else {
        Err(Status::new(Code::InvalidArgument, "details_do_not_match_type"))
    }
}

/// Every `Permission` a `PermissionsAccessSubscriptionDetails`/`PermissionsAccessPurchaseDetails`
/// may ever grant -- an explicit include-list (not the exclude-list `market.proto`'s own doc on
/// `PermissionsAccessSubscriptionDetails.permissions` describes), so a newly-added `Permission`
/// is never purchasable by default; it has to be deliberately added here. Excludes anything
/// `ADMIN`-adjacent, moderation-granting, or private-data-visibility-granting -- see that field's
/// own proto doc for the named exclusions this list actually encodes.
const PURCHASABLE_PERMISSIONS: &[Permission] = &[
    Permission::ViewUsers,
    Permission::PublishUsersLocally,
    Permission::PublishUsersGlobally,
    Permission::FollowUsers,
    Permission::ViewGroups,
    Permission::CreateGroups,
    Permission::PublishGroupsLocally,
    Permission::PublishGroupsGlobally,
    Permission::JoinGroups,
    Permission::InviteGroupMembers,
    Permission::ViewPosts,
    Permission::CreatePosts,
    Permission::PublishPostsLocally,
    Permission::PublishPostsGlobally,
    Permission::ReplyToPosts,
    Permission::EditPostTitlesAndLinks,
    Permission::ViewEvents,
    Permission::CreateEvents,
    Permission::PublishEventsLocally,
    Permission::PublishEventsGlobally,
    Permission::RsvpToEvents,
    Permission::ViewMedia,
    Permission::CreateMedia,
    Permission::PublishMediaLocally,
    Permission::PublishMediaGlobally,
    Permission::ReadPersonalMessages,
    Permission::CreateAiProviders,
    Permission::SyncEventsFromIcs,
    Permission::SyncPostsFromRss,
    Permission::SyncPostsFromAtom,
    Permission::SyncEventsToFacebook,
    Permission::SyncPostsToFacebook,
    Permission::SyncEventsToInstagram,
    Permission::SyncPostsToInstagram,
    Permission::SyncEventsToMastodon,
    Permission::SyncPostsToMastodon,
    Permission::SyncEventsToBluesky,
    Permission::SyncPostsToBluesky,
    Permission::SyncEventsToXTwitter,
    Permission::SyncPostsToXTwitter,
    Permission::SyncEventsToThreads,
    Permission::SyncPostsToThreads,
    Permission::Business,
    Permission::RunBots,
];

/// Also called directly from `rpcs::market::make_market_purchase` -- `validate_details_match_type`
/// above only ever runs at `CreateMarketProduct`/`UpdateMarketProduct` time, so re-checking here
/// too is defense in depth against `PURCHASABLE_PERMISSIONS` shrinking (a permission deliberately
/// removed from the list) after a `PermissionsAccessSubscriptionDetails` product that granted it
/// was already created -- without this, an existing product could keep selling a permission this
/// list no longer considers safe.
pub(super) fn validate_permissions_are_purchasable(permissions: &[i32]) -> Result<(), Status> {
    for &permission in permissions {
        let recognized = Permission::try_from(permission).unwrap_or(Permission::Unknown);
        if !PURCHASABLE_PERMISSIONS.contains(&recognized) {
            return Err(Status::new(Code::InvalidArgument, "permission_not_purchasable"));
        }
    }
    Ok(())
}
