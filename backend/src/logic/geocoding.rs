//! Best-effort free-text address -> IANA timezone resolution, used by `facebook_sync` to format
//! synced event times in the event's own local time instead of UTC.
//!
//! Chains two free, keyless lookups. Neither is precise/critical enough to justify failing a
//! Facebook sync over, so every failure path here (bad address, network error, unparseable
//! response) just returns `None` -- callers fall back to UTC:
//! 1. Geocode the address via OpenStreetMap's public Nominatim API -- the same service the
//!    Tamagui frontend's location picker already uses (`packages/app/hooks/use_nominatim.ts`),
//!    just server-side here. Per Nominatim's usage policy
//!    (<https://operations.osmfoundation.org/policies/nominatim/>), requests must carry a
//!    descriptive `User-Agent` and stay within ~1 req/s -- fine for this on-demand, per-sync-click
//!    use, not for bulk geocoding.
//! 2. Look up the IANA timezone for those coordinates offline via `tzf-rs` (a compact
//!    polygon-based dataset bundled into the binary) -- no second network call, no rate limit.

use lazy_static::lazy_static;
use tzf_rs::DefaultFinder;

const DEFAULT_NOMINATIM_BASE_URL: &str = "https://nominatim.openstreetmap.org";

lazy_static! {
    // Expensive to build (per tzf-rs's own docs) -- initialize once and reuse.
    static ref TZ_FINDER: DefaultFinder = DefaultFinder::new();
}

/// Resolves `address` (e.g. `Occasion.location`'s `uniformly_formatted_address`) to an IANA
/// timezone, or `None` if geocoding fails, returns no results, or the coordinates don't map to a
/// known timezone.
pub fn resolve_timezone(address: &str) -> Option<chrono_tz::Tz> {
    resolve_timezone_at(DEFAULT_NOMINATIM_BASE_URL, address)
}

/// Same as `resolve_timezone`, but against an arbitrary Nominatim-compatible `base_url` -- lets
/// specs point this at a local mock server instead of the real API (see
/// `factories::serve_nominatim_api`).
pub fn resolve_timezone_at(base_url: &str, address: &str) -> Option<chrono_tz::Tz> {
    let (lat, lon) = geocode_at(base_url, address)?;
    // tzf-rs takes (lng, lat), the reverse of the (lat, lon) Nominatim returns.
    let tz_name = TZ_FINDER.get_tz_name(lon, lat);
    match tz_name.parse() {
        Ok(tz) => Some(tz),
        Err(_) => {
            log::warn!(
                "tzf-rs returned an unparseable timezone name {tz_name:?} for ({lat}, {lon})"
            );
            None
        }
    }
}

/// See `facebook_sync::graph_request` for why `block_in_place` is used (and only when there's
/// already a Tokio runtime).
fn geocode_at(base_url: &str, address: &str) -> Option<(f64, f64)> {
    crate::init_crypto();
    let url = format!("{base_url}/search");
    let address = address.to_string();
    let call = move || -> Option<String> {
        reqwest::blocking::Client::new()
            .get(&url)
            .query(&[
                ("q", address.as_str()),
                ("format", "jsonv2"),
                ("limit", "1"),
            ])
            .header("User-Agent", "Rellm (https://rellm.org)")
            .send()
            .ok()?
            .text()
            .ok()
    };
    let text = if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(call)
    } else {
        call()
    }?;
    let results: Vec<serde_json::Value> = serde_json::from_str(&text).ok()?;
    let first = results.first()?;
    let lat: f64 = first.get("lat")?.as_str()?.parse().ok()?;
    let lon: f64 = first.get("lon")?.as_str()?.parse().ok()?;
    Some((lat, lon))
}
