extern crate diesel;
extern crate rellm;

use diesel::*;

use rellm::schema::*;
use rellm::{db_connection, init_bin_logging, init_crypto};

pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Unlinking all preview images...");
    log::info!("Connecting to DB...");
    let mut conn = db_connection::establish_connection();

    // The delete_unowned_media job should take care of the old media.
    update(media::table)
        .filter(media::generated.eq(true))
        .set(media::user_id.eq(None::<i64>))
        .execute(&mut conn)
        .unwrap();
    update(posts::table)
        .set(posts::media_generated.eq(false))
        .execute(&mut conn)
        .unwrap();

    // Everything's eligible for regeneration again, including posts that had given up.
    delete(link_preview_attempts::table)
        .execute(&mut conn)
        .unwrap();

    log::info!("Done unlinking preview images.");
}
