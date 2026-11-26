use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{subdomains, validate_custom_css_configuration};
use crate::models;
use crate::protos::*;
use crate::schema::users;

/// *Authenticated*, the caller's own subdomain only. Saves the user-editable part of their Rellm Subdomain -- the
/// `share_content_from_*` toggles and `custom_css_configuration` -- onto their user row, and nothing else
/// (`subdomain_of`/`subdomain` are server-assigned and ignored). The subdomain must be enabled (a subscription in
/// force, or an admin's grant). The CSS is validated exactly like `ConfigureCustomCSS`; an unset `custom_css` keeps
/// the stored text, and no `custom_css_configuration` at all keeps the stored stylesheet settings. An unset
/// `custom_frontend_host` keeps the stored domain, `""` clears it, anything else is validated and claimed
/// (`subdomains::set_custom_frontend_host`).
pub fn save_subdomain_settings(
    request: SaveSubdomainSettingsRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<UserSubdomain, Status> {
    let incoming = request
        .subdomain_settings
        .ok_or_else(|| Status::new(Code::InvalidArgument, "subdomain_settings_required"))?;
    let summary = models::get_subdomain_summary(current_user.id, conn)?;
    let subscribed = subdomains::has_subscription(current_user.id, conn)?;
    if !(summary.subdomain_granted_by_admin || subscribed) {
        return Err(Status::new(Code::FailedPrecondition, "subdomain_not_enabled"));
    }

    let mut css = incoming.custom_css_configuration.clone();
    let stored_css_json = if css.is_some() { models::get_subdomain_custom_css(current_user.id, conn)? } else { None };
    if let Some(css) = css.as_mut() {
        if css.custom_css.is_none() {
            css.custom_css = stored_css_json
                .and_then(|v| serde_json::from_value::<CustomCssConfiguration>(v).ok())
                .and_then(|c| c.custom_css);
        }
        validate_custom_css_configuration(css, conn)?;
    }
    let css_json = css
        .map(|css| {
            serde_json::to_value(&css).map_err(|e| {
                log::error!("Failed to serialize CustomCSSConfiguration: {:?}", e);
                Status::new(Code::Internal, "failed_to_serialize_details")
            })
        })
        .transpose()?;

    // The owner's own frontend domain: unset keeps it, an empty string clears it. Before anything is written, so a refusal
    // (invalid, reserved, taken) saves nothing.
    if let Some(requested) = incoming.custom_frontend_host.as_deref() {
        subdomains::set_custom_frontend_host(current_user, requested, conn)?;
    }

    let (followers, following, friends) = if request.keep_sharing_settings {
        (summary.subdomain_share_followers, summary.subdomain_share_following, summary.subdomain_share_friends)
    } else {
        (
            incoming.share_content_from_followers,
            incoming.share_content_from_following,
            incoming.share_content_from_friends,
        )
    };
    let target = users::table.filter(users::id.eq(current_user.id));
    diesel::update(target)
        .set((
            users::subdomain_share_followers.eq(followers),
            users::subdomain_share_following.eq(following),
            users::subdomain_share_friends.eq(friends),
        ))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to save subdomain settings: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_update_user")
        })?;
    // No stylesheet sent at all -> the stored one is untouched.
    if let Some(css_json) = css_json {
        diesel::update(users::table.filter(users::id.eq(current_user.id)))
            .set(users::subdomain_custom_css.eq(Some(css_json)))
            .execute(conn)
            .map_err(|e| {
                log::error!("Failed to save subdomain stylesheet: {:?}", crate::logic::log_redaction::safe_error(&e));
                Status::new(Code::Internal, "failed_to_update_user")
            })?;
    }

    subdomains::invalidate_cache();
    let frontend_host = models::get_subdomain_frontend_host(current_user.id, conn)?;
    Ok(subdomains::user_subdomain_proto(&models::get_subdomain_summary(current_user.id, conn)?, subscribed, frontend_host))
}
