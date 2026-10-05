//! Specs for `update_user`'s `VIEW_SERVER_LOGS` handling: like `EDIT_CLUSTER_SETTINGS` and
//! `EDIT_SERVER_MEDIA_ALLOCATION`, it's deliberately never settable via `UpdateUser` -- always
//! carried forward from whatever the target user already had, regardless of what the request asks
//! for (grant or revoke). See that permission's own proto doc.

use diesel::*;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::update_user;
use crate::tests::factories::*;

#[test]
fn update_user_cannot_grant_view_server_logs() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let target = create_user(conn, "usl_grant_target");
        let admin = create_user(conn, "usl_grant_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = target.to_proto(&None, &None, None, &None, None);
        request.permissions = vec![Permission::ViewServerLogs as i32];

        let updated = update_user(request, &admin, conn).expect("admin update should succeed");

        assert!(
            !updated.permissions.contains(&(Permission::ViewServerLogs as i32)),
            "VIEW_SERVER_LOGS must not be grantable via UpdateUser, even by an admin"
        );

        Ok(())
    });
}

#[test]
fn update_user_cannot_revoke_view_server_logs() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let target = create_user(conn, "usl_revoke_target");
        let target = grant_permissions(conn, &target, vec![Permission::ViewServerLogs]);
        let admin = create_user(conn, "usl_revoke_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = target.to_proto(&None, &None, None, &None, None);
        request.permissions = vec![]; // Requests revoking everything, including the held permission.

        let updated = update_user(request, &admin, conn).expect("admin update should succeed");

        assert!(
            updated.permissions.contains(&(Permission::ViewServerLogs as i32)),
            "VIEW_SERVER_LOGS must survive an UpdateUser call regardless of what the request asked for"
        );

        Ok(())
    });
}
