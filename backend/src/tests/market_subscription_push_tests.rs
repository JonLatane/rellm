//! Specs for opt-in push notifications about a Rellm hosting subscription's fulfillment chat
//! (`RegisterMarketSubscriptionPush`/`UnregisterMarketSubscriptionPush`/
//! `GetMarketSubscriptionPushStatus`, and who `web_push::notify_fulfillment_note` actually
//! notifies). Actually delivering a Web Push needs a push service and a VAPID key, so -- like
//! `web_push_tests` -- the delivery step itself isn't exercised; everything that decides *whether
//! and to whom* is.

use diesel::Connection;

use crate::marshaling::{ToDbId, ToProtoId, ToProtoTime, ToStringPurchasePeriod, ToStringPurchaseType};
use crate::models;
use crate::protos::*;
use crate::rpcs::{
    create_market_product, get_market_subscription_push_status, register_market_subscription_push,
    register_push_subscription, unregister_market_subscription_push, unregister_push_subscription,
    update_market_subscription, update_market_subscription_and_notify,
};
use crate::tests::factories::*;
use crate::web_push::{fulfillment_note_recipients, FulfillmentNoteNotificationContent};

const ENDPOINT: &str = "https://fcm.googleapis.com/fcm/send/market-endpoint";

type Conn = crate::db_connection::PgPooledConnection;

fn register_device(conn: &mut Conn, user: &models::User, endpoint: &str) {
    register_push_subscription(
        RegisterPushSubscriptionRequest {
            endpoint: endpoint.to_string(),
            p256dh_key: "some-p256dh-key".to_string(),
            auth_key: "some-auth-key".to_string(),
        },
        user,
        conn,
    )
    .expect("registering the device should succeed");
}

fn push_request(subscription: &models::MarketSubscription, endpoint: &str) -> MarketSubscriptionPushRequest {
    MarketSubscriptionPushRequest {
        market_subscription_id: subscription.id.to_proto_id(),
        endpoint: endpoint.to_string(),
    }
}

fn admin(conn: &mut Conn, name: &str) -> models::User {
    let user = create_user(conn, name);
    grant_permissions(conn, &user, vec![Permission::Admin])
}

fn hosting_product(conn: &mut Conn, admin: &models::User) -> MarketProduct {
    create_market_product(
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
        },
        admin,
        conn,
    )
    .expect("create should succeed")
}

fn hosting_subscription(
    conn: &mut Conn,
    buyer: &models::User,
    product: &MarketProduct,
) -> models::MarketSubscription {
    models::insert_market_subscription(
        &models::NewMarketSubscription {
            buyer_id: buyer.id,
            product_id: product.id.to_db_id().unwrap(),
            product_type: PurchaseType::RellmHosting.to_string_purchase_type(),
            period: PurchasePeriod::Annual.to_string_purchase_period(),
            amount: 12000,
            currency: 840,
            details: serde_json::to_value(RellmHostingSubscriptionDetails {
                domain: "band.rellm.org".to_string(),
                contact_email: "band@example.com".to_string(),
                ..Default::default()
            })
            .unwrap(),
            renews_at: None,
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to insert test rellm hosting subscription")
}

fn status(conn: &mut Conn, user: &models::User, subscription: &models::MarketSubscription) -> bool {
    get_market_subscription_push_status(push_request(subscription, ENDPOINT), user, conn)
        .expect("status should succeed")
        .registered
}

/// A buyer + admin + hosting subscription, the shape almost every spec here starts from.
fn setup(conn: &mut Conn, prefix: &str) -> (models::User, models::User, models::MarketSubscription) {
    let admin = admin(conn, &format!("{prefix}_admin"));
    let product = hosting_product(conn, &admin);
    let buyer = create_user(conn, &format!("{prefix}_buyer"));
    let subscription = hosting_subscription(conn, &buyer, &product);
    (buyer, admin, subscription)
}

#[test]
fn registering_requires_the_device_to_already_be_a_registered_push_subscription() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, _admin, subscription) = setup(conn, "mkt_push_unreg");

        let err = register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)
            .unwrap_err();
        assert_eq!(err.code(), tonic::Code::FailedPrecondition);
        assert_eq!(err.message(), "push_subscription_not_registered");
        assert!(!status(conn, &buyer, &subscription));
        Ok(())
    });
}

#[test]
fn a_buyer_can_opt_a_device_in_and_out() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, _admin, subscription) = setup(conn, "mkt_push_toggle");
        register_device(conn, &buyer, ENDPOINT);
        assert!(!status(conn, &buyer, &subscription), "registering a device alone opts into nothing");

        register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;
        assert!(status(conn, &buyer, &subscription));

        unregister_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;
        assert!(!status(conn, &buyer, &subscription));
        // The device's own (Messages) subscription is untouched.
        assert!(models::push_subscription_exists(buyer.id, ENDPOINT, conn)?);
        Ok(())
    });
}

#[test]
fn registering_twice_is_a_no_op_and_unregistering_when_not_registered_is_fine() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, _admin, subscription) = setup(conn, "mkt_push_idem");
        register_device(conn, &buyer, ENDPOINT);

        unregister_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;

        register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;
        register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;
        let linked = models::get_push_subscriptions_for_market_subscription(subscription.id, conn)?;
        assert_eq!(linked.len(), 1, "the unique pair must not produce a second row");
        Ok(())
    });
}

#[test]
fn opting_in_is_per_device_and_per_account() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_push_scope");
        // Same physical browser (same endpoint) signed into two accounts -> one row per account.
        register_device(conn, &buyer, ENDPOINT);
        register_device(conn, &admin, ENDPOINT);
        register_device(conn, &buyer, "https://example.com/second-device");

        register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;

        assert!(status(conn, &buyer, &subscription));
        assert!(!status(conn, &admin, &subscription), "the admin's row for that endpoint isn't linked");
        assert!(
            !get_market_subscription_push_status(
                push_request(&subscription, "https://example.com/second-device"),
                &buyer,
                conn
            )?
            .registered,
            "nor is the buyer's other device"
        );
        Ok(())
    });
}

#[test]
fn an_admin_can_opt_in_but_an_unrelated_user_cannot_do_anything() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (_buyer, admin, subscription) = setup(conn, "mkt_push_authz");
        let stranger = create_user(conn, "mkt_push_authz_stranger");
        register_device(conn, &admin, ENDPOINT);
        register_device(conn, &stranger, ENDPOINT);

        register_market_subscription_push(push_request(&subscription, ENDPOINT), &admin, conn)?;
        assert!(status(conn, &admin, &subscription));

        let register_err = register_market_subscription_push(push_request(&subscription, ENDPOINT), &stranger, conn)
            .unwrap_err();
        assert!(register_err.message().contains("permission"), "{:?}", register_err);
        let unregister_err =
            unregister_market_subscription_push(push_request(&subscription, ENDPOINT), &stranger, conn)
                .unwrap_err();
        assert!(unregister_err.message().contains("permission"), "{:?}", unregister_err);
        let status_err = get_market_subscription_push_status(push_request(&subscription, ENDPOINT), &stranger, conn)
            .unwrap_err();
        assert!(status_err.message().contains("permission"), "{:?}", status_err);
        Ok(())
    });
}

#[test]
fn any_subscription_type_can_opt_in_to_its_chat_notifications() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn, "mkt_push_type_admin");
        let product = create_market_product(
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
                    MediaStorageSubscriptionDetails { allocation_bytes: 1, ..Default::default() },
                )),
            },
            &admin,
            conn,
        )?;
        let buyer = create_user(conn, "mkt_push_type_buyer");
        let subscription = models::insert_market_subscription(
            &models::NewMarketSubscription {
                buyer_id: buyer.id,
                product_id: product.id.to_db_id().unwrap(),
                product_type: PurchaseType::MediaStorage.to_string_purchase_type(),
                period: PurchasePeriod::Monthly.to_string_purchase_period(),
                amount: 500,
                currency: 840,
                details: serde_json::to_value(MediaStorageSubscriptionDetails { allocation_bytes: 1, ..Default::default() }).unwrap(),
                renews_at: None,
                stripe_customer_id: None,
                stripe_payment_method_id: None,
            },
            conn,
        )?;
        register_device(conn, &buyer, ENDPOINT);

        // Every `PurchaseType` has a fulfillment chat, not just Rellm hosting.
        register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;
        assert!(status(conn, &buyer, &subscription));
        Ok(())
    });
}

#[test]
fn an_unknown_subscription_is_not_found() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "mkt_push_missing");
        let err = register_market_subscription_push(
            MarketSubscriptionPushRequest {
                market_subscription_id: 999_999_999_i64.to_proto_id(),
                endpoint: ENDPOINT.to_string(),
            },
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::NotFound);
        Ok(())
    });
}

#[test]
fn unregistering_the_device_itself_drops_its_chat_opt_ins() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, _admin, subscription) = setup(conn, "mkt_push_cascade");
        register_device(conn, &buyer, ENDPOINT);
        register_market_subscription_push(push_request(&subscription, ENDPOINT), &buyer, conn)?;

        unregister_push_subscription(UnregisterPushSubscriptionRequest { endpoint: ENDPOINT.to_string() }, &buyer, conn)?;

        assert!(models::get_push_subscriptions_for_market_subscription(subscription.id, conn)?.is_empty());
        Ok(())
    });
}

// ----- who gets notified ---------------------------------------------------------------------

fn content_for(
    subscription: &models::MarketSubscription,
    author: &models::User,
    buyer: &models::User,
) -> FulfillmentNoteNotificationContent {
    FulfillmentNoteNotificationContent {
        market_subscription_id: subscription.id,
        author_user_id: author.id,
        buyer_id: buyer.id,
        buyer_username: buyer.username.clone(),
        note_text: "Your server is up!".to_string(),
        new_status_label: None,
    }
}

fn recipient_user_ids(
    conn: &mut Conn,
    content: &FulfillmentNoteNotificationContent,
) -> Vec<i64> {
    let mut ids: Vec<i64> = fulfillment_note_recipients(content, conn)
        .expect("recipients should load")
        .into_iter()
        .map(|s| s.user_id)
        .collect();
    ids.sort_unstable();
    ids
}

#[test]
fn a_note_notifies_the_other_side_but_never_its_own_author() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_push_who");
        for user in [&buyer, &admin] {
            register_device(conn, user, ENDPOINT);
            register_market_subscription_push(push_request(&subscription, ENDPOINT), user, conn)?;
        }

        // The admin writes -> only the buyer is pushed to, even though the admin opted in too.
        assert_eq!(recipient_user_ids(conn, &content_for(&subscription, &admin, &buyer)), vec![buyer.id]);
        // The buyer writes -> only the admin.
        assert_eq!(recipient_user_ids(conn, &content_for(&subscription, &buyer, &buyer)), vec![admin.id]);
        Ok(())
    });
}

#[test]
fn only_devices_that_opted_in_to_this_subscription_are_notified() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_push_optin");
        let other_product = hosting_product(conn, &admin);
        let other_subscription = hosting_subscription(conn, &buyer, &other_product);
        register_device(conn, &buyer, ENDPOINT);
        // Opted in to the *other* subscription only.
        register_market_subscription_push(push_request(&other_subscription, ENDPOINT), &buyer, conn)?;
        // A registered-for-Messages device that never opted in to anything.
        register_device(conn, &admin, ENDPOINT);

        assert!(recipient_user_ids(conn, &content_for(&subscription, &admin, &buyer)).is_empty());
        Ok(())
    });
}

#[test]
fn losing_admin_stops_an_opted_in_admins_notifications_but_the_buyer_never_needs_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_push_revoked");
        let second_admin = self::admin(conn, "mkt_push_revoked_admin2");
        for user in [&buyer, &admin, &second_admin] {
            register_device(conn, user, ENDPOINT);
            register_market_subscription_push(push_request(&subscription, ENDPOINT), user, conn)?;
        }
        grant_permissions(conn, &admin, vec![Permission::ViewPosts]); // no longer an Admin

        let ids = recipient_user_ids(conn, &content_for(&subscription, &second_admin, &buyer));
        assert_eq!(ids, vec![buyer.id], "the ex-admin must not keep receiving the buyer's chat");
        Ok(())
    });
}

// ----- wiring into UpdateMarketSubscription --------------------------------------------------

fn note_request(
    subscription: &models::MarketSubscription,
    author: &models::User,
    text: &str,
) -> MarketSubscription {
    MarketSubscription {
        id: subscription.id.to_proto_id(),
        details: Some(market_subscription::Details::RellmHostingSubscriptionDetails(
            RellmHostingSubscriptionDetails {
                fulfillment_notes: vec![FulfillmentNote {
                    user_id: author.id.to_proto_id(),
                    note: text.to_string(),
                    fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
                    created_at: None,
                }],
                ..Default::default()
            },
        )),
        ..Default::default()
    }
}

#[test]
fn the_notifying_variant_stores_the_same_notes_and_tolerates_having_no_runtime_to_push_with() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (_buyer, admin, subscription) = setup(conn, "mkt_push_update");

        // Plain `#[test]`, so no Tokio runtime: `notify_fulfillment_note` logs and skips, and the
        // note itself must still be stored and returned.
        let updated = update_market_subscription_and_notify(
            note_request(&subscription, &admin, "Setting up DNS."),
            &admin,
            conn,
            test_pool(),
        )?;
        let Some(market_subscription::Details::RellmHostingSubscriptionDetails(details)) = updated.details else {
            panic!("expected hosting details");
        };
        assert_eq!(details.fulfillment_notes.len(), 1);
        assert_eq!(details.fulfillment_notes[0].note, "Setting up DNS.");
        Ok(())
    });
}

#[test]
fn a_rejected_update_is_rejected_by_the_notifying_variant_too() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_push_update_rej");

        // Same validation as the plain variant: not an admin...
        let err = update_market_subscription_and_notify(
            note_request(&subscription, &buyer, "hi"),
            &buyer,
            conn,
            test_pool(),
        )
        .unwrap_err();
        let plain_err = update_market_subscription(note_request(&subscription, &buyer, "hi"), &buyer, conn)
            .unwrap_err();
        assert_eq!(err.message(), plain_err.message());

        // ...and a note attributed to someone else.
        let err = update_market_subscription_and_notify(
            note_request(&subscription, &buyer, "spoof"),
            &admin,
            conn,
            test_pool(),
        )
        .unwrap_err();
        assert_eq!(err.message(), "fulfillment_note_user_id_mismatch");
        Ok(())
    });
}

// ----- MarkFulfillmentNotesRead --------------------------------------------------------------

fn notes_last_read_of(subscription: &MarketSubscription) -> Option<prost_wkt_types::Timestamp> {
    match &subscription.details {
        Some(market_subscription::Details::RellmHostingSubscriptionDetails(d)) => d.notes_last_read.clone(),
        other => panic!("expected hosting details, got {:?}", other),
    }
}

fn mark_read_request(subscription: &models::MarketSubscription) -> MarkFulfillmentNotesReadRequest {
    MarkFulfillmentNotesReadRequest { market_subscription_id: subscription.id.to_proto_id() }
}

#[test]
fn the_buyer_marking_notes_read_stamps_notes_last_read_and_nothing_else() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_read_stamp");
        update_market_subscription(note_request(&subscription, &admin, "Server is up."), &admin, conn)?;

        let before = crate::rpcs::mark_fulfillment_notes_read(mark_read_request(&subscription), &buyer, conn)?;
        assert!(notes_last_read_of(&before).is_some());
        let Some(market_subscription::Details::RellmHostingSubscriptionDetails(details)) = &before.details else {
            panic!("expected hosting details");
        };
        assert_eq!(details.fulfillment_notes.len(), 1, "notes untouched");
        assert_eq!(details.domain, "band.rellm.org", "other details untouched");

        // Idempotent: marking again just moves the timestamp forward, never backward or to unset.
        let after = crate::rpcs::mark_fulfillment_notes_read(mark_read_request(&subscription), &buyer, conn)?;
        let (a, b) = (notes_last_read_of(&before).unwrap(), notes_last_read_of(&after).unwrap());
        assert!((b.seconds, b.nanos) >= (a.seconds, a.nanos));
        Ok(())
    });
}

#[test]
fn notes_last_read_starts_unset() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, _admin, _subscription) = setup(conn, "mkt_read_unset");
        let listed = crate::rpcs::get_market_subscriptions(GetMarketSubscriptionsRequest::default(), &buyer, conn)?;
        assert!(notes_last_read_of(&listed.market_subscriptions[0]).is_none());
        Ok(())
    });
}

#[test]
fn only_the_buyer_may_mark_read_not_even_an_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (_buyer, admin, subscription) = setup(conn, "mkt_read_authz");
        let stranger = create_user(conn, "mkt_read_authz_stranger");
        for who in [&admin, &stranger] {
            let err = crate::rpcs::mark_fulfillment_notes_read(mark_read_request(&subscription), who, conn)
                .unwrap_err();
            assert_eq!(err.code(), tonic::Code::PermissionDenied);
            assert_eq!(err.message(), "only_the_buyer_can_mark_notes_read");
        }
        Ok(())
    });
}

#[test]
fn marking_read_works_for_any_subscription_type_and_rejects_unknown_ids() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn, "mkt_read_type_admin");
        let product = create_market_product(
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
                    MediaStorageSubscriptionDetails { allocation_bytes: 1, ..Default::default() },
                )),
            },
            &admin,
            conn,
        )?;
        let buyer = create_user(conn, "mkt_read_type_buyer");
        let subscription = models::insert_market_subscription(
            &models::NewMarketSubscription {
                buyer_id: buyer.id,
                product_id: product.id.to_db_id().unwrap(),
                product_type: PurchaseType::MediaStorage.to_string_purchase_type(),
                period: PurchasePeriod::Monthly.to_string_purchase_period(),
                amount: 500,
                currency: 840,
                details: serde_json::to_value(MediaStorageSubscriptionDetails { allocation_bytes: 1, ..Default::default() }).unwrap(),
                renews_at: None,
                stripe_customer_id: None,
                stripe_payment_method_id: None,
            },
            conn,
        )?;
        let marked = crate::rpcs::mark_fulfillment_notes_read(mark_read_request(&subscription), &buyer, conn)?;
        let Some(market_subscription::Details::MediaStorageSubscriptionDetails(details)) = marked.details else {
            panic!("expected media storage details");
        };
        assert!(details.notes_last_read.is_some(), "the marker is stamped on any type's details");

        let err = crate::rpcs::mark_fulfillment_notes_read(
            MarkFulfillmentNotesReadRequest { market_subscription_id: 999_999_999_i64.to_proto_id() },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::NotFound);
        Ok(())
    });
}

#[test]
fn appending_a_note_preserves_the_buyers_read_marker() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (buyer, admin, subscription) = setup(conn, "mkt_read_preserved");
        let marked = crate::rpcs::mark_fulfillment_notes_read(mark_read_request(&subscription), &buyer, conn)?;

        // An admin's update (the client's copy of the details carries no notes_last_read) must not
        // clobber it -- otherwise every new note would silently mark everything unread again.
        let updated = update_market_subscription(note_request(&subscription, &admin, "More news."), &admin, conn)?;
        assert_eq!(notes_last_read_of(&updated), notes_last_read_of(&marked));
        Ok(())
    });
}

#[test]
fn a_client_cannot_set_notes_last_read_through_update_market_subscription() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let (_buyer, admin, subscription) = setup(conn, "mkt_read_clientset");
        let mut request = note_request(&subscription, &admin, "Hello.");
        if let Some(market_subscription::Details::RellmHostingSubscriptionDetails(d)) = &mut request.details {
            d.notes_last_read = Some(std::time::SystemTime::now().to_proto());
        }
        let updated = update_market_subscription(request, &admin, conn)?;
        assert!(notes_last_read_of(&updated).is_none());
        Ok(())
    });
}


// ----- every PurchaseType has a chat ---------------------------------------------------------

fn media_storage_subscription(conn: &mut Conn, buyer: &models::User, admin: &models::User) -> models::MarketSubscription {
    let product = create_market_product(
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
            details: Some(market_product::Details::MediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails {
                allocation_bytes: 1,
                ..Default::default()
            })),
        },
        admin,
        conn,
    )
    .expect("create should succeed");
    models::insert_market_subscription(
        &models::NewMarketSubscription {
            buyer_id: buyer.id,
            product_id: product.id.to_db_id().unwrap(),
            product_type: PurchaseType::MediaStorage.to_string_purchase_type(),
            period: PurchasePeriod::Monthly.to_string_purchase_period(),
            amount: 500,
            currency: 840,
            // Stored the way it was before the chat fields existed: no chat keys at all.
            details: serde_json::json!({ "allocation_bytes": 1 }),
            renews_at: None,
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to insert test media storage subscription")
}

fn media_note_request(subscription: &models::MarketSubscription, author: &models::User, text: &str) -> MarketSubscription {
    MarketSubscription {
        id: subscription.id.to_proto_id(),
        details: Some(market_subscription::Details::MediaStorageSubscriptionDetails(MediaStorageSubscriptionDetails {
            allocation_bytes: 1,
            fulfillment_notes: vec![FulfillmentNote {
                user_id: author.id.to_proto_id(),
                note: text.to_string(),
                fulfillment_status: FulfillmentStatus::AwaitingHostAdmin as i32,
                created_at: None,
            }],
            ..Default::default()
        })),
        ..Default::default()
    }
}

#[test]
fn an_admin_can_chat_on_a_media_storage_subscription_including_one_stored_before_chats_existed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn, "mkt_anytype_admin");
        let buyer = create_user(conn, "mkt_anytype_buyer");
        let subscription = media_storage_subscription(conn, &buyer, &admin);

        let updated =
            update_market_subscription(media_note_request(&subscription, &admin, "Quota bumped."), &admin, conn)?;
        let Some(market_subscription::Details::MediaStorageSubscriptionDetails(details)) = updated.details else {
            panic!("expected media storage details");
        };
        assert_eq!(details.allocation_bytes, 1, "the rest of the details is untouched");
        assert_eq!(details.fulfillment_notes.len(), 1);
        assert_eq!(details.fulfillment_notes[0].note, "Quota bumped.");
        assert!(details.fulfillment_notes[0].created_at.is_some(), "server-stamped");

        // The buyer reads it, and the marker lands on the same details.
        let marked = crate::rpcs::mark_fulfillment_notes_read(mark_read_request(&subscription), &buyer, conn)?;
        let Some(market_subscription::Details::MediaStorageSubscriptionDetails(details)) = marked.details else {
            panic!("expected media storage details");
        };
        assert!(details.notes_last_read.is_some());
        assert_eq!(details.fulfillment_notes.len(), 1, "marking read leaves the chat alone");
        Ok(())
    });
}

#[test]
fn a_non_hosting_chat_is_append_only_and_author_checked_like_any_other() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn, "mkt_anytype_rules_admin");
        let buyer = create_user(conn, "mkt_anytype_rules_buyer");
        let subscription = media_storage_subscription(conn, &buyer, &admin);

        // Someone else's id on the note.
        let err = update_market_subscription(media_note_request(&subscription, &buyer, "spoof"), &admin, conn)
            .unwrap_err();
        assert_eq!(err.message(), "fulfillment_note_user_id_mismatch");
        // Blank text with no status change.
        let err = update_market_subscription(media_note_request(&subscription, &admin, "  "), &admin, conn)
            .unwrap_err();
        assert_eq!(err.message(), "fulfillment_note_text_required");
        // No details at all.
        let err = update_market_subscription(
            MarketSubscription { id: subscription.id.to_proto_id(), ..Default::default() },
            &admin,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.message(), "subscription_details_required");
        // Dropping an existing note.
        update_market_subscription(media_note_request(&subscription, &admin, "First."), &admin, conn)?;
        let err = update_market_subscription(
            MarketSubscription {
                id: subscription.id.to_proto_id(),
                details: Some(market_subscription::Details::MediaStorageSubscriptionDetails(
                    MediaStorageSubscriptionDetails { allocation_bytes: 1, ..Default::default() },
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

#[test]
fn the_all_admin_listing_returns_every_type_while_the_fulfillment_listing_stays_hosting_only() {
    use crate::rpcs::get_market_subscriptions;
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn, "mkt_listing_admin");
        let buyer = create_user(conn, "mkt_listing_buyer");
        let media = media_storage_subscription(conn, &buyer, &admin);
        let hosting_product = hosting_product(conn, &admin);
        let hosting = hosting_subscription(conn, &buyer, &hosting_product);

        let mut ids = |request_type: GetMarketSubscriptionsRequestType| -> Vec<String> {
            get_market_subscriptions(GetMarketSubscriptionsRequest { request_type: request_type as i32 }, &admin, conn)
                .expect("admin listing should succeed")
                .market_subscriptions
                .into_iter()
                .map(|s| s.id)
                .collect()
        };
        let all = ids(GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForAllAdmin);
        assert!(all.contains(&media.id.to_proto_id()) && all.contains(&hosting.id.to_proto_id()));
        let hosting_only = ids(GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForFulfillmentAdmin);
        assert!(hosting_only.contains(&hosting.id.to_proto_id()));
        assert!(!hosting_only.contains(&media.id.to_proto_id()), "the /market/fulfillment listing is unchanged");

        // Admin-only, like the other admin view.
        let err = get_market_subscriptions(
            GetMarketSubscriptionsRequest {
                request_type: GetMarketSubscriptionsRequestType::GetMarketSubscriptionsRequestForAllAdmin as i32,
            },
            &buyer,
            conn,
        )
        .unwrap_err();
        assert!(err.message().contains("permission"), "{:?}", err);
        Ok(())
    });
}
