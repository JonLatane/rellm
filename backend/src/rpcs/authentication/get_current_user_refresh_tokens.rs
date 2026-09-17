use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::{ToMediaLookup, ToProtoUser};
use crate::{models, protos};

pub fn get_current_user_refresh_tokens(
    _request: (),
    user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<protos::User, Status> {
    log::info!(
        "GetCurrentUser called for user {}, user_id={}",
        &user.username,
        user.id
    );

    let avatar: Option<models::MediaReference> = match user.avatar_media_id {
        None => None,
        Some(amid) => models::get_media_reference(amid, conn).ok(),
    };

    let lookup = avatar.to_media_lookup();
    let result = user.to_proto(&None, &None, lookup.as_ref(), &Some(user), Some(conn));
    log::info!("GetCurrentUser::response={:?}", &result);
    Ok(result)
}
