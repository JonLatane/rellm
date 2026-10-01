//! Specs for what a viewer is served for `LICENSED` media (`web::media::resolve_media_size_for_viewer`)
//! -- pure logic over a `models::Media` row, no DB needed -- plus `MediaMetadata`'s preview-range logic.

use std::time::SystemTime;

use crate::models::{blank_to_none, Media, MediaMetadata, MediaSize};
use crate::protos::MediaConversion;
use crate::web::{media_visible_to_viewer, resolve_media_size_for_viewer};

fn size(conversion: MediaConversion, content_type: &str) -> MediaSize {
    MediaSize {
        conversion: conversion as i32,
        object_storage_path: format!("path/{:?}", conversion),
        content_type: content_type.to_string(),
        size_bytes: 1,
        aspect_ratio: None,
    }
}

fn media_with(sizes: Vec<MediaSize>) -> Media {
    Media {
        id: 1,
        user_id: Some(1),
        name: None,
        description: None,
        generated: false,
        processed: true,
        visibility: "LICENSED".to_string(),
        moderation: "UNMODERATED".to_string(),
        created_at: SystemTime::now(),
        updated_at: SystemTime::now(),
        metadata: serde_json::json!({}),
        sizes: serde_json::to_value(sizes).unwrap(),
    }
}

fn path(result: Result<(String, String), rocket::http::Status>) -> String {
    result.expect("should resolve").0
}

#[test]
fn unlicensed_viewers_get_the_preview_never_the_original() {
    let media = media_with(vec![
        size(MediaConversion::Original, "video/mp4"),
        size(MediaConversion::UnlicensedPreviewMedium, "video/mp4"),
    ]);
    for requested in [None, Some("original"), Some("large"), Some("unlicensed_preview")] {
        assert_eq!(
            path(resolve_media_size_for_viewer(&media, requested, false)),
            "path/UnlicensedPreviewMedium",
            "{requested:?}"
        );
    }
}

#[test]
fn unlicensed_viewers_may_still_fetch_thumbnails() {
    let media = media_with(vec![
        size(MediaConversion::Original, "video/mp4"),
        size(MediaConversion::UnlicensedPreviewMedium, "video/mp4"),
        size(MediaConversion::VideoPreviewThumbnailSmall, "image/jpeg"),
    ]);
    assert_eq!(
        path(resolve_media_size_for_viewer(&media, Some("video_preview_small"), false)),
        "path/VideoPreviewThumbnailSmall"
    );
}

#[test]
fn unlicensed_viewers_are_forbidden_when_no_preview_exists() {
    let media = media_with(vec![size(MediaConversion::Original, "video/mp4")]);
    assert_eq!(
        resolve_media_size_for_viewer(&media, None, false).unwrap_err(),
        rocket::http::Status::Forbidden
    );
}

#[test]
fn licensed_images_fall_back_to_small_for_unlicensed_viewers() {
    let media = media_with(vec![
        size(MediaConversion::Original, "image/png"),
        size(MediaConversion::Small, "image/png"),
        size(MediaConversion::Medium, "image/png"),
    ]);
    assert_eq!(path(resolve_media_size_for_viewer(&media, Some("original"), false)), "path/Small");
}

#[test]
fn full_access_viewers_get_the_requested_size() {
    let media = media_with(vec![
        size(MediaConversion::Original, "video/mp4"),
        size(MediaConversion::UnlicensedPreviewMedium, "video/mp4"),
    ]);
    assert_eq!(path(resolve_media_size_for_viewer(&media, Some("original"), true)), "path/Original");
}

#[test]
fn preview_range_defaults_to_first_30s_and_clamps_to_duration() {
    let metadata = MediaMetadata::default();
    assert_eq!(metadata.effective_unlicensed_preview_range_ms(120_000), Some((0, 30_000)));
    assert_eq!(metadata.effective_unlicensed_preview_range_ms(10_000), Some((0, 10_000)));

    let metadata = MediaMetadata {
        unlicensed_preview_start_ms: Some(5_000),
        unlicensed_preview_end_ms: Some(500_000),
        ..Default::default()
    };
    assert_eq!(metadata.effective_unlicensed_preview_range_ms(60_000), Some((5_000, 60_000)));
}

#[test]
fn preview_range_is_none_when_start_is_past_the_end() {
    let metadata = MediaMetadata { unlicensed_preview_start_ms: Some(90_000), ..Default::default() };
    assert_eq!(metadata.effective_unlicensed_preview_range_ms(60_000), None);
}

#[test]
fn blank_credits_become_none() {
    assert_eq!(blank_to_none(Some("  ".to_string())), None);
    assert_eq!(blank_to_none(Some(" A ".to_string())), Some("A".to_string()));
    assert_eq!(blank_to_none(None), None);
}

fn media_visibility(visibility: &str, owner_id: i64) -> Media {
    Media { visibility: visibility.to_string(), user_id: Some(owner_id), ..media_with(vec![]) }
}

#[test]
fn visibility_rules_for_media_file_requests() {
    use crate::tests::factories::*;
    use diesel::Connection;
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let anon = None;
        let owner = create_user(conn, "mv_owner");
        let stranger = create_user(conn, "mv_stranger");
        let plain_admin = create_user(conn, "mv_admin");
        let admin = grant_permissions(conn, &plain_admin, vec![crate::protos::Permission::Admin]);
        let owner_id = owner.id;
        let can = |visibility: &str, viewer: Option<&crate::models::User>, follows: bool, globally: bool| {
            media_visible_to_viewer(&media_visibility(visibility, owner_id), viewer, follows, globally)
        };

        assert!(can("GLOBAL_PUBLIC", anon, false, false));
        assert!(!can("SERVER_PUBLIC", anon, false, false));
        assert!(can("SERVER_PUBLIC", Some(&stranger), false, false));

        // LICENSED: logged-in always, anonymous only with the setting.
        assert!(!can("LICENSED", anon, false, false));
        assert!(can("LICENSED", anon, false, true));
        assert!(can("LICENSED", Some(&stranger), false, false));

        assert!(!can("LIMITED", Some(&stranger), false, false));
        assert!(can("LIMITED", Some(&stranger), true, false));
        assert!(!can("LIMITED", anon, true, false));

        assert!(!can("PRIVATE", anon, false, true));
        assert!(!can("PRIVATE", Some(&stranger), true, true));
        assert!(can("PRIVATE", Some(&owner), false, false));
        assert!(can("PRIVATE", Some(&admin), false, false));
        Ok(())
    });
}
