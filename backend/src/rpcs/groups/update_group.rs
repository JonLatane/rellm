use std::time::SystemTime;

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

use crate::rpcs::validations::*;

pub fn update_group(
    request: Group,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Group, Status> {
    validate_group(&request)?;

    let (group, membership) =
        models::get_group_and_membership(request.id.to_db_id_or_err("id")?, Some(user.id), conn)?;

    validate_group_admin(&Some(user), &group, &membership.as_ref())?;

    let mut group = groups::table
        .select(groups::all_columns)
        .filter(groups::id.eq(request.id.to_db_id_or_err("id")?))
        .first::<models::Group>(conn)
        .map_err(|_| Status::new(Code::NotFound, "group_not_found"))?;

    let avatar = match &request.avatar.map(|a| a.id) {
        Some(id) => get_media_reference(id.to_db_id_or_err("avatar")?, conn).ok(),
        None => None,
    };

    group.shortname = derive_shortname(&request.name);
    group.name = request.name;
    group.description = request.description;
    group.avatar_media_id = avatar.map(|m| m.id);

    group.visibility = request.visibility.to_string_visibility();
    group.non_member_permissions = request.non_member_permissions.to_json_permissions();
    group.default_membership_permissions =
        request.default_membership_permissions.to_json_permissions();
    group.default_membership_moderation =
        request.default_membership_moderation.to_string_moderation();

    group.updated_at = SystemTime::now().into();

    match diesel::update(groups::table)
        .filter(groups::id.eq(group.id))
        .set(&group)
        .execute(conn)
    {
        Ok(_) => Ok(group.to_proto(conn, &Some(&user))),
        Err(DatabaseError(UniqueViolation, _)) => {
            Err(Status::new(Code::NotFound, "duplicate_group_name"))
        }
        Err(e) => {
            log::error!("Error updating group! {:?}", crate::logic::log_redaction::safe_error(&e));
            Err(Status::new(Code::Internal, "data_error"))
        }
    }
}
