use std::env;

#[macro_use]
extern crate diesel;
extern crate bcrypt;
extern crate bs58;
extern crate diesel_migrations;
extern crate dotenvy;
extern crate futures;
extern crate itertools;
extern crate ring;
extern crate serde;
extern crate serde_json;
extern crate tonic_web;
extern crate uuid;
#[macro_use]
extern crate lazy_static;
extern crate awscreds;
// extern crate awsregion;
extern crate bytes;
extern crate env_logger;
extern crate http;
extern crate log;
extern crate percent_encoding;
extern crate s3;
extern crate tempfile;
extern crate tokio_stream;

pub mod auth;
pub mod db_connection;
pub mod rellm_service;
pub mod logic;
pub mod marshaling;
pub mod object_storage_connection;
pub mod models;
pub mod protos;
pub mod rpcs;
pub mod schema;
pub mod servers;
pub mod web;
pub mod web_push;

pub use marshaling::*;

#[cfg(test)]
mod tests;

pub fn report_error<E: 'static>(err: E)
where
    E: std::error::Error,
    E: Send + Sync,
{
    let mut stack = String::from("\n");
    if let Some(cause) = err.source() {
        for (i, e) in std::iter::successors(Some(cause), |e| e.source()).enumerate() {
            stack.push_str(&format!("   {}: {}\n", i, e));
        }
    }
    log::error!("[ERROR] {}\nCaused by: {}", err, stack);
}

pub fn env_var(name: &str) -> Option<String> {
    env::var(name).ok().filter(|s| !s.is_empty())
}

/// Idempotent: reqwest and tonic both require a process-wide rustls `CryptoProvider` to be
/// installed (they're built with `rustls-no-provider`/`tls-ring` rather than a TLS backend that
/// installs one for us), so every entry point -- `main`s and the test harness alike -- must be
/// able to call this safely, including more than once from the same process.
pub fn init_crypto() {
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        rustls::crypto::ring::default_provider()
            .install_default()
            .expect("Failed to install rustls crypto provider");
    });
}

/// Designed to be called from the main function of a service.
pub fn init_service_logging() {
    env_logger::builder()
        .target(env_logger::Target::Stdout)
        .filter_level(log::LevelFilter::Info)
        .parse_env("RUST_LOG")
        .init();
}

/// Designed to be called from the main function of a bin command.
/// Writes to STDOUT without timestamps.
pub fn init_bin_logging() {
    env_logger::builder()
        .target(env_logger::Target::Stdout)
        .filter_level(log::LevelFilter::Info)
        .format_level(false)
        .format_target(false)
        .format_module_path(false)
        .format_indent(None)
        .format_timestamp(None)
        .parse_env("RUST_LOG")
        .init();
}
