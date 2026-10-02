use std::collections::HashMap;

use diesel::*;
use diesel_full_text_search::{
    configuration::TsConfigurationByName, to_tsquery_with_search_config, ts_rank_cd,
    TsVectorExtensions,
};
use log::info;
use serde_json::json;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::marshaling::*;
use crate::models;
use crate::models::AUTHOR_COLUMNS;
use crate::models::{get_group, get_membership};
use crate::protos::*;
use crate::rpcs::validate_group_permission;
use crate::rpcs::validations::PASSING_MODERATIONS;
use crate::schema::*;
use prost_wkt_types::Timestamp;

const LISTING_OCCASION_LIMIT: i64 = 160;
const SINGLE_OCCASION_LIMIT: i64 = 1000;

type EventLoadData = (
    models::Occasion,
    models::Event,
    models::Post,
    Option<models::Author>,
    models::Post,
    Option<models::Author>,
);

pub fn get_events(
    request: GetEventsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetEventsResponse, Status> {
    let result: Vec<MarshalableEvent> = if !request.occasion_post_ids.is_empty() {
        get_events_by_occasion_post_ids(&user, &request.occasion_post_ids, conn)?
    } else {
        match (
            request.listing_type(),
            request.to_owned().author_user_id,
            request.to_owned().post_id,
        ) {
            // TODO: implement the other listing types
            (EventListingType::EventTextSearch, _, _) => get_search_events(&request, &user, conn)?,
            (EventListingType::GroupEvents, _, _) => match &request.group_id {
                Some(group_id) => get_group_events(
                    group_id.to_db_id_or_err("group_id")?,
                    &user,
                    conn,
                    request.time_filter,
                )?,
                _ => return Err(Status::new(Code::InvalidArgument, "group_id_invalid")),
            },
            (_, Some(author_user_id), _) => get_user_events(
                author_user_id.to_db_id_or_err("author_user_id")?,
                user,
                conn,
                request.time_filter,
            )?,
            (_, _, Some(post_id)) => get_event_by_post_id(&user, &post_id, conn)?,
            _ => get_public_and_following_events(&user, conn, request.time_filter)?,
        }
    };
    let mut events = convert_events(&result, conn);
    attach_occasion_rsvps(&result, &mut events, &request, &user, conn);
    Ok(GetEventsResponse { events })
}

// Per-occasion context `attach_occasion_rsvps` needs but that isn't already sitting
// on `models::Rsvp` -- both come from the *parent Event*, not the occasion itself
// (`event_post.0.user_id`/`event.info` are shared across every occasion of that Event), so this
// is computed once per Event up front rather than re-derived per occasion.
struct OccasionRsvpContext {
    owner_user_id: Option<i64>,
    hide_location_until_rsvp_approved: bool,
}

fn rsvp_matches_anonymous_token(
    rsvp: &models::Rsvp,
    token: Option<&str>,
) -> bool {
    token.is_some()
        && rsvp
            .anonymous_attendee
            .as_ref()
            .and_then(|a| a.get("auth_token"))
            .and_then(|t| t.as_str())
            == token
}

// Loads rsvp info for every `Occasion` about to be returned, in one query keyed by
// `occasion_id IN (...)`, and attaches it as `Occasion.rsvps`/
// `current_user_rsvp` -- sparing callers (e.g. the Elm SPA's Posts page) a separate
// `GetRsvps` round trip per occasion just to show RSVP info. Also resolves
// `Occasion.location` (and mirrors it into `Rsvps.hidden_location`) the same way,
// since whether it's visible depends on the very rsvp data being loaded here.
//
// Deliberately mirrors `get_rsvps`'s own visibility rules field-for-field (see that
// RPC's doc comments for the reasoning behind each): moderation-passing rsvps are visible to
// everyone, an Event's owner sees every rsvp (regardless of moderation) for their own
// occasions, a viewer always sees their own rsvp regardless of moderation, and
// `request.anonymous_attendee_auth_token` (mirroring
// `GetRsvpsRequest.anonymous_attendee_auth_token`) unlocks an anonymous attendee's own
// record the same way. `private_note` and the real `location` (once
// `EventInfo.hide_location_until_rsvp_approved` is set) are likewise only revealed to the
// rsvp's own owner/attendee or the Event owner. Keeping these two RPCs' rules in sync by
// hand is exactly the kind of thing `get_rsvps_parity_tests` guards against drifting.
fn attach_occasion_rsvps(
    result: &[MarshalableEvent],
    events: &mut [Event],
    request: &GetEventsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) {
    let current_user_id = user.map(|u| u.id);
    let anonymous_auth_token = request.anonymous_attendee_auth_token.as_deref();

    let mut context_by_occasion: HashMap<i64, OccasionRsvpContext> = HashMap::new();
    for MarshalableEvent(event, event_post, occasions) in result {
        let hide_location_until_rsvp_approved = event.info["hide_location_until_rsvp_approved"]
            .as_bool()
            .unwrap_or(false);
        for MarshalableOccasion(occasion, _) in occasions {
            context_by_occasion.insert(
                occasion.post_id,
                OccasionRsvpContext {
                    owner_user_id: event_post.0.user_id,
                    hide_location_until_rsvp_approved,
                },
            );
        }
    }

    let occasion_ids: Vec<i64> = context_by_occasion.keys().cloned().collect();
    if occasion_ids.is_empty() {
        return;
    }

    let owned_occasion_ids: Vec<i64> = context_by_occasion
        .iter()
        .filter(|(_, context)| {
            current_user_id.is_some() && context.owner_user_id == current_user_id
        })
        .map(|(occasion_id, _)| *occasion_id)
        .collect();

    let rsvps: Vec<(models::Rsvp, Option<models::Author>)> =
        rsvps::table
            .left_join(users::table.on(rsvps::user_id.eq(users::id.nullable())))
            .select((rsvps::all_columns, AUTHOR_COLUMNS.nullable()))
            .filter(rsvps::occasion_id.eq_any(&occasion_ids))
            .filter(
                rsvps::occasion_id
                    .eq_any(&owned_occasion_ids)
                    .or(rsvps::moderation.eq_any(PASSING_MODERATIONS))
                    .or(rsvps::user_id.eq(current_user_id.unwrap_or(0)))
                    .or(rsvps::anonymous_attendee
                        .contains(json!({"auth_token": anonymous_auth_token}))),
            )
            .load::<(models::Rsvp, Option<models::Author>)>(conn)
            .unwrap_or_default();

    let media_ids = rsvps
        .iter()
        .filter_map(|(_, author)| author.as_ref().and_then(|a| a.avatar_media_id))
        .collect();
    let media_lookup = load_media_lookup(media_ids, conn);

    let mut rsvps_by_occasion: HashMap<
        i64,
        Vec<(models::Rsvp, Option<models::Author>)>,
    > = HashMap::new();
    for entry in rsvps {
        rsvps_by_occasion
            .entry(entry.0.occasion_id)
            .or_default()
            .push(entry);
    }

    for (marshalable_event, event) in result.iter().zip(events.iter_mut()) {
        for (MarshalableOccasion(occasion, _), occasion_proto) in
            marshalable_event.2.iter().zip(event.occasions.iter_mut())
        {
            let context = &context_by_occasion[&occasion.post_id];
            let is_owner = current_user_id.is_some() && context.owner_user_id == current_user_id;
            let occasion_rsvps = rsvps_by_occasion
                .get(&occasion.post_id)
                .cloned()
                .unwrap_or_default();

            let is_viewers_own = |a: &models::Rsvp| {
                (current_user_id.is_some() && a.user_id == current_user_id)
                    || rsvp_matches_anonymous_token(a, anonymous_auth_token)
            };

            let is_approved_attendee = is_owner
                || occasion_rsvps.iter().any(|(a, _)| {
                    a.moderation == Moderation::Approved.to_string_moderation() && is_viewers_own(a)
                });

            let visible_location =
                if is_approved_attendee || !context.hide_location_until_rsvp_approved {
                    occasion.location.clone().map(|l| l.to_proto_location())
                } else {
                    None
                };
            occasion_proto.location = visible_location.clone();

            occasion_proto.current_user_rsvp = occasion_rsvps
                .iter()
                .find(|(a, _)| is_viewers_own(a))
                .map(|entry| entry.to_proto(true, true, media_lookup.as_ref()));

            occasion_proto.rsvps = Some(Rsvps {
                rsvps: occasion_rsvps
                    .iter()
                    .map(|entry| {
                        let include_private_note = is_owner || is_viewers_own(&entry.0);
                        entry.to_proto(
                            include_private_note,
                            include_private_note,
                            media_lookup.as_ref(),
                        )
                    })
                    .collect(),
                hidden_location: visible_location,
            });
        }
    }
}

macro_rules! query_visible_events {
    ($user:expr, $timefilter:expr) => {
        query_visible_events!($user, $timefilter, LISTING_OCCASION_LIMIT)
    };
    ($user:expr, $timefilter:expr, $occasion_limit:expr) => {{
        let occasion_posts = alias!(posts as occasion_posts);
        let occasion_users = alias!(users as occasion_users);

        let ends_after = $timefilter
            .map(|f| f.ends_after.map(|t| t.to_db()))
            .flatten()
            .unwrap_or(
                Timestamp {
                    seconds: 100,
                    nanos: 0,
                }
                .to_db(),
            );
        info!("query_visible_events ends_after={:?}", ends_after);

        occasions::table
            .inner_join(events::table.on(events::post_id.eq(occasions::event_id)))
            .inner_join(posts::table.on(posts::id.eq(events::post_id)))
            .left_join(users::table.on(posts::user_id.eq(users::id.nullable())))
            .left_join(
                follows::table.on(posts::user_id.eq(follows::target_user_id.nullable()).and(
                    follows::user_id
                        .nullable()
                        .eq($user.as_ref().map(|u| u.id).unwrap_or(0)),
                )),
            )
            .left_join(group_posts::table.on(posts::id.eq(group_posts::post_id)))
            .left_join(
                memberships::table.on(memberships::user_id
                    .eq($user.as_ref().map(|u| u.id).unwrap_or(0))
                    .and(memberships::group_id.eq(group_posts::group_id))),
            )
            .inner_join(
                occasion_posts.on(occasions::post_id.eq(occasion_posts.field(posts::id))),
            )
            .left_join(
                occasion_users.on(occasion_posts
                    .field(posts::user_id)
                    .eq(occasion_users.field(users::id).nullable())),
            )
            .select((
                models::OCCASION_COLUMNS,
                events::all_columns,
                models::POST_COLUMNS,
                AUTHOR_COLUMNS.nullable(),
                occasion_posts.fields(models::POST_COLUMNS),
                occasion_users.fields(AUTHOR_COLUMNS).nullable(),
            ))
            //TODO UNCOMMENT THISSSS
            .filter(
                posts::visibility
                    .eq_any(public_string_visibilities($user))
                    .or(posts::visibility
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(follows::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    .or(posts::visibility
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(memberships::user_moderation.eq_any(PASSING_MODERATIONS))
                        .and(memberships::group_moderation.eq_any(PASSING_MODERATIONS))
                        .and(memberships::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    .or(posts::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))),
            )
            .filter(
                occasion_posts
                    .field(posts::visibility)
                    .eq_any(public_string_visibilities($user))
                    .or(occasion_posts
                        .field(posts::visibility)
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(follows::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    .or(occasion_posts
                        .field(posts::visibility)
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(memberships::user_moderation.eq_any(PASSING_MODERATIONS))
                        .and(memberships::group_moderation.eq_any(PASSING_MODERATIONS))
                        .and(memberships::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    .or(occasion_posts
                        .field(posts::user_id)
                        .eq($user.as_ref().map(|u| u.id).unwrap_or(0))),
            )
            .filter(
                posts::moderation
                    .eq_any(PASSING_MODERATIONS)
                    .or(posts::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))),
            )
            .filter(posts::user_id.is_not_null())
            .filter(occasions::ends_at.gt(ends_after))
            .order(occasions::starts_at)
            .distinct()
            .limit($occasion_limit)
    }};
}

macro_rules! marshalable_event_data {
    ($event_data:expr) => {{
        $event_data
            .iter()
            .map(
                |(occasion, event, event_post, event_author, occasion_post, occasion_author)| {
                    info!("occasion: {:?}", occasion);
                    MarshalableEvent(
                        event.clone(),
                        MarshalablePost(
                            event_post.clone(),
                            event_author.clone(),
                            None,
                            None,
                            vec![],
                        ),
                        vec![MarshalableOccasion(
                            occasion.clone(),
                            MarshalablePost(
                                occasion_post.clone(),
                                occasion_author.clone(),
                                None,
                                None,
                                vec![],
                            ),
                        )],
                    )
                },
            )
            .collect()
    }};
}

fn get_public_and_following_events(
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
    filter: Option<TimeFilter>,
) -> Result<Vec<MarshalableEvent>, Status> {
    let query = query_visible_events!(user, filter);
    let binding = query.load::<EventLoadData>(conn).unwrap();
    let event_data: Vec<&EventLoadData> = binding.iter().collect();

    Ok(marshalable_event_data!(event_data))
}

fn get_user_events(
    user_id: i64,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
    filter: Option<TimeFilter>,
) -> Result<Vec<MarshalableEvent>, Status> {
    let query = query_visible_events!(user, filter).filter(posts::user_id.eq(user_id));
    let binding = query.load::<EventLoadData>(conn).unwrap();
    let event_data: Vec<&EventLoadData> = binding.iter().collect();

    Ok(marshalable_event_data!(event_data))
}

// Full-text search across accessible Occasions' own-Post and parent-Event-Post title/
// content/author username/author real name (see occasions.search_text's own doc,
// backend/migrations/2026-07-30-170000_add_search_text_to_occasions). Still respects
// `request.time_filter` -- the caller's current Upcoming/After-date tab, same as every other
// listing type here -- and, when scoped to an author, filters on the denormalized
// `occasions::user_id` -- matching the composite GIN index added alongside search_text, so
// each of those filter combinations is served by a single index scan.
fn get_search_events(
    request: &GetEventsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalableEvent>, Status> {
    let search_text = request
        .search_text
        .as_deref()
        .map(str::trim)
        .filter(|search_text| !search_text.is_empty())
        .ok_or(Status::new(Code::InvalidArgument, "search_text_required"))?;
    let prefix_query_text = prefix_tsquery_text(search_text);
    if prefix_query_text.is_empty() {
        return Err(Status::new(Code::InvalidArgument, "search_text_required"));
    }
    let author_user_id = request
        .author_user_id
        .as_ref()
        .map(|author_user_id| author_user_id.to_db_id_or_err("author_user_id"))
        .transpose()?;

    // Prefix (not just whole/stemmed lexeme) matching, "simple" config -- mirrors
    // get_search_posts's own tsquery setup (see that function's doc comment for why).
    let search_query =
        to_tsquery_with_search_config(TsConfigurationByName("simple"), prefix_query_text.clone());
    // A second, independent tsquery expression for the rank calculation below -- `search_query`
    // above is consumed by `.matches(...)`, and the generated tsquery expression type isn't Clone.
    let rank_query =
        to_tsquery_with_search_config(TsConfigurationByName("simple"), prefix_query_text);

    // `query_visible_events!`'s joins can produce more than one row per matching occasion, so it
    // applies `SELECT DISTINCT` -- which Postgres requires every ORDER BY expression to appear in
    // the select list for. That's fine for the other GetEvents branches (they order by a plain
    // column), but `ts_rank_cd(...)` takes a bind parameter that can't structurally match between
    // a `.select(...)` and an `.order(...)` (see get_search_posts's own doc comment for the full
    // explanation). So this resolves matching occasion ids DISTINCT-ly first (a plain
    // `occasions::id` has no such problem), then ranks and orders the (already-unique)
    // matches in a second, DISTINCT-free query.
    // `query_visible_events!` bakes in `.order(occasions::starts_at)` (for its own normal
    // listing callers) ahead of its own `.distinct()` -- Postgres requires every ORDER BY
    // expression to appear in the SELECT list under SELECT DISTINCT, so once `.select(...)` below
    // narrows that list down to just `id`, the order has to be overridden to match (a plain `id`
    // order is fine here regardless -- this query only collects ids, `binding` below is what's
    // actually ordered by rank).
    let mut matching_occasion_ids = query_visible_events!(user, request.time_filter)
        .select(occasions::post_id)
        .order(occasions::post_id)
        .filter(occasions::search_text.matches(search_query))
        .into_boxed();

    if let Some(author_user_id) = author_user_id {
        matching_occasion_ids =
            matching_occasion_ids.filter(occasions::user_id.eq(author_user_id));
    }

    let occasion_posts = alias!(posts as occasion_posts);
    let occasion_users = alias!(users as occasion_users);

    let binding: Vec<EventLoadData> = occasions::table
        .inner_join(events::table.on(events::post_id.eq(occasions::event_id)))
        .inner_join(posts::table.on(posts::id.eq(events::post_id)))
        .left_join(users::table.on(posts::user_id.eq(users::id.nullable())))
        .inner_join(occasion_posts.on(occasions::post_id.eq(occasion_posts.field(posts::id))))
        .left_join(
            occasion_users.on(occasion_posts
                .field(posts::user_id)
                .eq(occasion_users.field(users::id).nullable())),
        )
        .filter(occasions::post_id.eq_any(matching_occasion_ids))
        .select((
            models::OCCASION_COLUMNS,
            events::all_columns,
            models::POST_COLUMNS,
            AUTHOR_COLUMNS.nullable(),
            occasion_posts.fields(models::POST_COLUMNS),
            occasion_users.fields(AUTHOR_COLUMNS).nullable(),
        ))
        // Search results are ordered by match quality first, falling back to start time to keep
        // ordering stable across the (common, with prefix matching) rank ties -- mirrors
        // get_search_posts's own recency fallback.
        .order(ts_rank_cd(occasions::search_text, rank_query).desc())
        .then_order_by(occasions::starts_at.desc())
        .limit(LISTING_OCCASION_LIMIT)
        .load::<EventLoadData>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_events"))?;
    let event_data: Vec<&EventLoadData> = binding.iter().collect();

    Ok(marshalable_event_data!(event_data))
}

// Batch lookup for `GetEventsRequest.occasion_post_ids` -- e.g. the Elm
// frontend's Starred panel (`Shared.StarredPanel`), which already has a flat
// list of starred `Post` ids (some of which may turn out to be an
// `Occasion`'s own Post, per `PostContext.OCCASION`) and wants
// their owning `Event`/`Occasion` data in one request rather than one
// `occasion_id`-scoped `GetEvents` call per starred post. Unlike
// `get_event_by_id` (which returns the *whole* `Event` with every one of its
// occasions, for the single-event detail page's date-picker strip), this
// mirrors `get_public_and_following_events`'s "one `Event` entry per matching
// `Occasion`" shape (see `marshalable_event_data!`) -- each requested
// post id maps to exactly one occasion, so the response shouldn't bloat with
// sibling occasions the caller never asked about. `occasions::post_id`
// is a plain (unaliased) column on the base `occasions::table` the
// `query_visible_events!` macro already joins in, so -- same as
// `get_group_events`'s own extra `.filter()`s -- this can filter on it
// directly without needing the macro to expose its internal `occasion_posts`
// alias.
fn get_events_by_occasion_post_ids(
    user: &Option<&models::User>,
    post_ids: &[String],
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalableEvent>, Status> {
    let occasion_post_db_ids: Vec<i64> = post_ids
        .iter()
        .filter_map(|post_id| post_id.to_string().to_db_id().ok())
        .collect();
    if occasion_post_db_ids.is_empty() {
        return Ok(vec![]);
    }

    let query = query_visible_events!(user, None::<TimeFilter>)
        .filter(occasions::post_id.eq_any(occasion_post_db_ids));
    let binding = query.load::<EventLoadData>(conn).unwrap();
    let event_data: Vec<&EventLoadData> = binding.iter().collect();

    Ok(marshalable_event_data!(event_data))
}

fn get_event_by_post_id(
    user: &Option<&models::User>,
    post_id: &str,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalableEvent>, Status> {
    let post_db_id = post_id.to_string().to_db_id_or_err("post_id")?;
    let event_id = match occasions::table
        .left_join(events::table.on(events::post_id.eq(occasions::event_id)))
        .select(occasions::event_id)
        .filter(
            occasions::post_id
                .eq(post_db_id)
                .or(events::post_id.eq(post_db_id)),
        )
        .first::<i64>(conn)
    {
        Ok(event_id) => event_id,
        Err(_) => match events::table
            .select(events::post_id)
            .filter(events::post_id.eq(post_db_id))
            .first::<i64>(conn)
        {
            Ok(event_id) => event_id,
            // `post_id` no longer distinguishes "the Event's own post" from "one of its
            // Occasions' posts" (both removed fields collapsed into this one) -- so there's
            // no way to tell which the caller meant once neither resolves. Same message
            // `get_event_by_id` itself uses below for "resolved but not visible", since from the
            // caller's perspective both are just "can't get this Event".
            Err(_) => return Err(Status::new(Code::NotFound, "event_not_found")),
        },
    };
    get_event_by_id(user, &event_id.to_proto_id(), conn)
}

fn get_event_by_id(
    user: &Option<&models::User>,
    event_id: &str,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalableEvent>, Status> {
    let event_db_id = match event_id.to_string().to_db_id() {
        Ok(db_id) => db_id,
        Err(_) => return Err(Status::new(Code::InvalidArgument, "post_id_invalid")),
    };
    info!("get_event_by_id event_db_id: {}", event_db_id);
    let query = query_visible_events!(user, None::<TimeFilter>, SINGLE_OCCASION_LIMIT)
        .filter(events::post_id.eq(event_db_id));
    let binding = query.load::<EventLoadData>(conn).unwrap();
    let event_data: Vec<&EventLoadData> = binding.iter().collect();
    info!("get_event_by_id event_data: {:?}", event_data);
    if event_data.is_empty() {
        // info!("get_event_by_id event_data.is_empty");
        return Err(Status::new(Code::NotFound, "event_not_found"));
    }

    let event_model = event_data[0].1.clone();
    let event_post = event_data[0].2.clone();
    let event_author = event_data[0].3.clone();

    let event = MarshalableEvent(
        event_model,
        MarshalablePost(event_post, event_author, None, None, vec![]),
        event_data
            .iter()
            .map(
                |(occasion, _event, _event_post, _event_author, occasion_post, occasion_author)| {
                    MarshalableOccasion(
                        occasion.clone(),
                        MarshalablePost(
                            occasion_post.clone(),
                            occasion_author.clone(),
                            None,
                            None,
                            vec![],
                        ),
                    )
                },
            )
            .collect(),
    );
    info!("get_event_by_id event: {:?}", event);

    Ok(vec![event])
    // .map(|e| vec![e])
    // .map_err(|_| Status::new(Code::NotFound, "event_not_found"))
}

fn get_group_events(
    group_id: i64,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
    filter: Option<TimeFilter>,
) -> Result<Vec<MarshalableEvent>, Status> {
    let group = get_group(group_id, conn);
    match group {
        Ok(group) => {
            let membership = user
                .map(|u| get_membership(group_id, u.id, conn).ok())
                .flatten();
            validate_group_permission(&group, &membership.as_ref(), user, Permission::ViewPosts)?;

            let query = query_visible_events!(user, filter)
                .filter(group_posts::group_id.eq(group_id))
                .filter(group_posts::group_moderation.eq_any(PASSING_MODERATIONS));
            let binding = query.load::<EventLoadData>(conn).unwrap();
            let event_data: Vec<&EventLoadData> = binding.iter().collect();

            Ok(marshalable_event_data!(event_data))
        }
        Err(_) => Err(Status::new(Code::NotFound, "group_not_found")),
    }
}
