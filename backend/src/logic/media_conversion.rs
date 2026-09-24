//! Generates `small`/`medium`/`large` resized copies of a `Media` item's original upload via the
//! system `ImageMagick` install (`magick`, or the legacy `convert`+`identify` pair) for images, or
//! `ffmpeg`/`ffprobe` for video, storing them in object storage alongside the original and recording them
//! (each with its own `size_bytes`/`aspect_ratio`) in `Media.sizes`. Used by
//! `bin/convert_media_sizes.rs`.
//!
//! Only PNG/JPEG are converted for images (`CONVERTIBLE_CONTENT_TYPES`) and MP4/QuickTime/WebM for
//! video (`VIDEO_CONVERTIBLE_CONTENT_TYPES`) for now -- both tools handle other common formats
//! fine, but we don't have callers needing them yet.

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};
use diesel::dsl::sql;
use diesel::sql_types::Bool;
use diesel::*;
use s3::Bucket;

use crate::db_connection::PgPooledConnection;
use crate::logic::update_media_storage_used;
use crate::models::{Media, MediaConversionExt, MediaSize, RESIZED_CONVERSIONS, VIDEO_PREVIEW_CONVERSIONS};
use crate::protos::MediaConversion;
use crate::schema::media;

pub const CONVERTIBLE_CONTENT_TYPES: [&str; 3] = ["image/png", "image/jpeg", "image/jpg"];
pub const VIDEO_CONVERTIBLE_CONTENT_TYPES: [&str; 3] =
    ["video/mp4", "video/quicktime", "video/webm"];

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
}

impl Converter<'_> {
    fn dimensions(&self, path: &Path) -> Result<(u32, u32)> {
        match self {
            Converter::Image(imagemagick) => imagemagick.dimensions(path),
            Converter::Video(ffmpeg) => ffmpeg.dimensions(path),
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

    let converter = if is_video_content_type(&original.content_type) {
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

    let (width, height) = converter.dimensions(&input_path)?;
    let aspect_ratio = width as f32 / height as f32;
    original.aspect_ratio = Some(aspect_ratio);

    let resized_content_type = resized_content_type(&original.content_type).to_string();
    let resized_extension = extension_for_content_type(&resized_content_type)?;

    let mut sizes = vec![original];

    for conversion in RESIZED_CONVERSIONS {
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

    let _ = std::fs::remove_file(&input_path);

    diesel::update(media::table.find(item.id))
        .set((
            media::sizes.eq(serde_json::to_value(&sizes)?),
            media::processed.eq(true),
        ))
        .execute(conn)?;

    if let Some(user_id) = item.user_id {
        update_media_storage_used(user_id, conn)?;
    }

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

    log::info!(
        "Media {}: stripped {} QuickTime-tagged resized size(s); marked unprocessed for regeneration.",
        item.id,
        removed.len()
    );
    Ok(true)
}
