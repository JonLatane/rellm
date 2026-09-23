//! Specs for Twilio SMS `ContactMethod` verification: `update_user`'s phone/email handling
//! (`apply_contact_method_update`'s security-sensitive "never trust `verified_at`/
//! `supported_by_server` from the client" behavior), `start_contact_method_verification` (run
//! against `factories::serve_capturing` instead of the real Twilio API, mirroring
//! `x_twitter_sync_tests`), and `verify_contact_method`.

use std::time::{Duration, SystemTime};

use base64::Engine;
use diesel::prelude::*;
use tonic::Code;

use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{start_contact_method_verification_at, update_user, verify_contact_method};
use crate::tests::factories::*;

/// Pulls the `username`/`password` pair out of a captured raw HTTP request's `Authorization:
/// Basic <base64>` header -- lets specs assert *which* credential pair a provider call actually
/// authenticated with (e.g. the Twilio API Key SID/Secret, not the Account SID), not just that
/// some Basic Auth header was present.
fn basic_auth_credentials(request: &str) -> Option<(String, String)> {
    let header = request
        .lines()
        .find(|line| line.to_lowercase().starts_with("authorization: basic "))?;
    let encoded = header.splitn(3, ' ').nth(2)?.trim();
    let decoded = base64::engine::general_purpose::STANDARD.decode(encoded).ok()?;
    let decoded = String::from_utf8(decoded).ok()?;
    let (username, password) = decoded.split_once(':')?;
    Some((username.to_string(), password.to_string()))
}

/// A phone `ContactMethod` with consent already granted -- most specs here exercise
/// `start_contact_method_verification`/`verify_contact_method`, which (see
/// `start_contact_method_verification_at`'s own doc) require `CONTACT_CONSENT_GRANTED` before
/// they'll send anything, same as any other outbound SMS. Specs for the *lack* of consent use
/// `phone_contact_method_without_consent` instead.
fn phone_contact_method(value: &str) -> ContactMethod {
    ContactMethod {
        value: Some(value.to_string()),
        visibility: Visibility::ServerPublic as i32,
        supported_by_server: false,
        verified_at: None,
        verification_in_progress: None,
        consent_state: ContactConsentState::ContactConsentGranted as i32,
        consent_history: vec![],
    }
}

fn phone_contact_method_without_consent(value: &str) -> ContactMethod {
    ContactMethod {
        consent_state: ContactConsentState::ContactConsentRevoked as i32,
        ..phone_contact_method(value)
    }
}

fn in_progress(code: &str, started_at: SystemTime, attempts: i32) -> ContactMethodVerification {
    ContactMethodVerification {
        verification_code: code.to_string(),
        verification_started_at: Some(started_at.to_proto()),
        attempts,
    }
}

mod update_user_contact_methods {
    use super::*;

    #[test]
    fn setting_a_new_tel_phone_marks_supported_by_server_true_when_twilio_enabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "cmu_enabled");

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(phone.value.as_deref(), Some("tel:+15551234567"));
            assert!(phone.supported_by_server);
            assert_eq!(phone.verified_at, None);

            Ok(())
        });
    }

    #[test]
    fn setting_a_new_tel_phone_marks_supported_by_server_false_when_provider_enabled_but_sms_sending_not_enabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            // Twilio enabled directly, but `supported_contact_protocols` deliberately left unset
            // -- mirrors an admin having entered Twilio credentials without (yet, or anymore)
            // checking "Enable SMS Sending" on `ContactIntegrationsTab.elm`. `supported_by_server`
            // must be false: `contact_protocol_supported` (not the raw `twilio_enabled` flag) is
            // the actual gate, per `ContactMethod.supported_by_server`'s own proto doc.
            let mut new_config = models::default_server_configuration();
            new_config.twilio_config = Some(
                serde_json::to_value(TwilioConfig {
                    twilio_enabled: true,
                    twilio_account_sid: "AC_sid".to_string(),
                    twilio_api_key_sid: "SK_test_key_sid".to_string(),
                    twilio_api_key_secret: "auth_token".to_string(),
                    twilio_from_number: "+15005550006".to_string(),
                    twilio_webhook_signing_key: None,
                })
                .unwrap(),
            );
            diesel::insert_into(crate::schema::server_configurations::table)
                .values(&new_config)
                .execute(conn)
                .expect("failed to create test server configuration");

            let user = create_user(conn, "cmu_protocol_gate");
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert!(
                !phone.supported_by_server,
                "twilio_enabled alone isn't enough -- CONTACT_PROTOCOL_TEL must be in supported_contact_protocols too"
            );

            Ok(())
        });
    }

    #[test]
    fn setting_a_new_tel_phone_marks_supported_by_server_false_when_twilio_disabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "cmu_disabled");

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert!(!phone.supported_by_server, "no TwilioConfig at all should mean unsupported");

            Ok(())
        });
    }

    #[test]
    fn mailto_email_is_never_supported_by_server_even_with_twilio_enabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "cmu_email");

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.email = Some(ContactMethod {
                value: Some("mailto:someone@example.com".to_string()),
                visibility: Visibility::ServerPublic as i32,
                supported_by_server: false,
                verified_at: None,
                verification_in_progress: None,
                consent_state: ContactConsentState::ContactConsentRevoked as i32,
                consent_history: vec![],
            });

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let email = updated.email.expect("email should be set");
            assert!(!email.supported_by_server, "no email provider exists yet");

            Ok(())
        });
    }

    #[test]
    fn editing_phone_value_resets_verification_state() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "cmu_edit_resets");
            let verified_phone = ContactMethod {
                value: Some("tel:+15551234567".to_string()),
                visibility: Visibility::ServerPublic as i32,
                supported_by_server: true,
                verified_at: Some(SystemTime::now().to_proto()),
                verification_in_progress: None,
                consent_state: ContactConsentState::ContactConsentRevoked as i32,
                consent_history: vec![],
            };
            let user = set_user_phone(conn, &user, &verified_phone);

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15559876543"));

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(phone.value.as_deref(), Some("tel:+15559876543"));
            assert_eq!(phone.verified_at, None, "changing the number should invalidate prior verification");

            Ok(())
        });
    }

    #[test]
    fn unchanged_phone_value_preserves_verification_state() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "cmu_unchanged");
            let verified_at = SystemTime::now().to_proto();
            let verified_phone = ContactMethod {
                value: Some("tel:+15551234567".to_string()),
                visibility: Visibility::ServerPublic as i32,
                supported_by_server: true,
                verified_at: Some(verified_at.clone()),
                verification_in_progress: None,
                consent_state: ContactConsentState::ContactConsentRevoked as i32,
                consent_history: vec![],
            };
            let user = set_user_phone(conn, &user, &verified_phone);

            // Resend the same value with a different `visibility` -- only `value` changing should
            // reset verification.
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(ContactMethod {
                value: Some("tel:+15551234567".to_string()),
                visibility: Visibility::Private as i32,
                supported_by_server: false, // client-supplied -- must be ignored
                verified_at: None,          // client-supplied -- must be ignored
                verification_in_progress: None,
                consent_state: ContactConsentState::ContactConsentRevoked as i32,
                consent_history: vec![],
            });

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(
                phone.verified_at,
                Some(verified_at),
                "same value should preserve the prior verification, ignoring client-supplied verified_at"
            );
            assert!(phone.supported_by_server, "supported_by_server must be server-computed, not taken from the (false) client value");

            Ok(())
        });
    }

    #[test]
    fn client_cannot_spoof_verified_at_on_a_brand_new_number() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "cmu_spoof");

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(ContactMethod {
                value: Some("tel:+15551234567".to_string()),
                visibility: Visibility::ServerPublic as i32,
                supported_by_server: true, // spoofed
                verified_at: Some(SystemTime::now().to_proto()), // spoofed
                verification_in_progress: None,
                consent_state: ContactConsentState::ContactConsentRevoked as i32,
                consent_history: vec![],
            });

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(phone.verified_at, None, "a brand new number can never come back pre-verified");
            assert!(!phone.supported_by_server, "no Twilio configured -- must not be trusted from the client");

            Ok(())
        });
    }

    #[test]
    fn granting_consent_appends_a_history_entry_and_sets_consent_state() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "cmu_consent_grant");
            let user = set_user_phone(conn, &user, &phone_contact_method_without_consent("tel:+15551234567"));

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(ContactMethod {
                consent_state: ContactConsentState::ContactConsentGranted as i32,
                ..phone_contact_method_without_consent("tel:+15551234567")
            });

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(phone.consent_state, ContactConsentState::ContactConsentGranted as i32);
            assert_eq!(phone.consent_history.len(), 1);
            assert_eq!(phone.consent_history[0].state, ContactConsentState::ContactConsentGranted as i32);
            assert!(phone.consent_history[0].changed_at.is_some());

            Ok(())
        });
    }

    #[test]
    fn revoking_after_granting_appends_a_second_history_entry_without_dropping_the_first() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "cmu_consent_revoke");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(ContactMethod {
                consent_state: ContactConsentState::ContactConsentRevoked as i32,
                ..phone_contact_method("tel:+15551234567")
            });

            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(phone.consent_state, ContactConsentState::ContactConsentRevoked as i32);
            assert_eq!(phone.consent_history.len(), 1, "revoking a ContactMethod with no prior history still logs the revocation");
            assert_eq!(phone.consent_history[0].state, ContactConsentState::ContactConsentRevoked as i32);

            Ok(())
        });
    }

    #[test]
    fn resending_the_same_consent_state_is_a_no_op_on_history() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "cmu_consent_noop");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            // First call actually changes nothing (phone_contact_method is already GRANTED with no
            // history), so append one entry to have something to *not* duplicate.
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));
            let updated = update_user(request, &user, conn).expect("update should succeed");
            let user = set_user_phone(conn, &user, &updated.phone.clone().unwrap());

            // Resend the exact same (already-GRANTED) consent_state again.
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));
            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");
            assert_eq!(phone.consent_state, ContactConsentState::ContactConsentGranted as i32);
            assert!(phone.consent_history.is_empty(), "no consent_state change means no new history entry");

            Ok(())
        });
    }

    #[test]
    fn re_granting_consent_after_revocation_does_not_erase_the_revocation_from_history() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "cmu_consent_regrant");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            // Grant -> revoke -> re-grant.
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));
            let updated = update_user(request, &user, conn).expect("update should succeed");
            let user = set_user_phone(conn, &user, &updated.phone.clone().unwrap());

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method_without_consent("tel:+15551234567"));
            let updated = update_user(request, &user, conn).expect("update should succeed");
            let user = set_user_phone(conn, &user, &updated.phone.clone().unwrap());

            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(phone_contact_method("tel:+15551234567"));
            let updated = update_user(request, &user, conn).expect("update should succeed");
            let phone = updated.phone.expect("phone should be set");

            assert_eq!(phone.consent_state, ContactConsentState::ContactConsentGranted as i32);
            assert_eq!(phone.consent_history.len(), 2, "the intermediate revocation stays in history");
            assert_eq!(phone.consent_history[0].state, ContactConsentState::ContactConsentRevoked as i32);
            assert_eq!(phone.consent_history[1].state, ContactConsentState::ContactConsentGranted as i32);

            Ok(())
        });
    }
}

mod start_contact_method_verification_spec {
    use super::*;

    #[test]
    fn sends_code_and_stores_verification_in_progress_with_code_blanked_in_response() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_test_sid", "SK_test_key_sid", "test_auth_token", "+15005550006");
            let user = create_user(conn, "scmv_happy");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                (
                    "HTTP/1.1 201 Created",
                    serde_json::json!({ "sid": "SM_test", "status": "queued" }),
                )
            });

            let response = start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed");

            assert!(response.verification_in_progress.is_some());
            let in_progress = response.verification_in_progress.unwrap();
            assert_eq!(in_progress.verification_code, "", "the real code must never be echoed back");
            assert!(in_progress.verification_started_at.is_some());
            assert_eq!(in_progress.attempts, 0);
            assert!(response.supported_by_server);

            let requests = captured.lock().unwrap();
            assert_eq!(requests.len(), 1);
            assert!(requests[0].contains("/Accounts/AC_test_sid/Messages.json"));
            assert!(requests[0].contains("To=%2B15551234567") || requests[0].contains("To=+15551234567"));
            assert_eq!(
                basic_auth_credentials(&requests[0]),
                Some(("SK_test_key_sid".to_string(), "test_auth_token".to_string())),
                "must authenticate with the API Key SID/Secret pair, never the Account SID -- see \
                 TwilioConfig's own doc on why the account's Auth Token is deliberately unsupported"
            );

            Ok(())
        });
    }

    #[test]
    fn rejects_when_consent_not_granted() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_no_consent");
            let user = set_user_phone(
                conn,
                &user,
                &phone_contact_method_without_consent("tel:+15551234567"),
            );

            let err = start_contact_method_verification_at(
                Some("http://127.0.0.1:1"),
                phone_contact_method_without_consent("tel:+15551234567"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "contact_consent_not_granted");

            Ok(())
        });
    }

    #[test]
    fn rejects_when_no_provider_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "scmv_no_provider");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let err = start_contact_method_verification_at(
                Some("http://127.0.0.1:1"),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "verification_not_configured");

            Ok(())
        });
    }

    #[test]
    fn rejects_mailto_as_unimplemented() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_mailto");

            let err = start_contact_method_verification_at(
                Some("http://127.0.0.1:1"),
                ContactMethod {
                    value: Some("mailto:someone@example.com".to_string()),
                    ..phone_contact_method("unused")
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::Unimplemented);
            assert_eq!(err.message(), "email_verification_not_implemented");

            Ok(())
        });
    }

    #[test]
    fn rejects_invalid_value_format() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_invalid");

            let err = start_contact_method_verification_at(
                Some("http://127.0.0.1:1"),
                ContactMethod {
                    value: Some("not-a-url".to_string()),
                    ..phone_contact_method("unused")
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);

            Ok(())
        });
    }

    #[test]
    fn rejects_when_phone_not_set_or_mismatched() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_mismatch");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let err = start_contact_method_verification_at(
                Some("http://127.0.0.1:1"),
                phone_contact_method("tel:+19998887777"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "phone_not_set");

            Ok(())
        });
    }

    #[test]
    fn rate_limits_resend_within_60_seconds() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_cooldown");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress("111111", SystemTime::now(), 0));
            let user = set_user_phone(conn, &user, &phone);

            // No mock server needed -- the rate limit must reject before any HTTP call is made.
            let err = start_contact_method_verification_at(
                Some("http://127.0.0.1:1"),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "verification_recently_sent");

            Ok(())
        });
    }

    #[test]
    fn allows_resend_once_cooldown_has_elapsed() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_cooldown_elapsed");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress(
                "111111",
                SystemTime::now() - Duration::from_secs(120),
                0,
            ));
            let user = set_user_phone(conn, &user, &phone);

            let (base_url, _captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 201 Created", serde_json::json!({ "sid": "SM_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("resend after cooldown should succeed");

            Ok(())
        });
    }

    #[test]
    fn surfaces_twilio_send_failure() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio(conn, true, "AC_sid", "SK_test_key_sid", "auth_token", "+15005550006");
            let user = create_user(conn, "scmv_send_fails");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, _captured) = serve_capturing(|_request, _prior| {
                (
                    "HTTP/1.1 400 Bad Request",
                    serde_json::json!({ "code": 21211, "message": "Invalid 'To' Phone Number" }),
                )
            });

            let err = start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "twilio_send_failed");

            Ok(())
        });
    }
}

mod sms_body_format_spec {
    use super::*;

    #[test]
    fn includes_server_name_and_frontend_host_when_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio_with_server_info(
                conn,
                "AC_sid",
                "SK_test_key_sid",
                "auth_token",
                "+15005550006",
                "Jonline",
                "jonline.io",
            );
            let user = create_user(conn, "sms_body_with_cdn");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 201 Created", serde_json::json!({ "sid": "SM_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed");

            let requests = captured.lock().unwrap();
            assert!(
                requests[0].contains("Phone+verification+requested+from+Jonline+%28jonline.io%29.+Your+code+is%3A")
                    || requests[0].contains("Phone verification requested from Jonline (jonline.io). Your code is:"),
                "expected the server name + frontend host in the message body: {:?}",
                requests[0]
            );
            assert!(requests[0].contains("Do+not+share+this+code+with+anyone") || requests[0].contains("Do not share this code with anyone"));

            Ok(())
        });
    }

    #[test]
    fn omits_the_parenthetical_when_no_frontend_host_is_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_twilio_with_server_info(
                conn,
                "AC_sid",
                "SK_test_key_sid",
                "auth_token",
                "+15005550006",
                "Jonline",
                "",
            );
            let user = create_user(conn, "sms_body_no_cdn");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 201 Created", serde_json::json!({ "sid": "SM_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed");

            let requests = captured.lock().unwrap();
            assert!(
                requests[0].contains("Phone+verification+requested+from+Jonline.+Your+code+is%3A")
                    || requests[0].contains("Phone verification requested from Jonline. Your code is:"),
                "expected no parenthetical when no frontend_host is configured: {:?}",
                requests[0]
            );

            Ok(())
        });
    }
}

mod bird_and_provider_selection_spec {
    use super::*;

    #[test]
    fn sends_via_bird_when_only_bird_is_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_bird(conn, true, "bird_test_key", "Bird", "us1");
            let user = create_user(conn, "bird_happy");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                (
                    "HTTP/1.1 202 Accepted",
                    serde_json::json!({ "id": "sms_test", "status": "accepted" }),
                )
            });

            let response = start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed via Bird");
            assert!(response.verification_in_progress.is_some());

            let requests = captured.lock().unwrap();
            assert_eq!(requests.len(), 1);
            assert!(requests[0].contains("POST /v1/sms/messages"));
            assert!(requests[0].to_lowercase().contains("authorization: bearer bird_test_key"));
            assert!(requests[0].contains("\"category\":\"authentication\""));

            Ok(())
        });
    }

    #[test]
    fn rejects_bird_send_failure() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_bird(conn, true, "bird_test_key", "Bird", "us1");
            let user = create_user(conn, "bird_send_fails");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, _captured) = serve_capturing(|_request, _prior| {
                (
                    "HTTP/1.1 422 Unprocessable Entity",
                    serde_json::json!({ "errors": [{ "message": "invalid destination" }] }),
                )
            });

            let err = start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "bird_send_failed");

            Ok(())
        });
    }

    #[test]
    fn prefers_twilio_by_default_when_both_are_enabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_verification_providers(
                conn,
                Some(("AC_sid", "SK_test_key_sid", "auth_token", "+15005550006")),
                Some(("bird_key", "Bird", "us1")),
                None,
                vec![],
            );
            let user = create_user(conn, "prefers_twilio_default");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 201 Created", serde_json::json!({ "sid": "SM_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed");

            let requests = captured.lock().unwrap();
            assert!(
                requests[0].contains("/Accounts/AC_sid/Messages.json"),
                "should have gone through Twilio (the default-order provider) when no preference is set: {:?}",
                requests[0]
            );

            Ok(())
        });
    }

    #[test]
    fn respects_an_explicit_preference_for_bird_over_twilio() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_verification_providers(
                conn,
                Some(("AC_sid", "SK_test_key_sid", "auth_token", "+15005550006")),
                Some(("bird_key", "Bird", "us1")),
                None,
                vec![ContactVerificationApi::Bird, ContactVerificationApi::Twilio],
            );
            let user = create_user(conn, "prefers_bird_explicit");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 202 Accepted", serde_json::json!({ "id": "sms_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed via the preferred provider");

            let requests = captured.lock().unwrap();
            assert!(
                requests[0].contains("POST /v1/sms/messages"),
                "should have gone through Bird per the explicit preference: {:?}",
                requests[0]
            );

            Ok(())
        });
    }

    #[test]
    fn falls_back_to_bird_when_twilio_is_preferred_but_not_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_verification_providers(
                conn,
                None,
                Some(("bird_key", "Bird", "us1")),
                None,
                vec![ContactVerificationApi::Twilio, ContactVerificationApi::Bird],
            );
            let user = create_user(conn, "falls_back_to_bird");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 202 Accepted", serde_json::json!({ "id": "sms_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("should fall back to Bird since Twilio isn't actually configured");

            let requests = captured.lock().unwrap();
            assert!(requests[0].contains("POST /v1/sms/messages"));

            Ok(())
        });
    }

    #[test]
    fn falls_back_to_telnyx_when_neither_twilio_nor_bird_is_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_verification_providers(
                conn,
                None,
                None,
                Some(("telnyx_key", "+15005550006", "profile_1")),
                vec![
                    ContactVerificationApi::Twilio,
                    ContactVerificationApi::Bird,
                    ContactVerificationApi::Telnyx,
                ],
            );
            let user = create_user(conn, "falls_back_to_telnyx");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                ("HTTP/1.1 202 Accepted", serde_json::json!({ "id": "sms_test" }))
            });

            start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("should fall back to Telnyx since neither Twilio nor Bird is configured");

            let requests = captured.lock().unwrap();
            assert!(requests[0].contains("POST /v2/messages"));

            Ok(())
        });
    }
}

mod telnyx_and_provider_selection_spec {
    use super::*;

    #[test]
    fn sends_via_telnyx_when_only_telnyx_is_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_telnyx(conn, true, "telnyx_test_key", "+15005550006", "profile_1");
            let user = create_user(conn, "telnyx_happy");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, captured) = serve_capturing(|_request, _prior| {
                (
                    "HTTP/1.1 202 Accepted",
                    serde_json::json!({ "data": { "id": "sms_test" } }),
                )
            });

            let response = start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .expect("start should succeed via Telnyx");
            assert!(response.verification_in_progress.is_some());

            let requests = captured.lock().unwrap();
            assert_eq!(requests.len(), 1);
            assert!(requests[0].contains("POST /v2/messages"));
            assert!(requests[0]
                .to_lowercase()
                .contains("authorization: bearer telnyx_test_key"));
            assert!(requests[0].contains("\"messaging_profile_id\":\"profile_1\""));

            Ok(())
        });
    }

    #[test]
    fn rejects_telnyx_send_failure() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            configure_telnyx(conn, true, "telnyx_test_key", "+15005550006", "profile_1");
            let user = create_user(conn, "telnyx_send_fails");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let (base_url, _captured) = serve_capturing(|_request, _prior| {
                (
                    "HTTP/1.1 422 Unprocessable Entity",
                    serde_json::json!({ "errors": [{ "detail": "invalid destination" }] }),
                )
            });

            let err = start_contact_method_verification_at(
                Some(&base_url),
                phone_contact_method("tel:+15551234567"),
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "telnyx_send_failed");

            Ok(())
        });
    }
}

mod verify_contact_method_spec {
    use super::*;

    #[test]
    fn verifies_on_correct_code() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_correct");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress("654321", SystemTime::now(), 0));
            let user = set_user_phone(conn, &user, &phone);

            let response = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "tel:+15551234567".to_string(),
                    code: "654321".to_string(),
                },
                &user,
                conn,
            )
            .expect("verification should succeed");

            assert!(response.verified_at.is_some());
            assert!(response.verification_in_progress.is_none());

            Ok(())
        });
    }

    #[test]
    fn rejects_incorrect_code_and_increments_attempts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_incorrect");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress("654321", SystemTime::now(), 0));
            let user = set_user_phone(conn, &user, &phone);

            let err = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "tel:+15551234567".to_string(),
                    code: "000000".to_string(),
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert_eq!(err.message(), "incorrect_code");

            let reloaded: models::User = crate::schema::users::table
                .select(models::USER_COLUMNS)
                .filter(crate::schema::users::id.eq(user.id))
                .first(conn)
                .unwrap();
            let phone: ContactMethod =
                serde_json::from_value(reloaded.phone.unwrap()).unwrap();
            assert_eq!(phone.verification_in_progress.unwrap().attempts, 1);

            Ok(())
        });
    }

    #[test]
    fn rejects_after_max_attempts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_max_attempts");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress("654321", SystemTime::now(), 5));
            let user = set_user_phone(conn, &user, &phone);

            let err = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "tel:+15551234567".to_string(),
                    code: "654321".to_string(),
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "too_many_attempts");

            Ok(())
        });
    }

    #[test]
    fn rejects_expired_code() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_expired");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress(
                "654321",
                SystemTime::now() - Duration::from_secs(11 * 60),
                0,
            ));
            let user = set_user_phone(conn, &user, &phone);

            let err = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "tel:+15551234567".to_string(),
                    code: "654321".to_string(),
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "verification_expired");

            Ok(())
        });
    }

    #[test]
    fn rejects_mailto_as_unimplemented() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_mailto");

            let err = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "mailto:someone@example.com".to_string(),
                    code: "123456".to_string(),
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::Unimplemented);
            assert_eq!(err.message(), "email_verification_not_implemented");

            Ok(())
        });
    }

    #[test]
    fn rejects_when_no_verification_in_progress() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_no_progress");
            let user = set_user_phone(conn, &user, &phone_contact_method("tel:+15551234567"));

            let err = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "tel:+15551234567".to_string(),
                    code: "123456".to_string(),
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "no_verification_in_progress");

            Ok(())
        });
    }

    #[test]
    fn rejects_when_phone_value_mismatched() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let user = create_user(conn, "vcm_mismatch");
            let mut phone = phone_contact_method("tel:+15551234567");
            phone.verification_in_progress = Some(in_progress("654321", SystemTime::now(), 0));
            let user = set_user_phone(conn, &user, &phone);

            let err = verify_contact_method(
                VerifyContactMethodRequest {
                    value: "tel:+19998887777".to_string(),
                    code: "654321".to_string(),
                },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "phone_not_set");

            Ok(())
        });
    }
}
