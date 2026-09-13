use diesel::*;
use tonic::Code;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;

use crate::rpcs::validations::PASSING_MODERATIONS;
use crate::schema::groups;
use crate::schema::memberships;

pub trait ToProtoGroup {
    fn to_proto_with(
        &self,
        user_membership: Option<Membership>,
        media_lookup: Option<&MediaLookup>,
    ) -> Group;
    fn to_proto(&self, conn: &mut PgPooledConnection, user: &Option<&models::User>) -> Group;
}
impl ToProtoGroup for models::Group {
    fn to_proto(&self, conn: &mut PgPooledConnection, user: &Option<&models::User>) -> Group {
        let user_membership = match user {
            Some(user) => memberships::table
                .select(memberships::all_columns)
                .filter(memberships::group_id.eq(self.id))
                .filter(memberships::user_id.eq(user.id))
                .first::<models::Membership>(conn)
                .ok(),
            None => None,
        };
        let media_reference = match self.avatar_media_id {
            Some(media_id) => models::get_media_reference(media_id, conn).ok(),
            None => None,
        };
        let media_lookup = media_reference.map(|mr| media_lookup(vec![mr]));
        self.to_proto_with(user_membership.map(|m| m.to_proto()), media_lookup.as_ref())
    }
    fn to_proto_with(
        &self,
        user_membership: Option<Membership>,
        media_lookup: Option<&MediaLookup>,
    ) -> Group {
        let avatar = match (media_lookup, &self.avatar_media_id) {
            (Some(media_lookup), Some(media_id)) => {
                media_lookup.get(media_id).map(|media| media.to_proto(&None))
            }
            _ => None,
        };
        let group = Group {
            id: self.id.to_proto_id().to_string(),
            name: self.name.to_owned(),
            shortname: self.shortname.to_owned(),
            description: self.description.to_owned(),
            avatar,
            default_membership_permissions: self
                .default_membership_permissions
                .to_i32_permissions(),
            non_member_permissions: self.non_member_permissions.to_i32_permissions(),
            default_membership_moderation: self.default_membership_moderation.to_i32_moderation(),
            default_post_moderation: self.default_post_moderation.to_i32_moderation(),
            default_event_moderation: self.default_event_moderation.to_i32_moderation(),
            visibility: self.visibility.to_i32_visibility(),
            member_count: self.member_count as u32,
            post_count: self.post_count as u32,
            event_count: self.event_count as u32,
            current_user_membership: user_membership,
            created_at: Some(self.created_at.to_proto()),
            updated_at: Some(self.updated_at.to_proto()),
        };
        return group;
    }
}

pub trait ToProtoMembership {
    fn to_proto(&self) -> Membership;
    fn update_related_counts(&self, conn: &mut PgPooledConnection) -> Result<(), Status>;
}
impl ToProtoMembership for models::Membership {
    fn to_proto(&self) -> Membership {
        let membership = Membership {
            // id: self.id.to_proto_id(),
            user_id: self.user_id.to_proto_id(),
            group_id: self.group_id.to_proto_id(),
            permissions: self.permissions.to_i32_permissions(),
            group_moderation: self.group_moderation.to_i32_moderation(),
            user_moderation: self.user_moderation.to_i32_moderation(),
            created_at: Some(self.created_at.to_proto()),
            updated_at: Some(self.updated_at.to_proto()),
        };
        // log::info!("Converted Membership: {:?}", membership);
        return membership;
    }

    fn update_related_counts(&self, conn: &mut PgPooledConnection) -> Result<(), Status> {
        let member_count = memberships::table
            .count()
            .filter(memberships::group_id.eq(self.group_id))
            .filter(memberships::group_moderation.eq_any(PASSING_MODERATIONS))
            .filter(memberships::user_moderation.eq_any(PASSING_MODERATIONS))
            .first::<i64>(conn)
            .unwrap() as i32;
        diesel::update(groups::table)
            .filter(groups::id.eq(self.group_id))
            .set(groups::member_count.eq(member_count))
            .execute(conn)
            .map_err(|_| Status::new(Code::Internal, "error_updating_member_count"))?;

        crate::logic::update_group_count(self.user_id, conn)
            .map_err(|_| Status::new(Code::Internal, "error_updating_user_group_count"))?;

        Ok(())
    }
}
