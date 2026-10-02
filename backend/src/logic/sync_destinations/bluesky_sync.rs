//! Connects a `SyncDestination` to a Bluesky (AT Protocol) account via an "App Password" (not the
//! account's main password) and posts `Occasion`s/`Post`s to it as a `app.bsky.feed.post`
//! record.
//!
//! Sessions are created fresh per post rather than stored/refreshed -- App Passwords don't expire,
//! so re-authenticating on every `post_record` call is simpler than session-refresh bookkeeping and
//! avoids session-expiry bugs entirely.

use tonic::{Code, Status};

use crate::logic::http_client::{blocking_json_request, run_blocking};
use crate::logic::truncate_for_bluesky;
use crate::logic::{MediaAttachment, SyncMessage};
use crate::models;

const DEFAULT_BASE_URL: &str = "https://bsky.social";

/// Bluesky's `app.bsky.embed.images` limit -- the max images a single post can embed.
const MAX_IMAGE_ATTACHMENTS: usize = 4;

/// Authenticates `handle`/`app_password` against Bluesky, returning `(did, access_jwt)`. Used both
/// to validate a `BlueskyAccount` on connect (`CreateSyncDestination`/`UpdateSyncDestination`, which
/// only need the `did`) and fresh before every `post_record` call (which also needs the
/// `access_jwt`).
pub fn create_session(handle: &str, app_password: &str) -> Result<(String, String), Status> {
    create_session_at(DEFAULT_BASE_URL, handle, app_password)
}

/// Same as `create_session`, but against an arbitrary `base_url` -- lets specs point this at a
/// local mock server instead of the real Bluesky API (see `factories::serve_bluesky_api`).
pub fn create_session_at(
    base_url: &str,
    handle: &str,
    app_password: &str,
) -> Result<(String, String), Status> {
    let url = format!("{base_url}/xrpc/com.atproto.server.createSession");
    let body = serde_json::json!({ "identifier": handle, "password": app_password });
    let (status, response) = blocking_json_request(
        move |client| client.post(&url).json(&body),
        "bluesky_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Bluesky createSession failed ({}): {:?}", status, response);
        return Err(Status::new(
            Code::FailedPrecondition,
            "bluesky_credentials_invalid",
        ));
    }
    let did = response
        .get("did")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Bluesky createSession response missing did: {:?}", response);
            Status::new(Code::FailedPrecondition, "bluesky_credentials_invalid")
        })?;
    let access_jwt = response
        .get("accessJwt")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Bluesky createSession response missing accessJwt: {:?}",
                response
            );
            Status::new(Code::FailedPrecondition, "bluesky_credentials_invalid")
        })?;
    Ok((did, access_jwt))
}

/// Posts an already-built `SyncMessage` to `destination`'s connected Bluesky account as a new
/// `app.bsky.feed.post` record. `message.text` is truncated to Bluesky's ~300-character limit
/// first (see `truncate_for_bluesky`) -- the one platform truncated proactively client-side rather
/// than surfacing the API's own rejection, since Bluesky's limit is fixed and known (unlike
/// Mastodon's, which varies per instance). Up to `MAX_IMAGE_ATTACHMENTS` **image** attachments are
/// uploaded and embedded as `app.bsky.embed.images` -- **video attachments are skipped entirely**
/// this round; Bluesky video embeds need a separate, more complex upload-and-processing flow this
/// doesn't build yet (flagged here rather than silently under-built, same spirit as the Threads
/// token-refresh gap). Returns the record's `at://` URI and a human-clickable
/// `https://bsky.app/...` permalink built from it.
pub fn post_record(
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    post_record_at(DEFAULT_BASE_URL, destination, message)
}

/// Same as `post_record`, but against an arbitrary `base_url` -- see `create_session_at`.
pub fn post_record_at(
    base_url: &str,
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    let not_configured =
        || Status::new(Code::FailedPrecondition, "sync_destination_not_configured");
    let bluesky_account = destination
        .configuration
        .get("bluesky_account")
        .ok_or_else(not_configured)?;
    let handle = bluesky_account
        .get("handle")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;
    let app_password = bluesky_account
        .get("app_password")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;

    let (did, access_jwt) = create_session_at(base_url, handle, app_password)?;

    // Skip video entirely (see this function's doc); upload and embed up to
    // `MAX_IMAGE_ATTACHMENTS` images, tolerating individual failures the same way
    // `mastodon_sync::post_status_at` does -- only hard-failing the whole post if every attempted
    // upload failed.
    let images: Vec<&MediaAttachment> = message
        .media
        .iter()
        .filter(|m| m.is_image())
        .take(MAX_IMAGE_ATTACHMENTS)
        .collect();
    let attempted = images.len();
    let mut blobs = Vec::with_capacity(attempted);
    for image in &images {
        match upload_blob_at(base_url, &access_jwt, image) {
            Ok(blob) => blobs.push(blob),
            Err(e) => log::error!(
                "Failed to upload image {:?} to Bluesky, skipping: {:?}",
                image.url,
                e
            ),
        }
    }
    if attempted > 0 && blobs.is_empty() {
        return Err(Status::new(
            Code::FailedPrecondition,
            "bluesky_media_upload_failed",
        ));
    }

    let text = truncate_for_bluesky(&message.text);
    let created_at = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    let mut record = serde_json::json!({
        "$type": "app.bsky.feed.post",
        "text": text,
        "createdAt": created_at,
    });
    if !blobs.is_empty() {
        let images: Vec<serde_json::Value> = blobs
            .into_iter()
            .map(|blob| serde_json::json!({ "image": blob, "alt": "" }))
            .collect();
        record["embed"] = serde_json::json!({
            "$type": "app.bsky.embed.images",
            "images": images,
        });
    }
    let record_body = serde_json::json!({
        "repo": did,
        "collection": "app.bsky.feed.post",
        "record": record,
    });
    let url = format!("{base_url}/xrpc/com.atproto.repo.createRecord");
    let (status, response) = blocking_json_request(
        move |client| client.post(&url).bearer_auth(access_jwt).json(&record_body),
        "bluesky_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Bluesky createRecord failed ({}): {:?}", status, response);
        return Err(Status::new(Code::FailedPrecondition, "bluesky_post_failed"));
    }
    let uri = response
        .get("uri")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Bluesky createRecord response missing uri: {:?}",
                response
            );
            Status::new(Code::Internal, "bluesky_post_failed")
        })?;
    let record_key = uri.rsplit('/').next().unwrap_or("");
    let permalink = format!("https://bsky.app/profile/{did}/post/{record_key}");
    Ok((uri, permalink))
}

/// Fetches `image.url`'s raw bytes from this Rellm server's own public media endpoint, then
/// uploads them to `base_url`'s `com.atproto.repo.uploadBlob` (which takes the raw bytes directly
/// as the request body, not JSON, unlike every other Bluesky XRPC call here). Returns the
/// response's opaque `blob` value as-is, to be embedded directly into the post record -- this
/// doesn't parse its internals.
fn upload_blob_at(
    base_url: &str,
    access_jwt: &str,
    image: &MediaAttachment,
) -> Result<serde_json::Value, Status> {
    let media_url = image.url.clone();
    let content_type = image.content_type.clone();
    let bytes = run_blocking(move || -> Result<Vec<u8>, Status> {
        let response = reqwest::blocking::Client::new()
            .get(&media_url)
            .send()
            .map_err(|e| {
                log::error!("Failed to fetch image {:?} for Bluesky upload: {:?}", media_url, e);
                Status::new(Code::FailedPrecondition, "bluesky_media_fetch_failed")
            })?;
        if !response.status().is_success() {
            log::error!(
                "Fetching image {:?} for Bluesky upload failed ({})",
                media_url,
                response.status()
            );
            return Err(Status::new(
                Code::FailedPrecondition,
                "bluesky_media_fetch_failed",
            ));
        }
        response.bytes().map(|b| b.to_vec()).map_err(|e| {
            log::error!("Failed to read image {:?} bytes: {:?}", media_url, e);
            Status::new(Code::FailedPrecondition, "bluesky_media_fetch_failed")
        })
    })?;

    let url = format!("{base_url}/xrpc/com.atproto.repo.uploadBlob");
    let access_jwt = access_jwt.to_string();
    let (status, body) = run_blocking(move || -> Result<(reqwest::StatusCode, serde_json::Value), Status> {
        let response = reqwest::blocking::Client::new()
            .post(&url)
            .header(reqwest::header::CONTENT_TYPE, content_type.as_str())
            .bearer_auth(&access_jwt)
            .body(bytes)
            .send()
            .map_err(|e| {
                log::error!("Bluesky uploadBlob request failed: {:?}", e);
                Status::new(Code::FailedPrecondition, "bluesky_request_failed")
            })?;
        let status = response.status();
        let text = response.text().map_err(|e| {
            log::error!("Failed to read Bluesky uploadBlob response body: {:?}", e);
            Status::new(Code::FailedPrecondition, "bluesky_request_failed")
        })?;
        let value: serde_json::Value = if text.trim().is_empty() {
            serde_json::Value::Null
        } else {
            serde_json::from_str(&text).map_err(|e| {
                log::error!("Failed to parse Bluesky uploadBlob response as JSON: {:?} ({})", e, text);
                Status::new(Code::FailedPrecondition, "bluesky_request_failed")
            })?
        };
        Ok((status, value))
    })?;
    if !status.is_success() {
        log::error!("Bluesky uploadBlob failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "bluesky_media_upload_failed",
        ));
    }
    body.get("blob").cloned().ok_or_else(|| {
        log::error!("Bluesky uploadBlob response missing blob: {:?}", body);
        Status::new(Code::Internal, "bluesky_media_upload_failed")
    })
}
