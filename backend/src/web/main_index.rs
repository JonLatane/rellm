use super::*;
use rocket::http::{ContentType, MediaType};
use rocket::{http::Status, State};

use super::RocketState;

use crate::protos::*;
use crate::rpcs::get_server_configuration_proto;
use rocket_cache_response::CacheResponse;
use std::fs;
use std::str::FromStr;

/// The unprefixed "/" home page. Renders whichever app the server's
/// configured `WebUserInterface` indicates (`ElmSpa` -> `elm_web::elm_index`'s
/// app, everything else -> `tamagui_web::index`'s app, at least for now) with
/// the same `RellmSummary` either way -- see `spa_web_path.rs`'s
/// `index_summary`. Flutter is handled separately: it isn't part of the
/// `SPA_PAGES`/`spa_web_path` system since it has no per-route SEO pages.
#[rocket::get("/")]
pub async fn main_index(
    state: &State<RocketState>,
) -> CacheResponse<Result<RellmResponder, Status>> {
    let mut conn = state.pool.get().unwrap();
    let configuration = get_server_configuration_proto(&mut conn).unwrap();
    let server_info = configuration.server_info.unwrap_or_default();

    if server_info.web_user_interface() == WebUserInterface::FlutterWeb {
        let result = match fs::read_to_string("opt/flutter_web/index.html") {
            Ok(file) => Ok(file),
            Err(_) => match fs::read_to_string("../frontends/flutter/build/web/index.html") {
                Ok(file) => Ok(file),
                Err(e) => Err(e),
            },
        };
        let result_data = result.map(|data| RellmResponder {
            inner: data,
            content_type: ContentType(MediaType::from_str("text/html").unwrap()),
        });
        return CacheResponse::public(
            result_data.map_err(|e| {
                log::info!("flutter: {:?}", crate::logic::log_redaction::safe_error(&e));
                Status::NotFound
            }),
            60,
        );
    }

    let server_name = server_info.name.clone().unwrap_or("Rellm".to_string());
    let server_logo = server_info
        .logo
        .clone()
        .unwrap_or_default()
        .square_media_id
        .map(|id| format!("/media/{}", id));
    let app = root_app(&server_info);
    spa_web_path(
        app,
        "index.html",
        index_summary(&server_name, server_logo),
        false,
    )
    .await
}
