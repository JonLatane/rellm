extern crate diesel;
extern crate rellm;
extern crate serde_json;
use diesel::*;
use rellm::marshaling::{ToProtoId, ToProtoPermission, ALL_PERMISSIONS};

use rellm::{db_connection, init_bin_logging, init_crypto};
// use rellm::protos::Permission;
use rellm::schema::*;
// use serde_json::Value::Array;
use std::env;

pub fn main() {
    init_crypto();
    init_bin_logging();

    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        return help("Invalid number of arguments.".to_string());
    }
    let username = &args[1];
    let permission = match args[2].to_proto_permission() {
        Some(permission) => permission,
        None => return help(format!("Invalid permission: {}.", args[2])),
    }
    .as_str_name();
    let status = &args[3];

    match status.as_str() {
        "on" | "true" | "off" | "false" => {}
        _ => return help(format!("Invalid status: {}.", status)),
    }
    log::info!("Setting '{}' permission to '{}'.", permission, status);

    log::info!("Connecting to DB...");
    let mut conn = db_connection::establish_connection();
    let mut user = match users::table
        .select(rellm::models::USER_COLUMNS)
        .filter(users::username.eq(username))
        .first::<rellm::models::User>(&mut conn)
    {
        Ok(user) => user,
        Err(_) => return log::info!("Could not find user."),
    };
    log::info!("Found user with ID {}/{}.", user.id.to_proto_id(), user.id);

    let mut perms: Vec<String> = match serde_json::from_value(user.permissions.to_owned()) {
        Ok(it) => it,
        Err(_) => return log::info!("Could not deserialize permissions."),
    };
    log::info!("Initial permissions: {:?}", perms);
    match status.as_str() {
        "on" | "true" => {
            if !perms.contains(&permission.to_owned()) {
                perms.push(permission.to_owned());
            }
        }
        "off" | "false" => {
            if perms.contains(&permission.to_owned()) {
                let index = perms.iter().position(|x| *x == permission).unwrap();
                perms.remove(index);
                // perms.ind(admin_permission.to_owned());
            }
        }
        _ => return help(format!("Invalid status. Aborting.")),
    }
    log::info!("Updated permissions: {:?}", perms);
    user.permissions = perms.into();
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set(&user)
        .returning(rellm::models::USER_COLUMNS)
        .get_result::<rellm::models::User>(&mut conn)
        .unwrap();
    log::info!("Updated user {}.", user.id);
}

fn help(error: String) {
    if error.len() > 0 {
        log::info!("{}", rellm::logic::log_redaction::safe_error(&error));
        log::info!("");
    }
    log::info!("This tool sets permissions for Rellm users.");
    log::info!("Usage:      set_permission <username> <permission> <status>");
    log::info!("Example:    set_permission jon admin off");
    log::info!("Statuses:   on|off|true|false");
    log::info!(
        "Permissions (case insensitive): \n * {}",
        ALL_PERMISSIONS
            .map(|p| p.as_str_name().to_ascii_lowercase())
            .join("\n * ")
    );
}
