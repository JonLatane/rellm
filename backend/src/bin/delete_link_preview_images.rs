extern crate diesel;
extern crate rellm;

use rellm::logic::delete_link_preview_images;
use rellm::{db_connection, init_bin_logging, init_crypto};

pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Unlinking all preview images...");
    log::info!("Connecting to DB...");
    let mut conn = db_connection::establish_connection();

    // The delete_unowned_media job should take care of the old media.
    delete_link_preview_images(&mut conn).expect("Failed to unlink preview images");

    log::info!("Done unlinking preview images.");
}
