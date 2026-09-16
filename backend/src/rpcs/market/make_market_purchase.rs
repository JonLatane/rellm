use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::stripe_sync;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;

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
    let product_id = request.market_product_id.to_db_id_or_err("market_product_id")?;
    let product = models::get_market_product(product_id, conn)?;
    if product.delisted_at.is_some() {
        return Err(Status::new(Code::FailedPrecondition, "product_delisted"));
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

    // `usable_server_stripe_config`, not `get_server_configuration_proto(conn)?.stripe_config` --
    // `ToProtoServerConfiguration::to_proto` always blanks `stripe_secret_key` (write-only, same as
    // `TwilioConfig.twilio_api_key_secret`), so reading it off the *proto* form here would find it
    // empty and report "not configured" even on a fully-configured server.
    let stripe_config = stripe_sync::usable_server_stripe_config(conn)
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "stripe_not_configured"))?;

    let server_configuration = get_server_configuration_proto(conn)?;
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

    let existing_customer_id = models::get_market_customer_id_for_buyer(current_user.id, conn);
    let customer_email = existing_customer_id.is_none().then(|| {
        current_user
            .email
            .to_owned()
            .and_then(|v| serde_json::from_value::<ContactMethod>(v).ok())
            .and_then(|cm| cm.value)
            .map(|v| v.trim_start_matches("mailto:").to_string())
    }).flatten();

    let checkout_url = stripe_sync::create_checkout_session_at(
        stripe_sync::DEFAULT_BASE_URL,
        &stripe_config.stripe_secret_key,
        stripe_sync::CreateCheckoutSessionParams {
            line_item: stripe_sync::CheckoutLineItem {
                currency,
                unit_amount: product.amount as u32,
                product_name: purchase_type.as_str_name().to_string(),
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
