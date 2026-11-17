use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::ai_providers;

pub fn delete_ai_provider(
    request: DeleteAiProviderRequest,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let requested_provider = request
        .provider
        .ok_or(Status::new(Code::InvalidArgument, "provider_required"))?;
    let provider_id = requested_provider.id.to_db_id_or_err("provider.id")?;
    let existing = models::get_ai_provider(provider_id, conn)?;

    if existing.user_id != current_user.id {
        validate_permission(&Some(current_user), Permission::Admin)?;
    }

    models::delete_ai_provider_grants(existing.id, conn)?;

    diesel::delete(ai_providers::table.filter(ai_providers::id.eq(existing.id)))
        .execute(conn)
        .map_err(|e| {
            log::error!("Failed to delete AI model provider {}: {:?}", existing.id, crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_delete_ai_provider")
        })?;

    Ok(())
}
