use std::collections::HashMap;

use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::{follows, media, media_filter, users};
use diesel_full_text_search::{to_tsquery_with_search_config, ts_rank_cd, configuration::TsConfigurationByName, TsVectorExtensions};
use crate::logic::prefix_tsquery_text;

/// Batch-loads every distinct author of `media_rows`, keyed by `user_id` -- see
/// `ToProtoMedia::to_proto`'s own doc on why each `Media`'s owner is populated here (rather than
/// e.g. always `None`, like most other `Media`/`MediaReference` marshaling call sites).
fn authors_by_id(media_rows: &[models::Media], conn: &mut PgPooledConnection) -> HashMap<i64, models::Author> {
    let user_ids: Vec<i64> = media_rows.iter().filter_map(|m| m.user_id).collect();
    models::get_authors(&user_ids, conn)
        .into_iter()
        .map(|author| (author.id, author))
        .collect()
}

const PAGE_SIZE: i64 = 100;

/// Visibilities any viewer may see for *other* users' media. `LICENSED` media is discoverable by
/// logged-in users, and by anonymous ones only if `MediaSettings.licensed_media_visible_globally`
/// (`licensed_globally`) is set -- its bytes are gated separately (see `Visibility::Licensed`'s doc).
fn public_media_visibilities(user: &Option<&models::User>, licensed_globally: bool) -> Vec<String> {
    let mut visibilities = vec![Visibility::GlobalPublic];
    if user.is_some() {
        visibilities.push(Visibility::ServerPublic);
    }
    if user.is_some() || licensed_globally {
        visibilities.push(Visibility::Licensed);
    }
    visibilities.to_string_visibilities()
}

/// `MediaSettings.licensed_media_visible_globally` -- off if the configuration can't be loaded.
pub fn licensed_media_visible_globally(conn: &mut PgPooledConnection) -> bool {
    crate::rpcs::get_server_configuration_proto(conn)
        .ok()
        .and_then(|c| c.media_settings)
        .is_some_and(|m| m.licensed_media_visible_globally)
}

/// Boxed `media` query pre-filtered to what `$user` may see: public(-ish) media, `LIMITED` media of
/// users they follow, and all of their own media. Mirrors `query_visible_posts!`.
macro_rules! query_visible_media {
    ($user: expr, $licensed_globally: expr) => {{
        let viewer_id = $user.as_ref().map(|u| u.id).unwrap_or(0);
        media::table
            .filter(
                media::visibility
                    .eq_any(public_media_visibilities($user, $licensed_globally))
                    .or(media::visibility
                        .eq(Visibility::Limited.to_string_visibility())
                        .and(
                            media::user_id.eq_any(
                                follows::table
                                    .filter(follows::user_id.eq(viewer_id))
                                    .select(follows::target_user_id.nullable()),
                            ),
                        ))
                    .or(media::user_id.eq(viewer_id)),
            )
            .into_boxed()
    }};
}

/// Splits a request's `content_type` into an exact match or a `type/*` wildcard prefix (`audio/`).
enum ContentTypeFilter {
    Exact(String),
    Prefix(String),
}

fn parse_content_type_filter(content_type: &str) -> Result<ContentTypeFilter, Status> {
    let content_type = content_type.trim().to_ascii_lowercase();
    let valid_part = |part: &str| {
        !part.is_empty()
            && part.chars().all(|c| c.is_ascii_alphanumeric() || "+-._".contains(c))
    };
    match content_type.split_once('/') {
        Some((main, "*")) if valid_part(main) => Ok(ContentTypeFilter::Prefix(format!("{}/", main))),
        Some((main, sub)) if valid_part(main) && valid_part(sub) => {
            Ok(ContentTypeFilter::Exact(content_type))
        }
        _ => Err(Status::invalid_argument("invalid_content_type")),
    }
}

pub fn get_media(
    request: GetMediaRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetMediaResponse, Status> {
    log::info!("GetMedia called: {:?}", request);
    let requested_user_id = match request.user_id.as_ref() {
        Some(user_id) => Some(user_id.to_db_id_or_err("user_id")?),
        None => None,
    };
    let requested_media_id = match request.media_id.as_ref() {
        Some(media_id) => Some(media_id.to_db_id_or_err("media_id")?),
        None => None,
    };
    let content_type_filter = request
        .content_type
        .as_deref()
        .map(parse_content_type_filter)
        .transpose()?;
    let search_text = request
        .search_text
        .as_deref()
        .map(str::trim)
        .filter(|search_text| !search_text.is_empty());
    let prefix_query_text = search_text.map(prefix_tsquery_text);
    if prefix_query_text.as_ref().is_some_and(|q| q.is_empty()) {
        return Err(Status::invalid_argument("search_text_required"));
    }

    let licensed_globally = licensed_media_visible_globally(conn);
    let mut query = query_visible_media!(user, licensed_globally);
    if let Some(media_id) = requested_media_id {
        query = query.filter(media::id.eq(media_id));
    }
    if let Some(user_id) = requested_user_id {
        query = query.filter(media::user_id.eq(user_id));
    }
    // Server-wide browsing (neither `media_id` nor `user_id`) is only for pages' feeds -- skip
    // media with no owner (e.g. deleted users' media) and server-generated media, so they don't
    // show up as "videos"/"audio" nobody posted.
    if requested_media_id.is_none() && requested_user_id.is_none() {
        // Also skip profile pictures, which are ordinary uploaded `Media` but not something
        // anyone posted to browse (they'd otherwise flood an `image/*` listing).
        query = query
            .filter(media::user_id.is_not_null())
            .filter(media::generated.eq(false))
            .filter(diesel::dsl::not(diesel::dsl::exists(
                users::table.filter(users::avatar_media_id.eq(media::id.nullable())),
            )));
    }
    match content_type_filter {
        Some(ContentTypeFilter::Exact(content_type)) => {
            query = query.filter(
                media::id.eq_any(
                    media_filter::table
                        .filter(media_filter::content_type.eq(content_type))
                        .select(media_filter::id),
                ),
            );
        }
        Some(ContentTypeFilter::Prefix(prefix)) => {
            query = query.filter(
                media::id.eq_any(
                    media_filter::table
                        .filter(media_filter::content_type.like(format!("{}%", prefix)))
                        .select(media_filter::id),
                ),
            );
        }
        None => {}
    }
    if let Some(prefix_query_text) = prefix_query_text.clone() {
        // "simple" to match `media_build_search_text`'s indexing config -- see `get_search_posts`.
        let search_query =
            to_tsquery_with_search_config(TsConfigurationByName("simple"), prefix_query_text.clone());
        let rank_query =
            to_tsquery_with_search_config(TsConfigurationByName("simple"), prefix_query_text);
        let matching_ids: Vec<i64> = media_filter::table
            .filter(media_filter::search_text.matches(search_query))
            .order(ts_rank_cd(media_filter::search_text, rank_query).desc())
            .select(media_filter::id)
            .limit(1000)
            .load(conn)
            .map_err(|_| Status::internal("error_loading_media"))?;
        // Ranked order is applied after loading (below) from this id list's order.
        query = query.filter(media::id.eq_any(matching_ids.clone()));
        return load_page(query, request.page, Some(matching_ids), conn);
    }

    load_page(query, request.page, None, conn)
}

/// Loads one page of `query` (newest first, or `ranked_ids` order for search results), plus whether
/// another page follows, and marshals it (with authors).
fn load_page(
    query: media::BoxedQuery<'_, diesel::pg::Pg>,
    page: u32,
    ranked_ids: Option<Vec<i64>>,
    conn: &mut PgPooledConnection,
) -> Result<GetMediaResponse, Status> {
    let mut media_rows: Vec<models::Media> = match ranked_ids {
        // Search results: page through the ranked id list itself, then fetch just that slice.
        Some(ranked_ids) => {
            let mut rows = query
                .load::<models::Media>(conn)
                .map_err(|_| Status::internal("error_loading_media"))?;
            let position = |id: i64| ranked_ids.iter().position(|r| *r == id).unwrap_or(usize::MAX);
            rows.sort_by_key(|m| position(m.id));
            rows.into_iter()
                .skip(page as usize * PAGE_SIZE as usize)
                .take(PAGE_SIZE as usize + 1)
                .collect()
        }
        None => query
            .order(media::created_at.desc())
            .limit(PAGE_SIZE + 1)
            .offset(page as i64 * PAGE_SIZE)
            .load::<models::Media>(conn)
            .map_err(|_| Status::internal("error_loading_media"))?,
    };
    let has_next_page = media_rows.len() > PAGE_SIZE as usize;
    media_rows.truncate(PAGE_SIZE as usize);

    let authors = authors_by_id(&media_rows, conn);
    // `ToProtoMedia::to_proto` leaves `Author.avatar` unresolved (see its doc), but a listing's
    // cards want to show the author's avatar -- batch-resolve them here, one level deep.
    let avatar_lookup = load_media_lookup(
        authors.values().filter_map(|a| a.avatar_media_id).collect(),
        conn,
    );
    let media = media_rows
        .iter()
        .map(|media| {
            let author = media.user_id.and_then(|uid| authors.get(&uid).cloned());
            let mut proto = media.to_proto(&author);
            if let (Some(proto_author), Some(avatar_id)) = (
                proto.author.as_mut(),
                author.as_ref().and_then(|a| a.avatar_media_id),
            ) {
                proto_author.avatar = avatar_lookup
                    .as_ref()
                    .find_media(avatar_id)
                    .map(|media_ref| Box::new(media_ref.to_proto(&None)));
            }
            proto
        })
        .collect::<Vec<_>>();
    log::info!("GetMedia response_length: {:?}", media.len());
    Ok(GetMediaResponse { media, has_next_page })
}
