//! Specs for `update_media`: only `name`/`description` are ever written, and self-or-`ADMIN`
//! ownership rules match `delete_media`'s.

use diesel::prelude::*;
use tonic::Code;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::update_media;
use crate::tests::factories::*;

fn unique_path(name: &str) -> String {
    format!("test/update_media_spec/{}-{}", name, uuid::Uuid::new_v4())
}

#[test]
fn self_update_changes_name_and_description() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_self");
        let media = create_media(conn, Some(&user), &unique_path("self"));

        let updated = update_media(
            Media {
                id: media.id.to_proto_id(),
                name: Some("New Name".to_string()),
                description: Some("New description".to_string()),
                ..Default::default()
            },
            &user,
            conn,
        )
        .expect("self update should succeed");

        assert_eq!(updated.name, Some("New Name".to_string()));
        assert_eq!(updated.description, Some("New description".to_string()));

        Ok(())
    });
}

#[test]
fn update_ignores_fields_other_than_name_and_description() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_ignored");
        let media = create_media(conn, Some(&user), &unique_path("ignored"));
        let original_sizes = media.sizes();

        let updated = update_media(
            Media {
                id: media.id.to_proto_id(),
                name: Some("Renamed".to_string()),
                generated: true,
                visibility: Visibility::GlobalPublic as i32,
                ..Default::default()
            },
            &user,
            conn,
        )
        .expect("update should succeed");

        assert_eq!(updated.name, Some("Renamed".to_string()));
        assert!(!updated.generated, "generated should be untouched by update_media");
        assert_eq!(
            updated.visibility,
            Visibility::ServerPublic as i32,
            "visibility should be untouched by update_media"
        );
        assert_eq!(
            updated.sizes.len(),
            original_sizes.len(),
            "sizes should be untouched by update_media"
        );

        Ok(())
    });
}

#[test]
fn update_rejects_non_owner_non_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "umt_owner");
        let other = create_user(conn, "umt_other");
        let media = create_media(conn, Some(&owner), &unique_path("rejected"));

        let err = update_media(
            Media {
                id: media.id.to_proto_id(),
                name: Some("Hijacked".to_string()),
                ..Default::default()
            },
            &other,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        Ok(())
    });
}

#[test]
fn admin_can_update_another_users_media() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "umt_admin_owner");
        let admin = create_user(conn, "umt_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let media = create_media(conn, Some(&owner), &unique_path("admin"));

        let updated = update_media(
            Media {
                id: media.id.to_proto_id(),
                name: Some("Admin Renamed".to_string()),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("admin update should succeed");
        assert_eq!(updated.name, Some("Admin Renamed".to_string()));

        Ok(())
    });
}

#[test]
fn update_unknown_media_returns_not_found() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_missing");

        let err = update_media(
            Media {
                id: 999_999_999i64.to_proto_id(),
                name: Some("Ghost".to_string()),
                ..Default::default()
            },
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::NotFound);
        assert_eq!(err.message(), "media_not_found");

        Ok(())
    });
}
