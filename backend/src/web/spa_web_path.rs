use rocket::http::Status;
use rocket_cache_response::CacheResponse;

use crate::protos::{ServerInfo, WebUserInterface};

use super::{rellm_path_responder, RellmResponder, RellmSummary};

/// Which single-page-app should render a given request: the Tamagui
/// (React/Next.js) frontend or the Elm frontend. Both apps are mounted at the
/// same set of paths (see `SPA_PAGES` in `spa_pages.rs`) three times over --
/// unprefixed ("/"), "/tamagui", and "/elm" -- so a request's path alone
/// doesn't always determine which app to render; unprefixed requests fall
/// back to the server's configured `WebUserInterface` (see `root_app`).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SpaApp {
    Tamagui,
    Elm,
}

/// Which app's prefix (if any) a request path is under.
pub fn spa_prefix(path: &str) -> Option<SpaApp> {
    if path == "/tamagui" || path.starts_with("/tamagui/") {
        Some(SpaApp::Tamagui)
    } else if path == "/elm" || path.starts_with("/elm/") {
        Some(SpaApp::Elm)
    } else {
        None
    }
}

/// Which app an *unprefixed* ("/"-rooted) request should render, per the
/// server's configured `WebUserInterface`. Only `ElmSpa` opts into the Elm
/// frontend; every other configuration (including ones with no SPA of their
/// own, like Flutter) renders Tamagui, at least for now.
pub fn root_app(server_info: &ServerInfo) -> SpaApp {
    match server_info.web_user_interface() {
        WebUserInterface::ElmSpa => SpaApp::Elm,
        _ => SpaApp::Tamagui,
    }
}

/// Strips whichever app prefix (if any) a request path is under, so route
/// handlers that derive meaning from path segments (e.g. extracting a
/// post/user/group id by index) can be written once, assuming no prefix --
/// otherwise everything under "/tamagui" or "/elm" resolves one segment off
/// from what it should.
pub fn strip_spa_prefix(path: &str) -> String {
    let prefix = match spa_prefix(path) {
        Some(SpaApp::Tamagui) => "/tamagui",
        Some(SpaApp::Elm) => "/elm",
        None => return path.to_string(),
    };
    match path.strip_prefix(prefix) {
        Some(rest) if rest.is_empty() => "/".to_string(),
        Some(rest) if rest.starts_with('/') => rest.to_string(),
        _ => path.to_string(),
    }
}

/// The first line of `text`, escaped for use as a double- or single-quoted HTML attribute value (`<meta
/// property="og:title" content="…" />`) or as element text (`<title>…</title>`).
///
/// Everything that ends up in a page's `<head>` from a `RellmSummary` goes through this, and most of it is
/// user-controlled (post titles and content, usernames, bios, and text from other networks). It has to escape
/// `&`, `<`, `>`, `"` and `'`: HTML has no backslash escape, so a `"` turned into `\"` still ends the attribute,
/// and the rest of the text then parses as markup -- `" /><script>…</script>` in a post title was a script that ran
/// for every visitor of that post's URL.
pub fn meta_text(text: &str) -> String {
    text.split('\n')
        .next()
        .unwrap_or("")
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

/// Per-request facts a link preview needs beyond its `RellmSummary`: where the page lives (crawlers need *absolute*
/// `og:image`/`og:url` URLs -- iMessage, Slack, Discord and Mastodon all ignore a relative `/media/ID`) and what the
/// site is called (`og:site_name`, kept out of `og:title`).
#[derive(Clone, Debug)]
pub struct PreviewContext {
    /// `https://host` (no trailing slash) -- the request's own host, so subdomains and custom domains preview as
    /// themselves.
    pub origin: String,
    /// The request path, as the browser sees it (including any `/elm` or `/tamagui` prefix).
    pub path: String,
    pub site_name: String,
}

impl PreviewContext {
    pub fn new(host: &rocket::http::uri::Host<'_>, path: &str, site_name: &str) -> Self {
        PreviewContext {
            origin: origin_for_host(&host.domain().to_string(), host.port()),
            path: path.to_string(),
            site_name: site_name.to_string(),
        }
    }
}

/// `https://domain`, except `http://` (and the port kept) for local development hosts -- Rocket can't see the scheme
/// behind a TLS-terminating proxy, and every real deployment is https.
pub fn origin_for_host(domain: &str, port: Option<u16>) -> String {
    let local = domain == "localhost"
        || domain.ends_with(".localhost")
        || domain.parse::<std::net::IpAddr>().is_ok();
    match port {
        Some(port) if local => format!("http://{}:{}", domain, port),
        _ if local => format!("http://{}", domain),
        _ => format!("https://{}", domain),
    }
}

/// A link to `origin` + `path` when `path` is site-relative; anything else (already absolute) is left alone.
fn absolute_url(origin: &str, path: &str) -> String {
    if path.starts_with('/') && !path.starts_with("//") {
        format!("{}{}", origin, path)
    } else {
        path.to_string()
    }
}

/// `og:title`: the page's title without the trailing `| Site Name` (that is `og:site_name`), and with the remaining
/// `|` separators as dashes -- iMessage showed only the text after the last `|` ("Bull City | Social" -> "Social")
/// as the whole title of a link.
pub fn og_title(title: &str, site_name: &str) -> String {
    let suffix = format!(" | {}", site_name);
    let without_site = match title.strip_suffix(&suffix) {
        Some(rest) if !rest.is_empty() => rest,
        _ => title,
    };
    without_site.replace(" | ", " \u{2013} ")
}

/// The link-preview summary shown for each SPA's home page. Shared so both
/// apps' home routes (and the "/" root dispatcher in `main_index.rs`) render
/// identical text, regardless of which app ends up serving the request.
pub fn index_summary(server_name: &str, server_logo: Option<String>) -> Option<RellmSummary> {
    Some(RellmSummary {
        title: Some(server_name.to_string()),
        description: None,
        image: server_logo.or(Some("/favicon.png".to_string())),
    })
}

/// Render a page for either SPA frontend. Interpolates `RellmSummary` data
/// into `<title/>`, `<meta property="og:title"/>`, etc. tags in the app's
/// HTML template -- both apps' templates use the same placeholder strings
/// (see `frontends/tamagui/apps/next/pages/_document.tsx`'s defaults and
/// `frontends/elm-spa/public/index.html`'s `<head>`), so the replacement
/// logic below is shared between them.
///
/// `tamagui_html_path` selects which static file to serve when `app` is
/// `Tamagui` (Next statically exports one HTML file per route); Elm is a
/// true SPA that always serves the same `index.html` regardless of route, so
/// this argument is ignored when `app` is `Elm`.
///
/// `is_tamagui_prefixed` selects which of the two Tamagui Next.js static
/// exports to read from: Next bakes a single fixed `basePath` into a
/// build's HTML/JS at build time (see apps/next/next.config.js), so serving
/// Tamagui correctly at both "/" and "/tamagui" requires two separate
/// builds/directories -- "out" (no basePath) and "out-tamagui" (basePath
/// "/tamagui"), see apps/next/package.json's "build:export". This is `true`
/// only when the request's literal path is under "/tamagui" -- an unprefixed
/// request that resolves to `SpaApp::Tamagui` via `root_app` must still use
/// the no-basePath "out" build, since it's served unprefixed.
pub async fn spa_web_path(
    app: SpaApp,
    tamagui_html_path: &str,
    summary: Option<RellmSummary>,
    is_tamagui_prefixed: bool,
    context: &PreviewContext,
) -> CacheResponse<Result<RellmResponder, Status>> {
    let mut template = match app {
        SpaApp::Tamagui => {
            let (opt_dir, repo_dir) = if is_tamagui_prefixed {
                ("tamagui_web_tamagui", "out-tamagui")
            } else {
                ("tamagui_web", "out")
            };
            let cache_key = format!("{}/{}", opt_dir, tamagui_html_path);
            rellm_path_responder(
                &cache_key,
                &format!("opt/{}/{}", opt_dir, tamagui_html_path),
                &format!(
                    "../frontends/tamagui/apps/next/{}/{}",
                    repo_dir, tamagui_html_path
                ),
            )
            .await
        }
        SpaApp::Elm => {
            rellm_path_responder(
                "elm_web/index.html",
                "opt/elm_web/index.html",
                "../frontends/elm-spa/public/index.html",
            )
            .await
        }
    };

    match (summary, template.as_mut()) {
        (Some(summary), Some(template)) => {
            if let Some(title) = summary.title {
                // `og:title` first: the page's own text is inserted by each step, so a post titled
                // "Rellm Social Link" must not be found by a later step's marker search.
                template.inner = template.inner.replacen(
                    "Rellm Social Link",
                    &meta_text(&og_title(&title, &context.site_name)),
                    1,
                );
                template.inner = template.inner.replacen(
                    "<title>Rellm</title>",
                    &format!("<title>{}</title>", meta_text(&title)),
                    1,
                );
            }

            let description = meta_text(&summary.description.unwrap_or_default());
            template.inner = template
                .inner
                .replacen(
                    "A link from a fediverse community with events, posts, and realtime chat",
                    &description,
                    1,
                )
                // The plain `<meta name="description">` (what search engines and non-OpenGraph crawlers read).
                .replacen(
                    "Rellm is a decentralized, federated, easy-to-deploy social network built in Rust and gRPC, with Flutter and Web frontends.",
                    &description,
                    1,
                );

            let mut tags = String::new();
            if let Some(image) = &summary.image {
                tags.push_str(&format!(
                    "<meta property=\"og:image\" content=\"{}\"/>",
                    meta_text(&absolute_url(&context.origin, image))
                ));
            }
            tags.push_str(&format!(
                "<meta property=\"og:site_name\" content=\"{}\"/>\
                 <meta property=\"og:url\" content=\"{}\"/>\
                 <meta property=\"og:type\" content=\"website\"/>\
                 <meta name=\"twitter:card\" content=\"{}\"/>",
                meta_text(&context.site_name),
                meta_text(&absolute_url(&context.origin, &context.path)),
                if summary.image.is_some() { "summary_large_image" } else { "summary" },
            ));
            // The Tamagui static export minifies its HTML (no space before
            // "/>"), while the Elm SPA's index.html is hand-formatted (space
            // before "/>") -- both variants must be matched here, or the
            // placeholder silently survives unreplaced.
            template.inner = template
                .inner
                .replacen(
                    "<meta property=\"og:image\" content=\"/favicon.png\"/>",
                    &tags,
                    1,
                )
                .replacen(
                    "<meta property=\"og:image\" content=\"/favicon.png\" />",
                    &tags,
                    1,
                );
        }
        _ => (),
    };
    CacheResponse::public(template.map_or(Err(Status::NotFound), |body| Ok(body)), 60)
}
