//! Specs for `logic::market_fulfillment::fulfill_purchase` -- pure DB logic (no Stripe round-trip
//! needed, unlike `web::stripe_webhook`/`logic::market_renewal`), so unlike those it's exercised
//! directly here rather than being out of scope for unit tests.

use diesel::Connection;

use crate::logic::fulfill_purchase;
use crate::marshaling::ToProtoPermissions;
use crate::protos::*;
use crate::tests::factories::*;

#[test]
fn permissions_access_grants_permissions_additively_without_duplicating_or_dropping_existing_ones() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "mkt_fulfill_perms");
        let user = grant_permissions(conn, &user, vec![Permission::ViewUsers]);
        assert_eq!(user.permissions.to_proto_permissions(), vec![Permission::ViewUsers]);

        // Grants overlap with the buyer's existing `ViewUsers` (should not duplicate it) and add
        // two new ones.
        let details = serde_json::to_value(PermissionsAccessPurchaseDetails {
            permissions: vec![
                Permission::ViewUsers as i32,
                Permission::SyncEventsToFacebook as i32,
                Permission::SyncPostsToFacebook as i32,
            ],
        })
        .unwrap();
        fulfill_purchase(PurchaseType::PermissionsAccess, user.id, &details, conn)?;

        let mut updated = crate::models::get_user(user.id, conn)?.permissions.to_proto_permissions();
        updated.sort_by_key(|p| *p as i32);
        let mut expected = vec![
            Permission::ViewUsers,
            Permission::SyncEventsToFacebook,
            Permission::SyncPostsToFacebook,
        ];
        expected.sort_by_key(|p| *p as i32);
        assert_eq!(updated, expected);

        Ok(())
    });
}
