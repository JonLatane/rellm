use diesel::*;
use tonic::Status;

use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::GroupListingType::*;
use crate::protos::*;
use crate::schema::groups;

const PAGE_SIZE: i64 = 1000;

pub fn get_groups(
    request: GetGroupsRequest,
    user: &Option<&models::User>,
    conn: &mut PgPooledConnection,
) -> Result<GetGroupsResponse, Status> {
    log::info!("GetGroups called");
    let response = match (
        request
            .to_owned()
            .listing_type
            .to_proto_group_listing_type(),
        request.to_owned().group_id,
        request.to_owned().group_name,
        request.to_owned().group_shortname,
    ) {
        //TODO: Implement other listing types. For now this can be done in the UI.
        (Some(InvitedGroups), _, _, _) => get_all_groups(request.to_owned(), user, conn),
        (_, Some(_), _, _) => get_by_id(request.to_owned(), user, conn),
        (_, _, Some(_), _) => get_by_name(request.to_owned(), user, conn),
        (_, _, _, Some(_)) => get_by_shortname(request.to_owned(), user, conn),
        _ => get_all_groups(request.to_owned(), user, conn),
    };
    // log::info!(
    //     "GetGroups::request: {:?}, response: {:?}",
    //     request, response
    // );
    log::info!("GetGroups: response_length: {}", response.groups.len());
    Ok(response)
}

fn get_all_groups(
    request: GetGroupsRequest,
    user: &Option<&models::User>,
    mut conn: &mut PgPooledConnection,
) -> GetGroupsResponse {
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();

    let groups = groups::table
        .select(groups::all_columns)
        .filter(groups::visibility.eq_any(visibilities))
        .order(groups::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .load::<models::Group>(conn)
        .unwrap()
        .iter()
        .map(|group| group.to_proto(&mut conn, &user))
        .collect();
    GetGroupsResponse {
        groups,
        has_next_page: false,
    }
}
fn get_by_name(
    request: GetGroupsRequest,
    user: &Option<&models::User>,
    mut conn: &mut PgPooledConnection,
) -> GetGroupsResponse {
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();
    let groups = groups::table
        .select(groups::all_columns)
        .filter(groups::visibility.eq_any(visibilities))
        .filter(groups::name.ilike(format!("%{}%", request.group_name.unwrap())))
        .order(groups::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .load::<models::Group>(conn)
        .unwrap()
        .iter()
        .map(|group| group.to_proto(&mut conn, &user))
        .collect();
    GetGroupsResponse {
        groups,
        has_next_page: false,
    }
}
fn get_by_shortname(
    request: GetGroupsRequest,
    user: &Option<&models::User>,
    mut conn: &mut PgPooledConnection,
) -> GetGroupsResponse {
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();
    let groups = groups::table
        .select(groups::all_columns)
        .filter(groups::visibility.eq_any(visibilities))
        .filter(groups::shortname.ilike(format!("{}", request.group_shortname.unwrap())))
        .order(groups::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .load::<models::Group>(conn)
        .unwrap()
        .iter()
        .map(|group| group.to_proto(&mut conn, &user))
        .collect();
    GetGroupsResponse {
        groups,
        has_next_page: false,
    }
}

fn get_by_id(
    request: GetGroupsRequest,
    user: &Option<&models::User>,
    mut conn: &mut PgPooledConnection,
) -> GetGroupsResponse {
    let visibilities = match user {
        Some(_) => vec![Visibility::ServerPublic, Visibility::GlobalPublic],
        None => vec![Visibility::GlobalPublic],
    }
    .iter()
    .map(|v| v.as_str_name())
    .collect::<Vec<&str>>();
    let groups = groups::table
        .select(groups::all_columns)
        .filter(groups::visibility.eq_any(visibilities))
        .filter(
            groups::id.eq(request
                .group_id
                .unwrap()
                .to_db_id_or_err("group_id")
                .unwrap()),
        )
        .order(groups::created_at.desc())
        .limit(PAGE_SIZE)
        .offset((request.page.unwrap_or(0) * 100).into())
        .load::<models::Group>(conn)
        .unwrap()
        .iter()
        .map(|group| group.to_proto(&mut conn, &user))
        .collect();
    GetGroupsResponse {
        groups,
        has_next_page: false,
    }
}
