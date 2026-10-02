extern crate diesel;
extern crate rellm;

use std::collections::HashMap;

use diesel::result::{DatabaseErrorKind, Error as DieselError};
use diesel::*;
use rellm::models::{Event, Occasion, OCCASION_COLUMNS};
use rellm::schema::*;
use rellm::{db_connection, init_bin_logging, init_crypto};

/// TODO(2026-09-04): temporary, one-off repair tool. Once this has been run against every
/// deployed namespace that has ever had a `SyncSource` (ato-band at least -- check
/// bullcitysocial/oakcitysocial/jonline.io too), delete this file and its `COPY`/rename entries
/// in `deploys/docker/server/Dockerfile` and `.github/workflows/server_ci_cd.yml`.
///
/// Repairs fallout from the `EventSyncSource` -> `SyncSource` rename (2026-09-04): the rename
/// mechanically renamed the JSON key `events.info.event_sync_source_uid` to `sync_source_uid` in
/// the *code* (`logic::sync_sources::event_sync`'s uid lookup), but pre-existing `events.info` rows already had
/// the old key persisted as data. That made `sync_source_text`'s `existing_by_uid` map silently
/// drop every pre-existing synced Event when built (`.get("sync_source_uid")` returned `None` for
/// all of them, so `filter_map` excluded them entirely), so the very next sync treated every
/// still-current iCal UID as brand new and created a full duplicate Event/Occasion/Post
/// chain for it, alongside the untouched original -- the *duplicate* uses the new key, so it's
/// matched correctly on every subsequent sync; only the original is (silently, harmlessly)
/// invisible to sync from then on, without this repair.
///
/// This does two things, in order, inside one transaction per duplicate group (a failure on one
/// group doesn't affect the others):
///
/// 1. Renames the persisted `event_sync_source_uid` key to `sync_source_uid` in every affected
///    `events.info`, so future syncs match existing rows correctly again.
/// 2. Finds duplicate Events (same UID, multiple `events` rows) created by that bug and collapses
///    each group down to its oldest ("keeper") Event -- matching up each duplicate's
///    Occasion(s) to the keeper's by `sync_source_recurrence_anchor` and, for every relation a real
///    user (not the iCal sync itself, which never touches Media and only ever updates occasion
///    times/text) could have created against the *newer* duplicate in the meantime -- Media,
///    replies, RSVPs (`rsvps`), cross-posts (`group_posts`/`user_posts`), and sync-out
///    records (`*_sync_destinations`) -- reassigns it onto the keeper before deleting the
///    duplicate. `posts.media` arrays are unioned rather than overwritten. A duplicate's occasion
///    with no matching keeper occasion (shouldn't happen in practice, but not impossible if the
///    feed changed between the two syncs) is adopted by the keeper Event rather than deleted.
pub fn main() {
    init_crypto();
    init_bin_logging();

    log::info!("Connecting to DB...");
    let mut conn = db_connection::establish_connection();

    log::info!("Step 1: repairing events.info's persisted `event_sync_source_uid` key...");
    let renamed = diesel::sql_query(
        "UPDATE events \
         SET info = (info - 'event_sync_source_uid') \
                     || jsonb_build_object('sync_source_uid', info -> 'event_sync_source_uid') \
         WHERE info ? 'event_sync_source_uid'",
    )
    .execute(&mut conn)
    .expect("Failed to repair events.info keys");
    log::info!("Repaired {} Event(s)' persisted UID key.", renamed);

    log::info!("Step 2: finding and collapsing duplicate synced Events...");
    // `sync_source_id` moved from `events` to `posts` (2026-09-11-000000_move_sync_source_to_posts,
    // after this tool was written) -- join through the Event's own Post to find it.
    let synced_events: Vec<Event> = events::table
        .inner_join(posts::table.on(posts::id.eq(events::post_id)))
        .filter(posts::sync_source_id.is_not_null())
        .select(events::all_columns)
        .load(&mut conn)
        .expect("Failed to load synced Events");

    let mut by_uid: HashMap<String, Vec<Event>> = HashMap::new();
    for event in synced_events {
        if let Some(uid) = event.info.get("sync_source_uid").and_then(|v| v.as_str()) {
            by_uid.entry(uid.to_string()).or_default().push(event);
        }
    }

    let mut stats = Stats::default();

    for (uid, mut group) in by_uid {
        if group.len() < 2 {
            continue;
        }
        group.sort_by_key(|e| (e.created_at, e.post_id));
        let keeper = group.remove(0);
        log::info!(
            "UID {}: {} duplicate(s) of keeper Event {} found.",
            uid,
            group.len(),
            keeper.post_id
        );

        let duplicate_count = group.len();
        let result = conn.transaction::<(), DieselError, _>(|conn| {
            for duplicate in &group {
                collapse_duplicate_event(conn, keeper.post_id, duplicate.post_id, &mut stats)?;
            }
            Ok(())
        });

        match result {
            Ok(()) => {
                stats.groups_collapsed += 1;
                stats.events_deleted += duplicate_count;
            }
            Err(e) => {
                log::error!(
                    "UID {}: failed to collapse duplicates: {:?}. Skipping this group.",
                    uid,
                    e
                );
            }
        }
    }

    log::info!(
        "Done. {} UID group(s) had duplicates; deleted {} duplicate Event(s) and {} duplicate \
         Occasion(s); merged {} Media reference(s); reassigned {} other relation(s) \
         (deleting {} that would've collided with the keeper's own).",
        stats.groups_collapsed,
        stats.events_deleted,
        stats.occasions_deleted,
        stats.media_merged,
        stats.relations_reassigned,
        stats.relations_dropped_as_duplicate,
    );
}

#[derive(Default)]
struct Stats {
    groups_collapsed: usize,
    events_deleted: usize,
    occasions_deleted: usize,
    media_merged: usize,
    relations_reassigned: usize,
    relations_dropped_as_duplicate: usize,
}

fn collapse_duplicate_event(
    conn: &mut PgConnection,
    keeper_event_id: i64,
    duplicate_event_id: i64,
    stats: &mut Stats,
) -> Result<(), DieselError> {
    // `sync_source_recurrence_anchor` moved from `occasions` to `posts`
    // (2026-09-11-000000_move_sync_source_to_posts, after this tool was written) -- join through
    // each occasion's own Post to find it.
    let keeper_occasions: Vec<(Occasion, Option<std::time::SystemTime>)> = occasions::table
        .inner_join(posts::table.on(posts::id.eq(occasions::post_id)))
        .select((OCCASION_COLUMNS, posts::sync_source_recurrence_anchor))
        .filter(occasions::event_id.eq(keeper_event_id))
        .load(conn)?;
    let mut keeper_by_anchor: HashMap<std::time::SystemTime, i64> = keeper_occasions
        .into_iter()
        .filter_map(|(i, anchor)| anchor.map(|anchor| (anchor, i.post_id)))
        .collect();

    let duplicate_occasions: Vec<(Occasion, Option<std::time::SystemTime>)> = occasions::table
        .inner_join(posts::table.on(posts::id.eq(occasions::post_id)))
        .select((OCCASION_COLUMNS, posts::sync_source_recurrence_anchor))
        .filter(occasions::event_id.eq(duplicate_event_id))
        .load(conn)?;

    for (duplicate_occasion, anchor) in duplicate_occasions {
        let Some(anchor) = anchor else {
            continue;
        };
        match keeper_by_anchor.get(&anchor) {
            Some(&keeper_occasion_post_id) => {
                reassign_occasion_relations(
                    conn,
                    keeper_occasion_post_id,
                    duplicate_occasion.post_id,
                    stats,
                )?;
                merge_and_delete_post(
                    conn,
                    keeper_occasion_post_id,
                    duplicate_occasion.post_id,
                    stats,
                )?;
                stats.occasions_deleted += 1;
            }
            None => {
                // No matching keeper occasion -- adopt this occurrence into the keeper Event
                // rather than lose it.
                log::warn!(
                    "Duplicate Event {}'s occasion {} (sync_source_recurrence_anchor {:?}) has no \
                     matching keeper occasion under Event {}; adopting it instead of deleting.",
                    duplicate_event_id,
                    duplicate_occasion.post_id,
                    anchor,
                    keeper_event_id,
                );
                diesel::update(
                    occasions::table.filter(occasions::post_id.eq(duplicate_occasion.post_id)),
                )
                .set(occasions::event_id.eq(keeper_event_id))
                .execute(conn)?;
                keeper_by_anchor.insert(anchor, duplicate_occasion.post_id);
            }
        }
    }

    reassign_post_relations(conn, keeper_event_id, duplicate_event_id, stats)?;
    merge_and_delete_post(conn, keeper_event_id, duplicate_event_id, stats)?;

    Ok(())
}

/// Relations keyed by `occasion_id` (the occasion's own `post_id`) -- only applicable when
/// merging two Occasions, not the top-level Event posts.
fn reassign_occasion_relations(
    conn: &mut PgConnection,
    keeper_post_id: i64,
    duplicate_post_id: i64,
    stats: &mut Stats,
) -> Result<(), DieselError> {
    let rsvps_moved = diesel::update(
        rsvps::table.filter(rsvps::occasion_id.eq(duplicate_post_id)),
    )
    .set(rsvps::occasion_id.eq(keeper_post_id))
    .execute(conn)?;
    stats.relations_reassigned += rsvps_moved;

    reassign_or_drop_composite(
        conn,
        duplicate_post_id,
        keeper_post_id,
        stats,
        |conn, from, to| {
            diesel::update(
                occasion_sync_destinations::table
                    .filter(occasion_sync_destinations::occasion_id.eq(from)),
            )
            .set(occasion_sync_destinations::occasion_id.eq(to))
            .execute(conn)
        },
        |conn, from| {
            diesel::delete(
                occasion_sync_destinations::table
                    .filter(occasion_sync_destinations::occasion_id.eq(from)),
            )
            .execute(conn)
        },
    )?;

    Ok(())
}

/// Relations keyed by plain `post_id` -- applicable to both Occasion and top-level Event
/// posts.
fn reassign_post_relations(
    conn: &mut PgConnection,
    keeper_post_id: i64,
    duplicate_post_id: i64,
    stats: &mut Stats,
) -> Result<(), DieselError> {
    let replies_moved = diesel::update(posts::table.filter(posts::parent_post_id.eq(duplicate_post_id)))
        .set(posts::parent_post_id.eq(keeper_post_id))
        .execute(conn)?;
    stats.relations_reassigned += replies_moved;

    reassign_or_drop_composite(
        conn,
        duplicate_post_id,
        keeper_post_id,
        stats,
        |conn, from, to| {
            diesel::update(group_posts::table.filter(group_posts::post_id.eq(from)))
                .set(group_posts::post_id.eq(to))
                .execute(conn)
        },
        |conn, from| {
            diesel::delete(group_posts::table.filter(group_posts::post_id.eq(from))).execute(conn)
        },
    )?;

    reassign_or_drop_composite(
        conn,
        duplicate_post_id,
        keeper_post_id,
        stats,
        |conn, from, to| {
            diesel::update(user_posts::table.filter(user_posts::post_id.eq(from)))
                .set(user_posts::post_id.eq(to))
                .execute(conn)
        },
        |conn, from| diesel::delete(user_posts::table.filter(user_posts::post_id.eq(from))).execute(conn),
    )?;

    reassign_or_drop_composite(
        conn,
        duplicate_post_id,
        keeper_post_id,
        stats,
        |conn, from, to| {
            diesel::update(post_sync_destinations::table.filter(post_sync_destinations::post_id.eq(from)))
                .set(post_sync_destinations::post_id.eq(to))
                .execute(conn)
        },
        |conn, from| {
            diesel::delete(post_sync_destinations::table.filter(post_sync_destinations::post_id.eq(from)))
                .execute(conn)
        },
    )?;

    Ok(())
}

/// Tries to reassign a duplicate's row(s) in a table whose primary key also includes the
/// keeper's own id (e.g. `(group_id, post_id)`) -- if the keeper already has its own row for the
/// same other-half-of-the-key (a real collision, not just this bug), the reassignment would
/// violate that table's uniqueness constraint; in that case the duplicate's row is simply dropped
/// (the keeper's own, presumably-real one already covers it) rather than failing the whole
/// collapse.
fn reassign_or_drop_composite(
    conn: &mut PgConnection,
    duplicate_post_id: i64,
    keeper_post_id: i64,
    stats: &mut Stats,
    reassign: impl Fn(&mut PgConnection, i64, i64) -> QueryResult<usize>,
    drop_duplicate: impl Fn(&mut PgConnection, i64) -> QueryResult<usize>,
) -> Result<(), DieselError> {
    match reassign(conn, duplicate_post_id, keeper_post_id) {
        Ok(count) => stats.relations_reassigned += count,
        Err(DieselError::DatabaseError(DatabaseErrorKind::UniqueViolation, _)) => {
            let dropped = drop_duplicate(conn, duplicate_post_id)?;
            stats.relations_dropped_as_duplicate += dropped;
        }
        Err(e) => return Err(e),
    }
    Ok(())
}

/// Unions `duplicate_post_id`'s `media` into `keeper_post_id`'s, then deletes the duplicate Post
/// (cascading its `events`/`occasions` row, whichever applies). Must run *after* every
/// other relation pointing at `duplicate_post_id` has already been reassigned/dropped above --
/// `group_posts`/`user_posts`/`occasions`.`post_id` cascade on Post delete, but
/// `post_sync_destinations`/`occasion_sync_destinations`.`occasion_id` restrict it.
fn merge_and_delete_post(
    conn: &mut PgConnection,
    keeper_post_id: i64,
    duplicate_post_id: i64,
    stats: &mut Stats,
) -> Result<(), DieselError> {
    let duplicate_media: Vec<Option<i64>> = posts::table
        .select(posts::media)
        .filter(posts::id.eq(duplicate_post_id))
        .first(conn)?;
    if !duplicate_media.is_empty() {
        let keeper_media: Vec<Option<i64>> = posts::table
            .select(posts::media)
            .filter(posts::id.eq(keeper_post_id))
            .first(conn)?;
        let mut merged = keeper_media.clone();
        let mut newly_added = 0;
        for media_id in duplicate_media {
            if !merged.contains(&media_id) {
                merged.push(media_id);
                newly_added += 1;
            }
        }
        if newly_added > 0 {
            diesel::update(posts::table.filter(posts::id.eq(keeper_post_id)))
                .set(posts::media.eq(merged))
                .execute(conn)?;
            stats.media_merged += newly_added;
        }
    }

    diesel::delete(posts::table.filter(posts::id.eq(duplicate_post_id))).execute(conn)?;
    Ok(())
}
