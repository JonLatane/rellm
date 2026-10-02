//! Specs for the denormalized `users` counters (`follower_count`, `following_count`,
//! `friend_count`, `post_count`, `response_count`, `event_count`, `occasion_count`) --
//! `backend/src/logic/user_counts.rs` defines what a correct value looks like, and this file
//! checks the RPC call sites that are supposed to keep them in sync actually do, plus
//! `update_all_counts` (the full recompute `bin/update_user_counts.rs` runs hourly).
//!
//! Regression coverage in particular for two bugs `logic::users::user_counts` fixed:
//! `create_post` used to bump the *wrong* counter for replies vs. top-level posts (see
//! `create_post_increments_post_count_and_reply_increments_response_count`), and `create_event`
//! used to bump `event_count` once per *occasion* rather than once per event (see
//! `create_event_sets_event_count_once_and_occasion_count_per_occasion`).

use std::time::{Duration, SystemTime};

use diesel::*;
use tonic::Status;

use crate::logic::update_all_counts;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{create_event, create_follow, create_post, delete_event, delete_post};
use crate::tests::factories::*;

fn new_top_level_post() -> Post {
    Post {
        title: Some("Test Post".to_string()),
        content: Some("Test content".to_string()),
        visibility: Visibility::GlobalPublic as i32,
        ..Default::default()
    }
}

fn new_event(num_occasions: usize) -> Event {
    let now = SystemTime::now();
    let starts_at = Some((now + Duration::from_secs(3600)).to_proto());
    let ends_at = Some((now + Duration::from_secs(7200)).to_proto());
    Event {
        post: Some(Post {
            title: Some("Test Event".to_string()),
            visibility: Visibility::GlobalPublic as i32,
            ..Default::default()
        }),
        occasions: (0..num_occasions)
            .map(|_| Occasion {
                starts_at: starts_at.clone(),
                ends_at: ends_at.clone(),
                ..Default::default()
            })
            .collect(),
        ..Default::default()
    }
}

#[test]
fn create_post_increments_post_count_and_reply_increments_response_count() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "uct_author1");
        let author = grant_permissions(
            conn,
            &author,
            vec![Permission::CreatePosts, Permission::PublishPostsGlobally],
        );

        let post = create_post(new_top_level_post(), &author, conn)?;
        let author = models::get_user(author.id, conn)?;
        assert_eq!(author.post_count, 1);
        assert_eq!(author.response_count, 0);

        let replier = create_user(conn, "uct_replier1");
        let replier = grant_permissions(
            conn,
            &replier,
            vec![Permission::CreatePosts, Permission::PublishPostsGlobally],
        );
        create_post(
            Post {
                content: Some("A reply".to_string()),
                reply_to_post_id: Some(post.id),
                ..Default::default()
            },
            &replier,
            conn,
        )?;
        let replier = models::get_user(replier.id, conn)?;
        assert_eq!(replier.post_count, 0);
        assert_eq!(replier.response_count, 1);

        Ok(())
    });
}

#[test]
fn delete_post_decrements_the_authors_counts() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "uct_author2");
        let author = grant_permissions(
            conn,
            &author,
            vec![Permission::CreatePosts, Permission::PublishPostsGlobally],
        );

        let post = create_post(new_top_level_post(), &author, conn)?;
        delete_post(
            Post {
                id: post.id,
                ..Default::default()
            },
            &author,
            conn,
        )?;
        let author = models::get_user(author.id, conn)?;
        assert_eq!(author.post_count, 0);

        Ok(())
    });
}

#[test]
fn mutual_follow_sets_friend_follower_and_following_counts_for_both_users() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let user_a = create_user(conn, "uct_friend_a");
        let user_b = create_user(conn, "uct_friend_b");

        create_follow(
            Follow {
                user_id: user_a.id.to_proto_id(),
                target_user_id: user_b.id.to_proto_id(),
                ..Default::default()
            },
            &user_a,
            conn,
        )?;
        // Only a one-way follow so far -- not friends yet.
        let a = models::get_user(user_a.id, conn)?;
        let b = models::get_user(user_b.id, conn)?;
        assert_eq!(a.following_count, 1);
        assert_eq!(a.friend_count, 0);
        assert_eq!(b.follower_count, 1);
        assert_eq!(b.friend_count, 0);

        create_follow(
            Follow {
                user_id: user_b.id.to_proto_id(),
                target_user_id: user_a.id.to_proto_id(),
                ..Default::default()
            },
            &user_b,
            conn,
        )?;
        let a = models::get_user(user_a.id, conn)?;
        let b = models::get_user(user_b.id, conn)?;
        assert_eq!(a.friend_count, 1);
        assert_eq!(a.follower_count, 1);
        assert_eq!(b.friend_count, 1);
        assert_eq!(b.following_count, 1);

        Ok(())
    });
}

#[test]
fn create_event_sets_event_count_once_and_occasion_count_per_occasion() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "uct_event_author1");
        let author = grant_permissions(
            conn,
            &author,
            vec![Permission::CreateEvents, Permission::PublishEventsGlobally],
        );

        create_event(new_event(3), &author, conn)?;
        let author = models::get_user(author.id, conn)?;
        // Regression check: previously event_count was bumped once per occasion (3), not once
        // per event (1).
        assert_eq!(author.event_count, 1);
        assert_eq!(author.occasion_count, 3);

        Ok(())
    });
}

#[test]
fn delete_event_clears_event_and_occasion_counts() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "uct_event_author2");
        let author = grant_permissions(
            conn,
            &author,
            vec![Permission::CreateEvents, Permission::PublishEventsGlobally],
        );

        let event = create_event(new_event(2), &author, conn)?;
        delete_event(
            Event {
                post: Some(Post {
                    id: event.post.as_ref().unwrap().id.clone(),
                    ..Default::default()
                }),
                ..Default::default()
            },
            &author,
            conn,
        )?;
        let author = models::get_user(author.id, conn)?;
        assert_eq!(author.event_count, 0);
        assert_eq!(author.occasion_count, 0);

        Ok(())
    });
}

#[test]
fn update_all_counts_corrects_manually_drifted_counts() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let author = create_user(conn, "uct_recompute1");
        let author = grant_permissions(
            conn,
            &author,
            vec![Permission::CreatePosts, Permission::PublishPostsGlobally],
        );
        create_post(new_top_level_post(), &author, conn)?;

        // Simulate drift -- e.g. a cascading delete that bypassed the RPC-level count updates.
        diesel::update(crate::schema::users::table)
            .filter(crate::schema::users::id.eq(author.id))
            .set((
                crate::schema::users::post_count.eq(99),
                crate::schema::users::follower_count.eq(99),
            ))
            .execute(conn)
            .unwrap();

        update_all_counts(author.id, conn).unwrap();
        let author = models::get_user(author.id, conn)?;
        assert_eq!(author.post_count, 1);
        assert_eq!(author.follower_count, 0);

        Ok(())
    });
}
