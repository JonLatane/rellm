//! Specs for `delete_media_sizes`: removes only the requested `sizes` (by `conversion`), deletes
//! their object storage objects, refreshes `media_storage_bytes_used`, and refuses to leave a `Media` item
//! with no sizes at all. Needs a real object storage connection -- see `factories::test_bucket`.

use diesel::prelude::*;
use tonic::Code;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models::MediaSize;
use crate::protos::MediaSize as ProtoMediaSize;
use crate::protos::*;
use crate::rpcs::delete_media_sizes;
use crate::schema::users;
use crate::tests::factories::*;

fn unique_path(name: &str) -> String {
    format!("test/delete_media_sizes_spec/{}-{}", name, uuid::Uuid::new_v4())
}

fn media_storage_bytes_used(conn: &mut PgPooledConnection, user_id: i64) -> i64 {
    users::table
        .select(users::media_storage_bytes_used)
        .filter(users::id.eq(user_id))
        .first(conn)
        .unwrap()
}

#[test]
fn deletes_only_the_requested_size_and_its_object_storage_object() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmst_self");
        let original_path = unique_path("original");
        let small_path = unique_path("small");
        for path in [&original_path, &small_path] {
            tb.block_on(tb.bucket.put_object(path, b"test-bytes"))
                .expect("failed to seed test object storage object");
        }
        let media = create_media_with_size(conn, Some(&user), &original_path, 100);
        let media = set_media_sizes(
            conn,
            &media,
            vec![
                MediaSize {
                    conversion: MediaConversion::Original as i32,
                    object_storage_path: original_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 100,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::Small as i32,
                    object_storage_path: small_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 20,
                    aspect_ratio: None,
                },
            ],
        );
        crate::logic::update_media_storage_used(user.id, conn).unwrap();
        assert_eq!(media_storage_bytes_used(conn, user.id), 120);

        let updated = tb
            .block_on(delete_media_sizes(
                Media {
                    id: media.id.to_proto_id(),
                    sizes: vec![ProtoMediaSize {
                        conversion: MediaConversion::Small as i32,
                        ..Default::default()
                    }],
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("delete_media_sizes should succeed");

        assert_eq!(updated.sizes.len(), 1);
        assert_eq!(updated.sizes[0].conversion, MediaConversion::Original as i32);
        assert!(!tb.object_exists(&small_path), "small object storage object should be deleted");
        assert!(tb.object_exists(&original_path), "original object storage object should survive");
        assert_eq!(
            media_storage_bytes_used(conn, user.id),
            100,
            "media_storage_bytes_used should drop by the deleted size's byte count"
        );

        Ok(())
    });
}

#[test]
fn deleting_a_size_reduces_server_media_usage_bytes_by_that_size_only() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmst_server_usage");
        let original_path = unique_path("server_usage_original");
        let small_path = unique_path("server_usage_small");
        for path in [&original_path, &small_path] {
            tb.block_on(tb.bucket.put_object(path, b"test-bytes"))
                .expect("failed to seed test object storage object");
        }
        let media = create_media_with_size(conn, Some(&user), &original_path, 100);
        let media = set_media_sizes(
            conn,
            &media,
            vec![
                MediaSize {
                    conversion: MediaConversion::Original as i32,
                    object_storage_path: original_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 100,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::Small as i32,
                    object_storage_path: small_path.clone(),
                    content_type: "image/png".to_string(),
                    size_bytes: 20,
                    aspect_ratio: None,
                },
            ],
        );
        // `server_media_usage_bytes` seeds the active `server_configurations` row first if this
        // test transaction doesn't already have one -- see its own doc.
        assert_eq!(server_media_usage_bytes(conn), 0);
        crate::logic::adjust_server_media_usage_bytes(conn, 120).unwrap();
        assert_eq!(server_media_usage_bytes(conn), 120);

        tb.block_on(delete_media_sizes(
            Media {
                id: media.id.to_proto_id(),
                sizes: vec![ProtoMediaSize {
                    conversion: MediaConversion::Small as i32,
                    ..Default::default()
                }],
                ..Default::default()
            },
            &user,
            conn,
            &tb.bucket,
        ))
        .expect("delete_media_sizes should succeed");

        assert_eq!(
            server_media_usage_bytes(conn),
            100,
            "server_media_usage_bytes should drop by only the deleted size's byte count"
        );

        Ok(())
    });
}

#[test]
fn errors_if_it_would_leave_media_with_no_sizes() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmst_last");
        let path = unique_path("only");
        let media = create_media(conn, Some(&user), &path);

        let err = tb
            .block_on(delete_media_sizes(
                Media {
                    id: media.id.to_proto_id(),
                    sizes: vec![ProtoMediaSize {
                        conversion: MediaConversion::Original as i32,
                        ..Default::default()
                    }],
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "would_leave_media_with_no_sizes");

        let remaining = media.sizes();
        assert_eq!(remaining.len(), 1, "no size should have actually been removed");

        Ok(())
    });
}

#[test]
fn rejects_non_owner_non_admin() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "dmst_owner");
        let other = create_user(conn, "dmst_other");
        let media = create_media(conn, Some(&owner), &unique_path("rejected"));

        let err = tb
            .block_on(delete_media_sizes(
                Media {
                    id: media.id.to_proto_id(),
                    sizes: vec![ProtoMediaSize {
                        conversion: MediaConversion::Original as i32,
                        ..Default::default()
                    }],
                    ..Default::default()
                },
                &other,
                conn,
                &tb.bucket,
            ))
            .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        Ok(())
    });
}

#[test]
fn admin_can_delete_sizes_of_another_users_media() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "dmst_admin_owner");
        let admin = create_user(conn, "dmst_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let original_path = unique_path("original");
        let small_path = unique_path("small");
        for path in [&original_path, &small_path] {
            tb.block_on(tb.bucket.put_object(path, b"test-bytes"))
                .expect("failed to seed test object storage object");
        }
        let media = create_media(conn, Some(&owner), &original_path);
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
                    size_bytes: 5,
                    aspect_ratio: None,
                },
            ],
        );

        let updated = tb
            .block_on(delete_media_sizes(
                Media {
                    id: media.id.to_proto_id(),
                    sizes: vec![ProtoMediaSize {
                        conversion: MediaConversion::Small as i32,
                        ..Default::default()
                    }],
                    ..Default::default()
                },
                &admin,
                conn,
                &tb.bucket,
            ))
            .expect("admin delete_media_sizes should succeed");
        assert_eq!(updated.sizes.len(), 1);
        assert!(!tb.object_exists(&small_path));

        Ok(())
    });
}

#[test]
fn delete_sizes_of_unknown_media_returns_not_found() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "dmst_missing");

        let err = tb
            .block_on(delete_media_sizes(
                Media {
                    id: 999_999_999i64.to_proto_id(),
                    sizes: vec![ProtoMediaSize {
                        conversion: MediaConversion::Original as i32,
                        ..Default::default()
                    }],
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
