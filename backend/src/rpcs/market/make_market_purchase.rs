use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{stripe_product_name, stripe_sync};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use crate::rpcs::market::create_market_product::validate_permissions_are_purchasable;

/// *Authenticated*. Starts (or resumes) buying a `MarketProduct` -- creates a Stripe Checkout
/// Session and returns its hosted URL. Deliberately does **not** create any `MarketPurchase`/
/// `MarketSubscription` row itself -- see this RPC's own proto doc: fulfillment only ever happens
/// from `web::stripe_webhook`'s `checkout.session.completed` handler (or, for recurring
/// subscriptions, `logic::market_renewal`), so an abandoned checkout never leaves a half-created
/// purchase behind.
pub fn make_market_purchase(
    request: MakeMarketPurchaseRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MakeMarketPurchaseResponse, Status> {
    let server_configuration = get_server_configuration_proto(conn)?;
    // `market_settings.enabled` is the admin's own "is Market open at all" toggle (see that
    // field's own proto doc) -- checked first, ahead of everything product-specific, since an
    // admin who's turned Market off entirely shouldn't have that bypassable by simply knowing a
    // still-valid product id. Defense in depth: `Pages.Market`'s own listing already hides a
    // disabled server's products from federated browsing, and `Components.Pages.MarketPage`/
    // `ProductPage` grey out their own "Buy" buttons the same way they do for
    // `stripe_configured` -- but a direct `MakeMarketPurchase` call (or a UI that hasn't caught up
    // yet) must still be rejected server-side.
    let market_enabled = server_configuration.market_settings.as_ref().is_some_and(|m| m.enabled);
    if !market_enabled {
        return Err(Status::new(Code::FailedPrecondition, "market_disabled"));
    }

    let product_id = request.market_product_id.to_db_id_or_err("market_product_id")?;
    let product = models::get_market_product(product_id, conn)?;
    if product.delisted_at.is_some() {
        return Err(Status::new(Code::FailedPrecondition, "product_delisted"));
    }
    // `available_count == 0` means no cap (see that field's own doc) -- otherwise, once
    // `sold_count` catches up, no one new can start a checkout for this product.
    if product.available_count > 0 && product.sold_count >= product.available_count {
        return Err(Status::new(Code::FailedPrecondition, "product_sold_out"));
    }
    let purchase_type = product
        .product_type
        .to_owned()
        .to_proto_purchase_type()
        .unwrap_or(PurchaseType::MediaStorage);

    // Only meaningful (and required) for `PURCHASE_TYPE_RELLM_HOSTING` -- see
    // `MakeMarketPurchaseRequest.rellm_hosting_details`'s own doc.
    if purchase_type == PurchaseType::RellmHosting && request.rellm_hosting_details.is_none() {
        return Err(Status::new(Code::InvalidArgument, "rellm_hosting_details_required"));
    }

    // Re-validates against `PURCHASABLE_PERMISSIONS` at purchase time too, not just at
    // Create/UpdateMarketProduct time -- see `validate_permissions_are_purchasable`'s own doc.
    if purchase_type == PurchaseType::PermissionsAccess {
        let parsed: PermissionsAccessSubscriptionDetails = serde_json::from_value(product.details.clone())
            .map_err(|e| {
                log::error!(
                    "Failed to parse PermissionsAccessSubscriptionDetails for product {}: {:?}",
                    product.id,
                    e
                );
                Status::new(Code::Internal, "invalid_product_details")
            })?;
        validate_permissions_are_purchasable(&parsed.permissions)?;
    }

    // `usable_server_stripe_config`, not `get_server_configuration_proto(conn)?.stripe_config` --
    // `ToProtoServerConfiguration::to_proto` always blanks `stripe_secret_key` (write-only, same as
    // `TwilioConfig.twilio_api_key_secret`), so reading it off the *proto* form here would find it
    // empty and report "not configured" even on a fully-configured server.
    let stripe_config = stripe_sync::usable_server_stripe_config(conn)
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "stripe_not_configured"))?;

    // Same constraint `rpcs::posts::sync_post` documents on its own `post_url`/`media` -- this is a
    // gRPC RPC, not a Rocket route, so there's no HTTP `Host` header to build an absolute URL from;
    // `external_cdn_config.frontend_host` is the only source of this server's own public domain
    // available here, and Stripe requires real `success_url`/`cancel_url`s, so (unlike `sync_post`,
    // which can just omit `post_url`) an unconfigured host has to be a hard error.
    let frontend_host = server_configuration
        .external_cdn_config
        .as_ref()
        .map(|c| c.frontend_host.clone())
        .filter(|h| !h.trim().is_empty())
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "frontend_host_not_configured"))?;
    let success_url = format!("https://{frontend_host}/market/product/{}", product.id.to_proto_id());
    let cancel_url = success_url.clone();

    let currency = stripe_sync::currency_code(product.currency as u32)?;

    let mut metadata: Vec<(String, String)> = vec![
        ("rellm_user_id".to_string(), current_user.id.to_proto_id()),
        ("rellm_market_product_id".to_string(), product.id.to_proto_id()),
    ];
    if let Some(details) = &request.rellm_hosting_details {
        metadata.push(("rellm_hosting_domain".to_string(), details.domain.clone()));
        metadata.push((
            "rellm_hosting_contact_email".to_string(),
            details.contact_email.clone(),
        ));
        metadata.push((
            "rellm_hosting_additional_information".to_string(),
            details.additional_information.clone(),
        ));
    }

    // Falls back to `name`/`"Rellm"` the same way `web::robots_sitemap::manifest` does -- Stripe's
    // own checkout page has no other context telling a buyer which Rellm instance they're paying
    // (see `market_summary::stripe_product_name`'s own doc).
    let server_name =
        server_configuration.server_info.clone().and_then(|i| i.name).unwrap_or_else(|| "Rellm".to_string());
    let server_short_name = server_configuration
        .server_info
        .clone()
        .and_then(|i| i.short_name)
        .unwrap_or(server_name);

    let existing_customer_id = models::get_market_customer_id_for_buyer(current_user.id, conn);
    let customer_email = existing_customer_id.is_none().then(|| {
        current_user
            .email
            .to_owned()
            .and_then(|v| serde_json::from_value::<ContactMethod>(v).ok())
            .and_then(|cm| cm.value)
            .map(|v| v.trim_start_matches("mailto:").to_string())
    }).flatten();

    // Best-effort: Stripe has no per-Checkout-Session color parameter, only an Account-level
    // branding setting (see `stripe_sync::update_account_branding_at`'s own doc) -- synced here,
    // right before creating this checkout, so a buyer's checkout page reflects this server's
    // *current* theme even if it's changed since the last purchase. A failure here logs and falls
    // through rather than blocking the purchase -- getting the buyer to Checkout at all matters
    // far more than the exact accent color once they're there.
    let colors = server_configuration.server_info.as_ref().and_then(|i| i.colors.as_ref());
    if let Some(colors) = colors {
        if let Err(e) = stripe_sync::update_account_branding_at(
            stripe_sync::DEFAULT_BASE_URL,
            &stripe_config.stripe_secret_key,
            colors.primary,
            colors.navigation,
        ) {
            log::warn!("Failed to sync Stripe account branding before checkout: {:?}", e);
        }
    }

    let checkout_url = stripe_sync::create_checkout_session_at(
        stripe_sync::DEFAULT_BASE_URL,
        &stripe_config.stripe_secret_key,
        stripe_sync::CreateCheckoutSessionParams {
            line_item: stripe_sync::CheckoutLineItem {
                currency,
                unit_amount: product.amount as u32,
                product_name: stripe_product_name(
                    &MarshalableMarketProduct(product.clone()).to_proto(),
                    &server_short_name,
                ),
            },
            customer: existing_customer_id,
            customer_email,
            success_url,
            cancel_url,
            metadata,
        },
    )?;

    Ok(MakeMarketPurchaseResponse { checkout_url })
}
