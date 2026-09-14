use std::collections::HashMap;

use super::{ToI32Moderation, ToI32Visibility, ToProtoAuthor, ToProtoId, ToProtoTime};
use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::*;

pub type MediaLookup = HashMap<i64, models::MediaReference>;

pub fn media_lookup(media: Vec<models::MediaReference>) -> MediaLookup {
    media.iter().map(|m| (m.id, m.to_owned())).collect()
}

pub trait ToMediaLookup {
    fn to_media_lookup(&self) -> Option<MediaLookup>;
}

impl ToMediaLookup for Vec<models::MediaReference> {
    fn to_media_lookup(&self) -> Option<MediaLookup> {
        Some(media_lookup(self.to_owned()))
    }
}

impl ToMediaLookup for Option<Vec<models::MediaReference>> {
    fn to_media_lookup(&self) -> Option<MediaLookup> {
        self.as_ref().map(|v| v.to_media_lookup()).flatten()
        // .unwrap_or_else(|| HashMap::new())
    }
}

impl ToMediaLookup for Option<models::MediaReference> {
    fn to_media_lookup(&self) -> Option<MediaLookup> {
        self.as_ref().map(|mr| media_lookup(vec![mr.clone()]))
    }
}

// impl ToMediaLookup for (Vec<i64>, &mut PgPooledConnection) {
pub fn load_media_lookup(
    media_ids: Vec<i64>,
    conn: &mut PgPooledConnection,
) -> Option<MediaLookup> {
    // let (media_ids, conn) = self;
    Some(
        models::get_all_media(media_ids.to_owned(), conn)
            .unwrap_or_else(|e| {
                log::error!("Error loading media references: {:?}", e);
                vec![]
            })
            .iter()
            .map(|media| (media.id, media.to_owned()))
            .collect::<MediaLookup>()
            .to_owned(),
    )
}
// }

pub trait FindMedia {
    fn find_media(&self, media_id: i64) -> Option<&models::MediaReference>;
}

impl FindMedia for MediaLookup {
    fn find_media(&self, media_id: i64) -> Option<&models::MediaReference> {
        self.get(&media_id)
    }
}

impl FindMedia for Option<&MediaLookup> {
    fn find_media(&self, media_id: i64) -> Option<&models::MediaReference> {
        self.map(|lookup| lookup.get(&media_id)).flatten()
    }
}

pub trait ToProtoMedia {
    /// `author`, if given, is marshaled in without its own avatar resolved (`ToProtoAuthor::
    /// to_proto`'s `media_lookup: None`) -- bounded on purpose: `Author.avatar` is itself a
    /// `MediaReference`, which would otherwise need an author of its own to marshal, and so on.
    /// Most callers (a `User`'s own avatar, a `Post`'s `media`, a `Group`'s logo, ...) pass
    /// `&None` here -- the owner is already obvious from context there. Only the media-specific
    /// RPCs (`GetMedia`, `UpdateMedia`, `DeleteMediaSizes`, `GenerateMedia`) populate a real one,
    /// so a caller can tell whether they own an item they're looking at directly.
    fn to_proto(&self, author: &Option<models::Author>) -> Media;
}

impl ToProtoMedia for models::Media {
    fn to_proto(&self, author: &Option<models::Author>) -> Media {
        Media {
            id: self.id.to_proto_id(),
            author: author.as_ref().map(|a| a.to_proto(None)),
            name: self.name.to_owned(),
            description: self.description.to_owned(),
            visibility: self.visibility.to_i32_visibility(),
            moderation: self.moderation.to_i32_moderation(),
            generated: self.generated,
            processed: self.processed,
            created_at: Some(self.created_at.to_proto()),
            updated_at: Some(self.updated_at.to_proto()),
            metadata: Some(self.metadata().to_proto()),
            url: None,
            sizes: self.sizes().iter().map(|s| s.to_proto()).collect(),
        }
    }
}

pub trait ToProtoMediaReference {
    /// See `ToProtoMedia::to_proto`'s own doc on `author`.
    fn to_proto(&self, author: &Option<models::Author>) -> MediaReference;
}

impl ToProtoMediaReference for models::MediaReference {
    fn to_proto(&self, author: &Option<models::Author>) -> MediaReference {
        MediaReference {
            id: self.id.to_proto_id(),
            author: author.as_ref().map(|a| Box::new(a.to_proto(None))),
            name: self.name.to_owned(),
            generated: self.generated,
            metadata: Some(self.metadata().to_proto()),
            url: None,
            description: None,
            sizes: self.sizes().iter().map(|s| s.to_proto()).collect(),
        }
    }
}

pub trait ToProtoMediaSize {
    fn to_proto(&self) -> MediaSize;
}

impl ToProtoMediaSize for models::MediaSize {
    fn to_proto(&self) -> MediaSize {
        MediaSize {
            conversion: self.conversion,
            size_bytes: self.size_bytes as u64,
            aspect_ratio: self.aspect_ratio,
            content_type: self.content_type.to_owned(),
        }
    }
}

pub trait ToProtoMediaMetadata {
    fn to_proto(&self) -> MediaMetadata;
}

impl ToProtoMediaMetadata for models::MediaMetadata {
    fn to_proto(&self) -> MediaMetadata {
        MediaMetadata {
            video_preview_time_ms: self.video_preview_time_ms.map(|ms| ms as u64),
        }
    }
}
