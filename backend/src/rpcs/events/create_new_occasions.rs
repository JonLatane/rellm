use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::{occasions, posts};

use super::event_permissions::{
    event_post_id, find_existing_occasion, occasion_info_json, validate_event_edit_permission,
};

/// Creates an `Occasion` for every entry in `occasions` that isn't already on `event` (i.e.
/// whose `post.id` doesn't parse, or doesn't belong to this event); entries that do match are left
/// untouched (see `update_occasions` for updating those in place). Returns `occasions` with
/// each created entry's `post.id` replaced by its newly-minted Post's id -- callers that need to
/// know which occasions survive this event (like `update_event`, feeding
/// `delete_removed_occasions`) can't otherwise tell a request occasion just created apart
/// from one about to be deleted, since both have no id the deletion pass would recognize.
pub(super) fn create_new_occasions_impl(
    event: &models::Event,
    occasions: &[Occasion],
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Vec<Occasion>, Status> {
    let mut resolved = Vec::with_capacity(occasions.len());
    for request_occasion in occasions {
        if find_existing_occasion(request_occasion, event.post_id, conn).is_some() {
            resolved.push(request_occasion.clone());
            continue;
        }
        let (_, created_occasion_post) =
            create_occasion(event, request_occasion, current_user, conn)?;
        let mut resolved_post = request_occasion.post.clone().unwrap_or_default();
        resolved_post.id = created_occasion_post.id.to_proto_id();
        resolved.push(Occasion {
            post: Some(resolved_post),
            ..request_occasion.clone()
        });
    }

    // New occasions are always owned by `current_user`; refresh their `occasion_count`.
    crate::logic::update_event_counts(current_user.id, conn)
        .map_err(|_| Status::new(Code::Internal, "error_updating_event_counts"))?;

    Ok(resolved)
}

pub fn create_new_occasions(
    request: Event,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Event, Status> {
    let event_id = event_post_id(&request)?;
    let event = models::get_event(event_id, &Some(current_user), conn)?;
    validate_event_edit_permission(&event, current_user, conn)?;

    create_new_occasions_impl(&event, &request.occasions, current_user, conn)?;

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

/// New occasions are always authored by `user` (the caller) -- syncing to any other owner isn't
/// supported.
pub fn create_occasion(
    event: &models::Event,
    occasion: &Occasion,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(models::Occasion, models::Post), Status> {
    let media_ids = occasion
        .post
        .as_ref()
        .map(|p| {
            p.media
                .iter()
                .map(|m| m.id.to_db_id_or_err("occasion.post.media"))
                .collect::<Result<Vec<i64>, Status>>()
        })
        .transpose()?
        .unwrap_or_default();
    let new_post = occasion.post.as_ref().map_or(
        models::NewPost {
            user_id: Some(user.id),
            parent_post_id: None,
            title: None,
            link: None,
            content: None,
            visibility: "GLOBAL_PUBLIC".to_string(),
            context: PostContext::Occasion.as_str_name().to_string(),
            moderation: "UNMODERATED".to_string(),
            media: vec![],
        },
        |p| models::NewPost {
            user_id: Some(user.id),
            parent_post_id: None,
            title: p.title.to_owned(),
            link: p.link.to_link(),
            content: p.content.to_owned(),
            visibility: p.visibility.to_string_visibility(),
            context: PostContext::Occasion.as_str_name().to_string(),
            moderation: "UNMODERATED".to_string(),
            media: media_ids,
        },
    );
    let occasion_post: models::Post = insert_into(posts::table)
        .values(&new_post)
        .returning(models::POST_COLUMNS)
        .get_result::<models::Post>(conn)
        .map_err(|e| {
            log::error!("Failed to create event occasion post: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_create_occasion_post")
        })?;
    let occasion = insert_into(occasions::table)
        .values(&models::NewOccasion {
            event_id: event.post_id,
            post_id: occasion_post.id,
            starts_at: occasion.starts_at.as_ref().unwrap().to_db(),
            ends_at: occasion.ends_at.as_ref().unwrap().to_db(),
            location: occasion
                .location
                .as_ref()
                .map(|c| serde_json::to_value(c).unwrap()),
            info: occasion_info_json(&occasion.info),
            timezone: occasion.timezone.clone(),
        })
        .returning(models::OCCASION_COLUMNS)
        .get_result::<models::Occasion>(conn)
        .map_err(|e| {
            log::error!("Failed to create event occasion: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_create_occasion")
        })?;
    Ok((occasion, occasion_post))
}
