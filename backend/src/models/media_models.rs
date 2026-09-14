use std::time::SystemTime;

use diesel::*;
use serde::{Deserialize, Serialize};
use tonic::{Code, Status};

use super::User;
use crate::protos::MediaConversion;
use crate::{db_connection::PgPooledConnection, schema::media};

pub fn get_media(media_id: i64, conn: &mut PgPooledConnection) -> Result<Media, Status> {
    media::table
        .select(media::all_columns)
        .filter(media::id.eq(media_id))
        .first::<Media>(conn)
        .map_err(|_| Status::new(Code::NotFound, "media_not_found"))
}
pub fn get_media_reference(
    media_id: i64,
    conn: &mut PgPooledConnection,
) -> Result<MediaReference, Status> {
    media::table
        .select(MEDIA_REFERENCE_COLUMNS)
        .filter(media::id.eq(media_id))
        .first::<MediaReference>(conn)
        .map_err(|_| Status::new(Code::NotFound, "media_not_found"))
}
pub fn get_all_media(
    media_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MediaReference>, Status> {
    media::table
        .select(MEDIA_REFERENCE_COLUMNS)
        .filter(media::id.eq_any(media_ids))
        .load::<MediaReference>(conn)
        .map_err(|_| Status::new(Code::NotFound, "media_not_found"))
}

#[derive(Debug, Queryable, Identifiable, Associations, AsChangeset, Clone)]
#[diesel(belongs_to(User))]
#[diesel(table_name = media)]
pub struct Media {
    pub id: i64,
    pub user_id: Option<i64>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub generated: bool,
    pub processed: bool,
    pub visibility: String,
    pub moderation: String,
    pub created_at: SystemTime,
    pub updated_at: SystemTime,
    pub metadata: serde_json::Value,
    pub sizes: serde_json::Value,
}

impl Media {
    /// Typed view of `sizes`. Falls back to an empty list if the column somehow holds something
    /// that doesn't parse -- callers should treat that the same as "no stored copies" rather than
    /// erroring.
    pub fn sizes(&self) -> Vec<MediaSize> {
        serde_json::from_value(self.sizes.clone()).unwrap_or_default()
    }

    /// The `MediaSize` for a specific `conversion`, if this item has one.
    pub fn size(&self, conversion: MediaConversion) -> Option<MediaSize> {
        self.sizes()
            .into_iter()
            .find(|s| s.conversion == conversion as i32)
    }

    /// The untouched original upload's `MediaSize` -- present on every `Media` row that actually
    /// stores bytes locally (i.e. every one, today; `url`-only media doesn't exist in the DB yet).
    pub fn original(&self) -> Option<MediaSize> {
        self.size(MediaConversion::Original)
    }

    /// Sum of every stored copy's `size_bytes` -- what this item contributes to its owner's
    /// `User.media_storage_bytes_used`. See `logic::user_counts::media_storage_bytes_used`, which
    /// computes the same sum across every `Media` a user owns via SQL rather than this (used only
    /// where a single already-loaded `Media` row's own contribution is needed).
    pub fn total_size_bytes(&self) -> i64 {
        self.sizes().iter().map(|s| s.size_bytes).sum()
    }

    /// Typed view of `metadata`. Falls back to an empty (all-`None`) `MediaMetadata` if the
    /// column somehow holds something that doesn't parse.
    pub fn metadata(&self) -> MediaMetadata {
        serde_json::from_value(self.metadata.clone()).unwrap_or_default()
    }
}

/// `Media.metadata`'s typed shape: `{ video_preview_time_ms: 1000 }`. Currently just the
/// timestamp `MediaRenderer.elm` seeks video previews to (via a `#t=` Media Fragments URI) and
/// `logic::media_conversion` seeks `ffmpeg` to when generating the `VIDEO_PREVIEW_THUMBNAIL_*`
/// poster frames; absence means the default computed by `effective_video_preview_time_ms`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MediaMetadata {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub video_preview_time_ms: Option<i64>,
}

impl MediaMetadata {
    /// The timestamp (in milliseconds) a video's preview/poster frame should actually be taken
    /// from -- `video_preview_time_ms` if set, else the default documented on that field in
    /// `media.proto`: 1s, or the midpoint of the video if it's shorter than 1.5s. `duration_ms` is
    /// the video's own total length, from `FFmpeg::duration_ms`.
    pub fn effective_video_preview_time_ms(&self, duration_ms: u64) -> u64 {
        self.video_preview_time_ms.map(|ms| ms as u64).unwrap_or_else(|| {
            if duration_ms < 1500 {
                duration_ms / 2
            } else {
                1000
            }
        })
    }
}

/// The 3 auto-generated resized copies `convert_media` (in `logic::media_conversion`) produces
/// for a `Media` item, in addition to its untouched `MediaConversion::Original`.
pub const RESIZED_CONVERSIONS: [MediaConversion; 3] = [
    MediaConversion::Small,
    MediaConversion::Medium,
    MediaConversion::Large,
];

/// The 3 auto-generated `image/jpeg` poster-frame sizes `convert_media` produces for *video*
/// `Media` items only, at the same dimension tiers as `RESIZED_CONVERSIONS` -- see each variant's
/// own doc in `media.proto`.
pub const VIDEO_PREVIEW_CONVERSIONS: [MediaConversion; 3] = [
    MediaConversion::VideoPreviewThumbnailSmall,
    MediaConversion::VideoPreviewThumbnailMedium,
    MediaConversion::VideoPreviewThumbnailLarge,
];

/// Sizing/naming details for each `MediaConversion` -- extension trait since `MediaConversion`
/// itself is generated from `protos/media.proto`.
pub trait MediaConversionExt {
    /// The max width/height (in pixels) media is resized to fit within for this conversion,
    /// preserving aspect ratio and never upscaling. Meaningless for `Original`.
    fn max_dimension(&self) -> u32;

    /// Lowercase name -- used to derive converted media's MinIO path and in logging.
    fn key(&self) -> &'static str;
}

impl MediaConversionExt for MediaConversion {
    fn max_dimension(&self) -> u32 {
        match self {
            MediaConversion::Original => 0,
            MediaConversion::Small | MediaConversion::VideoPreviewThumbnailSmall => 320,
            MediaConversion::Medium | MediaConversion::VideoPreviewThumbnailMedium => 800,
            MediaConversion::Large | MediaConversion::VideoPreviewThumbnailLarge => 1600,
        }
    }

    fn key(&self) -> &'static str {
        match self {
            MediaConversion::Original => "original",
            MediaConversion::Small => "small",
            MediaConversion::Medium => "medium",
            MediaConversion::Large => "large",
            MediaConversion::VideoPreviewThumbnailSmall => "video_preview_thumbnail_small",
            MediaConversion::VideoPreviewThumbnailMedium => "video_preview_thumbnail_medium",
            MediaConversion::VideoPreviewThumbnailLarge => "video_preview_thumbnail_large",
        }
    }
}

/// One stored copy of a `Media` item's bytes -- the DB-internal (JSONB-embedded, via `Media.sizes`/
/// `MediaReference.sizes`) counterpart to the wire `protos::MediaSize`, plus `minio_path`, which is
/// server-internal and deliberately never sent to clients (mirrors `Media`/`MediaReference`
/// themselves never exposing it). `conversion` is stored as `i32` (the raw `MediaConversion`
/// discriminant), matching the convention every other proto enum field uses in this codebase (e.g.
/// `Media.visibility`/`.moderation` on the wire) -- so this JSON round-trips as plain integers,
/// e.g. `{"conversion": 0, "minio_path": "...", "content_type": "...", "size_bytes": 12345,
/// "aspect_ratio": 1.5}`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaSize {
    pub conversion: i32,
    pub minio_path: String,
    pub content_type: String,
    pub size_bytes: i64,
    pub aspect_ratio: Option<f32>,
}

impl MediaSize {
    pub fn conversion(&self) -> MediaConversion {
        MediaConversion::try_from(self.conversion).unwrap_or(MediaConversion::Original)
    }
}

#[derive(Debug, Insertable)]
#[diesel(table_name = media)]
pub struct NewMedia {
    pub user_id: Option<i64>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub generated: bool,
    pub visibility: String,
    pub metadata: serde_json::Value,
    pub sizes: serde_json::Value,
}

pub const MEDIA_REFERENCE_COLUMNS: (
    media::id,
    media::user_id,
    media::name,
    media::generated,
    media::metadata,
    media::sizes,
) = (
    media::id,
    media::user_id,
    media::name,
    media::generated,
    media::metadata,
    media::sizes,
);

#[derive(Debug, Queryable, Identifiable, AsChangeset, Clone)]
#[diesel(table_name = media)]
pub struct MediaReference {
    pub id: i64,
    pub user_id: Option<i64>,
    pub name: Option<String>,
    pub generated: bool,
    pub metadata: serde_json::Value,
    pub sizes: serde_json::Value,
}

impl MediaReference {
    /// Typed view of `sizes`. See [`Media::sizes`].
    pub fn sizes(&self) -> Vec<MediaSize> {
        serde_json::from_value(self.sizes.clone()).unwrap_or_default()
    }

    /// See [`Media::original`].
    pub fn original(&self) -> Option<MediaSize> {
        self.sizes()
            .into_iter()
            .find(|s| s.conversion == MediaConversion::Original as i32)
    }

    /// Typed view of `metadata`. See [`Media::metadata`].
    pub fn metadata(&self) -> MediaMetadata {
        serde_json::from_value(self.metadata.clone()).unwrap_or_default()
    }
}
