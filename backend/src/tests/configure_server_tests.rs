//! Specs for `ConfigureServer`'s handling of `FederationInfo.facebook_auth_config.app_secret` and
//! `FederationInfo.x_twitter_auth_config.client_secret`: both are write-only (never sent back to a
//! client) and an empty incoming value is a deliberate no-op rather than a clear (see
//! `configure_server`'s own doc comment). Everything else about `ConfigureServer` is exercised
//! incidentally by other RPC specs' setup, not tested here.

use diesel::Connection;

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    server_bird_config, server_facebook_app_credentials, server_twilio_config,
    server_x_twitter_app_credentials,
};
use crate::protos::*;
use crate::rpcs::{configure_server, get_server_configuration_proto};
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

/// Mirrors `twilio_request` exactly, against `bird_config` instead.
fn bird_request(conn: &mut PgPooledConnection, access_key: &str, from: &str) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.bird_config = Some(BirdConfig {
        bird_enabled: true,
        bird_access_key: access_key.to_string(),
        bird_from: from.to_string(),
        bird_region: "us1".to_string(),
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
