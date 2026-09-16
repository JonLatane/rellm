use std::{fs, sync::Arc};

use crate::{db_connection::PgPool, env_var};
use crate::{report_error, web};

use ::log::{info, warn};
use rocket::*;
use rocket_async_compression::Compression;
use tokio::task::JoinHandle;

/// Starts a secure Rocket instance on port 443 in a separate thread.
pub fn start_rocket_secure(
    pool: Arc<PgPool>,
    bucket: Arc<s3::Bucket>,
    tempdir: Arc<tempfile::TempDir>,
) -> JoinHandle<()> {
    let cert = env_var("TLS_CERT");
    let key = env_var("TLS_KEY");

    let server_build = match (cert, key) {
        (Some(cert), Some(key)) => {
            info!("Configuring Rocket TLS...");

            fs::write(".tls.crt", cert).expect("Unable to write TLS certificate");
            fs::write(".tls.key", key).expect("Unable to write TLS key");
            let figment = rocket::Config::figment()
                .merge(("port", 443))
                .merge(("address", "0.0.0.0"))
                .merge(("tls.certs", ".tls.crt"))
                .merge(("tls.key", ".tls.key"));
            Some(create_rocket(figment, pool, bucket, tempdir))
        }
        _ => None,
    };

    rocket::tokio::spawn(async {
        match server_build {
            None => (),
            Some(rocket) => match rocket.launch().await {
                Ok(_) => (),
                Err(e) => {
                    warn!("Unable to start secure Rocket server on port 443");
                    report_error(e);
                }
            },
        };
        ()
    })
}

pub fn start_rocket_unsecured(
    port: i32,
    pool: Arc<PgPool>,
    bucket: Arc<s3::Bucket>,
    tempdir: Arc<tempfile::TempDir>,

    as_redirect: bool,
) -> JoinHandle<()> {
    let figment = rocket::Config::figment()
        .merge(("port", port))
        .merge(("address", "0.0.0.0"));
    let server_build = if as_redirect {
        create_rocket_https_redirect(figment, pool, bucket, tempdir)
    } else {
        create_rocket(figment, pool, bucket, tempdir)
    };

    rocket::tokio::spawn(async move {
        match server_build.launch().await {
            Ok(_) => (),
            Err(e) => {
                warn!("Unable to start Rocket server on port {}", port);
                report_error(e);
            }
        };
        ()
    })
}

/// Starts the internal-only Rocket instance used by the Stalwart mail server (see
/// `deploys/email`) to deliver accepted inbound mail -- see `web::email::create_email_message`.
/// Deliberately separate from `create_rocket`'s public 80/443/8000 instances: this port has no
/// authentication of its own (it trusts whatever calls it completely), so it must stay off the
/// public ingress and be restricted at the network layer (e.g. a K8s NetworkPolicy) to Stalwart's
/// pod alone -- see `deploys/email/README.md`.
pub fn start_rocket_internal(
    port: i32,
    pool: Arc<PgPool>,
    bucket: Arc<s3::Bucket>,
    tempdir: Arc<tempfile::TempDir>,
) -> JoinHandle<()> {
    let figment = rocket::Config::figment()
        .merge(("port", port))
        .merge(("address", "0.0.0.0"));
    let server = rocket::custom(figment)
        .manage(web::RocketState {
            pool,
            bucket,
            tempdir,
        })
        .mount("/", (*web::EMAIL_ENDPOINTS).clone());

    rocket::tokio::spawn(async move {
        match server.launch().await {
            Ok(_) => (),
            Err(e) => {
                warn!("Unable to start internal Rocket server on port {}", port);
                report_error(e);
            }
        };
        ()
    })
}

fn create_rocket<T: rocket::figment::Provider>(
    figment: T,
    pool: Arc<PgPool>,
    bucket: Arc<s3::Bucket>,
    tempdir: Arc<tempfile::TempDir>,
) -> rocket::Rocket<rocket::Build> {
    let mut routes = routes![web::main_index::main_index,];
    routes.append(&mut (*web::EXTERNAL_CDN_PAGES).clone());
    routes.append(&mut (*web::ICAL_PAGES).clone());
    routes.append(&mut (*web::RSS_PAGES).clone());
    routes.append(&mut (*web::ATOM_PAGES).clone());
    routes.append(&mut (*web::INFORMATIONAL_PAGES).clone());
    routes.append(&mut (*web::SEO_PAGES).clone());
    routes.append(&mut (*web::MEDIA_ENDPOINTS).clone());
    routes.append(&mut (*web::STRIPE_WEBHOOK_ENDPOINTS).clone());
    routes.append(&mut (*web::FLUTTER_PAGES).clone());
    routes.append(&mut (*web::ELM_PAGES).clone());
    routes.append(&mut (*web::TAMAGUI_PAGES).clone());
    routes.append(&mut (*web::SPA_PAGES).clone());
    let server = rocket::custom(figment)
        .attach(web::cors::CORS)
        .manage(web::RocketState {
            pool,
            bucket,
            tempdir,
        })
        .mount("/", routes)
        // SPA_PAGES (post/event/group/etc. pages -- see spa_pages.rs) are
        // shared by both frontends and reachable under "/tamagui" and "/elm"
        // prefixes too, so e.g. "/post/x", "/tamagui/post/x", and
        // "/elm/post/x" all resolve identically. Each mount is the same
        // route list; the handlers themselves inspect the request's literal
        // prefix (see `spa_prefix`) to decide which app to render.
        .mount("/tamagui", (*web::SPA_PAGES).clone())
        .mount("/elm", (*web::SPA_PAGES).clone())
        .register("/", catchers![web::catchers::not_found]);
    // Delete the "false &&" to disable compression in debug mode. Useful for debugging.
    if false && cfg!(debug_assertions) {
        server
    } else {
        // Cache all compressed responses, with some exclusions
        // server.attach(CachedCompression {
        //     cached_path_prefixes: vec!["".to_string()],
        //     excluded_path_prefixes: CachedCompression::static_paths(vec![
        //         "/media",
        //         "media",
        //         "/info_shield",
        //         "info_shield",
        //     ]),
        //     level: Some(async_compression::Level::Fastest),
        //     ..Default::default()
        // })
        server.attach(Compression::with_level(async_compression::Level::Fastest))
    }
}

fn create_rocket_https_redirect<T: rocket::figment::Provider>(
    figment: T,
    pool: Arc<PgPool>,
    bucket: Arc<s3::Bucket>,
    tempdir: Arc<tempfile::TempDir>,
) -> rocket::Rocket<rocket::Build> {
    rocket::custom(figment)
        .attach(web::cors::CORS)
        .manage(web::RocketState {
            pool,
            bucket,
            tempdir,
        })
        .mount("/", routes![web::redirect_to_secure,])
        .register("/", catchers![web::catchers::not_found])
}

// fn create_tonic_router(pool: Arc<PgPool>) -> (tonic::transport::server::Router, bool) {
// }
