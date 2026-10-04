//! Link preview generation, shared by the `generate_link_preview_images` job and the one-off
//! `regenerate_link_preview_images_for_post` tool (neither of which belongs in the server image -- only
//! `deploys/docker/preview_generator/Dockerfile` ships a browser).
//!
//! For a post's link we produce exactly one generated `Media`, trying in order:
//!
//! 1. the page's metadata image (`og:image`/`twitter:image`), found by simply fetching the page's
//!    HTML -- no browser needed -- if it downloads, is a supported image, and is over
//!    [`MIN_METADATA_IMAGE_BYTES`];
//! 2. otherwise, load the page in a headless Chromium-family browser, try to dismiss any
//!    cookie/consent banner, and use the page's "main image" (largest visible content image,
//!    falling back to the metadata image again) if one can be detected and downloaded;
//! 3. otherwise, a screenshot of that browser-rendered page.
//!
//! The result is appended to the post's existing media, so any user-provided media stays first.
//! Steps 2 and 3 are the only ones needing a browser, which [`LazyBrowser`] therefore starts (and,
//! in a cluster, takes the conductor's browser lock for) only when a post actually gets that far.
//!
//! Browser discovery ([`find_browser_executable`]) works across macOS, Debian/Ubuntu, Fedora/RHEL,
//! Arch, and the Docker image; set `PREVIEW_BROWSER_PATH` to force a specific binary.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use diesel::*;
use headless_chrome::protocol::cdp::Page::CaptureScreenshotFormatOption::Png;
use headless_chrome::{protocol::cdp::Target::CreateTarget, Browser};
use s3::Bucket;
use tokio::task::spawn_blocking;
use tokio::time::timeout;
use uuid::Uuid;

use crate::db_connection::PgPooledConnection;
use crate::logic::{acquire_cluster_lock, release_cluster_lock, update_media_storage_used};
use crate::marshaling::*;
use crate::models::{self, get_user, Post};
use crate::protos::{ClusterResource, ClusterResources, MediaConversion, Visibility};
use crate::schema::{link_preview_attempts, media, posts};

/// Hard wall-clock cap on capturing a single page.
pub const PREVIEW_TIMEOUT: Duration = Duration::from_secs(90);
/// Allowed time for client-side rendering (and consent banners, which often appear late).
const RENDER_WAIT: Duration = Duration::from_secs(6);
const MAX_MAIN_IMAGE_BYTES: usize = 15 * 1024 * 1024;
/// A metadata image at or under this size is treated as a placeholder/tracking pixel/tiny icon and
/// ignored (falling through to the browser).
pub const MIN_METADATA_IMAGE_BYTES: usize = 1024;
/// How much of a page's HTML is read looking for metadata (the tags live in `<head>`, near the top).
const MAX_HTML_BYTES: usize = 1024 * 1024;
const DEFAULT_EXTENSIONS_DIR: &str = "/opt/preview_generator_extensions";

// ---------------------------------------------------------------------------------------------
// Browser discovery
// ---------------------------------------------------------------------------------------------

/// Executables looked up on `PATH` (Linux packages; Homebrew symlinks on macOS), in preference order
/// (Chrome first, then Chromium, then Brave). Only *finds* an existing install -- never downloads one.
const PATH_CANDIDATES: &[&str] = &[
    "google-chrome-stable",
    "google-chrome",
    "chromium",
    "chromium-browser",
    "chrome",
    "brave-browser",
    "brave-browser-stable",
    "brave",
    "microsoft-edge-stable",
];

/// Well-known absolute install locations, in preference order.
const FIXED_CANDIDATES: &[&str] = &[
    // macOS
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    // Debian/Ubuntu/Fedora/Arch packages (Brave and Chrome install under /opt and symlink to /usr/bin)
    "/usr/bin/google-chrome-stable",
    "/usr/bin/google-chrome",
    "/opt/google/chrome/chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    // Fedora's chromium package puts the real binary here
    "/usr/lib64/chromium-browser/chromium-browser",
    "/usr/lib/chromium/chromium",
    "/usr/lib/chromium-browser/chromium-browser",
    "/usr/bin/brave-browser",
    "/usr/bin/brave",
    "/opt/brave.com/brave/brave-browser",
    "/opt/brave.com/brave/brave",
    // Snap
    "/snap/bin/chromium",
    "/snap/bin/brave",
];

fn is_executable_file(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// Finds a usable Chromium-family browser. Order: `PREVIEW_BROWSER_PATH` (must exist), then
/// `BRAVE_PATH`/`CHROME_PATH`, then well-known `PATH` names, then well-known install locations
/// (including `~/Applications` on macOS).
pub fn find_browser_executable() -> Option<PathBuf> {
    for var in ["PREVIEW_BROWSER_PATH", "BRAVE_PATH", "CHROME_PATH"] {
        if let Ok(value) = std::env::var(var) {
            let path = PathBuf::from(&value);
            if is_executable_file(&path) {
                return Some(path);
            }
            log::warn!("{} is set to {:?}, which is not an executable file; ignoring.", var, value);
        }
    }
    if let Some(path_var) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_var) {
            for name in PATH_CANDIDATES {
                let candidate = dir.join(name);
                if is_executable_file(&candidate) {
                    return Some(candidate);
                }
            }
        }
    }
    if let Some(home) = std::env::var_os("HOME") {
        let home = PathBuf::from(home);
        for app in [
            "Google Chrome.app/Contents/MacOS/Google Chrome",
            "Chromium.app/Contents/MacOS/Chromium",
            "Brave Browser.app/Contents/MacOS/Brave Browser",
        ] {
            let candidate = home.join("Applications").join(app);
            if is_executable_file(&candidate) {
                return Some(candidate);
            }
        }
    }
    FIXED_CANDIDATES
        .iter()
        .map(PathBuf::from)
        .find(|p| is_executable_file(p))
}

/// Containers and root users can't use Chromium's sandbox; elsewhere keep it on.
fn should_disable_sandbox() -> bool {
    if let Ok(v) = std::env::var("PREVIEW_BROWSER_NO_SANDBOX") {
        return v == "1" || v.eq_ignore_ascii_case("true");
    }
    Path::new("/.dockerenv").exists()
        || Path::new("/run/.containerenv").exists()
        || std::env::var("USER").map(|u| u == "root").unwrap_or(false)
        || std::env::var_os("KUBERNETES_SERVICE_HOST").is_some()
}

pub fn start_browser() -> Result<Browser, anyhow::Error> {
    let path = find_browser_executable().ok_or_else(|| {
        anyhow::anyhow!(
            "No Chrome/Brave/Chromium install found. Install one, or set PREVIEW_BROWSER_PATH."
        )
    })?;
    log::info!("Using browser at {:?}", path);

    // Optional ad/cookie-blocking extensions (only present in some images); skip missing ones.
    let extensions_dir = PathBuf::from(
        std::env::var("PREVIEW_EXTENSIONS_DIR").unwrap_or(DEFAULT_EXTENSIONS_DIR.to_string()),
    );
    let extensions: Vec<OsString> = ["ublock", "nocookies"]
        .iter()
        .map(|name| extensions_dir.join(name))
        .filter(|p| p.is_dir())
        .map(|p| p.into_os_string())
        .collect();

    let args: Vec<&std::ffi::OsStr> = [
        "--headless=chrome",
        "--hide-scrollbars",
        "--lang=en_US",
        // Default args but with extensions enabled
        "--disable-background-networking",
        "--enable-features=NetworkService,NetworkServiceInProcess",
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-breakpad",
        "--disable-client-side-phishing-detection",
        "--disable-default-apps",
        "--disable-dev-shm-usage",
        // BlinkGenPropertyTrees disabled due to crbug.com/937609
        "--disable-features=TranslateUI,BlinkGenPropertyTrees",
        "--disable-hang-monitor",
        "--disable-ipc-flooding-protection",
        "--disable-prompt-on-repost",
        "--disable-renderer-backgrounding",
        "--disable-sync",
        "--force-color-profile=srgb",
        "--metrics-recording-only",
        "--no-first-run",
        "--enable-automation",
        "--password-store=basic",
        "--use-mock-keychain",
    ]
    .iter()
    .map(std::ffi::OsStr::new)
    .collect();

    let extension_refs: Vec<&std::ffi::OsStr> = extensions.iter().map(|e| e.as_os_str()).collect();
    let options = headless_chrome::LaunchOptionsBuilder::default()
        .path(Some(path))
        .headless(false)
        .disable_default_args(true)
        .sandbox(!should_disable_sandbox())
        .args(args)
        .extensions(extension_refs)
        .window_size(Some((1080, 1080)))
        .build()
        .map_err(|e| anyhow::anyhow!("Invalid browser launch options: {}", e))?;
    Ok(Browser::new(options)?)
}

// ---------------------------------------------------------------------------------------------
// Page capture
// ---------------------------------------------------------------------------------------------

/// Tries to get rid of a cookie/consent banner: first by clicking a "reject"/"decline" button
/// (falling back to "accept") inside something that looks like a consent banner, then by hiding any
/// remaining fixed/sticky banner outright. Returns a short description for logging.
const DISMISS_COOKIE_BANNER_JS: &str = r#"
(function () {
  var BANNER_RE = /cookie|consent|gdpr|ccpa|onetrust|cookiebot|truste|didomi|usercentrics|osano|termly|quantcast|cc-window|cc_banner|klaro|cmplz|privacy-?(banner|notice|policy-bar)/i;
  var REJECT_RE = /^\s*(decline|reject|deny|refuse|no,? thanks|only (necessary|essential|required)|necessary only|essential only|continue without|disagree|opt.?out|manage later)/i;
  var ACCEPT_RE = /^\s*(accept|allow|i agree|agree|got it|ok(ay)?[.!]?\s*$|i understand|understood|yes,? i agree|consent|close)/i;
  var KNOWN_CLICK = [
    '#onetrust-reject-all-handler', '#onetrust-accept-btn-handler',
    '#CybotCookiebotDialogBodyButtonDecline', '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
    '.cmplz-deny', '.cmplz-accept', '#didomi-notice-disagree-button', '#didomi-notice-agree-button',
    '.cc-deny', '.cc-allow', '.cc-dismiss', '#truste-consent-required', '#truste-consent-button',
    '.osano-cm-denyAll', '.osano-cm-accept-all', '.fc-cta-do-not-consent', '.fc-cta-consent',
    '#hs-eu-decline-button', '#hs-eu-confirmation-button', '.js-cookie-consent-agree',
    '[data-testid="uc-deny-all-button"]', '[data-testid="uc-accept-all-button"]'
  ];
  var KNOWN_HIDE = [
    '#onetrust-consent-sdk', '#CybotCookiebotDialog', '#cookie-law-info-bar', '.cc-window',
    '#didomi-host', '#usercentrics-root', '.osano-cm-window', '#truste-consent-track',
    '.fc-consent-root', '.cmplz-cookiebanner', '#hs-eu-cookie-confirmation', '.cookie-banner',
    '#cookie-banner', '#cookieConsent', '.cookie-notice', '#cookie-notice'
  ];
  function visible(el) {
    var r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    var s = getComputedStyle(el);
    return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
  }
  function labelOf(el) {
    return (el.innerText || el.value || el.getAttribute('aria-label') || '').trim();
  }
  function sticky(el) {
    var p = getComputedStyle(el).position;
    return p === 'fixed' || p === 'sticky';
  }
  var did = [];

  for (var i = 0; i < KNOWN_CLICK.length; i++) {
    var known = document.querySelector(KNOWN_CLICK[i]);
    if (known && visible(known)) { known.click(); return 'clicked ' + KNOWN_CLICK[i]; }
  }

  // Heuristic: candidate banners are small-ish elements that either look like consent UI by
  // id/class/role, or are fixed/sticky and mention cookies.
  var banners = [];
  var all = document.body ? document.body.getElementsByTagName('*') : [];
  for (var j = 0; j < all.length; j++) {
    var el = all[j];
    if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE' || !visible(el)) continue;
    var text = el.innerText || '';
    if (text.length > 2500 || text.length < 15) continue;
    var ident = (el.id || '') + ' ' + (typeof el.className === 'string' ? el.className : '') + ' ' + (el.getAttribute('role') || '') + ' ' + (el.getAttribute('aria-label') || '');
    var looksLike = BANNER_RE.test(ident) || (sticky(el) && /cookie/i.test(text));
    if (looksLike && (sticky(el) || el.getAttribute('role') === 'dialog' || el.getAttribute('aria-modal'))) banners.push(el);
  }
  for (var pass = 0; pass < 2; pass++) {
    var RE = pass === 0 ? REJECT_RE : ACCEPT_RE;
    for (var b = 0; b < banners.length; b++) {
      var buttons = banners[b].querySelectorAll('button, a, [role="button"], input[type="button"], input[type="submit"]');
      for (var k = 0; k < buttons.length; k++) {
        var label = labelOf(buttons[k]);
        if (label.length < 40 && RE.test(label) && visible(buttons[k])) {
          buttons[k].click();
          return 'clicked "' + label + '"';
        }
      }
    }
  }

  // Couldn't click anything: hide.
  var hidden = 0;
  KNOWN_HIDE.forEach(function (sel) {
    document.querySelectorAll(sel).forEach(function (el) { el.style.setProperty('display', 'none', 'important'); hidden++; });
  });
  banners.forEach(function (el) {
    if (el.style.display !== 'none') { el.style.setProperty('display', 'none', 'important'); hidden++; }
  });
  [document.documentElement, document.body].forEach(function (el) {
    if (el && getComputedStyle(el).overflow === 'hidden') el.style.setProperty('overflow', 'auto', 'important');
  });
  return hidden ? 'hid ' + hidden + ' element(s)' : 'nothing found';
})()
"#;

/// Hides whatever banner remains after the click attempt (clicked banners usually animate away,
/// but not always).
const HIDE_REMAINING_BANNERS_JS: &str = r#"
(function () {
  var n = 0;
  var all = document.body ? document.body.getElementsByTagName('*') : [];
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    var s = getComputedStyle(el);
    if ((s.position === 'fixed' || s.position === 'sticky') && s.display !== 'none') {
      var t = el.innerText || '';
      if (t.length > 20 && t.length < 2500 && /cookie/i.test(t)) { el.style.setProperty('display', 'none', 'important'); n++; }
    }
  }
  return n;
})()
"#;

/// Picks the page's "main image": the largest visible content image outside of site chrome
/// (header/nav/footer/aside), falling back to `og:image`/`twitter:image`. Returns JSON
/// `{"url": ..., "source": "img"|"meta"}` or `null`.
const FIND_MAIN_IMAGE_JS: &str = r#"
(function () {
  function abs(u) { try { return new URL(u, document.baseURI).href; } catch (e) { return null; } }
  var SKIP_RE = /logo|avatar|icon|sprite|badge|advert|\bads?\b|pixel|tracking|emoji|spinner|placeholder/i;
  var best = null, bestArea = 0;
  var imgs = document.getElementsByTagName('img');
  for (var i = 0; i < imgs.length; i++) {
    var img = imgs[i];
    if (!img.complete || !img.naturalWidth) continue;
    var r = img.getBoundingClientRect();
    if (r.width < 200 || r.height < 150 || img.naturalWidth < 300 || img.naturalHeight < 200) continue;
    var s = getComputedStyle(img);
    if (s.visibility === 'hidden' || s.display === 'none' || s.opacity === '0') continue;
    if (img.closest('header, nav, footer, aside, [role="banner"], [role="navigation"], [role="contentinfo"], [aria-hidden="true"]')) continue;
    var src = img.currentSrc || img.src || '';
    if (!src || src.indexOf('data:') === 0) continue;
    var ident = (img.className || '') + ' ' + (img.id || '') + ' ' + (img.alt || '') + ' ' + src;
    if (SKIP_RE.test(ident)) continue;
    var ratio = r.width / r.height;
    if (ratio > 4 || ratio < 0.25) continue;
    var area = r.width * r.height;
    if (area > bestArea) { best = src; bestArea = area; }
  }
  if (best) return JSON.stringify({ url: abs(best), source: 'img' });
  var metas = document.querySelectorAll('meta[property="og:image"], meta[property="og:image:url"], meta[name="twitter:image"], meta[property="twitter:image"]');
  for (var m = 0; m < metas.length; m++) {
    var c = metas[m].getAttribute('content');
    if (c && c.indexOf('data:') !== 0) return JSON.stringify({ url: abs(c), source: 'meta' });
  }
  return null;
})()
"#;

/// Evaluates `js` and returns its string result (JS `null`/non-strings -> `None`).
fn eval_string(tab: &headless_chrome::Tab, js: &str) -> Option<String> {
    match tab.evaluate(js, false) {
        Ok(obj) => obj.value.and_then(|v| v.as_str().map(|s| s.to_string())),
        Err(e) => {
            log::debug!("Page script failed: {}", e);
            None
        }
    }
}

#[derive(Debug)]
pub struct PageCapture {
    /// Only taken when no `main_image_url` was found (or when explicitly asked for, see
    /// `capture_page`'s `screenshot_only`) -- it's the last-resort preview.
    pub screenshot: Option<Vec<u8>>,
    pub main_image_url: Option<String>,
}

/// Loads `url` in `browser` and looks for its main image, taking a screenshot only if there isn't
/// one. With `screenshot_only` it skips the image search and always takes the screenshot -- the
/// fallback for when a found main image then turned out to be undownloadable.
fn capture_page(
    url: &str,
    browser: &Browser,
    screenshot_only: bool,
) -> Result<PageCapture, anyhow::Error> {
    let tab = browser.new_tab_with_options(CreateTarget {
        // Navigate explicitly below; creating the tab *at* `url` too would race the load event
        // `wait_until_navigated` waits for.
        url: "about:blank".to_string(),
        background: Some(false),
        new_window: Some(true),
        width: Some(1080),
        height: Some(1080),
        left: None,
        top: None,
        window_state: None,
        browser_context_id: None,
        enable_begin_frame_control: None,
        for_tab: None,
        hidden: None,
    })?;
    let result = (|| {
        tab.set_default_timeout(Duration::from_secs(40));
        tab.navigate_to(url)?;
        // Pages with long-polling/ad requests may never fire a clean load event; a partially
        // loaded page is still worth a screenshot, so don't fail the whole preview over it.
        if let Err(e) = tab.wait_until_navigated() {
            log::warn!("Navigation to {} didn't finish cleanly ({}); capturing anyway.", url, e);
        }
        // Allow time for client-side page rendering and extensions to work.
        thread::sleep(RENDER_WAIT);

        // Banners often render late, so try now and again after a pause.
        for attempt in 0..2 {
            let outcome = eval_string(&tab, DISMISS_COOKIE_BANNER_JS);
            log::info!("Cookie banner dismissal for {} (attempt {}): {:?}", url, attempt + 1, outcome);
            thread::sleep(Duration::from_secs(if attempt == 0 { 2 } else { 1 }));
        }
        let _ = tab.evaluate(HIDE_REMAINING_BANNERS_JS, false);

        let main_image_url = if screenshot_only {
            None
        } else {
            eval_string(&tab, FIND_MAIN_IMAGE_JS)
                .and_then(|json| serde_json::from_str::<serde_json::Value>(&json).ok())
                .and_then(|v| v.get("url").and_then(|u| u.as_str()).map(|s| s.to_string()))
                .filter(|u| u.starts_with("http"))
        };

        let screenshot = if main_image_url.is_none() {
            let _ = tab.bring_to_front();
            // `from_surface: true` renders the page itself; `false` grabs the OS window's
            // compositor output, which comes back blank on macOS (and for background tabs).
            Some(tab.capture_screenshot(Png, None, None, true)?)
        } else {
            None
        };
        Ok(PageCapture { screenshot, main_image_url })
    })();
    let _ = tab.close(true);
    result
}

/// Runs [`capture_page`] (which blocks on Chrome IPC and fixed render-wait sleeps) on a
/// blocking-pool thread with a hard wall-clock cap, so one slow/unresponsive link can't wedge the
/// whole job. A timed-out call is left running on its thread rather than killed.
pub async fn capture_page_with_timeout(
    url: String,
    browser: Arc<Browser>,
    screenshot_only: bool,
) -> Result<PageCapture, anyhow::Error> {
    match timeout(
        PREVIEW_TIMEOUT,
        spawn_blocking(move || capture_page(&url, &browser, screenshot_only)),
    )
    .await
    {
        Ok(join_result) => join_result.unwrap_or_else(|e| Err(anyhow::anyhow!(e))),
        Err(_) => Err(anyhow::anyhow!("Timed out generating preview after {:?}", PREVIEW_TIMEOUT)),
    }
}

// ---------------------------------------------------------------------------------------------
// Main image download
// ---------------------------------------------------------------------------------------------

/// Image formats we accept for a main image, detected from magic bytes (servers' content types
/// are unreliable) -> (content type, file extension).
fn sniff_image_type(bytes: &[u8]) -> Option<(&'static str, &'static str)> {
    if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        Some(("image/png", "png"))
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(("image/jpeg", "jpg"))
    } else if bytes.starts_with(b"GIF8") {
        Some(("image/gif", "gif"))
    } else if bytes.len() > 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some(("image/webp", "webp"))
    } else {
        None
    }
}

/// Whether `ip` is somewhere a link-preview fetch must never go (loopback, private/CGNAT,
/// link-local incl. cloud metadata, multicast, unspecified, unique-local). The main image URL is
/// controlled by whoever controls the linked page, so without this the job is an SSRF vector into
/// the cluster's internal network.
pub fn is_forbidden_ip(ip: std::net::IpAddr) -> bool {
    use std::net::IpAddr;
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_broadcast()
                || v4.is_multicast()
                || v4.is_unspecified()
                || (o[0] == 100 && (64..128).contains(&o[1])) // CGNAT 100.64.0.0/10
        }
        IpAddr::V6(v6) => {
            if let Some(v4) = v6.to_ipv4_mapped() {
                return is_forbidden_ip(IpAddr::V4(v4));
            }
            let first = v6.segments()[0];
            v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                || (first & 0xfe00) == 0xfc00 // unique-local fc00::/7
                || (first & 0xffc0) == 0xfe80 // link-local fe80::/10
        }
    }
}

/// Errors unless `url` is http(s) and, if its host is an IP literal, that IP is publicly routable.
/// Hostnames are vetted at connect time instead, by [`PublicOnlyResolver`] -- checking them here
/// too would leave a window for DNS rebinding between this lookup and the connection's own.
fn ensure_public_http_url(url: &reqwest::Url) -> Result<(), anyhow::Error> {
    if !matches!(url.scheme(), "http" | "https") {
        anyhow::bail!("Refusing non-http(s) image URL {}", url);
    }
    let host = url
        .host_str()
        .ok_or_else(|| anyhow::anyhow!("Image URL {} has no host", url))?;
    // `host_str` keeps an IPv6 literal's brackets.
    if let Ok(ip) = host.trim_start_matches('[').trim_end_matches(']').parse::<std::net::IpAddr>() {
        if is_forbidden_ip(ip) {
            anyhow::bail!("Refusing to fetch image from non-public address {}", ip);
        }
    }
    Ok(())
}

/// The DNS resolver the image-download client uses: resolves normally, then drops every
/// non-public address. Because the HTTP client connects to exactly the addresses this returns
/// (it never re-resolves), there's no gap for DNS rebinding to swap in an internal address after
/// the check -- the check *is* the resolution the connection uses. (IP-literal hosts skip DNS
/// entirely; `ensure_public_http_url` covers those.)
struct PublicOnlyResolver;

impl reqwest::dns::Resolve for PublicOnlyResolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        Box::pin(async move {
            let host = name.as_str().to_string();
            let addrs: Vec<std::net::SocketAddr> = tokio::net::lookup_host((host.as_str(), 0))
                .await?
                .filter(|a| !is_forbidden_ip(a.ip()))
                .collect();
            if addrs.is_empty() {
                let err: Box<dyn std::error::Error + Send + Sync> =
                    format!("{} resolves to no public addresses", host).into();
                return Err(err);
            }
            let addrs: reqwest::dns::Addrs = Box::new(addrs.into_iter());
            Ok(addrs)
        })
    }
}

const MAX_IMAGE_REDIRECTS: usize = 5;

/// A successfully fetched HTTP(S) response body.
struct Fetched {
    bytes: Vec<u8>,
    content_type: Option<String>,
    /// The URL actually served, after redirects -- what relative links in the body resolve against.
    final_url: reqwest::Url,
}

/// GETs `url` through the SSRF-safe client (see `is_forbidden_ip`), reading at most `max_bytes`:
/// past that it errors, or, with `truncate`, just stops reading and returns what it has.
async fn fetch_public(
    url: &str,
    referer: &str,
    accept: &str,
    max_bytes: usize,
    truncate: bool,
) -> Result<Fetched, anyhow::Error> {
    crate::init_crypto();
    // Redirects are followed by hand so each hop's scheme/IP literal can be vetted (see
    // `is_forbidden_ip`); hostnames are vetted by `PublicOnlyResolver` on every connection.
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .dns_resolver(PublicOnlyResolver)
        .user_agent("Mozilla/5.0 (compatible; JonlineLinkPreview/1.0)")
        .build()?;
    let mut current = reqwest::Url::parse(url)?;
    let mut hops = 0;
    let mut response = loop {
        ensure_public_http_url(&current)?;
        let response = client
            .get(current.clone())
            .header("Referer", referer)
            .header("Accept", accept)
            .send()
            .await?;
        if response.status().is_redirection() {
            hops += 1;
            let location = response
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|v| v.to_str().ok())
                .ok_or_else(|| anyhow::anyhow!("Redirect from {} without Location", current))?;
            if hops > MAX_IMAGE_REDIRECTS {
                anyhow::bail!("Too many redirects fetching {}", url);
            }
            current = current.join(location)?;
            continue;
        }
        break response.error_for_status()?;
    };
    if !truncate && response.content_length().map(|l| l as usize > max_bytes).unwrap_or(false) {
        anyhow::bail!("{} is too large", url);
    }
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let mut bytes: Vec<u8> = vec![];
    while let Some(chunk) = response.chunk().await? {
        bytes.extend_from_slice(&chunk);
        if bytes.len() > max_bytes {
            if truncate {
                bytes.truncate(max_bytes);
                break;
            }
            anyhow::bail!("{} is too large", url);
        }
    }
    Ok(Fetched { bytes, content_type, final_url: current })
}

async fn download_main_image(
    image_url: &str,
    referer: &str,
) -> Result<(Vec<u8>, &'static str, &'static str), anyhow::Error> {
    let fetched = fetch_public(image_url, referer, "image/*,*/*;q=0.8", MAX_MAIN_IMAGE_BYTES, false).await?;
    let (content_type, extension) = sniff_image_type(&fetched.bytes)
        .ok_or_else(|| anyhow::anyhow!("Main image {} is not a supported image format", image_url))?;
    Ok((fetched.bytes, content_type, extension))
}

// ---------------------------------------------------------------------------------------------
// Metadata image (no browser)
// ---------------------------------------------------------------------------------------------

/// Metadata tags that name a page's preview image, most preferred first.
const METADATA_IMAGE_KEYS: &[&str] = &[
    "og:image",
    "og:image:secure_url",
    "og:image:url",
    "twitter:image",
    "twitter:image:src",
];

fn decode_html_entities(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&#x27;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
}

/// The preview image URLs a page's `<meta>` tags declare (`og:image`, `twitter:image`, ...), most
/// preferred first and deduplicated, resolved against `base` (the page's own final URL) and
/// limited to http(s). Tags with a missing/empty `content`, or in no particular attribute order,
/// are handled; anything not a `<meta>` tag is ignored.
pub fn parse_metadata_image_urls(html: &str, base: &reqwest::Url) -> Vec<String> {
    use std::sync::OnceLock;
    static TAG_RE: OnceLock<regex::Regex> = OnceLock::new();
    static ATTR_RE: OnceLock<regex::Regex> = OnceLock::new();
    let tag_re = TAG_RE.get_or_init(|| regex::Regex::new(r"(?is)<meta\b[^>]*>").unwrap());
    let attr_re = ATTR_RE.get_or_init(|| {
        regex::Regex::new(r#"(?is)([a-z_:][-a-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#).unwrap()
    });

    let mut found: Vec<(usize, String)> = vec![];
    for tag in tag_re.find_iter(html) {
        let mut key: Option<String> = None;
        let mut content: Option<String> = None;
        for attr in attr_re.captures_iter(tag.as_str()) {
            let name = attr[1].to_ascii_lowercase();
            let value = attr
                .get(2)
                .or_else(|| attr.get(3))
                .or_else(|| attr.get(4))
                .map(|m| m.as_str())
                .unwrap_or("");
            match name.as_str() {
                // Both are in real-world use for Open Graph/Twitter tags.
                "property" | "name" => key = Some(value.trim().to_ascii_lowercase()),
                "content" => content = Some(decode_html_entities(value.trim())),
                _ => {}
            }
        }
        if let (Some(key), Some(content)) = (key, content) {
            if let Some(rank) = METADATA_IMAGE_KEYS.iter().position(|k| *k == key) {
                if !content.is_empty() {
                    found.push((rank, content));
                }
            }
        }
    }
    // Stable: ties keep document order.
    found.sort_by_key(|(rank, _)| *rank);

    let mut urls: Vec<String> = vec![];
    for (_, content) in found {
        if let Ok(resolved) = base.join(&content) {
            if matches!(resolved.scheme(), "http" | "https") {
                let resolved = resolved.to_string();
                if !urls.contains(&resolved) {
                    urls.push(resolved);
                }
            }
        }
    }
    urls
}

/// Step 1: fetches `page_url`'s HTML (no browser) and returns the first metadata image that
/// downloads, is a supported image format, and is over [`MIN_METADATA_IMAGE_BYTES`]. `Ok(None)` if
/// the page has no usable one; `Err` only if the page itself couldn't be fetched.
async fn find_metadata_image(
    page_url: &str,
) -> Result<Option<(Vec<u8>, &'static str, &'static str)>, anyhow::Error> {
    let page = fetch_public(page_url, page_url, "text/html,application/xhtml+xml", MAX_HTML_BYTES, true).await?;
    if let Some(content_type) = &page.content_type {
        if !content_type.to_ascii_lowercase().contains("html") {
            return Ok(None);
        }
    }
    let html = String::from_utf8_lossy(&page.bytes);
    for image_url in parse_metadata_image_urls(&html, &page.final_url).into_iter().take(3) {
        match download_main_image(&image_url, page_url).await {
            Ok((bytes, content_type, extension)) if bytes.len() > MIN_METADATA_IMAGE_BYTES => {
                return Ok(Some((bytes, content_type, extension)));
            }
            Ok((bytes, ..)) => {
                log::info!("Metadata image {} is only {} bytes; skipping.", image_url, bytes.len())
            }
            Err(e) => log::info!("Metadata image {} unusable: {}", image_url, e),
        }
    }
    Ok(None)
}

// ---------------------------------------------------------------------------------------------
// Lazy browser
// ---------------------------------------------------------------------------------------------

/// The browser couldn't be started or (in a cluster) its lock couldn't be acquired. Unlike a bad
/// link this isn't the post's fault, so callers shouldn't count it as a failed attempt.
#[derive(Debug)]
pub struct BrowserUnavailable(pub String);

impl std::fmt::Display for BrowserUnavailable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Browser unavailable: {}", self.0)
    }
}

impl std::error::Error for BrowserUnavailable {}

/// A browser started on first use, so a run whose posts all resolve from page metadata never
/// launches one. If this server is part of a cluster (see `ClusterResources`'s own doc in
/// server_configuration.proto), only one instance may have a browser open at a time, so the lock
/// is tied to the browser's lifetime: the first `get` acquires it from the conductor (before
/// launching anything), it's held while the browser stays open for the rest of the run, and
/// [`LazyBrowser::release`] closes the browser *then* frees the lock -- so it's also freed when
/// `get` fails after acquiring it, as long as the caller still calls `release`. Posts resolved
/// from metadata never touch the lock. Servers without `cluster_resources` skip it entirely.
pub struct LazyBrowser {
    cluster_resources: Option<ClusterResources>,
    lock_held: bool,
    browser: Option<Arc<Browser>>,
}

impl LazyBrowser {
    pub fn new(cluster_resources: Option<ClusterResources>) -> Self {
        LazyBrowser { cluster_resources, lock_held: false, browser: None }
    }

    pub async fn get(&mut self) -> Result<Arc<Browser>, anyhow::Error> {
        if let Some(browser) = &self.browser {
            return Ok(Arc::clone(browser));
        }
        if let Some(resources) = &self.cluster_resources {
            if !self.lock_held {
                log::info!("Cluster resources configured; acquiring browser lock from conductor...");
                if !acquire_cluster_lock(resources, &[ClusterResource::Browser]).await {
                    return Err(BrowserUnavailable("could not acquire cluster browser lock in time".to_string()).into());
                }
                self.lock_held = true;
            }
        }
        log::info!("Starting browser...");
        let browser = Arc::new(
            start_browser().map_err(|e| BrowserUnavailable(format!("failed to start browser: {}", e)))?,
        );
        self.browser = Some(Arc::clone(&browser));
        Ok(browser)
    }

    /// Closes the browser (if one was started) and frees the cluster lock (if one was taken).
    pub async fn release(mut self) {
        self.browser = None;
        if self.lock_held {
            if let Some(resources) = &self.cluster_resources {
                release_cluster_lock(resources, &[ClusterResource::Browser]).await;
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Storage + post update
// ---------------------------------------------------------------------------------------------

async fn store_generated_media(
    post: &Post,
    user: &models::User,
    label: &str,
    extension: &str,
    content_type: &str,
    bytes: &[u8],
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> Result<i64, anyhow::Error> {
    let filename = format!("post_{}_{}.{}", post.id.to_proto_id(), label, extension);
    let object_storage_path = format!(
        "user/{}-{}/{}-{}",
        user.id.to_proto_id(),
        user.username,
        Uuid::new_v4(),
        filename
    );
    bucket.put_object(&object_storage_path, bytes).await?;

    let sizes = vec![models::MediaSize {
        conversion: MediaConversion::Original as i32,
        object_storage_path,
        content_type: content_type.to_string(),
        size_bytes: bytes.len() as i64,
        aspect_ratio: None,
    }];
    let media = insert_into(media::table)
        .values(&models::NewMedia {
            user_id: post.user_id,
            name: Some(filename),
            description: None,
            generated: true,
            visibility: Visibility::GlobalPublic.to_string_visibility(),
            metadata: serde_json::to_value(models::MediaMetadata::default())?,
            sizes: serde_json::to_value(sizes)?,
        })
        .get_result::<models::Media>(conn)?;
    Ok(media.id)
}

/// After this many failed `generate_previews_for_post` runs a post is left alone by the
/// `generate_link_preview_images` job (see `record_failed_attempt`); `regenerate_link_preview_images_for_post`
/// still works on it, and clears the count on success.
pub const MAX_PREVIEW_ATTEMPTS: i32 = 5;

/// Notes one more failed preview generation for `post_id`, so the batch query in
/// `generate_link_preview_images` can both deprioritize it (least-recently-attempted first) and
/// eventually give up on it (`MAX_PREVIEW_ATTEMPTS`) instead of retrying a permanently broken link
/// every run and crowding healthy posts out of the batch.
pub fn record_failed_attempt(post_id: i64, conn: &mut PgPooledConnection) {
    let result = insert_into(link_preview_attempts::table)
        .values((
            link_preview_attempts::post_id.eq(post_id),
            link_preview_attempts::attempts.eq(1),
        ))
        .on_conflict(link_preview_attempts::post_id)
        .do_update()
        .set((
            link_preview_attempts::attempts.eq(link_preview_attempts::attempts + 1),
            link_preview_attempts::last_attempt_at.eq(diesel::dsl::now),
        ))
        .execute(conn);
    if let Err(e) = result {
        log::error!("Failed to record preview attempt for post {}: {:?}", post_id, e);
    }
}

/// Forgets `post_id`'s failed attempts -- on success, or when its previews are deleted so it's
/// eligible again.
pub fn clear_failed_attempts(post_id: i64, conn: &mut PgPooledConnection) {
    if let Err(e) = delete(link_preview_attempts::table.filter(link_preview_attempts::post_id.eq(post_id))).execute(conn) {
        log::error!("Failed to clear preview attempts for post {}: {:?}", post_id, e);
    }
}

/// Whether this server has link preview generation turned on
/// (i.e. `MediaSettings.disable_link_preview_images` isn't set).
pub fn link_preview_generation_enabled(
    conn: &mut PgPooledConnection,
) -> Result<bool, diesel::result::Error> {
    let config = crate::rpcs::get_server_configuration_model(conn)
        .map_err(|e| {
            log::error!("Failed to load server configuration: {:?}", e);
            diesel::result::Error::NotFound
        })?;
    Ok(!normalized_media_settings(config.media_settings)
        .disable_link_preview_images)
}

/// Backlogs bigger than this are worked newest-first; smaller ones oldest-first.
pub const NEWEST_FIRST_BACKLOG_THRESHOLD: i64 = 20;

/// Up to `limit` posts with a link and no generated previews yet, skipping any at
/// `MAX_PREVIEW_ATTEMPTS`. If more than `NEWEST_FIRST_BACKLOG_THRESHOLD` posts need previews they
/// come newest (highest id) first, so fresh posts aren't stuck behind a big backlog; otherwise
/// oldest first.
pub fn posts_needing_previews(
    limit: i64,
    conn: &mut PgPooledConnection,
) -> Result<Vec<Post>, diesel::result::Error> {
    let eligible = || {
        posts::table
            .left_join(link_preview_attempts::table)
            .filter(posts::link.is_not_null())
            .filter(posts::media_generated.eq(false))
            .filter(
                link_preview_attempts::attempts
                    .is_null()
                    .or(link_preview_attempts::attempts.lt(MAX_PREVIEW_ATTEMPTS)),
            )
    };
    let backlog: i64 = eligible().count().get_result(conn)?;
    let query = eligible().select(models::POST_COLUMNS).limit(limit);
    if backlog > NEWEST_FIRST_BACKLOG_THRESHOLD {
        query.order(posts::id.desc()).load::<Post>(conn)
    } else {
        query.order(posts::id.asc()).load::<Post>(conn)
    }
}

/// Generates a single preview `Media` for `post`'s link -- metadata image, else the browser-found
/// main image, else a browser screenshot (see the module doc) -- appends it after the post's
/// existing media and marks the post `media_generated`. Doesn't check whether previews were already
/// generated; callers decide that. On error nothing is changed on the post. A
/// [`BrowserUnavailable`] error means the browser was needed but couldn't be had.
pub async fn generate_previews_for_post(
    post: &Post,
    browser: &mut LazyBrowser,
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> Result<(), anyhow::Error> {
    let user_id = post
        .user_id
        .ok_or_else(|| anyhow::anyhow!("Post {} has no user_id", post.id))?;
    let url = post
        .link
        .to_link()
        .ok_or_else(|| anyhow::anyhow!("Post {} has no valid link: {:?}", post.id, post.link))?;
    let user = get_user(user_id, conn).map_err(|e| anyhow::anyhow!("Failed to load user: {:?}", e))?;

    log::info!("Generating preview image for post {} ({})", post.id, url);

    // (label, extension, content type, bytes)
    let mut preview: Option<(&str, &str, &str, Vec<u8>)> = None;

    // 1. Page metadata, no browser.
    match find_metadata_image(&url).await {
        Ok(Some((bytes, content_type, extension))) => {
            log::info!("Using metadata image for {} ({} bytes)", url, bytes.len());
            preview = Some(("main_image", extension, content_type, bytes));
        }
        Ok(None) => log::info!("No usable metadata image for {}; using the browser.", url),
        Err(e) => log::info!("Couldn't fetch {} for metadata ({}); using the browser.", url, e),
    }

    // 2. The browser's main-image detection, 3. else a screenshot.
    if preview.is_none() {
        let browser = browser.get().await?;
        let capture = capture_page_with_timeout(url.clone(), Arc::clone(&browser), false).await?;
        log::info!("Captured {} (main image: {:?})", url, capture.main_image_url);

        if let Some(image_url) = &capture.main_image_url {
            match download_main_image(image_url, &url).await {
                Ok((bytes, content_type, extension)) => {
                    preview = Some(("main_image", extension, content_type, bytes));
                }
                Err(e) => log::warn!(
                    "Failed to fetch main image {} for post {}: {}; falling back to a screenshot.",
                    image_url,
                    post.id,
                    e
                ),
            }
        }

        if preview.is_none() {
            let screenshot = match capture.screenshot {
                Some(screenshot) => screenshot,
                // The page had a main image, but it wouldn't download -- so no screenshot was taken.
                None => capture_page_with_timeout(url.clone(), Arc::clone(&browser), true)
                    .await?
                    .screenshot
                    .ok_or_else(|| anyhow::anyhow!("No screenshot captured for {}", url))?,
            };
            preview = Some(("generated_preview", "png", "image/png", screenshot));
        }
    }

    let (label, extension, content_type, bytes) =
        preview.ok_or_else(|| anyhow::anyhow!("No preview produced for {}", url))?;
    let media_id =
        store_generated_media(post, &user, label, extension, content_type, &bytes, conn, bucket).await?;
    let mut new_media: Vec<Option<i64>> = post.media.clone();
    new_media.push(Some(media_id));

    update(posts::table)
        .filter(posts::id.eq(post.id))
        .set((posts::media.eq(new_media), posts::media_generated.eq(true)))
        .execute(conn)?;
    clear_failed_attempts(post.id, conn);

    if let Err(e) = update_media_storage_used(user_id, conn) {
        log::error!("Failed to update media_storage_bytes_used for user {}: {:?}", user_id, e);
    }
    Ok(())
}
