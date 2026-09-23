//! Specs for `ConfigureServer`'s handling of `FederationInfo.facebook_auth_config.app_secret` and
//! `FederationInfo.x_twitter_auth_config.client_secret`: both are write-only (never sent back to a
//! client) and an empty incoming value is a deliberate no-op rather than a clear (see
//! `configure_server`'s own doc comment). Everything else about `ConfigureServer` is exercised
//! incidentally by other RPC specs' setup, not tested here.

use diesel::{Connection, RunQueryDsl};

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    server_bird_config, server_facebook_app_credentials, server_telnyx_config,
    server_twilio_config, server_x_twitter_app_credentials,
};
use crate::logic::stripe_sync::server_stripe_config;
use crate::protos::*;
use crate::rpcs::{configure_server, get_server_configuration, get_server_configuration_proto};
use crate::tests::factories::*;

/// `configure_server` (like every real caller -- see `validate_configuration`'s
/// `people_settings.unwrap()`) expects a *fully populated* `ServerConfiguration`, not a
/// partial one -- real clients always fetch-then-mutate (mirrors the Elm frontend's
/// `AccountsPanel.updateServerConfig`), so specs do too rather than building a bare one by hand.
fn facebook_auth_request(
    conn: &mut PgPooledConnection,
    app_id: &str,
    app_secret: &str,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.federation_info = Some(FederationInfo {
        servers: config
            .federation_info
            .as_ref()
            .map(|f| f.servers.clone())
            .unwrap_or_default(),
        facebook_auth_config: Some(FacebookAuthConfig {
            app_id: app_id.to_string(),
            app_secret: app_secret.to_string(),
        }),
        mastodon_servers: config
            .federation_info
            .as_ref()
            .map(|f| f.mastodon_servers.clone())
            .unwrap_or_default(),
        x_twitter_auth_config: config.federation_info.and_then(|f| f.x_twitter_auth_config),
    });
    config
}

#[test]
fn app_secret_is_never_returned_to_the_client() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_secret_hidden");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(
            facebook_auth_request(conn, "app-1", "super-secret"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        let facebook_auth_config = updated
            .federation_info
            .expect("federation_info should be set")
            .facebook_auth_config
            .expect("facebook_auth_config should be set");
        assert_eq!(facebook_auth_config.app_id, "app-1");
        assert_eq!(facebook_auth_config.app_secret, "");

        Ok(())
    });
}

#[test]
fn empty_app_secret_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_secret_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            facebook_auth_request(conn, "app-1", "super-secret"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        // Changing just the App ID, with app_secret left blank (as the client always sends it,
        // since it never gets the real value back to resend).
        configure_server(facebook_auth_request(conn, "app-2", ""), &admin, conn)
            .expect("second configure should succeed");

        let (app_id, app_secret) =
            server_facebook_app_credentials(conn).expect("credentials should still be configured");
        assert_eq!(app_id, "app-2");
        assert_eq!(app_secret, "super-secret");

        Ok(())
    });
}

#[test]
fn setting_facebook_auth_config_to_none_clears_the_stored_secret() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_secret_cleared");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            facebook_auth_request(conn, "app-1", "super-secret"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        let mut clearing_config =
            get_server_configuration_proto(conn).expect("failed to fetch base config");
        clearing_config.federation_info = clearing_config.federation_info.map(|f| FederationInfo {
            servers: f.servers,
            facebook_auth_config: None,
            mastodon_servers: f.mastodon_servers,
            x_twitter_auth_config: f.x_twitter_auth_config,
        });
        configure_server(clearing_config, &admin, conn).expect("clearing configure should succeed");

        let err = server_facebook_app_credentials(conn).unwrap_err();
        assert_eq!(err.message(), "facebook_app_not_configured");

        Ok(())
    });
}

/// Mirrors `facebook_auth_request` exactly, against `x_twitter_auth_config` instead.
fn x_twitter_auth_request(
    conn: &mut PgPooledConnection,
    client_id: &str,
    client_secret: &str,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.federation_info = Some(FederationInfo {
        servers: config
            .federation_info
            .as_ref()
            .map(|f| f.servers.clone())
            .unwrap_or_default(),
        facebook_auth_config: config.federation_info.as_ref().and_then(|f| f.facebook_auth_config.clone()),
        mastodon_servers: config
            .federation_info
            .as_ref()
            .map(|f| f.mastodon_servers.clone())
            .unwrap_or_default(),
        x_twitter_auth_config: Some(XTwitterAuthConfig {
            client_id: client_id.to_string(),
            client_secret: client_secret.to_string(),
        }),
    });
    config
}

#[test]
fn client_secret_is_never_returned_to_the_client() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_x_secret_hidden");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(
            x_twitter_auth_request(conn, "client-1", "super-secret"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        let x_twitter_auth_config = updated
            .federation_info
            .expect("federation_info should be set")
            .x_twitter_auth_config
            .expect("x_twitter_auth_config should be set");
        assert_eq!(x_twitter_auth_config.client_id, "client-1");
        assert_eq!(x_twitter_auth_config.client_secret, "");

        Ok(())
    });
}

#[test]
fn empty_client_secret_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_x_secret_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            x_twitter_auth_request(conn, "client-1", "super-secret"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        // Changing just the Client ID, with client_secret left blank (as the client always sends
        // it, since it never gets the real value back to resend).
        configure_server(x_twitter_auth_request(conn, "client-2", ""), &admin, conn)
            .expect("second configure should succeed");

        let (client_id, client_secret) = server_x_twitter_app_credentials(conn)
            .expect("credentials should still be configured");
        assert_eq!(client_id, "client-2");
        assert_eq!(client_secret, "super-secret");

        Ok(())
    });
}

#[test]
fn setting_x_twitter_auth_config_to_none_clears_the_stored_secret() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_x_secret_cleared");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            x_twitter_auth_request(conn, "client-1", "super-secret"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        let mut clearing_config =
            get_server_configuration_proto(conn).expect("failed to fetch base config");
        clearing_config.federation_info = clearing_config.federation_info.map(|f| FederationInfo {
            servers: f.servers,
            facebook_auth_config: f.facebook_auth_config,
            mastodon_servers: f.mastodon_servers,
            x_twitter_auth_config: None,
        });
        configure_server(clearing_config, &admin, conn).expect("clearing configure should succeed");

        let err = server_x_twitter_app_credentials(conn).unwrap_err();
        assert_eq!(err.message(), "x_twitter_app_not_configured");

        Ok(())
    });
}

/// Saving one platform's auth config while the other already has a stored secret shouldn't
/// clobber it -- both `configure_server`'s merge blocks operate on the same
/// `new_config.federation_info` sequentially (Facebook's, then X's), so this specifically covers
/// that they compose rather than one overwriting the other's work.
#[test]
fn saving_facebook_auth_config_does_not_clobber_an_already_stored_x_twitter_secret() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_cross_platform");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            x_twitter_auth_request(conn, "client-1", "x-secret"),
            &admin,
            conn,
        )
        .expect("x_twitter configure should succeed");

        configure_server(
            facebook_auth_request(conn, "app-1", "fb-secret"),
            &admin,
            conn,
        )
        .expect("facebook configure should succeed");

        let (_, x_client_secret) =
            server_x_twitter_app_credentials(conn).expect("x_twitter credentials should still be configured");
        assert_eq!(x_client_secret, "x-secret");

        Ok(())
    });
}

/// Mirrors `facebook_auth_request`, against `twilio_config` instead -- see `TwilioConfig`'s own
/// doc for why `twilio_api_key_secret` (the API Key's Secret) gets the identical write-only/
/// merge-on-blank treatment as `FacebookAuthConfig.app_secret`, while `twilio_api_key_sid` (unlike
/// the Account SID's own Auth Token, which this deliberately never accepts) passes through freely.
fn twilio_request(
    conn: &mut PgPooledConnection,
    account_sid: &str,
    api_key_sid: &str,
    api_key_secret: &str,
    from_number: &str,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.twilio_config = Some(TwilioConfig {
        twilio_enabled: true,
        twilio_account_sid: account_sid.to_string(),
        twilio_api_key_sid: api_key_sid.to_string(),
        twilio_api_key_secret: api_key_secret.to_string(),
        twilio_from_number: from_number.to_string(),
        twilio_webhook_signing_key: String::new(),
        use_twilio_webhook_signing_key: false,
    });
    config
}

#[test]
fn twilio_api_key_secret_is_never_returned_to_the_client() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_twilio_hidden");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(
            twilio_request(conn, "AC_sid", "SK_key_sid", "super-secret-token", "+15005550006"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        assert_eq!(
            updated.twilio_config.expect("twilio_config should be set").twilio_api_key_secret,
            ""
        );

        Ok(())
    });
}

#[test]
fn empty_twilio_api_key_secret_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_twilio_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            twilio_request(conn, "AC_sid_1", "SK_key_sid", "super-secret-token", "+15005550006"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        // Changing just the Account SID, with the Secret left blank (as the client always sends
        // it, since it never gets the real value back to resend) -- this is exactly the bug
        // report this spec guards against: editing one field must not silently blank/clobber the
        // other already-stored secret.
        configure_server(
            twilio_request(conn, "AC_sid_2", "SK_key_sid", "", "+15005550006"),
            &admin,
            conn,
        )
        .expect("second configure should succeed");

        let stored = server_twilio_config(conn).expect("twilio config should still be configured");
        assert_eq!(stored.twilio_account_sid, "AC_sid_2");
        assert_eq!(stored.twilio_api_key_secret, "super-secret-token");

        Ok(())
    });
}

#[test]
fn setting_twilio_config_to_none_clears_the_stored_secret() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_twilio_cleared");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            twilio_request(conn, "AC_sid", "SK_key_sid", "super-secret-token", "+15005550006"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        let mut clearing_config =
            get_server_configuration_proto(conn).expect("failed to fetch base config");
        clearing_config.twilio_config = None;
        configure_server(clearing_config, &admin, conn).expect("clearing configure should succeed");

        assert_eq!(server_twilio_config(conn), None);

        Ok(())
    });
}

/// Sets `twilio_webhook_signing_key`/`use_twilio_webhook_signing_key` on top of whatever
/// `twilio_request` already built -- separated out since most specs above don't care about either
/// at all (both default to blank/`false` there).
fn with_twilio_webhook_signing_key(
    config: ServerConfiguration,
    key: &str,
    use_key: bool,
) -> ServerConfiguration {
    let mut config = config;
    config.twilio_config = config.twilio_config.map(|c| TwilioConfig {
        twilio_webhook_signing_key: key.to_string(),
        use_twilio_webhook_signing_key: use_key,
        ..c
    });
    config
}

#[test]
fn twilio_webhook_signing_key_is_blank_when_never_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_twilio_webhook_key_unset");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(
            twilio_request(conn, "AC_sid", "SK_key_sid", "secret", "+15005550006"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        let twilio_config = updated.twilio_config.expect("twilio_config should be set");
        assert_eq!(twilio_config.twilio_webhook_signing_key, "");
        assert!(!twilio_config.use_twilio_webhook_signing_key);

        Ok(())
    });
}

#[test]
fn twilio_webhook_signing_key_is_always_blanked_but_use_flag_round_trips() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_twilio_webhook_key_set");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let request = with_twilio_webhook_signing_key(
            twilio_request(conn, "AC_sid", "SK_key_sid", "secret", "+15005550006"),
            "real_auth_token",
            true,
        );
        let updated = configure_server(request, &admin, conn).expect("configure should succeed");

        let twilio_config = updated.twilio_config.expect("twilio_config should be set");
        assert_eq!(
            twilio_config.twilio_webhook_signing_key, "",
            "the real value must never round-trip to the client"
        );
        assert!(
            twilio_config.use_twilio_webhook_signing_key,
            "the (non-secret) use-flag isn't blanked -- it should round-trip as sent"
        );

        Ok(())
    });
}

#[test]
fn empty_twilio_webhook_signing_key_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_twilio_webhook_key_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let first_request = with_twilio_webhook_signing_key(
            twilio_request(conn, "AC_sid", "SK_key_sid", "secret", "+15005550006"),
            "real_auth_token",
            true,
        );
        configure_server(first_request, &admin, conn).expect("first configure should succeed");

        // Second save resends a blank key (as the client always does, since it never gets the
        // real value back) -- must not clobber the already-stored key.
        let second_request = with_twilio_webhook_signing_key(
            twilio_request(conn, "AC_sid_2", "SK_key_sid", "secret", "+15005550006"),
            "",
            true,
        );
        configure_server(second_request, &admin, conn).expect("second configure should succeed");

        let stored = server_twilio_config(conn).expect("twilio config should still be configured");
        assert_eq!(stored.twilio_account_sid, "AC_sid_2");
        assert_eq!(stored.twilio_webhook_signing_key, "real_auth_token");

        Ok(())
    });
}

/// Guards the actual backward-compat concern `twilio_webhook_signing_key`/
/// `use_twilio_webhook_signing_key`'s own `build.rs` `field_attribute`s exist for: a
/// `twilio_config` blob stored *before* this migration (`twilio_webhook_signing_key` was
/// `optional string`, serialized as literal JSON `null` when unset, and
/// `use_twilio_webhook_signing_key` didn't exist at all) must still deserialize -- not silently
/// drop the whole `twilio_config` (see `ToProtoServerConfiguration::to_proto`'s
/// `.ok()`-then-`.flatten()` chain, which does exactly that on any deserialize error). Inserted as
/// raw JSON, bypassing the current `TwilioConfig` struct entirely, since that struct can no longer
/// even express the old (pre-migration) shape.
#[test]
fn legacy_twilio_config_with_a_null_signing_key_and_no_use_flag_still_deserializes() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let mut new_config = crate::models::default_server_configuration();
        new_config.twilio_config = Some(serde_json::json!({
            "twilio_enabled": true,
            "twilio_account_sid": "AC_legacy",
            "twilio_api_key_sid": "SK_legacy",
            "twilio_api_key_secret": "legacy_secret",
            "twilio_from_number": "+15005550006",
            "twilio_webhook_signing_key": null
        }));
        diesel::insert_into(crate::schema::server_configurations::table)
            .values(&new_config)
            .execute(conn)
            .expect("failed to create legacy test server configuration");

        let config = get_server_configuration_proto(conn).expect("failed to fetch config");
        let twilio_config = config.twilio_config.expect(
            "twilio_config must survive deserializing a pre-migration blob, not silently vanish",
        );
        assert_eq!(twilio_config.twilio_account_sid, "AC_legacy");
        assert_eq!(twilio_config.twilio_webhook_signing_key, "");
        assert!(!twilio_config.use_twilio_webhook_signing_key);

        Ok(())
    });
}

/// Mirrors `twilio_request` exactly, against `bird_config` instead.
fn bird_request(conn: &mut PgPooledConnection, access_key: &str, from: &str) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.bird_config = Some(BirdConfig {
        bird_enabled: true,
        bird_access_key: access_key.to_string(),
        bird_from: from.to_string(),
        bird_region: "us1".to_string(),
        bird_webhook_signing_key: String::new(),
        use_bird_webhook_signing_key: false,
    });
    config
}

#[test]
fn bird_access_key_is_never_returned_to_the_client() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_bird_hidden");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(bird_request(conn, "super-secret-key", "Bird"), &admin, conn)
            .expect("configure should succeed");

        assert_eq!(
            updated.bird_config.expect("bird_config should be set").bird_access_key,
            ""
        );

        Ok(())
    });
}

#[test]
fn empty_bird_access_key_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_bird_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(bird_request(conn, "super-secret-key", "Bird-1"), &admin, conn)
            .expect("first configure should succeed");

        // Changing just the From value, with the Access Key left blank.
        configure_server(bird_request(conn, "", "Bird-2"), &admin, conn)
            .expect("second configure should succeed");

        let stored = server_bird_config(conn).expect("bird config should still be configured");
        assert_eq!(stored.bird_from, "Bird-2");
        assert_eq!(stored.bird_access_key, "super-secret-key");

        Ok(())
    });
}

#[test]
fn setting_bird_config_to_none_clears_the_stored_secret() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_bird_cleared");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(bird_request(conn, "super-secret-key", "Bird"), &admin, conn)
            .expect("first configure should succeed");

        let mut clearing_config =
            get_server_configuration_proto(conn).expect("failed to fetch base config");
        clearing_config.bird_config = None;
        configure_server(clearing_config, &admin, conn).expect("clearing configure should succeed");

        assert_eq!(server_bird_config(conn), None);

        Ok(())
    });
}

/// Mirrors `twilio_request` exactly, against `telnyx_config` instead.
fn telnyx_request(
    conn: &mut PgPooledConnection,
    api_key: &str,
    from_number: &str,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.telnyx_config = Some(TelnyxConfig {
        telnyx_enabled: true,
        telnyx_api_key: api_key.to_string(),
        telnyx_from_number: from_number.to_string(),
        telnyx_messaging_profile_id: "profile_1".to_string(),
        telnyx_webhook_signing_key: String::new(),
        use_telnyx_webhook_signing_key: false,
    });
    config
}

#[test]
fn telnyx_api_key_is_never_returned_to_the_client() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_telnyx_hidden");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(
            telnyx_request(conn, "super-secret-key", "+15005550006"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        assert_eq!(
            updated.telnyx_config.expect("telnyx_config should be set").telnyx_api_key,
            ""
        );

        Ok(())
    });
}

#[test]
fn empty_telnyx_api_key_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_telnyx_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            telnyx_request(conn, "super-secret-key", "+15005550006"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        // Changing just the From Number, with the API Key left blank.
        configure_server(telnyx_request(conn, "", "+15005550007"), &admin, conn)
            .expect("second configure should succeed");

        let stored = server_telnyx_config(conn).expect("telnyx config should still be configured");
        assert_eq!(stored.telnyx_from_number, "+15005550007");
        assert_eq!(stored.telnyx_api_key, "super-secret-key");

        Ok(())
    });
}

#[test]
fn setting_telnyx_config_to_none_clears_the_stored_secret() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_telnyx_cleared");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            telnyx_request(conn, "super-secret-key", "+15005550006"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        let mut clearing_config =
            get_server_configuration_proto(conn).expect("failed to fetch base config");
        clearing_config.telnyx_config = None;
        configure_server(clearing_config, &admin, conn).expect("clearing configure should succeed");

        assert_eq!(server_telnyx_config(conn), None);

        Ok(())
    });
}

/// Mirrors `twilio_request`, against `stripe_config` instead -- `StripeConfig` has *two*
/// write-only fields (`stripe_secret_key`, `stripe_webhook_signing_secret`, both merge-on-blank --
/// see `configure_server`'s own comment), unlike Twilio/Bird's single secret, so these specs cover
/// each independently.
fn stripe_request(
    conn: &mut PgPooledConnection,
    secret_key: &str,
    publishable_key: &str,
    webhook_signing_secret: &str,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.stripe_config = Some(StripeConfig {
        stripe_enabled: true,
        stripe_secret_key: secret_key.to_string(),
        stripe_publishable_key: publishable_key.to_string(),
        stripe_webhook_signing_secret: webhook_signing_secret.to_string(),
    });
    config
}

#[test]
fn stripe_secrets_are_never_returned_to_the_client() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_stripe_hidden");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let updated = configure_server(
            stripe_request(conn, "sk_test_secret", "pk_test_public", "whsec_test_secret"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        let stripe_config = updated.stripe_config.expect("stripe_config should be set");
        assert_eq!(stripe_config.stripe_publishable_key, "pk_test_public");
        assert_eq!(stripe_config.stripe_secret_key, "");
        assert_eq!(stripe_config.stripe_webhook_signing_secret, "");

        Ok(())
    });
}

#[test]
fn empty_stripe_secret_key_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_stripe_secret_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            stripe_request(conn, "sk_test_secret", "pk_test_public_1", "whsec_test_secret"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        // Changing just the publishable key, with the Secret Key left blank (as the client always
        // sends it, since it never gets the real value back to resend).
        configure_server(
            stripe_request(conn, "", "pk_test_public_2", "whsec_test_secret"),
            &admin,
            conn,
        )
        .expect("second configure should succeed");

        let stored =
            server_stripe_config(conn).expect("stripe config should still be configured");
        assert_eq!(stored.stripe_publishable_key, "pk_test_public_2");
        assert_eq!(stored.stripe_secret_key, "sk_test_secret");
        assert_eq!(stored.stripe_webhook_signing_secret, "whsec_test_secret");

        Ok(())
    });
}

#[test]
fn empty_stripe_webhook_signing_secret_preserves_the_previously_stored_one() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_stripe_webhook_preserved");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            stripe_request(conn, "sk_test_secret", "pk_test_public", "whsec_test_secret_1"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        configure_server(
            stripe_request(conn, "sk_test_secret", "pk_test_public", ""),
            &admin,
            conn,
        )
        .expect("second configure should succeed");

        let stored =
            server_stripe_config(conn).expect("stripe config should still be configured");
        assert_eq!(stored.stripe_secret_key, "sk_test_secret");
        assert_eq!(stored.stripe_webhook_signing_secret, "whsec_test_secret_1");

        Ok(())
    });
}

#[test]
fn setting_stripe_config_to_none_clears_the_stored_secrets() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_stripe_cleared");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        configure_server(
            stripe_request(conn, "sk_test_secret", "pk_test_public", "whsec_test_secret"),
            &admin,
            conn,
        )
        .expect("first configure should succeed");

        let mut clearing_config =
            get_server_configuration_proto(conn).expect("failed to fetch base config");
        clearing_config.stripe_config = None;
        configure_server(clearing_config, &admin, conn).expect("clearing configure should succeed");

        assert_eq!(server_stripe_config(conn), None);

        Ok(())
    });
}

#[test]
fn non_admin_never_sees_stripe_config_from_get_server_configuration() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_stripe_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        configure_server(
            stripe_request(conn, "sk_test_secret", "pk_test_public", "whsec_test_secret"),
            &admin,
            conn,
        )
        .expect("configure should succeed");

        let non_admin = create_user(conn, "cst_stripe_non_admin");
        let result = get_server_configuration(
            (),
            &Some(&non_admin),
            conn,
        )
        .expect("get_server_configuration should succeed");
        assert_eq!(result.stripe_config, None);

        Ok(())
    });
}

/// `market_settings` is a brand-new nullable column -- every server that existed before it did
/// (i.e. every `test_conn()` fixture here, which never calls `ConfigureServer` for it) must still
/// get a well-formed `MarketSettings` back, not `None`/a decode error, same read-time-fallback
/// convention `media_settings` already established. This is the actual behavior Jon asked to
/// double-check: a server that's never touched this setting shouldn't crash or misbehave.
#[test]
fn market_settings_defaults_to_disabled_for_a_server_that_never_set_it() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let config = get_server_configuration_proto(conn).expect("failed to fetch base config");
        assert_eq!(
            config.market_settings,
            Some(MarketSettings { enabled: false, stripe_configured: false })
        );

        Ok(())
    });
}

/// Unlike `stripe_config` (Admin-only, see the spec above), `market_settings` is the deliberately
/// public "is this server's Market open" signal -- even a non-admin (or fully unauthenticated)
/// caller must still see it, or federated multi-server Market browsing (`Pages.Market`) couldn't
/// work at all. See `ServerConfiguration.market_settings`'s own proto doc.
#[test]
fn market_settings_stays_visible_to_non_admins_and_unauthenticated_callers() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "cst_market_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);
        let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
        // `stripe_configured` is never actually written -- `configure_server`/`to_proto` always
        // recompute it live (see that field's own proto doc) -- but it's still required here to
        // construct this `MarketSettings` literal at all.
        config.market_settings = Some(MarketSettings { enabled: true, stripe_configured: false });
        configure_server(config, &admin, conn).expect("configure should succeed");

        let non_admin = create_user(conn, "cst_market_non_admin");
        let non_admin_result = get_server_configuration((), &Some(&non_admin), conn)
            .expect("get_server_configuration should succeed");
        assert_eq!(
            non_admin_result.market_settings,
            Some(MarketSettings { enabled: true, stripe_configured: false })
        );

        let unauthenticated_result =
            get_server_configuration((), &None, conn).expect("get_server_configuration should succeed");
        assert_eq!(
            unauthenticated_result.market_settings,
            Some(MarketSettings { enabled: true, stripe_configured: false })
        );

        Ok(())
    });
}

/// `market_settings.stripe_configured` is computed live off `stripe_config` on every
/// `GetServerConfiguration` -- never read back from whatever's stored on `market_settings` itself
/// (see that field's own proto doc). Unconfigured (never called `configure_stripe`) reads `false`,
/// same as `market_settings_defaults_to_disabled_for_a_server_that_never_set_it` above for
/// `enabled`.
#[test]
fn stripe_configured_is_false_when_stripe_was_never_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let config = get_server_configuration_proto(conn).expect("failed to fetch base config");
        assert_eq!(config.market_settings.unwrap().stripe_configured, false);

        Ok(())
    });
}

/// Credentials on file, but `stripe_enabled` is false -- an admin who's filled in Stripe
/// credentials but hasn't flipped the toggle on yet.
#[test]
fn stripe_configured_is_false_when_stripe_is_disabled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, false, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        let config = get_server_configuration_proto(conn).expect("failed to fetch base config");
        assert_eq!(config.market_settings.unwrap().stripe_configured, false);

        Ok(())
    });
}

/// Enabled, but no secret key on file -- e.g. an admin toggled it on before filling anything in.
#[test]
fn stripe_configured_is_false_when_enabled_but_missing_a_secret_key() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "", "pk_test_public", "whsec_test_secret");
        let config = get_server_configuration_proto(conn).expect("failed to fetch base config");
        assert_eq!(config.market_settings.unwrap().stripe_configured, false);

        Ok(())
    });
}

#[test]
fn stripe_configured_is_true_once_enabled_with_a_secret_key() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        configure_stripe(conn, true, "sk_test_secret", "pk_test_public", "whsec_test_secret");
        let config = get_server_configuration_proto(conn).expect("failed to fetch base config");
        assert_eq!(config.market_settings.unwrap().stripe_configured, true);

        Ok(())
    });
}

mod supported_contact_protocols_spec {
    use super::*;

    #[test]
    fn tel_is_rejected_with_no_sms_provider_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = create_user(conn, "cst_protocols_tel_no_provider");
            let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

            let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
            config.supported_contact_protocols = vec![ContactProtocol::Tel as i32];

            let err = configure_server(config, &admin, conn).unwrap_err();
            assert_eq!(err.code(), tonic::Code::FailedPrecondition);
            assert_eq!(err.message(), "sms_contact_protocol_requires_a_configured_provider");

            Ok(())
        });
    }

    #[test]
    fn mailto_is_always_rejected_even_with_an_sms_provider_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = create_user(conn, "cst_protocols_mailto");
            let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

            let mut config = twilio_request(conn, "AC_sid", "SK_key_sid", "secret", "+15005550006");
            config.supported_contact_protocols = vec![ContactProtocol::Mailto as i32];

            let err = configure_server(config, &admin, conn).unwrap_err();
            assert_eq!(err.code(), tonic::Code::Unimplemented);
            assert_eq!(err.message(), "mailto_contact_protocol_not_supported");

            Ok(())
        });
    }

    #[test]
    fn tel_succeeds_and_round_trips_once_an_sms_provider_is_enabled_in_the_same_request() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = create_user(conn, "cst_protocols_tel_ok");
            let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

            let mut config = twilio_request(conn, "AC_sid", "SK_key_sid", "secret", "+15005550006");
            config.supported_contact_protocols = vec![ContactProtocol::Tel as i32];

            let updated = configure_server(config, &admin, conn).expect("configure should succeed");
            assert_eq!(updated.supported_contact_protocols, vec![ContactProtocol::Tel as i32]);

            Ok(())
        });
    }

    #[test]
    fn disabling_the_only_provider_while_still_claiming_tel_is_rejected() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = create_user(conn, "cst_protocols_tel_disable");
            let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

            let mut config = twilio_request(conn, "AC_sid", "SK_key_sid", "secret", "+15005550006");
            config.supported_contact_protocols = vec![ContactProtocol::Tel as i32];
            configure_server(config, &admin, conn).expect("initial configure should succeed");

            // Same request shape a real save would resend (`ContactIntegrationsTab.elm` always
            // resends its whole loaded config), just with Twilio switched off and
            // `supported_contact_protocols` left untouched -- must be caught, not silently stored.
            let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
            config.twilio_config = config.twilio_config.map(|c| TwilioConfig {
                twilio_enabled: false,
                ..c
            });

            let err = configure_server(config, &admin, conn).unwrap_err();
            assert_eq!(err.code(), tonic::Code::FailedPrecondition);
            assert_eq!(err.message(), "sms_contact_protocol_requires_a_configured_provider");

            Ok(())
        });
    }
}
