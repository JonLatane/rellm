use std::time::SystemTime;

use diesel::*;
use diesel_derive_enum::DbEnum;
use serde::{Deserialize, Serialize};
use tonic::{Code, Status};

use super::User;
use crate::db_connection::PgPooledConnection;
use crate::schema::{message_reads, message_recipients, messages, messaging_groups};

/// The canonical conversation between a set of participants -- every [`Message`] belongs to
/// exactly one. `sorted_user_ids` excludes Bcc'd recipients (see [`MessageRecipient`],
/// [`RecipientType::Bcc`]) since they're invisible to the group's other members by design; a
/// message with no local To/Cc recipients (e.g. a purely Bcc'd or fully-external-recipient email)
/// lands in the `[]` group rather than one of its own.
#[derive(Debug, Queryable, Identifiable, Clone)]
#[diesel(table_name = messaging_groups)]
pub struct MessagingGroup {
    pub id: i64,
    /// Ascending, deduplicated participant user ids. Diesel reports Postgres arrays as
    /// nullable-element regardless of the column's own nullability (mirroring
    /// `post_models::Post::media`), but application code never stores a NULL element.
    pub sorted_user_ids: Vec<Option<i64>>,
    pub created_at: SystemTime,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = messaging_groups)]
pub struct NewMessagingGroup {
    pub sorted_user_ids: Vec<i64>,
}

#[derive(Debug, Queryable, Identifiable, Associations, Clone)]
#[diesel(belongs_to(MessagingGroup))]
#[diesel(table_name = messages)]
pub struct Message {
    pub id: i64,
    pub from_user_id: Option<i64>,
    pub subject: Option<String>,
    pub body_text: Option<String>,
    pub email_headers: Option<serde_json::Value>,
    pub email_message_id: Option<String>,
    pub email_object_storage_path: Option<String>,
    pub created_at: SystemTime,
    pub messaging_group_id: i64,
}

impl Message {
    /// Typed view of `email_headers`. Falls back to an empty (all-default) [`EmailHeaders`] if
    /// the column is unset or somehow holds something that doesn't parse.
    pub fn email_headers(&self) -> EmailHeaders {
        self.email_headers
            .as_ref()
            .and_then(|headers| serde_json::from_value(headers.clone()).ok())
            .unwrap_or_default()
    }
}

/// Explicit column list for `messages`, excluding `search_text` -- a denormalized tsvector used
/// only for full-text search filtering/indexing, it has no corresponding field on `Message` since
/// it's never read back into application code (mirroring `post_models::POST_COLUMNS`).
pub const MESSAGE_COLUMNS: (
    messages::id,
    messages::from_user_id,
    messages::subject,
    messages::body_text,
    messages::email_headers,
    messages::email_message_id,
    messages::email_object_storage_path,
    messages::created_at,
    messages::messaging_group_id,
) = (
    messages::id,
    messages::from_user_id,
    messages::subject,
    messages::body_text,
    messages::email_headers,
    messages::email_message_id,
    messages::email_object_storage_path,
    messages::created_at,
    messages::messaging_group_id,
);

#[derive(Debug, Insertable)]
#[diesel(table_name = messages)]
pub struct NewMessage {
    /// The sender for an in-app `SendMessage`. Always `None` for inbound email -- see `Message`'s
    /// own doc comment above.
    pub from_user_id: Option<i64>,
    pub subject: Option<String>,
    pub body_text: Option<String>,
    pub email_headers: Option<serde_json::Value>,
    pub email_message_id: Option<String>,
    pub email_object_storage_path: Option<String>,
    pub messaging_group_id: i64,
}

/// Finds the [`MessagingGroup`] for a given participant set, creating it if it doesn't exist yet.
/// `user_ids` need not be sorted or deduplicated -- that's normalized here, once, so callers can't
/// accidentally create two group rows for the same set in a different order.
///
/// Tries the insert first rather than checking existence up front (same "optimistic insert, fall
/// back to a select on unique violation" pattern used for `messages.email_message_id`) since group
/// reuse -- not creation -- is the common case once a conversation has more than one message.
///
/// The insert runs in its own `conn.transaction(...)` so a unique violation there can't poison a
/// transaction this function was called from (diesel nests via `SAVEPOINT` when one's already
/// open - e.g. a caller's own `conn.transaction(...)`, or `test_transaction` in specs). Without
/// this, Postgres aborts the whole enclosing transaction on the failed `INSERT`, and the fallback
/// `SELECT` below fails too ("current transaction is aborted, commands ignored until end of
/// transaction block") instead of returning the existing group's id.
pub fn find_or_create_messaging_group(
    mut user_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Result<i64, Status> {
    user_ids.sort_unstable();
    user_ids.dedup();

    let inserted = conn.transaction::<i64, diesel::result::Error, _>(|conn| {
        insert_into(messaging_groups::table)
            .values(&NewMessagingGroup {
                sorted_user_ids: user_ids.clone(),
            })
            .returning(messaging_groups::id)
            .get_result::<i64>(conn)
    });

    match inserted {
        Ok(id) => Ok(id),
        Err(diesel::result::Error::DatabaseError(
            diesel::result::DatabaseErrorKind::UniqueViolation,
            _,
        )) => messaging_groups::table
            .select(messaging_groups::id)
            .filter(messaging_groups::sorted_user_ids.eq(&user_ids))
            .first::<i64>(conn)
            .map_err(|_| Status::new(Code::Internal, "error_creating_messaging_group")),
        Err(_) => Err(Status::new(
            Code::Internal,
            "error_creating_messaging_group",
        )),
    }
}

/// `Message.email_headers`' typed shape. Address fields hold raw `To`/`Cc`/`Bcc`/`From` header
/// values (e.g. `"Jon Latané <jon@jonline.io>"`), not just bare addresses, since that's what's
/// useful to render without re-parsing the MIME blob in object storage. `date`/`message_id`/`x_mailer` are
/// backend-only for now (not surfaced on the `Message` proto -- `subject` already is, as its own
/// top-level field, so it has no counterpart here). New fields are all `Option`/default-on-missing
/// so existing stored rows (JSONB, no migration) still deserialize fine without them.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct EmailHeaders {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub to: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub cc: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub bcc: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub message_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub x_mailer: Option<String>,
}

/// Which envelope field a [`MessageRecipient`] was addressed through, backed by the Postgres
/// `recipient_type` enum (see 2026-08-02-120000_create_messages). `Direct` is for future in-app
/// messages that aren't email at all (see `messages.from_user_id`); the `/email` endpoint only
/// ever produces `To`/`Cc`/`Bcc`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, DbEnum)]
#[ExistingTypePath = "crate::schema::sql_types::RecipientType"]
pub enum RecipientType {
    To,
    Cc,
    Bcc,
    Direct,
}

#[derive(Debug, Queryable, Identifiable, Associations, Clone)]
#[diesel(belongs_to(Message))]
#[diesel(belongs_to(User))]
#[diesel(table_name = message_recipients)]
pub struct MessageRecipient {
    pub id: i64,
    pub message_id: i64,
    pub user_id: i64,
    pub recipient_type: RecipientType,
    pub created_at: SystemTime,
}

#[derive(Debug, Insertable)]
#[diesel(table_name = message_recipients)]
pub struct NewMessageRecipient {
    pub message_id: i64,
    pub user_id: i64,
    pub recipient_type: RecipientType,
}

/// One row per (message, user) once that user has read that [`Message`] -- absence of a row means
/// unread. Backs `Message.current_user_read`/`MarkMessageReadRequest` (see
/// protos/messages.proto), read/written for the *authenticated caller's own* user id only --
/// there's no notion of marking a message read on someone else's behalf. Composite primary key
/// (no separate id column), same reasoning as `models::OccasionSyncDestination` (see
/// 2026-08-09-205953_create_event_sync_destinations): a user can only ever have one read record
/// per Message, so there's nothing an extra surrogate key would let us express.
#[derive(Debug, Queryable, Identifiable, Associations, Clone)]
#[diesel(belongs_to(Message))]
#[diesel(belongs_to(User))]
#[diesel(table_name = message_reads)]
#[diesel(primary_key(message_id, user_id))]
pub struct MessageRead {
    pub message_id: i64,
    pub user_id: i64,
    pub read_at: SystemTime,
}

/// Also doubles as the changeset for "mark read" upserts (`mark_messages_read`, via `AsChangeset`)
/// -- `read_at` is always written fresh (rather than preserved across a re-mark), so there's no
/// separate changeset struct needed.
#[derive(Debug, Insertable, AsChangeset)]
#[diesel(table_name = message_reads)]
pub struct NewMessageRead {
    pub message_id: i64,
    pub user_id: i64,
    pub read_at: SystemTime,
}
