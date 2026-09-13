use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::schema::{follows, users};

pub fn get_user(user_id: i64, conn: &mut PgPooledConnection) -> Result<User, Status> {
    users::table
        .select(USER_COLUMNS)
        .filter(users::id.eq(user_id))
        .first::<User>(conn)
        .map_err(|_| Status::new(Code::NotFound, "user_not_found"))
}
pub fn get_author(user_id: i64, conn: &mut PgPooledConnection) -> Result<Author, Status> {
    users::table
        .select(AUTHOR_COLUMNS)
        .filter(users::id.eq(user_id))
        .first::<Author>(conn)
        .map_err(|_| Status::new(Code::NotFound, "user_not_found"))
}

/// Batched variant of `get_author` -- every `Author` for `user_ids`, in one query. Used wherever a
/// batch-attach step (e.g. `marshaling::build_ai_models_for_users`) needs several users'
/// `Author`s at once instead of one `get_author` call per row.
pub fn get_authors(user_ids: &[i64], conn: &mut PgPooledConnection) -> Vec<Author> {
    if user_ids.is_empty() {
        return vec![];
    }
    users::table
        .select(AUTHOR_COLUMNS)
        .filter(users::id.eq_any(user_ids))
        .load::<Author>(conn)
        .unwrap_or_default()
}

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
// Diesel's `AsChangeset` otherwise skips `Option<T>` fields entirely (no `SET`
// clause at all) when they're `None`, rather than setting the column to
// `NULL` -- without this, `update_user.rs`'s `existing_user.avatar_media_id =
// None` (clearing a user's avatar) silently no-ops instead of persisting.
// Safe for every other `Option` field here (`email`, `phone`) too: every
// `.set(&existing_user)`/`.set(&user)` caller only ever reassigns fields it
// actually means to change, leaving the rest at whatever was just fetched --
// so a `None` reaching this changeset always means "actually `NULL` in the
// DB already", never "leave whatever's there alone".
#[diesel(treat_none_as_null = true)]
pub struct User {
    pub id: i64,
    pub username: String,
    pub password_salted_hash: String,
    pub real_name: String,
    pub email: Option<serde_json::Value>,
    pub phone: Option<serde_json::Value>,
    /// A serialized (by name) list of [crate::protos::Permission]s.
    pub permissions: serde_json::Value,
    pub avatar_media_id: Option<i64>,
    pub bio: String,
    pub visibility: String,
    pub moderation: String,
    pub default_follow_moderation: String,
    pub follower_count: i32,
    pub following_count: i32,
    pub group_count: i32,
    pub post_count: i32,
    pub event_count: i32,
    pub response_count: i32,
    pub created_at: SystemTime,
    pub updated_at: SystemTime,
    pub friend_count: i32,
    pub occasion_count: i32,
    pub media_storage_limit_bytes: Option<i64>,
    pub media_storage_bytes_used: i64,
}

/// Explicit column list for `users`, excluding `search_text` (a generated tsvector used only for
/// full-text search filtering/indexing - it has no corresponding field on `User` since it's never
/// read back into application code, mirroring `post_models::POST_COLUMNS`).
pub const USER_COLUMNS: (
    users::id,
    users::username,
    users::password_salted_hash,
    users::real_name,
    users::email,
    users::phone,
    users::permissions,
    users::avatar_media_id,
    users::bio,
    users::visibility,
    users::moderation,
    users::default_follow_moderation,
    users::follower_count,
    users::following_count,
    users::group_count,
    users::post_count,
    users::event_count,
    users::response_count,
    users::created_at,
    users::updated_at,
    users::friend_count,
    users::occasion_count,
    users::media_storage_limit_bytes,
    users::media_storage_bytes_used,
) = (
    users::id,
    users::username,
    users::password_salted_hash,
    users::real_name,
    users::email,
    users::phone,
    users::permissions,
    users::avatar_media_id,
    users::bio,
    users::visibility,
    users::moderation,
    users::default_follow_moderation,
    users::follower_count,
    users::following_count,
    users::group_count,
    users::post_count,
    users::event_count,
    users::response_count,
    users::created_at,
    users::updated_at,
    users::friend_count,
    users::occasion_count,
    users::media_storage_limit_bytes,
    users::media_storage_bytes_used,
);

pub const AUTHOR_COLUMNS: (
    users::id,
    users::username,
    users::avatar_media_id,
    users::real_name,
    users::permissions,
) = (
    users::id,
    users::username,
    users::avatar_media_id,
    users::real_name,
    users::permissions,
);

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(table_name = users)]
pub struct Author {
    pub id: i64,
    pub username: String,
    pub avatar_media_id: Option<i64>,
    pub real_name: String,
    pub permissions: serde_json::Value,
}

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
pub struct Follow {
    pub id: i64,
    pub user_id: i64,
    pub target_user_id: i64,
    pub target_user_moderation: String,
    pub created_at: SystemTime,
    pub updated_at: SystemTime,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = follows)]
pub struct NewFollow {
    pub user_id: i64,
    pub target_user_id: i64,
    pub target_user_moderation: String,
}
