use diesel::NotFound;
use diesel::*;
use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs;
use crate::schema::{events, media, posts, users};

use crate::rpcs::validations::*;

pub async fn delete_user(
    request: User,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> Result<(), Status> {
    validate_user(&request)?;

    let target_user_id = request.id.to_db_id_or_err("id")?;
    let self_delete = request.id == current_user.id.to_proto_id();
    let admin = match validate_permission(&Some(current_user), Permission::Admin) {
        Ok(_) => true,
        Err(e) => {
            if !self_delete {
                return Err(e);
            } else {
                false
            }
        }
    };
    log::info!("self_delete: {}, admin: {}", self_delete, admin);

    // Events -- via DeleteEvent, which also refreshes the (about-to-be-deleted) owner's counts.
    let event_ids = events::table
        .inner_join(posts::table.on(events::post_id.eq(posts::id)))
        .filter(posts::user_id.eq(Some(target_user_id)))
        .select(events::post_id)
        .load::<i64>(conn)
        .map_err(|e| {
            log::error!("Error loading events for user {}: {:?}", target_user_id, e);
            Status::new(Code::Internal, "data_error")
        })?;
    for event_id in event_ids {
        rpcs::delete_event(
            Event {
                post: Some(Post {
                    id: event_id.to_proto_id(),
                    ..Default::default()
                }),
                ..Default::default()
            },
            current_user,
            conn,
        )?;
    }

    // Posts/Replies -- via DeletePost. Event/Occasion-context posts are handled above by
    // DeleteEvent instead.
    let post_ids = posts::table
        .filter(posts::user_id.eq(Some(target_user_id)))
        .filter(posts::context.eq_any(vec![
            PostContext::Post.to_string_post_context(),
            PostContext::Reply.to_string_post_context(),
        ]))
        .select(posts::id)
        .load::<i64>(conn)
        .map_err(|e| {
            log::error!("Error loading posts for user {}: {:?}", target_user_id, e);
            Status::new(Code::Internal, "data_error")
        })?;
    for post_id in post_ids {
        rpcs::delete_post(
            Post {
                id: post_id.to_proto_id(),
                ..Default::default()
            },
            current_user,
            conn,
        )?;
    }

    // Media -- via DeleteMedia, which also cleans up the underlying object storage object(s).
    let media_ids = media::table
        .filter(media::user_id.eq(Some(target_user_id)))
        .select(media::id)
        .load::<i64>(conn)
        .map_err(|e| {
            log::error!("Error loading media for user {}: {:?}", target_user_id, e);
            Status::new(Code::Internal, "data_error")
        })?;
    for media_id in media_ids {
        rpcs::delete_media(
            Media {
                id: media_id.to_proto_id(),
                ..Default::default()
            },
            current_user,
            conn,
            bucket,
        )
        .await?;
    }

    // SyncSources/SyncDestinations -- any events/occasions/posts they'd synced were already
    // covered above, so these are just detached rather than cascading further deletes.
    // `delete_sync_destination` cleans up join rows in both `occasion_sync_destinations` and
    // `post_sync_destinations` for the destination, so a synced Post/Occasion of *this*
    // user's, still pointing at *another* user's destination, is also cleaned up correctly here
    // without any extra Post-specific logic.
    let sync_sources = models::get_sync_sources_for_user(target_user_id, conn)?;
    for (source, _owner) in sync_sources {
        rpcs::delete_sync_source(
            DeleteSyncSourceRequest {
                source: Some(SyncSource {
                    id: source.id.to_proto_id(),
                    ..Default::default()
                }),
                delete_synced_events: false,
            },
            current_user,
            conn,
        )?;
    }

    let sync_destinations = models::get_sync_destinations_for_user(target_user_id, conn)?;
    for (destination, _owner) in sync_destinations {
        rpcs::delete_sync_destination(
            DeleteSyncDestinationRequest {
                destination: Some(SyncDestination {
                    id: destination.id.to_proto_id(),
                    ..Default::default()
                }),
                delete_synced_posts: false,
            },
            current_user,
            conn,
        )?;
    }

    let db_result = delete(users::table.find(target_user_id)).execute(conn);

    let result = match db_result {
        Ok(size) if size == 0 => Err(Status::new(Code::NotFound, "user_not_found")),
        Ok(_) => Ok(()),
        Err(NotFound) => Err(Status::new(Code::NotFound, "user_not_found")),
        Err(e) => {
            log::error!("Error deleting user: {:?}", e);
            Err(Status::new(Code::Internal, "data_error"))
        }
    };
    log::info!("DeleteUser::request: {:?}, result: {:?}", request, result);

    result
}
