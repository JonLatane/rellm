use diesel::*;
use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    adjust_server_media_usage_bytes, is_audio_content_type, is_video_content_type,
    update_media_storage_used,
};
use crate::marshaling::*;
use crate::models::{self, blank_to_none, is_valid_bpm, is_valid_musical_key, UNLICENSED_PREVIEW_CONVERSIONS, VIDEO_PREVIEW_CONVERSIONS};
use crate::protos::*;
use crate::schema::media;

use crate::rpcs::validations::*;

/// Updates a `Media` item's `name`/`description`/`visibility`/`metadata` by ID -- every other field
/// on `request` (moderation, `sizes`, etc.) is ignored. Self-or-`ADMIN`, same ownership check as
/// `delete_media`.
///
/// - `visibility` of `VISIBILITY_UNKNOWN` (the proto default) leaves it unchanged. `DIRECT` is
///   rejected (not applicable to media); `LICENSED` is accepted (see `Visibility.LICENSED`).
/// - `request.metadata` unset leaves metadata untouched. If set, it *replaces* all of it (every
///   credit/preview field not included becomes unset), with blank credit strings saved as null.
///   `unlicensed_preview_*` may only be set on audio/video media.
/// - If `video_preview_time_ms` changes on a video, existing `VIDEO_PREVIEW_THUMBNAIL_*` sizes are
///   stale (captured at the old time); likewise `UNLICENSED_PREVIEW_MEDIUM` when either
///   `unlicensed_preview_*` bound changes. Stale sizes are deleted here (from `sizes` and their
///   object storage objects) and the item is marked unprocessed, so `convert_media` (in
///   `logic::media::media_conversion`, run by the `convert_media_sizes` background job) regenerates them.
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

    let new_visibility = match request.visibility() {
        Visibility::Unknown => affected_media.visibility.clone(),
        Visibility::Direct => return Err(Status::new(Code::InvalidArgument, "invalid_visibility")),
        visibility => visibility.to_string_visibility(),
    };

    let is_audio_or_video = affected_media.original().is_some_and(|o| {
        is_video_content_type(&o.content_type) || is_audio_content_type(&o.content_type)
    });
    let is_video = affected_media
        .original()
        .is_some_and(|o| is_video_content_type(&o.content_type));

    let current_metadata = affected_media.metadata();
    let new_metadata = match request.metadata.as_ref() {
        None => current_metadata.clone(),
        Some(m) => {
            let new_metadata = models::MediaMetadata {
                video_preview_time_ms: m.video_preview_time_ms.map(|ms| ms as i64),
                artist: blank_to_none(m.artist.clone()),
                album: blank_to_none(m.album.clone()),
                composer: blank_to_none(m.composer.clone()),
                director: blank_to_none(m.director.clone()),
                producer: blank_to_none(m.producer.clone()),
                starring: blank_to_none(m.starring.clone()),
                cast: blank_to_none(m.cast.clone()),
                crew: blank_to_none(m.crew.clone()),
                narrator: blank_to_none(m.narrator.clone()),
                publisher: blank_to_none(m.publisher.clone()),
                unlicensed_preview_start_ms: m.unlicensed_preview_start_ms.map(|ms| ms as i64),
                unlicensed_preview_end_ms: m.unlicensed_preview_end_ms.map(|ms| ms as i64),
                start_bpm: m.start_bpm,
                end_bpm: m.end_bpm,
                min_bpm: m.min_bpm,
                max_bpm: m.max_bpm,
                start_key: blank_to_none(m.start_key.clone()),
                end_key: blank_to_none(m.end_key.clone()),
                cover_art_media_id: match blank_to_none(m.cover_art_media_id.clone()) {
                    None => None,
                    Some(id) => {
                        let art_id = id.to_db_id_or_err("cover_art_media_id")?;
                        // Unchanged is always fine; a new pick must be an image the caller owns (or an Admin).
                        if Some(art_id) != current_metadata.cover_art_media_id {
                            let art = models::get_media(art_id, conn)
                                .map_err(|_| Status::new(Code::InvalidArgument, "cover_art_not_found"))?;
                            let is_image = art
                                .original()
                                .is_some_and(|o| o.content_type.starts_with("image/"));
                            if !is_image {
                                return Err(Status::new(Code::InvalidArgument, "cover_art_must_be_image"));
                            }
                            if art.user_id != Some(current_user.id) {
                                validate_any_permission(&Some(current_user), vec![Permission::Admin])?;
                            }
                        }
                        Some(art_id)
                    }
                },
            };
            for (field, bpm) in [
                ("start_bpm", new_metadata.start_bpm),
                ("end_bpm", new_metadata.end_bpm),
                ("min_bpm", new_metadata.min_bpm),
                ("max_bpm", new_metadata.max_bpm),
            ] {
                if bpm.is_some_and(|bpm| !is_valid_bpm(bpm)) {
                    return Err(Status::new(Code::InvalidArgument, format!("invalid_{field}")));
                }
            }
            if let (Some(min), Some(max)) = (new_metadata.min_bpm, new_metadata.max_bpm) {
                if min > max {
                    return Err(Status::new(Code::InvalidArgument, "min_bpm_exceeds_max_bpm"));
                }
            }
            for (field, key) in [("start_key", &new_metadata.start_key), ("end_key", &new_metadata.end_key)] {
                if key.as_deref().is_some_and(|key| !is_valid_musical_key(key)) {
                    return Err(Status::new(Code::InvalidArgument, format!("invalid_{field}")));
                }
            }
            let has_unlicensed_preview = new_metadata.unlicensed_preview_start_ms.is_some()
                || new_metadata.unlicensed_preview_end_ms.is_some();
            if has_unlicensed_preview && !is_audio_or_video {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "unlicensed_preview_requires_audio_or_video",
                ));
            }
            if let (Some(start), Some(end)) = (
                new_metadata.unlicensed_preview_start_ms,
                new_metadata.unlicensed_preview_end_ms,
            ) {
                if end <= start {
                    return Err(Status::new(
                        Code::InvalidArgument,
                        "unlicensed_preview_end_must_be_after_start",
                    ));
                }
            }
            new_metadata
        }
    };

    let invalidate_video_thumbnails = is_video
        && new_metadata.video_preview_time_ms != current_metadata.video_preview_time_ms;
    let invalidate_unlicensed_preview = new_metadata.unlicensed_preview_start_ms
        != current_metadata.unlicensed_preview_start_ms
        || new_metadata.unlicensed_preview_end_ms != current_metadata.unlicensed_preview_end_ms;
    let invalidate_any = invalidate_video_thumbnails || invalidate_unlicensed_preview;

    let (kept_sizes, removed_sizes): (Vec<models::MediaSize>, Vec<models::MediaSize>) =
        affected_media.sizes().into_iter().partition(|s| {
            !(invalidate_video_thumbnails && VIDEO_PREVIEW_CONVERSIONS.contains(&s.conversion())
                || invalidate_unlicensed_preview
                    && UNLICENSED_PREVIEW_CONVERSIONS.contains(&s.conversion()))
        });

    let updated = diesel::update(media::table.find(media_id))
        .set((
            media::name.eq(request.name),
            media::description.eq(request.description),
            media::visibility.eq(new_visibility),
            media::metadata.eq(serde_json::to_value(&new_metadata).unwrap()),
            media::sizes.eq(serde_json::to_value(&kept_sizes).unwrap()),
            media::processed.eq(affected_media.processed && !invalidate_any),
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
