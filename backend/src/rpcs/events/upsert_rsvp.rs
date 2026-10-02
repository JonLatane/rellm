use diesel::*;

use ring::rand::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::generate_token;
use crate::marshaling::*;
use crate::models::{self, get_author, get_rsvp, NewRsvp};
use crate::protos::*;
use crate::schema::{rsvps, occasions, events, posts, users};

pub fn upsert_rsvp(
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

    let (_event, event_post, _occasion): (
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
        "is_event_owner: {}, is_own_rsvp: {}, is_anonymous: {}, user_id: {:?}, attendee: {:?}",
        is_event_owner,
        is_own_rsvp,
        is_anonymous,
        user.map(|u| u.id),
        request.attendee
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

            diesel::update(rsvps::table)
                .filter(rsvps::id.eq(rsvp.id))
                .set(rsvp.clone())
                .execute(conn)
                .map_err(|_e| Status::new(Code::Internal, "failed_to_update_rsvp"))?;

            Ok((rsvp, author).to_proto(true, true, lookup.as_ref()))
        }
        None => {
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
                    moderation: (if is_anonymous {
                        Moderation::Pending
                    } else {
                        Moderation::Unmoderated
                    })
                    .to_string_moderation(),
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
