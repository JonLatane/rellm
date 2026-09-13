use std::sync::Arc;

use base64::{Engine, prelude::BASE64_URL_SAFE_NO_PAD};
use serde::Serialize;
use web_push::{
    ContentEncoding, IsahcWebPushClient, SubscriptionInfo, VapidSignatureBuilder, WebPushClient,
    WebPushError, WebPushMessageBuilder,
};

use crate::db_connection::PgPool;
use crate::marshaling::ToProtoId;
use crate::models;
use crate::protos;
use crate::rpcs::get_server_configuration_model;

/// The JSON shape delivered (encrypted, per the Web Push standard) to the browser's service
/// worker `push` event -- see this file's own module doc comment. `url` (see
/// `notification_url`) is the full deep link `service-worker.js`'s `notificationclick` handler
/// navigates to, and `icon` (see `build_icon_url`) the sender's avatar to show alongside it --
/// both omitted entirely (not sent as `null`, via `skip_serializing_if`) rather than guessed at
/// when there's nothing to build them from (no configured `ExternalCdnConfig.frontend_host`, or,
/// for `icon`, no sender avatar/an inbound email with no local sender at all). `host` (the same
/// `frontend_host` `url`/`icon` are built from, plain rather than baked into a URL) is what lets
/// `service-worker.js`'s `push` handler tell an already-open tab *which* server's messages to
/// refresh, via `Ports.pushMessageReceived` -- see `Components.Pages.MessagesPage`'s own
/// `PushNotificationReceived`.
#[derive(Serialize)]
struct PushPayload {
    title: String,
    body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    icon: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    host: Option<String>,
}

/// The "who" half of a notification's title -- see `build_title`. Two shapes, not one generic
/// `{ from: String, to: String }`, because they render differently: an in-app Message always has
/// a real sender/recipient(s) on *this* server, so the title also names the server (disambiguating
/// once a browser can ever hold subscriptions to more than one); an inbound email's From/To are
/// raw, unauthenticated header text with no such guarantee, so it's shown as-is with no host
/// suffix. See `send_message::send_message`/`web::email::create_email_message`, the two sites that
/// build one of these each.
pub enum NotificationParticipants {
    Email { from: String, to: String },
    InApp { from_username: String, to_usernames: String },
}

/// Everything `notify_message_recipients` needs to actually render a notification's content --
/// gathered by its two callers (see `NotificationParticipants`'s own doc comment), but *rendered*
/// here rather than there, since the in-app title's host suffix needs `ExternalCdnConfig` (see
/// `build_title`), which only this module already fetches.
pub struct MessageNotificationContent {
    pub participants: NotificationParticipants,
    pub subject: Option<String>,
    /// The Message's full body text (not pre-truncated) -- `build_body` decides for itself how
    /// much of it to show, since that depends on whether `subject` is present too.
    pub body_text: String,
    /// The sender's own `avatar_media_id` (see `models::Author`) -- always `None` for
    /// `NotificationParticipants::Email` (no local sender to have one), and for an anonymous or
    /// avatar-less in-app sender.
    pub sender_avatar_media_id: Option<i64>,
}

/// Fans a new-Message notification out to every push subscription belonging to
/// `recipient_user_ids`, via the server's configured `WebPushConfig` (VAPID keys) -- see
/// `send_message::send_message`/`web::email::create_email_message`, this module's two callers.
/// `messaging_group_id`/`message_id` (the raw DB ids, not yet `to_proto_id()`-encoded -- this
/// does that itself, see `notification_url`) are the `Message`'s own, used to build a deep link
/// straight to it (`?messaging_group=<id>#message-<id>`, the same shape
/// `Components.Pages.MessagesPage.groupQueryParams`/`messageDomId` build client-side) rather than
/// just bringing the app to the front with no context.
///
/// Runs entirely in a spawned background task: neither trigger point should have its own
/// response (an in-app `SendMessage` RPC, or Stalwart's inbound-email MTA hook) wait on however
/// long it takes to reach every recipient's push subscriptions, and a failure to notify shouldn't
/// fail the Message send/delivery itself. `pool` is used only inside that task, for its own fresh
/// connection -- the caller's own `conn` can't cross the `tokio::spawn` boundary.
///
/// No-ops (logging a warning, not panicking) if called outside a Tokio runtime -- true of the
/// plain synchronous `#[test]`s in `tests::send_message_tests`, which call `rpcs::send_message`
/// directly rather than through the server's own tonic/Rocket runtimes.
pub fn notify_message_recipients(
    pool: Arc<PgPool>,
    recipient_user_ids: Vec<i64>,
    content: MessageNotificationContent,
    messaging_group_id: i64,
    message_id: i64,
) {
    let Ok(handle) = tokio::runtime::Handle::try_current() else {
        log::warn!("notify_message_recipients: no Tokio runtime available, skipping");
        return;
    };
    handle.spawn(async move {
        if let Err(error) = send_message_notifications(
            pool,
            recipient_user_ids,
            content,
            messaging_group_id,
            message_id,
        )
        .await
        {
            log::warn!("notify_message_recipients failed: {:?}", error);
        }
    });
}

async fn send_message_notifications(
    pool: Arc<PgPool>,
    recipient_user_ids: Vec<i64>,
    content: MessageNotificationContent,
    messaging_group_id: i64,
    message_id: i64,
) -> Result<(), String> {
    let mut conn = pool.get().map_err(|e| e.to_string())?;

    let web_push_config = stored_web_push_config(&mut conn)?;
    // No VAPID keys configured on this server -- nothing to sign/send with, and nothing to
    // configure this behind (see `RegisterPushSubscription`'s own doc comment on why registration
    // itself doesn't gate on this).
    let Some(web_push_config) = web_push_config else {
        return Ok(());
    };

    let subscriptions = models::get_push_subscriptions_for_users(&recipient_user_ids, &mut conn)
        .map_err(|e| e.to_string())?;
    if subscriptions.is_empty() {
        return Ok(());
    }

    validate_private_vapid_key(&web_push_config.private_vapid_key)?;

    let frontend_host = stored_frontend_host(&mut conn)?;
    let url = notification_url(frontend_host.as_deref(), messaging_group_id, message_id);
    let title = build_title(&content.participants, frontend_host.as_deref());
    let body = build_body(content.subject.as_deref(), &content.body_text);
    let icon = build_icon_url(frontend_host.as_deref(), content.sender_avatar_media_id);

    let partial_signature_builder =
        VapidSignatureBuilder::from_base64_no_sub(&web_push_config.private_vapid_key)
            .map_err(|e| format!("{:?}", e))?;
    let client = IsahcWebPushClient::new().map_err(|e| format!("{:?}", e))?;
    let payload = serde_json::to_vec(&PushPayload { title, body, url, icon, host: frontend_host })
        .map_err(|e| e.to_string())?;

    for subscription in subscriptions {
        let subscription_info = SubscriptionInfo::new(
            subscription.endpoint.clone(),
            subscription.p256dh_key.clone(),
            subscription.auth_key.clone(),
        );

        let send_result = (|| -> Result<_, WebPushError> {
            let signature = partial_signature_builder
                .clone()
                .add_sub_info(&subscription_info)
                .build()?;
            let mut builder = WebPushMessageBuilder::new(&subscription_info);
            builder.set_payload(ContentEncoding::Aes128Gcm, &payload);
            builder.set_vapid_signature(signature);
            builder.build()
        })();

        let send_result = match send_result {
            Ok(message) => client.send(message).await,
            Err(error) => Err(error),
        };

        match send_result {
            Ok(()) => {}
            // The push service itself says this endpoint is dead, or is otherwise permanently
            // unusable -- prune it so it isn't retried on every future Message. Confirmed in
            // production: a subscription registered under a since-rotated VAPID public key (see
            // today's key-corruption/regeneration saga) comes back as `BadRequest` with FCM's own
            // `{"reason":"VapidPkHashMismatch"}` -- that subscription's `endpoint` is permanently
            // tied to the *old* key and will never succeed no matter how many times it's retried,
            // same as an outright-dead endpoint. Any other error (network blip, server error, a
            // currently-misconfigured VAPID key that might get fixed) is just logged; those
            // aren't necessarily about this one subscription, so the subscription might still be
            // good next time.
            Err(WebPushError::EndpointNotValid(_))
            | Err(WebPushError::EndpointNotFound(_))
            | Err(WebPushError::BadRequest(_)) => {
                if let Err(e) = models::delete_push_subscription_by_id(subscription.id, &mut conn) {
                    log::warn!(
                        "Failed to prune dead push subscription {}: {:?}",
                        subscription.id,
                        e
                    );
                }
            }
            Err(error) => {
                log::warn!(
                    "Failed to send push notification to subscription {}: {:?}",
                    subscription.id,
                    error
                );
            }
        }
    }

    Ok(())
}

/// Fetches this server's configured `WebPushConfig`, if any, with `private_vapid_key` intact.
///
/// Deliberately *not* `get_server_configuration_model(conn)?.to_proto().web_push_config` --
/// `to_proto` (see `ToProtoServerConfiguration`) always blanks `private_vapid_key` before a
/// *client* sees it, since it's meant to never leave the server. Going through that here would
/// blank it before this, the one place actually meant to use it, ever sees it either -- confirmed
/// in production: every send silently no-op'd (`validate_private_vapid_key` rightfully rejecting
/// the now-always-empty key) even with a fully valid key stored. Parsing the raw model's own
/// `web_push_config` column directly is the same "read the unblanked value" pattern
/// `configure_server`'s own merge-on-blank block already relies on.
pub(crate) fn stored_web_push_config(
    conn: &mut crate::db_connection::PgPooledConnection,
) -> Result<Option<protos::WebPushConfig>, String> {
    Ok(get_server_configuration_model(conn)
        .map_err(|e| e.to_string())?
        .web_push_config
        .and_then(|c| serde_json::from_value::<protos::WebPushConfig>(c).ok()))
}

/// Fetches this server's own public-facing frontend host (`ExternalCdnConfig.frontend_host`), if
/// configured -- used to build a full `https://` deep link/avatar URL for a push notification
/// (`notification_url`/`build_icon_url`), since a push payload has no notion of "this server" the
/// way an in-app fetch already scoped to a connection does. Also what `build_title` names an
/// in-app Message's sender/recipients "on", so a browser that can ever hold subscriptions from
/// more than one server can tell them apart at a glance.
pub(crate) fn stored_frontend_host(
    conn: &mut crate::db_connection::PgPooledConnection,
) -> Result<Option<String>, String> {
    Ok(get_server_configuration_model(conn)
        .map_err(|e| e.to_string())?
        .external_cdn_config
        .and_then(|c| serde_json::from_value::<protos::ExternalCdnConfig>(c).ok())
        .map(|c| c.frontend_host))
}

/// Builds the full `https://<frontend_host>/messages?messaging_group=<id>#message-<id>` deep
/// link a push notification's `PushPayload.url` should point to -- the same query
/// param/fragment shape `Components.Pages.MessagesPage.groupQueryParams`/`messageDomId` build
/// client-side for a `MessagingGroup` conversation, given plain ids (no `@<host>` federation
/// suffix): a notification is always about a Message that lives on *this* server, so the
/// deep link's own host and the Message's group's host are always the same one, exactly the case
/// `groupRouteId` already renders as a bare id with no suffix.
///
/// `Message.messaging_group_id` is never null (`find_or_create_messaging_group` runs for every
/// Message, in-app or inbound email alike -- see `send_message`/`web::email::create_email_message`,
/// this function's two callers by way of `send_message_notifications`), so the only reason this
/// can come back `None` is `frontend_host` itself being `None` (no `ExternalCdnConfig` configured)
/// -- in which case there's no known public host to build a real URL against at all, and
/// `send_message_notifications` just omits `url` from the payload entirely rather than guessing.
fn notification_url(
    frontend_host: Option<&str>,
    messaging_group_id: i64,
    message_id: i64,
) -> Option<String> {
    frontend_host.map(|host| {
        format!(
            "https://{}/messages?messaging_group={}#message-{}",
            host,
            messaging_group_id.to_proto_id(),
            message_id.to_proto_id()
        )
    })
}

/// Renders `participants` into a notification's title -- see `NotificationParticipants`'s own
/// doc comment for why the two variants render differently. `▶` stands in for "to" between the
/// sender and recipient(s) (a deliberate stylistic choice, not a fallback for anything -- plain
/// ASCII "to" would be just as valid UTF-8 in a push payload). Falls back to just the "from" half
/// alone if `to`/`to_usernames` came back empty (shouldn't happen in practice -- both callers
/// always have at least one recipient, per `notify_message_recipients`'s own
/// `recipient_user_ids`), or, for `InApp`, if `frontend_host` is `None` (nothing to name it after).
fn build_title(participants: &NotificationParticipants, frontend_host: Option<&str>) -> String {
    match participants {
        NotificationParticipants::Email { from, to } => {
            if to.is_empty() {
                from.clone()
            } else {
                format!("{} ▶ {}", from, to)
            }
        }
        NotificationParticipants::InApp { from_username, to_usernames } => {
            match (frontend_host, to_usernames.is_empty()) {
                (Some(host), false) => format!("{} ▶ {} on {}", from_username, to_usernames, host),
                (Some(host), true) => format!("{} on {}", from_username, host),
                (None, false) => format!("{} ▶ {}", from_username, to_usernames),
                (None, true) => from_username.clone(),
            }
        }
    }
}

/// Renders a notification's body: `subject` plus the Message's own first line of body text if
/// `subject` is non-blank, otherwise the body's own first *two* lines -- either way, two lines
/// total. `\n`-joined; every browser this has been checked against (Chrome, Firefox, Safari)
/// renders an embedded newline in a `Notification`'s `body` as an actual line break, not literal
/// text.
fn build_body(subject: Option<&str>, body_text: &str) -> String {
    let mut body_lines = body_text.lines().map(str::trim).filter(|line| !line.is_empty());
    match subject.map(str::trim).filter(|subject| !subject.is_empty()) {
        Some(subject) => match body_lines.next() {
            Some(first_line) => format!("{}\n{}", subject, first_line),
            None => subject.to_string(),
        },
        None => body_lines.take(2).collect::<Vec<_>>().join("\n"),
    }
}

/// Builds a full `https://<frontend_host>/media/<id>?size=small` URL for a notification's `icon`
/// -- `?size=small` (see `protos::MediaConversion`) rather than the original upload: a
/// notification icon renders tiny (well under 320px on every platform this has been checked
/// against), so serving the original would just waste bandwidth decoding/downscaling an image far
/// larger than anything actually shown. `None` if either piece is missing -- no configured
/// `frontend_host`, or (the common case: an inbound email, or an avatar-less/anonymous in-app
/// sender) no `avatar_media_id` to build one from at all.
fn build_icon_url(frontend_host: Option<&str>, avatar_media_id: Option<i64>) -> Option<String> {
    match (frontend_host, avatar_media_id) {
        (Some(host), Some(id)) => Some(format!("https://{}/media/{}?size=small", host, id.to_proto_id())),
        _ => None,
    }
}

/// `VapidSignatureBuilder::from_base64_no_sub` hands its decoded bytes straight to `jwt_simple`'s
/// `ES256KeyPair::from_bytes`, which -- for anything other than exactly 32 bytes (a P-256 private
/// scalar) -- panics via a bare `assert_eq!` instead of returning a `Result`. Confirmed in
/// production: a server with `public_vapid_key` set but `private_vapid_key` still blank (see
/// `configure_server`'s merge-on-blank -- an admin who only ever saved the Public VAPID Key row
/// never actually set this one) crashed both backend pods the moment a message first tried to
/// notify. Decoding and length-checking it ourselves first turns that into an ordinary `Err`
/// `send_message_notifications` already handles gracefully, before ever reaching the panicking
/// call.
fn validate_private_vapid_key(private_vapid_key: &str) -> Result<(), String> {
    let len = BASE64_URL_SAFE_NO_PAD
        .decode(private_vapid_key)
        .map_err(|e| format!("invalid private_vapid_key (not valid base64url): {}", e))?
        .len();
    if len != 32 {
        return Err(format!(
            "invalid private_vapid_key: expected 32 bytes, got {} -- is WebPushConfig only half-configured?",
            len
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A real 32-byte VAPID private key, base64url-no-pad encoded -- lifted from the `web-push`
    /// crate's own test fixtures (`vapid::builder::tests::PRIVATE_BASE64`), so this is a
    /// known-good value rather than something hand-rolled that might not actually decode to a
    /// valid P-256 scalar.
    const VALID_PRIVATE_KEY: &str = "IQ9Ur0ykXoHS9gzfYX0aBjy9lvdrjx_PFUXmie9YRcY";

    #[test]
    fn empty_private_vapid_key_is_rejected_not_panicked() {
        // The exact production shape: `WebPushConfig.private_vapid_key` still `""` because only
        // the Public VAPID Key row was ever saved (see `configure_server`'s merge-on-blank).
        assert!(validate_private_vapid_key("").is_err());
    }

    #[test]
    fn wrong_length_private_vapid_key_is_rejected() {
        // Valid base64url, but decodes to fewer than 32 bytes.
        assert!(validate_private_vapid_key("AAAAAAAAAAAAAAAAAAAAAA").is_err());
    }

    #[test]
    fn malformed_base64_private_vapid_key_is_rejected() {
        assert!(validate_private_vapid_key("not valid base64url!!!").is_err());
    }

    #[test]
    fn well_formed_private_vapid_key_is_accepted() {
        assert!(validate_private_vapid_key(VALID_PRIVATE_KEY).is_ok());
    }

    #[test]
    fn notification_url_builds_a_deep_link_from_the_given_frontend_host() {
        let url = notification_url(Some("example.social"), 42, 99)
            .expect("frontend_host is given, so a url should be built");
        assert_eq!(
            url,
            format!(
                "https://example.social/messages?messaging_group={}#message-{}",
                42i64.to_proto_id(),
                99i64.to_proto_id()
            )
        );
    }

    #[test]
    fn notification_url_is_none_without_a_frontend_host() {
        assert_eq!(notification_url(None, 1, 2), None);
    }

    #[test]
    fn email_title_includes_from_and_to() {
        let participants = NotificationParticipants::Email {
            from: "jonlatane@armothy.local".to_string(),
            to: "jon@ato.band".to_string(),
        };
        assert_eq!(
            build_title(&participants, Some("ato.band")),
            "jonlatane@armothy.local ▶ jon@ato.band"
        );
    }

    #[test]
    fn email_title_falls_back_to_just_from_without_a_to() {
        let participants = NotificationParticipants::Email {
            from: "jonlatane@armothy.local".to_string(),
            to: "".to_string(),
        };
        assert_eq!(build_title(&participants, Some("ato.band")), "jonlatane@armothy.local");
    }

    #[test]
    fn in_app_title_includes_from_to_and_host() {
        let participants = NotificationParticipants::InApp {
            from_username: "ato".to_string(),
            to_usernames: "jon".to_string(),
        };
        assert_eq!(build_title(&participants, Some("ato.band")), "ato ▶ jon on ato.band");
    }

    #[test]
    fn in_app_title_without_a_frontend_host_drops_the_on_suffix() {
        let participants = NotificationParticipants::InApp {
            from_username: "ato".to_string(),
            to_usernames: "jon".to_string(),
        };
        assert_eq!(build_title(&participants, None), "ato ▶ jon");
    }

    #[test]
    fn body_with_a_subject_is_the_subject_plus_the_bodys_first_line() {
        assert_eq!(
            build_body(Some("Hi!"), "Testing from swaks.\r\n\r\nSecond line."),
            "Hi!\nTesting from swaks."
        );
    }

    #[test]
    fn body_without_a_subject_is_the_bodys_first_two_lines() {
        assert_eq!(
            build_body(None, "First line.\r\n\r\nSecond line.\r\n\r\nThird line."),
            "First line.\nSecond line."
        );
    }

    #[test]
    fn body_without_a_subject_and_only_one_body_line_is_just_that_line() {
        assert_eq!(build_body(None, "Only line."), "Only line.");
    }

    #[test]
    fn blank_subject_is_treated_the_same_as_no_subject() {
        assert_eq!(
            build_body(Some("   "), "First line.\r\nSecond line."),
            "First line.\nSecond line."
        );
    }

    #[test]
    fn icon_url_combines_frontend_host_and_avatar_media_id() {
        let url = build_icon_url(Some("ato.band"), Some(42)).expect("both pieces given");
        assert_eq!(url, format!("https://ato.band/media/{}?size=small", 42i64.to_proto_id()));
    }

    #[test]
    fn icon_url_is_none_without_an_avatar() {
        assert_eq!(build_icon_url(Some("ato.band"), None), None);
    }

    #[test]
    fn icon_url_is_none_without_a_frontend_host() {
        assert_eq!(build_icon_url(None, Some(42)), None);
    }
}
