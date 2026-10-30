//! HLS (HTTP Live Streaming) for video `Media`, served at `/media/hls/{id}/...` (see `web::media_hls`).
//!
//! Rellm doesn't store HLS: every video already has H.264/AAC MP4 renditions (`small`/`medium`/`large`,
//! see `media_conversion`), and an HLS stream is just those same frames cut into keyframe-aligned
//! `.ts` segments. So the first request for a rendition runs one `ffmpeg -c copy` pass (stream copy --
//! no re-encode, bounded by disk speed) into a local cache directory, and every later request is a
//! static file. Segments are small, whole `200` responses, which CDNs cache far better than the
//! `Range` requests a progressive MP4 needs.
//!
//! This module is the pure/`ffmpeg` part: probing, segmenting, and building playlists.

use std::path::Path;
use std::process::Command;

use anyhow::{bail, Context, Result};

use crate::protos::MediaConversion;

/// Target length of an HLS segment, in seconds. `ffmpeg` can only cut at keyframes, so a segment is
/// the first keyframe-to-keyframe stretch of at least this long.
pub const HLS_SEGMENT_SECONDS: u32 = 6;

/// The HLS variant names a client may request, and the stored rendition each one streams -- in
/// ascending quality. `preview` (the cropped `UNLICENSED_PREVIEW_MEDIUM`) is the only variant a viewer
/// without full access to `LICENSED` media may stream.
pub const HLS_VARIANTS: [(&str, MediaConversion); 4] = [
    ("small", MediaConversion::Small),
    ("medium", MediaConversion::Medium),
    ("large", MediaConversion::Large),
    ("preview", MediaConversion::UnlicensedPreviewMedium),
];

/// The `MediaConversion` `variant` streams, if it's one of `HLS_VARIANTS`.
pub fn variant_conversion(variant: &str) -> Option<MediaConversion> {
    HLS_VARIANTS.iter().find(|(name, _)| *name == variant).map(|(_, conversion)| *conversion)
}

/// Whether `segment` is the name of a segment `segment_video` writes (`<n>.ts`), so a request can
/// never name any other file in the cache directory.
pub fn is_segment_name(segment: &str) -> bool {
    segment
        .strip_suffix(".ts")
        .is_some_and(|n| !n.is_empty() && n.len() <= 9 && n.bytes().all(|b| b.is_ascii_digit()))
}

/// The version of the rendition stored at `object_storage_path`: the `.<unix ms>` suffix every generated
/// copy's path gets (see `media_conversion::versioned_object_path`), or `0` for an unversioned one. It's in
/// every playlist and segment URL (`?v=`), so a player holding a playlist from before the rendition was
/// regenerated gets a `404` for its segments rather than the new rendition's, which are cut differently.
pub fn version_of(object_storage_path: &str) -> String {
    match object_storage_path.rsplit_once('.') {
        Some((_, tail)) if super::is_version_suffix(tail) => tail.to_owned(),
        _ => "0".to_owned(),
    }
}

/// What `ffprobe` says about a rendition's first video stream -- enough for a master playlist entry.
#[derive(Debug, Clone, PartialEq)]
pub struct StreamInfo {
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub duration_seconds: f64,
    /// Whole-file average, in bits per second.
    pub bit_rate: u64,
}

impl StreamInfo {
    /// Whether `ffmpeg -c copy` can put this stream in MPEG-TS for every browser's HLS player.
    pub fn is_streamable(&self) -> bool {
        self.codec == "h264" && self.width > 0 && self.height > 0
    }
}

/// Parses `ffprobe -show_entries stream=codec_name,width,height:format=duration,bit_rate -of json`.
pub fn parse_stream_info(json: &str) -> Result<StreamInfo> {
    let value: serde_json::Value = serde_json::from_str(json).context("invalid ffprobe JSON")?;
    let stream = value["streams"].get(0).context("no video stream")?;
    // ffprobe prints numbers inside `format` as strings.
    let format_number = |key: &str| value["format"][key].as_str().and_then(|s| s.parse::<f64>().ok());
    Ok(StreamInfo {
        codec: stream["codec_name"].as_str().unwrap_or_default().to_owned(),
        width: stream["width"].as_u64().unwrap_or(0) as u32,
        height: stream["height"].as_u64().unwrap_or(0) as u32,
        duration_seconds: format_number("duration").unwrap_or(0.0),
        bit_rate: format_number("bit_rate").unwrap_or(0.0) as u64,
    })
}

/// A stand-in for `probe` of a rendition that hasn't been downloaded: its size on screen follows from the
/// `aspect_ratio` recorded when it was converted and the `max_dimension` that conversion fits within, and
/// its bit rate from its stored `size_bytes` over the video's `duration_seconds` (the same for every
/// full-length rendition). Renditions are never upscaled, so for a small source the resolution is an
/// upper bound -- all a master playlist's `RESOLUTION` has to be. Our converter always makes H.264.
pub fn estimate_stream_info(aspect_ratio: f32, max_dimension: u32, size_bytes: i64, duration_seconds: f64) -> StreamInfo {
    let even = |pixels: f32| ((pixels / 2.0).round() as u32).max(1) * 2;
    let max = max_dimension as f32;
    let (width, height) = if aspect_ratio >= 1.0 { (max, max / aspect_ratio) } else { (max * aspect_ratio, max) };
    StreamInfo {
        codec: "h264".to_owned(),
        width: even(width),
        height: even(height),
        duration_seconds,
        bit_rate: if duration_seconds > 0.0 { (size_bytes.max(0) as f64 * 8.0 / duration_seconds) as u64 } else { 0 },
    }
}

/// Runs `ffprobe` on `input`.
pub fn probe(input: &Path) -> Result<StreamInfo> {
    let output = Command::new("ffprobe")
        .args(["-v", "error", "-select_streams", "v:0"])
        .args(["-show_entries", "stream=codec_name,width,height:format=duration,bit_rate"])
        .args(["-of", "json"])
        .arg(input)
        .output()
        .context("failed to run ffprobe")?;
    if !output.status.success() {
        bail!("ffprobe exited with {}", output.status);
    }
    parse_stream_info(&String::from_utf8_lossy(&output.stdout))
}

/// Cuts `input` (a rendition `probe` found streamable) into `<n>.ts` segments plus a VOD
/// `playlist.m3u8` in `out_dir`, copying the streams as they are.
pub fn segment_video(input: &Path, out_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(out_dir).context("failed to create the HLS directory")?;
    let status = Command::new("ffmpeg")
        .args(["-y", "-nostdin", "-v", "error", "-i"])
        .arg(input)
        .args(["-c", "copy", "-f", "hls"])
        .args(["-hls_time", &HLS_SEGMENT_SECONDS.to_string()])
        .args(["-hls_playlist_type", "vod", "-hls_flags", "independent_segments"])
        .arg("-hls_segment_filename")
        .arg(out_dir.join("%d.ts"))
        .arg(out_dir.join("playlist.m3u8"))
        .status()
        .context("failed to run ffmpeg")?;
    if !status.success() {
        bail!("ffmpeg exited with {}", status);
    }
    Ok(())
}

/// The master playlist for `variants` (name, probe result and the query string to put on its URI -- see
/// `version_of` -- in ascending quality). Each entry's URI is relative: `<name>/playlist.m3u8<query>`.
pub fn master_playlist(variants: &[(&str, StreamInfo, String)]) -> String {
    let mut playlist = String::from("#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-INDEPENDENT-SEGMENTS\n");
    for (name, info, query) in variants {
        // Playlists carry no codec string (that would mean also probing the audio stream): players
        // take it from the stream itself, which is all hls.js/Safari need.
        playlist.push_str(&format!(
            "#EXT-X-STREAM-INF:BANDWIDTH={},RESOLUTION={}x{}\n{}/playlist.m3u8{}\n",
            info.bit_rate.max(1),
            info.width,
            info.height,
            name,
            query
        ));
    }
    playlist
}

/// `playlist` (ffmpeg's media playlist) with `uri_suffix` (the query string: the rendition's version, and the
/// viewer's `?authorization=` if they used one) appended to each segment URI.
pub fn with_uri_suffix(playlist: &str, uri_suffix: &str) -> String {
    if uri_suffix.is_empty() {
        return playlist.to_owned();
    }
    let mut out = String::with_capacity(playlist.len() + 64);
    for line in playlist.lines() {
        out.push_str(line);
        if !line.is_empty() && !line.starts_with('#') {
            out.push_str(uri_suffix);
        }
        out.push('\n');
    }
    out
}

/// Whether the cache directory `dir_name` holds an earlier version of the rendition whose object path
/// ends in `base_name` (without its version) -- see `media_conversion::object_path_version_base`.
/// Directories are named `<object path file name>.hls`.
pub fn is_superseded_hls_dir(dir_name: &str, base_name: &str) -> bool {
    let Some(rest) = dir_name.strip_prefix(base_name).and_then(|r| r.strip_suffix(".hls")) else {
        return false;
    };
    rest.is_empty() || rest.strip_prefix('.').is_some_and(super::is_version_suffix)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn info(width: u32, height: u32, bit_rate: u64) -> StreamInfo {
        StreamInfo { codec: "h264".into(), width, height, duration_seconds: 20.0, bit_rate }
    }

    #[test]
    fn parses_ffprobe_output() {
        let json = r#"{"programs":[],"streams":[{"codec_name":"h264","width":320,"height":240}],"format":{"duration":"20.000000","bit_rate":"412345"}}"#;
        let parsed = parse_stream_info(json).unwrap();
        assert_eq!(parsed, StreamInfo { codec: "h264".into(), width: 320, height: 240, duration_seconds: 20.0, bit_rate: 412345 });
        assert!(parsed.is_streamable());
        // No video stream at all (audio-only): not parseable, so not streamable.
        assert!(parse_stream_info(r#"{"streams":[],"format":{}}"#).is_err());
    }

    #[test]
    fn only_h264_is_streamable() {
        let mut vp9 = info(320, 240, 1);
        vp9.codec = "vp9".into();
        assert!(!vp9.is_streamable());
        assert!(!info(0, 0, 1).is_streamable());
    }

    #[test]
    fn master_playlist_lists_each_variant_with_relative_uris() {
        let playlist = master_playlist(&[
            ("small", info(320, 180, 300_000), "?v=1790000000000".to_owned()),
            ("medium", info(800, 450, 0), "?v=1790000000001&authorization=t".to_owned()),
        ]);
        assert_eq!(
            playlist,
            "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-INDEPENDENT-SEGMENTS\n\
             #EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=320x180\nsmall/playlist.m3u8?v=1790000000000\n\
             #EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=800x450\nmedium/playlist.m3u8?v=1790000000001&authorization=t\n"
        );
    }

    #[test]
    fn suffix_goes_on_segment_uris_only() {
        let playlist = "#EXTM3U\n#EXTINF:4.8,\n0.ts\n#EXTINF:2.4,\n1.ts\n#EXT-X-ENDLIST\n";
        assert_eq!(with_uri_suffix(playlist, ""), playlist);
        assert_eq!(
            with_uri_suffix(playlist, "?authorization=a%2Fb"),
            "#EXTM3U\n#EXTINF:4.8,\n0.ts?authorization=a%2Fb\n#EXTINF:2.4,\n1.ts?authorization=a%2Fb\n#EXT-X-ENDLIST\n"
        );
    }

    #[test]
    fn a_rendition_version_is_its_object_paths_timestamp_suffix() {
        assert_eq!(version_of("user/1@h-a/uuid-clip.mp4.medium.1790000000123"), "1790000000123");
        assert_eq!(version_of("user/1@h-a/uuid-clip.mp4.medium"), "0");
        assert_eq!(version_of("user/1@h-a/uuid-clip.mp4"), "0");
        assert_eq!(version_of("no-dots"), "0");
    }

    #[test]
    fn estimates_a_rendition_without_downloading_it() {
        // 16:9 fits the width, 9:16 the height; never odd (H.264 needs even dimensions).
        let landscape = estimate_stream_info(16.0 / 9.0, 800, 3_000_000, 24.0);
        assert_eq!((landscape.width, landscape.height), (800, 450));
        assert_eq!(landscape.bit_rate, 1_000_000);
        assert!(landscape.is_streamable());
        let portrait = estimate_stream_info(9.0 / 16.0, 320, 1_000_000, 0.0);
        assert_eq!((portrait.width, portrait.height), (180, 320));
        assert_eq!(portrait.bit_rate, 0);
        let odd = estimate_stream_info(0.7, 801, 1, 1.0);
        assert!(odd.width % 2 == 0 && odd.height % 2 == 0);
    }

    #[test]
    fn only_numbered_ts_files_are_segments() {
        assert!(is_segment_name("0.ts") && is_segment_name("123.ts"));
        for bad in ["playlist.m3u8", ".ts", "a.ts", "../0.ts", "0.ts/x", "0.TS", "1234567890.ts", "-1.ts"] {
            assert!(!is_segment_name(bad), "{bad}");
        }
    }

    #[test]
    fn variants_map_to_conversions() {
        assert_eq!(variant_conversion("medium"), Some(MediaConversion::Medium));
        assert_eq!(variant_conversion("preview"), Some(MediaConversion::UnlicensedPreviewMedium));
        assert_eq!(variant_conversion("original"), None);
    }

    #[test]
    fn only_other_versions_of_the_same_rendition_dir_are_superseded() {
        let base = "uuid-clip.mp4.medium";
        assert!(is_superseded_hls_dir("uuid-clip.mp4.medium.1790000000000.hls", base));
        assert!(is_superseded_hls_dir("uuid-clip.mp4.medium.hls", base));
        assert!(!is_superseded_hls_dir("uuid-clip.mp4.large.1790000000000.hls", base));
        assert!(!is_superseded_hls_dir("uuid-clip.mp4.medium.1790000000000.mediafile", base));
        assert!(!is_superseded_hls_dir("other-uuid-clip.mp4.medium.1790000000000.hls", base));
    }

    #[test]
    fn segments_a_real_clip_into_a_decodable_stream() {
        if Command::new("ffmpeg").arg("-version").output().is_err() {
            return; // ffmpeg is optional, like everywhere else
        }
        let dir = tempfile::tempdir().unwrap();
        let input = dir.path().join("in.mp4");
        let made = Command::new("ffmpeg")
            .args(["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=duration=14:size=160x120:rate=25"])
            .args(["-c:v", "libx264", "-preset", "ultrafast", "-g", "50", "-movflags", "+faststart"])
            .arg(&input)
            .status();
        if !made.is_ok_and(|s| s.success()) {
            return; // no libx264 in this ffmpeg
        }

        let probed = probe(&input).unwrap();
        assert!(probed.is_streamable());
        assert_eq!((probed.width, probed.height), (160, 120));

        let out = dir.path().join("hls");
        segment_video(&input, &out).unwrap();
        let playlist = std::fs::read_to_string(out.join("playlist.m3u8")).unwrap();
        assert!(playlist.contains("#EXT-X-ENDLIST") && playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD"));
        let segments: Vec<&str> = playlist.lines().filter(|l| !l.starts_with('#') && !l.is_empty()).collect();
        assert!(segments.len() >= 2, "{playlist}");
        assert!(segments.iter().all(|s| is_segment_name(s) && out.join(s).exists()));
    }
}
