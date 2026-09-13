#[macro_use]
extern crate diesel;
extern crate async_compression;
extern crate bcrypt;
extern crate bs58;
extern crate diesel_migrations;
extern crate dotenvy;
extern crate env_logger;
extern crate futures;
extern crate itertools;
extern crate log;
extern crate prost_types;
extern crate prost_wkt_types;
extern crate regex;
extern crate ring;
extern crate rocket;
extern crate rocket_async_compression;
extern crate rocket_cache_response;
extern crate serde;
extern crate serde_json;
extern crate tonic_web;
extern crate uuid;
#[macro_use]
extern crate lazy_static;
extern crate awscreds;
// extern crate awsregion;
extern crate bytes;
extern crate ico;
extern crate percent_encoding;
extern crate rand;
extern crate s3;
extern crate tempfile;
extern crate tokio_stream;

pub mod auth;
pub mod db_connection;
pub mod rellm_service;
pub mod logic;
pub mod marshaling;
pub mod minio_connection;
pub mod models;
pub mod protos;
pub mod rpcs;
pub mod schema;
pub mod servers;
pub mod web;
pub mod web_push;

use ::rellm::{env_var, init_crypto, init_service_logging, report_error};
use diesel::*;
use futures::future::join_all;
use marshaling::ToProtoServerConfiguration;
use servers::{
    start_rocket_internal, start_rocket_secure, start_rocket_unsecured, start_tonic_server,
};
use std::sync::Arc;
use tokio::task::JoinHandle;

#[rocket::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|arg| arg == "--version") {
        println!("{}", rpcs::get_service_version()?.version);
        return Ok(());
    }
    let no_internal_server = args.iter().any(|arg| arg == "--no-internal-server");

    init_crypto();
    init_service_logging();
    db_connection::migrate_database();

    log::info!(
        "Starting Rellm...
┏┳ ┏┓ ┳┓ ┓  ┳ ┳┓ ┏┓
 ┃ ┃┃ ┃┃ ┃  ┃ ┃┃ ┣ 
┗┛ ┗┛ ┛┗ ┗┛ ┻ ┛┗ ┗┛
 (Rellm Server)
A Rust HTTP (80/443/8000) and gRPC (27707) server for Rellm services
(providing a \"Twitter-like with events\" experience with no feeds and a
privacy-conscious design), plus an internal-only HTTP mail delivery endpoint
(27705, see deploys/email) used by a Stalwart mail server.

Serves up its React FE by default at \"/\" (configurable) and always at \"/tamagui\";
its Elm FE at \"/elm\" (also configurable to run from \"/\"), and
its Flutter FE at \"/flutter\" (deprecated/experimental and not really suitable to run from \"/\").

Serves up media and accepts Media uploads from users on its HTTP ports from \"/media\".

The gRPC API supports reflection/self-documentation, and is extremely friendly for AI clients.

Prompt your favorite AI (tested with Claude) with something like:

  \"I want to test your ability to use a gRPC client for Rellm, a social networking
    protocol with highly documented gRPC APIs. Use the tool grpcurl.

    You can use `grpcurl -plaintext localhost:27707 list rellm.Rellm` to list the 
    RPCs available for the Rellm service at localhost:27707.

    Take a look at the grpcurl docs for more info - there should be details docs on these APIs.

    When you feel you understand it, give me a list of the usernames for the users on this host.
   \"

And it should be able to understand the API. If you have grpcurl installed, you can ask it
questions about users, etc.

Supported environment variables (and examples):

    DATABASE_URL=postgres://localhost/rellm_dev

    MINIO_ENDPOINT=http://localhost:9000
    MINIO_REGION=
    MINIO_BUCKET=rellm-dev
    MINIO_ACCESS_KEY=ROOTNAME
    MINIO_SECRET_KEY=CHANGEME123

    TLS_CERT_PATH=/path/to/cert.pem

Supported flags:

    --version               Print the server version and exit
    --no-internal-server    Don't start the internal-only mail delivery server (27705) used by
                             a Stalwart mail server (deploys/email) -- irrelevant to most deploys
"
    );

    let pool = Arc::new(db_connection::establish_pool());
    let bucket = Arc::new(
        *minio_connection::get_and_test_bucket()
            .await
            .expect("Failed to connect to MinIO"),
    );

    let tempdir = Arc::new(tempfile::tempdir().map_err(|e| {
        log::error!("Failed to create tempdir: {:?}", e);
        e
    })?);

    // One-time backfill of `Media.sizes[].size_bytes` for rows that predate size tracking (see
    // migration `2026-09-13-000100_restructure_media_sizes`). Spawned, not awaited -- it must not
    // delay the server from actually starting to serve requests -- and naturally idempotent, so
    // it's safe to spawn on every startup (a restart after it completes just finds nothing to do).
    tokio::spawn(logic::run_media_size_backfill(
        pool.as_ref().clone(),
        bucket.clone(),
    ));

    // Ideally, we should be able to restart servers and switch between HTTPS redirects.
    let mut conn = pool
        .get()
        .expect("Failed to get connection trying to load server configuration");
    let mut server_configuration_model: models::ServerConfiguration =
        rpcs::get_server_configuration_model(&mut conn)
            .or_else(|_| {
                log::warn!("Failed to load server configuration, regenerating...");
                rpcs::create_default_server_configuration(&mut conn)
            })
            .expect("Failed to load or regenerate server configuration");
    let server_configuration: protos::ServerConfiguration = server_configuration_model.to_proto();

    log::info!("Loaded server configuration: {:?}", &server_configuration);

    let external_cdn_config = server_configuration.external_cdn_config;
    let cdn_grpc = match external_cdn_config {
        None => {
            log::info!("No external CDN configuration found.");
            false
        }
        Some(ref external_cdn_config) => {
            log::info!(
                "Using external CDN configuration: {:?}",
                &external_cdn_config
            );
            external_cdn_config.cdn_grpc
        }
    };

    let tonic_port: u16 = if cdn_grpc {
        log::info!("Using CDN for gRPC communication. Server will *disable this setting* and terminate if secure gRPC is not properly configured.");
        443
        // 27707
    } else {
        27707
    };

    let tls_configuration_successful =
        start_tonic_server(pool.clone(), bucket.clone(), tonic_port)?;

    if cdn_grpc {
        if !tls_configuration_successful {
            log::error!("Secure gRPC configuration failed. Cannot use CDN for gRPC communication. Reverting server configuration and terminating server.");
            let mut external_cdn_config = external_cdn_config.unwrap();
            external_cdn_config.cdn_grpc = false;
            server_configuration_model.external_cdn_config =
                serde_json::to_value(external_cdn_config).ok();
            // server_configuration.external_cdn_config = Some(external_cdn_config);

            diesel::update(schema::server_configurations::table)
                .set(&server_configuration_model)
                .execute(&mut conn)
                .expect("Failed to update server configuration. Bootloops likely.");

            return Ok(());
        }
        log::info!("Secure gRPC configuration successful. Starting only insecure HTTP servers...");
    }

    let mut rocket_handles: Vec<JoinHandle<()>> = vec![];

    let launch_http_as_redirect =
        // !cdn_grpc && external_cdn_config.is_none() && 
        tls_configuration_successful;

    log::info!(
        "Insecure HTTP port 80 server is in {} mode.",
        if launch_http_as_redirect {
            "redirect-only"
        } else {
            "standard files and media"
        }
    );

    rocket_handles.push(start_rocket_secure(
        pool.clone(),
        bucket.clone(),
        tempdir.clone(),
    ));
    rocket_handles.push(start_rocket_unsecured(
        80,
        pool.clone(),
        bucket.clone(),
        tempdir.clone(),
        launch_http_as_redirect,
    ));
    rocket_handles.push(start_rocket_unsecured(
        8000,
        pool.clone(),
        bucket.clone(),
        tempdir.clone(),
        false,
    ));
    // Internal-only: accepts mail delivery from the Stalwart mail server (deploys/email). Never
    // put this behind the public ingress -- see start_rocket_internal's docs. Skippable via
    // --no-internal-server for deploys (e.g. Homebrew/Linux end-user installs) that have no
    // Stalwart mail server to serve.
    if no_internal_server {
        log::info!("--no-internal-server set: skipping internal-only mail delivery server (27705).");
    } else {
        rocket_handles.push(start_rocket_internal(27705, pool, bucket, tempdir));
    }

    join_all::<_>(rocket_handles).await;

    Ok(())
}
