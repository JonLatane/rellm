//! Mirrors `web::ical_subscription` -- an RSS 2.0 feed of a user's (or, with no `user_id`, the
//! whole server's) plain Posts, for subscribing in a feed reader. The reverse direction of
//! `logic::sync_sources::feed_sync` (which pulls an *external* RSS/Atom feed's items in as
//! Posts): this endpoint serves Rellm's own Posts back out as one.

use super::RocketState;
use crate::marshaling::ToDbTime;
use crate::protos::{GetPostsRequest, GetUsersRequest, PostContext, User};
use crate::rpcs::{get_posts_for, get_server_configuration_proto, get_users};
use crate::web::external_cdn::configured_frontend_domain;
use chrono::{DateTime, Utc};
use rocket::http::uri::Host;
use rocket::{routes, Route, State};
use rocket_cache_response::CacheResponse;
use rss::{Channel, Guid, Item};

lazy_static! {
    pub static ref RSS_PAGES: Vec<Route> = routes![rss_subscription];
}

#[derive(rocket::Responder)]
#[response(content_type = "application/rss+xml")]
struct RssResponse(String);

#[rocket::get("/rss.xml?<user_id>")]
async fn rss_subscription(
    user_id: Option<String>,
    state: &State<RocketState>,
    host: &Host<'_>,
) -> CacheResponse<RssResponse> {
    let mut conn = state.pool.get().unwrap();
    // On a Rellm Subdomain the feed is the owner's (plus whatever they share) and is named after them.
    let subdomain = match crate::web::subdomain_web::request_subdomain(&mut conn, host) {
        Ok(subdomain) => subdomain,
        Err(e) => return CacheResponse::no_store(RssResponse(format!("Error resolving subdomain: {e}"))),
    };
    let server_configuration = match &subdomain {
        Some(subdomain) => subdomain
            .virtual_server_configuration(get_server_configuration_proto(&mut conn).unwrap(), &None),
        None => get_server_configuration_proto(&mut conn).unwrap(),
    };
    let server_name = server_configuration
        .server_info
        .map(|i| i.name)
        .flatten()
        .unwrap_or("Rellm".to_string());

    let author_user: Option<User> = match &user_id {
        Some(id) if !id.is_empty() => {
            let request = GetUsersRequest {
                user_id: user_id.clone(),
                ..Default::default()
            };
            match get_users(request, &None, &mut conn) {
                Ok(response) => response.users.into_iter().next(),
                Err(_) => None,
            }
        }
        _ => None, // Anonymous access
    };
    let author_user_name = match &author_user {
        Some(user) => match &user.real_name {
            name if name != "" => name.clone(),
            _ => user.username.clone(),
        },
        None => format!("User {}", &user_id.clone().unwrap_or("".to_string())),
    };

    // Only top-level Posts, same as `event_sync`/`ical_subscription` never surface Replies --
    // `PostListingType::AllAccessiblePosts` (its default) already restricts to SERVER_PUBLIC/
    // GLOBAL_PUBLIC visibility, same as `ical_subscription`'s `get_events` call relies on.
    let request = GetPostsRequest {
        author_user_id: user_id.clone(),
        context: Some(PostContext::Post as i32),
        ..Default::default()
    };

    let posts_response = match get_posts_for(request, &None, &subdomain, &mut conn) {
        Ok(response) => response,
        Err(e) => return CacheResponse::no_store(RssResponse(format!("Error fetching posts: {e}"))),
    };

    let frontend_domain = crate::web::subdomain_web::feed_frontend_domain(
        configured_frontend_domain(state, host),
        &subdomain,
    );
    let channel_link = format!("https://{frontend_domain}/");

    let items: Vec<Item> = posts_response
        .posts
        .into_iter()
        .map(|post| {
            let post_link = format!("https://{frontend_domain}/post/{}", post.id);
            let pub_date = post
                .created_at
                .as_ref()
                .map(|t| DateTime::<Utc>::from(t.to_db()).to_rfc2822());
            Item {
                title: post.title,
                link: Some(post.link.unwrap_or_else(|| post_link.clone())),
                description: post.content,
                guid: Some(Guid {
                    value: post_link,
                    permalink: false,
                }),
                pub_date,
                ..Default::default()
            }
        })
        .collect();

    let channel = Channel {
        title: match user_id {
            Some(_) => format!("{author_user_name} | Posts | {server_name}"),
            None => format!("{server_name} | Posts"),
        },
        link: channel_link,
        description: format!("Posts from {server_name}"),
        items,
        ..Default::default()
    };

    CacheResponse::no_store(RssResponse(channel.to_string()))
}
