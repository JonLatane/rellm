//! What the Rocket handlers need to be Rellm-Subdomain-aware (see `logic::subdomains`): the virtual configuration for
//! a request's host, and the scope the feeds are limited to.

use rocket::http::uri::Host;

use crate::db_connection::PgPooledConnection;
use crate::logic::subdomains::{resolve_subdomain, SubdomainContext};
use crate::protos::ServerConfiguration;
use crate::rpcs::get_server_configuration_proto;

/// The subdomain `host` addresses, if any (anonymous viewer -- these are public pages and feeds).
pub fn request_subdomain(conn: &mut PgPooledConnection, host: &Host<'_>) -> Option<SubdomainContext> {
    resolve_subdomain(Some(&host.to_string()), conn).ok().flatten()
}

/// The `ServerConfiguration` a public page for `host` is built from: the server's own, or -- on a subdomain -- the
/// owner's virtual one (their name, username and bio, as public as their profile is), so link previews and titles
/// describe the subdomain rather than the parent server.
pub fn request_configuration(conn: &mut PgPooledConnection, host: &Host<'_>) -> ServerConfiguration {
    let configuration = get_server_configuration_proto(conn).unwrap();
    match request_subdomain(conn, host) {
        Some(subdomain) => subdomain.virtual_server_configuration(configuration, &None),
        None => configuration,
    }
}

/// The public frontend domain for links in a feed served at `host`: the subdomain itself on a subdomain.
pub fn feed_frontend_domain(configured_frontend_domain: String, subdomain: &Option<SubdomainContext>) -> String {
    match subdomain {
        Some(subdomain) if !subdomain.settings.subdomain.is_empty() => {
            format!("{}.{}", subdomain.settings.subdomain, configured_frontend_domain)
        }
        _ => configured_frontend_domain,
    }
}
