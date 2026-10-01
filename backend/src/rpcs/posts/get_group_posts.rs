use diesel::*;
use log::info;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::marshaling::*;
use crate::models;
use crate::models::get_group_and_membership;
use crate::models::AUTHOR_COLUMNS;
use crate::protos::Moderation::*;
use crate::protos::Permission::ModeratePosts;
use crate::protos::*;
use crate::schema::{group_posts, posts, users};

use crate::rpcs::validations::validate_group_permission;

// Get GroupPosts by either group_id+post_id or post_id alone.
// Use get_posts to get Posts (and associated GroupPosts) by group_id.
pub fn get_group_posts(
    request: GetGroupPostsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetGroupPostsResponse, Status> {
    let post_id = request.post_id.to_db_id_or_err("post_id")?;
    let query = group_posts::table
        .inner_join(posts::table.on(group_posts::post_id.eq(posts::id)))
        .left_join(users::table.on(group_posts::user_id.eq(users::id)))
        // .left_join(memberships::table.on(memberships::group_id.eq(group_posts::group_id)))
        .select((
            group_posts::all_columns,
            AUTHOR_COLUMNS.nullable(),
            posts::visibility,
            // memberships::all_columns.nullable(),
        ));
    let results: Vec<(models::GroupPost, Option<models::Author>, String)> = match request.group_id {
        None => query
            .filter(group_posts::post_id.eq(post_id))
            .load::<(models::GroupPost, Option<models::Author>, String)>(conn)
            .unwrap(),
        Some(group_id) => {
            let group_id = group_id.to_db_id_or_err("group_id")?;
            query
                .filter(group_posts::group_id.eq(group_id))
                .filter(group_posts::post_id.eq(post_id))
                .load::<(models::GroupPost, Option<models::Author>, String)>(conn)
                .unwrap()
        }
    };

    let author_avatar_media_ids = results
        .iter()
        .map(|(_, author, _)| author.as_ref().map(|a| a.avatar_media_id).flatten())
        .filter_map(|x| x)
        .collect::<Vec<i64>>();
    let media_lookup = load_media_lookup(author_avatar_media_ids, conn);
    //     .map(|(gp, author, _)| author.avatar))

    let filtered_results = results
        .iter()
        .filter_map(|(group_post, author, post_visibility)| {
            let (group, membership) =
                get_group_and_membership(group_post.group_id, user.as_ref().map(|u| u.id), conn)
                    .ok()?;

            // let membership = models::get_membership(group_post.group_id, user.as_ref().map_or(-1, |u| u.id), conn).ok();
            let moderations = match (user.as_ref(), membership.as_ref()) {
                (Some(user), Some(membership)) => {
                    match (
                        membership.passes(),
                        validate_group_permission(
                            &group,
                            &Some(&membership),
                            &Some(user),
                            ModeratePosts,
                        ),
                    ) {
                        (true, Ok(_)) => vec![Unmoderated, Approved, Pending],
                        _ => vec![Unmoderated, Approved],
                    }
                }
                _ => vec![Unmoderated, Approved],
            };

            match post_visibility.to_proto_visibility().unwrap() {
                Visibility::Limited => {
                    if !membership.as_ref().map(|m| m.passes()).unwrap_or(false) {
                        return None;
                    }
                }
                Visibility::GlobalPublic | Visibility::ServerPublic => {}
                Visibility::Unknown | Visibility::Private => return None,
                //TODO implement direct post visibility
                Visibility::Direct | Visibility::Licensed => return None,
            };

            if moderations.contains(&group_post.group_moderation.to_proto_moderation().unwrap()) {
                Some(group_post.to_proto(&author, media_lookup.as_ref()))
            } else {
                None
            }
        })
        .collect::<Vec<GroupPost>>();

    info!(
        "get_group_posts results: {}, filtered_results: {}",
        &results.len(),
        &filtered_results.len()
    );
    Ok(GetGroupPostsResponse {
        group_posts: filtered_results,
    })
}
