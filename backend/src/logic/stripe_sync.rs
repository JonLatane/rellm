//! REST calls to Stripe's API (`api.stripe.com`), backing `protos/market.proto`'s Rellm
//! Marketplace -- mirrors `logic::twilio_sync`'s `_at`-suffixed testable shape (Bearer auth,
//! form-encoded body, since Stripe's REST API is form-encoded exactly like Twilio's). No Stripe
//! SDK crate -- plain `reqwest`, same as every other external-provider integration in this repo.

use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::http_client::blocking_json_request;
use crate::protos::StripeConfig;
use crate::rpcs::get_server_configuration_model;

pub const DEFAULT_BASE_URL: &str = "https://api.stripe.com";

/// This server's own `StripeConfig`, straight off the DB (not admin-stripped -- only ever called
/// from server-side logic, never handed to a client) -- mirrors
/// `logic::contact_verification::server_twilio_config`/`server_bird_config`.
pub fn server_stripe_config(conn: &mut PgPooledConnection) -> Option<StripeConfig> {
    get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.stripe_config)
        .and_then(|c| serde_json::from_value::<StripeConfig>(c).ok())
}

/// Same as `server_stripe_config`, but additionally requires `stripe_enabled` and a non-blank
/// `stripe_secret_key` -- what every real caller (`rpcs::market::make_market_purchase`,
/// `logic::market_renewal`) actually needs before it can call the Stripe API at all.
pub fn usable_server_stripe_config(conn: &mut PgPooledConnection) -> Option<StripeConfig> {
    server_stripe_config(conn).filter(|c| c.stripe_enabled && !c.stripe_secret_key.is_empty())
}

/// Numeric ISO 4217 currency code -> Stripe's lowercase alpha currency code. A small, common-currency
/// set Stripe supports well -- matches `market_summary::format_price`'s own display table exactly, so
/// every currency an admin can pick in the Elm product form is actually purchasable. Structured to
/// extend, not a full ISO 4217 table.
pub fn currency_code(currency: u32) -> Result<&'static str, Status> {
    match currency {
        840 => Ok("usd"),
        978 => Ok("eur"),
        826 => Ok("gbp"),
        124 => Ok("cad"),
        36 => Ok("aud"),
        392 => Ok("jpy"),
        756 => Ok("chf"),
        _ => Err(Status::new(Code::InvalidArgument, "unsupported_currency")),
    }
}

/// Whether `currency` has no minor unit (e.g. Japanese yen has no "cents") -- Stripe's own
/// zero-decimal currency list (a superset of this); only JPY is reachable through the currencies
/// `currency_code` actually supports today. `MarketProduct.amount` is still always a plain integer
/// (see that field's own proto doc) -- for a zero-decimal currency it's simply the whole-unit amount
/// itself (e.g. `500` = &yen;500), which is already exactly what Stripe's `unit_amount` wants with no
/// further conversion, so this only matters for *display* (`market_summary::format_price`) and the
/// Elm admin form's own amount-input label, not for anything sent to Stripe.
pub fn is_zero_decimal_currency(currency: u32) -> bool {
    matches!(currency, 392)
}

/// One Stripe Checkout Session line item -- a single `price_data`-based item (no pre-created
/// Stripe Price object needed), always quantity 1 for the Marketplace's single-product checkouts.
pub struct CheckoutLineItem {
    pub currency: &'static str,
    /// The smallest-currency-unit amount (e.g. cents for USD) -- same unit as `Product.amount`.
    pub unit_amount: u32,
    pub product_name: String,
}

pub struct CreateCheckoutSessionParams {
    pub line_item: CheckoutLineItem,
    /// An existing Stripe Customer id to bill, if the buyer already has one on file (from a prior
    /// purchase's webhook-recorded `Subscription.stripe_customer_id`). Mutually exclusive with
    /// `customer_email` -- Stripe creates a fresh Customer automatically when only an email is
    /// given, which the webhook then records for next time (see `web::stripe_webhook`).
    pub customer: Option<String>,
    pub customer_email: Option<String>,
    pub success_url: String,
    pub cancel_url: String,
    /// Carried through to the completed Checkout Session's `metadata` -- read back by
    /// `web::stripe_webhook` to know what to fulfill (`rellm_user_id`/`product_id`/any
    /// `RellmHostingPurchaseDetails` fields).
    pub metadata: Vec<(String, String)>,
    /// What shows up on the buyer's own bank/card statement for this charge, e.g. `"Rellm.org"` --
    /// this server's own `ServerInfo.short_name`/`name` (see `rpcs::market::make_market_purchase`'s
    /// own `server_short_name`), *not yet* sanitized to Stripe's `statement_descriptor` rules --
    /// `create_checkout_session_at` does that itself (`sanitize_statement_descriptor`), same
    /// division of labor as `CheckoutLineItem.product_name`/`stripe_product_name` (callers build a
    /// human-readable string, this module owns Stripe's own format rules for it).
    pub statement_descriptor: String,
}

/// Stripe's own `statement_descriptor` rules (https://stripe.com/docs/payments/account/statement-descriptors):
/// at most 22 characters, and never containing `< > \ ' "`. Not exhaustive (Stripe enforces a few
/// more rules server-side, e.g. requiring at least one letter) -- this is a best-effort local
/// sanitizer so an obviously-invalid descriptor (too long, or carrying a character Stripe's own API
/// would reject outright) doesn't need a round trip to find out; `create_checkout_session_at`'s own
/// error surfacing (see that function's doc) still shows Stripe's real rejection reason if this
/// sanitizer missed something. Falls back to `"Rellm"` if sanitizing leaves nothing at all (e.g. a
/// server name made up entirely of disallowed characters).
pub fn sanitize_statement_descriptor(raw: &str) -> String {
    let cleaned: String = raw.chars().filter(|c| !matches!(c, '<' | '>' | '\\' | '\'' | '"')).collect();
    let trimmed = cleaned.trim();
    let truncated: String = trimmed.chars().take(22).collect();
    if truncated.is_empty() {
        "Rellm".to_string()
    } else {
        truncated
    }
}

/// Creates a Stripe Checkout Session (`mode=payment`, `payment_intent_data[setup_future_usage]=off_session`
/// so the resulting PaymentMethod can be reused for off-session renewal charges later) and returns
/// its hosted `url` to redirect the buyer's browser to. See `rpcs::market::make_market_purchase`
/// for the one real caller; `base_url` is only ever overridden by specs (pointed at a local mock
/// server instead of the real Stripe API, mirroring `twilio_sync::send_sms_at`).
pub fn create_checkout_session_at(
    base_url: &str,
    secret_key: &str,
    params: CreateCheckoutSessionParams,
) -> Result<String, Status> {
    let secret_key = secret_key.to_string();
    let url = format!("{base_url}/v1/checkout/sessions");

    let mut form: Vec<(String, String)> = vec![
        ("mode".to_string(), "payment".to_string()),
        (
            "payment_intent_data[setup_future_usage]".to_string(),
            "off_session".to_string(),
        ),
        ("line_items[0][quantity]".to_string(), "1".to_string()),
        (
            "line_items[0][price_data][currency]".to_string(),
            params.line_item.currency.to_string(),
        ),
        (
            "line_items[0][price_data][unit_amount]".to_string(),
            params.line_item.unit_amount.to_string(),
        ),
        (
            "line_items[0][price_data][product_data][name]".to_string(),
            params.line_item.product_name,
        ),
        ("success_url".to_string(), params.success_url),
        ("cancel_url".to_string(), params.cancel_url),
        (
            "payment_intent_data[statement_descriptor]".to_string(),
            sanitize_statement_descriptor(&params.statement_descriptor),
        ),
    ];
    if let Some(customer) = params.customer {
        form.push(("customer".to_string(), customer));
    } else if let Some(email) = params.customer_email {
        form.push(("customer_email".to_string(), email));
    }
    for (key, value) in params.metadata {
        form.push((format!("metadata[{key}]"), value));
    }

    let (status, response_body) = blocking_json_request(
        move |client| client.post(url.clone()).bearer_auth(secret_key.clone()).form(&form),
        "stripe_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Stripe CreateCheckoutSession failed ({}): {:?}", status, response_body);
        // Stripe's own `error.message` is genuinely useful here (e.g. "The Checkout Session's
        // total amount due must add up to at least $0.50 USD" for a too-cheap product) -- surfaced
        // to the client via the Status message itself (the `Grpc.BadStatus` -> `errMessage` path
        // `Shared.AccountsPanel.grpcErrorToString` already renders verbatim for any message it
        // doesn't have a friendlier translation for), rather than the bare `stripe_checkout_session_failed`
        // key this used to always return -- that told a buyer/admin nothing actionable without a
        // server log dive. Keeps the `stripe_checkout_session_failed` prefix so it's still
        // greppable/distinguishable from other `FailedPrecondition`s in logs/client error handling.
        let stripe_message = response_body
            .get("error")
            .and_then(|e| e.get("message"))
            .and_then(|m| m.as_str())
            .unwrap_or("Stripe rejected the checkout request.");
        return Err(Status::new(
            Code::FailedPrecondition,
            format!("stripe_checkout_session_failed: {stripe_message}"),
        ));
    }
    response_body
        .get("url")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Stripe CreateCheckoutSession response missing url: {:?}", response_body);
            Status::new(Code::Internal, "stripe_checkout_session_missing_url")
        })
}

/// Looks up the `payment_method` id Stripe actually attached to a completed PaymentIntent --
/// `checkout.session.completed`'s own webhook payload doesn't include this directly (only a
/// `payment_intent` id), so `web::stripe_webhook` calls this once per initial purchase to learn
/// what to save as `market_subscriptions.stripe_payment_method_id` for later off-session renewals.
/// A card's brand/last4/expiry, as Stripe itself considers safe to display -- never a full card
/// number. Resolved from Stripe's own `PaymentMethod.card` object (`type: "card"` only -- other
/// payment method types, e.g. bank debits, resolve to `None`).
#[derive(Debug, Clone)]
pub struct CardDetails {
    pub brand: String,
    pub last4: String,
    pub exp_month: u32,
    pub exp_year: u32,
}

fn card_details_from_payment_method_json(payment_method: &serde_json::Value) -> Option<CardDetails> {
    let card = payment_method.get("card")?;
    Some(CardDetails {
        brand: card.get("brand").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        last4: card.get("last4").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        exp_month: card.get("exp_month").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
        exp_year: card.get("exp_year").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
    })
}

/// The payment method actually used for `payment_intent_id`, plus its card details in the same
/// round trip (`?expand[]=payment_method` inlines the full PaymentMethod object rather than just
/// its id, avoiding a second request) -- used right after a Checkout Session completes, when all
/// we have is the PaymentIntent id.
pub struct PaymentIntentPaymentMethod {
    pub payment_method_id: Option<String>,
    pub card: Option<CardDetails>,
}

pub fn get_payment_intent_payment_method_at(
    base_url: &str,
    secret_key: &str,
    payment_intent_id: &str,
) -> Result<PaymentIntentPaymentMethod, Status> {
    let secret_key = secret_key.to_string();
    let url = format!("{base_url}/v1/payment_intents/{payment_intent_id}?expand[]=payment_method");

    let (status, response_body) = blocking_json_request(
        move |client| client.get(url.clone()).bearer_auth(secret_key.clone()),
        "stripe_request_failed",
    )?;
    if !status.is_success() {
        log::error!(
            "Stripe GetPaymentIntent({}) failed ({}): {:?}",
            payment_intent_id,
            status,
            response_body
        );
        return Err(Status::new(Code::FailedPrecondition, "stripe_get_payment_intent_failed"));
    }
    let payment_method = response_body.get("payment_method");
    Ok(PaymentIntentPaymentMethod {
        payment_method_id: payment_method
            .and_then(|v| v.get("id").and_then(|id| id.as_str()).or_else(|| v.as_str()))
            .map(str::to_string),
        card: payment_method.and_then(card_details_from_payment_method_json),
    })
}

/// A previously-known PaymentMethod's card details, fetched fresh (e.g. right before recording a
/// renewal `MarketPayment`, where the payment method id is already on file on the
/// `MarketSubscription` -- no PaymentIntent lookup needed, unlike
/// `get_payment_intent_payment_method_at`).
pub fn get_payment_method_card_at(
    base_url: &str,
    secret_key: &str,
    payment_method_id: &str,
) -> Result<Option<CardDetails>, Status> {
    let secret_key = secret_key.to_string();
    let url = format!("{base_url}/v1/payment_methods/{payment_method_id}");

    let (status, response_body) = blocking_json_request(
        move |client| client.get(url.clone()).bearer_auth(secret_key.clone()),
        "stripe_request_failed",
    )?;
    if !status.is_success() {
        log::error!(
            "Stripe GetPaymentMethod({}) failed ({}): {:?}",
            payment_method_id,
            status,
            response_body
        );
        return Err(Status::new(Code::FailedPrecondition, "stripe_get_payment_method_failed"));
    }
    Ok(card_details_from_payment_method_json(&response_body))
}

pub struct OffSessionPaymentIntentParams {
    pub customer_id: String,
    pub payment_method_id: String,
    pub currency: &'static str,
    pub amount: u32,
    pub metadata: Vec<(String, String)>,
}

/// A successfully-charged off-session renewal PaymentIntent -- `id` is stored as
/// `market_payments.stripe_payment_intent_id`.
pub struct OffSessionPaymentIntentResult {
    pub id: String,
}

/// Charges a renewal via a previously-saved Customer/PaymentMethod pair (`off_session=true,
/// confirm=true`) -- used by `logic::market_renewal`. Returns `Err` (mapped by the caller to
/// "cancel the subscription, no retry" -- see `market_renewal`'s own doc) on any non-`succeeded`
/// result, including one requiring further authentication (`requires_action`), since there's no
/// user present to complete it off-session.
pub fn create_off_session_payment_intent_at(
    base_url: &str,
    secret_key: &str,
    params: OffSessionPaymentIntentParams,
) -> Result<OffSessionPaymentIntentResult, Status> {
    let secret_key = secret_key.to_string();
    let url = format!("{base_url}/v1/payment_intents");

    let mut form: Vec<(String, String)> = vec![
        ("amount".to_string(), params.amount.to_string()),
        ("currency".to_string(), params.currency.to_string()),
        ("customer".to_string(), params.customer_id),
        ("payment_method".to_string(), params.payment_method_id),
        ("off_session".to_string(), "true".to_string()),
        ("confirm".to_string(), "true".to_string()),
    ];
    for (key, value) in params.metadata {
        form.push((format!("metadata[{key}]"), value));
    }

    let (status, response_body) = blocking_json_request(
        move |client| client.post(url.clone()).bearer_auth(secret_key.clone()).form(&form),
        "stripe_request_failed",
    )?;
    let stripe_status = response_body.get("status").and_then(|v| v.as_str()).unwrap_or("");
    if !status.is_success() || stripe_status != "succeeded" {
        log::warn!(
            "Stripe off-session PaymentIntent did not succeed ({}, status={}): {:?}",
            status,
            stripe_status,
            response_body
        );
        return Err(Status::new(Code::FailedPrecondition, "stripe_payment_intent_failed"));
    }
    let id = response_body
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Stripe PaymentIntent response missing id: {:?}", response_body);
            Status::new(Code::Internal, "stripe_payment_intent_missing_id")
        })?;
    Ok(OffSessionPaymentIntentResult { id })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_statement_descriptor_passes_a_short_clean_name_through_unchanged() {
        assert_eq!(sanitize_statement_descriptor("Rellm.org"), "Rellm.org");
    }

    #[test]
    fn sanitize_statement_descriptor_truncates_to_22_characters() {
        assert_eq!(
            sanitize_statement_descriptor("A Very Long Community Name Indeed"),
            "A Very Long Community "
        );
    }

    #[test]
    fn sanitize_statement_descriptor_strips_disallowed_characters() {
        assert_eq!(sanitize_statement_descriptor("Jon's <Rellm> \"Server\""), "Jons Rellm Server");
    }

    #[test]
    fn sanitize_statement_descriptor_falls_back_to_rellm_when_nothing_survives() {
        assert_eq!(sanitize_statement_descriptor("<<<>>>"), "Rellm");
        assert_eq!(sanitize_statement_descriptor("   "), "Rellm");
    }
}
