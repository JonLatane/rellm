//! Specs for `logic::sync_destinations::facebook_sync`'s Graph API interaction correctness (token exchange, Page
//! lookup, posting, Instagram's linked-account lookup + 2-step publish flow) run against
//! `factories::serve_facebook_graph_api`/`factories::serve_facebook_graph_api_instagram` instead of
//! the real Facebook/Instagram Graph API. RPC-level permission/ownership handling is covered
//! separately by `sync_destination_rpc_tests`/`post_sync_rpc_tests`. `SyncMessage`'s own
//! text-formatting correctness is covered by `sync_message_tests`.

use chrono::{TimeZone, Utc};
use tonic::Code;

use crate::logic::{
    connect_facebook_page_at, get_linked_instagram_business_account_at, post_occasion_at,
    post_post_at, post_to_instagram_at, MediaAttachment, SyncMessage,
};
use crate::models;
use crate::tests::factories::*;

/// `app_id`/`app_secret` are this Rellm server's own Facebook App credentials (now sourced from
/// `ServerConfiguration.federation_info.facebook_auth_config`, not an env var) -- their actual
/// value doesn't matter against a mock server, only that they're passed through.
const TEST_APP_ID: &str = "test-app-id";
const TEST_APP_SECRET: &str = "test-app-secret";

fn message(text: &str, link: Option<&str>) -> SyncMessage {
    SyncMessage {
        text: text.to_string(),
        link: link.map(str::to_string),
        media: vec![],
    }
}

#[test]
fn connect_succeeds_for_a_page_the_user_manages() {
    let base_url = serve_facebook_graph_api(Some(("123", "Test Page", "page-token")), "unused");

    let connection = connect_facebook_page_at(
        &base_url,
        TEST_APP_ID,
        TEST_APP_SECRET,
        "short-lived-token",
        "123",
    )
    .expect("connect should succeed");
    assert_eq!(connection.page_id, "123");
    assert_eq!(connection.page_name, "Test Page");
    assert_eq!(connection.access_token, "page-token");
}

#[test]
fn connect_fails_for_a_page_the_user_does_not_manage() {
    let base_url = serve_facebook_graph_api(Some(("123", "Test Page", "page-token")), "unused");

    let err = connect_facebook_page_at(
        &base_url,
        TEST_APP_ID,
        TEST_APP_SECRET,
        "short-lived-token",
        "999",
    )
    .unwrap_err();
    assert_eq!(err.code(), Code::PermissionDenied);
    assert_eq!(err.message(), "facebook_page_not_managed_by_user");
}

#[test]
fn connect_fails_when_user_manages_no_pages() {
    let base_url = serve_facebook_graph_api(None, "unused");

    let err = connect_facebook_page_at(
        &base_url,
        TEST_APP_ID,
        TEST_APP_SECRET,
        "short-lived-token",
        "123",
    )
    .unwrap_err();
    assert_eq!(err.code(), Code::PermissionDenied);
    assert_eq!(err.message(), "facebook_page_not_managed_by_user");
}

#[test]
fn post_occasion_returns_the_new_posts_id_and_url() {
    let base_url = serve_facebook_graph_api(None, "123_456");
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "facebook_page": { "page_id": "123", "page_name": "Test Page", "access_token": "page-token" }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let starts_at = Utc.with_ymd_and_hms(2099, 1, 1, 9, 0, 0).unwrap();
    let ends_at = Utc.with_ymd_and_hms(2099, 1, 1, 11, 0, 0).unwrap();
    let _ = (starts_at, ends_at); // formatting itself is covered by `sync_message_tests`.

    let (post_id, post_url) = post_occasion_at(
        &base_url,
        &destination,
        &message("Test Event\n\nCome join us!", Some("https://example.com/event/abc")),
    )
    .expect("post should succeed");
    assert_eq!(post_id, "123_456");
    assert_eq!(post_url, "https://www.facebook.com/123_456");
}

#[test]
fn post_occasion_fails_when_destination_is_not_configured() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({}),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_occasion_at("http://127.0.0.1:1", &destination, &message("", None))
        .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "sync_destination_not_configured");
}

#[test]
fn post_post_at_returns_the_new_posts_id_and_url() {
    let base_url = serve_facebook_graph_api(None, "789_012");
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "facebook_page": { "page_id": "123", "page_name": "Test Page", "access_token": "page-token" }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let (post_id, post_url) = post_post_at(
        &base_url,
        &destination,
        &message("Test Post\n\nCheck this out!", None),
    )
    .expect("post should succeed");
    assert_eq!(post_id, "789_012");
    assert_eq!(post_url, "https://www.facebook.com/789_012");
}

#[test]
fn post_post_at_fails_when_destination_is_not_configured() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({}),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err =
        post_post_at("http://127.0.0.1:1", &destination, &message("", None)).unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "sync_destination_not_configured");
}

#[test]
fn post_post_uploads_photos_before_posting_to_feed_with_attached_media() {
    let (base_url, captured) = serve_capturing(|request, prior| {
        if request.contains("/photos") {
            let index = prior.iter().filter(|r| r.contains("/photos")).count();
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "id": format!("photo-{index}") }),
            )
        } else {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "789_012" }))
        }
    });
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "facebook_page": { "page_id": "123", "page_name": "Test Page", "access_token": "page-token" }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Check out these photos!".to_string(),
        link: Some("https://example.com/should-be-dropped".to_string()),
        media: vec![
            MediaAttachment {
                url: "https://example.com/photo1.jpg".to_string(),
                content_type: "image/jpeg".to_string(),
            },
            MediaAttachment {
                url: "https://example.com/photo2.jpg".to_string(),
                content_type: "image/png".to_string(),
            },
        ],
    };

    let (post_id, _post_url) =
        post_post_at(&base_url, &destination, &sync_message).expect("post should succeed");
    assert_eq!(post_id, "789_012");

    let requests = captured.lock().unwrap();
    let photo_requests: Vec<&String> = requests.iter().filter(|r| r.contains("/photos")).collect();
    assert_eq!(photo_requests.len(), 2);
    let feed_index = requests.iter().position(|r| r.contains("/feed")).unwrap();
    let last_photo_index = requests.iter().rposition(|r| r.contains("/photos")).unwrap();
    assert!(
        last_photo_index < feed_index,
        "expected both /photos uploads to happen before /feed"
    );
    let feed_request = &requests[feed_index];
    assert!(feed_request.contains("attached_media"));
    assert!(feed_request.contains("photo-0"));
    assert!(feed_request.contains("photo-1"));
    assert!(feed_request.contains("media_fbid"));
    // Link is dropped when attaching photos.
    assert!(!feed_request.contains("should-be-dropped"));
}

#[test]
fn post_post_uses_the_dedicated_videos_endpoint_for_a_video_attachment() {
    let (base_url, captured) = serve_capturing(|_request, _prior| {
        ("HTTP/1.1 200 OK", serde_json::json!({ "id": "video-1" }))
    });
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "facebook_page": { "page_id": "123", "page_name": "Test Page", "access_token": "page-token" }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Watch this!".to_string(),
        link: None,
        media: vec![MediaAttachment {
            url: "https://example.com/clip.mp4".to_string(),
            content_type: "video/mp4".to_string(),
        }],
    };

    let (post_id, post_url) =
        post_post_at(&base_url, &destination, &sync_message).expect("post should succeed");
    assert_eq!(post_id, "video-1");
    assert_eq!(post_url, "https://www.facebook.com/123/videos/video-1");

    let requests = captured.lock().unwrap();
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("/videos"));
    assert!(requests[0].contains("file_url="));
    assert!(!requests.iter().any(|r| r.contains("/feed")));
}

#[test]
fn get_linked_instagram_business_account_returns_the_linked_account() {
    let base_url = serve_facebook_graph_api_instagram(Some(("ig-123", "ig_user")), "unused");

    let (id, username) =
        get_linked_instagram_business_account_at(&base_url, "page-token", "123")
            .expect("lookup should succeed");
    assert_eq!(id, "ig-123");
    assert_eq!(username, "ig_user");
}

#[test]
fn get_linked_instagram_business_account_fails_when_none_linked() {
    let base_url = serve_facebook_graph_api_instagram(None, "unused");

    let err = get_linked_instagram_business_account_at(&base_url, "page-token", "123")
        .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "instagram_no_linked_business_account");
}

#[test]
fn post_to_instagram_fails_fast_with_no_media() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "instagram_account": {
                "instagram_business_account_id": "ig-123",
                "username": "ig_user",
                "page_id": "123",
                "access_token": "page-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_to_instagram_at("http://127.0.0.1:1", &destination, &message("Caption", None))
        .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "instagram_requires_media");
}

#[test]
fn post_to_instagram_publishes_and_returns_the_permalink() {
    let base_url = serve_facebook_graph_api_instagram(Some(("ig-123", "ig_user")), "media-999");
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "instagram_account": {
                "instagram_business_account_id": "ig-123",
                "username": "ig_user",
                "page_id": "123",
                "access_token": "page-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Check this out!".to_string(),
        link: None,
        media: vec![MediaAttachment {
            url: "https://example.com/photo.jpg".to_string(),
            content_type: "image/jpeg".to_string(),
        }],
    };

    let (media_id, permalink) = post_to_instagram_at(&base_url, &destination, &sync_message)
        .expect("post should succeed");
    assert_eq!(media_id, "media-999");
    assert_eq!(
        permalink,
        "https://www.instagram.com/p/media-999-permalink/"
    );
}

#[test]
fn post_to_instagram_uses_video_url_and_media_type_for_a_video_attachment() {
    let (base_url, captured) = serve_capturing(|request, _prior| {
        if request.contains("/media_publish") {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "media-999" }))
        } else if request.contains("fields=permalink") {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "permalink": "https://www.instagram.com/p/media-999-permalink/" }),
            )
        } else {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "media-999-creation" }))
        }
    });
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "instagram_account": {
                "instagram_business_account_id": "ig-123",
                "username": "ig_user",
                "page_id": "123",
                "access_token": "page-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Watch this!".to_string(),
        link: None,
        media: vec![MediaAttachment {
            url: "https://example.com/clip.mp4".to_string(),
            content_type: "video/mp4".to_string(),
        }],
    };

    post_to_instagram_at(&base_url, &destination, &sync_message).expect("post should succeed");

    let requests = captured.lock().unwrap();
    let create_request = requests
        .iter()
        .find(|r| r.contains("video_url="))
        .expect("expected the media creation request to include video_url");
    assert!(create_request.contains("media_type=REELS"));
    assert!(!requests.iter().any(|r| r.contains("image_url=")));
}

#[test]
fn post_to_instagram_fails_when_destination_is_not_configured() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({}),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Caption".to_string(),
        link: None,
        media: vec![MediaAttachment {
            url: "https://example.com/photo.jpg".to_string(),
            content_type: "image/jpeg".to_string(),
        }],
    };

    let err = post_to_instagram_at("http://127.0.0.1:1", &destination, &sync_message)
        .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "sync_destination_not_configured");
}
