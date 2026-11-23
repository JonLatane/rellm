//! Rellm Subdomains (`PURCHASE_TYPE_SUBDOMAIN`): `bullcity.social/jon` is also served as
//! `jon.bullcity.social`, by the same Rocket and Tonic servers as the parent -- a "virtual server" scoped
//! to one user. This module resolves a request's `Host` to that user's subscription and derives everything
//! the scoped RPCs/pages need from it (the visible authors, the virtual `ServerConfiguration`, the
//! stylesheet). See `SubdomainSettings` in `server_configuration.proto`.

use std::time::SystemTime;

use diesel::dsl::sql;
use diesel::sql_types::{Bool, Text};
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{public_string_visibilities, subscription_state};
use crate::marshaling::{ToProtoId, ToProtoPurchaseType, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use crate::schema::market_subscriptions;

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

/// Forgets every cached resolution -- called wherever a subscription's settings, state or label change in this
/// process (save, cancel, checkout, lapse). Other processes catch up within the cache's TTL.
pub fn invalidate_cache() {
    if let Ok(mut resolved) = RESOLVED.lock() {
        resolved.clear();
    }
}

/// Specs share one process and each rewrites subscriptions and server configuration inside a rolled-back
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

/// An active subdomain, resolved from a request's host.
#[derive(Clone, Debug)]
pub struct SubdomainContext {
    pub subscription: models::MarketSubscription,
    /// The subdomain's owner (the subscription's buyer).
    pub owner: models::User,
    /// The subscription's settings, `custom_css_configuration.custom_css` included.
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

/// The active (not canceled-and-lapsed) `PURCHASE_TYPE_SUBDOMAIN` subscription holding `label`.
pub fn find_active_subdomain_subscription(
    label: &str,
    conn: &mut PgPooledConnection,
) -> Result<Option<models::MarketSubscription>, Status> {
    let candidates = market_subscriptions::table
        .filter(market_subscriptions::product_type.eq(PurchaseType::Subdomain.to_string_purchase_type()))
        .filter(market_subscriptions::service_terminated_at.is_null())
        .filter(sql::<Bool>("market_subscriptions.details #>> '{settings,subdomain}' = ").bind::<Text, _>(label.to_string()))
        .load::<models::MarketSubscription>(conn)
        .map_err(|e| {
            log::error!("Failed to look up a subdomain: {:?}", e);
            Status::new(Code::Internal, "failed_to_load_subscriptions")
        })?;
    let now = SystemTime::now();
    Ok(candidates.into_iter().find(|s| {
        subscription_state(s.canceled_at, s.renews_at, s.service_terminated_at, now)
            != MarketSubscriptionState::SubscriptionCanceled
    }))
}

/// Whether `buyer` may start a (new) subdomain subscription: their username is a valid label, nobody holds it, and
/// they don't already hold an in-force subdomain subscription of their own (resuming a canceled-but-paid-up one is
/// `MakeMarketPurchase`'s resume path, which never gets here). Returns the label. A label whose holder has canceled
/// and run out of paid time is free even if the renewal job hasn't terminated it yet -- see
/// `release_lapsed_subdomain_labels`, which the webhook runs before inserting.
pub fn validate_label_available(buyer: &models::User, conn: &mut PgPooledConnection) -> Result<String, Status> {
    let label = label_for_username(&buyer.username);
    if !is_valid_label(&label) {
        return Err(Status::new(Code::FailedPrecondition, "username_not_a_valid_subdomain"));
    }
    // A user named like the CDN's backend host (`backend` on rellm.org, whose backend is backend.rellm.org) may not
    // take it: that name is the real backend, not theirs.
    let cdn = get_server_configuration_proto(conn)?.external_cdn_config.unwrap_or_default();
    if label_reserved_by_cdn(&label, &cdn.frontend_host, &cdn.backend_host) {
        return Err(Status::new(Code::FailedPrecondition, "subdomain_reserved"));
    }
    if let Some(existing) = find_active_subdomain_subscription(&label, conn)? {
        return Err(if existing.buyer_id == buyer.id {
            Status::new(Code::FailedPrecondition, "already_subscribed")
        } else {
            Status::new(Code::FailedPrecondition, "subdomain_taken")
        });
    }
    // One in-force subdomain per buyer -- also what lets `SaveMarketSubscription` take an empty id.
    let now = SystemTime::now();
    let holds_another = models::get_market_subscriptions_for_buyer(buyer.id, conn)?.into_iter().any(|s| {
        s.product_type.to_owned().to_proto_purchase_type() == Some(PurchaseType::Subdomain)
            && subscription_state(s.canceled_at, s.renews_at, s.service_terminated_at, now)
                != MarketSubscriptionState::SubscriptionCanceled
    });
    if holds_another {
        return Err(Status::new(Code::FailedPrecondition, "already_subscribed"));
    }
    Ok(label)
}

/// Marks as terminated every subdomain subscription holding `label` whose buyer canceled and whose paid-for period
/// has run out -- exactly what `renew_market_subscriptions` does a little later. Frees the label for the unique
/// index (`idx_market_subscriptions_subdomain_label`, which only counts rows with no `service_terminated_at`) when a
/// new buyer's paid checkout arrives before that job has run.
pub fn release_lapsed_subdomain_labels(label: &str, conn: &mut PgPooledConnection) -> Result<(), Status> {
    diesel::update(
        market_subscriptions::table
            .filter(market_subscriptions::product_type.eq(PurchaseType::Subdomain.to_string_purchase_type()))
            .filter(market_subscriptions::service_terminated_at.is_null())
            .filter(market_subscriptions::canceled_at.is_not_null())
            .filter(sql::<Bool>("market_subscriptions.details #>> '{settings,subdomain}' = ").bind::<Text, _>(label.to_string()))
            .filter(sql::<Bool>(
                "GREATEST(market_subscriptions.canceled_at, COALESCE(market_subscriptions.renews_at, market_subscriptions.canceled_at)) <= clock_timestamp()",
            )),
    )
    .set(market_subscriptions::service_terminated_at.eq(Some(SystemTime::now())))
    .execute(conn)
    .map(|_| invalidate_cache())
    .map_err(|e| {
        log::error!("Failed to release a lapsed subdomain label: {:?}", e);
        Status::new(Code::Internal, "failed_to_release_subdomain")
    })
}

/// `market_subscriptions.details` for a brand-new subdomain subscription owned by `owner`.
pub fn new_subscription_details_json(owner: &models::User) -> serde_json::Value {
    serde_json::to_value(SubdomainSubscriptionDetails {
        settings: Some(SubdomainSettings {
            subdomain_of: owner.id.to_proto_id(),
            subdomain: label_for_username(&owner.username),
            ..Default::default()
        }),
        fulfillment_status: FulfillmentStatus::Fulfilled as i32,
        ..Default::default()
    })
    .unwrap_or_default()
}

/// `market_purchases.details` (a `SubdomainPurchaseDetails`) for `label`.
pub fn subdomain_purchase_details_json_for_label(label: &str) -> serde_json::Value {
    serde_json::to_value(SubdomainPurchaseDetails { subdomain: label.to_string() }).unwrap_or_default()
}

/// The `SubdomainPurchaseDetails` for a renewal, from the subscription's own details.
pub fn subdomain_purchase_details_json(subscription_details: &serde_json::Value) -> serde_json::Value {
    let label = serde_json::from_value::<SubdomainSubscriptionDetails>(subscription_details.clone())
        .ok()
        .and_then(|d| d.settings)
        .map(|s| s.subdomain)
        .unwrap_or_default();
    subdomain_purchase_details_json_for_label(&label)
}

/// A subscription's `SubdomainSettings` (empty if its details don't parse).
pub fn settings_of(subscription: &models::MarketSubscription) -> SubdomainSettings {
    serde_json::from_value::<SubdomainSubscriptionDetails>(subscription.details.clone())
        .ok()
        .and_then(|d| d.settings)
        .unwrap_or_default()
}

/// Resolves `host` (a request's `Host`/`:authority`) to the subdomain it addresses, if any: the parent
/// server's `ExternalCDNConfig.frontend_host` must be configured, `host` must be one label beneath it, and an
/// active `PURCHASE_TYPE_SUBDOMAIN` subscription must hold that label. Everything else is `Ok(None)` -- the
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
    // server it is for, and the parent and a subdomain are never confused even though they share a backend.
    let Some(label) = subdomain_label_for_request_host(host, &frontend_host, &backend_host) else {
        // The parent itself, or a host that isn't one label beneath it: no database work at all.
        return Ok(None);
    };
    if cache_enabled() {
        if let Some(cached) = RESOLVED.lock().ok().and_then(|c| c.get(&label, now)) {
            return Ok(cached);
        }
    }
    let resolved = match find_active_subdomain_subscription(&label, conn)? {
        Some(subscription) => {
            let owner = models::get_user(subscription.buyer_id, conn)?;
            let settings = settings_of(&subscription);
            Some(SubdomainContext { subscription, owner, settings })
        }
        None => None,
    };
    if cache_enabled() {
        if let Ok(mut cache) = RESOLVED.lock() {
            cache.put(label, resolved.clone(), now);
        }
    }
    Ok(resolved)
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
                cdn.frontend_host = format!("{}.{}", self.settings.subdomain, cdn.frontend_host);
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
