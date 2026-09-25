//! Specs for `configure_server`'s handling of `MediaSettings.server_media_allocation_bytes`:
//! editing it requires `EDIT_SERVER_MEDIA_ALLOCATION` on top of plain `ADMIN` (mirrors
//! `configure_server_cluster_resources_tests`' coverage of `cluster_resources`/
//! `EDIT_CLUSTER_SETTINGS`), while `default_user_media_allocation_bytes` stays plain-`ADMIN`
//! editable as it always was, and the read-only usage/`calculated_at` fields are never settable via
//! `ConfigureServer` at all, regardless of permission.

use diesel::*;

use crate::protos::*;
use crate::rpcs::{configure_server, get_server_configuration_proto};
use crate::tests::factories::*;

fn media_settings_request(
    conn: &mut crate::db_connection::PgPooledConnection,
    media_settings: MediaSettings,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.media_settings = Some(media_settings);
    config
}

#[test]
fn plain_admin_cannot_raise_the_server_media_allocation() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csma_plain_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let existing = get_server_configuration_proto(conn)
            .unwrap()
            .media_settings
            .unwrap_or_default();
        let request = media_settings_request(
            conn,
            MediaSettings {
                server_media_allocation_bytes: existing.server_media_allocation_bytes + 1_000_000_000,
                ..existing.clone()
            },
        );

        let updated = configure_server(request, &admin, conn).expect("configure should succeed");

        assert_eq!(
            updated.media_settings.unwrap().server_media_allocation_bytes,
            existing.server_media_allocation_bytes,
            "a plain ADMIN's requested server_media_allocation_bytes must be ignored, carried forward unchanged"
        );

        Ok(())
    });
}

#[test]
fn admin_with_edit_server_media_allocation_can_raise_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csma_permitted_admin");
        let admin = grant_permissions(
            conn,
            &admin,
            vec![Permission::Admin, Permission::EditServerMediaAllocation],
        );

        let existing = get_server_configuration_proto(conn)
            .unwrap()
            .media_settings
            .unwrap_or_default();
        let request = media_settings_request(
            conn,
            MediaSettings {
                server_media_allocation_bytes: 10_000_000_000,
                ..existing
            },
        );

        let updated = configure_server(request, &admin, conn).expect("configure should succeed");

        assert_eq!(
            updated.media_settings.unwrap().server_media_allocation_bytes,
            10_000_000_000
        );

        Ok(())
    });
}

#[test]
fn plain_admin_can_still_edit_default_user_media_allocation() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csma_default_allocation");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let existing = get_server_configuration_proto(conn)
            .unwrap()
            .media_settings
            .unwrap_or_default();
        let request = media_settings_request(
            conn,
            MediaSettings {
                default_user_media_allocation_bytes: 31_457_280, // 30MB
                ..existing
            },
        );

        let updated = configure_server(request, &admin, conn).expect("configure should succeed");

        assert_eq!(
            updated.media_settings.unwrap().default_user_media_allocation_bytes,
            31_457_280,
            "default_user_media_allocation_bytes is unrelated to EDIT_SERVER_MEDIA_ALLOCATION and should stay plain-ADMIN editable"
        );

        Ok(())
    });
}

#[test]
fn usage_and_calculated_at_fields_are_never_settable_via_configure_server() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csma_readonly_fields");
        let admin = grant_permissions(
            conn,
            &admin,
            vec![Permission::Admin, Permission::EditServerMediaAllocation],
        );

        // Seeds the active `server_configurations` row first (see `adjust_server_media_usage_bytes`'s
        // own doc -- unlike `get_server_configuration_proto`, it assumes that row already exists),
        // then a real running total the way a Media mutation call site would, so there's a live
        // value that a malicious/stale `ConfigureServer` request could try to clobber.
        get_server_configuration_proto(conn).expect("failed to seed base config");
        crate::logic::adjust_server_media_usage_bytes(conn, 777).unwrap();
        let seeded = get_server_configuration_proto(conn).unwrap().media_settings.unwrap();
        assert_eq!(seeded.server_media_usage_bytes, 777);

        // Even a fully-permitted admin's request can't override these -- they're read-only,
        // populated only by the background jobs/incremental adjust call sites (see those fields'
        // own proto docs), never by ConfigureServer.
        let request = media_settings_request(
            conn,
            MediaSettings {
                server_media_usage_bytes: 0,
                server_media_usage_calculated_at: None,
                server_object_storage_usage_bytes: 123_456,
                server_object_storage_usage_calculated_at: None,
                ..seeded.clone()
            },
        );

        let updated = configure_server(request, &admin, conn).expect("configure should succeed");
        let updated_settings = updated.media_settings.unwrap();

        assert_eq!(
            updated_settings.server_media_usage_bytes, 777,
            "server_media_usage_bytes must be carried forward from the active row, not taken from the request"
        );
        assert_eq!(
            updated_settings.server_object_storage_usage_bytes,
            seeded.server_object_storage_usage_bytes,
            "server_object_storage_usage_bytes must likewise be carried forward, not taken from the request"
        );

        Ok(())
    });
}
