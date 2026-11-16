//! Specs for Rellm Subdomains (`logic::subdomains`, `rpcs::subdomain_rpcs`, `SaveMarketSubscription`):
//! host -> subscription resolution, the feed scoping the `share_content_from_*` toggles drive, and what
//! the subscriber may save. Stripe/fulfillment isn't involved -- the subscription row is inserted directly.

use std::time::SystemTime;

use diesel::prelude::*;
use diesel::Connection;
use tonic::{Code, Status};

use crate::logic::subdomains::{resolve_subdomain, SubdomainContext};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{create_market_product, get_posts_for, save_market_subscription};
use crate::schema::server_configurations;
use crate::tests::factories::*;

const FRONTEND_HOST: &str = "bullcity.test";

fn configure_frontend_host(conn: &mut crate::db_connection::PgPooledConnection) {
    let mut new_config = models::default_server_configuration();
    new_config.external_cdn_config = Some(
        serde_json::to_value(ExternalCdnConfig { frontend_host: FRONTEND_HOST.to_string(), ..Default::default() })
            .unwrap(),
    );
    diesel::insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// An active `PURCHASE_TYPE_SUBDOMAIN` subscription for `owner` (admin `admin` creates the product).
fn subscribe(
    conn: &mut crate::db_connection::PgPooledConnection,
    admin: &models::User,
    owner: &models::User,
    settings: SubdomainSettings,
) -> models::MarketSubscription {
    let product = create_market_product(
        MarketProduct {
            r#type: PurchaseType::Subdomain as i32,
            period: PurchasePeriod::Monthly as i32,
            amount: 300,
            currency: 840,
            details: Some(market_product::Details::SubdomainSubscriptionDetails(Default::default())),
            ..Default::default()
        },
        admin,
        conn,
    )
    .expect("failed to create subdomain product");
    let mut details = crate::logic::subdomains::new_subscription_details_json(owner);
    let mut parsed: SubdomainSubscriptionDetails = serde_json::from_value(details.clone()).unwrap();
    let mut merged = parsed.settings.take().unwrap();
    merged.share_content_from_followers = settings.share_content_from_followers;
    merged.share_content_from_following = settings.share_content_from_following;
    merged.share_content_from_friends = settings.share_content_from_friends;
    parsed.settings = Some(merged);
    details = serde_json::to_value(parsed).unwrap();
    models::insert_market_subscription(
        &models::NewMarketSubscription {
            buyer_id: owner.id,
            product_id: product.id.to_db_id().unwrap(),
            product_type: PurchaseType::Subdomain.to_string_purchase_type(),
            period: PurchasePeriod::Monthly.to_string_purchase_period(),
            amount: 300,
            currency: 840,
            details,
            renews_at: Some(SystemTime::now() + std::time::Duration::from_secs(86_400)),
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to create subdomain subscription")
}

fn public_post(conn: &mut crate::db_connection::PgPooledConnection, author: &models::User) -> String {
    create_post(conn, Some(author), PostOpts { visibility: Visibility::GlobalPublic, ..Default::default() })
        .id
        .to_proto_id()
}

fn scope(conn: &mut crate::db_connection::PgPooledConnection, host: &str) -> Option<SubdomainContext> {
    resolve_subdomain(Some(host), conn).expect("resolve_subdomain failed")
}

fn feed(conn: &mut crate::db_connection::PgPooledConnection, scope: &Option<SubdomainContext>) -> Vec<String> {
    let mut ids: Vec<String> = get_posts_for(GetPostsRequest::default(), &None, scope, conn)
        .expect("get_posts_for failed")
        .posts
        .into_iter()
        .map(|p| p.id)
        .collect();
    ids.sort();
    ids
}

fn sorted(mut ids: Vec<String>) -> Vec<String> {
    ids.sort();
    ids
}

#[test]
fn host_resolves_to_the_owners_active_subscription() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sdjon");
        let subscription = subscribe(conn, &admin, &owner, SubdomainSettings::default());

        let context = scope(conn, "sdjon.bullcity.test").expect("subdomain should resolve");
        assert_eq!(context.owner.id, owner.id);
        assert_eq!(context.settings.subdomain, "sdjon");
        assert_eq!(context.settings.subdomain_of, owner.id.to_proto_id());
        assert!(scope(conn, "bullcity.test").is_none(), "the parent host is not a subdomain");
        assert!(scope(conn, "nobody.bullcity.test").is_none(), "unsubscribed label");
        assert!(scope(conn, "sdjon.elsewhere.test").is_none(), "wrong parent");

        // Canceled with the paid period over -> stops resolving.
        diesel::update(crate::schema::market_subscriptions::table.find(subscription.id))
            .set((
                crate::schema::market_subscriptions::canceled_at.eq(Some(SystemTime::now())),
                crate::schema::market_subscriptions::renews_at.eq(Some(SystemTime::now() - std::time::Duration::from_secs(60))),
            ))
            .execute(conn)
            .unwrap();
        assert!(scope(conn, "sdjon.bullcity.test").is_none());
        Ok(())
    });
}

#[test]
fn feed_is_scoped_to_the_owner_plus_what_the_toggles_share() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd2_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd2owner");
        let follower = create_user(conn, "sd2follower"); // follows owner only
        let following = create_user(conn, "sd2following"); // followed by owner only
        let friend = create_user(conn, "sd2friend"); // both
        let stranger = create_user(conn, "sd2stranger");
        create_follow(conn, &follower, &owner);
        create_follow(conn, &owner, &following);
        create_follow(conn, &friend, &owner);
        create_follow(conn, &owner, &friend);

        let own = public_post(conn, &owner);
        let followers_post = public_post(conn, &follower);
        let following_post = public_post(conn, &following);
        let friends_post = public_post(conn, &friend);
        let _strangers_post = public_post(conn, &stranger);

        let subscription = subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let host = "sd2owner.bullcity.test";

        // Nothing shared: only the owner's own content.
        let context = scope(conn, host);
        assert_eq!(feed(conn, &context), vec![own.clone()]);

        let set = |conn: &mut crate::db_connection::PgPooledConnection, followers, following_, friends| {
            diesel::update(crate::schema::market_subscriptions::table.find(subscription.id))
                .set(crate::schema::market_subscriptions::details.eq(
                    serde_json::to_value(SubdomainSubscriptionDetails {
                        settings: Some(SubdomainSettings {
                            subdomain_of: owner.id.to_proto_id(),
                            subdomain: "sd2owner".to_string(),
                            share_content_from_followers: followers,
                            share_content_from_following: following_,
                            share_content_from_friends: friends,
                            custom_css_configuration: None,
                        }),
                        ..Default::default()
                    })
                    .unwrap(),
                ))
                .execute(conn)
                .unwrap();
        };

        set(conn, true, false, false);
        let context = scope(conn, host);
        assert_eq!(feed(conn, &context), sorted(vec![own.clone(), followers_post.clone(), friends_post.clone()]));
        set(conn, false, true, false);
        let context = scope(conn, host);
        assert_eq!(feed(conn, &context), sorted(vec![own.clone(), following_post.clone(), friends_post.clone()]));
        set(conn, false, false, true);
        let context = scope(conn, host);
        assert_eq!(feed(conn, &context), sorted(vec![own.clone(), friends_post.clone()]));

        // No subdomain scope at all: everything, as before.
        assert_eq!(feed(conn, &None).len(), 5);
        Ok(())
    });
}

#[test]
fn virtual_configuration_describes_the_owner_and_hides_irrelevant_tabs() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd3_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd3owner");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());

        let context = scope(conn, "sd3owner.bullcity.test").unwrap();
        let config = crate::rpcs::get_server_configuration_for((), &None, &Some(context), conn)?;
        assert_eq!(config.subdomain_settings.as_ref().unwrap().subdomain, "sd3owner");
        assert_eq!(config.server_info.unwrap().short_name.as_deref(), Some("sd3owner"));
        assert!(!config.people_settings.unwrap().visible);
        // The parent's CDN configuration is shared -- except that the subdomain keeps its own identity as the frontend host.
        assert_eq!(config.external_cdn_config.unwrap().frontend_host, "sd3owner.bullcity.test");
        Ok(())
    });
}

#[test]
fn only_the_buyer_saves_and_a_missing_stylesheet_is_kept() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd4_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd4owner");
        let other = create_user(conn, "sd4other");
        let subscription = subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let id = subscription.id.to_proto_id();

        let request = |css: Option<CustomCssConfiguration>| SaveMarketSubscriptionRequest {
            market_subscription_id: id.clone(),
            subdomain_settings: Some(SubdomainSettings {
                subdomain: "hijacked".to_string(),
                share_content_from_friends: true,
                custom_css_configuration: css,
                ..Default::default()
            }),
            keep_sharing_settings: false,
        };

        // Someone else -- even an admin -- can't.
        assert_eq!(save_market_subscription(request(None), &other, conn).unwrap_err().code(), Code::PermissionDenied);
        assert_eq!(save_market_subscription(request(None), &admin, conn).unwrap_err().code(), Code::PermissionDenied);

        // The buyer can: the CSS is stored, the label stays server-assigned.
        let saved = save_market_subscription(
            request(Some(CustomCssConfiguration { custom_css: Some("body { color: red }".to_string()), ..Default::default() })),
            &owner,
            conn,
        )?;
        let settings = Some(market_subscription::Details::SubdomainSubscriptionDetails(Default::default()))
            .and(saved.details)
            .map(|d| match d {
                market_subscription::Details::SubdomainSubscriptionDetails(d) => d.settings.unwrap(),
                _ => panic!("wrong details"),
            })
            .unwrap();
        assert_eq!(settings.subdomain, "sd4owner");
        assert!(settings.share_content_from_friends);
        // The stylesheet text is stored but never carried back in subscription payloads (`GetCustomCSS` serves it).
        assert_eq!(settings.custom_css_configuration.unwrap().custom_css, None);
        let stored = scope(conn, "sd4owner.bullcity.test").unwrap();
        assert_eq!(stored.custom_css_configuration().custom_css.as_deref(), Some("body { color: red }"));

        // An empty id means "my subdomain subscription"; no CSS in the request keeps the stored text.
        let mut keep = request(None);
        keep.market_subscription_id = String::new();
        save_market_subscription(keep, &owner, conn)?;
        let context = scope(conn, "sd4owner.bullcity.test").unwrap();
        assert_eq!(context.custom_css_configuration().custom_css.as_deref(), Some("body { color: red }"));

        // Oversized CSS is rejected like ConfigureCustomCSS.
        let too_big = CustomCssConfiguration { custom_css: Some("a".repeat(70 * 1024)), ..Default::default() };
        assert_eq!(save_market_subscription(request(Some(too_big)), &owner, conn).unwrap_err().code(), Code::InvalidArgument);
        Ok(())
    });
}

#[test]
fn a_label_can_only_be_bought_by_one_user_and_must_be_valid() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd5_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd5owner");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());

        // The owner already holds it (and may only hold one), so buying again is refused...
        assert_eq!(
            crate::logic::subdomains::validate_label_available(&owner, conn).unwrap_err().message(),
            "already_subscribed"
        );
        // A username that differs only by case maps to the same label -> taken for another user.
        let clash = create_user(conn, "SD5Owner");
        assert_eq!(
            crate::logic::subdomains::validate_label_available(&clash, conn).unwrap_err().message(),
            "subdomain_taken"
        );
        // Not a DNS label.
        let bad = create_user(conn, "sd5_bad");
        assert_eq!(
            crate::logic::subdomains::validate_label_available(&bad, conn).unwrap_err().message(),
            "username_not_a_valid_subdomain"
        );
        Ok(())
    });
}

#[test]
fn a_lapsed_label_is_released_for_a_new_buyer_and_the_index_blocks_duplicates() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd6_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let first = create_user(conn, "sd6owner");
        let subscription = subscribe(conn, &admin, &first, SubdomainSettings::default());
        let clash = create_user(conn, "SD6OWNER");

        // Held: the new buyer is refused, and the unique index refuses a second in-force row for the label.
        assert_eq!(
            crate::logic::subdomains::validate_label_available(&clash, conn).unwrap_err().message(),
            "subdomain_taken"
        );
        // A savepoint, so the failed insert doesn't poison the surrounding test transaction.
        let duplicate = conn.transaction::<(), diesel::result::Error, _>(|conn| {
            let mut details = crate::logic::subdomains::new_subscription_details_json(&first);
            details["settings"]["subdomain"] = serde_json::json!("sd6owner");
            models::insert_market_subscription(
                &models::NewMarketSubscription {
                    buyer_id: clash.id,
                    product_id: subscription.product_id,
                    product_type: PurchaseType::Subdomain.to_string_purchase_type(),
                    period: PurchasePeriod::Monthly.to_string_purchase_period(),
                    amount: 300,
                    currency: 840,
                    details,
                    renews_at: None,
                    stripe_customer_id: None,
                    stripe_payment_method_id: None,
                },
                conn,
            )
            .map(|_| ())
            .map_err(|_| diesel::result::Error::RollbackTransaction)
        });
        assert!(duplicate.is_err(), "a second in-force subscription for one label must violate the unique index");

        // The first buyer cancels and the paid period runs out; the renewal job hasn't run. The label is free for the
        // webhook once released.
        diesel::update(crate::schema::market_subscriptions::table.find(subscription.id))
            .set((
                crate::schema::market_subscriptions::canceled_at.eq(Some(SystemTime::now())),
                crate::schema::market_subscriptions::renews_at.eq(Some(SystemTime::now() - std::time::Duration::from_secs(60))),
            ))
            .execute(conn)
            .unwrap();
        let replacement = |conn: &mut crate::db_connection::PgPooledConnection| {
            conn.transaction::<(), diesel::result::Error, _>(|conn| {
                let mut details = crate::logic::subdomains::new_subscription_details_json(&first);
                details["settings"]["subdomain"] = serde_json::json!("sd6owner");
                models::insert_market_subscription(
                    &models::NewMarketSubscription {
                        buyer_id: clash.id,
                        product_id: subscription.product_id,
                        product_type: PurchaseType::Subdomain.to_string_purchase_type(),
                        period: PurchasePeriod::Monthly.to_string_purchase_period(),
                        amount: 300,
                        currency: 840,
                        details,
                        renews_at: None,
                        stripe_customer_id: None,
                        stripe_payment_method_id: None,
                    },
                    conn,
                )
                .map(|_| ())
                .map_err(|_| diesel::result::Error::RollbackTransaction)
            })
        };
        // The lapsed-but-unterminated row still reserves the label in the index: without the release, the new
        // buyer's insert fails even though `validate_label_available` (which ignores lapsed rows) says it's free.
        assert_eq!(crate::logic::subdomains::validate_label_available(&clash, conn)?, "sd6owner");
        assert!(replacement(conn).is_err(), "the index reserves a lapsed, unterminated label");

        crate::logic::subdomains::release_lapsed_subdomain_labels("sd6owner", conn)?;
        let released = models::get_market_subscription(subscription.id, conn)?;
        assert!(released.service_terminated_at.is_some(), "the lapsed subscription is terminated");
        assert!(replacement(conn).is_ok(), "and the label can then be re-bought");
        Ok(())
    });
}

#[test]
fn css_only_saves_keep_the_toggles_and_a_buyer_holds_one_subscription() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd7_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd7owner");
        subscribe(conn, &admin, &owner, SubdomainSettings { share_content_from_friends: true, ..Default::default() });

        // A CSS-only save carrying stale (all-off) toggles must not undo the stored ones.
        let saved = save_market_subscription(
            SaveMarketSubscriptionRequest {
                market_subscription_id: String::new(),
                subdomain_settings: Some(SubdomainSettings {
                    custom_css_configuration: Some(CustomCssConfiguration {
                        custom_css: Some("a{}".to_string()),
                        ..Default::default()
                    }),
                    ..Default::default()
                }),
                keep_sharing_settings: true,
            },
            &owner,
            conn,
        )?;
        let context = scope(conn, "sd7owner.bullcity.test").unwrap();
        assert!(context.settings.share_content_from_friends, "toggles kept");
        assert_eq!(context.custom_css_configuration().custom_css.as_deref(), Some("a{}"));
        assert!(saved.details.is_some());
        Ok(())
    });
}

#[test]
fn a_subdomain_is_recognized_on_the_backend_host_too() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let mut new_config = models::default_server_configuration();
        new_config.external_cdn_config = Some(
            serde_json::to_value(ExternalCdnConfig {
                frontend_host: FRONTEND_HOST.to_string(),
                backend_host: "bullcity.test.backend.example".to_string(),
                ..Default::default()
            })
            .unwrap(),
        );
        diesel::insert_into(server_configurations::table).values(&new_config).execute(conn).unwrap();
        let admin_user = create_user(conn, "sd8_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd8owner");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());

        // gRPC for the subdomain goes to `<label>.<backend_host>`; the parent's own backend host is the parent.
        assert!(scope(conn, "sd8owner.bullcity.test.backend.example").is_some());
        assert!(scope(conn, "sd8owner.bullcity.test").is_some());
        assert!(scope(conn, "bullcity.test.backend.example").is_none());
        assert!(scope(conn, "bullcity.test").is_none());

        // The virtual configuration points the page's connection at the subdomain's own backend name.
        let context = scope(conn, "sd8owner.bullcity.test");
        let config = crate::rpcs::get_server_configuration_for((), &None, &context, conn)?;
        let cdn = config.external_cdn_config.unwrap();
        assert_eq!(cdn.frontend_host, "sd8owner.bullcity.test");
        assert_eq!(cdn.backend_host, "sd8owner.bullcity.test.backend.example");
        Ok(())
    });
}

#[test]
fn a_private_profile_stays_private_on_the_subdomain() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd9_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user_with_profile(conn, "sd9owner", "Secret Name", "secret bio");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        diesel::update(crate::schema::users::table.find(owner.id))
            .set(crate::schema::users::visibility.eq(Visibility::Private.to_string_visibility()))
            .execute(conn)
            .unwrap();
        let owner = models::get_user(owner.id, conn)?;

        let context = scope(conn, "sd9owner.bullcity.test").unwrap();
        let anonymous = crate::rpcs::get_server_configuration_for((), &None, &Some(context.clone()), conn)?;
        let info = anonymous.server_info.unwrap();
        assert_eq!(info.name.as_deref(), Some("sd9owner"));
        assert_eq!(info.description, None);
        // The subdomain keeps its own identity: the page must not turn into the parent site.
        assert_eq!(anonymous.external_cdn_config.unwrap().frontend_host, "sd9owner.bullcity.test");

        let as_owner = crate::rpcs::get_server_configuration_for((), &Some(&owner), &Some(context), conn)?;
        assert_eq!(as_owner.server_info.unwrap().description.as_deref(), Some("secret bio"));
        Ok(())
    });
}

#[test]
fn feed_links_use_the_subdomains_own_domain() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd10_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd10owner");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let context = scope(conn, "sd10owner.bullcity.test");
        assert_eq!(
            crate::web::subdomain_web::feed_frontend_domain(
                FRONTEND_HOST.to_string(),
                "sd10owner.bullcity.test",
                &context
            ),
            "sd10owner.bullcity.test"
        );
        assert_eq!(
            crate::web::subdomain_web::feed_frontend_domain(FRONTEND_HOST.to_string(), FRONTEND_HOST, &None),
            FRONTEND_HOST
        );
        Ok(())
    });
}

#[test]
fn a_feed_domain_that_is_already_the_subdomain_is_not_prefixed_twice() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd11_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd11owner");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let context = scope(conn, "sd11owner.bullcity.test");
        // With `cdn_grpc` on, the configured domain is the request's own host -- already the subdomain.
        assert_eq!(
            crate::web::subdomain_web::feed_frontend_domain(
                "sd11owner.bullcity.test".to_string(),
                "sd11owner.bullcity.test",
                &context
            ),
            "sd11owner.bullcity.test"
        );
        assert_eq!(
            crate::web::subdomain_web::feed_frontend_domain(
                "bullcity.test".to_string(),
                "sd11owner.bullcity.test",
                &context
            ),
            "sd11owner.bullcity.test"
        );
        Ok(())
    });
}

#[test]
fn a_refunded_checkout_is_recorded_so_a_redelivery_cannot_grant_it() {
    use crate::schema::{market_payments, market_purchases};
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd12_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let holder = create_user(conn, "sd12holder");
        let subscription = subscribe(conn, &admin, &holder, SubdomainSettings::default());
        let product = models::get_market_product(subscription.product_id, conn)?;
        let loser = create_user(conn, "SD12HOLDER");

        // The buyer paid 250 (the price when they started checkout); the product has since been re-priced to 300.
        crate::web::stripe_webhook::record_refunded_checkout(
            conn, &loser, &product, "cs_test_1", Some("pi_1"), "re_1", 250, 978,
        )?;

        // The "already processed" lookup `process_checkout_session_completed` starts with finds it...
        let purchase = market_purchases::table
            .filter(market_purchases::stripe_checkout_session_id.eq("cs_test_1"))
            .first::<models::MarketPurchase>(conn)
            .expect("the refunded checkout is recorded");
        assert_eq!(purchase.subscription_id, None, "no subscription was granted");
        assert_eq!(purchase.buyer_id, loser.id);
        // ...and it carries the payment and the refund of it.
        let mut payments: Vec<(i32, Option<String>)> = market_payments::table
            .filter(market_payments::purchase_id.eq(purchase.id))
            .select((market_payments::amount, market_payments::stripe_refund_id))
            .load(conn)
            .unwrap();
        payments.sort();
        // The records carry what was actually charged, not the product's current price.
        assert_eq!(payments, vec![(-250, Some("re_1".to_string())), (250, None)]);
        Ok(())
    });
}

#[test]
fn an_owner_named_like_the_parents_first_label_still_gets_a_prefixed_feed_domain() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd13_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "bullcity");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let context = scope(conn, "bullcity.bullcity.test");
        assert!(context.is_some());
        // `cdn_grpc` off: the configured domain is the parent's, "bullcity.test" -- which *starts with* the owner's label.
        assert_eq!(
            crate::web::subdomain_web::feed_frontend_domain(
                "bullcity.test".to_string(),
                "bullcity.bullcity.test",
                &context
            ),
            "bullcity.bullcity.test"
        );
        Ok(())
    });
}
