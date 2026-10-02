//! Pulls events from a `SyncSource`'s external calendar (currently only ICS subscription
//! URLs) and upserts them into `events`/`occasions`/`posts`.
//!
//! Recurring `VEVENT`s (an `RRULE`) are expanded with the `rrule` crate: one ICS `UID` maps to
//! one `Event`, and each occurrence maps to one `Occasion`, keyed by
//! `(sync_source_id, sync_source_uid, sync_source_recurrence_anchor)` -- real, indexed columns
//! (and a hard DB unique constraint) on the occurrence's own `Post` (see migration
//! 2026-09-11-000000_move_sync_source_to_posts -- these columns started out on
//! `events`/`occasions` themselves, denormalized down onto `posts` so any kind of synced
//! Post, not just Events/Occasions, gets the same guarantee) rather than an app-level JSON
//! key or a hand-built/parsed string, so re-syncing finds and updates the same rows rather than
//! duplicating them, and a bug that breaks that matching fails loudly (a constraint violation)
//! instead of silently creating duplicates -- see 2026-09-04's duplicate-events incident, which is
//! exactly what motivated this.
//! A `VEVENT` with a `RECURRENCE-ID` overrides that one occurrence's time/text (a moved or edited
//! single occasion of a series); `sync_source_recurrence_anchor` is that occurrence's stable
//! identity within the series (its own start time for a plain expansion, or its *original*
//! scheduled time for one that's since moved -- deliberately different from that row's own
//! `starts_at` once moved, which is what lets it still be found as "the same one" next sync).
//!
//! Only occurrences ending within the last year through ~1 year out are created/updated.
//! Existing rows older than that are never touched, even if they'd otherwise be pruned for no
//! longer appearing in the feed.
//!
//! An in-window occasion that stops appearing in the feed isn't deleted right away: it's marked
//! `sync_missing_since` and only actually deleted once it's stayed missing for
//! `MISSING_GRACE_PERIOD_DAYS`. This protects against a transient or partial upstream response
//! (rate limiting, a mid-edit feed, a truncated fetch) being mistaken for a real deletion --
//! re-creating a dropped occasion always makes a brand new `Post`, so a same-sync round-trip
//! delete+recreate would silently orphan whatever comment thread/media the user had attached to
//! the original one. An `Event` itself is only deleted once none of its occasions remain.

use std::collections::{HashMap, HashSet};
use std::time::SystemTime;

use chrono::{DateTime, Duration, Utc};
use diesel::*;
use icalendar::{Calendar, CalendarDateTime, Component, DatePerhapsTime};
use rrule::{RRule, RRuleSet, Unvalidated};
use serde_json::json;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::{occasions, events, posts, sync_sources};

const SYNC_PAST_WINDOW_DAYS: i64 = 365;
const SYNC_FUTURE_WINDOW_DAYS: i64 = 365;
const MAX_RRULE_OCCURRENCES: u16 = 2000;
/// How long an in-window occasion can stay absent from the feed before `reconcile_occasions`
/// actually deletes it. See the module doc comment.
const MISSING_GRACE_PERIOD_DAYS: i64 = 3;

/// Fetches `source`'s ICS URL over HTTP, then delegates to [`sync_source_text`].
/// Split out so specs can exercise the parsing/upserting logic against a fixed ICS string
/// without any network access.
pub fn sync_source_ics(source: &models::SyncSource, conn: &mut PgPooledConnection) -> Result<(), Status> {
    let url = ics_subscription_url(source)?;
    let ics_text = fetch_ics(url)?;
    sync_source_text(source, &ics_text, conn)
}

/// RPC handlers here are plain sync functions, but in production they're still called from
/// within Rocket's (multi-threaded) Tokio runtime -- `reqwest::blocking` builds and tears down
/// its own nested runtime per call, which panics ("Cannot drop a runtime in a context where
/// blocking is not allowed") if done directly from an existing async context. `block_in_place`
/// tells Tokio this thread is about to block so it can hand off its other queued work first,
/// which is exactly what makes the nested runtime safe to create/drop -- but `block_in_place`
/// itself panics if there's no Tokio runtime at all (e.g. this same function called from a plain
/// `#[test]` or a `bin/`), so it's only used when actually inside one.
fn fetch_ics(url: &str) -> Result<String, Status> {
    crate::init_crypto();
    let fetch = || {
        reqwest::blocking::get(url)
            .and_then(|response| response.error_for_status())
            .map_err(|e| {
                log::error!("Failed to fetch ICS from {}: {:?}", url, e);
                Status::new(Code::FailedPrecondition, "ics_fetch_failed")
            })?
            .text()
            .map_err(|e| {
                log::error!("Failed to read ICS response body from {}: {:?}", url, e);
                Status::new(Code::FailedPrecondition, "ics_fetch_failed")
            })
    };

    if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(fetch)
    } else {
        fetch()
    }
}

fn ics_subscription_url(source: &models::SyncSource) -> Result<&str, Status> {
    source
        .configuration
        .get("ics_subscription_url")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "ics_url_required"))
}

struct Occurrence {
    /// This occurrence's stable identity within its series -- see the module doc comment.
    recurrence_anchor: DateTime<Utc>,
    starts_at: DateTime<Utc>,
    ends_at: DateTime<Utc>,
    location: Option<String>,
    title: Option<String>,
    content: Option<String>,
    /// The IANA timezone (`TZID`) `starts_at` was expressed in in the source feed, if any -- e.g.
    /// `DTSTART;TZID=America/New_York:...` -- so `Occasion.timezone` can be populated
    /// straight from the feed rather than only ever coming from `logic::resolve_timezone`'s
    /// Nominatim guess or a hand-picked selector value. `None` for a floating or UTC `DTSTART`
    /// (no `TZID` to read).
    timezone: Option<String>,
    /// Whether this occurrence came from its own `RECURRENCE-ID` VEVENT (as opposed to being a
    /// plain expansion of the master's `RRULE`) -- only overrides get their own occasion `Post`
    /// text; plain expansions leave their occasion `Post` empty, same as normal (non-synced)
    /// recurring events do.
    is_override: bool,
}

struct EventGroup {
    uid: String,
    title: Option<String>,
    content: Option<String>,
    link: Option<String>,
    occurrences: Vec<Occurrence>,
}

pub fn sync_source_text(
    source: &models::SyncSource,
    ics_text: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let calendar: Calendar = ics_text.parse().map_err(|e| {
        log::error!("Failed to parse ICS text: {:?}", e);
        Status::new(Code::FailedPrecondition, "ics_parse_failed")
    })?;

    let now = Utc::now();
    let window_start = now - Duration::days(SYNC_PAST_WINDOW_DAYS);
    let window_end = now + Duration::days(SYNC_FUTURE_WINDOW_DAYS);

    let event_groups = group_vevents(&calendar, window_start, window_end);

    let owner_user_id = source.user_id;
    let moderation = default_event_moderation(conn);

    let window_start_db: SystemTime = window_start.into();

    let result = conn.transaction::<(), diesel::result::Error, _>(|conn| {
        // Every currently-existing synced occasion's series UID -> parent Event id, via real,
        // indexed columns (see the module doc comment) instead of an app-level JSON key. Multiple
        // occasions of a recurring series share the same `event_id`, so a plain overwrite while
        // building this map is correct.
        let existing_event_ids_by_uid: HashMap<String, i64> = occasions::table
            .inner_join(posts::table.on(posts::id.eq(occasions::post_id)))
            .select((posts::sync_source_uid, occasions::event_id))
            .filter(posts::sync_source_id.eq(source.id))
            .load::<(Option<String>, i64)>(conn)?
            .into_iter()
            .filter_map(|(uid, event_id)| uid.map(|uid| (uid, event_id)))
            .collect();

        let mut seen_uids: HashSet<String> = HashSet::new();

        for group in &event_groups {
            seen_uids.insert(group.uid.clone());

            let event_id = match existing_event_ids_by_uid.get(&group.uid) {
                Some(&event_id) => {
                    sync_post_text(conn, event_id, &group.title, &group.content, &group.link)?;
                    event_id
                }
                None => {
                    create_event_for_group(conn, source.id, owner_user_id, &moderation, group)?
                        .post_id
                }
            };

            reconcile_occasions(
                conn,
                event_id,
                source.id,
                owner_user_id,
                &moderation,
                group,
                window_start_db,
                now,
            )?;
        }

        // Events whose UID no longer appears in the feed at all: prune their in-window
        // occasions the same way `reconcile_occasions` does for a group with zero occurrences
        // (subject to the same missing-grace-period before an occasion is actually deleted),
        // then delete the event itself (cascades its occasions/rsvps) once nothing's left.
        let stale_event_ids: HashSet<i64> = existing_event_ids_by_uid
            .iter()
            .filter(|(uid, _)| !seen_uids.contains(*uid))
            .map(|(_, &event_id)| event_id)
            .collect();
        for event_id in stale_event_ids {
            let empty_group = EventGroup {
                uid: String::new(),
                title: None,
                content: None,
                link: None,
                occurrences: vec![],
            };
            reconcile_occasions(
                conn,
                event_id,
                source.id,
                owner_user_id,
                &moderation,
                &empty_group,
                window_start_db,
                now,
            )?;

            let remaining: i64 = occasions::table
                .filter(occasions::event_id.eq(event_id))
                .count()
                .get_result(conn)?;
            if remaining == 0 {
                diesel::delete(events::table.filter(events::post_id.eq(event_id))).execute(conn)?;
            }
        }

        let event_count: i64 = events::table
            .inner_join(posts::table.on(posts::id.eq(events::post_id)))
            .filter(posts::sync_source_id.eq(source.id))
            .count()
            .get_result(conn)?;
        let occasion_count: i64 = occasions::table
            .inner_join(posts::table.on(posts::id.eq(occasions::post_id)))
            .filter(posts::sync_source_id.eq(source.id))
            .count()
            .get_result(conn)?;

        diesel::update(sync_sources::table.filter(sync_sources::id.eq(source.id)))
            .set((
                sync_sources::last_synced_at.eq(SystemTime::now()),
                sync_sources::event_count.eq(event_count),
                sync_sources::occasion_count.eq(occasion_count),
            ))
            .execute(conn)?;

        crate::logic::update_event_counts(owner_user_id, conn)?;

        Ok(())
    });

    result.map_err(|e| {
        log::error!("Failed to sync SyncSource {}: {:?}", source.id, e);
        Status::new(Code::Internal, "failed_to_sync_source")
    })
}

fn default_event_moderation(conn: &mut PgPooledConnection) -> String {
    crate::rpcs::get_server_configuration_proto(conn)
        .map(
            |c| match c.event_settings.unwrap_or_default().default_moderation() {
                Moderation::Pending => Moderation::Pending.as_str_name(),
                _ => Moderation::Unmoderated.as_str_name(),
            },
        )
        .unwrap_or_else(|_| Moderation::Unmoderated.as_str_name())
        .to_string()
}

fn create_event_for_group(
    conn: &mut PgPooledConnection,
    source_id: i64,
    owner_user_id: i64,
    moderation: &str,
    group: &EventGroup,
) -> Result<models::Event, diesel::result::Error> {
    let post = insert_into(posts::table)
        .values(&models::NewPost {
            user_id: Some(owner_user_id),
            parent_post_id: None,
            title: group.title.clone(),
            link: group.link.clone(),
            content: group.content.clone(),
            visibility: Visibility::GlobalPublic.to_string_visibility(),
            embed_link: false,
            context: PostContext::Event.to_string_post_context(),
            moderation: moderation.to_string(),
            media: vec![],
        })
        .returning(models::POST_COLUMNS)
        .get_result::<models::Post>(conn)?;

    // A plain UPDATE after the INSERT (mirroring `sync_post_text`'s pattern below), rather than
    // a field on `NewPost` itself -- `NewPost` is constructed at a dozen call sites across the
    // codebase that never set a SyncSource, and every nullable column a struct doesn't name is
    // simply left at its SQL default (NULL) on INSERT, so this is the only place that actually
    // needs to touch these columns at creation time. `sync_source_recurrence_anchor` stays NULL
    // here -- it's specific to a recurring Occasion's own occurrence identity, not this
    // series-level Post (see `models::Post`'s field doc).
    diesel::update(posts::table.filter(posts::id.eq(post.id)))
        .set((
            posts::sync_source_id.eq(Some(source_id)),
            posts::sync_source_uid.eq(Some(&group.uid)),
        ))
        .execute(conn)?;

    insert_into(events::table)
        .values(&models::NewEvent {
            post_id: post.id,
            info: json!({}),
        })
        .get_result::<models::Event>(conn)
}

fn sync_post_text(
    conn: &mut PgPooledConnection,
    post_id: i64,
    title: &Option<String>,
    content: &Option<String>,
    link: &Option<String>,
) -> Result<(), diesel::result::Error> {
    let post: models::Post = posts::table
        .select(models::POST_COLUMNS)
        .filter(posts::id.eq(post_id))
        .first(conn)?;
    if &post.title != title || &post.content != content || &post.link != link {
        diesel::update(posts::table.filter(posts::id.eq(post_id)))
            .set((
                posts::title.eq(title),
                posts::content.eq(content),
                posts::link.eq(link),
            ))
            .execute(conn)?;
    }
    Ok(())
}

fn location_json(location: &Option<String>) -> Option<serde_json::Value> {
    location.as_ref().map(|address| {
        serde_json::to_value(Location {
            id: String::new(),
            creator_id: String::new(),
            uniformly_formatted_address: address.clone(),
        })
        .unwrap()
    })
}

/// Creates/updates `Occasion`s (+ their `Post`s) for `group`'s occurrences under
/// `event_id`, then reconciles any existing occasion under `event_id` that's no longer present
/// in `group.occurrences` -- but only if that occasion's `ends_at` is still within the sync
/// window (`>= window_start_db`); older ones are left untouched no matter what the feed says now.
/// An in-window occasion that's missing isn't deleted immediately: the first sync that misses it
/// stamps `sync_missing_since` and leaves it alone, and only a sync that *still* misses it after
/// `MISSING_GRACE_PERIOD_DAYS` have passed since that stamp actually deletes it. An occasion that
/// reappears (matched by `sync_source_recurrence_anchor`) has its `sync_missing_since` cleared.
fn reconcile_occasions(
    conn: &mut PgPooledConnection,
    event_id: i64,
    source_id: i64,
    owner_user_id: i64,
    moderation: &str,
    group: &EventGroup,
    window_start_db: SystemTime,
    now: DateTime<Utc>,
) -> Result<(), diesel::result::Error> {
    let existing_occasions: Vec<(models::Occasion, Option<SystemTime>)> = occasions::table
        .inner_join(posts::table.on(posts::id.eq(occasions::post_id)))
        .select((models::OCCASION_COLUMNS, posts::sync_source_recurrence_anchor))
        .filter(occasions::event_id.eq(event_id))
        .load(conn)?;
    let mut existing_by_anchor: HashMap<SystemTime, models::Occasion> = existing_occasions
        .into_iter()
        .filter_map(|(i, anchor)| anchor.map(|anchor| (anchor, i)))
        .collect();

    for occ in &group.occurrences {
        let starts_at_db: SystemTime = occ.starts_at.into();
        let ends_at_db: SystemTime = occ.ends_at.into();
        let anchor_db: SystemTime = occ.recurrence_anchor.into();
        let loc_json = location_json(&occ.location);

        match existing_by_anchor.remove(&anchor_db) {
            Some(existing_occasion) => {
                if existing_occasion.starts_at != starts_at_db
                    || existing_occasion.ends_at != ends_at_db
                    || existing_occasion.location != loc_json
                    || existing_occasion.timezone != occ.timezone
                    || existing_occasion.sync_missing_since.is_some()
                {
                    diesel::update(
                        occasions::table
                            .filter(occasions::post_id.eq(existing_occasion.post_id)),
                    )
                    .set((
                        occasions::starts_at.eq(starts_at_db),
                        occasions::ends_at.eq(ends_at_db),
                        occasions::location.eq(&loc_json),
                        occasions::timezone.eq(&occ.timezone),
                        occasions::sync_missing_since.eq(None::<SystemTime>),
                    ))
                    .execute(conn)?;
                }
                if occ.is_override {
                    sync_post_text(
                        conn,
                        existing_occasion.post_id,
                        &occ.title,
                        &occ.content,
                        &None,
                    )?;
                }
            }
            None => {
                let occasion_post = insert_into(posts::table)
                    .values(&models::NewPost {
                        user_id: Some(owner_user_id),
                        parent_post_id: None,
                        title: if occ.is_override {
                            occ.title.clone()
                        } else {
                            None
                        },
                        link: None,
                        content: if occ.is_override {
                            occ.content.clone()
                        } else {
                            None
                        },
                        visibility: Visibility::GlobalPublic.to_string_visibility(),
                        embed_link: false,
                        context: PostContext::Occasion.as_str_name().to_string(),
                        moderation: moderation.to_string(),
                        media: vec![],
                    })
                    .returning(models::POST_COLUMNS)
                    .get_result::<models::Post>(conn)?;
                insert_into(occasions::table)
                    .values(&models::NewOccasion {
                        event_id,
                        post_id: occasion_post.id,
                        info: json!({}),
                        starts_at: starts_at_db,
                        ends_at: ends_at_db,
                        location: loc_json,
                        timezone: occ.timezone.clone(),
                    })
                    .execute(conn)?;
                // See `create_event_for_group`'s comment on why this is a follow-up UPDATE rather
                // than fields on `NewPost` -- this is also where the hard DB unique constraint on
                // (sync_source_id, sync_source_uid, sync_source_recurrence_anchor) actually gets
                // checked (the INSERT above never sets these columns, so it can't violate it).
                diesel::update(posts::table.filter(posts::id.eq(occasion_post.id)))
                    .set((
                        posts::sync_source_id.eq(Some(source_id)),
                        posts::sync_source_uid.eq(Some(&group.uid)),
                        posts::sync_source_recurrence_anchor.eq(Some(anchor_db)),
                    ))
                    .execute(conn)?;
            }
        }
    }

    let now_db: SystemTime = now.into();
    let mut newly_missing_ids: Vec<i64> = vec![];
    let mut expired_ids: Vec<i64> = vec![];
    for missing in existing_by_anchor
        .values()
        .filter(|i| i.ends_at >= window_start_db)
    {
        match missing.sync_missing_since {
            None => newly_missing_ids.push(missing.post_id),
            Some(missing_since) => {
                let missing_since: DateTime<Utc> = missing_since.into();
                if now - missing_since >= Duration::days(MISSING_GRACE_PERIOD_DAYS) {
                    expired_ids.push(missing.post_id);
                }
            }
        }
    }
    if !newly_missing_ids.is_empty() {
        diesel::update(
            occasions::table.filter(occasions::post_id.eq_any(newly_missing_ids)),
        )
        .set(occasions::sync_missing_since.eq(now_db))
        .execute(conn)?;
    }
    if !expired_ids.is_empty() {
        diesel::delete(occasions::table.filter(occasions::post_id.eq_any(expired_ids)))
            .execute(conn)?;
    }

    Ok(())
}

/// Converts an `icalendar` `DATE`/`DATE-TIME` into a concrete UTC instant. Floating (no
/// timezone) times are treated as already-UTC -- a pragmatic fallback rather than an accurate
/// one, since there's no user-local timezone to resolve them against server-side.
fn date_perhaps_time_to_utc(d: &DatePerhapsTime) -> Option<DateTime<Utc>> {
    match d {
        DatePerhapsTime::Date(date) => date
            .and_hms_opt(0, 0, 0)
            .map(|ndt| DateTime::<Utc>::from_naive_utc_and_offset(ndt, Utc)),
        DatePerhapsTime::DateTime(CalendarDateTime::Utc(dt)) => Some(*dt),
        DatePerhapsTime::DateTime(CalendarDateTime::Floating(ndt)) => {
            Some(DateTime::<Utc>::from_naive_utc_and_offset(*ndt, Utc))
        }
        DatePerhapsTime::DateTime(with_tz @ CalendarDateTime::WithTimezone { date_time, .. }) => {
            with_tz
                .try_into_utc()
                .or_else(|| Some(DateTime::<Utc>::from_naive_utc_and_offset(*date_time, Utc)))
        }
    }
}

fn get_date_property(event: &icalendar::Event, key: &str) -> Option<DateTime<Utc>> {
    let property = event.properties().get(key)?;
    let dpt = DatePerhapsTime::from_property(property)?;
    date_perhaps_time_to_utc(&dpt)
}

/// The IANA `TZID` `event`'s `key` property (e.g. `DTSTART`) was expressed in, if it carries one
/// (i.e. `key`'s value is `CalendarDateTime::WithTimezone` -- a `DATE`, a floating/`Z`-suffixed
/// `DATE-TIME`, or a missing property all have none).
fn get_tzid_property(event: &icalendar::Event, key: &str) -> Option<String> {
    let property = event.properties().get(key)?;
    match DatePerhapsTime::from_property(property)? {
        DatePerhapsTime::DateTime(CalendarDateTime::WithTimezone { tzid, .. }) => Some(tzid),
        _ => None,
    }
}

/// `EXDATE` may list multiple comma-separated date-times in one property (RFC 5545 §3.8.5.1).
/// Repeated `EXDATE:` lines aren't handled -- an accepted simplification given how rare they are
/// in practice compared to the single-line-with-commas form real calendar exporters use.
fn parse_exdates(event: &icalendar::Event) -> Vec<DateTime<Utc>> {
    let Some(raw) = event.property_value("EXDATE") else {
        return vec![];
    };
    raw.split(',')
        .filter_map(|token| token.trim().parse::<CalendarDateTime>().ok())
        .filter_map(|cdt| date_perhaps_time_to_utc(&DatePerhapsTime::DateTime(cdt)))
        .collect()
}

fn group_vevents(
    calendar: &Calendar,
    window_start: DateTime<Utc>,
    window_end: DateTime<Utc>,
) -> Vec<EventGroup> {
    let mut by_uid: HashMap<String, Vec<&icalendar::Event>> = HashMap::new();
    for component in calendar.iter() {
        if let Some(event) = component.as_event() {
            if let Some(uid) = event.property_value("UID") {
                by_uid.entry(uid.to_string()).or_default().push(event);
            }
        }
    }

    let mut groups = vec![];
    for (uid, vevents) in by_uid {
        let Some(master) = vevents
            .iter()
            .find(|e| e.property_value("RECURRENCE-ID").is_none())
            .copied()
        else {
            continue; // only override(s) present, nothing to anchor the series to
        };
        let Some(master_start) = get_date_property(master, "DTSTART") else {
            continue; // no DTSTART, nothing we can do with this VEVENT
        };
        let master_end = get_date_property(master, "DTEND").unwrap_or(master_start);
        let duration = master_end - master_start;

        let overrides: HashMap<DateTime<Utc>, &icalendar::Event> = vevents
            .iter()
            .filter(|e| e.property_value("RECURRENCE-ID").is_some())
            .filter_map(|e| get_date_property(e, "RECURRENCE-ID").map(|dt| (dt, *e)))
            .collect();

        let occurrence_starts =
            expand_occurrence_starts(master, master_start, window_start, window_end);

        let mut occurrences = vec![];
        let mut seen_starts: HashSet<DateTime<Utc>> = HashSet::new();
        for occ_start in occurrence_starts {
            seen_starts.insert(occ_start);
            let occ_end = occ_start + duration;
            if occ_end < window_start {
                continue;
            }
            let override_event = overrides.get(&occ_start).copied();
            occurrences.push(build_occurrence(occ_start, occ_end, master, override_event));
        }

        // Override VEVENTs whose RECURRENCE-ID falls outside the plain RRULE expansion (e.g. an
        // occurrence moved to a different time) still need their own occasion.
        for (recurrence_id, override_event) in &overrides {
            if seen_starts.contains(recurrence_id) {
                continue;
            }
            let starts_at = get_date_property(override_event, "DTSTART").unwrap_or(*recurrence_id);
            let ends_at =
                get_date_property(override_event, "DTEND").unwrap_or(starts_at + duration);
            if ends_at < window_start {
                continue;
            }
            occurrences.push(
                build_occurrence(*recurrence_id, ends_at, master, Some(override_event))
                    .with_start(starts_at),
            );
        }

        if occurrences.is_empty() {
            continue;
        }

        groups.push(EventGroup {
            uid,
            title: master.property_value("SUMMARY").map(str::to_string),
            content: master.property_value("DESCRIPTION").map(str::to_string),
            link: master.property_value("URL").map(str::to_string),
            occurrences,
        });
    }
    groups
}

fn build_occurrence(
    recurrence_anchor: DateTime<Utc>,
    ends_at: DateTime<Utc>,
    master: &icalendar::Event,
    override_event: Option<&icalendar::Event>,
) -> Occurrence {
    let source_event = override_event.unwrap_or(master);
    Occurrence {
        recurrence_anchor,
        starts_at: recurrence_anchor,
        ends_at,
        location: source_event.property_value("LOCATION").map(str::to_string),
        title: override_event
            .and_then(|e| e.property_value("SUMMARY"))
            .map(str::to_string),
        content: override_event
            .and_then(|e| e.property_value("DESCRIPTION"))
            .map(str::to_string),
        // Falls back to the master's own `DTSTART` `TZID` when the override doesn't set its own
        // (e.g. one that only moved the time or edited the text) -- a plain expansion (no
        // override at all) always reads the master's.
        timezone: get_tzid_property(source_event, "DTSTART")
            .or_else(|| get_tzid_property(master, "DTSTART")),
        is_override: override_event.is_some(),
    }
}

impl Occurrence {
    fn with_start(mut self, starts_at: DateTime<Utc>) -> Self {
        self.starts_at = starts_at;
        self
    }
}

fn expand_occurrence_starts(
    master: &icalendar::Event,
    master_start: DateTime<Utc>,
    window_start: DateTime<Utc>,
    window_end: DateTime<Utc>,
) -> Vec<DateTime<Utc>> {
    let Some(rrule_str) = master.property_value("RRULE") else {
        return vec![master_start];
    };

    let dt_start_rrule = master_start.with_timezone(&rrule::Tz::UTC);
    let parsed = rrule_str
        .parse::<RRule<Unvalidated>>()
        .map_err(|e| e.to_string())
        .and_then(|r| r.validate(dt_start_rrule).map_err(|e| e.to_string()));

    let validated_rrule = match parsed {
        Ok(r) => r,
        Err(e) => {
            log::warn!("Failed to parse/validate RRULE '{}': {}", rrule_str, e);
            return vec![master_start];
        }
    };

    let mut set = RRuleSet::new(dt_start_rrule).rrule(validated_rrule);
    for exdate in parse_exdates(master) {
        set = set.exdate(exdate.with_timezone(&rrule::Tz::UTC));
    }

    let result = set
        .after(window_start.with_timezone(&rrule::Tz::UTC))
        .before(window_end.with_timezone(&rrule::Tz::UTC))
        .all(MAX_RRULE_OCCURRENCES);

    result.dates.iter().map(|d| d.with_timezone(&Utc)).collect()
}
