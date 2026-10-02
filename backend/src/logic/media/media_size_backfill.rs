//! One-time backfill of `Media.sizes[].size_bytes` for rows created before per-size byte counts
//! were tracked at all (see migration `2026-09-13-000100_restructure_media_sizes`, which populates
//! pre-existing rows' `sizes` with a `0` placeholder for each entry, since no prior code path ever
//! recorded a real byte count anywhere). Spawned as a background task from `main.rs` on every
//! server startup -- naturally idempotent, since [`media_pending_size_backfill`] only ever selects
//! rows still holding a `0` placeholder (via `idx_media_sizes_gin`), so a restart after it
//! completes finds nothing left to do (a fast indexed lookup, not a sequential scan).

use diesel::dsl::sql;
use diesel::sql_types::Bool;
use diesel::*;
use s3::Bucket;

use crate::db_connection::PgPooledConnection;
use crate::logic::update_media_storage_used;
use crate::models::Media;
use crate::schema::media;

/// Runs one batch per invocation, since no `Media` byte count is stored anywhere else, this
/// processes in small batches so a large backlog doesn't hold up the pool/bucket connections
/// indefinitely on a fresh startup.
const BATCH_SIZE: i64 = 50;

/// `Media` rows with at least one `sizes` entry still holding the migration's `0` byte-count
/// placeholder.
fn media_pending_size_backfill(conn: &mut PgPooledConnection, limit: i64) -> QueryResult<Vec<Media>> {
    media::table
        .filter(sql::<Bool>(r#"sizes @> '[{"size_bytes": 0}]'::jsonb"#))
        .order(media::id.asc())
        .limit(limit)
        .load::<Media>(conn)
}

/// Backfills one `Media` row: stats every `sizes` entry still at the `0` placeholder via object storage
/// `HEAD`, writes the real byte counts back, and refreshes the owner's
/// `User.media_storage_bytes_used`. Best-effort per entry -- an object storage object that's somehow gone
/// (e.g. already garbage-collected) is left at `0` rather than failing the whole row, so one bad
/// entry can't block every other row's backfill.
async fn backfill_media(item: &Media, bucket: &Bucket, conn: &mut PgPooledConnection) -> QueryResult<()> {
    let mut sizes = item.sizes();
    let mut changed = false;
    for size in sizes.iter_mut() {
        if size.size_bytes != 0 {
            continue;
        }
        match bucket.head_object(&size.object_storage_path).await {
            Ok((head, _)) => {
                size.size_bytes = head.content_length.unwrap_or(0);
                changed = true;
            }
            Err(e) => {
                log::warn!(
                    "media_size_backfill: failed to stat object storage object {} for Media {}: {:?}",
                    size.object_storage_path,
                    item.id,
                    e
                );
            }
        }
    }

    if changed {
        diesel::update(media::table.find(item.id))
            .set(media::sizes.eq(serde_json::to_value(&sizes).unwrap()))
            .execute(conn)?;
        if let Some(user_id) = item.user_id {
            update_media_storage_used(user_id, conn)?;
        }
    }
    Ok(())
}

/// Runs the full backfill to completion (looping [`BATCH_SIZE`]-sized batches until none remain),
/// logging progress. Intended to be `tokio::spawn`ed once from `main.rs` at server startup --
/// never awaited there, so it can't delay the server from actually starting to serve requests.
pub async fn run_media_size_backfill(pool: crate::db_connection::PgPool, bucket: std::sync::Arc<Bucket>) {
    log::info!("media_size_backfill: starting...");
    let mut total = 0;
    loop {
        let mut conn = match pool.get() {
            Ok(conn) => conn,
            Err(e) => {
                log::error!("media_size_backfill: failed to get DB connection: {:?}", e);
                return;
            }
        };
        let pending = match media_pending_size_backfill(&mut conn, BATCH_SIZE) {
            Ok(pending) => pending,
            Err(e) => {
                log::error!("media_size_backfill: failed to load pending Media: {:?}", e);
                return;
            }
        };
        if pending.is_empty() {
            break;
        }
        for item in &pending {
            if let Err(e) = backfill_media(item, &bucket, &mut conn).await {
                log::error!("media_size_backfill: failed to backfill Media {}: {:?}", item.id, e);
            }
        }
        total += pending.len();
        log::info!("media_size_backfill: backfilled {} Media so far...", total);
    }
    log::info!("media_size_backfill: done ({} Media backfilled).", total);
}
