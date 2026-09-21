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
}
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
