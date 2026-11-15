use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::models;
use crate::protos::{ContactIntegrationsStatus, Permission};
use crate::rpcs::validations::validate_permission;

/// See `GetContactIntegrationsStatus` in `rellm.proto`. Admin-only.
// TODO(email-providers): implemented by the provider-status workstream.
pub fn get_contact_integrations_status(
    _request: (),
    user: &models::User,
    _conn: &mut PgPooledConnection,
) -> Result<ContactIntegrationsStatus, Status> {
    validate_permission(&Some(user), Permission::Admin)?;
    Err(Status::new(Code::Unimplemented, "not_implemented_yet"))
}
