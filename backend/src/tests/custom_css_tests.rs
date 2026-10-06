//! Specs for `GetCustomCSS`/`ConfigureCustomCSS`: the custom stylesheet lives in the
//! `server_configurations` table (so it's versioned like every other setting) -- its media IDs and forced
//! theme in `custom_css_configuration`, and the (potentially large) text in its own `custom_css` column that
//! `ServerConfiguration` never loads. `GetServerConfiguration` carries the former (with `custom_css` unset),
//! `ConfigureServer` must carry both forward untouched, and only these RPCs (and `/custom_css.css`) read or
//! write the text.

use diesel::*;

use crate::logic::{
    custom_css_etag, custom_css_stylesheet, get_custom_css_text, if_none_match_matches,
};
use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::{
    configure_custom_css, configure_server, get_custom_css, get_server_configuration,
    get_server_configuration_proto,
};
use crate::schema::server_configurations;
use crate::tests::factories::*;

/// A `CustomCssConfiguration` with just the media and CSS text set.
fn css(media_ids: Vec<String>, text: &str) -> CustomCssConfiguration {
    CustomCssConfiguration {
        media_ids,
        custom_css: Some(text.to_string()),
        ..Default::default()
    }
}

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
        assert_eq!(result.custom_css.as_deref(), Some(""), "GetCustomCSS always returns the text");
        assert!(!result.force_light_theme && !result.force_dark_theme);
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
            force_light_theme: true,
            ..css(
                vec![media_id.clone()],
                "body { background: var(--custom-media-1); }",
            )
        };

        let saved = configure_custom_css(request.clone(), &admin, conn)?;
        assert_eq!(saved, request);
        assert_eq!(get_custom_css((), &None, conn)?, request);
        Ok(())
    });
}

#[test]
fn get_server_configuration_carries_media_and_theme_but_never_the_css() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let media_id = public_media(conn, &admin);
        configure_custom_css(
            CustomCssConfiguration {
                force_dark_theme: true,
                ..css(vec![media_id.clone()], "body { color: red; }")
            },
            &admin,
            conn,
        )?;

        let served = get_server_configuration((), &None, conn)?
            .custom_css_configuration
            .expect("the configuration includes custom_css_configuration once set");
        assert_eq!(served.media_ids, vec![media_id]);
        assert!(served.force_dark_theme);
        assert!(!served.force_light_theme);
        assert_eq!(served.custom_css, None, "the stylesheet text must never ride along");

        // Same for the admin's own ConfigureServer response.
        let echoed = configure_server(get_server_configuration_proto(conn)?, &admin, conn)?;
        assert_eq!(echoed.custom_css_configuration.unwrap().custom_css, None);
        Ok(())
    });
}

#[test]
fn get_server_configuration_does_not_load_the_custom_css_column() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        configure_custom_css(css(vec![], "a { color: red; }"), &admin, conn)?;

        // The text really is stored in its own column...
        assert_eq!(get_custom_css_text(conn)?, Some("a { color: red; }".to_string()));
        // ...and the JSON column that GetServerConfiguration reads holds only the settings, so the text
        // can't have come along that way either.
        let json: Option<serde_json::Value> = server_configurations::table
            .filter(server_configurations::active.eq(true))
            .select(server_configurations::custom_css_configuration)
            .first(conn)
            .unwrap();
        let json = json.expect("settings are stored");
        assert!(
            json.get("custom_css").map_or(true, |v| v.is_null()),
            "custom_css_configuration JSON must not carry the stylesheet: {json}"
        );
        Ok(())
    });
}

#[test]
fn configure_custom_css_with_unset_css_keeps_the_stored_stylesheet() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        configure_custom_css(css(vec![], "p { color: blue; }"), &admin, conn)?;

        // A toggle-only save: no `custom_css` in the request.
        let saved = configure_custom_css(
            CustomCssConfiguration {
                force_light_theme: true,
                ..Default::default()
            },
            &admin,
            conn,
        )?;
        assert_eq!(saved.custom_css.as_deref(), Some("p { color: blue; }"));
        assert!(saved.force_light_theme);
        assert_eq!(
            get_custom_css((), &None, conn)?.custom_css.as_deref(),
            Some("p { color: blue; }")
        );

        // An explicit empty string clears it.
        let cleared = configure_custom_css(css(vec![], ""), &admin, conn)?;
        assert_eq!(cleared.custom_css.as_deref(), Some(""));
        Ok(())
    });
}

#[test]
fn configure_custom_css_rejects_forcing_both_themes() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let result = configure_custom_css(
            CustomCssConfiguration {
                force_light_theme: true,
                force_dark_theme: true,
                ..Default::default()
            },
            &admin,
            conn,
        );
        assert!(result.is_err(), "light and dark can't both be forced");
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
        configure_custom_css(css(vec![], "a{}"), &admin, conn)?;
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
        let saved = CustomCssConfiguration {
            force_light_theme: true,
            ..css(vec![], "p { color: red; }")
        };
        configure_custom_css(saved.clone(), &admin, conn)?;

        // A normal ConfigureServer round trip -- even one that tries to overwrite the custom CSS.
        let mut config = get_server_configuration_proto(conn)?;
        config.custom_css_configuration = Some(CustomCssConfiguration {
            force_dark_theme: true,
            ..css(vec![], "ignored")
        });
        configure_server(config, &admin, conn)?;

        assert_eq!(get_custom_css((), &None, conn)?, saved);
        Ok(())
    });
}

#[test]
fn configure_custom_css_preserves_the_rest_of_the_configuration() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let before = get_server_configuration_proto(conn)?;
        configure_custom_css(css(vec![], "a{}"), &admin, conn)?;
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
        let too_big = css(vec![], &"a".repeat(64 * 1024 + 1));
        assert!(configure_custom_css(too_big, &admin, conn).is_err());

        let media_id = public_media(conn, &admin);
        let too_many = css(vec![media_id; 33], "");
        assert!(configure_custom_css(too_many, &admin, conn).is_err());

        let max_size = css(vec![], &"a".repeat(64 * 1024));
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
            css(vec![server_public.id.to_proto_id()], ""),
            &admin,
            conn,
        );
        assert!(result.is_err(), "non-GLOBAL_PUBLIC media can't be loaded by anonymous visitors");

        let missing = configure_custom_css(css(vec![1_000_000_000i64.to_proto_id()], ""), &admin, conn);
        assert!(missing.is_err());

        let garbage = configure_custom_css(css(vec!["not an id!".to_string()], ""), &admin, conn);
        assert!(garbage.is_err());
        Ok(())
    });
}

/// The color variables every stylesheet starts with, for a server with no configured colors.
const DEFAULT_COLOR_VARS: &str = "  --primary-color: #424242;\n  --nav-color: #ffffff;\n";

#[test]
fn stylesheet_defines_one_based_custom_media_vars_before_the_css() {
    let sheet = custom_css_stylesheet(
        &css(
            vec!["abc".to_string(), "def".to_string()],
            "body { color: red; }",
        ),
        None,
    );
    assert_eq!(
        sheet,
        format!(
            ":root {{\n{DEFAULT_COLOR_VARS}  --custom-media-1: url(\"/media/abc\");\n  --custom-media-2: url(\"/media/def\");\n}}\nbody {{ color: red; }}"
        )
    );
}

#[test]
fn stylesheet_without_media_is_the_color_vars_then_the_css() {
    assert_eq!(
        custom_css_stylesheet(&css(vec![], "a{}"), None),
        format!(":root {{\n{DEFAULT_COLOR_VARS}}}\na{{}}")
    );
    // Never empty: even with no custom CSS at all, the variables are there.
    assert_eq!(
        custom_css_stylesheet(&CustomCssConfiguration::default(), None),
        format!(":root {{\n{DEFAULT_COLOR_VARS}}}\n")
    );
}

#[test]
fn stylesheet_defines_primary_and_nav_color_from_the_servers_colors() {
    let colors = ServerColors {
        // ARGB: only the low 24 bits (RGB) count.
        primary: Some(0xFF2E86AB),
        navigation: Some(0x00A23B72),
        ..Default::default()
    };
    let sheet = custom_css_stylesheet(&css(vec![], ""), Some(&colors));
    assert!(sheet.contains("  --primary-color: #2e86ab;\n"), "{sheet}");
    assert!(sheet.contains("  --nav-color: #a23b72;\n"), "{sheet}");

    // A color left unset falls back to the same default the Elm client uses.
    let only_primary = ServerColors { primary: Some(0xFF010203), ..Default::default() };
    let sheet = custom_css_stylesheet(&css(vec![], ""), Some(&only_primary));
    assert!(sheet.contains("--primary-color: #010203;"));
    assert!(sheet.contains("--nav-color: #ffffff;"));
}

#[test]
fn stylesheet_never_emits_ids_that_could_break_out_of_url() {
    let sheet = custom_css_stylesheet(
        &css(
            vec!["a\");}body{display:none".to_string(), "ok".to_string()],
            "",
        ),
        None,
    );
    assert!(!sheet.contains("display:none"));
    // The skipped id still occupies its slot, so later vars keep their documented numbers.
    assert!(sheet.contains("--custom-media-2: url(\"/media/ok\")"));
}

#[test]
fn if_none_match_accepts_weak_lists_and_wildcard() {
    let etag = custom_css_etag("a{}");
    assert!(if_none_match_matches(&etag, &etag));
    // A CDN that compresses the body turns the strong tag into a weak one; the browser echoes that back.
    assert!(if_none_match_matches(&format!("W/{etag}"), &etag));
    assert!(if_none_match_matches(&format!("\"other\", W/{etag} , \"more\""), &etag));
    assert!(if_none_match_matches("*", &etag));
    assert!(!if_none_match_matches(&custom_css_etag("b{}"), &etag));
    assert!(!if_none_match_matches("", &etag));
    assert!(!if_none_match_matches(",", &etag));
}

#[test]
fn etag_tracks_content_only() {
    assert_eq!(custom_css_etag("a{}"), custom_css_etag("a{}"));
    assert_ne!(custom_css_etag("a{}"), custom_css_etag("b{}"));
}

// ---- Configuration lifecycle: versioning, interleaved writers, and whatever is already stored ----

/// Overwrites the active row's `custom_css_configuration` JSON directly -- how rows written by older
/// builds (or corrupted ones) look to the code that reads them.
fn set_stored_settings_json(
    conn: &mut crate::db_connection::PgPooledConnection,
    json: Option<serde_json::Value>,
) {
    update(server_configurations::table.filter(server_configurations::active.eq(true)))
        .set(server_configurations::custom_css_configuration.eq(json))
        .execute(conn)
        .unwrap();
}

fn config_row_count(conn: &mut crate::db_connection::PgPooledConnection) -> i64 {
    server_configurations::table.count().get_result(conn).unwrap()
}

#[test]
fn configure_server_never_invents_custom_css() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        // Nothing was ever configured: a ConfigureServer save must leave it that way (no `Some("")`, no `{}`).
        configure_server(get_server_configuration_proto(conn)?, &admin, conn)?;
        assert_eq!(get_custom_css_text(conn)?, None);
        assert_eq!(get_server_configuration((), &None, conn)?.custom_css_configuration, None);
        assert_eq!(get_custom_css((), &None, conn)?, css(vec![], ""));
        Ok(())
    });
}

#[test]
fn a_rejected_save_creates_no_new_version_and_changes_nothing() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let stored = css(vec![], "p { color: green; }");
        configure_custom_css(stored.clone(), &admin, conn)?;
        let rows = config_row_count(conn);

        let non_admin = create_user(conn, "custom_css_rejected_non_admin");
        assert!(configure_custom_css(css(vec![], "evil{}"), &non_admin, conn).is_err());
        assert!(configure_custom_css(css(vec![], &"a".repeat(64 * 1024 + 1)), &admin, conn).is_err());
        let both = CustomCssConfiguration {
            force_light_theme: true,
            force_dark_theme: true,
            ..css(vec![], "also-evil{}")
        };
        assert!(configure_custom_css(both, &admin, conn).is_err());

        assert_eq!(config_row_count(conn), rows, "a rejected save must not insert a version");
        assert_eq!(get_custom_css((), &None, conn)?, stored);
        Ok(())
    });
}

#[test]
fn every_save_is_a_version_and_older_versions_keep_their_css() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        configure_custom_css(css(vec![], "first{}"), &admin, conn)?;
        configure_custom_css(css(vec![], "second{}"), &admin, conn)?;
        // A ConfigureServer save in between is a version too, and carries the CSS onto it.
        configure_server(get_server_configuration_proto(conn)?, &admin, conn)?;
        configure_custom_css(css(vec![], "third{}"), &admin, conn)?;

        let stored: Vec<(bool, Option<String>)> = server_configurations::table
            .filter(server_configurations::custom_css.is_not_null())
            .order(server_configurations::id.asc())
            .select((server_configurations::active, server_configurations::custom_css))
            .load(conn)
            .unwrap();
        let texts: Vec<&str> = stored.iter().map(|(_, t)| t.as_deref().unwrap()).collect();
        assert_eq!(texts, vec!["first{}", "second{}", "second{}", "third{}"]);
        assert_eq!(
            stored.iter().map(|(active, _)| *active).collect::<Vec<_>>(),
            vec![false, false, false, true],
            "only the newest version is active"
        );
        Ok(())
    });
}

#[test]
fn server_settings_and_custom_css_survive_each_others_saves() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        let saved = CustomCssConfiguration {
            force_dark_theme: true,
            ..css(vec![], "h1 { color: teal; }")
        };

        // ConfigureServer (renaming the server) -> ConfigureCustomCSS -> ConfigureServer, with the other
        // writer's setting checked after each step.
        let mut config = get_server_configuration_proto(conn)?;
        config.server_info.as_mut().unwrap().name = Some("Renamed Server".to_string());
        configure_server(config, &admin, conn)?;

        configure_custom_css(saved.clone(), &admin, conn)?;
        assert_eq!(
            get_server_configuration_proto(conn)?.server_info.unwrap().name.as_deref(),
            Some("Renamed Server"),
            "ConfigureCustomCSS must carry the rest of the configuration forward"
        );

        let mut config = get_server_configuration_proto(conn)?;
        config.server_info.as_mut().unwrap().name = Some("Renamed Again".to_string());
        configure_server(config, &admin, conn)?;
        assert_eq!(get_custom_css((), &None, conn)?, saved, "ConfigureServer must carry the CSS forward");
        assert_eq!(
            get_server_configuration_proto(conn)?.server_info.unwrap().name.as_deref(),
            Some("Renamed Again")
        );
        Ok(())
    });
}

#[test]
fn stored_settings_from_older_builds_still_load_and_never_leak_the_text() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        configure_custom_css(css(vec![], "real{}"), &admin, conn)?;

        // Before the `custom_css` column existed the text rode in this JSON, and a row may predate any of
        // the other fields: it must still parse, with the text stripped and absent fields defaulted.
        set_stored_settings_json(conn, Some(serde_json::json!({ "custom_css": "legacy-leak{}" })));
        let served = get_server_configuration((), &None, conn)?
            .custom_css_configuration
            .expect("a parseable object is served");
        assert_eq!(served, CustomCssConfiguration::default(), "no text, no media, no forced theme");

        // GetCustomCSS reads the text from its own column only.
        assert_eq!(get_custom_css((), &None, conn)?.custom_css.as_deref(), Some("real{}"));
        Ok(())
    });
}

#[test]
fn unparseable_stored_settings_are_treated_as_unset_not_an_error() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = admin(conn);
        configure_custom_css(css(vec![], "kept{}"), &admin, conn)?;
        set_stored_settings_json(conn, Some(serde_json::json!("not an object")));

        // The server keeps serving its configuration and a (settings-less) stylesheet...
        assert_eq!(get_server_configuration((), &None, conn)?.custom_css_configuration, None);
        let served = get_custom_css((), &None, conn)?;
        assert!(served.media_ids.is_empty() && !served.force_light_theme && !served.force_dark_theme);
        assert_eq!(served.custom_css.as_deref(), Some("kept{}"));

        // ...and an admin can repair it with a normal save, which keeps the stored text.
        let repaired = configure_custom_css(
            CustomCssConfiguration { force_light_theme: true, ..Default::default() },
            &admin,
            conn,
        )?;
        assert!(repaired.force_light_theme);
        assert_eq!(repaired.custom_css.as_deref(), Some("kept{}"));
        Ok(())
    });
}
