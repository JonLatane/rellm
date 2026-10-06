extern crate diesel;
extern crate rellm;

use diesel::*;

use rellm::protos::ClusterResources;
use rellm::schema::server_configurations::dsl::*;
use rellm::{db_connection, init_bin_logging, init_crypto, models};

/// Admin escape hatch for a stuck `ClusterResourceLock` (see that message's own doc in
/// server_configuration.proto): if a `generate_link_preview_images` job dies after acquiring the
/// cluster's browser lock but before calling `FreeClusterResources` (a crash, an OOM-killed pod,
/// `kubectl delete` mid-run), the lock is never released on its own -- it's persisted on the
/// conductor's `server_configurations` row, not tied to that job's process lifetime. Run this
/// directly against the conductor's own database (e.g. exec'd via k9s into its pod, the same way
/// `set_permission` is) to unconditionally clear every held lock, regardless of holder or
/// resource, so the next `LockClusterResources` call succeeds immediately.
pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Connecting to DB...");
    let mut conn = db_connection::establish_connection();

    let config = server_configurations
        .filter(active.eq(true))
        .select(models::SERVER_CONFIGURATION_COLUMNS)
        .first::<models::ServerConfiguration>(&mut conn)
        .expect("Failed to load server configuration");

    let mut resources: ClusterResources = match config
        .cluster_resources
        .and_then(|c| serde_json::from_value(c).ok())
    {
        Some(resources) => resources,
        None => {
            log::info!("This server has no cluster_resources configured; nothing to free.");
            return;
        }
    };

    let held_locks = resources
        .conductor_state
        .as_ref()
        .map(|s| s.locks.len())
        .unwrap_or(0);
    if held_locks == 0 {
        log::info!("No cluster resource locks are currently held.");
        return;
    }

    log::info!(
        "Clearing {} held cluster resource lock(s): {:?}",
        held_locks,
        resources.conductor_state
    );
    resources.conductor_state = resources.conductor_state.map(|mut state| {
        state.locks.clear();
        state
    });

    update(server_configurations.filter(id.eq(config.id)))
        .set(cluster_resources.eq(serde_json::to_value(&resources).unwrap()))
        .execute(&mut conn)
        .expect("Failed to clear cluster resource locks");

    log::info!("Done. All cluster resource locks have been freed.");
}
