//! Verification codes for contact methods that don't belong to any account *yet* -- the first
//! phase of `CreateAccount` with a phone/email (see `CreateAccountRequest` in
//! `authentication.proto`, and `logic::contact_methods::contact_login`). One row per normalized
//! contact value (`tel:+1...` / `mailto:...`, emails lowercased); a fresh send overwrites it. Only
//! a hash of the code is stored (see `logic::contact_methods::contact_login::hash_code`).

use std::time::{Duration, SystemTime};

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::schema::{contact_verification_sends, pending_contact_verifications};

#[derive(Debug, Queryable, Identifiable, Clone)]
#[diesel(table_name = pending_contact_verifications)]
pub struct PendingContactVerification {
    pub id: i64,
    pub contact_value: String,
    pub code_hash: String,
    pub attempts: i32,
    pub created_at: SystemTime,
    pub sent_at: SystemTime,
}

fn db_error(what: &str, e: diesel::result::Error) -> Status {
    log::error!("Failed to {} pending contact verification: {:?}", what, e);
    Status::new(Code::Internal, "data_error")
}

pub fn find_pending_contact_verification(
    contact_value: &str,
    conn: &mut PgPooledConnection,
) -> Result<Option<PendingContactVerification>, Status> {
    pending_contact_verifications::table
        .filter(pending_contact_verifications::contact_value.eq(contact_value))
        .first::<PendingContactVerification>(conn)
        .optional()
        .map_err(|e| db_error("load", e))
}

/// Stores a freshly-sent code's hash for `contact_value`, replacing any previous one (attempts
/// reset to 0, `sent_at` = now).
pub fn upsert_pending_contact_verification(
    contact_value: &str,
    code_hash: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let now = SystemTime::now();
    insert_into(pending_contact_verifications::table)
        .values((
            pending_contact_verifications::contact_value.eq(contact_value),
            pending_contact_verifications::code_hash.eq(code_hash),
            pending_contact_verifications::attempts.eq(0),
            pending_contact_verifications::created_at.eq(now),
            pending_contact_verifications::sent_at.eq(now),
        ))
        .on_conflict(pending_contact_verifications::contact_value)
        .do_update()
        .set((
            pending_contact_verifications::code_hash.eq(code_hash),
            pending_contact_verifications::attempts.eq(0),
            pending_contact_verifications::sent_at.eq(now),
        ))
        .execute(conn)
        .map(|_| ())
        .map_err(|e| db_error("store", e))
}

pub fn set_pending_contact_verification_attempts(
    id: i64,
    attempts: i32,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    update(pending_contact_verifications::table.filter(pending_contact_verifications::id.eq(id)))
        .set(pending_contact_verifications::attempts.eq(attempts))
        .execute(conn)
        .map(|_| ())
        .map_err(|e| db_error("update", e))
}

pub fn delete_pending_contact_verification(
    contact_value: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    delete(
        pending_contact_verifications::table
            .filter(pending_contact_verifications::contact_value.eq(contact_value)),
    )
    .execute(conn)
    .map(|_| ())
    .map_err(|e| db_error("delete", e))
}

/// Records one actually-sent verification code in the `contact_verification_sends` ledger (see
/// that table's migration for why it's separate from the pending rows). `contact_value` is
/// lowercased so spelling can't dodge the per-contact cap.
pub fn record_contact_verification_send(
    contact_value: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    insert_into(contact_verification_sends::table)
        .values(contact_verification_sends::contact_value.eq(contact_value.to_lowercase()))
        .execute(conn)
        .map(|_| ())
        .map_err(|e| db_error("record send of", e))
}

/// How many codes (to any contact) were sent within the last `window`.
pub fn count_contact_verification_sends_within(
    window: Duration,
    conn: &mut PgPooledConnection,
) -> Result<i64, Status> {
    contact_verification_sends::table
        .filter(contact_verification_sends::sent_at.gt(SystemTime::now() - window))
        .count()
        .get_result::<i64>(conn)
        .map_err(|e| db_error("count sends of", e))
}

/// How many codes were sent to `contact_value` within the last `window`.
pub fn count_contact_verification_sends_to_within(
    contact_value: &str,
    window: Duration,
    conn: &mut PgPooledConnection,
) -> Result<i64, Status> {
    contact_verification_sends::table
        .filter(contact_verification_sends::contact_value.eq(contact_value.to_lowercase()))
        .filter(contact_verification_sends::sent_at.gt(SystemTime::now() - window))
        .count()
        .get_result::<i64>(conn)
        .map_err(|e| db_error("count sends to", e))
}

/// Deletes ledger rows older than `older_than` (the `delete_expired_tokens` job keeps an hour).
pub fn delete_old_contact_verification_sends(
    older_than: Duration,
    conn: &mut PgPooledConnection,
) -> Result<usize, Status> {
    delete(
        contact_verification_sends::table
            .filter(contact_verification_sends::sent_at.lt(SystemTime::now() - older_than)),
    )
    .execute(conn)
    .map_err(|e| db_error("delete old sends of", e))
}

/// Deletes rows whose code was sent more than `older_than` ago. Used by the
/// `delete_expired_tokens` job.
pub fn delete_expired_pending_contact_verifications(
    older_than: Duration,
    conn: &mut PgPooledConnection,
) -> Result<usize, Status> {
    delete(
        pending_contact_verifications::table
            .filter(pending_contact_verifications::sent_at.lt(SystemTime::now() - older_than)),
    )
    .execute(conn)
    .map_err(|e| db_error("delete expired", e))
}
