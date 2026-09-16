use itertools::Itertools;
use rellm_path::create_responder;

use rocket::{
    http::{uri::Origin, Status},
    State,
};
use rocket_cache_response::CacheResponse;
use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{
    protos::{custom_navigation_tab, GetPostsRequest, GetUsersRequest, NavigationTab, Permission},
    rpcs,
    web::RocketState,
};

use super::{
    rellm_path, root_app, spa_prefix, spa_web_path, strip_spa_prefix, RellmResponder,
    RellmSummary, SpaApp,
};

/// Fallback for arbitrary Tamagui build assets and username/custom-tab shortcut links (e.g.
/// "/someuser", or "/weddings" once a `CustomNavigationTab` in the server's own
/// `ServerConfiguration.custom_tabs` claims that path -- see `Pages.UsernameOrCustomTab_` on the
/// Elm side, which this route's social-preview rendering mirrors). Reading the asset itself is
/// always done from the Tamagui build directories (that's the only place these static exports
/// live), but once we fall through to rendering a page (rather than a raw file), an unprefixed
/// request defers to `root_app`/`WebUserInterface` like the rest of `spa_pages.rs`, so e.g.
/// "/someuser" renders Elm when the server is configured for it. Only ever mounted at root (see
/// rocket.rs).
///
/// `rank = 20`: this route's own shape ("/<file..>", fully dynamic) gives it
/// a better default Rocket rank than `elm_web::elm_file`'s ("/elm/<file..>",
/// static + dynamic), so without an explicit override it would steal asset
/// requests like "/elm/dist/elm.js" out from under that route -- this is
/// meant to be the last-resort fallback of the whole route table (it matches
/// literally any path), so it should always lose ties.
#[rocket::get("/<file..>", rank = 20)]
pub async fn spa_file_or_username_or_custom_tab(
    file: PathBuf,
    state: &State<RocketState>,
    origin: &Origin<'_>,
) -> CacheResponse<Result<RellmResponder, Status>> {
    log::info!("file_or_username_or_custom_tab: {:?}", &file);
    // See spa_web_path.rs: Next bakes a single fixed basePath into a build, so
    // "/" and "/tamagui" are served from two separate exports on disk. This
    // route is only ever mounted at root, so under the "/tamagui" prefix
    // `file` still carries a leading "tamagui" component that must be
    // stripped before joining it against either variant's directory -- that
    // directory already stands in for the prefix.
    let is_tamagui = spa_prefix(origin.path().as_str()) == Some(SpaApp::Tamagui);
    let (opt_dir, repo_dir) = if is_tamagui {
        ("tamagui_web_tamagui", "out-tamagui")
    } else {
        ("tamagui_web", "out")
    };
    let relative_file: PathBuf = if is_tamagui {
        file.strip_prefix("tamagui").unwrap_or(&file).to_path_buf()
    } else {
        file.clone()
    };
    // Namespaced so the two variants (which otherwise share relative filenames)
    // don't collide in rellm_path's cache.
    let cache_key = format!("{}/{}", opt_dir, relative_file.to_str().unwrap());
    let result: Result<RellmResponder, Status> =
        match fs::read_to_string(Path::new(&format!("opt/{}/", opt_dir)).join(&relative_file)) {
            Ok(body) => Ok(create_responder(&cache_key, body).await),
            Err(_) => {
                match fs::read_to_string(
                    Path::new(&format!("../frontends/tamagui/apps/next/{}/", repo_dir))
                        .join(&relative_file),
                ) {
                    Ok(body) => Ok(create_responder(&cache_key, body).await),
                    Err(_) => {
                        // TODO: Preload social link data (i.e., <meta property="og:title" ... />) for this user.
                        let mut connection = state.pool.get().unwrap();
                        let configuration =
                            rpcs::get_server_configuration_proto(&mut connection).unwrap();
                        let server_info = configuration.server_info.unwrap_or_default();
                        let app = spa_prefix(origin.path().as_str())
                            .unwrap_or_else(|| root_app(&server_info));
                        let server_name = server_info.name.clone().unwrap_or("Rellm".to_string());
                        let server_logo = server_info
                            .logo
                            .clone()
                            .unwrap_or_default()
                            .square_media_id
                            .map(|id| format!("/media/{}", id));
                        let path = strip_spa_prefix(origin.path().as_str());
                        let path_components = path.split('/').collect_vec();
                        // FUck it let's see if this works
                        if path_components.len() != 2 {
                            return spa_web_path(
                                app,
                                relative_file.to_str().unwrap(),
                                None,
                                is_tamagui,
                            )
                            .await;
                        }

                        let path_segment = path.split('/').last().unwrap().to_string();

                        // A `CustomNavigationTab` claiming this exact segment (see
                        // `UI.CustomNav.customTabFor` on the Elm side, which this mirrors) wins
                        // over the plain username lookup below, regardless of what it targets --
                        // `Pages.UsernameOrCustomTab_.customTabFor` always runs before its own
                        // username fallback, so a configured custom path beats a same-named user
                        // even when it points at a built-in tab like Events, not just a Post.
                        let matched_tab = configuration
                            .custom_tabs
                            .as_ref()
                            .and_then(|set| set.tabs.iter().find(|t| t.path == path_segment));

                        let (page_title, description, avatar) = match matched_tab
                            .and_then(|ct| ct.target.as_ref())
                        {
                            Some(custom_navigation_tab::Target::PostId(post_id)) => {
                                let post = rpcs::get_posts(
                                    GetPostsRequest {
                                        post_id: Some(post_id.clone()),
                                        ..Default::default()
                                    },
                                    &None,
                                    &mut connection,
                                )
                                .ok()
                                .map(|r| r.posts.into_iter().next())
                                .flatten();

                                let (default_title, description, avatar) = match post {
                                    Some(post) => {
                                        let default_title = post
                                            .title
                                            .clone()
                                            .unwrap_or_else(|| "Post".to_string());
                                        let description = post.content.clone();
                                        let avatar = post
                                            .media
                                            .first()
                                            .map(|m| format!("/media/{}", m.id));
                                        (default_title, description, avatar)
                                    }
                                    None => ("Post".to_string(), None, None),
                                };
                                // `title` (see `CustomNavigationTab.title`'s own proto doc)
                                // overrides the Post's own title if the admin's set one, e.g. so
                                // "/see_us_live" can read "See Us Live" instead of the Post's
                                // internal title.
                                let page_title = matched_tab
                                    .and_then(|ct| ct.title.clone())
                                    .unwrap_or(default_title);
                                (page_title, description, avatar)
                            }
                            Some(custom_navigation_tab::Target::Tab(nav_tab))
                                if NavigationTab::try_from(*nav_tab).is_ok() =>
                            {
                                let (default_title, description) =
                                    match NavigationTab::try_from(*nav_tab).unwrap() {
                                        NavigationTab::HomeTab => ("Home".to_string(), None),
                                        NavigationTab::EventsTab => (
                                            "Events".to_string(),
                                            Some(
                                                "Searchable, RSVPable Events from a Rellm community"
                                                    .to_string(),
                                            ),
                                        ),
                                        NavigationTab::PostsTab => (
                                            "Posts".to_string(),
                                            Some("Posts from a Rellm community".to_string()),
                                        ),
                                        NavigationTab::PeopleTab => (
                                            "People".to_string(),
                                            Some(
                                                "User listings for a Rellm community"
                                                    .to_string(),
                                            ),
                                        ),
                                        NavigationTab::AboutTab => (
                                            "About Community".to_string(),
                                            Some("Information a Rellm community".to_string()),
                                        ),
                                        NavigationTab::MarketTab => (
                                            "Market".to_string(),
                                            Some(
                                                "Products and subscriptions from a Rellm community"
                                                    .to_string(),
                                            ),
                                        ),
                                    };
                                let page_title = matched_tab
                                    .and_then(|ct| ct.title.clone())
                                    .unwrap_or(default_title);
                                (page_title, description, server_logo.clone())
                            }
                            // No matching custom tab, an `IsProfile` target (whose url *is* the
                            // matched username either way -- see `UI.CustomNav.CustomTabTarget`'s
                            // own doc), or an unrecognized `Tab` value all fall back to the plain
                            // username lookup, mirroring `Pages.UsernameOrCustomTab_.initEmbedded`'s
                            // own `NavigationTabUnrecognized_ -> initProfile` fallback.
                            _ => {
                                let username = Some(path_segment);
                                let user = rpcs::get_users(
                                    GetUsersRequest {
                                        username,
                                        ..Default::default()
                                    },
                                    &None,
                                    &mut connection,
                                )
                                .ok()
                                .map(|u| u.users.into_iter().next())
                                .flatten();

                                match user {
                                    Some(user) => {
                                        let is_business = user
                                            .permissions
                                            .contains(&(Permission::Business as i32));
                                        let page_title = format!(
                                            "{} - {}",
                                            match user.real_name {
                                                name if name != "" => name,
                                                _ => user.username.clone(),
                                            },
                                            // user.username.clone(),
                                            if is_business {
                                                "Business Profile"
                                            } else {
                                                "Profile"
                                            }
                                        );
                                        let description = user.bio.clone();
                                        let avatar = user
                                            .avatar
                                            .clone()
                                            .map(|a| format!("/media/{}", a.id));
                                        (page_title, Some(description), avatar)
                                    }
                                    None => ("Profile".to_string(), None, None),
                                }
                            }
                        };

                        let title = Some(format!("{} - {}", page_title, server_name));

                        let summary: Option<RellmSummary> = Some(RellmSummary {
                            title,
                            description,
                            image: avatar,
                        });
                        return spa_web_path(app, "[username].html", summary, is_tamagui).await;
                    }
                }
            }
        };
    CacheResponse::public(result, 60)
}
