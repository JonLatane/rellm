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
use crate::logic::embeddings::{self, EmbeddingKind, ModelUnavailable, SyncContext, TextEmbedder};
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
        let hidden_place = make(conn, "Hidden-place supper", serde_json::json!({"hide_location_until_rsvp_approved": true}));

        let open_doc = document(conn, "event_search_document", open);
        assert!(open_doc.contains("Open house"));
        assert!(open_doc.contains("1 Infinite Loop, Cupertino"));
        assert!(open_doc.contains("20"), "has a date: {:?}", open_doc);

        let hidden_place_doc = document(conn, "event_search_document", hidden_place);
        assert!(hidden_place_doc.contains("Hidden-place supper"));
        assert!(!hidden_place_doc.contains("Infinite Loop"), "the hidden location appeared in the event document");
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
        occasion(conn, "Followers only", "7 Limited Lane", Visibility::Limited, Moderation::Unmoderated);

        let doc = document(conn, "event_search_document", post.id);
        assert!(doc.contains("Public toast") && doc.contains("10 Open Road"), "{:?}", doc);
        for leaked in ["Secret meeting", "99 Hidden Lane", "Awaiting review", "5 Pending Place", "Followers only", "7 Limited Lane"] {
            assert!(!doc.contains(leaked), "{:?} leaked into {:?}", leaked, doc);
        }

        // LIMITED event + LIMITED occasion: equally "open" but the audiences can differ (different
        // authors' followers), so the occasion's text stays out of the shared embedding.
        let (limited_event, limited_post) = create_event(
            conn,
            &organizer,
            EventOpts {
                title: Some("Followers brunch".to_string()),
                visibility: Visibility::Limited,
                default_occasion: None,
                ..Default::default()
            },
        );
        create_occasion(
            conn,
            &limited_event,
            Some(&organizer),
            OccasionOpts {
                title: Some("Brunch table".to_string()),
                visibility: Visibility::Limited,
                location: Some(serde_json::json!({"uniformly_formatted_address": "3 Brunch Boulevard"})),
                ..Default::default()
            },
        );
        let limited_doc = document(conn, "event_search_document", limited_post.id);
        assert!(limited_doc.contains("Followers brunch"));
        assert!(!limited_doc.contains("3 Brunch Boulevard"), "limited occasion leaked");
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
        // The default configuration reads as enabled, with the default model and the choices offered.
        let settings = crate::rpcs::get_server_configuration_proto(conn).unwrap().search_settings.unwrap();
        assert!(settings.semantic_search_enabled);
        assert_eq!(settings.embedding_model, embeddings::DEFAULT_MODEL_ID);
        assert_eq!(settings.available_models.len(), embeddings::MODELS.len());
        assert!(settings.available_models.iter().any(|m| m.id == "multilingual-e5-small" && m.multilingual && m.memory_megabytes > 0));

        update(server_configurations::table.filter(server_configurations::active.eq(true)))
            .set(server_configurations::search_settings.eq(
                serde_json::to_value(SearchSettings { semantic_search_enabled: false, ..Default::default() }).unwrap(),
            ))
            .execute(conn)?;
        assert!(!embeddings::semantic_search_enabled(conn));
        assert!(!crate::rpcs::get_server_configuration_proto(conn).unwrap().search_settings.unwrap().semantic_search_enabled);
        // Disabled: no semantic ranking is attempted at all.
        assert_eq!(embeddings::semantic_ranking(conn, EmbeddingKind::Post, "anything", &[1, 2]), None);
        Ok(())
    });
}

#[test]
fn the_chosen_model_is_used_and_unknown_or_missing_choices_fall_back_to_the_default() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        crate::rpcs::get_server_configuration_proto(conn).unwrap(); // creates the default row if there is none
        let choose = |conn: &mut PgPooledConnection, id: &str| {
            update(server_configurations::table.filter(server_configurations::active.eq(true)))
                .set(server_configurations::search_settings.eq(serde_json::json!({
                    "semantic_search_enabled": true,
                    "embedding_model": id,
                })))
                .execute(conn)
                .unwrap();
        };
        choose(conn, "multilingual-e5-small");
        assert_eq!(embeddings::active_model(conn).id, "multilingual-e5-small");
        assert_eq!(
            crate::rpcs::get_server_configuration_proto(conn).unwrap().search_settings.unwrap().embedding_model,
            "multilingual-e5-small"
        );
        choose(conn, "retired-model-from-an-older-version");
        assert_eq!(embeddings::active_model(conn).id, embeddings::DEFAULT_MODEL_ID);
        choose(conn, "");
        assert_eq!(embeddings::active_model(conn).id, embeddings::DEFAULT_MODEL_ID);
        Ok(())
    });
}

#[test]
fn configure_server_rejects_an_unknown_embedding_model() {
    let mut conn = test_conn();
    conn.test_transaction::<_, diesel::result::Error, _>(|conn| {
        let mut config = crate::rpcs::get_server_configuration_proto(conn).unwrap();
        config.search_settings = Some(SearchSettings { embedding_model: "no-such-model".to_string(), ..Default::default() });
        let err = crate::rpcs::validations::validate_configuration(&config).unwrap_err();
        assert_eq!(err.message(), "unknown_embedding_model");
        config.search_settings = Some(SearchSettings { embedding_model: "all-minilm-l6-v2".to_string(), ..Default::default() });
        assert!(crate::rpcs::validations::validate_configuration(&config).is_ok());
        config.search_settings = Some(SearchSettings::default()); // empty = the default
        assert!(crate::rpcs::validations::validate_configuration(&config).is_ok());
        Ok(())
    });
}

#[test]
fn saving_the_configuration_without_search_settings_keeps_what_was_saved() {
    let _state = EMBEDDER_STATE.lock().unwrap_or_else(|e| e.into_inner());
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "older_client_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        // The admin turns semantic search off and picks a model...
        let mut config = crate::rpcs::get_server_configuration_proto(conn)?;
        config.search_settings = Some(SearchSettings {
            semantic_search_enabled: false,
            embedding_model: "all-minilm-l6-v2".to_string(),
            ..Default::default()
        });
        crate::rpcs::configure_server(config, &admin, conn)?;
        assert!(!embeddings::semantic_search_enabled(conn));

        // ...then a client that predates `search_settings` saves something else, sending none.
        let mut older_client_request = crate::rpcs::get_server_configuration_proto(conn)?;
        older_client_request.search_settings = None;
        crate::rpcs::configure_server(older_client_request, &admin, conn)?;

        assert!(!embeddings::semantic_search_enabled(conn), "it must stay off");
        assert_eq!(embeddings::active_model(conn).id, "all-minilm-l6-v2", "and keep its model");
        Ok(())
    });
}

#[test]
fn rows_embedded_by_another_model_are_redone_when_the_model_changes() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        // A blank document needs no model, so this runs without downloading one: what matters is
        // that a row from a *different* model counts as missing and is rewritten for the new one.
        let blank = create_post(conn, None, PostOpts { title: None, content: None, ..Default::default() });
        let mut ctx = SyncContext::unrestricted();
        ctx.spec = embeddings::model_spec("all-minilm-l6-v2").unwrap();
        embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        let model_of = |conn: &mut PgPooledConnection| -> String {
            post_embeddings::table
                .filter(post_embeddings::post_id.eq(blank.id))
                .select(post_embeddings::model)
                .first(conn)
                .unwrap()
        };
        assert_eq!(model_of(conn), "all-minilm-l6-v2");

        let mut switched = SyncContext::unrestricted();
        switched.spec = embeddings::model_spec("bge-small-en-v1.5").unwrap();
        let stats = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut switched)?;
        assert_eq!(stats.empty, 1, "the old model's row was redone");
        assert_eq!(model_of(conn), "bge-small-en-v1.5");
        Ok(())
    });
}

/// A deterministic stand-in for the model, so the sync and hybrid-search paths are tested in CI without
/// downloading anything. Each word maps to a "concept" (a tiny synonym table), concepts are hashed into
/// a bag-of-concepts vector as long as the default model's (so storage and the index see the real size), and that is normalized: texts about the same concepts are
/// close, texts about different ones are not -- enough to exercise everything around the model.
struct FakeEmbedder;

impl FakeEmbedder {
    /// `Some(concept)` for words the fake "understands" (synonyms share one), `None` for filler.
    fn concept(word: &str) -> Option<&'static str> {
        match word.to_lowercase().as_str() {
            "dog" | "dogs" | "puppy" | "puppies" | "canine" => Some("dog"),
            "bread" | "loaf" | "sourdough" | "dough" => Some("bread"),
            "tax" | "taxes" | "accountant" | "fiscal" => Some("tax"),
            _ => None,
        }
    }

    fn slot(word: &str) -> usize {
        word.bytes().fold(7usize, |h, b| h.wrapping_mul(31).wrapping_add(b as usize)) % (embeddings::default_model().dimensions as usize)
    }

    /// Concept words weigh a lot, filler (titles' other words, usernames, "Test content") barely --
    /// roughly how a real model attends to a document's topic.
    fn vector(text: &str) -> Vec<f32> {
        let mut v = vec![0f32; embeddings::default_model().dimensions as usize];
        for word in text.split(|c: char| !c.is_alphanumeric()).filter(|w| w.len() > 2) {
            match Self::concept(word) {
                Some(concept) => v[Self::slot(concept)] += 3.0,
                None => v[Self::slot(&word.to_lowercase())] += 0.1,
            }
        }
        let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            v.iter_mut().for_each(|x| *x /= norm);
        }
        v
    }
}

impl TextEmbedder for FakeEmbedder {
    fn spec(&self) -> &'static embeddings::ModelSpec {
        embeddings::default_model()
    }
    fn embed_documents(&mut self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        Ok(texts.iter().map(|t| Self::vector(t)).collect())
    }
    fn embed_query(&mut self, text: &str) -> anyhow::Result<Vec<f32>> {
        Ok(Self::vector(text))
    }
}

#[test]
fn sync_embeds_and_re_embeds_only_what_changed_through_the_embedder_seam() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "seam_sync");
        let post = title_post(conn, &author, "Adopting a puppy");
        let mut ctx = SyncContext::unrestricted();
        ctx.embedder = Some(Box::new(FakeEmbedder));

        let first = embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        assert!(first.embedded >= 1);
        let stored = |conn: &mut PgPooledConnection| -> (i64, i32) {
            post_embeddings::table
                .filter(post_embeddings::post_id.eq(post.id))
                .select((post_embeddings::document_hash, diesel::dsl::sql::<diesel::sql_types::Integer>("octet_length(embedding)")))
                .first(conn)
                .unwrap()
        };
        let (hash, bytes) = stored(conn);
        assert_eq!(bytes, embeddings::default_model().dimensions as i32 * 4);

        assert_eq!(embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?.embedded, 0, "unchanged");

        update(posts::table.filter(posts::id.eq(post.id))).set(posts::title.eq("Adopting a kitten")).execute(conn)?;
        assert_eq!(embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?.embedded, 1, "edited");
        assert_ne!(stored(conn).0, hash);
        Ok(())
    });
}

#[test]
fn hybrid_search_finds_posts_by_meaning_and_never_returns_one_the_viewer_cannot_see() {
    let _state = EMBEDDER_STATE.lock().unwrap_or_else(|e| e.into_inner());
    let mut conn = test_conn();
    // Search uses the process-wide query embedder; give it the fake for this test, and restore after.
    embeddings::install_server_embedder(Box::new(FakeEmbedder));
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "meaning_author");
        let viewer = create_user(conn, "meaning_viewer");
        let dog = title_post(conn, &author, "Adopting a puppy from the shelter");
        let tax = title_post(conn, &author, "Corporate tax deadlines for the accountant");
        // The closest match of all -- but private to its author, so the viewer must never see it.
        let private_dog = create_post(
            conn,
            Some(&author),
            PostOpts {
                title: Some("Canine puppy dog diary".to_string()),
                content: Some("Private notes".to_string()),
                visibility: Visibility::Private,
                ..Default::default()
            },
        );
        let mut ctx = SyncContext::unrestricted();
        ctx.embedder = Some(Box::new(FakeEmbedder));
        embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;

        let search = |conn: &mut PgPooledConnection, who: &crate::models::User| -> Vec<String> {
            crate::rpcs::get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::TextSearch as i32,
                    search_text: Some("getting canine".to_string()),
                    ..Default::default()
                },
                &Some(who),
                conn,
            )
            .unwrap()
            .posts
            .iter()
            .map(|p| p.id.clone())
            .collect()
        };
        let id_of = |p: &crate::models::Post| crate::marshaling::ToProtoId::to_proto_id(&p.id).to_string();

        // "getting canine" shares no word with the puppy post: full-text alone finds nothing.
        let found = search(conn, &viewer);
        assert!(found.contains(&id_of(&dog)), "found by meaning: {:?}", found);
        assert!(!found.contains(&id_of(&tax)), "unrelated stays out: {:?}", found);
        assert!(!found.contains(&id_of(&private_dog)), "never a post the viewer can't see: {:?}", found);
        // Its own author does see their private post.
        assert!(search(conn, &author).contains(&id_of(&private_dog)));
        Ok(())
    });
    embeddings::unload_server_embedder();
}

/// An index that "knows" every vector: for each kind it answers with a fixed list of ids, *whatever* the viewer
/// may see -- standing in for the vector search service, which knows nothing about visibility. The RPCs must
/// therefore filter its answers themselves.
struct EverythingIndex(std::collections::HashMap<&'static str, Vec<i64>>);

impl embeddings::SemanticIndex for EverythingIndex {
    fn supports_global(&self) -> bool {
        true
    }
    fn search(&self, _conn: &mut PgPooledConnection, query: &embeddings::IndexQuery) -> Option<Vec<(i64, f32)>> {
        assert!(query.scope.is_none(), "global mode asks for 'anywhere', not a candidate scope");
        Some(self.0.get(query.kind.name())?.iter().map(|id| (*id, 0.95)).collect())
    }
}

/// Global-mode search installs process-wide state (the query embedder and the index); this takes the lock, installs
/// both, runs `body`, and puts everything back.
fn with_everything_index(kinds: Vec<(&'static str, Vec<i64>)>, body: impl FnOnce()) {
    let _state = EMBEDDER_STATE.lock().unwrap_or_else(|e| e.into_inner());
    embeddings::install_server_embedder(Box::new(FakeEmbedder));
    embeddings::install_semantic_index(Box::new(EverythingIndex(kinds.into_iter().collect())));
    body();
    embeddings::reset_semantic_index();
    embeddings::unload_server_embedder();
}

/// An index that says it can search "anywhere" but then can't answer -- what the vector search service looks like in
/// the moment between going down and its client noticing.
struct CannotAnswerIndex;

impl embeddings::SemanticIndex for CannotAnswerIndex {
    fn supports_global(&self) -> bool {
        true
    }
    fn search(&self, _conn: &mut PgPooledConnection, _query: &embeddings::IndexQuery) -> Option<Vec<(i64, f32)>> {
        None
    }
}

/// Like `with_everything_index` for any index; the fake model embeds queries.
fn with_index(index: Box<dyn embeddings::SemanticIndex>, body: impl FnOnce()) {
    let _state = EMBEDDER_STATE.lock().unwrap_or_else(|e| e.into_inner());
    embeddings::install_server_embedder(Box::new(FakeEmbedder));
    embeddings::install_semantic_index(index);
    body();
    embeddings::reset_semantic_index();
    embeddings::unload_server_embedder();
}

/// What the optional vector search service being unavailable must look like to a user: nothing -- the semantic search
/// still works, through the Postgres scan. One scenario per search type, each run against a few unavailable indexes.
fn unavailable_indexes() -> Vec<(&'static str, Box<dyn embeddings::SemanticIndex>)> {
    vec![
        ("claims to be up but cannot answer", Box::new(CannotAnswerIndex)),
        (
            "a real client pointed at nothing",
            Box::new(embeddings::RemoteIndex::new("http://127.0.0.1:9", None).expect("the client starts lazily")),
        ),
    ]
}

#[test]
fn without_the_vector_service_posts_are_still_found_by_meaning_through_the_postgres_scan() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "fallback_posts_author");
        let viewer = create_user(conn, "fallback_posts_viewer");
        let dog = title_post(conn, &author, "Adopting a puppy");
        let private_dog = create_post(
            conn,
            Some(&author),
            PostOpts { title: Some("Private puppy diary".to_string()), visibility: Visibility::Private, ..Default::default() },
        );
        let mut ctx = SyncContext::unrestricted();
        ctx.embedder = Some(Box::new(FakeEmbedder));
        embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        let id_of = |p: &crate::models::Post| crate::marshaling::ToProtoId::to_proto_id(&p.id).to_string();
        for (why, index) in unavailable_indexes() {
            with_index(index, || {
                let found: Vec<String> = crate::rpcs::get_posts(
                    GetPostsRequest {
                        listing_type: PostListingType::TextSearch as i32,
                        search_text: Some("getting canine".to_string()),
                        ..Default::default()
                    },
                    &Some(&viewer),
                    conn,
                )
                .unwrap()
                .posts
                .iter()
                .map(|p| p.id.clone())
                .collect();
                assert!(found.contains(&id_of(&dog)), "{}: found by meaning via the scan: {:?}", why, found);
                assert!(!found.contains(&id_of(&private_dog)), "{}: and still never a private post: {:?}", why, found);
            });
        }
        Ok(())
    });
}

#[test]
fn without_the_vector_service_users_events_and_media_fall_back_to_the_postgres_scan_too() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let viewer = create_user(conn, "fallback_all_viewer");
        let organizer = create_user(conn, "fallback_all_organizer");
        let profile = create_user_with_profile(conn, "fallback_trainer", "Fay Trainer", "trains puppies and rescue dogs");
        let (event, _event_post) = create_event(
            conn,
            &organizer,
            EventOpts { title: Some("Puppy meetup".to_string()), default_occasion: None, ..Default::default() },
        );
        let (_occasion, occasion_post) = create_occasion(conn, &event, Some(&organizer), OccasionOpts::default());
        let media = create_media_with_opts(conn, Some(&organizer), MediaOpts { name: Some("Puppy video"), ..Default::default() });
        let mut ctx = SyncContext::unrestricted();
        ctx.embedder = Some(Box::new(FakeEmbedder));
        for kind in EmbeddingKind::ALL {
            embeddings::sync_embeddings(conn, kind, &mut ctx)?;
        }
        for (why, index) in unavailable_indexes() {
            with_index(index, || {
                let users: Vec<String> = crate::rpcs::get_users(
                    GetUsersRequest {
                        listing_type: UserListingType::UsersTextSearch as i32,
                        search_text: Some("canine".to_string()),
                        ..Default::default()
                    },
                    &Some(&viewer),
                    conn,
                )
                .unwrap()
                .users
                .iter()
                .map(|u| u.username.clone())
                .collect();
                assert!(users.contains(&profile.username), "{}: users: {:?}", why, users);

                let occasions: Vec<String> = crate::rpcs::get_events(
                    GetEventsRequest {
                        listing_type: EventListingType::EventTextSearch as i32,
                        search_text: Some("canine".to_string()),
                        ..Default::default()
                    },
                    &Some(&viewer),
                    conn,
                )
                .unwrap()
                .events
                .iter()
                .flat_map(|e| e.occasions.iter().map(|o| o.post.as_ref().map(|p| p.id.clone()).unwrap_or_default()))
                .collect();
                let occasion_id = crate::marshaling::ToProtoId::to_proto_id(&occasion_post.id).to_string();
                assert!(occasions.contains(&occasion_id), "{}: events: {:?}", why, occasions);

                let found: Vec<String> = crate::rpcs::get_media(
                    GetMediaRequest { search_text: Some("canine".to_string()), ..Default::default() },
                    &Some(&viewer),
                    conn,
                )
                .unwrap()
                .media
                .iter()
                .map(|m| m.id.clone())
                .collect();
                let media_id = crate::marshaling::ToProtoId::to_proto_id(&media.id).to_string();
                assert!(found.contains(&media_id), "{}: media: {:?}", why, found);
            });
        }
        Ok(())
    });
}

#[test]
fn a_remote_index_that_fails_stops_asking_so_the_fallback_is_immediate() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let remote = embeddings::RemoteIndex::new("http://127.0.0.1:9", None)?;
        assert!(embeddings::SemanticIndex::supports_global(&remote), "believed up until it fails");
        let vector = FakeEmbedder::vector("dog");
        let query = embeddings::IndexQuery {
            kind: EmbeddingKind::Post,
            spec: embeddings::default_model(),
            vector: &vector,
            scope: None,
            limit: 5,
        };
        assert_eq!(embeddings::SemanticIndex::search(&remote, conn, &query), None);
        // The breaker is open: callers now skip it and use the Postgres scan without waiting on a timeout.
        assert!(!embeddings::SemanticIndex::supports_global(&remote), "down: take the scan path directly");
        let started = std::time::Instant::now();
        assert_eq!(embeddings::SemanticIndex::search(&remote, conn, &query), None);
        assert!(started.elapsed() < std::time::Duration::from_millis(200), "no second wait: {:?}", started.elapsed());
        Ok(())
    });
}

#[test]
fn global_mode_posts_finds_semantic_only_matches_and_never_shows_what_the_viewer_cannot_see() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "global_posts_author");
        let viewer = create_user(conn, "global_posts_viewer");
        let dog = title_post(conn, &author, "Adopting a puppy");
        let private_dog = create_post(
            conn,
            Some(&author),
            PostOpts { title: Some("Private puppy diary".to_string()), visibility: Visibility::Private, ..Default::default() },
        );
        let id_of = |p: &crate::models::Post| crate::marshaling::ToProtoId::to_proto_id(&p.id).to_string();
        // The index returns both (it can't tell them apart); neither shares a word with the search.
        with_everything_index(vec![("post", vec![private_dog.id, dog.id])], || {
            let search = |conn: &mut PgPooledConnection, who: &crate::models::User| -> Vec<String> {
                crate::rpcs::get_posts(
                    GetPostsRequest {
                        listing_type: PostListingType::TextSearch as i32,
                        search_text: Some("zzzunmatchable".to_string()),
                        ..Default::default()
                    },
                    &Some(who),
                    conn,
                )
                .unwrap()
                .posts
                .iter()
                .map(|p| p.id.clone())
                .collect()
            };
            assert_eq!(search(conn, &viewer), vec![id_of(&dog)], "found by meaning; the private one filtered out");
            let as_author = search(conn, &author);
            assert!(as_author.contains(&id_of(&dog)) && as_author.contains(&id_of(&private_dog)), "{:?}", as_author);
        });
        Ok(())
    });
}

#[test]
fn global_mode_users_returns_only_profiles_the_viewer_may_see() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let viewer = create_user(conn, "global_users_viewer");
        let open = create_user_with_profile(conn, "open_profile", "Olive Open", "trains puppies");
        let hidden = create_user_with(conn, "hidden_profile", Visibility::Private, Moderation::Unmoderated);
        with_everything_index(vec![("user_profile", vec![hidden.id, open.id])], || {
            let response = crate::rpcs::get_users(
                GetUsersRequest {
                    listing_type: UserListingType::UsersTextSearch as i32,
                    search_text: Some("zzzunmatchable".to_string()),
                    ..Default::default()
                },
                &Some(&viewer),
                conn,
            )
            .unwrap();
            let names: Vec<String> = response.users.iter().map(|u| u.username.clone()).collect();
            assert_eq!(names, vec!["open_profile".to_string()]);
        });
        Ok(())
    });
}

#[test]
fn global_mode_events_returns_only_occasions_of_events_the_viewer_may_see() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let organizer = create_user(conn, "global_events_organizer");
        let viewer = create_user(conn, "global_events_viewer");
        let make = |conn: &mut PgPooledConnection, title: &str, visibility: Visibility| {
            let (event, _post) = create_event(
                conn,
                &organizer,
                EventOpts { title: Some(title.to_string()), visibility, default_occasion: None, ..Default::default() },
            );
            let (_occasion, occasion_post) =
                create_occasion(conn, &event, Some(&organizer), OccasionOpts { visibility, ..Default::default() });
            (event, occasion_post)
        };
        let (open_event, open_occasion_post) = make(conn, "Puppy meetup", Visibility::ServerPublic);
        let (private_event, _) = make(conn, "Private dog club", Visibility::Private);
        with_everything_index(vec![("event", vec![private_event.post_id, open_event.post_id])], || {
            let response = crate::rpcs::get_events(
                GetEventsRequest {
                    listing_type: EventListingType::EventTextSearch as i32,
                    search_text: Some("zzzunmatchable".to_string()),
                    ..Default::default()
                },
                &Some(&viewer),
                conn,
            )
            .unwrap();
            let found: Vec<String> = response
                .events
                .iter()
                .flat_map(|e| e.occasions.iter().map(|o| o.post.as_ref().map(|p| p.id.clone()).unwrap_or_default()))
                .collect();
            let open_id = crate::marshaling::ToProtoId::to_proto_id(&open_occasion_post.id).to_string();
            assert_eq!(found, vec![open_id], "only the visible event's occasion: {:?}", found);
        });
        Ok(())
    });
}

#[test]
fn global_mode_media_returns_only_media_the_viewer_may_see() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let owner = create_user(conn, "global_media_owner");
        let viewer = create_user(conn, "global_media_viewer");
        let open = create_media_with_opts(conn, Some(&owner), MediaOpts { name: Some("Puppy video"), ..Default::default() });
        let private = create_media_with_opts(
            conn,
            Some(&owner),
            MediaOpts { name: Some("Private diary"), visibility: Visibility::Private, ..Default::default() },
        );
        with_everything_index(vec![("media", vec![private.id, open.id])], || {
            let response = crate::rpcs::get_media(
                GetMediaRequest { search_text: Some("zzzunmatchable".to_string()), ..Default::default() },
                &Some(&viewer),
                conn,
            )
            .unwrap();
            let found: Vec<String> = response.media.iter().map(|m| m.id.clone()).collect();
            let open_id = crate::marshaling::ToProtoId::to_proto_id(&open.id).to_string();
            assert_eq!(found, vec![open_id], "{:?}", found);
        });
        Ok(())
    });
}

/// Starts the real model service (gRPC, auth and all) in-process on a free port, backed by the fake model, and
/// returns its URL. Runs on its own thread/runtime for the life of the test process.
fn start_model_service(secret: Option<&str>) -> String {
    let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
    let secret = secret.map(str::to_string);
    std::thread::spawn(move || {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(embeddings::model_service::serve(
                format!("127.0.0.1:{}", port).parse().unwrap(),
                Box::new(FakeEmbedder),
                secret,
            ))
            .unwrap();
    });
    let url = format!("http://127.0.0.1:{}", port);
    // Wait for it to accept connections.
    for _ in 0..100 {
        if std::net::TcpStream::connect(("127.0.0.1", port)).is_ok() {
            return url;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    panic!("the model service didn't start");
}

#[test]
fn the_model_service_embeds_for_a_remote_client_and_reports_its_model() {
    let url = start_model_service(Some("s3cret"));
    let mut remote = embeddings::RemoteEmbedder::connect(&url, Some("s3cret".to_string())).expect("connects");
    assert_eq!(remote.spec().id, embeddings::default_model().id, "the client learns the service's model");

    // Same vectors as the model run locally -- the client is a drop-in TextEmbedder.
    let docs = vec!["Adopting a puppy".to_string(), "Corporate tax deadlines".to_string()];
    assert_eq!(remote.embed_documents(&docs).unwrap(), FakeEmbedder.embed_documents(&docs).unwrap());
    assert_eq!(remote.embed_query("canine").unwrap(), FakeEmbedder.embed_query("canine").unwrap());
    // More texts than one request allows are split across calls transparently.
    let many: Vec<String> = (0..150).map(|i| format!("dog {}", i)).collect();
    assert_eq!(remote.embed_documents(&many).unwrap().len(), 150);
}

#[test]
fn a_required_model_service_means_servers_and_jobs_never_load_a_model_themselves() {
    // Required but not configured: refused outright, without ever touching the model (so no download, no RAM).
    let refused = embeddings::load_embedder_with(embeddings::default_model(), 1, None, true);
    let message = format!("{:?}", refused.err().expect("must refuse"));
    assert!(message.contains("RELLM_EMBEDDING_SERVICE_REQUIRED"), "{}", message);
    assert!(message.contains(embeddings::default_model().id), "says which model it refused: {}", message);

    // Required and configured: embeds through the service, whose model it uses.
    let url = start_model_service(None);
    let remote = embeddings::load_embedder_with(embeddings::default_model(), 1, Some((url, None)), true).expect("remote");
    assert_eq!(remote.spec().id, embeddings::default_model().id);
}

#[test]
fn the_model_service_refuses_callers_without_the_secret() {
    let url = start_model_service(Some("right"));
    let denied = embeddings::RemoteEmbedder::connect(&url, Some("wrong".to_string()));
    assert!(denied.is_err(), "a wrong secret must not even learn the model");
    let anonymous = embeddings::RemoteEmbedder::connect(&url, None);
    assert!(anonymous.is_err(), "no secret must be refused too");
}

#[test]
fn a_server_embeds_search_queries_and_the_job_embeds_documents_through_the_model_service() {
    let _state = EMBEDDER_STATE.lock().unwrap_or_else(|e| e.into_inner());
    let url = start_model_service(None);
    let mut conn = test_conn();
    embeddings::install_server_embedder(Box::new(embeddings::RemoteEmbedder::connect(&url, None).unwrap()));
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "remote_model_author");
        let dog = title_post(conn, &author, "Adopting a puppy from the shelter");
        // The job side: sync with a remote embedder.
        let mut ctx = SyncContext::unrestricted();
        ctx.embedder = Some(Box::new(embeddings::RemoteEmbedder::connect(&url, None).unwrap()));
        embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
        // The server side: a semantic-only search through the remote query embedder.
        let ranking = embeddings::semantic_ranking(conn, EmbeddingKind::Post, "getting canine", &[dog.id]).unwrap();
        assert_eq!(ranking.first().map(|m| m.0), Some(dog.id));
        Ok(())
    });
    embeddings::unload_server_embedder();
}

#[test]
fn the_postgres_scan_index_needs_a_scope_and_answers_only_within_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, anyhow::Error, _>(|conn| {
        let author = create_user(conn, "scan_scope");
        let a = title_post(conn, &author, "Dog puppy");
        let b = title_post(conn, &author, "Dog canine");
        let mut ctx = SyncContext::unrestricted();
        ctx.embedder = Some(Box::new(FakeEmbedder));
        embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;

        let vector = FakeEmbedder::vector("dog puppy canine");
        let spec = embeddings::default_model();
        let ask = |conn: &mut PgPooledConnection, scope: Option<&[i64]>| {
            embeddings::semantic_index().search(
                conn,
                &embeddings::IndexQuery { kind: EmbeddingKind::Post, spec, vector: &vector, scope, limit: 10 },
            )
        };
        assert_eq!(ask(conn, None), None, "a per-query scan can't answer 'anywhere'");
        let only_a = ask(conn, Some(&[a.id])).unwrap();
        assert_eq!(only_a.iter().map(|m| m.0).collect::<Vec<_>>(), vec![a.id]);
        let both = ask(conn, Some(&[a.id, b.id])).unwrap();
        assert_eq!(both.len(), 2);
        Ok(())
    });
}

use crate::schema::{post_embeddings, posts, server_configurations};

/// The server's query embedder is process-wide state; tests that install, replace or free it (or save a
/// configuration, which does) take this so they can't interfere with each other.
static EMBEDDER_STATE: std::sync::Mutex<()> = std::sync::Mutex::new(());

mod with_model {
    use super::*;
    use crate::rpcs::get_posts;

    fn wait_for_server_model() {
        embeddings::enable_model_loading();
        let started = std::time::Instant::now();
        while embeddings::server_embedder(embeddings::default_model()).is_none() {
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
            assert_eq!(bytes, embeddings::default_model().dimensions as usize * 4);

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

    // ---- Model comparison -------------------------------------------------------------------
    //
    // `cargo test --lib embeddings_tests::with_model::compare_models -- --ignored --nocapture`
    // (set COMPARE_MODEL=<model id> to run one model per process, for honest RAM numbers)
    //
    // Downloads every model in `embeddings::MODELS` and scores each on a small retrieval set: 25
    // short documents (English, Spanish, French, German; "title\ncontent" like real search documents)
    // and 29 queries each with one right document, in four kinds. None of the paraphrase/non-English
    // queries shares a word with its document, so this measures meaning, not keywords. A further 6
    // queries have no right answer and calibrate `ModelSpec.min_similarity`. It is deliberately
    // small: a sanity check and calibration aid, not a benchmark -- the differences between models
    // on your content may be larger or smaller.

    const CORPUS: [&str; 25] = [
        "Adopting a puppy from the shelter\nWhat to buy before your new dog comes home",
        "Sourdough starter troubleshooting\nMy bread won't rise and the starter smells like acetone",
        "Quarterly corporate tax filing deadlines\nWhat accountants need submitted before the fiscal year closes",
        "Learning to play jazz piano\nChord voicings and improvisation exercises for beginners",
        "Marathon training plan\nTwelve weeks of long runs, tempo work and rest days",
        "Repotting a root-bound houseplant\nWhen the roots circle the pot it's time for fresh soil",
        "Community garden volunteer day\nHelp us plant tomatoes and build raised beds this Saturday",
        "Open source licenses explained\nThe difference between permissive and copyleft software licenses",
        "Camping gear checklist\nTent, sleeping bag, stove and water filter for a weekend in the mountains",
        "How vaccines train the immune system\nAntibodies, memory cells and why boosters matter",
        "Cheap flights to Lisbon\nTips for finding airfare deals to Portugal in spring",
        "Electric cars charging at home\nInstalling a wall charger and what it costs per mile",
        "Local election results\nCity council candidates and ballot measures counted overnight",
        "Watercolor painting for beginners\nWet-on-wet technique, brushes and paper choices",
        "Debugging a memory leak in Rust\nProfiling allocations and tracking down who holds the references",
        "Neighborhood block party\nPotluck, live music and kids' games on Elm Street this weekend",
        "Receta de paella valenciana\nArroz, azafr\u{e1}n, pollo y conejo cocinados a fuego lento",
        "Consejos para ahorrar dinero\nC\u{f3}mo reducir gastos mensuales y crear un fondo de emergencia",
        "Concierto de guitarra flamenca\nUna noche de m\u{fa}sica tradicional andaluza en el teatro municipal",
        "Apprendre \u{e0} cuisiner des cr\u{ea}pes\nLa p\u{e2}te, la po\u{ea}le et les garnitures sucr\u{e9}es ou sal\u{e9}es",
        "Randonn\u{e9}e dans les Alpes\nSentiers de montagne, refuges et conseils de s\u{e9}curit\u{e9} pour l'\u{e9}t\u{e9}",
        "Exposition d'art moderne au mus\u{e9}e\nPeintures et sculptures d'artistes contemporains \u{e0} Paris",
        "Fahrradtour entlang der Donau\nRadwege, Unterk\u{fc}nfte und Etappenplanung f\u{fc}r eine Woche",
        "Bier brauen zu Hause\nMalz, Hopfen, Hefe und G\u{e4}rung f\u{fc}r das erste eigene Bier",
        "Wohnung in Berlin suchen\nTipps f\u{fc}r Mieter bei Besichtigung, Vertrag und Kaution",
    ];

    // (kind, query, index of the right document)
    const QUERIES: [(&str, &str, usize); 29] = [
        ("english paraphrase", "getting a new dog", 0),
        ("english paraphrase", "my loaf is flat", 1),
        ("english paraphrase", "business paperwork due to the government", 2),
        ("english paraphrase", "learn improvising on the keys", 3),
        ("english paraphrase", "preparing to run 26 miles", 4),
        ("english paraphrase", "plant is too big for its container", 5),
        ("english paraphrase", "volunteers growing vegetables together", 6),
        ("english paraphrase", "rules for reusing other people's code", 7),
        ("english paraphrase", "what to pack for sleeping outdoors", 8),
        ("english paraphrase", "why do I need a second shot", 9),
        ("english paraphrase", "inexpensive airfare to Europe", 10),
        ("english paraphrase", "plug in my Tesla at the house", 11),
        ("english paraphrase", "who won the mayoral vote", 12),
        ("english paraphrase", "painting with water-based colours", 13),
        ("english paraphrase", "program keeps eating RAM", 14),
        ("english paraphrase", "street party with food and music", 15),
        ("non-english", "plato t\u{ed}pico espa\u{f1}ol con arroz", 16),
        ("non-english", "guardar dinero para imprevistos", 17),
        ("non-english", "espect\u{e1}culo de baile y guitarra del sur de Espa\u{f1}a", 18),
        ("non-english", "recette de galettes fines", 19),
        ("non-english", "marcher en haute montagne", 20),
        ("non-english", "galerie d'oeuvres d'artistes actuels", 21),
        ("non-english", "mit dem Rad an einem Fluss entlang", 22),
        ("non-english", "alkoholisches Getr\u{e4}nk selbst herstellen", 23),
        ("non-english", "eine Mietwohnung finden", 24),
        ("cross-lingual", "traditional Spanish rice dish", 16),
        ("cross-lingual", "hiking in the French mountains", 20),
        ("cross-lingual", "brewing your own beer", 23),
        ("cross-lingual", "renting an apartment in Germany", 24),
    ];

    const NO_MATCH_QUERIES: [&str; 6] = [
        "quantum chromodynamics lattice calculations",
        "medieval siege warfare tactics",
        "how to knit a sweater",
        "deep sea hydrothermal vents",
        "stock option vesting schedule",
        "volcano eruption lava flow",
    ];

    fn dir_bytes(path: &std::path::Path) -> u64 {
        std::fs::read_dir(path)
            .map(|entries| {
                entries
                    .filter_map(Result::ok)
                    .map(|e| match e.metadata() {
                        Ok(m) if m.is_dir() => dir_bytes(&e.path()),
                        Ok(m) => m.len(),
                        Err(_) => 0,
                    })
                    .sum()
            })
            .unwrap_or(0)
    }

    fn resident_megabytes() -> f64 {
        std::fs::read_to_string("/proc/self/status")
            .ok()
            .and_then(|s| s.lines().find(|l| l.starts_with("VmRSS:")).map(str::to_string))
            .and_then(|l| l.split_whitespace().nth(1).and_then(|kb| kb.parse::<f64>().ok()))
            .map(|kb| kb / 1024.0)
            .unwrap_or(0.0)
    }

    fn dot(a: &[f32], b: &[f32]) -> f32 {
        a.iter().zip(b).map(|(x, y)| x * y).sum()
    }

    #[test]
    #[ignore = "downloads every embedding model (~650MB) and takes a few minutes"]
    fn compare_models() {
        let documents: Vec<String> = CORPUS.iter().map(|d| d.to_string()).collect();
        println!("\n| model | download | RAM after load | ms/doc | R@1 | R@3 | MRR | en R@3 | non-en R@3 | cross R@3 | best min_similarity (kept / rejected) | worst right answer .. best no-answer |");
        println!("|---|---|---|---|---|---|---|---|---|---|---|---|");
        // COMPARE_MODEL=<id> runs just that model -- one process per model gives honest RAM numbers.
        let only = std::env::var("COMPARE_MODEL").ok();
        for spec in embeddings::MODELS.iter().filter(|m| only.as_deref().map_or(true, |o| o == m.id)) {
            let cache = embeddings::model_cache_dir();
            let (bytes_before, rss_before) = (dir_bytes(&cache), resident_megabytes());
            let mut embedder = embeddings::LocalEmbedder::load(spec, 2).expect("model loads");
            let downloaded_mb = dir_bytes(&cache).saturating_sub(bytes_before) as f64 / 1_048_576.0;
            let ram_mb = resident_megabytes() - rss_before;

            let started = std::time::Instant::now();
            let doc_vectors = embedder.embed_documents(&documents).unwrap();
            let ms_per_doc = started.elapsed().as_secs_f64() * 1000.0 / documents.len() as f64;

            let mut ranks: Vec<(&str, usize)> = vec![];
            let mut relevant_similarities: Vec<f32> = vec![];
            for (kind, query, relevant) in QUERIES.iter() {
                let q = embedder.embed_query(query).unwrap();
                let mut scored: Vec<(usize, f32)> = doc_vectors.iter().enumerate().map(|(i, d)| (i, dot(&q, d))).collect();
                scored.sort_by(|a, b| b.1.total_cmp(&a.1));
                let rank = scored.iter().position(|(i, _)| i == relevant).unwrap() + 1;
                relevant_similarities.push(scored.iter().find(|(i, _)| i == relevant).unwrap().1);
                ranks.push((kind, rank));
            }
            let no_match_max: Vec<f32> = NO_MATCH_QUERIES
                .iter()
                .map(|q| {
                    let v = embedder.embed_query(q).unwrap();
                    doc_vectors.iter().map(|d| dot(&v, d)).fold(f32::MIN, f32::max)
                })
                .collect();

            let n = ranks.len() as f64;
            let at = |k: usize| ranks.iter().filter(|(_, r)| *r <= k).count() as f64 / n;
            let at_for = |kind: &str, k: usize| {
                let of_kind: Vec<_> = ranks.iter().filter(|(kd, _)| *kd == kind).collect();
                of_kind.iter().filter(|(_, r)| *r <= k).count() as f64 / of_kind.len() as f64
            };
            let mrr = ranks.iter().map(|(_, r)| 1.0 / *r as f64).sum::<f64>() / n;

            // The threshold that keeps the most right answers while rejecting the most no-answer queries.
            let (mut best_t, mut best_score, mut best_kept, mut best_rejected) = (0.0, -1.0, 0.0, 0.0);
            for step in 20..=95 {
                let t = step as f32 / 100.0;
                let kept = relevant_similarities.iter().filter(|s| **s >= t).count() as f64 / n;
                let rejected = no_match_max.iter().filter(|s| **s < t).count() as f64 / no_match_max.len() as f64;
                if kept + rejected > best_score + 1e-9 {
                    (best_t, best_score, best_kept, best_rejected) = (t, kept + rejected, kept, rejected);
                }
            }
            // When the right answers and the no-answer queries don't overlap, every threshold in the gap between
            // them is "perfect" and the sweep above just reports the lowest -- the *middle* of the gap is the
            // threshold to configure (the most margin both ways).
            let worst_right = relevant_similarities.iter().cloned().fold(f32::MAX, f32::min);
            let best_no_answer = no_match_max.iter().cloned().fold(f32::MIN, f32::max);
            println!(
                "| {} | {:.0} MB | {:.0} MB | {:.0} | {:.0}% | {:.0}% | {:.2} | {:.0}% | {:.0}% | {:.0}% | {:.2} ({:.0}% / {:.0}%) (configured {:.2}) | {:.3} .. {:.3} (middle {:.2}) |",
                spec.id,
                downloaded_mb,
                ram_mb,
                ms_per_doc,
                at(1) * 100.0,
                at(3) * 100.0,
                mrr,
                at_for("english paraphrase", 3) * 100.0,
                at_for("non-english", 3) * 100.0,
                at_for("cross-lingual", 3) * 100.0,
                best_t,
                best_kept * 100.0,
                best_rejected * 100.0,
                spec.min_similarity,
                worst_right,
                best_no_answer,
                (worst_right + best_no_answer) / 2.0,
            );
        }
    }
}

/// Tests of the real per-namespace vector service (USearch index + gRPC). They need the C++ USearch build, so they
/// only exist with `--features vector-service`: `cargo test --lib --features vector-service vector_service_tests`.
#[cfg(feature = "vector-service")]
mod vector_service_tests {
    use super::*;
    use crate::logic::embeddings::vector_service::{serve, VectorIndexes};

    fn spec() -> &'static embeddings::ModelSpec {
        embeddings::default_model()
    }

    fn start_vector_service(indexes: std::sync::Arc<VectorIndexes>, secret: Option<&str>) -> String {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let secret = secret.map(str::to_string);
        std::thread::spawn(move || {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .unwrap()
                .block_on(serve(format!("127.0.0.1:{}", port).parse().unwrap(), indexes, secret))
                .unwrap();
        });
        for _ in 0..100 {
            if std::net::TcpStream::connect(("127.0.0.1", port)).is_ok() {
                return format!("http://127.0.0.1:{}", port);
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        panic!("the vector service didn't start");
    }

    #[test]
    fn the_index_is_built_from_embeddings_searched_and_kept_current() {
        let mut conn = test_conn();
        conn.test_transaction::<_, anyhow::Error, _>(|conn| {
            let author = create_user(conn, "vector_index_author");
            let dog = title_post(conn, &author, "Adopting a puppy");
            let bread = title_post(conn, &author, "Sourdough loaf troubleshooting");
            let mut ctx = SyncContext::unrestricted();
            ctx.embedder = Some(Box::new(FakeEmbedder));
            embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;

            let indexes = VectorIndexes::new(spec());
            let query = FakeEmbedder::vector("canine puppy dog");
            assert_eq!(indexes.search(EmbeddingKind::Post, spec().id, &query, 10, 0.5), None, "not ready before the first build");

            indexes.sync_all(conn);
            let found = indexes.search(EmbeddingKind::Post, spec().id, &query, 10, 0.5).expect("ready after a build");
            assert_eq!(found.first().map(|m| m.0), Some(dog.id), "{:?}", found);
            assert!(!found.iter().any(|m| m.0 == bread.id), "the unrelated post is under the threshold: {:?}", found);
            assert!(found[0].1 > 0.9, "int8 quantization keeps the similarity close to exact: {:?}", found);
            // A query from another model's vectors (or the wrong size) is refused rather than compared.
            assert_eq!(indexes.search(EmbeddingKind::Post, "some-other-model", &query, 10, 0.5), None);
            assert_eq!(indexes.search(EmbeddingKind::Post, spec().id, &query[..10], 10, 0.5), None);

            // New and edited posts are picked up incrementally.
            let puppy2 = title_post(conn, &author, "Canine puppy training");
            update(posts::table.filter(posts::id.eq(bread.id))).set(posts::title.eq("Dog bread: a puppy treat recipe")).execute(conn)?;
            embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
            indexes.sync_all(conn);
            let found = indexes.search(EmbeddingKind::Post, spec().id, &query, 10, 0.5).unwrap();
            let ids: Vec<i64> = found.iter().map(|m| m.0).collect();
            assert!(ids.contains(&puppy2.id), "a new post appears: {:?}", ids);
            assert!(ids.contains(&bread.id), "an edited post moves to its new meaning: {:?}", ids);
            assert_eq!(ids.iter().filter(|id| **id == bread.id).count(), 1, "re-embedding replaces, never duplicates");

            let status = indexes.status();
            let post_status = status.kinds.iter().find(|k| k.kind == "post").unwrap();
            assert!(post_status.ready && post_status.vectors >= 3 && post_status.memory_bytes > 0, "{:?}", post_status);
            Ok(())
        });
    }

    #[test]
    fn the_vector_service_answers_a_remote_index_over_grpc_and_refuses_bad_secrets() {
        let mut conn = test_conn();
        conn.test_transaction::<_, anyhow::Error, _>(|conn| {
            let author = create_user(conn, "vector_grpc_author");
            let dog = title_post(conn, &author, "Adopting a puppy");
            let mut ctx = SyncContext::unrestricted();
            ctx.embedder = Some(Box::new(FakeEmbedder));
            embeddings::sync_embeddings(conn, EmbeddingKind::Post, &mut ctx)?;
            let indexes = VectorIndexes::new(spec());
            indexes.sync_all(conn);
            let url = start_vector_service(indexes, Some("vector-secret"));

            let vector = FakeEmbedder::vector("canine puppy dog");
            let ask = |conn: &mut PgPooledConnection, remote: &embeddings::RemoteIndex, scope: Option<&[i64]>| {
                embeddings::SemanticIndex::search(
                    remote,
                    conn,
                    &embeddings::IndexQuery { kind: EmbeddingKind::Post, spec: spec(), vector: &vector, scope, limit: 10 },
                )
            };
            let good = embeddings::RemoteIndex::new(&url, Some("vector-secret".to_string()))?;
            assert!(embeddings::SemanticIndex::supports_global(&good));
            let found = ask(conn, &good, None).expect("answers 'anywhere'");
            assert_eq!(found.first().map(|m| m.0), Some(dog.id));
            // A scoped query keeps only the caller's ids.
            assert_eq!(ask(conn, &good, Some(&[dog.id + 999_999])).unwrap(), vec![]);

            // Wrong secret: the service refuses, so the client reports "can't answer" (full-text fallback).
            let wrong = embeddings::RemoteIndex::new(&url, Some("nope".to_string()))?;
            assert_eq!(ask(conn, &wrong, None), None);
            let unreachable = embeddings::RemoteIndex::new("http://127.0.0.1:9", None)?;
            assert_eq!(ask(conn, &unreachable, None), None, "an unreachable service means full-text only, not an error");
            Ok(())
        });
    }

    #[test]
    fn a_kind_still_being_built_says_not_ready_and_the_client_falls_back() {
        let mut conn = test_conn();
        conn.test_transaction::<_, anyhow::Error, _>(|conn| {
            let indexes = VectorIndexes::new(spec()); // never synced: nothing built yet
            let url = start_vector_service(indexes, None);
            let remote = embeddings::RemoteIndex::new(&url, None)?;
            let vector = FakeEmbedder::vector("dog");
            let answer = embeddings::SemanticIndex::search(
                &remote,
                conn,
                &embeddings::IndexQuery { kind: EmbeddingKind::Post, spec: spec(), vector: &vector, scope: None, limit: 10 },
            );
            assert_eq!(answer, None);
            Ok(())
        });
    }
}
