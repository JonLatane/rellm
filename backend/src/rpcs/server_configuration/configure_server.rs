use crate::schema::server_configurations::dsl::*;
use crate::{db_connection::PgPooledConnection, protos::Permission};
use diesel::*;
use tonic::{Code, Status};

use crate::{
    marshaling::*, models, protos, rpcs::get_server_configuration_model, rpcs::validations::*,
};

pub fn configure_server(
    request: protos::ServerConfiguration,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<protos::ServerConfiguration, Status> {
    log::info!("ConfigureServer called; request {:?}", request);
    validate_permission(&Some(user), Permission::Admin)?;
    validate_configuration(&request)?;

    let mut new_config = request.to_db();
    // `FacebookAuthConfig.app_secret` is write-only -- `to_proto` always blanks it before it
    // reaches a client (see `ToProtoServerConfiguration`), so an empty incoming value means
    // "leave whatever's already stored alone," not "clear it." Setting
    // `federation_info.facebook_auth_config` to `None` entirely is the only way to actually
    // clear a previously-stored secret.
    if let Some(incoming_facebook_auth_config) = request
        .federation_info
        .as_ref()
        .and_then(|f| f.facebook_auth_config.as_ref())
        .filter(|c| c.app_secret.is_empty())
    {
        let existing_secret = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| serde_json::from_value::<protos::FederationInfo>(c.federation_info).ok())
            .and_then(|f| f.facebook_auth_config)
            .map(|c| c.app_secret)
            .unwrap_or_default();
        let mut merged_federation_info: protos::FederationInfo =
            serde_json::from_value(new_config.federation_info.clone()).unwrap();
        merged_federation_info.facebook_auth_config = Some(protos::FacebookAuthConfig {
            app_id: incoming_facebook_auth_config.app_id.clone(),
            app_secret: existing_secret,
        });
        new_config.federation_info = serde_json::to_value(merged_federation_info).unwrap();
    }

    // `XTwitterAuthConfig.client_secret` is write-only, same reasoning (and same merge-on-blank
    // treatment) as `FacebookAuthConfig.app_secret` above.
    if let Some(incoming_x_twitter_auth_config) = request
        .federation_info
        .as_ref()
        .and_then(|f| f.x_twitter_auth_config.as_ref())
        .filter(|c| c.client_secret.is_empty())
    {
        let existing_secret = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| serde_json::from_value::<protos::FederationInfo>(c.federation_info).ok())
            .and_then(|f| f.x_twitter_auth_config)
            .map(|c| c.client_secret)
            .unwrap_or_default();
        let mut merged_federation_info: protos::FederationInfo =
            serde_json::from_value(new_config.federation_info.clone()).unwrap();
        merged_federation_info.x_twitter_auth_config = Some(protos::XTwitterAuthConfig {
            client_id: incoming_x_twitter_auth_config.client_id.clone(),
            client_secret: existing_secret,
        });
        new_config.federation_info = serde_json::to_value(merged_federation_info).unwrap();
    }

    // `WebPushConfig.private_vapid_key` is write-only -- `to_proto` always blanks it before it
    // reaches a client (see `ToProtoServerConfiguration`), so an empty incoming value means
    // "leave whatever's already stored alone," not "clear it." Setting `web_push_config` to
    // `None` entirely is the only way to actually clear a previously-stored config.
    if let Some(incoming_web_push_config) = request
        .web_push_config
        .as_ref()
        .filter(|c| c.private_vapid_key.is_empty())
    {
        let existing_private_key = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.web_push_config)
            .and_then(|c| serde_json::from_value::<protos::WebPushConfig>(c).ok())
            .map(|c| c.private_vapid_key)
            .unwrap_or_default();
        new_config.web_push_config = Some(
            serde_json::to_value(protos::WebPushConfig {
                public_vapid_key: incoming_web_push_config.public_vapid_key.clone(),
                private_vapid_key: existing_private_key,
            })
            .unwrap(),
        );
    }

    // `TwilioConfig.twilio_api_key_secret`/`twilio_webhook_signing_key` are each independently
    // write-only -- `to_proto` always blanks both before reaching a client (see
    // `ToProtoServerConfiguration`), so an empty incoming value for either means "leave whatever's
    // already stored alone," not "clear it." Setting `twilio_config` to `None` entirely is the
    // only way to actually clear a previously-stored config. `twilio_enabled`/`twilio_account_sid`/
    // `twilio_api_key_sid`/`twilio_from_number`/`use_twilio_webhook_signing_key` pass through
    // freely, no scrubbing needed -- an API Key SID is useless without its Secret, same as a
    // username alone, and `use_twilio_webhook_signing_key` isn't a secret at all (it's the
    // "Use Webhook Signing Key" toggle on `ContactIntegrationsTab`).
    if let Some(incoming_twilio_config) = request.twilio_config.as_ref() {
        let existing_twilio_config = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.twilio_config)
            .and_then(|c| serde_json::from_value::<protos::TwilioConfig>(c).ok());
        let existing_api_key_secret = existing_twilio_config
            .as_ref()
            .map(|c| c.twilio_api_key_secret.clone())
            .unwrap_or_default();
        let existing_webhook_signing_key = existing_twilio_config
            .as_ref()
            .map(|c| c.twilio_webhook_signing_key.clone())
            .unwrap_or_default();
        new_config.twilio_config = Some(
            serde_json::to_value(protos::TwilioConfig {
                twilio_enabled: incoming_twilio_config.twilio_enabled,
                twilio_account_sid: incoming_twilio_config.twilio_account_sid.clone(),
                twilio_api_key_sid: incoming_twilio_config.twilio_api_key_sid.clone(),
                twilio_api_key_secret: if incoming_twilio_config.twilio_api_key_secret.is_empty() {
                    existing_api_key_secret
                } else {
                    incoming_twilio_config.twilio_api_key_secret.clone()
                },
                twilio_from_number: incoming_twilio_config.twilio_from_number.clone(),
                twilio_webhook_signing_key: if incoming_twilio_config
                    .twilio_webhook_signing_key
                    .is_empty()
                {
                    existing_webhook_signing_key
                } else {
                    incoming_twilio_config.twilio_webhook_signing_key.clone()
                },
                use_twilio_webhook_signing_key: incoming_twilio_config
                    .use_twilio_webhook_signing_key,
            })
            .unwrap(),
        );
    }

    // Same merge-on-blank treatment as `twilio_config` above, for `BirdConfig.bird_access_key`/
    // `bird_webhook_signing_key`. `bird_enabled`/`bird_from`/`bird_region`/
    // `use_bird_webhook_signing_key` pass through freely, no scrubbing needed.
    if let Some(incoming_bird_config) = request.bird_config.as_ref() {
        let existing_bird_config = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.bird_config)
            .and_then(|c| serde_json::from_value::<protos::BirdConfig>(c).ok());
        let existing_access_key = existing_bird_config
            .as_ref()
            .map(|c| c.bird_access_key.clone())
            .unwrap_or_default();
        let existing_webhook_signing_key = existing_bird_config
            .as_ref()
            .map(|c| c.bird_webhook_signing_key.clone())
            .unwrap_or_default();
        new_config.bird_config = Some(
            serde_json::to_value(protos::BirdConfig {
                bird_enabled: incoming_bird_config.bird_enabled,
                bird_access_key: if incoming_bird_config.bird_access_key.is_empty() {
                    existing_access_key
                } else {
                    incoming_bird_config.bird_access_key.clone()
                },
                bird_from: incoming_bird_config.bird_from.clone(),
                bird_region: incoming_bird_config.bird_region.clone(),
                bird_webhook_signing_key: if incoming_bird_config.bird_webhook_signing_key.is_empty()
                {
                    existing_webhook_signing_key
                } else {
                    incoming_bird_config.bird_webhook_signing_key.clone()
                },
                use_bird_webhook_signing_key: incoming_bird_config.use_bird_webhook_signing_key,
            })
            .unwrap(),
        );
    }

    // Same merge-on-blank treatment as `twilio_config` above, for `TelnyxConfig.telnyx_api_key`/
    // `telnyx_webhook_signing_key`. `telnyx_enabled`/`telnyx_from_number`/
    // `telnyx_messaging_profile_id`/`use_telnyx_webhook_signing_key` pass through freely, no
    // scrubbing needed.
    if let Some(incoming_telnyx_config) = request.telnyx_config.as_ref() {
        let existing_telnyx_config = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.telnyx_config)
            .and_then(|c| serde_json::from_value::<protos::TelnyxConfig>(c).ok());
        let existing_api_key = existing_telnyx_config
            .as_ref()
            .map(|c| c.telnyx_api_key.clone())
            .unwrap_or_default();
        let existing_webhook_signing_key = existing_telnyx_config
            .as_ref()
            .map(|c| c.telnyx_webhook_signing_key.clone())
            .unwrap_or_default();
        new_config.telnyx_config = Some(
            serde_json::to_value(protos::TelnyxConfig {
                telnyx_enabled: incoming_telnyx_config.telnyx_enabled,
                telnyx_api_key: if incoming_telnyx_config.telnyx_api_key.is_empty() {
                    existing_api_key
                } else {
                    incoming_telnyx_config.telnyx_api_key.clone()
                },
                telnyx_from_number: incoming_telnyx_config.telnyx_from_number.clone(),
                telnyx_messaging_profile_id: incoming_telnyx_config
                    .telnyx_messaging_profile_id
                    .clone(),
                telnyx_webhook_signing_key: if incoming_telnyx_config
                    .telnyx_webhook_signing_key
                    .is_empty()
                {
                    existing_webhook_signing_key
                } else {
                    incoming_telnyx_config.telnyx_webhook_signing_key.clone()
                },
                use_telnyx_webhook_signing_key: incoming_telnyx_config
                    .use_telnyx_webhook_signing_key,
            })
            .unwrap(),
        );
    }

    // Same merge-on-blank treatment as `twilio_config` above, for `StripeConfig.stripe_secret_key`/
    // `stripe_webhook_signing_secret` -- both write-only (`to_proto` always blanks them before
    // reaching a client), so an empty incoming value means "leave whatever's already stored alone."
    // `stripe_enabled`/`stripe_publishable_key` pass through freely, no scrubbing needed.
    if let Some(incoming_stripe_config) = request.stripe_config.as_ref() {
        let existing_stripe_config = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.stripe_config)
            .and_then(|c| serde_json::from_value::<protos::StripeConfig>(c).ok());
        let existing_secret_key = existing_stripe_config
            .as_ref()
            .map(|c| c.stripe_secret_key.clone())
            .unwrap_or_default();
        let existing_webhook_signing_secret = existing_stripe_config
            .as_ref()
            .map(|c| c.stripe_webhook_signing_secret.clone())
            .unwrap_or_default();
        new_config.stripe_config = Some(
            serde_json::to_value(protos::StripeConfig {
                stripe_enabled: incoming_stripe_config.stripe_enabled,
                stripe_publishable_key: incoming_stripe_config.stripe_publishable_key.clone(),
                stripe_secret_key: if incoming_stripe_config.stripe_secret_key.is_empty() {
                    existing_secret_key
                } else {
                    incoming_stripe_config.stripe_secret_key.clone()
                },
                stripe_webhook_signing_secret: if incoming_stripe_config
                    .stripe_webhook_signing_secret
                    .is_empty()
                {
                    existing_webhook_signing_secret
                } else {
                    incoming_stripe_config.stripe_webhook_signing_secret.clone()
                },
            })
            .unwrap(),
        );
    }

    // `media_settings.server_media_usage_bytes`/`server_media_usage_calculated_at`/
    // `server_object_storage_usage_bytes`/`server_object_storage_usage_calculated_at` are
    // read-only -- populated only by the `calculate_server_media_usage`/
    // `calculate_server_object_storage_usage` background jobs and by incremental adjustments at
    // Media mutation call sites (see those fields' own docs in server_configuration.proto) -- so
    // they're always carried forward from the currently active config here, regardless of what
    // `request` sent for them (never trusted from a client, same reasoning as
    // `ClusterConductorState.conductor_state.locks` below). `server_media_allocation_bytes`
    // additionally requires `EDIT_SERVER_MEDIA_ALLOCATION` to actually change here -- same
    // `validate_exact_permission` gating as `cluster_resources`/`EDIT_CLUSTER_SETTINGS` below --
    // without it, that one field is *also* carried forward, but the rest of `media_settings`
    // (`visible`/`default_moderation`/`default_visibility`/
    // `default_user_media_allocation_bytes`) still comes from `request` as normal, same as any
    // other plain `ADMIN`-editable setting. A `None` `request.media_settings` leaves the whole
    // thing untouched (carried forward as-is), same "omitting a submessage never clears it"
    // treatment as `cluster_resources` below.
    let existing_media_settings = get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.media_settings)
        .and_then(|v| serde_json::from_value::<protos::MediaSettings>(v).ok())
        .unwrap_or_default();
    let can_edit_server_media_allocation =
        validate_exact_permission(&Some(user), Permission::EditServerMediaAllocation).is_ok();
    new_config.media_settings = request.media_settings.as_ref().map(|incoming| {
        serde_json::to_value(protos::MediaSettings {
            server_media_allocation_bytes: if can_edit_server_media_allocation {
                incoming.server_media_allocation_bytes
            } else {
                existing_media_settings.server_media_allocation_bytes
            },
            server_media_usage_bytes: existing_media_settings.server_media_usage_bytes,
            server_media_usage_calculated_at: existing_media_settings
                .server_media_usage_calculated_at
                .clone(),
            server_object_storage_usage_bytes: existing_media_settings
                .server_object_storage_usage_bytes,
            server_object_storage_usage_calculated_at: existing_media_settings
                .server_object_storage_usage_calculated_at
                .clone(),
            ..incoming.clone()
        })
        .unwrap()
    });

    // `cluster_resources` is admin-visible but only *editable* with `EDIT_CLUSTER_SETTINGS` (see
    // that permission's own doc). `conductor_state` as a whole is never *settable* via
    // `ConfigureServer` at all regardless of permission -- only `LockClusterResources`/
    // `FreeClusterResources` ever populate/mutate it (in place, outside this function's own
    // versioned insert), and only on an instance actually acting as a conductor -- but
    // `conductor_state.limits` *is* editable here, once that state already exists, same gating as
    // the rest of `cluster_resources` (see `ClusterConductorState.limits`'s own doc). So this
    // always overwrites whatever `to_db()` naively produced: without `EDIT_CLUSTER_SETTINGS`, the
    // whole field is carried forward unchanged from the currently active config (ignoring the
    // incoming request's copy of it entirely); with it, `namespace_id`/`conductor_host`/`limits`
    // come from the request (blank `cluster_shared_secret` preserving the existing one, same
    // write-only treatment as `FacebookAuthConfig.app_secret` above), but `conductor_state` itself
    // is still always carried forward from the active config as a whole (`None` stays `None` --
    // pointing `conductor_host` at some other instance doesn't make *this* one a conductor -- and
    // `locks` is never touched even when `Some`).
    let existing_cluster_resources = get_server_configuration_model(conn)
        .ok()
        .and_then(|c| c.cluster_resources)
        .and_then(|v| serde_json::from_value::<protos::ClusterResources>(v).ok());
    // `validate_exact_permission`, not `validate_permission` -- `EDIT_CLUSTER_SETTINGS` is
    // deliberately admin-insufficient (see that permission's own doc); `validate_permission`
    // would let any `ADMIN` through regardless, defeating the point.
    let can_edit_cluster_settings =
        validate_exact_permission(&Some(user), Permission::EditClusterSettings).is_ok();
    new_config.cluster_resources = if can_edit_cluster_settings {
        request.cluster_resources.as_ref().map(|incoming| {
            let existing_secret = existing_cluster_resources
                .as_ref()
                .map(|c| c.cluster_shared_secret.clone())
                .unwrap_or_default();
            let existing_conductor_state = existing_cluster_resources
                .as_ref()
                .and_then(|c| c.conductor_state.clone());
            serde_json::to_value(protos::ClusterResources {
                namespace_id: incoming.namespace_id.clone(),
                conductor_host: incoming.conductor_host.clone(),
                cluster_shared_secret: if incoming.cluster_shared_secret.is_empty() {
                    existing_secret
                } else {
                    incoming.cluster_shared_secret.clone()
                },
                // `None` (not `Some(_::default())`) whenever this instance was never itself a
                // conductor (`existing_conductor_state` unset) -- forcing `Some` here regardless,
                // as this used to, populated `conductor_state` on every satellite the moment an
                // admin merely pointed it *at* a conductor and saved, which `ClusterTab.elm`'s
                // "Held Locks"/"Limits" sections take as "this instance IS the conductor" (see
                // `ClusterResources.conductor_state`'s own doc: only `LockClusterResources`/
                // `FreeClusterResources` -- i.e. actually being asked to broker a lock -- may
                // populate it). `.limits` is still editable here, but only once this instance
                // already has conductor state to edit.
                conductor_state: existing_conductor_state.as_ref().map(|existing| {
                    protos::ClusterConductorState {
                        locks: existing.locks.clone(),
                        limits: incoming
                            .conductor_state
                            .as_ref()
                            .map(|s| s.limits.clone())
                            .unwrap_or_else(|| existing.limits.clone()),
                    }
                }),
            })
            .unwrap()
        })
    } else {
        existing_cluster_resources.map(|c| serde_json::to_value(c).unwrap())
    };

    let result =
        conn.transaction::<models::ServerConfiguration, diesel::result::Error, _>(|conn| {
            update(server_configurations)
                .set(active.eq(false))
                .execute(conn)?;
            let configuration = insert_into(server_configurations)
                .values(&new_config)
                .get_result::<models::ServerConfiguration>(conn)?;
            Ok(configuration)
        });
    match result {
        Ok(configuration) => {
            log::info!(
                "ConfigureServer called; updated configuration to {:?}",
                configuration.to_proto()
            );
            Ok(configuration.to_proto())
        }
        Err(e) => {
            log::error!("ConfigureServer failed. Error: {:?}", e);
            Err(Status::new(Code::Internal, "error_updating"))
        }
    }
}
