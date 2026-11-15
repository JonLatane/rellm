//! Specs for SMS/email login and verified account creation (`rpcs::login`/`rpcs::create_account`),
//! and email support in `StartContactMethodVerification`/`VerifyContactMethod`. SMS goes through a
//! mock provider (`factories::serve_capturing`); email through `logic::email_capture`, the
//! thread-local seam that stands in for a real email provider.

use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use diesel::prelude::*;
use tonic::Code;

use crate::logic::email_capture;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::{
    create_account_at, login_at, start_contact_method_verification_at, verify_contact_method,
};
use crate::schema::{pending_contact_verifications, users};
use crate::tests::factories::*;

const PHONE: &str = "tel:+15551234567";
const EMAIL: &str = "mailto:jon@example.com";

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

type Captured = Arc<Mutex<Vec<String>>>;

/// Twilio configured as the SMS provider, `features` enabled, and email capture started.
fn setup(conn: &mut crate::db_connection::PgPooledConnection, features: &[AuthenticationFeature]) {
    let mut config = models::default_server_configuration();
    config.twilio_config = Some(
        serde_json::to_value(TwilioConfig {
            twilio_enabled: true,
            twilio_account_sid: "AC_sid".to_string(),
            twilio_api_key_sid: "SK_sid".to_string(),
            twilio_api_key_secret: "secret".to_string(),
            twilio_from_number: "+15005550006".to_string(),
            twilio_webhook_signing_key: String::new(),
            use_twilio_webhook_signing_key: false,
        })
        .unwrap(),
    );
    config.supported_contact_protocols = Some(crate::logic::contact_protocols_to_json(&[
        ContactProtocol::Tel,
    ]));
    config.authentication_features = serde_json::to_value(
        features.iter().map(|f| f.as_str_name()).collect::<Vec<&str>>(),
    )
    .unwrap();
    diesel::insert_into(crate::schema::server_configurations::table)
        .values(&config)
        .execute(conn)
        .expect("failed to create test server configuration");
    email_capture::start();
}

const ALL_FEATURES: [AuthenticationFeature; 6] = [
    AuthenticationFeature::CreateAccountWithPassword,
    AuthenticationFeature::LoginWithPassword,
    AuthenticationFeature::LoginWithSms,
    AuthenticationFeature::LoginWithEmail,
    AuthenticationFeature::CreateAccountWithSms,
    AuthenticationFeature::CreateAccountWithEmail,
];

fn sms_mock() -> (String, Captured) {
    serve_capturing(|_request, _prior| {
        ("HTTP/1.1 201 Created", serde_json::json!({ "sid": "SM_test", "status": "queued" }))
    })
}

/// The 6-digit code in the SMS body of captured request `index`.
fn sms_code(captured: &Captured, index: usize) -> String {
    let requests = captured.lock().unwrap();
    let request = requests.get(index).expect("no such SMS was sent");
    let mut run = String::new();
    let mut runs = vec![];
    for c in request.chars().chain(std::iter::once(' ')) {
        if c.is_ascii_digit() {
            run.push(c);
        } else {
            if run.len() == 6 {
                runs.push(run.clone());
            }
            run.clear();
        }
    }
    assert_eq!(runs.len(), 1, "expected exactly one 6-digit run in {request}");
    runs.remove(0)
}

fn sms_count(captured: &Captured) -> usize {
    captured.lock().unwrap().len()
}

fn contact(value: &str, consent: ContactConsentState, verified: bool) -> ContactMethod {
    ContactMethod {
        value: Some(value.to_string()),
        visibility: Visibility::ServerPublic as i32,
        supported_by_server: false,
        verified_at: verified.then(|| SystemTime::now().to_proto()),
        verification_in_progress: None,
        consent_state: consent as i32,
        consent_history: vec![],
    }
}

fn granted(value: &str) -> ContactMethod {
    contact(value, ContactConsentState::ContactConsentGranted, false)
}

fn verified(value: &str) -> ContactMethod {
    contact(value, ContactConsentState::ContactConsentGranted, true)
}

fn set_user_email(
    conn: &mut crate::db_connection::PgPooledConnection,
    user: &models::User,
    cm: &ContactMethod,
) -> models::User {
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set(users::email.eq(serde_json::to_value(cm).unwrap()))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to set test user email")
}

fn reload(conn: &mut crate::db_connection::PgPooledConnection, user: &models::User) -> models::User {
    users::table
        .filter(users::id.eq(user.id))
        .select(models::USER_COLUMNS)
        .first(conn)
        .unwrap()
}

fn stored_phone(conn: &mut crate::db_connection::PgPooledConnection, user: &models::User) -> ContactMethod {
    serde_json::from_value(reload(conn, user).phone.unwrap()).unwrap()
}

fn stored_email(conn: &mut crate::db_connection::PgPooledConnection, user: &models::User) -> ContactMethod {
    serde_json::from_value(reload(conn, user).email.unwrap()).unwrap()
}

fn sms_login(phone: &str, code: Option<&str>, user_id: Option<String>) -> LoginRequest {
    LoginRequest {
        request: Some(login_request::Request::Sms(SmsLoginRequest {
            phone_number: phone.to_string(),
            code: code.map(|c| c.to_string()),
            expires_at: None,
            device_name: None,
            user_id,
        })),
    }
}

fn email_login(address: &str, code: Option<&str>, user_id: Option<String>) -> LoginRequest {
    LoginRequest {
        request: Some(login_request::Request::Email(EmailLoginRequest {
            email: address.to_string(),
            code: code.map(|c| c.to_string()),
            expires_at: None,
            device_name: None,
            user_id,
        })),
    }
}

fn password_login(username: &str, password: &str) -> LoginRequest {
    LoginRequest {
        request: Some(login_request::Request::UsernamePassword(UsernamePasswordLoginRequest {
            username: username.to_string(),
            password: password.to_string(),
            expires_at: None,
            device_name: None,
            user_id: None,
        })),
    }
}

fn account_request(
    username: &str,
    password: &str,
    phone: Option<ContactMethod>,
    email: Option<ContactMethod>,
) -> CreateAccountRequest {
    CreateAccountRequest {
        username: username.to_string(),
        password: password.to_string(),
        email,
        phone,
        expires_at: None,
        device_name: None,
        phone_verification_code: None,
        email_verification_code: None,
    }
}

fn pending_row(
    conn: &mut crate::db_connection::PgPooledConnection,
    value: &str,
) -> Option<models::PendingContactVerification> {
    models::find_pending_contact_verification(value, conn).unwrap()
}

fn age_pending_row(conn: &mut crate::db_connection::PgPooledConnection, value: &str, age: Duration) {
    diesel::update(
        pending_contact_verifications::table
            .filter(pending_contact_verifications::contact_value.eq(value)),
    )
    .set(pending_contact_verifications::sent_at.eq(SystemTime::now() - age))
    .execute(conn)
    .unwrap();
}

fn assert_challenge(response: &RefreshTokenResponse, sent_to: &[&str]) {
    assert!(response.refresh_token.is_none());
    assert!(response.access_token.is_none());
    assert!(response.user.is_none());
    let challenge = response.verification_challenge.as_ref().expect("expected a challenge");
    assert_eq!(challenge.sent_to, sent_to);
    assert!(challenge.expires_at.is_some());
    assert!(challenge.resend_available_at.is_some());
}

fn assert_logged_in(response: &RefreshTokenResponse, username: &str) {
    assert!(response.verification_challenge.is_none());
    assert!(response.refresh_token.is_some());
    assert!(response.access_token.is_some());
    assert_eq!(response.user.as_ref().unwrap().username, username);
}

// ---------------------------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------------------------

mod sms_login_spec {
    use super::*;

    #[test]
    fn happy_path_two_phases() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "sl_happy");
            let user = set_user_phone(conn, &user, &verified(PHONE));
            let (base_url, sms) = sms_mock();

            let phase1 = login_at(Some(&base_url), sms_login("+15551234567", None, None), conn).unwrap();
            assert_challenge(&phase1, &[PHONE]);
            assert_eq!(sms_count(&sms), 1);
            let code = sms_code(&sms, 0);
            assert!(stored_phone(conn, &user).verification_in_progress.is_some());

            let phase2 = login_at(
                Some(&base_url),
                // A leading `tel:` is accepted too.
                sms_login(PHONE, Some(&code), None),
                conn,
            )
            .unwrap();
            assert_logged_in(&phase2, "sl_happy");
            assert!(stored_phone(conn, &user).verification_in_progress.is_none());
            assert!(stored_phone(conn, &user).verified_at.is_some());
            Ok(())
        });
    }

    #[test]
    fn rejects_when_feature_disabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &[AuthenticationFeature::LoginWithPassword]);
            let user = create_user(conn, "sl_disabled");
            set_user_phone(conn, &user, &verified(PHONE));
            let (base_url, sms) = sms_mock();

            let err = login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "login_with_sms_not_enabled");
            assert_eq!(sms_count(&sms), 0);
            Ok(())
        });
    }

    #[test]
    fn rejects_when_sms_provider_not_configured() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            let mut config = models::default_server_configuration();
            config.authentication_features =
                serde_json::json!(["LOGIN_WITH_SMS"]);
            diesel::insert_into(crate::schema::server_configurations::table)
                .values(&config)
                .execute(conn)
                .unwrap();
            let err = login_at(None, sms_login(PHONE, None, None), conn).unwrap_err();
            assert_eq!(err.message(), "verification_not_configured");
            Ok(())
        });
    }

    #[test]
    fn rejects_malformed_phone_number() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let err = login_at(None, sms_login("555-1234", None, None), conn).unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            Ok(())
        });
    }

    /// Unknown contact, unverified contact, revoked consent, and an active resend cooldown must all
    /// look exactly like the real thing to the caller -- and only the real thing sends anything.
    #[test]
    fn first_phase_is_indistinguishable_for_every_non_sending_case() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();

            let real = create_user(conn, "sl_enum_real");
            set_user_phone(conn, &real, &verified("tel:+15550000001"));
            let unverified = create_user(conn, "sl_enum_unverified");
            set_user_phone(conn, &unverified, &granted("tel:+15550000002"));
            let revoked = create_user(conn, "sl_enum_revoked");
            set_user_phone(
                conn,
                &revoked,
                &contact("tel:+15550000003", ContactConsentState::ContactConsentRevoked, true),
            );
            let cooling = create_user(conn, "sl_enum_cooling");
            let mut cooling_phone = verified("tel:+15550000004");
            cooling_phone.verification_in_progress = Some(ContactMethodVerification {
                verification_code: "123456".to_string(),
                verification_started_at: Some(SystemTime::now().to_proto()),
                attempts: 0,
            });
            set_user_phone(conn, &cooling, &cooling_phone);

            let mut shapes = vec![];
            for number in [
                "tel:+15550000001", // real
                "tel:+15550000002", // unverified
                "tel:+15550000003", // consent revoked
                "tel:+15550000004", // cooldown
                "tel:+15550000099", // unknown
            ] {
                let response =
                    login_at(Some(&base_url), sms_login(number, None, None), conn).unwrap();
                assert_challenge(&response, &[number]);
                shapes.push(response);
            }
            assert_eq!(sms_count(&sms), 1, "only the real, consenting, not-cooling account is texted");
            // The cooling-down account's outstanding code is untouched.
            assert_eq!(
                stored_phone(conn, &cooling)
                    .verification_in_progress
                    .unwrap()
                    .verification_code,
                "123456"
            );
            // Same structure whichever branch ran: expiry/resend windows are `now`-relative for all.
            for shape in &shapes {
                let c = shape.verification_challenge.as_ref().unwrap();
                let expires: SystemTime = c.expires_at.as_ref().unwrap().to_db();
                assert!(expires > SystemTime::now() + Duration::from_secs(9 * 60));
                let resend: SystemTime = c.resend_available_at.as_ref().unwrap().to_db();
                assert!(resend > SystemTime::now() + Duration::from_secs(50));
            }
            Ok(())
        });
    }

    #[test]
    fn second_phase_for_unknown_contact_looks_like_a_wrong_code() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, _sms) = sms_mock();
            let user = create_user(conn, "sl_unknown_p2");
            set_user_phone(conn, &user, &verified(PHONE));
            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();

            let wrong_for_real =
                login_at(Some(&base_url), sms_login(PHONE, Some("000000"), None), conn).unwrap_err();
            let unknown = login_at(
                Some(&base_url),
                sms_login("tel:+15550000099", Some("000000"), None),
                conn,
            )
            .unwrap_err();
            assert_eq!(wrong_for_real.code(), unknown.code());
            assert_eq!(wrong_for_real.message(), unknown.message());
            assert_eq!(unknown.message(), "incorrect_code");
            Ok(())
        });
    }

    #[test]
    fn wrong_codes_are_counted_and_the_attempt_cap_locks_the_code() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "sl_attempts");
            let user = set_user_phone(conn, &user, &verified(PHONE));
            let (base_url, sms) = sms_mock();
            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            let code = sms_code(&sms, 0);
            let wrong = if code == "000000" { "000001" } else { "000000" };

            for attempt in 1..=5 {
                let err =
                    login_at(Some(&base_url), sms_login(PHONE, Some(wrong), None), conn).unwrap_err();
                assert_eq!(err.code(), Code::InvalidArgument);
                assert_eq!(err.message(), "incorrect_code");
                assert_eq!(
                    stored_phone(conn, &user).verification_in_progress.unwrap().attempts,
                    attempt
                );
            }
            // Even the right code no longer works after 5 wrong guesses -- and says the same thing.
            let err = login_at(Some(&base_url), sms_login(PHONE, Some(&code), None), conn).unwrap_err();
            assert_eq!(err.message(), "incorrect_code");
            // The exhausted record is KEPT (code burned, original send time preserved) so the
            // resend cooldown still applies...
            let kept = stored_phone(conn, &user).verification_in_progress.expect("exhausted record kept");
            assert_eq!(kept.verification_code, "");
            assert_eq!(kept.attempts, 5);
            // ...i.e. burning guesses can't buy an immediate fresh code.
            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            assert_eq!(sms_count(&sms), 1, "no new SMS inside the cooldown, even after exhaustion");
            // And the right code stays dead.
            let err = login_at(Some(&base_url), sms_login(PHONE, Some(&code), None), conn).unwrap_err();
            assert_eq!(err.message(), "incorrect_code");
            Ok(())
        });
    }

    #[test]
    fn expired_code_is_rejected_and_cleared() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "sl_expired");
            let mut phone = verified(PHONE);
            phone.verification_in_progress = Some(ContactMethodVerification {
                verification_code: "424242".to_string(),
                verification_started_at: Some((SystemTime::now() - Duration::from_secs(11 * 60)).to_proto()),
                attempts: 0,
            });
            let user = set_user_phone(conn, &user, &phone);

            let err = login_at(None, sms_login(PHONE, Some("424242"), None), conn).unwrap_err();
            assert_eq!(err.message(), "incorrect_code");
            assert!(stored_phone(conn, &user).verification_in_progress.is_none());
            Ok(())
        });
    }

    #[test]
    fn second_phase_without_an_outstanding_code_fails() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "sl_no_code");
            set_user_phone(conn, &user, &verified(PHONE));
            let err = login_at(None, sms_login(PHONE, Some("123456"), None), conn).unwrap_err();
            assert_eq!(err.message(), "incorrect_code");
            Ok(())
        });
    }

    #[test]
    fn resend_cooldown_keeps_the_first_code() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "sl_cooldown");
            let user = set_user_phone(conn, &user, &verified(PHONE));
            let (base_url, sms) = sms_mock();

            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            let again = login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            assert_challenge(&again, &[PHONE]);
            assert_eq!(sms_count(&sms), 1);

            let code = sms_code(&sms, 0);
            assert_eq!(
                stored_phone(conn, &user).verification_in_progress.unwrap().verification_code,
                code
            );
            let ok = login_at(Some(&base_url), sms_login(PHONE, Some(&code), None), conn).unwrap();
            assert_logged_in(&ok, "sl_cooldown");
            Ok(())
        });
    }

    #[test]
    fn a_new_code_can_be_sent_after_the_cooldown() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "sl_resend");
            let mut phone = verified(PHONE);
            phone.verification_in_progress = Some(ContactMethodVerification {
                verification_code: "111111".to_string(),
                verification_started_at: Some((SystemTime::now() - Duration::from_secs(120)).to_proto()),
                attempts: 3,
            });
            let user = set_user_phone(conn, &user, &phone);
            let (base_url, sms) = sms_mock();

            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            assert_eq!(sms_count(&sms), 1);
            let stored = stored_phone(conn, &user).verification_in_progress.unwrap();
            assert_eq!(stored.attempts, 0);
            assert_eq!(stored.verification_code, sms_code(&sms, 0));
            Ok(())
        });
    }

    #[test]
    fn two_accounts_with_the_same_verified_phone_need_a_user_id() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let first = create_user(conn, "sl_multi_a");
            set_user_phone(conn, &first, &verified(PHONE));
            let second = create_user(conn, "sl_multi_b");
            set_user_phone(conn, &second, &verified(PHONE));
            let (base_url, sms) = sms_mock();

            let err = login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap_err();
            assert_eq!(err.message(), "multiple_accounts_for_contact");
            assert_eq!(sms_count(&sms), 0);

            let second_id = Some(second.id.to_proto_id());
            login_at(Some(&base_url), sms_login(PHONE, None, second_id.clone()), conn).unwrap();
            assert_eq!(sms_count(&sms), 1);
            let code = sms_code(&sms, 0);
            let ok = login_at(Some(&base_url), sms_login(PHONE, Some(&code), second_id), conn).unwrap();
            assert_logged_in(&ok, "sl_multi_b");
            Ok(())
        });
    }
}

mod email_login_spec {
    use super::*;

    #[test]
    fn happy_path_is_case_insensitive() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "el_happy");
            let user = set_user_email(conn, &user, &verified("mailto:Jon@Example.com"));

            let phase1 = login_at(None, email_login("JON@EXAMPLE.COM", None, None), conn).unwrap();
            assert_challenge(&phase1, &["mailto:jon@example.com"]);
            let sent = email_capture::sent();
            assert_eq!(sent.len(), 1);
            assert_eq!(sent[0].0, "mailto:Jon@Example.com", "sent to the address as stored");
            let code = sent[0].1.clone();

            let phase2 =
                login_at(None, email_login("mailto:jon@example.com", Some(&code), None), conn).unwrap();
            assert_logged_in(&phase2, "el_happy");
            assert!(stored_email(conn, &user).verification_in_progress.is_none());
            Ok(())
        });
    }

    #[test]
    fn rejects_when_feature_disabled() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &[AuthenticationFeature::LoginWithSms]);
            let err = login_at(None, email_login(EMAIL, None, None), conn).unwrap_err();
            assert_eq!(err.message(), "login_with_email_not_enabled");
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn unknown_and_unverified_addresses_get_the_same_challenge_and_no_mail() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let unverified = create_user(conn, "el_unverified");
            set_user_email(conn, &unverified, &granted("mailto:unverified@example.com"));

            for address in ["unverified@example.com", "nobody@example.com"] {
                let response = login_at(None, email_login(address, None, None), conn).unwrap();
                assert_challenge(&response, &[&format!("mailto:{address}")]);
            }
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn consent_revoked_sends_nothing() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "el_revoked");
            set_user_email(
                conn,
                &user,
                &contact(EMAIL, ContactConsentState::ContactConsentRevoked, true),
            );
            let response = login_at(None, email_login(EMAIL, None, None), conn).unwrap();
            assert_challenge(&response, &[EMAIL]);
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn rejects_malformed_address() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            for bad in ["not-an-email", "a@b", "@example.com", "a b@example.com", "a@@example.com"] {
                let err = login_at(None, email_login(bad, None, None), conn).unwrap_err();
                assert_eq!(err.code(), Code::InvalidArgument, "{bad}");
            }
            Ok(())
        });
    }

    #[test]
    fn multiple_accounts_need_a_user_id() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let first = create_user(conn, "el_multi_a");
            set_user_email(conn, &first, &verified(EMAIL));
            let second = create_user(conn, "el_multi_b");
            set_user_email(conn, &second, &verified("mailto:JON@example.com"));

            let err = login_at(None, email_login(EMAIL, None, None), conn).unwrap_err();
            assert_eq!(err.message(), "multiple_accounts_for_contact");

            let wanted = Some(first.id.to_proto_id());
            login_at(None, email_login(EMAIL, None, wanted.clone()), conn).unwrap();
            let code = email_capture::sent()[0].1.clone();
            let ok = login_at(None, email_login(EMAIL, Some(&code), wanted), conn).unwrap();
            assert_logged_in(&ok, "el_multi_a");
            Ok(())
        });
    }
}

// ---------------------------------------------------------------------------------------------
// Account creation
// ---------------------------------------------------------------------------------------------

mod create_account_spec {
    use super::*;

    #[test]
    fn sms_happy_path_with_password() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_sms", "password123", Some(granted(PHONE)), None);

            let phase1 = create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            assert_challenge(&phase1, &[PHONE]);
            assert_eq!(sms_count(&sms), 1);
            let code = sms_code(&sms, 0);
            let row = pending_row(conn, PHONE).expect("pending row");
            assert_ne!(row.code_hash, code, "only a hash is stored");
            assert_eq!(row.code_hash, crate::logic::hash_code(PHONE, &code));
            assert!(
                users::table
                    .filter(users::username.eq("ca_sms"))
                    .count()
                    .get_result::<i64>(conn)
                    .unwrap()
                    == 0,
                "no account before the code is entered"
            );

            let phase2 = create_account_at(
                Some(&base_url),
                CreateAccountRequest { phone_verification_code: Some(code), ..request },
                conn,
            )
            .unwrap();
            assert_logged_in(&phase2, "ca_sms");
            let user_id = phase2.user.as_ref().unwrap().id.to_db_id_or_err("id").unwrap();
            let user = users::table
                .filter(users::id.eq(user_id))
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .unwrap();
            let phone = stored_phone(conn, &user);
            assert_eq!(phone.value.as_deref(), Some(PHONE));
            assert!(phone.verified_at.is_some());
            assert!(phone.supported_by_server);
            assert_eq!(phone.consent_state, ContactConsentState::ContactConsentGranted as i32);
            assert_eq!(
                phone.consent_history.last().map(|c| c.state),
                Some(ContactConsentState::ContactConsentGranted as i32)
            );
            assert!(pending_row(conn, PHONE).is_none(), "pending row cleaned up");

            // The password works too.
            let ok = login_at(None, password_login("ca_sms", "password123"), conn).unwrap();
            assert_logged_in(&ok, "ca_sms");
            Ok(())
        });
    }

    #[test]
    fn passwordless_email_account_logs_in_by_email_but_never_by_password() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let request = account_request("ca_nopass", "", None, Some(granted("mailto:New.User@Example.com")));

            let phase1 = create_account_at(None, request.clone(), conn).unwrap();
            assert_challenge(&phase1, &["mailto:new.user@example.com"]);
            let sent = email_capture::sent();
            assert_eq!(sent.len(), 1);
            assert_eq!(sent[0].0, "mailto:new.user@example.com");

            let phase2 = create_account_at(
                None,
                CreateAccountRequest { email_verification_code: Some(sent[0].1.clone()), ..request },
                conn,
            )
            .unwrap();
            assert_logged_in(&phase2, "ca_nopass");

            // Email login works (case-insensitively), now that the address is verified.
            login_at(None, email_login("new.user@example.com", None, None), conn).unwrap();
            let code = email_capture::sent()[1].1.clone();
            let ok = login_at(None, email_login("NEW.USER@example.com", Some(&code), None), conn).unwrap();
            assert_logged_in(&ok, "ca_nopass");

            // ...but no password -- empty, guessable, or the (unknowable) stored hash -- ever does.
            for password in ["", "password", "password123", "00000000"] {
                let result = login_at(None, password_login("ca_nopass", password), conn);
                assert!(result.is_err(), "password {password:?} must not log into a passwordless account");
            }
            let user = users::table
                .filter(users::username.eq("ca_nopass"))
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .unwrap();
            let hash = user.password_salted_hash.clone();
            let err = login_at(None, password_login("ca_nopass", &hash), conn).unwrap_err();
            assert_eq!(err.code(), Code::PermissionDenied);
            Ok(())
        });
    }

    #[test]
    fn phone_and_email_both_need_their_codes() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_both", "", Some(granted(PHONE)), Some(granted(EMAIL)));

            let phase1 = create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            assert_challenge(&phase1, &[PHONE, EMAIL]);
            let phone_code = sms_code(&sms, 0);
            let email_code = email_capture::sent()[0].1.clone();

            // Only one code: refused, and no account.
            let err = create_account_at(
                Some(&base_url),
                CreateAccountRequest {
                    phone_verification_code: Some(phone_code.clone()),
                    ..request.clone()
                },
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "email_verification_code_required");
            assert!(pending_row(conn, PHONE).is_some(), "valid code not consumed by a failed attempt");

            let ok = create_account_at(
                Some(&base_url),
                CreateAccountRequest {
                    phone_verification_code: Some(phone_code),
                    email_verification_code: Some(email_code),
                    ..request
                },
                conn,
            )
            .unwrap();
            assert_logged_in(&ok, "ca_both");
            let user_id = ok.user.as_ref().unwrap().id.to_db_id_or_err("id").unwrap();
            let user = users::table
                .filter(users::id.eq(user_id))
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .unwrap();
            assert!(stored_phone(conn, &user).verified_at.is_some());
            assert!(stored_email(conn, &user).verified_at.is_some());
            assert!(pending_row(conn, PHONE).is_none());
            assert!(pending_row(conn, EMAIL).is_none());
            Ok(())
        });
    }

    #[test]
    fn without_the_feature_contacts_are_saved_unverified_as_before() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(
                conn,
                &[
                    AuthenticationFeature::CreateAccountWithPassword,
                    AuthenticationFeature::LoginWithPassword,
                ],
            );
            let (base_url, sms) = sms_mock();
            let response = create_account_at(
                Some(&base_url),
                account_request("ca_classic", "password123", Some(granted(PHONE)), Some(granted(EMAIL))),
                conn,
            )
            .unwrap();
            assert_logged_in(&response, "ca_classic");
            assert_eq!(sms_count(&sms), 0);
            assert!(email_capture::sent().is_empty());
            let user_id = response.user.as_ref().unwrap().id.to_db_id_or_err("id").unwrap();
            let user = users::table
                .filter(users::id.eq(user_id))
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .unwrap();
            assert!(stored_phone(conn, &user).verified_at.is_none());
            assert!(stored_email(conn, &user).verified_at.is_none());
            Ok(())
        });
    }

    #[test]
    fn email_only_account_validates_the_email_not_as_a_phone() {
        // Regression: `create_account` used to run `validate_phone` on `email.value`.
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &[AuthenticationFeature::CreateAccountWithPassword]);
            let response = create_account_at(
                None,
                account_request("ca_email_classic", "password123", None, Some(granted(EMAIL))),
                conn,
            )
            .unwrap();
            assert_logged_in(&response, "ca_email_classic");
            Ok(())
        });
    }

    #[test]
    fn passwordless_requires_a_contact_and_its_feature() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &[AuthenticationFeature::CreateAccountWithEmail]);
            // No contact at all: it's still a password problem.
            let err = create_account_at(None, account_request("ca_np1", "", None, None), conn).unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            // A phone, but SMS signup isn't enabled.
            let err = create_account_at(
                None,
                account_request("ca_np2", "", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "create_account_with_sms_not_enabled");
            Ok(())
        });
    }

    /// A passwordless account's only way in is SMS/email login, so signup needs that login
    /// feature on, not just the signup one.
    #[test]
    fn passwordless_requires_a_login_feature_for_one_of_its_contacts() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(
                conn,
                &[
                    AuthenticationFeature::CreateAccountWithEmail,
                    AuthenticationFeature::CreateAccountWithSms,
                    AuthenticationFeature::LoginWithSms,
                ],
            );
            let (base_url, sms) = sms_mock();
            let err = create_account_at(
                Some(&base_url),
                account_request("ca_nologin", "", None, Some(granted(EMAIL))),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::FailedPrecondition);
            assert_eq!(err.message(), "login_with_email_not_enabled");
            assert!(email_capture::sent().is_empty(), "nothing sent for an account nobody could log into");
            // The same server is fine with a phone (LOGIN_WITH_SMS is on)...
            let ok = create_account_at(
                Some(&base_url),
                account_request("ca_nologin", "", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap();
            assert_challenge(&ok, &[PHONE]);
            // ...and with both, one loginable contact is enough.
            let both = create_account_at(
                Some(&base_url),
                account_request("ca_nologin2", "", Some(granted("tel:+15557654321")), Some(granted(EMAIL))),
                conn,
            )
            .unwrap();
            assert_challenge(&both, &["tel:+15557654321", EMAIL]);
            assert_eq!(sms_count(&sms), 2);
            // A password account doesn't need a login feature for its contacts.
            let with_password = create_account_at(
                Some(&base_url),
                account_request("ca_haspw", "password123", None, Some(granted("mailto:other@example.com"))),
                conn,
            )
            .unwrap();
            assert_challenge(&with_password, &["mailto:other@example.com"]);
            Ok(())
        });
    }

    #[test]
    fn password_is_still_validated_when_given() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let err = create_account_at(
                None,
                account_request("ca_shortpw", "short", None, Some(granted(EMAIL))),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::InvalidArgument);
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn requires_consent_before_sending() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            for state in [ContactConsentState::ContactConsentRevoked] {
                let err = create_account_at(
                    Some(&base_url),
                    account_request("ca_noconsent", "password123", Some(contact(PHONE, state, false)), None),
                    conn,
                )
                .unwrap_err();
                assert_eq!(err.message(), "contact_consent_not_granted");
            }
            assert_eq!(sms_count(&sms), 0);
            assert!(pending_row(conn, PHONE).is_none());
            Ok(())
        });
    }

    #[test]
    fn rejects_a_contact_already_verified_on_another_account() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let owner = create_user(conn, "ca_dup_owner");
            set_user_phone(conn, &owner, &verified(PHONE));
            set_user_email(conn, &owner, &verified("mailto:Jon@Example.com"));
            let (base_url, sms) = sms_mock();

            let err = create_account_at(
                Some(&base_url),
                account_request("ca_dup", "password123", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "contact_already_verified");
            let err = create_account_at(
                Some(&base_url),
                account_request("ca_dup", "password123", None, Some(granted(EMAIL))),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "contact_already_verified");
            assert_eq!(sms_count(&sms), 0);
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn an_unverified_contact_elsewhere_does_not_block() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let other = create_user(conn, "ca_unv_other");
            set_user_phone(conn, &other, &granted(PHONE));
            let (base_url, _sms) = sms_mock();
            let response = create_account_at(
                Some(&base_url),
                account_request("ca_unv", "password123", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap();
            assert_challenge(&response, &[PHONE]);
            Ok(())
        });
    }

    #[test]
    fn username_taken_is_reported_before_anything_is_sent() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            create_user(conn, "ca_taken");
            let (base_url, sms) = sms_mock();
            let err = create_account_at(
                Some(&base_url),
                account_request("ca_taken", "password123", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::AlreadyExists);
            assert_eq!(err.message(), "username_already_exists");
            assert_eq!(sms_count(&sms), 0);
            assert!(pending_row(conn, PHONE).is_none());
            Ok(())
        });
    }

    #[test]
    fn username_taken_between_phases_is_still_caught() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_race", "password123", Some(granted(PHONE)), None);
            create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            let code = sms_code(&sms, 0);
            create_user(conn, "ca_race");
            let err = create_account_at(
                Some(&base_url),
                CreateAccountRequest { phone_verification_code: Some(code), ..request },
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "username_already_exists");
            Ok(())
        });
    }

    #[test]
    fn wrong_codes_are_counted_then_the_row_is_kept_exhausted() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_wrong", "password123", Some(granted(PHONE)), None);
            create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            let code = sms_code(&sms, 0);
            let wrong = if code == "000000" { "000001" } else { "000000" };
            let with = |c: &str| CreateAccountRequest {
                phone_verification_code: Some(c.to_string()),
                ..request.clone()
            };

            for attempt in 1..=5 {
                let err = create_account_at(Some(&base_url), with(wrong), conn).unwrap_err();
                assert_eq!(err.message(), "incorrect_code");
                assert_eq!(pending_row(conn, PHONE).unwrap().attempts, attempt);
            }
            let err = create_account_at(Some(&base_url), with(&code), conn).unwrap_err();
            assert_eq!(err.message(), "too_many_attempts");
            assert!(pending_row(conn, PHONE).is_some(), "exhausted row is kept for the cooldown");
            let err = create_account_at(Some(&base_url), with(&code), conn).unwrap_err();
            assert_eq!(err.message(), "too_many_attempts");
            // A new first phase right away is refused (cooldown), so guesses can't be burned to
            // get a fresh code immediately...
            let err = create_account_at(Some(&base_url), request.clone(), conn).unwrap_err();
            assert_eq!(err.message(), "verification_recently_sent");
            assert_eq!(sms_count(&sms), 1);
            // ...but once the cooldown has passed one works, and the new code is good.
            age_pending_row(conn, PHONE, Duration::from_secs(61));
            create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            let fresh = sms_code(&sms, 1);
            let ok = create_account_at(Some(&base_url), with(&fresh), conn).unwrap();
            assert_logged_in(&ok, "ca_wrong");
            Ok(())
        });
    }

    #[test]
    fn expired_code_is_rejected_and_deleted() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_expired", "password123", Some(granted(PHONE)), None);
            create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            let code = sms_code(&sms, 0);
            age_pending_row(conn, PHONE, Duration::from_secs(11 * 60));

            let err = create_account_at(
                Some(&base_url),
                CreateAccountRequest { phone_verification_code: Some(code), ..request.clone() },
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "verification_expired");
            assert!(pending_row(conn, PHONE).is_none());

            // A fresh first phase works again.
            let again = create_account_at(Some(&base_url), request, conn).unwrap();
            assert_challenge(&again, &[PHONE]);
            Ok(())
        });
    }

    #[test]
    fn second_phase_without_a_first_fails() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let err = create_account_at(
                None,
                CreateAccountRequest {
                    phone_verification_code: Some("123456".to_string()),
                    ..account_request("ca_nofirst", "password123", Some(granted(PHONE)), None)
                },
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "no_verification_in_progress");
            Ok(())
        });
    }

    #[test]
    fn resend_cooldown_applies_per_contact() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_cool", "password123", Some(granted(PHONE)), None);
            create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            let err = create_account_at(Some(&base_url), request.clone(), conn).unwrap_err();
            assert_eq!(err.message(), "verification_recently_sent");
            assert_eq!(sms_count(&sms), 1);

            age_pending_row(conn, PHONE, Duration::from_secs(61));
            create_account_at(Some(&base_url), request, conn).unwrap();
            assert_eq!(sms_count(&sms), 2);
            // The newer code replaced the older one.
            assert_eq!(
                pending_row(conn, PHONE).unwrap().code_hash,
                crate::logic::hash_code(PHONE, &sms_code(&sms, 1))
            );
            Ok(())
        });
    }

    #[test]
    fn global_hourly_cap_refuses_new_sends() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            for i in 0..200 {
                models::record_contact_verification_send(&format!("tel:+1666000{i:04}"), conn).unwrap();
            }
            // Exactly 200 in the last hour is still allowed...
            create_account_at(
                Some(&base_url),
                account_request("ca_cap1", "password123", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap();
            assert_eq!(sms_count(&sms), 1);
            // ...but now there are 201.
            let err = create_account_at(
                Some(&base_url),
                account_request("ca_cap2", "password123", Some(granted("tel:+15557654321")), None),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.code(), Code::ResourceExhausted);
            assert_eq!(err.message(), "too_many_verification_requests");
            assert_eq!(sms_count(&sms), 1);

            // Old sends age out of the window (and the cleanup job's helper drops them).
            diesel::update(crate::schema::contact_verification_sends::table)
                .set(crate::schema::contact_verification_sends::sent_at.eq(SystemTime::now() - Duration::from_secs(2 * 3600)))
                .execute(conn)
                .unwrap();
            create_account_at(
                Some(&base_url),
                account_request("ca_cap2", "password123", Some(granted("tel:+15557654321")), None),
                conn,
            )
            .unwrap();
            let deleted = models::delete_old_contact_verification_sends(Duration::from_secs(3600), conn).unwrap();
            assert_eq!(deleted, 201, "every aged send (200 seeded + the first signup) but not the fresh one");
            Ok(())
        });
    }

    /// The cap counts every send, not pending rows: resends overwrite one row, so 3 sends to one
    /// number used to count as 1.
    #[test]
    fn global_cap_counts_resends_to_one_contact_separately() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            for i in 0..198 {
                models::record_contact_verification_send(&format!("tel:+1666000{i:04}"), conn).unwrap();
            }
            let request = account_request("ca_resends", "password123", Some(granted(PHONE)), None);
            for _ in 0..3 {
                // 198 -> 199 -> 200 -> 201: the third send still starts from 200 (allowed)...
                create_account_at(Some(&base_url), request.clone(), conn).unwrap();
                age_pending_row(conn, PHONE, Duration::from_secs(61));
            }
            assert_eq!(sms_count(&sms), 3);
            assert_eq!(pending_row(conn, PHONE).iter().count(), 1, "one pending row for three sends");
            // ...and the fourth finds 201 sends in the ledger and is refused.
            let err = create_account_at(Some(&base_url), request, conn).unwrap_err();
            assert_eq!(err.message(), "too_many_verification_requests");
            assert_eq!(sms_count(&sms), 3);
            Ok(())
        });
    }

    #[test]
    fn per_contact_hourly_cap_applies_to_signup_login_and_verify() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            for _ in 0..10 {
                models::record_contact_verification_send("TEL:+15551234567", conn).unwrap();
            }
            // Signup: reported.
            let err = create_account_at(
                Some(&base_url),
                account_request("ca_pcap", "password123", Some(granted(PHONE)), None),
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "too_many_verification_requests");
            // Login: silent (same challenge, nothing sent).
            let user = create_user(conn, "ca_pcap_user");
            let user = set_user_phone(conn, &user, &verified(PHONE));
            let response = login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            assert_challenge(&response, &[PHONE]);
            // Authenticated start: reported.
            let err = start_contact_method_verification_at(Some(&base_url), granted(PHONE), &user, conn)
                .unwrap_err();
            assert_eq!(err.message(), "too_many_verification_requests");
            assert_eq!(sms_count(&sms), 0);
            Ok(())
        });
    }

    #[test]
    fn email_is_not_sent_when_email_signup_is_the_only_unconfigured_piece() {
        // Email signup enabled but SMS signup not: phone is saved unverified, email is verified.
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &[AuthenticationFeature::CreateAccountWithEmail]);
            let (base_url, sms) = sms_mock();
            let request = account_request("ca_mixed", "password123", Some(granted(PHONE)), Some(granted(EMAIL)));
            let phase1 = create_account_at(Some(&base_url), request.clone(), conn).unwrap();
            assert_challenge(&phase1, &[EMAIL]);
            assert_eq!(sms_count(&sms), 0);
            let code = email_capture::sent()[0].1.clone();
            let ok = create_account_at(
                Some(&base_url),
                CreateAccountRequest { email_verification_code: Some(code), ..request },
                conn,
            )
            .unwrap();
            let user_id = ok.user.as_ref().unwrap().id.to_db_id_or_err("id").unwrap();
            let user = users::table
                .filter(users::id.eq(user_id))
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .unwrap();
            assert!(stored_email(conn, &user).verified_at.is_some());
            assert!(stored_phone(conn, &user).verified_at.is_none());
            Ok(())
        });
    }
}

// ---------------------------------------------------------------------------------------------
// StartContactMethodVerification / VerifyContactMethod for email
// ---------------------------------------------------------------------------------------------

mod email_contact_verification_spec {
    use super::*;

    #[test]
    fn start_and_verify_an_email() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "ecv_happy");
            let user = set_user_email(conn, &user, &granted("mailto:Jon@Example.com"));

            let started = start_contact_method_verification_at(
                None,
                granted("mailto:jon@example.com"),
                &user,
                conn,
            )
            .unwrap();
            assert_eq!(started.verification_in_progress.as_ref().unwrap().verification_code, "");
            let sent = email_capture::sent();
            assert_eq!(sent.len(), 1);

            // Cooldown.
            let user = reload(conn, &user);
            let err = start_contact_method_verification_at(None, granted(EMAIL), &user, conn).unwrap_err();
            assert_eq!(err.message(), "verification_recently_sent");

            let user = reload(conn, &user);
            let err = verify_contact_method(
                VerifyContactMethodRequest { value: EMAIL.to_string(), code: "nope".to_string() },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "incorrect_code");

            let user = reload(conn, &user);
            let verified = verify_contact_method(
                VerifyContactMethodRequest { value: EMAIL.to_string(), code: sent[0].1.clone() },
                &user,
                conn,
            )
            .unwrap();
            assert!(verified.verified_at.is_some());
            assert!(verified.verification_in_progress.is_none());
            assert!(stored_email(conn, &user).verified_at.is_some());
            Ok(())
        });
    }

    #[test]
    fn requires_consent() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "ecv_noconsent");
            let user = set_user_email(
                conn,
                &user,
                &contact(EMAIL, ContactConsentState::ContactConsentRevoked, false),
            );
            let err = start_contact_method_verification_at(None, granted(EMAIL), &user, conn).unwrap_err();
            assert_eq!(err.message(), "contact_consent_not_granted");
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn verification_is_refused_when_another_account_already_verified_the_contact() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let owner = create_user(conn, "ecv_owner");
            set_user_email(conn, &owner, &verified(EMAIL));
            let user = create_user(conn, "ecv_latecomer");
            let mut email = granted(EMAIL);
            email.verification_in_progress = Some(ContactMethodVerification {
                verification_code: "654321".to_string(),
                verification_started_at: Some(SystemTime::now().to_proto()),
                attempts: 0,
            });
            let user = set_user_email(conn, &user, &email);

            let err = verify_contact_method(
                VerifyContactMethodRequest { value: EMAIL.to_string(), code: "654321".to_string() },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "contact_already_verified");
            assert!(stored_email(conn, &user).verified_at.is_none());

            // ...and starting is refused up front too, so no mail is wasted.
            let user = set_user_email(conn, &user, &granted(EMAIL));
            let err = start_contact_method_verification_at(None, granted(EMAIL), &user, conn).unwrap_err();
            assert_eq!(err.message(), "contact_already_verified");
            assert!(email_capture::sent().is_empty());
            Ok(())
        });
    }

    #[test]
    fn phone_verification_is_refused_when_another_account_already_verified_the_number() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let owner = create_user(conn, "pcv_owner");
            set_user_phone(conn, &owner, &verified(PHONE));
            let user = create_user(conn, "pcv_latecomer");
            let mut phone = granted(PHONE);
            phone.verification_in_progress = Some(ContactMethodVerification {
                verification_code: "654321".to_string(),
                verification_started_at: Some(SystemTime::now().to_proto()),
                attempts: 0,
            });
            let user = set_user_phone(conn, &user, &phone);
            let err = verify_contact_method(
                VerifyContactMethodRequest { value: PHONE.to_string(), code: "654321".to_string() },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "contact_already_verified");
            Ok(())
        });
    }
}

// ---------------------------------------------------------------------------------------------
// Server-owned ContactMethod fields can't be forged by clients
// ---------------------------------------------------------------------------------------------

mod forged_server_owned_fields_spec {
    use super::*;

    fn forged_phone() -> ContactMethod {
        ContactMethod {
            value: Some(PHONE.to_string()),
            visibility: Visibility::ServerPublic as i32,
            supported_by_server: false,
            verified_at: Some(SystemTime::now().to_proto()),
            verification_in_progress: Some(ContactMethodVerification {
                verification_code: "123456".to_string(),
                verification_started_at: Some(SystemTime::now().to_proto()),
                attempts: 0,
            }),
            consent_state: ContactConsentState::ContactConsentGranted as i32,
            consent_history: vec![ContactConsentChange {
                state: ContactConsentState::ContactConsentGranted as i32,
                changed_at: Some((SystemTime::now() - Duration::from_secs(86400 * 365)).to_proto()),
            }],
        }
    }

    #[test]
    fn unverified_signup_contacts_cannot_carry_verified_at_or_a_chosen_code() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            // Signup-by-SMS is off, so the phone is saved unverified "as given" -- minus anything
            // the server owns.
            setup(
                conn,
                &[
                    AuthenticationFeature::CreateAccountWithPassword,
                    AuthenticationFeature::LoginWithPassword,
                    AuthenticationFeature::LoginWithSms,
                ],
            );
            let (base_url, sms) = sms_mock();
            let mut forged_email = forged_phone();
            forged_email.value = Some(EMAIL.to_string());
            let response = create_account_at(
                Some(&base_url),
                account_request("ca_forge", "password123", Some(forged_phone()), Some(forged_email)),
                conn,
            )
            .unwrap();
            let user_id = response.user.as_ref().unwrap().id.to_db_id_or_err("id").unwrap();
            let user = users::table
                .filter(users::id.eq(user_id))
                .select(models::USER_COLUMNS)
                .first::<models::User>(conn)
                .unwrap();
            for stored in [stored_phone(conn, &user), stored_email(conn, &user)] {
                assert!(stored.verified_at.is_none(), "verified_at is server-owned");
                assert!(stored.verification_in_progress.is_none(), "so is verification_in_progress");
                // History is built by the server: one fresh entry for the granted consent, not the
                // forged year-old one.
                assert_eq!(stored.consent_history.len(), 1);
                let changed: SystemTime = stored.consent_history[0].changed_at.as_ref().unwrap().to_db();
                assert!(changed > SystemTime::now() - Duration::from_secs(60));
                assert_eq!(stored.consent_state, ContactConsentState::ContactConsentGranted as i32);
            }
            // supported_by_server is recomputed: SMS is configured, email isn't.
            assert!(stored_phone(conn, &user).supported_by_server);
            assert!(!stored_email(conn, &user).supported_by_server);

            // The chosen code "123456" gets nobody into the account...
            let err = login_at(Some(&base_url), sms_login(PHONE, Some("123456"), None), conn).unwrap_err();
            assert_eq!(err.message(), "incorrect_code");
            // ...and phase 1 finds no *verified* contact, so it sends nothing.
            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            assert_eq!(sms_count(&sms), 0);
            Ok(())
        });
    }

    #[test]
    fn copying_a_verified_contact_does_not_create_a_second_verified_owner() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(
                conn,
                &[
                    AuthenticationFeature::CreateAccountWithPassword,
                    AuthenticationFeature::LoginWithSms,
                ],
            );
            let owner = create_user(conn, "ca_copy_owner");
            set_user_phone(conn, &owner, &verified(PHONE));
            let response = create_account_at(
                None,
                account_request("ca_copy_thief", "password123", Some(forged_phone()), None),
                conn,
            )
            .unwrap();
            assert_logged_in(&response, "ca_copy_thief");
            let owners = crate::logic::find_users_with_verified_contact(
                conn,
                crate::logic::ContactKind::Phone,
                PHONE,
            )
            .unwrap();
            assert_eq!(owners.len(), 1);
            assert_eq!(owners[0].0.username, "ca_copy_owner");
            Ok(())
        });
    }

    #[test]
    fn update_user_cannot_set_verified_at_or_verification_in_progress() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "uu_forge");
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(forged_phone());
            let updated = crate::rpcs::update_user(request, &user, conn).unwrap();
            let phone = updated.phone.unwrap();
            assert!(phone.verified_at.is_none());
            assert!(phone.verification_in_progress.is_none());
            let user = reload(conn, &user);
            assert!(stored_phone(conn, &user).verified_at.is_none());
            assert!(stored_phone(conn, &user).verification_in_progress.is_none());

            // Same when the value is unchanged and the stored contact already exists.
            let mut request = user.to_proto(&None, &None, None, &Some(&user), None);
            request.phone = Some(forged_phone());
            crate::rpcs::update_user(request, &user, conn).unwrap();
            let user = reload(conn, &user);
            assert!(stored_phone(conn, &user).verified_at.is_none());
            assert!(stored_phone(conn, &user).verification_in_progress.is_none());
            Ok(())
        });
    }
}

// ---------------------------------------------------------------------------------------------
// Cooldown survives exhaustion (authenticated flow)
// ---------------------------------------------------------------------------------------------

mod exhausted_code_cooldown_spec {
    use super::*;

    #[test]
    fn start_is_refused_inside_the_cooldown_after_the_code_is_exhausted() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let (base_url, sms) = sms_mock();
            let user = create_user(conn, "ecc_start");
            let user = set_user_phone(conn, &user, &granted(PHONE));
            start_contact_method_verification_at(Some(&base_url), granted(PHONE), &user, conn).unwrap();
            let code = sms_code(&sms, 0);
            let wrong = if code == "000000" { "000001" } else { "000000" };
            for _ in 0..5 {
                let user = reload(conn, &user);
                let err = verify_contact_method(
                    VerifyContactMethodRequest { value: PHONE.to_string(), code: wrong.to_string() },
                    &user,
                    conn,
                )
                .unwrap_err();
                assert_eq!(err.message(), "incorrect_code");
            }
            let user = reload(conn, &user);
            let err = verify_contact_method(
                VerifyContactMethodRequest { value: PHONE.to_string(), code },
                &user,
                conn,
            )
            .unwrap_err();
            assert_eq!(err.message(), "too_many_attempts");
            let user = reload(conn, &user);
            let err = start_contact_method_verification_at(Some(&base_url), granted(PHONE), &user, conn)
                .unwrap_err();
            assert_eq!(err.message(), "verification_recently_sent");
            assert_eq!(sms_count(&sms), 1);
            Ok(())
        });
    }
}

// ---------------------------------------------------------------------------------------------
// Locking / races
// ---------------------------------------------------------------------------------------------

mod locking_spec {
    use super::*;
    use crate::logic::after_send_hook;

    #[test]
    fn a_login_code_can_only_be_redeemed_once() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "lk_once");
            set_user_phone(conn, &user, &verified(PHONE));
            let (base_url, sms) = sms_mock();
            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            let code = sms_code(&sms, 0);
            login_at(Some(&base_url), sms_login(PHONE, Some(&code), None), conn).unwrap();
            let err = login_at(Some(&base_url), sms_login(PHONE, Some(&code), None), conn).unwrap_err();
            assert_eq!(err.message(), "incorrect_code");
            Ok(())
        });
    }

    #[test]
    fn a_contact_edit_made_while_the_code_was_in_flight_is_not_clobbered() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "lk_clobber");
            let user = set_user_phone(conn, &user, &verified(PHONE));
            let (base_url, sms) = sms_mock();

            // While the SMS is "in flight", the user changes the phone's visibility.
            let user_id = user.id;
            after_send_hook::set(move |conn| {
                let mut edited = verified(PHONE);
                edited.visibility = Visibility::Private as i32;
                diesel::update(users::table.filter(users::id.eq(user_id)))
                    .set(users::phone.eq(serde_json::to_value(&edited).unwrap()))
                    .execute(conn)
                    .unwrap();
            });
            login_at(Some(&base_url), sms_login(PHONE, None, None), conn).unwrap();
            assert_eq!(sms_count(&sms), 1);
            let stored = stored_phone(conn, &user);
            assert_eq!(stored.visibility, Visibility::Private as i32, "the concurrent edit survives");
            assert_eq!(
                stored.verification_in_progress.expect("code stored").verification_code,
                sms_code(&sms, 0)
            );
            assert!(stored.verified_at.is_some());
            Ok(())
        });
    }

    #[test]
    fn a_code_is_dropped_if_the_contact_value_changed_while_it_was_in_flight() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "lk_changed");
            let user = set_user_phone(conn, &user, &granted(PHONE));
            let (base_url, _sms) = sms_mock();

            let user_id = user.id;
            after_send_hook::set(move |conn| {
                diesel::update(users::table.filter(users::id.eq(user_id)))
                    .set(users::phone.eq(serde_json::to_value(granted("tel:+15557654321")).unwrap()))
                    .execute(conn)
                    .unwrap();
            });
            let err = start_contact_method_verification_at(Some(&base_url), granted(PHONE), &user, conn)
                .unwrap_err();
            assert_eq!(err.message(), "contact_changed");
            let stored = stored_phone(conn, &user);
            assert_eq!(stored.value.as_deref(), Some("tel:+15557654321"));
            assert!(stored.verification_in_progress.is_none(), "the old number's code isn't attached to the new one");
            Ok(())
        });
    }

    #[test]
    fn the_locked_helper_reloads_and_skips_a_contact_that_changed() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            setup(conn, &ALL_FEATURES);
            let user = create_user(conn, "lk_reload");
            set_user_phone(conn, &user, &granted("tel:+15557654321"));
            let ran = crate::logic::with_locked_user_contact(
                conn,
                user.id,
                crate::logic::ContactKind::Phone,
                PHONE,
                |_conn, _contact| Ok(()),
            )
            .unwrap();
            assert!(ran.is_none(), "stale expectations never reach the callback");
            Ok(())
        });
    }

    /// The advisory lock that serializes "who owns this verified contact" decisions really is held
    /// until the transaction ends, on a case-insensitive key: a second connection cannot take it.
    #[test]
    fn the_contact_advisory_lock_excludes_other_connections() {
        let mut conn = test_conn();
        conn.test_transaction::<_, tonic::Status, _>(|conn| {
            crate::logic::lock_contact_value(conn, "mailto:Jon@Example.com")?;
            let try_lock = |value: &'static str| {
                std::thread::spawn(move || {
                    let mut other = test_conn();
                    other
                        .transaction::<bool, diesel::result::Error, _>(|other| {
                            diesel::select(diesel::dsl::sql::<diesel::sql_types::Bool>(&format!(
                                "pg_try_advisory_xact_lock(hashtext('contact:{}'))",
                                value
                            )))
                            .get_result(other)
                        })
                        .unwrap()
                })
                .join()
                .unwrap()
            };
            assert!(!try_lock("mailto:jon@example.com"), "same contact (any case) is locked");
            assert!(try_lock("mailto:someone.else@example.com"), "other contacts are not");
            Ok(())
        });
    }
}
