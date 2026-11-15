use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_permission;
use crate::schema::ai_providers;

pub fn create_ai_provider(
    request: AiProvider,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<AiProvider, Status> {
    // Create is always for the current user -- admins may manage other users' providers (see
    // `update_ai_provider`/`delete_ai_provider`) but never create one on their behalf.
    validate_permission(&Some(current_user), Permission::CreateAiProviders)?;

    match &request.provider {
        Some(ai_provider::Provider::GeminiCredentials(credentials)) => {
            if credentials
                .gemini_api_key
                .as_ref()
                .map(|key| key.trim().is_empty())
                .unwrap_or(true)
            {
                return Err(Status::new(Code::InvalidArgument, "gemini_api_key_required"));
            }
        }
        Some(ai_provider::Provider::OpenaiCredentials(credentials)) => {
            if credentials
                .openai_api_key
                .as_ref()
                .map(|key| key.trim().is_empty())
                .unwrap_or(true)
            {
                return Err(Status::new(Code::InvalidArgument, "openai_api_key_required"));
            }
        }
        Some(ai_provider::Provider::DigitaloceanCredentials(credentials)) => {
            if credentials
                .digitalocean_api_key
                .as_ref()
                .map(|key| key.trim().is_empty())
                .unwrap_or(true)
            {
                return Err(Status::new(Code::InvalidArgument, "digitalocean_api_key_required"));
            }
        }
        Some(_) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "ai_provider_not_yet_supported",
            ));
        }
        None => return Err(Status::new(Code::InvalidArgument, "provider_required")),
    }

    let name = request.name.trim();
    if name.is_empty() {
        return Err(Status::new(Code::InvalidArgument, "name_required"));
    }

    let configuration = provider_configuration_to_json(&request.provider);

    let inserted = insert_into(ai_providers::table)
        .values(&models::NewAIProvider {
            user_id: current_user.id,
            name: name.to_string(),
            configuration,
        })
        .get_result::<models::AIProvider>(conn)
        .map_err(|e| {
            log::error!("Failed to create AI model provider: {:?}", crate::logic::log_redaction::safe_error(&e));
            Status::new(Code::Internal, "failed_to_create_ai_provider")
        })?;

    Ok(MarshalableAIProvider(inserted, current_user.to_author(), vec![]).to_proto())
}
