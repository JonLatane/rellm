use diesel::*;
use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{adjust_server_media_usage_bytes, is_video_content_type, update_media_storage_used};
use crate::marshaling::*;
use crate::models::{self, VIDEO_PREVIEW_CONVERSIONS};
use crate::protos::*;
use crate::schema::media;

use crate::rpcs::validations::*;

/// Updates a `Media` item's `name`/`description`/`metadata.video_preview_time_ms` by ID -- every
/// other field on `request` (visibility, moderation, `sizes`, etc.) is ignored. Self-or-`ADMIN`,
/// same ownership check as `delete_media`.
///
/// If `request.metadata` is set and its `video_preview_time_ms` differs from the item's current
/// value, any existing `VIDEO_PREVIEW_THUMBNAIL_*` sizes are stale (they were captured at the old
/// time) -- they're deleted here (from `sizes` and their object storage objects) and the item is marked
/// unprocessed, so `convert_media` (in `logic::media_conversion`, run by the `convert_media_sizes`
/// background job) regenerates them at the new time next run. `request.metadata` unset leaves
/// `video_preview_time_ms` untouched, same as `name`/`description` being unset.
pub async fn update_media(
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

    let self_update = affected_media.user_id == Some(current_user.id);
    if !self_update {
        validate_any_permission(&Some(current_user), vec![Permission::Admin])?;
    }

    let current_metadata = affected_media.metadata();
    let requested_video_preview_time_ms =
        request.metadata.as_ref().map(|m| m.video_preview_time_ms.map(|ms| ms as i64));
    let preview_time_changed = requested_video_preview_time_ms
        .is_some_and(|requested| requested != current_metadata.video_preview_time_ms);
    let new_metadata = models::MediaMetadata {
        video_preview_time_ms: requested_video_preview_time_ms
            .unwrap_or(current_metadata.video_preview_time_ms),
    };

    let invalidate_preview_thumbnails = preview_time_changed
        && affected_media
            .original()
            .is_some_and(|o| is_video_content_type(&o.content_type));

    let (kept_sizes, removed_sizes): (Vec<models::MediaSize>, Vec<models::MediaSize>) =
        affected_media.sizes().into_iter().partition(|s| {
            !invalidate_preview_thumbnails || !VIDEO_PREVIEW_CONVERSIONS.contains(&s.conversion())
        });

    let updated = diesel::update(media::table.find(media_id))
        .set((
            media::name.eq(request.name),
            media::description.eq(request.description),
            media::metadata.eq(serde_json::to_value(&new_metadata).unwrap()),
            media::sizes.eq(serde_json::to_value(&kept_sizes).unwrap()),
            media::processed.eq(affected_media.processed && !invalidate_preview_thumbnails),
        ))
        .get_result::<models::Media>(conn)
        .map_err(|e| {
            log::error!("Error updating media: {:?}", e);
            Status::new(Code::Internal, "data_error")
        })?;

    for size in &removed_sizes {
        if let Err(e) = bucket.delete_object(&size.object_storage_path).await {
            log::error!(
                "Failed to delete object storage object {} for media {}: {:?}",
                size.object_storage_path,
                media_id,
                e
            );
        }
    }

    if !removed_sizes.is_empty() {
        if let Some(owner_id) = updated.user_id {
            if let Err(e) = update_media_storage_used(owner_id, conn) {
                log::error!(
                    "Failed to update media_storage_bytes_used for user {}: {:?}",
                    owner_id,
                    e
                );
            }
        }
        let removed_bytes: i64 = removed_sizes.iter().map(|s| s.size_bytes).sum();
        if let Err(e) = adjust_server_media_usage_bytes(conn, -removed_bytes) {
            log::error!(
                "Failed to adjust server_media_usage_bytes for media {}: {:?}",
                media_id,
                e
            );
        }
    }

    let author = if self_update {
        Some(current_user.to_author())
    } else {
        updated.user_id.and_then(|uid| models::get_author(uid, conn).ok())
    };

    Ok(updated.to_proto(&author))
}
