//! Human-readable `MarketProduct` descriptions (e.g. "1.5GB storage for $1/mo", "100k tokens of
//! Nano Banana Pro image generation for $2/mo", "Rellm hosting, 1GB DB + 5GB MinIO for $15/mo",
//! "1GB lifetime storage for $10,000") -- used by `web::spa_pages`'s `/market/product/<_>` preview
//! (`og:description`), not exposed via any RPC (a client can build the same string itself from the
//! raw `MarketProduct` fields if it ever needs to; this only exists for the SSR preview, where
//! there's no client-side rendering to lean on).

use crate::marshaling::{ToProtoPermissions, ToProtoPurchasePeriod, ToProtoPurchaseType};
use crate::protos::*;

/// ISO 4217 numeric currency code -> the display Jon asked for: `$` for USD, otherwise a bare
/// "<amount> <ALPHA3>" -- matches `stripe_sync::currency_code`'s own supported-currency set exactly
/// (every currency displayable here is actually purchasable), plus a permissive fallback for any
/// other currency code a client might have set directly.
fn format_price(amount: u32, currency: u32) -> String {
    let formatted = format_amount_with_commas(amount, currency);
    match currency {
        840 => format!("${}", formatted),
        978 => format!("{} EUR", formatted),
        826 => format!("{} GBP", formatted),
        124 => format!("{} CAD", formatted),
        36 => format!("{} AUD", formatted),
        392 => format!("{} JPY", formatted),
        756 => format!("{} CHF", formatted),
        _ => format!("{} (currency {})", formatted, currency),
    }
}

/// `amount` is minor units (e.g. cents) for every currency except a zero-decimal one (see
/// `stripe_sync::is_zero_decimal_currency`, e.g. JPY), where it's already the whole-unit amount --
/// integer arithmetic throughout (no float rounding surprises), comma-grouped major-unit thousands,
/// and the minor-unit part dropped entirely when it's zero (`100` -> `"1"`, not `"1.00"`).
fn format_amount_with_commas(amount: u32, currency: u32) -> String {
    let (major, minor) = if crate::logic::stripe_sync::is_zero_decimal_currency(currency) {
        (amount, 0)
    } else {
        (amount / 100, amount % 100)
    };
    let digits = major.to_string();
    let mut grouped = String::new();
    for (i, c) in digits.chars().rev().enumerate() {
        if i != 0 && i % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(c);
    }
    let grouped: String = grouped.chars().rev().collect();
    if minor == 0 {
        grouped
    } else {
        format!("{}.{:02}", grouped, minor)
    }
}

/// `PurchasePeriod` -> its billing-cycle suffix (`""` for `PURCHASE_PERIOD_INDEFINITE`, which
/// never recurs).
fn period_suffix(period: PurchasePeriod) -> &'static str {
    match period {
        PurchasePeriod::Monthly => "/mo",
        PurchasePeriod::Annual => "/yr",
        PurchasePeriod::Indefinite => "",
    }
}

/// A byte count -> `"1.5GB"`/`"100MB"`/`"512KB"`/`"3B"` -- binary (1024-based) units, matching how
/// `MediaSettings.default_media_allocation_bytes`'s own 15MB default is actually computed
/// (`15 * 1024 * 1024`), at most one decimal place, trailing `.0` dropped.
fn humanize_bytes(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    if bytes >= GB {
        format!("{}GB", format_trimmed_decimal(bytes as f64 / GB as f64))
    } else if bytes >= MB {
        format!("{}MB", format_trimmed_decimal(bytes as f64 / MB as f64))
    } else if bytes >= KB {
        format!("{}KB", format_trimmed_decimal(bytes as f64 / KB as f64))
    } else {
        format!("{}B", bytes)
    }
}

/// A token count -> `"100k"`/`"1.5M"`/`"500"` -- decimal (1000-based) units, since these are
/// tokens, not bytes.
fn humanize_count(count: u64) -> String {
    const K: u64 = 1_000;
    const M: u64 = K * 1_000;
    if count >= M {
        format!("{}M", format_trimmed_decimal(count as f64 / M as f64))
    } else if count >= K {
        format!("{}k", format_trimmed_decimal(count as f64 / K as f64))
    } else {
        count.to_string()
    }
}

/// One decimal place, trailing `.0` dropped (`1.0` -> `"1"`, `1.5` -> `"1.5"`).
fn format_trimmed_decimal(value: f64) -> String {
    let rounded = (value * 10.0).round() / 10.0;
    if rounded.fract().abs() < f64::EPSILON {
        format!("{}", rounded as i64)
    } else {
        format!("{:.1}", rounded)
    }
}

/// The resource being sold, without its price -- e.g. `"1.5GB storage"`, `"100k tokens of Nano
/// Banana Pro image generation"`, `"Rellm hosting, 1GB DB + 5GB MinIO"`. `PURCHASE_TYPE_MEDIA_STORAGE`
/// gets a `"lifetime"` qualifier for an indefinite (non-recurring) product specifically, matching
/// the "1GB lifetime storage for $10,000" example this was designed around -- the other two types
/// don't need an equivalent qualifier, since "for $X" alone (no `/mo`/`/yr` suffix) already reads
/// as a one-off.
fn resource_description(product: &MarketProduct) -> String {
    let period = product.period.to_proto_purchase_period().unwrap_or(PurchasePeriod::Indefinite);
    match &product.details {
        Some(market_product::Details::MediaStorageSubscriptionDetails(d)) => {
            let size = humanize_bytes(d.allocation_bytes);
            if period == PurchasePeriod::Indefinite {
                format!("{} lifetime storage", size)
            } else {
                format!("{} storage", size)
            }
        }
        Some(market_product::Details::AiGrantSubscriptionDetails(d)) => {
            let tokens = humanize_count(d.tokens);
            let models = if d.model_names.is_empty() {
                "AI".to_string()
            } else {
                d.model_names
                    .iter()
                    .map(|m| crate::logic::ai_model_catalog::display_name(m))
                    .collect::<Vec<_>>()
                    .join("/")
            };
            format!("{} tokens of {} image generation", tokens, models)
        }
        Some(market_product::Details::RellmHostingSubscriptionDetails(d)) => {
            format!(
                "Rellm hosting, {} DB + {} MinIO",
                humanize_bytes(d.db_size_bytes),
                humanize_bytes(d.minio_size_bytes)
            )
        }
        Some(market_product::Details::PermissionsAccessSubscriptionDetails(d)) => {
            let permissions = d.permissions.to_proto_permissions();
            if permissions.is_empty() {
                "access to server features".to_string()
            } else {
                format!(
                    "access to {}",
                    permissions.iter().map(|p| humanize_permission(*p)).collect::<Vec<_>>().join(", ")
                )
            }
        }
        None => "Rellm Market product".to_string(),
    }
}

/// `Permission::as_str_name()`'s `SCREAMING_SNAKE_CASE` (e.g. `"SYNC_EVENTS_TO_FACEBOOK"`) ->
/// `"Sync Events To Facebook"`, for `PURCHASE_TYPE_PERMISSIONS_ACCESS`'s summary -- a light,
/// mechanical humanization rather than a second hand-maintained display-name table to keep in
/// sync with `permissions.proto` (unlike `ai_model_catalog::display_name`, where a real nickname
/// like "Nano Banana" genuinely can't be derived from the raw model name).
fn humanize_permission(permission: Permission) -> String {
    permission
        .as_str_name()
        .split('_')
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + &chars.as_str().to_lowercase(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// An explanatory sentence appended after the price, for a type where the bare resource+price
/// summary alone doesn't convey what's actually being sold. `PURCHASE_TYPE_RELLM_HOSTING` is the
/// only one that needs this today: the buyer becomes a full admin of their own new Rellm instance
/// (not a managed hosting plan with no further say), which is worth spelling out -- per Jon's own
/// framing, it specifically means the buyer can pay-gate features like Facebook sync themselves,
/// the same way this very server might, if they set up their own Facebook developer account.
fn additional_note(purchase_type: PurchaseType) -> Option<&'static str> {
    match purchase_type {
        PurchaseType::RellmHosting => Some(
            "You get full admin access to your own Rellm instance -- e.g. you can pay-gate \
             features like Facebook sync yourself, if you set up your own Facebook developer account.",
        ),
        PurchaseType::MediaStorage | PurchaseType::AiGrants | PurchaseType::PermissionsAccess => None,
    }
}

/// The full human-readable summary sentence for a `MarketProduct`, e.g. `"1.5GB storage for
/// $1/mo"` -- this module's own reason for existing (see its doc).
pub fn market_product_summary(product: &MarketProduct) -> String {
    let purchase_type = product.r#type.to_proto_purchase_type().unwrap_or(PurchaseType::MediaStorage);
    let period = product.period.to_proto_purchase_period().unwrap_or(PurchasePeriod::Indefinite);
    let headline = format!(
        "{} for {}{}",
        resource_description(product),
        format_price(product.amount, product.currency),
        period_suffix(period)
    );
    match additional_note(purchase_type) {
        Some(note) => format!("{} {}", headline, note),
        None => headline,
    }
}

/// A short label for the page `<title>`, e.g. `"Media Storage"`/`"AI Token Grant"`/`"Rellm
/// Hosting"`/`"Permissions Access"` -- `MarketProduct` has no admin-settable name of its own,
/// unlike a `Post`/`Event`, so this is derived purely from its `type` rather than any stored
/// string.
pub fn market_product_headline(product: &MarketProduct) -> String {
    match product.r#type.to_proto_purchase_type().unwrap_or(PurchaseType::MediaStorage) {
        PurchaseType::MediaStorage => "Media Storage".to_string(),
        PurchaseType::AiGrants => "AI Token Grant".to_string(),
        PurchaseType::RellmHosting => "Rellm Hosting".to_string(),
        PurchaseType::PermissionsAccess => "Permissions Access".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn product(
        purchase_type: PurchaseType,
        period: PurchasePeriod,
        amount: u32,
        currency: u32,
        details: market_product::Details,
    ) -> MarketProduct {
        MarketProduct {
            id: "p1".to_string(),
            r#type: purchase_type as i32,
            period: period as i32,
            amount,
            currency,
            created_at: None,
            delisted_at: None,
            details: Some(details),
        }
    }

    #[test]
    fn monthly_media_storage() {
        let p = product(
            PurchaseType::MediaStorage,
            PurchasePeriod::Monthly,
            100,
            840,
            market_product::Details::MediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails {
                allocation_bytes: 1024 * 1024 * 1024 + 512 * 1024 * 1024, // 1.5GB
            }),
        );
        assert_eq!(market_product_summary(&p), "1.5GB storage for $1/mo");
    }

    #[test]
    fn indefinite_media_storage_reads_lifetime() {
        let p = product(
            PurchaseType::MediaStorage,
            PurchasePeriod::Indefinite,
            1_000_000,
            840,
            market_product::Details::MediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails {
                allocation_bytes: 1024 * 1024 * 1024, // 1GB
            }),
        );
        assert_eq!(market_product_summary(&p), "1GB lifetime storage for $10,000");
    }

    #[test]
    fn monthly_ai_grants_uses_nano_banana_display_name() {
        let p = product(
            PurchaseType::AiGrants,
            PurchasePeriod::Monthly,
            200,
            840,
            market_product::Details::AiGrantSubscriptionDetails(AiGrantSubscriptionDetails {
                ai_provider_id: "prov1".to_string(),
                model_names: vec!["gemini-3-pro-image".to_string()],
                tokens: 100_000,
            }),
        );
        assert_eq!(
            market_product_summary(&p),
            "100k tokens of Nano Banana Pro image generation for $2/mo"
        );
    }

    #[test]
    fn monthly_rellm_hosting() {
        let p = product(
            PurchaseType::RellmHosting,
            PurchasePeriod::Monthly,
            1500,
            840,
            market_product::Details::RellmHostingSubscriptionDetails(RellmHostingSubscriptionDetails {
                db_size_bytes: 1024 * 1024 * 1024,
                minio_size_bytes: 5 * 1024 * 1024 * 1024,
                domain: String::new(),
                contact_email: String::new(),
                additional_information: String::new(),
            }),
        );
        assert_eq!(
            market_product_summary(&p),
            "Rellm hosting, 1GB DB + 5GB MinIO for $15/mo You get full admin access to your own \
             Rellm instance -- e.g. you can pay-gate features like Facebook sync yourself, if you \
             set up your own Facebook developer account."
        );
    }

    #[test]
    fn monthly_permissions_access_lists_humanized_permission_names() {
        let p = product(
            PurchaseType::PermissionsAccess,
            PurchasePeriod::Monthly,
            500,
            840,
            market_product::Details::PermissionsAccessSubscriptionDetails(PermissionsAccessSubscriptionDetails {
                permissions: vec![
                    Permission::SyncEventsToFacebook as i32,
                    Permission::SyncPostsToFacebook as i32,
                ],
            }),
        );
        assert_eq!(
            market_product_summary(&p),
            "access to Sync Events To Facebook, Sync Posts To Facebook for $5/mo"
        );
        assert_eq!(market_product_headline(&p), "Permissions Access");
    }

    #[test]
    fn non_usd_currency_uses_alpha_code_not_symbol() {
        let p = product(
            PurchaseType::MediaStorage,
            PurchasePeriod::Monthly,
            1000,
            978, // EUR
            market_product::Details::MediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails {
                allocation_bytes: 1024 * 1024 * 1024,
            }),
        );
        assert_eq!(market_product_summary(&p), "1GB storage for 10 EUR/mo");
    }

    #[test]
    fn zero_decimal_currency_is_not_divided_by_100() {
        let p = product(
            PurchaseType::MediaStorage,
            PurchasePeriod::Monthly,
            500,
            392, // JPY -- zero-decimal, so 500 means 500 yen, not 5 yen
            market_product::Details::MediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails {
                allocation_bytes: 1024 * 1024 * 1024,
            }),
        );
        assert_eq!(market_product_summary(&p), "1GB storage for 500 JPY/mo");
    }
}
