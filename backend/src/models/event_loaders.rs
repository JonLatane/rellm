use super::{
    Author, Event, Rsvp, Occasion, OccasionSyncDestination, Post, SyncSource,
    User, AUTHOR_COLUMNS, OCCASION_COLUMNS, POST_COLUMNS,
};
use diesel::{
    dsl::sql,
    sql_types::{Bool, Text},
    *,
};
use tonic::{Code, Status};

use crate::{
    db_connection::PgPooledConnection,
    // protos::Author,
    schema::{
        rsvps, occasion_sync_destinations, occasions, events, follows,
        posts, sync_sources, users,
    },
};

pub fn get_sync_source(id: i64, conn: &mut PgPooledConnection) -> Result<SyncSource, Status> {
    sync_sources::table
        .select(sync_sources::all_columns)
        .filter(sync_sources::id.eq(id))
        .first::<SyncSource>(conn)
        .map_err(|_| Status::new(Code::NotFound, "sync_source_not_found"))
}

pub fn get_sync_sources_for_user(
    user_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<Vec<(SyncSource, Author)>, Status> {
    sync_sources::table
        .inner_join(users::table.on(sync_sources::user_id.eq(users::id)))
        .select((sync_sources::all_columns, AUTHOR_COLUMNS))
        .filter(sync_sources::user_id.eq(user_id))
        .order(sync_sources::created_at.desc())
        .load::<(SyncSource, Author)>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load sync sources for user_id={}: {:?}",
                user_id,
                e
            );
            Status::new(Code::Internal, "failed_to_load_sync_sources")
        })
}

/// Batched variant of `get_sync_sources_for_user` -- every SyncSource owned by any of
/// `user_ids`, paired with each owner's `Author`. Used by `get_users.rs`'s
/// `attach_advanced_admin_data` to fill in `User.sync_sources` for many users in one query
/// rather than one per user.
pub fn get_sync_sources_for_users(
    user_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<Vec<(SyncSource, Author)>, Status> {
    if user_ids.is_empty() {
        return Ok(vec![]);
    }
    sync_sources::table
        .inner_join(users::table.on(sync_sources::user_id.eq(users::id)))
        .select((sync_sources::all_columns, AUTHOR_COLUMNS))
        .filter(sync_sources::user_id.eq_any(user_ids))
        .order(sync_sources::created_at.desc())
        .load::<(SyncSource, Author)>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load sync sources for user_ids={:?}: {:?}",
                user_ids,
                e
            );
            Status::new(Code::Internal, "failed_to_load_sync_sources")
        })
}

pub fn get_sync_sources_by_ids(
    ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Vec<(SyncSource, Author)> {
    if ids.is_empty() {
        return vec![];
    }
    sync_sources::table
        .inner_join(users::table.on(sync_sources::user_id.eq(users::id)))
        .select((sync_sources::all_columns, AUTHOR_COLUMNS))
        .filter(sync_sources::id.eq_any(ids))
        .load::<(SyncSource, Author)>(conn)
        .unwrap_or_default()
}

/// Loads sync status rows for a set of Occasions, keyed for `event_marshaling` to group by
/// `occasion_id`.
pub fn get_occasion_sync_destinations(
    occasion_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Vec<OccasionSyncDestination> {
    if occasion_ids.is_empty() {
        return vec![];
    }
    occasion_sync_destinations::table
        .filter(occasion_sync_destinations::occasion_id.eq_any(occasion_ids))
        .load::<OccasionSyncDestination>(conn)
        .unwrap_or_default()
}

pub fn get_event(
    event_id: i64,
    _user: &Option<&User>,
    conn: &mut PgPooledConnection,
) -> Result<Event, Status> {
    events::table
        .select(events::all_columns)
        .filter(events::post_id.eq(event_id))
        .first::<Event>(conn)
        .map_err(|_| Status::new(Code::NotFound, "event_not_found"))
}

pub fn get_occasion(
    occasion_id: i64,
    _user: &Option<&User>,
    conn: &mut PgPooledConnection,
) -> Result<Occasion, Status> {
    occasions::table
        .select(OCCASION_COLUMNS)
        .filter(occasions::post_id.eq(occasion_id))
        .first::<Occasion>(conn)
        .map_err(|_| Status::new(Code::NotFound, "occasion_not_found"))
}

pub fn get_occasions(
    event_id: i64,
    user: &Option<&User>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<(Occasion, Post, Option<Author>)>, Status> {
    occasions::table
        .inner_join(posts::table.on(occasions::post_id.eq(posts::id)))
        .left_join(users::table.on(posts::user_id.eq(users::id.nullable())))
        .left_join(
            follows::table.on(posts::user_id.eq(follows::target_user_id.nullable()).and(
                follows::user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id).unwrap_or(0)),
            )),
        )
        .select((
            OCCASION_COLUMNS,
            POST_COLUMNS,
            AUTHOR_COLUMNS.nullable(),
        ))
        .filter(occasions::event_id.eq(event_id))
        .load::<(Occasion, Post, Option<Author>)>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load occasions for event_id={}: {:?}",
                event_id,
                e
            );
            Status::new(Code::Internal, "failed_to_load_occasions")
        })
}

// Gets an existing event rsvp for update/deletion.
pub fn get_rsvp(
    occasion_id: i64,
    attendee_user_id: Option<i64>,
    attendee_auth_token: Option<String>,
    conn: &mut PgPooledConnection,
) -> Option<(Rsvp, Option<Author>)> {
    match (attendee_user_id, attendee_auth_token) {
        (Some(user_id), _) => rsvps::table
            .left_join(users::table.on(rsvps::user_id.eq(users::id.nullable())))
            .select((rsvps::all_columns, AUTHOR_COLUMNS.nullable()))
            .filter(rsvps::occasion_id.eq(occasion_id))
            .filter(rsvps::user_id.eq(Some(user_id)))
            .get_result::<(Rsvp, Option<Author>)>(conn)
            .ok(),
        (_, Some(auth_token)) => rsvps::table
            .left_join(users::table.on(rsvps::user_id.eq(users::id.nullable())))
            .select((rsvps::all_columns, AUTHOR_COLUMNS.nullable()))
            .filter(rsvps::occasion_id.eq(occasion_id))
            .filter(rsvps::anonymous_attendee.is_not_null().and(
                sql::<Bool>("anonymous_attendee->>'auth_token' = ").bind::<Text, _>(auth_token),
            ))
            .get_result::<(Rsvp, Option<Author>)>(conn)
            .ok(),
        (_, _) => None,
    }
}

pub fn get_rsvps(
    occasion_id: i64,
    user: &Option<User>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<Rsvp>, Status> {
    rsvps::table
        .inner_join(
            occasions::table
                .on(rsvps::occasion_id.eq(occasions::post_id)),
        )
        .left_join(posts::table.on(occasions::post_id.eq(posts::id)))
        .left_join(users::table.on(posts::user_id.eq(users::id.nullable())))
        .left_join(
            follows::table.on(posts::user_id.eq(follows::target_user_id.nullable()).and(
                follows::user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id).unwrap_or(0)),
            )),
        )
        .select(rsvps::all_columns)
        .filter(rsvps::occasion_id.eq(occasion_id))
        .load::<Rsvp>(conn)
        .map_err(|e| {
            log::error!(
                "Failed to load event rsvps for occasion_id={}: {:?}",
                occasion_id,
                e
            );
            Status::new(Code::Internal, "failed_to_load_rsvps")
        })
}

// pub fn get_group_event(group_id: i64, event_id: i64, conn: &mut PgPooledConnection,) -> Result<GroupEvent, Status> {
//     group_posts::table
//         .select(group_posts::all_columns)
//         .filter(group_posts::group_id.eq(group_id))
//         .filter(group_posts::event_id.eq(event_id))
//         .first::<GroupEvent>(conn)
//         .map_err(|_| Status::new(Code::NotFound, "group_event_not_found"))
// }
