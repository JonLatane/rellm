use std::mem::transmute;

use crate::protos::*;

pub const ALL_VISIBILITIES: [Visibility; 7] = [
    Visibility::Unknown,
    Visibility::Private,
    Visibility::Limited,
    Visibility::ServerPublic,
    Visibility::GlobalPublic,
    Visibility::Direct,
    Visibility::Licensed,
];

pub trait ToProtoVisibility {
    fn to_proto_visibility(&self) -> Option<Visibility>;
}
impl ToProtoVisibility for String {
    fn to_proto_visibility(&self) -> Option<Visibility> {
        for visibility in ALL_VISIBILITIES {
            if visibility.as_str_name().eq_ignore_ascii_case(self) {
                return Some(visibility);
            }
        }
        return None;
    }
}
impl ToProtoVisibility for i32 {
    fn to_proto_visibility(&self) -> Option<Visibility> {
        Some(unsafe { transmute::<i32, Visibility>(*self) })
    }
}
pub trait ToStringVisibility {
    fn to_string_visibility(&self) -> String;
}
impl ToStringVisibility for Visibility {
    fn to_string_visibility(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringVisibility for i32 {
    fn to_string_visibility(&self) -> String {
        self.to_proto_visibility().unwrap().to_string_visibility()
    }
}

pub trait ToStringVisibilities {
    fn to_string_visibilities(&self) -> Vec<String>;
}
impl ToStringVisibilities for Vec<Visibility> {
    fn to_string_visibilities(&self) -> Vec<String> {
        self.iter()
            .map(|v| v.to_string_visibility())
            .collect::<Vec<String>>()
    }
}

pub trait ToI32Visibility {
    fn to_i32_visibility(&self) -> i32;
}
impl ToI32Visibility for String {
    fn to_i32_visibility(&self) -> i32 {
        self.to_proto_visibility().unwrap() as i32
    }
}

pub const ALL_MODERATIONS: [Moderation; 5] = [
    Moderation::Unknown,
    Moderation::Unmoderated,
    Moderation::Pending,
    Moderation::Approved,
    Moderation::Rejected,
];

pub trait ToProtoModeration {
    fn to_proto_moderation(&self) -> Option<Moderation>;
}
impl ToProtoModeration for String {
    fn to_proto_moderation(&self) -> Option<Moderation> {
        for moderation in ALL_MODERATIONS {
            if moderation.as_str_name().eq_ignore_ascii_case(self) {
                return Some(moderation);
            }
        }
        return None;
    }
}
impl ToProtoModeration for i32 {
    fn to_proto_moderation(&self) -> Option<Moderation> {
        Some(unsafe { transmute::<i32, Moderation>(*self) })
    }
}

pub trait ToStringModeration {
    fn to_string_moderation(&self) -> String;
}
impl ToStringModeration for Moderation {
    fn to_string_moderation(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringModeration for i32 {
    fn to_string_moderation(&self) -> String {
        self.to_proto_moderation().unwrap().to_string_moderation()
    }
}

pub trait ToI32Moderation {
    fn to_i32_moderation(&self) -> i32;
}
impl ToI32Moderation for String {
    fn to_i32_moderation(&self) -> i32 {
        self.to_proto_moderation().unwrap().to_i32_moderation() //unwrap() as i32
    }
}
impl ToI32Moderation for Moderation {
    fn to_i32_moderation(&self) -> i32 {
        *self as i32
    }
}

pub trait ToStringModerations {
    fn to_string_moderations(&self) -> Vec<String>;
}
impl ToStringModerations for Vec<Moderation> {
    fn to_string_moderations(&self) -> Vec<String> {
        self.iter()
            .map(|v| v.to_string_moderation())
            .collect::<Vec<String>>()
    }
}
