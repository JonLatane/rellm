use lazy_static::lazy_static;

use rocket::{
    http::{ContentType, MediaType, Status},
    tokio::sync::RwLock,
    Responder,
};
use rocket_cache_response::CacheResponse;
use std::{collections::HashMap, fs, io, path::Path, str::FromStr};

#[derive(Responder, Clone)]
pub struct RellmResponder {
    pub inner: String,
    pub content_type: ContentType,
}

// Used to provide post/event/group/user link previews for Rellm pages.
#[derive(Clone)]
pub struct RellmSummary {
    pub title: Option<String>,
    pub description: Option<String>,
    pub image: Option<String>,
}

/// What link-preview summaries (`RellmSummary`) call a server and show for it -- derived from its
/// `ServerConfiguration`, which `spa_pages`' summary closures are handed whole.
pub trait ServerSummaryInfo {
    /// `ServerInfo.name`, else "Rellm" -- used in titles ("Videos | Server Name").
    fn display_name(&self) -> String;
    /// `ServerInfo.short_name` if set, else `display_name` -- used in descriptions
    /// ("Videos from Server").
    fn short_name(&self) -> String;
    /// `/media/{id}` of the server's square logo, if it has one.
    fn logo_url(&self) -> Option<String>;
}

impl ServerSummaryInfo for crate::protos::ServerConfiguration {
    fn display_name(&self) -> String {
        non_blank(self.server_info.as_ref().and_then(|i| i.name.as_deref())).unwrap_or_else(|| "Rellm".to_string())
    }

    fn short_name(&self) -> String {
        non_blank(self.server_info.as_ref().and_then(|i| i.short_name.as_deref()))
            .unwrap_or_else(|| self.display_name())
    }

    fn logo_url(&self) -> Option<String> {
        self.server_info
            .as_ref()
            .and_then(|i| i.logo.as_ref())
            .and_then(|l| l.square_media_id.as_ref())
            .map(|id| format!("/media/{}", id))
    }
}

fn non_blank(value: Option<&str>) -> Option<String> {
    value.map(str::trim).filter(|v| !v.is_empty()).map(str::to_string)
}

lazy_static! {
    static ref CACHED_FILES: RwLock<HashMap<String, RellmResponder>> = {
        let m = HashMap::new();
        RwLock::new(m)
    };
}

pub async fn rellm_path(
    path: &str,
    server_location: &str,
    repo_location: &str,
) -> CacheResponse<Result<RellmResponder, Status>> {
    let body = rellm_path_responder(path, server_location, repo_location).await;

    CacheResponse::public(body.map_or(Err(Status::NotFound), |body| Ok(body)), 60)
}

pub async fn rellm_path_responder(
    path: &str,
    server_location: &str,
    repo_location: &str,
) -> Option<RellmResponder> {
    let read_guard = CACHED_FILES.read().await;
    let cached_body = read_guard.get(path).cloned();
    drop(read_guard);

    let body = match cached_body {
        Some(body) => Some(body),
        None => {
            let result_string: io::Result<String> = match fs::read_to_string(server_location) {
                Ok(file) => Ok(file),
                Err(_) => match fs::read_to_string(repo_location) {
                    Ok(file) => Ok(file),
                    Err(e) => Err(e),
                },
            };
            match result_string {
                Ok(body) => {
                    let responder = create_responder(path, body).await;
                    Some(responder)
                }
                Err(_) => None,
            }
        }
    };

    body
}

pub async fn create_responder(path: &str, body: String) -> RellmResponder {
    let extension = Path::new(path)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("txt");
    let content_type = ContentType::from_extension(extension)
        .unwrap_or(ContentType(MediaType::from_str("text/html").unwrap()));
    log::info!(
        "caching: {:?}; extension={:?}, content_type={:?}, body.len()={}",
        path,
        &extension,
        &content_type,
        &body.len()
    );
    let responder = RellmResponder {
        inner: body,
        content_type,
    };
    // Disable this cache for development purposes.
    // Relying on commenting this out for now, but it would be nice to hide cache writes
    // behind a flag/argument for the `main` of `rellm`.
    CACHED_FILES
        .write()
        .await
        .insert(path.to_string(), responder.clone());
    responder
}
