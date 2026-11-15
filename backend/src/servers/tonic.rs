use std::{env, sync::Arc};

use crate::rellm_service::RellmService;
use crate::{db_connection::PgPool, env_var};

use crate::report_error;

use crate::protos::rellm_server::RellmServer;

use ::log::{info, warn};
use std::net::SocketAddr;
use tonic::transport::{Certificate, Identity, Server, ServerTlsConfig};
use tonic_web::GrpcWebLayer;
use tower_http::cors::CorsLayer;

/// Copies each request's host (`:authority` for HTTP/2, `Host` for HTTP/1.1 gRPC-Web) into the request's
/// extensions as a [`RequestHost`], which Tonic hands on to the RPC (`request.extensions()`) -- how
/// `GetPosts`/`GetEvents`/`GetServerConfiguration`/... know whether they were addressed to a Rellm Subdomain
/// (see `logic::subdomains`).
#[derive(Clone, Copy, Default)]
pub struct RequestHostLayer;

impl<S> tower::Layer<S> for RequestHostLayer {
    type Service = RequestHostService<S>;
    fn layer(&self, inner: S) -> Self::Service {
        RequestHostService { inner }
    }
}

#[derive(Clone)]
pub struct RequestHostService<S> {
    inner: S,
}

impl<S, B> tower::Service<http::Request<B>> for RequestHostService<S>
where
    S: tower::Service<http::Request<B>>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, mut request: http::Request<B>) -> Self::Future {
        let host = request
            .uri()
            .authority()
            .map(|a| a.as_str().to_string())
            .or_else(|| {
                request
                    .headers()
                    .get(http::header::HOST)
                    .and_then(|h| h.to_str().ok())
                    .map(str::to_string)
            });
        if let Some(host) = host {
            request.extensions_mut().insert(crate::logic::subdomains::RequestHost(host));
        }

        self.inner.call(request)
    }
}

const FILE_DESCRIPTOR_SET: &[u8] = tonic::include_file_descriptor_set!("greeter_descriptor");

pub fn start_tonic_server(
    pool: Arc<PgPool>,
    bucket: Arc<s3::Bucket>,
    port: u16,
) -> Result<bool, Box<dyn std::error::Error>> {
    let rellm = RellmService { pool, bucket };

    let reflection_service = tonic_reflection::server::Builder::configure()
        .register_encoded_file_descriptor_set(FILE_DESCRIPTOR_SET)
        .build_v1()
        .unwrap();

    let (tonic_server, secure_mode) = match get_tls_config() {
        Some(tls) => {
            info!("Configuring TLS...");
            match Server::builder().tls_config(tls) {
                Ok(server) => {
                    info!("TLS successfully configured.");
                    (server, true)
                }
                Err(details) => {
                    info!("Error configuring TLS. Connections are not secure.");
                    report_error(details);
                    (Server::builder(), false)
                }
            }
        }
        _ => {
            warn!("No TLS keys available. Connections are not secure.");
            (Server::builder(), false)
        }
    };

    let tonic_router = tonic_server
        .accept_http1(true)
        .layer(RequestHostLayer)
        .layer(CorsLayer::permissive())
        .layer(GrpcWebLayer::new())
        // .layer(CorsLayer::permissive())
        .add_service(RellmServer::new(rellm))
        .add_service(reflection_service);

    tokio::spawn(async move {
        let tonic_addr = SocketAddr::from(([0, 0, 0, 0], port));
        info!("Starting Tonic server on {}", tonic_addr);
        match tonic_router.serve(tonic_addr).await {
            Ok(_) => {
                ::log::warn!("Tonic server stopped unexpectedly. Sending a panic! to stop the Rellm server...");
                panic!("Tonic server stopped on {}", tonic_addr)
            }
            Err(e) => {
                ::log::warn!("Unable to start Tonic server on port {}", port);
                report_error(e);
            }
        };
        ()
    });

    Ok(secure_mode)
}

fn get_tls_config() -> Option<ServerTlsConfig> {
    let cert = env_var("TLS_CERT");
    let key = env_var("TLS_KEY");
    let ca_cert = env_var("CA_CERT");

    match (cert, key, ca_cert) {
        (Some(cert), Some(key), Some(ca_cert)) => {
            info!("Configuring TLS with custom CA...");
            Some(
                ServerTlsConfig::new()
                    .identity(Identity::from_pem(cert, key))
                    .client_ca_root(Certificate::from_pem(ca_cert)),
            )
        }
        (Some(cert), Some(key), None) => {
            info!("Configuring TLS with official CAs...");
            Some(ServerTlsConfig::new().identity(Identity::from_pem(cert, key)))
        }
        _ => None,
    }
}
