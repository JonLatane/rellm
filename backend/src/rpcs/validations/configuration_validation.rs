// use super::OperationType;
// use super::{validate_email, validate_phone, validate_username};
use std::collections::HashSet;

use base64::{prelude::BASE64_URL_SAFE_NO_PAD, Engine};
use tonic::{Code, Status};

// use crate::conversions::*;
use crate::protos::*;

pub fn validate_configuration(config: &ServerConfiguration) -> Result<(), Status> {
    if let Some(custom_tabs) = config.custom_tabs.as_ref() {
        // `CustomHomePage`'s own proto doc restricts `target` to only `HOME_TAB` (i.e.
        // unset/default), `EVENTS_TAB`, `POSTS_TAB`, or a `post_id` -- its `oneof` doesn't even
        // have a `PEOPLE_TAB`/`ABOUT_TAB`/`is_profile` branch to construct in the first place
        // (see `CustomHomePage.target`), so only `tab` needs narrowing here. The Elm admin editor
        // (`CustomTabsConfiguration.applyCustomTabs`/`UI.CustomNav.toProtoHome`, gated on
        // `UI.CustomNav.selectableHomeTargetKinds`) never constructs anything else, so this only
        // ever actually fires for a hand-edited/future-versioned config.
        if let Some(home) = custom_tabs.home.as_ref() {
            let home_target_ok = match home.target.as_ref() {
                None => true,
                Some(custom_home_page::Target::Tab(tab)) => {
                    *tab == NavigationTab::HomeTab as i32
                        || *tab == NavigationTab::EventsTab as i32
                        || *tab == NavigationTab::PostsTab as i32
                }
                Some(custom_home_page::Target::PostId(_)) => true,
            };
            if !home_target_ok {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "home_target_must_be_home_events_posts_tab_or_post_id",
                ));
            }
        }

        let mut seen_paths = HashSet::new();
        for tab in &custom_tabs.tabs {
            let is_profile_tab = matches!(
                tab.target.as_ref(),
                Some(custom_navigation_tab::Target::IsProfile(_))
            );
            super::validate_custom_tab_path(&tab.path, is_profile_tab)?;
            if !seen_paths.insert(tab.path.as_str()) {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "custom_tab_paths_must_be_distinct",
                ));
            }

            // "events", "posts", "people", "about", and "market" are reserved as top-level paths
            // (see `RESERVED_PATHS`/`CUSTOM_TAB_RESERVED_PATHS`), but still permitted as custom
            // tab paths since they're the predefined tabs' own paths. Make sure they're only ever
            // used to point to their matching `NavigationTab`, not remapped to a different tab
            // or a Post.
            let required_tab = match tab.path.as_str() {
                "events" => Some((NavigationTab::EventsTab, "events_path_must_point_to_events_tab")),
                "posts" => Some((NavigationTab::PostsTab, "posts_path_must_point_to_posts_tab")),
                "people" => Some((NavigationTab::PeopleTab, "people_path_must_point_to_people_tab")),
                "about" => Some((NavigationTab::AboutTab, "about_path_must_point_to_about_tab")),
                "market" => Some((NavigationTab::MarketTab, "market_path_must_point_to_market_tab")),
                _ => None,
            };
            if let Some((required_tab, error_message)) = required_tab {
                if tab.target != Some(custom_navigation_tab::Target::Tab(required_tab as i32)) {
                    return Err(Status::new(Code::InvalidArgument, error_message));
                }
            }
        }
    }

    if config.people_settings.as_ref().unwrap().default_visibility
        == Visibility::GlobalPublic as i32
        && !config
            .default_user_permissions
            .contains(&(Permission::PublishUsersGlobally as i32))
    {
        return Err(Status::new(
            Code::InvalidArgument,
            "global_public_users_require_PUBLISH_USERS_GLOBALLY_permission",
        ));
    }

    let external_edn_config = config.external_cdn_config.to_owned();
    let backend_host = external_edn_config.to_owned().map(|c| c.backend_host);
    let frontend_host = external_edn_config.map(|c| c.frontend_host);
    match (backend_host, frontend_host) {
        (None, None) => (),
        (Some(be), Some(fe)) if !be.is_empty() && !fe.is_empty() => (),
        _ => {
            return Err(Status::new(
                Code::InvalidArgument,
                "default_client_domain_cannot_be_empty",
            ))
        }
    }

    if let Some(web_push_config) = config.web_push_config.as_ref() {
        validate_vapid_public_key(&web_push_config.public_vapid_key)?;
        validate_vapid_private_key(&web_push_config.private_vapid_key)?;
    }

    Ok(())
}

/// A VAPID public key is a P-256 point in SEC1 uncompressed form -- `0x04` followed by 32-byte X
/// and Y coordinates, 65 bytes total, base64url-no-pad encoded (87 characters). Rejects anything
/// else up front, at save time, with a clear error -- confirmed in production: a corrupted paste
/// (a handful of characters from the *private* key, sitting right next to the public key in
/// `web-push generate-vapid-keys`'s own output, swept up in the same copy) saved successfully and
/// only surfaced later as a cryptic "applicationServerKey is not valid" browser error the moment
/// someone actually tried to subscribe.
fn validate_vapid_public_key(public_vapid_key: &str) -> Result<(), Status> {
    if public_vapid_key.is_empty() {
        // Not yet configured -- see `WebPushPublicKeyEditClicked`'s own initial blank pending
        // value, and `applyWebPushPrivateKey`'s `existingPublicKey` fallback.
        return Ok(());
    }
    let decoded = BASE64_URL_SAFE_NO_PAD
        .decode(public_vapid_key)
        .map_err(|_| Status::new(Code::InvalidArgument, "public_vapid_key_is_not_valid_base64url"))?;
    if decoded.len() != 65 || decoded[0] != 0x04 {
        return Err(Status::new(
            Code::InvalidArgument,
            "public_vapid_key_must_be_a_65_byte_uncompressed_p256_point",
        ));
    }
    Ok(())
}

/// A VAPID private key is the raw 32-byte P-256 scalar, base64url-no-pad encoded (43 characters).
/// Blank means "leave whatever's already stored alone" (see `configure_server`'s merge-on-blank
/// block) -- not validated here, since a blank incoming value is never actually what ends up
/// stored either way. A non-blank value that's the wrong shape, though, previously saved
/// successfully and only surfaced much later as either a production panic (`jwt_simple`'s bare
/// `assert_eq!` on the decoded byte count) or, once that crash was fixed to a graceful error
/// instead, a permanently and silently broken send (see `web_push::validate_private_vapid_key`'s
/// own doc comment for both) -- catching it here means neither ever happens.
fn validate_vapid_private_key(private_vapid_key: &str) -> Result<(), Status> {
    if private_vapid_key.is_empty() {
        return Ok(());
    }
    let decoded = BASE64_URL_SAFE_NO_PAD
        .decode(private_vapid_key)
        .map_err(|_| Status::new(Code::InvalidArgument, "private_vapid_key_is_not_valid_base64url"))?;
    if decoded.len() != 32 {
        return Err(Status::new(
            Code::InvalidArgument,
            "private_vapid_key_must_be_a_32_byte_p256_scalar",
        ));
    }
    Ok(())
}
