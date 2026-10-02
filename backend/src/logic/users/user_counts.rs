//! Single source of truth for how each of `users`' denormalized counters (`follower_count`,
//! `following_count`, `friend_count`, `group_count`, `post_count`, `response_count`,
//! `event_count`, `occasion_count`, `media_storage_bytes_used`) is *defined* -- each `*_count`/
//! `media_storage_bytes_used` function below computes a fresh, correct value via `COUNT(*)`/`SUM`,
//! rather than trusting an incrementally maintained one.
//!
//! Used both by RPC handlers (via the `update_*` functions, to refresh just the counters a
//! mutation could have affected) and by `bin/update_user_counts.rs` (via [`update_all_counts`],
//! which recomputes every counter for every user on an interval, correcting any drift the
//! incremental call sites missed -- e.g. a cascading delete that doesn't go through them at all).

use diesel::sql_types::{BigInt, Nullable};
use diesel::*;

use crate::db_connection::PgPooledConnection;
use crate::rpcs::validations::PASSING_MODERATIONS;
use crate::schema::{occasions, events, follows, memberships, posts, users};

#[derive(QueryableByName)]
struct SumRow {
    #[diesel(sql_type = Nullable<BigInt>)]
    sum: Option<i64>,
}

/// The sum of `size_bytes` across every stored copy (original plus any converted sizes) of every
/// `Media` item `user_id` owns -- what `User.media_storage_bytes_used` reports. Raw SQL (rather
/// than loading every `Media` row into Rust and summing there) so Postgres does the aggregation,
/// using `idx_media_user_id_created_at`, without shipping full `Media` rows over the wire just to
/// sum one field out of each.
pub fn media_storage_bytes_used(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i64> {
    // Postgres' `SUM(bigint)` aggregate returns `numeric` (to avoid silent overflow), not
    // `bigint` -- without the explicit `::bigint` cast back, Diesel's `BigInt` deserializer
    // chokes on the wider `numeric` wire format ("Received more than 8 bytes while decoding an
    // i64").
    let row: SumRow = sql_query(
        "SELECT SUM((entry->>'size_bytes')::bigint)::bigint AS sum \
         FROM media, jsonb_array_elements(media.sizes) AS entry \
         WHERE media.user_id = $1",
    )
    .bind::<BigInt, _>(user_id)
    .get_result(conn)?;
    Ok(row.sum.unwrap_or(0))
}

pub fn update_media_storage_used(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<()> {
    let used = media_storage_bytes_used(user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(user_id))
        .set(users::media_storage_bytes_used.eq(used))
        .execute(conn)?;
    Ok(())
}

pub fn follower_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = follows::table
        .filter(follows::target_user_id.eq(user_id))
        .filter(follows::target_user_moderation.eq_any(PASSING_MODERATIONS))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

pub fn following_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = follows::table
        .filter(follows::user_id.eq(user_id))
        .filter(follows::target_user_moderation.eq_any(PASSING_MODERATIONS))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

/// Users `user_id` mutually follows -- a passing `Follow` from `user_id` to them, and a passing
/// `Follow` from them back to `user_id`. Mirrors `get_users::get_friends`' definition of a
/// friend.
pub fn friend_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let (following, follower) = alias!(follows as friend_following, follows as friend_follower);
    let following_user_id = following.field(follows::user_id);
    let following_target_user_id = following.field(follows::target_user_id);
    let following_moderation = following.field(follows::target_user_moderation);
    let follower_user_id = follower.field(follows::user_id);
    let follower_target_user_id = follower.field(follows::target_user_id);
    let follower_moderation = follower.field(follows::target_user_moderation);

    let count: i64 = following
        .inner_join(
            follower.on(follower_user_id
                .eq(following_target_user_id)
                .and(follower_target_user_id.eq(following_user_id))),
        )
        .filter(following_user_id.eq(user_id))
        .filter(following_moderation.eq_any(PASSING_MODERATIONS))
        .filter(follower_moderation.eq_any(PASSING_MODERATIONS))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

pub fn group_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = memberships::table
        .filter(memberships::user_id.eq(user_id))
        .filter(memberships::group_moderation.eq_any(PASSING_MODERATIONS))
        .filter(memberships::user_moderation.eq_any(PASSING_MODERATIONS))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

/// Top-level `Post`s (`PostContext::Post`) authored by `user_id`. Excludes replies, events,
/// occasions -- see [`response_count`]/[`event_count`].
pub fn post_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = posts::table
        .filter(posts::user_id.eq(user_id))
        .filter(posts::context.eq("POST"))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

/// Replies (`PostContext::Reply`/`FederatedReply`) authored by `user_id`, to `Post`s, `Event`s,
/// or `Occasion`s.
pub fn response_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = posts::table
        .filter(posts::user_id.eq(user_id))
        .filter(posts::context.eq_any(["REPLY", "FEDERATED_REPLY"]))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

/// `Event`s owned by `user_id` (via their underlying Post's `user_id`). Joined through `posts`
/// rather than filtered by `posts::context.eq("EVENT")` directly, since `delete_event` only
/// deletes the `events` row -- an Event's underlying Post can outlive it.
pub fn event_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = events::table
        .inner_join(posts::table)
        .filter(posts::user_id.eq(user_id))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

/// `Occasion`s across all of `user_id`'s events. `occasions::user_id` is denormalized
/// (by DB trigger) from the Occasion's own Post's author -- see
/// `2026-07-30-170000_add_search_text_to_occasions` -- and always matches the parent
/// Event's author in this codebase.
pub fn occasion_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<i32> {
    let count: i64 = occasions::table
        .filter(occasions::user_id.eq(user_id))
        .count()
        .get_result(conn)?;
    Ok(count as i32)
}

/// Refreshes `following_count`/`friend_count` for `user_id` and `follower_count`/`friend_count`
/// for `target_user_id` -- the two users whose relationship a `Follow` create/update/delete
/// between them could have changed.
pub fn update_follow_counts(
    user_id: i64,
    target_user_id: i64,
    conn: &mut PgPooledConnection,
) -> QueryResult<()> {
    let following = following_count(user_id, conn)?;
    let user_friends = friend_count(user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(user_id))
        .set((
            users::following_count.eq(following),
            users::friend_count.eq(user_friends),
        ))
        .execute(conn)?;

    let follower = follower_count(target_user_id, conn)?;
    let target_friends = friend_count(target_user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(target_user_id))
        .set((
            users::follower_count.eq(follower),
            users::friend_count.eq(target_friends),
        ))
        .execute(conn)?;
    Ok(())
}

pub fn update_group_count(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<()> {
    let count = group_count(user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(user_id))
        .set(users::group_count.eq(count))
        .execute(conn)?;
    Ok(())
}

pub fn update_post_counts(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<()> {
    let posts = post_count(user_id, conn)?;
    let responses = response_count(user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(user_id))
        .set((
            users::post_count.eq(posts),
            users::response_count.eq(responses),
        ))
        .execute(conn)?;
    Ok(())
}

pub fn update_event_counts(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<()> {
    let events = event_count(user_id, conn)?;
    let occasions = occasion_count(user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(user_id))
        .set((
            users::event_count.eq(events),
            users::occasion_count.eq(occasions),
        ))
        .execute(conn)?;
    Ok(())
}

/// Recomputes and sets all 9 denormalized counters for `user_id` in one `UPDATE`. Used by
/// `bin/update_user_counts.rs`'s full sweep; the targeted `update_*` functions above are
/// preferred at individual RPC call sites since they only need to touch the counters a given
/// mutation could actually have affected.
pub fn update_all_counts(user_id: i64, conn: &mut PgPooledConnection) -> QueryResult<()> {
    let follower = follower_count(user_id, conn)?;
    let following = following_count(user_id, conn)?;
    let friends = friend_count(user_id, conn)?;
    let groups = group_count(user_id, conn)?;
    let posts = post_count(user_id, conn)?;
    let responses = response_count(user_id, conn)?;
    let events = event_count(user_id, conn)?;
    let occasions = occasion_count(user_id, conn)?;
    let media_storage_used = media_storage_bytes_used(user_id, conn)?;
    update(users::table)
        .filter(users::id.eq(user_id))
        .set((
            users::follower_count.eq(follower),
            users::following_count.eq(following),
            users::friend_count.eq(friends),
            users::group_count.eq(groups),
            users::post_count.eq(posts),
            users::response_count.eq(responses),
            users::event_count.eq(events),
            users::occasion_count.eq(occasions),
            users::media_storage_bytes_used.eq(media_storage_used),
        ))
        .execute(conn)?;
    Ok(())
}
