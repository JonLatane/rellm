use std::option::Option;
use std::time::SystemTime;

use crate::db_connection::*;
use crate::protos::*;
use crate::schema::user_access_tokens::dsl as user_access_tokens;
use crate::schema::user_refresh_tokens::dsl as user_refresh_tokens;
use diesel::*;
use prost_wkt_types::*;
use ring::rand::*;
use std::ops::Add;

const ACCESS_TOKEN_EXPIRATION_MINS: u64 = 15;

/// Generate a secure random token of the given length.
#[macro_export]
macro_rules! generate_token {
    ($length_u8:expr) => {{
        let mut randoms: [u8; $length_u8] = [0; $length_u8];
        let sr = SystemRandom::new();
        sr.fill(&mut randoms).unwrap();
        let mut token = String::new();
        for i in randoms.iter() {
            token.push_str(&format!("{:x}", i));
        }
        token
    }};
}

/// Generate and store a refresh token and access token for the given user.
pub fn generate_refresh_and_access_token(
    user_id: i64,
    conn: &mut PgPooledConnection,
    expires_at: &Option<Timestamp>,
) -> RefreshTokenResponse {
    let refresh_token = generate_token!(512);

    let requested_expiration: Option<SystemTime> = expires_at
        // .as_ref()
        // .map(|x| x.clone())
        .map(SystemTime::try_from)
        .map(|x| x.ok())
        .flatten();
    let (refresh_token_id, expires_at): (i64, Option<SystemTime>) =
        insert_into(user_refresh_tokens::user_refresh_tokens)
            .values((
                user_refresh_tokens::user_id.eq(user_id),
                user_refresh_tokens::token.eq(refresh_token.to_owned()),
                user_refresh_tokens::expires_at.eq(requested_expiration),
            ))
            .returning((user_refresh_tokens::id, user_refresh_tokens::expires_at))
            .get_result::<(i64, Option<SystemTime>)>(&mut *conn)
            .unwrap();
    let refresh_token = ExpirableToken {
        token: refresh_token.to_owned(),
        expires_at: expires_at.map(Timestamp::from),
    };
    log::info!("Generated refresh token for user_id={}", user_id);

    let access_token = generate_access_token(refresh_token_id, conn);

    RefreshTokenResponse {
        refresh_token: Some(refresh_token),
        access_token: Some(access_token),
        user: None,
        verification_challenge: None,
    }
}

/// Generate and store an access token for the given refresh token.
pub fn generate_access_token(
    refresh_token_id: i64,
    conn: &mut PgPooledConnection,
) -> ExpirableToken {
    let access_token = generate_token!(128);
    let expiration = SystemTime::now().add(std::time::Duration::from_secs(
        60 * ACCESS_TOKEN_EXPIRATION_MINS,
    ));
    let expires_at: SystemTime = insert_into(user_access_tokens::user_access_tokens)
        .values((
            user_access_tokens::refresh_token_id.eq(refresh_token_id),
            user_access_tokens::token.eq(access_token.to_owned()),
            user_access_tokens::expires_at.eq(expiration),
        ))
        .returning(user_access_tokens::expires_at)
        .get_result::<SystemTime>(conn)
        .unwrap();
    log::info!(
        "Generated access token for refresh_token_id={}, expires_at={:#?}",
        refresh_token_id,
        expires_at
    );
    ExpirableToken {
        token: access_token.to_owned(),
        expires_at: Some(Timestamp::from(expires_at)),
    }
}
