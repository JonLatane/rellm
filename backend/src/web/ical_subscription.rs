use super::RocketState;
use crate::marshaling::ToDbTime;
use crate::protos::{rsvp, GetEventsRequest, GetUsersRequest, User};
use crate::rpcs::events::parse_anonymous_auth_tokens;
use crate::rpcs::{get_events, get_server_configuration_proto, get_users};
use crate::web::external_cdn::configured_frontend_domain;
use chrono::{DateTime, Utc};
use icalendar::{Calendar, Component, Event, EventLike};
use rocket::http::uri::Host;
use rocket::{routes, Route, State};
use rocket_cache_response::CacheResponse;

lazy_static! {
    pub static ref ICAL_PAGES: Vec<Route> = routes![ical_subscription];
}

#[derive(rocket::Responder)]
#[response(content_type = "text/calendar")]
struct ICalResponse(String);

/// The server-wide (or, with `user_id`, one author's) event calendar -- or, with `post_id`, a
/// single Event's (every one of its Occasions, if `post_id` is the Event's own Post id) or a
/// single Occasion's (if it's an Occasion's Post id) calendar, e.g. for an "Add to Calendar"
/// download. `anonymous_auth_token` is passed straight through to `GetEvents` (so it takes the same
/// plain/multi-occasion forms -- see `rpcs::events::parse_anonymous_auth_tokens`), which reveals an
/// anonymous attendee's own location-hidden Occasions; an Occasion the token holds an RSVP for also
/// gets a "manage your RSVP" link in its description.
#[rocket::get("/calendar.ics?<user_id>&<post_id>&<anonymous_auth_token>")]
async fn ical_subscription(
    user_id: Option<String>,
    post_id: Option<String>,
    anonymous_auth_token: Option<String>,
    state: &State<RocketState>,
    host: &Host<'_>,
) -> CacheResponse<ICalResponse> {
    let mut conn = state.pool.get().unwrap();
    let server_configuration = get_server_configuration_proto(&mut conn).unwrap();
    let server_name = server_configuration
        .clone()
        .server_info
        .map(|i| i.name)
        .flatten()
        .unwrap_or("Rellm".to_string());
    // let server_logo_id = server_configuration
    //     .server_info
    //     .unwrap_or(ServerInfo {
    //         ..Default::default()
    //     })
    //     .logo
    //     .unwrap_or(ServerLogo {
    //         ..Default::default()
    //     })
    //     .square_media_id;
    // let server_logo = server_logo_id.map(|id| format!("/media/{}", id));

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
        //user.real_name.clone().unwrap_or(format!("User {}", user.id)),
        None => format!("User {}", &user_id.clone().unwrap_or("".to_string())),
    };

    // Create request for get_events RPC
    let post_id = post_id.filter(|id| !id.is_empty());
    let anonymous_auth_token = anonymous_auth_token.filter(|t| !t.is_empty());
    let request = GetEventsRequest {
        author_user_id: if post_id.is_some() { None } else { user_id.clone() },
        post_id: post_id.clone(),
        anonymous_attendee_auth_token: anonymous_auth_token.clone(),
        // time_filter: Some(TimeFilter {
        //     starts_after: Some(Utc::now().sub.to_db_time()),
        //     ..Default::default()
        // }),
        ..Default::default()
    };

    // Call get_events RPC (without user for anonymous access)
    let events_response = match get_events(request, &None, &mut conn) {
        Ok(response) => response,
        Err(e) => {
            return CacheResponse::no_store(ICalResponse(format!("Error fetching events: {e}")))
        }
    };

    // Create iCal calendar
    let mut calendar = Calendar::new();
    let single_event_title = match (&post_id, events_response.events.first()) {
        (Some(_), Some(event)) => event.post.as_ref().and_then(|p| p.title.clone()),
        _ => None,
    };
    match (&post_id, single_event_title) {
        (Some(_), Some(title)) => calendar.name(&format!("{title} | {server_name}")),
        (Some(_), None) => calendar.name(&format!("Event | {server_name}")),
        (None, _) => match user_id {
            Some(_) => calendar.name(&format!(
                "{author_user_name} | Event Calendar | {server_name}"
            )),
            None => calendar.name(&format!("{server_name} | Event Calendar")),
        },
    };
    let anonymous_auth_tokens =
        parse_anonymous_auth_tokens(anonymous_auth_token.as_deref());
    // calendar.name(&format!("{server_name} | Events Calendar"));
    // calendar.description("Events from Rellm");

    // Get the frontend domain for event links
    let frontend_domain = configured_frontend_domain(state, host);

    // Process each event and its occasions
    for event in events_response.events {
        let event_post = match &event.post {
            Some(post) => post,
            None => continue, // Skip events without posts
        };

        // `post_id` naming one of this Event's Occasions means just that one; an Event's own id
        // (or no `post_id` at all) means all of them.
        let only_occasion = post_id.as_ref().filter(|id| {
            event
                .occasions
                .iter()
                .any(|o| o.post.as_ref().map(|p| &p.id) == Some(*id))
        });

        for occasion in &event.occasions {
            let Some(occasion_post) = &occasion.post else {
                continue; // Skip occasions without posts
            };
            let occasion_id = &occasion_post.id;
            if only_occasion.map(|id| id != occasion_id).unwrap_or(false) {
                continue;
            }

            // Convert timestamps to DateTime<Utc>
            let starts_at = occasion
                .starts_at
                .as_ref()
                .map(|t| DateTime::<Utc>::from(t.to_db()))
                .unwrap_or(Utc::now());

            let ends_at = occasion
                .ends_at
                .as_ref()
                .map(|t| DateTime::<Utc>::from(t.to_db()))
                .unwrap_or(Utc::now());

            // Create event link
            let event_link = format!("https://{frontend_domain}/event/{occasion_id}");

            // The anonymous RSVP (if any) one of the given tokens holds for this Occasion.
            let rsvp_token = occasion
                .rsvps
                .as_ref()
                .into_iter()
                .flat_map(|r| r.rsvps.iter())
                .find_map(|rsvp| match &rsvp.attendee {
                    Some(rsvp::Attendee::AnonymousAttendee(a)) => a
                        .auth_token
                        .as_ref()
                        .filter(|t| anonymous_auth_tokens.contains(t)),
                    _ => None,
                });
            let description = match rsvp_token {
                Some(token) => format!(
                    "{}\n\nmanage your RSVP at:\n{event_link}?anonymousAuthToken={token}",
                    event_post.content.as_deref().unwrap_or("")
                ),
                None => event_post.content.clone().unwrap_or_default(),
            };

            // Create iCal event
            let mut ical_event = Event::new();
            ical_event
                .uid(&format!("{occasion_id}@{frontend_domain}"))
                .summary(event_post.title.as_deref().unwrap_or("Untitled Event"))
                .description(&description)
                .url(event_post.link.as_ref().unwrap_or(&event_link))
                .starts(starts_at)
                .ends(ends_at);

            // Add location if available
            if let Some(location) = &occasion.location {
                ical_event.location(&location.uniformly_formatted_address);
            }

            calendar.push(ical_event);
        }
    }

    // Generate iCal content
    let ical_content = calendar.to_string();

    CacheResponse::no_store(ICalResponse(ical_content))
}
