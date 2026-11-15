use diesel::sql_types::Jsonb;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{subdomains, subscription_state, validate_custom_css_configuration};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::market_subscriptions;

/// *Authenticated*, the subscription's own buyer only. Saves the buyer-editable part of a
/// `PURCHASE_TYPE_SUBDOMAIN` subscription -- its `SubdomainSettings`' `share_content_from_*` toggles and
/// `custom_css_configuration` -- and nothing else (`subdomain_of`/`subdomain` are server-assigned and ignored;
/// fulfillment notes are untouched). The CSS is validated exactly like `ConfigureCustomCSS`; an unset
/// `custom_css` keeps the stored text.
pub fn save_market_subscription(
    request: SaveMarketSubscriptionRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<MarketSubscription, Status> {
    let subscription_id = request.market_subscription_id.to_db_id_or_err("market_subscription_id")?;
    let existing = models::get_market_subscription(subscription_id, conn)?;
    if existing.buyer_id != current_user.id {
        return Err(Status::new(Code::PermissionDenied, "not_your_subscription"));
    }
    if existing.product_type.to_owned().to_proto_purchase_type() != Some(PurchaseType::Subdomain) {
        return Err(Status::new(Code::InvalidArgument, "subscription_has_no_savable_settings"));
    }
    if subscription_state(
        existing.canceled_at,
        existing.renews_at,
        existing.service_terminated_at,
        std::time::SystemTime::now(),
    ) == MarketSubscriptionState::SubscriptionCanceled
    {
        return Err(Status::new(Code::FailedPrecondition, "subscription_canceled"));
    }
    let incoming = request
        .subdomain_settings
        .ok_or_else(|| Status::new(Code::InvalidArgument, "subdomain_settings_required"))?;

    let stored = subdomains::settings_of(&existing);
    let mut css = incoming.custom_css_configuration.clone();
    if let Some(css) = css.as_mut() {
        if css.custom_css.is_none() {
            css.custom_css = stored.custom_css_configuration.as_ref().and_then(|c| c.custom_css.clone());
        }
        validate_custom_css_configuration(css, conn)?;
    }
    let saved = SubdomainSettings {
        // Server-assigned: always whatever is stored.
        subdomain_of: stored.subdomain_of,
        subdomain: stored.subdomain,
        share_content_from_followers: incoming.share_content_from_followers,
        share_content_from_following: incoming.share_content_from_following,
        share_content_from_friends: incoming.share_content_from_friends,
        // No css sent at all -> keep what is stored.
        custom_css_configuration: css.or(stored.custom_css_configuration),
    };
    let settings_json = serde_json::to_value(&saved).map_err(|e| {
        log::error!("Failed to serialize SubdomainSettings: {:?}", e);
        Status::new(Code::Internal, "failed_to_serialize_details")
    })?;

    // `jsonb_set` on just the `settings` key, so a concurrent fulfillment note/read marker write isn't undone.
    diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(existing.id)))
        .set(
            market_subscriptions::details.eq(diesel::dsl::sql::<Jsonb>(
                "jsonb_set(market_subscriptions.details, '{settings}', ",
            )
            .bind::<Jsonb, _>(settings_json)
            .sql(", true)")),
        )
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to save subdomain settings: {:?}", e);
            Status::new(Code::Internal, "failed_to_update_subscription")
        })?;

    build_subscription(existing.id, conn)
}
