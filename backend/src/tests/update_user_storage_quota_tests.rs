//! Specs for `update_user`'s `media_storage_limit_bytes` handling: admin-only, and untouched by
//! a self-update.

use diesel::prelude::*;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::update_user;
use crate::schema::users;
use crate::tests::factories::*;

fn media_storage_limit_bytes(conn: &mut crate::db_connection::PgPooledConnection, user_id: i64) -> Option<i64> {
    users::table
        .select(users::media_storage_limit_bytes)
        .filter(users::id.eq(user_id))
        .first(conn)
        .unwrap()
}

#[test]
fn admin_can_set_another_users_storage_quota() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let target = create_user(conn, "usq_target");
        let admin = create_user(conn, "usq_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = target.to_proto(&None, &None, None, None);
        request.media_storage_limit_bytes = Some(5_000_000_000);

        update_user(request, &admin, conn).expect("admin update should succeed");

        assert_eq!(media_storage_limit_bytes(conn, target.id), Some(5_000_000_000));

        Ok(())
    });
}

#[test]
fn admin_can_clear_a_storage_quota_back_to_unlimited() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let target = create_user(conn, "usq_clear");
        let admin = create_user(conn, "usq_admin_clear");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = target.to_proto(&None, &None, None, None);
        request.media_storage_limit_bytes = Some(1_000_000);
        update_user(request.clone(), &admin, conn).expect("first update should succeed");
        assert_eq!(media_storage_limit_bytes(conn, target.id), Some(1_000_000));

        let mut clear_request = target.to_proto(&None, &None, None, None);
        clear_request.media_storage_limit_bytes = None;
        update_user(clear_request, &admin, conn).expect("clearing update should succeed");
        assert_eq!(media_storage_limit_bytes(conn, target.id), None);

        Ok(())
    });
}

#[test]
fn self_update_cannot_change_own_storage_quota() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "usq_self");

        let mut request = user.to_proto(&None, &None, None, None);
        request.media_storage_limit_bytes = Some(999);

        update_user(request, &user, conn).expect("self update should succeed");

        assert_eq!(
            media_storage_limit_bytes(conn, user.id),
            None,
            "a non-admin self-update must not be able to set their own quota"
        );

        Ok(())
    });
}

#[test]
fn non_admin_moderator_cannot_change_someone_elses_storage_quota() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let target = create_user(conn, "usq_mod_target");
        let moderator = create_user(conn, "usq_moderator");
        let moderator = grant_permissions(conn, &moderator, vec![Permission::ModerateUsers]);

        let mut request = target.to_proto(&None, &None, None, None);
        request.media_storage_limit_bytes = Some(123);

        // A plain (non-admin) MODERATEUSERS holder may still update someone else's `moderation`
        // (see update_user.rs's `admin || moderator` branch), but the whole
        // username/bio/permissions/quota block above it is admin-or-self only -- so this
        // succeeds without touching the quota at all.
        update_user(request, &moderator, conn).expect("moderator update should still succeed");

        assert_eq!(media_storage_limit_bytes(conn, target.id), None);

        Ok(())
    });
}
