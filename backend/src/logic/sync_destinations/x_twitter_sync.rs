//! Connects a `SyncDestination` to an X (Twitter) account via an OAuth 2.0 Authorization Code +
//! PKCE flow at x.com, and posts `Occasion`s/`Post`s to it via the X API v2 (`api.x.com`).
//!
//! Architecturally closest to `threads_sync`: a `response_type=code` authorize-then-exchange flow
//! (not Facebook's client-side implicit token), directly authorizing the user's own account with
//! no "choose a Page" step. Two real differences from Threads:
//!
//! - **PKCE is mandatory.** X rejects a code exchange without a matching `code_verifier`/
//!   `code_challenge` pair. The popup's `code_challenge_method` is `plain` (challenge ==
//!   verifier), not the stronger `S256` -- computing a SHA-256 challenge needs `crypto.subtle`,
//!   which is only available asynchronously, and the popup must open *synchronously* in direct
//!   response to the user's click to survive mobile Safari's async-popup blocking (see
//!   `public/index.html`'s `facebookLoginPopup` port handler). `plain` is a real, spec-sanctioned
//!   PKCE mode, just a weaker one -- an honest, documented tradeoff, not an oversight.
//! - **Access tokens are short-lived (2 hours)**, unlike Threads' ~60-day token -- too short to
//!   punt on refreshing the way `threads_sync`'s module doc explicitly does. `post_tweet` refreshes
//!   proactively (via the stored `refresh_token`, no user interaction needed) before every post
//!   when the stored token is expired or close to it, persisting the new token pair back to the
//!   `sync_destinations` row -- the one platform-specific `post_*` function in this codebase that
//!   needs a `conn` for that reason.
//!
//! Needs this app's own X Developer App Client ID/Secret (an admin-configured
//! `ServerConfiguration.federation_info.x_twitter_auth_config`, mirroring
//! `facebook_sync::server_facebook_app_credentials`) -- one app registered by the server admin,
//! every user connects their own X account through it.
//!
//! **Known limitation, flagged rather than silently under-built**: only *images* are uploaded (up
//! to 4, downloaded from this server's own media URL and re-uploaded as raw bytes, mirroring
//! `mastodon_sync::upload_media_at`'s fetch-then-reupload shape since X's media endpoint also takes
//! bytes, not a remote URL). Video/GIF is not yet supported -- X's video upload requires a chunked
//! INIT/APPEND/FINALIZE-plus-processing-status-poll flow (mirrors `bluesky_sync`'s own documented
//! video gap) not yet built; a video attachment is silently skipped.

use base64::Engine;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::http_client::{blocking_json_request, run_blocking};
use crate::logic::truncate_for_x_twitter;
use crate::logic::{MediaAttachment, SyncMessage};
use crate::models;
use crate::protos::FederationInfo;
use crate::schema::sync_destinations;

const DEFAULT_API_BASE_URL: &str = "https://api.x.com";
/// X's media upload endpoint only accepts up to 4 images per Tweet (or a single video/GIF instead
/// -- not yet supported here, see the module doc).
const MAX_MEDIA_ATTACHMENTS: usize = 4;
/// Refresh the access token if it expires within this many seconds -- avoids a race where a token
/// that's valid when checked expires mid-request.
const REFRESH_SKEW_SECONDS: i64 = 60;

/// Loads this server's own X Developer App Client ID/Secret, as configured by an admin via
/// `ConfigureServer` (`ServerConfiguration.federation_info.x_twitter_auth_config`) -- required
/// before any `exchange_x_twitter_code_for_token`/`refresh_access_token` call. Reads the raw DB model (not
/// `get_server_configuration_proto`), since that always blanks `client_secret` for client
/// responses -- this needs the real value. Mirrors `facebook_sync::server_facebook_app_credentials`
/// exactly.
pub fn server_x_twitter_app_credentials(
    conn: &mut PgPooledConnection,
) -> Result<(String, String), Status> {
    let configuration = crate::rpcs::get_server_configuration_model(conn)?;
    let federation_info: FederationInfo = serde_json::from_value(configuration.federation_info)
        .map_err(|e| {
            log::error!("Failed to parse stored federation_info: {:?}", e);
            Status::new(Code::Internal, "failed_to_load_server_configuration")
        })?;
    federation_info
        .x_twitter_auth_config
        .filter(|c| !c.client_id.is_empty() && !c.client_secret.is_empty())
        .map(|c| (c.client_id, c.client_secret))
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "x_twitter_app_not_configured"))
}

/// Derives the X OAuth popup's `redirect_uri` -- identical derivation to
/// `threads_sync::threads_redirect_uri` (reusing the same `oauth-callback.html` page, which
/// just reads `code` off the query string -- see that function's own doc for the full rationale,
/// including the "non-root-mounted frontend" gap this shares).
pub fn x_twitter_redirect_uri(conn: &mut PgPooledConnection) -> Result<String, Status> {
    let frontend_host = crate::rpcs::get_server_configuration_proto(conn)?
        .external_cdn_config
        .map(|c| c.frontend_host)
        .filter(|h| !h.trim().is_empty())
        .ok_or_else(|| {
            Status::new(Code::FailedPrecondition, "x_twitter_redirect_uri_not_configured")
        })?;
    Ok(format!("https://{frontend_host}/oauth-callback.html"))
}

struct TokenResponse {
    access_token: String,
    refresh_token: String,
    /// Seconds from now until expiry, straight off the API response (`expires_in`) -- converted to
    /// an absolute Unix timestamp by the caller, which is what's actually persisted.
    expires_in: i64,
}

fn basic_auth_header(client_id: &str, client_secret: &str) -> String {
    let encoded =
        base64::engine::general_purpose::STANDARD.encode(format!("{client_id}:{client_secret}"));
    format!("Basic {encoded}")
}

fn parse_token_response(body: &serde_json::Value) -> Result<TokenResponse, Status> {
    let access_token = body
        .get("access_token")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("X token response missing access_token: {:?}", body);
            Status::new(Code::FailedPrecondition, "x_twitter_token_exchange_failed")
        })?;
    let refresh_token = body
        .get("refresh_token")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "X token response missing refresh_token -- was the `offline.access` scope requested?: {:?}",
                body
            );
            Status::new(Code::FailedPrecondition, "x_twitter_token_exchange_failed")
        })?;
    let expires_in = body
        .get("expires_in")
        .and_then(|v| v.as_i64())
        .unwrap_or(7200);
    Ok(TokenResponse {
        access_token,
        refresh_token,
        expires_in,
    })
}

/// Exchanges the OAuth authorization `code` from the X login popup (together with the PKCE
/// `code_verifier` the popup generated -- see the module doc on `plain` PKCE) for an access/refresh
/// token pair. `client_id`/`client_secret` are this Rellm server's own X Developer App
/// credentials. `redirect_uri` must be byte-for-byte identical to the one the popup sent X's own
/// authorize endpoint.
pub fn exchange_x_twitter_code_for_token(
    client_id: &str,
    client_secret: &str,
    code: &str,
    code_verifier: &str,
    redirect_uri: &str,
) -> Result<(String, String, i64), Status> {
    exchange_x_twitter_code_for_token_at(
        DEFAULT_API_BASE_URL,
        client_id,
        client_secret,
        code,
        code_verifier,
        redirect_uri,
    )
}

/// Same as `exchange_x_twitter_code_for_token`, but against an arbitrary `base_url` -- lets specs point this
/// at a local mock server instead of the real X API (see `factories::serve_x_twitter_api`).
pub fn exchange_x_twitter_code_for_token_at(
    base_url: &str,
    client_id: &str,
    client_secret: &str,
    code: &str,
    code_verifier: &str,
    redirect_uri: &str,
) -> Result<(String, String, i64), Status> {
    let url = format!("{base_url}/2/oauth2/token");
    let auth_header = basic_auth_header(client_id, client_secret);
    let (status, body) = blocking_json_request(
        move |client| {
            client
                .post(&url)
                .header("Authorization", auth_header)
                .form(&[
                    ("grant_type", "authorization_code"),
                    ("code", code),
                    ("client_id", client_id),
                    ("redirect_uri", redirect_uri),
                    ("code_verifier", code_verifier),
                ])
        },
        "x_twitter_request_failed",
    )?;
    if !status.is_success() {
        log::error!("X code exchange failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "x_twitter_code_exchange_failed",
        ));
    }
    let token = parse_token_response(&body)?;
    Ok((token.access_token, token.refresh_token, token.expires_in))
}

/// Exchanges a `refresh_token` for a fresh access/refresh token pair -- X rotates the refresh token
/// on every use (the old one is invalidated), so both must be persisted, not just the new access
/// token. `client_id`/`client_secret` are this Rellm server's own X Developer App credentials.
pub fn refresh_access_token(
    client_id: &str,
    client_secret: &str,
    refresh_token: &str,
) -> Result<(String, String, i64), Status> {
    refresh_access_token_at(DEFAULT_API_BASE_URL, client_id, client_secret, refresh_token)
}

/// Same as `refresh_access_token`, but against an arbitrary `base_url` -- see
/// `exchange_x_twitter_code_for_token_at`.
pub fn refresh_access_token_at(
    base_url: &str,
    client_id: &str,
    client_secret: &str,
    refresh_token: &str,
) -> Result<(String, String, i64), Status> {
    let url = format!("{base_url}/2/oauth2/token");
    let auth_header = basic_auth_header(client_id, client_secret);
    let (status, body) = blocking_json_request(
        move |client| {
            client
                .post(&url)
                .header("Authorization", auth_header)
                .form(&[
                    ("grant_type", "refresh_token"),
                    ("refresh_token", refresh_token),
                    ("client_id", client_id),
                ])
        },
        "x_twitter_request_failed",
    )?;
    if !status.is_success() {
        log::error!("X token refresh failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "x_twitter_token_refresh_failed",
        ));
    }
    let token = parse_token_response(&body)?;
    Ok((token.access_token, token.refresh_token, token.expires_in))
}

/// Looks up the connected account's own numeric user ID and `@username` off a fresh access token --
/// used once on connect (`CreateSyncDestination`) to populate `XTwitterAccount.x_user_id`/`username`.
pub fn get_me(access_token: &str) -> Result<(String, String), Status> {
    get_me_at(DEFAULT_API_BASE_URL, access_token)
}

/// Same as `get_me`, but against an arbitrary `base_url` -- see `exchange_x_twitter_code_for_token_at`.
pub fn get_me_at(base_url: &str, access_token: &str) -> Result<(String, String), Status> {
    let url = format!("{base_url}/2/users/me");
    let (status, body) = blocking_json_request(
        move |client| client.get(&url).bearer_auth(access_token),
        "x_twitter_request_failed",
    )?;
    if !status.is_success() {
        log::error!("X users/me lookup failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "x_twitter_username_lookup_failed",
        ));
    }
    let data = body.get("data").ok_or_else(|| {
        log::error!("X users/me response missing data: {:?}", body);
        Status::new(Code::FailedPrecondition, "x_twitter_username_lookup_failed")
    })?;
    let x_user_id = data
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("X users/me response missing id: {:?}", body);
            Status::new(Code::FailedPrecondition, "x_twitter_username_lookup_failed")
        })?;
    let username = data
        .get("username")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("X users/me response missing username: {:?}", body);
            Status::new(Code::FailedPrecondition, "x_twitter_username_lookup_failed")
        })?;
    Ok((x_user_id, username))
}

/// Posts an already-built `SyncMessage` (text truncated to X's 280-character limit, plus up to
/// `MAX_MEDIA_ATTACHMENTS` attached images -- see the module doc on video) to `destination`'s
/// connected X account. Refreshes the stored access token first if it's expired or close to it,
/// persisting the refreshed pair back to `destination`'s row via `conn`. Returns the new Tweet's ID
/// and its permalink (`https://x.com/{username}/status/{id}` -- X's API doesn't return one
/// directly, but this form is stable/documented, so it's built rather than looked up).
pub fn post_tweet(
    destination: &models::SyncDestination,
    message: &SyncMessage,
    conn: &mut PgPooledConnection,
) -> Result<(String, String), Status> {
    let (client_id, client_secret) = server_x_twitter_app_credentials(conn)?;
    post_tweet_at(DEFAULT_API_BASE_URL, &client_id, &client_secret, destination, message, conn)
}

/// Same as `post_tweet`, but against an arbitrary `base_url` -- see `exchange_x_twitter_code_for_token_at`.
/// `client_id`/`client_secret` are threaded in explicitly (rather than reloaded from `conn` inside
/// here) so specs can point them at test credentials without a real `server_x_twitter_app_credentials`
/// row.
pub fn post_tweet_at(
    base_url: &str,
    client_id: &str,
    client_secret: &str,
    destination: &models::SyncDestination,
    message: &SyncMessage,
    conn: &mut PgPooledConnection,
) -> Result<(String, String), Status> {
    let not_configured =
        || Status::new(Code::FailedPrecondition, "sync_destination_not_configured");
    let x_twitter_account = destination
        .configuration
        .get("x_twitter_account")
        .ok_or_else(not_configured)?;
    let x_user_id = x_twitter_account
        .get("x_user_id")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?
        .to_string();
    let username = x_twitter_account
        .get("username")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?
        .to_string();
    let stored_access_token = x_twitter_account
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?
        .to_string();
    let refresh_token = x_twitter_account
        .get("refresh_token")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?
        .to_string();
    let expires_at = x_twitter_account
        .get("expires_at")
        .and_then(|v| v.as_i64())
        .ok_or_else(not_configured)?;

    let now = chrono::Utc::now().timestamp();
    let access_token = if expires_at <= now + REFRESH_SKEW_SECONDS {
        let (new_access_token, new_refresh_token, expires_in) =
            refresh_access_token_at(base_url, client_id, client_secret, &refresh_token)?;
        let new_expires_at = now + expires_in;
        let new_configuration = serde_json::json!({
            "x_twitter_account": {
                "x_user_id": x_user_id,
                "username": username,
                "access_token": new_access_token,
                "refresh_token": new_refresh_token,
                "expires_at": new_expires_at,
            }
        });
        diesel::update(sync_destinations::table.filter(sync_destinations::id.eq(destination.id)))
            .set(sync_destinations::configuration.eq(&new_configuration))
            .execute(conn)
            .map_err(|e| {
                log::error!("Failed to persist refreshed X token: {:?}", e);
                Status::new(Code::Internal, "failed_to_update_sync_destination")
            })?;
        new_access_token
    } else {
        stored_access_token
    };

    let attempted = message.media.iter().filter(|m| m.is_image()).count().min(MAX_MEDIA_ATTACHMENTS);
    let mut media_ids = Vec::with_capacity(attempted);
    for media in message.media.iter().filter(|m| m.is_image()).take(MAX_MEDIA_ATTACHMENTS) {
        match upload_media_at(base_url, &access_token, media) {
            Ok(id) => media_ids.push(id),
            Err(e) => log::error!(
                "Failed to upload media {:?} to X, skipping: {:?}",
                media.url,
                e
            ),
        }
    }
    if attempted > 0 && media_ids.is_empty() {
        return Err(Status::new(
            Code::FailedPrecondition,
            "x_twitter_media_upload_failed",
        ));
    }

    let url = format!("{base_url}/2/tweets");
    let text = truncate_for_x_twitter(&message.text);
    let access_token_for_post = access_token.clone();
    let (status, body) = blocking_json_request(
        move |client| {
            let mut payload = serde_json::json!({ "text": text });
            if !media_ids.is_empty() {
                payload["media"] = serde_json::json!({ "media_ids": media_ids });
            }
            client
                .post(&url)
                .bearer_auth(&access_token_for_post)
                .json(&payload)
        },
        "x_twitter_request_failed",
    )?;
    if !status.is_success() {
        log::error!("X tweet creation failed ({}): {:?}", status, body);
        return Err(Status::new(Code::FailedPrecondition, "x_twitter_post_failed"));
    }
    let tweet_id = body
        .get("data")
        .and_then(|d| d.get("id"))
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("X tweet creation response missing data.id: {:?}", body);
            Status::new(Code::Internal, "x_twitter_post_failed")
        })?;
    let permalink = format!("https://x.com/{username}/status/{tweet_id}");
    Ok((tweet_id, permalink))
}

/// Fetches `media.url`'s raw bytes from this Rellm server's own public media endpoint, then
/// re-uploads them to `base_url`'s `/2/media/upload` as `multipart/form-data` with
/// `media_category=tweet_image`. Returns the new media attachment's ID (to pass as
/// `media.media_ids[]` on the subsequent `/2/tweets` call). Mirrors
/// `mastodon_sync::upload_media_at`'s fetch-then-reupload shape almost exactly, since X's media
/// endpoint (like Mastodon's, unlike Facebook/Instagram/Threads') takes raw bytes, not a remote URL.
fn upload_media_at(base_url: &str, access_token: &str, media: &MediaAttachment) -> Result<String, Status> {
    let media_url = media.url.clone();
    let content_type = media.content_type.clone();
    let bytes = run_blocking(move || -> Result<Vec<u8>, Status> {
        let response = reqwest::blocking::Client::new()
            .get(&media_url)
            .send()
            .map_err(|e| {
                log::error!("Failed to fetch media {:?} for X upload: {:?}", media_url, e);
                Status::new(Code::FailedPrecondition, "x_twitter_media_fetch_failed")
            })?;
        if !response.status().is_success() {
            log::error!(
                "Fetching media {:?} for X upload failed ({})",
                media_url,
                response.status()
            );
            return Err(Status::new(
                Code::FailedPrecondition,
                "x_twitter_media_fetch_failed",
            ));
        }
        response.bytes().map(|b| b.to_vec()).map_err(|e| {
            log::error!("Failed to read media {:?} bytes: {:?}", media_url, e);
            Status::new(Code::FailedPrecondition, "x_twitter_media_fetch_failed")
        })
    })?;

    let url = format!("{base_url}/2/media/upload");
    let access_token = access_token.to_string();
    let (status, body) = run_blocking(move || -> Result<(reqwest::StatusCode, serde_json::Value), Status> {
        let part = reqwest::blocking::multipart::Part::bytes(bytes)
            .file_name("media")
            .mime_str(&content_type)
            .map_err(|e| {
                log::error!("Invalid media content type {:?}: {:?}", content_type, e);
                Status::new(Code::FailedPrecondition, "x_twitter_request_failed")
            })?;
        let form = reqwest::blocking::multipart::Form::new()
            .text("media_category", "tweet_image")
            .part("media", part);
        let response = reqwest::blocking::Client::new()
            .post(&url)
            .bearer_auth(&access_token)
            .multipart(form)
            .send()
            .map_err(|e| {
                log::error!("X media upload request failed: {:?}", e);
                Status::new(Code::FailedPrecondition, "x_twitter_request_failed")
            })?;
        let status = response.status();
        let text = response.text().map_err(|e| {
            log::error!("Failed to read X media upload response body: {:?}", e);
            Status::new(Code::FailedPrecondition, "x_twitter_request_failed")
        })?;
        let value: serde_json::Value = if text.trim().is_empty() {
            serde_json::Value::Null
        } else {
            serde_json::from_str(&text).map_err(|e| {
                log::error!("Failed to parse X media upload response as JSON: {:?} ({})", e, text);
                Status::new(Code::FailedPrecondition, "x_twitter_request_failed")
            })?
        };
        Ok((status, value))
    })?;
    if !status.is_success() {
        log::error!("X media upload failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "x_twitter_media_upload_failed",
        ));
    }
    body.get("data")
        .and_then(|d| d.get("id"))
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("X media upload response missing data.id: {:?}", body);
            Status::new(Code::Internal, "x_twitter_media_upload_failed")
        })
}
