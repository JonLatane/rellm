use bcrypt::{hash, DEFAULT_COST};
use diesel::*;
use tonic::{Code, Status};

use crate::auth;
use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::{CreateAccountRequest, RefreshTokenResponse};
use crate::schema::users::dsl::*;

use crate::rpcs::{get_server_configuration_proto, validations::*};

pub fn create_account(
    request: CreateAccountRequest,
    conn: &mut PgPooledConnection,
) -> Result<RefreshTokenResponse, Status> {
    validate_username(&request.username)?;
    validate_password(&request.password)?;
    match request.email.to_owned() {
        Some(e) => validate_email(&e.value)?,
        None => {}
    }
    match request.email.to_owned() {
        Some(e) => validate_phone(&e.value)?,
        None => {}
    }

    let hashed_password = hash(request.password, DEFAULT_COST).unwrap();

    let req_email: Option<serde_json::Value> =
        match request.email.as_ref().map(|v| serde_json::to_value(v)) {
            None => None,
            Some(Err(_)) => None,
            Some(Ok(v)) => Some(v),
        };
    let req_phone: Option<serde_json::Value> =
        match request.phone.as_ref().map(|v| serde_json::to_value(v)) {
            None => None,
            Some(Err(_)) => None,
            Some(Ok(v)) => Some(v),
        };
    let server_configuration = get_server_configuration_proto(conn)?;
    // New users get the server's configured default media storage allocation (falls back to 15MB
    // -- see `ToProtoServerConfiguration::to_proto`'s `media_settings` deserialize -- so
    // `media_settings` is always `Some` here). Previously left unset entirely, which means
    // *unlimited* (see `MediaSettings.default_media_allocation_bytes`'s own doc) -- the actual bug
    // this fixes.
    let default_media_allocation_bytes = server_configuration
        .media_settings
        .as_ref()
        .map(|m| m.default_media_allocation_bytes as i64);
    let insert_result: Result<models::User, _> = insert_into(users)
        .values((
            username.eq(request.username.to_owned()),
            password_salted_hash.eq(hashed_password),
            email.eq(req_email),
            phone.eq(req_phone),
            permissions.eq(server_configuration
                .default_user_permissions
                .to_json_permissions()),
            moderation.eq(server_configuration
                .people_settings
                .as_ref()
                .unwrap()
                .default_moderation
                .to_string_moderation()),
            visibility.eq(server_configuration
                .people_settings
                .unwrap()
                .default_visibility
                .to_string_visibility()),
            media_storage_limit_bytes.eq(default_media_allocation_bytes),
        ))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn);

    let result = match insert_result {
        Err(e) => {
            print!("Username already exists {:?}", e);
            Err(Status::new(Code::AlreadyExists, "username_already_exists"))
        }
        Ok(user) => {
            let tokens =
                auth::generate_refresh_and_access_token(user.id, conn, &request.expires_at);
            let mut proto_user = user.to_proto(&None, &None, None, Some(conn));
            crate::rpcs::attach_own_advanced_data(&mut proto_user, &user, conn);
            Ok(RefreshTokenResponse {
                refresh_token: tokens.refresh_token,
                access_token: tokens.access_token,
                user: Some(proto_user),
            })
        }
    };

    log::info!(
        "CreateAccount::request: {:?}, result: {:?}",
        CreateAccountRequest {
            password: "<redacted>".to_string(),
            ..request
        },
        result
    );

    result
}
