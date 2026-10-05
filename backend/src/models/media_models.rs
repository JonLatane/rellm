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
    /// `User.media_storage_bytes_used`. See `logic::users::user_counts::media_storage_bytes_used`, which
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
/// `logic::media::media_conversion` seeks `ffmpeg` to when generating the `VIDEO_PREVIEW_THUMBNAIL_*`
/// poster frames; absence means the default computed by `effective_video_preview_time_ms`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MediaMetadata {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub video_preview_time_ms: Option<i64>,
    // Credits. Stored under these exact key names -- `media_build_search_text` (see
    // 2026-10-01-000000_media_search_licenses_credits) reads them out of the JSONB for search.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub artist: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub album: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub composer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub director: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub producer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub starring: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cast: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub crew: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub narrator: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub publisher: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub unlicensed_preview_start_ms: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub unlicensed_preview_end_ms: Option<i64>,
    /// DB id of the image `Media` chosen as this item's cover art -- see `MediaMetadata.cover_art_media_id`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cover_art_media_id: Option<i64>,
    /// Tempo (beats per minute) at the start/end of an audio track, and its slowest/fastest -- see
    /// `MediaMetadata.start_bpm`.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub start_bpm: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub end_bpm: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub min_bpm: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub max_bpm: Option<f32>,
    /// Musical key at the start/end of an audio track, e.g. `C#m`/`Db` -- see `is_valid_musical_key`
    /// for the accepted format.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub start_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub end_key: Option<String>,
    /// Internal (never sent to clients): set by `UpdateMedia` when only the *tag-relevant* fields (name,
    /// description, credits) changed on an already-converted audio/video item and the item was marked unprocessed
    /// for it -- `convert_media` then just rewrites the tags of the existing converted copies (a fast remux, see
    /// `retag_media`) instead of re-encoding everything.
    #[serde(skip_serializing_if = "std::ops::Not::not", default)]
    pub retag_only: bool,
}

/// Default length of the `UNLICENSED_PREVIEW_MEDIUM` crop when `unlicensed_preview_end_ms` is unset.
pub const DEFAULT_UNLICENSED_PREVIEW_LENGTH_MS: u64 = 30_000;

impl MediaMetadata {
    /// Whether any credit that ends up in a converted copy's file tags (artist, album, composer, publisher and
    /// the film credits) differs between `self` and `other` -- see `logic::media::media_conversion::output_tags`.
    pub fn tag_credits_differ(&self, other: &MediaMetadata) -> bool {
        self.artist != other.artist
            || self.album != other.album
            || self.composer != other.composer
            || self.publisher != other.publisher
            || self.director != other.director
            || self.producer != other.producer
            || self.starring != other.starring
            || self.cast != other.cast
            || self.crew != other.crew
            || self.narrator != other.narrator
    }

    /// Fills every *unset* credit (and the musical `start_bpm`/`end_bpm`/`min_bpm`/`max_bpm`/`start_key`/`end_key`) from `tags` -- a
    /// `MediaMetadata` built from `ffprobe` container tags (see `credits_from_tags`) or from audio
    /// analysis -- without touching any already-set one. Returns whether anything changed.
    pub fn fill_missing_credits(&mut self, tags: &MediaMetadata) -> bool {
        let mut changed = false;
        macro_rules! fill {
            ($($field:ident),*) => {$(
                if self.$field.is_none() && tags.$field.is_some() {
                    self.$field = tags.$field.clone();
                    changed = true;
                }
            )*};
        }
        fill!(artist, album, composer, director, producer, starring, cast, crew, narrator, publisher, start_bpm, end_bpm, min_bpm, max_bpm, start_key, end_key);
        changed
    }
}

/// Largest BPM `update_media` accepts (and smallest positive one is anything above 0) -- generous
/// on both ends so unusual music (very slow doom, extreme gabber) isn't rejected.
pub const MAX_BPM: f32 = 999.0;

/// Whether `bpm` is a valid `start_bpm`/`end_bpm`/`min_bpm`/`max_bpm`: finite, greater than 0, and at most `MAX_BPM`.
pub fn is_valid_bpm(bpm: f32) -> bool {
    bpm.is_finite() && bpm > 0.0 && bpm <= MAX_BPM
}

/// Accidental characters accepted after a key's letter: ASCII `#`/`b` and the Unicode sharps/flats
/// (`♯` U+266F, `♭` U+266D, fullwidth/small `＃` `﹟`). Only single accidentals: double sharps/flats
/// (`𝄪`, `𝄫`, `##`, `bb`) aren't valid keys. A trailing
/// emoji-presentation selector (U+FE0F) is allowed after the accidental, since `♯️`/`♭️` are what
/// emoji keyboards insert. Mirrored by `Shared.MediaViewerPanel.keyError` in the Elm client.
const SHARP_FLAT_CHARS: &[char] = &['#', 'b', '♯', '♭', '＃', '﹟'];

/// Whether `key` is a valid `MediaMetadata.start_key`/`end_key`: a letter `A`-`G`, then an optional sharp/flat
/// (see `SHARP_FLAT_CHARS`), then an optional `m`/`-` (minor) or `M` (major) suffix.
/// E.g. `C#m`, `DbM`, `Db`, `F`, `Am`, `B♭-`.
pub fn is_valid_musical_key(key: &str) -> bool {
    let mut chars = key.chars().peekable();
    if !matches!(chars.next(), Some('A'..='G')) {
        return false;
    }
    if chars.next_if(|c| SHARP_FLAT_CHARS.contains(c)).is_some() {
        chars.next_if(|c| *c == '\u{FE0F}');
    }
    chars.next_if(|c| matches!(c, 'm' | 'M' | '-'));
    chars.next().is_none()
}

/// Trims a credit field, mapping blank to `None` -- "If user blanks a value and saves, it saves as null".
pub fn blank_to_none(value: Option<String>) -> Option<String> {
    value.map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

impl MediaMetadata {
    /// The `[start, end)` range (ms) cropped into `UNLICENSED_PREVIEW_MEDIUM`, clamped to
    /// `duration_ms`. `None` if the resulting range is empty (e.g. start is past the end of the media).
    pub fn effective_unlicensed_preview_range_ms(&self, duration_ms: u64) -> Option<(u64, u64)> {
        let start = self.unlicensed_preview_start_ms.map(|ms| ms as u64).unwrap_or(0);
        let end = self
            .unlicensed_preview_end_ms
            .map(|ms| ms as u64)
            .unwrap_or(start + DEFAULT_UNLICENSED_PREVIEW_LENGTH_MS)
            .min(duration_ms);
        (start < end).then_some((start, end))
    }

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

/// The 3 auto-generated resized copies `convert_media` (in `logic::media::media_conversion`) produces
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

/// The 3 auto-generated `image/png` waveform sizes `convert_media` produces for *audio* `Media`
/// items only -- see each variant's own doc in `media.proto`.
pub const AUDIO_PREVIEW_CONVERSIONS: [MediaConversion; 3] = [
    MediaConversion::AudioPreviewThumbnailSmall,
    MediaConversion::AudioPreviewThumbnailMedium,
    MediaConversion::AudioPreviewThumbnailLarge,
];

/// The 3 auto-generated `image/jpeg` cover-art sizes `convert_media` produces for *audio* `Media`
/// items that have embedded cover art -- see each variant's own doc in `media.proto`.
pub const AUDIO_COVER_ART_CONVERSIONS: [MediaConversion; 3] = [
    MediaConversion::AudioCoverArtSmall,
    MediaConversion::AudioCoverArtMedium,
    MediaConversion::AudioCoverArtLarge,
];

/// The single auto-generated cropped preview `convert_media` produces for *audio and video* `Media`
/// items, served to viewers without a `License` -- see `UNLICENSED_PREVIEW_MEDIUM` in `media.proto`.
pub const UNLICENSED_PREVIEW_CONVERSIONS: [MediaConversion; 1] =
    [MediaConversion::UnlicensedPreviewMedium];

/// Sizing/naming details for each `MediaConversion` -- extension trait since `MediaConversion`
/// itself is generated from `protos/media.proto`.
pub trait MediaConversionExt {
    /// The max width/height (in pixels) media is resized to fit within for this conversion,
    /// preserving aspect ratio and never upscaling. Meaningless for `Original`.
    fn max_dimension(&self) -> u32;

    /// Lowercase name -- used to derive converted media's object storage path and in logging.
    fn key(&self) -> &'static str;
}

impl MediaConversionExt for MediaConversion {
    fn max_dimension(&self) -> u32 {
        match self {
            MediaConversion::Original => 0,
            MediaConversion::Small
            | MediaConversion::VideoPreviewThumbnailSmall
            | MediaConversion::AudioPreviewThumbnailSmall
            | MediaConversion::AudioCoverArtSmall => 320,
            MediaConversion::Medium
            | MediaConversion::VideoPreviewThumbnailMedium
            | MediaConversion::AudioPreviewThumbnailMedium
            | MediaConversion::AudioCoverArtMedium
            | MediaConversion::UnlicensedPreviewMedium => 800,
            MediaConversion::Large
            | MediaConversion::VideoPreviewThumbnailLarge
            | MediaConversion::AudioPreviewThumbnailLarge
            | MediaConversion::AudioCoverArtLarge => 1600,
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
            MediaConversion::AudioPreviewThumbnailSmall => "audio_preview_thumbnail_small",
            MediaConversion::AudioPreviewThumbnailMedium => "audio_preview_thumbnail_medium",
            MediaConversion::AudioPreviewThumbnailLarge => "audio_preview_thumbnail_large",
            MediaConversion::AudioCoverArtSmall => "audio_cover_art_small",
            MediaConversion::AudioCoverArtMedium => "audio_cover_art_medium",
            MediaConversion::AudioCoverArtLarge => "audio_cover_art_large",
            MediaConversion::UnlicensedPreviewMedium => "unlicensed_preview_medium",
        }
    }
}

/// One stored copy of a `Media` item's bytes -- the DB-internal (JSONB-embedded, via `Media.sizes`/
/// `MediaReference.sizes`) counterpart to the wire `protos::MediaSize`, plus `object_storage_path`,
/// which is server-internal and deliberately never sent to clients (mirrors `Media`/`MediaReference`
/// themselves never exposing it). `conversion` is stored as `i32` (the raw `MediaConversion`
/// discriminant), matching the convention every other proto enum field uses in this codebase (e.g.
/// `Media.visibility`/`.moderation` on the wire) -- so this JSON round-trips as plain integers,
/// e.g. `{"conversion": 0, "object_storage_path": "...", "content_type": "...", "size_bytes": 12345,
/// "aspect_ratio": 1.5}`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaSize {
    pub conversion: i32,
    pub object_storage_path: String,
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
    media::visibility,
) = (
    media::id,
    media::user_id,
    media::name,
    media::generated,
    media::metadata,
    media::sizes,
    media::visibility,
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
    pub visibility: String,
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
