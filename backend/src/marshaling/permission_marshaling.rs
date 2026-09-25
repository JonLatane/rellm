use std::mem::transmute;

use crate::itertools::Itertools;
use crate::protos::Permission::*;
use crate::protos::*;

pub const ALL_PERMISSIONS: [Permission; 55] = [
    Unknown,
    ViewUsers,
    PublishUsersLocally,
    PublishUsersGlobally,
    ModerateUsers,
    FollowUsers,
    GrantBasicPermissions,
    ViewGroups,
    CreateGroups,
    PublishGroupsLocally,
    PublishGroupsGlobally,
    ModerateGroups,
    JoinGroups,
    InviteGroupMembers,
    ViewPosts,
    CreatePosts,
    PublishPostsLocally,
    PublishPostsGlobally,
    ModeratePosts,
    ReplyToPosts,
    ViewEvents,
    CreateEvents,
    PublishEventsLocally,
    PublishEventsGlobally,
    ModerateEvents,
    RsvpToEvents,
    SyncEventsToFacebook,
    SyncPostsToFacebook,
    SyncEventsToInstagram,
    SyncPostsToInstagram,
    SyncEventsToMastodon,
    SyncPostsToMastodon,
    SyncEventsToBluesky,
    SyncPostsToBluesky,
    SyncEventsToXTwitter,
    SyncPostsToXTwitter,
    SyncEventsToThreads,
    SyncPostsToThreads,
    ViewMedia,
    CreateMedia,
    PublishMediaLocally,
    PublishMediaGlobally,
    ModerateMedia,
    ReadPersonalMessages,
    ReadAllSystemMessages,
    CreateAiProviders,
    SyncEventsFromIcs,
    SyncPostsFromRss,
    SyncPostsFromAtom,
    Business,
    RunBots,
    Admin,
    ViewPrivateContactMethods,
    EditClusterSettings,
    EditServerMediaAllocation,
];

pub trait ToProtoPermission {
    fn to_proto_permission(&self) -> Option<Permission>;
}
impl ToProtoPermission for String {
    fn to_proto_permission(&self) -> Option<Permission> {
        for permission in ALL_PERMISSIONS {
            if permission.as_str_name().eq_ignore_ascii_case(self) {
                return Some(permission);
            }
        }
        return None;
    }
}
impl ToProtoPermission for i32 {
    fn to_proto_permission(&self) -> Option<Permission> {
        Some(unsafe { transmute::<i32, Permission>(*self) })
    }
}
pub trait ToStringPermission {
    fn to_string_permission(&self) -> String;
}
impl ToStringPermission for Permission {
    fn to_string_permission(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringPermission for i32 {
    fn to_string_permission(&self) -> String {
        self.to_proto_permission().unwrap().to_string_permission()
    }
}

pub trait ToProtoPermissions {
    fn to_proto_permissions(&self) -> Vec<Permission>;
}
impl ToProtoPermissions for serde_json::Value {
    fn to_proto_permissions(&self) -> Vec<Permission> {
        match self {
            serde_json::Value::Array(permissions) => {
                let mut mapped_permissions: Vec<Permission> = Vec::new();
                // log::info!("Converting permissions: {:?}", permissions);
                for permission in permissions {
                    let mapped_permission = permission
                        .as_str()
                        .map(|s| s.to_string().to_proto_permission())
                        .flatten();

                    // log::info!("Mapped permission {:?} to {:?}", permission, mapped_permission);
                    if mapped_permission.is_some() {
                        mapped_permissions.push(mapped_permission.unwrap());
                    }
                }
                return mapped_permissions;
            }
            _ => return Vec::new(),
        }
    }
}
impl ToProtoPermissions for Vec<i32> {
    fn to_proto_permissions(&self) -> Vec<Permission> {
        self.iter()
            .unique()
            .map(|p| p.to_proto_permission().unwrap())
            .collect()
    }
}
pub trait ToJsonPermissions {
    fn to_json_permissions(&self) -> serde_json::Value;
}
impl ToJsonPermissions for Vec<Permission> {
    fn to_json_permissions(&self) -> serde_json::Value {
        serde_json::Value::Array(
            self.iter()
                .unique()
                .map(|p| serde_json::Value::String(p.as_str_name().to_string()))
                .collect(),
        )
    }
}
impl ToJsonPermissions for Vec<i32> {
    fn to_json_permissions(&self) -> serde_json::Value {
        self.iter()
            .map(|p| p.to_proto_permission().unwrap())
            .collect::<Vec<Permission>>()
            .to_json_permissions()
    }
}

pub trait ToI32Permissions {
    fn to_i32_permissions(&self) -> Vec<i32>;
}
impl ToI32Permissions for Vec<Permission> {
    fn to_i32_permissions(&self) -> Vec<i32> {
        self.iter().map(|p| *p as i32).collect()
    }
}
impl ToI32Permissions for serde_json::Value {
    fn to_i32_permissions(&self) -> Vec<i32> {
        self.to_proto_permissions().to_i32_permissions()
    }
}

pub trait ToStringPermissions {
    fn to_string_permissions(&self) -> Vec<String>;
}
impl ToStringPermissions for Vec<Permission> {
    fn to_string_permissions(&self) -> Vec<String> {
        self.iter()
            .map(|v| v.to_string_permission())
            .collect::<Vec<String>>()
    }
}
