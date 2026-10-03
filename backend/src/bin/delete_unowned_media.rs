extern crate diesel;
extern crate rellm;

use rellm::logic::delete_unowned_media;
use rellm::{db_connection, init_bin_logging, init_crypto, object_storage_connection};

#[tokio::main]
async fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Deleting Unowned Media...");
    log::info!("Connecting to DB and object storage...");
    let mut conn = db_connection::establish_connection();
    let bucket = object_storage_connection::get_and_test_bucket()
        .await
        .expect("Failed to connect to object storage");

    delete_unowned_media(&mut conn, &bucket)
        .await
        .expect("Failed to delete unowned media");
    log::info!("Done Deleting Unowned Media.");
}
