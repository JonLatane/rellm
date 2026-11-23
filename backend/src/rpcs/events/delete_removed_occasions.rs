use std::collections::HashSet;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::occasions;

use super::event_permissions::{event_post_id, validate_event_edit_permission};

/// Deletes every `Occasion` currently on the event whose `post.id` isn't present in
/// `occasions` -- their own `Post`s are left behind, not cascade-deleted. Refreshes
/// `occasion_count` for `current_user` and for any other user who owned a deleted occasion's
/// Post (e.g. an admin deleting occasions on someone else's event).
///
/// Callers orchestrating this alongside `create_new_occasions` (like `update_event`) must
/// pass `occasions` with any newly-created entries' `post.id`s already resolved (that function's
/// return value) -- an entry with no (or unparseable) `post.id` here can't be matched to anything,
/// so it wouldn't protect a just-created occasion from being swept up as "not present in
/// `occasions`".
pub(super) fn delete_removed_occasions_impl(
    event: &models::Event,
    occasions: &[Occasion],
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let existing_occasion_data =
        models::get_occasions(event.post_id, &Some(current_user), conn)?;
    let kept_ids: HashSet<i64> = occasions
        .iter()
        .filter_map(|i| i.post.as_ref())
        .filter_map(|p| p.id.to_db_id().ok())
        .collect();

    let removed_occasion_ids: Vec<i64> = existing_occasion_data
        .iter()
        .filter(|(occasion, _, _)| !kept_ids.contains(&occasion.post_id))
        .map(|(occasion, _, _)| occasion.post_id)
        .collect();
    // Occasions owned by users other than `current_user` (e.g. an admin editing someone else's
    // event) that are about to be deleted -- their `occasion_count` needs refreshing too.
    let removed_occasion_owner_ids: Vec<i64> = existing_occasion_data
        .iter()
        .filter(|(occasion, _, _)| removed_occasion_ids.contains(&occasion.post_id))
        .filter_map(|(_, post, _)| post.user_id)
        .collect();

    diesel::delete(
        occasions::table.filter(occasions::post_id.eq_any(removed_occasion_ids)),
    )
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to delete event occasions: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_delete_occasions")
        })?;

    let mut affected_user_ids = removed_occasion_owner_ids;
    affected_user_ids.push(current_user.id);
    affected_user_ids.sort_unstable();
    affected_user_ids.dedup();
    for user_id in affected_user_ids {
        crate::logic::update_event_counts(user_id, conn)
            .map_err(|_| Status::new(Code::Internal, "error_updating_event_counts"))?;
    }

    Ok(())
}

pub fn delete_removed_occasions(
    request: Event,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Event, Status> {
    let event_id = event_post_id(&request)?;
    let event = models::get_event(event_id, &Some(current_user), conn)?;
    validate_event_edit_permission(&event, current_user, conn)?;

    delete_removed_occasions_impl(&event, &request.occasions, current_user, conn)?;

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
