use diesel::NotFound;
use diesel::*;
use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{adjust_server_media_usage_bytes, update_media_storage_used};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::media;

use crate::rpcs::validations::*;

pub async fn delete_media(
    request: Media,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> Result<(), Status> {
    let media_id = request.id.to_db_id_or_err("id")?;
    let affected_media = media::table
        .filter(media::id.eq(media_id))
        .get_result::<models::Media>(conn)
        .optional()
        .map_err(|e| {
            log::error!("Error finding media: {:?}", e);
            Status::new(Code::Internal, "media_not_found")
        })?;

    let affected_media = match affected_media {
        Some(affected_media) => affected_media,
        None => return Err(Status::new(Code::NotFound, "media_not_found")),
    };

    let self_delete = affected_media.user_id == Some(current_user.id);
    let mut admin = false;
    if !self_delete {
        validate_any_permission(&Some(current_user), vec![Permission::Admin])?;
    }
    match validate_permission(&Some(current_user), Permission::Admin) {
        Ok(_) => admin = true,
        Err(_) => {}
    };
    log::info!("self_delete: {}, admin: {}", self_delete, admin);

    if !(self_delete | admin) {
        return Err(Status::new(Code::PermissionDenied, "not_your_media"));
    }

    // Collect every object storage object backing this Media -- the original upload plus any
    // small/medium/large converted copies -- before the row (and its `sizes`) is gone.
    let sizes = affected_media.sizes();
    let object_storage_paths: Vec<String> = sizes.iter().map(|s| s.object_storage_path.clone()).collect();
    let deleted_bytes: i64 = sizes.iter().map(|s| s.size_bytes).sum();
    let owner_id = affected_media.user_id;

    let db_result = delete(media::table.find(media_id)).execute(conn);

    let result = match db_result {
        Ok(size) if size == 0 => Err(Status::new(Code::NotFound, "media_not_found")),
        Ok(_) => Ok(()),
        Err(NotFound) => Err(Status::new(Code::NotFound, "media_not_found")),
        Err(e) => {
            log::error!("Error deleting media: {:?}", e);
            Err(Status::new(Code::Internal, "data_error"))
        }
    };

    if result.is_ok() {
        for object_storage_path in object_storage_paths {
            if let Err(e) = bucket.delete_object(&object_storage_path).await {
                log::error!(
                    "Failed to delete object storage object {} for media {}: {:?}",
                    object_storage_path,
                    media_id,
                    e
                );
            }
        }
        if let Some(owner_id) = owner_id {
            if let Err(e) = update_media_storage_used(owner_id, conn) {
                log::error!(
                    "Failed to update media_storage_bytes_used for user {}: {:?}",
                    owner_id,
                    e
                );
            }
        }
        if let Err(e) = adjust_server_media_usage_bytes(conn, -deleted_bytes) {
            log::error!(
                "Failed to adjust server_media_usage_bytes for deleted media {}: {:?}",
                media_id,
                e
            );
        }
    }

    log::info!("DeleteMedia::request: {:?}, result: {:?}", request, result);

    result
}
