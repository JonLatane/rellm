use std::collections::HashMap;

use diesel::*;
use diesel_full_text_search::{
    configuration::TsConfigurationByName, to_tsquery_with_search_config, ts_rank_cd,
    TsVectorExtensions,
};
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::marshaling::*;
use crate::models;
use crate::models::get_group;
use crate::models::get_membership;
use crate::protos::*;
use crate::rpcs::validate_group_permission;
use crate::schema::{follows, group_posts, memberships, posts, users};

use crate::rpcs::validations::PASSING_MODERATIONS;

const PAGE_SIZE: i64 = 200;

// The cutoff every listing branch (other than a single `post_id`/its replies) filters
// `posts::sort_published_at` against, per `GetPostsRequest.published_or_created_before`'s own
// doc comment -- `None` when unset, applying no cutoff. Cheap everywhere except
// `get_search_posts`: every other branch already orders by (and, per
// `2026-07-27-215959_add_sort_published_at_to_posts`, is indexed on) this exact column, so the
// filter rides the same index scan the ordering already needs; search instead resolves matches
// via its own GIN index on `search_text` first, so this filter there is a plain (still
// correct, just not index-assisted) predicate over that already-narrow candidate set.
fn published_or_created_before(request: &GetPostsRequest) -> Option<std::time::SystemTime> {
    request
        .published_or_created_before
        .as_ref()
        .map(|ts| ts.to_db())
}

pub fn get_posts(
    request: GetPostsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetPostsResponse, Status> {
    let cutoff = published_or_created_before(&request);
    let result = match (
        request.listing_type(),
        request.to_owned().post_id,
        request.to_owned().author_user_id,
    ) {
        (_, Some(post_id), _) => match request.reply_depth {
            None | Some(0) => get_by_post_id(&user, &post_id, conn)?,
            Some(reply_depth) => get_replies_to_post_id(&user, &post_id, reply_depth, conn)?,
        },
        (PostListingType::TextSearch, _, _) => get_search_posts(&request, &user.clone(), conn)?,
        (_, _, Some(_author_user_id)) => get_user_posts(request, &user.clone(), conn)?,
        (PostListingType::MyGroupsPosts, _, _) => get_my_group_posts(
            user.ok_or(Status::new(Code::Unauthenticated, "must_be_logged_in"))?,
            cutoff,
            conn,
        )?,
        (PostListingType::FollowingPosts, _, _) => get_following_posts(
            user.ok_or(Status::new(Code::Unauthenticated, "must_be_logged_in"))?,
            cutoff,
            conn,
        )?,
        (PostListingType::GroupPosts, _, _) => get_group_posts(
            request
                .to_owned()
                .group_id
                .ok_or(Status::new(Code::InvalidArgument, "group_id_required"))?
                .to_db_id_or_err("group_id")?,
            &user.clone(),
            vec![Moderation::Unmoderated, Moderation::Approved],
            cutoff,
            conn,
        )?,
        (PostListingType::GroupPostsPendingModeration, _, _) => {
            let binding = Some(
                user.clone()
                    .ok_or(Status::new(Code::Unauthenticated, "must_be_logged_in"))?,
            );
            get_group_posts(
                request
                    .to_owned()
                    .group_id
                    .ok_or(Status::new(Code::InvalidArgument, "group_id_required"))?
                    .to_db_id_or_err("group_id")?,
                &binding,
                vec![Moderation::Pending],
                cutoff,
                conn,
            )?
        }
        (_, None, _) => get_public_and_following_posts(&request, &user, conn),
    };

    let mut posts = convert_posts(&result, conn);
    attach_quoted_posts(&mut posts, user, conn);
    Ok(GetPostsResponse { posts })
}

macro_rules! query_visible_posts {
    ($user: expr) => {{
        posts::table
            .left_join(users::table.on(posts::user_id.eq(users::id.nullable())))
            .left_join(
                follows::table.on(posts::user_id
                    .eq(follows::target_user_id.nullable())
                    .and(follows::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0)))),
            )
            .left_join(group_posts::table.on(posts::id.eq(group_posts::post_id)))
            .left_join(
                memberships::table.on(memberships::user_id
                    .eq($user.as_ref().map(|u| u.id).unwrap_or(0))
                    .and(memberships::group_id.eq(group_posts::group_id))),
            )
            .filter(
                posts::visibility
                    .eq_any(public_string_visibilities($user))
                    .or(posts::visibility
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(follows::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    .or(posts::visibility
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(memberships::user_moderation.eq_any(PASSING_MODERATIONS))
                        .and(memberships::group_moderation.eq_any(PASSING_MODERATIONS))
                        .and(memberships::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    // .or(posts::visibility
                    //     .eq(Visibility::Private.to_string_visibility())
                    //     .and(posts::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))))
                    .or(posts::user_id.eq($user.as_ref().map(|u| u.id).unwrap_or(0))),
            )
            .distinct()
            .limit(PAGE_SIZE)
    }};
}

/// Fills in `Post.quoted_post` (one level deep -- the quoted post's own quote is left unresolved)
/// for every post in `posts` whose `quoted_post_id` the `user` can actually see. A quoted post
/// the viewer can't see (private, deleted-then-cleared, etc.) just stays `quoted_post: None`,
/// with `quoted_post_id` still set.
pub fn attach_quoted_posts(
    posts: &mut Vec<Post>,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) {
    let quoted_ids: Vec<i64> = posts
        .iter()
        .filter_map(|p| p.quoted_post_id.as_ref())
        .filter_map(|id| id.to_owned().to_db_id().ok())
        .collect();
    if quoted_ids.is_empty() {
        return;
    }
    let quoted: Vec<MarshalablePost> = query_visible_posts!(user)
        .filter(posts::id.eq_any(quoted_ids))
        .select((models::POST_COLUMNS, models::AUTHOR_COLUMNS.nullable()))
        .load::<(models::Post, Option<models::Author>)>(conn)
        .unwrap_or_default()
        .iter()
        .map(|(post, author)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect();
    let quoted_by_id: HashMap<String, Post> = convert_posts(&quoted, conn)
        .into_iter()
        .map(|p| (p.id.clone(), p))
        .collect();
    for post in posts.iter_mut() {
        if let Some(quoted_post) = post
            .quoted_post_id
            .as_ref()
            .and_then(|id| quoted_by_id.get(id))
        {
            post.quoted_post = Some(Box::new(quoted_post.clone()));
        }
    }
}

/// Whether `post_db_id` exists and is visible to `user` -- what a post must be to be quoted.
pub fn post_is_visible_to(
    user: &Option<&models::User>,
    post_db_id: i64,
    conn: &mut PgPooledConnection,
) -> bool {
    query_visible_posts!(user)
        .filter(posts::id.eq(post_db_id))
        .select(posts::id)
        .first::<i64>(conn)
        .is_ok()
}

fn get_by_post_id(
    user: &Option<&models::User>,
    post_id: &str,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    let post_db_id = match post_id.to_string().to_db_id() {
        Ok(db_id) => db_id,
        Err(_) => return Err(Status::new(Code::InvalidArgument, "post_id_invalid")),
    };
    let result: Vec<MarshalablePost> = query_visible_posts!(user)
        .filter(posts::id.eq(post_db_id))
        .select((models::POST_COLUMNS, models::AUTHOR_COLUMNS.nullable()))
        .load::<(models::Post, Option<models::Author>)>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?
        .iter()
        .map(|(post, author)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect();

    if result.len() == 0 {
        return Err(Status::new(Code::NotFound, "post_not_found"));
    }

    Ok(result)
}

// `request.context()` defaults to `Post` (see `GetPostsRequest.context`'s proto doc comment).
// The `parent_post_id IS NULL` filter only makes sense for that default POST case - it's what
// keeps this a feed of top-level posts; a real REPLY always has a parent, so requesting REPLY
// context here (e.g. "browse all accessible replies") would otherwise always come back empty.
fn get_public_and_following_posts(
    request: &GetPostsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Vec<MarshalablePost> {
    let context = request.context();

    // `sort_published_at` has to be selected explicitly (not just referenced in `.order(...)`) -
    // `query_visible_posts!`'s joins can produce more than one row per post (e.g. one cross-posted
    // to several groups), so it applies `SELECT DISTINCT`, and Postgres requires every ORDER BY
    // expression under DISTINCT to appear in the select list.
    let mut query = query_visible_posts!(user)
        .select((
            models::POST_COLUMNS,
            models::AUTHOR_COLUMNS.nullable(),
            posts::sort_published_at,
        ))
        .filter(posts::context.eq(context.as_str_name()))
        .filter(posts::user_id.is_not_null())
        .order(posts::sort_published_at.desc())
        .limit(PAGE_SIZE)
        .into_boxed();

    if context == PostContext::Post {
        query = query.filter(posts::parent_post_id.is_null());
    }

    if let Some(cutoff) = published_or_created_before(request) {
        query = query.filter(posts::sort_published_at.lt(cutoff));
    }

    query
        .load::<(models::Post, Option<models::Author>, std::time::SystemTime)>(conn)
        .unwrap()
        .iter()
        .map(|(post, author, _)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect()
}

// Full-text search across accessible posts' author username/real name, title, link, and content.
// Filters on (posts::context, posts::search_text) and, when scoped to an author, also
// posts::user_id - matching the composite GIN indexes added alongside the search_text column, so
// each of those filter combinations is served by a single index scan.
fn get_search_posts(
    request: &GetPostsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    let search_text = request
        .search_text
        .as_deref()
        .map(str::trim)
        .filter(|search_text| !search_text.is_empty())
        .ok_or(Status::new(Code::InvalidArgument, "search_text_required"))?;
    let prefix_query_text = prefix_tsquery_text(search_text);
    if prefix_query_text.is_empty() {
        return Err(Status::new(Code::InvalidArgument, "search_text_required"));
    }
    let author_user_id = request
        .author_user_id
        .as_ref()
        .map(|author_user_id| author_user_id.to_db_id_or_err("author_user_id"))
        .transpose()?;

    // Prefix (not just whole/stemmed lexeme) matching - see `prefix_tsquery_text`'s doc comment.
    // "simple" (not "english") to match posts_build_search_text's indexing config - see
    // 2026-07-23-012047_add_search_text_no_stopwords - otherwise a query for a stopword like
    // "about" would get stripped from the query side even though it's indexed on the document side.
    let search_query =
        to_tsquery_with_search_config(TsConfigurationByName("simple"), prefix_query_text.clone());
    // A second, independent tsquery expression for the rank calculation below - `search_query`
    // above is consumed by `.matches(...)`, and the generated tsquery expression type isn't Clone.
    let rank_query =
        to_tsquery_with_search_config(TsConfigurationByName("simple"), prefix_query_text);

    // `query_visible_posts!`'s joins can produce more than one row per matching post, so it
    // applies `SELECT DISTINCT` - which Postgres requires every ORDER BY expression to appear in
    // the select list for. That's fine for a plain column (see the other GetPosts branches), but
    // `ts_rank_cd(...)` takes a bind parameter, and reusing the "same" Rust expression in both
    // `.select(...)` and `.order(...)` still emits two independent bind placeholders - which
    // Postgres treats as structurally different expressions and rejects just the same. So this
    // resolves the post ids DISTINCT-ly first (a plain `posts::id` has no such problem), then
    // ranks and orders the (already-unique) matches in a second, DISTINCT-free query.
    let mut matching_post_ids = query_visible_posts!(user)
        .filter(posts::context.eq(request.context().as_str_name()))
        .filter(posts::search_text.matches(search_query))
        .select(posts::id)
        .into_boxed();

    if let Some(author_user_id) = author_user_id {
        matching_post_ids = matching_post_ids.filter(posts::user_id.eq(author_user_id));
    }

    if let Some(cutoff) = published_or_created_before(request) {
        matching_post_ids = matching_post_ids.filter(posts::sort_published_at.lt(cutoff));
    }

    let result: Vec<MarshalablePost> = posts::table
        .left_join(users::table.on(posts::user_id.eq(users::id.nullable())))
        .filter(posts::id.eq_any(matching_post_ids))
        .select((models::POST_COLUMNS, models::AUTHOR_COLUMNS.nullable()))
        // Search results are ordered by match quality first (best guess at what the user is
        // looking for), falling back to recency - `COALESCE(published_at, created_at)` - to keep
        // ordering stable across the (common, with prefix matching) rank ties rather than falling
        // through to unspecified/DB-natural order.
        .order(ts_rank_cd(posts::search_text, rank_query).desc())
        .then_order_by(posts::sort_published_at.desc())
        .limit(PAGE_SIZE)
        .load::<(models::Post, Option<models::Author>)>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?
        .iter()
        .map(|(post, author)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect();

    Ok(result)
}

fn get_my_group_posts(
    user: &models::User,
    cutoff: Option<std::time::SystemTime>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    // let is_admin = user
    //     .permissions
    //     .to_proto_permissions()
    //     .contains(&Permission::Admin);

    let mut query = query_visible_posts!(&Some(user))
        .filter(posts::context.eq(PostContext::Post.as_str_name()))
        .filter(memberships::user_id.eq(user.id))
        .filter(group_posts::group_moderation.eq_any(PASSING_MODERATIONS))
        .order(posts::sort_published_at.desc())
        .select((
            models::POST_COLUMNS,
            models::AUTHOR_COLUMNS.nullable(),
            posts::sort_published_at,
        ))
        .into_boxed();

    if let Some(cutoff) = cutoff {
        query = query.filter(posts::sort_published_at.lt(cutoff));
    }

    let result: Vec<MarshalablePost> = query
        .load::<(models::Post, Option<models::Author>, std::time::SystemTime)>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?
        .iter()
        .map(|(post, author, _)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect();

    Ok(result)
}

fn get_group_posts(
    group_id: i64,
    user: &Option<&models::User>,
    moderations: Vec<Moderation>,
    cutoff: Option<std::time::SystemTime>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    let group = get_group(group_id, conn);
    match group {
        Ok(group) => {
            let membership = user
                .map(|u| get_membership(group_id, u.id, conn).ok())
                .flatten();
            validate_group_permission(&group, &membership.as_ref(), user, Permission::ViewPosts)?;
            let group_post_users = alias!(users as group_post_users);
            let mut query = query_visible_posts!(user)
                .left_join(
                    group_post_users.on(group_posts::user_id.eq(group_post_users.field(users::id))),
                )
                .filter(posts::context.eq(PostContext::Post.as_str_name()))
                .filter(group_posts::group_id.eq(group_id))
                .filter(group_posts::group_moderation.eq_any(moderations.to_string_moderations()))
                .order(posts::sort_published_at.desc())
                .select((
                    models::POST_COLUMNS,
                    models::AUTHOR_COLUMNS.nullable(),
                    group_posts::all_columns.nullable(),
                    group_post_users.fields(models::AUTHOR_COLUMNS.nullable()),
                    posts::sort_published_at,
                ))
                .into_boxed();

            if let Some(cutoff) = cutoff {
                query = query.filter(posts::sort_published_at.lt(cutoff));
            }

            let result: Vec<MarshalablePost> = query
                .load::<(
                    models::Post,
                    Option<models::Author>,
                    Option<models::GroupPost>,
                    Option<models::Author>,
                    std::time::SystemTime,
                )>(conn)
                .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?
                .iter()
                .map(|(post, author, group_post, group_post_author, _)| {
                    MarshalablePost(
                        post.clone(),
                        author.clone(),
                        group_post.clone(),
                        group_post_author.clone(),
                        vec![],
                    )
                })
                .collect();

            Ok(result)
        }
        Err(_) => Err(Status::new(Code::NotFound, "group_not_found")),
    }
}

fn get_user_posts(
    request: GetPostsRequest,
    // user_id: i64,
    current_user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    let user_id = request
        .author_user_id
        .as_ref()
        .unwrap()
        .to_string()
        .to_db_id_or_err("user_id")?;

    let mut query = query_visible_posts!(current_user)
        .filter(posts::context.eq(request.context().as_str_name()))
        .filter(posts::user_id.eq(user_id))
        .select((
            models::POST_COLUMNS,
            models::AUTHOR_COLUMNS.nullable(),
            posts::sort_published_at,
        ))
        .order(posts::sort_published_at.desc())
        .into_boxed();

    if let Some(cutoff) = published_or_created_before(&request) {
        query = query.filter(posts::sort_published_at.lt(cutoff));
    }

    let result: Vec<MarshalablePost> = query
        .load::<(models::Post, Option<models::Author>, std::time::SystemTime)>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?
        .iter()
        .map(|(post, author, _)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect();

    Ok(result)
}

fn get_following_posts(
    user: &models::User,
    cutoff: Option<std::time::SystemTime>,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    let mut query = query_visible_posts!(&Some(user))
        .filter(posts::context.eq(PostContext::Post.as_str_name()))
        .filter(follows::user_id.eq(user.id))
        .select((
            models::POST_COLUMNS,
            models::AUTHOR_COLUMNS.nullable(),
            posts::sort_published_at,
        ))
        .order(posts::sort_published_at.desc())
        .into_boxed();

    if let Some(cutoff) = cutoff {
        query = query.filter(posts::sort_published_at.lt(cutoff));
    }

    let result: Vec<MarshalablePost> = query
        .load::<(models::Post, Option<models::Author>, std::time::SystemTime)>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?
        .iter()
        .map(|(post, author, _)| MarshalablePost(post.clone(), author.clone(), None, None, vec![]))
        .collect();

    Ok(result)
}

fn get_replies_to_post_id(
    user: &Option<&models::User>,
    post_id: &str,
    reply_depth: u32,
    conn: &mut PgPooledConnection,
) -> Result<Vec<MarshalablePost>, Status> {
    let post_db_id = match post_id.to_string().to_db_id() {
        Ok(db_id) => db_id,
        Err(_) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "replies_to_post_id_invalid",
            ))
        }
    };
    let mut replies_by_parent = get_replies_to_post_ids(user, &[post_db_id], reply_depth, conn)?;
    Ok(replies_by_parent.remove(&post_db_id).unwrap_or_default())
}

// Fetches replies to a batch of parent post ids, `reply_depth` levels deep, keyed
// by parent post id. Each depth level is a single query covering every post at
// that level (via `eq_any`), so getting replies `reply_depth` levels deep for any
// number of posts takes exactly `reply_depth` queries, not one query per post.
fn get_replies_to_post_ids(
    user: &Option<&models::User>,
    post_ids: &[i64],
    reply_depth: u32,
    conn: &mut PgPooledConnection,
) -> Result<HashMap<i64, Vec<MarshalablePost>>, Status> {
    if reply_depth == 0 || post_ids.is_empty() {
        return Ok(HashMap::new());
    }

    let level = query_visible_posts!(user)
        .filter(posts::parent_post_id.eq_any(post_ids))
        .filter(posts::user_id.is_not_null().or(posts::response_count.gt(0)))
        .select((
            models::POST_COLUMNS,
            models::AUTHOR_COLUMNS.nullable(),
            posts::sort_published_at,
        ))
        .order(posts::sort_published_at.desc())
        .limit(PAGE_SIZE)
        .load::<(models::Post, Option<models::Author>, std::time::SystemTime)>(conn)
        .map_err(|_| Status::new(Code::Internal, "error_loading_posts"))?;

    let child_ids: Vec<i64> = level.iter().map(|(post, ..)| post.id).collect();
    let mut grandchildren = get_replies_to_post_ids(user, &child_ids, reply_depth - 1, conn)?;

    let mut replies_by_parent: HashMap<i64, Vec<MarshalablePost>> = HashMap::new();
    for (post, author, _) in level {
        let replies = grandchildren.remove(&post.id).unwrap_or_default();
        replies_by_parent
            .entry(post.parent_post_id.unwrap_or(0))
            .or_default()
            .push(MarshalablePost(post, author, None, None, replies));
    }

    Ok(replies_by_parent)
}
