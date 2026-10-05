//! Specs for `backfill_audio_metadata` (`bin/reconvert_audio_media`'s `--stored-metadata-only` /
//! `--calculated-metadata-only`), end to end against real `ffmpeg`, the test database and the test
//! object storage bucket. Skipped where `ffmpeg` isn't installed.

use diesel::prelude::*;
use std::process::Command;

use crate::logic::{backfill_audio_metadata, FFmpeg, MetadataBackfill};
use crate::models::Media;
use crate::tests::factories::*;

/// End to end against real `ffmpeg` and the test object storage bucket/database: seeds only unset
/// fields, and only the steps asked for.
#[test]
fn backfill_audio_metadata_seeds_only_what_was_asked_and_never_overwrites() {
    let Some(ffmpeg) = FFmpeg::detect() else { return };
    let tb = test_bucket();
    let mut conn = test_conn();
    let dir = std::env::temp_dir().join(format!("backfill-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).unwrap();
    // 40s of 120 BPM beeps tagged with an artist, a composer and a key.
    let path = dir.join("tagged.mp3");
    let status = Command::new("ffmpeg")
        .args(["-y", "-nostdin", "-v", "error", "-f", "lavfi", "-i"])
        .arg("aevalsrc='sin(2*PI*440*t)*lt(mod(t,0.5),0.05)':s=44100:d=40")
        .args(["-metadata", "artist=Tagged Artist", "-metadata", "composer=Tagged Composer", "-metadata", "TKEY=Am"])
        .arg(&path)
        .status()
        .unwrap();
    assert!(status.success());
    let bytes = std::fs::read(&path).unwrap();

    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let new_item = |conn: &mut _| {
            let item = create_media_with_opts(
                conn,
                None,
                MediaOpts {
                    content_type: "audio/mpeg",
                    metadata: serde_json::json!({"composer": "Owner Edit"}),
                    ..Default::default()
                },
            );
            let original_path = item.original().unwrap().object_storage_path;
            tb.block_on(tb.bucket.put_object_with_content_type(&original_path, &bytes, "audio/mpeg")).unwrap();
            item
        };
        let metadata_of = |conn: &mut _, item: &Media| crate::models::get_media(item.id, conn).unwrap().metadata();
        let run = |conn: &mut _, item: &Media, stored, calculated| {
            tb.block_on(backfill_audio_metadata(item, MetadataBackfill { stored, calculated }, &ffmpeg, tb.bucket, &dir, conn))
                .unwrap()
        };

        // Calculated only: tempos estimated, but no credits are read from the tags.
        let item = new_item(conn);
        assert!(run(conn, &item, false, true));
        let m = metadata_of(conn, &item);
        assert!((m.start_bpm.unwrap() - 120.0).abs() < 1.5, "{m:?}");
        assert!(m.min_bpm.is_some() && m.max_bpm.is_some());
        assert_eq!((m.artist.clone(), m.composer.clone()), (None, Some("Owner Edit".to_string())));

        // ...and a later stored pass fills the credits (not the owner's composer) without redoing the estimates.
        let tempo = m.start_bpm;
        assert!(run(conn, &item, true, false));
        let m = metadata_of(conn, &item);
        assert_eq!(m.artist.as_deref(), Some("Tagged Artist"));
        assert_eq!(m.composer.as_deref(), Some("Owner Edit"), "owner edit survives");
        assert_eq!(m.start_bpm, tempo);
        // Everything's set or owner-held now (the tag key may or may not have beaten the estimate).
        assert!(!run(conn, &item, true, true));

        // Stored only: credits and the key tag, but no estimated tempos.
        let item = new_item(conn);
        assert!(run(conn, &item, true, false));
        let m = metadata_of(conn, &item);
        assert_eq!(m.artist.as_deref(), Some("Tagged Artist"));
        assert_eq!((m.start_key.as_deref(), m.end_key.as_deref()), (Some("Am"), Some("Am")));
        assert_eq!((m.start_bpm, m.end_bpm, m.min_bpm, m.max_bpm), (None, None, None, None));
        Ok(())
    });
    let _ = std::fs::remove_dir_all(&dir);
}
