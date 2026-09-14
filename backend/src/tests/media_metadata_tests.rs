//! Specs for `MediaMetadata::effective_video_preview_time_ms` -- pure logic, no DB/MinIO needed
//! (unlike most `tests/` specs, which exercise an RPC end-to-end).

use crate::models::MediaMetadata;

#[test]
fn explicit_value_is_used_regardless_of_duration() {
    let metadata = MediaMetadata { video_preview_time_ms: Some(4200) };
    assert_eq!(metadata.effective_video_preview_time_ms(60_000), 4200);
    assert_eq!(metadata.effective_video_preview_time_ms(500), 4200);
}

#[test]
fn unset_defaults_to_1s_for_videos_at_least_1500ms() {
    let metadata = MediaMetadata::default();
    assert_eq!(metadata.effective_video_preview_time_ms(1500), 1000);
    assert_eq!(metadata.effective_video_preview_time_ms(60_000), 1000);
}

#[test]
fn unset_defaults_to_the_midpoint_for_videos_shorter_than_1500ms() {
    let metadata = MediaMetadata::default();
    assert_eq!(metadata.effective_video_preview_time_ms(1000), 500);
    assert_eq!(metadata.effective_video_preview_time_ms(0), 0);
}
