//! Applies the actual entitlement for a completed Marketplace purchase -- called from both
//! `web::stripe_webhook` (the initial purchase, on `checkout.session.completed`) and
//! `logic::market_renewal` (every subsequent recurring charge). Never called from
//! `rpcs::market::make_market_purchase` itself -- see that RPC's own doc on why fulfillment is
//! webhook/renewal-driven only.

use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::{ToDbId, ToJsonPermissions, ToProtoPermissions};
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use crate::schema::users;

/// Applies `purchase_type`'s entitlement to `buyer_id`, given the just-created `Purchase`'s own
/// `details` JSON (the same shape `market_marshaling::purchase_details_to_json` produces/consumes
/// -- i.e. a `MediaStoragePurchaseDetails`/`AiGrantPurchaseDetails`/`RellmHostingPurchaseDetails`'s
/// own fields, untagged).
pub fn fulfill_purchase(
    purchase_type: PurchaseType,
    buyer_id: i64,
    details: &serde_json::Value,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    match purchase_type {
        PurchaseType::MediaStorage => {
            let parsed: MediaStoragePurchaseDetails = serde_json::from_value(details.clone())
                .map_err(|e| {
                    log::error!("Failed to parse MediaStoragePurchaseDetails: {:?}", e);
                    Status::new(tonic::Code::Internal, "invalid_purchase_details")
                })?;
            diesel::update(users::table.filter(users::id.eq(buyer_id)))
                .set(users::media_storage_limit_bytes.eq(Some(parsed.allocation_bytes as i64)))
                .execute(conn)
                .map_err(|e| {
                    log::error!(
                        "Failed to apply media storage entitlement to user {}: {:?}",
                        buyer_id,
                        e
                    );
                    Status::new(tonic::Code::Internal, "failed_to_apply_entitlement")
                })?;
            Ok(())
        }
        PurchaseType::AiGrants => {
            let parsed: AiGrantPurchaseDetails = serde_json::from_value(details.clone()).map_err(|e| {
                log::error!("Failed to parse AiGrantPurchaseDetails: {:?}", e);
                Status::new(tonic::Code::Internal, "invalid_purchase_details")
            })?;
            let ai_provider_id = parsed.ai_provider_id.to_db_id_or_err("ai_provider_id")?;
            // `upsert_ai_provider_grant` already implements exactly the "reset, don't add"
            // renewal semantics a Marketplace re-purchase/renewal needs (see its own doc).
            models::upsert_ai_provider_grant(
                &models::NewAIProviderGrant {
                    ai_provider_id,
                    grantee_id: buyer_id,
                    model_names: parsed.model_names,
                    tokens_remaining: parsed.tokens as i64,
                    overage: 0,
                },
                conn,
            )?;
            Ok(())
        }
        // No automatic entitlement -- just leaves the `Purchase` record (with domain/contact/
        // notes) for Jon to act on by hand. See `market.proto`'s own framing.
        PurchaseType::RellmHosting => Ok(()),
        // Adds the product's configured `Permission`s to the buyer's own `User.permissions`,
        // union-style (never removes anything the buyer already had, from this grant or any other
        // source) -- "just grant the permissions to the subscribed user," per Jon's own framing.
        // Unlike `AiGrants`, a lapsed/canceled `PermissionsAccess` subscription *does* eventually
        // claw back the permissions it granted -- see `terminate_entitlement` below -- just not
        // immediately: the entitlement stays in effect until `logic::market_renewal`'s
        // `terminate_subscriptions_of_type` finds both `renews_at`/`canceled_at` have passed, same
        // no-retry/no-reconciliation MVP simplicity as the rest of this module.
        PurchaseType::PermissionsAccess => {
            let parsed: PermissionsAccessPurchaseDetails =
                serde_json::from_value(details.clone()).map_err(|e| {
                    log::error!("Failed to parse PermissionsAccessPurchaseDetails: {:?}", e);
                    Status::new(tonic::Code::Internal, "invalid_purchase_details")
                })?;
            let buyer = models::get_user(buyer_id, conn)?;
            let mut updated_permissions = buyer.permissions.to_proto_permissions();
            for permission in parsed.permissions.to_proto_permissions() {
                if !updated_permissions.contains(&permission) {
                    updated_permissions.push(permission);
                }
            }
            diesel::update(users::table.filter(users::id.eq(buyer_id)))
                .set(users::permissions.eq(updated_permissions.to_json_permissions()))
                .execute(conn)
                .map_err(|e| {
                    log::error!(
                        "Failed to apply permissions entitlement to user {}: {:?}",
                        buyer_id,
                        e
                    );
                    Status::new(tonic::Code::Internal, "failed_to_apply_entitlement")
                })?;
            Ok(())
        }
    }
}

/// The semantic inverse of `fulfill_purchase` -- revokes `purchase_type`'s entitlement from
/// `buyer_id`, given a `MarketSubscription`'s own `details` JSON (the `*SubscriptionDetails`
/// shape `market_marshaling::subscription_details_to_proto` uses, NOT the `*PurchaseDetails` shape
/// `fulfill_purchase` itself parses -- field-for-field identical for every variant today, but the
/// distinct Rust types matter for `PermissionsAccess` below). Called only from
/// `logic::market_renewal::terminate_subscriptions_of_type`, once a subscription's cancellation has
/// actually taken effect (see that function's own doc).
pub fn terminate_entitlement(
    purchase_type: PurchaseType,
    buyer_id: i64,
    details: &serde_json::Value,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    match purchase_type {
        // Reverts to the server's *current* configured default allocation -- not `NULL`/unlimited
        // -- mirroring `rpcs::authentication::create_account`'s own read of
        // `media_settings.default_user_media_allocation_bytes` (always `Some` in practice, per that
        // read's own comment on `ToProtoServerConfiguration::to_proto`'s deserialize-with-fallback).
        PurchaseType::MediaStorage => {
            let server_configuration = get_server_configuration_proto(conn)?;
            let default_user_media_allocation_bytes = server_configuration
                .media_settings
                .as_ref()
                .map(|m| m.default_user_media_allocation_bytes as i64);
            diesel::update(users::table.filter(users::id.eq(buyer_id)))
                .set(users::media_storage_limit_bytes.eq(default_user_media_allocation_bytes))
                .execute(conn)
                .map_err(|e| {
                    log::error!(
                        "Failed to revert media storage entitlement for user {}: {:?}",
                        buyer_id,
                        e
                    );
                    Status::new(tonic::Code::Internal, "failed_to_revoke_entitlement")
                })?;
            Ok(())
        }
        // Removes exactly the permissions this subscription's own `details` granted -- a plain set
        // difference, not a reconciliation against any other subscription/grant the buyer might
        // also have (out of scope for this MVP, same "no reconciliation" simplicity noted on
        // `fulfill_purchase`'s own `PermissionsAccess` arm above).
        PurchaseType::PermissionsAccess => {
            let parsed: PermissionsAccessSubscriptionDetails =
                serde_json::from_value(details.clone()).map_err(|e| {
                    log::error!("Failed to parse PermissionsAccessSubscriptionDetails: {:?}", e);
                    Status::new(tonic::Code::Internal, "invalid_subscription_details")
                })?;
            let granted = parsed.permissions.to_proto_permissions();
            let buyer = models::get_user(buyer_id, conn)?;
            let updated_permissions: Vec<Permission> = buyer
                .permissions
                .to_proto_permissions()
                .into_iter()
                .filter(|p| !granted.contains(p))
                .collect();
            diesel::update(users::table.filter(users::id.eq(buyer_id)))
                .set(users::permissions.eq(updated_permissions.to_json_permissions()))
                .execute(conn)
                .map_err(|e| {
                    log::error!(
                        "Failed to revoke permissions entitlement for user {}: {:?}",
                        buyer_id,
                        e
                    );
                    Status::new(tonic::Code::Internal, "failed_to_revoke_entitlement")
                })?;
            Ok(())
        }
        // Out of scope for this MVP -- no automatic revocation action for either.
        PurchaseType::AiGrants | PurchaseType::RellmHosting => Ok(()),
    }
}
