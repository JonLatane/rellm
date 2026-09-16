//! `PurchaseType`/`PurchasePeriod` <-> DB `VARCHAR` conversions, mirroring
//! `visibility_moderation_marshaling`'s `ToProtoVisibility`/`ToStringVisibility` pattern exactly
//! (stored as `as_str_name()`, e.g. `"PURCHASE_TYPE_MEDIA_STORAGE"`).

use std::mem::transmute;

use crate::protos::*;

pub const ALL_PURCHASE_TYPES: [PurchaseType; 4] = [
    PurchaseType::MediaStorage,
    PurchaseType::AiGrants,
    PurchaseType::RellmHosting,
    PurchaseType::PermissionsAccess,
];

pub trait ToProtoPurchaseType {
    fn to_proto_purchase_type(&self) -> Option<PurchaseType>;
}
impl ToProtoPurchaseType for String {
    fn to_proto_purchase_type(&self) -> Option<PurchaseType> {
        for purchase_type in ALL_PURCHASE_TYPES {
            if purchase_type.as_str_name().eq_ignore_ascii_case(self) {
                return Some(purchase_type);
            }
        }
        None
    }
}
impl ToProtoPurchaseType for i32 {
    fn to_proto_purchase_type(&self) -> Option<PurchaseType> {
        Some(unsafe { transmute::<i32, PurchaseType>(*self) })
    }
}

pub trait ToStringPurchaseType {
    fn to_string_purchase_type(&self) -> String;
}
impl ToStringPurchaseType for PurchaseType {
    fn to_string_purchase_type(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringPurchaseType for i32 {
    fn to_string_purchase_type(&self) -> String {
        self.to_proto_purchase_type()
            .unwrap_or(PurchaseType::MediaStorage)
            .to_string_purchase_type()
    }
}

pub const ALL_PURCHASE_PERIODS: [PurchasePeriod; 3] = [
    PurchasePeriod::Indefinite,
    PurchasePeriod::Annual,
    PurchasePeriod::Monthly,
];

pub trait ToProtoPurchasePeriod {
    fn to_proto_purchase_period(&self) -> Option<PurchasePeriod>;
}
impl ToProtoPurchasePeriod for String {
    fn to_proto_purchase_period(&self) -> Option<PurchasePeriod> {
        for period in ALL_PURCHASE_PERIODS {
            if period.as_str_name().eq_ignore_ascii_case(self) {
                return Some(period);
            }
        }
        None
    }
}
impl ToProtoPurchasePeriod for i32 {
    fn to_proto_purchase_period(&self) -> Option<PurchasePeriod> {
        Some(unsafe { transmute::<i32, PurchasePeriod>(*self) })
    }
}

pub trait ToStringPurchasePeriod {
    fn to_string_purchase_period(&self) -> String;
}
impl ToStringPurchasePeriod for PurchasePeriod {
    fn to_string_purchase_period(&self) -> String {
        self.as_str_name().to_string()
    }
}
impl ToStringPurchasePeriod for i32 {
    fn to_string_purchase_period(&self) -> String {
        self.to_proto_purchase_period()
            .unwrap_or(PurchasePeriod::Indefinite)
            .to_string_purchase_period()
    }
}
