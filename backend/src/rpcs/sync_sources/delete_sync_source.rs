use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::{posts, sync_sources};

pub fn delete_sync_source(
    request: DeleteSyncSourceRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let requested_source = request
        .source
        .ok_or(Status::new(Code::InvalidArgument, "source_required"))?;
    let source_id = requested_source.id.to_db_id_or_err("source.id")?;
    let existing = models::get_sync_source(source_id, conn)?;

    if existing.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    // Every kind of synced Post -- an Event's own Post, an Occasion's own Post, or (once
    // RSS/Atom SyncSources exist) a plain synced Post -- carries `sync_source_id` directly now
    // (see migration 2026-09-11-000000_move_sync_source_to_posts), so this single
    // delete/detach on `posts` handles all of them uniformly instead of needing a separate pass
    // per content type.
    if request.delete_synced_events {
        diesel::delete(posts::table.filter(posts::sync_source_id.eq(existing.id)))
            .execute(conn)
            .map_err(|e| {
                log::error!(
                    "Failed to delete posts synced from source {}: {:?}",
                    existing.id,
                    crate::logic::log_redaction::safe_error(&e)
                );
                Status::new(Code::Internal, "failed_to_delete_synced_events")
            })?;
    } else {
        diesel::update(posts::table.filter(posts::sync_source_id.eq(existing.id)))
            .set((
                posts::sync_source_id.eq(None::<i64>),
                posts::sync_source_uid.eq(None::<String>),
                posts::sync_source_recurrence_anchor.eq(None::<std::time::SystemTime>),
            ))
            .execute(conn)
            .map_err(|e| {
                log::error!(
                    "Failed to detach posts synced from source {}: {:?}",
                    existing.id,
                    crate::logic::log_redaction::safe_error(&e)
                );
                Status::new(Code::Internal, "failed_to_detach_synced_events")
            })?;
    }

    diesel::delete(sync_sources::table.filter(sync_sources::id.eq(existing.id)))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to delete sync source {}: {:?}", existing.id, crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_delete_sync_source")
        })?;

    Ok(())
}
