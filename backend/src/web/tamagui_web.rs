use lazy_static::lazy_static;

use rocket::{http::Status, routes, Route, State};
use rocket_cache_response::CacheResponse;

use crate::web::RocketState;

use super::{index_summary, spa_file_or_username_or_custom_tab, spa_web_path, RellmResponder, SpaApp};

lazy_static! {
    pub static ref TAMAGUI_PAGES: Vec<Route> =
        routes![index, spa_file_or_username_or_custom_tab::spa_file_or_username_or_custom_tab,];
}

/// The Tamagui home page, always reachable at the literal "/tamagui" path
/// (unlike the rest of `SPA_PAGES`, this isn't remounted under "/tamagui" --
/// it *is* the "/tamagui" route -- see `spa_pages.rs`). The unprefixed "/"
/// home page is handled separately by `main_index.rs`, which picks between
/// this app and Elm's equivalent (`elm_web::elm_index`) based on the
/// server's configured `WebUserInterface`.
#[rocket::get("/tamagui")]
pub async fn index(
    state: &State<RocketState>,
    host: &rocket::http::uri::Host<'_>,
) -> CacheResponse<Result<RellmResponder, Status>> {
    let mut connection = state.pool.get().unwrap();
    let configuration = crate::web::subdomain_web::request_configuration(&mut connection, host);
    let server_info = configuration.server_info.unwrap_or_default();
    let server_name = server_info.name.clone().unwrap_or("Rellm".to_string());
    let server_logo = server_info
        .logo
        .clone()
        .unwrap_or_default()
        .square_media_id
        .map(|id| format!("/media/{}", id));
    spa_web_path(
        SpaApp::Tamagui,
        "index.html",
        index_summary(&server_name, server_logo),
        true,
    )
    .await
}
