use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::models::get_rsvp;
use crate::protos::*;
use crate::schema::{rsvps, occasions, events, posts};

pub fn delete_rsvp(
    request: Rsvp,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let occasion_id = request
        .occasion_id
        .to_db_id_or_err("occasion_id")?;

    let (_event, event_post, _occasion): (
        models::Event,
        models::Post,
        models::Occasion,
    ) = occasions::table
        .inner_join(events::table.on(occasions::event_id.eq(events::post_id)))
        .inner_join(posts::table.on(events::post_id.eq(posts::id)))
        .filter(occasions::post_id.eq(occasion_id))
        .select((
            events::all_columns,
            models::POST_COLUMNS,
            models::OCCASION_COLUMNS,
        ))
        .first::<(models::Event, models::Post, models::Occasion)>(conn)
        // .execute(conn)
        .map_err(|_e| Status::new(Code::Internal, "invalid_occasion_id"))?;

    let is_event_owner = user.is_some() && event_post.user_id == user.map(|u| u.id);
    let is_own_rsvp = match &request.attendee {
        Some(rsvp::Attendee::UserAttendee(author)) => {
            user.is_some() && user.map(|u| u.id) == author.user_id.to_db_id().ok()
        }
        _ => false,
    };

    let attendee_user_id = match &request.attendee {
        Some(rsvp::Attendee::UserAttendee(author)) => {
            Some(author.user_id.to_db_id_or_err("author.user_id")?)
        }
        _ => None,
    };
    let is_anonymous = attendee_user_id.is_none();

    let attendee_user_id = match &request.attendee {
        Some(rsvp::Attendee::UserAttendee(attendee)) => {
            Some(attendee.user_id.to_db_id_or_err("user_id")?)
        }
        _ => None,
    };
    // let is_anonymous = attendee_user_id.is_none();

    if !is_event_owner && !is_own_rsvp && !is_anonymous {
        return Err(Status::new(
            Code::PermissionDenied,
            "not_your_event_or_rsvp",
        ));
    }

    let attendee_auth_token = request
        .attendee
        .as_ref()
        .map(|a| match a {
            rsvp::Attendee::AnonymousAttendee(u) => u.auth_token.clone(),
            _ => None,
        })
        .flatten();
    let existing_rsvp = get_rsvp(
        occasion_id,
        attendee_user_id,
        attendee_auth_token,
        conn,
    );

    match existing_rsvp {
        Some(rsvp) => diesel::delete(rsvps::table)
            .filter(rsvps::id.eq(rsvp.0.id))
            .execute(conn)
            .map(|_| ())
            .map_err(|_e| Status::new(Code::Internal, "failed_to_delete_rsvp")),
        None => Err(Status::new(Code::NotFound, "rsvp_not_found")),
    }
}
