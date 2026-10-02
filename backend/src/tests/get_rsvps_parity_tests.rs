//! Cross-checks that `get_events`' embedded `Occasion.rsvps`/`current_user_rsvp`
//! (see `attach_occasion_rsvps` in `rpcs::events::get_events`) see *exactly* the same
//! data the dedicated `get_rsvps` RPC does, for the same viewer: the same set of
//! visible rsvps, the same per-row `private_note` redaction, and the same
//! resolved-or-hidden `location`. `attach_occasion_rsvps`'s doc comment explains why
//! these rules are duplicated by hand instead of shared code - this suite is what keeps that
//! duplication honest as either RPC changes.

use std::collections::BTreeMap;

use diesel::prelude::*;
use tonic::Status;

use crate::marshaling::*;
use crate::protos::*;
use crate::rpcs::{get_rsvps, get_events};
use crate::tests::factories::*;

const ANONYMOUS_AUTH_TOKEN: &str = "gea_parity_secret_token";

struct Scenario {
    owner: crate::models::User,
    pending_user: crate::models::User,
    approved_user: crate::models::User,
    occasion: crate::models::Occasion,
    approved_rsvp: crate::models::Rsvp,
    pending_rsvp: crate::models::Rsvp,
    anonymous_rsvp: crate::models::Rsvp,
}

fn location_json(address: &str) -> serde_json::Value {
    serde_json::to_value(Location {
        id: "".to_string(),
        creator_id: "".to_string(),
        uniformly_formatted_address: address.to_string(),
    })
    .unwrap()
}

/// A `GlobalPublic` event/occasion (owned by `owner`) with `hide_location_until_rsvp_approved`
/// set and a location on the occasion, plus three rsvps covering every visibility bucket
/// `get_rsvps` distinguishes: an `Approved` logged-in user, a `Pending` logged-in
/// user, and a `Pending` anonymous attendee (unlocked by `ANONYMOUS_AUTH_TOKEN`).
fn build_scenario(conn: &mut crate::db_connection::PgPooledConnection, suffix: &str) -> Scenario {
    let owner = create_user(conn, &format!("geap_owner_{suffix}"));
    let pending_user = create_user(conn, &format!("geap_pending_{suffix}"));
    let approved_user = create_user(conn, &format!("geap_approved_{suffix}"));

    let (event, _event_post) = create_event(
        conn,
        &owner,
        EventOpts {
            visibility: Visibility::GlobalPublic,
            info: serde_json::json!({ "hide_location_until_rsvp_approved": true }),
            ..Default::default()
        },
    );
    let (occasion, _occasion_post) = create_occasion(
        conn,
        &event,
        Some(&owner),
        OccasionOpts {
            visibility: Visibility::GlobalPublic,
            location: Some(location_json("123 Main St")),
            ..Default::default()
        },
    );

    let approved_rsvp = create_rsvp(
        conn,
        &occasion,
        RsvpOpts {
            user_id: Some(approved_user.id),
            status: RsvpStatus::Going,
            moderation: Moderation::Approved,
            private_note: "approved user's private note".to_string(),
            ..Default::default()
        },
    );
    let pending_rsvp = create_rsvp(
        conn,
        &occasion,
        RsvpOpts {
            user_id: Some(pending_user.id),
            status: RsvpStatus::Interested,
            moderation: Moderation::Pending,
            private_note: "pending user's private note".to_string(),
            ..Default::default()
        },
    );
    let anonymous_rsvp = create_rsvp(
        conn,
        &occasion,
        RsvpOpts {
            anonymous_attendee: Some(serde_json::json!({
                "name": "Anonymous Guest",
                "auth_token": ANONYMOUS_AUTH_TOKEN,
            })),
            status: RsvpStatus::Interested,
            moderation: Moderation::Pending,
            private_note: "anonymous guest's private note".to_string(),
            ..Default::default()
        },
    );

    Scenario {
        owner,
        pending_user,
        approved_user,
        occasion,
        approved_rsvp,
        pending_rsvp,
        anonymous_rsvp,
    }
}

fn via_get_events(
    conn: &mut crate::db_connection::PgPooledConnection,
    user: &Option<&crate::models::User>,
    occasion_id: i64,
    anonymous_attendee_auth_token: Option<String>,
) -> Occasion {
    let response = get_events(
        GetEventsRequest {
            post_id: Some(occasion_id.to_proto_id()),
            anonymous_attendee_auth_token,
            ..Default::default()
        },
        user,
        conn,
    )
    .expect("get_events failed");
    response
        .events
        .into_iter()
        .next()
        .expect("get_events returned no event")
        .occasions
        .into_iter()
        .find(|occasion| occasion.post.as_ref().unwrap().id == occasion_id.to_proto_id())
        .expect("get_events response is missing the occasion")
}

fn via_get_rsvps(
    conn: &mut crate::db_connection::PgPooledConnection,
    user: &Option<&crate::models::User>,
    occasion_id: i64,
    anonymous_attendee_auth_token: Option<String>,
) -> Rsvps {
    get_rsvps(
        GetRsvpsRequest {
            occasion_id: occasion_id.to_proto_id(),
            anonymous_attendee_auth_token,
        },
        user,
        conn,
    )
    .expect("get_rsvps failed")
}

/// Every per-status/pending total on `Rsvps`, as (count, attendees) pairs.
fn count_fields(rsvps: &Rsvps) -> [(u32, u32); 5] {
    [
        (rsvps.going_count, rsvps.going_attendees),
        (rsvps.interested_count, rsvps.interested_attendees),
        (rsvps.requested_count, rsvps.requested_attendees),
        (rsvps.not_going_count, rsvps.not_going_attendees),
        (rsvps.pending_count, rsvps.pending_attendees),
    ]
}

fn notes_by_id(rsvps: &Rsvps) -> BTreeMap<String, String> {
    rsvps
        .rsvps
        .iter()
        .map(|a| (a.id.clone(), a.private_note.clone()))
        .collect()
}

/// Fetches the same occasion/viewer combination through both RPCs and asserts they agree on
/// exactly which rsvps are visible, each row's `private_note` redaction, and whether the
/// location is revealed - both via `Rsvps.hidden_location` (present on both RPCs'
/// response shape) and via `Occasion.location` itself (`get_events`-only, since a plain
/// `get_rsvps` caller may never have fetched the occasion at all).
fn assert_parity(
    conn: &mut crate::db_connection::PgPooledConnection,
    user: &Option<&crate::models::User>,
    occasion_id: i64,
    anonymous_attendee_auth_token: Option<String>,
) -> (Occasion, Rsvps) {
    let events_occasion = via_get_events(
        conn,
        user,
        occasion_id,
        anonymous_attendee_auth_token.clone(),
    );
    let rsvps =
        via_get_rsvps(conn, user, occasion_id, anonymous_attendee_auth_token);
    let events_rsvps = events_occasion
        .rsvps
        .clone()
        .expect("get_events occasion is missing its rsvps field");

    assert_eq!(
        notes_by_id(&events_rsvps),
        notes_by_id(&rsvps),
        "get_events and get_rsvps disagree on which rsvps are visible \
         and/or their private_note redaction"
    );
    assert_eq!(
        count_fields(&events_rsvps),
        count_fields(&rsvps),
        "get_events and get_rsvps disagree on the Rsvps totals"
    );
    assert_eq!(
        events_rsvps.hidden_location.is_some(),
        rsvps.hidden_location.is_some(),
        "get_events and get_rsvps disagree on whether the location is revealed"
    );
    assert_eq!(
        events_occasion.location.is_some(),
        rsvps.hidden_location.is_some(),
        "Occasion.location should be revealed exactly when Rsvps.hidden_location is"
    );

    (events_occasion, rsvps)
}

#[test]
fn public_viewer_sees_only_the_approved_rsvp_notes_redacted_and_location_hidden() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let scenario = build_scenario(conn, "pub");

        let (events_occasion, rsvps) = assert_parity(conn, &None, scenario.occasion.post_id, None);

        assert_eq!(
            notes_by_id(&rsvps),
            BTreeMap::from([(scenario.approved_rsvp.id.to_proto_id(), "".to_string())]),
            "an unauthenticated viewer should see only the approved rsvp, with no private_note"
        );
        assert!(events_occasion.location.is_none());
        assert!(events_occasion.current_user_rsvp.is_none());
        Ok(())
    });
}

#[test]
fn own_pending_attendee_sees_their_own_row_but_location_stays_hidden() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let scenario = build_scenario(conn, "pending");

        let (events_occasion, rsvps) = assert_parity(
            conn,
            &Some(&scenario.pending_user),
            scenario.occasion.post_id,
            None,
        );

        assert_eq!(
            notes_by_id(&rsvps),
            BTreeMap::from([
                (
                    scenario.approved_rsvp.id.to_proto_id(),
                    "".to_string()
                ),
                (
                    scenario.pending_rsvp.id.to_proto_id(),
                    "pending user's private note".to_string()
                ),
            ]),
            "a pending attendee should see their own private_note but not the approved stranger's"
        );
        assert!(
            events_occasion.location.is_none(),
            "a merely-Pending (not Approved) attendee shouldn't unlock the hidden location"
        );
        assert_eq!(
            events_occasion
                .current_user_rsvp
                .expect("current_user_rsvp should be set")
                .id,
            scenario.pending_rsvp.id.to_proto_id()
        );
        Ok(())
    });
}

#[test]
fn approved_attendee_unlocks_the_hidden_location() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let scenario = build_scenario(conn, "approved");

        let (events_occasion, _rsvps) = assert_parity(
            conn,
            &Some(&scenario.approved_user),
            scenario.occasion.post_id,
            None,
        );

        assert!(
            events_occasion.location.is_some(),
            "an Approved attendee should unlock the hidden location"
        );
        assert_eq!(
            events_occasion
                .current_user_rsvp
                .expect("current_user_rsvp should be set")
                .id,
            scenario.approved_rsvp.id.to_proto_id()
        );
        Ok(())
    });
}

#[test]
fn anonymous_attendee_sees_their_own_pending_row_via_auth_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let scenario = build_scenario(conn, "anon");

        let (events_occasion, rsvps) = assert_parity(
            conn,
            &None,
            scenario.occasion.post_id,
            Some(ANONYMOUS_AUTH_TOKEN.to_string()),
        );

        assert_eq!(
            notes_by_id(&rsvps),
            BTreeMap::from([
                (
                    scenario.approved_rsvp.id.to_proto_id(),
                    "".to_string()
                ),
                (
                    scenario.anonymous_rsvp.id.to_proto_id(),
                    "anonymous guest's private note".to_string()
                ),
            ]),
            "the matching auth token should unlock only the anonymous attendee's own row"
        );
        assert!(
            events_occasion.location.is_none(),
            "the anonymous attendee is only Pending, so the location should stay hidden"
        );
        assert_eq!(
            events_occasion
                .current_user_rsvp
                .expect("current_user_rsvp should be set")
                .id,
            scenario.anonymous_rsvp.id.to_proto_id()
        );
        Ok(())
    });
}

#[test]
fn wrong_auth_token_is_treated_like_no_token() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let scenario = build_scenario(conn, "wrongtoken");

        let (events_occasion, rsvps) = assert_parity(
            conn,
            &None,
            scenario.occasion.post_id,
            Some("not-the-right-token".to_string()),
        );

        assert_eq!(
            notes_by_id(&rsvps),
            BTreeMap::from([(
                scenario.approved_rsvp.id.to_proto_id(),
                "".to_string()
            )]),
        );
        assert!(events_occasion.location.is_none());
        assert!(events_occasion.current_user_rsvp.is_none());
        Ok(())
    });
}

#[test]
fn event_owner_sees_every_rsvp_unredacted_and_the_real_location() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let scenario = build_scenario(conn, "owner");

        let (events_occasion, rsvps) =
            assert_parity(conn, &Some(&scenario.owner), scenario.occasion.post_id, None);

        assert_eq!(
            notes_by_id(&rsvps),
            BTreeMap::from([
                (
                    scenario.approved_rsvp.id.to_proto_id(),
                    "approved user's private note".to_string()
                ),
                (
                    scenario.pending_rsvp.id.to_proto_id(),
                    "pending user's private note".to_string()
                ),
                (
                    scenario.anonymous_rsvp.id.to_proto_id(),
                    "anonymous guest's private note".to_string()
                ),
            ]),
            "the event owner should see every rsvp's private_note, moderation status aside"
        );
        assert!(events_occasion.location.is_some());
        assert!(
            events_occasion.current_user_rsvp.is_none(),
            "the owner never RSVP'd to their own event in this scenario"
        );
        Ok(())
    });
}

#[test]
fn get_events_caps_returned_rsvps_but_totals_cover_all_of_them() {
    let mut conn = test_conn();
    conn.test_transaction::<_, Status, _>(|conn| {
        let owner = create_user(conn, "geap_cap_owner");
        let (event, _) = create_event(
            conn,
            &owner,
            EventOpts {
                visibility: Visibility::GlobalPublic,
                ..Default::default()
            },
        );
        let (occasion, _) = create_occasion(
            conn,
            &event,
            Some(&owner),
            OccasionOpts {
                visibility: Visibility::GlobalPublic,
                ..Default::default()
            },
        );

        let total = crate::rpcs::events::MAX_RSVPS_PER_OCCASION as usize + 5;
        for i in 0..total {
            create_rsvp(
                conn,
                &occasion,
                RsvpOpts {
                    anonymous_attendee: Some(serde_json::json!({
                        "name": format!("guest {i}"),
                        "auth_token": format!("gea_cap_token_{i}"),
                    })),
                    status: RsvpStatus::Interested,
                    ..Default::default()
                },
            );
        }
        // The viewer's own (last-created, so it would be cut first by id order alone) RSVP, plus one
        // GOING one -- both must beat plain INTERESTED ones for the cap.
        let own_token = format!("gea_cap_token_{}", total - 1);
        create_rsvp(
            conn,
            &occasion,
            RsvpOpts {
                anonymous_attendee: Some(serde_json::json!({ "name": "going", "auth_token": "going_token" })),
                status: RsvpStatus::Going,
                ..Default::default()
            },
        );

        let via_events = via_get_events(conn, &None, occasion.post_id, Some(own_token.clone()));
        let events_rsvps = via_events.rsvps.unwrap();
        assert_eq!(
            events_rsvps.rsvps.len(),
            crate::rpcs::events::MAX_RSVPS_PER_OCCASION as usize
        );
        assert_eq!(events_rsvps.interested_count as usize, total);
        assert_eq!(events_rsvps.going_count, 1);
        assert!(
            events_rsvps
                .rsvps
                .iter()
                .any(|r| r.status == RsvpStatus::Going as i32),
            "GOING outranks INTERESTED when capping"
        );
        assert!(
            via_events.current_user_rsvp.is_some(),
            "the viewer's own RSVP is always among the returned ones"
        );

        // `get_rsvps` isn't capped.
        let uncapped = via_get_rsvps(conn, &None, occasion.post_id, None);
        assert_eq!(uncapped.rsvps.len(), total + 1);
        assert_eq!(uncapped.interested_count as usize, total);
        Ok(())
    });
}
