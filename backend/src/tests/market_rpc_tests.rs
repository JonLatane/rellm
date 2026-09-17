//! Specs for the Rellm Marketplace RPCs (`protos/market.proto`): `MarketProduct` CRUD's
//! `Permission::Admin` gating, `GetMarketProducts`' delisted-product visibility, and
//! `MakeMarketPurchase`'s up-front validation (delisted products, `RellmHostingPurchaseDetails`
//! requiredness, and Stripe-not-configured). Fulfillment itself (`web::stripe_webhook`,
//! `logic::market_renewal`) isn't exercised here -- both require a real (or mocked) Stripe API
//! round-trip, out of scope for these RPC-level specs.

use diesel::prelude::*;
use diesel::Connection;

use crate::marshaling::{ToDbId, ToProtoId, ToStringPurchasePeriod, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::rpcs::{
    cancel_market_subscription, create_market_product, get_market_products,
    get_market_subscriptions, make_market_purchase, update_market_product, update_market_subscription,
};
use crate::schema::market_products;
use crate::tests::factories::*;

fn media_storage_product(amount: u32, period: PurchasePeriod) -> MarketProduct {
    MarketProduct {
        id: String::new(),
        r#type: PurchaseType::MediaStorage as i32,
        period: period as i32,
        amount,
        currency: 840, // USD
        created_at: None,
        delisted_at: None,
        available_count: 0,
        sold_count: 0,
        details: Some(market_product::Details::MediaStorageSubscriptionDetails(
            MediaStorageSubscriptionDetails {
                allocation_bytes: 1_073_741_824, // 1GB
            },
        )),
    }
}

#[test]
fn create_market_product_requires_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "mkt_create_non_admin");

        let err = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::InvalidArgument);
        assert!(err.message().contains("permission"));

        Ok(())
    });
}

#[test]
fn admin_can_create_and_the_product_is_marshaled_back() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_create_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        assert!(!created.id.is_empty());
        assert_eq!(created.r#type, PurchaseType::MediaStorage as i32);
        assert_eq!(created.period, PurchasePeriod::Monthly as i32);
        assert_eq!(created.amount, 500);
        assert_eq!(created.currency, 840);
        assert!(created.delisted_at.is_none());
        match created.details {
            Some(market_product::Details::MediaStorageSubscriptionDetails(d)) => {
                assert_eq!(d.allocation_bytes, 1_073_741_824);
            }
            other => panic!("expected MediaStorageSubscriptionDetails, got {:?}", other),
        }

        Ok(())
    });
}

#[test]
fn create_market_product_rejects_details_mismatched_with_type() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_create_mismatch");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = media_storage_product(500, PurchasePeriod::Monthly);
        request.r#type = PurchaseType::AiGrants as i32; // details still MediaStorage-shaped
        let err = create_market_product(request, &admin, conn).unwrap_err();
        assert_eq!(err.message(), "details_do_not_match_type");

        Ok(())
    });
}

#[test]
fn update_market_product_requires_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let non_admin = create_user(conn, "mkt_update_non_admin");
        let mut update_request = created.clone();
        update_request.amount = 999;
        let err = update_market_product(update_request, &non_admin, conn).unwrap_err();
        assert_eq!(err.code(), tonic::Code::InvalidArgument);
        assert!(err.message().contains("permission"));

        Ok(())
    });
}

#[test]
fn admin_can_update_amount_and_delist() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_delist_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let mut update_request = created.clone();
        update_request.amount = 750;
        // Client-supplied delisted_at timestamp is ignored -- only presence matters (see
        // `MarketProduct.delisted_at`'s own doc) -- the server stamps its own current time.
        update_request.delisted_at = Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 });
        let updated = update_market_product(update_request, &admin, conn).expect("update should succeed");

        assert_eq!(updated.amount, 750);
        assert!(updated.delisted_at.is_some());

        Ok(())
    });
}

#[test]
fn get_market_products_hides_delisted_products_from_non_admins() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_list_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");
        let mut delist_request = created.clone();
        delist_request.delisted_at = Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 });
        update_market_product(delist_request, &admin, conn).expect("delist should succeed");

        let non_admin_response =
            get_market_products(GetMarketProductsRequest {}, &None, conn).expect("get should succeed");
        assert!(non_admin_response
            .market_products
            .iter()
            .all(|p| p.id != created.id));

        let admin_response =
            get_market_products(GetMarketProductsRequest {}, &Some(&admin), conn).expect("get should succeed");
        assert!(admin_response.market_products.iter().any(|p| p.id == created.id));

        Ok(())
    });
}

#[test]
fn get_market_subscriptions_is_empty_for_a_buyer_with_none() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "mkt_subs_empty");

        let response = get_market_subscriptions(
            GetMarketSubscriptionsRequest {
                request_type: GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForPurchase as i32,
            },
            &user,
            conn,
        )
        .expect("get should succeed");
        assert!(response.market_subscriptions.is_empty());

        Ok(())
    });
}

/// `market_settings.enabled` (default `false` -- see `market_settings_defaults_to_disabled_for_a_
/// server_that_never_set_it`) is checked before anything product-specific, including Stripe --
/// even a fully-configured product/Stripe setup must still be rejected while Market itself is
/// administratively closed.
#[test]
fn make_market_purchase_rejects_when_market_is_disabled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        // Deliberately no `configure_market(conn, true)` -- Market defaults to closed.
        let admin = create_user(conn, "mkt_purchase_disabled_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_purchase_disabled_buyer");
        let err = make_market_purchase(
            MakeMarketPurchaseRequest {
                market_product_id: created.id,
                rellm_hosting_details: None,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "market_disabled");

        Ok(())
    });
}

#[test]
fn make_market_purchase_fails_cleanly_without_stripe_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let admin = create_user(conn, "mkt_purchase_no_stripe_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_purchase_no_stripe_buyer");
        let err = make_market_purchase(
            MakeMarketPurchaseRequest {
                market_product_id: created.id,
                rellm_hosting_details: None,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "stripe_not_configured");

        Ok(())
    });
}

#[test]
fn make_market_purchase_rejects_delisted_products() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        configure_market(conn, true);
        let admin = create_user(conn, "mkt_purchase_delisted_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");
        let mut delist_request = created.clone();
        delist_request.delisted_at = Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 });
        update_market_product(delist_request, &admin, conn).expect("delist should succeed");

        let buyer = create_user(conn, "mkt_purchase_delisted_buyer");
        let err = make_market_purchase(
            MakeMarketPurchaseRequest {
                market_product_id: created.id,
                rellm_hosting_details: None,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "product_delisted");

        Ok(())
    });
}

#[test]
fn make_market_purchase_requires_rellm_hosting_details_for_rellm_hosting_products() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        configure_market(conn, true);
        let admin = create_user(conn, "mkt_purchase_hosting_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            MarketProduct {
                id: String::new(),
                r#type: PurchaseType::RellmHosting as i32,
                period: PurchasePeriod::Annual as i32,
                amount: 12000,
                currency: 840,
                created_at: None,
                delisted_at: None,
                details: None,
                available_count: 0,
                sold_count: 0,
            },
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_purchase_hosting_buyer");
        let err = make_market_purchase(
            MakeMarketPurchaseRequest {
                market_product_id: created.id,
                rellm_hosting_details: None,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "rellm_hosting_details_required");

        Ok(())
    });
}

#[test]
fn admin_can_set_and_update_available_count() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_slots_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = media_storage_product(500, PurchasePeriod::Monthly);
        request.available_count = 5;
        let created = create_market_product(request, &admin, conn).expect("create should succeed");
        assert_eq!(created.available_count, 5);
        assert_eq!(created.sold_count, 0);

        let mut update_request = created.clone();
        update_request.available_count = 10;
        let updated = update_market_product(update_request, &admin, conn).expect("update should succeed");
        assert_eq!(updated.available_count, 10);

        Ok(())
    });
}

#[test]
fn update_market_product_does_not_let_a_client_set_sold_count_directly() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_slots_sold_count_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let created = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");
        assert_eq!(created.sold_count, 0);

        // A client sending a nonzero sold_count should be silently ignored, same treatment
        // type/period already get -- sold_count is server-managed only (see its own doc).
        let mut update_request = created.clone();
        update_request.sold_count = 999;
        let updated = update_market_product(update_request, &admin, conn).expect("update should succeed");
        assert_eq!(updated.sold_count, 0);

        Ok(())
    });
}

#[test]
fn make_market_purchase_rejects_a_sold_out_product() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        configure_market(conn, true);
        let admin = create_user(conn, "mkt_sold_out_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let mut request = media_storage_product(500, PurchasePeriod::Monthly);
        request.available_count = 1;
        let created = create_market_product(request, &admin, conn).expect("create should succeed");
        let product_id = created.id.to_db_id().expect("valid id");
        // Simulate the one slot already having been sold (normally done by
        // `web::stripe_webhook`'s `handle_checkout_session_completed`).
        models::increment_market_product_sold_count(product_id, conn);

        let buyer = create_user(conn, "mkt_sold_out_buyer");
        let err = make_market_purchase(
            MakeMarketPurchaseRequest {
                market_product_id: created.id,
                rellm_hosting_details: None,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "product_sold_out");

        Ok(())
    });
}

/// Inserts a `market_subscriptions` row directly (there's no `CreateMarketSubscription` RPC --
/// subscriptions are only ever created by `web::stripe_webhook`) for `buyer` against `product`, so
/// `CancelMarketSubscription` specs have something to act on.
fn create_subscription(
    conn: &mut crate::db_connection::PgPooledConnection,
    buyer: &models::User,
    product: &MarketProduct,
) -> models::MarketSubscription {
    let product_id = product.id.to_db_id().expect("product id should decode");
    crate::models::insert_market_subscription(
        &crate::models::NewMarketSubscription {
            buyer_id: buyer.id,
            product_id,
            product_type: PurchaseType::MediaStorage.to_string_purchase_type(),
            period: PurchasePeriod::Monthly.to_string_purchase_period(),
            amount: 500,
            currency: 840,
            details: serde_json::to_value(MediaStorageSubscriptionDetails {
                allocation_bytes: 1_073_741_824,
            })
            .unwrap(),
            renews_at: None,
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to insert test market subscription")
}

#[test]
fn cancel_market_subscription_by_own_buyer_sets_canceled_at() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_cancel_self_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_cancel_self_buyer");
        let subscription = create_subscription(conn, &buyer, &product);

        let response = cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &buyer,
            conn,
        )
        .expect("self-cancel should succeed");
        assert!(response.canceled_at.is_some());

        Ok(())
    });
}

#[test]
fn cancel_market_subscription_rejects_non_owner_non_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_cancel_other_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_cancel_other_buyer");
        let subscription = create_subscription(conn, &buyer, &product);

        let stranger = create_user(conn, "mkt_cancel_other_stranger");
        let err = cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &stranger,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::InvalidArgument);
        assert!(err.message().contains("permission"));

        Ok(())
    });
}

#[test]
fn cancel_market_subscription_allows_admin_to_cancel_someone_elses() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_cancel_admin_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_cancel_admin_buyer");
        let subscription = create_subscription(conn, &buyer, &product);

        let response = cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("admin cancel should succeed");
        assert!(response.canceled_at.is_some());

        Ok(())
    });
}

#[test]
fn cancel_market_subscription_is_idempotent() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_cancel_idempotent_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_cancel_idempotent_buyer");
        let subscription = create_subscription(conn, &buyer, &product);

        let first = cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &buyer,
            conn,
        )
        .expect("first cancel should succeed");
        let first_canceled_at = first.canceled_at.expect("should have canceled_at set");

        let second = cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &buyer,
            conn,
        )
        .expect("second cancel should succeed as a no-op");
        assert_eq!(second.canceled_at, Some(first_canceled_at));

        Ok(())
    });
}

/// See `MarketProduct.sold_count`'s own doc -- canceling frees the slot for a new buyer, but only
/// on the actual cancel transition; re-canceling an already-canceled subscription (see
/// `cancel_market_subscription_is_idempotent` above) must not decrement it a second time.
#[test]
fn cancel_market_subscription_decrements_sold_count_only_on_the_actual_transition() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_cancel_slots_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let mut request = media_storage_product(500, PurchasePeriod::Monthly);
        request.available_count = 5;
        let product = create_market_product(request, &admin, conn).expect("create should succeed");
        let product_id = product.id.to_db_id().expect("valid id");
        // Simulate this subscription's own purchase having already claimed a slot (normally done
        // by `web::stripe_webhook`'s `handle_checkout_session_completed`).
        models::increment_market_product_sold_count(product_id, conn);
        assert_eq!(models::get_market_product(product_id, conn)?.sold_count, 1);

        let buyer = create_user(conn, "mkt_cancel_slots_buyer");
        let subscription = create_subscription(conn, &buyer, &product);

        cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &buyer,
            conn,
        )
        .expect("first cancel should succeed");
        assert_eq!(
            models::get_market_product(product_id, conn)?.sold_count,
            0,
            "the actual cancel transition should free the slot"
        );

        cancel_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                ..Default::default()
            },
            &buyer,
            conn,
        )
        .expect("second cancel should succeed as a no-op");
        assert_eq!(
            models::get_market_product(product_id, conn)?.sold_count,
            0,
            "re-canceling an already-canceled subscription must not decrement sold_count again"
        );

        Ok(())
    });
}

fn rellm_hosting_product() -> MarketProduct {
    MarketProduct {
        id: String::new(),
        r#type: PurchaseType::RellmHosting as i32,
        period: PurchasePeriod::Annual as i32,
        amount: 12000,
        currency: 840,
        created_at: None,
        delisted_at: None,
        available_count: 0,
        sold_count: 0,
        details: None,
    }
}

fn rellm_hosting_details(
    fulfillment_status: FulfillmentStatus,
    fulfillment_notes: Vec<FulfillmentNote>,
) -> RellmHostingSubscriptionDetails {
    RellmHostingSubscriptionDetails {
        db_size_bytes: 1_073_741_824,
        minio_size_bytes: 5 * 1_073_741_824,
        domain: "band.rellm.org".to_string(),
        contact_email: "band@example.com".to_string(),
        additional_information: "Please set this up by Friday.".to_string(),
        fulfillment_status: fulfillment_status as i32,
        fulfillment_notes,
    }
}

fn create_rellm_hosting_subscription(
    conn: &mut crate::db_connection::PgPooledConnection,
    buyer: &models::User,
    product: &MarketProduct,
    details: RellmHostingSubscriptionDetails,
) -> models::MarketSubscription {
    let product_id = product.id.to_db_id().expect("product id should decode");
    crate::models::insert_market_subscription(
        &crate::models::NewMarketSubscription {
            buyer_id: buyer.id,
            product_id,
            product_type: PurchaseType::RellmHosting.to_string_purchase_type(),
            period: PurchasePeriod::Annual.to_string_purchase_period(),
            amount: 12000,
            currency: 840,
            details: serde_json::to_value(details).unwrap(),
            renews_at: None,
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to insert test rellm hosting subscription")
}

fn rellm_hosting_details_of(subscription: &MarketSubscription) -> RellmHostingSubscriptionDetails {
    match subscription.details.clone() {
        Some(market_subscription::Details::RellmHostingSubscriptionDetails(d)) => d,
        other => panic!("expected RellmHostingSubscriptionDetails, got {:?}", other),
    }
}

#[test]
fn get_market_subscriptions_for_fulfillment_requires_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let non_admin = create_user(conn, "mkt_fulfillment_non_admin");

        let err = get_market_subscriptions(
            GetMarketSubscriptionsRequest {
                request_type: GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForFulfillmentAdmin
                    as i32,
            },
            &non_admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::InvalidArgument);
        assert!(err.message().contains("permission"));

        Ok(())
    });
}

#[test]
fn get_market_subscriptions_for_fulfillment_returns_rellm_hosting_orders_across_every_buyer() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_fulfillment_list_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let hosting_product = create_market_product(rellm_hosting_product(), &admin, conn)
            .expect("create hosting product should succeed");
        let storage_product = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create storage product should succeed");

        let buyer_one = create_user(conn, "mkt_fulfillment_buyer_one");
        let buyer_two = create_user(conn, "mkt_fulfillment_buyer_two");
        let hosting_one = create_rellm_hosting_subscription(
            conn,
            &buyer_one,
            &hosting_product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );
        let hosting_two = create_rellm_hosting_subscription(
            conn,
            &buyer_two,
            &hosting_product,
            rellm_hosting_details(FulfillmentStatus::Fulfilled, vec![]),
        );
        // A MediaStorage subscription should never show up in the fulfillment list.
        let _storage = create_subscription(conn, &buyer_one, &storage_product);

        let response = get_market_subscriptions(
            GetMarketSubscriptionsRequest {
                request_type: GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForFulfillmentAdmin
                    as i32,
            },
            &admin,
            conn,
        )
        .expect("admin fulfillment list should succeed");

        let ids: Vec<String> = response.market_subscriptions.iter().map(|s| s.id.clone()).collect();
        assert!(ids.contains(&hosting_one.id.to_proto_id()));
        assert!(ids.contains(&hosting_two.id.to_proto_id()));
        assert_eq!(response.market_subscriptions.len(), 2);
        for subscription in &response.market_subscriptions {
            assert_eq!(subscription.r#type, PurchaseType::RellmHosting as i32);
        }

        Ok(())
    });
}

#[test]
fn update_market_subscription_requires_admin_even_for_the_buyer_themselves() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_admin_gate");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_buyer_gate");
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );

        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::Fulfilled, vec![]),
                )),
                ..Default::default()
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::InvalidArgument);
        assert!(err.message().contains("permission"));

        Ok(())
    });
}

#[test]
fn update_market_subscription_rejects_non_rellm_hosting_subscriptions() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_wrong_type_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(
            media_storage_product(500, PurchasePeriod::Monthly),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_wrong_type_buyer");
        let subscription = create_subscription(conn, &buyer, &product);

        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::Fulfilled, vec![]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "not_a_rellm_hosting_subscription");

        Ok(())
    });
}

/// A status-changing note ("Add and Mark as Fulfilled" on `/market/fulfillment`) can stand on its
/// own with no text -- see `FulfillmentNote.note`'s own proto doc.
#[test]
fn update_market_subscription_marks_fulfilled_via_a_status_changing_note_with_no_text() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_fulfilled_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_fulfilled_buyer");
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );

        let fulfilled_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: String::new(),
            fulfillment_status: FulfillmentStatus::Fulfilled as i32,
            created_at: None,
        };
        let updated = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![fulfilled_note]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("update should succeed");

        let details = rellm_hosting_details_of(&updated);
        assert_eq!(details.fulfillment_status, FulfillmentStatus::Fulfilled as i32);
        assert_eq!(details.fulfillment_notes.len(), 1);
        assert_eq!(details.fulfillment_notes[0].fulfillment_status, FulfillmentStatus::Fulfilled as i32);

        Ok(())
    });
}

/// A plain note (no status change) still requires text -- same rule the old boolean-toggle era
/// enforced, just conditioned on `fulfillment_status` staying the same now instead of applying
/// unconditionally.
#[test]
fn update_market_subscription_requires_text_for_a_note_that_does_not_change_status() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_blank_note_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_blank_note_buyer");
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );

        let blank_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "   ".to_string(),
            fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
            created_at: None,
        };
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![blank_note]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "fulfillment_note_text_required");

        Ok(())
    });
}

/// The full "fulfillment state history" -- a sequence of notes builds up a real status timeline,
/// and the subscription's own `fulfillment_status` always reflects the *last* one, matching
/// `/market/fulfillment`'s own "expanding an order marks it In Progress" auto-transition followed
/// by an admin later marking it Fulfilled.
#[test]
fn update_market_subscription_tracks_a_multi_step_fulfillment_history() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_history_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_history_buyer");
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );

        // Step 1: the automatic "admin opened this order" transition to In Progress, no text.
        let in_progress_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: String::new(),
            fulfillment_status: FulfillmentStatus::InProgress as i32,
            created_at: None,
        };
        let after_step_1 = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![in_progress_note]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("step 1 update should succeed");
        assert_eq!(
            rellm_hosting_details_of(&after_step_1).fulfillment_status,
            FulfillmentStatus::InProgress as i32
        );

        // Step 2: a plain progress note (status unchanged, so text is required). Builds on the
        // *server's* own stored notes (real `created_at`), not the locally-constructed ones above
        // -- the append-only check compares against exactly what's actually stored.
        let mut notes_so_far = rellm_hosting_details_of(&after_step_1).fulfillment_notes;
        notes_so_far.push(FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "Provisioning the instance now.".to_string(),
            fulfillment_status: FulfillmentStatus::InProgress as i32,
            created_at: None,
        });
        let after_step_2 = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, notes_so_far),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("step 2 update should succeed");
        assert_eq!(
            rellm_hosting_details_of(&after_step_2).fulfillment_status,
            FulfillmentStatus::InProgress as i32
        );

        // Step 3: marking it Fulfilled, with a closing note.
        let mut notes_so_far = rellm_hosting_details_of(&after_step_2).fulfillment_notes;
        notes_so_far.push(FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "Instance is live.".to_string(),
            fulfillment_status: FulfillmentStatus::Fulfilled as i32,
            created_at: None,
        });
        let after_step_3 = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, notes_so_far),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("step 3 update should succeed");
        let final_details = rellm_hosting_details_of(&after_step_3);
        assert_eq!(final_details.fulfillment_status, FulfillmentStatus::Fulfilled as i32);
        assert_eq!(final_details.fulfillment_notes.len(), 3);
        assert_eq!(
            final_details.fulfillment_notes.iter().map(|n| n.fulfillment_status).collect::<Vec<_>>(),
            vec![
                FulfillmentStatus::InProgress as i32,
                FulfillmentStatus::InProgress as i32,
                FulfillmentStatus::Fulfilled as i32,
            ]
        );

        Ok(())
    });
}

#[test]
fn update_market_subscription_appends_a_note_with_server_stamped_created_at() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_note_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_note_buyer");
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );

        let new_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "Waiting on DNS propagation.".to_string(),
            fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
            // The server should ignore this and stamp its own created_at.
            created_at: None,
        };
        let updated = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![new_note]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("update should succeed");

        let notes = rellm_hosting_details_of(&updated).fulfillment_notes;
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].user_id, admin.id.to_proto_id());
        assert_eq!(notes[0].note, "Waiting on DNS propagation.");
        assert!(notes[0].created_at.is_some());

        Ok(())
    });
}

#[test]
fn update_market_subscription_rejects_a_note_attributed_to_someone_else() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_spoof_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_spoof_buyer");
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
        );

        let spoofed_note = FulfillmentNote {
            user_id: buyer.id.to_proto_id(), // not the admin actually making this request
            note: "Pretending to be the buyer.".to_string(),
            fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
            created_at: None,
        };
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![spoofed_note]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "fulfillment_note_user_id_mismatch");

        Ok(())
    });
}

#[test]
fn update_market_subscription_rejects_altering_or_removing_existing_notes() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_immutable_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_immutable_buyer");
        let existing_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "Original note.".to_string(),
            fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
            created_at: Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 }),
        };
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![existing_note]),
        );

        // Trying to remove the existing note entirely.
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "fulfillment_notes_must_only_be_appended");

        // Trying to edit the existing note's text.
        let altered_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "Altered note.".to_string(),
            fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
            created_at: Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 }),
        };
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(FulfillmentStatus::AwaitingHostAdmin, vec![altered_note]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "fulfillment_notes_must_only_be_appended");

        Ok(())
    });
}

fn permissions_access_product(permissions: Vec<Permission>) -> MarketProduct {
    MarketProduct {
        id: String::new(),
        r#type: PurchaseType::PermissionsAccess as i32,
        period: PurchasePeriod::Monthly as i32,
        amount: 500,
        currency: 840, // USD
        created_at: None,
        delisted_at: None,
        available_count: 0,
        sold_count: 0,
        details: Some(market_product::Details::PermissionsAccessSubscriptionDetails(
            PermissionsAccessSubscriptionDetails { permissions: permissions.into_iter().map(|p| p as i32).collect() },
        )),
    }
}

#[test]
fn create_market_product_rejects_a_non_purchasable_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_permissions_create_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        // `Admin` itself is the clearest possible case of a permission that must never be
        // purchasable -- see `PURCHASABLE_PERMISSIONS`'s own doc.
        let err = create_market_product(
            permissions_access_product(vec![Permission::SyncPostsToFacebook, Permission::Admin]),
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "permission_not_purchasable");

        Ok(())
    });
}

#[test]
fn admin_can_create_a_permissions_access_product_with_only_purchasable_permissions() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_permissions_create_ok_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let created = create_market_product(
            permissions_access_product(vec![
                Permission::SyncEventsToFacebook,
                Permission::SyncPostsToFacebook,
            ]),
            &admin,
            conn,
        )
        .expect("create should succeed for purchasable permissions");
        match created.details {
            Some(market_product::Details::PermissionsAccessSubscriptionDetails(d)) => {
                assert_eq!(
                    d.permissions,
                    vec![Permission::SyncEventsToFacebook as i32, Permission::SyncPostsToFacebook as i32]
                );
            }
            other => panic!("expected PermissionsAccessSubscriptionDetails, got {:?}", other),
        }

        Ok(())
    });
}

#[test]
fn update_market_product_rejects_a_non_purchasable_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_permissions_update_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            permissions_access_product(vec![Permission::SyncEventsToFacebook]),
            &admin,
            conn,
        )
        .expect("create should succeed");

        let mut update_request = created;
        update_request.details = Some(market_product::Details::PermissionsAccessSubscriptionDetails(
            PermissionsAccessSubscriptionDetails {
                permissions: vec![Permission::ViewPrivateContactMethods as i32],
            },
        ));
        let err = update_market_product(update_request, &admin, conn).unwrap_err();
        assert_eq!(err.message(), "permission_not_purchasable");

        Ok(())
    });
}

#[test]
fn make_market_purchase_rejects_a_permission_no_longer_purchasable() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        configure_market(conn, true);
        let admin = create_user(conn, "mkt_permissions_purchase_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let created = create_market_product(
            permissions_access_product(vec![Permission::SyncEventsToFacebook]),
            &admin,
            conn,
        )
        .expect("create should succeed");
        let product_id = created.id.to_db_id().expect("valid id");

        // Simulate `PURCHASABLE_PERMISSIONS` having since dropped a permission that was
        // purchasable when this product was created -- defense in depth, since
        // `MakeMarketPurchase` re-validates even though `CreateMarketProduct`/
        // `UpdateMarketProduct` already reject this combination going forward.
        let stale_details = serde_json::to_value(PermissionsAccessSubscriptionDetails {
            permissions: vec![Permission::Admin as i32],
        })
        .expect("serialize stale details");
        diesel::update(market_products::table.filter(market_products::id.eq(product_id)))
            .set(market_products::details.eq(stale_details))
            .execute(conn)
            .expect("failed to seed stale product details");

        let buyer = create_user(conn, "mkt_permissions_purchase_buyer");
        let err = make_market_purchase(
            MakeMarketPurchaseRequest {
                market_product_id: created.id,
                rellm_hosting_details: None,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "permission_not_purchasable");

        Ok(())
    });
}
