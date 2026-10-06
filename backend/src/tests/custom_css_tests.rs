//! Specs for `GetCustomCSS`/`ConfigureCustomCSS`: the custom stylesheet lives in
//! `server_configurations.custom_css_configuration` (so it's versioned like every other setting)
//! but is never part of the `ServerConfiguration` proto -- `ConfigureServer` must carry it
//! forward untouched, and only these RPCs (and `/custom_css.css`) read or write it.

use diesel::*;

use crate::logic::{custom_css_etag, custom_css_stylesheet};
use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::{configure_custom_css, configure_server, get_custom_css, get_server_configuration_proto};
use crate::schema::server_configurations;
use crate::tests::factories::*;

fn admin(conn: &mut crate::db_connection::PgPooledConnection) -> crate::models::User {
    let user = create_user(conn, "custom_css_admin");
    grant_permissions(conn, &user, vec![Permission::Admin])
}

fn public_media(
    conn: &mut crate::db_connection::PgPooledConnection,
    owner: &crate::models::User,
) -> String {
    create_media_with_opts(
        conn,
        Some(owner),
        MediaOpts {
            visibility: Visibility::GlobalPublic,
            ..Default::default()
        },
    )
    .id
    .to_proto_id()
}

#[test]
fn get_custom_css_is_empty_when_never_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let result = get_custom_css((), &None, conn)?;
        assert!(result.media_ids.is_empty());
        assert!(result.custom_css.is_empty());
        Ok(())
    });
}

#[test]
fn configure_custom_css_round_trips_through_get_custom_css() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let media_id = public_media(conn, &admin);
        let request = CustomCssConfiguration {
            media_ids: vec![media_id.clone()],
            custom_css: "body { background: var(--custom-media-1); }".to_string(),
        };

        let saved = configure_custom_css(request.clone(), &admin, conn)?;
        assert_eq!(saved, request);
        assert_eq!(get_custom_css((), &None, conn)?, request);
        Ok(())
    });
}

#[test]
fn configure_custom_css_requires_admin() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let user = create_user(conn, "custom_css_non_admin");
        let result = configure_custom_css(CustomCssConfiguration::default(), &user, conn);
        assert!(result.is_err(), "a non-admin must not be able to set custom CSS");
        Ok(())
    });
}

#[test]
fn configure_custom_css_creates_a_new_configuration_version() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let before: i64 = server_configurations::table.count().get_result(conn).unwrap();
        configure_custom_css(
            CustomCssConfiguration { media_ids: vec![], custom_css: "a{}".to_string() },
            &admin,
            conn,
        )?;
        let after: i64 = server_configurations::table.count().get_result(conn).unwrap();
        let active: i64 = server_configurations::table
            .filter(server_configurations::active.eq(true))
            .count()
            .get_result(conn)
            .unwrap();
        // `get_server_configuration_model` may create the default row on first read, so a save adds
        // either one row (config already existed) or two (default + new version).
        assert!(after > before);
        assert_eq!(active, 1, "exactly one configuration version must be active");
        Ok(())
    });
}

#[test]
fn configure_server_carries_custom_css_forward() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let css = CustomCssConfiguration { media_ids: vec![], custom_css: "p { color: red; }".to_string() };
        configure_custom_css(css.clone(), &admin, conn)?;

        // A normal ConfigureServer round trip -- the proto has no custom CSS to send back.
        let config = get_server_configuration_proto(conn)?;
        configure_server(config, &admin, conn)?;

        assert_eq!(get_custom_css((), &None, conn)?, css);
        Ok(())
    });
}

#[test]
fn configure_custom_css_preserves_the_rest_of_the_configuration() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let before = get_server_configuration_proto(conn)?;
        configure_custom_css(
            CustomCssConfiguration { media_ids: vec![], custom_css: "a{}".to_string() },
            &admin,
            conn,
        )?;
        let after = get_server_configuration_proto(conn)?;
        assert_eq!(before.server_info, after.server_info);
        assert_eq!(before.custom_tabs, after.custom_tabs);
        assert_eq!(before.federation_info, after.federation_info);
        Ok(())
    });
}

#[test]
fn configure_custom_css_rejects_oversized_css_and_too_many_media() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let too_big = CustomCssConfiguration {
            media_ids: vec![],
            custom_css: "a".repeat(64 * 1024 + 1),
        };
        assert!(configure_custom_css(too_big, &admin, conn).is_err());

        let media_id = public_media(conn, &admin);
        let too_many = CustomCssConfiguration {
            media_ids: vec![media_id; 33],
            custom_css: String::new(),
        };
        assert!(configure_custom_css(too_many, &admin, conn).is_err());

        let max_size = CustomCssConfiguration {
            media_ids: vec![],
            custom_css: "a".repeat(64 * 1024),
        };
        assert!(configure_custom_css(max_size, &admin, conn).is_ok());
        Ok(())
    });
}

#[test]
fn configure_custom_css_requires_existing_global_public_media() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let server_public = create_media_with_opts(
            conn,
            Some(&admin),
            MediaOpts { visibility: Visibility::ServerPublic, ..Default::default() },
        );
        let result = configure_custom_css(
            CustomCssConfiguration {
                media_ids: vec![server_public.id.to_proto_id()],
                custom_css: String::new(),
            },
            &admin,
            conn,
        );
        assert!(result.is_err(), "non-GLOBAL_PUBLIC media can't be loaded by anonymous visitors");

        let missing = configure_custom_css(
            CustomCssConfiguration {
                media_ids: vec![1_000_000_000i64.to_proto_id()],
                custom_css: String::new(),
            },
            &admin,
            conn,
        );
        assert!(missing.is_err());

        let garbage = configure_custom_css(
            CustomCssConfiguration { media_ids: vec!["not an id!".to_string()], custom_css: String::new() },
            &admin,
            conn,
        );
        assert!(garbage.is_err());
        Ok(())
    });
}

#[test]
fn stylesheet_defines_one_based_custom_media_vars_before_the_css() {
    let sheet = custom_css_stylesheet(&CustomCssConfiguration {
        media_ids: vec!["abc".to_string(), "def".to_string()],
        custom_css: "body { color: red; }".to_string(),
    });
    assert_eq!(
        sheet,
        ":root {\n  --custom-media-1: url(\"/media/abc\");\n  --custom-media-2: url(\"/media/def\");\n}\nbody { color: red; }"
    );
}

#[test]
fn stylesheet_without_media_is_just_the_css() {
    let sheet = custom_css_stylesheet(&CustomCssConfiguration {
        media_ids: vec![],
        custom_css: "a{}".to_string(),
    });
    assert_eq!(sheet, "a{}");
    assert_eq!(custom_css_stylesheet(&CustomCssConfiguration::default()), "");
}

#[test]
fn stylesheet_never_emits_ids_that_could_break_out_of_url() {
    let sheet = custom_css_stylesheet(&CustomCssConfiguration {
        media_ids: vec!["a\");}body{display:none".to_string(), "ok".to_string()],
        custom_css: String::new(),
    });
    assert!(!sheet.contains("display:none"));
    // The skipped id still occupies its slot, so later vars keep their documented numbers.
    assert!(sheet.contains("--custom-media-2: url(\"/media/ok\")"));
}

#[test]
fn etag_tracks_content_only() {
    assert_eq!(custom_css_etag("a{}"), custom_css_etag("a{}"));
    assert_ne!(custom_css_etag("a{}"), custom_css_etag("b{}"));
}
