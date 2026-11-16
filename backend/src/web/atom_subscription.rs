//! Mirrors `web::rss_subscription` exactly, just serialized as an Atom feed instead of RSS 2.0
//! (see that module's own doc for the overall direction/rationale).

use super::RocketState;
use crate::marshaling::ToDbTime;
use crate::protos::{GetPostsRequest, GetUsersRequest, PostContext, User};
use crate::rpcs::{get_posts_for, get_server_configuration_proto, get_users};
use crate::web::external_cdn::configured_frontend_domain;
use atom_syndication::{Content, Entry, Feed, Link, Text};
use chrono::{DateTime, Utc};
use rocket::http::uri::Host;
use rocket::{routes, Route, State};
use rocket_cache_response::CacheResponse;

lazy_static! {
    pub static ref ATOM_PAGES: Vec<Route> = routes![atom_subscription];
}

#[derive(rocket::Responder)]
#[response(content_type = "application/atom+xml")]
struct AtomResponse(String);

#[rocket::get("/atom.xml?<user_id>")]
async fn atom_subscription(
    user_id: Option<String>,
    state: &State<RocketState>,
    host: &Host<'_>,
) -> CacheResponse<AtomResponse> {
    let mut conn = state.pool.get().unwrap();
    // On a Rellm Subdomain the feed is the owner's (plus whatever they share) and is named after them.
    let subdomain = crate::web::subdomain_web::request_subdomain(&mut conn, host);
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

    let request = GetPostsRequest {
        author_user_id: user_id.clone(),
        context: Some(PostContext::Post as i32),
        ..Default::default()
    };

    let posts_response = match get_posts_for(request, &None, &subdomain, &mut conn) {
        Ok(response) => response,
        Err(e) => {
            return CacheResponse::no_store(AtomResponse(format!("Error fetching posts: {e}")))
        }
    };

    let frontend_domain = crate::web::subdomain_web::feed_frontend_domain(
        configured_frontend_domain(state, host),
        &subdomain,
    );
    let feed_link = format!("https://{frontend_domain}/");
    let now: DateTime<Utc> = Utc::now();

    let entries: Vec<Entry> = posts_response
        .posts
        .into_iter()
        .map(|post| {
            let post_link = format!("https://{frontend_domain}/post/{}", post.id);
            let updated: DateTime<Utc> = post
                .updated_at
                .as_ref()
                .or(post.created_at.as_ref())
                .map(|t| DateTime::<Utc>::from(t.to_db()))
                .unwrap_or(now);
            let published: Option<DateTime<Utc>> = post
                .created_at
                .as_ref()
                .map(|t| DateTime::<Utc>::from(t.to_db()));
            Entry {
                title: Text::plain(post.title.unwrap_or_else(|| "Untitled Post".to_string())),
                id: post_link.clone(),
                updated: updated.into(),
                links: vec![Link {
                    href: post.link.unwrap_or(post_link),
                    ..Default::default()
                }],
                summary: post.content.clone().map(Text::plain),
                content: post.content.map(|content| Content {
                    value: Some(content),
                    content_type: Some("text".to_string()),
                    ..Default::default()
                }),
                published: published.map(|p| p.into()),
                ..Default::default()
            }
        })
        .collect();

    let feed = Feed {
        title: Text::plain(match user_id {
            Some(_) => format!("{author_user_name} | Posts | {server_name}"),
            None => format!("{server_name} | Posts"),
        }),
        id: feed_link.clone(),
        updated: now.into(),
        links: vec![Link {
            href: feed_link,
            ..Default::default()
        }],
        subtitle: Some(Text::plain(format!("Posts from {server_name}"))),
        entries,
        ..Default::default()
    };

    let mut buf: Vec<u8> = Vec::new();
    let atom_content = match feed.write_to(&mut buf) {
        Ok(_) => String::from_utf8(buf).unwrap_or_default(),
        Err(e) => return CacheResponse::no_store(AtomResponse(format!("Error generating feed: {e}"))),
    };

    CacheResponse::no_store(AtomResponse(atom_content))
}
