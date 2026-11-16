//! The Subdomain-aware variants of the RPCs a Rellm Subdomain (`jon.bullcity.social`, see
//! `logic::subdomains`) answers differently from its parent server. Each takes the `SubdomainContext` the
//! gRPC service resolved from the request's host (`None` = the request is for the parent server itself, and
//! the call behaves exactly like the plain RPC).

use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::subdomains::SubdomainContext;
use crate::models;
use crate::protos::*;

pub fn get_server_configuration_for(
    request: (),
    user: &Option<&models::User>,
    scope: &Option<SubdomainContext>,
    conn: &mut PgPooledConnection,
) -> Result<ServerConfiguration, Status> {
    let config = crate::rpcs::get_server_configuration(request, user, conn)?;
    Ok(match scope {
        Some(subdomain) => subdomain.virtual_server_configuration(config, user),
        None => config,
    })
}

pub fn get_custom_css_for(
    request: (),
    user: &Option<&models::User>,
    scope: &Option<SubdomainContext>,
    conn: &mut PgPooledConnection,
) -> Result<CustomCssConfiguration, Status> {
    match scope {
        Some(subdomain) => Ok(subdomain.custom_css_configuration()),
        None => crate::rpcs::get_custom_css(request, user, conn),
    }
}

pub fn get_posts_for(
    request: GetPostsRequest,
    user: &Option<&models::User>,
    scope: &Option<SubdomainContext>,
    conn: &mut PgPooledConnection,
) -> Result<GetPostsResponse, Status> {
    let only = scope.as_ref().map(|s| s.visible_author_ids(conn)).transpose()?;
    crate::rpcs::get_posts_scoped(request, user, &only, conn)
}

pub fn get_events_for(
    request: GetEventsRequest,
    user: &Option<&models::User>,
    scope: &Option<SubdomainContext>,
    conn: &mut PgPooledConnection,
) -> Result<GetEventsResponse, Status> {
    let only = scope.as_ref().map(|s| s.visible_author_ids(conn)).transpose()?;
    crate::rpcs::get_events_scoped(request, user, &only, conn)
}
