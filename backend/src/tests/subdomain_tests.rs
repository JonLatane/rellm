//! Specs for Rellm Subdomains (`logic::subdomains`, `rpcs::subdomain_rpcs`, `SaveSubdomainSettings`,
//! `SetUserSubdomain`): host -> user resolution (a subscription in force *or* an admin's grant enables it), the feed
//! scoping the `share_content_from_*` toggles drive, and what the owner may save. The settings live on the `users` row.
//! Stripe/fulfillment isn't involved -- the subscription row is inserted directly.

use std::time::SystemTime;

use diesel::prelude::*;
use diesel::Connection;
use tonic::{Code, Status};

use crate::logic::subdomains::{resolve_subdomain, SubdomainContext};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{create_market_product, get_posts_for, save_subdomain_settings, set_user_subdomain};
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

/// Writes the subdomain state of `owner`'s user row directly -- the label (their lower-cased username, *without* the
/// checks `claim_label` makes, so a spec can also set up what the checks forbid) and the sharing toggles.
fn set_row(
    conn: &mut crate::db_connection::PgPooledConnection,
    owner: &models::User,
    settings: &SubdomainSettings,
) {
    use crate::schema::users;
    diesel::update(users::table.find(owner.id))
        .set((
            users::subdomain.eq(Some(crate::logic::subdomains::label_for_username(&owner.username))),
            users::subdomain_share_followers.eq(settings.share_content_from_followers),
            users::subdomain_share_following.eq(settings.share_content_from_following),
            users::subdomain_share_friends.eq(settings.share_content_from_friends),
        ))
        .execute(conn)
        .expect("failed to set the subdomain row");
}

/// Changes just the sharing toggles of `owner`'s row.
fn set_toggles(
    conn: &mut crate::db_connection::PgPooledConnection,
    owner: &models::User,
    followers: bool,
    following: bool,
    friends: bool,
) {
    use crate::schema::users;
    diesel::update(users::table.find(owner.id))
        .set((
            users::subdomain_share_followers.eq(followers),
            users::subdomain_share_following.eq(following),
            users::subdomain_share_friends.eq(friends),
        ))
        .execute(conn)
        .unwrap();
}

/// A subscription in force for `owner` (admin `admin` creates the product), as fulfillment leaves things: the label is
/// held on the user row and the settings are theirs.
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
    set_row(conn, owner, &settings);
    models::insert_market_subscription(
        &models::NewMarketSubscription {
            buyer_id: owner.id,
            product_id: product.id.to_db_id().unwrap(),
            product_type: PurchaseType::Subdomain.to_string_purchase_type(),
            period: PurchasePeriod::Monthly.to_string_purchase_period(),
            amount: 300,
            currency: 840,
            details: crate::logic::subdomains::new_subscription_details_json(),
            renews_at: Some(SystemTime::now() + std::time::Duration::from_secs(86_400)),
            stripe_customer_id: None,
            stripe_payment_method_id: None,
        },
        conn,
    )
    .expect("failed to create subdomain subscription")
}

/// Cancels `subscription` with its paid period over (what the renewal job would then terminate).
fn lapse(conn: &mut crate::db_connection::PgPooledConnection, subscription: &models::MarketSubscription) {
    diesel::update(crate::schema::market_subscriptions::table.find(subscription.id))
        .set((
            crate::schema::market_subscriptions::canceled_at.eq(Some(SystemTime::now())),
            crate::schema::market_subscriptions::renews_at.eq(Some(SystemTime::now() - std::time::Duration::from_secs(60))),
        ))
        .execute(conn)
        .unwrap();
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
fn host_resolves_to_a_user_with_a_subscription_or_an_admin_grant() {
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

        // Canceled with the paid period over -> stops resolving (the user still holds the label until it is released).
        lapse(conn, &subscription);
        assert!(scope(conn, "sdjon.bullcity.test").is_none());
        // ...unless an admin has enabled it for them: the grant alone keeps it resolving, subscription or not.
        diesel::update(crate::schema::users::table.find(owner.id))
            .set(crate::schema::users::subdomain_granted_by_admin.eq(true))
            .execute(conn)
            .unwrap();
        assert!(scope(conn, "sdjon.bullcity.test").is_some());
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

        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let host = "sd2owner.bullcity.test";

        // Nothing shared: only the owner's own content.
        let context = scope(conn, host);
        assert_eq!(feed(conn, &context), vec![own.clone()]);

        let set = |conn: &mut crate::db_connection::PgPooledConnection, followers, following_, friends| {
            set_toggles(conn, &owner, followers, following_, friends);
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
fn only_an_enabled_owner_saves_and_a_missing_stylesheet_is_kept() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd4_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd4owner");
        let other = create_user(conn, "sd4other");
        let subscription = subscribe(conn, &admin, &owner, SubdomainSettings::default());

        let request = |css: Option<CustomCssConfiguration>| SaveSubdomainSettingsRequest {
            subdomain_settings: Some(SubdomainSettings {
                subdomain: "hijacked".to_string(),
                share_content_from_friends: true,
                custom_css_configuration: css,
                ..Default::default()
            }),
            keep_sharing_settings: false,
        };

        // Someone with no subdomain enabled -- even an admin -- can't save anything; saves only ever touch the caller's own.
        assert_eq!(save_subdomain_settings(request(None), &other, conn).unwrap_err().message(), "subdomain_not_enabled");
        assert_eq!(save_subdomain_settings(request(None), &admin, conn).unwrap_err().message(), "subdomain_not_enabled");
        assert_eq!(
            save_subdomain_settings(SaveSubdomainSettingsRequest::default(), &owner, conn).unwrap_err().code(),
            Code::InvalidArgument
        );

        // The owner can: the CSS is stored, the label stays server-assigned.
        let saved = save_subdomain_settings(
            request(Some(CustomCssConfiguration { custom_css: Some("body { color: red }".to_string()), ..Default::default() })),
            &owner,
            conn,
        )?;
        assert!(saved.enabled && saved.subscribed && !saved.granted_by_admin);
        let settings = saved.settings.unwrap();
        assert_eq!(settings.subdomain, "sd4owner");
        assert!(settings.share_content_from_friends);
        // The stylesheet text is stored but never carried back (`GetCustomCSS` serves it).
        assert_eq!(settings.custom_css_configuration, None);
        let stored = scope(conn, "sd4owner.bullcity.test").unwrap();
        assert_eq!(stored.custom_css_configuration().custom_css.as_deref(), Some("body { color: red }"));

        // No CSS in the request keeps the stored text; an unset `custom_css` inside one keeps it too.
        save_subdomain_settings(request(None), &owner, conn)?;
        let context = scope(conn, "sd4owner.bullcity.test").unwrap();
        assert_eq!(context.custom_css_configuration().custom_css.as_deref(), Some("body { color: red }"));
        save_subdomain_settings(request(Some(CustomCssConfiguration::default())), &owner, conn)?;
        let context = scope(conn, "sd4owner.bullcity.test").unwrap();
        assert_eq!(context.custom_css_configuration().custom_css.as_deref(), Some("body { color: red }"));

        // Oversized CSS is rejected like ConfigureCustomCSS.
        let too_big = CustomCssConfiguration { custom_css: Some("a".repeat(70 * 1024)), ..Default::default() };
        assert_eq!(save_subdomain_settings(request(Some(too_big)), &owner, conn).unwrap_err().code(), Code::InvalidArgument);

        // Once the subscription lapses, so does the right to save (the settings themselves are kept).
        lapse(conn, &subscription);
        assert_eq!(save_subdomain_settings(request(None), &owner, conn).unwrap_err().message(), "subdomain_not_enabled");
        Ok(())
    });
}

#[test]
fn a_label_can_only_be_held_by_one_user_and_must_be_valid() {
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
fn a_lapsed_label_is_released_for_a_new_claimant_and_the_index_blocks_duplicates() {
    use crate::schema::users;
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd6_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let first = create_user(conn, "sd6owner");
        let subscription = subscribe(conn, &admin, &first, SubdomainSettings { share_content_from_friends: true, ..Default::default() });
        let clash = create_user(conn, "SD6OWNER");

        // Held: the new claimant is refused, and the unique index refuses a second holder of the label.
        assert_eq!(crate::logic::subdomains::claim_label(&clash, conn).unwrap_err().message(), "subdomain_taken");
        // A savepoint, so the failed update doesn't poison the surrounding test transaction.
        let duplicate = conn.transaction::<usize, diesel::result::Error, _>(|conn| {
            diesel::update(users::table.find(clash.id)).set(users::subdomain.eq(Some("sd6owner".to_string()))).execute(conn)
        });
        assert!(duplicate.is_err(), "a second holder of one label must violate the unique index");

        // The first owner cancels and the paid period runs out; the renewal job hasn't run. The label is free for the
        // newcomer (the holder is released as part of the check)...
        lapse(conn, &subscription);
        assert_eq!(crate::logic::subdomains::validate_label_available(&clash, conn)?, "sd6owner");
        let released = models::get_subdomain_summary(first.id, conn)?;
        assert_eq!(released.subdomain, None, "the lapsed holder lost the label");
        assert!(released.subdomain_share_friends, "but keeps their settings for when they come back");
        // ...who can now take it.
        assert_eq!(crate::logic::subdomains::claim_label(&clash, conn)?, "sd6owner");
        assert_eq!(models::get_subdomain_summary(clash.id, conn)?.subdomain.as_deref(), Some("sd6owner"));
        Ok(())
    });
}

#[test]
fn terminating_a_subscription_frees_the_label_unless_an_admin_granted_it() {
    use crate::logic::terminate_entitlement;
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd20_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let lapsed = create_user(conn, "sd20lapsed");
        let granted = create_user(conn, "sd20granted");
        let lapsed_subscription = subscribe(conn, &admin, &lapsed, SubdomainSettings::default());
        let granted_subscription = subscribe(conn, &admin, &granted, SubdomainSettings::default());
        set_user_subdomain(SetUserSubdomainRequest { user_id: granted.id.to_proto_id(), enabled: true }, &admin, conn)?;
        lapse(conn, &lapsed_subscription);
        lapse(conn, &granted_subscription);

        // What `renew_market_subscriptions` runs once a canceled subscription's paid period is over.
        for user in [&lapsed, &granted] {
            terminate_entitlement(PurchaseType::Subdomain, user.id, &serde_json::json!({}), conn)?;
        }
        assert_eq!(models::get_subdomain_summary(lapsed.id, conn)?.subdomain, None);
        assert_eq!(
            models::get_subdomain_summary(granted.id, conn)?.subdomain.as_deref(),
            Some("sd20granted"),
            "the admin's grant keeps the subdomain"
        );
        assert!(scope(conn, "sd20lapsed.bullcity.test").is_none());
        assert!(scope(conn, "sd20granted.bullcity.test").is_some());
        Ok(())
    });
}

#[test]
fn css_only_saves_keep_the_toggles_and_a_user_holds_one_subscription() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd7_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd7owner");
        subscribe(conn, &admin, &owner, SubdomainSettings { share_content_from_friends: true, ..Default::default() });

        // A CSS-only save carrying stale (all-off) toggles must not undo the stored ones.
        let saved = save_subdomain_settings(
            SaveSubdomainSettingsRequest {
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
        assert!(saved.settings.unwrap().share_content_from_friends);
        Ok(())
    });
}

#[test]
fn an_admin_can_enable_a_subdomain_without_a_subscription() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd21_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let user = create_user(conn, "sd21user");
        let other = create_user(conn, "sd21other");
        let grant = |enabled: bool| SetUserSubdomainRequest { user_id: user.id.to_proto_id(), enabled };

        // Admin only.
        assert!(set_user_subdomain(grant(true), &other, conn).unwrap_err().message().starts_with("permission_"));
        assert!(scope(conn, "sd21user.bullcity.test").is_none(), "nothing changed");

        // Enabling gives the user the label and makes it resolve -- no subscription anywhere.
        let enabled = set_user_subdomain(grant(true), &admin, conn)?;
        assert!(enabled.enabled && enabled.granted_by_admin && !enabled.subscribed);
        assert_eq!(enabled.settings.unwrap().subdomain, "sd21user");
        let context = scope(conn, "sd21user.bullcity.test").expect("the granted subdomain resolves");
        assert_eq!(context.owner.id, user.id);
        // It is idempotent.
        assert!(set_user_subdomain(grant(true), &admin, conn)?.enabled);

        // The user can now edit their settings (no subscription needed) and the feed follows them.
        save_subdomain_settings(
            SaveSubdomainSettingsRequest {
                subdomain_settings: Some(SubdomainSettings { share_content_from_followers: true, ..Default::default() }),
                keep_sharing_settings: false,
            },
            &user,
            conn,
        )?;
        let follower = create_user(conn, "sd21follower");
        create_follow(conn, &follower, &user);
        let own = public_post(conn, &user);
        let followers_post = public_post(conn, &follower);
        let context = scope(conn, "sd21user.bullcity.test");
        assert_eq!(feed(conn, &context), sorted(vec![own, followers_post]));

        // It shows on the profile (`User.subdomain`), self-or-admin.
        let summaries = models::get_subdomain_summaries(&[user.id], conn)?;
        let proto = crate::logic::subdomains::user_subdomain_proto(&summaries[0], false);
        assert!(proto.granted_by_admin && proto.enabled && proto.settings.unwrap().share_content_from_followers);

        // Withdrawing releases the label and stops resolving; the settings are kept for next time.
        let disabled = set_user_subdomain(grant(false), &admin, conn)?;
        assert!(!disabled.enabled && !disabled.granted_by_admin);
        assert_eq!(disabled.settings.as_ref().unwrap().subdomain, "");
        assert!(disabled.settings.unwrap().share_content_from_followers);
        assert!(scope(conn, "sd21user.bullcity.test").is_none());
        assert_eq!(
            save_subdomain_settings(SaveSubdomainSettingsRequest::default(), &user, conn).unwrap_err().code(),
            Code::InvalidArgument,
            "request validation comes first"
        );
        Ok(())
    });
}

#[test]
fn withdrawing_a_grant_leaves_a_subscribers_subdomain_alone() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd22_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let user = create_user(conn, "sd22user");
        subscribe(conn, &admin, &user, SubdomainSettings::default());
        let request = |enabled| SetUserSubdomainRequest { user_id: user.id.to_proto_id(), enabled };
        assert!(set_user_subdomain(request(true), &admin, conn)?.subscribed);
        let after = set_user_subdomain(request(false), &admin, conn)?;
        assert!(after.enabled && after.subscribed && !after.granted_by_admin);
        assert!(scope(conn, "sd22user.bullcity.test").is_some(), "the subscription keeps it enabled");
        Ok(())
    });
}

#[test]
fn an_admin_cannot_grant_a_label_that_is_reserved_invalid_or_taken() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_cdn(conn, "rellm.org", "backend.rellm.org");
        let admin_user = create_user(conn, "sd23_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let grant = |user: &models::User| SetUserSubdomainRequest { user_id: user.id.to_proto_id(), enabled: true };

        let backend_user = create_user(conn, "backend");
        assert_eq!(set_user_subdomain(grant(&backend_user), &admin, conn).unwrap_err().message(), "subdomain_reserved");
        let bad = create_user(conn, "sd23_bad");
        assert_eq!(set_user_subdomain(grant(&bad), &admin, conn).unwrap_err().message(), "username_not_a_valid_subdomain");

        let holder = create_user(conn, "sd23holder");
        set_user_subdomain(grant(&holder), &admin, conn)?;
        let clash = create_user(conn, "SD23HOLDER");
        assert_eq!(set_user_subdomain(grant(&clash), &admin, conn).unwrap_err().message(), "subdomain_taken");
        // A refusal leaves the user untouched: no grant, no label.
        let untouched = models::get_subdomain_summary(clash.id, conn)?;
        assert!(!untouched.subdomain_granted_by_admin && untouched.subdomain.is_none());
        // And an unknown user id is a plain not-found.
        assert_eq!(
            set_user_subdomain(SetUserSubdomainRequest { user_id: "nope".into(), enabled: true }, &admin, conn).is_err(),
            true
        );
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

#[test]
fn event_listings_use_the_same_author_subqueries() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd14_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd14owner");
        let friend = create_user(conn, "sd14friend"); // follows the owner and is followed back
        let follower = create_user(conn, "sd14follower"); // follows the owner only
        let stranger = create_user(conn, "sd14stranger");
        create_follow(conn, &friend, &owner);
        create_follow(conn, &owner, &friend);
        create_follow(conn, &follower, &owner);

        let event_of = |conn: &mut crate::db_connection::PgPooledConnection, author: &models::User| {
            let (_event, post) = create_event(
                conn,
                author,
                EventOpts {
                    visibility: Visibility::GlobalPublic,
                    // An anonymous viewer needs the occasion itself to be globally public too.
                    default_occasion: Some(OccasionOpts { visibility: Visibility::GlobalPublic, ..Default::default() }),
                    ..Default::default()
                },
            );
            post.id
        };
        let own = event_of(conn, &owner);
        let friends = event_of(conn, &friend);
        let followers = event_of(conn, &follower);
        let _strangers = event_of(conn, &stranger);

        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let host = "sd14owner.bullcity.test";
        let event_post_ids = |conn: &mut crate::db_connection::PgPooledConnection| {
            let context = scope(conn, host);
            let mut ids: Vec<i64> = crate::rpcs::get_events_for(GetEventsRequest::default(), &None, &context, conn)
                .expect("get_events_for failed")
                .events
                .into_iter()
                .filter_map(|e| e.post.map(|p| p.id.to_db_id().unwrap()))
                .collect();
            ids.sort();
            ids
        };
        let sorted_ids = |mut ids: Vec<i64>| {
            ids.sort();
            ids
        };
        // Sanity: unscoped, all four events are listed (so an empty scoped result is the filter's doing).
        let unscoped = crate::rpcs::get_events_for(GetEventsRequest::default(), &None, &None, conn).unwrap().events.len();
        assert_eq!(unscoped, 4, "unscoped listing");
        assert_eq!(event_post_ids(conn), vec![own], "nothing shared: only the owner's events");

        let set = |conn: &mut crate::db_connection::PgPooledConnection, followers_on, friends_on| {
            set_toggles(conn, &owner, followers_on, false, friends_on);
        };
        set(conn, true, false);
        assert_eq!(event_post_ids(conn), sorted_ids(vec![own, friends, followers]));
        set(conn, false, true);
        assert_eq!(event_post_ids(conn), sorted_ids(vec![own, friends]));
        Ok(())
    });
}

#[test]
fn only_accepted_follows_are_shared() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd15_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd15owner");
        let accepted = create_user(conn, "sd15accepted");
        let pending = create_user(conn, "sd15pending");
        create_follow(conn, &accepted, &owner);
        create_follow_with_moderation(conn, &pending, &owner, Moderation::Pending);
        let accepted_post = public_post(conn, &accepted);
        let _pending_post = public_post(conn, &pending);
        let own = public_post(conn, &owner);
        subscribe(conn, &admin, &owner, SubdomainSettings { share_content_from_followers: true, ..Default::default() });
        let context = scope(conn, "sd15owner.bullcity.test");
        assert_eq!(feed(conn, &context), sorted(vec![own, accepted_post]), "a pending follow shares nothing");
        Ok(())
    });
}

#[test]
fn a_subdomains_sitemap_lists_its_own_pages_and_no_people_page() {
    use crate::web::robots_sitemap::base_sitemap_urls;
    let parent = ServerConfiguration::default();
    let parent_urls = base_sitemap_urls("bullcity.test", &parent, false);
    assert!(parent_urls.contains(&"https://bullcity.test/people".to_string()));

    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd16_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd16owner");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let context = scope(conn, "sd16owner.bullcity.test").unwrap();
        let virtual_configuration = context.virtual_server_configuration(ServerConfiguration::default(), &None);
        let urls = base_sitemap_urls("sd16owner.bullcity.test", &virtual_configuration, true);
        assert!(urls.contains(&"https://sd16owner.bullcity.test/posts".to_string()));
        assert!(urls.contains(&"https://sd16owner.bullcity.test/events".to_string()));
        assert!(urls.contains(&"https://sd16owner.bullcity.test/about".to_string()));
        // All six of the subdomain's navigation tabs, `media`/`video`/`audio` included.
        for tab in ["events", "posts", "media", "video", "audio", "about"] {
            assert!(
                urls.contains(&format!("https://sd16owner.bullcity.test/{tab}")),
                "the sitemap lists the {tab} tab"
            );
        }
        assert!(!urls.iter().any(|u| u.ends_with("/people")), "a subdomain has no People page");
        // Every URL is on the subdomain's own host, never the parent's.
        assert!(urls.iter().all(|u| u.starts_with("https://sd16owner.bullcity.test/")));
        Ok(())
    });
}

#[test]
fn a_subdomains_manifest_is_valid_json_named_after_its_owner() {
    use crate::web::robots_sitemap::build_manifest;
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd17_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        // A name with a backslash, a quote and a newline -- all of which the owner is free to choose.
        let owner = create_user_with_profile(conn, "sd17owner", "Alex\\Jones \"AJ\"\nLine2", "bio");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        let context = scope(conn, "sd17owner.bullcity.test").unwrap();
        // A subdomain's virtual configuration has no colors: the fallback must not panic (it used to, slicing a
        // five-digit hex string) and must still give a six-digit colour.
        let configuration = context.virtual_server_configuration(ServerConfiguration::default(), &None);
        let manifest: serde_json::Value = serde_json::from_str(&build_manifest(&configuration)).expect("valid JSON");
        assert_eq!(manifest["name"], "Alex\\Jones \"AJ\"\nLine2");
        assert_eq!(manifest["short_name"], "sd17owner");
        assert_eq!(manifest["background_color"], "#424242");
        assert_eq!(manifest["theme_color"], "#424242CC");
        Ok(())
    });
}

#[test]
fn the_manifest_uses_a_configured_primary_color_and_pads_small_ones() {
    use crate::web::robots_sitemap::build_manifest;
    let configuration = |primary: u32| ServerConfiguration {
        server_info: Some(ServerInfo {
            colors: Some(ServerColors { primary: Some(primary), ..Default::default() }),
            ..Default::default()
        }),
        ..Default::default()
    };
    // `ServerColors.primary` is ARGB: only the low 24 bits are the colour.
    let manifest: serde_json::Value = serde_json::from_str(&build_manifest(&configuration(0xFF12_34AB))).unwrap();
    assert_eq!(manifest["background_color"], "#1234ab");
    // A small value (a dark colour) is zero-padded to six digits.
    let manifest: serde_json::Value = serde_json::from_str(&build_manifest(&configuration(0xFF00_00FF))).unwrap();
    assert_eq!(manifest["background_color"], "#0000ff");
    // No server info at all: Rellm's defaults.
    let manifest: serde_json::Value = serde_json::from_str(&build_manifest(&ServerConfiguration::default())).unwrap();
    assert_eq!(manifest["name"], "Rellm");
}

/// rellm.org's own setup: a Cloudflare frontend at `rellm.org`, the real backend at `backend.rellm.org`.
fn configure_cdn(conn: &mut crate::db_connection::PgPooledConnection, frontend_host: &str, backend_host: &str) {
    let mut new_config = models::default_server_configuration();
    new_config.external_cdn_config = Some(
        serde_json::to_value(ExternalCdnConfig {
            frontend_host: frontend_host.to_string(),
            backend_host: backend_host.to_string(),
            ..Default::default()
        })
        .unwrap(),
    );
    diesel::insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

#[test]
fn a_user_named_like_the_cdn_backend_cannot_buy_it_and_the_backend_host_stays_the_parent() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_cdn(conn, "rellm.org", "backend.rellm.org");
        let admin_user = create_user(conn, "sd18_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);

        // A user named `backend` on rellm.org can't take the label: that host is the real backend.
        let backend_user = create_user(conn, "backend");
        assert_eq!(
            crate::logic::subdomains::validate_label_available(&backend_user, conn).unwrap_err().message(),
            "subdomain_reserved"
        );
        // Another user is unaffected.
        let jon = create_user(conn, "sd18jon");
        assert_eq!(crate::logic::subdomains::validate_label_available(&jon, conn)?, "sd18jon");

        // Even a subscription for `backend` that already exists (bought before this rule) never makes the backend host a
        // subdomain: it keeps serving the main server's configuration.
        subscribe(conn, &admin, &backend_user, SubdomainSettings::default());
        assert!(scope(conn, "backend.rellm.org").is_none(), "the backend host is the parent server");
        assert!(scope(conn, "backend.backend.rellm.org").is_none());
        assert!(scope(conn, "rellm.org").is_none());

        // A real subdomain resolves on the frontend host and on its own backend name.
        subscribe(conn, &admin, &jon, SubdomainSettings::default());
        assert!(scope(conn, "sd18jon.rellm.org").is_some());
        assert!(scope(conn, "sd18jon.backend.rellm.org").is_some());

        // And the configuration the backend host serves is the main one, with no subdomain settings.
        let config = crate::rpcs::get_server_configuration_for((), &None, &scope(conn, "backend.rellm.org"), conn)?;
        assert!(config.subdomain_settings.is_none());
        assert_eq!(config.external_cdn_config.unwrap().backend_host, "backend.rellm.org");
        Ok(())
    });
}

#[test]
fn backend_host_discovery_under_a_cloudflare_frontend() {
    use crate::web::external_cdn::backend_domain_for_host;
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_cdn(conn, "rellm.org", "backend.rellm.org");
        let admin_user = create_user(conn, "sd19_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let jon = create_user(conn, "sd19jon");
        subscribe(conn, &admin, &jon, SubdomainSettings::default());
        // A user named `backend` who somehow holds a subscription must not capture the backend host: without the CDN
        // guard this label would resolve (it is a valid, held label under the frontend) and the answer would be wrong.
        let backend_user = create_user(conn, "backend");
        subscribe(conn, &admin, &backend_user, SubdomainSettings::default());
        let cdn = crate::rpcs::get_server_configuration_proto(conn)?.external_cdn_config.unwrap();

        // What `GET /backend_host` answers for each host, with the subdomain lookup done exactly as the route does it.
        let mut answer = |host: &str| {
            let label = scope(conn, host).map(|s| s.settings.subdomain);
            backend_domain_for_host(Some(&cdn), host, || label)
        };
        // The reported failure: the backend host is itself a label under the frontend, and must stay itself.
        assert_eq!(answer("backend.rellm.org"), "backend.rellm.org");
        assert_eq!(answer("rellm.org"), "backend.rellm.org");
        // An unsubscribed label is not a subdomain.
        assert_eq!(answer("nobody.rellm.org"), "backend.rellm.org");
        // A subscriber gets its own backend name, from either of its hosts.
        assert_eq!(answer("sd19jon.rellm.org"), "sd19jon.backend.rellm.org");
        assert_eq!(answer("sd19jon.backend.rellm.org"), "sd19jon.backend.rellm.org");
        Ok(())
    });
}

#[test]
fn backend_host_discovery_without_a_separate_backend() {
    use crate::web::external_cdn::backend_domain_for_host;
    let never = || -> Option<String> { panic!("the subdomain lookup must not run") };
    // No CDN configuration, or no backend host: the request's own host is the backend, with no lookup at all.
    assert_eq!(backend_domain_for_host(None, "rellm.org", never), "rellm.org");
    let no_backend = ExternalCdnConfig { frontend_host: "rellm.org".to_string(), ..Default::default() };
    assert_eq!(backend_domain_for_host(Some(&no_backend), "jon.rellm.org", never), "jon.rellm.org");
    // `cdn_grpc` on: gRPC goes through the CDN to the request's own host.
    let cdn_grpc = ExternalCdnConfig {
        frontend_host: "rellm.org".to_string(),
        backend_host: "backend.rellm.org".to_string(),
        cdn_grpc: true,
        ..Default::default()
    };
    assert_eq!(backend_domain_for_host(Some(&cdn_grpc), "jon.rellm.org", never), "jon.rellm.org");
}

#[test]
fn a_renewal_after_a_username_change_keeps_the_label_the_user_already_holds() {
    use crate::schema::users;
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        configure_frontend_host(conn);
        let admin_user = create_user(conn, "sd24_admin");
        let admin = grant_permissions(conn, &admin_user, vec![Permission::Admin]);
        let owner = create_user(conn, "sd24old");
        subscribe(conn, &admin, &owner, SubdomainSettings::default());
        // The subscriber renames to a name that isn't a valid DNS label; the subdomain keeps its original label.
        diesel::update(users::table.find(owner.id)).set(users::username.eq("sd24_new")).execute(conn).unwrap();
        let renamed = models::get_user(owner.id, conn)?;
        // What `fulfill_purchase` runs on every renewal: it must not fail (a failure cancels future renewals).
        assert_eq!(crate::logic::subdomains::claim_label(&renamed, conn)?, "sd24old");
        assert!(scope(conn, "sd24old.bullcity.test").is_some());
        Ok(())
    });
}
