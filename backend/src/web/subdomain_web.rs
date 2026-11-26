//! What the Rocket handlers need to be Rellm-Subdomain-aware (see `logic::subdomains`): the virtual configuration for
//! a request's host, and the scope the feeds are limited to.

use rocket::http::uri::Host;

use crate::db_connection::PgPooledConnection;
use crate::logic::subdomains::{resolve_subdomain, SubdomainContext};
use crate::protos::ServerConfiguration;
use crate::rpcs::get_server_configuration_proto;

/// The subdomain `host` addresses, if any (anonymous viewer -- these are public pages and feeds). A failed lookup is
/// an error, never `None`: `None` means "the parent server", and a feed that quietly fell back to it would publish the
/// parent's content on someone's subdomain.
pub fn request_subdomain(
    conn: &mut PgPooledConnection,
    host: &Host<'_>,
) -> Result<Option<SubdomainContext>, tonic::Status> {
    resolve_subdomain(Some(&host.to_string()), conn)
}

/// The `ServerConfiguration` a public page for `host` is built from: the server's own, or -- on a subdomain -- the
/// owner's virtual one (their name, username and bio, as public as their profile is), so link previews and titles
/// describe the subdomain rather than the parent server.
pub fn request_configuration(conn: &mut PgPooledConnection, host: &Host<'_>) -> ServerConfiguration {
    let configuration = get_server_configuration_proto(conn).unwrap();
    // Like the configuration load above, a database failure fails the page (a 500) rather than quietly describing the
    // parent server on a subdomain.
    match request_subdomain(conn, host).expect("failed to look up the request's subdomain") {
        Some(subdomain) => subdomain.virtual_server_configuration(configuration, &None),
        None => configuration,
    }
}

/// The public frontend domain for links in a feed served at `request_host` (the request's own domain, no port):
/// the subdomain itself on a subdomain (its `custom_frontend_host` when it has one). `configured_frontend_domain` is the parent's configured host -- or, with
/// `cdn_grpc` on (or no CDN configuration), the request's own host, which already *is* the subdomain. That case is
/// told apart by comparing the two *whole* hosts (never a label prefix: an owner named like the parent's first
/// label, `bullcity` on `bullcity.test`, must still be prefixed), and is left as it is.
pub fn feed_frontend_domain(
    configured_frontend_domain: String,
    request_host: &str,
    subdomain: &Option<SubdomainContext>,
) -> String {
    match subdomain {
        // The owner's own domain, if they set one.
        Some(subdomain) if subdomain.settings.custom_frontend_host.as_deref().is_some_and(|host| !host.is_empty()) => {
            subdomain.settings.custom_frontend_host.clone().unwrap_or_default()
        }
        Some(subdomain) if !subdomain.settings.subdomain.is_empty() => {
            if configured_frontend_domain.eq_ignore_ascii_case(request_host) {
                configured_frontend_domain
            } else {
                format!("{}.{}", subdomain.settings.subdomain, configured_frontend_domain)
            }
        }
        _ => configured_frontend_domain,
    }
}
