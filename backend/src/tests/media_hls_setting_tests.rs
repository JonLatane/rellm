//! `MediaSettings.hls_streaming_enabled`: off by default (HLS costs more than the stored size
//! conversions -- see its doc in `server_configuration.proto`), and editable by a plain `ADMIN`
//! through `ConfigureServer` like the other media settings.

use diesel::*;

use crate::protos::*;
use crate::rpcs::{configure_server, get_server_configuration_proto};
use crate::tests::factories::*;

fn media_settings(conn: &mut crate::db_connection::PgPooledConnection) -> MediaSettings {
    get_server_configuration_proto(conn)
        .unwrap()
        .media_settings
        .unwrap_or_default()
}

#[test]
fn hls_streaming_is_off_by_default() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        assert!(!media_settings(conn).hls_streaming_enabled);
        Ok(())
    });
}

#[test]
fn a_plain_admin_can_turn_it_on_and_off() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "hls_setting_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        for enabled in [true, false] {
            let mut request = get_server_configuration_proto(conn).unwrap();
            request.media_settings = Some(MediaSettings {
                hls_streaming_enabled: enabled,
                ..media_settings(conn)
            });
            let updated = configure_server(request, &admin, conn).expect("configure should succeed");

            assert_eq!(updated.media_settings.unwrap().hls_streaming_enabled, enabled);
            assert_eq!(media_settings(conn).hls_streaming_enabled, enabled, "persisted, not just echoed");
        }
        Ok(())
    });
}

#[test]
fn saving_other_media_settings_doesnt_turn_it_on() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "hls_setting_other_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = get_server_configuration_proto(conn).unwrap();
        request.media_settings = Some(MediaSettings {
            block_cors_anonymous_media_access: true,
            ..media_settings(conn)
        });
        let updated = configure_server(request, &admin, conn).expect("configure should succeed");

        let updated = updated.media_settings.unwrap();
        assert!(updated.block_cors_anonymous_media_access);
        assert!(!updated.hls_streaming_enabled);
        Ok(())
    });
}
