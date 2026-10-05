//! Generates `small`/`medium`/`large` resized copies of a `Media` item's original upload via the
//! system `ImageMagick` install (`magick`, or the legacy `convert`+`identify` pair) for images, or
//! `ffmpeg`/`ffprobe` for video, storing them in object storage alongside the original and recording them
//! (each with its own `size_bytes`/`aspect_ratio`) in `Media.sizes`. Used by
//! `bin/convert_media_sizes.rs`.
//!
//! Only PNG/JPEG are converted for images (`CONVERTIBLE_CONTENT_TYPES`) and MP4/QuickTime/WebM for
//! video (`VIDEO_CONVERTIBLE_CONTENT_TYPES`) for now -- both tools handle other common formats
//! fine, but we don't have callers needing them yet.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};
use diesel::dsl::sql;
use diesel::sql_types::Bool;
use diesel::*;
use s3::Bucket;

use crate::db_connection::PgPooledConnection;
use crate::logic::{adjust_server_media_usage_bytes, update_media_storage_used};
use crate::models::{blank_to_none, is_valid_bpm, is_valid_musical_key, Media, MediaConversionExt, MediaMetadata, MediaSize, AUDIO_COVER_ART_CONVERSIONS, AUDIO_PREVIEW_CONVERSIONS, RESIZED_CONVERSIONS, VIDEO_PREVIEW_CONVERSIONS};
use crate::protos::MediaConversion;
use super::audio_analysis::analyze_audio_file;
use crate::schema::media;

pub const CONVERTIBLE_CONTENT_TYPES: [&str; 3] = ["image/png", "image/jpeg", "image/jpg"];
pub const VIDEO_CONVERTIBLE_CONTENT_TYPES: [&str; 3] =
    ["video/mp4", "video/quicktime", "video/webm"];
/// WAV/FLAC are accepted too (and get the same waveform/compressed copies as the lossy formats) --
/// browsers and tools disagree on their MIME types, hence the aliases.
pub const AUDIO_CONVERTIBLE_CONTENT_TYPES: [&str; 8] = [
    "audio/mpeg",
    "audio/ogg",
    "audio/wav",
    "audio/x-wav",
    "audio/wave",
    "audio/vnd.wave",
    "audio/flac",
    "audio/x-flac",
];

/// Content type of the compressed `small`/`medium`/`large` copies of audio: AAC-LC in an MP4
/// (`.m4a`) container. Plays in every browser (including Safari/iOS, which Ogg Opus doesn't yet
/// reliably), and at these bitrates is comparable to what streaming services serve.
const COMPRESSED_AUDIO_CONTENT_TYPE: &str = "audio/mp4";

/// Target AAC bitrate (kbps) of an audio `small`/`medium`/`large` copy: data-saver, the default
/// (`medium`, what lists and inline players request) and high quality (`large`, what the full-size
/// viewer requests).
fn audio_bitrate_kbps(conversion: MediaConversion) -> u32 {
    match conversion {
        MediaConversion::Small => 64,
        MediaConversion::Medium => 128,
        _ => 256,
    }
}

pub fn is_audio_content_type(content_type: &str) -> bool {
    AUDIO_CONVERTIBLE_CONTENT_TYPES.contains(&content_type)
}

/// Whether `content_type` is one `convert_media`/`update_media` treat as video (as opposed to
/// image) -- `pub` since `rpcs::update_media` also needs it, to know whether an item's
/// `video_preview_time_ms` change actually has `VIDEO_PREVIEW_THUMBNAIL_*` sizes to invalidate.
pub fn is_video_content_type(content_type: &str) -> bool {
    VIDEO_CONVERTIBLE_CONTENT_TYPES.contains(&content_type)
}

/// `Media` rows still needing conversion: not yet `processed`, with an original whose content
/// type we know how to convert. `processed` is only ever set once conversion (successfully)
/// completes, so this naturally retries anything a prior run errored out on (including runs where
/// the relevant tool, `ImageMagick` or `ffmpeg`, was missing).
///
/// Content type now lives inside `Media.sizes` (not a plain column), so it can't be filtered at
/// the SQL level as cheaply as before a plain `processed = false` scan -- loads a generous
/// multiple of `limit` still-unprocessed rows and filters/truncates to the real convertible ones
/// in Rust, so a backlog of non-convertible uploads (PDFs, etc.) can't perpetually crowd out real
/// work the way returning fewer-than-`limit` rows per call otherwise would.
pub fn media_pending_conversion(
    conn: &mut PgPooledConnection,
    limit: i64,
) -> QueryResult<Vec<Media>> {
    let content_types: Vec<&str> = CONVERTIBLE_CONTENT_TYPES
        .iter()
        .chain(VIDEO_CONVERTIBLE_CONTENT_TYPES.iter())
        .chain(AUDIO_CONVERTIBLE_CONTENT_TYPES.iter())
        .copied()
        .collect();
    let candidates: Vec<Media> = media::table
        .filter(media::processed.eq(false))
        .order(media::id.asc())
        .limit((limit * 10).max(200))
        .load::<Media>(conn)?;
    Ok(candidates
        .into_iter()
        .filter(|m| {
            m.original()
                .is_some_and(|o| content_types.contains(&o.content_type.as_str()))
        })
        .take(limit as usize)
        .collect())
}

/// Which `ImageMagick` command layout is on `$PATH`: v7 unifies everything under a single
/// `magick` binary (`magick identify ...`, `magick in.png -resize ... out.png`), while v6 (and
/// some v7 compat installs) only provide the separate legacy `convert`/`identify` binaries.
pub struct ImageMagick {
    modern: bool,
}

impl ImageMagick {
    /// Returns `None` if neither command layout is available -- callers should log and skip
    /// conversion entirely rather than fail hard, since ImageMagick is an optional dependency
    /// (see docs/README's "Prerequisites for your $PATH").
    pub fn detect() -> Option<Self> {
        if command_exists("magick") {
            Some(Self { modern: true })
        } else if command_exists("convert") && command_exists("identify") {
            Some(Self { modern: false })
        } else {
            None
        }
    }

    fn convert_command(&self) -> Command {
        if self.modern {
            Command::new("magick")
        } else {
            Command::new("convert")
        }
    }

    /// Dimensions as actually displayed -- i.e. *after* correcting for any EXIF orientation tag,
    /// same as `resize()`'s own `-auto-orient` does. Deliberately routed through
    /// `convert_command()` (writing to the `info:` pseudo-format) rather than bare `identify
    /// -format`: `identify` reports raw, undecoded pixel dimensions and ignores EXIF orientation
    /// entirely, so a photo shot in portrait but stored with landscape pixel data plus a rotate
    /// tag (extremely common -- most phone/DSLR cameras never physically rotate the pixels) would
    /// otherwise be detected -- and thus `aspect_ratio`'d -- as landscape, while every actual
    /// viewer (browsers, `resize()`'s own output) shows it upright.
    fn dimensions(&self, path: &Path) -> Result<(u32, u32)> {
        let output = self
            .convert_command()
            .arg(path)
            .arg("-auto-orient")
            .arg("-format")
            .arg("%w %h")
            .arg("info:")
            .output()
            .context("failed to run convert/magick for dimensions")?;
        if !output.status.success() {
            bail!(
                "convert/magick exited with {}: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut parts = stdout.split_whitespace();
        let width: u32 = parts.next().context("missing width")?.parse()?;
        let height: u32 = parts.next().context("missing height")?.parse()?;
        Ok((width, height))
    }

    /// Resizes `input` to fit within `max_dimension`x`max_dimension`, preserving aspect ratio and
    /// never upscaling (ImageMagick's `>` geometry flag), stripping EXIF/color-profile metadata,
    /// and correcting orientation from EXIF before doing so.
    fn resize(&self, input: &Path, output: &Path, max_dimension: u32) -> Result<()> {
        let status = self
            .convert_command()
            .arg(input)
            .arg("-auto-orient")
            .arg("-strip")
            .arg("-resize")
            .arg(format!("{0}x{0}>", max_dimension))
            .arg(output)
            .status()
            .context("failed to run convert")?;
        if !status.success() {
            bail!("convert exited with {}", status);
        }
        Ok(())
    }

    /// Same resizing as `resize()`, but also forces truecolor (32bpp RGBA) PNG output via
    /// ImageMagick's `PNG32:` coder prefix. `resize()`'s plain PNG output lets ImageMagick choose
    /// an indexed/palette encoding for simple/small images, which the `ico` crate's PNG reader
    /// (`web::server_information`'s favicon.ico builder, its only caller) rejects outright with
    /// "Unsupported PNG color type: Indexed".
    ///
    /// `pub(crate)`: called directly from `web::server_information` to build favicon.ico frames
    /// on demand, bypassing `Converter` and the cluster-wide `ClusterResource::Imagemagick` lock
    /// in `convert_media_sizes.rs` -- that lock caps concurrent *background* conversion load
    /// across a cluster, not this kind of small, synchronous, per-request resize.
    pub(crate) fn resize_to_truecolor_png(
        &self,
        input: &Path,
        output: &Path,
        max_dimension: u32,
    ) -> Result<()> {
        let status = self
            .convert_command()
            .arg(input)
            .arg("-auto-orient")
            .arg("-strip")
            .arg("-resize")
            .arg(format!("{0}x{0}>", max_dimension))
            .arg("-type")
            .arg("TrueColorAlpha")
            .arg(format!("PNG32:{}", output.display()))
            .status()
            .context("failed to run convert")?;
        if !status.success() {
            bail!("convert exited with {}", status);
        }
        Ok(())
    }
}

/// Resizes video `Media` via a system `ffmpeg`/`ffprobe` install.
pub struct FFmpeg;

impl FFmpeg {
    /// Returns `None` if `ffmpeg` or `ffprobe` aren't both on `$PATH` -- callers should log and
    /// skip video conversion entirely rather than fail hard, since ffmpeg is an optional
    /// dependency (see docs/README's "Prerequisites for your $PATH"), same as `ImageMagick`.
    pub fn detect() -> Option<Self> {
        if command_exists("ffmpeg") && command_exists("ffprobe") {
            Some(Self)
        } else {
            None
        }
    }

    /// Dimensions as actually displayed -- i.e. *after* accounting for any rotation transform on
    /// the stream. Phone-recorded video is commonly stored at the camera sensor's native
    /// (landscape) pixel dimensions plus a rotation transform telling players to display it
    /// upright, rather than physically rotating the pixels -- browsers' `<video>` honor that
    /// transform (same as `resize()`'s own scale filter does, since it operates on the decoded,
    /// already-rotated frames), so a portrait recording would otherwise be detected -- and thus
    /// `aspect_ratio`'d -- as landscape. The transform surfaces as either `stream_side_data`'s
    /// `rotation` (modern "Display Matrix" side data) or the legacy `rotate` stream tag,
    /// depending on how the file was produced; either is honored here.
    fn dimensions(&self, path: &Path) -> Result<(u32, u32)> {
        let output = Command::new("ffprobe")
            .arg("-v")
            .arg("error")
            .arg("-select_streams")
            .arg("v:0")
            .arg("-show_entries")
            .arg("stream=width,height:stream_tags=rotate:stream_side_data=rotation")
            .arg("-of")
            .arg("default=noprint_wrappers=1")
            .arg(path)
            .output()
            .context("failed to run ffprobe")?;
        if !output.status.success() {
            bail!(
                "ffprobe exited with {}: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut width: Option<u32> = None;
        let mut height: Option<u32> = None;
        let mut rotation: Option<f64> = None;
        for line in stdout.lines() {
            match line.split_once('=') {
                Some(("width", value)) => width = value.trim().parse().ok(),
                Some(("height", value)) => height = value.trim().parse().ok(),
                Some(("TAG:rotate" | "rotation", value)) => {
                    rotation = value.trim().parse().ok().or(rotation)
                }
                _ => {}
            }
        }
        let width = width.context("missing width")?;
        let height = height.context("missing height")?;

        let quarter_turned = rotation
            .map(|degrees| (degrees.round() as i64).rem_euclid(360) / 90 % 2 == 1)
            .unwrap_or(false);
        Ok(if quarter_turned {
            (height, width)
        } else {
            (width, height)
        })
    }

    /// Resizes `input` to fit within `max_dimension`x`max_dimension`, preserving aspect ratio and
    /// never upscaling (the `min(N,iw/ih)` scale filter, mirroring `ImageMagick::resize`'s `>`
    /// geometry flag), re-encoding with a codec appropriate to `content_type`'s container.
    fn resize(
        &self,
        input: &Path,
        output: &Path,
        max_dimension: u32,
        content_type: &str,
    ) -> Result<()> {
        let mut command = Command::new("ffmpeg");
        command
            .arg("-y")
            .arg("-nostdin")
            .arg("-i")
            .arg(input)
            .arg("-vf")
            .arg(format!(
                "scale='min({0},iw)':'min({0},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
                max_dimension
            ));
        if content_type == "video/webm" {
            command.args([
                "-c:v",
                "libvpx-vp9",
                "-b:v",
                "0",
                "-crf",
                "32",
                "-c:a",
                "libopus",
            ]);
        } else {
            command.args([
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "23",
                "-c:a",
                "aac",
                "-movflags",
                "+faststart",
            ]);
        }
        let status = command
            .arg(output)
            .status()
            .context("failed to run ffmpeg")?;
        if !status.success() {
            bail!("ffmpeg exited with {}", status);
        }
        Ok(())
    }

    /// Total length of `input`, in milliseconds -- used to compute
    /// `MediaMetadata::effective_video_preview_time_ms`'s default (the midpoint, for videos
    /// shorter than 1.5s) before `screenshot` seeks to it.
    fn duration_ms(&self, path: &Path) -> Result<u64> {
        let output = Command::new("ffprobe")
            .arg("-v")
            .arg("error")
            .arg("-show_entries")
            .arg("format=duration")
            .arg("-of")
            .arg("default=noprint_wrappers=1:nokey=1")
            .arg(path)
            .output()
            .context("failed to run ffprobe")?;
        if !output.status.success() {
            bail!(
                "ffprobe exited with {}: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        let seconds: f64 = String::from_utf8_lossy(&output.stdout)
            .trim()
            .parse()
            .context("failed to parse ffprobe duration")?;
        Ok((seconds * 1000.0).round() as u64)
    }

    /// Whether `path` carries embedded cover art -- for an audio file, any video stream at all (ID3
    /// `APIC`, FLAC/Vorbis pictures and MP4 `covr` atoms all surface to ffprobe as an attached-picture
    /// video stream).
    fn has_cover_art(&self, path: &Path) -> Result<bool> {
        let output = Command::new("ffprobe")
            .args(["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_type", "-of", "csv=p=0"])
            .arg(path)
            .output()
            .context("failed to run ffprobe")?;
        if !output.status.success() {
            bail!(
                "ffprobe exited with {}: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        Ok(!String::from_utf8_lossy(&output.stdout).trim().is_empty())
    }

    /// Extracts `input`'s embedded cover art as an `image/jpeg` fitting within
    /// `max_dimension`x`max_dimension` (aspect ratio kept, never upscaled).
    fn cover_art(&self, input: &Path, output: &Path, max_dimension: u32) -> Result<()> {
        let status = Command::new("ffmpeg")
            .args(["-y", "-nostdin", "-i"])
            .arg(input)
            .args(["-an", "-map", "0:v:0", "-frames:v", "1", "-vf"])
            .arg(format!(
                "scale='min({0},iw)':'min({0},ih)':force_original_aspect_ratio=decrease",
                max_dimension
            ))
            .args(["-q:v", "3"])
            .arg(output)
            .status()
            .context("failed to run ffmpeg")?;
        if !status.success() {
            bail!("ffmpeg exited with {}", status);
        }
        Ok(())
    }

    /// Overall bitrate of `path` in bits/second, if ffprobe can tell.
    fn bit_rate(&self, path: &Path) -> Result<Option<u64>> {
        let output = Command::new("ffprobe")
            .args(["-v", "error", "-show_entries", "format=bit_rate", "-of", "default=noprint_wrappers=1:nokey=1"])
            .arg(path)
            .output()
            .context("failed to run ffprobe")?;
        if !output.status.success() {
            bail!(
                "ffprobe exited with {}: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        Ok(String::from_utf8_lossy(&output.stdout).trim().parse().ok())
    }

    /// Re-encodes `input`'s audio as AAC-LC at `kbps` into an `.m4a` -- cover art/video streams
    /// dropped (`-vn`), tags kept, `+faststart` so playback can begin before the download ends.
    fn compress_audio(&self, input: &Path, output: &Path, kbps: u32) -> Result<()> {
        let status = Command::new("ffmpeg")
            .args(["-y", "-nostdin", "-i"])
            .arg(input)
            .args(["-vn", "-c:a", "aac", "-b:a"])
            .arg(format!("{kbps}k"))
            .args(["-movflags", "+faststart"])
            .arg(output)
            .status()
            .context("failed to run ffmpeg")?;
        if !status.success() {
            bail!("ffmpeg exited with {}", status);
        }
        Ok(())
    }

    /// The container-level metadata tags of `path` (ID3 for MP3, Vorbis comments for Ogg/WebM,
    /// QuickTime/iTunes atoms for MP4/MOV, ...), as `ffprobe` normalizes them, keys lowercased. See
    /// `credits_from_tags` for which map to which `MediaMetadata` credit.
    fn tags(&self, path: &Path) -> Result<HashMap<String, String>> {
        let output = Command::new("ffprobe")
            .arg("-v")
            .arg("error")
            .arg("-show_entries")
            .arg("format_tags")
            .arg("-of")
            .arg("json")
            .arg(path)
            .output()
            .context("failed to run ffprobe")?;
        if !output.status.success() {
            bail!(
                "ffprobe exited with {}: {}",
                output.status,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        parse_ffprobe_tags(&String::from_utf8_lossy(&output.stdout))
    }

    /// Captures a single `image/jpeg` poster frame from `input` at `time_ms` milliseconds in,
    /// resized to fit within `max_dimension`x`max_dimension` the same way `resize`'s own scale
    /// filter does (preserving aspect ratio, never upscaling) -- used to generate the
    /// `VIDEO_PREVIEW_THUMBNAIL_*` sizes. `-ss` before `-i` seeks via the (fast, keyframe-based)
    /// demuxer rather than decoding and discarding every frame up to `time_ms`.
    fn screenshot(&self, input: &Path, output: &Path, time_ms: u64, max_dimension: u32) -> Result<()> {
        let status = Command::new("ffmpeg")
            .arg("-y")
            .arg("-nostdin")
            .arg("-ss")
            .arg(format!("{:.3}", time_ms as f64 / 1000.0))
            .arg("-i")
            .arg(input)
            .arg("-frames:v")
            .arg("1")
            .arg("-vf")
            .arg(format!(
                "scale='min({0},iw)':'min({0},ih)':force_original_aspect_ratio=decrease",
                max_dimension
            ))
            .arg(output)
            .status()
            .context("failed to run ffmpeg")?;
        if !status.success() {
            bail!("ffmpeg exited with {}", status);
        }
        Ok(())
    }
}

impl FFmpeg {
    /// Crops `[start_ms, end_ms)` out of `input` at "medium" quality, for `UNLICENSED_PREVIEW_MEDIUM`.
    /// Video is re-encoded to fit within `max_dimension` (same scale filter as `resize`) at a
    /// higher CRF than `resize` uses; audio is re-encoded at a modest VBR bitrate. Codecs follow
    /// `content_type`'s container, as in `resize`. `-ss`/`-t` come *after* `-i` so the cut is
    /// frame/sample-accurate (we're re-encoding anyway).
    fn crop(
        &self,
        input: &Path,
        output: &Path,
        start_ms: u64,
        end_ms: u64,
        is_video: bool,
        max_dimension: u32,
        content_type: &str,
    ) -> Result<()> {
        let mut command = Command::new("ffmpeg");
        command
            .arg("-y")
            .arg("-nostdin")
            .arg("-i")
            .arg(input)
            .arg("-ss")
            .arg(format!("{:.3}", start_ms as f64 / 1000.0))
            .arg("-t")
            .arg(format!("{:.3}", (end_ms - start_ms) as f64 / 1000.0));
        if is_video {
            command.arg("-vf").arg(format!(
                "scale='min({0},iw)':'min({0},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
                max_dimension
            ));
            if content_type == "video/webm" {
                command.args(["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "36", "-c:a", "libopus"]);
            } else {
                command.args([
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "28", "-c:a", "aac", "-b:a",
                    "96k", "-movflags", "+faststart",
                ]);
            }
        } else if content_type == "audio/ogg" {
            command.args(["-vn", "-c:a", "libvorbis", "-q:a", "3"]);
        } else {
            command.args(["-vn", "-c:a", "libmp3lame", "-q:a", "5"]);
        }
        let status = command
            .arg(output)
            .status()
            .context("failed to run ffmpeg")?;
        if !status.success() {
            bail!("ffmpeg exited with {}", status);
        }
        Ok(())
    }
}

/// Audio waveform images are stored square (1:1) -- clients squash them vertically to whatever
/// height suits the layout (a waveform has no fine detail to distort).
const WAVEFORM_ASPECT_RATIO: f32 = 1.0;

impl FFmpeg {
    /// Renders a transparent-background `image/png` waveform of the whole of `input`, exactly `width`
    /// px square, via `showwavespic` -- used to generate the
    /// `AUDIO_PREVIEW_THUMBNAIL_*` sizes. The (light grey) waveform color reads on both light and
    /// dark backgrounds, so one image serves every theme.
    fn waveform(&self, input: &Path, output: &Path, width: u32) -> Result<()> {
        let height = width;
        let status = Command::new("ffmpeg")
            .arg("-y")
            .arg("-nostdin")
            .arg("-i")
            .arg(input)
            .arg("-filter_complex")
            .arg(format!(
                "aformat=channel_layouts=mono,showwavespic=s={width}x{height}:colors=#9a9a9a:draw=full,format=rgba"
            ))
            .arg("-frames:v")
            .arg("1")
            .arg(output)
            .status()
            .context("failed to run ffmpeg")?;
        if !status.success() {
            bail!("ffmpeg exited with {}", status);
        }
        Ok(())
    }
}

/// `ffprobe -show_entries format_tags -of json`'s output -> `{lowercased key: value}`. Pure so it's
/// unit-testable without ffprobe.
pub fn parse_ffprobe_tags(json: &str) -> Result<HashMap<String, String>> {
    let value: serde_json::Value = serde_json::from_str(json).context("unparseable ffprobe output")?;
    Ok(value
        .pointer("/format/tags")
        .and_then(|tags| tags.as_object())
        .map(|tags| {
            tags.iter()
                .filter_map(|(k, v)| v.as_str().map(|v| (k.to_lowercase(), v.to_string())))
                .collect()
        })
        .unwrap_or_default())
}

/// Maps container tags to `MediaMetadata` credits plus musical `start_bpm`/`end_bpm`/`min_bpm`/
/// `max_bpm`/`start_key`/`end_key` (only those fields are populated). The first non-blank tag among each credit's aliases wins:
/// ID3/Vorbis/iTunes/Matroska all spell these a little differently (`artist`/`performer`/
/// `album_artist`, `actor`/`actors`/`starring`, ...). A file's single `BPM` tag (ID3 `TBPM`) can't
/// say how the tempo changes, so it seeds all four BPM fields (likewise a single key tag both keys); keys are normalized by
/// `key_from_tag`, and a tag that isn't a recognizable key/BPM is ignored.
pub fn credits_from_tags(tags: &HashMap<String, String>) -> MediaMetadata {
    let pick = |aliases: &[&str]| {
        aliases
            .iter()
            .find_map(|alias| blank_to_none(tags.get(*alias).cloned()))
    };
    let key = pick(&["initialkey", "initial_key", "tkey", "key"]).and_then(|key| key_from_tag(&key));
    let bpm = pick(&["bpm", "tbpm", "tempo", "beats_per_minute"])
        .and_then(|bpm| bpm.parse::<f32>().ok())
        .filter(|bpm| is_valid_bpm(*bpm));
    MediaMetadata {
        start_bpm: bpm,
        end_bpm: bpm,
        min_bpm: bpm,
        max_bpm: bpm,
        start_key: key.clone(),
        end_key: key,
        artist: pick(&["artist", "performer", "album_artist"]),
        album: pick(&["album"]),
        composer: pick(&["composer"]),
        director: pick(&["director"]),
        producer: pick(&["producer"]),
        starring: pick(&["starring", "actor", "actors"]),
        cast: pick(&["cast"]),
        crew: pick(&["crew"]),
        narrator: pick(&["narrator", "reader"]),
        publisher: pick(&["publisher", "label"]),
        ..Default::default()
    }
}

/// A key tag as a valid `MediaMetadata.key` (see `is_valid_musical_key`), or `None`. Besides already-valid
/// keys (`Am`, `C#m`), taggers commonly write spelled-out keys: `A minor`, `Db major`, `F# Min`, `Bb`.
pub fn key_from_tag(tag: &str) -> Option<String> {
    let tag = tag.trim();
    if is_valid_musical_key(tag) {
        return Some(tag.to_string());
    }
    let (tonic, mode) = tag.split_once(char::is_whitespace)?;
    let suffix = match mode.trim().to_lowercase().as_str() {
        "minor" | "min" => "m",
        "major" | "maj" => "",
        _ => return None,
    };
    let key = format!("{tonic}{suffix}");
    is_valid_musical_key(&key).then_some(key)
}

/// The file's own `title` tag, when it should replace `item.name` -- i.e. the name is still the
/// upload's filename (the last segment of the original's object storage path, after the
/// `{uuid}-` prefix `create_media` adds) or blank, so a name the owner has since edited is kept.
fn title_name_override(
    item: &Media,
    original_object_storage_path: &str,
    tags: &HashMap<String, String>,
) -> Option<String> {
    let title = blank_to_none(tags.get("title").cloned())?.trim().to_string();
    let still_filename = match item.name.as_deref().map(str::trim) {
        None | Some("") => true,
        Some(name) => original_object_storage_path.ends_with(&format!("-{name}")),
    };
    (still_filename && item.name.as_deref() != Some(title.as_str())).then_some(title)
}

fn command_exists(program: &str) -> bool {
    Command::new(program)
        .arg("-version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn extension_for_content_type(content_type: &str) -> Result<&'static str> {
    match content_type {
        "image/png" => Ok("png"),
        "image/jpeg" | "image/jpg" => Ok("jpg"),
        "video/mp4" => Ok("mp4"),
        "video/quicktime" => Ok("mov"),
        "video/webm" => Ok("webm"),
        "audio/mpeg" => Ok("mp3"),
        "audio/ogg" => Ok("ogg"),
        "audio/wav" | "audio/x-wav" | "audio/wave" | "audio/vnd.wave" => Ok("wav"),
        "audio/flac" | "audio/x-flac" => Ok("flac"),
        "audio/mp4" => Ok("m4a"),
        other => bail!("unsupported content type: {other}"),
    }
}

/// Content type for a *resized* copy, which may differ from the original's. QuickTime
/// (`video/quicktime`) is re-muxed into an MP4 container: `FFmpeg::resize` already re-encodes it
/// to H.264/AAC (same codecs an MP4 would use) since it isn't `video/webm`, so this is a free
/// container swap -- and it matters because Chrome refuses to play `video/quicktime` inline when a
/// media URL is navigated to directly (e.g. shared/opened in its own tab), downloading it instead
/// regardless of the actual codec inside, while `video/mp4` plays fine. The original upload is left
/// as `video/quicktime` (some clients care about round-tripping the exact original), so this only
/// ever affects `small`/`medium`/`large`.
fn resized_content_type(original_content_type: &str) -> &str {
    match original_content_type {
        "video/quicktime" => "video/mp4",
        other => other,
    }
}

/// Which tool converts a given `Media` item, chosen by its content type.
enum Converter<'a> {
    Image(&'a ImageMagick),
    Video(&'a FFmpeg),
    /// Audio has no pixel dimensions and no resized copies -- only waveform thumbnails.
    Audio(&'a FFmpeg),
}

impl Converter<'_> {
    fn dimensions(&self, path: &Path) -> Result<(u32, u32)> {
        match self {
            Converter::Image(imagemagick) => imagemagick.dimensions(path),
            Converter::Video(ffmpeg) => ffmpeg.dimensions(path),
            Converter::Audio(_) => bail!("audio has no dimensions"),
        }
    }

    fn resize(
        &self,
        input: &Path,
        output: &Path,
        max_dimension: u32,
        content_type: &str,
    ) -> Result<()> {
        match self {
            Converter::Image(imagemagick) => imagemagick.resize(input, output, max_dimension),
            Converter::Video(ffmpeg) => ffmpeg.resize(input, output, max_dimension, content_type),
            Converter::Audio(_) => bail!("audio has no resized copies"),
        }
    }
}

/// Downloads `item`'s original from object storage, generates any `RESIZED_CONVERSIONS` entry it's larger
/// than (skipping sizes it already fits within -- those fall back to the original), uploads the
/// results back to object storage next to the original, records each new size's `size_bytes`/
/// `aspect_ratio` (and backfills the original's own `aspect_ratio`, which is unknown until this
/// point) into `Media.sizes`, updates the owner's `media_storage_bytes_used`, and marks `item`
/// `processed`.
///
/// `imagemagick`/`ffmpeg` are `None` when the respective tool wasn't found on `$PATH` at startup;
/// converting a `Media` item that needs the missing one fails (and is retried next run) without
/// affecting items convertible by the other.
pub async fn convert_media(
    item: &Media,
    imagemagick: Option<&ImageMagick>,
    ffmpeg: Option<&FFmpeg>,
    bucket: &Bucket,
    tmp_dir: &Path,
    conn: &mut PgPooledConnection,
) -> Result<()> {
    let mut original = item
        .original()
        .context("Media has no MEDIA_CONVERSION_ORIGINAL size")?;

    let converter = if is_audio_content_type(&original.content_type) {
        Converter::Audio(ffmpeg.context("ffmpeg not found on $PATH; cannot convert audio Media")?)
    } else if is_video_content_type(&original.content_type) {
        Converter::Video(ffmpeg.context("ffmpeg not found on $PATH; cannot convert video Media")?)
    } else {
        Converter::Image(
            imagemagick.context("ImageMagick not found on $PATH; cannot convert image Media")?,
        )
    };

    let extension = extension_for_content_type(&original.content_type)?;
    let input_path: PathBuf = tmp_dir.join(format!("{}-original.{}", item.id, extension));

    let original_bytes = bucket
        .get_object(&original.object_storage_path)
        .await
        .context("failed to download original from object storage")?;
    std::fs::write(&input_path, original_bytes.as_slice())?;

    // Audio has no dimensions: skip resizing entirely and leave the original's `aspect_ratio` unset.
    let is_audio = matches!(converter, Converter::Audio(_));
    let (width, height) = if is_audio { (0, 0) } else { converter.dimensions(&input_path)? };
    let aspect_ratio = width as f32 / height as f32;
    if !is_audio {
        original.aspect_ratio = Some(aspect_ratio);
    }

    let resized_content_type = resized_content_type(&original.content_type).to_string();
    let resized_extension = extension_for_content_type(&resized_content_type)?;

    let mut sizes = vec![original];

    for conversion in RESIZED_CONVERSIONS.into_iter().filter(|_| !is_audio) {
        if width.max(height) <= conversion.max_dimension() {
            log::info!(
                "Media {} ({}x{}) already fits within '{}' ({}px) -- skipping",
                item.id,
                width,
                height,
                conversion.key(),
                conversion.max_dimension()
            );
            continue;
        }

        let output_path = tmp_dir.join(format!(
            "{}-{}.{}",
            item.id,
            conversion.key(),
            resized_extension
        ));
        converter.resize(
            &input_path,
            &output_path,
            conversion.max_dimension(),
            &resized_content_type,
        )?;
        let output_bytes = std::fs::read(&output_path)?;
        let _ = std::fs::remove_file(&output_path);

        let converted_object_storage_path = format!("{}.{}", sizes[0].object_storage_path, conversion.key());
        bucket
            .put_object_with_content_type(&converted_object_storage_path, &output_bytes, &resized_content_type)
            .await
            .context("failed to upload converted size to object storage")?;

        log::info!(
            "Media {}: generated '{}' ({} bytes) at {}",
            item.id,
            conversion.key(),
            output_bytes.len(),
            converted_object_storage_path
        );
        sizes.push(MediaSize {
            conversion: conversion as i32,
            object_storage_path: converted_object_storage_path,
            content_type: resized_content_type.clone(),
            size_bytes: output_bytes.len() as i64,
            aspect_ratio: Some(aspect_ratio),
        });
    }

    // Video-only: `image/jpeg` poster frames at `MediaMetadata.effective_video_preview_time_ms`,
    // at the same 3 dimension tiers as `RESIZED_CONVERSIONS` above. Unlike those, generated
    // unconditionally regardless of the original's own dimensions (never skipped as "already
    // fits") -- there's no directly-renderable fallback for a video the way `MEDIA_CONVERSION_
    // ORIGINAL` itself serves as one for an image, so every video needs an actual poster image.
    if let Converter::Video(ffmpeg) = &converter {
        let duration_ms = ffmpeg.duration_ms(&input_path)?;
        let preview_time_ms = item.metadata().effective_video_preview_time_ms(duration_ms);

        for conversion in VIDEO_PREVIEW_CONVERSIONS {
            let output_path = tmp_dir.join(format!("{}-{}.jpg", item.id, conversion.key()));
            ffmpeg.screenshot(&input_path, &output_path, preview_time_ms, conversion.max_dimension())?;
            let output_bytes = std::fs::read(&output_path)?;
            let _ = std::fs::remove_file(&output_path);

            let converted_object_storage_path = format!("{}.{}", sizes[0].object_storage_path, conversion.key());
            bucket
                .put_object_with_content_type(&converted_object_storage_path, &output_bytes, "image/jpeg")
                .await
                .context("failed to upload video preview thumbnail to object storage")?;

            log::info!(
                "Media {}: generated '{}' ({} bytes) at {}",
                item.id,
                conversion.key(),
                output_bytes.len(),
                converted_object_storage_path
            );
            sizes.push(MediaSize {
                conversion: conversion as i32,
                object_storage_path: converted_object_storage_path,
                content_type: "image/jpeg".to_string(),
                size_bytes: output_bytes.len() as i64,
                aspect_ratio: Some(aspect_ratio),
            });
        }
    }

    // Audio-only: compressed AAC copies at 3 quality tiers. A tier is skipped when the original's
    // own bitrate is already at or below it (re-encoding would only make it bigger/worse) -- the
    // server then falls back to the original for that size, as for images that already fit.
    if let Converter::Audio(ffmpeg) = &converter {
        let original_bit_rate = ffmpeg.bit_rate(&input_path).unwrap_or(None);
        for conversion in RESIZED_CONVERSIONS {
            let kbps = audio_bitrate_kbps(conversion);
            if original_bit_rate.is_some_and(|bps| bps <= kbps as u64 * 1000) {
                log::info!(
                    "Media {} ({:?} bps) already at or below '{}' ({} kbps) -- skipping",
                    item.id,
                    original_bit_rate,
                    conversion.key(),
                    kbps
                );
                continue;
            }
            let output_path = tmp_dir.join(format!("{}-{}.m4a", item.id, conversion.key()));
            ffmpeg.compress_audio(&input_path, &output_path, kbps)?;
            let output_bytes = std::fs::read(&output_path)?;
            let _ = std::fs::remove_file(&output_path);

            let converted_object_storage_path = format!("{}.{}", sizes[0].object_storage_path, conversion.key());
            bucket
                .put_object_with_content_type(&converted_object_storage_path, &output_bytes, COMPRESSED_AUDIO_CONTENT_TYPE)
                .await
                .context("failed to upload compressed audio to object storage")?;
            log::info!(
                "Media {}: generated '{}' ({} kbps, {} bytes) at {}",
                item.id,
                conversion.key(),
                kbps,
                output_bytes.len(),
                converted_object_storage_path
            );
            sizes.push(MediaSize {
                conversion: conversion as i32,
                object_storage_path: converted_object_storage_path,
                content_type: COMPRESSED_AUDIO_CONTENT_TYPE.to_string(),
                size_bytes: output_bytes.len() as i64,
                aspect_ratio: None,
            });
        }
    }

    // Audio-only: the embedded cover art, if any, as `image/jpeg` at the 3 dimension tiers.
    // Best-effort -- a file whose art ffmpeg can't decode just gets no cover art sizes.
    if let Converter::Audio(ffmpeg) = &converter {
        if ffmpeg.has_cover_art(&input_path).unwrap_or(false) {
            let art_aspect_ratio = ffmpeg.dimensions(&input_path).ok().map(|(w, h)| w as f32 / h as f32);
            for conversion in AUDIO_COVER_ART_CONVERSIONS {
                let output_path = tmp_dir.join(format!("{}-{}.jpg", item.id, conversion.key()));
                if let Err(e) = ffmpeg.cover_art(&input_path, &output_path, conversion.max_dimension()) {
                    log::warn!("Media {}: couldn't extract cover art (skipping): {:#}", item.id, e);
                    break;
                }
                let output_bytes = std::fs::read(&output_path)?;
                let _ = std::fs::remove_file(&output_path);

                let converted_object_storage_path = format!("{}.{}", sizes[0].object_storage_path, conversion.key());
                bucket
                    .put_object_with_content_type(&converted_object_storage_path, &output_bytes, "image/jpeg")
                    .await
                    .context("failed to upload audio cover art to object storage")?;
                log::info!(
                    "Media {}: generated '{}' ({} bytes) at {}",
                    item.id,
                    conversion.key(),
                    output_bytes.len(),
                    converted_object_storage_path
                );
                sizes.push(MediaSize {
                    conversion: conversion as i32,
                    object_storage_path: converted_object_storage_path,
                    content_type: "image/jpeg".to_string(),
                    size_bytes: output_bytes.len() as i64,
                    aspect_ratio: art_aspect_ratio,
                });
            }
        }
    }

    // Audio-only: `image/png` waveforms of the whole file at the 3 width tiers.
    if let Converter::Audio(ffmpeg) = &converter {
        for conversion in AUDIO_PREVIEW_CONVERSIONS {
            let output_path = tmp_dir.join(format!("{}-{}.png", item.id, conversion.key()));
            ffmpeg.waveform(&input_path, &output_path, conversion.max_dimension())?;
            let output_bytes = std::fs::read(&output_path)?;
            let _ = std::fs::remove_file(&output_path);

            let converted_object_storage_path = format!("{}.{}", sizes[0].object_storage_path, conversion.key());
            bucket
                .put_object_with_content_type(&converted_object_storage_path, &output_bytes, "image/png")
                .await
                .context("failed to upload audio waveform thumbnail to object storage")?;

            log::info!(
                "Media {}: generated '{}' ({} bytes) at {}",
                item.id,
                conversion.key(),
                output_bytes.len(),
                converted_object_storage_path
            );
            sizes.push(MediaSize {
                conversion: conversion as i32,
                object_storage_path: converted_object_storage_path,
                content_type: "image/png".to_string(),
                size_bytes: output_bytes.len() as i64,
                aspect_ratio: Some(WAVEFORM_ASPECT_RATIO),
            });
        }
    }

    // Audio/video: the cropped `UNLICENSED_PREVIEW_MEDIUM` served to viewers without a license for
    // `LICENSED` media. Skipped if `unlicensed_preview_start_ms` is past the end of the media.
    if let Converter::Audio(ffmpeg) | Converter::Video(ffmpeg) = &converter {
        let duration_ms = ffmpeg.duration_ms(&input_path)?;
        if let Some((start_ms, end_ms)) =
            item.metadata().effective_unlicensed_preview_range_ms(duration_ms)
        {
            let is_video = matches!(converter, Converter::Video(_));
            let content_type = if is_video {
                resized_content_type.clone()
            } else if sizes[0].content_type == "audio/ogg" {
                "audio/ogg".to_string()
            } else {
                // MP3 stays MP3; WAV/FLAC (far too big for a "preview") become MP3 too.
                "audio/mpeg".to_string()
            };
            let conversion = MediaConversion::UnlicensedPreviewMedium;
            let output_path = tmp_dir.join(format!(
                "{}-{}.{}",
                item.id,
                conversion.key(),
                extension_for_content_type(&content_type)?
            ));
            ffmpeg.crop(
                &input_path,
                &output_path,
                start_ms,
                end_ms,
                is_video,
                conversion.max_dimension(),
                &content_type,
            )?;
            let output_bytes = std::fs::read(&output_path)?;
            let _ = std::fs::remove_file(&output_path);

            let converted_object_storage_path =
                format!("{}.{}", sizes[0].object_storage_path, conversion.key());
            bucket
                .put_object_with_content_type(&converted_object_storage_path, &output_bytes, &content_type)
                .await
                .context("failed to upload unlicensed preview to object storage")?;
            log::info!(
                "Media {}: generated '{}' ({}ms-{}ms, {} bytes) at {}",
                item.id,
                conversion.key(),
                start_ms,
                end_ms,
                output_bytes.len(),
                converted_object_storage_path
            );
            sizes.push(MediaSize {
                conversion: conversion as i32,
                object_storage_path: converted_object_storage_path,
                content_type,
                size_bytes: output_bytes.len() as i64,
                aspect_ratio: if is_video { Some(aspect_ratio) } else { None },
            });
        }
    }

    // Audio/video, first conversion only (i.e. the item has nothing but its original so far -- a
    // reconversion after an edit shouldn't re-fill a credit the owner deliberately cleared): seed
    // blank credits from the file's own tags. Best-effort -- unreadable/missing tags are logged and
    // skipped, never failing the conversion.
    let mut metadata = item.metadata();
    let mut title_name: Option<String> = None;
    let credits_changed = match &converter {
        Converter::Audio(ffmpeg) | Converter::Video(ffmpeg) if item.sizes().len() <= 1 => {
            match ffmpeg.tags(&input_path) {
                Ok(tags) => {
                    title_name = title_name_override(&item, &sizes[0].object_storage_path, &tags);
                    metadata.fill_missing_credits(&credits_from_tags(&tags))
                }
                Err(e) => {
                    log::warn!("Media {}: couldn't read tags (skipping): {:#}", item.id, e);
                    false
                }
            }
        }
        _ => false,
    };

    // Audio, first conversion only: whatever tempo/key the tags didn't supply is estimated from the
    // audio itself (see `audio_analysis`). Best-effort, like the tags above.
    let analysis_changed = match &converter {
        Converter::Audio(_)
            if item.sizes().len() <= 1 && needs_analysis(&metadata) =>
        {
            match analyze_audio_file(&input_path) {
                Ok(analysis) => {
                    log::info!("Media {}: analyzed {:?}", item.id, analysis);
                    metadata.fill_missing_credits(&analysis.into_metadata())
                }
                Err(e) => {
                    log::warn!("Media {}: couldn't analyze tempo/key (skipping): {:#}", item.id, e);
                    false
                }
            }
        }
        _ => false,
    };
    let credits_changed = credits_changed || analysis_changed;

    let _ = std::fs::remove_file(&input_path);

    diesel::update(media::table.find(item.id))
        .set((
            media::sizes.eq(serde_json::to_value(&sizes)?),
            media::processed.eq(true),
        ))
        .execute(conn)?;
    if credits_changed {
        diesel::update(media::table.find(item.id))
            .set(media::metadata.eq(serde_json::to_value(&metadata)?))
            .execute(conn)?;
    }
    if let Some(name) = title_name {
        diesel::update(media::table.find(item.id))
            .set(media::name.eq(Some(name)))
            .execute(conn)?;
    }

    if let Some(user_id) = item.user_id {
        update_media_storage_used(user_id, conn)?;
    }
    // `sizes[0]` is the original, carried over unchanged (its `size_bytes` doesn't change here,
    // only `aspect_ratio` gets backfilled) -- every entry after it is newly generated by this run,
    // so that's the actual added weight.
    let added_bytes: i64 = sizes.iter().skip(1).map(|s| s.size_bytes).sum();
    adjust_server_media_usage_bytes(conn, added_bytes)?;

    Ok(())
}

/// `Media` rows with at least one non-`Original` `sizes` entry still tagged `video/quicktime` --
/// left over from before `resized_content_type` started re-muxing resized video copies to MP4 (see
/// its own doc comment for why `video/quicktime` breaks Chrome's inline playback). Paged by `id` via
/// `min_id` (rather than a plain `processed = false` filter, since these rows are already
/// `processed`) so `bin/reencode_quicktime_media.rs` can walk the whole backlog in one run without
/// re-fetching a row it already handled -- including one it skipped because its original was
/// missing, which would otherwise match this filter forever.
pub fn media_with_quicktime_resized_sizes(
    conn: &mut PgPooledConnection,
    min_id: i64,
    limit: i64,
) -> QueryResult<Vec<Media>> {
    media::table
        .filter(media::id.gt(min_id))
        .filter(sql::<Bool>(
            r#"EXISTS (
                SELECT 1 FROM jsonb_array_elements(sizes) e
                WHERE e->>'content_type' = 'video/quicktime'
                AND (e->>'conversion')::int <> 0
            )"#,
        ))
        .order(media::id.asc())
        .limit(limit)
        .load::<Media>(conn)
}

/// Strips `item`'s `video/quicktime`-tagged resized (`small`/`medium`/`large`) `sizes` entries and
/// deletes their object storage objects, then marks `item` unprocessed so the ordinary `convert_media_sizes`
/// job regenerates them (now correctly muxed to MP4 -- see `resized_content_type`) next time it
/// runs. Only touches rows whose original is still actually downloadable from object storage -- originals
/// can be pruned independently of resized copies, and there'd be no source to regenerate anything
/// from for a row missing one, so those are left untouched (returns `Ok(false)`) rather than
/// stripped down to nothing. Returns `Ok(false)` too if the row turns out to have nothing to strip
/// (a defensive check against a race with a concurrent run/fix, not expected in practice since
/// callers already select via [`media_with_quicktime_resized_sizes`]).
pub async fn strip_quicktime_resized_sizes(
    item: &Media,
    bucket: &Bucket,
    conn: &mut PgPooledConnection,
) -> Result<bool> {
    let Some(original) = item.original() else {
        return Ok(false);
    };
    if bucket.head_object(&original.object_storage_path).await.is_err() {
        return Ok(false);
    }

    let (removed, kept): (Vec<MediaSize>, Vec<MediaSize>) =
        item.sizes().into_iter().partition(|s| {
            s.conversion() != MediaConversion::Original && s.content_type == "video/quicktime"
        });
    if removed.is_empty() {
        return Ok(false);
    }

    for size in &removed {
        if let Err(e) = bucket.delete_object(&size.object_storage_path).await {
            log::warn!(
                "Media {}: failed to delete stale object storage object {}: {:?}",
                item.id,
                size.object_storage_path,
                e
            );
        }
    }

    diesel::update(media::table.find(item.id))
        .set((
            media::sizes.eq(serde_json::to_value(&kept)?),
            media::processed.eq(false),
        ))
        .execute(conn)?;
    if let Some(user_id) = item.user_id {
        update_media_storage_used(user_id, conn)?;
    }
    let removed_bytes: i64 = removed.iter().map(|s| s.size_bytes).sum();
    adjust_server_media_usage_bytes(conn, -removed_bytes)?;

    log::info!(
        "Media {}: stripped {} QuickTime-tagged resized size(s); marked unprocessed for regeneration.",
        item.id,
        removed.len()
    );
    Ok(true)
}

/// Already-`processed` audio `Media` rows (original content type `audio/*`), paged by `id` via
/// `min_id` -- see `media_with_quicktime_resized_sizes` for why paging rather than a filter.
/// For `bin/reconvert_audio_media.rs`.
pub fn audio_media(conn: &mut PgPooledConnection, min_id: i64, limit: i64) -> QueryResult<Vec<Media>> {
    media::table
        .filter(media::id.gt(min_id))
        .filter(media::processed.eq(true))
        .filter(sql::<Bool>(
            r#"EXISTS (
                SELECT 1 FROM jsonb_array_elements(sizes) e
                WHERE (e->>'conversion')::int = 0
                AND e->>'content_type' LIKE 'audio/%'
            )"#,
        ))
        .order(media::id.asc())
        .limit(limit)
        .load::<Media>(conn)
}

/// Whether any of `metadata`'s musical (`audio_analysis`-estimable) fields is still unset.
fn needs_analysis(metadata: &MediaMetadata) -> bool {
    [metadata.start_bpm, metadata.end_bpm, metadata.min_bpm, metadata.max_bpm]
        .iter()
        .any(Option::is_none)
        || metadata.start_key.is_none()
        || metadata.end_key.is_none()
}

/// Which of `convert_media`'s metadata seeding steps `backfill_audio_metadata` runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MetadataBackfill {
    /// Read the file's own tags: credits (artist, composer, ...) and any BPM/key tags.
    pub stored: bool,
    /// Estimate BPM/key from the audio itself (see `audio_analysis`).
    pub calculated: bool,
}

/// Seeds *unset* metadata of an already-converted audio `item` from its original -- the same steps
/// `convert_media` runs on a first conversion (`which` picks the steps) but without touching its
/// sizes, so it's cheap enough to run across a whole library (`bin/reconvert_audio_media.rs`'s
/// `--stored-metadata-only`/`--calculated-metadata-only`). Tags run before analysis, so a file's own
/// BPM/key tag wins over an estimate. Never overwrites a set field, and merges into the row's
/// *current* metadata (re-read after the slow part) so a concurrent owner edit isn't clobbered.
/// Unlike `convert_media`'s first-conversion seeding, a credit the owner deliberately cleared is
/// filled again by `stored`. Does not rename the item from its `title` tag. Returns whether anything changed.
pub async fn backfill_audio_metadata(
    item: &Media,
    which: MetadataBackfill,
    ffmpeg: &FFmpeg,
    bucket: &Bucket,
    tmp_dir: &Path,
    conn: &mut PgPooledConnection,
) -> Result<bool> {
    let calculate = which.calculated && needs_analysis(&item.metadata());
    if !which.stored && !calculate {
        return Ok(false);
    }
    let original = item.original().context("Media has no MEDIA_CONVERSION_ORIGINAL size")?;
    let input_path = tmp_dir.join(format!(
        "{}-backfill.{}",
        item.id,
        extension_for_content_type(&original.content_type)?
    ));
    let original_bytes = bucket
        .get_object(&original.object_storage_path)
        .await
        .context("failed to download original from object storage")?;
    std::fs::write(&input_path, original_bytes.as_slice())?;

    let found = (|| -> Result<MediaMetadata> {
        let mut found = MediaMetadata::default();
        if which.stored {
            found = credits_from_tags(&ffmpeg.tags(&input_path).context("couldn't read tags")?);
        }
        if calculate {
            found.fill_missing_credits(&analyze_audio_file(&input_path)?.into_metadata());
        }
        Ok(found)
    })();
    let _ = std::fs::remove_file(&input_path);

    let mut metadata = crate::models::get_media(item.id, conn)
        .map_err(|e| anyhow::anyhow!("failed to re-read media: {}", e))?
        .metadata();
    let changed = metadata.fill_missing_credits(&found?);
    if changed {
        diesel::update(media::table.find(item.id))
            .set(media::metadata.eq(serde_json::to_value(&metadata)?))
            .execute(conn)?;
    }
    Ok(changed)
}

/// Strips every derived (non-`Original`) `sizes` entry from audio `item` -- deleting their object
/// storage objects -- and marks it unprocessed, so `convert_media_sizes` regenerates the lot with
/// the current recipe (compressed AAC tiers, waveforms, embedded cover art, tag seeding of blank
/// credits/name -- see `convert_media`). Like `strip_quicktime_resized_sizes`, leaves rows whose
/// original is gone alone (`Ok(false)`), since there'd be nothing to regenerate from.
pub async fn strip_derived_audio_sizes(
    item: &Media,
    bucket: &Bucket,
    conn: &mut PgPooledConnection,
) -> Result<bool> {
    let Some(original) = item.original() else {
        return Ok(false);
    };
    if bucket.head_object(&original.object_storage_path).await.is_err() {
        return Ok(false);
    }

    let (kept, removed): (Vec<MediaSize>, Vec<MediaSize>) = item
        .sizes()
        .into_iter()
        .partition(|s| s.conversion() == MediaConversion::Original);
    for size in &removed {
        if let Err(e) = bucket.delete_object(&size.object_storage_path).await {
            log::warn!(
                "Media {}: failed to delete stale object storage object {}: {:?}",
                item.id,
                size.object_storage_path,
                e
            );
        }
    }

    diesel::update(media::table.find(item.id))
        .set((
            media::sizes.eq(serde_json::to_value(&kept)?),
            media::processed.eq(false),
        ))
        .execute(conn)?;
    if let Some(user_id) = item.user_id {
        update_media_storage_used(user_id, conn)?;
    }
    let removed_bytes: i64 = removed.iter().map(|s| s.size_bytes).sum();
    adjust_server_media_usage_bytes(conn, -removed_bytes)?;

    log::info!(
        "Media {}: stripped {} derived size(s); marked unprocessed for regeneration.",
        item.id,
        removed.len()
    );
    Ok(true)
}

#[cfg(test)]
mod tag_tests {
    use super::*;

    #[test]
    fn parses_and_lowercases_ffprobe_tags() {
        let tags = parse_ffprobe_tags(r#"{"format": {"tags": {"ARTIST": "Miles Davis", "Album": "Kind of Blue", "n": 3}}}"#).unwrap();
        assert_eq!(tags.get("artist"), Some(&"Miles Davis".to_string()));
        assert_eq!(tags.get("album"), Some(&"Kind of Blue".to_string()));
        assert!(!tags.contains_key("n"), "non-string tags are ignored");
    }

    #[test]
    fn no_tags_is_empty_not_an_error() {
        assert!(parse_ffprobe_tags(r#"{"format": {}}"#).unwrap().is_empty());
        assert!(parse_ffprobe_tags("{}").unwrap().is_empty());
        assert!(parse_ffprobe_tags("not json").is_err());
    }

    #[test]
    fn credits_use_aliases_and_skip_blanks() {
        let tags: HashMap<String, String> = [
            ("performer", "Trane"),
            ("album_artist", "ignored, performer wins"),
            ("actor", "Someone"),
            ("composer", "   "),
            ("label", "Impulse!"),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        let credits = credits_from_tags(&tags);
        assert_eq!(credits.artist.as_deref(), Some("Trane"));
        assert_eq!(credits.starring.as_deref(), Some("Someone"));
        assert_eq!(credits.publisher.as_deref(), Some("Impulse!"));
        assert_eq!(credits.composer, None);
    }

    #[test]
    fn bpm_and_key_tags_seed_musical_fields() {
        let tags: HashMap<String, String> = [("tbpm", "128"), ("tkey", "F# minor")]
            .into_iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        let metadata = credits_from_tags(&tags);
        assert_eq!((metadata.start_bpm, metadata.end_bpm), (Some(128.0), Some(128.0)));
        assert_eq!((metadata.min_bpm, metadata.max_bpm), (Some(128.0), Some(128.0)));
        assert_eq!((metadata.start_key.as_deref(), metadata.end_key.as_deref()), (Some("F#m"), Some("F#m")));

        let junk: HashMap<String, String> = [("bpm", "fast"), ("initialkey", "8A")]
            .into_iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        let metadata = credits_from_tags(&junk);
        assert_eq!((metadata.start_bpm, metadata.max_bpm, metadata.start_key), (None, None, None));
    }

    #[test]
    fn key_tags_are_normalized() {
        assert_eq!(key_from_tag(" Am ").as_deref(), Some("Am"));
        assert_eq!(key_from_tag("A minor").as_deref(), Some("Am"));
        assert_eq!(key_from_tag("Db Major").as_deref(), Some("Db"));
        assert_eq!(key_from_tag("Bb min").as_deref(), Some("Bbm"));
        assert_eq!(key_from_tag("H"), None);
        assert_eq!(key_from_tag("C lydian"), None);
    }

    #[test]
    fn fill_missing_credits_never_overwrites() {
        let mut metadata = MediaMetadata { artist: Some("Owner Edit".to_string()), ..Default::default() };
        let tags = MediaMetadata { artist: Some("Tag".to_string()), album: Some("Tag Album".to_string()), ..Default::default() };
        assert!(metadata.fill_missing_credits(&tags));
        assert_eq!(metadata.artist.as_deref(), Some("Owner Edit"));
        assert_eq!(metadata.album.as_deref(), Some("Tag Album"));
        assert!(!metadata.fill_missing_credits(&tags), "second fill changes nothing");
    }

    /// End to end against the real `ffprobe`/`ffmpeg`, skipped where they aren't installed.
    #[test]
    fn reads_id3_tags_from_a_real_file() {
        let Some(ffmpeg) = FFmpeg::detect() else { return };
        let path = std::env::temp_dir().join(format!("rellm-tag-test-{}.mp3", std::process::id()));
        let status = Command::new("ffmpeg")
            .args(["-y", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=1"])
            .args(["-metadata", "artist=Test Artist", "-metadata", "composer=Test Composer"])
            .arg(&path)
            .status()
            .unwrap();
        assert!(status.success());
        let credits = credits_from_tags(&ffmpeg.tags(&path).unwrap());
        let _ = std::fs::remove_file(&path);
        assert_eq!(credits.artist.as_deref(), Some("Test Artist"));
        assert_eq!(credits.composer.as_deref(), Some("Test Composer"));
    }
}
