use std::mem::transmute;

use itertools::Itertools;

use crate::protos::*;

pub const ALL_PRIVATE_USER_STRATEGIES: [PrivateUserStrategy; 3] = [
    PrivateUserStrategy::AccountIsFrozen,
    PrivateUserStrategy::LimitedCreepiness,
    PrivateUserStrategy::LetMeCreepOnPpl,
];

pub trait ToProtoPrivateUserStrategy {
    fn to_proto_private_user_strategy(&self) -> Option<PrivateUserStrategy>;
}
impl ToProtoPrivateUserStrategy for String {
    fn to_proto_private_user_strategy(&self) -> Option<PrivateUserStrategy> {
        for private_user_strategy in ALL_PRIVATE_USER_STRATEGIES {
            if private_user_strategy
                .as_str_name()
                .eq_ignore_ascii_case(self)
            {
                return Some(private_user_strategy);
            }
        }
        return None;
    }
}
impl ToProtoPrivateUserStrategy for i32 {
    fn to_proto_private_user_strategy(&self) -> Option<PrivateUserStrategy> {
        Some(unsafe { transmute::<i32, PrivateUserStrategy>(*self) })
    }
}
pub trait ToStringPrivateUserStrategy {
    fn to_string_private_user_strategy(&self) -> String;
}
impl ToStringPrivateUserStrategy for PrivateUserStrategy {
    fn to_string_private_user_strategy(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringPrivateUserStrategy for i32 {
    fn to_string_private_user_strategy(&self) -> String {
        self.to_proto_private_user_strategy()
            .unwrap()
            .to_string_private_user_strategy()
    }
}

pub trait ToI32PrivateUserStrategy {
    fn to_i32_private_user_strategy(&self) -> i32;
}
impl ToI32PrivateUserStrategy for String {
    fn to_i32_private_user_strategy(&self) -> i32 {
        self.to_proto_private_user_strategy().unwrap() as i32
    }
}

pub const ALL_AUTHENTICATION_FEATURES: [AuthenticationFeature; 7] = [
    AuthenticationFeature::Unknown,
    AuthenticationFeature::CreateAccountWithPassword,
    AuthenticationFeature::CreateAccountWithSms,
    AuthenticationFeature::CreateAccountWithEmail,
    AuthenticationFeature::LoginWithPassword,
    AuthenticationFeature::LoginWithSms,
    AuthenticationFeature::LoginWithEmail,
];

pub trait ToProtoAuthenticationFeature {
    fn to_proto_authentication_feature(&self) -> Option<AuthenticationFeature>;
}
impl ToProtoAuthenticationFeature for String {
    fn to_proto_authentication_feature(&self) -> Option<AuthenticationFeature> {
        for authentication_feature in ALL_AUTHENTICATION_FEATURES {
            if authentication_feature
                .as_str_name()
                .eq_ignore_ascii_case(self)
            {
                return Some(authentication_feature);
            }
        }
        return None;
    }
}
impl ToProtoAuthenticationFeature for i32 {
    fn to_proto_authentication_feature(&self) -> Option<AuthenticationFeature> {
        Some(unsafe { transmute::<i32, AuthenticationFeature>(*self) })
    }
}

pub trait ToStringAuthenticationFeature {
    fn to_string_authentication_feature(&self) -> String;
}
impl ToStringAuthenticationFeature for AuthenticationFeature {
    fn to_string_authentication_feature(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringAuthenticationFeature for i32 {
    fn to_string_authentication_feature(&self) -> String {
        self.to_proto_authentication_feature()
            .unwrap()
            .to_string_authentication_feature()
    }
}

pub trait ToI32AuthenticationFeature {
    fn to_i32_authentication_feature(&self) -> i32;
}
impl ToI32AuthenticationFeature for String {
    fn to_i32_authentication_feature(&self) -> i32 {
        self.to_proto_authentication_feature().unwrap() as i32
    }
}

pub trait ToProtoAuthenticationFeatures {
    fn to_proto_authentication_features(&self) -> Vec<AuthenticationFeature>;
}
impl ToProtoAuthenticationFeatures for serde_json::Value {
    fn to_proto_authentication_features(&self) -> Vec<AuthenticationFeature> {
        match self {
            serde_json::Value::Array(authentication_features) => {
                let mut mapped_authentication_features: Vec<AuthenticationFeature> = Vec::new();
                // log::info!("Converting authentication_features: {:?}", authentication_features);
                for feature in authentication_features {
                    let mapped_feature = feature
                        .as_str()
                        .map(|s| s.to_string().to_proto_authentication_feature())
                        .flatten();

                    // log::info!("Mapped feature {:?} to {:?}", feature, mapped_feature);
                    if mapped_feature.is_some() {
                        mapped_authentication_features.push(mapped_feature.unwrap());
                    }
                }
                return mapped_authentication_features;
            }
            _ => return Vec::new(),
        }
    }
}
impl ToProtoAuthenticationFeatures for Vec<i32> {
    fn to_proto_authentication_features(&self) -> Vec<AuthenticationFeature> {
        self.iter()
            .unique()
            .map(|p| p.to_proto_authentication_feature().unwrap())
            .collect()
    }
}
pub trait ToJsonAuthenticationFeatures {
    fn to_json_authentication_features(&self) -> serde_json::Value;
}
impl ToJsonAuthenticationFeatures for Vec<AuthenticationFeature> {
    fn to_json_authentication_features(&self) -> serde_json::Value {
        serde_json::Value::Array(
            self.iter()
                .unique()
                .map(|p| serde_json::Value::String(p.as_str_name().to_string()))
                .collect(),
        )
    }
}
impl ToJsonAuthenticationFeatures for Vec<i32> {
    fn to_json_authentication_features(&self) -> serde_json::Value {
        self.iter()
            .unique()
            .map(|p| p.to_proto_authentication_feature().unwrap())
            .collect::<Vec<AuthenticationFeature>>()
            .to_json_authentication_features()
    }
}

pub trait ToI32AuthenticationFeatures {
    fn to_i32_authentication_features(&self) -> Vec<i32>;
}
impl ToI32AuthenticationFeatures for Vec<AuthenticationFeature> {
    fn to_i32_authentication_features(&self) -> Vec<i32> {
        self.iter().unique().map(|p| *p as i32).collect()
    }
}
impl ToI32AuthenticationFeatures for serde_json::Value {
    fn to_i32_authentication_features(&self) -> Vec<i32> {
        self.to_proto_authentication_features()
            .to_i32_authentication_features()
    }
}
