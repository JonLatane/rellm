use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{stellarwp_page_url, sync_source_after_edit};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::sync_sources;

const DEFAULT_SYNC_INTERVAL_SECONDS: i64 = 3600;
const MIN_SYNC_INTERVAL_SECONDS: i64 = 60;

pub fn create_sync_source(
    request: SyncSource,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<SyncSource, Status> {
    // Create is always for the current user -- admins may manage other users' sources (see
    // `update_sync_source`/`delete_sync_source`) but never create one on their
    // behalf. Gated per-configuration-type (`SyncEventsFromIcs`/`SyncPostsFromRss`/
    // `SyncPostsFromAtom`, whichever matches `request.configuration`, or Admin) -- see
    // `required_sync_source_permission`.
    validate_permission(
        &Some(current_user),
        required_sync_source_permission(&request.configuration),
    )?;

    let configuration = source_configuration_to_json(&request.configuration);
    let has_subscription_url = [
        "ics_subscription_url",
        "stellarwp_ics_subscription_url",
        "rss_subscription_url",
        "atom_subscription_url",
    ]
    .iter()
        .any(|key| {
            configuration
                .get(key)
                .and_then(|v| v.as_str())
                .map(|s| !s.trim().is_empty())
                .unwrap_or(false)
        });
    if !has_subscription_url {
        return Err(Status::new(
            Code::InvalidArgument,
            "subscription_url_required",
        ));
    }
    if let Some(endpoint) = configuration
        .get("stellarwp_ics_subscription_url")
        .and_then(|v| v.as_str())
    {
        stellarwp_page_url(endpoint, 1)?;
    }

    let user_agent = user_agent_to_db(request.user_agent)?;

    let sync_interval_seconds = if request.sync_interval_seconds == 0 {
        DEFAULT_SYNC_INTERVAL_SECONDS
    } else if (request.sync_interval_seconds as i64) < MIN_SYNC_INTERVAL_SECONDS {
        return Err(Status::new(
            Code::InvalidArgument,
            "sync_interval_seconds_too_short",
        ));
    } else {
        request.sync_interval_seconds as i64
    };

    let inserted = insert_into(sync_sources::table)
        .values(&models::NewSyncSource {
            user_id: current_user.id,
            sync_interval_seconds,
            configuration,
            user_agent,
        })
        .get_result::<models::SyncSource>(conn)
        .map_err(|e| {
            log::error!("Failed to create sync source: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_create_sync_source")
        })?;

    // Not transactional with the insert above (per product decision) -- if the very first sync
    // (just the first page, for a paginated StellarWP source -- see `sync_source_after_edit`)
    // fails, delete the source we just created rather than leaving a never-synced, broken row
    // around, and surface the sync error to the caller.
    if let Err(sync_err) = sync_source_after_edit(&inserted, conn) {
        log::error!(
            "Initial sync failed for new SyncSource {}, deleting it: {:?}",
            inserted.id,
            sync_err
        );
        if let Err(e) =
            diesel::delete(sync_sources::table.filter(sync_sources::id.eq(inserted.id)))
                .execute(conn)
        {
            log::error!(
                "Failed to delete SyncSource {} after failed initial sync: {:?}",
                inserted.id,
                crate::logic::log_redaction::safe_error(&e)
            );
        }
        return Err(sync_err);
    }

    let synced = models::get_sync_source(inserted.id, conn)?;
    Ok(MarshalableSyncSource(synced, current_user.to_author()).to_proto())
}
