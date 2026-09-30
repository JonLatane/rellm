use diesel::prelude::*;
use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};

// embed_migrations!("./migrations");
pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!();

use diesel::r2d2::{ConnectionManager, Pool, PooledConnection};
use dotenvy::dotenv;
use std::env;

use diesel::pg::PgConnection;
pub type PgPooledConnection = PooledConnection<ConnectionManager<PgConnection>>;
pub type PgPool = Pool<ConnectionManager<PgConnection>>;

pub type Backend = <PgConnection as Connection>::Backend;

/// Connections per server process. Deliberately small: every deploy (2 replicas per site) shares
/// one central Postgres with all the other sites, and r2d2's default of 10 eagerly-opened
/// connections per process would exhaust `max_connections` after a handful of sites. `min_idle(1)`
/// lets a quiet server shrink back to one connection (r2d2 reaps idle connections above it).
const SERVER_POOL_SIZE: u32 = 4;

pub fn establish_pool() -> PgPool {
    build_pool(SERVER_POOL_SIZE, 1)
}

/// For everything in `bin/` (background jobs, one-off tools): each takes one connection up front
/// and never asks for a second, so a pool of exactly 1 is all they need.
pub fn establish_job_pool() -> PgPool {
    build_pool(1, 1)
}

fn build_pool(max_size: u32, min_idle: u32) -> PgPool {
    dotenv().ok();

    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let manager = ConnectionManager::<PgConnection>::new(&database_url);
    Pool::builder()
        .max_size(max_size)
        .min_idle(Some(min_idle))
        .build(manager)
        .expect("Failed to create pool")
}

pub fn establish_connection() -> PgConnection {
    dotenv().ok();

    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    PgConnection::establish(&database_url).expect(&format!("Error connecting to {}", database_url))
}

/// Mirrors `establish_pool`, but points at `TEST_DATABASE_URL` (a separate database, e.g.
/// `rellm_test` alongside the `rellm_dev` pointed to by `DATABASE_URL`) so integration tests
/// never touch dev data. Used only by `crate::tests::factories::test_conn`.
pub fn establish_test_pool() -> PgPool {
    dotenv().ok();

    let database_url = env::var("TEST_DATABASE_URL").expect("TEST_DATABASE_URL must be set");
    let manager = ConnectionManager::<PgConnection>::new(&database_url);
    Pool::builder()
        .build(manager)
        .expect("Failed to create test pool")
}

pub fn migrate_database() {
    let mut connection = establish_connection();
    connection.run_pending_migrations(MIGRATIONS).unwrap();
    // embedded_migrations::run_with_output(&connection, &mut std::io::stdout())
    //     .expect("Error running migrations");
}
