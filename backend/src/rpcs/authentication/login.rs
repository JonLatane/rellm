use bcrypt::verify;
use diesel::*;
use tonic::{Code, Status};

use crate::auth;
use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validations::*;
use crate::schema::users::dsl::*;

pub fn login(
    request: LoginRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    validate_username(&request.username)?;
    validate_password(&request.password)?;

    let permission_denied = Status::new(
        Code::PermissionDenied,
        match &request.user_id {
            Some(user_id) if user_id.len() > 0 => "invalid_password",
            _ => "invalid_username_or_password",
        },
    );
    let user_result = match &request.user_id {
        Some(user_id) if user_id.len() > 0 => users
            .select(models::USER_COLUMNS)
            .filter(id.eq(user_id.to_db_id_or_err("user_id")?))
            .first::<models::User>(conn),
        _ => users
            .select(models::USER_COLUMNS)
            .filter(username.eq(&request.username))
            .first::<models::User>(conn),
    };
    let user: models::User = match user_result {
        Err(_) => return Err(permission_denied),
        Ok(user) => user,
    };
    let avatar: Option<models::MediaReference> = match user.avatar_media_id {
        None => None,
        Some(amid) => models::get_media_reference(amid, conn).ok(),
    };

    let tokens = match verify(request.password, &user.password_salted_hash) {
        Err(_) => return Err(permission_denied),
        Ok(false) => return Err(permission_denied),
        Ok(true) => auth::generate_refresh_and_access_token(user.id, conn, &request.expires_at),
    };

    log::info!("Logged in user {}, user_id={}", &request.username, user.id);

    let lookup = avatar.to_media_lookup();

    let mut proto_user = user.to_proto(&None, &None, lookup.as_ref(), &Some(&user), Some(conn));
    crate::rpcs::attach_own_advanced_data(&mut proto_user, &user, conn);

    Ok(RefreshTokenResponse {
        refresh_token: tokens.refresh_token,
        access_token: tokens.access_token,
        user: Some(proto_user),
    })
}
