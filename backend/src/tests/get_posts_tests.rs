//! Specs for `rpcs::posts::get_posts`, covering every branch of the `match` in
//! `get_posts()` plus the visibility/moderation rules baked into `query_visible_posts!`.
//!
//! Each test opens its own connection to `TEST_DATABASE_URL` and runs entirely inside a
//! `test_transaction`, so nothing here is ever committed - tests are free to create users,
//! posts, groups, etc. via `crate::tests::factories` without any cleanup step.

use std::time::{Duration, SystemTime};

use diesel::Connection;
use tonic::{Code, Status};

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::get_posts;
use crate::tests::factories::*;

fn ids(response: &GetPostsResponse) -> Vec<String> {
    response.posts.iter().map(|p| p.id.clone()).collect()
}

/// A timestamp `seconds` in the past - for building posts with distinct, explicit
/// `created_at`/`published_at` values (see `PostOpts`'s doc comment on those fields for why that's
/// necessary: plain `NOW()`-defaulted timestamps would all collide within one `test_transaction`).
fn ago(seconds: u64) -> SystemTime {
    SystemTime::now() - Duration::from_secs(seconds)
}

mod get_by_post_id {
    use super::*;

    #[test]
    fn found_returns_public_post() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "gbpi_author1");
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(ids(&response), vec![post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn not_found_for_nonexistent_id() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let result = get_posts(
                GetPostsRequest {
                    post_id: Some(999_999_999i64.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            );

            let err = result.unwrap_err();
            assert_eq!(err.code(), Code::NotFound);
            assert_eq!(err.message(), "post_not_found");
            Ok(())
        });
    }

    #[test]
    fn invalid_id_format() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let result = get_posts(
                GetPostsRequest {
                    post_id: Some("not-valid-base58!!".to_string()),
                    ..Default::default()
                },
                &None,
                conn,
            );

            let err = result.unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "post_id_invalid");
            Ok(())
        });
    }

    #[test]
    fn private_post_visible_to_author_only() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "gbpi_author2");
            let other = create_user(conn, "gbpi_other2");
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::Private,
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&author),
                conn,
            )?;
            assert_eq!(ids(&response), vec![post.id.to_proto_id()]);

            let hidden = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&other),
                conn,
            );
            assert_eq!(hidden.unwrap_err().code(), Code::NotFound);

            let anon = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            );
            assert_eq!(anon.unwrap_err().code(), Code::NotFound);
            Ok(())
        });
    }

    #[test]
    fn limited_post_visible_to_follower_only() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "gbpi_author3");
            let follower = create_user(conn, "gbpi_follower3");
            let stranger = create_user(conn, "gbpi_stranger3");
            create_follow(conn, &follower, &author);
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::Limited,
                    ..Default::default()
                },
            );

            let visible = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&follower),
                conn,
            )?;
            assert_eq!(ids(&visible), vec![post.id.to_proto_id()]);

            let hidden = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&stranger),
                conn,
            );
            assert_eq!(hidden.unwrap_err().code(), Code::NotFound);
            Ok(())
        });
    }

    #[test]
    fn limited_post_visible_via_passing_group_membership() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "gbpi_author4");
            let member = create_user(conn, "gbpi_member4");
            let pending_member = create_user(conn, "gbpi_pending4");
            let group = create_group(conn, "gbpi-group4", GroupOpts::default());
            create_membership(
                conn,
                &member,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![],
            );
            create_membership(
                conn,
                &pending_member,
                &group,
                Moderation::Pending,
                Moderation::Approved,
                vec![],
            );
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::Limited,
                    ..Default::default()
                },
            );
            create_group_post(conn, &post, &group, &author, Moderation::Approved);

            let visible = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&member),
                conn,
            )?;
            assert_eq!(ids(&visible), vec![post.id.to_proto_id()]);

            let hidden = get_posts(
                GetPostsRequest {
                    post_id: Some(post.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&pending_member),
                conn,
            );
            assert_eq!(hidden.unwrap_err().code(), Code::NotFound);
            Ok(())
        });
    }
}

mod replies {
    use super::*;

    struct Tree {
        root: crate::models::Post,
        reply1: crate::models::Post,
        reply2: crate::models::Post,
    }

    fn build_tree(conn: &mut crate::db_connection::PgPooledConnection) -> Tree {
        let author = create_user(conn, "replies_author");
        let root = create_post(
            conn,
            Some(&author),
            PostOpts {
                visibility: Visibility::GlobalPublic,
                ..Default::default()
            },
        );
        let reply1 = create_post(
            conn,
            Some(&author),
            PostOpts {
                visibility: Visibility::GlobalPublic,
                context: PostContext::Reply,
                parent_post_id: Some(root.id),
                ..Default::default()
            },
        );
        let reply2 = create_post(
            conn,
            Some(&author),
            PostOpts {
                visibility: Visibility::GlobalPublic,
                context: PostContext::Reply,
                parent_post_id: Some(reply1.id),
                ..Default::default()
            },
        );
        Tree {
            root,
            reply1,
            reply2,
        }
    }

    #[test]
    fn depth_zero_or_none_returns_only_the_post_itself() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let tree = build_tree(conn);

            let none_response = get_posts(
                GetPostsRequest {
                    post_id: Some(tree.root.id.to_proto_id()),
                    reply_depth: None,
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&none_response), vec![tree.root.id.to_proto_id()]);

            let zero_response = get_posts(
                GetPostsRequest {
                    post_id: Some(tree.root.id.to_proto_id()),
                    reply_depth: Some(0),
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&zero_response), vec![tree.root.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn depth_one_returns_only_direct_replies() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let tree = build_tree(conn);

            let response = get_posts(
                GetPostsRequest {
                    post_id: Some(tree.root.id.to_proto_id()),
                    reply_depth: Some(1),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(ids(&response), vec![tree.reply1.id.to_proto_id()]);
            assert!(response.posts[0].replies.is_empty());
            Ok(())
        });
    }

    #[test]
    fn depth_two_returns_nested_replies() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let tree = build_tree(conn);

            let response = get_posts(
                GetPostsRequest {
                    post_id: Some(tree.root.id.to_proto_id()),
                    reply_depth: Some(2),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(ids(&response), vec![tree.reply1.id.to_proto_id()]);
            let nested = &response.posts[0].replies;
            assert_eq!(
                nested.iter().map(|p| p.id.clone()).collect::<Vec<_>>(),
                vec![tree.reply2.id.to_proto_id()]
            );
            Ok(())
        });
    }

    #[test]
    fn invalid_id_format() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let result = get_posts(
                GetPostsRequest {
                    post_id: Some("not-valid-base58!!".to_string()),
                    reply_depth: Some(1),
                    ..Default::default()
                },
                &None,
                conn,
            );

            let err = result.unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "replies_to_post_id_invalid");
            Ok(())
        });
    }

    #[test]
    fn excludes_replies_with_no_author_and_no_responses() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "replies_author_orphan");
            let root = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            // Simulates a reply left behind by a deleted user (user_id NULL) that never
            // itself received any responses - get_replies_to_post_ids filters these out.
            create_post(
                conn,
                None,
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(root.id),
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    post_id: Some(root.id.to_proto_id()),
                    reply_depth: Some(1),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert!(response.posts.is_empty());
            Ok(())
        });
    }

    #[test]
    fn orders_direct_replies_by_effective_publish_date() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "replies_order_author");
            let root = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            let older_reply = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(root.id),
                    created_at: Some(ago(120)),
                    ..Default::default()
                },
            );
            let newer_reply = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(root.id),
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    post_id: Some(root.id.to_proto_id()),
                    reply_depth: Some(1),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(
                ids(&response),
                vec![newer_reply.id.to_proto_id(), older_reply.id.to_proto_id()]
            );
            Ok(())
        });
    }
}

mod text_search {
    use super::*;

    fn search(
        conn: &mut crate::db_connection::PgPooledConnection,
        search_text: Option<&str>,
        author_user_id: Option<String>,
        user: &Option<&crate::models::User>,
    ) -> Result<GetPostsResponse, Status> {
        search_with_context(conn, search_text, author_user_id, None, user)
    }

    fn search_with_context(
        conn: &mut crate::db_connection::PgPooledConnection,
        search_text: Option<&str>,
        author_user_id: Option<String>,
        context: Option<PostContext>,
        user: &Option<&crate::models::User>,
    ) -> Result<GetPostsResponse, Status> {
        get_posts(
            GetPostsRequest {
                listing_type: PostListingType::TextSearch as i32,
                search_text: search_text.map(str::to_string),
                author_user_id,
                context: context.map(|c| c as i32),
                ..Default::default()
            },
            user,
            conn,
        )
    }

    #[test]
    fn missing_search_text_is_invalid_argument() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let err = search(conn, None, None, &None).unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "search_text_required");
            Ok(())
        });
    }

    #[test]
    fn blank_search_text_is_invalid_argument() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let err = search(conn, Some("   "), None, &None).unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "search_text_required");
            Ok(())
        });
    }

    #[test]
    fn matches_title() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "search_title_author");
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("A post about xylophones".to_string()),
                    ..Default::default()
                },
            );

            let response = search(conn, Some("xylophones"), None, &None)?;
            assert_eq!(ids(&response), vec![post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn matches_author_username() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "zzyzxauthor");
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );

            let response = search(conn, Some("zzyzxauthor"), None, &None)?;
            assert_eq!(ids(&response), vec![post.id.to_proto_id()]);
            Ok(())
        });
    }

    /// `search_text` matches by tsquery *prefix* (Postgres's `:*` operator - see
    /// `crate::logic::prefix_tsquery_text`), not just a whole/stemmed lexeme - "zzyzxauth" should
    /// find a "zzyzxauthor2"-authored post too, not just an exact "zzyzxauthor2" username.
    #[test]
    fn matches_author_username_prefix() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "zzyzxauthor2");
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );

            let response = search(conn, Some("zzyzxauth"), None, &None)?;
            assert_eq!(ids(&response), vec![post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn scoped_by_author_user_id() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author1 = create_user(conn, "search_scope_author1");
            let author2 = create_user(conn, "search_scope_author2");
            let post1 = create_post(
                conn,
                Some(&author1),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("wobblepost from author1".to_string()),
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&author2),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("wobblepost from author2".to_string()),
                    ..Default::default()
                },
            );

            let response = search(
                conn,
                Some("wobblepost"),
                Some(author1.id.to_proto_id()),
                &None,
            )?;
            assert_eq!(ids(&response), vec![post1.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn excludes_posts_not_visible_to_requester() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "search_private_author");
            create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::Private,
                    title: Some("a secret gizmo post".to_string()),
                    ..Default::default()
                },
            );

            let response = search(conn, Some("gizmo"), None, &None)?;
            assert!(response.posts.is_empty());
            Ok(())
        });
    }

    #[test]
    fn excludes_non_post_context() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "search_reply_author");
            let root = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(root.id),
                    title: None,
                    content: Some("flibbertigibbet".to_string()),
                    ..Default::default()
                },
            );

            let response = search(conn, Some("flibbertigibbet"), None, &None)?;
            assert!(response.posts.is_empty());
            Ok(())
        });
    }

    #[test]
    fn matches_reply_context_when_requested() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "search_context_author");
            let root = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("a post about wombats".to_string()),
                    ..Default::default()
                },
            );
            let reply = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(root.id),
                    title: None,
                    content: Some("a reply about wombats".to_string()),
                    ..Default::default()
                },
            );

            let post_response =
                search_with_context(conn, Some("wombats"), None, Some(PostContext::Post), &None)?;
            assert_eq!(ids(&post_response), vec![root.id.to_proto_id()]);

            let reply_response =
                search_with_context(conn, Some("wombats"), None, Some(PostContext::Reply), &None)?;
            assert_eq!(ids(&reply_response), vec![reply.id.to_proto_id()]);
            Ok(())
        });
    }

    /// Search results rank by match quality first: a title match (tsvector weight 'A') outranks
    /// a content-only match (weight 'B') even when the content match is far more recent - unlike
    /// every other GetPosts branch, which orders purely by effective publish date.
    #[test]
    fn orders_by_relevance_before_recency() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "search_relevance_author");
            let title_match = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("gerbilmongoose special".to_string()),
                    created_at: Some(ago(600)),
                    ..Default::default()
                },
            );
            let content_match = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    content: Some("a post that mentions gerbilmongoose in passing".to_string()),
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );

            let response = search(conn, Some("gerbilmongoose"), None, &None)?;

            assert_eq!(
                ids(&response),
                vec![title_match.id.to_proto_id(), content_match.id.to_proto_id()]
            );
            Ok(())
        });
    }

    /// When two results rank equally (identical title match), ties break by effective publish
    /// date, most recent first.
    #[test]
    fn breaks_relevance_ties_by_recency() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "search_tiebreak_author");
            let older = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("wizardquokka".to_string()),
                    created_at: Some(ago(120)),
                    ..Default::default()
                },
            );
            let newer = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    title: Some("wizardquokka".to_string()),
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );

            let response = search(conn, Some("wizardquokka"), None, &None)?;

            assert_eq!(
                ids(&response),
                vec![newer.id.to_proto_id(), older.id.to_proto_id()]
            );
            Ok(())
        });
    }
}

mod user_posts {
    use super::*;

    #[test]
    fn returns_only_that_authors_posts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author1 = create_user(conn, "userposts_author1");
            let author2 = create_user(conn, "userposts_author2");
            let post1 = create_post(
                conn,
                Some(&author1),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&author2),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author1.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(ids(&response), vec![post1.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn respects_visibility_of_other_users_posts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "userposts_author3");
            let public_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            let private_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::Private,
                    ..Default::default()
                },
            );

            let anon_response = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&anon_response), vec![public_post.id.to_proto_id()]);

            let self_response = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&author),
                conn,
            )?;
            let mut self_ids = ids(&self_response);
            self_ids.sort();
            let mut expected = vec![public_post.id.to_proto_id(), private_post.id.to_proto_id()];
            expected.sort();
            assert_eq!(self_ids, expected);
            Ok(())
        });
    }

    #[test]
    fn orders_by_effective_publish_date() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "userposts_order_author");
            let older = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(120)),
                    ..Default::default()
                },
            );
            let newer = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(
                ids(&response),
                vec![newer.id.to_proto_id(), older.id.to_proto_id()]
            );
            Ok(())
        });
    }
}

mod my_groups_posts {
    use super::*;

    #[test]
    fn requires_login() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let err = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::MyGroupsPosts as i32,
                    ..Default::default()
                },
                &None,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::Unauthenticated);
            Ok(())
        });
    }

    #[test]
    fn returns_posts_from_my_groups_with_passing_group_post_moderation() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let member = create_user(conn, "mygroups_member1");
            let author = create_user(conn, "mygroups_author1");
            let group = create_group(conn, "mygroups-group1", GroupOpts::default());
            create_membership(
                conn,
                &member,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![],
            );
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_group_post(conn, &post, &group, &author, Moderation::Approved);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::MyGroupsPosts as i32,
                    ..Default::default()
                },
                &Some(&member),
                conn,
            )?;

            assert_eq!(ids(&response), vec![post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn excludes_group_posts_pending_moderation() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let member = create_user(conn, "mygroups_member2");
            let author = create_user(conn, "mygroups_author2");
            let group = create_group(conn, "mygroups-group2", GroupOpts::default());
            create_membership(
                conn,
                &member,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![],
            );
            let post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_group_post(conn, &post, &group, &author, Moderation::Pending);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::MyGroupsPosts as i32,
                    ..Default::default()
                },
                &Some(&member),
                conn,
            )?;

            assert!(response.posts.is_empty());
            Ok(())
        });
    }

    #[test]
    fn orders_by_effective_publish_date() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let member = create_user(conn, "mygroups_order_member");
            let author = create_user(conn, "mygroups_order_author");
            let group = create_group(conn, "mygroups-order-group", GroupOpts::default());
            create_membership(
                conn,
                &member,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![],
            );
            let older = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    created_at: Some(ago(120)),
                    ..Default::default()
                },
            );
            create_group_post(conn, &older, &group, &author, Moderation::Approved);
            let newer = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );
            create_group_post(conn, &newer, &group, &author, Moderation::Approved);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::MyGroupsPosts as i32,
                    ..Default::default()
                },
                &Some(&member),
                conn,
            )?;

            assert_eq!(
                ids(&response),
                vec![newer.id.to_proto_id(), older.id.to_proto_id()]
            );
            Ok(())
        });
    }
}

mod following_posts {
    use super::*;

    #[test]
    fn requires_login() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let err = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::FollowingPosts as i32,
                    ..Default::default()
                },
                &None,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::Unauthenticated);
            Ok(())
        });
    }

    #[test]
    fn returns_posts_from_followed_users_only() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let follower = create_user(conn, "following_follower1");
            let followed = create_user(conn, "following_followed1");
            let not_followed = create_user(conn, "following_notfollowed1");
            create_follow(conn, &follower, &followed);

            let followed_post = create_post(
                conn,
                Some(&followed),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&not_followed),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::FollowingPosts as i32,
                    ..Default::default()
                },
                &Some(&follower),
                conn,
            )?;

            assert_eq!(ids(&response), vec![followed_post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn ignores_pending_follows_replies_and_own_posts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let follower = create_user(conn, "following_pending_follower");
            let approved = create_user(conn, "following_pending_approved");
            let pending = create_user(conn, "following_pending_pending");
            create_follow(conn, &follower, &approved);
            create_follow_with_moderation(conn, &follower, &pending, Moderation::Pending);

            let kept = create_post(
                conn,
                Some(&approved),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&pending),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&follower),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            let reply = create_post(
                conn,
                Some(&approved),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(kept.id),
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::FollowingPosts as i32,
                    ..Default::default()
                },
                &Some(&follower),
                conn,
            )?;

            assert_eq!(ids(&response), vec![kept.id.to_proto_id()]);

            let replies = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::FollowingPosts as i32,
                    context: Some(PostContext::Reply as i32),
                    ..Default::default()
                },
                &Some(&follower),
                conn,
            )?;
            assert_eq!(ids(&replies), vec![reply.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn orders_by_effective_publish_date() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let follower = create_user(conn, "following_order_follower");
            let followed = create_user(conn, "following_order_followed");
            create_follow(conn, &follower, &followed);

            let older = create_post(
                conn,
                Some(&followed),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    created_at: Some(ago(120)),
                    ..Default::default()
                },
            );
            let newer = create_post(
                conn,
                Some(&followed),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::FollowingPosts as i32,
                    ..Default::default()
                },
                &Some(&follower),
                conn,
            )?;

            assert_eq!(
                ids(&response),
                vec![newer.id.to_proto_id(), older.id.to_proto_id()]
            );
            Ok(())
        });
    }
}

mod group_posts {
    use super::*;

    #[test]
    fn missing_group_id_is_invalid_argument() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let err = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPosts as i32,
                    ..Default::default()
                },
                &None,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "group_id_required");
            Ok(())
        });
    }

    #[test]
    fn nonexistent_group_is_not_found() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let err = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPosts as i32,
                    group_id: Some(999_999_999i64.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::NotFound);
            assert_eq!(err.message(), "group_not_found");
            Ok(())
        });
    }

    #[test]
    fn permission_denied_for_private_group_non_member() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            // No non_member_permissions granted, and requester isn't a member.
            let group = create_group(conn, "grouppost-private1", GroupOpts::default());
            let stranger = create_user(conn, "grouppost_stranger1");

            let err = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPosts as i32,
                    group_id: Some(group.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&stranger),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            Ok(())
        });
    }

    #[test]
    fn anonymous_can_view_when_group_grants_view_posts_to_non_members() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "grouppost_author2");
            let group = create_group(
                conn,
                "grouppost-public2",
                GroupOpts {
                    non_member_permissions: vec![Permission::ViewPosts],
                },
            );
            let unmoderated_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            create_group_post(
                conn,
                &unmoderated_post,
                &group,
                &author,
                Moderation::Unmoderated,
            );
            let approved_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            create_group_post(conn, &approved_post, &group, &author, Moderation::Approved);
            let pending_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            create_group_post(conn, &pending_post, &group, &author, Moderation::Pending);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPosts as i32,
                    group_id: Some(group.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            let mut actual = ids(&response);
            actual.sort();
            let mut expected = vec![
                unmoderated_post.id.to_proto_id(),
                approved_post.id.to_proto_id(),
            ];
            expected.sort();
            assert_eq!(actual, expected);
            Ok(())
        });
    }

    #[test]
    fn orders_by_effective_publish_date() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "grouppost_order_author");
            let group = create_group(
                conn,
                "grouppost-order-group",
                GroupOpts {
                    non_member_permissions: vec![Permission::ViewPosts],
                },
            );
            let older = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(120)),
                    ..Default::default()
                },
            );
            create_group_post(conn, &older, &group, &author, Moderation::Approved);
            let newer = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(10)),
                    ..Default::default()
                },
            );
            create_group_post(conn, &newer, &group, &author, Moderation::Approved);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPosts as i32,
                    group_id: Some(group.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )?;

            assert_eq!(
                ids(&response),
                vec![newer.id.to_proto_id(), older.id.to_proto_id()]
            );
            Ok(())
        });
    }
}

mod group_posts_pending_moderation {
    use super::*;

    #[test]
    fn requires_login() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let group = create_group(conn, "grouppending-anon1", GroupOpts::default());
            let err = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPostsPendingModeration as i32,
                    group_id: Some(group.id.to_proto_id()),
                    ..Default::default()
                },
                &None,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::Unauthenticated);
            Ok(())
        });
    }

    #[test]
    fn returns_only_pending_posts_for_an_authorized_member() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "grouppending_author1");
            let moderator = create_user(conn, "grouppending_mod1");
            let group = create_group(conn, "grouppending-group1", GroupOpts::default());
            create_membership(
                conn,
                &moderator,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![Permission::ViewPosts],
            );
            let pending_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_group_post(conn, &pending_post, &group, &author, Moderation::Pending);
            let approved_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );
            create_group_post(conn, &approved_post, &group, &author, Moderation::Approved);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPostsPendingModeration as i32,
                    group_id: Some(group.id.to_proto_id()),
                    ..Default::default()
                },
                &Some(&moderator),
                conn,
            )?;

            assert_eq!(ids(&response), vec![pending_post.id.to_proto_id()]);
            Ok(())
        });
    }
}

mod default_listing {
    use super::*;

    #[test]
    fn excludes_replies_and_authorless_posts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "default_listing_author1");
            let top_level = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(top_level.id),
                    ..Default::default()
                },
            );
            create_post(
                conn,
                None,
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );

            let response = get_posts(GetPostsRequest::default(), &None, conn)?;

            assert_eq!(ids(&response), vec![top_level.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn anonymous_sees_only_global_public_authenticated_sees_server_public_too() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "default_listing_author2");
            let viewer = create_user(conn, "default_listing_viewer2");
            let global_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            let server_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    ..Default::default()
                },
            );

            let anon_response = get_posts(GetPostsRequest::default(), &None, conn)?;
            assert_eq!(ids(&anon_response), vec![global_post.id.to_proto_id()]);

            let auth_response = get_posts(GetPostsRequest::default(), &Some(&viewer), conn)?;
            let mut actual = ids(&auth_response);
            actual.sort();
            let mut expected = vec![global_post.id.to_proto_id(), server_post.id.to_proto_id()];
            expected.sort();
            assert_eq!(actual, expected);
            Ok(())
        });
    }

    /// A real reply always has `parent_post_id` set, so simply swapping the `context` filter to
    /// `REPLY` (like the `POST` default does) would come back empty were the `parent_post_id IS
    /// NULL` filter still applied unconditionally - that filter only makes sense for the `POST`
    /// case. See `get_public_and_following_posts`'s doc comment.
    #[test]
    fn respects_requested_context() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "default_listing_author3");
            let top_level = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    ..Default::default()
                },
            );
            let reply = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(top_level.id),
                    ..Default::default()
                },
            );

            let post_response = get_posts(
                GetPostsRequest {
                    context: Some(PostContext::Post as i32),
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&post_response), vec![top_level.id.to_proto_id()]);

            let reply_response = get_posts(
                GetPostsRequest {
                    context: Some(PostContext::Reply as i32),
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&reply_response), vec![reply.id.to_proto_id()]);
            Ok(())
        });
    }

    /// Orders by `COALESCE(published_at, created_at)` descending: a post republished 1 minute
    /// ago outranks one merely created 5 minutes ago, even though the republished post is
    /// actually the oldest of the three by `created_at`.
    #[test]
    fn orders_by_effective_publish_date() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "default_listing_order_author");
            let old_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(600)),
                    ..Default::default()
                },
            );
            let new_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(300)),
                    ..Default::default()
                },
            );
            let republished_post = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    created_at: Some(ago(1200)),
                    published_at: Some(ago(60)),
                    ..Default::default()
                },
            );

            let response = get_posts(GetPostsRequest::default(), &None, conn)?;

            assert_eq!(
                ids(&response),
                vec![
                    republished_post.id.to_proto_id(),
                    new_post.id.to_proto_id(),
                    old_post.id.to_proto_id(),
                ]
            );
            Ok(())
        });
    }
}

/// `RECENTLY_POPULAR_POSTS`: `(stars + 2 * responses + 1) / (age_hours + 2) ^ 1.5` over the last 14
/// days. See that listing type's doc comment in `posts.proto`.
mod recently_popular_posts {
    use diesel::{ExpressionMethods, QueryDsl, RunQueryDsl};

    use super::*;
    use crate::schema::posts;

    const HOUR: u64 = 60 * 60;
    const DAY: u64 = 24 * HOUR;

    fn popular_request() -> GetPostsRequest {
        GetPostsRequest {
            listing_type: PostListingType::RecentlyPopularPosts as i32,
            ..Default::default()
        }
    }

    /// A global-public post by `author` published `age_secs` ago, with `stars` stars and
    /// `responses` responses (set directly -- the columns `star_post`/`create_post` maintain).
    fn post_with(
        conn: &mut crate::db_connection::PgPooledConnection,
        author: &crate::models::User,
        age_secs: u64,
        stars: i64,
        responses: i32,
    ) -> crate::models::Post {
        let post = create_post(
            conn,
            Some(author),
            PostOpts {
                visibility: Visibility::GlobalPublic,
                created_at: Some(ago(age_secs)),
                published_at: Some(ago(age_secs)),
                ..Default::default()
            },
        );
        diesel::update(posts::table.filter(posts::id.eq(post.id)))
            .set((
                posts::unauthenticated_star_count.eq(stars),
                posts::response_count.eq(responses),
            ))
            .execute(conn)
            .expect("failed to set engagement");
        post
    }

    #[test]
    fn ranks_engaged_posts_above_newer_unengaged_ones() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author1");
            let newest_quiet = post_with(conn, &author, 60, 0, 0);
            let older_liked = post_with(conn, &author, 3 * HOUR, 20, 0);

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(
                ids(&response),
                vec![older_liked.id.to_proto_id(), newest_quiet.id.to_proto_id()]
            );
            Ok(())
        });
    }

    /// The decay matters: a week-old post with 100 stars scores ~0.05, a one-hour-old post with 5
    /// stars ~1.15.
    #[test]
    fn newer_moderately_engaged_beats_old_heavily_engaged() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author2");
            let old_hit = post_with(conn, &author, 7 * DAY, 100, 0);
            let fresh = post_with(conn, &author, HOUR, 5, 0);

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(
                ids(&response),
                vec![fresh.id.to_proto_id(), old_hit.id.to_proto_id()]
            );
            Ok(())
        });
    }

    /// Each response counts as two stars: 10 responses (score numerator 21) outranks 15 stars (16)
    /// at the same age.
    #[test]
    fn a_response_counts_double() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author3");
            let starred = post_with(conn, &author, 2 * HOUR, 15, 0);
            let discussed = post_with(conn, &author, 2 * HOUR, 0, 10);

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(
                ids(&response),
                vec![discussed.id.to_proto_id(), starred.id.to_proto_id()]
            );
            Ok(())
        });
    }

    /// With no engagement anywhere the `+ 1` still scores every post, so the listing degrades to
    /// newest-first rather than coming back empty.
    #[test]
    fn with_no_engagement_it_is_newest_first() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author4");
            let oldest = post_with(conn, &author, 5 * HOUR, 0, 0);
            let middle = post_with(conn, &author, 3 * HOUR, 0, 0);
            let newest = post_with(conn, &author, HOUR, 0, 0);

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(
                ids(&response),
                vec![
                    newest.id.to_proto_id(),
                    middle.id.to_proto_id(),
                    oldest.id.to_proto_id()
                ]
            );
            Ok(())
        });
    }

    #[test]
    fn excludes_posts_older_than_the_14_day_window() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author5");
            let inside = post_with(conn, &author, 13 * DAY, 0, 0);
            let _outside = post_with(conn, &author, 15 * DAY, 1000, 100);

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(ids(&response), vec![inside.id.to_proto_id()]);
            Ok(())
        });
    }

    /// `published_or_created_before` moves the window (and the "now" ages are measured from) back in
    /// time: "what was popular as of then".
    #[test]
    fn published_or_created_before_scopes_the_window() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author6");
            let recent = post_with(conn, &author, HOUR, 50, 0);
            let earlier = post_with(conn, &author, 20 * DAY, 1, 0);
            let earlier_but_in_window_of_cutoff = post_with(conn, &author, 18 * DAY, 3, 0);

            let response = get_posts(
                GetPostsRequest {
                    published_or_created_before: Some(ago(15 * DAY).to_proto()),
                    ..popular_request()
                },
                &None,
                conn,
            )?;

            let mut actual = ids(&response);
            actual.sort();
            let mut expected = vec![
                earlier.id.to_proto_id(),
                earlier_but_in_window_of_cutoff.id.to_proto_id(),
            ];
            expected.sort();
            assert_eq!(actual, expected);
            assert!(!ids(&response).contains(&recent.id.to_proto_id()));
            Ok(())
        });
    }

    #[test]
    fn author_user_id_narrows_to_that_authors_posts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author7");
            let other = create_user(conn, "popular_author8");
            let mine = post_with(conn, &author, HOUR, 1, 0);
            let _theirs = post_with(conn, &other, HOUR, 500, 0);

            let response = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author.id.to_proto_id()),
                    ..popular_request()
                },
                &None,
                conn,
            )?;

            assert_eq!(ids(&response), vec![mine.id.to_proto_id()]);
            Ok(())
        });
    }

    /// Same visibility rules as every other listing: an anonymous viewer only gets global-public
    /// posts, however popular a server-public one is.
    #[test]
    fn respects_visibility() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author9");
            let public = post_with(conn, &author, HOUR, 1, 0);
            let server_only = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::ServerPublic,
                    created_at: Some(ago(HOUR)),
                    published_at: Some(ago(HOUR)),
                    ..Default::default()
                },
            );
            diesel::update(posts::table.filter(posts::id.eq(server_only.id)))
                .set(posts::unauthenticated_star_count.eq(1000_i64))
                .execute(conn)
                .expect("failed to set engagement");

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(ids(&response), vec![public.id.to_proto_id()]);
            Ok(())
        });
    }

    /// Replies aren't listed (the default `POST` context keeps this a feed of top-level posts), even
    /// popular ones.
    #[test]
    fn excludes_replies() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "popular_author10");
            let top_level = post_with(conn, &author, 2 * HOUR, 0, 0);
            let reply = create_post(
                conn,
                Some(&author),
                PostOpts {
                    visibility: Visibility::GlobalPublic,
                    context: PostContext::Reply,
                    parent_post_id: Some(top_level.id),
                    created_at: Some(ago(HOUR)),
                    published_at: Some(ago(HOUR)),
                    ..Default::default()
                },
            );
            diesel::update(posts::table.filter(posts::id.eq(reply.id)))
                .set(posts::unauthenticated_star_count.eq(1000_i64))
                .execute(conn)
                .expect("failed to set engagement");

            let response = get_posts(popular_request(), &None, conn)?;

            assert_eq!(ids(&response), vec![top_level.id.to_proto_id()]);
            Ok(())
        });
    }
}

mod excluded_author_user_ids {
    use super::*;

    fn public_post(
        conn: &mut crate::db_connection::PgPooledConnection,
        author: &crate::models::User,
        title: &str,
    ) -> crate::models::Post {
        create_post(
            conn,
            Some(author),
            PostOpts {
                visibility: Visibility::GlobalPublic,
                title: Some(title.to_string()),
                ..Default::default()
            },
        )
    }

    #[test]
    fn default_listing_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let kept = create_user(conn, "excl_posts_kept");
            let dropped = create_user(conn, "excl_posts_dropped");
            let kept_post = public_post(conn, &kept, "kept excl post");
            let dropped_post = public_post(conn, &dropped, "dropped excl post");

            let all = get_posts(GetPostsRequest::default(), &None, conn)?;
            assert!(ids(&all).contains(&dropped_post.id.to_proto_id()));

            let response = get_posts(
                GetPostsRequest {
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert!(ids(&response).contains(&kept_post.id.to_proto_id()));
            assert!(!ids(&response).contains(&dropped_post.id.to_proto_id()));
            Ok(())
        });
    }

    #[test]
    fn several_authors_can_be_excluded_at_once() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let kept = create_user(conn, "excl_posts_multi_kept");
            let dropped1 = create_user(conn, "excl_posts_multi_dropped1");
            let dropped2 = create_user(conn, "excl_posts_multi_dropped2");
            let kept_post = public_post(conn, &kept, "kept multi");
            let dropped_post1 = public_post(conn, &dropped1, "dropped multi 1");
            let dropped_post2 = public_post(conn, &dropped2, "dropped multi 2");

            let response = get_posts(
                GetPostsRequest {
                    excluded_author_user_ids: vec![
                        dropped1.id.to_proto_id(),
                        dropped2.id.to_proto_id(),
                    ],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            let result_ids = ids(&response);
            assert!(result_ids.contains(&kept_post.id.to_proto_id()));
            assert!(!result_ids.contains(&dropped_post1.id.to_proto_id()));
            assert!(!result_ids.contains(&dropped_post2.id.to_proto_id()));
            Ok(())
        });
    }

    #[test]
    fn text_search_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let kept = create_user(conn, "excl_search_kept");
            let dropped = create_user(conn, "excl_search_dropped");
            let kept_post = public_post(conn, &kept, "quuxexcl from kept");
            let dropped_post = public_post(conn, &dropped, "quuxexcl from dropped");

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::TextSearch as i32,
                    search_text: Some("quuxexcl".to_string()),
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&response), vec![kept_post.id.to_proto_id()]);
            assert!(!ids(&response).contains(&dropped_post.id.to_proto_id()));
            Ok(())
        });
    }

    #[test]
    fn recently_popular_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let kept = create_user(conn, "excl_popular_kept");
            let dropped = create_user(conn, "excl_popular_dropped");
            let kept_post = public_post(conn, &kept, "kept popular");
            let dropped_post = public_post(conn, &dropped, "dropped popular");

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::RecentlyPopularPosts as i32,
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert!(ids(&response).contains(&kept_post.id.to_proto_id()));
            assert!(!ids(&response).contains(&dropped_post.id.to_proto_id()));
            Ok(())
        });
    }

    #[test]
    fn following_listing_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let viewer = create_user(conn, "excl_follow_viewer");
            let kept = create_user(conn, "excl_follow_kept");
            let dropped = create_user(conn, "excl_follow_dropped");
            create_follow(conn, &viewer, &kept);
            create_follow(conn, &viewer, &dropped);
            let kept_post = public_post(conn, &kept, "kept followed");
            let dropped_post = public_post(conn, &dropped, "dropped followed");

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::FollowingPosts as i32,
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &Some(&viewer),
                conn,
            )?;
            assert_eq!(ids(&response), vec![kept_post.id.to_proto_id()]);
            assert!(!ids(&response).contains(&dropped_post.id.to_proto_id()));
            Ok(())
        });
    }

    #[test]
    fn author_listing_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let author = create_user(conn, "excl_author_listing");
            let post = public_post(conn, &author, "author listing post");

            // Excluding the very author asked for leaves nothing...
            let excluded = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author.id.to_proto_id()),
                    excluded_author_user_ids: vec![author.id.to_proto_id()],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert!(excluded.posts.is_empty());

            // ...while excluding someone else changes nothing.
            let other = create_user(conn, "excl_author_listing_other");
            let kept = get_posts(
                GetPostsRequest {
                    author_user_id: Some(author.id.to_proto_id()),
                    excluded_author_user_ids: vec![other.id.to_proto_id()],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&kept), vec![post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn my_groups_listing_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let member = create_user(conn, "excl_mygroups_member");
            let kept = create_user(conn, "excl_mygroups_kept");
            let dropped = create_user(conn, "excl_mygroups_dropped");
            let group = create_group(conn, "excl-mygroups-group", GroupOpts::default());
            create_membership(
                conn,
                &member,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![],
            );
            let kept_post = public_post(conn, &kept, "kept my groups");
            let dropped_post = public_post(conn, &dropped, "dropped my groups");
            create_group_post(conn, &kept_post, &group, &kept, Moderation::Approved);
            create_group_post(conn, &dropped_post, &group, &dropped, Moderation::Approved);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::MyGroupsPosts as i32,
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &Some(&member),
                conn,
            )?;
            assert_eq!(ids(&response), vec![kept_post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn group_listing_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let kept = create_user(conn, "excl_group_kept");
            let dropped = create_user(conn, "excl_group_dropped");
            let group = create_group(
                conn,
                "excl-group-public",
                GroupOpts {
                    non_member_permissions: vec![Permission::ViewPosts],
                },
            );
            let kept_post = public_post(conn, &kept, "kept group");
            let dropped_post = public_post(conn, &dropped, "dropped group");
            create_group_post(conn, &kept_post, &group, &kept, Moderation::Approved);
            create_group_post(conn, &dropped_post, &group, &dropped, Moderation::Approved);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPosts as i32,
                    group_id: Some(group.id.to_proto_id()),
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &None,
                conn,
            )?;
            assert_eq!(ids(&response), vec![kept_post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn group_pending_moderation_listing_omits_excluded_authors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let kept = create_user(conn, "excl_pending_kept");
            let dropped = create_user(conn, "excl_pending_dropped");
            let moderator = create_user(conn, "excl_pending_mod");
            let group = create_group(conn, "excl-pending-group", GroupOpts::default());
            create_membership(
                conn,
                &moderator,
                &group,
                Moderation::Approved,
                Moderation::Approved,
                vec![Permission::ViewPosts],
            );
            let kept_post = public_post(conn, &kept, "kept pending");
            let dropped_post = public_post(conn, &dropped, "dropped pending");
            create_group_post(conn, &kept_post, &group, &kept, Moderation::Pending);
            create_group_post(conn, &dropped_post, &group, &dropped, Moderation::Pending);

            let response = get_posts(
                GetPostsRequest {
                    listing_type: PostListingType::GroupPostsPendingModeration as i32,
                    group_id: Some(group.id.to_proto_id()),
                    excluded_author_user_ids: vec![dropped.id.to_proto_id()],
                    ..Default::default()
                },
                &Some(&moderator),
                conn,
            )?;
            assert_eq!(ids(&response), vec![kept_post.id.to_proto_id()]);
            Ok(())
        });
    }

    #[test]
    fn malformed_id_is_invalid_argument() {
        let mut conn = test_conn();
        conn.test_transaction::<_, Status, _>(|conn| {
            let result = get_posts(
                GetPostsRequest {
                    excluded_author_user_ids: vec!["not a real id!".to_string()],
                    ..Default::default()
                },
                &None,
                conn,
            );
            assert_eq!(result.unwrap_err().code(), Code::InvalidArgument);
            Ok(())
        });
    }
}
