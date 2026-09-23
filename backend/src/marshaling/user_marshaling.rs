use crate::db_connection::PgPooledConnection;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs::get_federated_users;
use crate::rpcs::validate_exact_permission;
use crate::rpcs::validate_permission;
use tonic::Code;
use tonic::Status;

use super::MediaLookup;

/// Whether `contact_method` (an `email`/`phone` on some user `owner_id`) should be visible to
/// `viewer`, per the `ContactMethod`'s own `visibility` -- independent of the owning `User`'s
/// overall `visibility`.
///
/// - `GLOBAL_PUBLIC` is visible to everyone, including anonymous (`viewer: &None`) users.
/// - `SERVER_PUBLIC` is visible to any authenticated user, but not anonymously.
/// - `LIMITED`/`PRIVATE` (and any unrecognized visibility, treated as `PRIVATE`) are visible only
///   to the owner themselves, or to a viewer holding `VIEW_PRIVATE_CONTACT_METHODS` -- checked via
///   `validate_exact_permission`, deliberately *not* `validate_permission`, so a plain `ADMIN`
///   does *not* get this for free (see `Permission::ViewPrivateContactMethods`'s own doc).
fn visible_contact_method(
    contact_method: &ContactMethod,
    owner_id: i64,
    viewer: &Option<&models::User>,
) -> bool {
    match contact_method.visibility.to_proto_visibility() {
        Some(Visibility::GlobalPublic) => true,
        Some(Visibility::ServerPublic) => viewer.is_some(),
        _ => {
            viewer.map(|v| v.id) == Some(owner_id)
                || validate_exact_permission(viewer, Permission::ViewPrivateContactMethods).is_ok()
        }
    }
}

/// Blanks `consent_state`/`consent_history` on `contact_method` for anyone but its owner or an
/// `ADMIN` -- regardless of the `ContactMethod`'s own `visibility` (see `visible_contact_method`
/// above, which gates `value` itself). Consent is a record of the user's own contact
/// preferences/actions and has no reason to be exposed to other viewers just because they can see
/// a public `value` -- unlike `value`'s own visibility, this isn't relaxable via
/// `VIEW_PRIVATE_CONTACT_METHODS`.
fn scrub_consent_for_viewer(
    mut contact_method: ContactMethod,
    owner_id: i64,
    viewer: &Option<&models::User>,
) -> ContactMethod {
    let is_owner_or_admin =
        viewer.map(|v| v.id) == Some(owner_id) || validate_permission(viewer, Permission::Admin).is_ok();
    if !is_owner_or_admin {
        contact_method.consent_state = ContactConsentState::ContactConsentRevoked as i32;
        contact_method.consent_history = vec![];
    }
    contact_method
}

pub trait ToProtoUser {
    fn to_proto(
        &self,
        follow: &Option<&models::Follow>,
        target_follow: &Option<&models::Follow>,
        media_lookup: Option<&MediaLookup>,
        // The user viewing this profile (if authenticated) -- gates `email`/`phone` visibility,
        // per each `ContactMethod`'s own `visibility` (see `visible_contact_method` below).
        viewer: &Option<&models::User>,
        // If provided, marshaling will load federated user data from the DB.
        conn: Option<&mut PgPooledConnection>,
    ) -> User;

    fn to_author(&self) -> models::Author;
}
impl ToProtoUser for models::User {
    // fn to_proto(&self) -> User {
    //     return self.to_proto(&None, &None);
    // }
    fn to_proto(
        &self,
        follow: &Option<&models::Follow>,
        target_follow: &Option<&models::Follow>,
        media_lookup: Option<&MediaLookup>,
        viewer: &Option<&models::User>,
        // If provided, marshaling will load federated user data from the DB.
        conn: Option<&mut PgPooledConnection>,
    ) -> User {
        let email: Option<ContactMethod> = self
            .email
            .to_owned()
            .map(|cm| serde_json::from_value(cm).unwrap())
            .filter(|cm| visible_contact_method(cm, self.id, viewer))
            .map(|cm| scrub_consent_for_viewer(cm, self.id, viewer));
        let phone: Option<ContactMethod> = self
            .phone
            .to_owned()
            .map(|cm| serde_json::from_value(cm).unwrap())
            .filter(|cm| visible_contact_method(cm, self.id, viewer))
            .map(|cm| scrub_consent_for_viewer(cm, self.id, viewer));

        log::info!("user.avatar_media_id={:?}", &self.avatar_media_id);
        let user = User {
            id: self.id.to_proto_id().to_string(),
            username: self.username.to_owned(),
            real_name: self.real_name.to_owned(),
            email: email,
            phone: phone,
            permissions: self.permissions.to_i32_permissions(),
            bio: self.bio.to_owned(),
            media_storage_limit_bytes: self.media_storage_limit_bytes.map(|b| b as u64),
            media_storage_bytes_used: self.media_storage_bytes_used as u64,
            // avatar_media_id: self.avatar_media_id.to_owned().map(|id| id.to_proto_id()),
            avatar: media_lookup
                .map(|ml| ml.get(&self.avatar_media_id.unwrap()).unwrap().to_proto(&None)),
            visibility: self.visibility.to_proto_visibility().unwrap() as i32,
            moderation: self.moderation.to_proto_moderation().unwrap() as i32,
            follower_count: Some(self.follower_count),
            following_count: Some(self.following_count),
            friend_count: Some(self.friend_count),
            group_count: Some(self.group_count),
            post_count: Some(self.post_count),
            event_count: Some(self.event_count),
            occasion_count: Some(self.occasion_count),
            response_count: Some(self.response_count),
            default_follow_moderation: self
                .default_follow_moderation
                .to_proto_moderation()
                .unwrap() as i32,
            federated_profiles: conn
                .map(|conn| get_federated_users(self.id, conn))
                .unwrap_or(vec![]),
            // Only ever populated by `get_users.rs`'s single-user lookups
            // (`get_by_username`/`get_by_user_id`, self-or-Admin gated), as a
            // post-`to_proto` step -- see `attach_own_sync_destinations`.
            // Never populated here, unlike `federated_profiles` above.
            sync_destinations: vec![],
            // Same deal as `sync_destinations`, but populated by `get_users.rs`'s
            // `attach_advanced_admin_data` across *every* listing type (not just the two
            // single-user lookups) -- see that function's own doc.
            sync_sources: vec![],
            ai_models: vec![],
            // Same deal as `ai_models` -- populated by `get_users.rs`'s `attach_advanced_admin_data`
            // across every listing type, self-or-Admin gated (see `market.proto`'s own doc on
            // `User.market_subscriptions`).
            market_subscriptions: vec![],
            current_user_follow: follow.as_ref().map(|f| f.to_proto()),
            target_current_user_follow: target_follow.as_ref().map(|f| f.to_proto()),
            current_group_membership: None, // TODO
            created_at: Some(self.created_at.to_proto()),
            updated_at: Some(self.updated_at.to_proto()),
        };
        // log::info!("Converted user: {:?}", user);
        return user;
    }

    fn to_author(&self) -> models::Author {
        models::Author {
            id: self.id,
            username: self.username.clone(),
            avatar_media_id: self.avatar_media_id,
            real_name: self.real_name.clone(),
            permissions: self.permissions.clone(),
        }
    }
}

pub trait ToProtoAuthor {
    fn to_proto(&self, media_lookup: Option<&MediaLookup>) -> Author;
    fn to_proto_user_attendee(&self, media_lookup: Option<&MediaLookup>) -> UserAttendee;
}
impl ToProtoAuthor for models::Author {
    fn to_proto(&self, media_lookup: Option<&MediaLookup>) -> Author {
        Author {
            user_id: self.id.to_proto_id().to_string(),
            username: Some(self.username.to_owned()),
            avatar: self
                .avatar_media_id
                .to_owned()
                .map(|id| {
                    media_lookup
                        .find_media(id)
                        .map(|media_ref| Box::new(media_ref.to_proto(&None)))
                })
                .flatten(),
            real_name: Some(self.real_name.to_owned()),
            permissions: self.permissions.to_i32_permissions(),
        }
    }
    fn to_proto_user_attendee(&self, media_lookup: Option<&MediaLookup>) -> UserAttendee {
        UserAttendee {
            user_id: self.id.to_proto_id().to_string(),
            username: Some(self.username.to_owned()),
            avatar: self
                .avatar_media_id
                .to_owned()
                .map(|id| {
                    media_lookup
                        .find_media(id)
                        .map(|media_ref| media_ref.to_proto(&None))
                })
                .flatten(),
            real_name: Some(self.real_name.to_owned()),
            permissions: self.permissions.to_i32_permissions(),
        }
    }
}

pub trait ToProtoFollow {
    fn to_proto(&self) -> Follow;
    fn update_related_counts(&self, conn: &mut PgPooledConnection) -> Result<(), Status>;
}
impl ToProtoFollow for models::Follow {
    fn to_proto(&self) -> Follow {
        return Follow {
            user_id: self.user_id.to_proto_id().to_string(),
            target_user_id: self.target_user_id.to_proto_id().to_string(),
            target_user_moderation: self.target_user_moderation.to_proto_moderation().unwrap()
                as i32,
            created_at: Some(self.created_at.to_proto()),
            updated_at: Some(self.updated_at.to_proto()),
        };
    }

    fn update_related_counts(&self, conn: &mut PgPooledConnection) -> Result<(), Status> {
        crate::logic::update_follow_counts(self.user_id, self.target_user_id, conn)
            .map_err(|_| Status::new(Code::Internal, "error_updating_follow_counts"))
    }
}
