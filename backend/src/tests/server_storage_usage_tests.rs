//! Specs for `logic::server_storage_usage`: `total_media_bytes`'s whole-table sum,
//! `recompute_server_media_usage_bytes`'s full recompute, and `adjust_server_media_usage_bytes`'s
//! cheap incremental delta (including its zero-floor clamp and no-op-on-zero-delta shortcut).
//! `recompute_server_object_storage_usage_bytes` itself needs a real object storage connection --
//! see `object_storage_usage_tests` below, which mirrors `delete_media_tests`' `test_bucket` use.

use diesel::prelude::*;

use crate::logic::{
    adjust_server_media_usage_bytes, recompute_server_media_usage_bytes,
    recompute_server_object_storage_usage_bytes, total_media_bytes,
};
use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use crate::tests::factories::*;

fn unique_path(name: &str) -> String {
    format!("test/server_storage_usage_spec/{}-{}", name, uuid::Uuid::new_v4())
}

fn media_settings(conn: &mut crate::db_connection::PgPooledConnection) -> MediaSettings {
    get_server_configuration_proto(conn)
        .expect("failed to fetch config")
        .media_settings
        .expect("media_settings should be set")
}

#[test]
fn total_media_bytes_sums_every_size_across_every_owner() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let alice = create_user(conn, "ssu_alice");
        let bob = create_user(conn, "ssu_bob");
        create_media_with_size(conn, Some(&alice), &unique_path("a1"), 100);
        create_media_with_size(conn, Some(&bob), &unique_path("b1"), 250);
        create_media_with_size(conn, None, &unique_path("unowned"), 10);

        assert_eq!(total_media_bytes(conn).unwrap(), 360);

        Ok(())
    });
}

#[test]
fn recompute_writes_total_and_calculated_at_in_place() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // Seed the active row (and pick up its own defaults) the same way `configure_market` does.
        get_server_configuration_proto(conn).expect("failed to seed base config");

        let user = create_user(conn, "ssu_recompute");
        create_media_with_size(conn, Some(&user), &unique_path("r1"), 400);

        recompute_server_media_usage_bytes(conn).expect("recompute should succeed");

        let settings = media_settings(conn);
        assert_eq!(settings.server_media_usage_bytes, 400);
        assert!(
            settings.server_media_usage_calculated_at.is_some(),
            "calculated_at should be stamped by a recompute"
        );

        Ok(())
    });
}

#[test]
fn adjust_moves_usage_by_delta_without_a_full_rescan() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        get_server_configuration_proto(conn).expect("failed to seed base config");

        adjust_server_media_usage_bytes(conn, 500).expect("positive adjust should succeed");
        assert_eq!(media_settings(conn).server_media_usage_bytes, 500);

        adjust_server_media_usage_bytes(conn, -200).expect("negative adjust should succeed");
        assert_eq!(media_settings(conn).server_media_usage_bytes, 300);

        Ok(())
    });
}

#[test]
fn adjust_clamps_at_zero_rather_than_underflowing() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        get_server_configuration_proto(conn).expect("failed to seed base config");

        adjust_server_media_usage_bytes(conn, 100).expect("positive adjust should succeed");
        adjust_server_media_usage_bytes(conn, -900).expect("over-large negative adjust should succeed");

        assert_eq!(
            media_settings(conn).server_media_usage_bytes,
            0,
            "usage should floor at 0 rather than underflow"
        );

        Ok(())
    });
}

#[test]
fn adjust_is_a_no_op_for_a_zero_delta() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        get_server_configuration_proto(conn).expect("failed to seed base config");
        adjust_server_media_usage_bytes(conn, 250).expect("seed adjust should succeed");
        let before = media_settings(conn);

        adjust_server_media_usage_bytes(conn, 0).expect("zero adjust should succeed");
        let after = media_settings(conn);

        assert_eq!(after.server_media_usage_bytes, before.server_media_usage_bytes);
        assert_eq!(
            after.server_media_usage_calculated_at, before.server_media_usage_calculated_at,
            "a zero delta should skip the row lock/write entirely, not just no-op the byte count"
        );

        Ok(())
    });
}

#[test]
fn recompute_self_heals_drift_a_prior_adjust_missed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        get_server_configuration_proto(conn).expect("failed to seed base config");

        // Simulates an incremental adjust that never happened (e.g. a cascading delete that
        // bypassed every call site) -- the DB's real total and the running counter disagree.
        adjust_server_media_usage_bytes(conn, 999).expect("seed adjust should succeed");
        let user = create_user(conn, "ssu_drift");
        create_media_with_size(conn, Some(&user), &unique_path("drift"), 42);

        recompute_server_media_usage_bytes(conn).expect("recompute should succeed");

        assert_eq!(
            media_settings(conn).server_media_usage_bytes,
            42,
            "a full recompute should replace the drifted running total with the real one"
        );

        Ok(())
    });
}

mod object_storage_usage_tests {
    use super::*;

    #[test]
    fn recompute_lists_and_sums_every_object_in_the_bucket() {
        let tb = test_bucket();
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            get_server_configuration_proto(conn).expect("failed to seed base config");

            let path = unique_path("object");
            tb.block_on(tb.bucket.put_object(&path, b"0123456789"))
                .expect("failed to seed test object storage object");

            tb.block_on(recompute_server_object_storage_usage_bytes(conn, &tb.bucket))
                .expect("recompute should succeed");

            let settings = media_settings(conn);
            assert!(
                settings.server_object_storage_usage_bytes >= 10,
                "should include at least the 10-byte object just seeded (bucket may hold other test objects too)"
            );
            assert!(
                settings.server_object_storage_usage_calculated_at.is_some(),
                "calculated_at should be stamped by a recompute"
            );

            Ok(())
        });
    }
}
