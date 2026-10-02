//! Connects a `SyncDestination` to a Mastodon account (via a user-pasted Personal Access Token --
//! Mastodon instances are user-chosen arbitrary domains, so there's no single app to register ahead
//! of time the way Facebook has one) and posts `Occasion`s/`Post`s to it as a status, with
//! attached media (up to Mastodon's own 4-attachment-per-status limit).
//!
//! No text-length truncation here -- unlike Bluesky's hard 300-grapheme limit, Mastodon's status
//! length limit varies per instance (the default is 500, but admins can raise or lower it), so
//! there's nothing sensible to guess-truncate to. A too-long status just surfaces as the API's own
//! 422 (`mastodon_post_failed`).

use tonic::{Code, Status};

use crate::logic::http_client::{blocking_json_request, run_blocking};
use crate::logic::{MediaAttachment, SyncMessage};
use crate::models;

/// Mastodon's own per-status attachment limit.
const MAX_MEDIA_ATTACHMENTS: usize = 4;

/// Verifies `access_token` is a valid Personal Access Token for `instance_host`, returning the
/// account's username. Used both to validate a `MastodonAccount` on connect (`CreateSyncDestination`/
/// `UpdateSyncDestination`) and to populate `MastodonAccount.username` in the stored configuration.
pub fn verify_credentials(instance_host: &str, access_token: &str) -> Result<String, Status> {
    verify_credentials_at(&format!("https://{instance_host}"), access_token)
}

/// Same as `verify_credentials`, but against an arbitrary `base_url` -- lets specs point this at a
/// local mock server instead of a real Mastodon instance (see `factories::serve_mastodon_api`).
pub fn verify_credentials_at(base_url: &str, access_token: &str) -> Result<String, Status> {
    let url = format!("{base_url}/api/v1/accounts/verify_credentials");
    let (status, body) = blocking_json_request(
        move |client| client.get(&url).bearer_auth(access_token),
        "mastodon_request_failed",
    )?;
    if !status.is_success() {
        log::error!(
            "Mastodon verify_credentials failed ({}): {:?}",
            status,
            body
        );
        return Err(Status::new(
            Code::FailedPrecondition,
            "mastodon_token_invalid",
        ));
    }
    body.get("username")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Mastodon verify_credentials response missing username: {:?}",
                body
            );
            Status::new(Code::FailedPrecondition, "mastodon_token_invalid")
        })
}

/// Posts an already-built `SyncMessage` (including up to `MAX_MEDIA_ATTACHMENTS` attached media)
/// to `destination`'s connected Mastodon account as a new status. Returns the new status's ID and
/// its public permalink.
pub fn post_status(
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    let not_configured =
        || Status::new(Code::FailedPrecondition, "sync_destination_not_configured");
    let instance_host = destination
        .configuration
        .get("mastodon_account")
        .and_then(|c| c.get("instance_host"))
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;
    post_status_at(&format!("https://{instance_host}"), destination, message)
}

/// Same as `post_status`, but against an arbitrary `base_url` -- see `verify_credentials_at`.
pub fn post_status_at(
    base_url: &str,
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    let not_configured =
        || Status::new(Code::FailedPrecondition, "sync_destination_not_configured");
    let mastodon_account = destination
        .configuration
        .get("mastodon_account")
        .ok_or_else(not_configured)?;
    let access_token = mastodon_account
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;

    // Mastodon's media API takes actual file bytes, not a remote URL (unlike Facebook/
    // Instagram/Threads), so each attachment has to be fetched from Rellm's own public media
    // URL first, then re-uploaded. Individual fetch/upload failures are logged and skipped (a
    // partially-illustrated status is better than none) -- only failing the whole post if every
    // attempted upload failed.
    let attempted = message.media.len().min(MAX_MEDIA_ATTACHMENTS);
    let mut media_ids = Vec::with_capacity(attempted);
    for media in message.media.iter().take(MAX_MEDIA_ATTACHMENTS) {
        match upload_media_at(base_url, access_token, media) {
            Ok(id) => media_ids.push(id),
            Err(e) => log::error!(
                "Failed to upload media {:?} to Mastodon, skipping: {:?}",
                media.url,
                e
            ),
        }
    }
    if attempted > 0 && media_ids.is_empty() {
        return Err(Status::new(
            Code::FailedPrecondition,
            "mastodon_media_upload_failed",
        ));
    }

    let url = format!("{base_url}/api/v1/statuses");
    let status_text = message.text.clone();
    let (status, body) = blocking_json_request(
        move |client| {
            let mut form: Vec<(String, String)> = vec![("status".to_string(), status_text)];
            for id in &media_ids {
                form.push(("media_ids[]".to_string(), id.clone()));
            }
            client.post(&url).bearer_auth(access_token).form(&form)
        },
        "mastodon_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Mastodon post_status failed ({}): {:?}", status, body);
        return Err(Status::new(Code::FailedPrecondition, "mastodon_post_failed"));
    }
    let id = body
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Mastodon post_status response missing id: {:?}", body);
            Status::new(Code::Internal, "mastodon_post_failed")
        })?;
    let url = body
        .get("url")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Mastodon post_status response missing url: {:?}", body);
            Status::new(Code::Internal, "mastodon_post_failed")
        })?;
    Ok((id, url))
}

/// Fetches `media.url`'s raw bytes from this Rellm server's own public media endpoint, then
/// re-uploads them to `base_url`'s `/api/v2/media` as `multipart/form-data`. Returns the new media
/// attachment's ID (to pass as `media_ids[]` on the subsequent `/api/v1/statuses` call). The v2
/// endpoint may return while Mastodon is still processing the attachment server-side for large
/// files -- this doesn't poll/retry for that, just attaches the returned id immediately, which is
/// standard practice for typical image sizes.
fn upload_media_at(base_url: &str, access_token: &str, media: &MediaAttachment) -> Result<String, Status> {
    let media_url = media.url.clone();
    let content_type = media.content_type.clone();
    let bytes = run_blocking(move || -> Result<Vec<u8>, Status> {
        let response = reqwest::blocking::Client::new()
            .get(&media_url)
            .send()
            .map_err(|e| {
                log::error!("Failed to fetch media {:?} for Mastodon upload: {:?}", media_url, e);
                Status::new(Code::FailedPrecondition, "mastodon_media_fetch_failed")
            })?;
        if !response.status().is_success() {
            log::error!(
                "Fetching media {:?} for Mastodon upload failed ({})",
                media_url,
                response.status()
            );
            return Err(Status::new(
                Code::FailedPrecondition,
                "mastodon_media_fetch_failed",
            ));
        }
        response.bytes().map(|b| b.to_vec()).map_err(|e| {
            log::error!("Failed to read media {:?} bytes: {:?}", media_url, e);
            Status::new(Code::FailedPrecondition, "mastodon_media_fetch_failed")
        })
    })?;

    let url = format!("{base_url}/api/v2/media");
    let access_token = access_token.to_string();
    let (status, body) = run_blocking(move || -> Result<(reqwest::StatusCode, serde_json::Value), Status> {
        let part = reqwest::blocking::multipart::Part::bytes(bytes)
            .file_name("media")
            .mime_str(&content_type)
            .map_err(|e| {
                log::error!("Invalid media content type {:?}: {:?}", content_type, e);
                Status::new(Code::FailedPrecondition, "mastodon_request_failed")
            })?;
        let form = reqwest::blocking::multipart::Form::new().part("file", part);
        let response = reqwest::blocking::Client::new()
            .post(&url)
            .bearer_auth(&access_token)
            .multipart(form)
            .send()
            .map_err(|e| {
                log::error!("Mastodon media upload request failed: {:?}", e);
                Status::new(Code::FailedPrecondition, "mastodon_request_failed")
            })?;
        let status = response.status();
        let text = response.text().map_err(|e| {
            log::error!("Failed to read Mastodon media upload response body: {:?}", e);
            Status::new(Code::FailedPrecondition, "mastodon_request_failed")
        })?;
        let value: serde_json::Value = if text.trim().is_empty() {
            serde_json::Value::Null
        } else {
            serde_json::from_str(&text).map_err(|e| {
                log::error!("Failed to parse Mastodon media upload response as JSON: {:?} ({})", e, text);
                Status::new(Code::FailedPrecondition, "mastodon_request_failed")
            })?
        };
        Ok((status, value))
    })?;
    if !status.is_success() {
        log::error!("Mastodon media upload failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "mastodon_media_upload_failed",
        ));
    }
    body.get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Mastodon media upload response missing id: {:?}", body);
            Status::new(Code::Internal, "mastodon_media_upload_failed")
        })
}
