//! Specs for `logic::sync_destinations::x_twitter_sync`'s X API v2 interaction correctness (code exchange, token
//! refresh, `users/me` lookup, posting -- including image upload and the refresh-before-post path)
//! run against `factories::serve_x_twitter_api`/`factories::serve_capturing` instead of the real X
//! API. RPC-level permission/ownership handling is covered separately by `sync_destination_rpc_tests`.

use diesel::Connection;
use tonic::Code;

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    exchange_x_twitter_code_for_token_at, get_me_at, post_tweet_at, refresh_access_token_at,
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
fn exchange_code_for_token_returns_the_token_pair() {
    let base_url = serve_x_twitter_api(true, "x-user-1", "unused", "unused");

    let (access_token, refresh_token, expires_in) = exchange_x_twitter_code_for_token_at(
        &base_url,
        "test-client-id",
        "test-client-secret",
        "test-code",
        "test-verifier",
        "https://example.com/oauth-callback.html",
    )
    .expect("code exchange should succeed");
    assert_eq!(access_token, "x-access-token");
    assert_eq!(refresh_token, "x-refresh-token");
    assert_eq!(expires_in, 7200);
}

#[test]
fn exchange_code_for_token_fails_for_an_invalid_code() {
    let base_url = serve_x_twitter_api(false, "x-user-1", "unused", "unused");

    let err = exchange_x_twitter_code_for_token_at(
        &base_url,
        "test-client-id",
        "test-client-secret",
        "bad-code",
        "test-verifier",
        "https://example.com/oauth-callback.html",
    )
    .unwrap_err();
    assert_eq!(err.code(), Code::FailedPrecondition);
    assert_eq!(err.message(), "x_twitter_code_exchange_failed");
}

#[test]
fn refresh_access_token_returns_a_rotated_token_pair() {
    let base_url = serve_x_twitter_api(true, "x-user-1", "unused", "unused");

    let (access_token, refresh_token, expires_in) =
        refresh_access_token_at(&base_url, "test-client-id", "test-client-secret", "old-refresh-token")
            .expect("refresh should succeed");
    assert_eq!(access_token, "refreshed-x-access-token");
    assert_eq!(refresh_token, "refreshed-x-refresh-token");
    assert_eq!(expires_in, 7200);
}

#[test]
fn get_me_returns_the_user_id_and_username() {
    let base_url = serve_x_twitter_api(true, "x-user-1", "jon_on_x", "unused");

    let (x_user_id, username) =
        get_me_at(&base_url, "x-access-token").expect("lookup should succeed");
    assert_eq!(x_user_id, "x-user-1");
    assert_eq!(username, "jon_on_x");
}

fn x_twitter_destination(expires_at: i64) -> models::SyncDestination {
    models::SyncDestination {
        id: 1,
        user_id: 1,
        configuration: serde_json::json!({
            "x_twitter_account": {
                "x_user_id": "x-user-1",
                "username": "jon_on_x",
                "access_token": "stored-access-token",
                "refresh_token": "stored-refresh-token",
                "expires_at": expires_at,
            }
        }),
        created_at: std::time::SystemTime::now(),
        updated_at: None,
    }
}

fn far_future_expiry() -> i64 {
    chrono::Utc::now().timestamp() + 3600
}

#[test]
fn post_tweet_succeeds_text_only_and_does_not_refresh_a_still_valid_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn: &mut PgPooledConnection| {
        let base_url = serve_x_twitter_api(true, "x-user-1", "jon_on_x", "tweet-123");

        let (tweet_id, permalink) = post_tweet_at(
            &base_url,
            "test-client-id",
            "test-client-secret",
            &x_twitter_destination(far_future_expiry()),
            &message("Hello, X!", vec![]),
            conn,
        )
        .expect("post should succeed");
        assert_eq!(tweet_id, "tweet-123");
        assert_eq!(permalink, "https://x.com/jon_on_x/status/tweet-123");

        Ok(())
    });
}

#[test]
fn post_tweet_fails_when_destination_is_not_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn: &mut PgPooledConnection| {
        let destination = models::SyncDestination {
            id: 1,
            user_id: 1,
            configuration: serde_json::json!({}),
            created_at: std::time::SystemTime::now(),
            updated_at: None,
        };

        let err = post_tweet_at(
            "http://127.0.0.1:1",
            "test-client-id",
            "test-client-secret",
            &destination,
            &message("Hello", vec![]),
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "sync_destination_not_configured");

        Ok(())
    });
}

#[test]
fn post_tweet_refreshes_and_persists_a_new_token_when_the_stored_one_is_expired() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn: &mut PgPooledConnection| {
        use diesel::prelude::*;
        use crate::schema::sync_destinations;

        let owner = create_user(conn, "xtw_refresh");
        let inserted = diesel::insert_into(sync_destinations::table)
            .values(&models::NewSyncDestination {
                user_id: owner.id,
                configuration: serde_json::json!({
                    "x_twitter_account": {
                        "x_user_id": "x-user-1",
                        "username": "jon_on_x",
                        "access_token": "stale-access-token",
                        "refresh_token": "stale-refresh-token",
                        // Already expired.
                        "expires_at": chrono::Utc::now().timestamp() - 10,
                    }
                }),
            })
            .get_result::<models::SyncDestination>(conn)
            .expect("failed to create test x_twitter sync destination");

        let base_url = serve_x_twitter_api(true, "x-user-1", "jon_on_x", "tweet-123");
        post_tweet_at(
            &base_url,
            "test-client-id",
            "test-client-secret",
            &inserted,
            &message("Hello, X!", vec![]),
            conn,
        )
        .expect("post should succeed");

        let reloaded = sync_destinations::table
            .filter(sync_destinations::id.eq(inserted.id))
            .first::<models::SyncDestination>(conn)
            .expect("failed to reload sync destination");
        let account = reloaded.configuration.get("x_twitter_account").unwrap();
        assert_eq!(
            account.get("access_token").and_then(|v| v.as_str()),
            Some("refreshed-x-access-token")
        );
        assert_eq!(
            account.get("refresh_token").and_then(|v| v.as_str()),
            Some("refreshed-x-refresh-token")
        );

        Ok(())
    });
}

#[test]
fn post_tweet_uploads_up_to_4_images_and_skips_video() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn: &mut PgPooledConnection| {
        let (base_url, captured) = serve_capturing(|request, _prior| {
            if request.contains("/2/tweets") {
                ("HTTP/1.1 200 OK", serde_json::json!({ "data": { "id": "tweet-123" } }))
            } else if request.contains("/2/media/upload") {
                ("HTTP/1.1 200 OK", serde_json::json!({ "data": { "id": "x-media-1" } }))
            } else {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "data": { "id": "x-user-1", "username": "jon_on_x" } }),
                )
            }
        });

        let media = vec![
            MediaAttachment {
                url: format!("{base_url}/photo1.jpg"),
                content_type: "image/jpeg".to_string(),
            },
            MediaAttachment {
                url: format!("{base_url}/photo2.jpg"),
                content_type: "image/jpeg".to_string(),
            },
            MediaAttachment {
                url: format!("{base_url}/clip.mp4"),
                content_type: "video/mp4".to_string(),
            },
        ];

        post_tweet_at(
            &base_url,
            "test-client-id",
            "test-client-secret",
            &x_twitter_destination(far_future_expiry()),
            &message("Check this out", media),
            conn,
        )
        .expect("post should succeed");

        let requests = captured.lock().unwrap();
        let upload_count = requests.iter().filter(|r| r.contains("/2/media/upload")).count();
        // Only the 2 images are uploaded -- the video attachment is silently skipped (see the
        // module doc on X video support).
        assert_eq!(upload_count, 2);

        let tweet_request = requests
            .iter()
            .find(|r| r.contains("/2/tweets"))
            .expect("expected a tweet creation request");
        assert!(tweet_request.contains("x-media-1"));

        Ok(())
    });
}
