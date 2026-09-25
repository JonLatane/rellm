use std::time::SystemTime;

use diesel::result::DatabaseErrorKind::UniqueViolation;
use diesel::result::Error::DatabaseError;
use diesel::result::Error::RollbackTransaction;
use diesel::NotFound;
use diesel::*;
use tonic::{Code, Status};

use crate::db_connection::PgPooledConnection;
use crate::logic::contact_protocol_supported;
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::rpcs;
use crate::schema::users;

use crate::rpcs::validations::*;

/// Applies a client-supplied `ContactMethod` (`request.phone`/`.email`) onto the currently-stored
/// JSONB value, folding in the fields the server always computes/protects itself. Guards against
/// a plain `UpdateUser` call spoofing a verified contact method: `value`/`visibility`/
/// `consent_state` are the *only* fields ever taken from client input -- `verified_at`/
/// `verification_in_progress` are always carried forward from the currently-stored copy, UNLESS
/// `value` actually changed (or is newly set), in which case editing invalidates any prior
/// verification and both are reset to `None` (correct behavior, not just a safety guard --
/// otherwise brute-forcing `UpdateUser` to fake a verified status would work). `supported_by_server`
/// is always recomputed here via `is_supported`, never trusted from client input or carried over
/// stale from a prior write (e.g. if Twilio gets disabled server-side after a number was marked
/// supported).
///
/// `consent_state`/`consent_history` (see `docs/contact_integrations.md`) work differently:
/// `consent_state` *is* taken from client input (this is how `UserProfilePage.elm`'s consent
/// checkbox actually grants/revokes consent), but `consent_history` itself is never trusted from
/// the client -- whenever the requested `consent_state` differs from the currently-stored one, the
/// server appends its own `ContactConsentChange` (server-timestamped) rather than accepting
/// whatever history the client sent. Sending the same `consent_state` the `ContactMethod` already
/// has is a no-op (no new history entry). Consent is intentionally independent of `value`/
/// `verified_at` -- changing the phone number or re-verifying does not itself grant or revoke
/// consent, and revoking/re-granting doesn't touch verification.
///
/// `incoming: None` (the client's request omits this contact method entirely) clears the stored
/// value, same as every other plain field `update_user` copies over unconditionally -- callers
/// (e.g. `UserProfilePage.elm`) always resend the user's current phone/email on every save, so an
/// absent value here means the user genuinely has none.
fn apply_contact_method_update(
    existing: Option<serde_json::Value>,
    incoming: Option<&ContactMethod>,
    is_supported: impl Fn(&str) -> bool,
) -> Option<serde_json::Value> {
    let incoming = incoming?;
    let existing_cm: Option<ContactMethod> =
        existing.and_then(|v| serde_json::from_value(v).ok());
    let value_changed = existing_cm.as_ref().and_then(|cm| cm.value.clone()) != incoming.value;
    let (verified_at, verification_in_progress) = if value_changed {
        (None, None)
    } else {
        (
            existing_cm.as_ref().and_then(|cm| cm.verified_at.clone()),
            existing_cm
                .as_ref()
                .and_then(|cm| cm.verification_in_progress.clone()),
        )
    };
    let supported_by_server = incoming.value.as_deref().is_some_and(&is_supported);

    let existing_consent_state = existing_cm
        .as_ref()
        .map(|cm| ContactConsentState::try_from(cm.consent_state).unwrap_or_default())
        .unwrap_or_default();
    let requested_consent_state =
        ContactConsentState::try_from(incoming.consent_state).unwrap_or_default();
    let mut consent_history = existing_cm
        .as_ref()
        .map(|cm| cm.consent_history.clone())
        .unwrap_or_default();
    if requested_consent_state != existing_consent_state {
        consent_history.push(ContactConsentChange {
            state: requested_consent_state as i32,
            changed_at: Some(SystemTime::now().into()),
        });
    }

    Some(
        serde_json::to_value(ContactMethod {
            value: incoming.value.clone(),
            visibility: incoming.visibility,
            supported_by_server,
            verified_at,
            verification_in_progress,
            consent_state: requested_consent_state as i32,
            consent_history,
        })
        .unwrap(),
    )
}

pub fn update_user(
    request: User,
    current_user: &models::User,
    conn: &mut PgPooledConnection,
) -> Result<User, Status> {
    validate_user(&request)?;

    let user_db_id = request.id.to_db_id_or_err("id")?;
    let avatar_media_id = request
        .avatar
        .as_ref()
        .map(|a| &a.id)
        .to_db_opt_id_or_err("avatar")?;

    let self_update = request.id == current_user.id.to_proto_id();
    let mut admin = false;
    let mut moderator = false;
    if !self_update {
        validate_any_permission(
            &Some(current_user),
            vec![Permission::Admin, Permission::ModerateUsers],
        )?;
    }
    match validate_permission(&Some(current_user), Permission::Admin) {
        Ok(_) => admin = true,
        Err(_) => {}
    };
    match validate_permission(&Some(current_user), Permission::ModerateUsers) {
        Ok(_) => moderator = true,
        Err(_) => {}
    };
    log::info!(
        "self_update: {}, admin: {}, moderator: {}",
        self_update,
        admin,
        moderator
    );

    let transaction_result: Result<models::User, diesel::result::Error> = conn
        .transaction::<models::User, diesel::result::Error, _>(|conn| {
            let mut existing_user = users::table
                .select(models::USER_COLUMNS)
                .filter(users::id.eq(user_db_id))
                .first::<models::User>(conn)?;
            if admin || self_update {
                existing_user.username = request.username.to_owned();
                existing_user.real_name = request.real_name.to_owned();
                existing_user.bio = request.bio.to_owned();
                existing_user.avatar_media_id = avatar_media_id;
                if request.visibility == Visibility::GlobalPublic as i32
                    && existing_user.visibility.to_proto_visibility().unwrap()
                        != Visibility::GlobalPublic
                {
                    validate_permission(&Some(current_user), Permission::PublishUsersGlobally)
                        .map_err(|_| RollbackTransaction)?;
                }
                existing_user.visibility = request.visibility.to_string_visibility();
                existing_user.default_follow_moderation =
                    request.default_follow_moderation.to_string_moderation();

                // `ContactMethod.supported_by_server` mirrors whichever `ContactProtocol` this
                // value's scheme (`tel:`/`mailto:`) corresponds to in the admin-set
                // `ServerConfiguration.supported_contact_protocols` (see that field's own proto
                // doc for why `users.proto` can't reference it directly) --
                // `contact_protocol_supported` is already invariant-enforced at `ConfigureServer`
                // time, so a `true` here always implies a real provider is actually enabled too.
                // `mailto:` is checked the same way as `tel:` for consistency, even though
                // `CONTACT_PROTOCOL_MAILTO` can never actually be enabled today (see
                // `validate_configuration`). See `apply_contact_method_update`'s own doc for why
                // `supported_by_server` is always recomputed here rather than trusted from the
                // request.
                let tel_supported = contact_protocol_supported(conn, ContactProtocol::Tel);
                let mailto_supported = contact_protocol_supported(conn, ContactProtocol::Mailto);
                existing_user.phone = apply_contact_method_update(
                    existing_user.phone.to_owned(),
                    request.phone.as_ref(),
                    |value| value.starts_with("tel:") && tel_supported,
                );
                existing_user.email = apply_contact_method_update(
                    existing_user.email.to_owned(),
                    request.email.as_ref(),
                    |value| value.starts_with("mailto:") && mailto_supported,
                );
            }
            if admin {
                // `EDIT_CLUSTER_SETTINGS`/`EDIT_SERVER_MEDIA_ALLOCATION` are deliberately never
                // settable via `UpdateUser` -- see their own docs -- so each is always carried
                // forward from whatever the user already had, regardless of what this request
                // asked for (grant or revoke).
                let existing_permissions = existing_user.permissions.to_proto_permissions();
                let has_cluster_settings =
                    existing_permissions.contains(&Permission::EditClusterSettings);
                let has_server_media_allocation =
                    existing_permissions.contains(&Permission::EditServerMediaAllocation);
                let mut permissions = request.permissions.to_proto_permissions();
                permissions.retain(|p| {
                    *p != Permission::EditClusterSettings
                        && *p != Permission::EditServerMediaAllocation
                });
                if has_cluster_settings {
                    permissions.push(Permission::EditClusterSettings);
                }
                if has_server_media_allocation {
                    permissions.push(Permission::EditServerMediaAllocation);
                }
                existing_user.permissions = permissions.to_json_permissions();

                // Storage quota: admin-only, same gate as `permissions` above. Unset (`None`)
                // means unlimited -- see `User.media_storage_limit_bytes`'s own proto doc.
                existing_user.media_storage_limit_bytes =
                    request.media_storage_limit_bytes.map(|b| b as i64);
            }
            if admin || moderator {
                existing_user.moderation = request.moderation.to_string_moderation();
            }
            existing_user.updated_at = SystemTime::now().into();

            log::info!("Updating user: {:?}", existing_user);
            match diesel::update(users::table)
                .filter(users::id.eq(&existing_user.id))
                .set(&existing_user)
                .execute(conn)
            {
                Ok(_) => Ok(existing_user),
                Err(e) => Err(e),
            }
        });

    let result = match transaction_result {
        //TODO: properly marshal this stuff
        Ok(_user) => {
            rpcs::get_users(
                GetUsersRequest {
                    user_id: Some(request.id.clone()),
                    ..Default::default()
                },
                &Some(current_user),
                conn,
            )
            .map(|u| u.users[0].to_owned())
            // Ok(result.to_proto(&None, &None, None))
        }
        Err(NotFound) => Err(Status::new(Code::NotFound, "user_not_found")),
        Err(RollbackTransaction) => Err(Status::new(
            Code::InvalidArgument,
            "cannot_publish_globally",
        )),
        Err(DatabaseError(UniqueViolation, _)) => {
            Err(Status::new(Code::NotFound, "duplicate_username"))
        }
        Err(e) => {
            log::error!("Error updating user: {:?}", e);
            Err(Status::new(Code::Internal, "data_error"))
        }
    };
    log::info!("UpdateUser::request: {:?}, result: {:?}", &request, result);

    result
}
