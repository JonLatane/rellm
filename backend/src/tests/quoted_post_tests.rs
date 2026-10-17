//! Specs for `Post.quoted_post_id`/`quoted_post`: only a top-level `POST` may quote another
//! post, the quoted post has to be visible to the quoting author, and `quoted_post` is only
//! hydrated for viewers who can themselves see the quoted post.

use diesel::Connection;
use tonic::{Code, Status};

use crate::protos::*;
use crate::rpcs::{create_post, delete_post, get_posts, update_post};
use crate::tests::factories::*;

fn new_post(content: &str, visibility: Visibility) -> Post {
    Post {
        title: Some("Test Post".to_string()),
        content: Some(content.to_string()),
        visibility: visibility as i32,
        ..Default::default()
    }
}

fn quoting(content: &str, quoted_post_id: &str) -> Post {
    Post {
        quoted_post_id: Some(quoted_post_id.to_string()),
        ..new_post(content, Visibility::GlobalPublic)
    }
}

fn permissions() -> Vec<Permission> {
    vec![
        Permission::CreatePosts,
        Permission::PublishPostsGlobally,
        Permission::PublishPostsLocally,
    ]
}

#[test]
fn creating_a_post_that_quotes_a_visible_post_returns_it_hydrated() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author1");
        let author = grant_permissions(conn, &author, permissions());
        let quoted = create_post(new_post("original", Visibility::GlobalPublic), &author, conn)?;

        let quote = create_post(quoting("my take", &quoted.id), &author, conn)?;

        assert_eq!(quote.quoted_post_id, Some(quoted.id.clone()));
        assert_eq!(
            quote.quoted_post.map(|p| (p.id, p.content)),
            Some((quoted.id, Some("original".to_string())))
        );
        Ok(())
    });
}

#[test]
fn quoted_post_is_hydrated_one_level_deep_on_get_posts() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author2");
        let author = grant_permissions(conn, &author, permissions());
        let first = create_post(new_post("first", Visibility::GlobalPublic), &author, conn)?;
        let second = create_post(quoting("second", &first.id), &author, conn)?;
        let third = create_post(quoting("third", &second.id), &author, conn)?;

        let fetched = get_posts(
            GetPostsRequest {
                post_id: Some(third.id.clone()),
                ..Default::default()
            },
            &None,
            conn,
        )?
        .posts
        .remove(0);

        let quoted = fetched.quoted_post.expect("second should be hydrated");
        assert_eq!(quoted.content, Some("second".to_string()));
        assert_eq!(quoted.quoted_post_id, Some(first.id));
        assert!(quoted.quoted_post.is_none());
        Ok(())
    });
}

#[test]
fn a_reply_cannot_quote_a_post() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author3");
        let author = grant_permissions(conn, &author, permissions());
        let parent = create_post(new_post("parent", Visibility::GlobalPublic), &author, conn)?;

        let result = create_post(
            Post {
                reply_to_post_id: Some(parent.id.clone()),
                quoted_post_id: Some(parent.id),
                content: Some("a reply".to_string()),
                ..Default::default()
            },
            &author,
            conn,
        );

        assert_eq!(result.unwrap_err().code(), Code::InvalidArgument);
        Ok(())
    });
}

#[test]
fn cannot_quote_a_post_the_author_cannot_see() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "qpt_owner4");
        let owner = grant_permissions(conn, &owner, permissions());
        let private = create_post(new_post("secret", Visibility::Private), &owner, conn)?;
        let other = create_user(conn, "qpt_other4");
        let other = grant_permissions(conn, &other, permissions());

        let result = create_post(quoting("sneaky", &private.id), &other, conn);

        assert_eq!(result.unwrap_err().code(), Code::NotFound);
        Ok(())
    });
}

#[test]
fn quoted_post_is_not_hydrated_for_a_viewer_who_cannot_see_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author5");
        let author = grant_permissions(conn, &author, permissions());
        let private = create_post(new_post("secret", Visibility::Private), &author, conn)?;
        let quote = create_post(quoting("public take", &private.id), &author, conn)?;

        let as_author = get_posts(
            GetPostsRequest {
                post_id: Some(quote.id.clone()),
                ..Default::default()
            },
            &Some(&author),
            conn,
        )?
        .posts
        .remove(0);
        let as_anonymous = get_posts(
            GetPostsRequest {
                post_id: Some(quote.id.clone()),
                ..Default::default()
            },
            &None,
            conn,
        )?
        .posts
        .remove(0);

        assert!(as_author.quoted_post.is_some());
        assert!(as_anonymous.quoted_post.is_none());
        assert_eq!(as_anonymous.quoted_post_id, Some(private.id));
        Ok(())
    });
}

#[test]
fn updating_a_post_sets_and_clears_its_quote() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author6");
        let author = grant_permissions(conn, &author, permissions());
        let quoted = create_post(new_post("original", Visibility::GlobalPublic), &author, conn)?;
        let post = create_post(new_post("plain", Visibility::GlobalPublic), &author, conn)?;

        let with_quote = update_post(
            Post {
                id: post.id.clone(),
                quoted_post_id: Some(quoted.id.clone()),
                ..new_post("plain", Visibility::GlobalPublic)
            },
            &author,
            conn,
        )?;
        assert_eq!(with_quote.quoted_post_id, Some(quoted.id));
        assert!(with_quote.quoted_post.is_some());

        let without_quote = update_post(
            Post {
                id: post.id,
                ..new_post("plain", Visibility::GlobalPublic)
            },
            &author,
            conn,
        )?;
        assert_eq!(without_quote.quoted_post_id, None);
        Ok(())
    });
}

#[test]
fn cannot_update_a_post_to_quote_itself_or_a_reply_to_quote_anything() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author7");
        let author = grant_permissions(conn, &author, permissions());
        let post = create_post(new_post("post", Visibility::GlobalPublic), &author, conn)?;
        let reply = create_post(
            Post {
                reply_to_post_id: Some(post.id.clone()),
                content: Some("reply".to_string()),
                ..Default::default()
            },
            &author,
            conn,
        )?;

        let self_quote = update_post(
            Post {
                id: post.id.clone(),
                quoted_post_id: Some(post.id.clone()),
                ..new_post("post", Visibility::GlobalPublic)
            },
            &author,
            conn,
        );
        let reply_quote = update_post(
            Post {
                id: reply.id,
                quoted_post_id: Some(post.id),
                content: Some("reply".to_string()),
                visibility: Visibility::GlobalPublic as i32,
                ..Default::default()
            },
            &author,
            conn,
        );

        assert_eq!(self_quote.unwrap_err().code(), Code::InvalidArgument);
        assert_eq!(reply_quote.unwrap_err().code(), Code::InvalidArgument);
        Ok(())
    });
}

#[test]
fn deleting_the_quoted_post_clears_the_quote() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "qpt_author8");
        let author = grant_permissions(conn, &author, permissions());
        let quoted = create_post(new_post("original", Visibility::GlobalPublic), &author, conn)?;
        let quote = create_post(quoting("take", &quoted.id), &author, conn)?;

        delete_post(
            Post {
                id: quoted.id,
                ..Default::default()
            },
            &author,
            conn,
        )?;

        let fetched = get_posts(
            GetPostsRequest {
                post_id: Some(quote.id),
                ..Default::default()
            },
            &None,
            conn,
        )?
        .posts
        .remove(0);
        assert_eq!(fetched.quoted_post_id, None);
        assert!(fetched.quoted_post.is_none());
        Ok(())
    });
}
