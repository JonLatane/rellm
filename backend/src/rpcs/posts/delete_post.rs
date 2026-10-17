use std::time::SystemTime;

use diesel::result::Error::RollbackTransaction;
use diesel::NotFound;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs;
use crate::schema::posts;

use crate::rpcs::validations::*;

pub fn delete_post(
    request: Post,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Post, Status> {
    let admin = validate_permission(&Some(current_user), Permission::Admin).is_ok();
    let moderator = validate_permission(&Some(current_user), Permission::ModeratePosts).is_ok();

    let mut existing_post = posts::table
        .select(models::POST_COLUMNS)
        .filter(posts::id.eq(request.id.to_db_id_or_err("id")?))
        .first::<models::Post>(conn)
        .map_err(|_| Status::new(Code::NotFound, "post_not_found"))?;
    let mut ancestor_post_ids: Vec<i64> = vec![];
    let parent_post_db_id: Option<i64> = match existing_post.parent_post_id {
        Some(db_id) => {
            let mut ppdpid: Option<i64> = Some(db_id);
            while let Some(parent_id) = ppdpid {
                ancestor_post_ids.push(parent_id);
                ppdpid = posts::table
                    .select(posts::parent_post_id)
                    .find(parent_id)
                    .first::<Option<i64>>(conn)
                    .unwrap();
            }
            Some(db_id)
        }
        None => None,
    };

    // Captured before the post is soft-deleted below (which nulls `existing_post.user_id`) --
    // counts must be refreshed for the post's actual author, not necessarily `current_user`
    // (an admin can delete another user's post).
    let post_author_id = existing_post.user_id;

    let self_update = existing_post.user_id == Some(current_user.id);
    log::info!(
        "self_update: {}, admin: {}, moderator: {}",
        self_update,
        admin,
        moderator
    );

    if !self_update {
        validate_any_permission(&Some(current_user), vec![Permission::Admin])?;
    }
    let transaction_result: Result<models::Post, diesel::result::Error> = conn
        .transaction::<models::Post, diesel::result::Error, _>(|conn| {
            if admin || self_update {
                // Only Events/Occasions support title updates.
                if vec![PostContext::Event, PostContext::Occasion]
                    .iter()
                    .map(|c| c.to_string_post_context())
                    .any(|s| s == existing_post.context)
                {
                    existing_post.title = request.title.to_owned();
                }
                existing_post.user_id = None;
                existing_post.title = None;
                existing_post.content = None;
                existing_post.link = None;
                existing_post.media = vec![];
                existing_post.updated_at = SystemTime::now().into();
            }
            existing_post.updated_at = SystemTime::now().into();

            if parent_post_db_id.is_some() {
                update(posts::table)
                    .filter(posts::id.eq(parent_post_db_id.unwrap()))
                    .set(posts::reply_count.eq(posts::reply_count - 1))
                    .execute(conn)?;
                update(posts::table)
                    .filter(posts::id.eq_any(ancestor_post_ids))
                    .set((
                        posts::response_count.eq(posts::response_count - 1),
                        // posts::last_activity_at.eq(inserted_post.created_at),
                    ))
                    .execute(conn)?;
            }

            // The row survives a soft-delete (so the FK's `ON DELETE SET NULL` never fires) -- un-quote
            // it explicitly rather than leaving other posts embedding an empty shell.
            update(posts::table)
                .filter(posts::quoted_post_id.eq(existing_post.id))
                .set(posts::quoted_post_id.eq(None::<i64>))
                .execute(conn)?;

            log::info!("Soft deleting post: {:?}", existing_post);
            let update_result = diesel::update(posts::table)
                .filter(posts::id.eq(&existing_post.id))
                .set(&existing_post)
                .execute(conn);

            // Recomputed after the soft-delete above, so it no longer counts the just-deleted post.
            if let Some(author_id) = post_author_id {
                crate::logic::update_post_counts(author_id, conn)?;
            }

            match update_result {
                Ok(_) => Ok(existing_post),
                Err(e) => Err(e),
            }
        });

    let result = match transaction_result {
        //TODO: properly marshal this stuff
        Ok(_user) => {
            rpcs::get_posts(
                GetPostsRequest {
                    post_id: Some(request.id.clone()),
                    ..Default::default()
                },
                &Some(current_user),
                conn,
            )
            .map(|u| u.posts[0].to_owned())
            // Ok(result.to_proto(&None, &None, None))
        }
        Err(NotFound) => Err(Status::new(Code::NotFound, "user_not_found")),
        Err(RollbackTransaction) => Err(Status::new(
            Code::InvalidArgument,
            "cannot_publish_globally",
        )),
        Err(e) => {
            log::error!("Error updating user: {:?}", e);
            Err(Status::new(Code::Internal, "data_error"))
        }
    };
    log::info!("DeletePost::request: {:?}, result: {:?}", &request, result);

    result
}
