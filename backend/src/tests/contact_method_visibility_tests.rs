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
    serde_json::to_value(ContactMethod {
        value: Some("tel:+15551234567".to_string()),
        visibility: visibility as i32,
        supported_by_server: false,
        verified_at: None,
        verification_in_progress: None,
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
