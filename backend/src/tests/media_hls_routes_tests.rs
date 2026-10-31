//! `web::media_hls`'s routes: that they coexist with `/media/{id}` (no collisions, the playlist and segment routes
//! don't capture each other's URLs), and reject a bad segment name / media id before touching the database or
//! object storage -- the access-checked behavior itself needs the full server and is covered by
//! `logic::media::hls`'s tests plus manual runs.

use std::sync::Arc;

use diesel::r2d2::{ConnectionManager, Pool};
use diesel::PgConnection;
use rocket::{http::Status, local::blocking::Client};
use s3::{creds::Credentials, Bucket, Region};

use crate::web::{RocketState, MEDIA_ENDPOINTS, MEDIA_HLS_ENDPOINTS};

/// A server whose database and bucket nothing can reach: requests that get that far would fail.
fn client() -> Client {
    let pool = Pool::builder()
        .min_idle(Some(0))
        .build_unchecked(ConnectionManager::<PgConnection>::new("postgres://unreachable.invalid/none"));
    let bucket = Bucket::new(
        "unreachable",
        Region::Custom { region: "none".into(), endpoint: "http://unreachable.invalid".into() },
        Credentials::new(Some("a"), Some("b"), None, None, None).unwrap(),
    )
    .unwrap()
    .with_path_style();
    let mut routes = (*MEDIA_ENDPOINTS).clone();
    routes.append(&mut (*MEDIA_HLS_ENDPOINTS).clone());
    Client::tracked(
        rocket::build()
            .manage(RocketState {
                pool: Arc::new(pool),
                bucket: Arc::new(*bucket),
                tempdir: Arc::new(tempfile::tempdir().unwrap()),
            })
            .mount("/", routes),
    )
    .expect("the routes don't collide")
}

#[test]
fn each_url_shape_reaches_its_own_route() {
    let client = client();
    // "!!" isn't a media id, so a request that reaches `authorize_media_view` is a 400 before any database access.
    for path in ["master.m3u8", "small/playlist.m3u8", "small/0.ts"] {
        assert_eq!(client.get(format!("/media/hls/!!/{path}")).dispatch().status(), Status::BadRequest, "{path}");
    }
}

#[test]
fn rejects_segment_names_that_arent_numbered_ts_files() {
    let client = client();
    for name in ["other.txt", "..%2Fplaylist.m3u8", "a.ts", "0.TS"] {
        let status = client.get(format!("/media/hls/!!/small/{name}")).dispatch().status();
        assert_eq!(status, Status::NotFound, "{name}");
    }
}

#[test]
fn answers_cors_preflights() {
    let client = client();
    for path in ["master.m3u8", "small/playlist.m3u8", "small/0.ts"] {
        let response = client.options(format!("/media/hls/!!/{path}")).dispatch();
        assert_eq!(response.status(), Status::Ok, "{path}");
    }
}
