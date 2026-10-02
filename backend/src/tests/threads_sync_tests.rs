//! Specs for `logic::sync_destinations::threads_sync`'s Graph API interaction correctness (code exchange, long-lived
//! token exchange, username lookup, posting -- including media type selection), run against
//! `factories::serve_threads_api`/`factories::serve_capturing` instead of the real Threads API.
//! RPC-level permission/ownership handling is covered separately by `sync_destination_rpc_tests`.

use tonic::Code;

use crate::logic::{
    exchange_code_for_token_at, exchange_long_lived_token_at, get_username_at, post_thread_at,
    MediaAttachment, SyncMessage,
};
use crate::models;
use crate::tests::factories::*;

fn message(text: &str, media: Vec<MediaAttachment>) -> SyncMessage {
    SyncMessage {
        text: text.to_string(),
        link: None,
        media,
    }
}

#[test]
fn exchange_code_for_token_returns_the_access_token_and_user_id() {
    let base_url = serve_threads_api(true, "threads-user-1", "unused", "unused", "unused");

    let (access_token, threads_user_id) = exchange_code_for_token_at(
        &base_url,
        "test-app-id",
        "test-app-secret",
        "test-code",
        "https://example.com/oauth-callback.html",
    )
    .expect("code exchange should succeed");
    assert_eq!(access_token, "short-lived-threads-token");
    assert_eq!(threads_user_id, "threads-user-1");
}

#[test]
fn exchange_code_for_token_fails_for_an_invalid_code() {
    let base_url = serve_threads_api(false, "threads-user-1", "unused", "unused", "unused");

    let err = exchange_code_for_token_at(
        &base_url,
        "test-app-id",
        "test-app-secret",
        "bad-code",
        "https://example.com/oauth-callback.html",
    )
    .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "threads_code_exchange_failed");
}

#[test]
fn exchange_long_lived_token_returns_the_long_lived_token() {
    let base_url = serve_threads_api(true, "threads-user-1", "unused", "unused", "unused");

    let access_token = exchange_long_lived_token_at(&base_url, "test-app-secret", "short-lived")
        .expect("exchange should succeed");
    assert_eq!(access_token, "long-lived-threads-token");
}

#[test]
fn get_username_returns_the_username() {
    let base_url = serve_threads_api(true, "threads-user-1", "jon_on_threads", "unused", "unused");

    let username = get_username_at(&base_url, "long-lived-threads-token", "threads-user-1")
        .expect("lookup should succeed");
    assert_eq!(username, "jon_on_threads");
}

fn threads_destination() -> models::SyncDestination {
    models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "threads_account": {
                "threads_user_id": "threads-user-1",
                "username": "jon_on_threads",
                "access_token": "long-lived-threads-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    }
}

#[test]
fn post_thread_succeeds_text_only() {
    // Unlike Instagram, text-only posts are valid on Threads -- doesn't early-return on empty
    // media.
    let base_url = serve_threads_api(
        true,
        "threads-user-1",
        "jon_on_threads",
        "thread-123",
        "https://www.threads.net/@jon_on_threads/post/thread-123",
    );

    let (post_id, permalink) =
        post_thread_at(&base_url, &threads_destination(), &message("Hello, Threads!", vec![]))
            .expect("post should succeed");
    assert_eq!(post_id, "thread-123");
    assert_eq!(
        permalink,
        "https://www.threads.net/@jon_on_threads/post/thread-123"
    );
}

#[test]
fn post_thread_fails_when_destination_is_not_configured() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({}),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_thread_at("http://127.0.0.1:1", &destination, &message("Hello", vec![]))
        .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "sync_destination_not_configured");
}

#[test]
fn post_thread_sends_image_url_and_media_type_image_for_an_image_attachment() {
    let (base_url, captured) = serve_capturing(|request, _prior| {
        if request.contains("/threads_publish") {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "thread-123" }))
        } else if request.contains("fields=permalink") {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "permalink": "https://www.threads.net/@jon/post/thread-123" }),
            )
        } else {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "creation-1" }))
        }
    });

    let media = vec![MediaAttachment {
        url: "https://example.com/photo.jpg".to_string(),
        content_type: "image/jpeg".to_string(),
    }];
    post_thread_at(&base_url, &threads_destination(), &message("Check this out", media))
        .expect("post should succeed");

    let requests = captured.lock().unwrap();
    let create_request = requests
        .iter()
        .find(|r| r.contains("image_url="))
        .expect("expected a media container request with image_url");
    assert!(create_request.contains("media_type=IMAGE"));
    assert!(create_request.contains("example.com"));
    assert!(create_request.contains("photo.jpg"));
}

#[test]
fn post_thread_sends_video_url_and_media_type_video_for_a_video_attachment() {
    let (base_url, captured) = serve_capturing(|request, _prior| {
        if request.contains("/threads_publish") {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "thread-123" }))
        } else if request.contains("fields=permalink") {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "permalink": "https://www.threads.net/@jon/post/thread-123" }),
            )
        } else {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "creation-1" }))
        }
    });

    let media = vec![MediaAttachment {
        url: "https://example.com/clip.mp4".to_string(),
        content_type: "video/mp4".to_string(),
    }];
    post_thread_at(&base_url, &threads_destination(), &message("Watch this", media))
        .expect("post should succeed");

    let requests = captured.lock().unwrap();
    let create_request = requests
        .iter()
        .find(|r| r.contains("video_url="))
        .expect("expected a media container request with video_url");
    assert!(create_request.contains("media_type=VIDEO"));
}
