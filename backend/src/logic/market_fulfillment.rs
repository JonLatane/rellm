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
        // Mirrors `AiGrants`' "no revoke-on-lapse" behavior too: a subscription that stops
        // renewing simply stops re-granting, it doesn't claw back permissions already applied --
        // same no-retry/no-reconciliation MVP simplicity as the rest of this module.
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
