//! Specs for `ToProtoUser::to_proto`'s `email`/`phone` gating (see
//! `marshaling::user_marshaling::visible_contact_method`): each `ContactMethod` carries its own
//! `visibility`, independent of the owning `User`'s overall `visibility`, and that's what's
//! enforced here -- `GLOBAL_PUBLIC` to everyone, `SERVER_PUBLIC` to any authenticated viewer, and
//! `LIMITED`/`PRIVATE` to only the owner or a viewer holding `VIEW_PRIVATE_CONTACT_METHODS`
//! (deliberately *not* just `ADMIN` -- see that permission's own doc).

use diesel::prelude::*;

use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::users;
use crate::tests::factories::*;

fn contact_method(visibility: Visibility) -> serde_json::Value {
    contact_method_with_consent(visibility, ContactConsentState::ContactConsentRevoked, vec![])
}

/// Same as `contact_method`, but with an explicit `consent_state`/`consent_history` -- for specs
/// on `scrub_consent_for_viewer` (see `user_marshaling.rs`), which is independent of (and, unlike
/// it, never relaxed by `VIEW_PRIVATE_CONTACT_METHODS` for) the `value`/`visibility` gating the
/// rest of this file exercises.
fn contact_method_with_consent(
    visibility: Visibility,
    consent_state: ContactConsentState,
    consent_history: Vec<ContactConsentChange>,
) -> serde_json::Value {
    serde_json::to_value(ContactMethod {
        value: Some("tel:+15551234567".to_string()),
        visibility: visibility as i32,
        supported_by_server: false,
        verified_at: None,
        verification_in_progress: None,
        consent_state: consent_state as i32,
        consent_history,
    })
    .unwrap()
}

fn set_phone(
    conn: &mut crate::db_connection::PgPooledConnection,
    user: &models::User,
    visibility: Visibility,
) -> models::User {
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set(users::phone.eq(contact_method(visibility)))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to set test user's phone")
}

fn set_phone_with_consent(
    conn: &mut crate::db_connection::PgPooledConnection,
    user: &models::User,
    visibility: Visibility,
    consent_state: ContactConsentState,
    consent_history: Vec<ContactConsentChange>,
) -> models::User {
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set(users::phone.eq(contact_method_with_consent(visibility, consent_state, consent_history)))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to set test user's phone")
}

#[test]
fn global_public_phone_is_visible_to_anonymous_viewers() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_global_owner");
        let owner = set_phone(conn, &owner, Visibility::GlobalPublic);

        let proto = owner.to_proto(&None, &None, None, &None, None);
        assert!(proto.phone.is_some());

        Ok(())
    });
}

#[test]
fn server_public_phone_is_hidden_from_anonymous_viewers() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_server_owner");
        let owner = set_phone(conn, &owner, Visibility::ServerPublic);

        let proto = owner.to_proto(&None, &None, None, &None, None);
        assert!(proto.phone.is_none());

        Ok(())
    });
}

#[test]
fn server_public_phone_is_visible_to_any_authenticated_viewer() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_server_owner2");
        let owner = set_phone(conn, &owner, Visibility::ServerPublic);
        let viewer = create_user(conn, "cmv_server_viewer");

        let proto = owner.to_proto(&None, &None, None, &Some(&viewer), None);
        assert!(proto.phone.is_some());

        Ok(())
    });
}

#[test]
fn private_phone_is_hidden_from_other_authenticated_viewers() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_private_owner");
        let owner = set_phone(conn, &owner, Visibility::Private);
        let viewer = create_user(conn, "cmv_private_viewer");

        let proto = owner.to_proto(&None, &None, None, &Some(&viewer), None);
        assert!(proto.phone.is_none());

        Ok(())
    });
}

#[test]
fn limited_phone_is_treated_like_private_and_hidden_from_other_viewers() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_limited_owner");
        let owner = set_phone(conn, &owner, Visibility::Limited);
        let viewer = create_user(conn, "cmv_limited_viewer");

        let proto = owner.to_proto(&None, &None, None, &Some(&viewer), None);
        assert!(proto.phone.is_none());

        Ok(())
    });
}

#[test]
fn private_phone_is_always_visible_to_its_owner() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_private_self");
        let owner = set_phone(conn, &owner, Visibility::Private);

        let proto = owner.to_proto(&None, &None, None, &Some(&owner), None);
        assert!(proto.phone.is_some());

        Ok(())
    });
}

#[test]
fn private_phone_is_visible_to_a_viewer_with_view_private_contact_methods() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_private_owner2");
        let owner = set_phone(conn, &owner, Visibility::Private);
        let viewer = create_user(conn, "cmv_private_privileged_viewer");
        let viewer = grant_permissions(conn, &viewer, vec![Permission::ViewPrivateContactMethods]);

        let proto = owner.to_proto(&None, &None, None, &Some(&viewer), None);
        assert!(proto.phone.is_some());

        Ok(())
    });
}

#[test]
fn consent_is_visible_to_the_contact_methods_own_owner() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_consent_owner");
        let owner = set_phone_with_consent(
            conn,
            &owner,
            Visibility::GlobalPublic,
            ContactConsentState::ContactConsentGranted,
            vec![ContactConsentChange {
                state: ContactConsentState::ContactConsentGranted as i32,
                changed_at: Some(std::time::SystemTime::now().to_proto()),
            }],
        );

        let proto = owner.to_proto(&None, &None, None, &Some(&owner), None);
        let phone = proto.phone.expect("phone should be visible to its own owner");
        assert_eq!(phone.consent_state, ContactConsentState::ContactConsentGranted as i32);
        assert_eq!(phone.consent_history.len(), 1);

        Ok(())
    });
}

#[test]
fn consent_is_scrubbed_from_other_viewers_even_when_value_is_global_public() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_consent_hidden_owner");
        let owner = set_phone_with_consent(
            conn,
            &owner,
            Visibility::GlobalPublic,
            ContactConsentState::ContactConsentGranted,
            vec![ContactConsentChange {
                state: ContactConsentState::ContactConsentGranted as i32,
                changed_at: Some(std::time::SystemTime::now().to_proto()),
            }],
        );
        let viewer = create_user(conn, "cmv_consent_hidden_viewer");

        // The `value` itself is visible (GLOBAL_PUBLIC), but consent is a different, stricter
        // gate -- see `scrub_consent_for_viewer`.
        let proto = owner.to_proto(&None, &None, None, &Some(&viewer), None);
        let phone = proto.phone.expect("value should still be visible");
        assert_eq!(phone.consent_state, ContactConsentState::ContactConsentRevoked as i32);
        assert!(phone.consent_history.is_empty());

        Ok(())
    });
}

#[test]
fn consent_is_visible_to_a_plain_admin_when_value_itself_is_visible() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // `value` needs GLOBAL_PUBLIC here (rather than Private) so a plain admin -- lacking
        // `VIEW_PRIVATE_CONTACT_METHODS` -- can see the `ContactMethod` at all; this isolates
        // consent's own visibility rule (a plain `ADMIN` check) from `value`'s stricter one.
        let owner = create_user(conn, "cmv_consent_admin_owner");
        let owner = set_phone_with_consent(
            conn,
            &owner,
            Visibility::GlobalPublic,
            ContactConsentState::ContactConsentGranted,
            vec![ContactConsentChange {
                state: ContactConsentState::ContactConsentGranted as i32,
                changed_at: Some(std::time::SystemTime::now().to_proto()),
            }],
        );
        let admin = create_user(conn, "cmv_consent_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        let proto = owner.to_proto(&None, &None, None, &Some(&admin), None);
        let phone = proto.phone.expect("value should be visible to any viewer (GLOBAL_PUBLIC)");
        assert_eq!(
            phone.consent_state,
            ContactConsentState::ContactConsentGranted as i32,
            "unlike value's own visibility, consent is a plain ADMIN check, not gated on VIEW_PRIVATE_CONTACT_METHODS"
        );
        assert_eq!(phone.consent_history.len(), 1);

        Ok(())
    });
}

#[test]
fn private_phone_is_hidden_from_a_plain_admin_without_view_private_contact_methods() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_private_owner3");
        let owner = set_phone(conn, &owner, Visibility::Private);
        let admin = create_user(conn, "cmv_private_admin");
        let admin = grant_permissions(conn, &admin, vec![Permission::Admin]);

        // `VIEW_PRIVATE_CONTACT_METHODS` is deliberately not implied by `ADMIN` -- unlike most
        // other admin-gated things on a user profile.
        let proto = owner.to_proto(&None, &None, None, &Some(&admin), None);
        assert!(proto.phone.is_none());

        Ok(())
    });
}

/// Regression test for a production panic: `ToProtoUser::to_proto` deserializes
/// `users.phone`/`.email` with a bare `.unwrap()` (see `user_marshaling.rs`), so a `ContactMethod`
/// stored before `consent_state`/`consent_history` existed -- missing those two keys entirely, not
/// just holding falsy values -- crashed the whole request with `missing field 'consent_state'`
/// once those fields shipped. `build.rs`'s `#[serde(default)]` field attributes on both are what
/// fix this; this test writes exactly the pre-existing (missing-key) JSON shape by hand, bypassing
/// `ContactMethod`'s own (always-complete) struct literal, to prove old rows still load.
#[test]
fn phone_stored_before_consent_fields_existed_deserializes_without_panicking() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "cmv_pre_consent_shape");
        let pre_consent_shape = serde_json::json!({
            "value": "tel:+15551234567",
            "visibility": Visibility::GlobalPublic as i32,
            "supported_by_server": false,
            "verified_at": null,
            "verification_in_progress": null,
            // Deliberately no "consent_state"/"consent_history" keys at all -- the panic this
            // guards against was `missing field 'consent_state'` (confirming stored JSON keys are
            // the Rust struct's own snake_case field names, not camelCase).
        });
        let owner = diesel::update(users::table.filter(users::id.eq(owner.id)))
            .set(users::phone.eq(pre_consent_shape))
            .returning(models::USER_COLUMNS)
            .get_result::<models::User>(conn)
            .expect("failed to set test user's pre-consent-shape phone");

        let proto = owner.to_proto(&None, &None, None, &Some(&owner), None);
        let phone = proto.phone.expect("phone should still deserialize and be visible");
        assert_eq!(phone.value.as_deref(), Some("tel:+15551234567"));
        assert_eq!(
            phone.consent_state,
            ContactConsentState::ContactConsentRevoked as i32,
            "missing consent_state must default to the proto3 zero value, not panic"
        );
        assert!(phone.consent_history.is_empty());

        Ok(())
    });
}
