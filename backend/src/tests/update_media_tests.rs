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
fn update_ignores_fields_other_than_name_description_visibility_and_metadata() {
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
            "visibility should be untouched by update_media when the request leaves it unknown"
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
                ..Default::default()
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
                    content_type: "video/mp4".to_string(),
                    size_bytes: 1000,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::VideoPreviewThumbnailSmall as i32,
                    object_storage_path: thumb_small_path.clone(),
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
        // `server_media_usage_bytes` seeds the active `server_configurations` row first if this
        // test transaction doesn't already have one -- see its own doc.
        assert_eq!(server_media_usage_bytes(conn), 0);
        crate::logic::adjust_server_media_usage_bytes(conn, 1050).unwrap();
        assert_eq!(server_media_usage_bytes(conn), 1050);

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    metadata: Some(ProtoMediaMetadata {
                        video_preview_time_ms: Some(3000),
                        ..Default::default()
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
            "the stale preview thumbnail's object storage object should be deleted"
        );
        assert!(!updated.processed, "media should be marked unprocessed so the thumbnail regenerates");
        assert_eq!(
            media_storage_bytes_used(conn, user.id),
            1000,
            "media_storage_bytes_used should drop by the deleted thumbnail's byte count"
        );
        assert_eq!(
            server_media_usage_bytes(conn),
            1000,
            "server_media_usage_bytes should drop by the deleted thumbnail's byte count too"
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
                .expect("failed to seed test object storage object");
        }
        let media = create_media(conn, Some(&user), &original_path);
        diesel::update(crate::schema::media::table.find(media.id))
            .set(crate::schema::media::metadata.eq(serde_json::to_value(models::MediaMetadata {
                video_preview_time_ms: Some(1000),
                ..Default::default()
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
                    object_storage_path: original_path.clone(),
                    content_type: "video/mp4".to_string(),
                    size_bytes: 1000,
                    aspect_ratio: None,
                },
                MediaSize {
                    conversion: MediaConversion::VideoPreviewThumbnailSmall as i32,
                    object_storage_path: thumb_small_path.clone(),
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
                        ..Default::default()
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
                        ..Default::default()
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

#[test]
fn visibility_can_be_changed_to_licensed_but_not_direct() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_visibility");
        let media = create_media(conn, Some(&user), &unique_path("visibility"));

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    visibility: Visibility::Licensed as i32,
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .expect("LICENSED should be accepted");
        assert_eq!(updated.visibility, Visibility::Licensed as i32);

        let rejected = tb.block_on(update_media(
            Media {
                id: media.id.to_proto_id(),
                visibility: Visibility::Direct as i32,
                ..Default::default()
            },
            &user,
            conn,
            &tb.bucket,
        ));
        assert_eq!(rejected.unwrap_err().code(), tonic::Code::InvalidArgument);
        Ok(())
    });
}

#[test]
fn credits_are_saved_and_blank_credits_are_cleared_to_null() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_credits");
        let media = create_media(conn, Some(&user), &unique_path("credits"));

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    metadata: Some(ProtoMediaMetadata {
                        artist: Some("  Miles Davis ".to_string()),
                        album: Some("Kind of Blue".to_string()),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .unwrap();
        let metadata = updated.metadata.unwrap();
        assert_eq!(metadata.artist, Some("Miles Davis".to_string()));
        assert_eq!(metadata.album, Some("Kind of Blue".to_string()));

        let updated = tb
            .block_on(update_media(
                Media {
                    id: media.id.to_proto_id(),
                    metadata: Some(ProtoMediaMetadata {
                        artist: Some("Miles Davis".to_string()),
                        album: Some("   ".to_string()),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                &user,
                conn,
                &tb.bucket,
            ))
            .unwrap();
        assert_eq!(updated.metadata.as_ref().unwrap().album, None, "blank saves as null");
        Ok(())
    });
}

#[test]
fn unlicensed_preview_bounds_are_rejected_on_non_audio_video_media() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_preview_image");
        let media = create_media(conn, Some(&user), &unique_path("preview-image")); // image/png

        let result = tb.block_on(update_media(
            Media {
                id: media.id.to_proto_id(),
                metadata: Some(ProtoMediaMetadata {
                    unlicensed_preview_start_ms: Some(1000),
                    ..Default::default()
                }),
                ..Default::default()
            },
            &user,
            conn,
            &tb.bucket,
        ));
        assert_eq!(result.unwrap_err().code(), tonic::Code::InvalidArgument);
        Ok(())
    });
}

#[test]
fn musical_key_validation_accepts_documented_forms_only() {
    use crate::models::is_valid_musical_key;
    for key in ["C#m", "DbM", "Db", "F", "Am", "B♭-", "F♯m", "E♭️M", "C＃", "D﹟m", "B", "Bb"] {
        assert!(is_valid_musical_key(key), "{key} should be valid");
    }
    for key in ["", "H", "am", "db", "C##", "Cbb", "C♮", "A𝄪", "G𝄫m", "Dbb", "F♯♯", "Cmm", "C minor", " C", "C ", "Cx", "H#", "#C", "m", "C#M7"] {
        assert!(!is_valid_musical_key(key), "{key:?} should be invalid");
    }
}

#[test]
fn bpms_and_keys_are_saved_trimmed_and_blank_key_clears() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_bpm_key");
        let media = create_media(conn, Some(&user), &unique_path("bpm-key"));
        let update = |conn: &mut _, metadata: ProtoMediaMetadata| {
            tb.block_on(update_media(
                Media { id: media.id.to_proto_id(), metadata: Some(metadata), ..Default::default() },
                &user,
                conn,
                &tb.bucket,
            ))
        };

        let saved = update(
            conn,
            ProtoMediaMetadata {
                start_bpm: Some(127.5),
                end_bpm: Some(130.0),
                min_bpm: Some(120.0),
                max_bpm: Some(130.0),
                start_key: Some(" F♯m ".to_string()),
                end_key: Some("Ab".to_string()),
                ..Default::default()
            },
        )
        .unwrap();
        let metadata = saved.metadata.unwrap();
        assert_eq!((metadata.start_bpm, metadata.end_bpm), (Some(127.5), Some(130.0)));
        assert_eq!((metadata.min_bpm, metadata.max_bpm), (Some(120.0), Some(130.0)));
        assert_eq!(metadata.start_key.as_deref(), Some("F♯m"));
        assert_eq!(metadata.end_key.as_deref(), Some("Ab"));

        let cleared = update(
            conn,
            ProtoMediaMetadata { start_key: Some("  ".to_string()), end_key: Some("Ab".to_string()), ..Default::default() },
        )
        .unwrap();
        let metadata = cleared.metadata.unwrap();
        assert_eq!((metadata.start_bpm, metadata.end_bpm, metadata.min_bpm, metadata.max_bpm), (None, None, None, None));
        assert_eq!((metadata.start_key.as_deref(), metadata.end_key.as_deref()), (None, Some("Ab")));
        Ok(())
    });
}

#[test]
fn invalid_bpms_and_keys_are_rejected() {
    let tb = test_bucket();
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "umt_bad_bpm_key");
        let media = create_media(conn, Some(&user), &unique_path("bad-bpm-key"));
        let key = |k: &str| Some(k.to_string());
        for (metadata, message) in [
            (ProtoMediaMetadata { start_bpm: Some(0.0), ..Default::default() }, "invalid_start_bpm"),
            (ProtoMediaMetadata { start_bpm: Some(-5.0), ..Default::default() }, "invalid_start_bpm"),
            (ProtoMediaMetadata { end_bpm: Some(1000.0), ..Default::default() }, "invalid_end_bpm"),
            (ProtoMediaMetadata { end_bpm: Some(f32::NAN), ..Default::default() }, "invalid_end_bpm"),
            (ProtoMediaMetadata { min_bpm: Some(0.0), ..Default::default() }, "invalid_min_bpm"),
            (ProtoMediaMetadata { max_bpm: Some(f32::INFINITY), ..Default::default() }, "invalid_max_bpm"),
            (
                ProtoMediaMetadata { min_bpm: Some(131.0), max_bpm: Some(130.0), ..Default::default() },
                "min_bpm_exceeds_max_bpm",
            ),
            (ProtoMediaMetadata { start_key: key("H"), ..Default::default() }, "invalid_start_key"),
            (ProtoMediaMetadata { end_key: key("c#m"), ..Default::default() }, "invalid_end_key"),
            (ProtoMediaMetadata { end_key: key("C𝄪"), ..Default::default() }, "invalid_end_key"),
            (ProtoMediaMetadata { start_key: key("Dbb"), ..Default::default() }, "invalid_start_key"),
        ] {
            let err = tb
                .block_on(update_media(
                    Media { id: media.id.to_proto_id(), metadata: Some(metadata), ..Default::default() },
                    &user,
                    conn,
                    &tb.bucket,
                ))
                .unwrap_err();
            assert_eq!(err.code(), tonic::Code::InvalidArgument);
            assert_eq!(err.message(), message);
        }
        Ok(())
    });
}
