use rocket::{
    fs::*,
    http::Status,
    request::{FromRequest, Outcome},
    routes, Request, Route, State,
};
use rocket_cache_response::CacheResponse;
use std::path::*;

use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use crate::web::RocketState;

use super::spa_path::SpaPath;
use super::{index_summary, spa_web_path, RellmResponder, SpaApp};

lazy_static! {
    pub static ref ELM_PAGES: Vec<Route> = routes![
        elm_index,
        elm_file,
        elm_root_style,
        elm_root_dist,
        elm_root_vendor,
        elm_root_markdown_js,
        elm_root_rellm_media_js,
        elm_root_rellm_video_js,
        elm_root_oauth_callback,
        elm_root_service_worker,
    ];
}

// `rank = 1`: Rocket computes a route's rank from its own declared segment
// shape ("elm" static + dynamic trailing = "Partial" color, in Rocket's
// terms), which happens to tie (default rank -5) with every `SPA_PAGES`
// route that mixes static and dynamic segments (e.g. "/post/<_..>",
// "/event/<_>") once those are remounted under "/elm" (see
// `servers/rocket.rs`) -- Rocket ranks purely on the route's own unmounted
// pattern, not the final mounted URI, so it can't tell apart e.g.
// "elm"+wildcard from "post"+wildcard on its own. An explicit rank breaks
// those ties in favor of the more specific `SPA_PAGES` routes (this is a
// fallback -- see below). It just needs to be worse than -5; it still needs
// to beat `spa_file_or_username_or_custom_tab`'s rank (see that route's own doc comment),
// which is also explicit for the same reason.
#[rocket::get("/elm/<file..>", rank = 1)]
async fn elm_file(file: SpaPath) -> CacheResponse<Result<NamedFile, Status>> {
    // `SpaPath`, not `PathBuf`: `/elm/~did:plc:…~rkey@bluesky:` is a client-side route ending in `:`.
    let file = file.0;
    log::info!("elm_file: {:?}", file);
    let result = match elm_asset(&file).await {
        Ok(file) => Ok(file),
        // Not a real static asset -- treat it as a client-side route (e.g.
        // `/elm/about`, or `/elm` itself with a trailing slash) and fall back to
        // index.html, same as `elm_index`, so deep links/refreshes reach the Elm
        // router instead of 404ing before the app ever loads.
        Err(_) => open_elm_index().await,
    };
    CacheResponse::public(result, 60)
}

/// The Elm home page, always reachable at the literal "/elm" path (unlike the
/// rest of `SPA_PAGES` in `spa_pages.rs`, this isn't remounted under "/elm"
/// -- it *is* the "/elm" route). The unprefixed "/" home page is handled
/// separately by `main_index.rs`, which picks between this app and Tamagui's
/// equivalent (`tamagui_web::index`) based on the server's configured
/// `WebUserInterface`.
#[rocket::get("/elm")]
pub async fn elm_index(
    state: &State<RocketState>,
) -> CacheResponse<Result<RellmResponder, Status>> {
    let mut connection = state.pool.get().unwrap();
    let configuration = get_server_configuration_proto(&mut connection).unwrap();
    let server_info = configuration.server_info.unwrap_or_default();
    let server_name = server_info.name.clone().unwrap_or("Rellm".to_string());
    let server_logo = server_info
        .logo
        .clone()
        .unwrap_or_default()
        .square_media_id
        .map(|id| format!("/media/{}", id));
    spa_web_path(
        SpaApp::Elm,
        "index.html",
        index_summary(&server_name, server_logo),
        false,
    )
    .await
}

/// A server can serve the Elm SPA at its *root* too (`main_index.rs`'s
/// `WebUserInterface::ElmSpa` branch) -- but `index.html` there references its
/// assets at plain `/style/*`, `/dist/elm.js`, `/vendor/*`, and
/// `/markdown.js`, `/rellm-media.js`, `/rellm-video.js` (see `index.html`'s base-path bootstrap script), which would
/// otherwise only ever reach `tamagui_file_or_username`'s `/<file..>`
/// catch-all (there is no other root route for them). These routes claim
/// those paths first -- literal/mostly-literal routes outrank a bare
/// `/<file..>` wildcard under Rocket's default ranking, same as e.g.
/// `tamagui_web.rs`'s `/g/<_>/posts` already relies on -- but only when
/// `ElmSpaAtRoot` actually succeeds; otherwise they forward, and Rocket falls
/// through to that same catch-all, so this can't intercept these paths for
/// any other frontend.
#[rocket::get("/style/<file..>")]
async fn elm_root_style(
    _gate: ElmSpaAtRoot,
    file: PathBuf,
) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(&Path::new("style").join(file)).await;
    CacheResponse::public(result, 60)
}

#[rocket::get("/dist/<file..>")]
async fn elm_root_dist(
    _gate: ElmSpaAtRoot,
    file: PathBuf,
) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(&Path::new("dist").join(file)).await;
    CacheResponse::public(result, 60)
}

#[rocket::get("/vendor/<file..>")]
async fn elm_root_vendor(
    _gate: ElmSpaAtRoot,
    file: PathBuf,
) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(&Path::new("vendor").join(file)).await;
    CacheResponse::public(result, 60)
}

#[rocket::get("/markdown.js")]
async fn elm_root_markdown_js(_gate: ElmSpaAtRoot) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(Path::new("markdown.js")).await;
    CacheResponse::public(result, 60)
}

/// The players' shared rules (`public/rellm-media.js`), for the same reason as `elm_root_markdown_js`.
#[rocket::get("/rellm-media.js")]
async fn elm_root_rellm_media_js(_gate: ElmSpaAtRoot) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(Path::new("rellm-media.js")).await;
    CacheResponse::public(result, 60)
}

/// The `<rellm-video>` player (`public/rellm-video.js`), for the same reason as `elm_root_markdown_js`.
#[rocket::get("/rellm-video.js")]
async fn elm_root_rellm_video_js(_gate: ElmSpaAtRoot) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(Path::new("rellm-video.js")).await;
    CacheResponse::public(result, 60)
}

/// The OAuth popup's `redirect_uri` target for every provider (Facebook/Threads/X Twitter/Mastodon --
/// see `public/index.html`'s `facebookLoginPopup` port and `public/oauth-callback.html`) -- computed
/// client-side as `window.location.origin + rellmBasePath + "/oauth-callback.html"`, so when Elm is
/// served at root (`rellmBasePath == ""`) this needs its own root-mounted route the same reason
/// `elm_root_markdown_js`/etc do: without one, `/oauth-callback.html` falls through to
/// `spa_file_or_username_or_custom_tab`'s catch-all and gets misinterpreted as a username lookup. (Under
/// `/elm`, `elm_file`'s own asset fallback already serves it -- no separate route needed there.)
#[rocket::get("/oauth-callback.html")]
async fn elm_root_oauth_callback(_gate: ElmSpaAtRoot) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(Path::new("oauth-callback.html")).await;
    CacheResponse::public(result, 60)
}

/// The service worker script `index.html` registers for Web Push (see `Ports.subscribeToPush`'s
/// own doc comment) -- same reasoning as `elm_root_oauth_callback` just above: when Elm is
/// served at root, `rellmBasePath == ""`, so the browser fetches this at the literal root
/// `/service-worker.js`, which would otherwise fall through to `spa_file_or_username_or_custom_tab`'s
/// catch-all and get served `index.html` -- the wrong content (and MIME type: browsers refuse to
/// register a service worker whose script doesn't come back as JavaScript). Also load-bearing for
/// *scope*, not just content: a service worker's default max scope is everything at or below its
/// own script's own path, so this has to actually be served from `/`, not `/elm/`, for it to be
/// able to control the whole origin. (Under `/elm`, `elm_file`'s own asset fallback already serves
/// it at `/elm/service-worker.js`, correctly scoped to `/elm/` -- no separate route needed there.)
#[rocket::get("/service-worker.js")]
async fn elm_root_service_worker(_gate: ElmSpaAtRoot) -> CacheResponse<Result<NamedFile, Status>> {
    let result = elm_asset(Path::new("service-worker.js")).await;
    CacheResponse::public(result, 60)
}

/// Request guard for `elm_root_style`/`elm_root_dist`: succeeds only when this
/// server's configured `web_user_interface` is `ElmSpa`, forwarding (rather
/// than erroring) otherwise so Rocket tries the next matching route instead
/// of hard-404ing a path some other frontend might actually own.
struct ElmSpaAtRoot;

#[rocket::async_trait]
impl<'r> FromRequest<'r> for ElmSpaAtRoot {
    type Error = ();

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        let is_elm_spa = req
            .guard::<&State<RocketState>>()
            .await
            .succeeded()
            .and_then(|state| state.pool.get().ok())
            .and_then(|mut conn| get_server_configuration_proto(&mut conn).ok())
            .and_then(|config| config.server_info)
            .map(|info| info.web_user_interface() == WebUserInterface::ElmSpa)
            .unwrap_or(false);

        if is_elm_spa {
            Outcome::Success(ElmSpaAtRoot)
        } else {
            Outcome::Forward(Status::NotFound)
        }
    }
}

async fn elm_asset(relative: &Path) -> Result<NamedFile, Status> {
    match NamedFile::open(Path::new("opt/elm_web/").join(relative)).await {
        Ok(file) => Ok(file),
        Err(_) => {
            match NamedFile::open(Path::new("../frontends/elm-spa/public/").join(relative)).await {
                Ok(file) => Ok(file),
                Err(_) => Err(Status::NotFound),
            }
        }
    }
}

async fn open_elm_index() -> Result<NamedFile, Status> {
    match NamedFile::open("opt/elm_web/index.html").await {
        Ok(file) => Ok(file),
        Err(_) => match NamedFile::open("../frontends/elm-spa/public/index.html").await {
            Ok(file) => Ok(file),
            Err(_) => Err(Status::NotFound),
        },
    }
}
