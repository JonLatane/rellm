extern crate diesel;
extern crate rellm;
use diesel::*;
use rellm::schema::pending_contact_verifications::dsl as pending_contact_verifications;
use rellm::schema::user_access_tokens::dsl as user_access_tokens;
use rellm::schema::user_refresh_tokens::dsl as user_refresh_tokens;
use rellm::{db_connection, init_bin_logging, init_crypto};

pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Cleaning Expired Tokens...");
    log::info!("Connecting to DB...");
    let mut conn = db_connection::establish_connection();
    log::info!("Deleting Expired Access Tokens...");
    delete(
        user_access_tokens::user_access_tokens
            .filter(user_access_tokens::expires_at.lt(diesel::dsl::now)),
    )
    .execute(&mut conn)
    .unwrap_or(0);
    log::info!("Deleting Expired Refresh Tokens...");
    delete(
        user_refresh_tokens::user_refresh_tokens
            .filter(user_refresh_tokens::expires_at.lt(diesel::dsl::now)),
    )
    .execute(&mut conn)
    .unwrap_or(0);
    log::info!("Deleting Expired Pending Contact Verifications...");
    // Codes expire after `CODE_TTL`; anything sent longer ago than that is dead weight (and no
    // longer counts toward CreateAccount's hourly send cap either way).
    delete(
        pending_contact_verifications::pending_contact_verifications.filter(
            pending_contact_verifications::sent_at
                .lt(std::time::SystemTime::now() - rellm::logic::CODE_TTL),
        ),
    )
    .execute(&mut conn)
    .unwrap_or(0);
    log::info!("Done Cleaning Expired Tokens.");
}
