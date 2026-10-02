//! `SyncDestination` -- a user-owned destination to sync (cross-post) content out to (today
//! always a connected Facebook Page). Originally Event-specific (`EventSyncDestination`), now
//! shared by both `Occasion`s (`occasion_sync_destinations`, still in
//! `event_models.rs`/`event_loaders.rs` since that join table stays Event-specific) and `Post`s
//! (`post_sync_destinations`, in `post_models.rs`).

use std::collections::HashMap;
use std::time::SystemTime;

use diesel::{dsl::count_star, *};
use tonic::{Code, Status};

use super::{Author, AUTHOR_COLUMNS};
use crate::db_connection::PgPooledConnection;
use crate::schema::{occasion_sync_destinations, post_sync_destinations, sync_destinations, users};

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
pub struct SyncDestination {
    pub id: i64,
    pub user_id: i64,
    pub configuration: serde_json::Value,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = sync_destinations)]
pub struct NewSyncDestination {
    pub user_id: i64,
    pub configuration: serde_json::Value,
}

pub fn get_sync_destination(id: i64, conn: &mut PgPooledConnection) -> Result<SyncDestination, Status> {
    sync_destinations::table
        .select(sync_destinations::all_columns)
        .filter(sync_destinations::id.eq(id))
        .first::<SyncDestination>(conn)
        .map_err(|_| Status::new(Code::NotFound, "sync_destination_not_found"))
}

pub fn get_sync_destinations_for_user(
    user_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<Vec<(SyncDestination, Author)>, Status> {
    sync_destinations::table
        .inner_join(users::table.on(sync_destinations::user_id.eq(users::id)))
        .select((sync_destinations::all_columns, AUTHOR_COLUMNS))
        .filter(sync_destinations::user_id.eq(user_id))
        .order(sync_destinations::created_at.desc())
        .load::<(SyncDestination, Author)>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load sync destinations for user_id={}: {:?}",
                user_id,
                e
            );
            Status::new(Code::Internal, "failed_to_load_sync_destinations")
        })
}

/// The number of Occasions synced to each of `destination_ids` so far, batched into one
/// `GROUP BY` query (mirrors `get_events.rs`'s `attach_occasion_rsvps`: fetch the
/// primary rows first, then attach a derived count/list in a second, batched query rather than
/// one query per row) -- see `marshaling::attach_synced_counts`, which mutates already-built
/// `SyncDestination` protos with this. A destination with zero synced occasions is simply absent
/// from the result map (no row to group), so callers should treat a missing key as `0`.
pub fn get_sync_destination_synced_counts(
    destination_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> HashMap<i64, i64> {
    if destination_ids.is_empty() {
        return HashMap::new();
    }
    occasion_sync_destinations::table
        .filter(occasion_sync_destinations::sync_destination_id.eq_any(destination_ids))
        .group_by(occasion_sync_destinations::sync_destination_id)
        .select((
            occasion_sync_destinations::sync_destination_id,
            count_star(),
        ))
        .load::<(i64, i64)>(conn)
        .unwrap_or_default()
        .into_iter()
        .collect()
}

/// Same as `get_sync_destination_synced_counts`, but the number of Posts synced to each
/// destination (`post_sync_destinations`) instead of Occasions.
pub fn get_post_sync_destination_synced_counts(
    destination_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> HashMap<i64, i64> {
    if destination_ids.is_empty() {
        return HashMap::new();
    }
    post_sync_destinations::table
        .filter(post_sync_destinations::sync_destination_id.eq_any(destination_ids))
        .group_by(post_sync_destinations::sync_destination_id)
        .select((post_sync_destinations::sync_destination_id, count_star()))
        .load::<(i64, i64)>(conn)
        .unwrap_or_default()
        .into_iter()
        .collect()
}
