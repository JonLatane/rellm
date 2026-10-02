use std::collections::HashMap;
use std::mem::transmute;

use super::{
    load_media_lookup, MediaLookup, ToI32Moderation, ToProtoId, ToProtoMarshalablePost,
    ToProtoSyncDestinationStatus, ToProtoTime,
};
use crate::db_connection::PgPooledConnection;
use crate::protos::rsvp::Attendee;
use crate::protos::*;
use crate::{marshaling::ToProtoAuthor, models};

use super::{load_sync_source_lookup, MarshalablePost, SyncSourceLookup};

pub type OccasionSyncLookup = HashMap<i64, Vec<models::OccasionSyncDestination>>;

pub fn load_occasion_sync_lookup(
    occasion_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> OccasionSyncLookup {
    let mut lookup: OccasionSyncLookup = HashMap::new();
    for row in models::get_occasion_sync_destinations(occasion_ids, conn) {
        lookup.entry(row.occasion_id).or_default().push(row);
    }
    lookup
}

#[derive(Debug, Clone)]
pub struct MarshalableEvent(
    pub models::Event,
    pub MarshalablePost,
    pub Vec<MarshalableOccasion>,
);
#[derive(Debug, Clone)]
pub struct MarshalableOccasion(pub models::Occasion, pub MarshalablePost);

pub fn convert_events(data: &Vec<MarshalableEvent>, conn: &mut PgPooledConnection) -> Vec<Event> {
    let media_ids: Vec<i64> = data
        .iter()
        .map(|ref marshalable_event| {
            let post = marshalable_event.1.to_owned();
            let mut ids = post.0.media.to_owned();
            post.1
                .as_ref()
                .map(|a| a.avatar_media_id.map(|id| ids.push(Some(id))));
            post.3
                .as_ref()
                .map(|a| a.avatar_media_id.map(|id| ids.push(Some(id))));
            post.4.iter().for_each(|reply| {
                ids.extend(reply.0.media.iter());
                reply
                    .1
                    .as_ref()
                    .map(|a| a.avatar_media_id.map(|id| ids.push(Some(id))));
            });
            ids
        })
        .flatten()
        .filter(|v| v.is_some())
        .map(|v| v.unwrap())
        .collect();

    let lookup = load_media_lookup(media_ids, conn);

    let sync_source_ids: Vec<i64> = data
        .iter()
        .flat_map(|marshalable_event| {
            let mut ids: Vec<i64> = marshalable_event.1 .0.sync_source_id.into_iter().collect();
            ids.extend(
                marshalable_event
                    .2
                    .iter()
                    .filter_map(|MarshalableOccasion(_, post)| post.0.sync_source_id),
            );
            ids
        })
        .collect();
    let sync_source_lookup = load_sync_source_lookup(sync_source_ids, conn);

    let occasion_ids: Vec<i64> = data
        .iter()
        .flat_map(|marshalable_event| {
            marshalable_event
                .2
                .iter()
                .map(|MarshalableOccasion(occasion, _)| occasion.post_id)
        })
        .collect();
    let occasion_sync_lookup = load_occasion_sync_lookup(occasion_ids, conn);

    data.iter()
        .map(|marshalable_event| {
            marshalable_event.to_proto(
                lookup.as_ref(),
                sync_source_lookup.as_ref(),
                Some(&occasion_sync_lookup),
            )
        })
        .collect()
}
pub trait ToProtoMarshalableEvent {
    fn to_proto(
        &self,
        media_lookup: Option<&MediaLookup>,
        sync_source_lookup: Option<&SyncSourceLookup>,
        occasion_sync_lookup: Option<&OccasionSyncLookup>,
    ) -> Event;
}

impl ToProtoMarshalableEvent for MarshalableEvent {
    fn to_proto(
        &self,
        media_lookup: Option<&MediaLookup>,
        sync_source_lookup: Option<&SyncSourceLookup>,
        occasion_sync_lookup: Option<&OccasionSyncLookup>,
    ) -> Event {
        let event = self.0.to_owned();
        let post = self.1.to_owned();
        let occasions = self.2.to_owned();
        let hide_location = event.info["hide_location_until_rsvp_approved"]
            .as_bool()
            .unwrap_or(false);
        log::info!(
            "ToProtoMarshalableEvent hide_location={} info={:?}",
            hide_location,
            event.info
        );
        // self.to_proto(username, None)
        Event {
            post: Some(post.to_proto(media_lookup, None, sync_source_lookup)),
            occasions: occasions
                .iter()
                .map(|i| {
                    i.to_proto(
                        media_lookup,
                        hide_location,
                        occasion_sync_lookup,
                        sync_source_lookup,
                    )
                })
                .collect(),
            info: serde_json::from_value(self.0.info.to_owned()).ok(),
            ..Default::default()
        }
    }
}

pub trait ToProtoMarshalableOccasion {
    fn to_proto(
        &self,
        media_lookup: Option<&MediaLookup>,
        hide_location: bool,
        occasion_sync_lookup: Option<&OccasionSyncLookup>,
        sync_source_lookup: Option<&SyncSourceLookup>,
    ) -> Occasion;
}

impl ToProtoMarshalableOccasion for MarshalableOccasion {
    fn to_proto(
        &self,
        media_lookup: Option<&MediaLookup>,
        hide_location: bool,
        occasion_sync_lookup: Option<&OccasionSyncLookup>,
        sync_source_lookup: Option<&SyncSourceLookup>,
    ) -> Occasion {
        let occasion = self.0.to_owned();
        let marshalable_post = self.1.to_owned();
        let location: Option<Location> = if hide_location {
            None
        } else {
            occasion.location.map(|c| c.to_proto_location())
        };
        let sync_destinations = occasion_sync_lookup
            .and_then(|lookup| lookup.get(&occasion.post_id))
            .map(|rows| rows.iter().map(|row| row.to_proto()).collect())
            .unwrap_or_default();
        Occasion {
            event_id: occasion.event_id.to_proto_id(),
            post: Some(marshalable_post.to_proto(media_lookup, None, sync_source_lookup)),
            starts_at: Some(occasion.starts_at.to_proto()),
            ends_at: Some(occasion.ends_at.to_proto()),
            info: Some(OccasionInfo {
                ..Default::default()
            }),
            location,
            timezone: occasion.timezone,
            sync_destinations,
            ..Default::default()
        }
    }
}

pub trait ToProtoLocation {
    fn to_proto_location(&self) -> Location;
}

impl ToProtoLocation for serde_json::Value {
    fn to_proto_location(&self) -> Location {
        serde_json::from_value(self.to_owned()).unwrap()
    }
}

pub trait ToProtoRsvp {
    fn to_proto(
        &self,
        include_auth_tokens: bool,
        include_private_note: bool,
        media_lookup: Option<&MediaLookup>,
    ) -> Rsvp;
}

impl ToProtoRsvp for (models::Rsvp, Option<models::Author>) {
    fn to_proto(
        &self,
        include_auth_tokens: bool,
        include_private_note: bool,
        media_lookup: Option<&MediaLookup>,
    ) -> Rsvp {
        Rsvp {
            id: self.0.id.to_proto_id(),
            occasion_id: self.0.occasion_id.to_proto_id(),
            attendee: match (&self.1, &self.0.anonymous_attendee) {
                (Some(author), _) => Some(Attendee::UserAttendee(
                    author.to_proto_user_attendee(media_lookup),
                )),
                (_, Some(anonymous_attendee)) => {
                    Some(Attendee::AnonymousAttendee(AnonymousAttendee {
                        name: anonymous_attendee
                            .get("name")
                            .unwrap()
                            .as_str()
                            .unwrap()
                            .to_string(),
                        //TODO add contact methods
                        contact_methods: vec![],
                        auth_token: if include_auth_tokens {
                            Some(
                                anonymous_attendee
                                    .get("auth_token")
                                    .unwrap()
                                    .as_str()
                                    .unwrap()
                                    .to_string(),
                            )
                        } else {
                            None
                        },
                    }))
                }
                _ => None,
            },
            number_of_guests: u32::try_from(self.0.number_of_guests).unwrap(),
            status: self.0.status.to_i32_rsvp_status(),
            inviting_user_id: self.0.inviting_user_id.map(|id| id.to_proto_id()),
            public_note: self.0.public_note.clone(),
            private_note: if include_private_note {
                self.0.private_note.clone()
            } else {
                "".to_string()
            },
            moderation: self.0.moderation.to_i32_moderation(),
            created_at: Some(self.0.created_at.to_proto()),
            updated_at: self.0.updated_at.map(|t| t.to_proto()),
        }
    }
}

pub const ALL_RSVP_STATUSES: [RsvpStatus; 4] = [
    RsvpStatus::Interested,
    RsvpStatus::Requested,
    RsvpStatus::Going,
    RsvpStatus::NotGoing,
    // RsvpStatus::Went,
    // RsvpStatus::DidNotGo,
];

pub trait ToProtoRsvpStatus {
    fn to_proto_rsvp_status(&self) -> Option<RsvpStatus>;
}
impl ToProtoRsvpStatus for String {
    fn to_proto_rsvp_status(&self) -> Option<RsvpStatus> {
        for rsvp_status in ALL_RSVP_STATUSES {
            if rsvp_status.as_str_name().eq_ignore_ascii_case(self) {
                return Some(rsvp_status);
            }
        }
        return None;
    }
}
impl ToProtoRsvpStatus for i32 {
    fn to_proto_rsvp_status(&self) -> Option<RsvpStatus> {
        Some(unsafe { transmute::<i32, RsvpStatus>(*self) })
    }
}

pub trait ToStringRsvpStatus {
    fn to_string_rsvp_status(&self) -> String;
}
impl ToStringRsvpStatus for RsvpStatus {
    fn to_string_rsvp_status(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringRsvpStatus for i32 {
    fn to_string_rsvp_status(&self) -> String {
        self.to_proto_rsvp_status()
            .unwrap()
            .to_string_rsvp_status()
    }
}

pub trait ToI32RsvpStatus {
    fn to_i32_rsvp_status(&self) -> i32;
}
impl ToI32RsvpStatus for String {
    fn to_i32_rsvp_status(&self) -> i32 {
        self.to_proto_rsvp_status()
            .unwrap()
            .to_i32_rsvp_status()
    }
}
impl ToI32RsvpStatus for RsvpStatus {
    fn to_i32_rsvp_status(&self) -> i32 {
        *self as i32
    }
}
