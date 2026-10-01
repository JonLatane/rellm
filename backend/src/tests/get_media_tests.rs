//! Specs for `rpcs::media::get_media`: visibility rules (`query_visible_media!`), server-wide
//! browsing, `content_type` wildcards, and `search_text`.

use diesel::Connection;
use tonic::Status;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::get_media;
use crate::tests::factories::*;

fn ids(response: &GetMediaResponse) -> Vec<String> {
    response.media.iter().map(|m| m.id.clone()).collect()
}

fn opts(content_type: &'static str, visibility: Visibility) -> MediaOpts {
    MediaOpts { content_type, visibility, ..Default::default() }
}

#[test]
fn anonymous_sees_only_global_public_unless_licensed_media_is_globally_visible() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "gm_anon_owner");
        let global = create_media_with_opts(conn, Some(&owner), opts("video/mp4", Visibility::GlobalPublic));
        create_media_with_opts(conn, Some(&owner), opts("video/mp4", Visibility::Licensed));
        create_media_with_opts(conn, Some(&owner), opts("video/mp4", Visibility::ServerPublic));
        create_media_with_opts(conn, Some(&owner), opts("video/mp4", Visibility::Private));
        create_media_with_opts(conn, Some(&owner), opts("video/mp4", Visibility::Limited));

        let response = get_media(
            GetMediaRequest { user_id: Some(owner.id.to_proto_id()), ..Default::default() },
            &None,
            conn,
        )?;
        let got = ids(&response);
        // The test DB's server configuration leaves `licensed_media_visible_globally` off.
        assert_eq!(got, vec![global.id.to_proto_id()]);
        Ok(())
    });
}

#[test]
fn logged_in_viewer_sees_server_public_and_followed_limited_but_never_private() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "gm_li_owner");
        let viewer = create_user(conn, "gm_li_viewer");
        let stranger = create_user(conn, "gm_li_stranger");
        let server = create_media_with_opts(conn, Some(&owner), opts("audio/mpeg", Visibility::ServerPublic));
        let limited = create_media_with_opts(conn, Some(&owner), opts("audio/mpeg", Visibility::Limited));
        let licensed = create_media_with_opts(conn, Some(&owner), opts("audio/mpeg", Visibility::Licensed));
        let private = create_media_with_opts(conn, Some(&owner), opts("audio/mpeg", Visibility::Private));
        create_follow(conn, &viewer, &owner);

        let request = || GetMediaRequest { user_id: Some(owner.id.to_proto_id()), ..Default::default() };
        let as_follower = ids(&get_media(request(), &Some(&viewer), conn)?);
        assert!(as_follower.contains(&server.id.to_proto_id()));
        assert!(as_follower.contains(&limited.id.to_proto_id()));
        assert!(!as_follower.contains(&private.id.to_proto_id()));

        let as_stranger = ids(&get_media(request(), &Some(&stranger), conn)?);
        assert!(as_stranger.contains(&server.id.to_proto_id()));
        assert!(as_stranger.contains(&licensed.id.to_proto_id()), "logged-in users see LICENSED media");
        assert!(!as_stranger.contains(&limited.id.to_proto_id()));

        let as_owner = ids(&get_media(request(), &Some(&owner), conn)?);
        assert!(as_owner.contains(&private.id.to_proto_id()), "owner sees all their own media");
        Ok(())
    });
}

#[test]
fn by_id_lets_owner_fetch_their_private_media_but_hides_it_from_others() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "gm_id_owner");
        let other = create_user(conn, "gm_id_other");
        let private = create_media_with_opts(conn, Some(&owner), opts("image/png", Visibility::Private));
        let request = || GetMediaRequest { media_id: Some(private.id.to_proto_id()), ..Default::default() };
        assert_eq!(ids(&get_media(request(), &Some(&owner), conn)?).len(), 1);
        assert!(get_media(request(), &Some(&other), conn)?.media.is_empty());
        assert!(get_media(request(), &None, conn)?.media.is_empty());
        Ok(())
    });
}

#[test]
fn server_wide_browse_filters_by_content_type_wildcard_and_exact() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let a = create_user(conn, "gm_ct_a");
        let b = create_user(conn, "gm_ct_b");
        let mp4 = create_media_with_opts(conn, Some(&a), opts("video/mp4", Visibility::GlobalPublic));
        let webm = create_media_with_opts(conn, Some(&b), opts("video/webm", Visibility::GlobalPublic));
        let mp3 = create_media_with_opts(conn, Some(&a), opts("audio/mpeg", Visibility::GlobalPublic));
        let private_video = create_media_with_opts(conn, Some(&b), opts("video/mp4", Visibility::Private));
        let generated = create_media_with_opts(
            conn,
            Some(&b),
            MediaOpts { generated: true, ..opts("video/mp4", Visibility::GlobalPublic) },
        );

        let mut browse = |content_type: &str| -> Result<Vec<String>, Status> {
            Ok(ids(&get_media(
                GetMediaRequest { content_type: Some(content_type.to_string()), ..Default::default() },
                &None,
                conn,
            )?))
        };
        let videos = browse("video/*")?;
        assert!(videos.contains(&mp4.id.to_proto_id()) && videos.contains(&webm.id.to_proto_id()));
        assert!(!videos.contains(&mp3.id.to_proto_id()));
        assert!(!videos.contains(&private_video.id.to_proto_id()));
        assert!(!videos.contains(&generated.id.to_proto_id()), "generated media is not browsable");

        let audio = browse("audio/*")?;
        assert!(audio.contains(&mp3.id.to_proto_id()) && !audio.contains(&mp4.id.to_proto_id()));

        let exact = browse("video/webm")?;
        assert!(exact.contains(&webm.id.to_proto_id()) && !exact.contains(&mp4.id.to_proto_id()));
        Ok(())
    });
}

#[test]
fn invalid_content_type_is_rejected() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        for bad in ["video", "*/*x", "video/%", "/mp4"] {
            let result = get_media(
                GetMediaRequest { content_type: Some(bad.to_string()), ..Default::default() },
                &None,
                conn,
            );
            assert_eq!(result.unwrap_err().code(), tonic::Code::InvalidArgument, "{bad}");
        }
        Ok(())
    });
}

#[test]
fn search_text_matches_credits_and_ranks_name_above_description() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "gm_search_owner");
        let by_artist = create_media_with_opts(
            conn,
            Some(&owner),
            MediaOpts {
                name: Some("Track 1"),
                metadata: serde_json::json!({"artist": "Coltrane"}),
                ..opts("audio/mpeg", Visibility::GlobalPublic)
            },
        );
        let by_publisher = create_media_with_opts(
            conn,
            Some(&owner),
            MediaOpts {
                name: Some("Track 2"),
                metadata: serde_json::json!({"publisher": "Coltrane Records"}),
                ..opts("audio/mpeg", Visibility::GlobalPublic)
            },
        );
        create_media_with_opts(
            conn,
            Some(&owner),
            MediaOpts { name: Some("Unrelated"), ..opts("audio/mpeg", Visibility::GlobalPublic) },
        );

        let response = get_media(
            GetMediaRequest {
                search_text: Some("coltr".to_string()), // prefix match
                content_type: Some("audio/*".to_string()),
                ..Default::default()
            },
            &None,
            conn,
        )?;
        assert_eq!(
            ids(&response),
            vec![by_artist.id.to_proto_id(), by_publisher.id.to_proto_id()],
            "artist (weight A) outranks publisher (weight C)"
        );

        let blank = get_media(
            GetMediaRequest { search_text: Some("   ".to_string()), ..Default::default() },
            &None,
            conn,
        );
        assert!(blank.is_ok(), "blank search text is treated as no search");
        Ok(())
    });
}

#[test]
fn has_next_page_reflects_more_results() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "gm_paging_owner");
        for _ in 0..101 {
            create_media_with_opts(conn, Some(&owner), opts("video/mp4", Visibility::GlobalPublic));
        }
        let request = |page| GetMediaRequest {
            user_id: Some(owner.id.to_proto_id()),
            page,
            ..Default::default()
        };
        let first = get_media(request(0), &None, conn)?;
        assert_eq!((first.media.len(), first.has_next_page), (100, true));
        let second = get_media(request(1), &None, conn)?;
        assert_eq!((second.media.len(), second.has_next_page), (1, false));
        Ok(())
    });
}
