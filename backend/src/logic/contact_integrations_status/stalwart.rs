//! Live status of the Stalwart (self-hosted mail server) integration.
//!
//! * Sending: a TCP connect (3s timeout) to the SMTP submission `host:port`. This proves the
//!   listener is reachable, not that SMTP AUTH succeeds (that would mean sending real mail).
//! * Receiving: nothing to probe from here (Stalwart calls *us*), so just reported as INFO.
//! * Management API (only if `stalwart_management_url` is set, read-only calls, Bearer token):
//!   - `GET /healthz/ready` (unauthenticated; documented) -- readiness.
//!   - `GET /api/account` (documented for current Stalwart) -- token validity + edition.
//!   - Best-effort, version-dependent *legacy REST* calls: `GET /api/queue/messages?limit=1`
//!     (`data.total`), `GET /api/reports/dmarc?limit=1` (`data.total`),
//!     `GET /api/dns/records/{domain}` (`data[]` of `{type,name,content}`, used to learn which DKIM
//!     selectors are published). Newer Stalwart releases moved most management to JMAP and don't
//!     document these REST routes, so on a 404 these are silently skipped and one INFO check says the
//!     numbers are unavailable.

use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use serde_json::Value;

use crate::protos::StalwartConfig;

use super::domain::domain_of_address;
use super::http::{encode_segment, get_json, get, i64_of, str_of, Auth, Ctx, Fail};
use super::report::{DomainReport, ProviderReport};

/// `host:port` reachable within `timeout`?
pub fn tcp_reachable(host: &str, port: u16, timeout: Duration) -> Result<(), String> {
    let addrs = (host, port)
        .to_socket_addrs()
        .map_err(|_| "the host name didn't resolve".to_string())?;
    let mut last = "no addresses".to_string();
    for addr in addrs {
        match TcpStream::connect_timeout(&addr, timeout) {
            Ok(_) => return Ok(()),
            Err(e) => {
                last = if e.kind() == std::io::ErrorKind::TimedOut {
                    "timed out".to_string()
                } else {
                    "connection refused or unreachable".to_string()
                }
            }
        }
    }
    Err(last)
}

pub fn check(config: &StalwartConfig, ctx: &Ctx, tcp_timeout: Duration) -> ProviderReport {
    let mut report = ProviderReport::default();

    // Sending.
    let mut dr: Option<DomainReport> = None;
    if config.stalwart_sending_enabled {
        let host = config.stalwart_smtp_host.trim();
        let port = if config.stalwart_smtp_port <= 0 { 587 } else { config.stalwart_smtp_port as u16 };
        if host.is_empty() || config.stalwart_from_address.trim().is_empty() {
            report.error(
                "Sending configuration",
                "Sending is on, but the SMTP host or From address is missing.",
                "Fill in the SMTP host and From address, or turn sending off.",
            );
        } else {
            match tcp_reachable(host, port, tcp_timeout) {
                Ok(()) => report.ok("SMTP submission", format!("Connected to {host}:{port}.")),
                Err(why) => report.error(
                    "SMTP submission",
                    format!("Couldn't connect to {host}:{port} ({why})."),
                    "Check that Stalwart is running and that this server can reach that host and port.",
                ),
            }
        }
        if let Some(domain) = domain_of_address(&config.stalwart_from_address) {
            dr = Some(DomainReport { domain, provider: "stalwart".to_string(), ..Default::default() });
        }
    }

    // Receiving.
    if config.stalwart_receiving_enabled {
        report.info(
            "Receiving",
            "Receiving is on: Stalwart hands incoming email to this server. That can't be tested from here.",
        );
    }

    // Management API.
    let base = config.stalwart_management_url.trim().trim_end_matches('/');
    if !base.is_empty() {
        let base = ctx.base_url.clone().unwrap_or_else(|| base.to_string());
        management(config, ctx, &base, &mut report, dr.as_mut());
    } else {
        report.info(
            "Management API",
            "No management URL is set, so queue and DNS details aren't shown.",
        );
    }

    if let Some(dr) = dr {
        report.domains.push(dr);
    }
    report
}

fn management(config: &StalwartConfig, ctx: &Ctx, base: &str, report: &mut ProviderReport, dr: Option<&mut DomainReport>) {
    const NAME: &str = "Management API";
    let token = config.stalwart_management_token.trim();
    let auth = if token.is_empty() { Auth::None } else { Auth::Bearer(token) };

    // Readiness (no auth).
    match get(ctx, &format!("{base}/healthz/ready"), Auth::None, &[], &[]) {
        Ok(r) if (200..300).contains(&r.status) => report.ok("Server health", "Stalwart reports ready."),
        Ok(r) if r.status == 503 => report.error(
            "Server health",
            "Stalwart is running but not ready (its data store is unavailable).",
            "Check Stalwart's logs and its storage backend.",
        ),
        Ok(_) => {}
        Err(e) => {
            report.error(
                NAME,
                format!("Couldn't reach the management URL ({e})."),
                "Check the management URL and that this server can reach it.",
            );
            return;
        }
    }

    // Token validity.
    let mut token_rejected = false;
    match get_json(ctx, &format!("{base}/api/account"), auth, &[], &[]) {
        Ok(body) => {
            report.ok(NAME, "The management token is accepted.");
            let edition = str_of(&body, "edition");
            if !edition.is_empty() {
                report.metric("Edition", edition, None);
            }
        }
        Err(Fail::Unauthorized) => {
            token_rejected = true;
            report.error(
                NAME,
                "Stalwart didn't accept the management token.",
                "Create an API key in Stalwart and paste its token here.",
            );
        }
        Err(Fail::Forbidden(_)) => report.warn(NAME, "The management token works but isn't allowed to read this.", "Give the API key read access in Stalwart."),
        Err(_) => report.info(NAME, "Stalwart answered, but this version doesn't offer the account check."),
    }
    if token_rejected {
        return;
    }

    // Best-effort legacy REST statistics.
    let mut got_any = false;
    if let Ok(body) = get_json(ctx, &format!("{base}/api/queue/messages"), auth, &[], &[("limit", "1".to_string())]) {
        if let Some(total) = body.pointer("/data/total") {
            report.metric("Messages queued", i64_of(total).to_string(), Some("outbound queue"));
            got_any = true;
        }
    }
    if let Ok(body) = get_json(ctx, &format!("{base}/api/reports/dmarc"), auth, &[], &[("limit", "1".to_string())]) {
        if let Some(total) = body.pointer("/data/total") {
            report.metric("DMARC reports received", i64_of(total).to_string(), Some("aggregate reports"));
            got_any = true;
        }
    }
    if let Some(dr) = dr {
        let url = format!("{base}/api/dns/records/{}", encode_segment(&dr.domain));
        if let Ok(body) = get_json(ctx, &url, auth, &[], &[]) {
            for record in body.get("data").and_then(Value::as_array).into_iter().flatten() {
                let name = str_of(record, "name").trim_end_matches('.').to_ascii_lowercase();
                if name.contains("._domainkey.") {
                    dr.dkim_hosts.push(name);
                    got_any = true;
                }
            }
        }
    }
    if !got_any {
        report.info(
            "Queue and reports",
            "Queue size and DMARC report counts aren't available from this Stalwart version.",
        );
    }
}
