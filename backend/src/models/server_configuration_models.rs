use std::time::SystemTime;

use crate::marshaling::ToJsonPermissions;
use crate::protos::*;
use crate::schema::server_configurations;

#[derive(Debug, Queryable, Identifiable, AsChangeset)]
pub struct ServerConfiguration {
    pub id: i64,

    pub active: bool,

    pub server_info: serde_json::Value,

    pub anonymous_user_permissions: serde_json::Value,
    pub default_user_permissions: serde_json::Value,
    pub basic_user_permissions: serde_json::Value,

    pub people_settings: serde_json::Value,
    pub group_settings: serde_json::Value,
    pub post_settings: serde_json::Value,
    pub event_settings: serde_json::Value,

    pub external_cdn_config: Option<serde_json::Value>,

    pub private_user_strategy: String,
    pub authentication_features: serde_json::Value,

    pub created_at: SystemTime,
    pub updated_at: SystemTime,

    pub federation_info: serde_json::Value,

    pub web_push_config: Option<serde_json::Value>,

    pub custom_tabs: Option<serde_json::Value>,

    pub cluster_resources: Option<serde_json::Value>,

    pub twilio_config: Option<serde_json::Value>,

    pub bird_config: Option<serde_json::Value>,

    pub preferred_verification_apis: Option<serde_json::Value>,

    pub media_settings: Option<serde_json::Value>,

    pub stripe_config: Option<serde_json::Value>,

    pub market_settings: Option<serde_json::Value>,

    pub telnyx_config: Option<serde_json::Value>,

    pub supported_contact_protocols: Option<serde_json::Value>,

    pub stalwart_config: Option<serde_json::Value>,

    /// A `CustomCSSConfiguration` *without* its `custom_css` text (that's the separate `custom_css` column,
    /// not loaded here -- see `SERVER_CONFIGURATION_COLUMNS`): the media IDs and forced theme.
    /// `to_proto` serves it as `ServerConfiguration.custom_css_configuration`; `to_db` never writes it
    /// (`ConfigureServer` carries it forward) -- only `ConfigureCustomCSS` changes it.
    pub custom_css_configuration: Option<serde_json::Value>,
}
/// Explicit column list for `server_configurations`, excluding `custom_css` -- the (potentially large)
/// custom stylesheet text, which has no field on `ServerConfiguration` because only `GetCustomCSS`,
/// `ConfigureCustomCSS`, `/custom_css.css` and the versioning carry-forward ever read it (see
/// `logic::custom_css`). Every query that loads a `ServerConfiguration` selects (or `returning`s) this, so
/// loading the configuration -- e.g. for `GetServerConfiguration` -- never touches that column. Mirrors
/// `USER_COLUMNS`/`POST_COLUMNS`.
pub const SERVER_CONFIGURATION_COLUMNS: (
    server_configurations::id,
    server_configurations::active,
    server_configurations::server_info,
    server_configurations::anonymous_user_permissions,
    server_configurations::default_user_permissions,
    server_configurations::basic_user_permissions,
    server_configurations::people_settings,
    server_configurations::group_settings,
    server_configurations::post_settings,
    server_configurations::event_settings,
    server_configurations::external_cdn_config,
    server_configurations::private_user_strategy,
    server_configurations::authentication_features,
    server_configurations::created_at,
    server_configurations::updated_at,
    server_configurations::federation_info,
    server_configurations::web_push_config,
    server_configurations::custom_tabs,
    server_configurations::cluster_resources,
    server_configurations::twilio_config,
    server_configurations::bird_config,
    server_configurations::preferred_verification_apis,
    server_configurations::media_settings,
    server_configurations::stripe_config,
    server_configurations::market_settings,
    server_configurations::telnyx_config,
    server_configurations::supported_contact_protocols,
    server_configurations::stalwart_config,
    server_configurations::custom_css_configuration,
) = (
    server_configurations::id,
    server_configurations::active,
    server_configurations::server_info,
    server_configurations::anonymous_user_permissions,
    server_configurations::default_user_permissions,
    server_configurations::basic_user_permissions,
    server_configurations::people_settings,
    server_configurations::group_settings,
    server_configurations::post_settings,
    server_configurations::event_settings,
    server_configurations::external_cdn_config,
    server_configurations::private_user_strategy,
    server_configurations::authentication_features,
    server_configurations::created_at,
    server_configurations::updated_at,
    server_configurations::federation_info,
    server_configurations::web_push_config,
    server_configurations::custom_tabs,
    server_configurations::cluster_resources,
    server_configurations::twilio_config,
    server_configurations::bird_config,
    server_configurations::preferred_verification_apis,
    server_configurations::media_settings,
    server_configurations::stripe_config,
    server_configurations::market_settings,
    server_configurations::telnyx_config,
    server_configurations::supported_contact_protocols,
    server_configurations::stalwart_config,
    server_configurations::custom_css_configuration,
);

#[derive(Debug, Insertable)]
#[diesel(table_name = server_configurations)]
pub struct NewServerConfiguration {
    pub server_info: serde_json::Value,
    pub anonymous_user_permissions: serde_json::Value,
    pub default_user_permissions: serde_json::Value,
    pub basic_user_permissions: serde_json::Value,
    pub people_settings: serde_json::Value,
    pub group_settings: serde_json::Value,
    pub post_settings: serde_json::Value,
    pub event_settings: serde_json::Value,
    pub external_cdn_config: Option<serde_json::Value>,
    pub private_user_strategy: String,
    pub authentication_features: serde_json::Value,
    pub federation_info: serde_json::Value,
    pub web_push_config: Option<serde_json::Value>,
    pub custom_tabs: Option<serde_json::Value>,
    pub cluster_resources: Option<serde_json::Value>,
    pub twilio_config: Option<serde_json::Value>,
    pub bird_config: Option<serde_json::Value>,
    pub preferred_verification_apis: Option<serde_json::Value>,
    pub media_settings: Option<serde_json::Value>,
    pub stripe_config: Option<serde_json::Value>,
    pub market_settings: Option<serde_json::Value>,
    pub telnyx_config: Option<serde_json::Value>,
    pub supported_contact_protocols: Option<serde_json::Value>,
    pub stalwart_config: Option<serde_json::Value>,
    /// Always `None` out of `to_db` -- `ConfigureServer` carries the active row's value forward
    /// (see `configure_server`).
    pub custom_css_configuration: Option<serde_json::Value>,
    /// The custom stylesheet text -- a separate column that `ServerConfiguration` doesn't have (see
    /// `SERVER_CONFIGURATION_COLUMNS`). Always `None` out of `to_db` and `From<ServerConfiguration>`;
    /// whoever writes a new version carries the active row's value forward (see `ConfigureServer`) or sets it
    /// (`ConfigureCustomCSS`).
    pub custom_css: Option<String>,
}

/// A new version of an existing configuration: every setting copied, `id`/`active`/timestamps left
/// for the database to assign. Used by writers (e.g. `ConfigureCustomCSS`) that change only part of
/// the row outside the `ServerConfiguration` proto round trip.
impl From<ServerConfiguration> for NewServerConfiguration {
    fn from(c: ServerConfiguration) -> Self {
        NewServerConfiguration {
            server_info: c.server_info,
            anonymous_user_permissions: c.anonymous_user_permissions,
            default_user_permissions: c.default_user_permissions,
            basic_user_permissions: c.basic_user_permissions,
            people_settings: c.people_settings,
            group_settings: c.group_settings,
            post_settings: c.post_settings,
            event_settings: c.event_settings,
            external_cdn_config: c.external_cdn_config,
            private_user_strategy: c.private_user_strategy,
            authentication_features: c.authentication_features,
            federation_info: c.federation_info,
            web_push_config: c.web_push_config,
            custom_tabs: c.custom_tabs,
            cluster_resources: c.cluster_resources,
            twilio_config: c.twilio_config,
            bird_config: c.bird_config,
            preferred_verification_apis: c.preferred_verification_apis,
            media_settings: c.media_settings,
            stripe_config: c.stripe_config,
            market_settings: c.market_settings,
            telnyx_config: c.telnyx_config,
            supported_contact_protocols: c.supported_contact_protocols,
            stalwart_config: c.stalwart_config,
            custom_css_configuration: c.custom_css_configuration,
            custom_css: None,
        }
    }
}

pub fn default_server_configuration() -> NewServerConfiguration {
    let basic_user_permissions = vec![
        Permission::ViewUsers,
        Permission::FollowUsers,
        Permission::PublishUsersLocally,
        Permission::PublishUsersGlobally,
        Permission::ViewMedia,
        Permission::CreateMedia,
        Permission::PublishMediaLocally,
        Permission::PublishMediaGlobally,
        Permission::ViewGroups,
        Permission::JoinGroups,
        Permission::ViewPosts,
        Permission::CreatePosts,
        Permission::ReplyToPosts,
        Permission::PublishPostsLocally,
        Permission::PublishPostsGlobally,
        Permission::ReplyToPosts,
        Permission::ViewEvents,
        Permission::CreateEvents,
        Permission::PublishEventsLocally,
        Permission::PublishEventsGlobally,
        Permission::RsvpToEvents,
    ]
    .to_json_permissions();
    return NewServerConfiguration {
        server_info: serde_json::to_value(ServerInfo {
            name: Some("Rellm 🛠️ Unconfigured server".to_string()),
            short_name: None,
            description: Some("
This is a description of your server and/or the community, business, group, etc. you're running it for.
            ".to_string()),
            privacy_policy: Some("
Rellm is configured to be very private, but is also open-source. The privacy policy should mention any ways you might use private user data.
            ".to_string()),
            media_policy: Some("
Your media policy should describe who has ownership of uploaded media, anything you may use it for, etc.
            ".to_string()),
            logo: None,
            web_user_interface: Some(WebUserInterface::ElmSpa as i32),
            colors: Some(ServerColors {
                primary: Some(0xFF2E86AB),
                navigation: Some(0xFFA23B72),
                ..Default::default()
            }),
            ..Default::default()
        })
        .unwrap(),
        federation_info: serde_json::to_value(FederationInfo {
            servers: vec![
                FederatedServer {
                    host: "jonline.io".to_string(),
                    configured_by_default: Some(false),
                    pinned_by_default: Some(false),
                },
                FederatedServer {
                    host: "bullcity.social".to_string(),
                    configured_by_default: Some(false),
                    pinned_by_default: Some(false),
                },
                FederatedServer {
                    host: "oakcity.social".to_string(),
                    configured_by_default: Some(false),
                    pinned_by_default: Some(false),
                },
            ],
            facebook_auth_config: None,
            x_twitter_auth_config: None,
            mastodon_servers: vec![],
            unsecure_localhost_federated_auth_enabled: None,
         }).unwrap(),
        anonymous_user_permissions: vec![
            Permission::ViewUsers,
            Permission::ViewGroups,
            Permission::ViewPosts,
            Permission::ViewEvents,
            Permission::ViewMedia,
        ].to_json_permissions(),
        default_user_permissions: basic_user_permissions.to_owned(),
        basic_user_permissions: basic_user_permissions,
        people_settings: serde_json::to_value(FeatureSettings {
            visible: true,
            default_moderation: Moderation::Unmoderated as i32,
            default_visibility: Visibility::GlobalPublic as i32,
            alias_singular: None,
            alias_plural: None,
        })
        .unwrap(),
        group_settings: serde_json::to_value(FeatureSettings {
            visible: true,
            default_moderation: Moderation::Unmoderated as i32,
            default_visibility: Visibility::ServerPublic as i32,
            alias_singular: None,
            alias_plural: None,
        }).unwrap(),
        post_settings: serde_json::to_value(PostSettings {
            visible: true,
            default_moderation: Moderation::Unmoderated as i32,
            default_visibility: Visibility::ServerPublic as i32,
            alias_singular: None,
            alias_plural: None,
            enable_replies: Some(true),
        })
        .unwrap(),
        event_settings: serde_json::to_value(EventSettings {
            visible: true,
            default_moderation: Moderation::Unmoderated as i32,
            default_visibility: Visibility::ServerPublic as i32,
            alias_singular: None,
            alias_plural: None,
            enable_replies: Some(true),
            calendar_lookback_days: None,
            default_calendar_display_mode: CalendarDisplayMode::CalendarDisplayWeek as i32,
            show_started_or_long_events_by_default: false,
        })
        .unwrap(),
        external_cdn_config: None,
        web_push_config: None,
        custom_tabs: None,
        cluster_resources: None,
        twilio_config: None,
        bird_config: None,
        preferred_verification_apis: None,
        media_settings: None,
        stripe_config: None,
        market_settings: None,
        telnyx_config: None,
        supported_contact_protocols: None,
        stalwart_config: None,
        custom_css_configuration: None,
        custom_css: None,
        private_user_strategy: PrivateUserStrategy::AccountIsFrozen
            .as_str_name()
            .to_string(),
        authentication_features: serde_json::to_value(
            [
                AuthenticationFeature::Login,
                AuthenticationFeature::CreateAccount,
            ]
            .iter()
            .map(|it| it.as_str_name())
            .collect::<Vec<&str>>(),
        )
        .unwrap(),
    };
}
