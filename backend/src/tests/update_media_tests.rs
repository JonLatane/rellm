//! Specs for `update_media`: `name`/`description`/`metadata.video_preview_time_ms` are the only
//! fields ever written, self-or-`ADMIN` ownership rules match `delete_media`'s, and a changed
//! `video_preview_time_ms` on a video invalidates any existing `VIDEO_PREVIEW_THUMBNAIL_*` sizes.

use diesel::prelude::*;
use tonic::Code;

use crate::marshaling::*;
use crate::models;
use crate::models::MediaSize;
use crate::protos::MediaMetadata as ProtoMediaMetadata;
use crate::protos::*;
use crate::rpcs::update_media;
use crate::schema::users;
use crate::tests::factories::*;

fn unique_path(name: &str) -> String {
    format!("test/update_media_spec/{}-{}", name, uuid::Uuid::new_v4())
}

fn media_storage_bytes_used(conn: &mut crate::db_connection::PgPooledConnection, user_id: i64) -> i64 {
    users::table
        .select(users::media_storage_bytes_used)
        .filter(users::id.eq(user_id))
        .first(conn)
        .unwrap()
}

#[test]
fn self_update_changes_name_and_description() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_self");
        let media = create_media(conn, Some(&user), &unique_path("self"));

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    name: Some("New Name".to_string()),
                    description: Some("New description".to_string()),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("self update should succeed");

        assert_eq!(updated.name, Some("New Name".to_string()));
        assert_eq!(updated.description, Some("New description".to_string()));

        Ok(())
    });
}

#[test]
fn update_ignores_fields_other_than_name_description_and_metadata() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_ignored");
        let media = create_media(conn, Some(&user), &unique_path("ignored"));
        let original_sizes = media.sizes();

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    name: Some("Renamed".to_string()),
                    generated: true,
                    visibility: Visibility::GlobalPublic as i32,
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
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
fn unset_metadata_leaves_video_preview_time_ms_untouched() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_meta_untouched");
        let media = create_media(conn, Some(&user), &unique_path("meta_untouched"));
        diesel::update(crate::schema::media::table.find(media.id))
            .set(crate::schema::media::metadata.eq(serde_json::to_value(models::MediaMetadata {
                video_preview_time_ms: Some(2500),
            })
            .unwrap()))
            .execute(conn)
            .unwrap();

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    name: Some("Untouched Metadata".to_string()),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("update should succeed");

        assert_eq!(
            updated.metadata.and_then(|m| m.video_preview_time_ms),
            Some(2500),
            "video_preview_time_ms should be untouched when request.metadata is unset"
        );

        Ok(())
    });
}

#[test]
fn changing_video_preview_time_invalidates_thumbnails_on_video_media() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_video_invalidate");
        let original_path = unique_path("original");
        let thumb_small_path = unique_path("thumb_small");
        for path in [&original_path, &thumb_small_path] {
            tb.block_on(tb.bucket.put_object(path, b"test-bytes"))
                .expect("failed to seed test MinIO object");
        }
        let media = create_media(conn, Some(&user), &original_path);
        let media = set_media_sizes(
            conn,
            &media,
            vec![
                MediaSize {
                    conversion: MediaConversion::Original as i32,
                    minio_path: original_path.clone(),
                    content_type: "video/mp4".to_string(),
                    size_bytes: 1000,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::VideoPreviewThumbnailSmall as i32,
                    minio_path: thumb_small_path.clone(),
                    content_type: "image/jpeg".to_string(),
                    size_bytes: 50,
                    aspect_ratio: None,
                },
            ],
        );
        diesel::update(crate::schema::media::table.find(media.id))
            .set(crate::schema::media::processed.eq(true))
            .execute(conn)
            .unwrap();
        crate::logic::update_media_storage_used(user.id, conn).unwrap();
        assert_eq!(media_storage_bytes_used(conn, user.id), 1050);

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    metadata: Some(ProtoMediaMetadata {
                        video_preview_time_ms: Some(3000),
                    }),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("update should succeed");

        assert_eq!(
            updated.metadata.and_then(|m| m.video_preview_time_ms),
            Some(3000)
        );
        assert_eq!(updated.sizes.len(), 1, "the stale preview thumbnail should be removed");
        assert_eq!(updated.sizes[0].conversion, MediaConversion::Original as i32);
        assert!(
            !tb.object_exists(&thumb_small_path),
            "the stale preview thumbnail's MinIO object should be deleted"
        );
        assert!(!updated.processed, "media should be marked unprocessed so the thumbnail regenerates");
        assert_eq!(
            media_storage_bytes_used(conn, user.id),
            1000,
            "media_storage_bytes_used should drop by the deleted thumbnail's byte count"
        );

        Ok(())
    });
}

#[test]
fn changing_video_preview_time_to_same_value_does_not_invalidate() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_video_same");
        let original_path = unique_path("original");
        let thumb_small_path = unique_path("thumb_small");
        for path in [&original_path, &thumb_small_path] {
            tb.block_on(tb.bucket.put_object(path, b"test-bytes"))
                .expect("failed to seed test MinIO object");
        }
        let media = create_media(conn, Some(&user), &original_path);
        diesel::update(crate::schema::media::table.find(media.id))
            .set(crate::schema::media::metadata.eq(serde_json::to_value(models::MediaMetadata {
                video_preview_time_ms: Some(1000),
            })
            .unwrap()))
            .execute(conn)
            .unwrap();
        let media = set_media_sizes(
            conn,
            &media,
            vec![
                MediaSize {
                    conversion: MediaConversion::Original as i32,
                    minio_path: original_path.clone(),
                    content_type: "video/mp4".to_string(),
                    size_bytes: 1000,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::VideoPreviewThumbnailSmall as i32,
                    minio_path: thumb_small_path.clone(),
                    content_type: "image/jpeg".to_string(),
                    size_bytes: 50,
                    aspect_ratio: None,
                },
            ],
        );
        diesel::update(crate::schema::media::table.find(media.id))
            .set(crate::schema::media::processed.eq(true))
            .execute(conn)
            .unwrap();

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    metadata: Some(ProtoMediaMetadata {
                        video_preview_time_ms: Some(1000),
                    }),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("update should succeed");

        assert_eq!(updated.sizes.len(), 2, "sizes should be untouched when the value doesn't change");
        assert!(updated.processed, "media should stay processed when nothing was invalidated");
        assert!(tb.object_exists(&thumb_small_path));

        Ok(())
    });
}

#[test]
fn changing_video_preview_time_on_non_video_media_does_not_invalidate_sizes() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_image_preview_time");
        let media = create_media(conn, Some(&user), &unique_path("image"));
        diesel::update(crate::schema::media::table.find(media.id))
            .set(crate::schema::media::processed.eq(true))
            .execute(conn)
            .unwrap();

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    metadata: Some(ProtoMediaMetadata {
                        video_preview_time_ms: Some(3000),
                    }),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("update should succeed");

        assert_eq!(updated.sizes.len(), 1, "an image's sizes should be untouched");
        assert!(updated.processed, "an image should stay processed");
        assert_eq!(
            updated.metadata.and_then(|m| m.video_preview_time_ms),
            Some(3000),
            "video_preview_time_ms should still be saved on non-video media"
        );

        Ok(())
    });
}

#[test]
fn update_rejects_non_owner_non_admin() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "umt_owner");
        let other = create_user(conn, "umt_other");
        let media = create_media(conn, Some(&owner), &unique_path("rejected"));

        let err = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    name: Some("Hijacked".to_string()),
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
fn admin_can_update_another_users_media() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "umt_admin_owner");
        let admin = create_user(conn, "umt_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let media = create_media(conn, Some(&owner), &unique_path("admin"));

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    name: Some("Admin Renamed".to_string()),
                    ..Default::default()
                },
                &admin,
                conn,
                &tb.bucket,
            ))
            .expect("admin update should succeed");
        assert_eq!(updated.name, Some("Admin Renamed".to_string()));

        Ok(())
    });
}

#[test]
fn update_unknown_media_returns_not_found() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_missing");

        let err = tb
            .block_on(update_media(
                Media {
                    id: 999_999_999i64.to_proto_id(),
                    name: Some("Ghost".to_string()),
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
