//! Specs for `delete_media`: ownership/permission checks, and that both the `media` row and every
//! object storage object backing it (the original upload plus any small/medium/large converted copies) are
//! actually removed. Needs a real object storage connection -- see `factories::test_bucket`.

use diesel::prelude::*;
use tonic::Code;

use crate::marshaling::*;
use crate::models::MediaSize;
use crate::protos::*;
use crate::rpcs::delete_media;
use crate::schema::media;
use crate::tests::factories::*;

fn unique_path(name: &str) -> String {
    format!("test/delete_media_spec/{}-{}", name, uuid::Uuid::new_v4())
}

#[test]
fn self_delete_removes_row_and_object_storage_object() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmt_self");
        let path = unique_path("self");
        tb.block_on(tb.bucket.put_object(&path, b"test-bytes"))
            .expect("failed to seed test object storage object");
        let media = create_media(conn, Some(&user), &path);

        tb.block_on(delete_media(
            Media {
                id: media.id.to_proto_id(),
                ..Default::default()
            },
            &user,
            conn,
            &tb.bucket,
        ))
        .expect("self delete should succeed");

        let remaining: i64 = media::table
            .filter(media::id.eq(media.id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 0, "media row should be hard-deleted");
        assert!(
            !tb.object_exists(&path),
            "the original object storage object should be deleted"
        );

        Ok(())
    });
}

#[test]
fn delete_also_removes_converted_size_objects() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmt_converted");
        let original_path = unique_path("original");
        let small_path = unique_path("small");
        let medium_path = unique_path("medium");
        let large_path = unique_path("large");
        for path in [&original_path, &small_path, &medium_path, &large_path] {
            tb.block_on(tb.bucket.put_object(path, b"test-bytes"))
                .expect("failed to seed test object storage object");
        }

        let media = create_media(conn, Some(&user), &original_path);
        let media = set_media_sizes(
            conn,
            &media,
            vec![
                MediaSize {
                    conversion: MediaConversion::Original as i32,
                    object_storage_path: original_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 10,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::Small as i32,
                    object_storage_path: small_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 10,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::Medium as i32,
                    object_storage_path: medium_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 10,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::Large as i32,
                    object_storage_path: large_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 10,
                    aspect_ratio: None,
                },
            ],
        );

        tb.block_on(delete_media(
            Media {
                id: media.id.to_proto_id(),
                ..Default::default()
            },
            &user,
            conn,
            &tb.bucket,
        ))
        .expect("delete should succeed");

        for path in [&original_path, &small_path, &medium_path, &large_path] {
            assert!(
                !tb.object_exists(path),
                "Object storage object {} should be deleted",
                path
            );
        }

        Ok(())
    });
}

#[test]
fn delete_rejects_non_owner_non_admin() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "dmt_owner");
        let other = create_user(conn, "dmt_other");
        let media = create_media(conn, Some(&owner), &unique_path("rejected"));

        let err = tb
            .block_on(delete_media(
                Media {
                    id: media.id.to_proto_id(),
                    ..Default::default()
                },
                &other,
                conn,
                &tb.bucket,
            ))
            .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        let remaining: i64 = media::table
            .filter(media::id.eq(media.id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 1, "media should survive a rejected delete");

        Ok(())
    });
}

#[test]
fn admin_can_delete_another_users_media() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "dmt_admin_owner");
        let admin = create_user(conn, "dmt_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let path = unique_path("admin");
        tb.block_on(tb.bucket.put_object(&path, b"test-bytes"))
            .expect("failed to seed test object storage object");
        let media = create_media(conn, Some(&owner), &path);

        tb.block_on(delete_media(
            Media {
                id: media.id.to_proto_id(),
                ..Default::default()
            },
            &admin,
            conn,
            &tb.bucket,
        ))
        .expect("admin delete should succeed");

        let remaining: i64 = media::table
            .filter(media::id.eq(media.id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 0);
        assert!(!tb.object_exists(&path));

        Ok(())
    });
}

#[test]
fn delete_unknown_media_returns_not_found() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmt_missing");

        let err = tb
            .block_on(delete_media(
                Media {
                    id: 999_999_999i64.to_proto_id(),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .unwrap_err();
        assert_eq!(err.code(), Code::NotFound);
        assert_eq!(err.message(), "media_not_found");

        Ok(())
    });
}
