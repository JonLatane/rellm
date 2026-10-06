use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::protos::Permission;
use crate::rpcs::server_configuration::lock_cluster_resources::{resources_overlap, validate_conductor};
use crate::rpcs::validations::validate_exact_permission;
use crate::schema::server_configurations::dsl as scd;
use crate::{models, protos};

/// Releases `request.resources` previously locked by `request.namespace_id` via
/// `LockClusterResources`. A no-op for any resource `request.namespace_id` doesn't currently
/// hold -- see `FreeClusterResourcesRequest`'s own doc in server_configuration.proto. Same
/// in-place (not versioned) update as `lock_cluster_resources`, but -- unlike `Lock` -- this
/// accepts *either* auth style (an "auth-optional" RPC in the usual sense, just with two possible
/// auth mechanisms instead of one-or-none): an authenticated caller holding
/// `EDIT_CLUSTER_SETTINGS` can free any lock directly from the admin UI (see `ClusterTab.elm`),
/// falling back to the cluster-internal `cluster-shared-secret` check when no user is
/// authenticated -- see `authorize` below.
pub fn free_cluster_resources(
    request: protos::FreeClusterResourcesRequest,
    user: &Option<&models::User>,
    shared_secret: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    log::info!("FreeClusterResources called: {:?}", request);

    let config = scd::server_configurations
        .filter(scd::active.eq(true))
        .select(models::SERVER_CONFIGURATION_COLUMNS)
        .first::<models::ServerConfiguration>(conn)
        .map_err(|_| Status::new(Code::Internal, "data_error"))?;
    authorize(&config, user, shared_secret)?;

    let result = conn.transaction::<(), diesel::result::Error, _>(|conn| {
        let config = scd::server_configurations
            .filter(scd::active.eq(true))
            .select(models::SERVER_CONFIGURATION_COLUMNS)
            .for_update()
            .first::<models::ServerConfiguration>(conn)?;
        let mut resources: protos::ClusterResources =
            serde_json::from_value(config.cluster_resources.clone().unwrap_or_default())
                .unwrap_or_default();
        let mut conductor_state = resources.conductor_state.clone().unwrap_or_default();

        let held_by_caller = conductor_state.locks.iter().any(|lock| {
            lock.lock_holder_namespace_id == request.namespace_id
                && resources_overlap(&lock.resources, &request.resources)
        });
        if held_by_caller {
            conductor_state.locks.retain(|lock| {
                lock.lock_holder_namespace_id != request.namespace_id
                    || !resources_overlap(&lock.resources, &request.resources)
            });
            resources.conductor_state = Some(conductor_state);
            update(scd::server_configurations.filter(scd::id.eq(config.id)))
                .set(scd::cluster_resources.eq(serde_json::to_value(&resources).unwrap()))
                .execute(conn)?;
        }

        Ok(())
    });

    match result {
        Ok(()) => Ok(()),
        Err(e) => {
            log::error!("FreeClusterResources failed: {:?}", e);
            Err(Status::new(Code::Internal, "data_error"))
        }
    }
}

/// `FreeClusterResources`'s own auth check, distinct from `LockClusterResources`'s
/// secret-only `validate_conductor`: an authenticated user needs `EDIT_CLUSTER_SETTINGS` (the
/// same permission `ConfigureServer` requires to edit `cluster_resources` at all -- see that
/// permission's own doc) and nothing else -- no shared secret involved, since this is the normal
/// per-user auth system, not the cluster-internal one. Uses `validate_exact_permission`, not
/// `validate_permission` -- `EDIT_CLUSTER_SETTINGS` is deliberately admin-insufficient, so a plain
/// `ADMIN` without it must still be rejected here. With no authenticated user at all, falls back
/// to `validate_conductor`'s shared-secret check, same as `LockClusterResources`.
fn authorize(
    config: &models::ServerConfiguration,
    user: &Option<&models::User>,
    shared_secret: &str,
) -> Result<protos::ClusterResources, Status> {
    match user {
        Some(_) => {
            validate_exact_permission(user, Permission::EditClusterSettings)?;
            config
                .cluster_resources
                .clone()
                .and_then(|c| serde_json::from_value(c).ok())
                .ok_or(Status::new(Code::FailedPrecondition, "no_cluster"))
        }
        None => validate_conductor(config, shared_secret),
    }
}
