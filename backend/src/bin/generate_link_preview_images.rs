extern crate anyhow;
extern crate diesel;
extern crate rellm;

use std::sync::Arc;

use diesel::*;

use rellm::logic::{
    acquire_cluster_lock, generate_previews_for_post, release_cluster_lock, start_browser,
};
use rellm::models::{Post, POST_COLUMNS};
use rellm::protos::{ClusterResource, ClusterResources};
use rellm::schema::posts;
use rellm::init_crypto;
use rellm::{db_connection, init_bin_logging, object_storage_connection, rpcs};

#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Generating preview images...");
    log::info!("Connecting to DB...");
    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");

    let posts_to_update = posts::table
        .filter(posts::link.is_not_null())
        .filter(posts::media_generated.eq(false))
        .select(POST_COLUMNS)
        .limit(100)
        .load::<Post>(&mut conn)
        .unwrap();
    log::info!("Got {} posts to update.", posts_to_update.len());

    if posts_to_update.is_empty() {
        log::info!("No posts to update, exiting.");
        return;
    }

    log::info!("Connecting to object storage...");
    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");

    // If this server is part of a cluster (see `ClusterResources`'s own doc in
    // server_configuration.proto), only one instance may have a browser open at a time --
    // acquire that lock from the conductor before launching Chrome/Brave below. Servers not
    // configured with `cluster_resources` skip this entirely (single-instance mode, unchanged
    // from before this existed).
    let cluster_resources: Option<ClusterResources> = rpcs::get_server_configuration_model(&mut conn)
        .expect("Failed to load server configuration")
        .cluster_resources
        .and_then(|v| serde_json::from_value(v).ok());

    if let Some(resources) = &cluster_resources {
        log::info!("Cluster resources configured; acquiring browser lock from conductor...");
        if !acquire_cluster_lock(resources, &[ClusterResource::Browser]).await {
            log::warn!("Could not acquire cluster browser lock in time; skipping this run.");
            return;
        }
    }

    log::info!("Starting browser...");
    let browser = Arc::new(start_browser().expect("Failed to start browser"));

    for post in posts_to_update {
        if let Err(e) = generate_previews_for_post(&post, &browser, &mut conn, &bucket).await {
            log::error!("Failed to generate previews for post {}: {}", post.id, e);
        }
    }

    if let Some(resources) = &cluster_resources {
        release_cluster_lock(resources, &[ClusterResource::Browser]).await;
    }

    log::info!("Done generating preview images.");
}
