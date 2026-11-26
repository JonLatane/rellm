//! Rellm Subdomains (`PURCHASE_TYPE_SUBDOMAIN`): `bullcity.social/jon` is also served as
//! `jon.bullcity.social`, by the same Rocket and Tonic servers as the parent -- a "virtual server" scoped
//! to one user. This module resolves a request's `Host` to that user and derives everything the scoped
//! RPCs/pages need from them (the visible authors, the virtual `ServerConfiguration`, the stylesheet). See
//! `SubdomainSettings` in `server_configuration.proto`.
//!
//! The label and settings live on the `users` row (`users.subdomain*`). A user's subdomain is *enabled* -- resolves --
//! while they hold an in-force `PURCHASE_TYPE_SUBDOMAIN` subscription **or** an admin enabled it for them
//! (`users.subdomain_granted_by_admin`, `SetUserSubdomain`); the label is claimed when it first becomes enabled and
//! released when it stops being (`release_label_if_not_enabled`).

use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{public_string_visibilities, subscription_state};
use crate::marshaling::{ToProtoId, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use crate::schema::{market_subscriptions, subdomain_frontend_hosts, users};

/// A tiny TTL map for the two things every subdomain-aware request would otherwise ask the database for: the
/// parent's `frontend_host`/`backend_host`, and which subscription (if any) a host resolves to. Entries expire
/// after `ttl`, and the map is bounded (`MAX_ENTRIES`; cleared when full -- the keys are request-controlled, so it
/// must never grow without limit). Pure -- the caller passes `now` -- so it is unit-testable.
pub struct TtlCache<V> {
    entries: std::collections::HashMap<String, (V, std::time::Instant)>,
    ttl: std::time::Duration,
}

impl<V: Clone> TtlCache<V> {
    pub const MAX_ENTRIES: usize = 1024;

    pub fn new(ttl: std::time::Duration) -> Self {
        TtlCache { entries: std::collections::HashMap::new(), ttl }
    }

    pub fn get(&self, key: &str, now: std::time::Instant) -> Option<V> {
        self.entries
            .get(key)
            .filter(|(_, stored_at)| now.saturating_duration_since(*stored_at) < self.ttl)
            .map(|(value, _)| value.clone())
    }

    pub fn put(&mut self, key: String, value: V, now: std::time::Instant) {
        if self.entries.len() >= Self::MAX_ENTRIES {
            self.entries.clear();
        }
        self.entries.insert(key, (value, now));
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }
}

lazy_static::lazy_static! {
    /// `(frontend_host, backend_host)` of the parent's `ExternalCDNConfig` -- changes only when an admin edits it.
    static ref CDN_HOSTS: std::sync::Mutex<TtlCache<(String, String)>> =
        std::sync::Mutex::new(TtlCache::new(std::time::Duration::from_secs(30)));
    /// Host -> resolved subdomain (`None` = a well-formed label nobody holds). Settings edited through *this*
    /// process invalidate it at once (`invalidate_cache`); another replica's edits show up within the TTL.
    static ref RESOLVED: std::sync::Mutex<TtlCache<Option<SubdomainContext>>> =
        std::sync::Mutex::new(TtlCache::new(std::time::Duration::from_secs(15)));
}

/// Forgets every cached resolution -- called wherever a user's settings, label or entitlement change in this
/// process (save, grant, cancel, checkout, lapse). Other processes catch up within the cache's TTL.
pub fn invalidate_cache() {
    if let Ok(mut resolved) = RESOLVED.lock() {
        resolved.clear();
    }
}

/// Specs share one process and each rewrites users and server configuration inside a rolled-back
/// transaction, so a process-wide cache would leak state between them: it is simply off under `cargo test`.
const fn cache_enabled() -> bool {
    !cfg!(test)
}

/// A request's host, as the Tonic layer saw it (`:authority`/`Host`) -- an extension on every Tonic
/// `Request` (see `servers::tonic::RequestHostLayer`).
#[derive(Clone, Debug)]
pub struct RequestHost(pub String);

/// Labels that must never be handed out as a subdomain (they'd shadow real infrastructure hosts).
const RESERVED_LABELS: &[&str] = &["www", "api", "admin", "mail", "smtp", "imap", "ftp", "cdn", "media", "static"];

/// An enabled subdomain, resolved from a request's host.
#[derive(Clone, Debug)]
pub struct SubdomainContext {
    /// The subdomain's owner.
    pub owner: models::User,
    /// The owner's settings, `custom_css_configuration.custom_css` included.
    pub settings: SubdomainSettings,
}

/// A username as a candidate DNS label (lower case) -- `None` if it can't be one (see `is_valid_label`).
pub fn label_for_username(username: &str) -> String {
    username.trim().to_ascii_lowercase()
}

/// `a-z`, `0-9` and inner `-`, 1-63 characters, not reserved.
pub fn is_valid_label(label: &str) -> bool {
    !label.is_empty()
        && label.len() <= 63
        && !label.starts_with('-')
        && !label.ends_with('-')
        && label.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        && !RESERVED_LABELS.contains(&label)
}

/// The subdomain label `host` addresses under `frontend_host`: `jon.bullcity.social` (any port) under
/// `bullcity.social` is `jon`. `None` for the parent host itself, for hosts that aren't a single label
/// beneath it, and for invalid labels.
pub fn subdomain_label_for_host(host: &str, frontend_host: &str) -> Option<String> {
    let host = strip_port(host).trim_end_matches('.').to_ascii_lowercase();
    let frontend_host = strip_port(frontend_host).trim_end_matches('.').to_ascii_lowercase();
    if frontend_host.is_empty() {
        return None;
    }
    let label = host.strip_suffix(&format!(".{frontend_host}"))?;
    is_valid_label(label).then(|| label.to_string())
}

/// `host` as compared against configured hosts: no port, no trailing dot, lower case.
fn normalize_host(host: &str) -> String {
    strip_port(host).trim_end_matches('.').to_ascii_lowercase()
}

/// Whether `label` is spoken for by the CDN setup itself. With a Cloudflare-style frontend/backend split
/// (`frontend_host = rellm.org`, `backend_host = backend.rellm.org`), the backend is *itself* one label beneath the
/// frontend, so `backend` must never be a user's subdomain -- it would shadow the real backend host. True when
/// `<label>.<frontend_host>` is the configured `backend_host`.
pub fn label_reserved_by_cdn(label: &str, frontend_host: &str, backend_host: &str) -> bool {
    let (frontend_host, backend_host) = (normalize_host(frontend_host), normalize_host(backend_host));
    !frontend_host.is_empty() && !backend_host.is_empty() && format!("{label}.{frontend_host}") == backend_host
}

/// The subdomain label a request for `host` means, given the parent's configured `frontend_host`/`backend_host`:
/// `<label>.<frontend_host>` (pages) or `<label>.<backend_host>` (gRPC). `None` for everything else -- crucially the
/// configured frontend and backend hosts *themselves* (the backend of a CDN setup can sit one label under the
/// frontend, `backend.rellm.org`, and is the parent server, not a subdomain), and any label the CDN setup reserves
/// (`label_reserved_by_cdn`).
pub fn subdomain_label_for_request_host(host: &str, frontend_host: &str, backend_host: &str) -> Option<String> {
    let bare = normalize_host(host);
    if bare == normalize_host(frontend_host) || (!backend_host.is_empty() && bare == normalize_host(backend_host)) {
        return None;
    }
    let label = subdomain_label_for_host(host, frontend_host)
        .or_else(|| subdomain_label_for_host(host, backend_host))?;
    (!label_reserved_by_cdn(&label, frontend_host, backend_host)).then_some(label)
}

fn strip_port(host: &str) -> &str {
    // IPv6 literals ("[::1]:80") never match a frontend_host anyway.
    match host.rsplit_once(':') {
        Some((name, port)) if !name.contains(':') && port.bytes().all(|b| b.is_ascii_digit()) => name,
        _ => host,
    }
}

fn internal(what: &'static str, code: &'static str) -> impl Fn(diesel::result::Error) -> Status {
    move |e| {
        log::error!("{}: {:?}", what, crate::logic::log_redaction::safe_error(&e));
        Status::new(Code::Internal, code)
    }
}

/// Whether `subscription` is still in force: not terminated, and not canceled with its paid period run out.
fn subscription_in_force(s: &models::MarketSubscription, now: SystemTime) -> bool {
    s.service_terminated_at.is_none()
        && subscription_state(s.canceled_at, s.renews_at, s.service_terminated_at, now)
            != MarketSubscriptionState::SubscriptionCanceled
}

/// The ids among `user_ids` that hold an in-force `PURCHASE_TYPE_SUBDOMAIN` subscription -- one query (an index probe
/// on `buyer_id`), however many users are asked about.
pub fn subscribed_user_ids(
    user_ids: &[i64],
    conn: &mut PgPooledConnection,
) -> Result<std::collections::HashSet<i64>, Status> {
    let candidates = market_subscriptions::table
        .filter(market_subscriptions::buyer_id.eq_any(user_ids))
        .filter(market_subscriptions::product_type.eq(PurchaseType::Subdomain.to_string_purchase_type()))
        .filter(market_subscriptions::service_terminated_at.is_null())
        .load::<models::MarketSubscription>(conn)
        .map_err(internal("Failed to look up subdomain subscriptions", "failed_to_load_subscriptions"))?;
    let now = SystemTime::now();
    Ok(candidates.iter().filter(|s| subscription_in_force(s, now)).map(|s| s.buyer_id).collect())
}

/// Whether `user_id` holds an in-force `PURCHASE_TYPE_SUBDOMAIN` subscription.
pub fn has_subscription(user_id: i64, conn: &mut PgPooledConnection) -> Result<bool, Status> {
    Ok(subscribed_user_ids(&[user_id], conn)?.contains(&user_id))
}

/// Whether the user's subdomain is enabled: an admin granted it, or a subscription is in force.
pub fn is_enabled(
    summary: &models::UserSubdomainSummary,
    conn: &mut PgPooledConnection,
) -> Result<bool, Status> {
    Ok(summary.subdomain_granted_by_admin || has_subscription(summary.id, conn)?)
}

/// `UserSubdomain` for the profile -- the settings (no stylesheet), and why the subdomain is (not) enabled.
pub fn user_subdomain_proto(
    summary: &models::UserSubdomainSummary,
    subscribed: bool,
    frontend_host: Option<String>,
) -> UserSubdomain {
    UserSubdomain {
        settings: Some(settings_for(summary, None, frontend_host)),
        enabled: summary.subdomain_granted_by_admin || subscribed,
        subscribed,
        granted_by_admin: summary.subdomain_granted_by_admin,
    }
}

/// `SubdomainSettings` from a user's stored state. `custom_css` is the stored `CustomCSSConfiguration` JSON (None where
/// the text isn't wanted -- `User.subdomain`).
pub fn settings_for(
    summary: &models::UserSubdomainSummary,
    custom_css: Option<serde_json::Value>,
    frontend_host: Option<String>,
) -> SubdomainSettings {
    SubdomainSettings {
        subdomain_of: summary.subdomain.as_ref().map(|_| summary.id.to_proto_id()).unwrap_or_default(),
        subdomain: summary.subdomain.clone().unwrap_or_default(),
        share_content_from_followers: summary.subdomain_share_followers,
        share_content_from_following: summary.subdomain_share_following,
        share_content_from_friends: summary.subdomain_share_friends,
        custom_css_configuration: custom_css.and_then(|v| serde_json::from_value(v).ok()),
        custom_frontend_host: frontend_host,
    }
}

/// Whether `host` (already lower case, no port) is shaped like a registrable domain a user could own: at least two
/// labels of `a-z`, `0-9` and inner `-` (1-63 characters each, 253 in all) and a TLD that isn't all digits -- which
/// also rules out IP addresses, `localhost` and bare names. Says nothing about whether it may be a subdomain's host.
pub fn is_domain_like(host: &str) -> bool {
    let labels: Vec<&str> = host.split('.').collect();
    host.len() <= 253
        && labels.len() >= 2
        && labels.iter().all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        })
        && !labels.last().is_some_and(|tld| tld.bytes().all(|b| b.is_ascii_digit()))
}

/// Whether `host` is `parent` itself or anything beneath it (`a.b.parent`). False for an empty `parent`.
fn is_parent_or_beneath(host: &str, parent: &str) -> bool {
    let parent = normalize_host(parent);
    !parent.is_empty() && (host == parent || host.ends_with(&format!(".{parent}")))
}

/// A user's requested `custom_frontend_host` as it would be stored (trimmed, lower case), or the refusal: not a domain
/// (`invalid_frontend_host`), or the server's own `frontend_host`/`backend_host` or something beneath them
/// (`frontend_host_reserved` -- those are the parent's and its subdomains', and `<label>.<frontend_host>` already
/// serves every subdomain).
pub fn validate_custom_frontend_host(raw: &str, frontend_host: &str, backend_host: &str) -> Result<String, Status> {
    let host = raw.trim().to_ascii_lowercase();
    if !is_domain_like(&host) {
        return Err(Status::new(Code::InvalidArgument, "invalid_frontend_host"));
    }
    if is_parent_or_beneath(&host, frontend_host) || is_parent_or_beneath(&host, backend_host) {
        return Err(Status::new(Code::FailedPrecondition, "frontend_host_reserved"));
    }
    Ok(host)
}

/// Sets (or, with an empty `requested`, clears) `user`'s `custom_frontend_host`. Validates it, refuses one another user
/// holds whose subdomain is still enabled (`frontend_host_taken`) and takes it over from one whose subdomain no longer is
/// -- the same rule as labels. Setting what the user already has changes nothing and re-validates nothing, so a later
/// change to the CDN configuration can't make unrelated saves fail. All under the user's row lock; the unique index
/// the table's primary key backstops a race for the same domain.
pub fn set_custom_frontend_host(user: &models::User, requested: &str, conn: &mut PgPooledConnection) -> Result<(), Status> {
    in_transaction(conn, |conn| {
        lock_user_row(user.id, conn)?;
        let current = models::get_subdomain_frontend_host(user.id, conn)?;
        let wanted = if requested.trim().is_empty() {
            None
        } else {
            let cdn = get_server_configuration_proto(conn)?.external_cdn_config.unwrap_or_default();
            let host = validate_custom_frontend_host(requested, &cdn.frontend_host, &cdn.backend_host)?;
            if current.as_deref() == Some(host.as_str()) {
                return Ok(());
            }
            if let Some(holder) = models::get_user_by_subdomain_frontend_host(&host, conn)? {
                if holder.id != user.id {
                    let summary = models::get_subdomain_summary(holder.id, conn)?;
                    if is_enabled(&summary, conn)? {
                        return Err(Status::new(Code::FailedPrecondition, "frontend_host_taken"));
                    }
                    diesel::delete(subdomain_frontend_hosts::table.filter(subdomain_frontend_hosts::user_id.eq(holder.id)))
                        .execute(conn)
                        .map_err(internal("Failed to release a frontend host", "failed_to_update_user"))?;
                }
            }
            Some(host)
        };
        if current == wanted {
            return Ok(());
        }
        // A savepoint, so a lost race doesn't abort a surrounding transaction -- it is just a refusal.
        let saved = conn.transaction::<usize, diesel::result::Error, _>(|conn| {
            diesel::delete(subdomain_frontend_hosts::table.filter(subdomain_frontend_hosts::user_id.eq(user.id))).execute(conn)?;
            match &wanted {
                Some(host) => diesel::insert_into(subdomain_frontend_hosts::table)
                    .values((subdomain_frontend_hosts::host.eq(host), subdomain_frontend_hosts::user_id.eq(user.id)))
                    .execute(conn),
                None => Ok(0),
            }
        });
        match saved {
            Ok(_) => {
                invalidate_cache();
                Ok(())
            }
            Err(diesel::result::Error::DatabaseError(diesel::result::DatabaseErrorKind::UniqueViolation, _)) => {
                Err(Status::new(Code::FailedPrecondition, "frontend_host_taken"))
            }
            Err(e) => Err(internal("Failed to save a frontend host", "failed_to_update_user")(e)),
        }
    })
}

/// Whether `user` may hold the subdomain label their username makes, as far as the label itself goes: a valid DNS label,
/// not one the CDN setup uses, and not held by another user whose subdomain is still enabled. A holder that is no longer
/// entitled (canceled and run out, grant withdrawn) is released here, so the label is free for the new claimant even if
/// the renewal job hasn't cleaned up yet. Returns the label.
pub fn check_label_for(user: &models::User, conn: &mut PgPooledConnection) -> Result<String, Status> {
    let label = label_for_username(&user.username);
    if !is_valid_label(&label) {
        return Err(Status::new(Code::FailedPrecondition, "username_not_a_valid_subdomain"));
    }
    // A user named like the CDN's backend host (`backend` on rellm.org, whose backend is backend.rellm.org) may not
    // take it: that name is the real backend, not theirs.
    let cdn = get_server_configuration_proto(conn)?.external_cdn_config.unwrap_or_default();
    if label_reserved_by_cdn(&label, &cdn.frontend_host, &cdn.backend_host) {
        return Err(Status::new(Code::FailedPrecondition, "subdomain_reserved"));
    }
    if let Some(holder) = models::get_user_by_subdomain_label(&label, conn)? {
        if holder.id != user.id {
            let summary = models::get_subdomain_summary(holder.id, conn)?;
            if is_enabled(&summary, conn)? {
                return Err(Status::new(Code::FailedPrecondition, "subdomain_taken"));
            }
            release_label_if_not_enabled(holder.id, conn)?;
        }
    }
    Ok(label)
}

/// Whether `buyer` may start a (new) subdomain subscription: the label is theirs to take (`check_label_for`) and they
/// don't already hold an in-force subdomain subscription (resuming a canceled-but-paid-up one is `MakeMarketPurchase`'s
/// resume path, which never gets here). Returns the label.
pub fn validate_label_available(buyer: &models::User, conn: &mut PgPooledConnection) -> Result<String, Status> {
    let label = check_label_for(buyer, conn)?;
    if has_subscription(buyer.id, conn)? {
        return Err(Status::new(Code::FailedPrecondition, "already_subscribed"));
    }
    Ok(label)
}

/// `conn.transaction`'s error type must absorb Diesel's own errors (it rolls back through them) while carrying the
/// `Status` the steps inside return.
pub struct TxError(pub Status);

impl From<diesel::result::Error> for TxError {
    fn from(e: diesel::result::Error) -> Self {
        log::error!("Subdomain transaction failed: {:?}", crate::logic::log_redaction::safe_error(&e));
        TxError(Status::new(Code::Internal, "db_error"))
    }
}

impl From<Status> for TxError {
    fn from(status: Status) -> Self {
        TxError(status)
    }
}

/// Runs `f` in a transaction (a savepoint when already inside one), rolling back on a `Status` error.
pub fn in_transaction<T>(
    conn: &mut PgPooledConnection,
    f: impl FnOnce(&mut PgPooledConnection) -> Result<T, Status>,
) -> Result<T, Status> {
    conn.transaction::<T, TxError, _>(|conn| f(conn).map_err(TxError)).map_err(|e| e.0)
}

/// Locks `user_id`'s row (`SELECT ... FOR UPDATE`) until the surrounding transaction ends, so a grant, a claim and a
/// release for one user can't interleave. Callers must be inside a transaction (a savepoint inside one counts -- the lock
/// is held until the outermost commit).
pub fn lock_user_row(user_id: i64, conn: &mut PgPooledConnection) -> Result<(), Status> {
    users::table
        .filter(users::id.eq(user_id))
        .select(users::id)
        .for_update()
        .first::<i64>(conn)
        .map(|_| ())
        .map_err(|_| Status::new(Code::NotFound, "user_not_found"))
}

/// Reserves `user`'s label for them and returns it: the one they already hold (fixed once claimed -- a later rename
/// never invalidates it, so a renewal after a username change still works), else their lower-cased username if
/// `check_label_for` allows it. The caller has checked the subdomain is (about to be) enabled. A unique violation -- a
/// racing claimant got the label between `check_label_for` and here -- is `subdomain_taken`; `idx_users_subdomain` is the
/// backstop that makes the claim atomic.
pub fn claim_label(user: &models::User, conn: &mut PgPooledConnection) -> Result<String, Status> {
    in_transaction(conn, |conn| {
        lock_user_row(user.id, conn)?;
        let held = users::table
            .filter(users::id.eq(user.id))
            .select(users::subdomain)
            .first::<Option<String>>(conn)
            .map_err(|_| Status::new(Code::NotFound, "user_not_found"))?;
        if let Some(held) = held {
            return Ok(held);
        }
        let label = check_label_for(user, conn)?;
        // A savepoint, so a lost race doesn't abort a surrounding transaction (the webhook's) -- it is just a refusal.
        let claimed = conn.transaction::<usize, diesel::result::Error, _>(|conn| {
            diesel::update(users::table.filter(users::id.eq(user.id)).filter(users::subdomain.is_null()))
                .set(users::subdomain.eq(Some(label.clone())))
                .execute(conn)
        });
        match claimed {
            Ok(_) => {
                invalidate_cache();
                Ok(label)
            }
            Err(diesel::result::Error::DatabaseError(diesel::result::DatabaseErrorKind::UniqueViolation, _)) => {
                Err(Status::new(Code::FailedPrecondition, "subdomain_taken"))
            }
            Err(e) => Err(internal("Failed to claim a subdomain label", "failed_to_claim_subdomain")(e)),
        }
    })
}

/// Releases `user_id`'s label if their subdomain is no longer enabled -- no grant, no in-force subscription. Their
/// settings stay, so enabling it again brings the old theme and toggles back. Called wherever an entitlement can end
/// (a grant withdrawn, a subscription terminated) and for a label someone else wants (`check_label_for`). The decision
/// and the write happen under the user's row lock, so a grant or claim racing it can't have its label cleared.
pub fn release_label_if_not_enabled(user_id: i64, conn: &mut PgPooledConnection) -> Result<(), Status> {
    in_transaction(conn, |conn| {
        lock_user_row(user_id, conn)?;
        let summary = models::get_subdomain_summary(user_id, conn)?;
        if summary.subdomain.is_none() || is_enabled(&summary, conn)? {
            return Ok(());
        }
        diesel::update(users::table.filter(users::id.eq(user_id)))
            .set(users::subdomain.eq(None::<String>))
            .execute(conn)
            .map(|_| invalidate_cache())
            .map_err(internal("Failed to release a subdomain label", "failed_to_release_subdomain"))
    })
}

/// `market_subscriptions.details` for a brand-new subdomain subscription -- just the (automatic) fulfillment status; the
/// settings live on the user.
pub fn new_subscription_details_json() -> serde_json::Value {
    serde_json::to_value(SubdomainSubscriptionDetails {
        fulfillment_status: FulfillmentStatus::Fulfilled as i32,
        ..Default::default()
    })
    .unwrap_or_default()
}

/// `market_purchases.details` (a `SubdomainPurchaseDetails`) for `label`.
pub fn subdomain_purchase_details_json_for_label(label: &str) -> serde_json::Value {
    serde_json::to_value(SubdomainPurchaseDetails { subdomain: label.to_string() }).unwrap_or_default()
}

/// The `SubdomainPurchaseDetails` for a renewal: the label the subscription's buyer holds.
pub fn subdomain_purchase_details_json_for_buyer(
    buyer_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<serde_json::Value, Status> {
    let label = models::get_subdomain_summary(buyer_id, conn)?.subdomain.unwrap_or_default();
    Ok(subdomain_purchase_details_json_for_label(&label))
}

/// Resolves `host` (a request's `Host`/`:authority`) to the subdomain it addresses, if any: the parent
/// server's `ExternalCDNConfig.frontend_host` must be configured, `host` must be one label beneath it, and the user
/// holding that label must have their subdomain enabled (a subscription in force, or an admin's grant). Everything else is `Ok(None)` -- the
/// request is simply for the parent server.
pub fn resolve_subdomain(
    host: Option<&str>,
    conn: &mut PgPooledConnection,
) -> Result<Option<SubdomainContext>, Status> {
    let Some(host) = host else {
        return Ok(None);
    };
    let now = std::time::Instant::now();
    let cached_hosts = cache_enabled().then(|| CDN_HOSTS.lock().ok().and_then(|c| c.get("", now))).flatten();
    let (frontend_host, backend_host) = match cached_hosts {
        Some(hosts) => hosts,
        None => {
            let cdn = get_server_configuration_proto(conn)?.external_cdn_config.unwrap_or_default();
            let hosts = (cdn.frontend_host, cdn.backend_host);
            if cache_enabled() {
                if let Ok(mut cache) = CDN_HOSTS.lock() {
                    cache.put(String::new(), hosts.clone(), now);
                }
            }
            hosts
        }
    };
    // A subdomain is reached at `<label>.<frontend_host>` (pages) and, for gRPC when the backend is a separate host,
    // at `<label>.<backend_host>` (what `/backend_host` returns on a subdomain) -- so every request carries which
    // server it is for, and the parent and a subdomain are never confused even though they share a backend. Or at the
    // owner's own `custom_frontend_host`, for a host outside the parent's domains that looks like a domain at all.
    let lookup = match subdomain_label_for_request_host(host, &frontend_host, &backend_host) {
        Some(label) => Lookup::Label(label),
        None => {
            let bare = normalize_host(host);
            if is_parent_or_beneath(&bare, &frontend_host) || is_parent_or_beneath(&bare, &backend_host) || !is_domain_like(&bare) {
                // The parent itself, a host beneath it that isn't a held label, or something that can't be a custom domain
                // (an IP, `localhost`): no database work at all.
                return Ok(None);
            }
            Lookup::CustomHost(bare)
        }
    };
    let cache_key = match &lookup {
        Lookup::Label(label) => label.clone(),
        // Labels never contain a dot, so the two kinds of key can't collide.
        Lookup::CustomHost(host) => format!("host:{host}"),
    };
    if cache_enabled() {
        if let Some(cached) = RESOLVED.lock().ok().and_then(|c| c.get(&cache_key, now)) {
            return Ok(cached);
        }
    }
    let holder = match &lookup {
        Lookup::Label(label) => models::get_user_by_subdomain_label(label, conn)?,
        Lookup::CustomHost(host) => models::get_user_by_subdomain_frontend_host(host, conn)?,
    };
    let resolved = match holder {
        Some(owner) => {
            let summary = models::get_subdomain_summary(owner.id, conn)?;
            // A custom host only serves a subdomain whose label the user actually holds.
            if summary.subdomain.is_some() && is_enabled(&summary, conn)? {
                let css = models::get_subdomain_custom_css(owner.id, conn)?;
                Some(SubdomainContext { settings: settings_for(&summary, css, models::get_subdomain_frontend_host(owner.id, conn)?), owner })
            } else {
                None
            }
        }
        None => None,
    };
    if cache_enabled() {
        if let Ok(mut cache) = RESOLVED.lock() {
            cache.put(cache_key, resolved.clone(), now);
        }
    }
    Ok(resolved)
}

/// What a request's host asks for: a subdomain by label, or whoever set the host as their own frontend.
enum Lookup {
    Label(String),
    CustomHost(String),
}

impl SubdomainContext {
    /// Whose content `GetPosts`/`GetEvents` may show here: the owner plus -- per the `share_content_from_*` toggles --
    /// followers / people the owner follows / friends. Just a description: it is rendered as SQL subqueries against
    /// `follows` inside the feed query itself (`AuthorSet::sql_condition`), so a request never loads or ships the id
    /// lists -- the cost no longer grows with how many followers the owner has.
    pub fn author_set(&self) -> AuthorSet {
        AuthorSet {
            owner_id: self.owner.id,
            followers: self.settings.share_content_from_followers,
            following: self.settings.share_content_from_following,
            friends: self.settings.share_content_from_friends,
        }
    }

    /// The subdomain's own stylesheet configuration, `custom_css` text included (empty if never set) -- what
    /// `GetCustomCSS` and `/custom_css.css` serve on this host.
    pub fn custom_css_configuration(&self) -> CustomCssConfiguration {
        let mut css = self.settings.custom_css_configuration.clone().unwrap_or_default();
        css.custom_css = Some(css.custom_css.unwrap_or_default());
        css
    }

    /// The virtual `ServerConfiguration` `GetServerConfiguration` returns on this subdomain: the parent's
    /// configuration (CDN, contact integrations, permissions, ... are all shared) re-skinned for the owner --
    /// their name/bio instead of the server's, their stylesheet's settings, only the tabs that make sense for
    /// one user, and `subdomain_settings` set so clients can tell.
    pub fn virtual_server_configuration(
        &self,
        parent: ServerConfiguration,
        viewer: &Option<&models::User>,
    ) -> ServerConfiguration {
        let mut config = parent;
        let owner = &self.owner;
        // The owner's profile fields are only as public as their profile is (what `GetUsers` enforces): a `PRIVATE` or
        // `SERVER_PUBLIC` profile shows an anonymous visitor just the username -- which is the address itself.
        let profile_visible = viewer.is_some_and(|v| v.id == owner.id)
            || public_string_visibilities(viewer).contains(&owner.visibility);
        let display_name = if !profile_visible || owner.real_name.trim().is_empty() {
            owner.username.clone()
        } else {
            owner.real_name.clone()
        };
        let mut server_info = config.server_info.take().unwrap_or_default();
        server_info.name = Some(display_name);
        server_info.short_name = Some(owner.username.clone());
        server_info.description = profile_visible.then(|| owner.bio.clone());
        // The parent's logo/colors/policies describe the whole server, not this user.
        server_info.logo = None;
        server_info.colors = None;
        config.server_info = Some(server_info);

        // Only what is relevant to one user's site: no People/Groups/Market, no custom tab set.
        for settings in [config.people_settings.as_mut(), config.group_settings.as_mut()].into_iter().flatten() {
            settings.visible = false;
        }
        if let Some(market) = config.market_settings.as_mut() {
            market.enabled = false;
        }
        config.custom_tabs = Some(subdomain_tabs());
        config.federation_info = None;
        // Secrets/infrastructure of the parent are never shown on a subdomain, whoever is looking.
        config.cluster_resources = None;
        // Clients adopt `external_cdn_config.frontend_host` as the server's identity, so it must be the subdomain
        // itself -- not the parent's -- or the page would turn into the parent site. Likewise `backend_host`: gRPC
        // for a subdomain goes to `<label>.<backend_host>` (wildcard DNS/TLS on the backend domain, like the
        // frontend's), which is how the backend knows the request is for the subdomain and not the parent.
        if let Some(cdn) = config.external_cdn_config.as_mut() {
            if !cdn.frontend_host.is_empty() {
                cdn.frontend_host = match self.settings.custom_frontend_host.as_deref() {
                    // The owner's own domain is the site's identity; gRPC still goes to `<label>.<backend_host>` below.
                    Some(custom) if !custom.is_empty() => custom.to_string(),
                    _ => format!("{}.{}", self.settings.subdomain, cdn.frontend_host),
                };
            }
            if !cdn.backend_host.is_empty() {
                cdn.backend_host = format!("{}.{}", self.settings.subdomain, cdn.backend_host);
            }
        }
        config.twilio_config = None;
        config.bird_config = None;
        config.telnyx_config = None;
        config.stalwart_config = None;
        config.stripe_config = None;
        config.preferred_verification_apis = vec![];

        let mut css = self.settings.custom_css_configuration.clone().unwrap_or_default();
        css.custom_css = None;
        config.custom_css_configuration = Some(css);

        let mut settings = self.settings.clone();
        settings.subdomain_of = owner.id.to_proto_id();
        if let Some(css) = settings.custom_css_configuration.as_mut() {
            css.custom_css = None;
        }
        config.subdomain_settings = Some(settings);
        config
    }
}

/// The only nav tabs a subdomain shows -- everything that is about one user's content. People, Groups and Market
/// (and the per-server Home override) don't apply to a single user's site, so they are simply not listed.
fn subdomain_tabs() -> CustomNavigationTabSet {
    let tab = |tab: NavigationTab, emoji: &str, path: &str| CustomNavigationTab {
        target: Some(custom_navigation_tab::Target::Tab(tab as i32)),
        icon: Some(custom_navigation_tab::Icon::EmojiIcon(emoji.to_string())),
        title: None,
        path: path.to_string(),
    };
    CustomNavigationTabSet {
        home: None,
        tabs: vec![
            tab(NavigationTab::EventsTab, "📅", "events"),
            tab(NavigationTab::PostsTab, "📝", "posts"),
            tab(NavigationTab::MediaTab, "🎨", "media"),
            tab(NavigationTab::VideoTab, "🎥", "video"),
            tab(NavigationTab::AudioTab, "🎵", "audio"),
            tab(NavigationTab::AboutTab, "i", "about"),
        ],
        tab_style: NavigationTabStyle::NavigationTabIconOnly as i32,
    }
}

/// Which authors a subdomain's feeds show -- see `SubdomainContext::author_set`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AuthorSet {
    pub owner_id: i64,
    /// Users with an accepted follow *of* the owner.
    pub followers: bool,
    /// Users the owner has an accepted follow of.
    pub following: bool,
    /// Users who follow the owner *and* whom the owner follows back.
    pub friends: bool,
}

impl AuthorSet {
    /// A SQL boolean expression, true when `column` (an author id, e.g. `"posts.user_id"`) is in this set. Always
    /// includes the owner; each enabled toggle adds one `IN (subquery)` over `follows` (accepted follows only --
    /// `PASSING_MODERATIONS`). The only interpolated values are the owner's integer id and those constant moderation
    /// names, so there is nothing to inject; the subqueries use their own aliases (`sf`/`sg`) so they never collide
    /// with the `follows` join the post queries already have.
    pub fn sql_condition(&self, column: &str) -> String {
        let owner = self.owner_id;
        let passing = crate::rpcs::PASSING_MODERATIONS
            .iter()
            .map(|m| format!("'{m}'"))
            .collect::<Vec<_>>()
            .join(",");
        let mut conditions = vec![format!("{column} = {owner}")];
        if self.followers {
            conditions.push(format!(
                "{column} IN (SELECT sf.user_id FROM follows sf WHERE sf.target_user_id = {owner} \
                 AND sf.target_user_moderation IN ({passing}))"
            ));
        }
        if self.following {
            conditions.push(format!(
                "{column} IN (SELECT sf.target_user_id FROM follows sf WHERE sf.user_id = {owner} \
                 AND sf.target_user_moderation IN ({passing}))"
            ));
        }
        if self.friends {
            conditions.push(format!(
                "{column} IN (SELECT sf.user_id FROM follows sf WHERE sf.target_user_id = {owner} \
                 AND sf.target_user_moderation IN ({passing}) AND EXISTS (SELECT 1 FROM follows sg \
                 WHERE sg.user_id = {owner} AND sg.target_user_id = sf.user_id \
                 AND sg.target_user_moderation IN ({passing})))"
            ));
        }
        format!("({})", conditions.join(" OR "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn label_for_host() {
        assert_eq!(subdomain_label_for_host("jon.bullcity.social", "bullcity.social"), Some("jon".to_string()));
        assert_eq!(subdomain_label_for_host("Jon.BullCity.Social:8000", "bullcity.social"), Some("jon".to_string()));
        assert_eq!(subdomain_label_for_host("bullcity.social", "bullcity.social"), None);
        assert_eq!(subdomain_label_for_host("a.b.bullcity.social", "bullcity.social"), None);
        assert_eq!(subdomain_label_for_host("www.bullcity.social", "bullcity.social"), None);
        assert_eq!(subdomain_label_for_host("jon.other.social", "bullcity.social"), None);
        assert_eq!(subdomain_label_for_host("jon.bullcity.social", ""), None);
        assert_eq!(subdomain_label_for_host("notbullcity.social", "bullcity.social"), None);
    }

    #[test]
    fn subdomain_has_no_people_or_market_tabs() {
        let tabs = subdomain_tabs().tabs;
        let has = |t: NavigationTab| {
            tabs.iter().any(|x| x.target == Some(custom_navigation_tab::Target::Tab(t as i32)))
        };
        assert!(has(NavigationTab::EventsTab) && has(NavigationTab::PostsTab) && has(NavigationTab::AboutTab));
        assert!(!has(NavigationTab::PeopleTab) && !has(NavigationTab::MarketTab));
    }

    #[test]
    fn ttl_cache_expires_is_bounded_and_clears() {
        use std::time::{Duration, Instant};
        let start = Instant::now();
        let mut cache = TtlCache::new(Duration::from_secs(10));
        cache.put("jon".to_string(), 1, start);
        assert_eq!(cache.get("jon", start + Duration::from_secs(9)), Some(1));
        assert_eq!(cache.get("jon", start + Duration::from_secs(10)), None, "expired");
        assert_eq!(cache.get("other", start), None);
        cache.put("jon".to_string(), 2, start);
        cache.clear();
        assert_eq!(cache.get("jon", start), None, "cleared");
        // Bounded: request-controlled keys can't grow it without limit.
        for i in 0..(TtlCache::<i32>::MAX_ENTRIES + 5) {
            cache.put(format!("k{i}"), 0, start);
        }
        assert!(cache.entries.len() <= TtlCache::<i32>::MAX_ENTRIES);
    }

    #[test]
    fn the_cdn_backend_host_is_never_a_subdomain() {
        // rellm.org's setup: a Cloudflare frontend at rellm.org, the real backend at backend.rellm.org.
        let (frontend, backend) = ("rellm.org", "backend.rellm.org");
        let label = |host: &str| subdomain_label_for_request_host(host, frontend, backend);
        // The backend host is one label under the frontend -- and still the parent server.
        assert_eq!(label("backend.rellm.org"), None);
        assert_eq!(label("BACKEND.rellm.org:443"), None);
        assert_eq!(label("rellm.org"), None);
        assert_eq!(label("backend.backend.rellm.org"), None, "the reserved label can't be reached via the backend host either");
        // Real subdomains still resolve, on either host.
        assert_eq!(label("jon.rellm.org"), Some("jon".to_string()));
        assert_eq!(label("jon.backend.rellm.org"), Some("jon".to_string()));
        assert!(label_reserved_by_cdn("backend", frontend, backend));
        assert!(!label_reserved_by_cdn("jon", frontend, backend));
        // No CDN split configured: nothing is reserved.
        assert!(!label_reserved_by_cdn("backend", frontend, ""));
        assert_eq!(subdomain_label_for_request_host("jon.rellm.org", frontend, ""), Some("jon".to_string()));
        // A backend that isn't under the frontend reserves nothing.
        assert!(!label_reserved_by_cdn("backend", frontend, "rellm.org.itsj.online"));
        assert_eq!(
            subdomain_label_for_request_host("jon.rellm.org.itsj.online", frontend, "rellm.org.itsj.online"),
            Some("jon".to_string())
        );
    }

    #[test]
    fn valid_labels() {
        assert!(is_valid_label("jon"));
        assert!(is_valid_label("jon-1"));
        assert!(!is_valid_label("-jon"));
        assert!(!is_valid_label("jon_l"));
        assert!(!is_valid_label("jon.l"));
        assert!(!is_valid_label(""));
        assert!(!is_valid_label("admin"));
    }

    #[test]
    fn author_condition_has_one_subquery_per_enabled_toggle() {
        let set = |followers, following, friends| AuthorSet { owner_id: 7, followers, following, friends };
        let none = set(false, false, false).sql_condition("posts.user_id");
        assert_eq!(none, "(posts.user_id = 7)");
        assert_eq!(set(true, false, false).sql_condition("posts.user_id").matches("SELECT").count(), 1);
        assert_eq!(set(true, true, false).sql_condition("posts.user_id").matches("SELECT").count(), 2);
        let all = set(true, true, true).sql_condition("posts.user_id");
        assert_eq!(all.matches("IN (SELECT").count(), 3);
        // Friends are the intersection: a follower the owner follows back.
        assert!(all.contains("EXISTS (SELECT 1 FROM follows sg"));
        // Accepted follows only.
        assert!(all.contains("'UNMODERATED','APPROVED'"));
    }
}
