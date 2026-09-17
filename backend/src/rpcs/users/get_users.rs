use std::collections::HashMap;

use diesel::*;
// use diesel::internal::operators_macro::FieldAliasMapper;
use diesel_full_text_search::{
    configuration::TsConfigurationByName, to_tsquery_with_search_config, TsVectorExtensions,
};
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::prefix_tsquery_text;
use crate::marshaling::*;
use crate::models;
use crate::models::MEDIA_REFERENCE_COLUMNS;
use crate::protos::UserListingType::*;
use crate::protos::*;
use crate::rpcs::validate_any_permission;
use crate::rpcs::validate_permission;
use crate::rpcs::validations::PASSING_MODERATIONS;
use crate::schema::follows;
use crate::schema::media;
use crate::schema::users;

const PAGE_SIZE: i64 = 1000;
pub fn get_users(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetUsersResponse, Status> {
    log::info!("GetUsers::request: {:?}", request);
    let mut response = match (
        &user,
        request.to_owned().listing_type.to_proto_user_listing_type(),
        request.to_owned().username,
        request.to_owned().user_id,
    ) {
        (Some(user), Some(FollowRequests), _, _) => {
            Ok(get_follow_requests(request.to_owned(), user, None, conn))
        }
        (Some(user), Some(FollowRequestsTextSearch), _, _) => Ok(get_follow_requests(
            request.to_owned(),
            user,
            Some(required_search_text(&request)?),
            conn,
        )),
        (None, Some(FollowRequests), _, _) => Ok(GetUsersResponse::default()),
        (None, Some(FollowRequestsTextSearch), _, _) => Ok(GetUsersResponse::default()),
        (_, Some(Following), _, Some(_)) => get_following(request.to_owned(), user, None, conn),
        (_, Some(FollowingTextSearch), _, Some(_)) => get_following(
            request.to_owned(),
            user,
            Some(required_search_text(&request)?),
            conn,
        ),
        (_, Some(Followers), _, Some(_)) => get_followers(request.to_owned(), user, None, conn),
        (_, Some(FollowersTextSearch), _, Some(_)) => get_followers(
            request.to_owned(),
            user,
            Some(required_search_text(&request)?),
            conn,
        ),
        (_, Some(Friends), _, Some(_)) => get_friends(request.to_owned(), user, None, conn),
        (_, Some(FriendsTextSearch), _, Some(_)) => get_friends(
            request.to_owned(),
            user,
            Some(required_search_text(&request)?),
            conn,
        ),
        (_, Some(UsersTextSearch), _, _) => Ok(get_all_users(
            request.to_owned(),
            user,
            Some(required_search_text(&request)?),
            conn,
        )),
        (_, _, Some(_), _) => Ok(get_by_username(request.to_owned(), user, conn)),
        (_, _, _, Some(_)) => get_by_user_id(request.to_owned(), user, conn),
        _ => Ok(get_all_users(request.to_owned(), user, None, conn)),
    }?;
    attach_advanced_admin_data(&mut response.users, user, conn);
    // let response = match request.to_owned().username {
    //     Some(_) => get_by_username(request.to_owned(), user, conn),
    //     None => match request.to_owned().user_id {
    //         Some(_) => get_by_user_id(request.to_owned(), user, conn),
    //         None => get_all_users(request.to_owned(), user, conn),
    //     },
    // };
    // log::info!("GetUsers::request: {:?}, response: {:?}", request, response);
    log::info!(
        "GetUsers::request: {:?}, response_length: {:?}",
        request,
        response.users.len()
    );
    Ok(response)
}

// `request.search_text`, trimmed and required non-empty - used by every `*_TEXT_SEARCH`
// `UserListingType` (see `get_users`' dispatch match). Also rejects search_text that
// `prefix_tsquery_text` can't turn into anything (e.g. all punctuation), so every downstream
// caller can assume `prefix_tsquery_text` on the value returned here is always non-empty.
fn required_search_text(request: &GetUsersRequest) -> Result<&str, Status> {
    let search_text = request
        .search_text
        .as_deref()
        .map(str::trim)
        .filter(|search_text| !search_text.is_empty())
        .ok_or(Status::new(Code::InvalidArgument, "search_text_required"))?;
    if prefix_tsquery_text(search_text).is_empty() {
        return Err(Status::new(Code::InvalidArgument, "search_text_required"));
    }
    Ok(search_text)
}

fn get_all_users(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    search_text: Option<&str>,
    conn: &mut PgPooledConnection,
) -> GetUsersResponse {
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let target_follows = alias!(follows as target_follows);
    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);
    let mut query = users::table
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.as_ref().map(|u| u.id)))),
        )
        .left_join(
            target_follows.on(target_follows_user_id.eq(users::id).and(
                target_follows_target_user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id)),
            )),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(
            users::visibility
                .eq_any(visibilities)
                .or(users::id.nullable().eq(user.map(|u| u.id))),
        )
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .into_boxed();

    if let Some(search_text) = search_text {
        // "simple" (not "english") to match users_build_search_text's indexing config - see
        // 2026-07-23-012047_add_search_text_no_stopwords.
        let search_query = to_tsquery_with_search_config(
            TsConfigurationByName("simple"),
            prefix_tsquery_text(search_text),
        );
        query = query.filter(users::search_text.matches(search_query));
    }

    let users = query
        .load::<(
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            row_user.to_proto(
                &follow.as_ref(),
                &target_follow.as_ref(),
                lookup.as_ref(),
                user,
                None,
            )
        })
        .collect();
    GetUsersResponse {
        users,
        has_next_page: false,
    }
}

fn get_follow_requests(
    request: GetUsersRequest,
    user: &models::User,
    search_text: Option<&str>,
    conn: &mut PgPooledConnection,
) -> GetUsersResponse {
    let target_follows = alias!(follows as target_follows);
    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_target_user_moderation =
        target_follows.field(follows::target_user_moderation);
    let target_follows_columns = target_follows.fields(follows::all_columns);
    let mut query = target_follows
        .inner_join(users::table.on(target_follows_user_id.eq(users::id)))
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.id))),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns,
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(target_follows_target_user_id.eq(user.id).and(
            target_follows_target_user_moderation.eq(Moderation::Pending.to_string_moderation()),
        ))
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .into_boxed();

    if let Some(search_text) = search_text {
        // "simple" (not "english") to match users_build_search_text's indexing config - see
        // 2026-07-23-012047_add_search_text_no_stopwords.
        let search_query = to_tsquery_with_search_config(
            TsConfigurationByName("simple"),
            prefix_tsquery_text(search_text),
        );
        query = query.filter(users::search_text.matches(search_query));
    }

    let users = query
        .load::<(
            models::User,
            Option<models::Follow>,
            models::Follow,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            row_user.to_proto(
                &follow.as_ref(),
                &Some(target_follow),
                lookup.as_ref(),
                &Some(user),
                None,
            )
        })
        .collect();
    GetUsersResponse {
        users,
        has_next_page: false,
    }
}

// Attaches `row_user`'s own `SyncDestination`s to `proto_user` -- only for the single-user
// `GetUsers` lookups (`get_by_username`/`get_by_user_id`), never the list-returning ones, and only
// when `user` (the viewer) is `row_user` themselves (and holds *any* of the 10 `SYNC_EVENTS_TO_*`/
// `SYNC_POSTS_TO_*` permissions, since a destination can now be any of 5 platforms) or an Admin --
// mirrors `get_sync_destinations.rs`'s own self-or-Admin gate exactly.
// `validate_permission`/`validate_any_permission` already check with `Admin` included, so the
// self-view check below also passes for an Admin viewing their own profile, with no extra
// permission needed.
pub fn attach_own_sync_destinations(
    proto_user: &mut User,
    row_user: &models::User,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) {
    let can_view_destinations = match user {
        Some(viewer) if viewer.id == row_user.id => validate_any_permission(
            &Some(viewer),
            vec![
                Permission::SyncEventsToFacebook,
                Permission::SyncPostsToFacebook,
                Permission::SyncEventsToInstagram,
                Permission::SyncPostsToInstagram,
                Permission::SyncEventsToMastodon,
                Permission::SyncPostsToMastodon,
                Permission::SyncEventsToBluesky,
                Permission::SyncPostsToBluesky,
                Permission::SyncEventsToXTwitter,
                Permission::SyncPostsToXTwitter,
                Permission::Admin,
            ],
        )
        .is_ok(),
        Some(viewer) => validate_permission(&Some(viewer), Permission::Admin).is_ok(),
        None => false,
    };
    if can_view_destinations {
        if let Ok(destinations) = models::get_sync_destinations_for_user(row_user.id, conn) {
            let mut destinations: Vec<SyncDestination> = destinations
                .into_iter()
                .map(|(destination, owner)| MarshalableSyncDestination(destination, owner).to_proto())
                .collect();
            attach_synced_counts(&mut destinations, conn);
            proto_user.sync_destinations = destinations;
        }
    }
}

/// Batch-attaches `sync_sources`/`ai_models` to every user in `users` the viewer is
/// allowed to see them for (themselves, or an Admin) -- across *every* `GetUsers` listing type, not
/// just the two single-user lookups `attach_own_sync_destinations` is restricted to (that
/// restriction is `sync_destinations`' own, unchanged, and doesn't apply here -- see
/// `protos/users.proto`'s doc on `User.sync_sources`/`User.ai_models` for why these
/// two are broader). A handful of queries total, batched via `eq_any`/
/// `build_ai_models_for_users`, regardless of how many users are in `users`.
pub fn attach_advanced_admin_data(
    users: &mut [User],
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) {
    let is_admin = validate_permission(user, Permission::Admin).is_ok();
    let viewer_id = user.map(|u| u.id);
    let allowed_ids: Vec<i64> = users
        .iter()
        .filter_map(|u| u.id.to_db_id().ok())
        .filter(|id| is_admin || Some(*id) == viewer_id)
        .collect();
    if allowed_ids.is_empty() {
        return;
    }

    if let Ok(sources) = models::get_sync_sources_for_users(&allowed_ids, conn) {
        let mut sources_by_user_id: HashMap<i64, Vec<SyncSource>> = HashMap::new();
        for (source, owner) in sources {
            sources_by_user_id
                .entry(source.user_id)
                .or_default()
                .push(MarshalableSyncSource(source, owner).to_proto());
        }
        for proto_user in users.iter_mut() {
            if let Ok(id) = proto_user.id.to_db_id() {
                if let Some(sources) = sources_by_user_id.remove(&id) {
                    proto_user.sync_sources = sources;
                }
            }
        }
    }

    if let Ok(mut available) = build_ai_models_for_users(&allowed_ids, conn) {
        for proto_user in users.iter_mut() {
            if let Ok(id) = proto_user.id.to_db_id() {
                if let Some((_, ai_models)) = available.remove(&id) {
                    proto_user.ai_models = ai_models;
                }
            }
        }
    }

    if let Ok(mut subscriptions_by_id) = build_subscriptions_for_buyers(&allowed_ids, conn) {
        for proto_user in users.iter_mut() {
            if let Ok(id) = proto_user.id.to_db_id() {
                if let Some(subscriptions) = subscriptions_by_id.remove(&id) {
                    proto_user.market_subscriptions = subscriptions;
                }
            }
        }
    }
}

/// Convenience wrapper combining `attach_own_sync_destinations` + `attach_advanced_admin_data` for
/// a single freshly-authenticated user viewing their own profile -- used by `login.rs`/
/// `create_account.rs`, where it's always a self-view (there's no separate `viewer` to thread
/// through: the user who just logged in/signed up *is* `row_user`). Without this, a client would
/// have to fire a follow-up `GetUsers` lookup just to learn its own `sync_destinations`/
/// `sync_sources`/`ai_models` right after authenticating.
pub fn attach_own_advanced_data(
    proto_user: &mut User,
    row_user: &models::User,
    conn: &mut PgPooledConnection,
) {
    attach_own_sync_destinations(proto_user, row_user, &Some(row_user), conn);
    attach_advanced_admin_data(std::slice::from_mut(proto_user), &Some(row_user), conn);
}

fn get_by_username(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> GetUsersResponse {
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let target_follows = alias!(follows as target_follows);
    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);

    let has_follow_relationship = follows::user_id
        .is_not_null()
        .or(target_follows_user_id.is_not_null());
    let is_self = users::id.nullable().eq(user.as_ref().map(|u| u.id));
    let users = users::table
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.as_ref().map(|u| u.id)))),
        )
        .left_join(
            target_follows.on(target_follows_user_id.eq(users::id).and(
                target_follows_target_user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id)),
            )),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(
            users::visibility
                .eq_any(visibilities)
                .or(is_self)
                .or(has_follow_relationship),
        )
        // .filter(users::username.ilike(format!("{}%", request.username.unwrap())))
        .filter(users::username.eq(request.username.unwrap()))
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .load::<(
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            let mut proto_user = row_user.to_proto(
                &follow.as_ref(),
                &target_follow.as_ref(),
                lookup.as_ref(),
                user,
                Some(conn),
            );
            attach_own_sync_destinations(&mut proto_user, row_user, user, conn);
            proto_user
        })
        .collect();
    GetUsersResponse {
        users,
        has_next_page: false,
    }
}

fn get_by_user_id(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetUsersResponse, Status> {
    let user_id = request.user_id.to_db_opt_id_or_err("user_id")?.unwrap();
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let target_follows = alias!(follows as target_follows);
    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);
    let users = users::table
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.as_ref().map(|u| u.id)))),
        )
        .left_join(
            target_follows.on(target_follows_user_id.eq(users::id).and(
                target_follows_target_user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id)),
            )),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(
            users::visibility
                .eq_any(visibilities)
                .or(users::id.nullable().eq(user.map(|u| u.id))),
        )
        .filter(users::id.eq(user_id))
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .load::<(
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            let mut proto_user = row_user.to_proto(
                &follow.as_ref(),
                &target_follow.as_ref(),
                lookup.as_ref(),
                user,
                Some(conn),
            );
            attach_own_sync_destinations(&mut proto_user, row_user, user, conn);
            proto_user
        })
        .collect();
    Ok(GetUsersResponse {
        users,
        has_next_page: false,
    })
}

// Lists the users that the user identified by `request.user_id` follows.
fn get_following(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    search_text: Option<&str>,
    conn: &mut PgPooledConnection,
) -> Result<GetUsersResponse, Status> {
    let target_user_id = request
        .to_owned()
        .user_id
        .to_db_opt_id_or_err("user_id")?
        .unwrap();
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let (relationship_follows, target_follows) =
        alias!(follows as relationship_follows, follows as target_follows);
    let relationship_follows_user_id = relationship_follows.field(follows::user_id);
    let relationship_follows_target_user_id = relationship_follows.field(follows::target_user_id);
    let relationship_follows_target_user_moderation =
        relationship_follows.field(follows::target_user_moderation);

    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);

    let mut query = relationship_follows
        .inner_join(users::table.on(relationship_follows_target_user_id.eq(users::id)))
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.as_ref().map(|u| u.id)))),
        )
        .left_join(
            target_follows.on(target_follows_user_id.eq(users::id).and(
                target_follows_target_user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id)),
            )),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(relationship_follows_user_id.eq(target_user_id))
        .filter(relationship_follows_target_user_moderation.eq_any(PASSING_MODERATIONS))
        .filter(
            users::visibility
                .eq_any(visibilities)
                .or(users::id.nullable().eq(user.map(|u| u.id))),
        )
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .into_boxed();

    if let Some(search_text) = search_text {
        // "simple" (not "english") to match users_build_search_text's indexing config - see
        // 2026-07-23-012047_add_search_text_no_stopwords.
        let search_query = to_tsquery_with_search_config(
            TsConfigurationByName("simple"),
            prefix_tsquery_text(search_text),
        );
        query = query.filter(users::search_text.matches(search_query));
    }

    let users = query
        .load::<(
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            row_user.to_proto(
                &follow.as_ref(),
                &target_follow.as_ref(),
                lookup.as_ref(),
                user,
                Some(conn),
            )
        })
        .collect();
    Ok(GetUsersResponse {
        users,
        has_next_page: false,
    })
}

// Lists the users that follow the user identified by `request.user_id`.
fn get_followers(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    search_text: Option<&str>,
    conn: &mut PgPooledConnection,
) -> Result<GetUsersResponse, Status> {
    let target_user_id = request
        .to_owned()
        .user_id
        .to_db_opt_id_or_err("user_id")?
        .unwrap();
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let (relationship_follows, target_follows) =
        alias!(follows as relationship_follows, follows as target_follows);
    let relationship_follows_user_id = relationship_follows.field(follows::user_id);
    let relationship_follows_target_user_id = relationship_follows.field(follows::target_user_id);
    let relationship_follows_target_user_moderation =
        relationship_follows.field(follows::target_user_moderation);

    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);

    let mut query = relationship_follows
        .inner_join(users::table.on(relationship_follows_user_id.eq(users::id)))
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.as_ref().map(|u| u.id)))),
        )
        .left_join(
            target_follows.on(target_follows_user_id.eq(users::id).and(
                target_follows_target_user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id)),
            )),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(relationship_follows_target_user_id.eq(target_user_id))
        .filter(relationship_follows_target_user_moderation.eq_any(PASSING_MODERATIONS))
        .filter(
            users::visibility
                .eq_any(visibilities)
                .or(users::id.nullable().eq(user.map(|u| u.id))),
        )
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .into_boxed();

    if let Some(search_text) = search_text {
        // "simple" (not "english") to match users_build_search_text's indexing config - see
        // 2026-07-23-012047_add_search_text_no_stopwords.
        let search_query = to_tsquery_with_search_config(
            TsConfigurationByName("simple"),
            prefix_tsquery_text(search_text),
        );
        query = query.filter(users::search_text.matches(search_query));
    }

    let users = query
        .load::<(
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            row_user.to_proto(
                &follow.as_ref(),
                &target_follow.as_ref(),
                lookup.as_ref(),
                user,
                Some(conn),
            )
        })
        .collect();
    Ok(GetUsersResponse {
        users,
        has_next_page: false,
    })
}

// Lists the users who mutually follow (and are followed by) the user
// identified by `request.user_id`.
fn get_friends(
    request: GetUsersRequest,
    user: &Option<&models::User>,
    search_text: Option<&str>,
    conn: &mut PgPooledConnection,
) -> Result<GetUsersResponse, Status> {
    let target_user_id = request
        .to_owned()
        .user_id
        .to_db_opt_id_or_err("user_id")?
        .unwrap();
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let (following_relationship, follower_relationship, target_follows) = alias!(
        follows as following_relationship,
        follows as follower_relationship,
        follows as target_follows
    );
    let following_relationship_user_id = following_relationship.field(follows::user_id);
    let following_relationship_target_user_id =
        following_relationship.field(follows::target_user_id);
    let following_relationship_target_user_moderation =
        following_relationship.field(follows::target_user_moderation);

    let follower_relationship_user_id = follower_relationship.field(follows::user_id);
    let follower_relationship_target_user_id = follower_relationship.field(follows::target_user_id);
    let follower_relationship_target_user_moderation =
        follower_relationship.field(follows::target_user_moderation);

    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);

    let mut query = following_relationship
        .inner_join(users::table.on(following_relationship_target_user_id.eq(users::id)))
        .inner_join(follower_relationship.on(follower_relationship_user_id.eq(users::id)))
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(user.as_ref().map(|u| u.id)))),
        )
        .left_join(
            target_follows.on(target_follows_user_id.eq(users::id).and(
                target_follows_target_user_id
                    .nullable()
                    .eq(user.as_ref().map(|u| u.id)),
            )),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(following_relationship_user_id.eq(target_user_id))
        .filter(following_relationship_target_user_moderation.eq_any(PASSING_MODERATIONS))
        .filter(follower_relationship_target_user_id.eq(target_user_id))
        .filter(follower_relationship_target_user_moderation.eq_any(PASSING_MODERATIONS))
        .filter(
            users::visibility
                .eq_any(visibilities)
                .or(users::id.nullable().eq(user.map(|u| u.id))),
        )
        .order(users::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .into_boxed();

    if let Some(search_text) = search_text {
        // "simple" (not "english") to match users_build_search_text's indexing config - see
        // 2026-07-23-012047_add_search_text_no_stopwords.
        let search_query = to_tsquery_with_search_config(
            TsConfigurationByName("simple"),
            prefix_tsquery_text(search_text),
        );
        query = query.filter(users::search_text.matches(search_query));
    }

    let users = query
        .load::<(
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(|(row_user, follow, target_follow, media_reference)| {
            let lookup = media_reference.to_media_lookup();
            row_user.to_proto(
                &follow.as_ref(),
                &target_follow.as_ref(),
                lookup.as_ref(),
                user,
                Some(conn),
            )
        })
        .collect();
    Ok(GetUsersResponse {
        users,
        has_next_page: false,
    })
}
