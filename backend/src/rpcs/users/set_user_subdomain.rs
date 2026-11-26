use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::subdomains;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::users;

/// *Authenticated*, `ADMIN` only. Enables (or withdraws the grant of) a user's Rellm Subdomain without a subscription.
/// Enabling reserves the user's label (`subdomains::claim_label`: a valid label, not one the CDN setup uses, not held
/// by another user); withdrawing only clears the grant -- an in-force subscription keeps the subdomain enabled, and
/// otherwise the label is released (the user's settings are kept). Idempotent.
pub fn set_user_subdomain(
    request: SetUserSubdomainRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<UserSubdomain, Status> {
    validate_permission(&Some(current_user), Permission::Admin)?;
    let user_id = request.user_id.to_db_id_or_err("user_id")?;
    let user = models::get_user(user_id, conn)?;
    // One transaction under the user's row lock: the label claim and the grant commit together, and a concurrent claim or
    // release for the same label (`check_label_for` releases a holder that looks unentitled) waits for it and then sees the
    // grant. A refusal (invalid/reserved/taken label) rolls back, leaving the user untouched.
    subdomains::in_transaction(conn, |conn| {
        subdomains::lock_user_row(user.id, conn)?;
        if request.enabled {
            subdomains::claim_label(&user, conn)?;
        }
        diesel::update(users::table.filter(users::id.eq(user.id)))
            .set(users::subdomain_granted_by_admin.eq(request.enabled))
            .execute(conn)
            .map_err(|e| {
                log::error!("Failed to set a user's subdomain grant: {:?}", crate::logic::log_redaction::safe_error(&e));
                Status::new(tonic::Code::Internal, "failed_to_update_user")
            })?;
        if !request.enabled {
            subdomains::release_label_if_not_enabled(user.id, conn)?;
        }
        Ok(())
    })?;
    subdomains::invalidate_cache();
    log::info!("Subdomain grant for user {} set to {} by admin {}", user.id, request.enabled, current_user.id);
    let subscribed = subdomains::has_subscription(user.id, conn)?;
    let frontend_host = models::get_subdomain_frontend_host(user.id, conn)?;
    Ok(subdomains::user_subdomain_proto(&models::get_subdomain_summary(user.id, conn)?, subscribed, frontend_host))
}
