use std::ops::{Add, Sub};
use std::time::Duration;
use std::time::SystemTime;

use diesel::*;
use rand;
use rand::RngExt;
use tonic::{Code, Status};

use crate::auth::*;
use crate::db_connection::*;
use crate::protos::*;
use crate::schema::user_refresh_tokens;

pub const LIFETIME_DAYS: u64 = 14;
pub const RENEWAL_PERIOD_DAYS: u64 = 13;

pub fn access_token(
    request: AccessTokenRequest,
    conn: &mut PgPooledConnection,
) -> Result<AccessTokenResponse, Status> {
    log::info!("AccessToken called.");
    let refresh_token = &request.refresh_token;
    let token_user_expiry: Result<(i64, i64, Option<SystemTime>), _> = user_refresh_tokens::table
        .select((
            user_refresh_tokens::id,
            user_refresh_tokens::user_id,
            user_refresh_tokens::expires_at,
        ))
        .filter(user_refresh_tokens::token.eq(refresh_token))
        .first::<(i64, i64, Option<SystemTime>)>(conn);

    match token_user_expiry {
        Ok((refresh_token_id, user_id, refresh_token_expires_at)) => match refresh_token_expires_at
        {
            Some(t) if t > SystemTime::now() => {
                log::warn!(
                    "Attempt to use expired refresh token. refresh_token_id={}, user_id={}",
                    refresh_token_id,
                    user_id
                );
                Err(Status::new(Code::Unauthenticated, "not_authorized"))
            }
            Some(t)
                if t.sub(Duration::from_secs(60 * 60 * 24 * RENEWAL_PERIOD_DAYS))
                    < SystemTime::now() =>
            {
                log::info!(
                    "Generating both refresh token and access token for user_id={}, refresh_token_id={}...",
                    user_id,
                    refresh_token_id
                );
                let new_expiry =
                    SystemTime::now().add(Duration::from_secs(60 * 60 * 24 * LIFETIME_DAYS));
                let new_token_pair =
                    generate_refresh_and_access_token(user_id, conn, &Some(new_expiry.into()));
                Ok(AccessTokenResponse {
                    access_token: new_token_pair.access_token,
                    refresh_token: new_token_pair.refresh_token,
                })
            }
            Some(_) => {
                log::info!(
                    "Generating access token for user_id={}, refresh_token_id={}...",
                    user_id,
                    refresh_token_id
                );
                let access_token = generate_access_token(refresh_token_id, conn);
                Ok(AccessTokenResponse {
                    access_token: Some(access_token),
                    refresh_token: None,
                })
            }
            None => {
                match rand::rng().random_range(0..=20) {
                    0 => {
                        log::info!(
                            "Randomly generating new refresh/access token pair for non-expiring refresh token for user_id={}; current token will expire in 360s.",
                            user_id
                        );
                        // log::warn!("Randomly failing to generate access token for user_id={}", user_id);

                        let new_expiry = SystemTime::now().add(Duration::from_secs(360));
                        diesel::update(user_refresh_tokens::table)
                            .set(user_refresh_tokens::expires_at.eq(new_expiry))
                            .filter(user_refresh_tokens::id.eq(refresh_token_id))
                            .execute(conn)
                            .map_err(|e| {
                                log::error!(
                                    "Failed to delete refresh token for user_id={}: {:?}",
                                    user_id,
                                    crate::logic::log_redaction::safe_error(&e)
                                );
                                Status::new(Code::Internal, "internal_error")
                            })?;
                        let new_token_pair =
                            generate_refresh_and_access_token(user_id, conn, &None);
                        Ok(AccessTokenResponse {
                            access_token: new_token_pair.access_token,
                            refresh_token: new_token_pair.refresh_token,
                        })
                    }
                    _ => {
                        log::debug!("Generating access token for user_id={}", user_id);
                        let access_token = generate_access_token(refresh_token_id, conn);
                        Ok(AccessTokenResponse {
                            access_token: Some(access_token),
                            refresh_token: None,
                        })
                    }
                }
            }
        },
        Err(_) => {
            log::warn!("Auth token not found.");
            Err(Status::new(Code::Unauthenticated, "not_authorized"))
        }
    }
}
