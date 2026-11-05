//! Specs for `logic::sync_source[_text]` -- the actual ICS-pull/upsert logic behind
//! `CreateSyncSource`/`UpdateSyncSource`. Most specs drive `sync_source_text`
//! directly against a fixed ICS string (no network at all); a couple exercise
//! `sync_source` itself against `factories::serve_ics`'s local stub server to confirm
//! the HTTP fetch path also works end to end.

use chrono::{Duration, Utc};
use diesel::Connection;

use crate::logic::{sync_source, sync_source_text};
use crate::models;
use crate::schema::{occasions, events, posts};
use crate::tests::factories::*;
use diesel::prelude::*;

const ICS_FORMAT: &str = "%Y%m%dT%H%M%SZ";

fn occasions_for(
    conn: &mut crate::db_connection::PgPooledConnection,
    event_id: i64,
) -> Vec<models::Occasion> {
    occasions::table
        .select(models::OCCASION_COLUMNS)
        .filter(occasions::event_id.eq(event_id))
        .load::<models::Occasion>(conn)
        .unwrap()
}

fn synced_event(
    conn: &mut crate::db_connection::PgPooledConnection,
    source_id: i64,
    uid: &str,
) -> Option<models::Event> {
    let event_id: Option<i64> = occasions::table
        .inner_join(posts::table.on(posts::id.eq(occasions::post_id)))
        .select(occasions::event_id)
        .filter(posts::sync_source_id.eq(source_id))
        .filter(posts::sync_source_uid.eq(uid))
        .first(conn)
        .optional()
        .unwrap();
    event_id.map(|id| {
        events::table
            .filter(events::post_id.eq(id))
            .first::<models::Event>(conn)
            .unwrap()
    })
}

fn post_of(conn: &mut crate::db_connection::PgPooledConnection, post_id: i64) -> models::Post {
    posts::table
        .select(models::POST_COLUMNS)
        .filter(posts::id.eq(post_id))
        .first(conn)
        .unwrap()
}

#[test]
fn single_vevent_creates_event_and_occasion() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_single_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:single-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Single Event\r\nDESCRIPTION:Single description\r\nLOCATION:Somewhere\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );

        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        let event = synced_event(conn, source.id, "single-1").expect("event should have been created");
        let post = post_of(conn, event.post_id);
        assert_eq!(post.title, Some("Single Event".to_string()));
        assert_eq!(post.content, Some("Single description".to_string()));

        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 1);
        let occasion_post = post_of(conn, occasions[0].post_id);
        assert!(occasion_post.sync_source_uid.is_some());
        assert!(occasion_post.sync_source_recurrence_anchor.is_some());

        Ok(())
    });
}

/// `DTSTART`'s `TZID` parameter (RFC 5545 §3.3.5) should populate `Occasion.timezone`
/// straight from the feed, without needing `logic::resolve_timezone`'s Nominatim geocoding or a
/// hand-picked selector value at all.
#[test]
fn vevent_with_tzid_dtstart_populates_occasion_timezone() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_tzid_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = (Utc::now() + Duration::days(1)).with_timezone(&chrono_tz::America::New_York);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:tzid-1\r\nDTSTART;TZID=America/New_York:{}\r\nDTEND;TZID=America/New_York:{}\r\nSUMMARY:TZID Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format("%Y%m%dT%H%M%S"),
            end.format("%Y%m%dT%H%M%S")
        );

        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        let event = synced_event(conn, source.id, "tzid-1").expect("event should have been created");
        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 1);
        assert_eq!(occasions[0].timezone.as_deref(), Some("America/New_York"));

        Ok(())
    });
}

/// Deploying this feature doesn't retroactively touch occasions a `SyncSource` already synced
/// under the old (pre-`timezone`-column) code -- they simply have `timezone = NULL` until
/// something re-syncs them. This proves that happens automatically, with no backfill script
/// needed: `reconcile_occasions`' change-detection compares `timezone` alongside
/// `starts_at`/`ends_at`/`location`, so the very next scheduled sync after deploy updates a
/// stale `NULL` row from the feed's own `TZID` even though nothing else about the occurrence
/// changed.
#[test]
fn resyncing_backfills_a_timezone_that_was_null_before_this_feature_shipped() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_backfill_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = (Utc::now() + Duration::days(1)).with_timezone(&chrono_tz::America::New_York);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:backfill-1\r\nDTSTART;TZID=America/New_York:{}\r\nDTEND;TZID=America/New_York:{}\r\nSUMMARY:Backfill Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format("%Y%m%dT%H%M%S"),
            end.format("%Y%m%dT%H%M%S")
        );

        sync_source_text(&source, &ics, conn).expect("first sync should succeed");
        let event = synced_event(conn, source.id, "backfill-1").expect("event should exist");

        // Simulate a pre-deploy row by nulling out the timezone this first sync just set -- what
        // an occasion synced by the old code would actually look like.
        diesel::update(occasions::table.filter(occasions::event_id.eq(event.post_id)))
            .set(occasions::timezone.eq(None::<String>))
            .execute(conn)
            .unwrap();
        assert_eq!(occasions_for(conn, event.post_id)[0].timezone, None);

        sync_source_text(&source, &ics, conn).expect("resync should succeed");

        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 1, "resync must update the existing occasion in place, not duplicate it");
        assert_eq!(occasions[0].timezone.as_deref(), Some("America/New_York"));

        Ok(())
    });
}

/// Regression test for the 2026-09-04 duplicate-events incident: re-syncing the exact same feed
/// twice in a row (e.g. two runs of the background job before anything upstream changes) must
/// match every existing Event/Occasion by `(sync_source_id, sync_source_uid,
/// sync_source_recurrence_anchor)` rather than silently creating a second copy of everything.
#[test]
fn resyncing_the_same_feed_twice_creates_no_duplicates() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_reresync_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:reresync-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Reresync Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );

        sync_source_text(&source, &ics, conn).expect("first sync should succeed");
        sync_source_text(&source, &ics, conn).expect("second sync of the same feed should succeed");

        let matching_events: Vec<models::Event> = events::table
            .inner_join(posts::table.on(posts::id.eq(events::post_id)))
            .filter(posts::sync_source_id.eq(source.id))
            .select(events::all_columns)
            .load(conn)
            .unwrap();
        assert_eq!(
            matching_events.len(),
            1,
            "expected exactly one Event after syncing the same feed twice"
        );

        let occasions = occasions_for(conn, matching_events[0].post_id);
        assert_eq!(
            occasions.len(),
            1,
            "expected exactly one Occasion after syncing the same feed twice"
        );

        Ok(())
    });
}

/// Direct proof that the DB itself, not just application-level matching, rejects a duplicate
/// occurrence: this is what actually would have stopped the 2026-09-04 incident (a loud
/// constraint-violation error instead of 19 silently-created duplicate Events).
#[test]
fn duplicate_recurrence_anchor_is_rejected_by_db_unique_constraint() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_dbconstraint_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:dbconstraint-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:DB Constraint Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );
        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        let event = synced_event(conn, source.id, "dbconstraint-1").expect("event should exist");
        let existing_occasion = &occasions_for(conn, event.post_id)[0];
        let existing_occasion_post = post_of(conn, existing_occasion.post_id);

        let duplicate_post: models::Post = diesel::insert_into(posts::table)
            .values(&models::NewPost {
                user_id: Some(user.id),
                parent_post_id: None,
                title: None,
                link: None,
                content: None,
                visibility: "GLOBAL_PUBLIC".to_string(),
                context: "OCCASION".to_string(),
                moderation: "UNMODERATED".to_string(),
                media: vec![],
            })
            .returning(models::POST_COLUMNS)
            .get_result(conn)
            .unwrap();

        diesel::insert_into(occasions::table)
            .values(&models::NewOccasion {
                event_id: event.post_id,
                post_id: duplicate_post.id,
                info: serde_json::json!({}),
                starts_at: existing_occasion.starts_at,
                ends_at: existing_occasion.ends_at,
                location: None,
                timezone: existing_occasion.timezone.clone(),
            })
            .execute(conn)
            .expect("occasions insert itself no longer carries the unique constraint");

        // The unique constraint now lives on `posts` (see migration
        // 2026-09-11-000000_move_sync_source_to_posts), so it's this follow-up UPDATE --
        // mirroring `event_sync.rs`'s own insert-then-update pattern -- that must be rejected.
        let insert_result = diesel::update(posts::table.filter(posts::id.eq(duplicate_post.id)))
            .set((
                posts::sync_source_id.eq(existing_occasion_post.sync_source_id),
                posts::sync_source_uid.eq(existing_occasion_post.sync_source_uid.clone()),
                posts::sync_source_recurrence_anchor
                    .eq(existing_occasion_post.sync_source_recurrence_anchor),
            ))
            .execute(conn);

        assert!(
            matches!(
                insert_result,
                Err(diesel::result::Error::DatabaseError(
                    diesel::result::DatabaseErrorKind::UniqueViolation,
                    _
                ))
            ),
            "expected a unique constraint violation, got {:?}",
            insert_result
        );

        Ok(())
    });
}

/// Direct proof of the other half of the two-partial-index split (see migration
/// 2026-09-11-000000_move_sync_source_to_posts's doc comment): a single unique index across all
/// three `posts` sync columns wouldn't actually stop two rows both having
/// `sync_source_recurrence_anchor IS NULL` -- Postgres never treats two NULLs as colliding -- and
/// every Event's own series-level Post has exactly that (no recurrence anchor at all), same as a
/// future plain RSS/Atom-synced Post would. `idx_posts_sync_source_unique_non_recurring` exists
/// specifically to still catch that case.
#[test]
fn duplicate_non_recurring_sync_source_uid_is_rejected_by_db_unique_constraint() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_nonrecurring_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:nonrecurring-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Nonrecurring Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );
        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        let event = synced_event(conn, source.id, "nonrecurring-1").expect("event should exist");
        let event_post = post_of(conn, event.post_id);
        assert_eq!(
            event_post.sync_source_recurrence_anchor, None,
            "an Event's own series-level Post has no recurrence anchor"
        );

        let duplicate_series_post: models::Post = diesel::insert_into(posts::table)
            .values(&models::NewPost {
                user_id: Some(user.id),
                parent_post_id: None,
                title: None,
                link: None,
                content: None,
                visibility: "GLOBAL_PUBLIC".to_string(),
                context: "EVENT".to_string(),
                moderation: "UNMODERATED".to_string(),
                media: vec![],
            })
            .returning(models::POST_COLUMNS)
            .get_result(conn)
            .unwrap();

        let update_result = diesel::update(posts::table.filter(posts::id.eq(duplicate_series_post.id)))
            .set((
                posts::sync_source_id.eq(event_post.sync_source_id),
                posts::sync_source_uid.eq(event_post.sync_source_uid.clone()),
                // Left NULL, same as `event_post`'s own -- this is exactly the case a single
                // three-column unique index would have missed.
            ))
            .execute(conn);

        assert!(
            matches!(
                update_result,
                Err(diesel::result::Error::DatabaseError(
                    diesel::result::DatabaseErrorKind::UniqueViolation,
                    _
                ))
            ),
            "expected a unique constraint violation, got {:?}",
            update_result
        );

        Ok(())
    });
}

#[test]
fn recurring_vevent_expands_into_multiple_occasions() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_recur_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:recur-1\r\nDTSTART:{}\r\nDTEND:{}\r\nRRULE:FREQ=DAILY;COUNT=5\r\nSUMMARY:Recurring Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );

        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        let event = synced_event(conn, source.id, "recur-1").expect("event should have been created");
        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 5, "RRULE COUNT=5 should expand to 5 occasions");

        Ok(())
    });
}

#[test]
fn recurrence_id_override_changes_one_occurrence() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_override_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let second_occurrence_start = start + Duration::days(1);
        let moved_start = second_occurrence_start + Duration::hours(3);
        let moved_end = moved_start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:override-1\r\nDTSTART:{}\r\nDTEND:{}\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:Series\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:override-1\r\nRECURRENCE-ID:{}\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Moved Occurrence\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT),
            second_occurrence_start.format(ICS_FORMAT),
            moved_start.format(ICS_FORMAT),
            moved_end.format(ICS_FORMAT),
        );

        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        let event = synced_event(conn, source.id, "override-1").expect("event should have been created");
        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 3);

        let overridden_post_titles: Vec<Option<String>> = occasions
            .iter()
            .map(|i| post_of(conn, i.post_id).title)
            .collect();
        assert!(
            overridden_post_titles.contains(&Some("Moved Occurrence".to_string())),
            "one occasion should carry the RECURRENCE-ID override's own title, got {:?}",
            overridden_post_titles
        );

        Ok(())
    });
}

#[test]
fn occurrence_more_than_a_year_in_the_past_is_not_created() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_old_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() - Duration::days(400);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:old-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Old Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );

        sync_source_text(&source, &ics, conn).expect("sync should succeed");

        assert!(
            synced_event(conn, source.id, "old-1").is_none(),
            "an event more than a year in the past should not be synced in"
        );

        Ok(())
    });
}

#[test]
fn resync_removes_occasions_no_longer_in_feed_but_leaves_old_ones_alone() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_prune_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let recent_start = Utc::now() + Duration::days(1);
        let recent_end = recent_start + Duration::hours(1);
        let old_start = Utc::now() - Duration::days(400);
        let old_end = old_start + Duration::hours(1);

        // First sync: one recent occurrence for a recurring UID, plus a standalone old one that
        // (per the 1-year-lookback rule) should never come from a *feed* -- so instead we insert
        // it directly to simulate "a row that predates the lookback window, from before we
        // tightened the window, or from manual entry" and confirm resync doesn't touch it.
        let ics_v1 = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:prune-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Will vanish\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            recent_start.format(ICS_FORMAT),
            recent_end.format(ICS_FORMAT)
        );
        sync_source_text(&source, &ics_v1, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "prune-1").expect("event should exist after first sync");
        assert_eq!(occasions_for(conn, event.post_id).len(), 1);

        // Manually backdate that occasion to simulate a pre-existing old occurrence, and insert
        // an extra manually-tagged "old" occasion under the same event/source to prove old rows
        // aren't deleted by resync even when absent from the feed.
        let old_start_db: std::time::SystemTime = old_start.into();
        let old_end_db: std::time::SystemTime = old_end.into();
        diesel::update(occasions::table.filter(occasions::event_id.eq(event.post_id)))
            .set((
                occasions::starts_at.eq(old_start_db),
                occasions::ends_at.eq(old_end_db),
            ))
            .execute(conn)
            .unwrap();

        // Second sync: same UID, but the feed no longer mentions that (now old-dated) occurrence
        // at all (empty calendar). Since it's now more than a year in the past, it must survive.
        let ics_v2 = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nEND:VCALENDAR\r\n";
        sync_source_text(&source, ics_v2, conn).expect("second sync should succeed");

        assert_eq!(
            occasions_for(conn, event.post_id).len(),
            1,
            "an occasion older than the 1-year lookback should survive even after it drops out of the feed"
        );

        Ok(())
    });
}

/// A single missing sync shouldn't nuke the event: the occasion (and its Post, which may be
/// carrying a comment thread/media the user attached) is only marked missing, not deleted, and
/// the event survives right along with it.
#[test]
fn resync_marks_recent_occasion_missing_instead_of_deleting_it_immediately() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_prune2_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics_v1 = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:prune-2\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Will vanish\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );
        sync_source_text(&source, &ics_v1, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "prune-2").expect("event should exist after first sync");
        let original_occasion_id = occasions_for(conn, event.post_id)[0].post_id;

        let ics_v2 = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nEND:VCALENDAR\r\n";
        sync_source_text(&source, ics_v2, conn).expect("second sync should succeed");

        assert!(
            events::table.filter(events::post_id.eq(event.post_id)).first::<models::Event>(conn).optional().unwrap().is_some(),
            "an event whose only occasion just went missing this sync should not be deleted yet"
        );
        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 1, "the occasion should still exist, just marked missing");
        assert_eq!(occasions[0].post_id, original_occasion_id);
        assert!(occasions[0].sync_missing_since.is_some());

        Ok(())
    });
}

/// If the feed goes back to reporting the occurrence before the grace period elapses, the exact
/// same Occasion row (and its Post, i.e. any comment thread/media on it) is reused rather
/// than deleted-then-recreated.
#[test]
fn occasion_reappearing_before_grace_period_elapses_reuses_the_same_row() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_reappear_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics_v1 = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:reappear-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Flaky\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );
        sync_source_text(&source, &ics_v1, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "reappear-1").expect("event should exist after first sync");
        let original_occasion = occasions_for(conn, event.post_id).into_iter().next().unwrap();

        // Simulates a transient/partial upstream response that momentarily drops the occurrence.
        let ics_empty = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nEND:VCALENDAR\r\n";
        sync_source_text(&source, ics_empty, conn).expect("second sync should succeed");
        assert!(occasions_for(conn, event.post_id)[0].sync_missing_since.is_some());

        // The feed recovers before the grace period elapses.
        sync_source_text(&source, &ics_v1, conn).expect("third sync should succeed");
        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 1);
        assert_eq!(occasions[0].post_id, original_occasion.post_id, "should reuse the same occasion/Post, not recreate it");
        assert_eq!(occasions[0].post_id, original_occasion.post_id);
        assert!(occasions[0].sync_missing_since.is_none(), "reappearing should clear the missing marker");

        Ok(())
    });
}

/// Once an occasion has genuinely been missing for longer than the grace period, it (and the
/// emptied event) are pruned for real.
#[test]
fn occasion_missing_past_grace_period_is_deleted_and_emptied_event_is_removed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_expire_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics_v1 = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:expire-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Will vanish\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );
        sync_source_text(&source, &ics_v1, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "expire-1").expect("event should exist after first sync");

        let ics_empty = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nEND:VCALENDAR\r\n";
        sync_source_text(&source, ics_empty, conn).expect("second sync should succeed");

        // Simulate the grace period having elapsed by backdating the missing-since stamp.
        let long_ago: std::time::SystemTime = (Utc::now() - Duration::days(4)).into();
        diesel::update(occasions::table.filter(occasions::event_id.eq(event.post_id)))
            .set(occasions::sync_missing_since.eq(long_ago))
            .execute(conn)
            .unwrap();

        sync_source_text(&source, ics_empty, conn).expect("third sync should succeed");

        assert_eq!(occasions_for(conn, event.post_id).len(), 0);
        assert!(
            events::table
                .filter(events::post_id.eq(event.post_id))
                .first::<models::Event>(conn)
                .optional()
                .unwrap()
                .is_none(),
            "an event whose only occasion stayed missing past the grace period should be deleted"
        );
        assert_eq!(
            synced_post_count(conn, source.id),
            0,
            "pruning must delete the Event's and Occasion's Posts too, not leave them holding the UID"
        );

        Ok(())
    });
}

fn synced_post_count(conn: &mut crate::db_connection::PgPooledConnection, source_id: i64) -> i64 {
    posts::table
        .filter(posts::sync_source_id.eq(source_id))
        .count()
        .get_result(conn)
        .unwrap()
}

fn single_event_ics(uid: &str, summary: &str) -> String {
    let start = Utc::now() + Duration::days(1);
    let end = start + Duration::hours(1);
    format!(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:{}\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:{}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        uid,
        start.format(ICS_FORMAT),
        end.format(ICS_FORMAT),
        summary
    )
}

/// An event that dropped out of the feed long enough to be pruned and later came back must sync
/// again. Pruning used to delete only the `events` row, leaving the Event's Post behind still
/// holding `(source, uid)`, so re-creating it violated the unique index and failed every sync
/// (production incident, ATO band, 2026-11).
#[test]
fn event_pruned_after_grace_period_can_be_synced_again_when_it_returns() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_return_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let ics = single_event_ics("returns-1", "Comes back");
        let ics_empty = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nEND:VCALENDAR\r\n";
        sync_source_text(&source, &ics, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "returns-1").expect("event should exist");
        sync_source_text(&source, ics_empty, conn).expect("sync without the event should succeed");
        let long_ago: std::time::SystemTime = (Utc::now() - Duration::days(4)).into();
        diesel::update(occasions::table.filter(occasions::event_id.eq(event.post_id)))
            .set(occasions::sync_missing_since.eq(long_ago))
            .execute(conn)
            .unwrap();
        sync_source_text(&source, ics_empty, conn).expect("sync should prune the event");
        assert_eq!(synced_post_count(conn, source.id), 0);

        sync_source_text(&source, &ics, conn).expect("sync should succeed once the event returns");

        let returned = synced_event(conn, source.id, "returns-1").expect("event should exist again");
        assert_eq!(occasions_for(conn, returned.post_id).len(), 1);
        assert_eq!(synced_post_count(conn, source.id), 2, "one Event Post + one Occasion Post");

        Ok(())
    });
}

/// Data already damaged by that old behavior -- an Event's Post (and its Occasion's Post) with no
/// `events`/`occasions` row left -- heals on the next sync instead of failing it forever.
#[test]
fn sync_recovers_from_synced_posts_orphaned_by_a_deleted_event_row() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_orphan_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let ics = single_event_ics("orphaned-1", "Orphaned");
        sync_source_text(&source, &ics, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "orphaned-1").expect("event should exist");

        // What the old stale-event cleanup (and `delete_event`) did: delete the `events` row
        // (cascading to `occasions`), leaving both Posts behind.
        diesel::delete(events::table.filter(events::post_id.eq(event.post_id)))
            .execute(conn)
            .unwrap();
        assert_eq!(synced_post_count(conn, source.id), 2);

        sync_source_text(&source, &ics, conn).expect("sync should recover from the orphaned Posts");

        let recreated = synced_event(conn, source.id, "orphaned-1").expect("event should be re-created");
        assert_eq!(occasions_for(conn, recreated.post_id).len(), 1);
        assert_eq!(synced_post_count(conn, source.id), 2, "orphans replaced, not duplicated");

        Ok(())
    });
}

/// An Event that has lost all its Occasions (e.g. someone deleted the occasion Posts) is still
/// found by UID and reused, rather than re-created and colliding on the unique index.
#[test]
fn event_with_no_occasions_left_is_reused_when_the_feed_still_lists_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_no_occasions_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");

        let ics = single_event_ics("hollow-1", "Hollow");
        sync_source_text(&source, &ics, conn).expect("initial sync should succeed");
        let event = synced_event(conn, source.id, "hollow-1").expect("event should exist");
        let occasion_post_ids: Vec<i64> = occasions_for(conn, event.post_id)
            .iter()
            .map(|o| o.post_id)
            .collect();
        diesel::delete(posts::table.filter(posts::id.eq_any(occasion_post_ids)))
            .execute(conn)
            .unwrap();
        assert_eq!(occasions_for(conn, event.post_id).len(), 0);

        sync_source_text(&source, &ics, conn).expect("sync should reuse the occasion-less Event");

        let occasions = occasions_for(conn, event.post_id);
        assert_eq!(occasions.len(), 1, "the Event should have its occasion back, under the same Event");
        assert_eq!(synced_post_count(conn, source.id), 2);

        Ok(())
    });
}

#[test]
fn last_synced_at_is_updated() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_lastsync_owner");
        let source = create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");
        assert!(source.last_synced_at.is_none());

        let ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nEND:VCALENDAR\r\n";
        sync_source_text(&source, ics, conn).expect("sync should succeed");

        let refreshed = models::get_sync_source(source.id, conn).unwrap();
        assert!(refreshed.last_synced_at.is_some());

        Ok(())
    });
}

#[test]
fn sync_via_http_fetches_and_parses_from_a_real_url() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_http_owner");

        let start = Utc::now() + Duration::days(1);
        let end = start + Duration::hours(1);
        let ics = format!(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//\r\nBEGIN:VEVENT\r\nUID:http-1\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:Via HTTP\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            start.format(ICS_FORMAT),
            end.format(ICS_FORMAT)
        );
        let url = serve_ics(&ics);
        let source = create_sync_source_row(conn, &user, &url);

        sync_source(&source, conn).expect("sync over HTTP should succeed");

        let event = synced_event(conn, source.id, "http-1").expect("event should have been created via HTTP sync");
        let post = post_of(conn, event.post_id);
        assert_eq!(post.title, Some("Via HTTP".to_string()));

        Ok(())
    });
}

#[test]
fn missing_ics_url_fails_with_precondition_error() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "est_nourl_owner");
        let mut source =
            create_sync_source_row(conn, &user, "http://example.invalid/cal.ics");
        source.configuration = serde_json::json!({});

        // `sync_source` (the ICS/RSS/Atom dispatcher -- see `logic::sync_sources::mod`) can't
        // tell what kind of source this is at all with an empty `configuration`, so it's this
        // generic precondition, not `event_sync::sync_source_ics`'s own `ics_url_required`
        // (unreachable here since the dispatcher never gets that far).
        let err = sync_source(&source, conn).unwrap_err();
        assert_eq!(err.code(), tonic::Code::FailedPrecondition);
        assert_eq!(err.message(), "sync_source_configuration_required");

        Ok(())
    });
}
