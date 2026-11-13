//! Specs for `MarketSubscription.state` (`MarketSubscriptionState`) and every transition between
//! its values: `logic::subscription_state`'s derivation matrix (pure), `CancelMarketSubscription`,
//! resuming via `MakeMarketPurchase`, the renewal job's own cancellations, and termination. The
//! point of the whole feature: a buyer who cancels has still paid for the rest of their period, so
//! cancel is `SUBSCRIPTION_ACTIVE_BUT_CANCELED` (not an instant off switch), and buying again before
//! it lapses resumes that same subscription -- no second charge, no second subscription.

use std::time::{Duration, SystemTime};

use diesel::prelude::*;
use diesel::Connection;

use crate::logic::{
    renew_subscriptions_of_type, service_ends_at, subscription_state, terminate_subscriptions_of_type,
};
use crate::marshaling::{ToDbId, ToProtoId, ToStringPurchasePeriod, ToStringPurchaseType};
use crate::models;
use crate::protos::MarketSubscriptionState::{SubscriptionActive, SubscriptionActiveButCanceled, SubscriptionCanceled};
use crate::protos::*;
use crate::rpcs::{
    cancel_market_subscription, create_market_product, get_market_subscriptions, make_market_purchase,
};
use crate::schema::market_subscriptions;
use crate::tests::factories::*;

fn ago(secs: u64) -> SystemTime {
    SystemTime::now() - Duration::from_secs(secs)
}

fn from_now(secs: u64) -> SystemTime {
    SystemTime::now() + Duration::from_secs(secs)
}

// ---------------------------------------------------------------------------------------------
// `subscription_state` -- the pure derivation
// ---------------------------------------------------------------------------------------------

#[test]
fn a_subscription_that_was_never_canceled_is_active() {
    let now = SystemTime::now();
    assert_eq!(subscription_state(None, Some(from_now(100)), None, now), SubscriptionActive);
    // Even if `renews_at` is overdue (the renewal job just hasn't gotten to it yet) -- not canceled
    // is not canceled.
    assert_eq!(subscription_state(None, Some(ago(100)), None, now), SubscriptionActive);
    // A `PURCHASE_PERIOD_INDEFINITE` subscription has no `renews_at` at all.
    assert_eq!(subscription_state(None, None, None, now), SubscriptionActive);
}

#[test]
fn a_canceled_subscription_with_paid_for_time_left_is_active_but_canceled() {
    let now = SystemTime::now();
    assert_eq!(
        subscription_state(Some(ago(10)), Some(from_now(100)), None, now),
        SubscriptionActiveButCanceled
    );
}

#[test]
fn a_canceled_subscription_whose_period_has_run_out_is_canceled_even_before_the_job_terminates_it() {
    let now = SystemTime::now();
    assert_eq!(
        subscription_state(Some(ago(10)), Some(ago(5)), None, now),
        SubscriptionCanceled,
        "renews_at and canceled_at both passed, service_terminated_at just not stamped yet"
    );
}

#[test]
fn canceling_a_non_recurring_subscription_takes_effect_immediately() {
    let now = SystemTime::now();
    assert_eq!(subscription_state(Some(ago(1)), None, None, now), SubscriptionCanceled);
}

#[test]
fn a_terminated_subscription_is_canceled_regardless_of_the_other_timestamps() {
    let now = SystemTime::now();
    assert_eq!(
        subscription_state(Some(ago(10)), Some(from_now(100)), Some(ago(1)), now),
        SubscriptionCanceled
    );
    // Never produced by this codebase, but a terminated entitlement must never read as active.
    assert_eq!(subscription_state(None, None, Some(ago(1)), now), SubscriptionCanceled);
}

#[test]
fn the_exact_instant_service_ends_is_already_canceled() {
    let canceled_at = ago(10);
    let renews_at = from_now(100);
    assert_eq!(
        subscription_state(Some(canceled_at), Some(renews_at), None, renews_at),
        SubscriptionCanceled
    );
    assert_eq!(
        subscription_state(
            Some(canceled_at),
            Some(renews_at),
            None,
            renews_at - Duration::from_nanos(1)
        ),
        SubscriptionActiveButCanceled
    );
}

#[test]
fn service_ends_at_the_later_of_canceled_at_and_renews_at() {
    let early = ago(100);
    let late = from_now(100);
    assert_eq!(service_ends_at(early, Some(late)), late);
    assert_eq!(service_ends_at(late, Some(early)), late);
    assert_eq!(service_ends_at(early, None), early);
}

// ---------------------------------------------------------------------------------------------
// DB-backed transitions
// ---------------------------------------------------------------------------------------------

fn media_storage_product_request(available_count: u32) -> MarketProduct {
    MarketProduct {
        id: String::new(),
        r#type: PurchaseType::MediaStorage as i32,
        period: PurchasePeriod::Monthly as i32,
        amount: 500,
        currency: 840,
        created_at: None,
        delisted_at: None,
        available_count,
        sold_count: 0,
        details: Some(market_product::Details::MediaStorageSubscriptionDetails(
            MediaStorageSubscriptionDetails { allocation_bytes: 1_073_741_824, ..Default::default() },
        )),
    }
}

/// A product with `available_count` slots, plus an admin who made it. `sold_count` starts at 0.
fn make_product(
    conn: &mut crate::db_connection::PgPooledConnection,
    admin_name: &str,
    available_count: u32,
) -> MarketProduct {
    let admin = create_user(conn, admin_name);
    let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
    create_market_product(media_storage_product_request(available_count), &admin, conn)
        .expect("create should succeed")
}

/// Inserts a subscription the way `web::stripe_webhook` would have (including claiming a slot via
/// `increment_market_product_sold_count`), with explicit lifecycle timestamps.
fn subscribe(
    conn: &mut crate::db_connection::PgPooledConnection,
    buyer: &models::User,
    product: &MarketProduct,
    renews_at: Option<SystemTime>,
    canceled_at: Option<SystemTime>,
    service_terminated_at: Option<SystemTime>,
) -> models::MarketSubscription {
    let product_id = product.id.to_db_id().expect("product id should decode");
    let inserted = models::insert_market_subscription(
        &models::NewMarketSubscription {
            buyer_id: buyer.id,
            product_id,
            product_type: PurchaseType::MediaStorage.to_string_purchase_type(),
            period: PurchasePeriod::Monthly.to_string_purchase_period(),
            amount: 500,
            currency: 840,
            details: serde_json::to_value(MediaStorageSubscriptionDetails { allocation_bytes: 1_073_741_824, ..Default::default() })
                .unwrap(),
            renews_at,
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to insert test market subscription");
    models::increment_market_product_sold_count(product_id, conn);
    diesel::update(market_subscriptions::table.filter(market_subscriptions::id.eq(inserted.id)))
        .set((
            market_subscriptions::canceled_at.eq(canceled_at),
            market_subscriptions::service_terminated_at.eq(service_terminated_at),
        ))
        .execute(conn)
        .expect("failed to seed lifecycle timestamps");
    // A seeded-canceled subscription has already released its slot, same as a real cancel would.
    if canceled_at.is_some() {
        models::decrement_market_product_sold_count(product_id, conn);
    }
    models::get_market_subscription(inserted.id, conn).expect("reload")
}

fn sold_count(conn: &mut crate::db_connection::PgPooledConnection, product: &MarketProduct) -> i32 {
    models::get_market_product(product.id.to_db_id().unwrap(), conn)
        .expect("product should exist")
        .sold_count
}

fn cancel(
    conn: &mut crate::db_connection::PgPooledConnection,
    who: &models::User,
    subscription: &models::MarketSubscription,
) -> MarketSubscription {
    cancel_market_subscription(
        MarketSubscription { id: subscription.id.to_proto_id(), ..Default::default() },
        who,
        conn,
    )
    .expect("cancel should succeed")
}

fn buy(
    conn: &mut crate::db_connection::PgPooledConnection,
    who: &models::User,
    product: &MarketProduct,
) -> Result<MakeMarketPurchaseResponse, tonic::Status> {
    make_market_purchase(
        MakeMarketPurchaseRequest { market_product_id: product.id.clone(), rellm_hosting_details: None },
        who,
        conn,
    )
}

fn state_of(proto: &MarketSubscription) -> MarketSubscriptionState {
    MarketSubscriptionState::try_from(proto.state).expect("state should be a known value")
}

fn subscription_count(conn: &mut crate::db_connection::PgPooledConnection, buyer: &models::User) -> usize {
    models::get_market_subscriptions_for_buyer(buyer.id, conn).unwrap().len()
}

#[test]
fn a_fresh_subscription_is_listed_as_active() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_state_fresh_admin", 0);
        let buyer = create_user(conn, "mkt_state_fresh_buyer");
        subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);

        let listed = get_market_subscriptions(
            GetMarketSubscriptionsRequest::default(),
            &buyer,
            conn,
        )?;
        assert_eq!(listed.market_subscriptions.len(), 1);
        assert_eq!(state_of(&listed.market_subscriptions[0]), SubscriptionActive);
        Ok(())
    });
}

#[test]
fn canceling_a_paid_up_subscription_keeps_it_active_but_canceled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_state_cancel_admin", 0);
        let buyer = create_user(conn, "mkt_state_cancel_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);

        let canceled = cancel(conn, &buyer, &subscription);
        assert_eq!(state_of(&canceled), SubscriptionActiveButCanceled);
        assert!(canceled.canceled_at.is_some());
        assert!(canceled.service_terminated_at.is_none(), "entitlement is still in force");

        // And that's what listing it back says too, not just the cancel response.
        let listed = get_market_subscriptions(GetMarketSubscriptionsRequest::default(), &buyer, conn)?;
        assert_eq!(state_of(&listed.market_subscriptions[0]), SubscriptionActiveButCanceled);
        Ok(())
    });
}

#[test]
fn canceling_a_non_recurring_subscription_is_canceled_right_away() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_state_nonrecurring_admin", 0);
        let buyer = create_user(conn, "mkt_state_nonrecurring_buyer");
        let subscription = subscribe(conn, &buyer, &product, None, None, None);

        let canceled = cancel(conn, &buyer, &subscription);
        assert_eq!(state_of(&canceled), SubscriptionCanceled);
        Ok(())
    });
}

#[test]
fn recanceling_leaves_state_and_canceled_at_untouched() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_state_recancel_admin", 0);
        let buyer = create_user(conn, "mkt_state_recancel_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);

        let first = cancel(conn, &buyer, &subscription);
        let second = cancel(conn, &buyer, &subscription);
        assert_eq!(state_of(&second), SubscriptionActiveButCanceled);
        assert_eq!(first.canceled_at, second.canceled_at);
        Ok(())
    });
}

#[test]
fn termination_moves_an_elapsed_canceled_subscription_to_canceled_and_stays_there() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_state_terminate_admin", 0);
        let buyer = create_user(conn, "mkt_state_terminate_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(ago(5)), Some(ago(10)), None);

        terminate_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        let listed = get_market_subscriptions(GetMarketSubscriptionsRequest::default(), &buyer, conn)?;
        let proto = &listed.market_subscriptions[0];
        assert_eq!(state_of(proto), SubscriptionCanceled);
        assert!(proto.service_terminated_at.is_some());
        // Cancel after the fact is an idempotent no-op that doesn't resurrect anything.
        assert_eq!(state_of(&cancel(conn, &buyer, &subscription)), SubscriptionCanceled);
        Ok(())
    });
}

#[test]
fn the_termination_job_leaves_an_active_but_canceled_subscription_alone() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_state_notyet_admin", 0);
        let buyer = create_user(conn, "mkt_state_notyet_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), Some(ago(10)), None);

        terminate_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        let reloaded = models::get_market_subscription(subscription.id, conn)?;
        assert!(reloaded.service_terminated_at.is_none(), "the buyer paid for that time");
        Ok(())
    });
}

// ----- resuming ------------------------------------------------------------------------------

#[test]
fn buying_again_while_active_but_canceled_resumes_without_a_checkout() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // Deliberately no Stripe configured: resuming must not need it.
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_admin", 0);
        let buyer = create_user(conn, "mkt_resume_buyer");
        let renews_at = from_now(3600);
        let subscription = subscribe(conn, &buyer, &product, Some(renews_at), None, None);
        cancel(conn, &buyer, &subscription);

        let response = buy(conn, &buyer, &product)?;

        assert!(response.checkout_url.is_empty(), "nothing to pay for");
        let resumed = response.resumed_subscription.expect("should report the resumed subscription");
        assert_eq!(resumed.id, subscription.id.to_proto_id());
        assert_eq!(state_of(&resumed), SubscriptionActive);
        assert!(resumed.canceled_at.is_none());
        let reloaded = models::get_market_subscription(subscription.id, conn)?;
        assert!(reloaded.canceled_at.is_none());
        assert_eq!(reloaded.renews_at, subscription.renews_at, "the paid-for period is untouched");
        assert_eq!(subscription_count(conn, &buyer), 1, "no second subscription");
        Ok(())
    });
}

#[test]
fn resuming_reclaims_the_slot_cancellation_freed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_slots_admin", 5);
        let buyer = create_user(conn, "mkt_resume_slots_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);
        assert_eq!(sold_count(conn, &product), 1);

        cancel(conn, &buyer, &subscription);
        assert_eq!(sold_count(conn, &product), 0);

        buy(conn, &buyer, &product)?;
        assert_eq!(sold_count(conn, &product), 1);

        // And the cycle is symmetric however many times it repeats.
        cancel(conn, &buyer, &subscription);
        assert_eq!(sold_count(conn, &product), 0);
        buy(conn, &buyer, &product)?;
        assert_eq!(sold_count(conn, &product), 1);
        Ok(())
    });
}

#[test]
fn a_resumed_subscription_can_be_canceled_again() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_recancel_admin", 0);
        let buyer = create_user(conn, "mkt_resume_recancel_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);
        cancel(conn, &buyer, &subscription);
        buy(conn, &buyer, &product)?;

        let canceled_again = cancel(conn, &buyer, &subscription);
        assert_eq!(state_of(&canceled_again), SubscriptionActiveButCanceled);
        Ok(())
    });
}

#[test]
fn resuming_is_refused_when_someone_else_took_the_freed_slot() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_soldout_admin", 1);
        let buyer = create_user(conn, "mkt_resume_soldout_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);
        cancel(conn, &buyer, &subscription);
        // A new buyer claims the only slot (what their completed checkout's webhook would do).
        models::increment_market_product_sold_count(product.id.to_db_id().unwrap(), conn);

        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "product_sold_out");

        let reloaded = models::get_market_subscription(subscription.id, conn)?;
        assert!(reloaded.canceled_at.is_some(), "stays canceled");
        assert_eq!(sold_count(conn, &product), 1, "and the other buyer's slot is not disturbed");
        Ok(())
    });
}

#[test]
fn a_delisted_product_can_still_be_resumed_since_the_buyer_already_paid() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_delisted_admin", 0);
        let buyer = create_user(conn, "mkt_resume_delisted_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);
        cancel(conn, &buyer, &subscription);
        diesel::update(crate::schema::market_products::table.find(product.id.to_db_id().unwrap()))
            .set(crate::schema::market_products::delisted_at.eq(Some(SystemTime::now())))
            .execute(conn)
            .unwrap();

        let response = buy(conn, &buyer, &product)?;
        assert!(response.resumed_subscription.is_some());
        Ok(())
    });
}

#[test]
fn resuming_respects_market_being_disabled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // Market left closed (the default).
        let product = make_product(conn, "mkt_resume_disabled_admin", 0);
        let buyer = create_user(conn, "mkt_resume_disabled_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);
        cancel(conn, &buyer, &subscription);

        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "market_disabled");
        assert!(models::get_market_subscription(subscription.id, conn)?.canceled_at.is_some());
        Ok(())
    });
}

#[test]
fn a_subscription_that_already_lapsed_is_not_resumed_buying_starts_a_new_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_lapsed_admin", 0);
        let buyer = create_user(conn, "mkt_resume_lapsed_buyer");
        // Paid-for period over, termination job not yet run: `SUBSCRIPTION_CANCELED` already.
        let subscription = subscribe(conn, &buyer, &product, Some(ago(5)), Some(ago(10)), None);

        // Falls through to the normal checkout path -- which, with no Stripe configured here, is
        // where it stops. Anything but `stripe_not_configured` would mean it resumed.
        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "stripe_not_configured");
        assert!(models::get_market_subscription(subscription.id, conn)?.canceled_at.is_some());
        Ok(())
    });
}

#[test]
fn a_terminated_subscription_is_never_resumed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_terminated_admin", 0);
        let buyer = create_user(conn, "mkt_resume_terminated_buyer");
        // Even with `renews_at` somehow still in the future, `service_terminated_at` means the
        // entitlement is already gone.
        let subscription =
            subscribe(conn, &buyer, &product, Some(from_now(3600)), Some(ago(10)), Some(ago(1)));

        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "stripe_not_configured");
        assert!(models::get_market_subscription(subscription.id, conn)?.service_terminated_at.is_some());
        Ok(())
    });
}

#[test]
fn a_non_recurring_canceled_subscription_is_not_resumable() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_norenew_admin", 0);
        let buyer = create_user(conn, "mkt_resume_norenew_buyer");
        let subscription = subscribe(conn, &buyer, &product, None, None, None);
        cancel(conn, &buyer, &subscription);

        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "stripe_not_configured");
        Ok(())
    });
}

#[test]
fn only_the_buyers_own_subscription_to_that_same_product_is_resumed() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_scope_admin", 0);
        let other_product = {
            let admin = create_user(conn, "mkt_resume_scope_admin2");
            let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
            create_market_product(media_storage_product_request(0), &admin, conn)?
        };
        let buyer = create_user(conn, "mkt_resume_scope_buyer");
        let someone_else = create_user(conn, "mkt_resume_scope_other");

        let others_subscription = subscribe(conn, &someone_else, &product, Some(from_now(3600)), Some(ago(1)), None);
        let other_product_subscription =
            subscribe(conn, &buyer, &other_product, Some(from_now(3600)), Some(ago(1)), None);

        // The buyer has nothing resumable for `product`: someone else's canceled subscription to
        // it, and their own canceled subscription to a *different* product, both must be ignored.
        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "stripe_not_configured");
        assert!(models::get_market_subscription(others_subscription.id, conn)?.canceled_at.is_some());
        assert!(models::get_market_subscription(other_product_subscription.id, conn)?.canceled_at.is_some());
        Ok(())
    });
}

#[test]
fn an_active_subscription_is_not_touched_by_buying_the_product_again() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_active_admin", 5);
        let buyer = create_user(conn, "mkt_resume_active_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);

        // Nothing to resume -> normal checkout path (unconfigured Stripe stops it there).
        let err = buy(conn, &buyer, &product).unwrap_err();
        assert_eq!(err.message(), "stripe_not_configured");
        assert!(models::get_market_subscription(subscription.id, conn)?.canceled_at.is_none());
        assert_eq!(sold_count(conn, &product), 1, "resume's slot accounting must not run");
        Ok(())
    });
}

#[test]
fn resumed_subscriptions_renew_again_and_are_no_longer_terminable() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_market(conn, true);
        let product = make_product(conn, "mkt_resume_jobs_admin", 0);
        let buyer = create_user(conn, "mkt_resume_jobs_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);
        let purchase_type = PurchaseType::MediaStorage.to_string_purchase_type();

        cancel(conn, &buyer, &subscription);
        buy(conn, &buyer, &product)?;

        // Move the clock forward by rewinding `renews_at`: once the period elapses, the resumed
        // subscription is due for renewal like any active one...
        diesel::update(market_subscriptions::table.find(subscription.id))
            .set(market_subscriptions::renews_at.eq(Some(ago(5))))
            .execute(conn)
            .unwrap();
        let due = models::get_due_market_subscriptions(&purchase_type, conn)?;
        assert!(due.iter().any(|s| s.id == subscription.id));
        // ...and was never terminable.
        let terminable = models::get_terminable_market_subscriptions(&purchase_type, conn)?;
        assert!(terminable.iter().all(|s| s.id != subscription.id));
        Ok(())
    });
}

// ----- the renewal job's own cancellations ---------------------------------------------------

#[test]
fn a_failed_renewal_cancels_the_subscription_and_frees_its_slot() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // No Stripe configured: every due subscription is ended (see `renew_subscriptions_of_type`).
        let product = make_product(conn, "mkt_renew_fail_admin", 3);
        let buyer = create_user(conn, "mkt_renew_fail_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(ago(5)), None, None);
        assert_eq!(sold_count(conn, &product), 1);

        renew_subscriptions_of_type(PurchaseType::MediaStorage, conn)?;

        let reloaded = models::get_market_subscription(subscription.id, conn)?;
        assert!(reloaded.canceled_at.is_some());
        assert_eq!(sold_count(conn, &product), 0, "ending a subscription frees its slot like a cancel");
        let listed = get_market_subscriptions(GetMarketSubscriptionsRequest::default(), &buyer, conn)?;
        assert_eq!(
            state_of(&listed.market_subscriptions[0]),
            SubscriptionCanceled,
            "its paid-for period was already over, so it is not resumable"
        );

        // The buyer then explicitly canceling it must not free the slot a second time.
        cancel(conn, &buyer, &subscription);
        assert_eq!(sold_count(conn, &product), 0);
        Ok(())
    });
}

// ----- the atomic resume/cancel primitives (what concurrent requests race on) -----------------

#[test]
fn a_second_resume_of_the_same_subscription_reports_already_active_and_claims_no_second_slot() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_atomic_twice_admin", 5);
        let buyer = create_user(conn, "mkt_atomic_twice_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), Some(ago(10)), None);
        let product_id = product.id.to_db_id().unwrap();

        let first = models::resume_market_subscription_and_claim_slot(subscription.id, product_id, conn)?;
        let second = models::resume_market_subscription_and_claim_slot(subscription.id, product_id, conn)?;

        assert_eq!(first, models::ResumeOutcome::Resumed);
        assert_eq!(second, models::ResumeOutcome::AlreadyActive);
        assert_eq!(sold_count(conn, &product), 1, "only the call that actually resumed claims a slot");
        Ok(())
    });
}

#[test]
fn resume_primitive_reports_sold_out_and_not_resumable() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_atomic_outcomes_admin", 1);
        let product_id = product.id.to_db_id().unwrap();
        let buyer = create_user(conn, "mkt_atomic_outcomes_buyer");
        let paid_up = subscribe(conn, &buyer, &product, Some(from_now(3600)), Some(ago(10)), None);
        models::increment_market_product_sold_count(product_id, conn); // someone else took the slot
        assert_eq!(
            models::resume_market_subscription_and_claim_slot(paid_up.id, product_id, conn)?,
            models::ResumeOutcome::SoldOut
        );
        assert!(models::get_market_subscription(paid_up.id, conn)?.canceled_at.is_some());

        let lapsed = subscribe(conn, &buyer, &product, Some(ago(5)), Some(ago(10)), None);
        diesel::update(crate::schema::market_products::table.find(product_id))
            .set(crate::schema::market_products::sold_count.eq(0))
            .execute(conn)
            .unwrap();
        assert_eq!(
            models::resume_market_subscription_and_claim_slot(lapsed.id, product_id, conn)?,
            models::ResumeOutcome::NotResumable
        );
        assert_eq!(sold_count(conn, &product), 0, "a failed resume claims nothing");
        Ok(())
    });
}

#[test]
fn cancel_primitive_releases_exactly_one_slot_however_often_it_is_called() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let product = make_product(conn, "mkt_atomic_cancel_admin", 5);
        let product_id = product.id.to_db_id().unwrap();
        let buyer = create_user(conn, "mkt_atomic_cancel_buyer");
        let subscription = subscribe(conn, &buyer, &product, Some(from_now(3600)), None, None);

        assert!(models::cancel_market_subscription_and_release_slot(subscription.id, product_id, conn)?);
        assert!(!models::cancel_market_subscription_and_release_slot(subscription.id, product_id, conn)?);
        assert_eq!(sold_count(conn, &product), 0);
        Ok(())
    });
}
