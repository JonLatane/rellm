// use super::id_conversions::ToProtoId;
use crate::marshaling::ToProtoUser;
// use super::permission_conversions::ToProtoPermissions;
use crate::models;
use crate::protos::*;

pub trait HasPermission {
    fn has_permission(&self, permission: Permission) -> bool;
}
impl HasPermission for User {
    fn has_permission(&self, permission: Permission) -> bool {
        self.permissions.contains(&(permission as i32))
    }
}

impl HasPermission for models::User {
    fn has_permission(&self, permission: Permission) -> bool {
        self.to_proto(&None, &None, None, &None, None)
            .has_permission(permission)
    }
}
