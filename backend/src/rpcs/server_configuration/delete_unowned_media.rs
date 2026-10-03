use s3::Bucket;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::*;

pub async fn delete_unowned_media(
    _request: (),
    user: &models::User,
    conn: &mut PgPooledConnection,
    bucket: &Bucket,
) -> Result<(), Status> {
    log::info!("DeleteUnownedMedia called");
    validate_permission(&Some(user), Permission::Admin)?;
    logic::delete_unowned_media(conn, bucket).await.map_err(|e| {
        log::error!("Failed to delete unowned media: {:?}", e);
        Status::new(Code::Internal, "error_updating")
    })
}
