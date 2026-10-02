use diesel::*;
use serde_json::json;
// use serde_json::json;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::models::AUTHOR_COLUMNS;
use crate::protos::*;
use crate::schema::users;
use crate::schema::{rsvps, occasions, events, posts};

use crate::rpcs::validations::*;

pub fn get_rsvps(
    request: GetRsvpsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<Rsvps, Status> {
    let occasion_id = request.occasion_id.to_db_id_or_err("id")?;

    let (event, event_post, occasion): (models::Event, models::Post, models::Occasion) =
        occasions::table
            .inner_join(events::table.on(occasions::event_id.eq(events::post_id)))
            .inner_join(posts::table.on(events::post_id.eq(posts::id)))
            .filter(occasions::post_id.eq(occasion_id))
            .select((
                events::all_columns,
                models::POST_COLUMNS,
                models::OCCASION_COLUMNS,
            ))
            .first::<(models::Event, models::Post, models::Occasion)>(conn)
            .map_err(|_e| Status::new(Code::Internal, "invalid_occasion_id"))?;

    let is_event_owner = user.is_some()
        && event_post.user_id.is_some()
        && event_post.user_id.unwrap() == user.map(|u| u.id).unwrap();
    log::info!("is_event_owner={:?}", is_event_owner);

    match (event_post.visibility.to_proto_visibility().unwrap(), user) {
        (Visibility::GlobalPublic, _) => {}
        (Visibility::ServerPublic, _) => validate_permission(user, Permission::ViewEvents)?,
        (Visibility::Limited, Some(user))
            if event_post.user_id.map(|id| id == user.id).unwrap_or(false) => {}
        (Visibility::Private, Some(user))
            if event_post.user_id.map(|id| id == user.id).unwrap_or(false) => {}
        _ => {
            return Err(Status::new(
                Code::PermissionDenied,
                "not_logged_in_cannot_view_private_events",
            ))
        }
    }

    let mut rsvps_query = rsvps::table
        .left_join(users::table.on(rsvps::user_id.eq(users::id.nullable())))
        .select((rsvps::all_columns, AUTHOR_COLUMNS.nullable()))
        .filter(rsvps::occasion_id.eq(occasion_id))
        .into_boxed();

    if !is_event_owner {
        rsvps_query = rsvps_query.filter(
            rsvps::moderation
                .eq_any(PASSING_MODERATIONS)
                .or(rsvps::user_id
                    .eq(user.map(|u| u.id).unwrap_or(0))
                    .or(rsvps::anonymous_attendee
                        .contains(json!({"auth_token": request.anonymous_attendee_auth_token})))),
        );
    }

    let rsvps: Vec<(models::Rsvp, Option<models::Author>)> =
        rsvps_query
            .load::<(models::Rsvp, Option<models::Author>)>(conn)
            .map_err(|e| {
                log::error!(
                    "Failed to load event rsvps for occasion_id={}: {:?}",
                    occasion_id,
                    e
                );
                Status::new(Code::Internal, "failed_to_load_rsvps")
            })?;

    let is_approved_attendee = is_event_owner
        || rsvps.iter().any(|(a, _)| {
            a.moderation == Moderation::Approved.to_string_moderation()
                && ((user.is_some() && a.user_id == user.map(|u| u.id))
                    || (request.anonymous_attendee_auth_token.is_some()
                        && a.anonymous_attendee.is_some()
                        && a.anonymous_attendee.as_ref().unwrap()["auth_token"]
                            .as_str()
                            .unwrap()
                            == request.anonymous_attendee_auth_token.as_ref().unwrap()))
        });

    let hidden_location = if is_approved_attendee
        || !event.info["hide_location_until_rsvp_approved"]
            .as_bool()
            .unwrap_or(false)
    {
        occasion.location.map(|l| l.to_proto_location())
    } else {
        None
    };

    let media_ids = rsvps
        .iter()
        .filter_map(|(_, author)| author.as_ref().map(|a| a.avatar_media_id))
        .map(|id| id.unwrap_or(0))
        .collect();
    let lookup = load_media_lookup(media_ids, conn);
    Ok(Rsvps {
        rsvps: rsvps
            .into_iter()
            .map(|(a, attendee)| {
                let is_current_anonymous_attendeee =
                    request.anonymous_attendee_auth_token.is_some()
                        && a.anonymous_attendee.is_some()
                        && match (a.clone(), attendee.clone())
                            .to_proto(true, false, lookup.as_ref())
                            .attendee
                            .unwrap()
                        {
                            rsvp::Attendee::AnonymousAttendee(anonymous_attendee) => {
                                anonymous_attendee.auth_token.unwrap()
                                    == request
                                        .anonymous_attendee_auth_token
                                        .as_ref()
                                        .unwrap()
                                        .clone()
                            }
                            _ => false,
                        };

                let is_current_user_attendee =
                    a.user_id.is_some() && user.is_some() && a.user_id.unwrap() == user.unwrap().id;

                let include_private_note =
                    is_event_owner || is_current_user_attendee || is_current_anonymous_attendeee;
                (a, attendee).to_proto(include_private_note, include_private_note, lookup.as_ref())
            })
            .collect(),

        hidden_location,
    })
}
