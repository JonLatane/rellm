use std::collections::HashMap;
use std::time::SystemTime;

use super::{ToDbId, ToProtoAuthor, ToProtoId, ToProtoTime};
use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::*;

pub type SyncSourceLookup = HashMap<i64, MarshalableSyncSource>;

/// Loads every `SyncSource` in `sync_source_ids` (deduplicated by the caller's `HashMap`), for
/// batch-attaching `Post.sync_source` across a whole page of results in one query instead of one
/// per Post -- mirrors `load_post_sync_lookup`/`load_occasion_sync_lookup` for
/// `SyncDestination`s.
pub fn load_sync_source_lookup(
    sync_source_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Option<SyncSourceLookup> {
    Some(
        models::get_sync_sources_by_ids(sync_source_ids, conn)
            .into_iter()
            .map(|(source, owner)| (source.id, MarshalableSyncSource(source, owner)))
            .collect::<SyncSourceLookup>(),
    )
}

pub trait FindSyncSource {
    fn find_sync_source(&self, id: i64) -> Option<&MarshalableSyncSource>;
}

impl FindSyncSource for Option<&SyncSourceLookup> {
    fn find_sync_source(&self, id: i64) -> Option<&MarshalableSyncSource> {
        self.map(|lookup| lookup.get(&id)).flatten()
    }
}

#[derive(Debug, Clone)]
pub struct MarshalableSyncSource(pub models::SyncSource, pub models::Author);

pub trait ToProtoMarshalableSyncSource {
    fn to_proto(&self) -> SyncSource;
}

impl ToProtoMarshalableSyncSource for MarshalableSyncSource {
    fn to_proto(&self) -> SyncSource {
        let source = &self.0;
        let owner = &self.1;
        SyncSource {
            id: source.id.to_proto_id(),
            owner: Some(owner.to_proto(None)),
            sync_interval_seconds: source.sync_interval_seconds as u64,
            created_at: Some(source.created_at.to_proto()),
            updated_at: source.updated_at.map(|t| t.to_proto()),
            last_synced_at: source.last_synced_at.map(|t| t.to_proto()),
            event_count: source.event_count as u64,
            occasion_count: source.occasion_count as u64,
            post_count: source.post_count as u64,
            configuration: source_configuration_to_proto(&source.configuration),
        }
    }
}

/// `configuration` JSONB shape today: one of `{"ics_subscription_url": "https://..."}`,
/// `{"rss_subscription_url": "https://..."}`, or `{"atom_subscription_url": "https://..."}` --
/// mirrors the proto `oneof`'s 3 variants (an ICS URL syncs Events/Occasions;
/// RSS/Atom sync plain Posts -- see `logic::sync_sources::feed_sync`).
pub fn source_configuration_to_proto(
    configuration: &serde_json::Value,
) -> Option<sync_source::Configuration> {
    if let Some(url) = configuration.get("ics_subscription_url").and_then(|v| v.as_str()) {
        return Some(sync_source::Configuration::IcsSubscriptionUrl(url.to_string()));
    }
    if let Some(url) = configuration.get("rss_subscription_url").and_then(|v| v.as_str()) {
        return Some(sync_source::Configuration::RssSubscriptionUrl(url.to_string()));
    }
    if let Some(url) = configuration.get("atom_subscription_url").and_then(|v| v.as_str()) {
        return Some(sync_source::Configuration::AtomSubscriptionUrl(url.to_string()));
    }
    None
}

pub fn source_configuration_to_json(
    configuration: &Option<sync_source::Configuration>,
) -> serde_json::Value {
    match configuration {
        Some(sync_source::Configuration::IcsSubscriptionUrl(url)) => {
            serde_json::json!({ "ics_subscription_url": url })
        }
        Some(sync_source::Configuration::RssSubscriptionUrl(url)) => {
            serde_json::json!({ "rss_subscription_url": url })
        }
        Some(sync_source::Configuration::AtomSubscriptionUrl(url)) => {
            serde_json::json!({ "atom_subscription_url": url })
        }
        None => serde_json::json!({}),
    }
}

/// Which permission gates creating/updating a `SyncSource` with this `configuration` -- one of
/// `SyncEventsFromIcs`/`SyncPostsFromRss`/`SyncPostsFromAtom` (see `permissions.proto`), matching
/// whichever `oneof` variant is set. Falls back to `SyncEventsFromIcs` for `None` (mirrors
/// `source_configuration_to_json`'s own `None` fallback, and matches `create_sync_source`'s
/// existing behavior before RSS/Atom sources existed).
pub fn required_sync_source_permission(configuration: &Option<sync_source::Configuration>) -> Permission {
    match configuration {
        Some(sync_source::Configuration::RssSubscriptionUrl(_)) => Permission::SyncPostsFromRss,
        Some(sync_source::Configuration::AtomSubscriptionUrl(_)) => Permission::SyncPostsFromAtom,
        _ => Permission::SyncEventsFromIcs,
    }
}

#[derive(Debug, Clone)]
pub struct MarshalableSyncDestination(pub models::SyncDestination, pub models::Author);

pub trait ToProtoMarshalableSyncDestination {
    fn to_proto(&self) -> SyncDestination;
}

impl ToProtoMarshalableSyncDestination for MarshalableSyncDestination {
    fn to_proto(&self) -> SyncDestination {
        let destination = &self.0;
        let owner = &self.1;
        SyncDestination {
            id: destination.id.to_proto_id(),
            owner: Some(owner.to_proto(None)),
            created_at: Some(destination.created_at.to_proto()),
            updated_at: destination.updated_at.map(|t| t.to_proto()),
            // Left unset here -- see `attach_synced_counts`, which every RPC handler that returns
            // a `SyncDestination` calls as a second pass to fill these in (mirrors
            // `get_events.rs`'s "build the response, then attach_occasion_rsvps"
            // shape), rather than every caller of `to_proto` having to supply it up front.
            synced_occasion_count: None,
            synced_post_count: None,
            configuration: destination_configuration_to_proto(&destination.configuration),
        }
    }
}

/// Second-pass attach step for `synced_occasion_count`/`synced_post_count` -- batches two
/// `GROUP BY` queries (`models::get_sync_destination_synced_counts`/
/// `models::get_post_sync_destination_synced_counts`) across every destination in `destinations`
/// and mutates each in place, rather than each RPC handler querying per-row. Works the same for a
/// single freshly created/updated destination (pass a one-element slice, e.g. via
/// `std::slice::from_mut`) as it does for a whole `GetSyncDestinations` page.
pub fn attach_synced_counts(destinations: &mut [SyncDestination], conn: &mut PgPooledConnection) {
    let ids: Vec<i64> = destinations
        .iter()
        .filter_map(|d| d.id.to_db_id().ok())
        .collect();
    let occasion_counts = models::get_sync_destination_synced_counts(ids.clone(), conn);
    let post_counts = models::get_post_sync_destination_synced_counts(ids, conn);
    for destination in destinations.iter_mut() {
        if let Ok(id) = destination.id.to_db_id() {
            destination.synced_occasion_count =
                Some(occasion_counts.get(&id).copied().unwrap_or(0) as u64);
            destination.synced_post_count = Some(post_counts.get(&id).copied().unwrap_or(0) as u64);
        }
    }
}

/// `configuration` JSONB shape today, one top-level tagged key per platform (mirroring the proto
/// `oneof`'s variants): `{"facebook_page": {"page_id", "page_name", "access_token"}}`,
/// `{"instagram_account": {"instagram_business_account_id", "username", "page_id",
/// "access_token"}}` (the linked Page's long-lived token, reused for Instagram posting too),
/// `{"mastodon_account": {"instance_host", "username", "access_token"}}`, `{"bluesky_account":
/// {"handle", "did", "app_password"}}`, `{"x_twitter_account": {"x_user_id", "username",
/// "access_token", "refresh_token", "expires_at"}}`. The secret field in each (`access_token`/
/// `app_password`/`refresh_token`) is intentionally never
/// surfaced back here; it's server-side only (see `logic::sync_destinations::facebook_sync`/`logic::sync_destinations::mastodon_sync`/
/// `logic::sync_destinations::bluesky_sync`/`logic::sync_destinations::x_twitter_sync`).
pub fn destination_configuration_to_proto(
    configuration: &serde_json::Value,
) -> Option<sync_destination::Configuration> {
    if let Some(facebook_page) = configuration.get("facebook_page") {
        let page_id = facebook_page.get("page_id").and_then(|v| v.as_str())?;
        let page_name = facebook_page
            .get("page_name")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        return Some(sync_destination::Configuration::FacebookPage(FacebookPage {
            page_id: page_id.to_string(),
            page_name: page_name.to_string(),
            short_lived_user_access_token: None,
        }));
    }
    if let Some(instagram_account) = configuration.get("instagram_account") {
        let instagram_business_account_id = instagram_account
            .get("instagram_business_account_id")
            .and_then(|v| v.as_str())?;
        let username = instagram_account
            .get("username")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let page_id = instagram_account
            .get("page_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        return Some(sync_destination::Configuration::InstagramAccount(
            InstagramAccount {
                instagram_business_account_id: instagram_business_account_id.to_string(),
                username: username.to_string(),
                page_id: page_id.to_string(),
                short_lived_user_access_token: None,
            },
        ));
    }
    if let Some(mastodon_account) = configuration.get("mastodon_account") {
        let instance_host = mastodon_account
            .get("instance_host")
            .and_then(|v| v.as_str())?;
        let username = mastodon_account
            .get("username")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        return Some(sync_destination::Configuration::MastodonAccount(
            MastodonAccount {
                instance_host: instance_host.to_string(),
                username: username.to_string(),
                access_token: None,
            },
        ));
    }
    if let Some(bluesky_account) = configuration.get("bluesky_account") {
        let handle = bluesky_account.get("handle").and_then(|v| v.as_str())?;
        let did = bluesky_account
            .get("did")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        return Some(sync_destination::Configuration::BlueskyAccount(
            BlueskyAccount {
                handle: handle.to_string(),
                did: did.to_string(),
                app_password: None,
            },
        ));
    }
    if let Some(x_twitter_account) = configuration.get("x_twitter_account") {
        let x_user_id = x_twitter_account.get("x_user_id").and_then(|v| v.as_str())?;
        let username = x_twitter_account
            .get("username")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        return Some(sync_destination::Configuration::XTwitterAccount(
            XTwitterAccount {
                username: username.to_string(),
                x_user_id: x_user_id.to_string(),
                // Never echoed back -- the stored `access_token`/`refresh_token` are server-side
                // only, same omission pattern as every other platform's secret field.
                authorization_code: None,
                code_verifier: None,
            },
        ));
    }
    if let Some(threads_account) = configuration.get("threads_account") {
        let threads_user_id = threads_account
            .get("threads_user_id")
            .and_then(|v| v.as_str())?;
        let username = threads_account
            .get("username")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        return Some(sync_destination::Configuration::ThreadsAccount(
            ThreadsAccount {
                threads_user_id: threads_user_id.to_string(),
                username: username.to_string(),
                // Never echoed back -- the stored `access_token` is server-side only, same
                // omission pattern as every other platform's secret field.
                authorization_code: None,
            },
        ));
    }
    None
}

/// Shared field-mapping for a single piece of content's (`Occasion` or `Post`) sync status
/// against one `SyncDestination` -- both `models::OccasionSyncDestination` and
/// `models::PostSyncDestination` have identical shape (just `occasion_id`/`post_id`
/// differs, which isn't even part of the output message), so this is the one place that maps
/// either into the shared `SyncDestinationStatus` proto.
pub fn to_proto_sync_destination_status(
    sync_destination_id: i64,
    destination_instance_id: Option<String>,
    destination_url: Option<String>,
    synced_at: Option<SystemTime>,
) -> SyncDestinationStatus {
    SyncDestinationStatus {
        sync_destination_id: sync_destination_id.to_proto_id(),
        destination_instance_id,
        destination_url,
        synced_at: synced_at.map(|t| t.to_proto()),
    }
}

pub trait ToProtoSyncDestinationStatus {
    fn to_proto(&self) -> SyncDestinationStatus;
}

impl ToProtoSyncDestinationStatus for models::OccasionSyncDestination {
    fn to_proto(&self) -> SyncDestinationStatus {
        to_proto_sync_destination_status(
            self.sync_destination_id,
            self.destination_instance_id.clone(),
            self.destination_url.clone(),
            self.synced_at,
        )
    }
}

impl ToProtoSyncDestinationStatus for models::PostSyncDestination {
    fn to_proto(&self) -> SyncDestinationStatus {
        to_proto_sync_destination_status(
            self.sync_destination_id,
            self.destination_instance_id.clone(),
            self.destination_url.clone(),
            self.synced_at,
        )
    }
}
