use rocket::http::uri::Host;
use rocket::{routes, Route, State};
use rocket_cache_response::CacheResponse;

use super::RocketState;
use crate::{protos::ExternalCdnConfig, rpcs::get_server_configuration_proto};

lazy_static! {
    pub static ref EXTERNAL_CDN_PAGES: Vec<Route> = routes![backend_host, frontend_host];
}

#[rocket::get("/backend_host")]
async fn backend_host(state: &State<RocketState>, host: &Host<'_>) -> CacheResponse<String> {
    let configured_backend_domain = configured_backend_domain(state, host);
    CacheResponse::no_store(configured_backend_domain)
}

#[rocket::get("/frontend_host")]
async fn frontend_host(state: &State<RocketState>, host: &Host<'_>) -> CacheResponse<String> {
    let configured_backend_domain = configured_backend_domain(state, host);
    CacheResponse::no_store(configured_backend_domain)
}

pub fn configured_backend_domain(state: &State<RocketState>, host: &Host<'_>) -> String {
    backend_domain_for_host(external_cdn_config(state).as_ref(), &host.domain().to_string(), || {
        // Only a host with an *active subscription* behind it is a subdomain -- not merely any label under the
        // frontend host. In particular the backend host itself (`backend.rellm.org` under a `rellm.org` frontend)
        // must be told its backend is itself, never `backend.backend.rellm.org`.
        let mut conn = state.pool.get().unwrap();
        crate::web::subdomain_web::request_subdomain(&mut conn, host)
            .expect("failed to look up the request's subdomain")
            .map(|subdomain| subdomain.settings.subdomain)
    })
}

/// What `/backend_host` answers for a request to `host_domain`: the configured `backend_host` -- or, for a Rellm
/// Subdomain (`jon.rellm.org`, found by `resolve_subdomain`, consulted only when a separate backend host is configured),
/// its own backend name `jon.<backend_host>`, so gRPC to it arrives with a `Host` that says which subdomain it is for (see
/// `logic::subdomains`). With `cdn_grpc` on, or no backend host, the request's own host is the backend.
pub fn backend_domain_for_host(
    cdn_config: Option<&ExternalCdnConfig>,
    host_domain: &str,
    resolve_subdomain_label: impl FnOnce() -> Option<String>,
) -> String {
    match cdn_config {
        Some(cdn_config) if !cdn_config.cdn_grpc && !cdn_config.backend_host.is_empty() => {
            match resolve_subdomain_label() {
                Some(label) => format!("{label}.{}", cdn_config.backend_host),
                None => cdn_config.backend_host.clone(),
            }
        }
        _ => host_domain.to_string(),
    }
}

pub fn configured_frontend_domain(state: &State<RocketState>, host: &Host<'_>) -> String {
    match external_cdn_config(state) {
        Some(cdn_config) => match (cdn_config.frontend_host, cdn_config.cdn_grpc) {
            (frontend_host, false) if frontend_host != "" => frontend_host,
            _ => host.domain().to_string(),
        },
        None => host.domain().to_string(),
    }
}

pub fn external_cdn_config(state: &State<RocketState>) -> Option<ExternalCdnConfig> {
    let mut conn = state.pool.get().unwrap();
    get_server_configuration_proto(&mut conn)
        .unwrap()
        .external_cdn_config
}
