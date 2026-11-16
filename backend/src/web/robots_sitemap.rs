use rocket::http::uri::Host;
use rocket::*;
use std::collections::HashSet;
use std::time::{Duration, SystemTime};

use super::RocketState;
use rocket::response::content::{RawJson, RawText, RawXml};

use rocket_cache_response::CacheResponse;

use crate::marshaling::ToProtoTime;
use crate::protos::{GetEventsRequest, GetPostsRequest, TimeFilter};
use crate::rpcs::{get_events_for, get_posts_for, get_server_configuration_proto};

// Mirrors `calendarLookbackDaysDefault` in the Elm SPA's `EventsPage.elm`, used when
// `EventSettings.calendar_lookback_days` is unset.
const DEFAULT_CALENDAR_LOOKBACK_DAYS: u32 = 14;

/// The sitemap's fixed URLs: the home and tab pages, plus any custom tab paths. A Rellm Subdomain (`is_subdomain`) has
/// no People page, and its tab list comes from its virtual configuration (see
/// `SubdomainContext::virtual_server_configuration`), so only pages that exist on it are listed.
pub fn base_sitemap_urls(
    domain: &str,
    configuration: &crate::protos::ServerConfiguration,
    is_subdomain: bool,
) -> Vec<String> {
    let mut urls = vec![
        format!("https://{}/", domain),
        format!("https://{}/posts", domain),
        format!("https://{}/events", domain),
    ];
    if !is_subdomain {
        urls.push(format!("https://{}/people", domain));
    }
    urls.extend([
        format!("https://{}/about", domain),
        format!("https://{}/about_rellm", domain),
        format!("https://{}/flutter", domain),
        format!("https://{}/tamagui", domain),
        format!("https://{}/elm", domain),
    ]);

    for tab in configuration
        .custom_tabs
        .as_ref()
        .map(|set| set.tabs.as_slice())
        .unwrap_or_default()
    {
        // Every tab's page is listed -- the reserved paths too (`media`/`video`/`audio`/... are real pages that were
        // never in the fixed list above); repeats are removed when the sitemap is assembled.
        if !tab.path.is_empty() {
            urls.push(format!("https://{}/{}", domain, tab.path));
        }
    }
    urls
}

/// The web app manifest for `configuration`'s server (or a subdomain's virtual one). Serialized with `serde_json`, so
/// names an owner chose themselves (backslashes, quotes, newlines) can never make it invalid JSON. The theme colour is
/// the primary colour's low 24 bits as exactly six hex digits -- the server's configured `ServerColors.primary` is an
/// ARGB `uint32`, and a configuration with no colour (every subdomain) falls back to the neutral `0x424242`.
pub fn build_manifest(configuration: &crate::protos::ServerConfiguration) -> String {
    let server_name = configuration
        .server_info
        .as_ref()
        .and_then(|i| i.name.clone())
        .unwrap_or_else(|| "Rellm".to_string());
    let server_short_name = configuration
        .server_info
        .as_ref()
        .and_then(|i| i.short_name.clone())
        .unwrap_or_else(|| server_name.clone());
    let primary_color_int = configuration
        .server_info
        .as_ref()
        .and_then(|i| i.colors.as_ref())
        .and_then(|c| c.primary)
        .unwrap_or(crate::logic::DEFAULT_PRIMARY_COLOR);
    let primary_color = format!("{:06x}", primary_color_int & 0x00FF_FFFF);

    let manifest = serde_json::json!({
        "name": server_name,
        "short_name": server_short_name,
        "theme_color": format!("#{primary_color}CC"),
        "background_color": format!("#{primary_color}"),
        "start_url": "/",
        "display": "standalone",
        "orientation": "portrait-primary",
        "icons": [{ "src": "/favicon.ico", "sizes": "any", "type": "image/x-icon" }]
    });
    format!("{}\n", serde_json::to_string_pretty(&manifest).unwrap_or_default())
}

lazy_static! {
    pub static ref SEO_PAGES: Vec<Route> = routes![robots, sitemap, manifest];
}
#[rocket::get("/robots.txt")]
async fn robots(state: &State<RocketState>, host: &Host<'_>) -> CacheResponse<RawText<String>> {
    let domain = host.domain();
    let mut conn = state.pool.get().unwrap();
    let _configuration = get_server_configuration_proto(&mut conn).unwrap();
    let response = RawText(
        format!(
            "User-agent: *
Allow: /

Sitemap: https://{}/sitemap.xml
",
            domain
        )
        .to_string(),
    );

    CacheResponse::public(response, 3600)
}

#[rocket::get("/sitemap.xml")]
async fn sitemap(state: &State<RocketState>, host: &Host<'_>) -> CacheResponse<RawXml<String>> {
    let domain = host.domain();
    let mut conn = state.pool.get().unwrap();
    // On a Rellm Subdomain the sitemap is the owner's site: their tabs, and the posts/events their feeds show (the
    // owner plus whatever they share) -- never the parent server's. A failed lookup fails the request rather than
    // publishing the parent's URLs under the subdomain.
    let subdomain = crate::web::subdomain_web::request_subdomain(&mut conn, host)
        .expect("failed to look up the request's subdomain");
    let parent_configuration = get_server_configuration_proto(&mut conn).unwrap();
    let configuration = match &subdomain {
        Some(subdomain) => subdomain.virtual_server_configuration(parent_configuration, &None),
        None => parent_configuration,
    };

    let mut urls = base_sitemap_urls(&domain.to_string(), &configuration, subdomain.is_some());

    // Unauthenticated `get_posts`: the same "first page" of posts an anonymous visitor sees.
    if let Ok(posts_response) = get_posts_for(GetPostsRequest::default(), &None, &subdomain, &mut conn) {
        for post in posts_response.posts {
            urls.push(format!("https://{}/post/{}", domain, post.id));
        }
    }

    // Unauthenticated `get_events`, from `calendar_lookback_days` ago onward -- mirrors the Elm
    // SPA's EventsPage default time window.
    let lookback_days = configuration
        .event_settings
        .as_ref()
        .and_then(|s| s.calendar_lookback_days)
        .unwrap_or(DEFAULT_CALENDAR_LOOKBACK_DAYS);
    let starts_after = SystemTime::now() - Duration::from_secs(lookback_days as u64 * 24 * 60 * 60);
    let events_request = GetEventsRequest {
        time_filter: Some(TimeFilter {
            starts_after: Some(starts_after.to_proto()),
            ..Default::default()
        }),
        ..Default::default()
    };
    if let Ok(events_response) = get_events_for(events_request, &None, &subdomain, &mut conn) {
        for event in events_response.events {
            for occasion in event.occasions {
                if let Some(post) = &occasion.post {
                    urls.push(format!("https://{}/event/{}", domain, post.id));
                }
            }
        }
    }

    let mut seen = HashSet::new();
    urls.retain(|url| seen.insert(url.clone()));

    let url_entries: String = urls
        .iter()
        .map(|url| format!("    <url>\n        <loc>{}</loc>\n    </url>\n", url))
        .collect();

    let response = RawXml(format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">
{}</urlset>
",
        url_entries
    ));

    CacheResponse::public(response, 3600)
}

#[rocket::get("/manifest.json")]
async fn manifest(state: &State<RocketState>, host: &Host<'_>) -> CacheResponse<RawJson<String>> {
    let mut conn = state.pool.get().unwrap();
    // The installed app of a Rellm Subdomain is named after its owner, not the parent server.
    let configuration = crate::web::subdomain_web::request_configuration(&mut conn, host);
    let response = RawJson(build_manifest(&configuration));

    CacheResponse::public(response, 3600)
}
