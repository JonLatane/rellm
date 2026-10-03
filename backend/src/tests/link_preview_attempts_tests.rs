//! Specs for `posts_needing_previews`' ordering (newest first only for big backlogs) and attempt cap (so a permanently
//! failing link can't hog the `generate_link_preview_images` batch) and the SSRF address filter.

use std::net::IpAddr;

use diesel::prelude::*;

use crate::logic::{
    clear_failed_attempts, is_forbidden_ip, posts_needing_previews, record_failed_attempt,
    MAX_PREVIEW_ATTEMPTS, NEWEST_FIRST_BACKLOG_THRESHOLD,
};
use crate::schema::posts;
use crate::tests::factories::*;

fn linked_post(conn: &mut crate::db_connection::PgPooledConnection, user: &crate::models::User) -> i64 {
    let post = create_post(conn, Some(user), PostOpts::default());
    diesel::update(posts::table.filter(posts::id.eq(post.id)))
        .set(posts::link.eq(Some("https://example.com/page".to_string())))
        .execute(conn)
        .unwrap();
    post.id
}

fn needing(conn: &mut crate::db_connection::PgPooledConnection) -> Vec<i64> {
    posts_needing_previews(1000, conn)
        .unwrap()
        .into_iter()
        .map(|p| p.id)
        .collect()
}

#[test]
fn failed_posts_are_dropped_at_the_cap_and_small_backlogs_go_oldest_first() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "lpa_user");
        let broken = linked_post(conn, &user);
        let healthy = linked_post(conn, &user);

        assert_eq!(needing(conn), vec![broken, healthy], "small backlogs go oldest first");

        record_failed_attempt(broken, conn);
        assert_eq!(needing(conn), vec![broken, healthy], "a failed attempt doesn't change the order");

        for _ in 1..MAX_PREVIEW_ATTEMPTS {
            record_failed_attempt(broken, conn);
        }
        assert_eq!(needing(conn), vec![healthy], "capped posts are no longer selected");

        clear_failed_attempts(broken, conn);
        assert_eq!(needing(conn), vec![broken, healthy]);
        Ok(())
    });
}

#[test]
fn big_backlogs_go_newest_first() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "lpa_backlog_user");
        let mut ids: Vec<i64> = (0..=NEWEST_FIRST_BACKLOG_THRESHOLD)
            .map(|_| linked_post(conn, &user))
            .collect();
        ids.reverse();
        assert_eq!(needing(conn), ids, "more than the threshold -> highest id first");

        // Dropping back to the threshold flips to oldest first.
        let newest = ids.remove(0);
        diesel::update(posts::table.filter(posts::id.eq(newest)))
            .set(posts::media_generated.eq(true))
            .execute(conn)
            .unwrap();
        ids.reverse();
        assert_eq!(needing(conn), ids, "at the threshold -> lowest id first");
        Ok(())
    });
}

#[test]
fn forbids_internal_addresses_only() {
    for bad in ["127.0.0.1", "10.1.2.3", "192.168.0.1", "172.16.0.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "::1", "fe80::1", "fd00::1", "::ffff:10.0.0.1"] {
        assert!(is_forbidden_ip(bad.parse::<IpAddr>().unwrap()), "{bad} should be forbidden");
    }
    for ok in ["8.8.8.8", "93.184.216.34", "2606:4700:4700::1111"] {
        assert!(!is_forbidden_ip(ok.parse::<IpAddr>().unwrap()), "{ok} should be allowed");
    }
}
