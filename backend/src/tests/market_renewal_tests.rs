//! Specs for `logic::market_renewal::terminate_subscriptions_of_type` -- the delayed
//! entitlement-revocation half of subscription cancellation (see that function's own doc, and
//! `MarketSubscription.canceled_at`/`service_terminated_at`'s proto docs). Exercised directly here
//! (not through the `CancelMarketSubscription` RPC, which only ever sets `canceled_at`) since it's
//! pure DB logic with no Stripe round-trip needed, same rationale as `market_fulfillment_tests`.
//!
//! Lives under `src/tests/` (not inlined into `src/logic/market_renewal.rs` itself) because
//! `crate::tests::factories` is only reachable from files under `src/tests/` -- `src/logic/` is
//! compiled into both the `rellm` lib AND the `rellm` bin crate roots, but only `lib.rs` declares
//! `mod tests;`, so an inline `#[cfg(test)] mod tests` inside `src/logic/market_renewal.rs` would
//! fail to compile for the bin target.

use std::time::{Duration, SystemTime};

use diesel::*;

use crate::logic::{renew_subscriptions_of_type, terminate_subscriptions_of_type};
use crate::marshaling::{ToDbId, ToProtoPermissions, ToStringPurchasePeriod, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::rpcs::create_market_product;
use crate::schema::market_subscriptions;
use crate::tests::factories::*;

fn media_storage_product(admin: &models::User, conn: &mut crate::db_connection::PgPooledConnection) -> MarketProduct {
    create_market_product(
        MarketProduct {
            id: String::new(),
            r#type: PurchaseType::MediaStorage as i32,
            period: PurchasePeriod::Monthly as i32,
            amount: 500,
            currency: 840,
            created_at: None,
            delisted_at: None,
            available_count: 0,
            sold_count: 0,
            details: Some(market_product::Details::MediaStorageSubscriptionDetails(
                MediaStorageSubscriptionDetails {
                    allocation_bytes: 1_073_741_824, // 1GB
                },
            )),
        },
        admin,
        conn,
    )
    .expect("create should succeed")
}

fn ai_grants_product(admin: &models::User, conn: &mut crate::db_connection::PgPooledConnection) -> MarketProduct {
    create_market_product(
        MarketProduct {
            id: String::new(),
            r#type: PurchaseType::AiGrants as i32,
            period: PurchasePeriod::Monthly as i32,
            amount: 500,
            currency: 840,
            created_at: None,
            delisted_at: None,
            available_count: 0,
            sold_count: 0,
            details: Some(market_product::Details::AiGrantSubscriptionDetails(AiGrantSubscriptionDetails {
                ai_provider_id: "some-provider".to_string(),
                model_names: vec!["gemini-2.5-flash-image".to_string()],
                tokens: 100_000,
            })),
        },
        admin,
        conn,
    )
    .expect("create should succeed")
}

fn permissions_access_product(
    admin: &models::User,
    permissions: Vec<Permission>,
    conn: &mut crate::db_connection::PgPooledConnection,
) -> MarketProduct {
    create_market_product(
        MarketProduct {
            id: String::new(),
            r#type: PurchaseType::PermissionsAccess as i32,
            period: PurchasePeriod::Monthly as i32,
            amount: 500,
            currency: 840,
            created_at: None,
            delisted_at: None,
            available_count: 0,
            sold_count: 0,
            details: Some(market_product::Details::PermissionsAccessSubscriptionDetails(
                PermissionsAccessSubscriptionDetails {
                    permissions: permissions.into_iter().map(|p| p as i32).collect(),
                },
            )),
        },
        admin,
        conn,
    )
    .expect("create should succeed")
}

/// Inserts a `market_subscriptions` row directly (no `CreateMarketSubscription` RPC exists) with
/// explicit `canceled_at`/`renews_at`/`service_terminated_at`, so specs can set up exactly the
/// terminable/not-yet-terminable/already-terminated states they need.
#[allow(clippy::too_many_arguments)]
fn create_subscription_with_state(
    conn: &mut crate::db_connection::PgPooledConnection,
    buyer: &models::User,
    product: &MarketProduct,
    purchase_type: PurchaseType,
    details: serde_json::Value,
    canceled_at: Option<SystemTime>,
    renews_at: Option<SystemTime>,
    service_terminated_at: Option<SystemTime>,
) -> models::MarketSubscription {
    let product_id = product.id.to_db_id().expect("product id should decode");
    let inserted = models::insert_market_subscription(
        &models::NewMarketSubscription {
            buyer_id: buyer.id,
            product_id,
            product_type: purchase_type.to_string_purchase_type(),
            period: PurchasePeriod::Monthly.to_string_purchase_period(),
            amount: 500,
            currency: 840,
            details,
            renews_at,
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to insert test market subscription");

    diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(inserted.id)))
        .set((
            market_subscriptions::canceled_at.eq(canceled_at),
            market_subscriptions::service_terminated_at.eq(service_terminated_at),
        ))
        .execute(conn)
        .expect("failed to seed test subscription cancellation state");

    models::get_market_subscription(inserted.id, conn).expect("failed to reload test subscription")
}

fn an_hour_ago() -> SystemTime {
    SystemTime::now() - Duration::from_secs(3600)
}

fn an_hour_from_now() -> SystemTime {
    SystemTime::now() + Duration::from_secs(3600)
}

#[test]
fn terminates_media_storage_subscription_once_canceled_and_renews_at_have_both_passed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_term_media_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = media_storage_product(&admin, conn);

        let buyer = create_user(conn, "mkt_term_media_buyer");
        // Give the buyer a non-default limit first, so the revert is actually observable.
        let buyer = grant_permissions(conn, &buyer, vec![Permission::ViewPosts]);
        diesel::update(crate::schema::users::table.filter(crate::schema::users::id.eq(buyer.id)))
            .set(crate::schema::users::media_storage_limit_bytes.eq(Some(1_073_741_824_i64)))
            .execute(conn)
            .unwrap();

        let subscription = create_subscription_with_state(
            conn,
            &buyer,
            &product,
            PurchaseType::MediaStorage,
            serde_json::to_value(MediaStorageSubscriptionDetails {
                allocation_bytes: 1_073_741_824,
            })
            .unwrap(),
            Some(an_hour_ago()),
            Some(an_hour_ago()),
            None,
        );

        terminate_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        let updated_buyer = models::get_user(buyer.id, conn)?;
        // Falls back to the server's default (15MB, since no ServerConfiguration row exists in
        // this test transaction -- see `ToProtoServerConfiguration::to_proto`'s own fallback).
        assert_eq!(updated_buyer.media_storage_limit_bytes, Some(15_728_640));

        let updated_subscription = models::get_market_subscription(subscription.id, conn)?;
        assert!(updated_subscription.service_terminated_at.is_some());

        Ok(())
    });
}

#[test]
fn terminates_permissions_access_subscription_removing_only_its_own_granted_permissions() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_term_perms_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let granted_permissions = vec![Permission::SyncEventsToFacebook, Permission::SyncPostsToFacebook];
        let product = permissions_access_product(&admin, granted_permissions.clone(), conn);

        let buyer = create_user(conn, "mkt_term_perms_buyer");
        // A permission from an unrelated source (granted directly, not via this subscription) --
        // must survive termination untouched.
        let mut all_permissions = granted_permissions.clone();
        all_permissions.push(Permission::ViewUsers);
        let buyer = grant_permissions(conn, &buyer, all_permissions);

        let subscription = create_subscription_with_state(
            conn,
            &buyer,
            &product,
            PurchaseType::PermissionsAccess,
            serde_json::to_value(PermissionsAccessSubscriptionDetails {
                permissions: granted_permissions.iter().map(|p| *p as i32).collect(),
            })
            .unwrap(),
            Some(an_hour_ago()),
            Some(an_hour_ago()),
            None,
        );

        terminate_subscriptions_of_type(PurchaseType::PermissionsAccess, conn)?;

        let updated_buyer = models::get_user(buyer.id, conn)?;
        let remaining = updated_buyer.permissions.to_proto_permissions();
        assert!(!remaining.contains(&Permission::SyncEventsToFacebook));
        assert!(!remaining.contains(&Permission::SyncPostsToFacebook));
        assert!(remaining.contains(&Permission::ViewUsers));

        let updated_subscription = models::get_market_subscription(subscription.id, conn)?;
        assert!(updated_subscription.service_terminated_at.is_some());

        Ok(())
    });
}

/// `AiGrants`/`RellmHosting` are deliberately out of scope for automatic revocation (see
/// `terminate_entitlement`'s own doc, and `PurchaseType.PURCHASE_TYPE_AI_GRANTS`'s proto doc) --
/// this confirms that's a genuine no-op (nothing errors, nothing else changes) rather than an
/// oversight, while `service_terminated_at` still gets stamped so the subscription itself is
/// correctly marked as processed and never reprocessed.
#[test]
fn terminates_ai_grants_subscription_as_a_no_op_that_still_marks_service_terminated() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_term_ai_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = ai_grants_product(&admin, conn);

        let buyer = create_user(conn, "mkt_term_ai_buyer");

        let subscription = create_subscription_with_state(
            conn,
            &buyer,
            &product,
            PurchaseType::AiGrants,
            serde_json::to_value(AiGrantSubscriptionDetails {
                ai_provider_id: "some-provider".to_string(),
                model_names: vec!["gemini-2.5-flash-image".to_string()],
                tokens: 100_000,
            })
            .unwrap(),
            Some(an_hour_ago()),
            Some(an_hour_ago()),
            None,
        );

        terminate_subscriptions_of_type(PurchaseType::AiGrants, conn)?;

        let updated_subscription = models::get_market_subscription(subscription.id, conn)?;
        assert!(updated_subscription.service_terminated_at.is_some());

        Ok(())
    });
}

/// A `PURCHASE_PERIOD_INDEFINITE` subscription's `renews_at` is always unset (see that field's own
/// proto doc) -- `get_due_market_subscriptions`' `renews_at <= now()` filter never matches a NULL
/// column, so it should never be picked up here at all. Uses no Stripe config on purpose: if this
/// were ever mistakenly treated as "due," `renew_subscriptions_of_type` would immediately cancel it
/// (see that function's own doc's "Stripe isn't configured -- ending them all" branch), which is
/// exactly the wrong, observable failure this test would catch.
#[test]
fn an_indefinite_subscription_is_never_picked_up_for_renewal() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_indefinite_no_renew_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = media_storage_product(&admin, conn);

        let buyer = create_user(conn, "mkt_indefinite_no_renew_buyer");
        let subscription = create_subscription_with_state(
            conn,
            &buyer,
            &product,
            PurchaseType::MediaStorage,
            serde_json::to_value(MediaStorageSubscriptionDetails {
                allocation_bytes: 1_073_741_824,
            })
            .unwrap(),
            None,
            None,
            None,
        );

        renew_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        let unchanged = models::get_market_subscription(subscription.id, conn)?;
        assert!(
            unchanged.canceled_at.is_none(),
            "an indefinite subscription must never be treated as due for renewal"
        );

        Ok(())
    });
}

#[test]
fn does_not_terminate_a_canceled_subscription_whose_renews_at_is_still_in_the_future() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_term_future_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = media_storage_product(&admin, conn);

        let buyer = create_user(conn, "mkt_term_future_buyer");
        diesel::update(crate::schema::users::table.filter(crate::schema::users::id.eq(buyer.id)))
            .set(crate::schema::users::media_storage_limit_bytes.eq(Some(1_073_741_824_i64)))
            .execute(conn)
            .unwrap();

        let subscription = create_subscription_with_state(
            conn,
            &buyer,
            &product,
            PurchaseType::MediaStorage,
            serde_json::to_value(MediaStorageSubscriptionDetails {
                allocation_bytes: 1_073_741_824,
            })
            .unwrap(),
            Some(an_hour_ago()),
            // Still-future renews_at -- the buyer paid through the end of this period, so the
            // entitlement (and the subscription row) must be left alone for now.
            Some(an_hour_from_now()),
            None,
        );

        terminate_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        let updated_buyer = models::get_user(buyer.id, conn)?;
        assert_eq!(updated_buyer.media_storage_limit_bytes, Some(1_073_741_824));

        let updated_subscription = models::get_market_subscription(subscription.id, conn)?;
        assert!(updated_subscription.service_terminated_at.is_none());

        Ok(())
    });
}

#[test]
fn skips_a_subscription_that_is_already_service_terminated() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_term_already_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = media_storage_product(&admin, conn);

        let buyer = create_user(conn, "mkt_term_already_buyer");
        diesel::update(crate::schema::users::table.filter(crate::schema::users::id.eq(buyer.id)))
            .set(crate::schema::users::media_storage_limit_bytes.eq(Some(1_073_741_824_i64)))
            .execute(conn)
            .unwrap();

        let already_terminated_at = an_hour_ago();
        let subscription = create_subscription_with_state(
            conn,
            &buyer,
            &product,
            PurchaseType::MediaStorage,
            serde_json::to_value(MediaStorageSubscriptionDetails {
                allocation_bytes: 1_073_741_824,
            })
            .unwrap(),
            Some(an_hour_ago()),
            Some(an_hour_ago()),
            Some(already_terminated_at),
        );

        terminate_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        // Never reprocessed -- the buyer's (deliberately non-default) limit is untouched, and
        // service_terminated_at stays exactly what it was seeded to.
        let updated_buyer = models::get_user(buyer.id, conn)?;
        assert_eq!(updated_buyer.media_storage_limit_bytes, Some(1_073_741_824));

        let updated_subscription = models::get_market_subscription(subscription.id, conn)?;
        let seconds_diff = updated_subscription
            .service_terminated_at
            .unwrap()
            .duration_since(already_terminated_at)
            .unwrap_or_default()
            .as_secs();
        assert_eq!(seconds_diff, 0);

        Ok(())
    });
}
