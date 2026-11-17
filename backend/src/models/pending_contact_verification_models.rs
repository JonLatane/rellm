//! Verification codes for contact methods that don't belong to any account *yet* -- the first
//! phase of `CreateAccount` with a phone/email (see `CreateAccountRequest` in
//! `authentication.proto`, and `logic::contact_methods::contact_login`). One row per normalized
//! contact value (`tel:+1...` / `mailto:...`, emails lowercased); a fresh send overwrites it. Only
//! a hash of the code is stored (see `logic::contact_methods::contact_login::hash_code`).

use std::time::{Duration, SystemTime};

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::schema::{contact_consents, contact_verification_sends, pending_contact_verifications};

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
    log::error!(
        "Failed to {} pending contact verification: {}",
        what,
        crate::logic::safe_db_error(&e)
    );
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

/// Puts back a row exactly as it was (`code_hash`/`attempts`/`sent_at`) -- the undo of a failed
/// reservation that had overwritten it.
pub fn restore_pending_contact_verification(
    previous: &PendingContactVerification,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    update(
        pending_contact_verifications::table
            .filter(pending_contact_verifications::contact_value.eq(&previous.contact_value)),
    )
    .set((
        pending_contact_verifications::code_hash.eq(&previous.code_hash),
        pending_contact_verifications::attempts.eq(previous.attempts),
        pending_contact_verifications::sent_at.eq(previous.sent_at),
    ))
    .execute(conn)
    .map(|_| ())
    .map_err(|e| db_error("restore", e))
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

/// The sign-up / sign-in form a `contact_consents` row was given on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConsentFlow {
    CreateAccount,
    Login,
}

impl ConsentFlow {
    pub fn as_str(self) -> &'static str {
        match self {
            ConsentFlow::CreateAccount => "create_account",
            ConsentFlow::Login => "login",
        }
    }
}

#[derive(Debug, Queryable, Clone)]
#[diesel(table_name = contact_consents)]
pub struct ContactConsentRecord {
    pub id: i64,
    pub contact_value: String,
    pub flow: String,
    pub user_id: Option<i64>,
    pub consented_at: SystemTime,
}

/// Appends a `contact_consents` row: the person using the `flow` form consented to be messaged at
/// `contact_value` (stored lowercased, like the send ledger) as of `at`. `user_id` if the account is
/// known.
pub fn record_contact_consent(
    contact_value: &str,
    flow: ConsentFlow,
    user_id: Option<i64>,
    at: SystemTime,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    insert_into(contact_consents::table)
        .values((
            contact_consents::contact_value.eq(contact_value.to_lowercase()),
            contact_consents::flow.eq(flow.as_str()),
            contact_consents::user_id.eq(user_id),
            // The app's clock, like `pending_contact_verifications.created_at`, so the two compare.
            contact_consents::consented_at.eq(at),
        ))
        .execute(conn)
        .map(|_| ())
        .map_err(|e| db_error("record consent for", e))
}

/// Ties a just-created account to the sign-up consents recorded for `contact_value` by the attempt it
/// just completed: rows still without an account that were given at or after `since` (when that
/// attempt's pending verification was created). Older unlinked rows -- e.g. orphaned when an earlier
/// account of this contact was deleted -- belong to someone else and are left alone.
pub fn link_signup_consents_to_user(
    contact_value: &str,
    since: SystemTime,
    user_id: i64,
    conn: &mut diesel::PgConnection,
) -> QueryResult<usize> {
    update(
        contact_consents::table
            .filter(contact_consents::contact_value.eq(contact_value.to_lowercase()))
            .filter(contact_consents::flow.eq(ConsentFlow::CreateAccount.as_str()))
            .filter(contact_consents::user_id.is_null())
            .filter(contact_consents::consented_at.ge(since)),
    )
    .set(contact_consents::user_id.eq(user_id))
    .execute(conn)
}

/// When the most recent `flow` consent for `contact_value` was given: for a sign-up, the rows still
/// without an account given at/after `since` (the attempt's pending verification); for a sign-in,
/// `user_id`'s rows. Used to copy the *time consent was actually given* onto the account's
/// `ContactMethod.consent_history`, rather than the (later) moment the sign-up/sign-in completed.
pub fn latest_contact_consent_at(
    contact_value: &str,
    flow: ConsentFlow,
    user_id: Option<i64>,
    since: Option<SystemTime>,
    conn: &mut PgPooledConnection,
) -> Option<SystemTime> {
    let mut query = contact_consents::table
        .filter(contact_consents::contact_value.eq(contact_value.to_lowercase()))
        .filter(contact_consents::flow.eq(flow.as_str()))
        .into_boxed();
    query = match user_id {
        Some(id) => query.filter(contact_consents::user_id.eq(id)),
        None => query.filter(contact_consents::user_id.is_null()),
    };
    if let Some(since) = since {
        query = query.filter(contact_consents::consented_at.ge(since));
    }
    query
        .select(diesel::dsl::max(contact_consents::consented_at))
        .first::<Option<SystemTime>>(conn)
        .ok()
        .flatten()
}

/// The sign-in consent recorded when the code that was sent at `code_sent_at` (a
/// `ContactMethodVerification.verification_started_at`, which only has whole seconds) was reserved --
/// `None` if that code was sent without the checkbox. Ties the consent time copied onto the account
/// to the code being redeemed rather than to some earlier sign-in attempt.
pub fn login_consent_for_code(
    contact_value: &str,
    user_id: i64,
    code_sent_at: SystemTime,
    conn: &mut PgPooledConnection,
) -> Option<SystemTime> {
    let secs = code_sent_at
        .duration_since(SystemTime::UNIX_EPOCH)
        .ok()?
        .as_secs();
    let from = SystemTime::UNIX_EPOCH + Duration::from_secs(secs);
    contact_consents::table
        .filter(contact_consents::contact_value.eq(contact_value.to_lowercase()))
        .filter(contact_consents::flow.eq(ConsentFlow::Login.as_str()))
        .filter(contact_consents::user_id.eq(user_id))
        .filter(contact_consents::consented_at.ge(from))
        .filter(contact_consents::consented_at.lt(from + Duration::from_secs(1)))
        .select(diesel::dsl::max(contact_consents::consented_at))
        .first::<Option<SystemTime>>(conn)
        .ok()
        .flatten()
}
