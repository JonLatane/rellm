//! Connects a `SyncDestination` to a Threads account (Meta's text-first app) via a
//! `response_type=code` OAuth flow at `threads.net` and posts `Occasion`s/`Post`s to it via
//! the Threads Graph API (`graph.threads.net`).
//!
//! Threads is architecturally the odd one out among this server's platforms:
//! - It authorizes at `threads.net` (not `facebook.com`) and uses an authorization **code**
//!   exchanged server-side for a token, rather than Facebook's client-side implicit token flow --
//!   hence `exchange_code_for_token` below, which Facebook/Instagram don't need.
//! - Unlike Facebook/Instagram, there's no "choose a Page" step -- Threads OAuth directly
//!   authorizes the user's own single Threads account.
//! - Unlike Instagram, Threads posting supports **text-only** posts -- `post_thread` doesn't
//!   early-return when `message.media` is empty the way `instagram_sync::post_to_instagram` does.
//!
//! Threads API is a product/"use case" added to this server's *existing* Meta App (see
//! `FacebookAuthConfig`/`server_facebook_app_credentials`), not a separately-registered app, so
//! there's no separate credentials-loading function here.
//!
//! **Known limitation, flagged rather than silently under-built**: the long-lived access token
//! `exchange_long_lived_token` returns expires in ~60 days and is refreshable
//! (`grant_type=th_refresh_token`), unlike Facebook's Page tokens (effectively non-expiring) or
//! Bluesky's app passwords (never expire). No refresh job is built this round -- a connected
//! Threads destination will silently stop working ~60 days after connecting until the user
//! reconnects it. A background job mirroring `sync_sources` could refresh tokens before
//! expiry as a future follow-up.

use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::http_client::blocking_json_request;
use crate::logic::SyncMessage;
use crate::models;

const DEFAULT_BASE_URL: &str = "https://graph.threads.net";
const API_VERSION: &str = "v1.0";

/// Derives the Threads OAuth popup's `redirect_uri` -- the frontend's popup sends this exact
/// string to Threads' authorize endpoint (reusing the same `oauth-callback.html` page
/// Facebook/Instagram's OAuth popup already redirects to, at `window.location.origin +
/// rellmBasePath + "/oauth-callback.html"`), and this server's own token-exchange call
/// (`exchange_code_for_token`) has to send back the identical string -- OAuth requires an exact
/// match between the authorize and token-exchange calls' `redirect_uri`.
///
/// There's no per-RPC HTTP `Host` header available here to derive the origin from at request time
/// (`CreateSyncDestination`/`UpdateSyncDestination` are plain gRPC calls, not web-facing routes),
/// so this mirrors how `sync_post`/`sync_occasion` already build `post_url`/`event_url`:
/// from this server's own configured `external_cdn_config.frontend_host`, assuming the frontend is
/// served at that domain's root (`rellmBasePath == ""`) -- the exact same assumption
/// `post_url`/`event_url` already make, so this isn't a new limitation. **Judgment call worth
/// flagging**: a server whose frontend is mounted at a non-root path (e.g. `/elm`) would need a
/// different `redirect_uri` than this derives, and `ThreadsAccount` has no field for the client to
/// supply one explicitly instead (per the proto's current shape) -- a real gap for that
/// deployment shape, not something silently worked around here.
pub fn threads_redirect_uri(conn: &mut PgPooledConnection) -> Result<String, Status> {
    let frontend_host = crate::rpcs::get_server_configuration_proto(conn)?
        .external_cdn_config
        .map(|c| c.frontend_host)
        .filter(|h| !h.trim().is_empty())
        .ok_or_else(|| {
            Status::new(Code::FailedPrecondition, "threads_redirect_uri_not_configured")
        })?;
    Ok(format!("https://{frontend_host}/oauth-callback.html"))
}

/// Exchanges the OAuth authorization `code` from the Threads login popup for a short-lived access
/// token, returning `(short_lived_access_token, threads_user_id)`. `app_id`/`app_secret` are this
/// Rellm server's own Facebook App credentials (see `server_facebook_app_credentials` -- Threads
/// rides on the same Meta App). `redirect_uri` must be byte-for-byte identical to the one the
/// popup sent Threads' own authorize endpoint (OAuth requires an exact match between the authorize
/// and token-exchange calls).
pub fn exchange_code_for_token(
    app_id: &str,
    app_secret: &str,
    code: &str,
    redirect_uri: &str,
) -> Result<(String, String), Status> {
    exchange_code_for_token_at(DEFAULT_BASE_URL, app_id, app_secret, code, redirect_uri)
}

/// Same as `exchange_code_for_token`, but against an arbitrary `base_url` -- lets specs point this
/// at a local mock server instead of the real Threads API (see `factories::serve_threads_api`).
pub fn exchange_code_for_token_at(
    base_url: &str,
    app_id: &str,
    app_secret: &str,
    code: &str,
    redirect_uri: &str,
) -> Result<(String, String), Status> {
    let url = format!("{base_url}/oauth/access_token");
    let (status, body) = blocking_json_request(
        move |client| {
            client.post(&url).form(&[
                ("client_id", app_id),
                ("client_secret", app_secret),
                ("grant_type", "authorization_code"),
                ("redirect_uri", redirect_uri),
                ("code", code),
            ])
        },
        "threads_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Threads code exchange failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "threads_code_exchange_failed",
        ));
    }
    let access_token = body
        .get("access_token")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Threads code exchange response missing access_token: {:?}",
                body
            );
            Status::new(Code::FailedPrecondition, "threads_code_exchange_failed")
        })?;
    let threads_user_id = body
        .get("user_id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Threads code exchange response missing user_id: {:?}",
                body
            );
            Status::new(Code::FailedPrecondition, "threads_code_exchange_failed")
        })?;
    Ok((access_token, threads_user_id))
}

/// Exchanges a short-lived Threads access token for a long-lived one (~60 day expiry -- see the
/// module doc). `app_secret` is this Rellm server's own Facebook App Secret.
pub fn exchange_long_lived_token(app_secret: &str, short_lived_token: &str) -> Result<String, Status> {
    exchange_long_lived_token_at(DEFAULT_BASE_URL, app_secret, short_lived_token)
}

/// Same as `exchange_long_lived_token`, but against an arbitrary `base_url` -- see
/// `exchange_code_for_token_at`.
pub fn exchange_long_lived_token_at(
    base_url: &str,
    app_secret: &str,
    short_lived_token: &str,
) -> Result<String, Status> {
    let url = format!("{base_url}/access_token");
    let (status, body) = blocking_json_request(
        move |client| {
            client.get(&url).query(&[
                ("grant_type", "th_exchange_token"),
                ("client_secret", app_secret),
                ("access_token", short_lived_token),
            ])
        },
        "threads_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Threads long-lived token exchange failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "threads_token_exchange_failed",
        ));
    }
    body.get("access_token")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Threads long-lived token exchange response missing access_token: {:?}",
                body
            );
            Status::new(Code::FailedPrecondition, "threads_token_exchange_failed")
        })
}

/// Looks up `threads_user_id`'s `@username`, populated into `ThreadsAccount.username` when a
/// connection is made.
pub fn get_username(access_token: &str, threads_user_id: &str) -> Result<String, Status> {
    get_username_at(DEFAULT_BASE_URL, access_token, threads_user_id)
}

/// Same as `get_username`, but against an arbitrary `base_url` -- see `exchange_code_for_token_at`.
pub fn get_username_at(
    base_url: &str,
    access_token: &str,
    threads_user_id: &str,
) -> Result<String, Status> {
    let url = format!("{base_url}/{API_VERSION}/{threads_user_id}");
    let (status, body) = blocking_json_request(
        move |client| {
            client
                .get(&url)
                .query(&[("fields", "username"), ("access_token", access_token)])
        },
        "threads_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Threads username lookup failed ({}): {:?}", status, body);
        return Err(Status::new(
            Code::FailedPrecondition,
            "threads_username_lookup_failed",
        ));
    }
    body.get("username")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!("Threads username lookup response missing username: {:?}", body);
            Status::new(Code::FailedPrecondition, "threads_username_lookup_failed")
        })
}

/// Posts an already-built `SyncMessage` to `destination`'s connected Threads account. Unlike
/// Instagram, **text-only is valid** -- doesn't early-return on empty `message.media`. A 3-step
/// flow: create a media container (`media_type=TEXT`/`IMAGE`/`VIDEO` depending on `message.media`),
/// publish it, then fetch the published post's real `permalink` (the publish step only returns an
/// opaque ID) -- mirrors `instagram_sync::post_to_instagram`'s shape. Returns `(post_id, permalink)`.
pub fn post_thread(
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    post_thread_at(DEFAULT_BASE_URL, destination, message)
}

/// Same as `post_thread`, but against an arbitrary `base_url` -- see `exchange_code_for_token_at`.
pub fn post_thread_at(
    base_url: &str,
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    let not_configured =
        || Status::new(Code::FailedPrecondition, "sync_destination_not_configured");
    let threads_account = destination
        .configuration
        .get("threads_account")
        .ok_or_else(not_configured)?;
    let threads_user_id = threads_account
        .get("threads_user_id")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;
    let access_token = threads_account
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;

    let create_url = format!("{base_url}/{API_VERSION}/{threads_user_id}/threads");
    let mut create_params: Vec<(&str, &str)> = vec![
        ("text", message.text.as_str()),
        ("access_token", access_token),
    ];
    match message.media.first() {
        Some(media) if media.is_video() => {
            create_params.push(("media_type", "VIDEO"));
            create_params.push(("video_url", media.url.as_str()));
        }
        Some(media) => {
            // Default to IMAGE for anything that isn't explicitly video (mirrors
            // `instagram_sync::post_to_instagram`'s image-by-default handling).
            create_params.push(("media_type", "IMAGE"));
            create_params.push(("image_url", media.url.as_str()));
        }
        None => create_params.push(("media_type", "TEXT")),
    }
    let create_response = threads_post(&create_url, &create_params)?;
    let creation_id = create_response
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Threads media creation response missing id: {:?}",
                create_response
            );
            Status::new(Code::Internal, "threads_post_failed")
        })?;

    let publish_url = format!("{base_url}/{API_VERSION}/{threads_user_id}/threads_publish");
    let publish_response = threads_post(
        &publish_url,
        &[
            ("creation_id", creation_id.as_str()),
            ("access_token", access_token),
        ],
    )?;
    let post_id = publish_response
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Threads threads_publish response missing id: {:?}",
                publish_response
            );
            Status::new(Code::Internal, "threads_post_failed")
        })?;

    let permalink_url = format!("{base_url}/{API_VERSION}/{post_id}");
    let permalink_response = threads_get(
        &permalink_url,
        &[("fields", "permalink"), ("access_token", access_token)],
    )?;
    let permalink = permalink_response
        .get("permalink")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Threads permalink lookup response missing permalink: {:?}",
                permalink_response
            );
            Status::new(Code::Internal, "threads_post_failed")
        })?;

    Ok((post_id, permalink))
}

fn threads_post(url: &str, params: &[(&str, &str)]) -> Result<serde_json::Value, Status> {
    let (status, body) = blocking_json_request(
        move |client| client.post(url).form(params),
        "threads_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Threads post request failed ({}): {:?}", status, body);
        return Err(Status::new(Code::FailedPrecondition, "threads_post_failed"));
    }
    Ok(body)
}

fn threads_get(url: &str, params: &[(&str, &str)]) -> Result<serde_json::Value, Status> {
    let (status, body) = blocking_json_request(
        move |client| client.get(url).query(params),
        "threads_request_failed",
    )?;
    if !status.is_success() {
        log::error!("Threads get request failed ({}): {:?}", status, body);
        return Err(Status::new(Code::FailedPrecondition, "threads_post_failed"));
    }
    Ok(body)
}
