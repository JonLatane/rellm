use diesel::*;
use serde_json::json;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::{
    connect_facebook_page, create_session, exchange_code_for_token, exchange_long_lived_token,
    exchange_x_twitter_code_for_token, get_linked_instagram_business_account, get_me,
    get_username, server_facebook_app_credentials, server_x_twitter_app_credentials,
    threads_redirect_uri, verify_credentials, x_twitter_redirect_uri,
};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::validate_any_permission;
use crate::schema::sync_destinations;

pub fn create_sync_destination(
    request: SyncDestination,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<SyncDestination, Status> {
    // Create is always for the current user -- admins may manage other users' destinations (see
    // `update_sync_destination`/`delete_sync_destination`) but never create one on their behalf.
    //
    // Gated per-platform (`SyncEventsTo*`/`SyncPostsTo*`, whichever pair matches the platform of
    // `request.configuration`, or Admin) rather than the broader `SYNC_EVENTS_FROM_ICS`/
    // `SYNC_POSTS_FROM_RSS`/`SYNC_POSTS_FROM_ATOM` (used by `SyncSource`) since posting to a
    // third-party account is a more sensitive grant than
    // pulling events in from one. Checked *before* validating the configuration's completeness
    // below, matching this RPC's original (Facebook-only) behavior of always checking permission
    // first; an unspecified/`None` configuration falls back to requiring the Facebook pair, same
    // as before multiple platforms existed.
    match &request.configuration {
        Some(sync_destination::Configuration::FacebookPage(_)) | None => validate_any_permission(
            &Some(current_user),
            vec![
                Permission::SyncEventsToFacebook,
                Permission::SyncPostsToFacebook,
                Permission::Admin,
            ],
        )?,
        Some(sync_destination::Configuration::InstagramAccount(_)) => validate_any_permission(
            &Some(current_user),
            vec![
                Permission::SyncEventsToInstagram,
                Permission::SyncPostsToInstagram,
                Permission::Admin,
            ],
        )?,
        Some(sync_destination::Configuration::MastodonAccount(_)) => validate_any_permission(
            &Some(current_user),
            vec![
                Permission::SyncEventsToMastodon,
                Permission::SyncPostsToMastodon,
                Permission::Admin,
            ],
        )?,
        Some(sync_destination::Configuration::BlueskyAccount(_)) => validate_any_permission(
            &Some(current_user),
            vec![
                Permission::SyncEventsToBluesky,
                Permission::SyncPostsToBluesky,
                Permission::Admin,
            ],
        )?,
        Some(sync_destination::Configuration::XTwitterAccount(_)) => validate_any_permission(
            &Some(current_user),
            vec![
                Permission::SyncEventsToXTwitter,
                Permission::SyncPostsToXTwitter,
                Permission::Admin,
            ],
        )?,
        Some(sync_destination::Configuration::ThreadsAccount(_)) => validate_any_permission(
            &Some(current_user),
            vec![
                Permission::SyncEventsToThreads,
                Permission::SyncPostsToThreads,
                Permission::Admin,
            ],
        )?,
    };

    let configuration = match request.configuration {
        Some(sync_destination::Configuration::FacebookPage(FacebookPage {
            page_id,
            short_lived_user_access_token: Some(short_lived_user_access_token),
            ..
        })) if !page_id.trim().is_empty() && !short_lived_user_access_token.trim().is_empty() => {
            let (app_id, app_secret) = server_facebook_app_credentials(conn)?;
            let connection = connect_facebook_page(
                &app_id,
                &app_secret,
                &short_lived_user_access_token,
                &page_id,
            )?;
            json!({
                "facebook_page": {
                    "page_id": connection.page_id,
                    "page_name": connection.page_name,
                    "access_token": connection.access_token,
                }
            })
        }
        Some(sync_destination::Configuration::InstagramAccount(InstagramAccount {
            page_id,
            short_lived_user_access_token: Some(short_lived_user_access_token),
            ..
        })) if !page_id.trim().is_empty() && !short_lived_user_access_token.trim().is_empty() => {
            // Instagram posting piggybacks on a linked Facebook Page's access token, so this
            // reuses the exact same OAuth exchange as `FacebookPage` -- see `connect_facebook_page`.
            let (app_id, app_secret) = server_facebook_app_credentials(conn)?;
            let connection = connect_facebook_page(
                &app_id,
                &app_secret,
                &short_lived_user_access_token,
                &page_id,
            )?;
            let (instagram_business_account_id, username) =
                get_linked_instagram_business_account(&connection.access_token, &connection.page_id)?;
            json!({
                "instagram_account": {
                    "instagram_business_account_id": instagram_business_account_id,
                    "username": username,
                    "page_id": connection.page_id,
                    "access_token": connection.access_token,
                }
            })
        }
        Some(sync_destination::Configuration::MastodonAccount(MastodonAccount {
            instance_host,
            access_token: Some(access_token),
            ..
        })) if !instance_host.trim().is_empty() && !access_token.trim().is_empty() => {
            let username = verify_credentials(&instance_host, &access_token)?;
            json!({
                "mastodon_account": {
                    "instance_host": instance_host,
                    "username": username,
                    "access_token": access_token,
                }
            })
        }
        Some(sync_destination::Configuration::BlueskyAccount(BlueskyAccount {
            handle,
            app_password: Some(app_password),
            ..
        })) if !handle.trim().is_empty() && !app_password.trim().is_empty() => {
            // Only used to validate the handle/app-password pair (and learn the `did`) -- the
            // session JWT itself is discarded; `logic::sync_destinations::bluesky_sync::post_record` re-authenticates
            // fresh on every post instead of storing/refreshing it.
            let (did, _access_jwt) = create_session(&handle, &app_password)?;
            json!({
                "bluesky_account": {
                    "handle": handle,
                    "did": did,
                    "app_password": app_password,
                }
            })
        }
        Some(sync_destination::Configuration::XTwitterAccount(XTwitterAccount {
            authorization_code: Some(authorization_code),
            code_verifier: Some(code_verifier),
            ..
        })) if !authorization_code.trim().is_empty() && !code_verifier.trim().is_empty() => {
            // One admin-registered X Developer App (`server_x_twitter_app_credentials`) shared by
            // every user's own connected account -- see `XTwitterAccount`'s own proto doc. X
            // mandates PKCE, unlike Threads' plain code exchange, hence `code_verifier` alongside
            // `authorization_code` (see `logic::sync_destinations::x_twitter_sync`'s module doc for why the popup
            // uses the weaker `plain` PKCE method rather than `S256`).
            let (client_id, client_secret) = server_x_twitter_app_credentials(conn)?;
            let redirect_uri = x_twitter_redirect_uri(conn)?;
            let (access_token, refresh_token, expires_in) = exchange_x_twitter_code_for_token(
                &client_id,
                &client_secret,
                &authorization_code,
                &code_verifier,
                &redirect_uri,
            )?;
            let (x_user_id, username) = get_me(&access_token)?;
            let expires_at = chrono::Utc::now().timestamp() + expires_in;
            json!({
                "x_twitter_account": {
                    "x_user_id": x_user_id,
                    "username": username,
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "expires_at": expires_at,
                }
            })
        }
        Some(sync_destination::Configuration::ThreadsAccount(ThreadsAccount {
            authorization_code: Some(authorization_code),
            ..
        })) if !authorization_code.trim().is_empty() => {
            // Threads API is a product added to this server's existing Meta App -- reuses the same
            // credentials as Facebook/Instagram (see `server_facebook_app_credentials`), but
            // otherwise has its own 3-step connect flow (code -> short-lived token -> long-lived
            // token -> username), unlike Facebook/Instagram's single-Page-token exchange.
            let (app_id, app_secret) = server_facebook_app_credentials(conn)?;
            let redirect_uri = threads_redirect_uri(conn)?;
            let (short_lived_token, threads_user_id) =
                exchange_code_for_token(&app_id, &app_secret, &authorization_code, &redirect_uri)?;
            let access_token = exchange_long_lived_token(&app_secret, &short_lived_token)?;
            let username = get_username(&access_token, &threads_user_id)?;
            json!({
                "threads_account": {
                    "threads_user_id": threads_user_id,
                    "username": username,
                    "access_token": access_token,
                }
            })
        }
        Some(sync_destination::Configuration::FacebookPage(_)) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "facebook_page.page_id_and_short_lived_user_access_token_required",
            ))
        }
        Some(sync_destination::Configuration::InstagramAccount(_)) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "instagram_account.page_id_and_short_lived_user_access_token_required",
            ))
        }
        Some(sync_destination::Configuration::MastodonAccount(_)) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "mastodon_account.instance_host_and_access_token_required",
            ))
        }
        Some(sync_destination::Configuration::BlueskyAccount(_)) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "bluesky_account.handle_and_app_password_required",
            ))
        }
        Some(sync_destination::Configuration::ThreadsAccount(_)) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "threads_account.authorization_code_required",
            ))
        }
        Some(sync_destination::Configuration::XTwitterAccount(_)) => {
            return Err(Status::new(
                Code::InvalidArgument,
                "x_twitter_account.authorization_code_and_code_verifier_required",
            ))
        }
        None => {
            return Err(Status::new(
                Code::InvalidArgument,
                "facebook_page.page_id_and_short_lived_user_access_token_required",
            ))
        }
    };

    let inserted = insert_into(sync_destinations::table)
        .values(&models::NewSyncDestination {
            user_id: current_user.id,
            configuration,
        })
        .get_result::<models::SyncDestination>(conn)
        .map_err(|e| {
            log::error!("Failed to create sync destination: {:?}", e);
            Status::new(Code::Internal, "failed_to_create_sync_destination")
        })?;

    let mut proto = MarshalableSyncDestination(inserted, current_user.to_author()).to_proto();
    attach_synced_counts(std::slice::from_mut(&mut proto), conn);
    Ok(proto)
}
