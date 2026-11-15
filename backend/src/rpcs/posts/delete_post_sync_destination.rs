use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{validate_any_permission, validate_permission};
use crate::schema::post_sync_destinations;

pub fn delete_post_sync_destination(
    request: DeletePostSyncDestinationRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    // Widened from a Facebook-only check to any `SYNC_POSTS_TO_*` -- see
    // `delete_occasion_sync_destination`'s identical comment.
    validate_any_permission(
        &Some(current_user),
        vec![
            Permission::SyncPostsToFacebook,
            Permission::SyncPostsToInstagram,
            Permission::SyncPostsToMastodon,
            Permission::SyncPostsToBluesky,
            Permission::SyncPostsToXTwitter,
            Permission::Admin,
        ],
    )?;

    let post_id = request.post_id.to_db_id_or_err("post_id")?;
    let destination_id = request
        .sync_destination_id
        .to_db_id_or_err("sync_destination_id")?;

    let destination = models::get_sync_destination(destination_id, conn)?;
    if destination.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    diesel::delete(
        post_sync_destinations::table.filter(
            post_sync_destinations::post_id
                .eq(post_id)
                .and(post_sync_destinations::sync_destination_id.eq(destination.id)),
        ),
    )
    .execute(conn)
    .map_err(|e| {
        log::error!(
            "Failed to delete post sync destination ({}, {}): {:?}",
            post_id,
            destination.id,
            crate::logic::log_redaction::safe_error(&e)
        );
        Status::new(
            tonic::Code::Internal,
            "failed_to_delete_post_sync_destination",
        )
    })?;

    Ok(())
}
