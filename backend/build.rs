use std::{env, fs, path::PathBuf};

fn main() {
    let proto_file = "../protos/rellm.proto";
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let _ = fs::create_dir("./target");
    let _ = fs::create_dir("./target/compiled_protos");
    tonic_prost_build::configure()
        .build_server(true)
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        // Used for updating servers from 0.5.551 -> 0.5.553+. Can be removed
        // in the distant future.
        // Lets `event_settings` JSON stored before this field existed deserialize
        // instead of erroring, defaulting to CALENDAR_DISPLAY_WEEK (proto enum value 0).
        .field_attribute(
            "EventSettings.default_calendar_display_mode",
            "#[serde(default)]",
        )
        // Same as above, for `show_started_or_long_events_by_default` -- lets `event_settings`
        // JSON stored before this field existed deserialize instead of erroring, defaulting to
        // `false`.
        .field_attribute(
            "EventSettings.show_started_or_long_events_by_default",
            "#[serde(default)]",
        )
        // Same idea, for `FederationInfo.mastodon_servers` (added alongside `MastodonServer`) --
        // lets `federation_info` JSON stored before this field existed deserialize instead of
        // erroring, defaulting to an empty list. Unlike the two above, this one's a `repeated`
        // field (`Vec<MastodonServer>`), not an `optional` one -- serde already tolerates a
        // missing `Option` field for free, but a missing `Vec` field is a hard error without this.
        .field_attribute("FederationInfo.mastodon_servers", "#[serde(default)]")
        // Same idea, for `ClusterConductorState.limits` (added alongside `ClusterResourceLimit`,
        // after `cluster_resources.conductor_state` had already accumulated real stored data, e.g.
        // `locks`) -- lets that pre-existing JSON deserialize instead of erroring on the newly
        // missing key, defaulting to an empty list (`ClusterTab.elm`'s `effectiveLimit`, and
        // `lock_cluster_resources.rs`'s own `effective_limit`, already treat an empty/missing
        // `limits` list as every `ClusterResource` defaulting to `1`).
        .field_attribute("ClusterConductorState.limits", "#[serde(default)]")
        // Same idea, for `CustomNavigationTabSet.tab_style` (added alongside `NavigationTabStyle`)
        // -- lets `custom_tabs` JSON stored before this field existed deserialize instead of
        // erroring, defaulting to NAVIGATION_TAB_ICON_ONLY (proto enum value 0, the nav's existing
        // icon-only look). Without this, `configuration_marshaling::deserialize_custom_tabs`'s
        // "current shape" parse would fail on every pre-existing `custom_tabs` blob (none of which
        // have a `tab_style` key), falling through to its legacy-shape attempt and, since that one's
        // `home` type doesn't match either, resetting the admin's whole `custom_tabs` -- tabs and
        // all -- back to unset.
        .field_attribute("CustomNavigationTabSet.tab_style", "#[serde(default)]")
        // Same idea, for `RellmHostingSubscriptionDetails.fulfillment_status`/`fulfillment_notes`
        // (added for `/market/fulfillment` -- see `UpdateMarketSubscription`'s own doc) -- lets a
        // `market_subscriptions`/`market_products` row's `details` JSON, stored before these two
        // fields existed, deserialize instead of erroring: `fulfillment_status` defaults to `0`
        // (`FULFILLMENT_STATUS_AWAITING_HOST_ADMIN` -- correct anyway, since it's always
        // server-recomputed from `fulfillment_notes`' own last entry right after deserializing, same
        // as `MarketSettings.stripe_configured` below), and `fulfillment_notes` (a `repeated` field,
        // same reasoning as `mastodon_servers` above) to an empty list.
        .field_attribute(
            "RellmHostingSubscriptionDetails.fulfillment_status",
            "#[serde(default)]",
        )
        .field_attribute(
            "RellmHostingSubscriptionDetails.fulfillment_notes",
            "#[serde(default)]",
        )
        // Same idea, for `FulfillmentNote.fulfillment_status` -- lets a `fulfillment_notes` entry
        // stored before this field existed (none should exist outside dev/test data, but the
        // pattern's cheap insurance regardless) deserialize instead of erroring, defaulting to
        // `FULFILLMENT_STATUS_AWAITING_HOST_ADMIN`.
        .field_attribute("FulfillmentNote.fulfillment_status", "#[serde(default)]")
        // Same idea, for `MarketSettings.stripe_configured` -- lets `market_settings` JSON stored
        // before this field existed (i.e. every server with Market already turned on) deserialize
        // instead of erroring. Doesn't actually matter for correctness either way --
        // `configuration_marshaling::to_proto` always overwrites this field with a freshly computed
        // value right after deserializing (see that function's own comment) -- but without this, a
        // pre-existing `market_settings` blob missing this key would fail the whole `MarketSettings`
        // deserialize and silently reset `enabled` back to `false` too.
        .field_attribute("MarketSettings.stripe_configured", "#[serde(default)]")
        // This is specifically for rust-analyzer in VSCode
        // .client_attribute(".", "#![allow(non_snake_case)]")
        .extern_path(".google.protobuf.Any", "::prost_wkt_types::Any")
        .extern_path(".google.protobuf.Timestamp", "::prost_wkt_types::Timestamp")
        .extern_path(".google.protobuf.Value", "::prost_wkt_types::Value")
        .file_descriptor_set_path(out_dir.join("greeter_descriptor.bin"))
        .out_dir("./src/protos")
        .compile_protos(&[proto_file], &["../protos"])
        .unwrap_or_else(|e| panic!("protobuf compile error: {}", e));

    // `rellm.proto` imports nearly every other file under `../protos` (sync.proto,
    // permissions.proto, ai_providers.proto, etc), but Cargo only reruns this script for
    // paths explicitly named here -- watching just `proto_file` meant editing an *imported* .proto
    // alone left the generated code stale until something else (e.g. `make rebuild_protos`) forced
    // a full recompile. Watch every .proto file in the directory instead.
    for entry in fs::read_dir("../protos").expect("failed to read ../protos") {
        let path = entry.expect("failed to read ../protos entry").path();
        if path.extension().and_then(|ext| ext.to_str()) == Some("proto") {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }
}
