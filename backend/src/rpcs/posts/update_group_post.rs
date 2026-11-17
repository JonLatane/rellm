use std::time::SystemTime;

use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models::{self, get_group_and_membership, get_group_post};
use crate::protos::*;
use crate::rpcs::validations::*;
use crate::schema::group_posts;

// The only reason for anyone to update a group post is to change the moderation status.
// All actual data about what's posted lives in the Post itself.
pub fn update_group_post(
    request: GroupPost,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<GroupPost, Status> {
    let group_id = request.group_id.to_db_id_or_err("group_id")?;
    let post_id = request.post_id.to_db_id_or_err("post_id")?;
    let (group, membership) = get_group_and_membership(group_id, Some(current_user.id), conn)?;
    validate_group_permission(
        &group,
        &membership.as_ref(),
        &Some(current_user),
        Permission::ModeratePosts,
    )?;

    let mut existing_group_post = get_group_post(group_id, post_id, conn)?;
    existing_group_post.group_moderation = request.group_moderation.to_string_moderation();
    existing_group_post.updated_at = SystemTime::now().into();

    let media_lookup = load_media_lookup(
        current_user
            .avatar_media_id
            .map(|mid| vec![mid])
            .unwrap_or(vec![]),
        conn,
    );
    match diesel::update(group_posts::table)
        .filter(group_posts::group_id.eq(group_id))
        .filter(group_posts::post_id.eq(post_id))
        .set(&existing_group_post)
        .execute(conn)
    {
        Ok(_) => {
            existing_group_post.update_related_counts(conn)?;
            Ok(
                existing_group_post
                    .to_proto(&Some(current_user.to_author()), media_lookup.as_ref()),
            )
        }
        Err(e) => {
            log::error!("Error updating group_post: {:?}", crate::logic::log_redaction::safe_error(&e));
            Err(Status::new(Code::Internal, "error_updating_group_post"))
        }
    }
}
