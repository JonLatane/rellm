use super::*;
use crate::models::{self, NewServerConfiguration};
use crate::protos::*;
use std::mem::transmute;

/// Blanks an `optional string` secret for the client-facing path while keeping `Some`/`None`
/// itself meaningful -- `Some(_)` (configured, real value hidden) becomes `Some(String::new())`,
/// `None` (never configured) stays `None`. Used for the webhook-signing-key fields
/// (`TwilioConfig`/`TelnyxConfig`/`BirdConfig`), which -- unlike this file's other write-only
/// secrets (plain `string`, always blanked to `""` either way) -- need a client to be able to tell
/// "is one configured at all" without ever seeing the real value.
fn blank_but_keep_presence(value: Option<String>) -> Option<String> {
    value.map(|_| String::new())
}

pub trait ToDbServerConfiguration {
    fn to_db(&self) -> NewServerConfiguration;
}

impl ToDbServerConfiguration for ServerConfiguration {
    fn to_db(&self) -> NewServerConfiguration {
        NewServerConfiguration {
            server_info: serde_json::to_value(self.server_info.to_owned()).unwrap(),
            federation_info: serde_json::to_value(self.federation_info.to_owned()).unwrap(),
            anonymous_user_permissions: self.anonymous_user_permissions.to_json_permissions(),
            default_user_permissions: self.default_user_permissions.to_json_permissions(),
            basic_user_permissions: self.basic_user_permissions.to_json_permissions(),
            people_settings: serde_json::to_value(self.people_settings.to_owned()).unwrap(),
            group_settings: serde_json::to_value(self.group_settings.to_owned()).unwrap(),
            post_settings: serde_json::to_value(self.post_settings.to_owned()).unwrap(),
            event_settings: serde_json::to_value(self.event_settings.to_owned()).unwrap(),
            external_cdn_config: self
                .external_cdn_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            web_push_config: self
                .web_push_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            twilio_config: self
                .twilio_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            bird_config: self
                .bird_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            telnyx_config: self
                .telnyx_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            stalwart_config: self
                .stalwart_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            media_settings: self
                .media_settings
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            stripe_config: self
                .stripe_config
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            market_settings: self
                .market_settings
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            preferred_verification_apis: Some(crate::logic::verification_apis_to_json(
                &self
                    .preferred_verification_apis
                    .iter()
                    .filter_map(|a| ContactVerificationApi::try_from(*a).ok())
                    .collect::<Vec<_>>(),
            )),
            // Already validated (see `validate_configuration`'s own `ContactProtocol` check,
            // called before `to_db` on the `ConfigureServer` path) -- by the time this runs,
            // `MAILTO` can't be present and `TEL` can't be present without an enabled SMS
            // provider, so this is a plain round-trip, not another enforcement point.
            supported_contact_protocols: Some(crate::logic::contact_protocols_to_json(
                &self
                    .supported_contact_protocols
                    .iter()
                    .filter_map(|p| ContactProtocol::try_from(*p).ok())
                    .collect::<Vec<_>>(),
            )),
            custom_tabs: self
                .custom_tabs
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            // Always overwritten by `configure_server`'s own `cluster_resources` gating (permission
            // check + `conductor_state` preservation) -- see that function's own comment. Mapped
            // naively here only for consistency with every other `NewServerConfiguration` field.
            cluster_resources: self
                .cluster_resources
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            private_user_strategy: self.private_user_strategy.to_string_private_user_strategy(),
            authentication_features: self
                .authentication_features
                .to_json_authentication_features(),
        }
    }
}

pub trait ToProtoServerConfiguration {
    fn to_proto(&self) -> ServerConfiguration;
}
impl ToProtoServerConfiguration for models::ServerConfiguration {
    fn to_proto(&self) -> ServerConfiguration {
        let server_info: ServerInfo = serde_json::from_value(self.server_info.to_owned()).unwrap();
        let mut federation_info: FederationInfo =
            serde_json::from_value(self.federation_info.to_owned()).unwrap();
        // `FacebookAuthConfig.app_secret` is write-only -- never send the real value to a
        // client. See `configure_server`'s merge logic for how a blank incoming value is kept
        // from clobbering the stored secret.
        federation_info.facebook_auth_config =
            federation_info
                .facebook_auth_config
                .map(|c| FacebookAuthConfig {
                    app_secret: String::new(),
                    ..c
                });
        // `XTwitterAuthConfig.client_secret` is write-only, same reasoning (and same
        // `configure_server` merge-on-blank counterpart) as `FacebookAuthConfig.app_secret` above.
        federation_info.x_twitter_auth_config =
            federation_info
                .x_twitter_auth_config
                .map(|c| XTwitterAuthConfig {
                    client_secret: String::new(),
                    ..c
                });
        let group_settings: FeatureSettings =
            serde_json::from_value(self.group_settings.to_owned()).unwrap();
        let people_settings: FeatureSettings =
            serde_json::from_value(self.people_settings.to_owned()).unwrap();
        let post_settings: PostSettings =
            serde_json::from_value(self.post_settings.to_owned()).unwrap();
        let event_settings: EventSettings =
            serde_json::from_value(self.event_settings.to_owned()).unwrap();
        let external_cdn_config: Option<ExternalCdnConfig> = self
            .external_cdn_config
            .to_owned()
            .map(|c| serde_json::from_value(c).unwrap_or_else(|_| ExternalCdnConfig::default()));
        // `WebPushConfig.private_vapid_key` is write-only -- never send the real value to a
        // client, same reasoning (and same `configure_server` merge-on-blank counterpart) as
        // `FacebookAuthConfig.app_secret` above.
        let web_push_config: Option<WebPushConfig> = self
            .web_push_config
            .to_owned()
            .map_or(Some(None), |c| serde_json::from_value(c).ok())
            .flatten()
            .map(|c| WebPushConfig {
                private_vapid_key: String::new(),
                ..c
            });
        // .map(|c| serde_json::from_value(c).unwrap_or_else(|_| None));
        // `TwilioConfig.twilio_api_key_secret` (the API Key's Secret) and `twilio_webhook_signing_key`
        // (the Auth Token, used only for inbound signature verification -- see that field's own
        // doc) are each independently write-only -- never send the real value to a client, same
        // reasoning (and same `configure_server` merge-on-blank counterpart) as
        // `FacebookAuthConfig.app_secret` above. `twilio_webhook_signing_key` is `optional`, unlike
        // the other secrets here, specifically so blanking it can still tell a client whether one
        // is configured at all (`Some(String::new())`) versus never set (`None`) -- see that
        // field's own doc.
        let twilio_config: Option<TwilioConfig> = self
            .twilio_config
            .to_owned()
            .map_or(Some(None), |c| serde_json::from_value::<Option<TwilioConfig>>(c).ok())
            .flatten()
            .map(|c| TwilioConfig {
                twilio_api_key_secret: String::new(),
                twilio_webhook_signing_key: blank_but_keep_presence(c.twilio_webhook_signing_key),
                ..c
            });
        // Same write-only treatment for `BirdConfig.bird_access_key`/`bird_webhook_signing_key`.
        let bird_config: Option<BirdConfig> = self
            .bird_config
            .to_owned()
            .map_or(Some(None), |c| serde_json::from_value::<Option<BirdConfig>>(c).ok())
            .flatten()
            .map(|c| BirdConfig {
                bird_access_key: String::new(),
                bird_webhook_signing_key: blank_but_keep_presence(c.bird_webhook_signing_key),
                ..c
            });
        // Same write-only treatment for `TelnyxConfig.telnyx_api_key`/`telnyx_webhook_signing_key`.
        let telnyx_config: Option<TelnyxConfig> = self
            .telnyx_config
            .to_owned()
            .map_or(Some(None), |c| serde_json::from_value::<Option<TelnyxConfig>>(c).ok())
            .flatten()
            .map(|c| TelnyxConfig {
                telnyx_api_key: String::new(),
                telnyx_webhook_signing_key: blank_but_keep_presence(c.telnyx_webhook_signing_key),
                ..c
            });
        // No secret to blank -- `StalwartConfig` is just the one on/off flag.
        let stalwart_config: Option<StalwartConfig> = self
            .stalwart_config
            .to_owned()
            .and_then(|c| serde_json::from_value(c).ok());
        // Same write-only treatment for `StripeConfig.stripe_secret_key`/
        // `stripe_webhook_signing_secret`. `stripe_configured` (computed below, for
        // `market_settings`) is derived from this *before* the blanking, since a blanked
        // `stripe_secret_key` would otherwise always read as "not configured".
        let raw_stripe_config: Option<StripeConfig> = self
            .stripe_config
            .to_owned()
            .map_or(Some(None), |c| serde_json::from_value(c).ok())
            .flatten();
        let stripe_configured =
            raw_stripe_config.as_ref().is_some_and(|c| c.stripe_enabled && !c.stripe_secret_key.is_empty());
        let stripe_config: Option<StripeConfig> = raw_stripe_config.map(|c| StripeConfig {
            stripe_secret_key: String::new(),
            stripe_webhook_signing_secret: String::new(),
            ..c
        });
        // Real `MediaSettings` deserialize (replacing the old hardcoded stub) -- falls back to the
        // 15MB default whenever the stored blob is missing *or* its own
        // `default_media_allocation_bytes` is `0` (covers every server today, since the column is
        // brand new) -- see this repo's established read-time-fallback convention
        // (`deserialize_custom_tabs` above, `federation_info_migration_tests` below) rather than a
        // SQL backfill migration.
        let media_settings: MediaSettings = self
            .media_settings
            .to_owned()
            .and_then(|c| serde_json::from_value::<MediaSettings>(c).ok())
            .filter(|m| m.default_media_allocation_bytes != 0)
            .unwrap_or(MediaSettings {
                visible: true,
                default_moderation: Moderation::Unmoderated as i32,
                default_visibility: Visibility::GlobalPublic as i32,
                default_media_allocation_bytes: 15_728_640,
            });
        // `MarketSettings` deserialize -- falls back to `enabled: false` whenever the stored blob
        // is missing (every server before this column existed), same read-time-fallback convention
        // as `media_settings` above. Never stripped for non-admins (see `get_server_configuration`)
        // -- it's the public signal, unlike `stripe_config` itself. `stripe_configured` is never
        // read from the stored blob (even if a stale value were somehow present there) -- always
        // overwritten with the just-computed live value below, so it can never drift from whether
        // Stripe is actually usable right now.
        let market_settings: MarketSettings = MarketSettings {
            stripe_configured,
            ..self
                .market_settings
                .to_owned()
                .and_then(|c| serde_json::from_value::<MarketSettings>(c).ok())
                .unwrap_or(MarketSettings { enabled: false, stripe_configured: false })
        };
        // Not persisted anywhere yet -- see `NewServerConfiguration`'s doc and
        // `preferred_verification_apis`'s own proto comment. `ConfigureServer` does persist this
        // one (unlike the comment below used to say), stored the same way `Permission` lists are
        // (see `contact_verification::json_to_verification_apis`).
        let preferred_verification_apis: Vec<i32> = self
            .preferred_verification_apis
            .to_owned()
            .map(|v| crate::logic::json_to_verification_apis(&v))
            .unwrap_or_default()
            .into_iter()
            .map(|a| a as i32)
            .collect();
        // The public "is SMS verification available" signal -- serialized to *everyone*, unlike
        // `twilio_config`/`bird_config`/`preferred_verification_apis` themselves (see
        // `get_server_configuration`'s admin-only stripping). Mirrors
        // `contact_verification::available_verification_apis`'s own preference-ordering logic, just
        // computed straight off the just-deserialized configs here (this trait has no `conn` to
        // call that function with).
        let twilio_enabled = twilio_config.as_ref().is_some_and(|c| c.twilio_enabled);
        let bird_enabled = bird_config.as_ref().is_some_and(|c| c.bird_enabled);
        let telnyx_enabled = telnyx_config.as_ref().is_some_and(|c| c.telnyx_enabled);
        let is_available = |api: &ContactVerificationApi| match api {
            ContactVerificationApi::Twilio => twilio_enabled,
            ContactVerificationApi::Bird => bird_enabled,
            ContactVerificationApi::Telnyx => telnyx_enabled,
        };
        let mut available_verification_apis: Vec<i32> = preferred_verification_apis
            .iter()
            .filter_map(|a| ContactVerificationApi::try_from(*a).ok())
            .filter(|a| is_available(a))
            .map(|a| a as i32)
            .collect();
        for api in [
            ContactVerificationApi::Twilio,
            ContactVerificationApi::Bird,
            ContactVerificationApi::Telnyx,
        ] {
            if is_available(&api) && !available_verification_apis.contains(&(api as i32)) {
                available_verification_apis.push(api as i32);
            }
        }
        // Already invariant-enforced at write time (`validate_configuration`'s `ContactProtocol`
        // check, on the `ConfigureServer` path) -- a stored `TEL` always implies some SMS provider
        // was enabled as of that same write, so this is a plain round-trip on read, same as
        // `preferred_verification_apis` above (not live-recomputed like `available_verification_apis`
        // below, which has no admin-settable counterpart to validate in the first place).
        let supported_contact_protocols: Vec<i32> = self
            .supported_contact_protocols
            .to_owned()
            .map(|v| crate::logic::json_to_contact_protocols(&v))
            .unwrap_or_default()
            .into_iter()
            .map(|p| p as i32)
            .collect();
        let custom_tabs: Option<CustomNavigationTabSet> =
            self.custom_tabs.to_owned().and_then(deserialize_custom_tabs);
        // `cluster_shared_secret` is write-only -- never send the real value to a client (not even
        // an admin), same reasoning (and same `configure_server` merge-on-blank counterpart) as
        // `FacebookAuthConfig.app_secret` above. Whether `cluster_resources` is visible *at all* to
        // this caller is decided by `get_server_configuration` (it needs the requesting user, which
        // this trait doesn't have) -- this only ever blanks the secret.
        let cluster_resources: Option<ClusterResources> = self
            .cluster_resources
            .to_owned()
            .and_then(|c| serde_json::from_value(c).ok())
            .map(|c: ClusterResources| ClusterResources {
                cluster_shared_secret: String::new(),
                ..c
            });

        ServerConfiguration {
            server_info: Some(server_info),
            federation_info: Some(federation_info),
            anonymous_user_permissions: self.anonymous_user_permissions.to_i32_permissions(),
            default_user_permissions: self.default_user_permissions.to_i32_permissions(),
            basic_user_permissions: self.basic_user_permissions.to_i32_permissions(),
            people_settings: Some(people_settings),
            group_settings: Some(group_settings),
            post_settings: Some(post_settings),
            event_settings: Some(event_settings),
            custom_tabs: custom_tabs,
            media_settings: Some(media_settings),
            market_settings: Some(market_settings),
            private_user_strategy: self.private_user_strategy.to_i32_private_user_strategy(),
            authentication_features: self
                .authentication_features
                .to_i32_authentication_features(),
            external_cdn_config: external_cdn_config,
            cluster_resources: cluster_resources,
            web_push_config: web_push_config, // ..Default::default()
            twilio_config: twilio_config,
            bird_config: bird_config,
            telnyx_config: telnyx_config,
            stalwart_config: stalwart_config,
            stripe_config: stripe_config,
            preferred_verification_apis: preferred_verification_apis,
            available_verification_apis: available_verification_apis,
            supported_contact_protocols: supported_contact_protocols,
        }
    }
}

/// Backward-compatible deserialization for `ServerConfiguration.custom_tabs`, stored as plain JSON
/// (not protobuf wire bytes -- see `ToDbServerConfiguration::to_db` above), across the breaking
/// `CustomNavigationTabSet.home`/`tabs` shape change (`home` used to be a bare `CustomNavigationTab`
/// restricted by convention -- never by the type itself -- to Home/Events/Posts/a Post; it's now
/// its own dedicated `CustomHomePage`. `tabs` used to wrap each entry in a `CustomNavigationTabWithPath`;
/// `path` now lives on `CustomNavigationTab` itself). Three layers, each a real attempt rather than
/// a blind fallback, so a config actually gets migrated rather than silently reset whenever that's
/// at all possible:
///   1. Deserialize as the *current* shape -- succeeds for every config saved since this migration
///      shipped (including a freshly-initialized server), since `Serialize` always emits every
///      field and this is exactly what it wrote.
///   2. Otherwise, deserialize as the *legacy* shape (`legacy_custom_tabs`) and transform it into
///      the current one, preserving an admin's existing custom nav setup across the upgrade.
///   3. Otherwise -- neither shape fits, e.g. a config saved by some future, again-different
///      version -- fall back to `None` (no custom tabs) rather than ever failing the whole
///      `ServerConfiguration` fetch over it. Logged (unlike the old unconditional `.ok()` this
///      replaces) so a revert to defaults is at least diagnosable, never silent operationally.
///
/// Checks for a legacy-shaped `tabs` entry (any element carrying a `custom_tab` key) *before*
/// ever attempting step 1 above -- every field `CustomNavigationTab` (current) has other than
/// `path` is an `Option<T>`, and serde's derived `Deserialize` treats `Option<T>` fields as
/// implicitly optional (defaulting to `None`) whether or not `#[serde(default)]` is written on
/// them, unlike this module's own hand-written `legacy_custom_tabs` structs, which only get that
/// leniency where explicitly annotated. That means step 1 doesn't actually fail on a legacy blob
/// -- `path` is a sibling of `custom_tab` in both shapes, so it deserializes "successfully",
/// silently dropping `target`/`icon`/`title` to `None` instead of erroring and falling through to
/// the real migration in step 2. Confirmed live: an admin's real legacy `custom_tabs` column
/// deserialized as the current shape with every tab's `path` intact and `target`/`icon`/`title`
/// all `None` -- tabs that render, but link nowhere and show no icon/title, which is exactly what
/// silently matched a `CustomNavigationTab` missing every field but `path` would produce.
fn deserialize_custom_tabs(value: serde_json::Value) -> Option<CustomNavigationTabSet> {
    let looks_legacy = value
        .get("tabs")
        .and_then(|tabs| tabs.as_array())
        .is_some_and(|tabs| tabs.iter().any(|tab| tab.get("custom_tab").is_some()));

    if looks_legacy {
        return match serde_json::from_value::<legacy_custom_tabs::CustomNavigationTabSet>(value) {
            Ok(legacy) => Some(legacy.into_current()),
            Err(legacy_err) => {
                log::warn!(
                    "custom_tabs looked legacy-shaped but failed to deserialize as one ({}) -- resetting to unset rather than failing the configuration fetch",
                    legacy_err
                );
                None
            }
        };
    }

    match serde_json::from_value::<CustomNavigationTabSet>(value.clone()) {
        Ok(current) => Some(current),
        Err(current_err) => match serde_json::from_value::<legacy_custom_tabs::CustomNavigationTabSet>(value) {
            Ok(legacy) => Some(legacy.into_current()),
            Err(legacy_err) => {
                log::warn!(
                    "custom_tabs failed to deserialize as either the current or legacy shape (current: {}; legacy: {}) -- resetting to unset rather than failing the configuration fetch",
                    current_err,
                    legacy_err
                );
                None
            }
        },
    }
}

/// The pre-migration JSON shape of `CustomNavigationTabSet`/`CustomNavigationTab`, kept only so
/// `deserialize_custom_tabs` can recover an admin's existing setup -- see that function's own doc.
/// Field/variant names below must match exactly what the *old* generated prost types' own
/// `#[derive(serde::Serialize)]` actually produced; `custom_navigation_tab::Target`/`Icon`
/// themselves are reused directly from `crate::protos` since this migration didn't touch their own
/// shape at all (only which messages carry `path`, and what type `home` is), so their JSON
/// representation is identical whichever version wrote it. Can be deleted once every server still
/// running the old shape has saved a config at least once post-upgrade -- there's no way to know
/// that from here, so: in the distant future.
mod legacy_custom_tabs {
    use crate::protos::{
        custom_home_page, custom_navigation_tab, CalendarDisplayMode, CustomHomePage,
        CustomNavigationTab as CurrentTab, CustomNavigationTabSet as CurrentSet, NavigationTabStyle,
    };

    // Deliberately *no* `#[serde(default)]` on either field here (unlike the sub-fields below) --
    // a real legacy blob always has both keys present (`Serialize` on the old type emitted every
    // field, same as the current one does), so requiring them is what keeps this from matching
    // arbitrary unrelated JSON (e.g. `{}`, or some future-again-different shape) and silently
    // "migrating" it into an empty `CustomNavigationTabSet` -- that should fall through to
    // `deserialize_custom_tabs`'s own logged `None` fallback instead.
    #[derive(serde::Deserialize)]
    pub struct CustomNavigationTabSet {
        home: Option<CustomNavigationTab>,
        tabs: Vec<CustomNavigationTabWithPath>,
    }

    #[derive(serde::Deserialize)]
    struct CustomNavigationTab {
        #[serde(default)]
        target: Option<custom_navigation_tab::Target>,
        #[serde(default)]
        icon: Option<custom_navigation_tab::Icon>,
        #[serde(default)]
        title: Option<String>,
    }

    #[derive(serde::Deserialize)]
    struct CustomNavigationTabWithPath {
        #[serde(default)]
        custom_tab: Option<CustomNavigationTab>,
        #[serde(default)]
        path: String,
    }

    impl CustomNavigationTabSet {
        pub fn into_current(self) -> CurrentSet {
            CurrentSet {
                home: self.home.and_then(CustomNavigationTab::into_current_home),
                tabs: self
                    .tabs
                    .into_iter()
                    .filter_map(CustomNavigationTabWithPath::into_current)
                    .collect(),
                // A legacy config predates `tab_style` entirely -- the nav has only ever rendered
                // icon-only up to this point, so that's the only sensible migration target (proto
                // enum value 0, same default an unset/never-saved `tab_style` already gets).
                tab_style: NavigationTabStyle::NavigationTabIconOnly as i32,
            }
        }
    }

    impl CustomNavigationTab {
        /// `home`'s own doc already restricted its `target` to `Tab(Home|Events|Posts)`/`PostId`
        /// (enforced by `validate_configuration`, never by the old type itself) -- an `IsProfile`
        /// here could only ever come from a hand-edited config, and has no `CustomHomePage.target`
        /// variant to become, so it's dropped (`None`, i.e. "no home override") same as an unset
        /// `target` (nothing meaningful to migrate either way).
        fn into_current_home(self) -> Option<CustomHomePage> {
            let target = match self.target? {
                custom_navigation_tab::Target::Tab(tab) => custom_home_page::Target::Tab(tab),
                custom_navigation_tab::Target::PostId(post_id) => {
                    custom_home_page::Target::PostId(post_id)
                }
                custom_navigation_tab::Target::IsProfile(_) => return None,
            };
            Some(CustomHomePage {
                target: Some(target),
                pinned_post_ids: Vec::new(),
                show_events_strip: false,
                default_events_strip_to_row: false,
                default_events_strip_calendar_display_mode: CalendarDisplayMode::CalendarDisplayWeek
                    as i32,
            })
        }

        fn into_current_tab(self, path: String) -> CurrentTab {
            CurrentTab {
                target: self.target,
                icon: self.icon,
                title: self.title,
                path,
            }
        }
    }

    impl CustomNavigationTabWithPath {
        fn into_current(self) -> Option<CurrentTab> {
            Some(self.custom_tab?.into_current_tab(self.path))
        }
    }
}

pub const ALL_WEB_UIS: [WebUserInterface; 4] = [
    WebUserInterface::FlutterWeb,
    WebUserInterface::HandlebarsTemplates,
    WebUserInterface::ReactTamagui,
    WebUserInterface::ElmSpa,
];

pub trait ToProtoWebUI {
    fn to_proto_web_ui(&self) -> Option<WebUserInterface>;
}
impl ToProtoWebUI for String {
    fn to_proto_web_ui(&self) -> Option<WebUserInterface> {
        for web_ui in ALL_WEB_UIS {
            if web_ui.as_str_name().eq_ignore_ascii_case(self) {
                return Some(web_ui);
            }
        }
        return None;
    }
}
impl ToProtoWebUI for i32 {
    fn to_proto_web_ui(&self) -> Option<WebUserInterface> {
        Some(unsafe { transmute::<i32, WebUserInterface>(*self) })
    }
}
pub trait ToStringWebUI {
    fn to_string_web_ui(&self) -> String;
}
impl ToStringWebUI for WebUserInterface {
    fn to_string_web_ui(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringWebUI for i32 {
    fn to_string_web_ui(&self) -> String {
        self.to_proto_web_ui().unwrap().to_string_web_ui()
    }
}

#[cfg(test)]
mod custom_tabs_migration_tests {
    use super::deserialize_custom_tabs;
    use crate::protos::*;

    /// A config saved by *this* version round-trips straight through the first (current-shape)
    /// deserialization attempt.
    #[test]
    fn current_shape_round_trips() {
        let set = CustomNavigationTabSet {
            home: Some(CustomHomePage {
                target: Some(custom_home_page::Target::PostId("post1".to_string())),
                pinned_post_ids: vec!["post2".to_string()],
                show_events_strip: true,
                default_events_strip_to_row: true,
                default_events_strip_calendar_display_mode: CalendarDisplayMode::CalendarDisplayMonth
                    as i32,
            }),
            tabs: vec![CustomNavigationTab {
                target: Some(custom_navigation_tab::Target::Tab(
                    NavigationTab::EventsTab as i32,
                )),
                icon: Some(custom_navigation_tab::Icon::EmojiIcon("📅".to_string())),
                title: None,
                path: "gigs".to_string(),
            }],
            tab_style: NavigationTabStyle::NavigationTabIconAndTextRight as i32,
        };
        let value = serde_json::to_value(&set).unwrap();
        assert_eq!(deserialize_custom_tabs(value), Some(set));
    }

    /// Regression test for `custom_tabs` JSON saved before `tab_style` existed -- current-shape in
    /// every other way (`home`/`tabs` already migrated, no nested `custom_tab` key), just missing
    /// the `tab_style` key entirely. Without `build.rs`'s `#[serde(default)]` `field_attribute` for
    /// `CustomNavigationTabSet.tab_style`, step 1 (current-shape deserialize) would hard-error on
    /// this (a plain, non-`optional` enum field is otherwise required), fall through to a legacy-shape
    /// attempt that also can't match it, and reset the admin's whole `custom_tabs` -- tabs and all --
    /// back to unset, exactly like `legacy_federation_info_without_mastodon_servers_deserializes`
    /// below guards against for `FederationInfo.mastodon_servers`.
    #[test]
    fn custom_tabs_without_tab_style_deserializes_as_current_shape() {
        let value = serde_json::json!({
            "home": null,
            "tabs": [{
                "target": { "Tab": NavigationTab::EventsTab as i32 },
                "icon": { "EmojiIcon": "📅" },
                "title": null,
                "path": "events"
            }]
        });

        let migrated = deserialize_custom_tabs(value)
            .expect("custom_tabs predating tab_style should still deserialize");

        assert_eq!(
            migrated.tab_style,
            NavigationTabStyle::NavigationTabIconOnly as i32
        );
        assert_eq!(migrated.tabs.len(), 1);
        assert_eq!(migrated.tabs[0].path, "events");
    }

    /// A config saved by the *pre-migration* backend (`home: CustomNavigationTab`, `tabs:
    /// Vec<CustomNavigationTabWithPath>`) -- hand-built JSON matching exactly what that old
    /// generated `#[derive(serde::Serialize)]` produced -- migrates into the current shape rather
    /// than getting reset to unset.
    #[test]
    fn legacy_shape_migrates() {
        let legacy = serde_json::json!({
            "home": {
                "target": { "Tab": NavigationTab::EventsTab as i32 },
                "icon": null,
                "title": null
            },
            "tabs": [
                {
                    "custom_tab": {
                        "target": { "PostId": "weddings-post" },
                        "icon": { "EmojiIcon": "💍" },
                        "title": "Weddings"
                    },
                    "path": "weddings"
                },
                {
                    "custom_tab": {
                        "target": { "IsProfile": true },
                        "icon": { "EmojiIcon": "👤" },
                        "title": null
                    },
                    "path": "someuser"
                }
            ]
        });

        let migrated = deserialize_custom_tabs(legacy).expect("legacy shape should migrate");

        assert_eq!(
            migrated.home,
            Some(CustomHomePage {
                target: Some(custom_home_page::Target::Tab(NavigationTab::EventsTab as i32)),
                ..Default::default()
            })
        );
        assert_eq!(migrated.tabs.len(), 2);
        assert_eq!(migrated.tabs[0].path, "weddings");
        assert_eq!(
            migrated.tabs[0].target,
            Some(custom_navigation_tab::Target::PostId(
                "weddings-post".to_string()
            ))
        );
        assert_eq!(migrated.tabs[0].title, Some("Weddings".to_string()));
        assert_eq!(migrated.tabs[1].path, "someuser");
        assert_eq!(
            migrated.tabs[1].target,
            Some(custom_navigation_tab::Target::IsProfile(true))
        );
    }

    /// Neither shape fits -- falls back to `None` rather than panicking or propagating an error
    /// that would fail the whole `ServerConfiguration` fetch.
    #[test]
    fn unrecognized_shape_falls_back_to_none() {
        let garbage = serde_json::json!({ "totally": "unrecognized" });
        assert_eq!(deserialize_custom_tabs(garbage), None);
    }

    /// Regression test for a real legacy blob (6 tabs, `home: null`) that used to silently
    /// deserialize as the *current* shape -- see `deserialize_custom_tabs`'s own doc for why:
    /// `path` is a sibling of `custom_tab` in both shapes, and every other field is an implicitly
    /// optional `Option<T>`, so step 1 "succeeded" with just `path` intact and `target`/`icon`/
    /// `title` all silently `None`, never reaching the real migration below. Distinct from
    /// `legacy_shape_migrates` above in one load-bearing way: that test's tabs all use plain
    /// string/bool oneof variants (`PostId`, `IsProfile`), which happen to still be present as
    /// *some* value under the wrong key structure; this one also exercises `Tab(i32)` (an
    /// enumeration oneof) and a non-ASCII `EmojiIcon`, and -- most importantly -- asserts the
    /// actual field *values* survive the migration, not just that migration returns `Some` with
    /// the right tab count (which is exactly what the bug this guards against would still do).
    #[test]
    fn legacy_shape_with_six_tabs_migrates_with_fields_intact() {
        let value = serde_json::json!({
          "home": null,
          "tabs": [
            {
              "path": "what_is_rellm",
              "custom_tab": {
                "icon": { "IconMediaId": "5F6wnF" },
                "title": "What Is Rellm?",
                "target": { "PostId": "4zHQSj" }
              }
            },
            {
              "path": "jon",
              "custom_tab": {
                "icon": { "IconMediaId": "54j2oq" },
                "title": null,
                "target": { "IsProfile": true }
              }
            },
            {
              "path": "events",
              "custom_tab": {
                "icon": { "EmojiIcon": "📅" },
                "title": null,
                "target": { "Tab": 10 }
              }
            }
          ]
        });

        let migrated = deserialize_custom_tabs(value).expect("legacy shape should migrate");

        assert_eq!(migrated.home, None);
        assert_eq!(migrated.tabs.len(), 3);
        assert_eq!(migrated.tabs[0].path, "what_is_rellm");
        assert_eq!(migrated.tabs[0].title, Some("What Is Rellm?".to_string()));
        assert_eq!(
            migrated.tabs[0].target,
            Some(custom_navigation_tab::Target::PostId("4zHQSj".to_string()))
        );
        assert_eq!(
            migrated.tabs[0].icon,
            Some(custom_navigation_tab::Icon::IconMediaId("5F6wnF".to_string()))
        );
        assert_eq!(migrated.tabs[1].path, "jon");
        assert_eq!(
            migrated.tabs[1].target,
            Some(custom_navigation_tab::Target::IsProfile(true))
        );
        assert_eq!(migrated.tabs[2].path, "events");
        assert_eq!(
            migrated.tabs[2].target,
            Some(custom_navigation_tab::Target::Tab(
                NavigationTab::EventsTab as i32
            ))
        );
        assert_eq!(
            migrated.tabs[2].icon,
            Some(custom_navigation_tab::Icon::EmojiIcon("📅".to_string()))
        );
    }
}

#[cfg(test)]
mod federation_info_migration_tests {
    use crate::protos::*;

    /// Regression test: `federation_info` JSON stored before `mastodon_servers` existed used to
    /// panic the whole server on startup (`ToProtoServerConfiguration::to_proto`'s
    /// `serde_json::from_value(...).unwrap()`) with "missing field `mastodon_servers`" -- unlike
    /// `facebook_auth_config`/`x_twitter_auth_config` (both `optional`, so serde already treats a
    /// missing key as `None` for free), `mastodon_servers` is a `repeated` field
    /// (`Vec<MastodonServer>`), which serde treats as a hard error when absent unless told
    /// otherwise -- see `build.rs`'s `#[serde(default)]` `field_attribute` for this field, added
    /// specifically to fix this.
    #[test]
    fn legacy_federation_info_without_mastodon_servers_deserializes() {
        let legacy = serde_json::json!({
            "servers": [],
            "facebook_auth_config": null,
            "x_twitter_auth_config": null
        });

        let federation_info: FederationInfo = serde_json::from_value(legacy)
            .expect("federation_info predating mastodon_servers should still deserialize");

        assert_eq!(federation_info.mastodon_servers, Vec::new());
    }
}
