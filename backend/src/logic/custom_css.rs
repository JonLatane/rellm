use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_model;
use crate::schema::media;

pub const MAX_CUSTOM_CSS_BYTES: usize = 64 * 1024;
pub const MAX_CUSTOM_CSS_MEDIA_IDS: usize = 32;

/// The active server configuration's `CustomCssConfiguration` (empty if never set, or if the stored
/// JSON somehow doesn't parse -- same "treat as unset" fallback `Media::sizes` uses).
pub fn get_custom_css_configuration(
    conn: &mut PgPooledConnection,
) -> Result<CustomCssConfiguration, Status> {
    Ok(get_server_configuration_model(conn)?
        .custom_css_configuration
        .and_then(|v| serde_json::from_value::<CustomCssConfiguration>(v).ok())
        .unwrap_or_default())
}

/// Checks `ConfigureCustomCSS`' size limits, and that every `media_id` is an existing
/// `GLOBAL_PUBLIC` Media -- anything less restrictive would 404 (or leak, for `PRIVATE`) for
/// anonymous visitors loading the stylesheet.
pub fn validate_custom_css_configuration(
    config: &CustomCssConfiguration,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    if config.custom_css.len() > MAX_CUSTOM_CSS_BYTES {
        return Err(Status::new(Code::InvalidArgument, "custom_css_too_large"));
    }
    if config.media_ids.len() > MAX_CUSTOM_CSS_MEDIA_IDS {
        return Err(Status::new(
            Code::InvalidArgument,
            "too_many_custom_css_media_ids",
        ));
    }
    for media_id in &config.media_ids {
        let db_id = media_id.to_db_id_or_err("media_ids")?;
        let visibility = media::table
            .filter(media::id.eq(db_id))
            .select(media::visibility)
            .first::<String>(conn)
            .map_err(|_| Status::new(Code::InvalidArgument, "custom_css_media_not_found"))?;
        if visibility != Visibility::GlobalPublic.to_string_visibility() {
            return Err(Status::new(
                Code::InvalidArgument,
                "custom_css_media_must_be_global_public",
            ));
        }
    }
    Ok(())
}

/// The stylesheet served at `/custom_css.css`: a `:root` block defining `--custom-media-N` (1-based,
/// in `media_ids` order) as `url("/media/<id>")`, followed by the admin's CSS verbatim, so it can
/// override anything before it. Media URLs are relative -- the stylesheet is always served from the
/// same origin as the media. (The Elm dev server, which isn't, builds its own absolute URLs.)
pub fn custom_css_stylesheet(config: &CustomCssConfiguration) -> String {
    let mut css = String::new();
    // Ids were validated as decodable on write, but this is also what runs on whatever is in the
    // database, so only ever emit ones that are plain base58 (no quote/paren/backslash to break `url()`).
    let vars: Vec<String> = config
        .media_ids
        .iter()
        .enumerate()
        .filter(|(_, id)| !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric()))
        .map(|(i, id)| format!("  --custom-media-{}: url(\"/media/{}\");\n", i + 1, id))
        .collect();
    if !vars.is_empty() {
        css.push_str(":root {\n");
        vars.iter().for_each(|v| css.push_str(v));
        css.push_str("}\n");
    }
    css.push_str(&config.custom_css);
    css
}

/// A strong-enough `ETag` for `custom_css_stylesheet`'s output, derived from its content (not the
/// configuration row's id) so unrelated `ConfigureServer` saves don't invalidate browser caches.
pub fn custom_css_etag(stylesheet: &str) -> String {
    let mut hasher = DefaultHasher::new();
    stylesheet.hash(&mut hasher);
    format!("\"{:016x}-{:x}\"", hasher.finish(), stylesheet.len())
}

/// Writes `config` as a new server configuration version -- same deactivate-then-insert flow as
/// `configure_server`, with everything else copied from the active row.
pub fn save_custom_css_configuration(
    config: &CustomCssConfiguration,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    use crate::schema::server_configurations::dsl::*;
    let current = get_server_configuration_model(conn)?;
    let mut new_config = models::NewServerConfiguration::from(current);
    new_config.custom_css_configuration = Some(serde_json::to_value(config).unwrap());
    conn.transaction::<_, diesel::result::Error, _>(|conn| {
        update(server_configurations).set(active.eq(false)).execute(conn)?;
        insert_into(server_configurations)
            .values(&new_config)
            .execute(conn)?;
        Ok(())
    })
    .map_err(|e| {
        log::error!("ConfigureCustomCSS failed. Error: {:?}", e);
        Status::new(Code::Internal, "error_updating")
    })
}
