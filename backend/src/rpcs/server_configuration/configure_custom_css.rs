use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::*;

pub fn configure_custom_css(
    request: CustomCssConfiguration,
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<CustomCssConfiguration, Status> {
    validate_permission(&Some(user), Permission::Admin)?;
    validate_custom_css_configuration(&request, conn)?;
    save_custom_css_configuration(&request, conn)?;
    get_custom_css_configuration(conn)
}
