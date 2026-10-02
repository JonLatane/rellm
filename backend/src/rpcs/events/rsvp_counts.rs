//! Per-status RSVP totals for `Rsvps` (see its proto doc), plus the bounded batch loader
//! `GetEvents` uses so a huge event can't make one listing page drag in thousands of RSVP rows.
//!
//! "Visible" below means exactly what `get_rsvps`'s own filter means (and what `get_events`
//! used to filter on inline): moderation-passing RSVPs, plus -- for the Event's owner -- every
//! RSVP of their own Occasions, plus the viewer's own (by user id or anonymous auth token).
//! It's expressed here as one raw-SQL `WHERE` shared by the counts query and the capped-ids query,
//! so those two can never disagree with each other; `get_rsvps_parity_tests` guards it against
//! `get_rsvps`' Diesel filter.

use std::collections::HashMap;

use diesel::sql_types::{Array, BigInt, Text};
use diesel::*;

use crate::db_connection::PgPooledConnection;
use crate::protos::*;
use crate::rpcs::validations::PASSING_MODERATIONS;

/// Most RSVPs `GetEvents` returns per Occasion; beyond this, only the `Rsvps` counts grow.
pub const MAX_RSVPS_PER_OCCASION: i64 = 100;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct RsvpCounts {
    going: (u32, u32),
    interested: (u32, u32),
    requested: (u32, u32),
    not_going: (u32, u32),
    pending: (u32, u32),
}

impl RsvpCounts {
    /// Adds `rsvp_count` RSVPs (with `attendees` total guests) of the given stored `status`/
    /// `moderation` strings -- see `Rsvps`' proto doc for which bucket each lands in.
    pub fn add(&mut self, status: &str, moderation: &str, rsvp_count: u32, attendees: u32) {
        let bucket = if moderation == "PENDING" {
            &mut self.pending
        } else if PASSING_MODERATIONS.iter().any(|&m| m == moderation) {
            match status {
                "GOING" => &mut self.going,
                "INTERESTED" => &mut self.interested,
                "REQUESTED" => &mut self.requested,
                "NOT_GOING" => &mut self.not_going,
                _ => return,
            }
        } else {
            return; // REJECTED etc. aren't counted.
        };
        bucket.0 += rsvp_count;
        bucket.1 += attendees;
    }

    pub fn apply_to(&self, rsvps: &mut Rsvps) {
        rsvps.going_count = self.going.0;
        rsvps.going_attendees = self.going.1;
        rsvps.interested_count = self.interested.0;
        rsvps.interested_attendees = self.interested.1;
        rsvps.requested_count = self.requested.0;
        rsvps.requested_attendees = self.requested.1;
        rsvps.not_going_count = self.not_going.0;
        rsvps.not_going_attendees = self.not_going.1;
        rsvps.pending_count = self.pending.0;
        rsvps.pending_attendees = self.pending.1;
    }
}

// Binds: $1 occasion ids, $2 occasion ids the viewer owns, $3 viewer's user id (0 if anonymous),
// $4 the viewer's anonymous auth tokens (any may match; see `anonymous_tokens`), $5 passing
// moderations.
const VISIBLE_RSVPS_WHERE: &str = "occasion_id = ANY($1) AND ( \
        occasion_id = ANY($2) \
        OR moderation = ANY($5) \
        OR user_id = $3 \
        OR anonymous_attendee ->> 'auth_token' = ANY($4) \
    )";

#[derive(QueryableByName)]
struct CountRow {
    #[diesel(sql_type = BigInt)]
    occasion_id: i64,
    #[diesel(sql_type = Text)]
    status: String,
    #[diesel(sql_type = Text)]
    moderation: String,
    #[diesel(sql_type = BigInt)]
    rsvp_count: i64,
    #[diesel(sql_type = BigInt)]
    attendee_count: i64,
}

#[derive(QueryableByName)]
struct IdRow {
    #[diesel(sql_type = BigInt)]
    id: i64,
}

/// For every one of `occasion_ids`, the totals over all RSVPs visible to the viewer (see the
/// module doc), and -- capped at `MAX_RSVPS_PER_OCCASION` per Occasion -- the ids of the RSVPs to
/// actually load. When capping, the viewer's own RSVP comes first, then pending ones (which only
/// the owner sees besides their author), then `GOING`/`REQUESTED`/`INTERESTED`/`NOT_GOING`.
pub fn load_visible_rsvp_counts_and_ids(
    occasion_ids: &[i64],
    owned_occasion_ids: &[i64],
    current_user_id: Option<i64>,
    anonymous_auth_tokens: &[String],
    conn: &mut PgPooledConnection,
) -> (HashMap<i64, RsvpCounts>, Vec<i64>) {
    let passing: Vec<String> = PASSING_MODERATIONS.iter().map(|m| m.to_string()).collect();
    let viewer_id = current_user_id.unwrap_or(0);

    let count_rows: Vec<CountRow> = sql_query(format!(
        "SELECT occasion_id, status, moderation, COUNT(*)::bigint AS rsvp_count, \
                COALESCE(SUM(number_of_guests), 0)::bigint AS attendee_count \
         FROM rsvps WHERE {VISIBLE_RSVPS_WHERE} GROUP BY occasion_id, status, moderation"
    ))
    .bind::<Array<BigInt>, _>(occasion_ids)
    .bind::<Array<BigInt>, _>(owned_occasion_ids)
    .bind::<BigInt, _>(viewer_id)
    .bind::<Array<Text>, _>(anonymous_auth_tokens)
    .bind::<Array<Text>, _>(&passing)
    .load(conn)
    .unwrap_or_default();

    let mut counts: HashMap<i64, RsvpCounts> = HashMap::new();
    for row in count_rows {
        counts.entry(row.occasion_id).or_default().add(
            &row.status,
            &row.moderation,
            row.rsvp_count as u32,
            row.attendee_count as u32,
        );
    }

    let ids: Vec<IdRow> = sql_query(format!(
        "SELECT id FROM ( \
           SELECT id, occasion_id, row_number() OVER ( \
             PARTITION BY occasion_id \
             ORDER BY \
               COALESCE(user_id = $3 OR anonymous_attendee ->> 'auth_token' = ANY($4), false) DESC, \
               (moderation = 'PENDING') DESC, \
               CASE status WHEN 'GOING' THEN 0 WHEN 'REQUESTED' THEN 1 \
                           WHEN 'INTERESTED' THEN 2 ELSE 3 END, \
               id \
           ) AS rn \
           FROM rsvps WHERE {VISIBLE_RSVPS_WHERE} \
         ) ranked WHERE rn <= $6"
    ))
    .bind::<Array<BigInt>, _>(occasion_ids)
    .bind::<Array<BigInt>, _>(owned_occasion_ids)
    .bind::<BigInt, _>(viewer_id)
    .bind::<Array<Text>, _>(anonymous_auth_tokens)
    .bind::<Array<Text>, _>(&passing)
    .bind::<BigInt, _>(MAX_RSVPS_PER_OCCASION)
    .load(conn)
    .unwrap_or_default();

    (counts, ids.into_iter().map(|r| r.id).collect())
}
