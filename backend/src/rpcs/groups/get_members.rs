use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::models::MEDIA_REFERENCE_COLUMNS;
use crate::protos::*;
use crate::rpcs::validations::*;

use crate::schema::media;
use crate::schema::{follows, memberships, users};

pub fn get_members(
    request: GetMembersRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetMembersResponse, Status> {
    let group_id: i64 = request.group_id.to_db_id_or_err("group_id")?;
    let (group, membership) = models::get_group_and_membership(group_id, user.map(|u| u.id), conn)?;
    match request.group_moderation() {
        Moderation::Pending => validate_group_user_moderator(user, &group, &membership.as_ref())?,
        _ => {}
    };
    let passing_moderations = vec![Moderation::Approved, Moderation::Unmoderated];
    let response = match (
        request.to_owned().username,
        request.to_owned().group_moderation(),
    ) {
        (None, Moderation::Unknown) => get_all_members(
            group_id,
            passing_moderations.to_owned(),
            passing_moderations,
            request.page(),
            user,
            conn,
        ),
        (None, m) => get_all_members(
            group_id,
            passing_moderations,
            vec![m],
            request.page(),
            user,
            conn,
        ),
        (Some(username), Moderation::Unknown) => get_members_by_username(
            group_id,
            passing_moderations.to_owned(),
            passing_moderations,
            request.page(),
            username,
            user,
            conn,
        ),
        (Some(username), m) => get_members_by_username(
            group_id,
            passing_moderations,
            vec![m],
            request.page(),
            username,
            user,
            conn,
        ),
        // _ => return Err(Status::invalid_argument("invalid_request")),
    };
    log::info!(
        "GetMembers::request: {:?}\nresponse: {:?}",
        request,
        response
    );
    Ok(response)
}

fn get_all_members(
    group_id: i64,
    user_moderations: Vec<Moderation>,
    group_moderations: Vec<Moderation>,
    page: i32,
    // request: GetMembersRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> GetMembersResponse {
    let user_moderations_string = user_moderations
        .iter()
        .map(|m| m.to_string_moderation())
        .collect::<Vec<String>>();
    let group_moderations_string = group_moderations
        .iter()
        .map(|m| m.to_string_moderation())
        .collect::<Vec<String>>();
    let target_follows = alias!(follows as target_follows);
    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);

    let matched_user_id = user.map(|u| u.id);
    let members: Vec<Member> = memberships::table
        .inner_join(users::table)
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(matched_user_id))),
        )
        .left_join(
            target_follows.on(target_follows_user_id
                .eq(users::id)
                .and(target_follows_target_user_id.nullable().eq(matched_user_id))),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            memberships::all_columns,
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(memberships::group_id.eq(group_id))
        .filter(memberships::user_moderation.eq_any(user_moderations_string))
        .filter(memberships::group_moderation.eq_any(group_moderations_string))
        // .filter(memberships::group_.eq(group_id)))
        // .filter(
        //     users::visibility
        //         .eq_any(visibilities)
        //         .or(users::id.nullable().eq(user.map(|u| u.id))),
        // )
        .order(memberships::created_at.desc())
        .limit(100)
        .offset((page * 100).into())
        .load::<(
            models::Membership,
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(
            |(membership, row_user, follow, target_follow, media_reference)| {
                let lookup = media_reference.to_media_lookup();
                // .as_ref()
                // .map(|mr| media_lookup(vec![mr.clone()]));
                Member {
                    user: Some(row_user.to_proto(
                        &follow.as_ref(),
                        &target_follow.as_ref(),
                        lookup.as_ref(),
                        user,
                        None,
                    )),
                    membership: Some(membership.to_proto()),
                }
            },
        )
        .collect();
    GetMembersResponse {
        members,
        has_next_page: false,
    }
}

fn get_members_by_username(
    group_id: i64,
    user_moderations: Vec<Moderation>,
    group_moderations: Vec<Moderation>,
    page: i32,
    username: String,
    // request: GetMembersRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> GetMembersResponse {
    let user_moderations_string = user_moderations
        .iter()
        .map(|m| m.to_string_moderation())
        .collect::<Vec<String>>();
    let group_moderations_string = group_moderations
        .iter()
        .map(|m| m.to_string_moderation())
        .collect::<Vec<String>>();
    let target_follows = alias!(follows as target_follows);
    let target_follows_user_id = target_follows.field(follows::user_id);
    let target_follows_target_user_id = target_follows.field(follows::target_user_id);
    let target_follows_columns = target_follows.fields(follows::all_columns);

    let matched_user_id = user.map(|u| u.id);
    let members: Vec<Member> = memberships::table
        .inner_join(users::table)
        .left_join(
            follows::table.on(follows::target_user_id
                .eq(users::id)
                .and(follows::user_id.nullable().eq(matched_user_id))),
        )
        .left_join(
            target_follows.on(target_follows_user_id
                .eq(users::id)
                .and(target_follows_target_user_id.nullable().eq(matched_user_id))),
        )
        .left_join(media::table.on(media::id.nullable().eq(users::avatar_media_id.nullable())))
        .select((
            memberships::all_columns,
            models::USER_COLUMNS,
            follows::all_columns.nullable(),
            target_follows_columns.nullable(),
            MEDIA_REFERENCE_COLUMNS.nullable(),
        ))
        .filter(memberships::group_id.eq(group_id))
        .filter(memberships::user_moderation.eq_any(user_moderations_string))
        .filter(memberships::group_moderation.eq_any(group_moderations_string))
        .filter(users::username.ilike(format!("{}%", username)))
        // .filter(memberships::group_.eq(group_id)))
        // .filter(
        //     users::visibility
        //         .eq_any(visibilities)
        //         .or(users::id.nullable().eq(user.map(|u| u.id))),
        // )
        .order(memberships::created_at.desc())
        .limit(100)
        .offset((page * 100).into())
        .load::<(
            models::Membership,
            models::User,
            Option<models::Follow>,
            Option<models::Follow>,
            Option<models::MediaReference>,
        )>(conn)
        .unwrap()
        .iter()
        .map(
            |(membership, row_user, follow, target_follow, media_reference)| Member {
                user: Some(row_user.to_proto(
                    &follow.as_ref(),
                    &target_follow.as_ref(),
                    media_reference.to_media_lookup().as_ref(),
                    user,
                    None,
                )),
                membership: Some(membership.to_proto()),
            },
        )
        .collect();
    GetMembersResponse {
        members,
        has_next_page: false,
    }
}
