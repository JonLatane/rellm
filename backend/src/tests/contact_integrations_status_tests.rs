//! Specs for `GetContactIntegrationsStatus`: the admin-only gate, and the live provider checks run
//! against `factories::serve_capturing` mock servers (every provider host is overridden by the
//! mock's URL via `StatusEnv::base_url`) with a fake DNS resolver instead of DNS-over-HTTPS.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use diesel::prelude::*;
use serde_json::json;
use tonic::Code;

use crate::logic::contact_integrations_status::dns::{
    DnsAnswer, DnsLookup, DnsResolver, RecordType, TYPE_MX, TYPE_TXT,
};
use crate::logic::contact_integrations_status::StatusEnv;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_contact_integrations_status_with;
use crate::tests::factories::*;

struct FakeDns {
    txt: HashMap<String, Vec<String>>,
}

impl FakeDns {
    fn new(entries: &[(&str, &str)]) -> Arc<FakeDns> {
        let mut txt: HashMap<String, Vec<String>> = HashMap::new();
        for (name, value) in entries {
            txt.entry(name.to_string()).or_default().push(value.to_string());
        }
        Arc::new(FakeDns { txt })
    }
}

impl DnsResolver for FakeDns {
    fn lookup(&self, name: &str, record_type: RecordType) -> DnsLookup {
        let rtype = if record_type == RecordType::Mx { TYPE_MX } else { TYPE_TXT };
        match (record_type, self.txt.get(name)) {
            (RecordType::Txt, Some(v)) => {
                DnsLookup::Found(v.iter().map(|d| DnsAnswer { rtype, data: d.clone() }).collect())
            }
            _ => DnsLookup::NotFound,
        }
    }
}

fn env(base_url: &str, dns: Arc<FakeDns>) -> StatusEnv {
    StatusEnv {
        base_url: Some(base_url.to_string()),
        dns,
        provider_budget: Duration::from_secs(10),
        tcp_timeout: Duration::from_millis(500),
    }
}

fn admin(conn: &mut crate::db_connection::PgPooledConnection, name: &str) -> models::User {
    let user = create_user(conn, name);
    grant_permissions(conn, &user, vec![Permission::Admin])
}

/// Inserts a server configuration with the given providers.
#[allow(clippy::too_many_arguments)]
fn configure(
    conn: &mut crate::db_connection::PgPooledConnection,
    twilio: Option<TwilioConfig>,
    telnyx: Option<TelnyxConfig>,
    email: models::EmailProvidersJson,
    stalwart: Option<StalwartConfig>,
) {
    let mut config = models::default_server_configuration();
    config.twilio_config = twilio.map(|c| serde_json::to_value(c).unwrap());
    config.telnyx_config = telnyx.map(|c| serde_json::to_value(c).unwrap());
    config.stalwart_config = stalwart.map(|c| serde_json::to_value(c).unwrap());
    config.email_providers_config = Some(serde_json::to_value(email).unwrap());
    diesel::insert_into(crate::schema::server_configurations::table)
        .values(&config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

fn twilio(enabled: bool) -> TwilioConfig {
    TwilioConfig {
        twilio_enabled: enabled,
        twilio_account_sid: "AC_test_account".to_string(),
        twilio_api_key_sid: "SK_test_key".to_string(),
        twilio_api_key_secret: "super-secret-twilio-value".to_string(),
        twilio_from_number: "+15005550006".to_string(),
        ..Default::default()
    }
}

fn postmark(enabled: bool, account_token: &str) -> PostmarkConfig {
    PostmarkConfig {
        postmark_enabled: enabled,
        postmark_server_token: "super-secret-postmark-server".to_string(),
        postmark_account_token: account_token.to_string(),
        postmark_from_address: "noreply@example.com".to_string(),
        ..Default::default()
    }
}

fn email_only(postmark: Option<PostmarkConfig>, sendgrid: Option<SendgridConfig>) -> models::EmailProvidersJson {
    models::EmailProvidersJson {
        postmark_config: postmark,
        sendgrid_config: sendgrid,
        ..Default::default()
    }
}

fn request_line(request: &str) -> String {
    request.lines().next().unwrap_or("").to_string()
}

fn check<'a>(provider: &'a ProviderStatus, name: &str) -> &'a StatusCheck {
    provider
        .checks
        .iter()
        .find(|c| c.name == name)
        .unwrap_or_else(|| panic!("no check named {name}: {:?}", provider.checks))
}

/// Mock Twilio: a healthy full account with one SMS-capable number and a few messages.
fn twilio_mock(account_type: &'static str) -> (String, std::sync::Arc<std::sync::Mutex<Vec<String>>>) {
    serve_capturing(move |request, _| {
        let line = request_line(request);
        if line.contains("/Balance.json") {
            ("HTTP/1.1 200 OK", json!({"balance": "12.34", "currency": "USD"}))
        } else if line.contains("/IncomingPhoneNumbers.json") {
            (
                "HTTP/1.1 200 OK",
                json!({"incoming_phone_numbers": [{"sid": "PN1", "phone_number": "+15005550006", "capabilities": {"sms": true}}]}),
            )
        } else if line.contains("/Messages.json") {
            (
                "HTTP/1.1 200 OK",
                json!({"messages": [
                    {"direction": "outbound-api", "status": "delivered"},
                    {"direction": "outbound-api", "status": "delivered"},
                    {"direction": "outbound-api", "status": "failed", "error_code": 30034}
                ], "next_page_uri": null}),
            )
        } else if line.contains("/v1/Services") {
            ("HTTP/1.1 200 OK", json!({"services": []}))
        } else if line.contains("/Accounts/") {
            (
                "HTTP/1.1 200 OK",
                json!({"status": "active", "type": account_type, "friendly_name": "Test Account"}),
            )
        } else {
            ("HTTP/1.1 404 Not Found", json!({}))
        }
    })
}

mod access {
    use super::*;

    #[test]
    fn non_admin_gets_permission_denied() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, Some(twilio(true)), None, Default::default(), None);
            let user = create_user(conn, "cis_non_admin");
            let result = get_contact_integrations_status_with(&user, conn, &env("http://127.0.0.1:1", FakeDns::new(&[])));
            // `validate_permission` is this codebase's permission gate; it reports a missing
            // permission as `InvalidArgument("permission_<NAME>_required")`.
            let err = result.unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "permission_ADMIN_required");
            Ok(())
        });
    }
}

mod sms {
    use super::*;

    #[test]
    fn healthy_twilio_reports_checks_metrics_and_never_leaks_secrets() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, Some(twilio(true)), None, Default::default(), None);
            let user = admin(conn, "cis_twilio_ok");
            let (url, captured) = twilio_mock("Full");

            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();

            assert!(status.checked_at.is_some());
            assert_eq!(status.sms_providers.len(), 1);
            assert!(status.email_providers.is_empty());
            let twilio = &status.sms_providers[0];
            assert_eq!(twilio.provider, "twilio");
            assert_eq!(twilio.display_name, "Twilio");
            assert!(twilio.enabled && twilio.configured);
            assert_eq!(twilio.dashboard_url.as_deref(), Some("https://console.twilio.com/"));
            assert_eq!(check(twilio, "API credentials").level, StatusLevel::Ok as i32);
            assert_eq!(check(twilio, "Sender number").level, StatusLevel::Ok as i32);
            assert_eq!(check(twilio, "Account balance").level, StatusLevel::Ok as i32);
            assert!(twilio.metrics.iter().any(|m| m.label == "Balance" && m.value == "12.34 USD"));
            // A 10DLC long code with no Messaging Service/campaign is a warning, not an error.
            assert_eq!(check(twilio, "Carrier registration").level, StatusLevel::Warning as i32);
            assert_eq!(twilio.level, StatusLevel::Warning as i32);
            assert!(twilio.summary.starts_with("Ready to send - "), "{}", twilio.summary);

            // The credentials actually used were the API Key pair, and the secret never comes back.
            let calls = captured.lock().unwrap();
            assert!(!calls.is_empty());
            assert!(calls.iter().all(|r| r.to_lowercase().contains("authorization: basic")));
            let rendered = format!("{status:?}");
            assert!(!rendered.contains("super-secret-twilio-value"));
            assert!(!rendered.contains("SK_test_key"));
            Ok(())
        });
    }

    #[test]
    fn twilio_trial_account_is_a_warning() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, Some(twilio(true)), None, Default::default(), None);
            let user = admin(conn, "cis_twilio_trial");
            let (url, _) = twilio_mock("Trial");
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let twilio = &status.sms_providers[0];
            let plan = check(twilio, "Account plan");
            assert_eq!(plan.level, StatusLevel::Warning as i32);
            assert!(plan.fix_hint.is_some());
            Ok(())
        });
    }

    #[test]
    fn rejected_twilio_credentials_are_an_error_with_a_clear_summary() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, Some(twilio(true)), None, Default::default(), None);
            let user = admin(conn, "cis_twilio_401");
            let (url, captured) = serve_capturing(|_, _| ("HTTP/1.1 401 Unauthorized", json!({"message": "Authenticate"})));
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let twilio = &status.sms_providers[0];
            assert_eq!(twilio.level, StatusLevel::Error as i32);
            assert_eq!(twilio.summary, "Credentials rejected by Twilio");
            assert_eq!(check(twilio, "API credentials").level, StatusLevel::Error as i32);
            // It stopped after the first rejected call rather than hammering Twilio.
            assert_eq!(captured.lock().unwrap().len(), 1);
            Ok(())
        });
    }

    #[test]
    fn unreachable_provider_is_unknown_not_error() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, Some(twilio(true)), None, Default::default(), None);
            let user = admin(conn, "cis_twilio_down");
            // Nothing listens on port 1.
            let status = get_contact_integrations_status_with(&user, conn, &env("http://127.0.0.1:1", FakeDns::new(&[]))).unwrap();
            let twilio = &status.sms_providers[0];
            assert_eq!(twilio.level, StatusLevel::Unknown as i32);
            assert_eq!(twilio.summary, "Couldn't reach Twilio");
            Ok(())
        });
    }

    #[test]
    fn disabled_provider_with_stored_config_is_listed_but_never_called() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, Some(twilio(false)), None, Default::default(), None);
            let user = admin(conn, "cis_twilio_off");
            let (url, captured) = serve_capturing(|_, _| ("HTTP/1.1 200 OK", json!({})));
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            assert_eq!(status.sms_providers.len(), 1);
            let twilio = &status.sms_providers[0];
            assert_eq!(twilio.level, StatusLevel::Disabled as i32);
            assert!(!twilio.enabled);
            assert!(captured.lock().unwrap().is_empty());
            Ok(())
        });
    }

    #[test]
    fn enabled_but_incomplete_provider_is_an_error_naming_what_is_missing() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let mut incomplete = twilio(true);
            incomplete.twilio_api_key_secret = String::new();
            configure(conn, Some(incomplete), None, Default::default(), None);
            let user = admin(conn, "cis_twilio_incomplete");
            let (url, captured) = serve_capturing(|_, _| ("HTTP/1.1 200 OK", json!({})));
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let twilio = &status.sms_providers[0];
            assert_eq!(twilio.level, StatusLevel::Error as i32);
            assert!(!twilio.configured);
            assert!(twilio.summary.contains("API Key Secret"), "{}", twilio.summary);
            assert!(captured.lock().unwrap().is_empty());
            Ok(())
        });
    }

    #[test]
    fn telnyx_number_on_a_different_messaging_profile_is_an_error() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(
                conn,
                None,
                Some(TelnyxConfig {
                    telnyx_enabled: true,
                    telnyx_api_key: "KEY_secret".to_string(),
                    telnyx_from_number: "+18885550100".to_string(),
                    telnyx_messaging_profile_id: "profile-configured".to_string(),
                    ..Default::default()
                }),
                Default::default(),
                None,
            );
            let user = admin(conn, "cis_telnyx");
            let (url, _) = serve_capturing(|request, _| {
                let line = request_line(request);
                if line.contains("/v2/balance") {
                    ("HTTP/1.1 200 OK", json!({"data": {"balance": "20.00", "available_credit": "20.00", "currency": "USD"}}))
                } else if line.contains("/v2/phone_numbers") {
                    (
                        "HTTP/1.1 200 OK",
                        json!({"data": [{"id": "n1", "phone_number": "+18885550100", "status": "active", "messaging_profile_id": "profile-other"}]}),
                    )
                } else if line.contains("/v2/messaging_profiles/") {
                    ("HTTP/1.1 200 OK", json!({"data": {"name": "Main", "enabled": true, "whitelisted_destinations": ["US"]}}))
                } else if line.contains("/verification/requests") {
                    ("HTTP/1.1 200 OK", json!({"records": [{"verificationStatus": "Verified"}], "total_records": 1}))
                } else {
                    ("HTTP/1.1 404 Not Found", json!({}))
                }
            });
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let telnyx = &status.sms_providers[0];
            assert_eq!(telnyx.provider, "telnyx");
            assert_eq!(check(telnyx, "API credentials").level, StatusLevel::Ok as i32);
            assert_eq!(check(telnyx, "Messaging profile assignment").level, StatusLevel::Error as i32);
            assert_eq!(check(telnyx, "Carrier registration").level, StatusLevel::Ok as i32);
            assert_eq!(telnyx.level, StatusLevel::Error as i32);
            assert!(telnyx.summary.starts_with("Not ready to send"), "{}", telnyx.summary);
            Ok(())
        });
    }
}

mod email {
    use super::*;

    fn postmark_mock(dkim_verified: bool) -> (String, std::sync::Arc<std::sync::Mutex<Vec<String>>>) {
        serve_capturing(move |request, _| {
            let line = request_line(request);
            if line.contains("GET /server ") {
                ("HTTP/1.1 200 OK", json!({"Name": "My Server", "DeliveryType": "Live"}))
            } else if line.contains("/stats/outbound") {
                (
                    "HTTP/1.1 200 OK",
                    json!({"Sent": 200, "Bounced": 2, "BounceRate": 1.0, "SpamComplaints": 0, "SpamComplaintsRate": 0.0}),
                )
            } else if line.contains("GET /domains/") {
                (
                    "HTTP/1.1 200 OK",
                    json!({"ID": 7, "Name": "example.com", "DKIMVerified": dkim_verified, "WeakDKIM": false,
                           "DKIMHost": "20240101pm._domainkey.example.com", "DKIMPendingHost": "",
                           "ReturnPathDomain": "pm-bounces.example.com", "ReturnPathDomainVerified": true}),
                )
            } else if line.contains("GET /domains") {
                ("HTTP/1.1 200 OK", json!({"TotalCount": 1, "Domains": [{"ID": 7, "Name": "example.com", "DKIMVerified": dkim_verified}]}))
            } else {
                ("HTTP/1.1 404 Not Found", json!({}))
            }
        })
    }

    #[test]
    fn healthy_postmark_with_domain_authentication() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, None, None, email_only(Some(postmark(true, "account-secret")), None), None);
            let user = admin(conn, "cis_postmark_ok");
            let (url, captured) = postmark_mock(true);
            let dns = FakeDns::new(&[
                ("example.com", "v=spf1 include:spf.mtasv.net ~all"),
                ("_dmarc.example.com", "v=DMARC1; p=reject; rua=mailto:dmarc@example.com"),
                ("20240101pm._domainkey.example.com", "k=rsa; p=abc"),
            ]);
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, dns)).unwrap();

            assert!(status.sms_providers.is_empty());
            assert_eq!(status.email_providers.len(), 1);
            let pm = &status.email_providers[0];
            assert_eq!(pm.provider, "postmark");
            assert_eq!(check(pm, "API credentials").level, StatusLevel::Ok as i32);
            assert_eq!(check(pm, "Recent delivery").level, StatusLevel::Ok as i32);
            assert_eq!(pm.level, StatusLevel::Ok as i32, "{:?}", pm.checks);
            assert_eq!(pm.summary, "Ready to send");
            assert!(pm.metrics.iter().any(|m| m.label == "Emails sent" && m.value == "200"));

            // Server vs Account token headers were each used and neither leaks back.
            let calls = captured.lock().unwrap().join("\n").to_lowercase();
            assert!(calls.contains("x-postmark-server-token: super-secret-postmark-server"));
            assert!(calls.contains("x-postmark-account-token: account-secret"));
            let rendered = format!("{status:?}");
            assert!(!rendered.contains("super-secret-postmark-server"));
            assert!(!rendered.contains("account-secret"));

            // Domain authentication: DNS + the provider-reported DKIM state, fully parsed DMARC.
            assert_eq!(status.email_domains.len(), 1);
            let domain = &status.email_domains[0];
            assert_eq!(domain.domain, "example.com");
            assert_eq!(domain.used_by, vec!["postmark".to_string()]);
            let dmarc = domain.dmarc.as_ref().unwrap();
            assert!(dmarc.record_found);
            assert_eq!(dmarc.policy, "reject");
            assert_eq!(dmarc.aggregate_report_uris, vec!["mailto:dmarc@example.com".to_string()]);
            assert_eq!(domain.level, StatusLevel::Ok as i32, "{:?}", domain.checks);
            assert!(domain.checks.iter().any(|c| c.name == "Postmark: DKIM" && c.level == StatusLevel::Ok as i32));
            Ok(())
        });
    }

    #[test]
    fn unverified_postmark_dkim_and_missing_dmarc_surface_on_provider_and_domain() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, None, None, email_only(Some(postmark(true, "account-secret")), None), None);
            let user = admin(conn, "cis_postmark_dkim");
            let (url, _) = postmark_mock(false);
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let pm = &status.email_providers[0];
            assert_eq!(pm.level, StatusLevel::Error as i32);
            let domain = &status.email_domains[0];
            assert!(!domain.dmarc.as_ref().unwrap().record_found);
            let dmarc = domain.checks.iter().find(|c| c.name == "DMARC").unwrap();
            assert_eq!(dmarc.level, StatusLevel::Warning as i32);
            assert!(dmarc.fix_hint.as_ref().unwrap().contains("_dmarc.example.com"));
            assert_eq!(domain.level, StatusLevel::Error as i32);
            Ok(())
        });
    }

    #[test]
    fn rejected_postmark_token_is_an_error() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(conn, None, None, email_only(Some(postmark(true, "")), None), None);
            let user = admin(conn, "cis_postmark_401");
            let (url, _) = serve_capturing(|_, _| ("HTTP/1.1 401 Unauthorized", json!({"ErrorCode": 10, "Message": "Bad or missing Server API token"})));
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let pm = &status.email_providers[0];
            assert_eq!(pm.level, StatusLevel::Error as i32);
            assert_eq!(pm.summary, "Credentials rejected by Postmark");
            Ok(())
        });
    }

    #[test]
    fn sendgrid_missing_scopes_are_info_not_errors() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure(
                conn,
                None,
                None,
                email_only(
                    None,
                    Some(SendgridConfig {
                        sendgrid_enabled: true,
                        sendgrid_api_key: "SG.secret".to_string(),
                        sendgrid_from_address: "hello@mail.example.org".to_string(),
                        ..Default::default()
                    }),
                ),
                None,
            );
            let user = admin(conn, "cis_sendgrid_scopes");
            let (url, _) = serve_capturing(|request, _| {
                let line = request_line(request);
                if line.contains("/v3/scopes") {
                    ("HTTP/1.1 200 OK", json!({"scopes": ["mail.send"]}))
                } else {
                    // Everything else needs a scope this key doesn't have.
                    ("HTTP/1.1 403 Forbidden", json!({"errors": [{"message": "access forbidden"}]}))
                }
            });
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let sg = &status.email_providers[0];
            assert_eq!(sg.provider, "sendgrid");
            assert_eq!(check(sg, "API credentials").level, StatusLevel::Ok as i32);
            assert_eq!(check(sg, "Domain authentication").level, StatusLevel::Info as i32);
            assert_eq!(check(sg, "Recent delivery").level, StatusLevel::Info as i32);
            assert_ne!(sg.level, StatusLevel::Error as i32, "{:?}", sg.checks);
            // The domain is still reported on, from DNS alone, with SendGrid's s1/s2 probed.
            assert_eq!(status.email_domains[0].domain, "mail.example.org");
            let dkim = status.email_domains[0].checks.iter().find(|c| c.name == "DKIM keys in DNS").unwrap();
            assert!(dkim.detail.contains("s1._domainkey.mail.example.org"), "{}", dkim.detail);
            Ok(())
        });
    }

    #[test]
    fn stalwart_smtp_connect_check_and_shared_domain_merge() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            let port = listener.local_addr().unwrap().port() as i32;
            let stalwart = StalwartConfig {
                stalwart_sending_enabled: true,
                stalwart_smtp_host: "127.0.0.1".to_string(),
                stalwart_smtp_port: port,
                stalwart_from_address: "noreply@example.com".to_string(),
                ..Default::default()
            };
            configure(conn, None, None, email_only(Some(postmark(true, "")), None), Some(stalwart));
            let user = admin(conn, "cis_stalwart");
            let (url, _) = postmark_mock(true);
            let status = get_contact_integrations_status_with(&user, conn, &env(&url, FakeDns::new(&[]))).unwrap();
            let st = status.email_providers.iter().find(|p| p.provider == "stalwart").unwrap();
            assert_eq!(check(st, "SMTP submission").level, StatusLevel::Ok as i32);
            // Postmark and Stalwart both send as example.com: one domain entry, both listed.
            assert_eq!(status.email_domains.len(), 1);
            assert_eq!(status.email_domains[0].used_by.len(), 2);
            drop(listener);
            Ok(())
        });
    }

    #[test]
    fn stalwart_unreachable_smtp_is_an_error() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            // Bind then drop to get a port nothing listens on.
            let port = {
                let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
                l.local_addr().unwrap().port() as i32
            };
            configure(
                conn,
                None,
                None,
                Default::default(),
                Some(StalwartConfig {
                    stalwart_sending_enabled: true,
                    stalwart_smtp_host: "127.0.0.1".to_string(),
                    stalwart_smtp_port: port,
                    stalwart_from_address: "noreply@example.com".to_string(),
                    ..Default::default()
                }),
            );
            let user = admin(conn, "cis_stalwart_down");
            let status = get_contact_integrations_status_with(&user, conn, &env("http://127.0.0.1:1", FakeDns::new(&[]))).unwrap();
            let st = &status.email_providers[0];
            assert_eq!(check(st, "SMTP submission").level, StatusLevel::Error as i32);
            assert_eq!(st.level, StatusLevel::Error as i32);
            Ok(())
        });
    }
}
