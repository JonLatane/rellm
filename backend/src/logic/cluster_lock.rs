//! Cluster-wide resource locking for `bin/` background jobs -- see `ClusterResources`'s own doc in
//! server_configuration.proto for the overall design (a "conductor" instance brokers
//! `LockClusterResources`/`FreeClusterResources` for every instance in a cluster, including
//! itself). Shared between `bin/generate_preview_images.rs` (the `CLUSTER_RESOURCE_BROWSER` job
//! that motivated all of this) and `bin/convert_media_sizes.rs` (`CLUSTER_RESOURCE_FFMPEG`/
//! `CLUSTER_RESOURCE_IMAGEMAGICK`), so both jobs poll/connect/release identically.

use std::time::Duration;

use tonic::transport::{Channel, ClientTlsConfig};

use crate::protos::rellm_client::RellmClient;
use crate::protos::{
    ClusterResource, ClusterResources, FreeClusterResourcesRequest, LockClusterResourcesRequest,
};

const LOCK_POLL_INTERVAL: Duration = Duration::from_secs(5);
const LOCK_MAX_WAIT: Duration = Duration::from_secs(180);

/// Polls `LockClusterResources` on the conductor until it grants every resource in `wanted` to
/// this instance or `LOCK_MAX_WAIT` elapses (returning `false` in the latter case -- there's no
/// server-side queueing, see `LockClusterResourcesResponse`'s own doc). Also backs off and
/// retries on a connection/RPC error (e.g. the conductor briefly unreachable), rather than
/// failing the whole job over a transient network blip.
pub async fn acquire_cluster_lock(resources: &ClusterResources, wanted: &[ClusterResource]) -> bool {
    let deadline = tokio::time::Instant::now() + LOCK_MAX_WAIT;
    loop {
        match try_lock_cluster_resources(resources, wanted).await {
            Ok(true) => return true,
            Ok(false) => log::info!("Cluster resource lock held by another namespace; waiting..."),
            Err(e) => log::warn!("Error calling LockClusterResources: {:?}", e),
        }
        if tokio::time::Instant::now() >= deadline {
            return false;
        }
        tokio::time::sleep(LOCK_POLL_INTERVAL).await;
    }
}

async fn try_lock_cluster_resources(
    resources: &ClusterResources,
    wanted: &[ClusterResource],
) -> Result<bool, anyhow::Error> {
    let mut client = cluster_client(resources).await?;
    let mut request = tonic::Request::new(LockClusterResourcesRequest {
        namespace_id: resources.namespace_id.clone(),
        resources: wanted.iter().map(|r| *r as i32).collect(),
    });
    request
        .metadata_mut()
        .insert("cluster-shared-secret", resources.cluster_shared_secret.parse()?);
    let response = client.lock_cluster_resources(request).await?.into_inner();
    Ok(response.granted)
}

/// Best-effort: logs and gives up on error rather than panicking -- the job's container exiting
/// doesn't clear a lock recorded in the conductor's database the way it would an in-memory one, so
/// a failed release here does leak the lock until manually cleared (see `free_all_cluster_resources`,
/// a `bin/` admin tool). Not retried; a transient failure here is rare enough (this runs right
/// after a successful `LockClusterResources` call to the same conductor) not to be worth another
/// poll loop.
pub async fn release_cluster_lock(resources: &ClusterResources, held: &[ClusterResource]) {
    let result: Result<(), anyhow::Error> = async {
        let mut client = cluster_client(resources).await?;
        let mut request = tonic::Request::new(FreeClusterResourcesRequest {
            namespace_id: resources.namespace_id.clone(),
            resources: held.iter().map(|r| *r as i32).collect(),
        });
        request
            .metadata_mut()
            .insert("cluster-shared-secret", resources.cluster_shared_secret.parse()?);
        client.free_cluster_resources(request).await?;
        Ok(())
    }
    .await;
    if let Err(e) = result {
        log::error!(
            "Error calling FreeClusterResources (lock may be stuck held): {:?}",
            e
        );
    }
}

/// Connects to `resources.conductor_host` on the standard Rellm gRPC port, first resolving it
/// through the usual [`GET /backend_host`](#http-based-client-host-negotiation-for-external-cdns-get-backend_host)
/// negotiation (see `ClusterResources.conductor_host`'s own doc) in case it sits behind an
/// external CDN. Uses plaintext HTTP (no TLS) when `conductor_host` is literally `localhost` --
/// a local dev conductor has no cert to terminate TLS with -- and HTTPS otherwise, in which case
/// `tls_config` must be set explicitly (tonic refuses to connect an `https://` `Endpoint` with no
/// TLS config at all, rather than silently picking a default) -- `with_enabled_roots()` picks up
/// whichever of `tls-native-roots`/`tls-webpki-roots` this binary was built with, and `domain_name`
/// is pinned to `conductor_host` itself (not `host`, which -- per the CDN case above -- may be a
/// different address entirely) so SNI/cert validation targets the hostname the conductor's own
/// Cert-Manager cert (and Traefik's SNI-based routing) actually expect.
async fn cluster_client(resources: &ClusterResources) -> Result<RellmClient<Channel>, anyhow::Error> {
    let host = discover_backend_host(&resources.conductor_host).await;
    let scheme = if resources.conductor_host == "localhost" {
        "http"
    } else {
        "https"
    };
    let mut endpoint =
        Channel::from_shared(format!("{scheme}://{host}:27707"))?.timeout(Duration::from_secs(10));
    if scheme == "https" {
        endpoint = endpoint.tls_config(
            ClientTlsConfig::new()
                .with_enabled_roots()
                .domain_name(resources.conductor_host.clone()),
        )?;
    }
    let channel = endpoint.connect().await?;
    Ok(RellmClient::new(channel))
}

async fn discover_backend_host(host: &str) -> String {
    let host = host.to_string();
    let lookup = move || {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap();
        for scheme in ["https", "http"] {
            if let Ok(response) = client.get(format!("{scheme}://{host}/backend_host")).send() {
                if response.status().is_success() {
                    if let Ok(body) = response.text() {
                        let body = body.trim();
                        if !body.is_empty() {
                            return body.to_string();
                        }
                    }
                }
            }
        }
        host
    };
    // `reqwest::blocking` panics if called directly from a Tokio worker thread -- callers here
    // are all `#[tokio::main]` `bin/`s, so route it through `block_in_place` the same way
    // `logic::http_client::run_blocking` does for in-process (non-`bin/`) callers.
    tokio::task::block_in_place(lookup)
}
