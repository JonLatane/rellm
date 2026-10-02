//! Specs for `logic::sync_destinations::bluesky_sync`'s AT Protocol interaction correctness (session creation,
//! posting, and proactive text truncation), run against `factories::serve_bluesky_api` instead of
//! the real Bluesky API. RPC-level permission/ownership handling is covered separately by
//! `sync_destination_rpc_tests`/`post_sync_rpc_tests`.

use tonic::Code;

use crate::logic::{create_session_at, post_record_at, MediaAttachment, SyncMessage};
use crate::models;
use crate::tests::factories::*;

#[test]
fn create_session_returns_the_did_and_access_jwt() {
    let base_url = serve_bluesky_api("did:plc:abc123", "test-jwt", true, true, "at://unused");

    let (did, access_jwt) =
        create_session_at(&base_url, "jon.bsky.social", "app-password").expect("should succeed");
    assert_eq!(did, "did:plc:abc123");
    assert_eq!(access_jwt, "test-jwt");
}

#[test]
fn create_session_fails_for_invalid_credentials() {
    let base_url = serve_bluesky_api("did:plc:abc123", "test-jwt", false, true, "at://unused");

    let err = create_session_at(&base_url, "jon.bsky.social", "wrong-password").unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "bluesky_credentials_invalid");
}

fn message(text: &str) -> SyncMessage {
    SyncMessage {
        text: text.to_string(),
        link: None,
        media: vec![],
    }
}

#[test]
fn post_record_returns_the_uri_and_a_permalink() {
    let base_url = serve_bluesky_api(
        "did:plc:abc123",
        "test-jwt",
        true,
        true,
        "at://did:plc:abc123/app.bsky.feed.post/3jzfcijpj2z2a",
    );
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "bluesky_account": {
                "handle": "jon.bsky.social",
                "did": "did:plc:abc123",
                "app_password": "app-password"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let (uri, permalink) = post_record_at(&base_url, &destination, &message("Hello, Bluesky!"))
        .expect("post should succeed");
    assert_eq!(uri, "at://did:plc:abc123/app.bsky.feed.post/3jzfcijpj2z2a");
    assert_eq!(
        permalink,
        "https://bsky.app/profile/did:plc:abc123/post/3jzfcijpj2z2a"
    );
}

#[test]
fn post_record_truncates_text_over_300_characters() {
    // Not directly observable through `post_record`'s return value (the mock server doesn't
    // inspect the request body) -- `truncate_for_bluesky` itself is covered directly by
    // `sync_message_tests`. This spec just proves `post_record` doesn't fail/panic on
    // over-length text (e.g. from a byte-length assumption mismatching `String::chars`).
    let base_url = serve_bluesky_api(
        "did:plc:abc123",
        "test-jwt",
        true,
        true,
        "at://did:plc:abc123/app.bsky.feed.post/xyz",
    );
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "bluesky_account": {
                "handle": "jon.bsky.social",
                "did": "did:plc:abc123",
                "app_password": "app-password"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let long_text = "a".repeat(500);

    post_record_at(&base_url, &destination, &message(&long_text)).expect("post should succeed");
}

#[test]
fn post_record_uploads_images_and_embeds_them_skipping_video() {
    let (base_url, captured) = serve_capturing(|request, _prior| {
        if request.contains("createSession") {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "did": "did:plc:abc123", "accessJwt": "test-jwt" }),
            )
        } else if request.starts_with("GET /media/") {
            ("HTTP/1.1 200 OK", serde_json::json!("fake-image-bytes"))
        } else if request.contains("uploadBlob") {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "blob": { "$type": "blob", "ref": { "$link": "abc" }, "mimeType": "image/jpeg", "size": 100 } }),
            )
        } else {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "uri": "at://did:plc:abc123/app.bsky.feed.post/xyz" }),
            )
        }
    });
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "bluesky_account": {
                "handle": "jon.bsky.social",
                "did": "did:plc:abc123",
                "app_password": "app-password"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Check out this photo!".to_string(),
        link: None,
        media: vec![
            MediaAttachment {
                url: format!("{base_url}/media/1"),
                content_type: "image/jpeg".to_string(),
            },
            // Video attachments are skipped entirely this round -- should never even be fetched.
            MediaAttachment {
                url: format!("{base_url}/media/2-should-not-be-fetched"),
                content_type: "video/mp4".to_string(),
            },
        ],
    };

    post_record_at(&base_url, &destination, &sync_message).expect("post should succeed");

    let requests = captured.lock().unwrap();
    assert!(requests.iter().any(|r| r.contains("uploadBlob")));
    assert!(!requests.iter().any(|r| r.contains("2-should-not-be-fetched")));
    let create_record_request = requests
        .iter()
        .find(|r| r.contains("createRecord"))
        .expect("expected a createRecord request");
    assert!(create_record_request.contains("\"embed\""));
    assert!(create_record_request.contains("app.bsky.embed.images"));
}

#[test]
fn post_record_fails_when_the_api_rejects_the_post() {
    let base_url = serve_bluesky_api("did:plc:abc123", "test-jwt", true, false, "at://unused");
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "bluesky_account": {
                "handle": "jon.bsky.social",
                "did": "did:plc:abc123",
                "app_password": "app-password"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_record_at(&base_url, &destination, &message("Hello")).unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "bluesky_post_failed");
}

#[test]
fn post_record_fails_when_destination_is_not_configured() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({}),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_record_at("http://127.0.0.1:1", &destination, &message("Hello")).unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "sync_destination_not_configured");
}
