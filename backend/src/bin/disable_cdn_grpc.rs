extern crate diesel;
extern crate rellm;
use std::sync::Arc;

use diesel::*;
use rellm::{
    db_connection, init_bin_logging, init_crypto, marshaling::*, models, protos, rpcs, schema,
};

pub fn main() {
    init_crypto();
    init_bin_logging();
    log::info!("Disabling gRPC CDN support...");
    log::info!("Connecting to DB...");
    let pool = Arc::new(db_connection::establish_job_pool());
    let mut conn = pool
        .get()
        .expect("Failed to get connection trying to load server configuration");

    log::info!("Loading Server Configuration...");
    let mut server_configuration_model: models::ServerConfiguration =
        rpcs::get_server_configuration_model(&mut conn)
            .or_else(|_| {
                log::warn!("Failed to load server configuration, regenerating...");
                rpcs::create_default_server_configuration(&mut conn)
            })
            .expect("Failed to load or regenerate server configuration");
    let server_configuration: protos::ServerConfiguration = server_configuration_model.to_proto();

    let external_cdn_config = server_configuration.external_cdn_config;
    let cdn_grpc = match external_cdn_config {
        None => {
            log::info!("No External CDN configuration found.");
            return;
        }
        Some(ref external_cdn_config) => {
            log::info!(
                "Using external CDN configuration: {:?}",
                &external_cdn_config
            );
            external_cdn_config.cdn_grpc
        }
    };

    if !cdn_grpc {
        log::info!("gRPC CDN support is already disabled.");
        return;
    }

    let mut external_cdn_config = external_cdn_config.unwrap();
    external_cdn_config.cdn_grpc = false;
    server_configuration_model.external_cdn_config = serde_json::to_value(external_cdn_config).ok();
    // server_configuration.external_cdn_config = Some(external_cdn_config);

    diesel::update(schema::server_configurations::table)
        .set(&server_configuration_model)
        .execute(&mut conn)
        .expect("Failed to update server configuration. Bootloops likely.");

    log::info!("Done Disabling gRPC CDN support.");
}
