use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::contact_integrations_status::{
    gather_status, load_provider_configs, StatusEnv,
};
use crate::logic::http_client::run_blocking;
use crate::models;
use crate::protos::{ContactIntegrationsStatus, Permission};
use crate::rpcs::validations::validate_permission;

/// See `GetContactIntegrationsStatus` in `rellm.proto`. Admin-only. Calls every configured SMS/email
/// provider's own API (and looks up the sending domains' DNS records) *live*, concurrently and with
/// per-call timeouts -- see `logic::contact_integrations_status` for exactly what is checked.
pub fn get_contact_integrations_status(
    _request: (),
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<ContactIntegrationsStatus, Status> {
    get_contact_integrations_status_with(user, conn, &StatusEnv::production())
}

/// Same, with the environment (provider base URL override, DNS resolver, timeouts) injectable so
/// specs can point it at local mock servers.
pub fn get_contact_integrations_status_with(
    user: &models::User,
    conn: &mut PgPooledConnection,
    env: &StatusEnv,
) -> Result<ContactIntegrationsStatus, Status> {
    validate_permission(&Some(user), Permission::Admin)?;
    let configs = load_provider_configs(conn);
    // The checks block on network I/O (on their own scoped threads), so make sure we don't stall
    // an async worker thread while waiting for them.
    Ok(run_blocking(|| gather_status(&configs, env)))
}
