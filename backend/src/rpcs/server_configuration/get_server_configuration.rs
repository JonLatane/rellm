use crate::db_connection::PgPooledConnection;
use crate::models::default_server_configuration;
use crate::schema::server_configurations::dsl::*;
use diesel::*;
use tonic::{Code, Status};

use crate::marshaling::{ToProtoPermissions, ToProtoServerConfiguration};
use crate::{models, protos};

pub fn get_server_configuration(
    _request: (),
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<protos::ServerConfiguration, Status> {
    log::info!("GetServerConfiguration called");
    let mut result = get_server_configuration_proto(conn)?;
    // `cluster_resources` describes internal cluster topology, not anything end users need -- see
    // that field's own doc. Stripped here (rather than in `to_proto`, which has no user context)
    // so `ConfigureServer`'s own response -- always admin-only already -- can still include it.
    let is_admin = user
        .map(|u| {
            u.permissions
                .to_proto_permissions()
                .contains(&protos::Permission::Admin)
        })
        .unwrap_or(false);
    if !is_admin {
        result.cluster_resources = None;
        // `twilio_config`/`bird_config`/`telnyx_config`/`preferred_verification_apis` are
        // admin-only -- see their own proto doc. `available_verification_apis` is deliberately NOT
        // stripped here: it's the public "is SMS verification available" signal a non-admin client
        // needs (e.g. to show/hide the "Start Verification" button), and it carries no secret or
        // configuration detail itself.
        result.twilio_config = None;
        result.bird_config = None;
        result.telnyx_config = None;
        result.stripe_config = None;
        result.preferred_verification_apis = vec![];
    }
    // log::info!("GetServerConfiguration called, returning {:?}", result);
    Ok(result)
}

/// Provides access to the Rellm instance's server configuration in gRPC format.
pub fn get_server_configuration_proto(
    conn: &mut PgPooledConnection,
) -> Result<protos::ServerConfiguration, Status> {
    Ok(get_server_configuration_model(conn)?.to_proto())
}

/// Provides access to the Rellm instance's server configuration as loaded by Diesel from Postgres (so JSON is unstructured).
pub fn get_server_configuration_model(
    conn: &mut PgPooledConnection,
) -> Result<models::ServerConfiguration, Status> {
    let server_configuration = server_configurations
        .filter(active.eq(true))
        .first::<models::ServerConfiguration>(conn);
    // log::info!(
    //     "GetServerConfiguration called, found {:?}",
    //     server_configuration
    // );
    match server_configuration {
        Ok(sc) => Ok(sc),
        Err(diesel::NotFound) => {
            let result = create_default_server_configuration(conn);
            log::warn!(
                "get_server_configuration_model diesel::NotFound error {:?}",
                result
            );
            result
        }
        Err(e) => {
            log::error!("get_server_configuration_model error: {:?}", e);
            Err(Status::new(Code::Unauthenticated, "data_error"))
        }
    }
}

pub fn create_default_server_configuration(
    conn: &mut PgPooledConnection,
) -> Result<models::ServerConfiguration, Status> {
    let result = match insert_into(server_configurations)
        .values(default_server_configuration())
        .get_result::<models::ServerConfiguration>(conn)
    {
        Ok(server_configuration) => server_configuration,
        Err(e) => {
            log::error!("Error inserting default server configuration: {:?}", e);
            return Err(Status::new(
                Code::Internal,
                "error_inserting_default_server_configuration",
            ));
        }
    };
    Ok(result)
}
