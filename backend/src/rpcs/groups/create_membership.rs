use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::*;
use crate::schema::{groups, memberships};

pub fn create_membership(
    request: Membership,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Membership, Status> {
    validate_membership(&request, OperationType::Create)?;
    let group = groups::table
        .select(groups::all_columns)
        .filter(groups::id.eq(request.group_id.to_db_id_or_err("group_id")?))
        .first::<models::Group>(conn)
        .map_err(|_| Status::new(Code::NotFound, "group_not_found"))?;

    // Is the current user already in the group and an admin?
    let user_membership = match memberships::table
        .select(memberships::all_columns)
        .filter(memberships::user_id.eq(user.id))
        .filter(memberships::group_id.eq(request.group_id.to_db_id_or_err("group_id")?))
        .first::<models::Membership>(conn)
    {
        Ok(membership) => Some(membership),
        Err(diesel::NotFound) => None,
        Err(_) => return Err(Status::new(Code::Internal, "data_error")),
    };

    let result = if request.user_id.to_db_id_or_err("user_id")? == user.id {
        match user_membership {
            Some(_) => {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "membership_already_exists",
                ));
            }
            None => create_membership_for_self(request, group, user, conn),
        }
    } else {
        match user_membership {
            None => {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "membership_required_to_invite",
                ))
            }
            Some(membership) => invite_other_user(request, group, user, membership, conn),
        }
    };
    match result {
        Ok(membership) => {
            membership.update_related_counts(conn)?;
            Ok(membership.to_proto())
        }
        Err(e) => Err(e),
    }
}

fn create_membership_for_self(
    request: Membership,
    group: models::Group,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<models::Membership, Status> {
    let initial_permissions: serde_json::Value =
        match group.default_membership_moderation.to_proto_moderation() {
            Some(Moderation::Unmoderated) => group.default_membership_permissions,
            _ => Vec::<i32>::new().to_json_permissions(),
        };
    let membership: Result<models::Membership, diesel::result::Error> = conn
        .transaction::<models::Membership, diesel::result::Error, _>(|conn| {
            let membership = insert_into(memberships::table)
                .values(&models::NewMembership {
                    user_id: user.id,
                    group_id: request.group_id.to_db_id().unwrap(),
                    permissions: initial_permissions,
                    group_moderation: group.default_membership_moderation,
                    user_moderation: Moderation::Approved.to_string_moderation(),
                })
                .get_result::<models::Membership>(conn)?;
            Ok(membership)
        });
    membership.map_err(|e| {
        log::error!("Error creating membership! {:?}", crate::logic::log_redaction::safe_error(&e));
        Status::new(Code::Internal, "data_error")
    })
}

fn invite_other_user(
    request: Membership,
    group: models::Group,
    user: &models::User,
    user_membership: models::Membership,
    conn: &mut PgPooledConnection,
) -> Result<models::Membership, Status> {
    let (group_moderation, initial_permissions) = match (
        group.default_membership_moderation.to_proto_moderation(),
        validate_any_group_permission(
            &group,
            &Some(&user_membership),
            &Some(user),
            vec![Permission::Admin, Permission::ModerateUsers],
        ),
    ) {
        // Unmoderated group
        (Some(Moderation::Unmoderated), _) => (
            Moderation::Approved.to_string_moderation(),
            group.default_membership_permissions,
        ),
        // User sending invite is a moderator
        (_, Ok(_)) => (
            Moderation::Approved.to_string_moderation(),
            group.default_membership_permissions,
        ),
        // User sending invite is a regular member
        (_, Err(_)) => (
            group.default_membership_moderation,
            Vec::<i32>::new().to_json_permissions(),
        ),
    };

    let membership: Result<models::Membership, diesel::result::Error> = conn
        .transaction::<models::Membership, diesel::result::Error, _>(|conn| {
            let membership = insert_into(memberships::table)
                .values(&models::NewMembership {
                    user_id: request.user_id.to_db_id().unwrap(),
                    group_id: request.group_id.to_db_id().unwrap(),
                    permissions: initial_permissions,
                    group_moderation: group_moderation,
                    user_moderation: Moderation::Pending.to_string_moderation(),
                })
                .get_result::<models::Membership>(conn)?;
            Ok(membership)
        });
    membership.map_err(|e| {
        log::error!("Error creating membership! {:?}", crate::logic::log_redaction::safe_error(&e));
        Status::new(Code::Internal, "data_error")
    })
}
