use std::time::SystemTime;

use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::{stellarwp_page_url, sync_source_after_edit};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::sync_sources;

const MIN_SYNC_INTERVAL_SECONDS: i64 = 60;

pub fn update_sync_source(
    request: SyncSource,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<SyncSource, Status> {
    let source_id = request.id.to_db_id_or_err("id")?;
    let mut existing = models::get_sync_source(source_id, conn)?;

    // Gated per-configuration-type (`SyncEventsFromIcs`/`SyncPostsFromRss`/`SyncPostsFromAtom`,
    // or Admin) same as `create_sync_source` -- against the request's own `configuration` if
    // it's changing the source's type, else the existing source's, so e.g. just bumping
    // `sync_interval_seconds` on an RSS source is gated on `SyncPostsFromRss`, not
    // `SyncEventsFromIcs`.
    let effective_configuration = request
        .configuration
        .clone()
        .or_else(|| source_configuration_to_proto(&existing.configuration));
    validate_permission(
        &Some(current_user),
        required_sync_source_permission(&effective_configuration),
    )?;

    if existing.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    if request.sync_interval_seconds > 0 {
        if (request.sync_interval_seconds as i64) < MIN_SYNC_INTERVAL_SECONDS {
            return Err(Status::new(
                tonic::Code::InvalidArgument,
                "sync_interval_seconds_too_short",
            ));
        }
        existing.sync_interval_seconds = request.sync_interval_seconds as i64;
    }
    if request.configuration.is_some() {
        existing.configuration = source_configuration_to_json(&request.configuration);
        if let Some(endpoint) = existing
            .configuration
            .get("stellarwp_ics_subscription_url")
            .and_then(|v| v.as_str())
        {
            stellarwp_page_url(endpoint, 1)?;
        }
    }
    if request.user_agent.is_some() {
        existing.user_agent = user_agent_to_db(request.user_agent)?;
    }
    existing.updated_at = Some(SystemTime::now());

    let mut existing = diesel::update(sync_sources::table.filter(sync_sources::id.eq(existing.id)))
        .set(&existing)
        .get_result::<models::SyncSource>(conn)
        .map_err(|e| {
            log::error!("Failed to update sync source: {:?}", crate::logic::log_redaction::safe_error(&e));
            tonic::Status::new(tonic::Code::Internal, "failed_to_update_sync_source")
        })?;

    let owner = models::get_author(existing.user_id, conn)?;

    // Unlike create, a failed re-sync doesn't undo the config change -- the caller (and the UI's
    // "last synced at") can see the source still exists but didn't sync just now.
    sync_source_after_edit(&existing, conn)?;
    existing = models::get_sync_source(existing.id, conn)?;

    Ok(MarshalableSyncSource(existing, owner).to_proto())
}
