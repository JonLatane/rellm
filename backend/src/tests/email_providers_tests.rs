//! Specs for outbound email (`logic::contact_methods::email_sending` and the Postmark / SendGrid /
//! Mailgun / Stalwart senders), the email half of `ConfigureServer`/`GetServerConfiguration`
//! (write-only secrets, admin-only fields, `CONTACT_PROTOCOL_MAILTO` validation). HTTP providers run
//! against `factories::serve_capturing`; Stalwart against a tiny in-process plaintext SMTP server.

use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};

use base64::Engine;
use diesel::prelude::*;
use tonic::Code;

use crate::db_connection::PgPooledConnection;
use crate::logic::stalwart_email::{self, SmtpTls};
use crate::logic::{
    available_email_apis, build_verification_email, email_sending_available, format_from_header,
    normalize_recipient, order_email_apis, send_verification_email, server_mailgun_config,
    server_postmark_config, server_sendgrid_config, server_stalwart_config,
};
use crate::models;
use crate::protos::*;
use crate::rpcs::{
    configure_server, get_server_configuration, get_server_configuration_proto, redact_secrets,
};
use crate::schema::server_configurations;
use crate::tests::factories::*;

fn postmark(enabled: bool) -> PostmarkConfig {
    PostmarkConfig {
        postmark_enabled: enabled,
        postmark_server_token: "pm-server-token".to_string(),
        postmark_account_token: "pm-account-token".to_string(),
        postmark_from_address: "noreply@example.com".to_string(),
        postmark_from_name: "Example Server".to_string(),
        postmark_message_stream: String::new(),
    }
}

fn sendgrid(enabled: bool) -> SendgridConfig {
    SendgridConfig {
        sendgrid_enabled: enabled,
        sendgrid_api_key: "SG.test-key".to_string(),
        sendgrid_from_address: "noreply@example.com".to_string(),
        sendgrid_from_name: "Example Server".to_string(),
        sendgrid_region: String::new(),
    }
}

fn mailgun(enabled: bool) -> MailgunConfig {
    MailgunConfig {
        mailgun_enabled: enabled,
        mailgun_api_key: "mg-key".to_string(),
        mailgun_domain: "mg.example.com".to_string(),
        mailgun_region: String::new(),
        mailgun_from_address: "noreply@mg.example.com".to_string(),
        mailgun_from_name: "Example Server".to_string(),
    }
}

fn stalwart(enabled: bool, host: &str, port: i32) -> StalwartConfig {
    StalwartConfig {
        stalwart_sending_enabled: enabled,
        stalwart_smtp_host: host.to_string(),
        stalwart_smtp_port: port,
        stalwart_smtp_username: "rellm".to_string(),
        stalwart_smtp_password: "smtp-secret".to_string(),
        stalwart_from_address: "noreply@example.com".to_string(),
        stalwart_from_name: "Example Server".to_string(),
        ..Default::default()
    }
}

/// Inserts an active configuration straight into the DB (mirrors `configure_twilio`) with the given
/// email providers, preference order, and `MAILTO` listed iff any `Some` provider is enabled.
fn configure_email(
    conn: &mut PgPooledConnection,
    postmark_config: Option<PostmarkConfig>,
    sendgrid_config: Option<SendgridConfig>,
    mailgun_config: Option<MailgunConfig>,
    stalwart_config: Option<StalwartConfig>,
    preferred: &[EmailVerificationApi],
) {
    let mut new_config = models::default_server_configuration();
    new_config.server_info = serde_json::to_value(ServerInfo {
        name: Some("Example Server".to_string()),
        ..Default::default()
    })
    .unwrap();
    let any_enabled = postmark_config.as_ref().is_some_and(|c| c.postmark_enabled)
        || sendgrid_config.as_ref().is_some_and(|c| c.sendgrid_enabled)
        || mailgun_config.as_ref().is_some_and(|c| c.mailgun_enabled)
        || stalwart_config.as_ref().is_some_and(|c| c.stalwart_sending_enabled);
    new_config.email_providers_config = Some(
        serde_json::to_value(models::EmailProvidersJson {
            postmark_config,
            sendgrid_config,
            mailgun_config,
            preferred_email_apis: preferred.iter().map(|a| a.as_str_name().to_string()).collect(),
        })
        .unwrap(),
    );
    new_config.stalwart_config = stalwart_config.map(|c| serde_json::to_value(c).unwrap());
    if any_enabled {
        new_config.supported_contact_protocols =
            Some(crate::logic::contact_protocols_to_json(&[ContactProtocol::Mailto]));
    }
    diesel::insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// The JSON/form body of a captured raw HTTP request.
fn request_body(request: &str) -> String {
    request.split_once("\r\n\r\n").map(|(_, b)| b.to_string()).unwrap_or_default()
}

fn header(request: &str, name: &str) -> Option<String> {
    request
        .lines()
        .find(|l| l.to_lowercase().starts_with(&format!("{}:", name.to_lowercase())))
        .and_then(|l| l.split_once(':'))
        .map(|(_, v)| v.trim().to_string())
}

fn ok_json(_: &str, _: &[String]) -> (&'static str, serde_json::Value) {
    ("HTTP/1.1 200 OK", serde_json::json!({"ErrorCode": 0, "Message": "OK", "id": "<x>"}))
}

mod content {
    use super::*;

    #[test]
    fn subject_and_bodies_name_the_server_and_code() {
        let email = build_verification_email("Example Server", Some("example.com"), "123456");
        assert_eq!(email.subject, "Your Example Server verification code: 123456");
        for body in [&email.text, &email.html] {
            assert!(body.contains("Example Server"));
            assert!(body.contains("example.com"));
            assert!(body.contains("123456"));
            assert!(body.contains("10 minutes"));
            assert!(body.contains("didn't request this"));
        }
    }

    #[test]
    fn untrusted_text_is_escaped_in_html_and_stripped_from_the_subject() {
        let email = build_verification_email("<script>x</script>\r\nBcc: evil@x.com", None, "1&2");
        assert!(!email.html.contains("<script>"));
        assert!(email.html.contains("&lt;script&gt;"));
        assert!(email.html.contains("1&amp;2"));
        assert!(!email.subject.contains('\n') && !email.subject.contains('\r'));
    }

    #[test]
    fn recipients_are_normalized_and_header_smuggling_rejected() {
        assert_eq!(normalize_recipient("mailto:a@b.com").unwrap(), "a@b.com");
        assert_eq!(normalize_recipient("MAILTO:a@b.com?subject=hi").unwrap(), "a@b.com");
        assert_eq!(normalize_recipient("a@b.com").unwrap(), "a@b.com");
        for bad in [
            "mailto:",
            "mailto:nope",
            "mailto:a@b.com,c@d.com",
            "mailto:a@b.com\r\nBcc: c@d.com",
            "mailto:a b@c.com",
            "mailto:<a@b.com>",
            "mailto:a@@b.com",
            "mailto:a@localhost",
        ] {
            let err = normalize_recipient(bad).expect_err(bad);
            assert_eq!(err.code(), Code::InvalidArgument, "{bad}");
        }
    }

    #[test]
    fn from_header_quotes_and_escapes_the_display_name() {
        assert_eq!(format_from_header("", "a@b.com"), "a@b.com");
        assert_eq!(format_from_header("Ex", "a@b.com"), "\"Ex\" <a@b.com>");
        assert_eq!(
            format_from_header("E\"x\r\n", "a@b.com"),
            "\"E\\\"x\" <a@b.com>"
        );
    }
}

mod providers {
    use super::*;

    #[test]
    fn postmark_posts_the_email_api_shape() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, Some(postmark(true)), None, None, None, &[]);
            let (base, captured) = serve_capturing(ok_json);
            send_verification_email(Some(&base), conn, "mailto:user@example.org", "123456")?;

            let requests = captured.lock().unwrap();
            assert_eq!(requests.len(), 1);
            assert!(requests[0].starts_with("POST /email "));
            assert_eq!(header(&requests[0], "x-postmark-server-token").as_deref(), Some("pm-server-token"));
            let body: serde_json::Value = serde_json::from_str(&request_body(&requests[0])).unwrap();
            assert_eq!(body["From"], "\"Example Server\" <noreply@example.com>");
            assert_eq!(body["To"], "user@example.org");
            assert_eq!(body["MessageStream"], "outbound");
            assert_eq!(body["Subject"], "Your Example Server verification code: 123456");
            assert!(body["TextBody"].as_str().unwrap().contains("123456"));
            assert!(body["HtmlBody"].as_str().unwrap().contains("<html>"));
            Ok(())
        });
    }

    #[test]
    fn postmark_error_code_in_a_200_is_a_failure() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, Some(postmark(true)), None, None, None, &[]);
            let (base, _) = serve_capturing(|_, _| {
                ("HTTP/1.1 200 OK", serde_json::json!({"ErrorCode": 300, "Message": "Invalid email request"}))
            });
            let err = send_verification_email(Some(&base), conn, "mailto:user@example.org", "123456")
                .expect_err("should fail");
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "postmark_send_failed");
            Ok(())
        });
    }

    #[test]
    fn sendgrid_posts_the_v3_mail_send_shape() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, None, Some(sendgrid(true)), None, None, &[]);
            let (base, captured) = serve_capturing(|_, _| ("HTTP/1.1 202 Accepted", serde_json::Value::Null));
            send_verification_email(Some(&base), conn, "mailto:user@example.org", "654321")?;

            let requests = captured.lock().unwrap();
            assert!(requests[0].starts_with("POST /v3/mail/send "));
            assert_eq!(header(&requests[0], "authorization").as_deref(), Some("Bearer SG.test-key"));
            let body: serde_json::Value = serde_json::from_str(&request_body(&requests[0])).unwrap();
            assert_eq!(body["personalizations"][0]["to"][0]["email"], "user@example.org");
            assert_eq!(body["from"]["email"], "noreply@example.com");
            assert_eq!(body["from"]["name"], "Example Server");
            assert_eq!(body["content"][0]["type"], "text/plain");
            assert_eq!(body["content"][1]["type"], "text/html");
            assert!(body["content"][0]["value"].as_str().unwrap().contains("654321"));
            Ok(())
        });
    }

    #[test]
    fn sendgrid_failure_status_is_an_error() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, None, Some(sendgrid(true)), None, None, &[]);
            let (base, _) = serve_capturing(|_, _| {
                ("HTTP/1.1 401 Unauthorized", serde_json::json!({"errors": [{"message": "bad key"}]}))
            });
            let err = send_verification_email(Some(&base), conn, "mailto:user@example.org", "1")
                .expect_err("should fail");
            assert_eq!(err.message(), "sendgrid_send_failed");
            Ok(())
        });
    }

    #[test]
    fn region_picks_the_regional_host() {
        use crate::logic::{mailgun_email, sendgrid_email};
        assert_eq!(sendgrid_email::default_base_url(""), "https://api.sendgrid.com");
        assert_eq!(sendgrid_email::default_base_url("eu"), "https://api.eu.sendgrid.com");
        assert_eq!(mailgun_email::default_base_url(""), "https://api.mailgun.net");
        assert_eq!(mailgun_email::default_base_url("us"), "https://api.mailgun.net");
        assert_eq!(mailgun_email::default_base_url("eu"), "https://api.eu.mailgun.net");
    }

    #[test]
    fn mailgun_posts_a_form_to_the_domain_messages_endpoint() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, None, None, Some(mailgun(true)), None, &[]);
            let (base, captured) = serve_capturing(ok_json);
            send_verification_email(Some(&base), conn, "mailto:user@example.org", "111222")?;

            let requests = captured.lock().unwrap();
            assert!(requests[0].starts_with("POST /v3/mg.example.com/messages "));
            let auth = header(&requests[0], "authorization").unwrap();
            let decoded = base64::engine::general_purpose::STANDARD
                .decode(auth.trim_start_matches("Basic ").trim())
                .unwrap();
            assert_eq!(String::from_utf8(decoded).unwrap(), "api:mg-key");
            let form: std::collections::HashMap<String, String> =
                form_urlencoded::parse(request_body(&requests[0]).as_bytes()).into_owned().collect();
            assert_eq!(form["from"], "\"Example Server\" <noreply@mg.example.com>");
            assert_eq!(form["to"], "user@example.org");
            assert_eq!(form["subject"], "Your Example Server verification code: 111222");
            assert!(form["text"].contains("111222"));
            assert!(form["html"].contains("<html>"));
            Ok(())
        });
    }

    #[test]
    fn invalid_recipient_never_reaches_a_provider() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, Some(postmark(true)), None, None, None, &[]);
            let (base, captured) = serve_capturing(ok_json);
            let err = send_verification_email(Some(&base), conn, "mailto:a@b.com,c@d.com", "1")
                .expect_err("should fail");
            assert_eq!(err.code(), Code::InvalidArgument);
            assert!(captured.lock().unwrap().is_empty());
            Ok(())
        });
    }
}

mod dispatch {
    use super::*;

    #[test]
    fn order_is_preferred_first_then_fixed_fallback() {
        use EmailVerificationApi::*;
        let all = |_: &EmailVerificationApi| true;
        assert_eq!(order_email_apis(&[], all), vec![Postmark, Sendgrid, Mailgun, Stalwart]);
        assert_eq!(
            order_email_apis(&[Mailgun, Stalwart, Mailgun], all),
            vec![Mailgun, Stalwart, Postmark, Sendgrid]
        );
        // Preferred-but-unavailable providers are dropped.
        assert_eq!(
            order_email_apis(&[Sendgrid], |a| *a != Sendgrid),
            vec![Postmark, Mailgun, Stalwart]
        );
    }

    #[test]
    fn nothing_configured_means_unavailable_and_send_fails_precondition() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(conn, None, None, None, None, &[]);
            assert!(available_email_apis(conn).is_empty());
            assert!(!email_sending_available(conn));
            let err = send_verification_email(None, conn, "mailto:a@b.com", "1").expect_err("no provider");
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "email_verification_not_configured");
            Ok(())
        });
    }

    #[test]
    fn available_requires_enabled_and_configured_and_honors_preference() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let incomplete_postmark = PostmarkConfig { postmark_server_token: String::new(), ..postmark(true) };
            configure_email(
                conn,
                Some(incomplete_postmark),
                Some(sendgrid(true)),
                Some(mailgun(true)),
                Some(stalwart(true, "stalwart.local", 0)),
                &[EmailVerificationApi::Stalwart, EmailVerificationApi::Postmark],
            );
            assert!(email_sending_available(conn));
            assert_eq!(
                available_email_apis(conn),
                vec![
                    EmailVerificationApi::Stalwart,
                    EmailVerificationApi::Sendgrid,
                    EmailVerificationApi::Mailgun
                ]
            );
            // `to_proto` agrees with the DB-backed dispatcher.
            let proto = get_server_configuration_proto(conn)?;
            assert_eq!(
                proto.available_email_apis,
                vec![
                    EmailVerificationApi::Stalwart as i32,
                    EmailVerificationApi::Sendgrid as i32,
                    EmailVerificationApi::Mailgun as i32
                ]
            );
            Ok(())
        });
    }

    #[test]
    fn disabled_provider_is_not_available_and_unconfigured_one_is_skipped_when_sending() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            // Preferred SendGrid is disabled, so Postmark (fixed-order first) must send.
            configure_email(
                conn,
                Some(postmark(true)),
                Some(sendgrid(false)),
                None,
                None,
                &[EmailVerificationApi::Sendgrid],
            );
            assert_eq!(available_email_apis(conn), vec![EmailVerificationApi::Postmark]);
            let (base, captured) = serve_capturing(ok_json);
            send_verification_email(Some(&base), conn, "mailto:a@example.org", "1")?;
            assert!(captured.lock().unwrap()[0].starts_with("POST /email "));
            Ok(())
        });
    }

    #[test]
    fn preferred_provider_sends_first() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(
                conn,
                Some(postmark(true)),
                Some(sendgrid(true)),
                None,
                None,
                &[EmailVerificationApi::Sendgrid],
            );
            let (base, captured) = serve_capturing(|_, _| ("HTTP/1.1 202 Accepted", serde_json::Value::Null));
            send_verification_email(Some(&base), conn, "mailto:a@example.org", "1")?;
            assert!(captured.lock().unwrap()[0].starts_with("POST /v3/mail/send "));
            Ok(())
        });
    }

    #[test]
    fn internal_accessors_return_unscrubbed_secrets() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(
                conn,
                Some(postmark(true)),
                Some(sendgrid(true)),
                Some(mailgun(true)),
                Some(stalwart(true, "h", 587)),
                &[],
            );
            assert_eq!(server_postmark_config(conn).unwrap().postmark_server_token, "pm-server-token");
            assert_eq!(server_sendgrid_config(conn).unwrap().sendgrid_api_key, "SG.test-key");
            assert_eq!(server_mailgun_config(conn).unwrap().mailgun_api_key, "mg-key");
            assert_eq!(server_stalwart_config(conn).unwrap().stalwart_smtp_password, "smtp-secret");
            Ok(())
        });
    }
}

mod stalwart_smtp {
    use super::*;

    /// A one-connection plaintext SMTP server recording every received line. Advertises (and
    /// accepts) AUTH PLAIN/LOGIN; returns `(port, lines)`.
    fn serve_smtp() -> (u16, Arc<Mutex<Vec<String>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let lines = Arc::new(Mutex::new(Vec::new()));
        let lines_thread = lines.clone();
        std::thread::spawn(move || {
            let Ok((stream, _)) = listener.accept() else { return };
            let mut writer = stream.try_clone().unwrap();
            let mut reader = BufReader::new(stream);
            let _ = writer.write_all(b"220 fake ESMTP\r\n");
            let mut in_data = false;
            let mut line = String::new();
            loop {
                line.clear();
                if reader.read_line(&mut line).unwrap_or(0) == 0 {
                    break;
                }
                let trimmed = line.trim_end().to_string();
                lines_thread.lock().unwrap().push(trimmed.clone());
                if in_data {
                    if trimmed == "." {
                        in_data = false;
                        let _ = writer.write_all(b"250 queued\r\n");
                    }
                    continue;
                }
                let upper = trimmed.to_uppercase();
                let reply: &[u8] = if upper.starts_with("EHLO") {
                    b"250-fake\r\n250 AUTH PLAIN LOGIN\r\n"
                } else if upper.starts_with("AUTH PLAIN") && trimmed.split_whitespace().count() == 2 {
                    b"334 \r\n"
                } else if upper.starts_with("AUTH") {
                    b"235 ok\r\n"
                } else if upper.starts_with("MAIL") || upper.starts_with("RCPT") {
                    b"250 ok\r\n"
                } else if upper == "DATA" {
                    in_data = true;
                    b"354 go\r\n"
                } else if upper == "QUIT" {
                    let _ = writer.write_all(b"221 bye\r\n");
                    break;
                } else if upper.starts_with("AUTH") || trimmed.len() > 40 {
                    // second leg of AUTH PLAIN (base64 credentials)
                    b"235 ok\r\n"
                } else {
                    b"250 ok\r\n"
                };
                let _ = writer.write_all(reply);
            }
        });
        (port, lines)
    }

    #[test]
    fn message_is_multipart_alternative_with_the_right_headers() {
        let config = stalwart(true, "stalwart.local", 587);
        let email = build_verification_email("Example Server", None, "123456");
        let message = stalwart_email::build_message(&config, "user@example.org", &email).unwrap();
        let raw = String::from_utf8(message.formatted()).unwrap();
        assert!(raw.contains("From: \"Example Server\" <noreply@example.com>"), "{raw}");
        assert!(raw.contains("To: user@example.org"), "{raw}");
        assert!(raw.contains("Subject: Your Example Server verification code: 123456"), "{raw}");
        assert!(raw.contains("multipart/alternative"), "{raw}");
        assert!(raw.contains("text/plain") && raw.contains("text/html"), "{raw}");
    }

    #[test]
    fn bad_from_address_is_a_precondition_failure() {
        let config = StalwartConfig { stalwart_from_address: "not an address".to_string(), ..stalwart(true, "h", 587) };
        let email = build_verification_email("S", None, "1");
        let err = stalwart_email::build_message(&config, "user@example.org", &email).expect_err("bad from");
        assert_eq!(err.code(), Code::FailedPrecondition);
    }

    #[test]
    fn port_selects_the_tls_mode() {
        assert_eq!(stalwart_email::effective_port(&stalwart(true, "h", 0)), 587);
        assert_eq!(stalwart_email::effective_port(&stalwart(true, "h", 2525)), 2525);
        assert_eq!(stalwart_email::tls_mode_for_port(587), SmtpTls::Starttls);
        assert_eq!(stalwart_email::tls_mode_for_port(465), SmtpTls::Implicit);
    }

    #[test]
    fn delivers_over_smtp_with_auth() {
        let (port, lines) = serve_smtp();
        let config = stalwart(true, "127.0.0.1", port as i32);
        let email = build_verification_email("Example Server", None, "987654");
        let message = stalwart_email::build_message(&config, "user@example.org", &email).unwrap();
        stalwart_email::send_message_with(&config, "127.0.0.1", port, SmtpTls::None, message)
            .expect("smtp send should succeed");
        let lines = lines.lock().unwrap().join("\n");
        assert!(lines.contains("AUTH"), "{lines}");
        assert!(lines.contains("MAIL FROM:<noreply@example.com>"), "{lines}");
        assert!(lines.contains("RCPT TO:<user@example.org>"), "{lines}");
        assert!(lines.contains("Subject: Your Example Server verification code: 987654"), "{lines}");
    }

    #[test]
    fn connection_failure_is_a_precondition_failure() {
        // A port nothing listens on.
        let port = { TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port() };
        let config = stalwart(true, "127.0.0.1", port as i32);
        let email = build_verification_email("S", None, "1");
        let message = stalwart_email::build_message(&config, "user@example.org", &email).unwrap();
        let err = stalwart_email::send_message_with(&config, "127.0.0.1", port, SmtpTls::None, message)
            .expect_err("should fail");
        assert_eq!(err.code(), Code::FailedPrecondition);
        assert_eq!(err.message(), "stalwart_send_failed");
    }
}

mod configure_server_email {
    use super::*;

    fn admin(conn: &mut PgPooledConnection, name: &str) -> models::User {
        let user = create_user(conn, name);
        grant_permissions(conn, &user, vec![Permission::Admin])
    }

    fn base_request(conn: &mut PgPooledConnection) -> ServerConfiguration {
        get_server_configuration_proto(conn).expect("base config")
    }

    fn with_postmark_token(conn: &mut PgPooledConnection, token: &str, from: &str) -> ServerConfiguration {
        let mut config = base_request(conn);
        config.postmark_config = Some(PostmarkConfig {
            postmark_server_token: token.to_string(),
            postmark_account_token: if token.is_empty() { String::new() } else { "acct".to_string() },
            postmark_from_address: from.to_string(),
            ..postmark(true)
        });
        config
    }

    #[test]
    fn secrets_are_blanked_in_responses_and_kept_on_blank_resubmit() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = admin(conn, "esm_blank_merge");
            let mut request = base_request(conn);
            request.postmark_config = Some(postmark(true));
            request.sendgrid_config = Some(sendgrid(true));
            request.mailgun_config = Some(mailgun(true));
            request.stalwart_config = Some(stalwart(true, "stalwart.local", 587));
            request.preferred_email_apis = vec![EmailVerificationApi::Mailgun as i32];
            request.supported_contact_protocols = vec![ContactProtocol::Mailto as i32];
            let response = configure_server(request, &admin, conn).expect("configure");

            let pm = response.postmark_config.clone().unwrap();
            assert_eq!((pm.postmark_server_token.as_str(), pm.postmark_account_token.as_str()), ("", ""));
            assert_eq!(pm.postmark_from_address, "noreply@example.com");
            assert_eq!(response.sendgrid_config.clone().unwrap().sendgrid_api_key, "");
            assert_eq!(response.mailgun_config.clone().unwrap().mailgun_api_key, "");
            let st = response.stalwart_config.clone().unwrap();
            assert_eq!(st.stalwart_smtp_password, "");
            assert_eq!(st.stalwart_management_token, "");
            assert_eq!(st.stalwart_smtp_host, "stalwart.local");
            assert_eq!(response.preferred_email_apis, vec![EmailVerificationApi::Mailgun as i32]);
            assert_eq!(response.available_email_apis[0], EmailVerificationApi::Mailgun as i32);
            assert_eq!(response.available_email_apis.len(), 4);

            // Resubmit exactly what the client got back (all secrets blank), with an edited
            // non-secret field on each.
            let mut again = response.clone();
            again.postmark_config.as_mut().unwrap().postmark_from_name = "Renamed".to_string();
            again.sendgrid_config.as_mut().unwrap().sendgrid_region = "eu".to_string();
            again.mailgun_config.as_mut().unwrap().mailgun_region = "eu".to_string();
            again.stalwart_config.as_mut().unwrap().stalwart_smtp_port = 465;
            configure_server(again, &admin, conn).expect("second configure");

            let pm = server_postmark_config(conn).unwrap();
            assert_eq!(pm.postmark_server_token, "pm-server-token");
            assert_eq!(pm.postmark_account_token, "pm-account-token");
            assert_eq!(pm.postmark_from_name, "Renamed");
            let sg = server_sendgrid_config(conn).unwrap();
            assert_eq!((sg.sendgrid_api_key.as_str(), sg.sendgrid_region.as_str()), ("SG.test-key", "eu"));
            let mg = server_mailgun_config(conn).unwrap();
            assert_eq!((mg.mailgun_api_key.as_str(), mg.mailgun_region.as_str()), ("mg-key", "eu"));
            let st = server_stalwart_config(conn).unwrap();
            assert_eq!(st.stalwart_smtp_password, "smtp-secret");
            assert_eq!(st.stalwart_smtp_port, 465);
            Ok(())
        });
    }

    #[test]
    fn a_non_blank_secret_replaces_the_stored_one() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = admin(conn, "esm_replace");
            let request = with_postmark_token(conn, "old-token", "noreply@example.com");
            configure_server(request, &admin, conn).expect("first");
            let request = with_postmark_token(conn, "new-token", "noreply@example.com");
            configure_server(request, &admin, conn).expect("second");
            assert_eq!(server_postmark_config(conn).unwrap().postmark_server_token, "new-token");
            Ok(())
        });
    }

    #[test]
    fn non_admins_do_not_see_email_config_but_do_see_availability() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_email(
                conn,
                Some(postmark(true)),
                Some(sendgrid(true)),
                Some(mailgun(true)),
                Some(stalwart(true, "stalwart.local", 587)),
                &[EmailVerificationApi::Sendgrid],
            );
            let regular = create_user(conn, "esm_regular");
            let for_user = get_server_configuration((), &Some(&regular), conn)?;
            assert!(for_user.postmark_config.is_none());
            assert!(for_user.sendgrid_config.is_none());
            assert!(for_user.mailgun_config.is_none());
            assert!(for_user.stalwart_config.is_none());
            assert!(for_user.preferred_email_apis.is_empty());
            assert_eq!(for_user.available_email_apis[0], EmailVerificationApi::Sendgrid as i32);
            assert_eq!(for_user.available_email_apis.len(), 4);
            assert!(for_user.supported_contact_protocols.contains(&(ContactProtocol::Mailto as i32)));

            let anonymous = get_server_configuration((), &None, conn)?;
            assert!(anonymous.postmark_config.is_none() && anonymous.preferred_email_apis.is_empty());
            assert_eq!(anonymous.available_email_apis.len(), 4);

            let admin = admin(conn, "esm_admin_view");
            let for_admin = get_server_configuration((), &Some(&admin), conn)?;
            assert!(for_admin.postmark_config.is_some() && for_admin.stalwart_config.is_some());
            assert_eq!(for_admin.preferred_email_apis, vec![EmailVerificationApi::Sendgrid as i32]);
            Ok(())
        });
    }

    #[test]
    fn mailto_protocol_requires_an_enabled_email_provider_in_the_same_request() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = admin(conn, "esm_mailto");
            let mut request = base_request(conn);
            request.supported_contact_protocols = vec![ContactProtocol::Mailto as i32];
            let err = configure_server(request.clone(), &admin, conn).expect_err("no provider");
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "email_contact_protocol_requires_a_configured_provider");

            // A configured-but-disabled provider doesn't count.
            request.postmark_config = Some(postmark(false));
            assert!(configure_server(request.clone(), &admin, conn).is_err());

            // Each provider kind counts when enabled.
            for enable in 0..4 {
                let mut r = request.clone();
                match enable {
                    0 => r.postmark_config = Some(postmark(true)),
                    1 => r.sendgrid_config = Some(sendgrid(true)),
                    2 => r.mailgun_config = Some(mailgun(true)),
                    _ => r.stalwart_config = Some(stalwart(true, "stalwart.local", 587)),
                }
                let response = configure_server(r, &admin, conn).expect("enabled provider should allow MAILTO");
                assert!(response.supported_contact_protocols.contains(&(ContactProtocol::Mailto as i32)));
            }

            // Stalwart *receiving* alone isn't a sending provider.
            let mut r = request.clone();
            r.postmark_config = None;
            r.stalwart_config = Some(StalwartConfig { stalwart_receiving_enabled: true, ..Default::default() });
            assert!(configure_server(r, &admin, conn).is_err());
            Ok(())
        });
    }

    #[test]
    fn field_shapes_are_validated() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let admin = admin(conn, "esm_shapes");
            let cases: Vec<(&str, Box<dyn Fn(&mut ServerConfiguration)>)> = vec![
                ("postmark_from_address_invalid", Box::new(|c| {
                    c.postmark_config = Some(PostmarkConfig { postmark_from_address: "nope".into(), ..postmark(true) })
                })),
                ("sendgrid_from_address_invalid", Box::new(|c| {
                    c.sendgrid_config = Some(SendgridConfig { sendgrid_from_address: "a b@c.com".into(), ..sendgrid(true) })
                })),
                ("sendgrid_region_invalid", Box::new(|c| {
                    c.sendgrid_config = Some(SendgridConfig { sendgrid_region: "us".into(), ..sendgrid(true) })
                })),
                ("mailgun_region_invalid", Box::new(|c| {
                    c.mailgun_config = Some(MailgunConfig { mailgun_region: "asia".into(), ..mailgun(true) })
                })),
                ("mailgun_from_address_invalid", Box::new(|c| {
                    c.mailgun_config = Some(MailgunConfig { mailgun_from_address: "x".into(), ..mailgun(true) })
                })),
                ("stalwart_smtp_port_invalid", Box::new(|c| {
                    c.stalwart_config = Some(stalwart(true, "h", 70000))
                })),
                ("stalwart_smtp_port_invalid", Box::new(|c| {
                    c.stalwart_config = Some(stalwart(true, "h", -1))
                })),
                ("stalwart_from_address_invalid", Box::new(|c| {
                    c.stalwart_config = Some(StalwartConfig { stalwart_from_address: "bad".into(), ..stalwart(true, "h", 587) })
                })),
                ("stalwart_management_url_invalid", Box::new(|c| {
                    c.stalwart_config = Some(StalwartConfig {
                        stalwart_management_url: "ftp://x".into(),
                        ..stalwart(true, "h", 587)
                    })
                })),
            ];
            for (expected, mutate) in cases {
                let mut request = base_request(conn);
                mutate(&mut request);
                let err = configure_server(request, &admin, conn).expect_err(expected);
                assert_eq!(err.code(), Code::InvalidArgument, "{expected}");
                assert_eq!(err.message(), expected);
            }

            // Valid edge values pass.
            let mut ok = base_request(conn);
            ok.mailgun_config = Some(MailgunConfig { mailgun_region: "us".into(), ..mailgun(false) });
            ok.sendgrid_config = Some(SendgridConfig { sendgrid_region: "eu".into(), ..sendgrid(false) });
            ok.stalwart_config = Some(StalwartConfig {
                stalwart_management_url: "http://stalwart.email.svc:8080".into(),
                ..stalwart(false, "h", 65535)
            });
            configure_server(ok, &admin, conn).expect("valid shapes");
            Ok(())
        });
    }
}

#[test]
fn redact_secrets_blanks_every_secret() {
    let s = |v: &str| v.to_string();
    let config = ServerConfiguration {
        federation_info: Some(FederationInfo {
            facebook_auth_config: Some(FacebookAuthConfig { app_id: s("fb-id"), app_secret: s("SECRET") }),
            x_twitter_auth_config: Some(XTwitterAuthConfig { client_id: s("x-id"), client_secret: s("SECRET") }),
            ..Default::default()
        }),
        web_push_config: Some(WebPushConfig { public_vapid_key: s("pub"), private_vapid_key: s("SECRET") }),
        cluster_resources: Some(ClusterResources { cluster_shared_secret: s("SECRET"), ..Default::default() }),
        twilio_config: Some(TwilioConfig {
            twilio_api_key_secret: s("SECRET"),
            twilio_webhook_signing_key: s("SECRET"),
            twilio_account_sid: s("AC123"),
            ..Default::default()
        }),
        bird_config: Some(BirdConfig {
            bird_access_key: s("SECRET"),
            bird_webhook_signing_key: s("SECRET"),
            ..Default::default()
        }),
        telnyx_config: Some(TelnyxConfig {
            telnyx_api_key: s("SECRET"),
            telnyx_webhook_signing_key: s("SECRET"),
            ..Default::default()
        }),
        stripe_config: Some(StripeConfig {
            stripe_secret_key: s("SECRET"),
            stripe_webhook_signing_secret: s("SECRET"),
            stripe_publishable_key: s("pk_public"),
            ..Default::default()
        }),
        postmark_config: Some(PostmarkConfig {
            postmark_server_token: s("SECRET"),
            postmark_account_token: s("SECRET"),
            ..Default::default()
        }),
        sendgrid_config: Some(SendgridConfig { sendgrid_api_key: s("SECRET"), ..Default::default() }),
        mailgun_config: Some(MailgunConfig { mailgun_api_key: s("SECRET"), ..Default::default() }),
        stalwart_config: Some(StalwartConfig {
            stalwart_smtp_password: s("SECRET"),
            stalwart_management_token: s("SECRET"),
            stalwart_smtp_host: s("stalwart.local"),
            ..Default::default()
        }),
        ..Default::default()
    };
    let redacted = redact_secrets(&config);
    let dump = format!("{:?}", redacted);
    assert!(!dump.contains("SECRET"), "a secret survived redaction: {dump}");
    // Non-secret identifiers are kept (the log stays useful).
    for kept in ["fb-id", "x-id", "AC123", "pk_public", "stalwart.local"] {
        assert!(dump.contains(kept), "{kept} should not be redacted");
    }
    // The input is untouched.
    assert!(format!("{:?}", config).contains("SECRET"));
}
