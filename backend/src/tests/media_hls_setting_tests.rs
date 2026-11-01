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

/// What a server that last saved its media settings before `hls_streaming_enabled` existed has stored: the
/// current settings' JSON with that key missing. It must still load as itself (with the new field off) --
/// failing to deserialize makes `normalized_media_settings` quietly replace the whole blob with defaults.
#[test]
fn media_settings_saved_before_the_field_existed_still_load() {
    let saved = MediaSettings {
        visible: false,
        default_moderation: Moderation::Pending as i32,
        default_visibility: Visibility::ServerPublic as i32,
        default_user_media_allocation_bytes: 123_456_789,
        server_media_allocation_bytes: 42_000_000_000,
        block_cors_anonymous_media_access: true,
        licensed_media_visible_globally: true,
        ..Default::default()
    };
    let mut legacy = serde_json::to_value(&saved).unwrap();
    assert!(legacy.as_object_mut().unwrap().remove("hls_streaming_enabled").is_some());

    let loaded = crate::marshaling::normalized_media_settings(Some(legacy));

    assert_eq!(loaded, saved);
    assert!(!loaded.hls_streaming_enabled);
}
