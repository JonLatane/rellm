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

    // `TwilioConfig.twilio_api_key_secret` (the API Key's Secret) is write-only -- `to_proto`
    // always blanks it before it reaches a client (see `ToProtoServerConfiguration`), so an empty
    // incoming value means "leave whatever's already stored alone," not "clear it." Setting
    // `twilio_config` to `None` entirely is the only way to actually clear a previously-stored
    // config. `twilio_enabled`/`twilio_account_sid`/`twilio_api_key_sid`/`twilio_from_number` pass
    // through freely, no scrubbing needed -- an API Key SID is useless without its Secret, same as
    // a username alone.
    if let Some(incoming_twilio_config) = request
        .twilio_config
        .as_ref()
        .filter(|c| c.twilio_api_key_secret.is_empty())
    {
        let existing_api_key_secret = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.twilio_config)
            .and_then(|c| serde_json::from_value::<protos::TwilioConfig>(c).ok())
            .map(|c| c.twilio_api_key_secret)
            .unwrap_or_default();
        new_config.twilio_config = Some(
            serde_json::to_value(protos::TwilioConfig {
                twilio_enabled: incoming_twilio_config.twilio_enabled,
                twilio_account_sid: incoming_twilio_config.twilio_account_sid.clone(),
                twilio_api_key_sid: incoming_twilio_config.twilio_api_key_sid.clone(),
                twilio_api_key_secret: existing_api_key_secret,
                twilio_from_number: incoming_twilio_config.twilio_from_number.clone(),
            })
            .unwrap(),
        );
    }

    // Same merge-on-blank treatment as `twilio_config` above, for `BirdConfig.bird_access_key`.
    // `bird_enabled`/`bird_from`/`bird_region` pass through freely, no scrubbing needed.
    if let Some(incoming_bird_config) = request
        .bird_config
        .as_ref()
        .filter(|c| c.bird_access_key.is_empty())
    {
        let existing_access_key = get_server_configuration_model(conn)
            .ok()
            .and_then(|c| c.bird_config)
            .and_then(|c| serde_json::from_value::<protos::BirdConfig>(c).ok())
            .map(|c| c.bird_access_key)
            .unwrap_or_default();
        new_config.bird_config = Some(
            serde_json::to_value(protos::BirdConfig {
                bird_enabled: incoming_bird_config.bird_enabled,
                bird_access_key: existing_access_key,
                bird_from: incoming_bird_config.bird_from.clone(),
                bird_region: incoming_bird_config.bird_region.clone(),
            })
            .unwrap(),
        );
    }

    // `cluster_resources` is admin-visible but only *editable* with `EDIT_CLUSTER_SETTINGS` (see
    // that permission's own doc). `conductor_state.locks` specifically is never settable via
    // `ConfigureServer` at all regardless of permission -- only `LockClusterResources`/
    // `FreeClusterResources` ever mutate it (in place, outside this function's own versioned
    // insert) -- but `conductor_state.limits` *is* editable here, same gating as the rest of
    // `cluster_resources` (see `ClusterConductorState.limits`'s own doc). So this always
    // overwrites whatever `to_db()` naively produced: without `EDIT_CLUSTER_SETTINGS`, the whole
    // field is carried forward unchanged from the currently active config (ignoring the incoming
    // request's copy of it entirely); with it, `namespace_id`/`conductor_host`/`limits` come from
    // the request (blank `cluster_shared_secret` preserving the existing one, same write-only
    // treatment as `FacebookAuthConfig.app_secret` above), but `locks` is still always carried
    // forward from the active config.
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
                conductor_state: Some(protos::ClusterConductorState {
                    locks: existing_conductor_state
                        .as_ref()
                        .map(|s| s.locks.clone())
                        .unwrap_or_default(),
                    limits: incoming
                        .conductor_state
                        .as_ref()
                        .map(|s| s.limits.clone())
                        .unwrap_or_else(|| {
                            existing_conductor_state
                                .map(|s| s.limits)
                                .unwrap_or_default()
                        }),
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
