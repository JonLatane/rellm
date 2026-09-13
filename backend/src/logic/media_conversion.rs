//! Generates `small`/`medium`/`large` resized copies of a `Media` item's original upload via the
//! system `ImageMagick` install (`magick`, or the legacy `convert`+`identify` pair) for images, or
//! `ffmpeg`/`ffprobe` for video, storing them in MinIO alongside the original and recording them
//! (each with its own `size_bytes`/`aspect_ratio`) in `Media.sizes`. Used by
//! `bin/convert_media_sizes.rs`.
//!
//! Only PNG/JPEG are converted for images (`CONVERTIBLE_CONTENT_TYPES`) and MP4/QuickTime/WebM for
//! video (`VIDEO_CONVERTIBLE_CONTENT_TYPES`) for now -- both tools handle other common formats
//! fine, but we don't have callers needing them yet.

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};
use diesel::*;
use s3::Bucket;

use crate::db_connection::PgPooledConnection;
use crate::logic::update_media_storage_used;
use crate::models::{Media, MediaConversionExt, MediaSize, RESIZED_CONVERSIONS};
use crate::schema::media;

pub const CONVERTIBLE_CONTENT_TYPES: [&str; 3] = ["image/png", "image/jpeg", "image/jpg"];
pub const VIDEO_CONVERTIBLE_CONTENT_TYPES: [&str; 3] =
    ["video/mp4", "video/quicktime", "video/webm"];

fn is_video_content_type(content_type: &str) -> bool {
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

/// Downloads `item`'s original from MinIO, generates any `RESIZED_CONVERSIONS` entry it's larger
/// than (skipping sizes it already fits within -- those fall back to the original), uploads the
/// results back to MinIO next to the original, records each new size's `size_bytes`/
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
        .get_object(&original.minio_path)
        .await
        .context("failed to download original from MinIO")?;
    std::fs::write(&input_path, original_bytes.as_slice())?;

    let (width, height) = converter.dimensions(&input_path)?;
    let aspect_ratio = width as f32 / height as f32;
    original.aspect_ratio = Some(aspect_ratio);

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

        let output_path = tmp_dir.join(format!("{}-{}.{}", item.id, conversion.key(), extension));
        converter.resize(
            &input_path,
            &output_path,
            conversion.max_dimension(),
            &sizes[0].content_type,
        )?;
        let output_bytes = std::fs::read(&output_path)?;
        let _ = std::fs::remove_file(&output_path);

        let converted_minio_path = format!("{}.{}", sizes[0].minio_path, conversion.key());
        bucket
            .put_object_with_content_type(&converted_minio_path, &output_bytes, &sizes[0].content_type)
            .await
            .context("failed to upload converted size to MinIO")?;

        log::info!(
            "Media {}: generated '{}' ({} bytes) at {}",
            item.id,
            conversion.key(),
            output_bytes.len(),
            converted_minio_path
        );
        sizes.push(MediaSize {
            conversion: conversion as i32,
            minio_path: converted_minio_path,
            content_type: sizes[0].content_type.clone(),
            size_bytes: output_bytes.len() as i64,
            aspect_ratio: Some(aspect_ratio),
        });
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
