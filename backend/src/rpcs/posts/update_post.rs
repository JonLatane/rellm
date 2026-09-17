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
// use crate::schema::users;

use crate::rpcs::validations::*;

pub fn update_post(
    request: Post,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Post, Status> {
    // validate_user(&request)?;
    // validate_post(&request)?;

    let admin = validate_permission(&Some(user), Permission::Admin).is_ok();

    let mut existing_post = posts::table
        .select(models::POST_COLUMNS)
        .filter(posts::id.eq(request.id.to_db_id_or_err("id")?))
        .first::<models::Post>(conn)
        .map_err(|_| Status::new(Code::NotFound, "post_not_found"))?;

    let is_event_context = vec![PostContext::Event, PostContext::Occasion]
        .iter()
        .map(|c| c.to_string_post_context())
        .any(|s| s == existing_post.context);

    // A plain Post/Reply's moderator needs `ModeratePosts`; an Event/
    // Occasion's own Post needs `ModerateEvents` instead -- mirrors the
    // `PublishEvents*`/`PublishPosts*` split just below, for the same reason
    // (this Post's `context` decides which permission family governs it).
    let moderator = validate_permission(&Some(user), Permission::ModeratePosts).is_ok()
        || (is_event_context
            && validate_permission(&Some(user), Permission::ModerateEvents).is_ok());

    let moderator_accessible_moderations = [
        Moderation::Approved,
        Moderation::Rejected,
        Moderation::Pending,
    ];
    let moderation = match (
        moderator,
        request
            .moderation
            .to_proto_moderation()
            .ok_or(Status::new(Code::InvalidArgument, "invalid_moderation"))?,
    ) {
        (true, m) if moderator_accessible_moderations.contains(&m) => Some(request.moderation),
        _ => None,
    };

    let self_update = existing_post.user_id == Some(user.id);
    log::info!(
        "self_update: {}, admin: {}, moderator: {}",
        self_update,
        admin,
        moderator
    );

    if !self_update {
        let mut required_permissions = vec![Permission::Admin, Permission::ModeratePosts];
        if is_event_context {
            required_permissions.push(Permission::ModerateEvents);
        }
        validate_any_permission(&Some(user), required_permissions)?;
    }

    if admin || self_update {
        match request.visibility() {
            Visibility::GlobalPublic => validate_permission(
                &Some(user),
                if is_event_context {
                    Permission::PublishEventsGlobally
                } else {
                    Permission::PublishPostsGlobally
                },
            )?,
            Visibility::ServerPublic => validate_permission(
                &Some(user),
                if is_event_context {
                    Permission::PublishEventsLocally
                } else {
                    Permission::PublishPostsLocally
                },
            )?,
            _ => {}
        };
    }

    let transaction_result: Result<models::Post, diesel::result::Error> = conn
        .transaction::<models::Post, diesel::result::Error, _>(|conn| {
            let now = SystemTime::now();
            if admin || self_update {
                // Only Events/Occasions support title and link updates.
                if vec![PostContext::Event, PostContext::Occasion]
                    .iter()
                    .map(|c| c.to_string_post_context())
                    .any(|s| s == existing_post.context)
                    || (existing_post.context == PostContext::Post.to_string_post_context()
                        && existing_post.published_at == None)
                {
                    existing_post.title = request.title.to_owned();
                    existing_post.link = request.link.to_owned();
                }

                // Unpublished posts also support title updates.
                if existing_post.context == PostContext::Post.to_string_post_context()
                    && existing_post.published_at == None
                {
                    existing_post.title = request.title.to_owned();
                }

                existing_post.content = request.content.to_owned();
                existing_post.media = request
                    .media
                    .iter()
                    .map(|m| m.id.to_db_id_or_err("media.id").map(|r| Some(r)))
                    .collect::<Result<Vec<Option<i64>>, Status>>()
                    .map_err(|_| diesel::result::Error::RollbackTransaction)?;

                existing_post.embed_link = request.embed_link;
                existing_post.shareable = request.shareable;
                existing_post.updated_at = now.into();
                existing_post.visibility = request.visibility.to_string_visibility();
                existing_post.post_media_layout =
                    request.post_media_layout.to_model_post_media_layout();

                // `published_at` is set once, the first time a post becomes SERVER_PUBLIC/
                // GLOBAL_PUBLIC, and is immutable thereafter - so only fill it in while it's
                // still unset, matching whatever timestamp this update is otherwise using.
                if existing_post.published_at.is_none()
                    && matches!(
                        existing_post.visibility.to_proto_visibility(),
                        Some(Visibility::ServerPublic | Visibility::GlobalPublic)
                    )
                {
                    existing_post.published_at = Some(now);
                }

                if moderation.is_some() {
                    existing_post.moderation = moderation.unwrap().to_string_moderation();
                }

                // if validate_permission(&Some(user), Permission::ModeratePosts).is_ok() {
                //     let moderation = match request.moderation.to_proto_moderation().ok_or() {
                //         Moderation::Approved | Moderation::Rejected | Moderation::Pending => {
                //             request.moderation.to_string_moderation()
                //         }
                //         _ => existing_post.moderation,
                //     };
                //     existing_post.moderation = moderation;
                // }

                // existing_post.username = request.username.to_owned();
                // existing_post.bio = request.bio.to_owned();
                // existing_post.avatar_media_id = request.avatar.as_ref().map(|a| &a.id).to_db_opt_id().unwrap();
                // if request.visibility == Visibility::GlobalPublic as i32
                //     && existing_post.visibility.to_proto_visibility().unwrap()
                //         != Visibility::GlobalPublic
                // {
                //     validate_permission(&current_user, Permission::PublishUsersGlobally)
                //         .map_err(|_| RollbackTransaction)?;
                // }
                // existing_post.visibility = request.visibility.to_string_visibility();
                // existing_post.default_follow_moderation = request.default_follow_moderation.to_string_moderation();
            }
            if admin || moderator {
                existing_post.moderation = request.moderation.to_string_moderation();
                // existing_post.permissions = request.permissions.to_json_permissions();
            }
            existing_post.updated_at = now.into();

            log::info!("Updating post: {:?}", existing_post);
            match diesel::update(posts::table)
                .filter(posts::id.eq(&existing_post.id))
                .set(&existing_post)
                .execute(conn)
            {
                Ok(_) => Ok(existing_post),
                Err(e) => Err(e),
            }
        });

    let result = match transaction_result {
        //TODO: properly marshal this stuff
        Ok(_post) => {
            rpcs::get_posts(
                GetPostsRequest {
                    post_id: Some(request.id.clone()),
                    ..Default::default()
                },
                &Some(user),
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
    log::info!("UpdatePost::request: {:?}, result: {:?}", &request, result);

    result
}
