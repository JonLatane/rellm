//! Specs for `logic::market_fulfillment::fulfill_purchase` -- pure DB logic (no Stripe round-trip
//! needed, unlike `web::stripe_webhook`/`logic::market_renewal`), so unlike those it's exercised
//! directly here rather than being out of scope for unit tests.

use diesel::*;

use crate::logic::fulfill_purchase;
use crate::marshaling::{ToProtoId, ToProtoPermissions};
use crate::models;
use crate::protos::*;
use crate::schema::{ai_provider_grants, ai_providers, users};
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

#[test]
fn media_storage_fulfillment_sets_the_buyers_allocation_outright() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let buyer = create_user(conn, "mkt_fulfill_media");
        // A pre-existing, different limit -- fulfillment should replace it, not add to it.
        diesel::update(users::table.filter(users::id.eq(buyer.id)))
            .set(users::media_storage_limit_bytes.eq(Some(1_048_576_i64))) // 1MB
            .execute(conn)
            .unwrap();

        let details = serde_json::to_value(MediaStoragePurchaseDetails {
            allocation_bytes: 5_368_709_120, // 5GB
        })
        .unwrap();
        fulfill_purchase(PurchaseType::MediaStorage, buyer.id, &details, conn)?;

        let updated_buyer = models::get_user(buyer.id, conn)?;
        assert_eq!(updated_buyer.media_storage_limit_bytes, Some(5_368_709_120));

        Ok(())
    });
}

#[test]
fn ai_grants_fulfillment_resets_the_buyers_token_balance_rather_than_adding_to_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "mkt_fulfill_ai_owner");
        let buyer = create_user(conn, "mkt_fulfill_ai_buyer");
        let provider = insert_into(ai_providers::table)
            .values(&models::NewAIProvider {
                user_id: owner.id,
                name: "Test Provider".to_string(),
                configuration: serde_json::json!({}),
            })
            .get_result::<models::AIProvider>(conn)
            .expect("failed to insert test AI provider");

        // A pre-existing grant with tokens left over from a prior period -- the new purchase
        // should reset this, not add to it (same "reset, don't add" semantics a renewal needs).
        insert_into(ai_provider_grants::table)
            .values(&models::NewAIProviderGrant {
                ai_provider_id: provider.id,
                grantee_id: buyer.id,
                model_names: vec!["gemini-2.5-flash-image".to_string()],
                tokens_remaining: 100,
                overage: 0,
            })
            .execute(conn)
            .expect("failed to seed existing AI provider grant");

        let details = serde_json::to_value(AiGrantPurchaseDetails {
            ai_provider_id: provider.id.to_proto_id(),
            model_names: vec!["gemini-2.5-flash-image".to_string()],
            tokens: 500_000,
        })
        .unwrap();
        fulfill_purchase(PurchaseType::AiGrants, buyer.id, &details, conn)?;

        let grants = ai_provider_grants::table
            .filter(ai_provider_grants::ai_provider_id.eq(provider.id))
            .filter(ai_provider_grants::grantee_id.eq(buyer.id))
            .load::<models::AIProviderGrant>(conn)
            .expect("failed to load test AI provider grants");
        assert_eq!(grants.len(), 1, "should upsert in place, not add a second row");
        assert_eq!(grants[0].tokens_remaining, 500_000);

        Ok(())
    });
}

#[test]
fn rellm_hosting_fulfillment_is_a_no_op() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let buyer = create_user(conn, "mkt_fulfill_hosting");
        let details = serde_json::to_value(RellmHostingPurchaseDetails {
            db_size_bytes: 0,
            minio_size_bytes: 0,
            domain: "example.rellm.org".to_string(),
            contact_email: "buyer@example.com".to_string(),
            additional_information: "".to_string(),
        })
        .unwrap();

        // Deliberately not automated -- see `PurchaseType.PURCHASE_TYPE_RELLM_HOSTING`'s own
        // proto doc. This just confirms the no-op arm doesn't error and genuinely touches nothing.
        fulfill_purchase(PurchaseType::RellmHosting, buyer.id, &details, conn)?;

        let unchanged_buyer = models::get_user(buyer.id, conn)?;
        assert_eq!(unchanged_buyer.media_storage_limit_bytes, None);
        assert_eq!(
            unchanged_buyer.permissions.to_proto_permissions(),
            buyer.permissions.to_proto_permissions(),
            "fulfillment must not touch the buyer's permissions at all"
        );

        Ok(())
    });
}
