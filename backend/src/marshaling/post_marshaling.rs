use std::collections::HashMap;
use std::mem::transmute;

use diesel::*;
use itertools::Itertools;
use tonic::Code;
use tonic::Status;

use super::{
    load_media_lookup, load_sync_source_lookup, FindSyncSource, MediaLookup, SyncSourceLookup,
    ToI32Moderation, ToI32Visibility, ToLink, ToProtoAuthor, ToProtoId, ToProtoMarshalableSyncSource,
    ToProtoMediaReference, ToProtoSyncDestinationStatus, ToProtoTime,
};
use crate::db_connection::PgPooledConnection;
use crate::models;

use crate::protos::*;
use crate::rpcs::validations::PASSING_MODERATIONS;
use crate::schema::{group_posts, groups, posts};

pub type PostSyncLookup = HashMap<i64, Vec<models::PostSyncDestination>>;

/// Mirrors `event_marshaling::load_occasion_sync_lookup`, batched for Posts instead of
/// Occasions.
pub fn load_post_sync_lookup(post_ids: Vec<i64>, conn: &mut PgPooledConnection) -> PostSyncLookup {
    let mut lookup: PostSyncLookup = HashMap::new();
    for row in models::get_post_sync_destinations(post_ids, conn) {
        lookup.entry(row.post_id).or_default().push(row);
    }
    lookup
}

#[derive(Debug, Clone)]
pub struct MarshalablePost(
    pub models::Post,
    pub Option<models::Author>,
    pub Option<models::GroupPost>,
    pub Option<models::Author>, // GroupPost author
    pub Vec<MarshalablePost>,
);

pub fn convert_posts(data: &Vec<MarshalablePost>, conn: &mut PgPooledConnection) -> Vec<Post> {
    let media_ids: Vec<i64> = data
        .iter()
        .map(|ref post| {
            let mut ids = post.0.media.to_owned();
            post.1
                .as_ref()
                .map(|a| a.avatar_media_id.map(|id| ids.push(Some(id))));
            post.3
                .as_ref()
                .map(|a| a.avatar_media_id.map(|id| ids.push(Some(id))));
            post.4.iter().for_each(|reply| {
                ids.extend(reply.0.media.iter());
                reply
                    .1
                    .as_ref()
                    .map(|a| a.avatar_media_id.map(|id| ids.push(Some(id))));
            });
            ids
        })
        .flatten()
        .filter(|v| v.is_some())
        .map(|v| v.unwrap())
        .collect();

    let lookup = load_media_lookup(media_ids, conn);

    let post_ids: Vec<i64> = data
        .iter()
        .flat_map(|post| {
            let mut ids = vec![post.0.id];
            ids.extend(post.4.iter().map(|reply| reply.0.id));
            ids
        })
        .collect();
    let sync_lookup = load_post_sync_lookup(post_ids, conn);

    let sync_source_ids: Vec<i64> = data
        .iter()
        .flat_map(|post| {
            let mut ids: Vec<i64> = post.0.sync_source_id.into_iter().collect();
            ids.extend(post.4.iter().filter_map(|reply| reply.0.sync_source_id));
            ids
        })
        .collect();
    let sync_source_lookup = load_sync_source_lookup(sync_source_ids, conn);

    data.iter()
        .map(|marshalable_post| {
            marshalable_post.to_proto(lookup.as_ref(), Some(&sync_lookup), sync_source_lookup.as_ref())
        })
        .collect()
}

pub trait ToProtoMarshalablePost {
    fn to_proto(
        &self,
        media_lookup: Option<&MediaLookup>,
        sync_lookup: Option<&PostSyncLookup>,
        sync_source_lookup: Option<&SyncSourceLookup>,
    ) -> Post;
}

impl ToProtoMarshalablePost for MarshalablePost {
    fn to_proto(
        &self,
        media_lookup: Option<&MediaLookup>,
        sync_lookup: Option<&PostSyncLookup>,
        sync_source_lookup: Option<&SyncSourceLookup>,
    ) -> Post {
        let post = &self.0;
        let author = &self.1;
        let group_post = &self.2;
        let replies = self.4.to_owned();
        Post {
            id: post.id.to_proto_id(),
            reply_to_post_id: post.parent_post_id.map(|i| i.to_proto_id()),
            author: author.as_ref().map(|a| a.to_proto(media_lookup)),

            title: post.title.to_owned(),
            link: post.link.to_link(),
            content: post.content.to_owned(),

            response_count: post.response_count,
            reply_count: post.reply_count,
            group_count: post.group_count,
            unauthenticated_star_count: post.unauthenticated_star_count,
            current_group_post: group_post
                .as_ref()
                .map(|gp| gp.to_proto(author, media_lookup)),
            media: match media_lookup {
                Some(lookup) => post
                    .media
                    .iter()
                    .map(|v| match v {
                        Some(v) => match lookup.get(v) {
                            Some(media) => Some(media.to_proto(&None)),
                            None => None,
                        },
                        None => None,
                    })
                    .filter(|v| v.is_some())
                    .map(|v| v.unwrap())
                    .collect_vec(),
                None => vec![],
            }, // self.media.iter().map(|v| v.to_proto_id()).collect_vec(),
            media_generated: post.media_generated,
            embed_link: post.embed_link,
            shareable: post.shareable,

            context: post.context.to_i32_post_context(),
            visibility: post.visibility.to_i32_visibility(),
            moderation: post.moderation.to_i32_moderation(),
            post_media_layout: post.post_media_layout.to_i32_post_media_layout(),

            replies: replies
                .iter()
                .map(|r| r.to_proto(media_lookup, sync_lookup, sync_source_lookup))
                .collect_vec(),

            created_at: Some(post.created_at.to_proto()),
            updated_at: post.updated_at.map(|t| t.to_proto()),
            published_at: post.published_at.map(|t| t.to_proto()),
            last_activity_at: Some(post.last_activity_at.to_proto()),

            sync_destinations: sync_lookup
                .and_then(|lookup| lookup.get(&post.id))
                .map(|rows| rows.iter().map(|row| row.to_proto()).collect())
                .unwrap_or_default(),

            sync_source: post
                .sync_source_id
                .and_then(|id| sync_source_lookup.find_sync_source(id))
                .map(|source| source.to_proto()),
        }
    }
}

pub trait ToProtoGroupPost {
    fn to_proto(
        &self,
        author: &Option<models::Author>,
        media_lookup: Option<&MediaLookup>,
    ) -> GroupPost;
    fn update_related_counts(&self, conn: &mut PgPooledConnection) -> Result<(), Status>;
}
impl ToProtoGroupPost for models::GroupPost {
    fn to_proto(
        &self,
        author: &Option<models::Author>,
        media_lookup: Option<&MediaLookup>,
    ) -> GroupPost {
        return GroupPost {
            group_id: self.group_id.to_proto_id().to_string(),
            post_id: self.post_id.to_proto_id().to_string(),
            user_id: self.user_id.to_proto_id().to_string(),
            group_moderation: self.group_moderation.to_i32_moderation(),
            created_at: Some(self.created_at.to_proto()),
            shared_by: author.as_ref().map(|a| a.to_proto(media_lookup)),
            // updated_at: self.updated_at.map(|t| t.to_proto()),
        };
    }

    fn update_related_counts(&self, conn: &mut PgPooledConnection) -> Result<(), Status> {
        let post_count = group_posts::table
            .count()
            .filter(group_posts::group_id.eq(self.group_id))
            .filter(group_posts::group_moderation.eq_any(PASSING_MODERATIONS))
            .first::<i64>(conn)
            .unwrap() as i32;
        diesel::update(groups::table)
            .filter(groups::id.eq(self.group_id))
            .set(groups::post_count.eq(post_count))
            .execute(conn)
            .map_err(|_| Status::new(Code::Internal, "error_updating_group_post_count"))?;

        let group_count = group_posts::table
            .count()
            .filter(group_posts::post_id.eq(self.post_id))
            .filter(group_posts::group_moderation.eq_any(PASSING_MODERATIONS))
            .first::<i64>(conn)
            .unwrap() as i32;
        diesel::update(posts::table)
            .filter(posts::id.eq(self.post_id))
            .set(posts::group_count.eq(group_count))
            .execute(conn)
            .map_err(|_| Status::new(Code::Internal, "error_updating_post_group_count"))?;

        Ok(())
    }
}

pub const ALL_POST_CONTEXTS: [PostContext; 4] = [
    PostContext::Post,
    PostContext::Reply,
    PostContext::Event,
    PostContext::Occasion,
];
pub trait ToStringPostContext {
    fn to_string_post_context(&self) -> String;
}
impl ToStringPostContext for PostContext {
    fn to_string_post_context(&self) -> String {
        self.as_str_name().to_string()
    }
}

pub trait ToProtoPostContext {
    fn to_proto_post_context(&self) -> Option<PostContext>;
}
impl ToProtoPostContext for String {
    fn to_proto_post_context(&self) -> Option<PostContext> {
        for post_context in ALL_POST_CONTEXTS {
            if post_context.as_str_name().eq_ignore_ascii_case(self) {
                return Some(post_context);
            }
        }
        return None;
    }
}
impl ToProtoPostContext for i32 {
    fn to_proto_post_context(&self) -> Option<PostContext> {
        Some(unsafe { transmute::<i32, PostContext>(*self) })
    }
}

pub trait ToI32PostContext {
    fn to_i32_post_context(&self) -> i32;
}
impl ToI32PostContext for String {
    fn to_i32_post_context(&self) -> i32 {
        self.to_proto_post_context().unwrap() as i32
    }
}

pub trait ToProtoPostMediaLayout {
    fn to_proto_post_media_layout(&self) -> PostMediaLayout;
}
impl ToProtoPostMediaLayout for models::PostMediaLayout {
    fn to_proto_post_media_layout(&self) -> PostMediaLayout {
        match self {
            models::PostMediaLayout::MediaLayoutStandard => PostMediaLayout::MediaLayoutStandard,
            models::PostMediaLayout::MediaLayoutDynamicVerticalScroll => {
                PostMediaLayout::MediaLayoutDynamicVerticalScroll
            }
        }
    }
}

pub trait ToI32PostMediaLayout {
    fn to_i32_post_media_layout(&self) -> i32;
}
impl ToI32PostMediaLayout for models::PostMediaLayout {
    fn to_i32_post_media_layout(&self) -> i32 {
        self.to_proto_post_media_layout() as i32
    }
}

/// The reverse of `ToProtoPostMediaLayout`: maps a request's raw proto `post_media_layout` i32
/// back to the DB-backed `models::PostMediaLayout`, defaulting unrecognized values to the
/// standard layout (matches how UpdatePost/CreatePost treat other unset/invalid enum fields).
pub trait ToModelPostMediaLayout {
    fn to_model_post_media_layout(&self) -> models::PostMediaLayout;
}
impl ToModelPostMediaLayout for i32 {
    fn to_model_post_media_layout(&self) -> models::PostMediaLayout {
        match PostMediaLayout::MediaLayoutDynamicVerticalScroll as i32 == *self {
            true => models::PostMediaLayout::MediaLayoutDynamicVerticalScroll,
            false => models::PostMediaLayout::MediaLayoutStandard,
        }
    }
}
