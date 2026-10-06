use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::logic::get_custom_css_configuration;
use crate::models;
use crate::protos::*;

/// Public -- anonymous visitors' browsers need the same content via `/custom_css.css`, so nothing
/// here is secret.
pub fn get_custom_css(
    _request: (),
    _user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<CustomCssConfiguration, Status> {
    log::info!("GetCustomCSS called");
    get_custom_css_configuration(conn)
}
