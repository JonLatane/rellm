//! Specs for `logic::sync_destinations::mastodon_sync`'s REST API interaction correctness (credential verification,
//! posting), run against `factories::serve_mastodon_api` instead of a real Mastodon instance.
//! RPC-level permission/ownership handling is covered separately by `sync_destination_rpc_tests`/
//! `post_sync_rpc_tests`.

use tonic::Code;

use crate::logic::{post_status_at, verify_credentials_at, MediaAttachment, SyncMessage};
use crate::models;
use crate::tests::factories::*;

#[test]
fn verify_credentials_returns_the_username_for_a_valid_token() {
    let base_url = serve_mastodon_api("test_user", true, true, "1", "https://unused");

    let username =
        verify_credentials_at(&base_url, "valid-token").expect("verify should succeed");
    assert_eq!(username, "test_user");
}

#[test]
fn verify_credentials_fails_for_an_invalid_token() {
    let base_url = serve_mastodon_api("test_user", false, true, "1", "https://unused");

    let err = verify_credentials_at(&base_url, "invalid-token").unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "mastodon_token_invalid");
}

fn message(text: &str) -> SyncMessage {
    SyncMessage {
        text: text.to_string(),
        link: None,
        media: vec![],
    }
}

#[test]
fn post_status_returns_the_new_statuss_id_and_url() {
    let base_url = serve_mastodon_api(
        "test_user",
        true,
        true,
        "12345",
        "https://mastodon.social/@test_user/12345",
    );
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "mastodon_account": {
                "instance_host": "mastodon.social",
                "username": "test_user",
                "access_token": "test-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let (id, url) = post_status_at(&base_url, &destination, &message("Hello, Mastodon!"))
        .expect("post should succeed");
    assert_eq!(id, "12345");
    assert_eq!(url, "https://mastodon.social/@test_user/12345");
}

#[test]
fn post_status_uploads_media_before_posting_and_attaches_media_ids() {
    let (base_url, captured) = serve_capturing(|request, _prior| {
        if request.starts_with("GET /media/") {
            // The bytes themselves don't matter -- only that they get fetched and re-uploaded.
            ("HTTP/1.1 200 OK", serde_json::json!("fake-image-bytes"))
        } else if request.contains("/api/v2/media") {
            ("HTTP/1.1 200 OK", serde_json::json!({ "id": "media-attachment-1" }))
        } else {
            (
                "HTTP/1.1 200 OK",
                serde_json::json!({ "id": "12345", "url": "https://mastodon.social/@test_user/12345" }),
            )
        }
    });
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "mastodon_account": {
                "instance_host": "mastodon.social",
                "username": "test_user",
                "access_token": "test-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };
    let sync_message = SyncMessage {
        text: "Check this out!".to_string(),
        link: None,
        media: vec![MediaAttachment {
            url: format!("{base_url}/media/1"),
            content_type: "image/jpeg".to_string(),
        }],
    };

    let (id, _url) =
        post_status_at(&base_url, &destination, &sync_message).expect("post should succeed");
    assert_eq!(id, "12345");

    let requests = captured.lock().unwrap();
    let fetch_index = requests.iter().position(|r| r.starts_with("GET /media/")).unwrap();
    let upload_index = requests.iter().position(|r| r.contains("/api/v2/media")).unwrap();
    let status_index = requests.iter().position(|r| r.contains("/api/v1/statuses")).unwrap();
    assert!(fetch_index < upload_index, "media should be fetched before being uploaded");
    assert!(upload_index < status_index, "media should be uploaded before posting the status");
    assert!(requests[status_index].contains("media_ids"));
    assert!(requests[status_index].contains("media-attachment-1"));
}

#[test]
fn post_status_fails_when_the_api_rejects_the_post() {
    let base_url = serve_mastodon_api("test_user", true, false, "12345", "https://unused");
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "mastodon_account": {
                "instance_host": "mastodon.social",
                "username": "test_user",
                "access_token": "test-token"
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_status_at(&base_url, &destination, &message("Too long..."))
        .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "mastodon_post_failed");
}

#[test]
fn post_status_fails_when_destination_is_not_configured() {
    let destination = models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({}),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    };

    let err = post_status_at("http://127.0.0.1:1", &destination, &message("Hello")).unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "sync_destination_not_configured");
}
