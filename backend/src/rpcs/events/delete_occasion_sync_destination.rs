use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{validate_any_permission, validate_permission};
use crate::schema::occasion_sync_destinations;

pub fn delete_occasion_sync_destination(
    request: DeleteOccasionSyncDestinationRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    // Widened from a Facebook-only check to any `SYNC_EVENTS_TO_*` -- unsyncing is platform-agnostic
    // (it's just a join-row delete, no platform API call), so a Mastodon/Bluesky/Instagram/X-only
    // holder needs to be able to remove their own destinations' sync status too.
    validate_any_permission(
        &Some(current_user),
        vec![
            Permission::SyncEventsToFacebook,
            Permission::SyncEventsToInstagram,
            Permission::SyncEventsToMastodon,
            Permission::SyncEventsToBluesky,
            Permission::SyncEventsToXTwitter,
            Permission::Admin,
        ],
    )?;

    let occasion_id = request
        .occasion_id
        .to_db_id_or_err("occasion_id")?;
    let destination_id = request
        .sync_destination_id
        .to_db_id_or_err("sync_destination_id")?;

    let destination = models::get_sync_destination(destination_id, conn)?;
    if destination.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    diesel::delete(
        occasion_sync_destinations::table.filter(
            occasion_sync_destinations::occasion_id
                .eq(occasion_id)
                .and(occasion_sync_destinations::sync_destination_id.eq(destination.id)),
        ),
    )
    .execute(conn)
    .map_err(|e| {
        log::error!(
            "Failed to delete event occasion sync destination ({}, {}): {:?}",
            occasion_id,
            destination.id,
            crate::logic::log_redaction::safe_error(&e)
        );
        Status::new(
            tonic::Code::Internal,
            "failed_to_delete_occasion_sync_destination",
        )
    })?;

    Ok(())
}
