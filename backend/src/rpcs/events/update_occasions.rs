use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::posts;

use super::event_permissions::{
    event_post_id, find_existing_occasion, occasion_info_json, validate_event_edit_permission,
};

/// Updates, in place, every `Occasion` in `occasions` that's already on the event (i.e.
/// whose `post.id` matches an existing occasion belonging to this event). Any other occasions are
/// ignored -- see `create_new_occasions` for creating those instead.
///
/// An `Occasion`'s identity *is* its `post.id`, so (unlike the old surrogate-ID scheme) a
/// matched occasion's `post` is never missing here -- to explicitly reset an occasion's Post to
/// `PRIVATE`, send its `post` with `visibility: PRIVATE` rather than omitting `post` entirely.
pub(super) fn update_occasions_impl(
    event: &models::Event,
    occasions: &[Occasion],
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    for request_occasion in occasions {
        let Some(existing_occasion) =
            find_existing_occasion(request_occasion, event.post_id, conn)
        else {
            continue;
        };
        let existing_occasion_post = posts::table
            .select(models::POST_COLUMNS)
            .filter(posts::id.eq(existing_occasion.post_id))
            .first::<models::Post>(conn)
            .map_err(|_| Status::new(Code::NotFound, "occasion_post_not_found"))?;

        let mut updated_occasion = existing_occasion.clone();
        let starts_at = request_occasion.starts_at.to_db()?;
        let ends_at = request_occasion.ends_at.to_db()?;
        let location = request_occasion
            .location
            .as_ref()
            .map(|c| serde_json::to_value(c).unwrap());
        if starts_at > ends_at {
            return Err(Status::new(
                Code::InvalidArgument,
                format!(
                    "occasion[{}] starts_at must be before ends_at",
                    existing_occasion.post_id
                ),
            ));
        }

        let timezone = request_occasion.timezone.clone();
        // Only touched when the request carries `info` -- a client that omits it leaves the
        // stored RSVP overrides alone.
        if request_occasion.info.is_some() {
            let info = occasion_info_json(&request_occasion.info);
            if info != updated_occasion.info {
                updated_occasion.info = info;
                updated_occasion.updated_at = SystemTime::now().into();
            }
        }

        if starts_at != updated_occasion.starts_at
            || ends_at != updated_occasion.ends_at
            || location != updated_occasion.location
            || timezone != updated_occasion.timezone
        {
            updated_occasion.starts_at = starts_at;
            updated_occasion.ends_at = ends_at;
            updated_occasion.location = location;
            updated_occasion.timezone = timezone;
            updated_occasion.updated_at = SystemTime::now().into();
        }

        diesel::update(&updated_occasion)
            .set(&updated_occasion)
            .returning(models::OCCASION_COLUMNS)
            .get_result::<models::Occasion>(conn)
            .map_err(|e| {
                log::error!("Failed to update event occasion: {:?}", crate::logic::log_redaction::safe_error(&e));
                Status::new(Code::Internal, "failed_to_update_occasion")
            })?;

        let mut updated_occasion_post = existing_occasion_post.clone();
        // `request_occasion.post` is always `Some` here -- `find_existing_occasion` can only
        // match via `post.id` -- so this `unwrap_or` is just a defensive fallback, not a live path.
        let visibility = request_occasion
            .post
            .as_ref()
            .map(|p| p.visibility())
            .unwrap_or(Visibility::Private);
        if visibility.to_string_visibility() != updated_occasion_post.visibility {
            updated_occasion_post.visibility = visibility.to_string_visibility();
        }
        diesel::update(&updated_occasion_post)
            .set(&updated_occasion_post)
            .returning(models::POST_COLUMNS)
            .get_result::<models::Post>(conn)
            .map_err(|e| {
                log::error!("Failed to update event occasion post: {:?}", crate::logic::log_redaction::safe_error(&e));
                Status::new(Code::Internal, "failed_to_update_occasion")
            })?;
    }

    Ok(())
}

pub fn update_occasions(
    request: Event,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Event, Status> {
    let event_id = event_post_id(&request)?;
    let event = models::get_event(event_id, &Some(current_user), conn)?;
    validate_event_edit_permission(&event, current_user, conn)?;

    update_occasions_impl(&event, &request.occasions, conn)?;

    Ok(super::get_events(
        GetEventsRequest {
            post_id: Some(event_id.to_proto_id()),
            ..Default::default()
        },
        &Some(current_user),
        conn,
    )?
    .events[0]
        .clone())
}
