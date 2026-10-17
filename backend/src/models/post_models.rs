use std::time::SystemTime;

use super::{SyncDestination, User};
use diesel::*;
use diesel_derive_enum::DbEnum;
use tonic::{Code, Status};

use crate::{
    db_connection::PgPooledConnection,
    schema::{group_posts, post_sync_destinations, posts, user_posts},
};

/// The end-user layout a [`Post`]'s attached Media should be rendered in, backed by the Postgres
/// `post_media_layout` enum (see 2026-08-25-165450_add_post_media_layout_to_posts).
#[derive(Debug, Clone, Copy, PartialEq, Eq, DbEnum)]
#[ExistingTypePath = "crate::schema::sql_types::PostMediaLayout"]
pub enum PostMediaLayout {
    MediaLayoutStandard,
    MediaLayoutDynamicVerticalScroll,
}

pub fn get_post(post_id: i64, conn: &mut PgPooledConnection) -> Result<Post, Status> {
    posts::table
        .select(POST_COLUMNS)
        .filter(posts::id.eq(post_id))
        .first::<Post>(conn)
        .map_err(|_| Status::new(Code::NotFound, "post_not_found"))
}

pub fn get_group_post(
    group_id: i64,
    post_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<GroupPost, Status> {
    group_posts::table
        .select(group_posts::all_columns)
        .filter(group_posts::group_id.eq(group_id))
        .filter(group_posts::post_id.eq(post_id))
        .first::<GroupPost>(conn)
        .map_err(|_| Status::new(Code::NotFound, "group_post_not_found"))
}

// numeric_expr!(posts::unauthenticated_star_count);

#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(belongs_to(User))]
#[diesel(treat_none_as_null = true)]
pub struct Post {
    pub id: i64,
    pub user_id: Option<i64>,
    pub parent_post_id: Option<i64>,

    pub title: Option<String>,
    pub link: Option<String>,
    pub content: Option<String>,

    pub response_count: i32,
    pub reply_count: i32,
    pub group_count: i32,

    pub media: Vec<Option<i64>>,
    pub media_generated: bool,
    pub embed_link: bool,
    pub shareable: bool,

    pub context: String,
    pub visibility: String,
    pub moderation: String,

    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
    pub published_at: Option<SystemTime>,
    pub last_activity_at: SystemTime,

    pub unauthenticated_star_count: i64,

    pub post_media_layout: PostMediaLayout,

    /// The `SyncSource` this Post was created/is kept in sync from (an ICS Event/Occasion
    /// today; RSS/Atom items directly in the future), if any -- `None` for a plain, hand-created
    /// Post. See migration 2026-09-11-000000_move_sync_source_to_posts's doc comment for why this
    /// lives here rather than on `events`/`occasions`.
    pub sync_source_id: Option<i64>,
    /// The SyncSource's own stable identifier for this Post (an iCal `UID`, an RSS `guid`, an
    /// Atom `id`), scoped to `sync_source_id`.
    pub sync_source_uid: Option<String>,
    /// For a recurring Event's per-occurrence Occasion Post only: that occurrence's stable
    /// identity within its series (see `logic::sync_sources::event_sync`'s module doc comment).
    /// `None` for every other kind of synced Post (a plain synced Post, or an Event's own
    /// series-level Post).
    pub sync_source_recurrence_anchor: Option<SystemTime>,

    /// The Post this one quotes, if any. Only ever set on a `PostContext::Post` Post -- see
    /// `rpcs::posts::create_post`/`update_post`. Cleared (`ON DELETE SET NULL`) if the quoted
    /// Post is deleted.
    pub quoted_post_id: Option<i64>,
}

/// Explicit column list for `posts`, excluding:
/// - `search_text`, a denormalized tsvector used only for full-text search filtering/indexing -
///   it has no corresponding field on `Post` since it's never read back into application code,
///   and diesel_full_text_search's `TsVector` doesn't support being written from Rust via
///   `AsChangeset` anyway.
/// - `sort_published_at`, a `GENERATED ALWAYS AS (COALESCE(published_at, created_at)) STORED`
///   column GetPosts orders by (see 2026-07-27-215959_add_sort_published_at_to_posts). It's read
///   via `posts::sort_published_at` directly in `.order(...)` calls rather than through a `Post`
///   field - Postgres rejects any UPDATE/INSERT that names a generated column, and `Post` derives
///   `AsChangeset`, so giving it a field here would make every `.set(&existing_post)` call fail.
pub const POST_COLUMNS: (
    posts::id,
    posts::user_id,
    posts::parent_post_id,
    posts::title,
    posts::link,
    posts::content,
    posts::response_count,
    posts::reply_count,
    posts::group_count,
    posts::media,
    posts::media_generated,
    posts::embed_link,
    posts::shareable,
    posts::context,
    posts::visibility,
    posts::moderation,
    posts::created_at,
    posts::updated_at,
    posts::published_at,
    posts::last_activity_at,
    posts::unauthenticated_star_count,
    posts::post_media_layout,
    posts::sync_source_id,
    posts::sync_source_uid,
    posts::sync_source_recurrence_anchor,
    posts::quoted_post_id,
) = (
    posts::id,
    posts::user_id,
    posts::parent_post_id,
    posts::title,
    posts::link,
    posts::content,
    posts::response_count,
    posts::reply_count,
    posts::group_count,
    posts::media,
    posts::media_generated,
    posts::embed_link,
    posts::shareable,
    posts::context,
    posts::visibility,
    posts::moderation,
    posts::created_at,
    posts::updated_at,
    posts::published_at,
    posts::last_activity_at,
    posts::unauthenticated_star_count,
    posts::post_media_layout,
    posts::sync_source_id,
    posts::sync_source_uid,
    posts::sync_source_recurrence_anchor,
    posts::quoted_post_id,
);

#[derive(Debug, Insertable)]
#[diesel(table_name = posts)]
pub struct NewPost {
    pub user_id: Option<i64>,
    pub parent_post_id: Option<i64>,
    pub title: Option<String>,
    pub link: Option<String>,
    pub content: Option<String>,
    pub context: String,
    pub visibility: String,
    pub moderation: String,
    pub media: Vec<i64>,
    pub embed_link: bool,
}

#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(belongs_to(User))]
pub struct GroupPost {
    pub id: i64,
    pub group_id: i64,
    pub post_id: i64,
    pub user_id: i64,
    pub group_moderation: String,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
}
#[derive(Debug, Insertable)]
#[diesel(table_name = group_posts)]
pub struct NewGroupPost {
    pub group_id: i64,
    pub post_id: i64,
    pub user_id: i64,
    pub group_moderation: String,
}

#[derive(Debug, Queryable, Identifiable, AsChangeset)]
pub struct UserPost {
    pub id: i64,
    pub user_id: i64,
    pub post_id: i64,
    pub created_at: SystemTime,
    pub updated_at: Option<SystemTime>,
}
#[derive(Debug, Insertable)]
#[diesel(table_name = user_posts)]
pub struct NewUserPost {
    pub user_id: i64,
    pub post_id: i64,
}

/// A single Post's sync status against a single SyncDestination -- exact mirror of
/// `event_models::OccasionSyncDestination`, just for `Post`s instead of `Occasion`s.
/// Composite-keyed (no surrogate `id`), so it's `Identifiable` via both foreign keys rather than
/// one.
#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(table_name = post_sync_destinations)]
#[diesel(primary_key(post_id, sync_destination_id))]
#[diesel(belongs_to(Post))]
#[diesel(belongs_to(SyncDestination))]
pub struct PostSyncDestination {
    pub post_id: i64,
    pub sync_destination_id: i64,
    pub destination_instance_id: Option<String>,
    pub destination_url: Option<String>,
    pub synced_at: Option<SystemTime>,
    pub created_at: SystemTime,
}

#[derive(Debug, Insertable, AsChangeset)]
#[diesel(table_name = post_sync_destinations)]
pub struct NewPostSyncDestination {
    pub post_id: i64,
    pub sync_destination_id: i64,
    pub destination_instance_id: Option<String>,
    pub destination_url: Option<String>,
    pub synced_at: Option<SystemTime>,
}

/// Loads sync status rows for a set of Posts, keyed for `post_marshaling` to group by `post_id`.
pub fn get_post_sync_destinations(
    post_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Vec<PostSyncDestination> {
    if post_ids.is_empty() {
        return vec![];
    }
    post_sync_destinations::table
        .filter(post_sync_destinations::post_id.eq_any(post_ids))
        .load::<PostSyncDestination>(conn)
        .unwrap_or_default()
}
