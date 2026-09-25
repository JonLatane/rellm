//! Server-wide Media storage accounting -- backs `MediaSettings.server_media_usage_bytes` (a
//! `media`-table-derived running total, kept fresh by cheap incremental
//! `adjust_server_media_usage_bytes` calls at every Media mutation call site plus a full
//! self-healing recompute every 3 minutes -- see `bin/calculate_server_media_usage.rs`) and
//! `server_object_storage_usage_bytes` (an independent drift check computed by listing and
//! summing object storage itself every 4h -- see `bin/calculate_server_object_storage_usage.rs`).
//!
//! Both fields live inside `ServerConfiguration.media_settings`'s JSONB blob, but are mutated *in
//! place* on the active `server_configurations` row (via `SELECT ... FOR UPDATE`) rather than
//! through `ConfigureServer`'s usual versioned insert -- the same non-versioned-mutation pattern
//! `ClusterConductorState.locks` uses via `LockClusterResources`/`FreeClusterResources`, and for
//! the same reason: a background job ticking every few minutes (or a Media upload/delete) would
//! otherwise spam a new `ServerConfiguration` version on every single run.

use std::time::SystemTime;

use diesel::sql_types::{BigInt, Nullable};
use diesel::*;
use s3::Bucket;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::{normalized_media_settings, ToProtoTime};
use crate::protos::MediaSettings;
use crate::schema::server_configurations::dsl as scd;

#[derive(QueryableByName)]
struct SumRow {
    #[diesel(sql_type = Nullable<BigInt>)]
    sum: Option<i64>,
}

/// The sum of `size_bytes` across every stored copy (original plus any converted sizes) of every
/// `Media` item on the server, across every owner -- what `MediaSettings.server_media_usage_bytes`
/// reports. Raw SQL (same shape as `user_counts::media_storage_bytes_used`, just without the
/// `WHERE user_id = $1`) so Postgres does the aggregation rather than shipping every `Media` row's
/// `sizes` over the wire.
///
/// Note this query is *not* index-accelerated -- `idx_media_sizes_gin` is a containment (`@>`)
/// index, useful for `WHERE sizes @> ...`-style lookups, not for aggregating over every row. A
/// full sequential scan of `media` (unavoidable for a whole-table `SUM`) is what this always does,
/// same as it would with no index on the table at all. That's fine for a job that only runs every
/// 3 minutes; it's exactly why mutation call sites use the cheap incremental
/// `adjust_server_media_usage_bytes` below instead of calling this on every upload/delete.
pub fn total_media_bytes(conn: &mut PgPooledConnection) -> QueryResult<i64> {
    let row: SumRow = sql_query(
        "SELECT SUM((entry->>'size_bytes')::bigint)::bigint AS sum \
         FROM media, jsonb_array_elements(media.sizes) AS entry",
    )
    .get_result(conn)?;
    Ok(row.sum.unwrap_or(0))
}

/// Loads the active `ServerConfiguration` row's `media_settings` with a `SELECT ... FOR UPDATE`
/// (so concurrent callers serialize rather than racing a lost update), applies `f` to it, and
/// writes the result back to that same row -- *not* a new `ConfigureServer` version. Used by every
/// function in this module; see this module's own doc for why.
fn update_media_settings<F>(conn: &mut PgPooledConnection, f: F) -> QueryResult<()>
where
    F: FnOnce(&mut MediaSettings),
{
    conn.transaction::<(), diesel::result::Error, _>(|conn| {
        let config = scd::server_configurations
            .filter(scd::active.eq(true))
            .for_update()
            .first::<crate::models::ServerConfiguration>(conn)?;
        // Normalized the same way `to_proto()` reads it (see `normalized_media_settings`'s own
        // doc) -- critical here specifically: writing back a raw, un-normalized deserialize whose
        // `default_user_media_allocation_bytes` is still `0` (e.g. a column that's never been
        // touched by `ConfigureServer`) would make `to_proto()`'s own staleness check discard this
        // very write on the next read, silently losing whatever `f` just set.
        let mut settings: MediaSettings = normalized_media_settings(config.media_settings);
        f(&mut settings);
        update(scd::server_configurations.filter(scd::id.eq(config.id)))
            .set(scd::media_settings.eq(serde_json::to_value(&settings).unwrap()))
            .execute(conn)?;
        Ok(())
    })
}

/// Fully recomputes `server_media_usage_bytes` from the `media` table (see [`total_media_bytes`])
/// and stamps `server_media_usage_calculated_at` -- used by `bin/calculate_server_media_usage.rs`
/// every 3 minutes to self-heal any drift the incremental [`adjust_server_media_usage_bytes`] call
/// sites missed (e.g. a cascading delete that doesn't go through them).
pub fn recompute_server_media_usage_bytes(conn: &mut PgPooledConnection) -> QueryResult<()> {
    let total = total_media_bytes(conn)?;
    update_media_settings(conn, |settings| {
        settings.server_media_usage_bytes = total.max(0) as u64;
        settings.server_media_usage_calculated_at = Some(SystemTime::now().to_proto());
    })
}

/// Cheaply adjusts `server_media_usage_bytes` by `delta_bytes` (positive for a create/enlarging
/// conversion, negative for a delete/shrinking one) instead of re-summing the whole `media` table
/// on every single mutation -- see this module's own doc. Clamped to never go negative (drift
/// should only ever make this an *under*-count in practice, but a negative floor keeps a display
/// bug from showing a nonsensical negative usage). Called at every Media mutation call site; see
/// [`recompute_server_media_usage_bytes`] for the periodic drift-correcting counterpart. A `0`
/// delta is a no-op -- skips taking the row lock entirely.
pub fn adjust_server_media_usage_bytes(
    conn: &mut PgPooledConnection,
    delta_bytes: i64,
) -> QueryResult<()> {
    if delta_bytes == 0 {
        return Ok(());
    }
    update_media_settings(conn, |settings| {
        let adjusted = settings.server_media_usage_bytes as i64 + delta_bytes;
        settings.server_media_usage_bytes = adjusted.max(0) as u64;
        settings.server_media_usage_calculated_at = Some(SystemTime::now().to_proto());
    })
}

/// Lists and sums every object in `bucket` (recursively -- empty prefix, no delimiter) and writes
/// the total to `server_object_storage_usage_bytes`/`server_object_storage_usage_calculated_at` --
/// used by `bin/calculate_server_object_storage_usage.rs` every 4h as a drift check against
/// `server_media_usage_bytes` above (which is derived from the `media` table, not object storage
/// itself, so the two can diverge -- e.g. an object storage object orphaned by a bug elsewhere).
/// `Bucket::list` already pages through the whole bucket internally, so this is a single logical
/// listing regardless of object count.
pub async fn recompute_server_object_storage_usage_bytes(
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> anyhow::Result<()> {
    let pages = bucket.list(String::new(), None).await?;
    let total: u64 = pages.iter().flat_map(|page| &page.contents).map(|object| object.size).sum();
    update_media_settings(conn, |settings| {
        settings.server_object_storage_usage_bytes = total;
        settings.server_object_storage_usage_calculated_at = Some(SystemTime::now().to_proto());
    })?;
    Ok(())
}
