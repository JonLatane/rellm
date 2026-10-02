//! Specs for `delete_rsvp`: the event owner or the attendee themselves may delete a
//! user-backed rsvp; anonymous rsvps are gated by a matching `auth_token` instead
//! (see `logic`/`models::get_rsvp`'s auth_token lookup) rather than by `user`.

use diesel::prelude::*;
use tonic::Code;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::delete_rsvp;
use crate::schema::rsvps;
use crate::tests::factories::*;

#[test]
fn event_owner_can_delete_any_rsvp() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "deat_owner");
        let (event, _post) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _occasion_post) =
            create_occasion(conn, &event, Some(&owner), OccasionOpts::default());
        let attendee = create_user(conn, "deat_attendee");
        create_rsvp(
            conn,
            &occasion,
            RsvpOpts {
                user_id: Some(attendee.id),
                ..Default::default()
            },
        );

        delete_rsvp(
            Rsvp {
                occasion_id: occasion.post_id.to_proto_id(),
                attendee: Some(rsvp::Attendee::UserAttendee(UserAttendee {
                    user_id: attendee.id.to_proto_id(),
                    ..Default::default()
                })),
                ..Default::default()
            },
            &Some(&owner),
            conn,
        )
        .expect("event owner delete should succeed");

        let remaining: i64 = rsvps::table
            .filter(rsvps::occasion_id.eq(occasion.post_id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 0);

        Ok(())
    });
}

#[test]
fn attendee_can_delete_their_own_rsvp() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "deat_owner2");
        let (event, _post) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _occasion_post) =
            create_occasion(conn, &event, Some(&owner), OccasionOpts::default());
        let attendee = create_user(conn, "deat_attendee2");
        create_rsvp(
            conn,
            &occasion,
            RsvpOpts {
                user_id: Some(attendee.id),
                ..Default::default()
            },
        );

        delete_rsvp(
            Rsvp {
                occasion_id: occasion.post_id.to_proto_id(),
                attendee: Some(rsvp::Attendee::UserAttendee(UserAttendee {
                    user_id: attendee.id.to_proto_id(),
                    ..Default::default()
                })),
                ..Default::default()
            },
            &Some(&attendee),
            conn,
        )
        .expect("attendee self delete should succeed");

        let remaining: i64 = rsvps::table
            .filter(rsvps::occasion_id.eq(occasion.post_id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 0);

        Ok(())
    });
}

#[test]
fn delete_rejects_an_unrelated_user() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "deat_owner3");
        let (event, _post) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _occasion_post) =
            create_occasion(conn, &event, Some(&owner), OccasionOpts::default());
        let attendee = create_user(conn, "deat_attendee3");
        create_rsvp(
            conn,
            &occasion,
            RsvpOpts {
                user_id: Some(attendee.id),
                ..Default::default()
            },
        );
        let bystander = create_user(conn, "deat_bystander");

        let err = delete_rsvp(
            Rsvp {
                occasion_id: occasion.post_id.to_proto_id(),
                attendee: Some(rsvp::Attendee::UserAttendee(UserAttendee {
                    user_id: attendee.id.to_proto_id(),
                    ..Default::default()
                })),
                ..Default::default()
            },
            &Some(&bystander),
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::PermissionDenied);
        assert_eq!(err.message(), "not_your_event_or_rsvp");

        let remaining: i64 = rsvps::table
            .filter(rsvps::occasion_id.eq(occasion.post_id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 1, "rsvp should survive a rejected delete");

        Ok(())
    });
}

#[test]
fn anonymous_rsvp_is_deleted_with_a_matching_auth_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "deat_owner4");
        let (event, _post) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _occasion_post) =
            create_occasion(conn, &event, Some(&owner), OccasionOpts::default());
        create_rsvp(
            conn,
            &occasion,
            RsvpOpts {
                anonymous_attendee: Some(
                    serde_json::json!({"name": "Anon", "auth_token": "correct-token"}),
                ),
                ..Default::default()
            },
        );

        delete_rsvp(
            Rsvp {
                occasion_id: occasion.post_id.to_proto_id(),
                attendee: Some(rsvp::Attendee::AnonymousAttendee(
                    AnonymousAttendee {
                        name: "Anon".to_string(),
                        contact_methods: vec![],
                        auth_token: Some("correct-token".to_string()),
                    },
                )),
                ..Default::default()
            },
            &None,
            conn,
        )
        .expect("matching auth_token delete should succeed");

        let remaining: i64 = rsvps::table
            .filter(rsvps::occasion_id.eq(occasion.post_id))
            .count()
            .get_result(conn)
            .unwrap();
        assert_eq!(remaining, 0);

        Ok(())
    });
}

#[test]
fn anonymous_rsvp_delete_fails_with_the_wrong_auth_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let owner = create_user(conn, "deat_owner5");
        let (event, _post) = create_event(
            conn,
            &owner,
            EventOpts {
                default_occasion: None,
                ..Default::default()
            },
        );
        let (occasion, _occasion_post) =
            create_occasion(conn, &event, Some(&owner), OccasionOpts::default());
        create_rsvp(
            conn,
            &occasion,
            RsvpOpts {
                anonymous_attendee: Some(
                    serde_json::json!({"name": "Anon", "auth_token": "correct-token"}),
                ),
                ..Default::default()
            },
        );

        let err = delete_rsvp(
            Rsvp {
                occasion_id: occasion.post_id.to_proto_id(),
                attendee: Some(rsvp::Attendee::AnonymousAttendee(
                    AnonymousAttendee {
                        name: "Anon".to_string(),
                        contact_methods: vec![],
                        auth_token: Some("wrong-token".to_string()),
                    },
                )),
                ..Default::default()
            },
            &None,
            conn,
        )
        .unwrap_err();
        assert_eq!(err.code(), Code::NotFound);
        assert_eq!(err.message(), "rsvp_not_found");

        Ok(())
    });
}
