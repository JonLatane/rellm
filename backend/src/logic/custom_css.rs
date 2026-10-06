use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_server_configuration_model;
use crate::schema::{media, server_configurations};

pub const MAX_CUSTOM_CSS_BYTES: usize = 64 * 1024;
pub const MAX_CUSTOM_CSS_MEDIA_IDS: usize = 32;

/// The active configuration's custom stylesheet text -- the one place (with `save_custom_css_configuration`'s
/// carry-forward) that reads the `custom_css` column, which `models::ServerConfiguration` deliberately
/// doesn't load (see `models::SERVER_CONFIGURATION_COLUMNS`). `None` if it was never set.
pub fn get_custom_css_text(conn: &mut PgPooledConnection) -> Result<Option<String>, Status> {
    // Make sure a configuration row exists at all (creating the default one on first use).
    get_server_configuration_model(conn)?;
    server_configurations::table
        .filter(server_configurations::active.eq(true))
        .select(server_configurations::custom_css)
        .first::<Option<String>>(conn)
        .map_err(|e| {
            log::error!("get_custom_css_text error: {:?}", e);
            Status::new(Code::Internal, "data_error")
        })
}

/// The media IDs and forced theme of the active configuration -- everything `ServerConfiguration.custom_css_configuration`
/// carries (`custom_css` always unset), without touching the stylesheet text. Empty if never set (or if the
/// stored JSON somehow doesn't parse -- same "treat as unset" fallback `Media::sizes` uses).
pub fn get_custom_css_settings(
    conn: &mut PgPooledConnection,
) -> Result<CustomCssConfiguration, Status> {
    Ok(get_server_configuration_model(conn)?
        .custom_css_configuration
        .and_then(|v| serde_json::from_value::<CustomCssConfiguration>(v).ok())
        .map(|c| CustomCssConfiguration {
            custom_css: None,
            ..c
        })
        .unwrap_or_default())
}

/// The full `CustomCSSConfiguration` -- settings plus the stylesheet text (always `Some`, empty if never
/// set). What `GetCustomCSS` returns and `/custom_css.css` renders.
pub fn get_custom_css_configuration(
    conn: &mut PgPooledConnection,
) -> Result<CustomCssConfiguration, Status> {
    let settings = get_custom_css_settings(conn)?;
    let text = get_custom_css_text(conn)?.unwrap_or_default();
    Ok(CustomCssConfiguration {
        custom_css: Some(text),
        ..settings
    })
}

/// Checks `ConfigureCustomCSS`' limits: the size of the CSS and number of media IDs, that every `media_id` is
/// an existing `GLOBAL_PUBLIC` Media (anything less restrictive would 404 -- or leak, for `PRIVATE` --
/// for anonymous visitors loading the stylesheet), and that the two forced themes aren't both on.
pub fn validate_custom_css_configuration(
    config: &CustomCssConfiguration,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    if config.custom_css.as_deref().map_or(0, str::len) > MAX_CUSTOM_CSS_BYTES {
        return Err(Status::new(Code::InvalidArgument, "custom_css_too_large"));
    }
    if config.media_ids.len() > MAX_CUSTOM_CSS_MEDIA_IDS {
        return Err(Status::new(
            Code::InvalidArgument,
            "too_many_custom_css_media_ids",
        ));
    }
    if config.force_light_theme && config.force_dark_theme {
        return Err(Status::new(
            Code::InvalidArgument,
            "cannot_force_both_light_and_dark_theme",
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

/// What `--primary-color` is when the server has no `ServerColors.primary` configured -- the same neutral gray
/// the Elm client falls back to (`Shared.AccountsPanel.RellmServers.brandingOf`).
pub const DEFAULT_PRIMARY_COLOR: u32 = 0x424242;
/// What `--nav-color` is when the server has no `ServerColors.navigation` configured (the Elm client's fallback).
pub const DEFAULT_NAV_COLOR: u32 = 0xFFFFFF;

/// A `ServerColors`-style ARGB `uint32` as a CSS `#rrggbb` (only the low 24 bits count -- this codebase never
/// stores a translucent server color), or `default` if it's unset.
pub fn css_hex_color(argb: Option<u32>, default: u32) -> String {
    format!("#{:06x}", argb.unwrap_or(default) & 0xFFFFFF)
}

/// The theme `config` forces, as the value of the `--forced-theme` variable: `light` or `dark`, `None` if it
/// forces neither. Light wins if both are somehow set -- the same tie-break the Elm client uses
/// (`Shared.forcedDarkMode`).
pub fn forced_theme(config: &CustomCssConfiguration) -> Option<&'static str> {
    if config.force_light_theme {
        Some("light")
    } else if config.force_dark_theme {
        Some("dark")
    } else {
        None
    }
}

/// The stylesheet served at `/custom_css.css`: a `:root` block defining `--primary-color` and `--nav-color`
/// (the server's configured colors, from `colors`), `--forced-theme` (`light`/`dark`, only when the config
/// forces one -- `index.html` reads it right after the stylesheet loads, to set `<html data-theme>` before
/// the first paint instead of waiting for the Elm app to boot) and `--custom-media-N` (1-based, in `media_ids` order) as
/// `url("/media/<id>")`, followed by the admin's CSS verbatim, so it can override anything before it. The color
/// variables are always present, even with no custom CSS at all, so the stylesheet is never empty. Media URLs
/// are relative -- the stylesheet is always served from the same origin as the media. (The Elm dev server,
/// which isn't, builds its own absolute URLs.)
pub fn custom_css_stylesheet(config: &CustomCssConfiguration, colors: Option<&ServerColors>) -> String {
    let mut css = String::from(":root {\n");
    css.push_str(&format!(
        "  --primary-color: {};\n",
        css_hex_color(colors.and_then(|c| c.primary), DEFAULT_PRIMARY_COLOR)
    ));
    css.push_str(&format!(
        "  --nav-color: {};\n",
        css_hex_color(colors.and_then(|c| c.navigation), DEFAULT_NAV_COLOR)
    ));
    if let Some(theme) = forced_theme(config) {
        css.push_str(&format!("  --forced-theme: {};\n", theme));
    }
    // Ids were validated as decodable on write, but this is also what runs on whatever is in the
    // database, so only ever emit ones that are plain base58 (no quote/paren/backslash to break `url()`).
    config
        .media_ids
        .iter()
        .enumerate()
        .filter(|(_, id)| !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric()))
        .for_each(|(i, id)| css.push_str(&format!("  --custom-media-{}: url(\"/media/{}\");\n", i + 1, id)));
    css.push_str("}\n");
    css.push_str(config.custom_css.as_deref().unwrap_or(""));
    css
}

/// A strong-enough `ETag` for `custom_css_stylesheet`'s output, derived from its content (not the
/// configuration row's id) so unrelated `ConfigureServer` saves don't invalidate browser caches.
pub fn custom_css_etag(stylesheet: &str) -> String {
    let mut hasher = DefaultHasher::new();
    stylesheet.hash(&mut hasher);
    format!("\"{:016x}-{:x}\"", hasher.finish(), stylesheet.len())
}

/// Whether an `If-None-Match` request header (`*`, or a comma-separated list of entity tags, any of which may
/// carry a `W/` weak prefix) matches `etag`. Uses the weak comparison RFC 9110 requires for `If-None-Match`:
/// a CDN that compresses the response commonly rewrites our strong `ETag` to `W/"..."`, and a browser then
/// echoes that back -- an exact string compare would never see a match, so it would never get a `304`.
pub fn if_none_match_matches(header: &str, etag: &str) -> bool {
    let opaque = |tag: &str| tag.trim().trim_start_matches("W/").to_string();
    let ours = opaque(etag);
    header
        .split(',')
        .map(str::trim)
        .any(|candidate| candidate == "*" || (!candidate.is_empty() && opaque(candidate) == ours))
}

/// Writes `config` as a new server configuration version -- same deactivate-then-insert flow as
/// `configure_server`, with everything else copied from the active row. The stylesheet text is
/// `config.custom_css` if set, otherwise carried forward unchanged from the active row.
///
/// The active row is read inside the transaction, locked `FOR UPDATE`, so a concurrent
/// `ConfigureServer` (or another `ConfigureCustomCSS`) can't slip a version in between this read and the
/// insert and then be silently reverted by it.
pub fn save_custom_css_configuration(
    config: &CustomCssConfiguration,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    use crate::schema::server_configurations::dsl::*;
    // Make sure a configuration row exists at all (creating the default one on first use).
    get_server_configuration_model(conn)?;
    conn.transaction::<_, diesel::result::Error, _>(|conn| {
        let current = server_configurations
            .filter(active.eq(true))
            .select(models::SERVER_CONFIGURATION_COLUMNS)
            .for_update()
            .first::<models::ServerConfiguration>(conn)?;
        let existing_css = server_configurations
            .filter(id.eq(current.id))
            .select(custom_css)
            .first::<Option<String>>(conn)?;
        let mut new_config = models::NewServerConfiguration::from(current);
        new_config.custom_css = match config.custom_css.as_ref() {
            Some(text) => Some(text.clone()),
            None => existing_css,
        };
        // The text lives in its own column; the JSON carries just the settings.
        new_config.custom_css_configuration = Some(
            serde_json::to_value(CustomCssConfiguration {
                custom_css: None,
                ..config.clone()
            })
            .unwrap(),
        );
        update(server_configurations)
            .set(active.eq(false))
            .execute(conn)?;
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
