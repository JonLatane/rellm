use diesel::*;
use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{adjust_server_media_usage_bytes, update_media_storage_used};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::media;

use crate::rpcs::validations::*;

/// Deletes only the given `sizes` (matched by `conversion`) of a `Media` item by ID -- e.g. to
/// reclaim space by dropping `MEDIA_CONVERSION_ORIGINAL` once converted copies exist to serve in
/// its place. Self-or-`ADMIN`, same ownership check as `delete_media`. Errors
/// (`FailedPrecondition`) if this would leave the item with no sizes at all -- use `DeleteMedia`
/// to remove the whole item instead.
pub async fn delete_media_sizes(
    request: Media,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
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

    let self_delete = affected_media.user_id == Some(current_user.id);
    if !self_delete {
        validate_any_permission(&Some(current_user), vec![Permission::Admin])?;
    }

    let conversions_to_remove: Vec<i32> = request.sizes.iter().map(|s| s.conversion).collect();

    let existing_sizes = affected_media.sizes();
    let (removed, remaining): (Vec<models::MediaSize>, Vec<models::MediaSize>) = existing_sizes
        .into_iter()
        .partition(|s| conversions_to_remove.contains(&s.conversion));

    if remaining.is_empty() {
        return Err(Status::new(
            Code::FailedPrecondition,
            "would_leave_media_with_no_sizes",
        ));
    }

    let updated = diesel::update(media::table.find(media_id))
        .set(media::sizes.eq(serde_json::to_value(&remaining).unwrap()))
        .get_result::<models::Media>(conn)
        .map_err(|e| {
            log::error!("Error deleting media sizes: {:?}", e);
            Status::new(Code::Internal, "data_error")
        })?;

    let removed_bytes: i64 = removed.iter().map(|s| s.size_bytes).sum();

    for size in removed {
        if let Err(e) = bucket.delete_object(&size.object_storage_path).await {
            log::error!(
                "Failed to delete object storage object {} for media {}: {:?}",
                size.object_storage_path,
                media_id,
                e
            );
        }
    }

    if let Some(owner_id) = updated.user_id {
        if let Err(e) = update_media_storage_used(owner_id, conn) {
            log::error!(
                "Failed to update media_storage_bytes_used for user {}: {:?}",
                owner_id,
                e
            );
        }
    }
    if let Err(e) = adjust_server_media_usage_bytes(conn, -removed_bytes) {
        log::error!(
            "Failed to adjust server_media_usage_bytes for media {}: {:?}",
            media_id,
            e
        );
    }

    let author = if self_delete {
        Some(current_user.to_author())
    } else {
        updated.user_id.and_then(|uid| models::get_author(uid, conn).ok())
    };

    Ok(updated.to_proto(&author))
}
