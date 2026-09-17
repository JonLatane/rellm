//! Specs for the Rellm Marketplace RPCs (`protos/market.proto`): `MarketProduct` CRUD's
//! `Permission::Admin` gating, `GetMarketProducts`' delisted-product visibility, and
//! `MakeMarketPurchase`'s up-front validation (delisted products, `RellmHostingPurchaseDetails`
//! requiredness, and Stripe-not-configured). Fulfillment itself (`web::stripe_webhook`,
//! `logic::market_renewal`) isn't exercised here -- both require a real (or mocked) Stripe API
//! round-trip, out of scope for these RPC-level specs.

use diesel::Connection;

use crate::marshaling::{ToDbId, ToProtoId, ToStringPurchasePeriod, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::rpcs::{
    cancel_market_subscription, create_market_product, get_market_products,
    get_market_subscriptions, make_market_purchase, update_market_product, update_market_subscription,
};
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

#[test]
fn make_market_purchase_fails_cleanly_without_stripe_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
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

fn rellm_hosting_details(fulfilled: bool, fulfillment_notes: Vec<FulfillmentNote>) -> RellmHostingSubscriptionDetails {
    RellmHostingSubscriptionDetails {
        db_size_bytes: 1_073_741_824,
        minio_size_bytes: 5 * 1_073_741_824,
        domain: "band.rellm.org".to_string(),
        contact_email: "band@example.com".to_string(),
        additional_information: "Please set this up by Friday.".to_string(),
        fulfilled,
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
        let hosting_one =
            create_rellm_hosting_subscription(conn, &buyer_one, &hosting_product, rellm_hosting_details(false, vec![]));
        let hosting_two =
            create_rellm_hosting_subscription(conn, &buyer_two, &hosting_product, rellm_hosting_details(true, vec![]));
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
        let subscription =
            create_rellm_hosting_subscription(conn, &buyer, &product, rellm_hosting_details(false, vec![]));

        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(true, vec![]),
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
                    rellm_hosting_details(true, vec![]),
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

#[test]
fn update_market_subscription_toggles_fulfilled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "mkt_update_sub_fulfilled_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let product = create_market_product(rellm_hosting_product(), &admin, conn).expect("create should succeed");

        let buyer = create_user(conn, "mkt_update_sub_fulfilled_buyer");
        let subscription =
            create_rellm_hosting_subscription(conn, &buyer, &product, rellm_hosting_details(false, vec![]));

        let updated = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(true, vec![]),
                )),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("update should succeed");

        assert!(rellm_hosting_details_of(&updated).fulfilled);

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
        let subscription =
            create_rellm_hosting_subscription(conn, &buyer, &product, rellm_hosting_details(false, vec![]));

        let new_note = FulfillmentNote {
            user_id: admin.id.to_proto_id(),
            note: "Waiting on DNS propagation.".to_string(),
            // The server should ignore this and stamp its own created_at.
            created_at: None,
        };
        let updated = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(false, vec![new_note]),
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
        let subscription =
            create_rellm_hosting_subscription(conn, &buyer, &product, rellm_hosting_details(false, vec![]));

        let spoofed_note = FulfillmentNote {
            user_id: buyer.id.to_proto_id(), // not the admin actually making this request
            note: "Pretending to be the buyer.".to_string(),
            created_at: None,
        };
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(false, vec![spoofed_note]),
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
            created_at: Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 }),
        };
        let subscription = create_rellm_hosting_subscription(
            conn,
            &buyer,
            &product,
            rellm_hosting_details(false, vec![existing_note]),
        );

        // Trying to remove the existing note entirely.
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(false, vec![]),
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
            created_at: Some(prost_wkt_types::Timestamp { seconds: 0, nanos: 0 }),
        };
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
                    rellm_hosting_details(false, vec![altered_note]),
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
