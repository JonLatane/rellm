extern crate diesel;
extern crate rellm;
use diesel::*;
use rellm::logic::update_all_counts;
use rellm::schema::users;
use rellm::{db_connection, init_bin_logging, init_crypto};

pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Updating User counts...");
    log::info!("Connecting to DB...");
    let pool = db_connection::establish_job_pool();
    let mut conn = pool.get().expect("Failed to get DB connection");

    let user_ids = users::table
        .select(users::id)
        .load::<i64>(&mut conn)
        .expect("Failed to load User ids");
    log::info!("{} User(s) to update.", user_ids.len());

    for user_id in user_ids {
        match update_all_counts(user_id, &mut conn) {
            Ok(()) => log::info!("Updated counts for User {}.", user_id),
            Err(e) => log::error!(
                "Failed to update counts for User {}: {:?}. Proceeding through remaining Users.",
                user_id,
                e
            ),
        }
    }
    log::info!("Done Updating User counts.");
}
