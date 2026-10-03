use diesel::*;
use s3::Bucket;

use crate::models;
use crate::schema::{media, posts};

/// Deletes all `Media` with no owner (`user_id IS NULL`): removes it from any posts' `media`
/// lists, deletes its objects from storage (logging, not failing on, storage errors) and then the
/// `media` row itself.
pub async fn delete_unowned_media(
    conn: &mut PgConnection,
    bucket: &Bucket,
) -> Result<(), diesel::result::Error> {
    let unowned_media = media::table
        .filter(media::user_id.is_null())
        .load::<models::Media>(conn)?;

    for media in unowned_media.iter() {
        log::info!("Deleting Media: {:?}", media);
        let posts = posts::table
            .filter(posts::media.contains(vec![media.id]))
            .select(models::POST_COLUMNS)
            .load::<models::Post>(conn)?;
        for post in posts {
            log::info!("Removing Media {} from Post {}", media.id, post.id);
            let mut post_media = post.media.clone();
            post_media.retain(|&x| x != Some(media.id));
            update(posts::table.find(post.id))
                .set(posts::media.eq(post_media))
                .execute(conn)?;
        }

        for size in media.sizes() {
            if let Err(e) = bucket.delete_object(&size.object_storage_path).await {
                log::error!(
                    "Failed to delete object storage object {} for Media {}: {:?}. Proceeding through remaining media.",
                    size.object_storage_path,
                    media.id,
                    e
                );
            }
        }
        delete(media::table.find(media.id)).execute(conn)?;
        log::info!("Deleted Media: {:?}", media);
    }
    Ok(())
}
