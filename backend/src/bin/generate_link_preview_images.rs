extern crate anyhow;
extern crate diesel;
extern crate rellm;

use rellm::logic::{
    generate_previews_for_post, link_preview_settings, posts_needing_previews,
    record_failed_attempt, BrowserUnavailable, LazyBrowser,
};
use rellm::protos::ClusterResources;
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

    let settings = link_preview_settings(&mut conn).expect("Failed to load server configuration");
    if !settings.generation_enabled {
        log::info!("Link preview image generation is disabled in MediaSettings, exiting.");
        return;
    }

    let posts_to_update = posts_needing_previews(100, &mut conn).unwrap();
    log::info!("Got {} posts to update.", posts_to_update.len());

    if posts_to_update.is_empty() {
        log::info!("No posts to update, exiting.");
        return;
    }

    log::info!("Connecting to object storage...");
    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");

    // Only posts that get past the no-browser metadata step start a browser (and, in a cluster,
    // take the conductor's browser lock) -- see `LazyBrowser`.
    let cluster_resources: Option<ClusterResources> = rpcs::get_server_configuration_model(&mut conn)
        .expect("Failed to load server configuration")
        .cluster_resources
        .and_then(|v| serde_json::from_value(v).ok());
    let mut browser = LazyBrowser::new(cluster_resources);

    for post in posts_to_update {
        if let Err(e) = generate_previews_for_post(&post, settings.prefer_metadata, &mut browser, &mut conn, &bucket).await {
            if e.downcast_ref::<BrowserUnavailable>().is_some() {
                // Not the post's fault, so don't count an attempt against it -- and the rest of
                // the batch would hit the same wall, so skip them (metadata-only posts get
                // another chance next run).
                log::warn!("{}; ending this run early.", e);
                break;
            }
            log::error!("Failed to generate previews for post {}: {}", post.id, e);
            record_failed_attempt(post.id, &mut conn);
        }
    }

    browser.release().await;

    log::info!("Done generating preview images.");
}
