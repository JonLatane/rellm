extern crate anyhow;
extern crate diesel;
extern crate rellm;

use std::sync::Arc;

use diesel::*;

use rellm::logic::{generate_previews_for_post, start_browser};
use rellm::marshaling::*;
use rellm::models::{Post, POST_COLUMNS};
use rellm::schema::posts;
use rellm::{db_connection, init_bin_logging, init_crypto, object_storage_connection};

/// Generates preview images (main image + page screenshot) for one post's link and adds them to the
/// post, even if it already has generated previews. Requires a Chrome/Brave install (see
/// `logic::media::link_preview_generation::find_browser_executable`), so it's only shipped in the
/// preview_generator image.
///
/// Usage: regenerate_link_preview_images_for_post <post id>
/// where the ID is either the integer DB ID (all digits) or the proto/string (base58) ID.
#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    let arg = std::env::args()
        .nth(1)
        .expect("Usage: regenerate_link_preview_images_for_post <post id (integer or proto ID)>");
    let post_id: i64 = match arg.parse::<i64>() {
        Ok(id) => id,
        Err(_) => arg.to_string().to_db_id().expect("Invalid Proto ID Format"),
    };

    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");
    let post = posts::table
        .filter(posts::id.eq(post_id))
        .select(POST_COLUMNS)
        .first::<Post>(&mut conn)
        .expect("Post not found");
    if post.link.is_none() {
        panic!("Post {} has no link.", post_id);
    }

    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");
    let browser = Arc::new(start_browser().expect("Failed to start browser"));

    generate_previews_for_post(&post, &browser, &mut conn, &bucket)
        .await
        .expect("Failed to generate previews");
    log::info!("Done: added generated previews to post {}.", post_id.to_proto_id());
}
