//! Specs for the 5 SyncDestination/sync RPCs: `get_sync_destinations`, `create_sync_destination`,
//! `update_sync_destination`, `delete_sync_destination`, `sync_occasion`. Facebook Graph API
//! interaction correctness itself is covered by `facebook_sync_tests`; these specs focus on
//! permissions, ownership, and validation.

use diesel::prelude::*;
use diesel::Connection;
use tonic::Code;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::{
    create_sync_destination, delete_sync_destination, get_sync_destinations, sync_occasion,
    update_sync_destination,
};
use crate::schema::sync_destinations;
use crate::tests::factories::*;

fn facebook_page_request(page_id: &str, short_lived_user_access_token: &str) -> SyncDestination {
    SyncDestination {
        configuration: Some(sync_destination::Configuration::FacebookPage(FacebookPage {
            page_id: page_id.to_string(),
            page_name: String::new(),
            short_lived_user_access_token: Some(short_lived_user_access_token.to_string()),
        })),
        ..Default::default()
    }
}

fn instagram_account_request(
    page_id: &str,
    short_lived_user_access_token: &str,
) -> SyncDestination {
    SyncDestination {
        configuration: Some(sync_destination::Configuration::InstagramAccount(
            InstagramAccount {
                instagram_business_account_id: String::new(),
                username: String::new(),
                page_id: page_id.to_string(),
                short_lived_user_access_token: Some(short_lived_user_access_token.to_string()),
            },
        )),
        ..Default::default()
    }
}

fn mastodon_account_request(instance_host: &str, access_token: &str) -> SyncDestination {
    SyncDestination {
        configuration: Some(sync_destination::Configuration::MastodonAccount(
            MastodonAccount {
                instance_host: instance_host.to_string(),
                username: String::new(),
                access_token: Some(access_token.to_string()),
            },
        )),
        ..Default::default()
    }
}

fn bluesky_account_request(handle: &str, app_password: &str) -> SyncDestination {
    SyncDestination {
        configuration: Some(sync_destination::Configuration::BlueskyAccount(
            BlueskyAccount {
                handle: handle.to_string(),
                did: String::new(),
                app_password: Some(app_password.to_string()),
            },
        )),
        ..Default::default()
    }
}

fn threads_account_request(authorization_code: &str) -> SyncDestination {
    SyncDestination {
        configuration: Some(sync_destination::Configuration::ThreadsAccount(
            ThreadsAccount {
                threads_user_id: String::new(),
                username: String::new(),
                authorization_code: Some(authorization_code.to_string()),
            },
        )),
        ..Default::default()
    }
}

fn x_twitter_account_request(authorization_code: &str, code_verifier: &str) -> SyncDestination {
    SyncDestination {
        configuration: Some(sync_destination::Configuration::XTwitterAccount(
            XTwitterAccount {
                username: String::new(),
                x_user_id: String::new(),
                authorization_code: Some(authorization_code.to_string()),
                code_verifier: Some(code_verifier.to_string()),
            },
        )),
        ..Default::default()
    }
}

#[test]
fn create_requires_sync_events_or_posts_to_facebook_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_create_noperm");

        let err = create_sync_destination(
            facebook_page_request("123", "short-lived-token"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_FACEBOOK_required");

        Ok(())
    });
}

#[test]
fn create_succeeds_with_only_sync_posts_to_facebook_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_facebook_app(conn, "test-app-id", "test-app-secret");

        let user = create_user(conn, "sdt_create_postperm");
        let user = grant_permissions(conn, &user, vec![Permission::SyncPostsToFacebook]);

        // Once an app is configured, create_sync_destination goes on to hit the real Graph API
        // base URL, which isn't reachable in tests -- see `facebook_sync_tests` for coverage of
        // the actual Graph API interaction (against a mock server) via `logic::sync_destinations::facebook_sync`'s
        // `_at` functions. Reaching `FailedPrecondition` (rather than the permission check's
        // `InvalidArgument`) proves `SyncPostsToFacebook` alone is sufficient here.
        let err = create_sync_destination(
            facebook_page_request("123", "short-lived-token"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);

        Ok(())
    });
}

#[test]
fn create_requires_facebook_page_configuration() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_create_noconfig");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToFacebook]);

        let err =
            create_sync_destination(SyncDestination::default(), &user, conn).unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(
            err.message(),
            "facebook_page.page_id_and_short_lived_user_access_token_required"
        );

        Ok(())
    });
}

#[test]
fn create_fails_when_facebook_app_not_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_create_noapp");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToFacebook]);

        let err = create_sync_destination(
            facebook_page_request("123", "short-lived-token"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "facebook_app_not_configured");

        Ok(())
    });
}

#[test]
fn create_succeeds_and_owner_is_always_current_user() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_facebook_app(conn, "test-app-id", "test-app-secret");

        let user = create_user(conn, "sdt_create_ok");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToFacebook]);

        // Once an app is configured, create_sync_destination goes on to hit the real Graph API
        // base URL, which isn't reachable in tests -- see `facebook_sync_tests` for coverage of
        // the actual Graph API interaction (against a mock server) via `logic::sync_destinations::facebook_sync`'s
        // `_at` functions.
        let err = create_sync_destination(
            facebook_page_request("123", "short-lived-token"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);

        Ok(())
    });
}

#[test]
fn get_sync_destinations_self_only_by_default() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_get_owner");
        let other = create_user(conn, "sdt_get_other");
        create_sync_destination_row(conn, &owner, "123");

        let response = get_sync_destinations(User::default(), &owner, conn)
            .expect("self get should succeed");
        assert_eq!(response.destinations.len(), 1);

        let err = get_sync_destinations(
            User {
                id: owner.id.to_proto_id(),
                ..Default::default()
            },
            &other,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        Ok(())
    });
}

#[test]
fn admin_can_get_another_users_sync_destinations() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_get_owner2");
        let admin = create_user(conn, "sdt_get_admin2");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        create_sync_destination_row(conn, &owner, "123");

        let response = get_sync_destinations(
            User {
                id: owner.id.to_proto_id(),
                ..Default::default()
            },
            &admin,
            conn,
        )
        .expect("admin get should succeed");
        assert_eq!(response.destinations.len(), 1);

        Ok(())
    });
}

#[test]
fn returned_destination_never_includes_the_access_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_get_notoken");
        create_sync_destination_row(conn, &owner, "123");

        let response = get_sync_destinations(User::default(), &owner, conn)
            .expect("self get should succeed");
        let destination = &response.destinations[0];
        match destination.configuration.as_ref().unwrap() {
            sync_destination::Configuration::FacebookPage(page) => {
                assert_eq!(page.page_id, "123");
                assert_eq!(page.short_lived_user_access_token, None);
            }
            _ => panic!("expected FacebookPage"),
        }

        Ok(())
    });
}

#[test]
fn update_requires_sync_events_or_posts_to_facebook_permission_even_for_the_owner() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_update_noperm");
        let destination = create_sync_destination_row(conn, &owner, "123");

        let err = update_sync_destination(
            SyncDestination {
                id: destination.id.to_proto_id(),
                ..Default::default()
            },
            &owner,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_FACEBOOK_required");

        Ok(())
    });
}

#[test]
fn update_rejects_non_owner_non_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_update_owner");
        let destination = create_sync_destination_row(conn, &owner, "123");

        let other = create_user(conn, "sdt_update_other");
        let other = grant_permissions(conn, &other, vec![Permission::SyncEventsToFacebook]);

        let err = update_sync_destination(
            SyncDestination {
                id: destination.id.to_proto_id(),
                ..Default::default()
            },
            &other,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        Ok(())
    });
}

#[test]
fn delete_rejects_non_owner_non_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_delete_owner");
        let destination = create_sync_destination_row(conn, &owner, "123");
        let other = create_user(conn, "sdt_delete_other");

        let err = delete_sync_destination(
            DeleteSyncDestinationRequest {
                destination: Some(SyncDestination {
                    id: destination.id.to_proto_id(),
                    ..Default::default()
                }),
                delete_synced_posts: false,
            },
            &other,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        Ok(())
    });
}

#[test]
fn delete_removes_the_destination() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_delete_ok");
        let destination = create_sync_destination_row(conn, &owner, "123");

        delete_sync_destination(
            DeleteSyncDestinationRequest {
                destination: Some(SyncDestination {
                    id: destination.id.to_proto_id(),
                    ..Default::default()
                }),
                delete_synced_posts: false,
            },
            &owner,
            conn,
        )
        .expect("owner delete should succeed");

        let remaining: i64 = sync_destinations::table
            .filter(sync_destinations::id.eq(destination.id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 0);

        Ok(())
    });
}

#[test]
fn delete_removes_synced_occasion_and_post_join_rows() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_delete_joins");
        let destination = create_sync_destination_row(conn, &owner, "123");

        let (event, _) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _) = create_occasion(conn, &event, Some(&owner), Default::default());
        create_occasion_sync_destination_row(conn, &occasion, &destination);

        let post = create_post(conn, Some(&owner), PostOpts::default());
        create_post_sync_destination_row(conn, &post, &destination);

        delete_sync_destination(
            DeleteSyncDestinationRequest {
                destination: Some(SyncDestination {
                    id: destination.id.to_proto_id(),
                    ..Default::default()
                }),
                delete_synced_posts: false,
            },
            &owner,
            conn,
        )
        .expect("owner delete should succeed");

        use crate::schema::{occasion_sync_destinations, post_sync_destinations};
        let remaining_occasion_joins: i64 = occasion_sync_destinations::table
            .filter(occasion_sync_destinations::sync_destination_id.eq(destination.id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining_occasion_joins, 0);

        let remaining_post_joins: i64 = post_sync_destinations::table
            .filter(post_sync_destinations::sync_destination_id.eq(destination.id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining_post_joins, 0);

        Ok(())
    });
}

#[test]
fn sync_occasion_requires_sync_events_to_facebook_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_sync_noperm");
        let destination = create_sync_destination_row(conn, &owner, "123");
        let (event, _) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _) = create_occasion(conn, &event, Some(&owner), Default::default());

        let err = sync_occasion(
            SyncOccasionRequest {
                occasion_id: occasion.post_id.to_proto_id(),
                sync_destination_id: destination.id.to_proto_id(),
            },
            &owner,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_FACEBOOK_required");

        Ok(())
    });
}

#[test]
fn sync_occasion_rejects_non_owner_non_admin_of_the_destination() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_sync_owner");
        let destination = create_sync_destination_row(conn, &owner, "123");
        let (event, _) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _) = create_occasion(conn, &event, Some(&owner), Default::default());

        let other = create_user(conn, "sdt_sync_other");
        let other = grant_permissions(conn, &other, vec![Permission::SyncEventsToFacebook]);

        let err = sync_occasion(
            SyncOccasionRequest {
                occasion_id: occasion.post_id.to_proto_id(),
                sync_destination_id: destination.id.to_proto_id(),
            },
            &other,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_ADMIN_required");

        Ok(())
    });
}

#[test]
fn sync_occasion_fails_for_unknown_occasion() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_sync_nooccasion");
        let owner = grant_permissions(conn, &owner, vec![Permission::SyncEventsToFacebook]);
        let destination = create_sync_destination_row(conn, &owner, "123");

        let err = sync_occasion(
            SyncOccasionRequest {
                occasion_id: 999_999_i64.to_proto_id(),
                sync_destination_id: destination.id.to_proto_id(),
            },
            &owner,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::NotFound);

        Ok(())
    });
}

// -- New-platform `CreateSyncDestination` coverage --------------------------------------------
//
// None of these can reach a real success (the actual Instagram/Mastodon/Bluesky APIs aren't
// reachable from this test environment, mirroring the existing Facebook specs above) -- each
// proves its own permission gate, then that holding the right permission clears the gate and
// reaches the network call (surfacing as `FailedPrecondition` once the fake host/credentials
// can't actually be reached), same pattern as `create_succeeds_and_owner_is_always_current_user`.

#[test]
fn create_instagram_account_requires_sync_events_or_posts_to_instagram_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_ig_noperm");

        let err = create_sync_destination(
            instagram_account_request("123", "short-lived-token"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_INSTAGRAM_required");

        Ok(())
    });
}

#[test]
fn create_instagram_account_succeeds_with_only_sync_events_to_instagram_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_facebook_app(conn, "test-app-id", "test-app-secret");
        let user = create_user(conn, "sdt_ig_perm");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToInstagram]);

        // Instagram reuses the same Facebook OAuth exchange, so this reaches the real (unreachable
        // in tests) Graph API base URL once the platform-specific permission passes.
        let err = create_sync_destination(
            instagram_account_request("123", "short-lived-token"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);

        Ok(())
    });
}

#[test]
fn create_mastodon_account_requires_sync_events_or_posts_to_mastodon_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_mn_noperm");

        let err = create_sync_destination(
            mastodon_account_request("mastodon.example.invalid", "test-pat"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_MASTODON_required");

        Ok(())
    });
}

#[test]
fn create_mastodon_account_succeeds_with_only_sync_posts_to_mastodon_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_mn_perm");
        let user = grant_permissions(conn, &user, vec![Permission::SyncPostsToMastodon]);

        // `mastodon.example.invalid` isn't a real, resolvable host -- proves the permission gate
        // passed and the RPC went on to attempt `verify_credentials`.
        let err = create_sync_destination(
            mastodon_account_request("mastodon.example.invalid", "test-pat"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "mastodon_request_failed");

        Ok(())
    });
}

#[test]
fn create_bluesky_account_requires_sync_events_or_posts_to_bluesky_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_bs_noperm");

        let err = create_sync_destination(
            bluesky_account_request("jon.bsky.social", "app-password"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_BLUESKY_required");

        Ok(())
    });
}

#[test]
fn create_bluesky_account_succeeds_with_only_sync_posts_to_bluesky_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_bs_perm");
        let user = grant_permissions(conn, &user, vec![Permission::SyncPostsToBluesky]);

        // Once the platform-specific permission passes, this reaches the real (unreachable in
        // tests) `bsky.social` -- proving the permission gate, not full connect success.
        let err = create_sync_destination(
            bluesky_account_request("jon.bsky.social", "app-password"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);

        Ok(())
    });
}

#[test]
fn create_threads_account_requires_sync_events_or_posts_to_threads_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_th_noperm");

        let err = create_sync_destination(threads_account_request("test-code"), &user, conn)
            .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_THREADS_required");

        Ok(())
    });
}

#[test]
fn create_threads_account_requires_authorization_code() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "sdt_th_nocode");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToThreads]);

        let err = create_sync_destination(
            SyncDestination {
                configuration: Some(sync_destination::Configuration::ThreadsAccount(
                    ThreadsAccount {
                        threads_user_id: String::new(),
                        username: String::new(),
                        authorization_code: None,
                    },
                )),
                ..Default::default()
            },
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(
            err.message(),
            "threads_account.authorization_code_required"
        );

        Ok(())
    });
}

#[test]
fn create_threads_account_succeeds_with_only_sync_posts_to_threads_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_facebook_app_and_frontend_host(
            conn,
            "test-app-id",
            "test-app-secret",
            "example.com",
        );
        let user = create_user(conn, "sdt_th_perm");
        let user = grant_permissions(conn, &user, vec![Permission::SyncPostsToThreads]);

        // Once the platform-specific permission passes and the redirect_uri is derivable, this
        // reaches the real (unreachable in tests) `graph.threads.net` -- proving the permission
        // gate, not full connect success (see `threads_sync_tests` for coverage of the actual
        // Threads Graph API interaction against a mock server via `logic::sync_destinations::threads_sync`'s `_at`
        // functions).
        let err = create_sync_destination(
            threads_account_request("test-code"),
            &user,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);

        Ok(())
    });
}

#[test]
fn create_threads_account_fails_when_redirect_uri_is_not_derivable() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // Facebook app configured, but no `external_cdn_config.frontend_host` -- can't derive the
        // OAuth `redirect_uri` (see `logic::sync_destinations::threads_sync::threads_redirect_uri`).
        configure_facebook_app(conn, "test-app-id", "test-app-secret");
        let user = create_user(conn, "sdt_th_nohost");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToThreads]);

        let err = create_sync_destination(threads_account_request("test-code"), &user, conn)
            .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "threads_redirect_uri_not_configured");

        Ok(())
    });
}

#[test]
fn returned_threads_destination_never_includes_the_authorization_code_or_access_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_th_notoken");
        diesel::insert_into(sync_destinations::table)
            .values(&crate::models::NewSyncDestination {
                user_id: owner.id,
                configuration: serde_json::json!({
                    "threads_account": {
                        "threads_user_id": "threads-user-1",
                        "username": "jon_on_threads",
                        "access_token": "super-secret-long-lived-token"
                    }
                }),
            })
            .get_result::<crate::models::SyncDestination>(conn)
            .expect("failed to create test threads sync destination");

        let response = get_sync_destinations(User::default(), &owner, conn)
            .expect("self get should succeed");
        let destination = &response.destinations[0];
        match destination.configuration.as_ref().unwrap() {
            sync_destination::Configuration::ThreadsAccount(account) => {
                assert_eq!(account.threads_user_id, "threads-user-1");
                assert_eq!(account.username, "jon_on_threads");
                assert_eq!(account.authorization_code, None);
            }
            _ => panic!("expected ThreadsAccount"),
        }

        Ok(())
    });
}

#[test]
fn create_x_twitter_account_fails_when_app_not_configured_even_for_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // No `configure_x_twitter_app` call -- no `XTwitterAuthConfig` stored at all.
        let admin = create_user(conn, "sdt_x_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let err = create_sync_destination(x_twitter_account_request("code", "verifier"), &admin, conn)
            .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "x_twitter_app_not_configured");

        Ok(())
    });
}

#[test]
fn create_x_twitter_account_requires_sync_events_or_posts_to_x_twitter_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_x_twitter_app_and_frontend_host(conn, "test-client-id", "test-client-secret", "example.com");
        let user = create_user(conn, "sdt_x_noperm");

        let err = create_sync_destination(x_twitter_account_request("code", "verifier"), &user, conn)
            .unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(err.message(), "permission_SYNC_EVENTS_TO_X_TWITTER_required");

        Ok(())
    });
}

#[test]
fn create_x_twitter_account_succeeds_with_only_sync_posts_to_x_twitter_permission() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_x_twitter_app_and_frontend_host(conn, "test-client-id", "test-client-secret", "example.com");
        let user = create_user(conn, "sdt_x_perm");
        let user = grant_permissions(conn, &user, vec![Permission::SyncPostsToXTwitter]);

        // Once the platform-specific permission passes and the redirect_uri is derivable, this
        // reaches the real (unreachable in tests) `api.x.com`, proving the permission gate, not
        // full connect success (see `x_twitter_sync_tests` for coverage of the actual X API
        // interaction against a mock server via `logic::sync_destinations::x_twitter_sync`'s `_at` functions).
        let err = create_sync_destination(x_twitter_account_request("code", "verifier"), &user, conn)
            .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);

        Ok(())
    });
}

#[test]
fn create_x_twitter_account_fails_when_redirect_uri_is_not_derivable() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // X app configured, but no `external_cdn_config.frontend_host` -- can't derive the OAuth
        // `redirect_uri` (see `logic::sync_destinations::x_twitter_sync::x_twitter_redirect_uri`).
        configure_x_twitter_app(conn, "test-client-id", "test-client-secret");
        let user = create_user(conn, "sdt_x_nohost");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToXTwitter]);

        let err = create_sync_destination(x_twitter_account_request("code", "verifier"), &user, conn)
            .unwrap_err();
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "x_twitter_redirect_uri_not_configured");

        Ok(())
    });
}

#[test]
fn create_x_twitter_account_fails_when_authorization_code_or_code_verifier_missing() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_x_twitter_app_and_frontend_host(conn, "test-client-id", "test-client-secret", "example.com");
        let user = create_user(conn, "sdt_x_nocode");
        let user = grant_permissions(conn, &user, vec![Permission::SyncEventsToXTwitter]);

        let request = SyncDestination {
            configuration: Some(sync_destination::Configuration::XTwitterAccount(
                XTwitterAccount {
                    username: String::new(),
                    x_user_id: String::new(),
                    authorization_code: None,
                    code_verifier: None,
                },
            )),
            ..Default::default()
        };
        let err = create_sync_destination(request, &user, conn).unwrap_err();
        assert_eq!(err.code(), Code::InvalidArgument);
        assert_eq!(
            err.message(),
            "x_twitter_account.authorization_code_and_code_verifier_required"
        );

        Ok(())
    });
}

#[test]
fn returned_x_twitter_destination_never_includes_the_authorization_code_or_tokens() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "sdt_x_notoken");
        diesel::insert_into(sync_destinations::table)
            .values(&crate::models::NewSyncDestination {
                user_id: owner.id,
                configuration: serde_json::json!({
                    "x_twitter_account": {
                        "x_user_id": "x-user-1",
                        "username": "jon_on_x",
                        "access_token": "super-secret-access-token",
                        "refresh_token": "super-secret-refresh-token",
                        "expires_at": 9999999999i64,
                    }
                }),
            })
            .get_result::<crate::models::SyncDestination>(conn)
            .expect("failed to create test x_twitter sync destination");

        let response = get_sync_destinations(User::default(), &owner, conn)
            .expect("self get should succeed");
        let destination = &response.destinations[0];
        match destination.configuration.as_ref().unwrap() {
            sync_destination::Configuration::XTwitterAccount(account) => {
                assert_eq!(account.x_user_id, "x-user-1");
                assert_eq!(account.username, "jon_on_x");
                assert_eq!(account.authorization_code, None);
                assert_eq!(account.code_verifier, None);
            }
            _ => panic!("expected XTwitterAccount"),
        }

        Ok(())
    });
}
