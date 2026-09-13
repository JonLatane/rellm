use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    build_post_message, post_post, post_record, post_status, post_thread, post_to_instagram,
    post_tweet, MediaAttachment, PostMessageInput,
};
use crate::marshaling::*;
use crate::models;
use crate::models::POST_COLUMNS;
use crate::protos::*;
use crate::rpcs::{get_server_configuration_proto, validate_permission};
use crate::schema::{post_sync_destinations, posts};

pub fn sync_post(
    request: SyncPostRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Post, Status> {
    let post_id = request.post_id.to_db_id_or_err("post_id")?;
    let destination_id = request
        .sync_destination_id
        .to_db_id_or_err("sync_destination_id")?;

    let post: models::Post = posts::table
        .select(POST_COLUMNS)
        .filter(posts::id.eq(post_id))
        .first(conn)
        .map_err(|_| Status::new(Code::NotFound, "post_not_found"))?;

    let destination = models::get_sync_destination(destination_id, conn)?;
    if destination.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    // Gated per the destination's actual platform (`SYNC_POSTS_TO_*`) rather than the single
    // `SyncPostsToFacebook` this used to hardcode -- see `sync_destination::Configuration`.
    let configuration = destination_configuration_to_proto(&destination.configuration);
    match &configuration {
        Some(sync_destination::Configuration::FacebookPage(_)) => {
            validate_permission(&Some(current_user), Permission::SyncPostsToFacebook)?
        }
        Some(sync_destination::Configuration::InstagramAccount(_)) => {
            validate_permission(&Some(current_user), Permission::SyncPostsToInstagram)?
        }
        Some(sync_destination::Configuration::MastodonAccount(_)) => {
            validate_permission(&Some(current_user), Permission::SyncPostsToMastodon)?
        }
        Some(sync_destination::Configuration::BlueskyAccount(_)) => {
            validate_permission(&Some(current_user), Permission::SyncPostsToBluesky)?
        }
        Some(sync_destination::Configuration::XTwitterAccount(_)) => {
            validate_permission(&Some(current_user), Permission::SyncPostsToXTwitter)?
        }
        Some(sync_destination::Configuration::ThreadsAccount(_)) => {
            validate_permission(&Some(current_user), Permission::SyncPostsToThreads)?
        }
        None => {
            return Err(Status::new(
                Code::FailedPrecondition,
                "sync_destination_not_configured",
            ))
        }
    };

    // Only buildable when this server has `external_cdn_config.frontend_host`/`backend_host`
    // configured -- this RPC has no HTTP `Host` header to fall back on the way web-facing routes
    // (`configured_frontend_domain`) do, so both are simply omitted otherwise. See
    // `docs/facebook_and_x_twitter_federation.md`.
    let external_cdn_config = get_server_configuration_proto(conn)?.external_cdn_config;
    let post_url = external_cdn_config
        .as_ref()
        .map(|c| c.frontend_host.clone())
        .filter(|h| !h.trim().is_empty())
        .map(|host| format!("https://{host}/post/{}", post.id.to_proto_id()));
    let media_ids: Vec<i64> = post.media.iter().filter_map(|m| *m).collect();
    let media_lookup = load_media_lookup(media_ids.clone(), conn);
    let media: Vec<MediaAttachment> = external_cdn_config
        .as_ref()
        .map(|c| c.backend_host.clone())
        .filter(|h| !h.trim().is_empty())
        .map(|host| {
            media_ids
                .iter()
                .map(|id| MediaAttachment {
                    url: format!("https://{host}/media/{}", id.to_proto_id()),
                    content_type: media_lookup
                        .as_ref()
                        .find_media(*id)
                        .and_then(|m| m.original())
                        .map(|s| s.content_type)
                        .unwrap_or_default(),
                })
                .collect()
        })
        .unwrap_or_default();

    let message = build_post_message(PostMessageInput {
        title: &post.title,
        content: &post.content,
        link: &post.link,
        post_url: &post_url,
        media,
    });

    let (destination_instance_id, destination_url) = match &configuration {
        Some(sync_destination::Configuration::FacebookPage(_)) => post_post(&destination, &message)?,
        Some(sync_destination::Configuration::InstagramAccount(_)) => {
            post_to_instagram(&destination, &message)?
        }
        Some(sync_destination::Configuration::MastodonAccount(_)) => {
            post_status(&destination, &message)?
        }
        Some(sync_destination::Configuration::BlueskyAccount(_)) => {
            post_record(&destination, &message)?
        }
        Some(sync_destination::Configuration::XTwitterAccount(_)) => {
            post_tweet(&destination, &message, conn)?
        }
        Some(sync_destination::Configuration::ThreadsAccount(_)) => {
            post_thread(&destination, &message)?
        }
        None => {
            return Err(Status::new(
                Code::FailedPrecondition,
                "sync_destination_not_configured",
            ))
        }
    };

    let new_row = models::NewPostSyncDestination {
        post_id: post.id,
        sync_destination_id: destination.id,
        destination_instance_id: Some(destination_instance_id),
        destination_url: Some(destination_url),
        synced_at: Some(SystemTime::now()),
    };
    insert_into(post_sync_destinations::table)
        .values(&new_row)
        .on_conflict((
            post_sync_destinations::post_id,
            post_sync_destinations::sync_destination_id,
        ))
        .do_update()
        .set(&new_row)
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to record post sync status: {:?}", e);
            Status::new(Code::Internal, "failed_to_record_post_sync")
        })?;

    let posts = crate::rpcs::get_posts(
        GetPostsRequest {
            post_id: Some(post.id.to_proto_id()),
            ..Default::default()
        },
        &Some(current_user),
        conn,
    )?
    .posts;
    posts
        .into_iter()
        .find(|p| p.id == post.id.to_proto_id())
        .ok_or_else(|| Status::new(Code::Internal, "failed_to_reload_synced_post"))
}
