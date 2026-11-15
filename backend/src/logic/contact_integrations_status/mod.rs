//! Live health report for every SMS and email integration (`GetContactIntegrationsStatus`).
//!
//! Each configured provider is checked by calling its *real* API with the stored credentials (see
//! the per-provider modules for exactly which endpoints and fields), the sending domains' SPF /
//! DKIM / DMARC / MX records are looked up in DNS (see `dns.rs` for what that egresses to), and
//! everything is folded into the `ContactIntegrationsStatus` proto. Properties:
//!
//! * **Concurrent and bounded.** Every provider runs on its own thread (`std::thread::scope`); each
//!   HTTP call times out after ~8s and each provider has a ~20s overall budget, so a slow
//!   provider can't hang the RPC.
//! * **Never panics.** A panicking check becomes an `UNKNOWN` status for that provider.
//! * **No secrets.** Credentials are only ever put into request headers; nothing from the
//!   configs is copied into the response except non-secret identifiers (account SID, from number).
//! * **Honest about uncertainty.** Where a provider doesn't expose something (or the key lacks the
//!   scope), the check says so as `INFO`/`UNKNOWN` rather than claiming success or failure.
//!
//! Everything below the entry points is a pure function of the provider configs plus a
//! [`StatusEnv`] (mock-server base URL, DNS resolver, timeouts), which is how the tests drive it.

use std::sync::Arc;
use std::time::{Duration, SystemTime};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::ToProtoTime;
use crate::protos::*;

pub mod bird;
pub mod dns;
pub mod domain;
pub mod http;
pub mod mailgun;
pub mod postmark;
pub mod report;
pub mod sendgrid;
pub mod stalwart;
pub mod telnyx;
pub mod twilio;

use dns::{DnsResolver, DohResolver};
use domain::{build_domain_statuses, domain_of_address, SendingDomain};
use http::Ctx;
use report::{summarize, worst_level, DomainReport, ProviderReport};

/// The stored (unscrubbed, internal-only) configuration of every provider, plus the order the
/// server would try them in. Built from the database by [`load_provider_configs`].
#[derive(Clone, Debug, Default)]
pub struct ProviderConfigs {
    pub twilio: Option<TwilioConfig>,
    pub bird: Option<BirdConfig>,
    pub telnyx: Option<TelnyxConfig>,
    pub postmark: Option<PostmarkConfig>,
    pub sendgrid: Option<SendgridConfig>,
    pub mailgun: Option<MailgunConfig>,
    pub stalwart: Option<StalwartConfig>,
    pub sms_order: Vec<ContactVerificationApi>,
    pub email_order: Vec<EmailVerificationApi>,
}

/// Everything environmental a status run depends on.
#[derive(Clone)]
pub struct StatusEnv {
    /// If `Some`, every provider API host is replaced by this URL (mock servers in tests).
    pub base_url: Option<String>,
    pub dns: Arc<dyn DnsResolver>,
    /// Overall budget for one provider's calls.
    pub provider_budget: Duration,
    pub tcp_timeout: Duration,
}

impl StatusEnv {
    /// Real providers, real DNS (DNS-over-HTTPS; see `dns.rs`).
    pub fn production() -> StatusEnv {
        StatusEnv {
            base_url: None,
            dns: Arc::new(DohResolver::from_env()),
            provider_budget: http::PROVIDER_BUDGET,
            tcp_timeout: Duration::from_secs(3),
        }
    }
}

/// Reads every provider's stored config.
pub fn load_provider_configs(conn: &mut PgPooledConnection) -> ProviderConfigs {
    let preferred_sms = crate::logic::preferred_verification_apis(conn);
    let mut sms_order = preferred_sms;
    for api in [
        ContactVerificationApi::Telnyx,
        ContactVerificationApi::Bird,
        ContactVerificationApi::Twilio,
    ] {
        if !sms_order.contains(&api) {
            sms_order.push(api);
        }
    }
    let mut email_order: Vec<EmailVerificationApi> = crate::logic::preferred_email_apis(conn);
    for api in [
        EmailVerificationApi::Postmark,
        EmailVerificationApi::Sendgrid,
        EmailVerificationApi::Mailgun,
        EmailVerificationApi::Stalwart,
    ] {
        if !email_order.contains(&api) {
            email_order.push(api);
        }
    }

    ProviderConfigs {
        twilio: crate::logic::server_twilio_config(conn),
        bird: crate::logic::server_bird_config(conn),
        telnyx: crate::logic::server_telnyx_config(conn),
        postmark: crate::logic::server_postmark_config(conn),
        sendgrid: crate::logic::server_sendgrid_config(conn),
        mailgun: crate::logic::server_mailgun_config(conn),
        stalwart: crate::logic::server_stalwart_config(conn),
        sms_order,
        email_order,
    }
}

/// Production entry point: loads the configs and runs every check against the real providers.
pub fn get_contact_integrations_status(conn: &mut PgPooledConnection) -> ContactIntegrationsStatus {
    let configs = load_provider_configs(conn);
    gather_status(&configs, &StatusEnv::production())
}

/// What the status page needs to know about one provider before (and instead of) calling it.
struct Spec {
    provider: &'static str,
    display: &'static str,
    /// Whether the admin switched it on.
    enabled: bool,
    /// Whether any setting is stored at all (so a switched-off provider is still listed).
    stored: bool,
    /// Names of required settings that are empty (only meaningful when `enabled`).
    missing: Vec<&'static str>,
    dashboard_url: String,
    /// `From` domain this provider sends as, if it sends.
    sending_domain: Option<String>,
}

fn blank(s: &str) -> bool {
    s.trim().is_empty()
}

fn any_set(values: &[&str]) -> bool {
    values.iter().any(|v| !blank(v))
}

fn missing_of(pairs: &[(&'static str, &str)]) -> Vec<&'static str> {
    pairs.iter().filter(|(_, v)| blank(v)).map(|(n, _)| *n).collect()
}

fn sms_spec(api: ContactVerificationApi, c: &ProviderConfigs) -> Option<Spec> {
    match api {
        ContactVerificationApi::Twilio => c.twilio.as_ref().map(|t| Spec {
            provider: "twilio",
            display: "Twilio",
            enabled: t.twilio_enabled,
            stored: t.twilio_enabled
                || any_set(&[&t.twilio_account_sid, &t.twilio_api_key_sid, &t.twilio_api_key_secret, &t.twilio_from_number]),
            missing: missing_of(&[
                ("Account SID", &t.twilio_account_sid),
                ("API Key SID", &t.twilio_api_key_sid),
                ("API Key Secret", &t.twilio_api_key_secret),
                ("From number", &t.twilio_from_number),
            ]),
            dashboard_url: twilio::DASHBOARD_URL.to_string(),
            sending_domain: None,
        }),
        ContactVerificationApi::Bird => c.bird.as_ref().map(|b| Spec {
            provider: "bird",
            display: "Bird",
            enabled: b.bird_enabled,
            stored: b.bird_enabled || any_set(&[&b.bird_access_key, &b.bird_from]),
            missing: missing_of(&[("Access key", &b.bird_access_key), ("Originator", &b.bird_from)]),
            dashboard_url: bird::DASHBOARD_URL.to_string(),
            sending_domain: None,
        }),
        ContactVerificationApi::Telnyx => c.telnyx.as_ref().map(|t| Spec {
            provider: "telnyx",
            display: "Telnyx",
            enabled: t.telnyx_enabled,
            stored: t.telnyx_enabled
                || any_set(&[&t.telnyx_api_key, &t.telnyx_from_number, &t.telnyx_messaging_profile_id]),
            missing: missing_of(&[
                ("API key", &t.telnyx_api_key),
                ("From number", &t.telnyx_from_number),
                ("Messaging profile ID", &t.telnyx_messaging_profile_id),
            ]),
            dashboard_url: telnyx::DASHBOARD_URL.to_string(),
            sending_domain: None,
        }),
    }
}

fn email_spec(api: EmailVerificationApi, c: &ProviderConfigs) -> Option<Spec> {
    match api {
        EmailVerificationApi::Postmark => c.postmark.as_ref().map(|p| Spec {
            provider: "postmark",
            display: "Postmark",
            enabled: p.postmark_enabled,
            stored: p.postmark_enabled
                || any_set(&[&p.postmark_server_token, &p.postmark_account_token, &p.postmark_from_address]),
            missing: missing_of(&[
                ("Server API token", &p.postmark_server_token),
                ("From address", &p.postmark_from_address),
            ]),
            dashboard_url: postmark::DASHBOARD_URL.to_string(),
            sending_domain: domain_of_address(&p.postmark_from_address),
        }),
        EmailVerificationApi::Sendgrid => c.sendgrid.as_ref().map(|s| Spec {
            provider: "sendgrid",
            display: "SendGrid",
            enabled: s.sendgrid_enabled,
            stored: s.sendgrid_enabled || any_set(&[&s.sendgrid_api_key, &s.sendgrid_from_address]),
            missing: missing_of(&[("API key", &s.sendgrid_api_key), ("From address", &s.sendgrid_from_address)]),
            dashboard_url: sendgrid::DASHBOARD_URL.to_string(),
            sending_domain: domain_of_address(&s.sendgrid_from_address),
        }),
        EmailVerificationApi::Mailgun => c.mailgun.as_ref().map(|m| Spec {
            provider: "mailgun",
            display: "Mailgun",
            enabled: m.mailgun_enabled,
            stored: m.mailgun_enabled
                || any_set(&[&m.mailgun_api_key, &m.mailgun_domain, &m.mailgun_from_address]),
            missing: missing_of(&[
                ("API key", &m.mailgun_api_key),
                ("Domain", &m.mailgun_domain),
                ("From address", &m.mailgun_from_address),
            ]),
            dashboard_url: mailgun::dashboard_url(&m.mailgun_region).to_string(),
            // Mailgun authenticates (and DNS-verifies) its own sending domain.
            sending_domain: if blank(&m.mailgun_domain) {
                domain_of_address(&m.mailgun_from_address)
            } else {
                Some(m.mailgun_domain.trim().to_ascii_lowercase())
            },
        }),
        EmailVerificationApi::Stalwart => c.stalwart.as_ref().map(|s| {
            let enabled = s.stalwart_receiving_enabled || s.stalwart_sending_enabled;
            let mut missing = vec![];
            if s.stalwart_sending_enabled {
                missing.extend(missing_of(&[
                    ("SMTP host", &s.stalwart_smtp_host),
                    ("From address", &s.stalwart_from_address),
                ]));
            }
            Spec {
                provider: "stalwart",
                display: "Stalwart",
                enabled,
                stored: enabled
                    || any_set(&[&s.stalwart_smtp_host, &s.stalwart_from_address, &s.stalwart_management_url]),
                missing,
                dashboard_url: String::new(),
                sending_domain: if s.stalwart_sending_enabled {
                    domain_of_address(&s.stalwart_from_address)
                } else {
                    None
                },
            }
        }),
    }
}

/// Runs one provider's live check (never called for disabled/unconfigured providers).
fn run_check(provider: &str, configs: &ProviderConfigs, env: &StatusEnv) -> ProviderReport {
    let ctx = Ctx::new(env.base_url.as_deref(), env.provider_budget);
    match provider {
        "twilio" => configs.twilio.as_ref().map(|c| twilio::check(c, &ctx)),
        "bird" => configs.bird.as_ref().map(|c| bird::check(c, &ctx)),
        "telnyx" => configs.telnyx.as_ref().map(|c| telnyx::check(c, &ctx)),
        "postmark" => configs.postmark.as_ref().map(|c| postmark::check(c, &ctx)),
        "sendgrid" => configs.sendgrid.as_ref().map(|c| sendgrid::check(c, &ctx)),
        "mailgun" => configs.mailgun.as_ref().map(|c| mailgun::check(c, &ctx)),
        "stalwart" => configs.stalwart.as_ref().map(|c| stalwart::check(c, &ctx, env.tcp_timeout)),
        _ => None,
    }
    .unwrap_or_default()
}

fn crashed_report() -> ProviderReport {
    let mut r = ProviderReport::default();
    r.unknown("Status check", "The status check failed unexpectedly.");
    r.headline = Some("Couldn't check this provider".to_string());
    r
}

/// Folds a spec plus (if it was run) its report into the proto.
fn provider_status(spec: &Spec, report: Option<ProviderReport>) -> (ProviderStatus, Vec<DomainReport>) {
    let configured = spec.missing.is_empty();
    let dashboard_url = if spec.dashboard_url.is_empty() { None } else { Some(spec.dashboard_url.clone()) };
    let mut status = ProviderStatus {
        provider: spec.provider.to_string(),
        display_name: spec.display.to_string(),
        enabled: spec.enabled,
        configured,
        level: StatusLevel::Disabled as i32,
        summary: "Disabled".to_string(),
        checks: vec![],
        metrics: vec![],
        dashboard_url,
    };
    if !spec.enabled {
        status.summary = if spec.stored { "Configured but switched off".to_string() } else { "Disabled".to_string() };
        return (status, vec![]);
    }
    let Some(report) = report else {
        // Enabled but incomplete: nothing to call.
        status.level = StatusLevel::Error as i32;
        status.summary = format!("Enabled but missing: {}", spec.missing.join(", "));
        status.checks.push(report::make_check(
            StatusLevel::Error,
            "Configuration",
            format!("Missing required settings: {}.", spec.missing.join(", ")),
            Some("Fill in the missing fields on the Contact Integrations tab, or switch the provider off."),
        ));
        return (status, vec![]);
    };
    status.level = worst_level(report.checks.iter().map(|c| c.level)) as i32;
    status.summary = summarize(spec.display, &report);
    status.checks = report.checks;
    status.metrics = report.metrics;
    (status, report.domains)
}

/// Runs the provider checks, then the DNS checks, and assembles the response. Pure aside from
/// the network calls `env` allows.
pub fn gather_status(configs: &ProviderConfigs, env: &StatusEnv) -> ContactIntegrationsStatus {
    let sms_specs: Vec<Spec> = configs.sms_order.iter().filter_map(|a| sms_spec(*a, configs)).filter(|s| s.stored).collect();
    let email_specs: Vec<Spec> = configs.email_order.iter().filter_map(|a| email_spec(*a, configs)).filter(|s| s.stored).collect();

    // Phase 1: every enabled+configured provider concurrently.
    let reports: Vec<Option<ProviderReport>> = std::thread::scope(|scope| {
        let handles: Vec<_> = sms_specs
            .iter()
            .chain(email_specs.iter())
            .map(|spec| {
                if spec.enabled && spec.missing.is_empty() {
                    Some(scope.spawn(move || run_check(spec.provider, configs, env)))
                } else {
                    None
                }
            })
            .collect();
        handles
            .into_iter()
            .map(|h| h.map(|h| h.join().unwrap_or_else(|_| crashed_report())))
            .collect()
    });

    let mut reports = reports.into_iter();
    let mut sms_providers = vec![];
    for spec in &sms_specs {
        sms_providers.push(provider_status(spec, reports.next().flatten()).0);
    }
    let mut email_providers = vec![];
    let mut domain_reports: Vec<DomainReport> = vec![];
    for spec in &email_specs {
        let (status, domains) = provider_status(spec, reports.next().flatten());
        email_providers.push(status);
        domain_reports.extend(domains);
    }

    // Phase 2: DNS-level authentication for each distinct sending domain of an enabled provider.
    let mut domains: Vec<SendingDomain> = vec![];
    for spec in email_specs.iter().filter(|s| s.enabled) {
        let Some(name) = spec.sending_domain.clone() else { continue };
        match domains.iter_mut().find(|d| d.domain == name) {
            Some(existing) => existing.used_by.push(spec.provider.to_string()),
            None => domains.push(SendingDomain { domain: name, used_by: vec![spec.provider.to_string()] }),
        }
    }
    let email_domains = build_domain_statuses(&domains, &domain_reports, env.dns.as_ref());

    ContactIntegrationsStatus {
        checked_at: Some(SystemTime::now().to_proto()),
        sms_providers,
        email_providers,
        email_domains,
    }
}
