//! Specs for the Rellm Marketplace RPCs (`protos/market.proto`): `MarketProduct` CRUD's
//! `Permission::Admin` gating, `GetMarketProducts`' delisted-product visibility, and
//! `MakeMarketPurchase`'s up-front validation (delisted products, `RellmHostingPurchaseDetails`
//! requiredness, and Stripe-not-configured). Fulfillment itself (`web::stripe_webhook`,
//! `logic::market_renewal`) isn't exercised here -- both require a real (or mocked) Stripe API
//! round-trip, out of scope for these RPC-level specs.

use diesel::Connection;

use crate::protos::*;
use crate::rpcs::{
    create_market_product, get_market_products, get_market_subscriptions, make_market_purchase,
    update_market_product,
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

        let response = get_market_subscriptions(GetMarketSubscriptionsRequest {}, &user, conn)
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
