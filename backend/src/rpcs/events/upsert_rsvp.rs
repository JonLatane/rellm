use diesel::dsl::sum;
use diesel::result::Error::RollbackTransaction;
use diesel::*;

use ring::rand::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::generate_token;
use crate::marshaling::*;
use crate::models::{self, get_author, get_rsvp, NewRsvp};
use crate::protos::*;
use crate::rpcs::validations::PASSING_MODERATIONS;
use crate::schema::{rsvps, occasions, events, posts, users};

/// Creates or updates an RSVP. Runs in a transaction holding a row lock on the `Occasion`, so
/// the attendee-limit check in `upsert_rsvp_impl` can't be raced by concurrent RSVPs to the same
/// `Occasion`.
pub fn upsert_rsvp(
    request: Rsvp,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<Rsvp, Status> {
    let occasion_id = request.occasion_id.to_db_id_or_err("occasion_id")?;
    let mut result: Option<Result<Rsvp, Status>> = None;
    let transaction_result = conn.transaction::<(), diesel::result::Error, _>(|conn| {
        occasions::table
            .filter(occasions::post_id.eq(occasion_id))
            .select(occasions::post_id)
            .for_update()
            .first::<i64>(conn)
            .optional()?;
        let upserted = upsert_rsvp_impl(request, user, conn);
        let succeeded = upserted.is_ok();
        result = Some(upserted);
        if succeeded {
            Ok(())
        } else {
            Err(RollbackTransaction)
        }
    });
    match (result, transaction_result) {
        (Some(Ok(rsvp)), Ok(())) => Ok(rsvp),
        (Some(Err(status)), _) => Err(status),
        _ => Err(Status::new(Code::Internal, "failed_to_upsert_rsvp")),
    }
}

/// The parent `Event`'s RSVP settings (`EventInfo`); unreadable stored `info` reads as all-unset.
fn event_info(event: &models::Event) -> EventInfo {
    serde_json::from_value(event.info.clone()).unwrap_or_else(|e| {
        log::warn!("Unreadable info on event {}: {:?}", event.post_id, crate::logic::log_redaction::safe_error(&e));
        EventInfo::default()
    })
}

/// The `Occasion`'s own RSVP overrides (`OccasionRsvpInfo`), if any.
fn occasion_rsvp_info(occasion: &models::Occasion) -> Option<OccasionRsvpInfo> {
    serde_json::from_value::<OccasionInfo>(occasion.info.clone())
        .map_err(|e| log::warn!("Unreadable info on occasion {}: {:?}", occasion.post_id, crate::logic::log_redaction::safe_error(&e)))
        .ok()
        .and_then(|info| info.rsvp_info)
}

/// Whether RSVPs, and anonymous RSVPs, are on for the `Occasion`: its own override if set, else the
/// `Event`'s setting, else off -- the same resolution as the Elm client's `Rsvps.rsvpsAllowed`.
fn rsvps_allowed(event: &EventInfo, occasion: &Option<OccasionRsvpInfo>) -> (bool, bool) {
    let allows = occasion
        .as_ref()
        .and_then(|o| o.allows_rsvps)
        .or(event.allows_rsvps)
        .unwrap_or(false);
    let allows_anonymous = occasion
        .as_ref()
        .and_then(|o| o.allows_anonymous_rsvps)
        .or(event.allows_anonymous_rsvps)
        .unwrap_or(false);
    (allows, allows && allows_anonymous)
}

/// The attendee limit that applies to an `Occasion`: its own `OccasionRsvpInfo.max_attendees`
/// override if set, else the parent `Event`'s `EventInfo.max_attendees`. `None` means unlimited.
fn max_attendees(event: &EventInfo, occasion: &Option<OccasionRsvpInfo>) -> Option<u32> {
    occasion
        .as_ref()
        .and_then(|o| o.max_attendees)
        .or(event.max_attendees)
}

/// Whether an RSVP with this stored `status`/`moderation` counts against the attendee limit:
/// `GOING` and passing moderation (so pending/rejected RSVPs never use up capacity).
fn counts_toward_limit(status: &str, moderation: &str) -> bool {
    status == RsvpStatus::Going.to_string_rsvp_status()
        && PASSING_MODERATIONS.iter().any(|&m| m == moderation)
}

/// Fails with `attendee_limit_reached` if adding an RSVP of `guests` to the `Occasion` would put
/// its counted attendees over the limit. `excluding_rsvp_id` leaves out the RSVP being updated.
fn check_attendee_limit(
    limit: Option<u32>,
    occasion_id: i64,
    excluding_rsvp_id: Option<i64>,
    guests: i64,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let Some(limit) = limit else {
        return Ok(());
    };
    let mut query = rsvps::table
        .filter(rsvps::occasion_id.eq(occasion_id))
        .filter(rsvps::status.eq(RsvpStatus::Going.to_string_rsvp_status()))
        .filter(rsvps::moderation.eq_any(PASSING_MODERATIONS))
        .into_boxed();
    if let Some(id) = excluding_rsvp_id {
        query = query.filter(rsvps::id.ne(id));
    }
    let taken: i64 = query
        .select(sum(rsvps::number_of_guests))
        .first::<Option<i64>>(conn)
        .map_err(|_e| Status::new(Code::Internal, "failed_to_count_attendees"))?
        .unwrap_or(0);
    if taken + guests > i64::from(limit) {
        return Err(Status::new(
            Code::FailedPrecondition,
            "attendee_limit_reached",
        ));
    }
    Ok(())
}

fn upsert_rsvp_impl(
    request: Rsvp,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<Rsvp, Status> {
    if &request.number_of_guests < &1 {
        return Err(Status::new(
            Code::InvalidArgument,
            "invalid_number_of_guests",
        ));
    }

    let occasion_id = request
        .occasion_id
        .to_db_id_or_err("occasion_id")?;

    let (event, event_post, occasion): (
        models::Event,
        models::Post,
        models::Occasion,
    ) = occasions::table
        .inner_join(events::table.on(occasions::event_id.eq(events::post_id)))
        .inner_join(posts::table.on(events::post_id.eq(posts::id)))
        .filter(occasions::post_id.eq(occasion_id))
        .select((
            events::all_columns,
            models::POST_COLUMNS,
            models::OCCASION_COLUMNS,
        ))
        .first::<(models::Event, models::Post, models::Occasion)>(conn)
        // .execute(conn)
        .map_err(|_e| Status::new(Code::Internal, "invalid_occasion_id"))?;

    let event_info = event_info(&event);
    let occasion_rsvp_info = occasion_rsvp_info(&occasion);
    let is_event_owner = user.is_some() && event_post.user_id == user.map(|u| u.id);
    let is_own_rsvp = match &request.attendee {
        Some(rsvp::Attendee::UserAttendee(attendee)) => {
            user.is_some()
                && user.unwrap().id == attendee.user_id.to_db_id_or_err("user_attendee.user_id")?
        }
        _ => false,
    };

    let attendee_user_id = match &request.attendee {
        Some(rsvp::Attendee::UserAttendee(author)) => {
            Some(author.user_id.to_db_id_or_err("author.user_id")?)
        }
        _ => None,
    };
    let attendee_avatar_media_id: Option<i64> = attendee_user_id
        .map(|user_id| {
            users::table
                .filter(users::id.eq(user_id))
                .select(users::avatar_media_id)
                .first::<Option<i64>>(conn)
                .map_err(|_e| Status::new(Code::Internal, "failed_to_load_user"))
        })
        .map(|r| r.ok())
        .flatten()
        .flatten();
    let lookup_media_ids: Vec<i64> = vec![attendee_avatar_media_id]
        .iter()
        .filter_map(|v| v.to_owned())
        .collect();
    let lookup: Option<MediaLookup> = load_media_lookup(lookup_media_ids, conn);
    let is_anonymous = attendee_user_id.is_none();

    log::info!(
        "is_event_owner: {}, is_own_rsvp: {}, is_anonymous: {}, user_id: {:?}",
        is_event_owner,
        is_own_rsvp,
        is_anonymous,
        user.map(|u| u.id)
    );

    let attendee_auth_token = request
        .attendee
        .as_ref()
        .map(|a| match a {
            rsvp::Attendee::AnonymousAttendee(u) => u.auth_token.clone(),
            _ => None,
        })
        .flatten();
    let existing_rsvp = get_rsvp(
        occasion_id,
        attendee_user_id,
        attendee_auth_token,
        conn,
    );

    let anonymous_attendee: Option<AnonymousAttendee> = match &attendee_user_id {
        Some(_user_id) => None,
        None => match request.attendee {
            Some(rsvp::Attendee::AnonymousAttendee(attendee)) => {
                Some(AnonymousAttendee {
                    name: attendee.name,
                    contact_methods: attendee.contact_methods,
                    auth_token: Some(match existing_rsvp {
                        Some(ref rsvp) => {
                            match rsvp.to_proto(true, false, None).attendee {
                                Some(rsvp::Attendee::AnonymousAttendee(
                                    AnonymousAttendee {
                                        auth_token: Some(token),
                                        ..
                                    },
                                )) => token,
                                _ => generate_token!(42),
                            }
                        }
                        None => generate_token!(42),
                    }),
                })
            }
            Some(rsvp::Attendee::UserAttendee(_)) => None,
            None => return Err(Status::new(Code::InvalidArgument, "attendee_required")),
        },
    };

    match existing_rsvp {
        Some((mut rsvp, author)) => {
            let before = rsvp.clone();
            if !is_own_rsvp && !is_event_owner && !is_anonymous {
                return Err(Status::new(
                    Code::PermissionDenied,
                    "cannot_update_rsvp",
                ));
            }

            // Update anonymous attendee data and reset moderation status.
            if is_anonymous {
                let attendee = anonymous_attendee.as_ref().unwrap();

                if &rsvp.public_note != &request.public_note
                // || &rsvp.private_note != &request.private_note
                // || &rsvp.status != &request.status
                    || &attendee.name
                        != &rsvp
                            .anonymous_attendee
                            .as_ref()
                            .unwrap()
                            .get("name")
                            .unwrap()
                            .as_str()
                            .unwrap()
                            .to_string()
                {
                    rsvp.anonymous_attendee = anonymous_attendee
                        .map(|a| serde_json::to_value(a).unwrap())
                        .or(rsvp.anonymous_attendee);
                    rsvp.moderation = Moderation::Pending.to_string_moderation();
                }
            }
            if is_event_owner {
                rsvp.moderation = match (
                    rsvp.moderation.to_proto_moderation(),
                    request.moderation.to_proto_moderation(),
                ) {
                    (_, Some(Moderation::Rejected)) => Moderation::Rejected.to_string_moderation(),
                    (_, Some(Moderation::Approved)) => Moderation::Approved.to_string_moderation(),
                    (_, Some(Moderation::Pending)) => Moderation::Pending.to_string_moderation(),
                    (_, Some(Moderation::Unmoderated)) => {
                        Moderation::Approved.to_string_moderation()
                    }
                    _ => rsvp.moderation,
                };
            }
            if is_own_rsvp || is_anonymous {
                rsvp.number_of_guests = i32::try_from(request.number_of_guests)
                    .map_err(|_e| Status::new(Code::InvalidArgument, "invalid_number_of_guests"))?;
                rsvp.public_note = request.public_note;
                rsvp.private_note = request.private_note;
                rsvp.status = request.status.to_string_rsvp_status();
            }

            // Only an RSVP that newly counts (or grows) is checked, so an unrelated edit (a note)
            // to an RSVP that's already in doesn't start failing after the limit is lowered.
            if counts_toward_limit(&rsvp.status, &rsvp.moderation)
                && (!counts_toward_limit(&before.status, &before.moderation)
                    || rsvp.number_of_guests > before.number_of_guests)
            {
                check_attendee_limit(
                    max_attendees(&event_info, &occasion_rsvp_info),
                    occasion_id,
                    Some(rsvp.id),
                    i64::from(rsvp.number_of_guests),
                    conn,
                )?;
            }

            diesel::update(rsvps::table)
                .filter(rsvps::id.eq(rsvp.id))
                .set(rsvp.clone())
                .execute(conn)
                .map_err(|_e| Status::new(Code::Internal, "failed_to_update_rsvp"))?;

            Ok((rsvp, author).to_proto(true, true, lookup.as_ref()))
        }
        None => {
            // Existing RSVPs can still be changed (e.g. to "not going") after RSVPs are switched
            // off; only new ones are refused.
            let (allows_rsvps, allows_anonymous_rsvps) =
                rsvps_allowed(&event_info, &occasion_rsvp_info);
            if !allows_rsvps {
                return Err(Status::new(Code::PermissionDenied, "rsvps_not_allowed"));
            }
            if is_anonymous && !allows_anonymous_rsvps {
                return Err(Status::new(
                    Code::PermissionDenied,
                    "anonymous_rsvps_not_allowed",
                ));
            }
            let authenticated_user_id = &user.map(|u| u.id);
            let inviting_user_id = match (authenticated_user_id, &attendee_user_id) {
                (Some(a), Some(b)) if b == a => user.map(|u| u.id),
                _ => None,
            };
            let status = match (
                inviting_user_id,
                request.status.to_proto_rsvp_status(),
            ) {
                (Some(_), _) if !is_own_rsvp => {
                    RsvpStatus::Requested.to_string_rsvp_status()
                }
                (_, Some(RsvpStatus::Going)) => {
                    RsvpStatus::Going.to_string_rsvp_status()
                }
                (_, Some(RsvpStatus::NotGoing)) => {
                    RsvpStatus::NotGoing.to_string_rsvp_status()
                }
                _ => RsvpStatus::Interested.to_string_rsvp_status(),
            };
            // Anonymous RSVPs are always moderated; logged-in users' follow the event's default
            // (`EventInfo.default_rsvp_moderation`), except the event owner's own.
            let moderation = (if is_anonymous
                || (!is_event_owner
                    && event_info.default_rsvp_moderation == Some(Moderation::Pending as i32))
            {
                Moderation::Pending
            } else {
                Moderation::Unmoderated
            })
            .to_string_moderation();
            if counts_toward_limit(&status, &moderation) {
                check_attendee_limit(
                    max_attendees(&event_info, &occasion_rsvp_info),
                    occasion_id,
                    None,
                    i64::from(request.number_of_guests),
                    conn,
                )?;
            }
            let rsvp = diesel::insert_into(rsvps::table)
                .values(NewRsvp {
                    occasion_id,
                    user_id: attendee_user_id,
                    inviting_user_id,
                    status,
                    anonymous_attendee: anonymous_attendee
                        .map(|a| serde_json::to_value(a).unwrap()),
                    number_of_guests: i32::try_from(request.number_of_guests).map_err(|_e| {
                        Status::new(Code::InvalidArgument, "invalid_number_of_guests")
                    })?,
                    public_note: request.public_note,
                    private_note: request.private_note,
                    moderation,
                })
                .get_result::<models::Rsvp>(conn)
                .map_err(|_e| Status::new(Code::Internal, "failed_to_create_rsvp"))?;
            let author = match attendee_user_id {
                Some(user_id) => Some(
                    get_author(user_id, conn)
                        .map_err(|_e| Status::new(Code::Internal, "failed_to_load_author"))?,
                ),
                _ => None,
            };
            Ok((rsvp, author).to_proto(true, true, lookup.as_ref()))
        }
    }
}
