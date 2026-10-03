use diesel::*;

use crate::schema::*;

/// Unlinks every generated link preview image so previews get regenerated: the generated `Media`
/// is orphaned (`user_id = NULL`; `delete_unowned_media` removes it from storage and from posts'
/// `media` lists), every post is marked as needing previews again, and all failed-attempt records
/// are forgotten so posts that had given up are eligible too.
pub fn delete_link_preview_images(conn: &mut PgConnection) -> Result<(), diesel::result::Error> {
    conn.transaction(|conn| {
        update(media::table)
            .filter(media::generated.eq(true))
            .set(media::user_id.eq(None::<i64>))
            .execute(conn)?;
        update(posts::table)
            .set(posts::media_generated.eq(false))
            .execute(conn)?;
        delete(link_preview_attempts::table).execute(conn)?;
        Ok(())
    })
}
