use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::{occasion_sync_destinations, post_sync_destinations, sync_destinations};

pub fn delete_sync_destination(
    request: DeleteSyncDestinationRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let requested_destination = request
        .destination
        .ok_or(Status::new(Code::InvalidArgument, "destination_required"))?;
    let destination_id = requested_destination.id.to_db_id_or_err("destination.id")?;
    let existing = models::get_sync_destination(destination_id, conn)?;

    if existing.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    // `delete_synced_posts` is intentionally a no-op today: deleting the already-posted Facebook
    // content would require the Page's access token to remain valid at delete time and isn't
    // implemented yet. Disconnecting always stops future syncing; it just leaves existing posts
    // up on Facebook.
    let _ = request.delete_synced_posts;

    diesel::delete(
        occasion_sync_destinations::table
            .filter(occasion_sync_destinations::sync_destination_id.eq(existing.id)),
    )
    .execute(conn)
    .map_err(|e| {
        log::error!(
            "Failed to delete Occasion sync statuses for destination {}: {:?}",
            existing.id,
            crate::logic::log_redaction::safe_error(&e)
        );
        Status::new(Code::Internal, "failed_to_delete_sync_destination")
    })?;

    diesel::delete(
        post_sync_destinations::table
            .filter(post_sync_destinations::sync_destination_id.eq(existing.id)),
    )
    .execute(conn)
    .map_err(|e| {
        log::error!(
            "Failed to delete Post sync statuses for destination {}: {:?}",
            existing.id,
            crate::logic::log_redaction::safe_error(&e)
        );
        Status::new(Code::Internal, "failed_to_delete_sync_destination")
    })?;

    diesel::delete(sync_destinations::table.filter(sync_destinations::id.eq(existing.id)))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to delete sync destination {}: {:?}", existing.id, crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_delete_sync_destination")
        })?;

    Ok(())
}
