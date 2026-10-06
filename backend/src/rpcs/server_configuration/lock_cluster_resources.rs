use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::ToProtoTime;
use crate::schema::server_configurations::dsl as scd;
use crate::{models, protos};

/// Attempts to acquire `request.resources` on behalf of `request.namespace_id`. `shared_secret`
/// must match this server's own stored `cluster_shared_secret` -- that's the only requirement to
/// act as conductor for the call (see `validate_conductor`'s own doc). See
/// `ClusterResources`/`LockClusterResourcesResponse`'s own docs in
/// server_configuration.proto for the polling contract this expects of callers, and
/// `ClusterConductorState`'s own doc for why this updates the active `server_configurations` row
/// in place (via a `SELECT ... FOR UPDATE`, so two concurrent Lock calls can't both see the lock
/// as free) rather than going through `ConfigureServer`'s usual versioning.
pub fn lock_cluster_resources(
    request: protos::LockClusterResourcesRequest,
    shared_secret: &str,
    conn: &mut PgPooledConnection,
) -> Result<protos::LockClusterResourcesResponse, Status> {
    log::info!("LockClusterResources called: {:?}", request);

    // Validated once up front (a plain read, no row lock needed just to fail fast on a
    // misconfigured/unauthorized caller) before taking the `FOR UPDATE` lock below.
    let config = scd::server_configurations
        .filter(scd::active.eq(true))
        .select(models::SERVER_CONFIGURATION_COLUMNS)
        .first::<models::ServerConfiguration>(conn)
        .map_err(|_| Status::new(Code::Internal, "data_error"))?;
    validate_conductor(&config, shared_secret)?;

    let result = conn.transaction::<protos::LockClusterResourcesResponse, diesel::result::Error, _>(
        |conn| {
            let config = scd::server_configurations
                .filter(scd::active.eq(true))
                .select(models::SERVER_CONFIGURATION_COLUMNS)
                .for_update()
                .first::<models::ServerConfiguration>(conn)?;
            let mut resources: protos::ClusterResources =
                serde_json::from_value(config.cluster_resources.clone().unwrap_or_default())
                    .unwrap_or_default();
            let mut conductor_state = resources.conductor_state.clone().unwrap_or_default();

            // Each requested resource may already be held by up to its configured
            // `ClusterResourceLimit` (default `1`, see `effective_limit`) *other* namespaces
            // before this request is denied -- one already held by *this* namespace doesn't count
            // against that limit at all (it's an idempotent re-lock, e.g. a retried call after a
            // dropped response, granted the same as if nothing were held). A request naming
            // several resources is never partially granted -- see `LockClusterResourcesResponse`'s
            // own doc -- so the first resource found at its limit denies the whole thing.
            let conflict = request.resources.iter().find_map(|resource| {
                let limit = effective_limit(&conductor_state, *resource);
                let holders: Vec<&str> = conductor_state
                    .locks
                    .iter()
                    .filter(|lock| {
                        lock.lock_holder_namespace_id != request.namespace_id
                            && lock.resources.contains(resource)
                    })
                    .map(|lock| lock.lock_holder_namespace_id.as_str())
                    .collect();
                if holders.len() as u32 >= limit {
                    holders.first().map(|holder| holder.to_string())
                } else {
                    None
                }
            });

            let response = match conflict {
                Some(holder) => protos::LockClusterResourcesResponse {
                    granted: false,
                    holder: Some(holder),
                },
                None => {
                    conductor_state.locks.retain(|lock| {
                        lock.lock_holder_namespace_id != request.namespace_id
                            || !resources_overlap(&lock.resources, &request.resources)
                    });
                    conductor_state.locks.push(protos::ClusterResourceLock {
                        lock_holder_namespace_id: request.namespace_id.clone(),
                        resources: request.resources.clone(),
                        acquired_at: Some(SystemTime::now().to_proto()),
                    });
                    protos::LockClusterResourcesResponse {
                        granted: true,
                        holder: None,
                    }
                }
            };

            if response.granted {
                resources.conductor_state = Some(conductor_state);
                update(scd::server_configurations.filter(scd::id.eq(config.id)))
                    .set(scd::cluster_resources.eq(serde_json::to_value(&resources).unwrap()))
                    .execute(conn)?;
            }

            Ok(response)
        },
    );

    match result {
        Ok(response) => Ok(response),
        Err(e) => {
            log::error!("LockClusterResources failed: {:?}", e);
            Err(Status::new(Code::Internal, "data_error"))
        }
    }
}

/// Whether any `ClusterResource` (as its raw `i32` enum value) appears in both lists -- used to
/// decide whether one `ClusterResourceLock` conflicts with a `Lock`/`FreeClusterResourcesRequest`.
pub(super) fn resources_overlap(a: &[i32], b: &[i32]) -> bool {
    a.iter().any(|resource| b.contains(resource))
}

/// The number of distinct namespaces that may concurrently hold `resource`'s lock -- see
/// `ClusterConductorState.limits`/`ClusterResourceLimit`'s own docs for the (parallel
/// `resource`/`limit` list) shape this reads. Any `ClusterResource` (`resource` here is the raw
/// `i32` enum value, same convention as `ClusterResourceLock.resources`) not present in `limits`
/// at all -- including every resource on a cluster that's never had `ConfigureServer` touch
/// `limits` -- defaults to `1`, matching `ClusterTab.elm`'s client-side default.
fn effective_limit(state: &protos::ClusterConductorState, resource: i32) -> u32 {
    state
        .limits
        .iter()
        .find_map(|entry| {
            entry
                .resource
                .iter()
                .position(|r| *r == resource)
                .and_then(|i| entry.limit.get(i).copied())
        })
        .unwrap_or(1)
}

/// Loads and validates `config.cluster_resources` for a `LockClusterResources`/
/// `FreeClusterResources` call: `shared_secret` must match this server's own stored
/// `cluster_shared_secret`. That's the *only* check -- knowing the secret is what makes a caller
/// entitled to treat this server as the conductor, regardless of what this server's own
/// `namespace_id`/`conductor_host` happen to say (e.g. a server that hasn't gotten around to
/// setting `namespace_id == conductor_host` on itself yet, or simply doesn't need to for whatever
/// it's being used for).
pub(super) fn validate_conductor(
    config: &models::ServerConfiguration,
    shared_secret: &str,
) -> Result<protos::ClusterResources, Status> {
    let cluster_resources: protos::ClusterResources = config
        .cluster_resources
        .clone()
        .and_then(|c| serde_json::from_value(c).ok())
        .ok_or(Status::new(Code::FailedPrecondition, "no_cluster_resources"))?;
    if shared_secret.is_empty() || shared_secret != cluster_resources.cluster_shared_secret {
        return Err(Status::new(Code::Unauthenticated, "invalid_shared_secret"));
    }
    Ok(cluster_resources)
}
