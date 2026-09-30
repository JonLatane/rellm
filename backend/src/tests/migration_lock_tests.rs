//! Regression test for the first-boot race: many replicas of a brand-new deployment migrate the same
//! empty database at once. Uses a scratch database on the same server as `TEST_DATABASE_URL`.

use crate::db_connection::run_migrations_exclusively;
use diesel::prelude::*;
use diesel::sql_query;
use std::sync::{Arc, Barrier};
use std::thread;

const SCRATCH_DB: &str = "rellm_migration_lock_test";

#[test]
fn concurrent_migrations_of_an_empty_database_all_succeed() {
    dotenvy::dotenv().ok();
    let test_url = std::env::var("TEST_DATABASE_URL").expect("TEST_DATABASE_URL must be set");
    let (server_url, _) = test_url.rsplit_once('/').expect("TEST_DATABASE_URL has no database name");
    let mut admin = PgConnection::establish(&format!("{server_url}/postgres")).expect("connect to postgres db");
    sql_query(format!("DROP DATABASE IF EXISTS {SCRATCH_DB} WITH (FORCE)")).execute(&mut admin).unwrap();
    sql_query(format!("CREATE DATABASE {SCRATCH_DB}")).execute(&mut admin).unwrap();

    let scratch_url = format!("{server_url}/{SCRATCH_DB}");
    let replicas = 8;
    let barrier = Arc::new(Barrier::new(replicas));
    let handles: Vec<_> = (0..replicas)
        .map(|_| {
            let (url, barrier) = (scratch_url.clone(), Arc::clone(&barrier));
            thread::spawn(move || {
                let mut connection = PgConnection::establish(&url).expect("connect to scratch db");
                barrier.wait();
                run_migrations_exclusively(&mut connection);
            })
        })
        .collect();
    let failures = handles.into_iter().map(|h| h.join()).filter(Result::is_err).count();

    sql_query(format!("DROP DATABASE IF EXISTS {SCRATCH_DB} WITH (FORCE)")).execute(&mut admin).ok();
    assert_eq!(failures, 0, "{failures} of {replicas} concurrent migrators failed");
}
