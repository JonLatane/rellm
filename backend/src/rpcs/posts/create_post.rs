use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::posts;

use crate::rpcs::validations::*;

pub fn create_post(
    request: Post,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<Post, Status> {
    log::info!("CreatePost called for user_id={}", user.id);
    validate_permission(&Some(user), Permission::CreatePosts)?;

    let configuration = crate::rpcs::get_server_configuration_proto(conn)?;
    match request.title.to_owned() {
        Some(t) if t.len() > 0 => match request.reply_to_post_id {
            Some(_) => {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "title_not_allowed_with_reply",
                ))
            }
            None => validate_length(&t, "title", 1, 255)?,
        },
        _ => {}
    }
    validate_max_length(request.link.to_owned(), "link", 10000)?;
    validate_max_length(request.content.to_owned(), "content", 10000)?;
    for media in &request.media {
        media.id.to_db_id_or_err("media")?;
    }
    let media_ids = request
        .media
        .iter()
        .map(|m| m.id.to_db_id().unwrap())
        .collect::<Vec<i64>>();
    let media_references: Vec<models::MediaReference> = models::get_all_media(media_ids, conn)?;
    let media_lookup: MediaLookup = media_lookup(media_references);

    // let media_references: MediaLookup = models::get_all_media(media_ids, conn)
    //     .unwrap_or_else(|e| {
    //         log::error!("Error getting media references: {:?}", e);
    //         vec![]
    //     })
    //     .iter()
    //     .map(|media| (media.id, media))
    //     .collect();

    // Generate the list of the post's ancestors so we can increment their response_count all at once.
    let mut ancestor_post_ids: Vec<i64> = vec![];
    let parent_post_db_id: Option<i64> = match request.reply_to_post_id.to_owned() {
        Some(proto_id) => match proto_id.to_db_id() {
            Ok(db_id) => {
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
            Err(_) => {
                return Err(Status::new(
                    Code::InvalidArgument,
                    "replying_to_nonexistent_post",
                ))
            }
        },
        None => None,
    };

    let visibility = match request.visibility() {
        Visibility::Unknown => Visibility::GlobalPublic,
        v => v,
    };
    match visibility {
        Visibility::GlobalPublic => {
            validate_permission(&Some(user), Permission::PublishPostsGlobally)?
        }
        Visibility::ServerPublic => {
            validate_permission(&Some(user), Permission::PublishPostsLocally)?
        }
        _ => {}
    };

    let post_title: Option<String> = match request.reply_to_post_id {
        Some(_) => None,
        None => request.to_owned().title,
    };

    let post = conn.transaction::<models::Post, diesel::result::Error, _>(|conn| {
        let inserted_post = insert_into(posts::table)
            .values(&models::NewPost {
                user_id: Some(user.id),
                parent_post_id: parent_post_db_id,
                title: post_title,
                link: request.link.to_link(),
                content: request.content.to_owned(),
                context: if parent_post_db_id.is_none() {
                    PostContext::Post
                } else {
                    PostContext::Reply
                }
                .to_string_post_context(),
                visibility: visibility.to_string_visibility(),
                media: request
                    .media
                    .iter()
                    .map(|m| m.id.to_db_id().unwrap())
                    .collect(),
                moderation: match configuration
                    .post_settings
                    .unwrap_or_default()
                    .default_moderation()
                {
                    Moderation::Pending => Moderation::Pending.as_str_name().to_string(),
                    _ => Moderation::Unmoderated.as_str_name().to_string(),
                },
            })
            .returning(models::POST_COLUMNS)
            .get_result::<models::Post>(conn)?;

        // `published_at` is set once, the first time a post becomes SERVER_PUBLIC/GLOBAL_PUBLIC,
        // and is immutable thereafter (see UpdatePost). Matching `inserted_post.created_at`
        // exactly, rather than a separately-captured `SystemTime::now()`, avoids any clock skew
        // between the two columns.
        let inserted_post = if matches!(
            visibility,
            Visibility::ServerPublic | Visibility::GlobalPublic
        ) {
            update(posts::table)
                .filter(posts::id.eq(inserted_post.id))
                .set(posts::published_at.eq(inserted_post.created_at))
                .returning(models::POST_COLUMNS)
                .get_result::<models::Post>(conn)?
        } else {
            inserted_post
        };

        if let Some(parent_id) = parent_post_db_id.to_owned() {
            update(posts::table)
                .filter(posts::id.eq(parent_id))
                .set(posts::reply_count.eq(posts::reply_count + 1))
                .execute(conn)?;
            update(posts::table)
                .filter(posts::id.eq_any(ancestor_post_ids))
                .set((
                    posts::response_count.eq(posts::response_count + 1),
                    posts::last_activity_at.eq(inserted_post.created_at),
                ))
                .execute(conn)?;
        }
        crate::logic::update_post_counts(user.id, conn)?;
        Ok(inserted_post)
    });

    match post {
        Ok(post) => {
            log::info!("Post created! PostID:{:?}", post.id);
            let author = models::get_author(user.id, conn)?;
            Ok(MarshalablePost(post, Some(author), None, None, vec![])
                .to_proto(Some(&media_lookup), None, None))
        }
        Err(e) => {
            log::error!("Error creating post! {:?}", crate::logic::log_redaction::safe_error(&e));
            Err(Status::new(Code::Internal, "internal_error"))
        }
    }
}
