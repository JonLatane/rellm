use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::media;

use crate::rpcs::validations::*;

/// Updates a `Media` item's `name`/`description` by ID -- every other field on `request` (visibility,
/// moderation, `sizes`, etc.) is ignored. Self-or-`ADMIN`, same ownership check as `delete_media`.
pub fn update_media(
    request: Media,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Media, Status> {
    let media_id = request.id.to_db_id_or_err("id")?;
    let affected_media = media::table
        .filter(media::id.eq(media_id))
        .get_result::<models::Media>(conn)
        .optional()
        .map_err(|e| {
            log::error!("Error finding media: {:?}", e);
            Status::new(Code::Internal, "media_not_found")
        })?
        .ok_or_else(|| Status::new(Code::NotFound, "media_not_found"))?;

    let self_update = affected_media.user_id == Some(current_user.id);
    if !self_update {
        validate_any_permission(&Some(current_user), vec![Permission::Admin])?;
    }

    let updated = diesel::update(media::table.find(media_id))
        .set((
            media::name.eq(request.name),
            media::description.eq(request.description),
        ))
        .get_result::<models::Media>(conn)
        .map_err(|e| {
            log::error!("Error updating media: {:?}", e);
            Status::new(Code::Internal, "data_error")
        })?;

    Ok(updated.to_proto())
}
