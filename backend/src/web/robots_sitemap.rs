use rocket::http::uri::Host;
use rocket::*;
use std::collections::HashSet;
use std::time::{Duration, SystemTime};

use super::RocketState;
use rocket::response::content::{RawJson, RawText, RawXml};

use rocket_cache_response::CacheResponse;

use crate::marshaling::ToProtoTime;
use crate::protos::{GetEventsRequest, GetPostsRequest, TimeFilter};
use crate::rpcs::{get_events, get_posts, get_server_configuration_proto};

// `/posts`, `/events`, `/people`, and `/about` are always real pages -- per
// `CustomNavigationTabSet.tabs`'s own doc comment, those paths can't be claimed by a custom tab --
// so they're listed unconditionally rather than depending on server configuration.
const RESERVED_TAB_PATHS: [&str; 8] = ["posts", "events", "people", "about", "media", "video", "audio", "images"];
// Mirrors `calendarLookbackDaysDefault` in the Elm SPA's `EventsPage.elm`, used when
// `EventSettings.calendar_lookback_days` is unset.
const DEFAULT_CALENDAR_LOOKBACK_DAYS: u32 = 14;

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
    let configuration = get_server_configuration_proto(&mut conn).unwrap();

    let mut urls = vec![
        format!("https://{}/", domain),
        format!("https://{}/posts", domain),
        format!("https://{}/events", domain),
        format!("https://{}/people", domain),
        format!("https://{}/about", domain),
        format!("https://{}/about_rellm", domain),
        format!("https://{}/flutter", domain),
        format!("https://{}/tamagui", domain),
        format!("https://{}/elm", domain),
    ];

    for tab in configuration
        .custom_tabs
        .as_ref()
        .map(|set| set.tabs.as_slice())
        .unwrap_or_default()
    {
        if !RESERVED_TAB_PATHS.contains(&tab.path.as_str()) {
            urls.push(format!("https://{}/{}", domain, tab.path));
        }
    }

    // Unauthenticated `get_posts`: the same "first page" of posts an anonymous visitor sees.
    if let Ok(posts_response) = get_posts(GetPostsRequest::default(), &None, &mut conn) {
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
    if let Ok(events_response) = get_events(events_request, &None, &mut conn) {
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
async fn manifest(state: &State<RocketState>, _host: &Host<'_>) -> CacheResponse<RawJson<String>> {
    // let domain = host.domain();
    let mut conn = state.pool.get().unwrap();
    let configuration = get_server_configuration_proto(&mut conn).unwrap();

    let server_name = configuration
        .clone()
        .server_info
        .map(|i| i.name)
        .flatten()
        .unwrap_or("Rellm".to_string());
    let server_short_name = configuration
        .clone()
        .server_info
        .map(|i| i.short_name)
        .flatten()
        .unwrap_or(server_name.clone());
    // let server_logo_id = configuration
    //     .server_info
    //     .as_ref()
    //     .map(|i| i.logo.as_ref())
    //     .flatten()
    //     .map(|l| l.square_media_id.clone())
    //     .flatten();
    // let server_logo = server_logo_id.map(|id| format!("/media/{}", id));
    let primary_color_int = configuration
        .server_info
        .map(|i| i.colors)
        .flatten()
        .map(|c| c.primary)
        .flatten()
        .unwrap_or(424242);
    let primary_color = &format!("{:x}", primary_color_int)[2..8];

    let response = RawJson(
        format!(
            "{{
  \"name\": \"{}\",
  \"short_name\": \"{}\",
  \"theme_color\": \"#{}CC\",
  \"background_color\": \"#{}\",
  \"start_url\": \"/\",
  \"display\": \"standalone\",
  \"orientation\": \"portrait-primary\",
  \"icons\": [
    {{
      \"src\": \"/favicon.ico\",
      \"sizes\": \"any\",
      \"type\": \"image/x-icon\"
    }}
  ]
}}
",
            server_name.replace("\"", "\\\""),
            server_short_name.replace("\"", "\\\""),
            primary_color,
            primary_color,
        )
        .to_string(),
    );

    CacheResponse::public(response, 3600)
}
