//! Specs for semantic search: the shared search documents (`*_search_document`, defined next to the
//! tsvector builders), the embedding tables' upkeep (`logic::embeddings::sync_embeddings`), the
//! `SearchSettings` toggle, and hybrid ranking in `GetPosts`.
//!
//! Everything outside `with_model` runs without the embedding model. The specs in `with_model`
//! download it (~120MB, once, into `RELLM_EMBEDDING_CACHE_DIR`) so they're `#[ignore]`d by default:
//! `cargo test --lib embeddings_tests -- --ignored`.

use diesel::sql_types::{BigInt, Nullable, Text};
use diesel::*;

use crate::db_connection::PgPooledConnection;
use crate::logic::embeddings::{self, EmbeddingKind, ModelUnavailable, SyncContext};
use crate::protos::*;
use crate::tests::factories::*;

#[derive(QueryableByName)]
struct Doc {
    #[diesel(sql_type = Nullable<Text>)]
    doc: Option<String>,
}

fn document(conn: &mut PgPooledConnection, function: &str, id: i64) -> String {
    sql_query(format!("SELECT {}($1) AS doc", function))
        .bind::<BigInt, _>(id)
        .get_result::<Doc>(conn)
        .unwrap()
        .doc
        .unwrap_or_default()
}

fn title_post(conn: &mut PgPooledConnection, author: &crate::models::User, title: &str) -> crate::models::Post {
    create_post(
        conn,
        Some(author),
        PostOpts { title: Some(title.to_string()), ..Default::default() },
    )
}

#[test]
fn a_post_document_holds_the_same_fields_full_text_search_indexes() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        let author = create_user_with_profile(conn, "pizzafan", "Pia Zanotti", "");
        let post = create_post(
            conn,
            Some(&author),
            PostOpts {
                title: Some("Best dough".to_string()),
                content: Some("Slow fermentation".to_string()),
                ..Default::default()
            },
        );
        let doc = document(conn, "post_search_document", post.id);
        for word in ["Best dough", "pizzafan", "Slow fermentation", "Pia Zanotti"] {
            assert!(doc.contains(word), "{:?} missing from {:?}", word, doc);
        }
        // Most important text first: title before content.
        assert!(doc.find("Best dough").unwrap() < doc.find("Slow fermentation").unwrap());
        // ...and every word of the document is a lexeme of posts.search_text (same source).
        let matches: i64 = posts::table
            .filter(posts::id.eq(post.id))
            .filter(diesel::dsl::sql::<diesel::sql_types::Bool>(
                "search_text @@ to_tsquery('simple', 'dough & fermentation & zanotti & pizzafan')",
            ))
            .count()
            .get_result(conn)?;
        assert_eq!(matches, 1);
        Ok(())
    });
}

#[test]
fn a_user_profile_document_is_username_name_and_bio() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        let user = create_user_with_profile(conn, "gardener", "Greta Green", "I grow tomatoes");
        let doc = document(conn, "user_search_document", user.id);
        assert_eq!(doc, "gardener\nGreta Green\nI grow tomatoes");
        Ok(())
    });
}

#[test]
fn an_event_document_adds_occasion_places_and_dates_but_not_a_hidden_location() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        let organizer = create_user(conn, "organizer");
        let location = serde_json::json!({"uniformly_formatted_address": "1 Infinite Loop, Cupertino"});
        let make = |conn: &mut PgPooledConnection, title: &str, info: serde_json::Value| {
            let (event, post) = create_event(
                conn,
                &organizer,
                EventOpts {
                    title: Some(title.to_string()),
                    info,
                    default_occasion: None,
                    ..Default::default()
                },
            );
            create_occasion(
                conn,
                &event,
                Some(&organizer),
                OccasionOpts { location: Some(location.clone()), ..Default::default() },
            );
            post.id
        };
        let open = make(conn, "Open house", serde_json::json!({}));
        let secret = make(conn, "Secret supper", serde_json::json!({"hide_location_until_rsvp_approved": true}));

        let open_doc = document(conn, "event_search_document", open);
        assert!(open_doc.contains("Open house"));
        assert!(open_doc.contains("1 Infinite Loop, Cupertino"));
        assert!(open_doc.contains("20"), "has a date: {:?}", open_doc);

        let secret_doc = document(conn, "event_search_document", secret);
        assert!(secret_doc.contains("Secret supper"));
        assert!(!secret_doc.contains("Infinite Loop"), "location leaked: {:?}", secret_doc);
        Ok(())
    });
}

#[test]
fn an_event_document_leaves_out_occasions_the_event_s_viewers_could_not_see() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        let organizer = create_user(conn, "occasion_privacy");
        let (event, post) = create_event(
            conn,
            &organizer,
            EventOpts { title: Some("Garden party".to_string()), default_occasion: None, ..Default::default() },
        );
        let occasion = |conn: &mut PgPooledConnection, title: &str, address: &str, visibility, moderation| {
            create_occasion(
                conn,
                &event,
                Some(&organizer),
                OccasionOpts {
                    title: Some(title.to_string()),
                    visibility,
                    moderation,
                    location: Some(serde_json::json!({"uniformly_formatted_address": address})),
                    ..Default::default()
                },
            );
        };
        occasion(conn, "Public toast", "10 Open Road", Visibility::ServerPublic, Moderation::Unmoderated);
        occasion(conn, "Secret meeting", "99 Hidden Lane", Visibility::Private, Moderation::Unmoderated);
        occasion(conn, "Awaiting review", "5 Pending Place", Visibility::ServerPublic, Moderation::Pending);

        let doc = document(conn, "event_search_document", post.id);
        assert!(doc.contains("Public toast") && doc.contains("10 Open Road"), "{:?}", doc);
        for leaked in ["Secret meeting", "99 Hidden Lane", "Awaiting review", "5 Pending Place"] {
            assert!(!doc.contains(leaked), "{:?} leaked into {:?}", leaked, doc);
        }
        Ok(())
    });
}

#[test]
fn a_document_with_nothing_to_embed_gets_one_null_embedding_row_and_is_not_retried() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        // No author, title or content: an empty document, so the model is never needed.
        let blank = create_post(conn, None, PostOpts { title: None, content: None, ..Default::default() });
        let mut ctx = SyncContext::unrestricted();
        let stats = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        assert_eq!(stats.empty, 1);
        assert!(ctx.embedder.is_none(), "the model must not load for empty documents");

        let stored: (Option<Vec<u8>>, i64) = post_embeddings::table
            .filter(post_embeddings::post_id.eq(blank.id))
            .select((post_embeddings::embedding, post_embeddings::document_hash))
            .first(conn)?;
        assert_eq!(stored.0, None);

        // Second pass: it's no longer "missing", and the sweep finds it unchanged.
        let again = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        assert_eq!((again.embedded, again.empty, again.unchanged), (0, 0, 1));
        Ok(())
    });
}

#[test]
fn a_denied_cluster_lock_stops_the_run_before_the_model_loads_and_embeds_nothing() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "locked_out");
        let post = title_post(conn, &author, "Needs embedding");
        let mut asked = 0;
        let mut ctx = SyncContext::unrestricted();
        ctx.before_model_load = Box::new(|| {
            asked += 1;
            false
        });
        let err = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx).unwrap_err();
        assert!(err.downcast_ref::<ModelUnavailable>().is_some(), "{:?}", err);
        assert!(ctx.embedder.is_none());
        drop(ctx);
        assert_eq!(asked, 1);
        let stored: i64 = post_embeddings::table
            .filter(post_embeddings::post_id.eq(post.id))
            .count()
            .get_result(conn)?;
        assert_eq!(stored, 0, "nothing may be recorded as embedded");
        Ok(())
    });
}

#[test]
fn an_expired_time_budget_ends_the_run_with_work_left_for_next_time() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "slowpoke");
        let post = title_post(conn, &author, "Waits for its turn");
        let mut ctx = SyncContext::unrestricted();
        ctx.deadline = std::time::Instant::now();
        let stats = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        assert!(stats.out_of_time);
        assert_eq!(stats.embedded, 0);
        assert!(ctx.embedder.is_none(), "an out-of-budget run must not load the model");
        let stored: i64 = post_embeddings::table
            .filter(post_embeddings::post_id.eq(post.id))
            .count()
            .get_result(conn)?;
        assert_eq!(stored, 0);
        Ok(())
    });
}

#[test]
fn semantic_search_is_on_by_default_and_the_setting_turns_it_off() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        assert!(embeddings::semantic_search_enabled(conn)); // nothing saved: default on
        // The default configuration reads as enabled through the proto too.
        let config = crate::rpcs::get_server_configuration_proto(conn).unwrap();
        assert_eq!(config.search_settings, Some(SearchSettings { semantic_search_enabled: true, embedding_model: embeddings::MODEL_DESCRIPTION.to_string() }));

        update(server_configurations::table.filter(server_configurations::active.eq(true)))
            .set(server_configurations::search_settings
                .eq(serde_json::to_value(SearchSettings { semantic_search_enabled: false, embedding_model: String::new() }).unwrap()))
            .execute(conn)?;
        assert!(!embeddings::semantic_search_enabled(conn));
        let config = crate::rpcs::get_server_configuration_proto(conn).unwrap();
        assert_eq!(config.search_settings, Some(SearchSettings { semantic_search_enabled: false, embedding_model: embeddings::MODEL_DESCRIPTION.to_string() }));
        // Disabled: no semantic ranking is attempted at all.
        assert_eq!(embeddings::semantic_ranking(conn, EmbeddingKind::Post, "anything", &[1, 2]), None);
        Ok(())
    });
}

use crate::schema::{post_embeddings, posts, server_configurations};

mod with_model {
    use super::*;
    use crate::rpcs::get_posts;

    fn wait_for_server_model() {
        let started = std::time::Instant::now();
        while embeddings::server_embedder().is_none() {
            assert!(started.elapsed().as_secs() < 900, "embedding model never became ready");
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }

    #[test]
    #[ignore = "downloads the embedding model"]
    fn sync_embeds_posts_and_re_embeds_only_what_changed() {
        let mut conn = test_conn();
        conn.test_transaction::<_, anyhow::Error, _>(|conn| {
            let author = create_user(conn, "alice");
            let post = title_post(conn, &author, "Adopting a puppy from the shelter");
            let mut ctx = SyncContext::unrestricted();
            let first = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
            assert!(first.embedded >= 1);

            let hash_of = |conn: &mut PgPooledConnection| -> (i64, usize) {
                post_embeddings::table
                    .filter(post_embeddings::post_id.eq(post.id))
                    .select((post_embeddings::document_hash, diesel::dsl::sql::<diesel::sql_types::Integer>("octet_length(embedding)")))
                    .first::<(i64, i32)>(conn)
                    .map(|(h, n)| (h, n as usize))
                    .unwrap()
            };
            let (hash, bytes) = hash_of(conn);
            assert_eq!(bytes, 384 * 4);

            // Nothing changed: nothing re-embedded.
            let second = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
            assert_eq!(second.embedded, 0);

            // Editing the post and renaming its author both change the document -> re-embedded.
            update(posts::table.filter(posts::id.eq(post.id)))
                .set(posts::title.eq("Adopting a kitten"))
                .execute(conn)?;
            let third = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
            assert_eq!(third.embedded, 1);
            assert_ne!(hash_of(conn).0, hash);
            Ok(())
        });
    }

    #[test]
    #[ignore = "downloads the embedding model"]
    fn related_text_ranks_above_unrelated_text_and_search_finds_posts_sharing_no_words() {
        wait_for_server_model();
        let mut conn = test_conn();
        conn.test_transaction::<_, anyhow::Error, _>(|conn| {
            let author = create_user(conn, "bob");
            let dog = title_post(conn, &author, "Adopting a puppy from the shelter");
            let tax = title_post(conn, &author, "Quarterly corporate tax filing deadlines");
            let mut ctx = SyncContext::unrestricted();
            embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;

            let ranking = embeddings::semantic_ranking(
                conn,
                EmbeddingKind::Post,
                "getting a new dog",
                &[dog.id, tax.id],
            )
            .expect("semantic search should be ready");
            eprintln!("similarities: {:?}", ranking);
            assert_eq!(ranking.first().map(|r| r.0), Some(dog.id));
            assert!(!ranking.iter().any(|r| r.0 == tax.id), "unrelated text must fall under the threshold");

            // "getting a new dog" shares no word with "Adopting a puppy..." -- full-text finds
            // nothing, but GetPosts' hybrid search does.
            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::TextSearch as i32,
                    search_text: Some("getting a new dog".to_string()),
                    ..Default::default()
                },
                &Some(&author),
                conn,
            )
            .map_err(|s| anyhow::anyhow!("{:?}", s))?;
            let found: Vec<String> = response.posts.iter().map(|p| p.id.clone()).collect();
            assert!(found.contains(&crate::marshaling::ToProtoId::to_proto_id(&dog.id).to_string()), "{:?}", found);
            Ok(())
        });
    }

    #[test]
    #[ignore = "downloads the embedding model"]
    fn a_profile_found_only_by_meaning_is_returned_by_the_all_users_search() {
        wait_for_server_model();
        let mut conn = test_conn();
        conn.test_transaction::<_, anyhow::Error, _>(|conn| {
            let trainer = create_user_with_profile(conn, "pawsitive", "Sam Rivers", "I train puppies and rescue dogs");
            let baker = create_user_with_profile(conn, "doughboy", "Dee Baker", "Sourdough bread and pastries");
            let mut ctx = SyncContext::unrestricted();
            embeddings::sync_embeddings(conn, EmbeddingKind::UserProfile, &mut ctx)?;

            let response = crate::rpcs::get_users(
                GetUsersRequest {
                    listing_type: UserListingType::UsersTextSearch as i32,
                    search_text: Some("canine behaviorist".to_string()),
                    ..Default::default()
                },
                &None,
                conn,
            )
            .map_err(|s| anyhow::anyhow!("{:?}", s))?;
            let names: Vec<String> = response.users.iter().map(|u| u.username.clone()).collect();
            assert!(names.contains(&trainer.username), "{:?}", names);
            assert!(!names.contains(&baker.username), "{:?}", names);
            Ok(())
        });
    }
}
