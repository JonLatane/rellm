use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::*;

pub fn delete_link_preview_images(
    _request: (),
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    log::info!("DeleteLinkPreviewImages called");
    validate_permission(&Some(user), Permission::Admin)?;
    logic::delete_link_preview_images(conn).map_err(|e| {
        log::error!("Failed to delete link preview images: {:?}", e);
        Status::new(Code::Internal, "error_updating")
    })
}
