//! Posts to a `SyncDestination`'s linked Instagram Business/Creator account via the Graph API.
//!
//! Instagram posting piggybacks on the Facebook Page connection (`facebook_sync::connect_facebook_page`):
//! the Page's long-lived access token is used for the Instagram API calls too, so this module shares
//! `facebook_sync`'s Graph API plumbing rather than having its own login flow.

use tonic::{Code, Status};

use super::facebook_sync::{graph_get, graph_post, DEFAULT_GRAPH_API_BASE_URL, GRAPH_API_VERSION};
use crate::logic::SyncMessage;
use crate::models;

/// Looks up the Instagram Business/Creator account linked to `page_id` (via `page_access_token`,
/// the same long-lived Page token `connect_facebook_page` returns) -- required before posting to
/// Instagram, since posting piggybacks on the linked Page's token rather than a separate Instagram
/// login. Returns `(instagram_business_account_id, username)`.
pub fn get_linked_instagram_business_account(
    page_access_token: &str,
    page_id: &str,
) -> Result<(String, String), Status> {
    get_linked_instagram_business_account_at(DEFAULT_GRAPH_API_BASE_URL, page_access_token, page_id)
}

/// Same as `get_linked_instagram_business_account`, but against an arbitrary `base_url` -- see
/// `connect_facebook_page_at`.
pub fn get_linked_instagram_business_account_at(
    base_url: &str,
    page_access_token: &str,
    page_id: &str,
) -> Result<(String, String), Status> {
    let url = format!("{}/{}/{}", base_url, GRAPH_API_VERSION, page_id);
    let response = graph_get(
        &url,
        &[
            ("fields", "instagram_business_account{id,username}"),
            ("access_token", page_access_token),
        ],
    )?;
    let account = response
        .get("instagram_business_account")
        .ok_or_else(|| {
            Status::new(
                Code::FailedPrecondition,
                "instagram_no_linked_business_account",
            )
        })?;
    let id = account
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            Status::new(
                Code::FailedPrecondition,
                "instagram_no_linked_business_account",
            )
        })?;
    let username = account
        .get("username")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    Ok((id, username))
}

/// Posts an already-built `SyncMessage` to `destination`'s linked Instagram Business account.
/// Instagram's Graph API has **no text-only post type**, so this fails fast with
/// `instagram_requires_media` if `message.media` is empty rather than attempting the call. A
/// 2-step flow otherwise: create a media container (`/media`) from the first media URL + caption,
/// then publish it (`/media_publish`), then fetch the published media's real `permalink` (the
/// publish step only returns an opaque ID, not a link). Returns `(media_id, permalink)`.
pub fn post_to_instagram(
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    post_to_instagram_at(DEFAULT_GRAPH_API_BASE_URL, destination, message)
}

/// Same as `post_to_instagram`, but against an arbitrary `base_url` -- see
/// `connect_facebook_page_at`.
pub fn post_to_instagram_at(
    base_url: &str,
    destination: &models::SyncDestination,
    message: &SyncMessage,
) -> Result<(String, String), Status> {
    let Some(media) = message.media.first() else {
        return Err(Status::new(
            Code::FailedPrecondition,
            "instagram_requires_media",
        ));
    };

    let not_configured =
        || Status::new(Code::FailedPrecondition, "sync_destination_not_configured");
    let instagram_account = destination
        .configuration
        .get("instagram_account")
        .ok_or_else(not_configured)?;
    let ig_user_id = instagram_account
        .get("instagram_business_account_id")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;
    let access_token = instagram_account
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(not_configured)?;

    let create_url = format!("{}/{}/{}/media", base_url, GRAPH_API_VERSION, ig_user_id);
    let mut create_params: Vec<(&str, &str)> = vec![
        ("caption", message.text.as_str()),
        ("access_token", access_token),
    ];
    if media.is_video() {
        // Current Meta guidance routes single-video feed posts through the Reels container type
        // via the Graph API (there's no separate plain "feed video" media_type) -- if Meta's docs
        // have since introduced a dedicated non-Reels video post type, prefer that instead.
        create_params.push(("media_type", "REELS"));
        create_params.push(("video_url", media.url.as_str()));
    } else {
        // No `media_type` needed -- Instagram defaults to IMAGE.
        create_params.push(("image_url", media.url.as_str()));
    }
    let create_response = graph_post(&create_url, &create_params)?;
    let creation_id = create_response
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Instagram media creation response missing id: {:?}",
                create_response
            );
            Status::new(Code::Internal, "instagram_post_failed")
        })?;

    let publish_url = format!(
        "{}/{}/{}/media_publish",
        base_url, GRAPH_API_VERSION, ig_user_id
    );
    let publish_response = graph_post(
        &publish_url,
        &[
            ("creation_id", creation_id.as_str()),
            ("access_token", access_token),
        ],
    )?;
    let media_id = publish_response
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Instagram media_publish response missing id: {:?}",
                publish_response
            );
            Status::new(Code::Internal, "instagram_post_failed")
        })?;

    let permalink_url = format!("{}/{}/{}", base_url, GRAPH_API_VERSION, media_id);
    let permalink_response = graph_get(
        &permalink_url,
        &[("fields", "permalink"), ("access_token", access_token)],
    )?;
    let permalink = permalink_response
        .get("permalink")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| {
            log::error!(
                "Instagram media permalink lookup response missing permalink: {:?}",
                permalink_response
            );
            Status::new(Code::Internal, "instagram_post_failed")
        })?;

    Ok((media_id, permalink))
}
