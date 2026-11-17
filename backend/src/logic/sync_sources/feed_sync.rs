//! Pulls items from a `SyncSource`'s RSS or Atom feed and upserts them into plain `posts` --
//! the flat counterpart to `event_sync`'s Event/Occasion handling. `feed-rs` parses both
//! formats (plus JSON Feed) into one unified `model::Feed`/`model::Entry` shape, so unlike
//! `event_sync` there's no format-specific branching here at all: whichever subscription URL is
//! configured, the fetched text goes through the same parse-and-upsert path.
//!
//! Each entry's own feed-assigned id (an Atom `id`, an RSS `guid`, or a hash `feed-rs` derives
//! from the item's link when neither is present) becomes that Post's `sync_source_uid`, matched
//! against `posts.sync_source_id`/`sync_source_uid` on every re-sync via
//! `idx_posts_sync_source_unique_non_recurring` (see migration
//! 2026-09-11-000000_move_sync_source_to_posts) -- a flat item has no recurrence concept, so
//! `sync_source_recurrence_anchor` is always left `NULL`, same as an Event's own series-level
//! Post.
//!
//! Unlike `event_sync`, a feed item that stops appearing is left alone entirely rather than
//! pruned -- RSS/Atom feeds are commonly truncated to their most recent N items by the
//! publisher, so "no longer in the feed" doesn't mean "was retracted" the way a missing iCal
//! occurrence does.

use std::collections::HashMap;
use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::{posts, sync_sources};

/// Fetches `source`'s RSS/Atom subscription URL over HTTP, then delegates to
/// [`sync_feed_text`]. Split out so specs can exercise the parsing/upserting logic against a
/// fixed feed string without any network access -- mirrors `event_sync::sync_source`/
/// `sync_source_text`.
pub fn sync_source_feed(source: &models::SyncSource, conn: &mut PgPooledConnection) -> Result<(), Status> {
    let url = feed_subscription_url(source)?;
    let feed_text = fetch_feed(source, url)?;
    sync_feed_text(source, &feed_text, conn)
}

/// See `event_sync::fetch_ics`'s doc comment -- same `block_in_place` requirement, since this is
/// also called from within Rocket's Tokio runtime in production but also directly from plain
/// `#[test]`s.
fn fetch_feed(source: &models::SyncSource, url: &str) -> Result<String, Status> {
    crate::init_crypto();
    let fetch = || {
        super::client_builder(source)
            .build()
            .and_then(|client| client.get(url).send())
            .and_then(|response| response.error_for_status())
            .map_err(|e| {
                log::error!("Failed to fetch feed from {}: {:?}", crate::logic::log_redaction::redact_url(&url), crate::logic::log_redaction::safe_error(&e));
                Status::new(Code::FailedPrecondition, "feed_fetch_failed")
            })?
            .text()
            .map_err(|e| {
                log::error!("Failed to read feed response body from {}: {:?}", crate::logic::log_redaction::redact_url(&url), crate::logic::log_redaction::safe_error(&e));
                Status::new(Code::FailedPrecondition, "feed_fetch_failed")
            })
    };

    if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(fetch)
    } else {
        fetch()
    }
}

fn feed_subscription_url(source: &models::SyncSource) -> Result<&str, Status> {
    source
        .configuration
        .get("rss_subscription_url")
        .or_else(|| source.configuration.get("atom_subscription_url"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "feed_url_required"))
}

pub fn sync_feed_text(
    source: &models::SyncSource,
    feed_text: &str,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let feed = feed_rs::parser::parse(feed_text.as_bytes()).map_err(|e| {
        log::error!("Failed to parse feed text: {:?}", crate::logic::log_redaction::safe_error(&e));
        Status::new(Code::FailedPrecondition, "feed_parse_failed")
    })?;

    let owner_user_id = source.user_id;
    let moderation = default_post_moderation(conn);

    let result = conn.transaction::<(), diesel::result::Error, _>(|conn| {
        // Every currently-synced Post's own feed id -> its post_id, via the same real, indexed
        // `posts.sync_source_uid` column `event_sync` uses (see the module doc comment).
        let existing_post_ids_by_uid: HashMap<String, i64> = posts::table
            .select((posts::sync_source_uid, posts::id))
            .filter(posts::sync_source_id.eq(source.id))
            .load::<(Option<String>, i64)>(conn)?
            .into_iter()
            .filter_map(|(uid, post_id)| uid.map(|uid| (uid, post_id)))
            .collect();

        for entry in &feed.entries {
            if entry.id.trim().is_empty() {
                continue;
            }
            let title = entry.title.as_ref().map(|t| t.content.clone());
            let content = entry_content(entry);
            let link = entry.links.first().map(|l| l.href.clone());

            match existing_post_ids_by_uid.get(&entry.id) {
                Some(&post_id) => sync_post_text(conn, post_id, &title, &content, &link)?,
                None => {
                    create_post_for_entry(conn, source.id, owner_user_id, &moderation, &entry.id, &title, &content, &link)?;
                }
            }
        }

        let post_count: i64 = posts::table
            .filter(posts::sync_source_id.eq(source.id))
            .count()
            .get_result(conn)?;

        diesel::update(sync_sources::table.filter(sync_sources::id.eq(source.id)))
            .set((
                sync_sources::last_synced_at.eq(SystemTime::now()),
                sync_sources::post_count.eq(post_count),
            ))
            .execute(conn)?;

        crate::logic::update_post_counts(owner_user_id, conn)?;

        Ok(())
    });

    result.map_err(|e| {
        log::error!("Failed to sync SyncSource {}: {:?}", source.id, crate::logic::log_redaction::safe_error(&e));
        Status::new(Code::Internal, "failed_to_sync_source")
    })
}

/// Prefers the entry's full `content`, falling back to its `summary` -- mirrors `feed-rs`'s own
/// doc comment on `Entry.summary` (RSS in particular often only has a `description`, which
/// `feed-rs` surfaces as `summary` not `content`).
fn entry_content(entry: &feed_rs::model::Entry) -> Option<String> {
    entry
        .content
        .as_ref()
        .and_then(|c| c.body.clone())
        .or_else(|| entry.summary.as_ref().map(|s| s.content.clone()))
}

fn default_post_moderation(conn: &mut PgPooledConnection) -> String {
    crate::rpcs::get_server_configuration_proto(conn)
        .map(
            |c| match c.post_settings.unwrap_or_default().default_moderation() {
                Moderation::Pending => Moderation::Pending.as_str_name(),
                _ => Moderation::Unmoderated.as_str_name(),
            },
        )
        .unwrap_or_else(|_| Moderation::Unmoderated.as_str_name())
        .to_string()
}

fn create_post_for_entry(
    conn: &mut PgPooledConnection,
    source_id: i64,
    owner_user_id: i64,
    moderation: &str,
    uid: &str,
    title: &Option<String>,
    content: &Option<String>,
    link: &Option<String>,
) -> Result<(), diesel::result::Error> {
    let post = insert_into(posts::table)
        .values(&models::NewPost {
            user_id: Some(owner_user_id),
            parent_post_id: None,
            title: title.clone(),
            link: link.clone(),
            content: content.clone(),
            visibility: Visibility::GlobalPublic.to_string_visibility(),
            context: PostContext::Post.to_string_post_context(),
            moderation: moderation.to_string(),
            media: vec![],
        })
        .returning(models::POST_COLUMNS)
        .get_result::<models::Post>(conn)?;

    // See `event_sync::create_event_for_group`'s comment on why this is a follow-up UPDATE
    // rather than fields on `NewPost` itself. `sync_source_recurrence_anchor` is left `NULL` --
    // a flat feed item has no recurrence concept -- which is exactly what
    // `idx_posts_sync_source_unique_non_recurring` (rather than the recurring-only index) exists
    // to still guard against duplicates for.
    diesel::update(posts::table.filter(posts::id.eq(post.id)))
        .set((
            posts::sync_source_id.eq(Some(source_id)),
            posts::sync_source_uid.eq(Some(uid)),
        ))
        .execute(conn)?;

    Ok(())
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
