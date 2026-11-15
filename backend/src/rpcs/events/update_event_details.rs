use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;

use super::event_permissions::event_post_id;

/// Updates only the `Event`'s top-level details (`info`) and those of its own `Post` -- not any
/// `Occasion`s or their `Post`s. Ownership/permission checks are enforced by `update_post`
/// (self-update, or `Admin`/`ModeratePosts`/`ModerateEvents`) on the event's own `Post`.
pub(super) fn update_event_details_impl(
    event_id: i64,
    request: &Event,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let mut existing_event = models::get_event(event_id, &Some(current_user), conn)?;

    existing_event.info = serde_json::to_value(request.info.to_owned()).unwrap();
    diesel::update(&existing_event)
        .set(&existing_event)
        .get_result::<models::Event>(conn)
        .map_err(|e| {
            log::error!("Failed to update event: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_update_event")
        })?;

    // update_post handles ownership/permission checks.
    match &request.post {
        None => {
            return Err(Status::new(
                Code::InvalidArgument,
                "event must contain associated post",
            ));
        }
        Some(post) => match post.id.to_db_id_or_err("post.id")? {
            post_id if post_id == existing_event.post_id => {
                crate::rpcs::update_post(post.clone(), current_user, conn)?;
            }
            _ => {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "post ID mismatches event post ID",
                ));
            }
        },
    }

    Ok(())
}

pub fn update_event_details(
    request: Event,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Event, Status> {
    let event_id = event_post_id(&request)?;
    update_event_details_impl(event_id, &request, current_user, conn)?;

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
