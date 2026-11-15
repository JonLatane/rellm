use diesel::result::DatabaseErrorKind::UniqueViolation;
use diesel::result::Error::DatabaseError;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::models::get_media_reference;
use crate::protos::*;
use crate::schema::groups;
use crate::schema::memberships;

use crate::rpcs::validations::*;

pub fn create_group(
    request: Group,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Group, Status> {
    validate_permission(&Some(user), Permission::CreateGroups)?;
    validate_group(&request)?;

    let visibility = match request.visibility.to_proto_visibility() {
        Some(Visibility::Unknown) => Visibility::ServerPublic,
        Some(v) => v,
        _ => Visibility::ServerPublic,
    }
    .to_string_visibility();
    let default_membership_moderation =
        match request.default_membership_moderation.to_proto_moderation() {
            Some(Moderation::Pending) => Moderation::Pending,
            _ => Moderation::Unmoderated,
        }
        .to_string_moderation();
    let default_post_moderation = match request.default_post_moderation.to_proto_moderation() {
        Some(Moderation::Pending) => Moderation::Pending,
        _ => Moderation::Unmoderated,
    }
    .to_string_moderation();
    let default_event_moderation = match request.default_event_moderation.to_proto_moderation() {
        Some(Moderation::Pending) => Moderation::Pending,
        _ => Moderation::Unmoderated,
    }
    .to_string_moderation();
    let avatar = match request.avatar.as_ref().map(|a| &a.id) {
        Some(id) => get_media_reference(id.to_db_id_or_err("avatar")?, conn).ok(),
        None => None,
    };
    let avatar_media_id = avatar.clone().map(|m| m.id);
    let non_member_permissions = request.non_member_permissions.to_json_permissions();
    let mut default_membership_permissions =
        request.default_membership_permissions.to_json_permissions();
    if request.default_membership_permissions.is_empty() {
        default_membership_permissions =
            vec![Permission::ViewPosts, Permission::ViewEvents].to_json_permissions();
    }
    let mut membership: Option<models::Membership> = None;
    let name = (&request.name).clone();
    let description = (&request.description).clone();

    let derived_shortname = derive_shortname(&request.name);

    let group: Result<models::Group, diesel::result::Error> = conn
        .transaction::<models::Group, diesel::result::Error, _>(|conn| {
            let group = insert_into(groups::table)
                .values(&models::NewGroup {
                    name,
                    shortname: (&derived_shortname).clone(),
                    description,
                    avatar_media_id,
                    visibility,
                    non_member_permissions,
                    default_membership_permissions,
                    default_membership_moderation,
                    default_post_moderation,
                    default_event_moderation,
                    member_count: 1,
                })
                .get_result::<models::Group>(conn)?;

            let group_moderation =
                match request.default_membership_moderation.to_proto_moderation() {
                    Some(Moderation::Unmoderated) => Moderation::Unmoderated,
                    _ => Moderation::Approved,
                }
                .to_string_moderation();
            membership = Some(
                insert_into(memberships::table)
                    .values(&models::NewMembership {
                        user_id: user.id,
                        group_id: group.id,
                        permissions: vec![Permission::Admin].to_json_permissions(),
                        group_moderation: group_moderation,
                        user_moderation: Moderation::Approved.to_string_moderation(),
                    })
                    .get_result::<models::Membership>(conn)?,
            );
            Ok(group)
        });

    match group {
        Ok(group) => {
            log::info!("Group created: group_id={}", group.id);
            Ok(group.to_proto_with(
                membership.map(|m| m.to_proto()),
                Some(&media_lookup(avatar.map(|a| vec![a]).unwrap_or(vec![]))),
            ))
        }
        Err(DatabaseError(UniqueViolation, _)) => {
            log::error!("Error creating group: unique violation");
            Err(Status::new(Code::NotFound, "duplicate_group_name"))
        }
        Err(e) => {
            log::error!("Error creating group! {:?}", crate::logic::log_redaction::safe_error(&e));
            Err(Status::new(Code::Internal, "internal_error"))
        }
    }
}
