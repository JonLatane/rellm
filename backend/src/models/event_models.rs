use std::time::SystemTime;

use diesel::*;

use super::SyncDestination;
use crate::schema::{
    rsvps, occasion_sync_destinations, occasions, events, sync_sources,
};

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(primary_key(post_id))]
pub struct Event {
    pub post_id: i64,
    pub info: serde_json::Value,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = events)]
pub struct NewEvent {
    pub post_id: i64,
    pub info: serde_json::Value,
}

#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(belongs_to(Event))]
#[diesel(primary_key(post_id))]
pub struct Occasion {
    pub event_id: i64,
    pub post_id: i64,
    pub info: serde_json::Value,
    pub starts_at: SystemTime,
    pub ends_at: SystemTime,
    pub location: Option<serde_json::Value>,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
    /// When this synced Occasion first stopped appearing in its `SyncSource`'s feed --
    /// `None` while it's present (or for Occasions never touched by sync). Gives it a grace
    /// period before `event_sync::reconcile_occasions` actually deletes it, so a transient/partial
    /// upstream response can't permanently orphan the Post backing the Occasion's comment
    /// thread/media.
    pub sync_missing_since: Option<SystemTime>,
    /// An explicit IANA timezone (e.g. "America/New_York"), set by hand (`CreateNewPanel`/
    /// `EventPage`'s timezone selector) or from an ICS Sync Source's own `DTSTART`'s `TZID` --
    /// preferred over `logic::resolve_timezone`'s Nominatim-geocoded guess wherever both could
    /// apply (see `sync_occasion`).
    pub timezone: Option<String>,
}

/// Explicit column list for `occasions`, excluding:
/// - `search_text`, a denormalized tsvector used only for full-text search filtering/indexing --
///   see `backend/migrations/2026-07-30-170000_add_search_text_to_occasions` -- mirroring
///   why `POST_COLUMNS` (`post_models.rs`) excludes `posts.search_text`.
/// - `user_id`, denormalized from the Occasion's own Post's author purely so a composite GIN
///   index can cover author-scoped search in one scan (see that same migration) -- never read
///   back into application code, and `Occasion` derives `AsChangeset`, so a field here would
///   let a stray `.set(&existing_occasion)` stomp the trigger-maintained value with stale data.
pub const OCCASION_COLUMNS: (
    occasions::event_id,
    occasions::post_id,
    occasions::info,
    occasions::starts_at,
    occasions::ends_at,
    occasions::location,
    occasions::created_at,
    occasions::updated_at,
    occasions::sync_missing_since,
    occasions::timezone,
) = (
    occasions::event_id,
    occasions::post_id,
    occasions::info,
    occasions::starts_at,
    occasions::ends_at,
    occasions::location,
    occasions::created_at,
    occasions::updated_at,
    occasions::sync_missing_since,
    occasions::timezone,
);

#[derive(Debug, Insertable)]
#[diesel(table_name = occasions)]
pub struct NewOccasion {
    pub event_id: i64,
    pub post_id: i64,
    pub info: serde_json::Value,
    pub starts_at: SystemTime,
    pub ends_at: SystemTime,
    pub location: Option<serde_json::Value>,
    pub timezone: Option<String>,
}

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
pub struct SyncSource {
    pub id: i64,
    pub user_id: i64,
    pub sync_interval_seconds: i64,
    pub configuration: serde_json::Value,
    pub last_synced_at: Option<SystemTime>,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
    pub event_count: i64,
    pub occasion_count: i64,
    pub post_count: i64,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = sync_sources)]
pub struct NewSyncSource {
    pub user_id: i64,
    pub sync_interval_seconds: i64,
    pub configuration: serde_json::Value,
}

/// A single Occasion's sync status against a single SyncDestination (see
/// `models::SyncDestination` in `sync_models.rs`). Composite-keyed (no surrogate `id`), so it's
/// `Identifiable` via both foreign keys rather than one.
#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(table_name = occasion_sync_destinations)]
#[diesel(primary_key(occasion_id, sync_destination_id))]
#[diesel(belongs_to(Occasion))]
#[diesel(belongs_to(SyncDestination))]
pub struct OccasionSyncDestination {
    pub occasion_id: i64,
    pub sync_destination_id: i64,
    pub destination_instance_id: Option<String>,
    pub destination_url: Option<String>,
    pub synced_at: Option<SystemTime>,
    pub created_at: SystemTime,
}

#[derive(Debug, Insertable, AsChangeset)]
#[diesel(table_name = occasion_sync_destinations)]
pub struct NewOccasionSyncDestination {
    pub occasion_id: i64,
    pub sync_destination_id: i64,
    pub destination_instance_id: Option<String>,
    pub destination_url: Option<String>,
    pub synced_at: Option<SystemTime>,
}

#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(belongs_to(Occasion))]
pub struct Rsvp {
    pub id: i64,
    pub occasion_id: i64,
    pub user_id: Option<i64>,
    pub anonymous_attendee: Option<serde_json::Value>,
    pub number_of_guests: i32,
    pub status: String,
    pub inviting_user_id: Option<i64>,
    pub public_note: String,
    pub private_note: String,
    pub moderation: String,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = rsvps)]
pub struct NewRsvp {
    pub occasion_id: i64,
    pub user_id: Option<i64>,
    pub anonymous_attendee: Option<serde_json::Value>,
    pub number_of_guests: i32,
    pub status: String,
    pub inviting_user_id: Option<i64>,
    pub public_note: String,
    pub private_note: String,
    pub moderation: String,
}

// #[derive(Debug, Queryable, Identifiable, AsChangeset)]
// pub struct GroupEvent {
//     pub id: i64,
//     pub group_id: i64,
//     pub event_id: i64,
//     pub user_id: i64,
//     pub group_moderation: String,
//     pub created_at: SystemTime,
//     pub updated_at: Option<SystemTime>,
// }
// #[derive(Debug, Insertable)]
// #[diesel(table_name = group_posts)]
// pub struct NewGroupEvent {
//     pub group_id: i64,
//     pub event_id: i64,
//     pub user_id: i64,
//     pub group_moderation: String,
// }

// #[derive(Debug, Queryable, Identifiable, AsChangeset)]
// pub struct UserEvent {
//     pub id: i64,
//     pub user_id: i64,
//     pub event_id: i64,
//     pub created_at: SystemTime,
//     pub updated_at: SystemTime,
// }
// #[derive(Debug, Insertable)]
// #[diesel(table_name = user_events)]
// pub struct NewUserEvent {
//     pub user_id: i64,
//     pub event_id: i64,
// }
