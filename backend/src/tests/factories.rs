//! Test data builders for DB-backed specs. Each `#[test]` gets its own connection from
//! [`test_conn`] and should wrap its body in `conn.test_transaction(...)`, so nothing created
//! here is ever committed to `TEST_DATABASE_URL`.

use std::sync::Arc;
use std::time::SystemTime;

use diesel::*;
use diesel_migrations::MigrationHarness;
use s3::Bucket;

use crate::db_connection::{establish_test_pool, PgPool, PgPooledConnection, MIGRATIONS};
use crate::marshaling::*;
use crate::models;
use crate::protos::*;
use crate::schema::{
    event_attendances, occasion_sync_destinations, occasions, events, follows,
    group_posts, groups, media, memberships, messages, post_sync_destinations, posts,
    server_configurations, sync_destinations, sync_sources, users,
};

lazy_static! {
    static ref TEST_POOL: Arc<PgPool> = {
        let pool = establish_test_pool();
        pool.get()
            .expect("failed to connect to TEST_DATABASE_URL")
            .run_pending_migrations(MIGRATIONS)
            .expect("failed to run migrations against TEST_DATABASE_URL");
        Arc::new(pool)
    };
}

/// Returns a pooled connection to `TEST_DATABASE_URL`, migrating it on first use (once per test
/// binary process, since `Once`/`lazy_static` state doesn't cross the parallel test threads
/// cargo spawns, but each of those threads shares this same process-wide pool/static).
pub fn test_conn() -> PgPooledConnection {
    TEST_POOL
        .get()
        .expect("failed to check out a pooled test connection")
}

/// The same process-wide pool `test_conn` checks connections out of -- for specs exercising an
/// RPC (like `send_message`) that itself needs an `Arc<PgPool>`, e.g. to spawn
/// `web_push::notify_message_recipients` with its own connection.
pub fn test_pool() -> Arc<PgPool> {
    TEST_POOL.clone()
}

pub fn create_user(conn: &mut PgPooledConnection, username: &str) -> models::User {
    create_user_with(
        conn,
        username,
        Visibility::ServerPublic,
        Moderation::Unmoderated,
    )
}

pub fn create_user_with(
    conn: &mut PgPooledConnection,
    username: &str,
    visibility: Visibility,
    moderation: Moderation,
) -> models::User {
    insert_into(users::table)
        .values((
            users::username.eq(username),
            users::password_salted_hash.eq("test_hash"),
            users::real_name.eq(username),
            users::permissions.eq(vec![
                Permission::ViewPosts,
                Permission::CreatePosts,
                Permission::ViewGroups,
                Permission::FollowUsers,
            ]
            .to_json_permissions()),
            users::visibility.eq(visibility.to_string_visibility()),
            users::moderation.eq(moderation.to_string_moderation()),
        ))
        // users::search_text has no corresponding field on `models::User` (see USER_COLUMNS'
        // doc comment), so a plain `RETURNING *` can't deserialize into it - the explicit
        // column list is required here, same as create_post's own `POST_COLUMNS`.
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to create test user")
}

/// Like `create_user_with`, but with distinct `real_name`/`bio` text (`create_user_with` always
/// sets `real_name` equal to `username`, and leaves `bio` at its DB default of `""`) - for
/// `get_users_tests`' `USERS_TEXT_SEARCH` specs, which need each of username/real_name/bio to be
/// independently distinguishable/matchable.
pub fn create_user_with_profile(
    conn: &mut PgPooledConnection,
    username: &str,
    real_name: &str,
    bio: &str,
) -> models::User {
    insert_into(users::table)
        .values((
            users::username.eq(username),
            users::password_salted_hash.eq("test_hash"),
            users::real_name.eq(real_name),
            users::bio.eq(bio),
            users::permissions.eq(vec![
                Permission::ViewPosts,
                Permission::CreatePosts,
                Permission::ViewGroups,
                Permission::FollowUsers,
            ]
            .to_json_permissions()),
            users::visibility.eq(Visibility::GlobalPublic.to_string_visibility()),
            users::moderation.eq(Moderation::Unmoderated.to_string_moderation()),
        ))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to create test user")
}

/// Updates `user`'s `real_name`/`bio` - exercises `users.search_text`'s `GENERATED ALWAYS AS
/// ... STORED` recompute-on-update behavior (see
/// `2026-07-22-202628_add_search_text_to_users/up.sql`), for a spec confirming a changed
/// real_name/bio actually changes what that user matches on.
pub fn update_user_profile(
    conn: &mut PgPooledConnection,
    user: &models::User,
    real_name: &str,
    bio: &str,
) -> models::User {
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set((users::real_name.eq(real_name), users::bio.eq(bio)))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to update test user")
}

/// Sets `user`'s `phone` column directly to `contact_method` (serialized JSONB) -- bypasses
/// `update_user`'s own `apply_contact_method_update` logic entirely, so specs can seed exact
/// `verification_in_progress`/`verified_at` states (e.g. an already-expired or already-max-attempts
/// verification) that `UpdateUser` itself would never produce.
pub fn set_user_phone(
    conn: &mut PgPooledConnection,
    user: &models::User,
    contact_method: &ContactMethod,
) -> models::User {
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set(users::phone.eq(serde_json::to_value(contact_method).unwrap()))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to set test user phone")
}

/// `create_user`'s default permission set (`ViewPosts`/`CreatePosts`/`ViewGroups`/`FollowUsers`)
/// doesn't include `PublishPosts{Locally,Globally}` - specs exercising CreatePost/UpdatePost's
/// visibility handling grant those explicitly via this.
pub fn grant_permissions(
    conn: &mut PgPooledConnection,
    user: &models::User,
    permissions: Vec<Permission>,
) -> models::User {
    diesel::update(users::table.filter(users::id.eq(user.id)))
        .set(users::permissions.eq(permissions.to_json_permissions()))
        .returning(models::USER_COLUMNS)
        .get_result::<models::User>(conn)
        .expect("failed to update test user permissions")
}

#[derive(Clone)]
pub struct PostOpts {
    pub visibility: Visibility,
    pub moderation: Moderation,
    pub context: PostContext,
    pub parent_post_id: Option<i64>,
    pub title: Option<String>,
    pub content: Option<String>,
    /// Overrides `created_at`/`published_at`, which otherwise both default to `NOW()` - and
    /// since `NOW()` is frozen for the lifetime of a Postgres transaction, every post a test
    /// creates inside its `test_transaction` would otherwise get the *same* `created_at`. Specs
    /// asserting on `GetPosts`' `sort_published_at` ordering need distinct, explicit timestamps
    /// to have something meaningful to order by.
    pub created_at: Option<SystemTime>,
    pub published_at: Option<SystemTime>,
}

impl Default for PostOpts {
    fn default() -> Self {
        PostOpts {
            visibility: Visibility::ServerPublic,
            moderation: Moderation::Unmoderated,
            context: PostContext::Post,
            parent_post_id: None,
            title: Some("Test Post".to_string()),
            content: Some("Test content".to_string()),
            created_at: None,
            published_at: None,
        }
    }
}

/// `author: None` creates a post with no `user_id` (e.g. a reply left behind by a deleted user).
pub fn create_post(
    conn: &mut PgPooledConnection,
    author: Option<&models::User>,
    opts: PostOpts,
) -> models::Post {
    let post = insert_into(posts::table)
        .values(&models::NewPost {
            user_id: author.map(|u| u.id),
            parent_post_id: opts.parent_post_id,
            title: opts.title,
            link: None,
            content: opts.content,
            context: opts.context.to_string_post_context(),
            visibility: opts.visibility.to_string_visibility(),
            moderation: opts.moderation.to_string_moderation(),
            media: vec![],
            embed_link: false,
        })
        // posts::search_text has no corresponding field on `models::Post` (see POST_COLUMNS'
        // doc comment), so a plain `RETURNING *` can't deserialize into it - the explicit
        // column list is required here, same as in create_post.rs.
        .returning(models::POST_COLUMNS)
        .get_result::<models::Post>(conn)
        .expect("failed to create test post");

    if opts.created_at.is_none() && opts.published_at.is_none() {
        return post;
    }
    diesel::update(posts::table.filter(posts::id.eq(post.id)))
        .set((
            opts.created_at.map(|t| posts::created_at.eq(t)),
            opts.published_at.map(|t| posts::published_at.eq(t)),
        ))
        .returning(models::POST_COLUMNS)
        .get_result::<models::Post>(conn)
        .expect("failed to create test post")
}

pub struct MessageOpts {
    pub subject: Option<String>,
    pub body_text: Option<String>,
    /// Overrides `created_at`, which otherwise defaults to `NOW()` - frozen for the lifetime of a
    /// Postgres transaction, so specs asserting on `GetMessages`' recency ordering need distinct,
    /// explicit timestamps (mirroring `PostOpts::created_at`).
    pub created_at: Option<SystemTime>,
    /// Sets `email_headers.from` (only - `to`/`cc`/`bcc` are left empty), simulating an inbound
    /// email from this address - see `get_by_from_email`'s own spec module.
    pub from_email: Option<String>,
}

impl Default for MessageOpts {
    fn default() -> Self {
        MessageOpts {
            subject: Some("Test Subject".to_string()),
            body_text: Some("Test body".to_string()),
            created_at: None,
            from_email: None,
        }
    }
}

/// Creates a `Message` from `sender` (`None` for an anonymous/inbound-email-style Message) to
/// `to_users`, reusing (or creating) their `MessagingGroup` - the sender is folded into the group
/// too, mirroring `send_message.rs`'s own behavior.
pub fn create_message(
    conn: &mut PgPooledConnection,
    sender: Option<&models::User>,
    to_users: &[&models::User],
    opts: MessageOpts,
) -> models::Message {
    let mut group_user_ids: Vec<i64> = to_users.iter().map(|u| u.id).collect();
    if let Some(sender) = sender {
        group_user_ids.push(sender.id);
    }
    let messaging_group_id = models::find_or_create_messaging_group(group_user_ids, conn)
        .expect("failed to create test messaging group");

    let message = insert_into(messages::table)
        .values(&models::NewMessage {
            from_user_id: sender.map(|u| u.id),
            subject: opts.subject,
            body_text: opts.body_text,
            email_headers: opts.from_email.map(|from| {
                serde_json::to_value(models::EmailHeaders {
                    from: Some(from),
                    ..Default::default()
                })
                .unwrap()
            }),
            email_message_id: None,
            email_minio_path: None,
            messaging_group_id,
        })
        .returning(models::MESSAGE_COLUMNS)
        .get_result::<models::Message>(conn)
        .expect("failed to create test message");

    let Some(created_at) = opts.created_at else {
        return message;
    };
    diesel::update(messages::table.filter(messages::id.eq(message.id)))
        .set(messages::created_at.eq(created_at))
        .returning(models::MESSAGE_COLUMNS)
        .get_result::<models::Message>(conn)
        .expect("failed to update test message")
}

pub struct GroupOpts {
    pub non_member_permissions: Vec<Permission>,
}

impl Default for GroupOpts {
    fn default() -> Self {
        GroupOpts {
            non_member_permissions: vec![],
        }
    }
}

pub fn create_group(
    conn: &mut PgPooledConnection,
    shortname: &str,
    opts: GroupOpts,
) -> models::Group {
    insert_into(groups::table)
        .values(&models::NewGroup {
            name: shortname.to_string(),
            shortname: shortname.to_string(),
            description: "".to_string(),
            avatar_media_id: None,
            visibility: Visibility::ServerPublic.to_string_visibility(),
            non_member_permissions: opts.non_member_permissions.to_json_permissions(),
            default_membership_permissions: vec![Permission::ViewPosts].to_json_permissions(),
            default_membership_moderation: Moderation::Unmoderated.to_string_moderation(),
            default_post_moderation: Moderation::Unmoderated.to_string_moderation(),
            default_event_moderation: Moderation::Unmoderated.to_string_moderation(),
            member_count: 0,
        })
        .get_result::<models::Group>(conn)
        .expect("failed to create test group")
}

pub fn create_membership(
    conn: &mut PgPooledConnection,
    user: &models::User,
    group: &models::Group,
    user_moderation: Moderation,
    group_moderation: Moderation,
    permissions: Vec<Permission>,
) -> models::Membership {
    insert_into(memberships::table)
        .values(&models::NewMembership {
            user_id: user.id,
            group_id: group.id,
            permissions: permissions.to_json_permissions(),
            group_moderation: group_moderation.to_string_moderation(),
            user_moderation: user_moderation.to_string_moderation(),
        })
        .get_result::<models::Membership>(conn)
        .expect("failed to create test membership")
}

pub fn create_group_post(
    conn: &mut PgPooledConnection,
    post: &models::Post,
    group: &models::Group,
    user: &models::User,
    group_moderation: Moderation,
) -> models::GroupPost {
    insert_into(group_posts::table)
        .values(&models::NewGroupPost {
            group_id: group.id,
            post_id: post.id,
            user_id: user.id,
            group_moderation: group_moderation.to_string_moderation(),
        })
        .get_result::<models::GroupPost>(conn)
        .expect("failed to create test group post")
}

/// `user` is the follower; `target` is the account being followed (matches `follows.user_id` /
/// `follows.target_user_id`). Always `Approved` - see `create_follow_with_moderation` for a
/// `Pending` one (e.g. for `get_users_tests`' `follow_requests_text_search` specs).
pub fn create_follow(
    conn: &mut PgPooledConnection,
    user: &models::User,
    target: &models::User,
) -> models::Follow {
    create_follow_with_moderation(conn, user, target, Moderation::Approved)
}

pub fn create_follow_with_moderation(
    conn: &mut PgPooledConnection,
    user: &models::User,
    target: &models::User,
    target_user_moderation: Moderation,
) -> models::Follow {
    insert_into(follows::table)
        .values(&models::NewFollow {
            user_id: user.id,
            target_user_id: target.id,
            target_user_moderation: target_user_moderation.to_string_moderation(),
        })
        .get_result::<models::Follow>(conn)
        .expect("failed to create test follow")
}

/// Inserts a `sync_sources` row directly (bypassing `rpcs::create_sync_source`, so
/// no sync/HTTP fetch happens) -- for specs that only care about ownership/permission handling,
/// not the actual sync. Specs exercising sync itself should go through the RPC/logic functions
/// against a `serve_ics`-backed URL instead.
pub fn create_sync_source_row(
    conn: &mut PgPooledConnection,
    user: &models::User,
    ics_subscription_url: &str,
) -> models::SyncSource {
    insert_into(sync_sources::table)
        .values(&models::NewSyncSource {
            user_id: user.id,
            sync_interval_seconds: 3600,
            configuration: serde_json::json!({ "ics_subscription_url": ics_subscription_url }),
        })
        .get_result::<models::SyncSource>(conn)
        .expect("failed to create test sync source")
}

/// Mirrors `create_sync_source_row`, for an RSS/Atom feed subscription instead of an ICS one.
pub fn create_feed_sync_source_row(
    conn: &mut PgPooledConnection,
    user: &models::User,
    feed_subscription_url: &str,
) -> models::SyncSource {
    insert_into(sync_sources::table)
        .values(&models::NewSyncSource {
            user_id: user.id,
            sync_interval_seconds: 3600,
            configuration: serde_json::json!({ "rss_subscription_url": feed_subscription_url }),
        })
        .get_result::<models::SyncSource>(conn)
        .expect("failed to create test sync source")
}

/// Options for `create_event`'s underlying container `Post` (context `EVENT`) - mirrors
/// `PostOpts`, but only exposes the fields `get_events_tests` actually varies.
pub struct EventOpts {
    pub visibility: Visibility,
    pub moderation: Moderation,
    pub title: Option<String>,
    /// `EventInfo` JSON, e.g. `json!({"hide_location_until_rsvp_approved": true})` -- see
    /// `EventInfo`'s proto doc for the full set of recognized keys.
    pub info: serde_json::Value,
    /// An `Event` with zero `Occasion`s can't actually exist in production -- `create_event`
    /// (the RPC) rejects `occasions: vec![]` with `at_least_one_occasion_required`, and
    /// `get_events`' own visibility query (`query_visible_events!`) starts from an `INNER JOIN` on
    /// `occasions`, so a zero-occasion event is unqueryable even if it existed. Defaults to
    /// `Some(OccasionOpts::default())` so `create_event` always seeds one, owned by the same
    /// `author`, keeping every fixture built from this factory realistic without callers having to
    /// remember to add one themselves. Pass `None` when a test wants full control over its own
    /// occasion(s) instead (custom `OccasionOpts`, a different owner, etc.) -- see
    /// `get_events_tests::create_simple_event`.
    pub default_occasion: Option<OccasionOpts>,
}

impl Default for EventOpts {
    fn default() -> Self {
        EventOpts {
            visibility: Visibility::ServerPublic,
            moderation: Moderation::Unmoderated,
            title: Some("Test Post".to_string()),
            info: serde_json::json!({}),
            default_occasion: Some(OccasionOpts::default()),
        }
    }
}

/// Inserts an `events` row directly (bypassing `rpcs::create_event`) along with its container
/// `Post` (context `EVENT`, per `create_event.rs`), plus -- unless `opts.default_occasion` is
/// `None` -- one `Occasion` (see that field's doc for why). Returns just the event/its own
/// post, matching `rpcs::create_event`'s own `(Event, Post)`-shaped read path (`get_events`
/// filters on the container post's visibility/moderation/user_id independently of any occasion's
/// own post); callers that need to reference the seeded occasion itself should pass
/// `default_occasion: None` and call `create_occasion` directly instead.
pub fn create_event(
    conn: &mut PgPooledConnection,
    author: &models::User,
    opts: EventOpts,
) -> (models::Event, models::Post) {
    let default_occasion = opts.default_occasion;
    let post = create_post(
        conn,
        Some(author),
        PostOpts {
            visibility: opts.visibility,
            moderation: opts.moderation,
            context: PostContext::Event,
            title: opts.title,
            ..Default::default()
        },
    );
    let event = insert_into(events::table)
        .values(&models::NewEvent {
            post_id: post.id,
            info: opts.info,
        })
        .get_result::<models::Event>(conn)
        .expect("failed to create test event");
    if let Some(occasion_opts) = default_occasion {
        create_occasion(conn, &event, Some(author), occasion_opts);
    }
    (event, post)
}

/// Options for `create_occasion`'s underlying `Post` (context `OCCASION`) plus its
/// `starts_at`/`ends_at`. Defaults to a one-hour occasion starting a day from now.
pub struct OccasionOpts {
    pub visibility: Visibility,
    pub moderation: Moderation,
    pub starts_at: SystemTime,
    pub ends_at: SystemTime,
    pub title: Option<String>,
    /// `Location` JSON (e.g. `serde_json::to_value(Location { .. }).unwrap()`) -- defaults to
    /// `None` (no location set), same as `create_occasion` always inserted before this
    /// field existed.
    pub location: Option<serde_json::Value>,
    /// An explicit IANA timezone (e.g. "America/New_York") -- defaults to `None`, same as
    /// `location`.
    pub timezone: Option<String>,
}

impl Default for OccasionOpts {
    fn default() -> Self {
        let starts_at = SystemTime::now() + std::time::Duration::from_secs(86400);
        OccasionOpts {
            visibility: Visibility::ServerPublic,
            moderation: Moderation::Unmoderated,
            starts_at,
            ends_at: starts_at + std::time::Duration::from_secs(3600),
            title: Some("Test Post".to_string()),
            location: None,
            timezone: None,
        }
    }
}

/// Inserts an `occasions` row directly, along with its own `Post` (context
/// `OCCASION`) - `get_events`' `query_visible_events!` requires *both* the parent event's
/// post and the occasion's own post to independently pass visibility/moderation, so tests need
/// separate control over each. `author: None` mirrors `create_post`'s own `author: None` (e.g. an
/// occasion post left behind by a deleted user).
pub fn create_occasion(
    conn: &mut PgPooledConnection,
    event: &models::Event,
    author: Option<&models::User>,
    opts: OccasionOpts,
) -> (models::Occasion, models::Post) {
    let post = create_post(
        conn,
        author,
        PostOpts {
            visibility: opts.visibility,
            moderation: opts.moderation,
            context: PostContext::Occasion,
            title: opts.title,
            ..Default::default()
        },
    );
    let occasion = insert_into(occasions::table)
        .values(&models::NewOccasion {
            event_id: event.post_id,
            post_id: post.id,
            info: serde_json::json!({}),
            starts_at: opts.starts_at,
            ends_at: opts.ends_at,
            location: opts.location,
            timezone: opts.timezone,
        })
        .returning(models::OCCASION_COLUMNS)
        .get_result::<models::Occasion>(conn)
        .expect("failed to create test event occasion");
    (occasion, post)
}

/// Options for `create_event_attendance`. Defaults to an unmoderated, logged-in-user-less
/// (i.e. this needs a `user_id` or `anonymous_attendee` set explicitly, same as
/// `upsert_event_attendance` requires exactly one of the two) `INTERESTED` RSVP.
pub struct EventAttendanceOpts {
    pub user_id: Option<i64>,
    pub anonymous_attendee: Option<serde_json::Value>,
    pub status: AttendanceStatus,
    pub moderation: Moderation,
    pub public_note: String,
    pub private_note: String,
}

impl Default for EventAttendanceOpts {
    fn default() -> Self {
        EventAttendanceOpts {
            user_id: None,
            anonymous_attendee: None,
            status: AttendanceStatus::Interested,
            moderation: Moderation::Unmoderated,
            public_note: "".to_string(),
            private_note: "".to_string(),
        }
    }
}

/// Inserts an `event_attendances` row directly (bypassing `rpcs::upsert_event_attendance`), for
/// specs that need precise control over `moderation`/`user_id`/`anonymous_attendee` to exercise
/// `get_event_attendances`/`get_events`' visibility rules.
pub fn create_event_attendance(
    conn: &mut PgPooledConnection,
    occasion: &models::Occasion,
    opts: EventAttendanceOpts,
) -> models::EventAttendance {
    insert_into(event_attendances::table)
        .values(&models::NewEventAttendance {
            occasion_id: occasion.post_id,
            user_id: opts.user_id,
            anonymous_attendee: opts.anonymous_attendee,
            number_of_guests: 0,
            status: opts.status.to_string_attendance_status(),
            inviting_user_id: None,
            public_note: opts.public_note,
            private_note: opts.private_note,
            moderation: opts.moderation.to_string_moderation(),
        })
        .get_result::<models::EventAttendance>(conn)
        .expect("failed to create test event attendance")
}

/// Starts a background thread serving `ics_text` as `text/calendar` for every HTTP request it
/// receives (looping for the life of the test process -- there's no teardown, same as any other
/// test-scoped leaked thread), and returns the `http://127.0.0.1:<port>/...` URL to fetch it
/// from. Keeps sync specs hermetic: real network calls in a test suite are flaky and slow, so
/// `sync_source` (which always does a real HTTP fetch, unlike
/// `sync_source_text`) is exercised against this instead of the public internet.
pub fn serve_ics(ics_text: &str) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0").expect("failed to bind test ICS server");
    let port = listener
        .local_addr()
        .expect("failed to read test ICS server port")
        .port();
    let body = ics_text.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 2048];
            let _ = stream.read(&mut buf);
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: text/calendar\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}/test.ics")
}

/// Mirrors `serve_ics`, for an RSS/Atom feed body instead of an ICS calendar.
pub fn serve_feed(feed_text: &str) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0").expect("failed to bind test feed server");
    let port = listener
        .local_addr()
        .expect("failed to read test feed server port")
        .port();
    let body = feed_text.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 2048];
            let _ = stream.read(&mut buf);
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/rss+xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}/test.rss")
}

/// Inserts a `sync_destinations` row directly (bypassing `rpcs::create_sync_destination`, so no
/// Facebook OAuth exchange happens) -- for specs that only care about ownership/permission
/// handling. Specs exercising the actual Facebook Graph API calls should go through
/// `logic::facebook_sync`'s `_at` functions against `serve_facebook_graph_api` instead.
pub fn create_sync_destination_row(
    conn: &mut PgPooledConnection,
    user: &models::User,
    page_id: &str,
) -> models::SyncDestination {
    insert_into(sync_destinations::table)
        .values(&models::NewSyncDestination {
            user_id: user.id,
            configuration: serde_json::json!({
                "facebook_page": {
                    "page_id": page_id,
                    "page_name": "Test Page",
                    "access_token": "test-page-access-token",
                }
            }),
        })
        .get_result::<models::SyncDestination>(conn)
        .expect("failed to create test sync destination")
}

/// Inserts an `occasion_sync_destinations` row directly -- simulates a successful
/// `SyncOccasion` without going through the RPC (which always hits the real Facebook Graph
/// API -- see `sync_destination_rpc_tests`' own note on that).
pub fn create_occasion_sync_destination_row(
    conn: &mut PgPooledConnection,
    occasion: &models::Occasion,
    destination: &models::SyncDestination,
) {
    insert_into(occasion_sync_destinations::table)
        .values(&models::NewOccasionSyncDestination {
            occasion_id: occasion.post_id,
            sync_destination_id: destination.id,
            destination_instance_id: Some("test-post-id".to_string()),
            destination_url: Some("https://www.facebook.com/test-post-id".to_string()),
            synced_at: Some(SystemTime::now()),
        })
        .execute(conn)
        .expect("failed to create test event occasion sync destination");
}

/// Inserts a `post_sync_destinations` row directly -- mirrors
/// `create_occasion_sync_destination_row`, simulating a successful `SyncPost` without going
/// through the RPC (which always hits the real Facebook Graph API).
pub fn create_post_sync_destination_row(
    conn: &mut PgPooledConnection,
    post: &models::Post,
    destination: &models::SyncDestination,
) {
    insert_into(post_sync_destinations::table)
        .values(&models::NewPostSyncDestination {
            post_id: post.id,
            sync_destination_id: destination.id,
            destination_instance_id: Some("test-post-id".to_string()),
            destination_url: Some("https://www.facebook.com/test-post-id".to_string()),
            synced_at: Some(SystemTime::now()),
        })
        .execute(conn)
        .expect("failed to create test post sync destination");
}

/// Inserts an active `server_configurations` row with `federation_info.facebook_auth_config` set
/// to `app_id`/`app_secret` -- lets specs exercise `logic::server_facebook_app_credentials` (and
/// RPCs that call it, like `create_sync_destination`) without going through
/// `ConfigureServer`'s own merge logic.
pub fn configure_facebook_app(conn: &mut PgPooledConnection, app_id: &str, app_secret: &str) {
    let mut new_config = models::default_server_configuration();
    new_config.federation_info = serde_json::to_value(FederationInfo {
        servers: vec![],
        facebook_auth_config: Some(FacebookAuthConfig {
            app_id: app_id.to_string(),
            app_secret: app_secret.to_string(),
        }),
        x_twitter_auth_config: None,
        mastodon_servers: vec![],
    })
    .unwrap();
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Same as `configure_facebook_app`, but also sets `external_cdn_config.frontend_host` -- needed
/// for specs that exercise `logic::threads_sync::threads_redirect_uri` (and RPCs that call it,
/// like `create_sync_destination`'s `ThreadsAccount` arm), which derives the OAuth popup's
/// `redirect_uri` from it and fails fast with `threads_redirect_uri_not_configured` otherwise.
pub fn configure_facebook_app_and_frontend_host(
    conn: &mut PgPooledConnection,
    app_id: &str,
    app_secret: &str,
    frontend_host: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.federation_info = serde_json::to_value(FederationInfo {
        servers: vec![],
        facebook_auth_config: Some(FacebookAuthConfig {
            app_id: app_id.to_string(),
            app_secret: app_secret.to_string(),
        }),
        x_twitter_auth_config: None,
        mastodon_servers: vec![],
    })
    .unwrap();
    new_config.external_cdn_config = Some(
        serde_json::to_value(ExternalCdnConfig {
            frontend_host: frontend_host.to_string(),
            ..Default::default()
        })
        .unwrap(),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Mirrors `configure_facebook_app`, but sets `x_twitter_auth_config` instead -- needed for specs
/// that exercise `logic::x_twitter_sync::server_x_twitter_app_credentials` (and RPCs that call it,
/// like `create_sync_destination`'s `XTwitterAccount` arm).
pub fn configure_x_twitter_app(conn: &mut PgPooledConnection, client_id: &str, client_secret: &str) {
    let mut new_config = models::default_server_configuration();
    new_config.federation_info = serde_json::to_value(FederationInfo {
        servers: vec![],
        facebook_auth_config: None,
        x_twitter_auth_config: Some(XTwitterAuthConfig {
            client_id: client_id.to_string(),
            client_secret: client_secret.to_string(),
        }),
        mastodon_servers: vec![],
    })
    .unwrap();
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Same as `configure_x_twitter_app`, but also sets `external_cdn_config.frontend_host` -- needed
/// for specs that exercise `logic::x_twitter_sync::x_twitter_redirect_uri` (and RPCs that call it,
/// like `create_sync_destination`'s `XTwitterAccount` arm), which derives the OAuth popup's
/// `redirect_uri` from it and fails fast with `x_twitter_redirect_uri_not_configured` otherwise.
pub fn configure_x_twitter_app_and_frontend_host(
    conn: &mut PgPooledConnection,
    client_id: &str,
    client_secret: &str,
    frontend_host: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.federation_info = serde_json::to_value(FederationInfo {
        servers: vec![],
        facebook_auth_config: None,
        x_twitter_auth_config: Some(XTwitterAuthConfig {
            client_id: client_id.to_string(),
            client_secret: client_secret.to_string(),
        }),
        mastodon_servers: vec![],
    })
    .unwrap();
    new_config.external_cdn_config = Some(
        serde_json::to_value(ExternalCdnConfig {
            frontend_host: frontend_host.to_string(),
            ..Default::default()
        })
        .unwrap(),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Inserts an active `server_configurations` row with `twilio_config` set -- lets specs exercise
/// `logic::contact_verification::{server_twilio_config, twilio_available}` (and RPCs/logic that
/// call them, like `update_user`'s `supported_by_server` computation and
/// `start_contact_method_verification`) without going through `ConfigureServer`'s own merge logic.
/// Mirrors `configure_x_twitter_app`.
pub fn configure_twilio(
    conn: &mut PgPooledConnection,
    enabled: bool,
    account_sid: &str,
    api_key_sid: &str,
    api_key_secret: &str,
    from_number: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.twilio_config = Some(
        serde_json::to_value(TwilioConfig {
            twilio_enabled: enabled,
            twilio_account_sid: account_sid.to_string(),
            twilio_api_key_sid: api_key_sid.to_string(),
            twilio_api_key_secret: api_key_secret.to_string(),
            twilio_from_number: from_number.to_string(),
        })
        .unwrap(),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Inserts an active `server_configurations` row with `stripe_config` set -- mirrors
/// `configure_twilio`, for specs exercising the Rellm Marketplace's Stripe integration
/// (`rpcs::market::make_market_purchase`, `logic::market_renewal`, `web::stripe_webhook`,
/// `configure_server`/`get_server_configuration`'s own `stripe_config` handling) without going
/// through `ConfigureServer`'s own merge logic.
pub fn configure_stripe(
    conn: &mut PgPooledConnection,
    enabled: bool,
    secret_key: &str,
    publishable_key: &str,
    webhook_signing_secret: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.stripe_config = Some(
        serde_json::to_value(StripeConfig {
            stripe_enabled: enabled,
            stripe_secret_key: secret_key.to_string(),
            stripe_publishable_key: publishable_key.to_string(),
            stripe_webhook_signing_secret: webhook_signing_secret.to_string(),
        })
        .unwrap(),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Sets `market_settings.enabled` -- for specs on `rpcs::market::make_market_purchase`'s
/// `market_disabled` precondition (and anything else gated on Market being administratively open).
/// Unlike `configure_stripe`/`configure_twilio` (which `insert_into` a brand-new row, assuming
/// nothing's touched `server_configurations` in this test transaction yet), this updates whichever
/// row already exists -- creating the default one first if needed, via
/// `rpcs::get_server_configuration_model` -- so it composes with `configure_stripe` regardless of
/// which is called first in a given test.
pub fn configure_market(conn: &mut PgPooledConnection, enabled: bool) {
    let existing = crate::rpcs::get_server_configuration_model(conn)
        .expect("failed to load or create test server configuration");
    diesel::update(server_configurations::table.filter(server_configurations::id.eq(existing.id)))
        .set(
            server_configurations::market_settings.eq(serde_json::to_value(MarketSettings {
                enabled,
                stripe_configured: false,
            })
            .unwrap()),
        )
        .execute(conn)
        .expect("failed to configure test market_settings");
}

/// Same as `configure_twilio`, but also sets `server_info.name`/`external_cdn_config.frontend_host`
/// (pass `frontend_host: ""` to leave the CDN config unset) -- for specs on
/// `contact_verification::verification_sms_body`'s "which server is this from" text, which needs
/// both live in the same row.
pub fn configure_twilio_with_server_info(
    conn: &mut PgPooledConnection,
    account_sid: &str,
    api_key_sid: &str,
    api_key_secret: &str,
    from_number: &str,
    server_name: &str,
    frontend_host: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.twilio_config = Some(
        serde_json::to_value(TwilioConfig {
            twilio_enabled: true,
            twilio_account_sid: account_sid.to_string(),
            twilio_api_key_sid: api_key_sid.to_string(),
            twilio_api_key_secret: api_key_secret.to_string(),
            twilio_from_number: from_number.to_string(),
        })
        .unwrap(),
    );
    new_config.server_info = serde_json::to_value(ServerInfo {
        name: Some(server_name.to_string()),
        ..Default::default()
    })
    .unwrap();
    new_config.external_cdn_config = if frontend_host.is_empty() {
        None
    } else {
        Some(
            serde_json::to_value(ExternalCdnConfig {
                frontend_host: frontend_host.to_string(),
                ..Default::default()
            })
            .unwrap(),
        )
    };
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Mirrors `configure_twilio`, but sets `bird_config` instead -- for specs exercising Bird as a
/// verification provider (or the two providers' fallback ordering together).
pub fn configure_bird(
    conn: &mut PgPooledConnection,
    enabled: bool,
    access_key: &str,
    from: &str,
    region: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.bird_config = Some(
        serde_json::to_value(BirdConfig {
            bird_enabled: enabled,
            bird_access_key: access_key.to_string(),
            bird_from: from.to_string(),
            bird_region: region.to_string(),
        })
        .unwrap(),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Mirrors `configure_twilio`/`configure_bird`, but sets `telnyx_config` instead -- for specs
/// exercising Telnyx as a verification provider (or the three providers' fallback ordering
/// together).
pub fn configure_telnyx(
    conn: &mut PgPooledConnection,
    enabled: bool,
    api_key: &str,
    from_number: &str,
    messaging_profile_id: &str,
) {
    let mut new_config = models::default_server_configuration();
    new_config.telnyx_config = Some(
        serde_json::to_value(TelnyxConfig {
            telnyx_enabled: enabled,
            telnyx_api_key: api_key.to_string(),
            telnyx_from_number: from_number.to_string(),
            telnyx_messaging_profile_id: messaging_profile_id.to_string(),
        })
        .unwrap(),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// Like `configure_twilio`/`configure_bird`/`configure_telnyx`, but sets any combination of the
/// three providers at once plus `preferred_verification_apis` -- for specs exercising
/// `contact_verification`'s preference-ordering/fallback logic between them.
pub fn configure_verification_providers(
    conn: &mut PgPooledConnection,
    twilio: Option<(&str, &str, &str, &str)>,
    bird: Option<(&str, &str, &str)>,
    telnyx: Option<(&str, &str, &str)>,
    preferred: Vec<VerificationApi>,
) {
    let mut new_config = models::default_server_configuration();
    new_config.twilio_config = twilio.map(|(account_sid, api_key_sid, api_key_secret, from)| {
        serde_json::to_value(TwilioConfig {
            twilio_enabled: true,
            twilio_account_sid: account_sid.to_string(),
            twilio_api_key_sid: api_key_sid.to_string(),
            twilio_api_key_secret: api_key_secret.to_string(),
            twilio_from_number: from.to_string(),
        })
        .unwrap()
    });
    new_config.bird_config = bird.map(|(key, from, region)| {
        serde_json::to_value(BirdConfig {
            bird_enabled: true,
            bird_access_key: key.to_string(),
            bird_from: from.to_string(),
            bird_region: region.to_string(),
        })
        .unwrap()
    });
    new_config.telnyx_config = telnyx.map(|(api_key, from, messaging_profile_id)| {
        serde_json::to_value(TelnyxConfig {
            telnyx_enabled: true,
            telnyx_api_key: api_key.to_string(),
            telnyx_from_number: from.to_string(),
            telnyx_messaging_profile_id: messaging_profile_id.to_string(),
        })
        .unwrap()
    });
    new_config.preferred_verification_apis = Some(
        crate::logic::verification_apis_to_json(&preferred),
    );
    insert_into(server_configurations::table)
        .values(&new_config)
        .execute(conn)
        .expect("failed to create test server configuration");
}

/// A minimal mock of the X (Twitter) API v2 OAuth token endpoint (`/2/oauth2/token`, both the
/// initial `authorization_code` exchange and subsequent `refresh_token` exchanges -- distinguished
/// by inspecting the request *body*, not just the request line, since both share one path/method),
/// `/2/users/me`, `/2/media/upload`, and `/2/tweets`, for `logic::x_twitter_sync` specs. Mirrors
/// `serve_threads_api`'s shape. `valid_code: false` simulates a rejected authorization code (`400`
/// on the initial exchange only -- a refresh always succeeds here, since specs cover refresh
/// failure separately via `serve_capturing` where finer control is needed).
pub fn serve_x_twitter_api(valid_code: bool, x_user_id: &str, username: &str, tweet_id: &str) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0").expect("failed to bind test X API server");
    let port = listener
        .local_addr()
        .expect("failed to read test X API server port")
        .port();
    let x_user_id = x_user_id.to_string();
    let username = username.to_string();
    let tweet_id = tweet_id.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 16384];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]).to_string();
            let request_line = request.lines().next().unwrap_or("").to_string();

            let (status_line, body) = if request_line.contains("/2/oauth2/token") {
                if request.contains("grant_type=refresh_token") {
                    (
                        "HTTP/1.1 200 OK",
                        serde_json::json!({
                            "access_token": "refreshed-x-access-token",
                            "refresh_token": "refreshed-x-refresh-token",
                            "expires_in": 7200,
                            "token_type": "bearer",
                        }),
                    )
                } else if valid_code {
                    (
                        "HTTP/1.1 200 OK",
                        serde_json::json!({
                            "access_token": "x-access-token",
                            "refresh_token": "x-refresh-token",
                            "expires_in": 7200,
                            "token_type": "bearer",
                        }),
                    )
                } else {
                    (
                        "HTTP/1.1 400 Bad Request",
                        serde_json::json!({ "error": "invalid_request" }),
                    )
                }
            } else if request_line.contains("/2/users/me") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "data": { "id": x_user_id, "username": username } }),
                )
            } else if request_line.contains("/2/media/upload") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "data": { "id": "x-media-1" } }),
                )
            } else if request_line.contains("/2/tweets") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "data": { "id": tweet_id, "text": "unused" } }),
                )
            } else {
                (
                    "HTTP/1.1 404 Not Found",
                    serde_json::json!({ "error": "not_found" }),
                )
            };
            let body = body.to_string();
            let response = format!(
                "{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status_line,
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// Inserts a `media` row directly (bypassing the `/media` upload endpoint, which lives outside
/// the gRPC/`rpcs` layer entirely). Doesn't touch MinIO -- pair with `TestBucket::put_object` (via
/// `test_bucket()`) when a spec needs a real object at `minio_path` to verify gets cleaned up.
/// Starts with a single `MEDIA_CONVERSION_ORIGINAL` size of `size_bytes: 10` (matching the
/// `b"test-bytes"` payload specs conventionally seed at `minio_path`) -- use
/// `create_media_with_size` when a spec needs a specific byte count (e.g. quota specs), or
/// `set_media_sizes` to fully control the `sizes` list (e.g. adding converted copies).
pub fn create_media(
    conn: &mut PgPooledConnection,
    author: Option<&models::User>,
    minio_path: &str,
) -> models::Media {
    create_media_with_size(conn, author, minio_path, 10)
}

/// Like `create_media`, but with an explicit `size_bytes` on the original -- for specs exercising
/// storage-quota accounting.
pub fn create_media_with_size(
    conn: &mut PgPooledConnection,
    author: Option<&models::User>,
    minio_path: &str,
    size_bytes: i64,
) -> models::Media {
    let sizes = vec![models::MediaSize {
        conversion: MediaConversion::Original as i32,
        minio_path: minio_path.to_string(),
        content_type: "image/png".to_string(),
        size_bytes,
        aspect_ratio: None,
    }];
    insert_into(media::table)
        .values(&models::NewMedia {
            user_id: author.map(|u| u.id),
            name: None,
            description: None,
            generated: false,
            visibility: Visibility::ServerPublic.to_string_visibility(),
            metadata: serde_json::json!({}),
            sizes: serde_json::to_value(sizes).unwrap(),
        })
        .get_result::<models::Media>(conn)
        .expect("failed to create test media")
}

/// Sets `media.sizes` directly -- `create_media` always starts with a single original size, and
/// specs covering `delete_media`/`delete_media_sizes`'s MinIO cleanup need converted copies
/// present to prove they get deleted too.
pub fn set_media_sizes(
    conn: &mut PgPooledConnection,
    test_media: &models::Media,
    sizes: Vec<models::MediaSize>,
) -> models::Media {
    diesel::update(media::table.filter(media::id.eq(test_media.id)))
        .set(media::sizes.eq(serde_json::to_value(sizes).unwrap()))
        .get_result::<models::Media>(conn)
        .expect("failed to set test media sizes")
}

/// A live connection to the MinIO bucket configured by the `MINIO_*` env vars (see `.env`), plus
/// the single Tokio runtime used to drive it. Specs proving `delete_media`/`delete_user` actually
/// clean up MinIO objects need a real bucket -- `rust-s3`'s async client isn't mockable -- and
/// need to run those RPCs' `.await` points from *somewhere*, but the rest of the test harness
/// (`test_conn`/`test_transaction`) is entirely synchronous. Every await for a given spec should
/// go through this same runtime, and every spec should share the same `Bucket` -- besides the
/// (real, tokio-bound) cross-runtime concerns, `get_and_test_bucket` sanity-checks the connection
/// with a put/get/head/delete round trip against a *fixed* `"test.file"` key, so calling it fresh
/// per-spec races those round trips against each other under `cargo test`'s parallel threads.
/// `test_bucket` therefore hands out a single process-wide connection (`lazy_static`, same trick
/// `test_conn`'s `POOL` uses) instead of dialing MinIO anew for every spec.
fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    lazy_static! {
        static ref RUNTIME: tokio::runtime::Runtime =
            tokio::runtime::Runtime::new().expect("failed to create test tokio runtime");
    }
    RUNTIME.block_on(fut)
}

pub struct TestBucket {
    pub bucket: &'static Bucket,
}

impl TestBucket {
    pub fn block_on<F: std::future::Future>(&self, fut: F) -> F::Output {
        block_on(fut)
    }

    /// Whether an object exists at `minio_path` -- used to assert deletion actually happened.
    pub fn object_exists(&self, minio_path: &str) -> bool {
        self.block_on(self.bucket.get_object(minio_path)).is_ok()
    }
}

pub fn test_bucket() -> TestBucket {
    lazy_static! {
        static ref BUCKET: Box<Bucket> = {
            // `test_conn`/`establish_test_pool` load `.env` (via `dotenv()`) before reading
            // `TEST_DATABASE_URL`; `minio_connection::get_and_test_bucket` doesn't load `.env`
            // itself, and callers may reach for a bucket before ever calling `test_conn`, so do
            // it here too.
            dotenvy::dotenv().ok();
            block_on(crate::minio_connection::get_and_test_bucket()).expect(
                "failed to connect to test MinIO bucket -- is MinIO running? (`docker compose up minio`, or the full dev stack)",
            )
        };
    }
    TestBucket { bucket: &BUCKET }
}

/// Starts a background thread serving canned Facebook Graph API JSON responses (mirrors
/// `serve_ics`, but routes by request path since `logic::facebook_sync` hits different endpoints
/// depending on which step it's on): `/oauth/access_token` returns a long-lived user token,
/// `/me/accounts` returns `page` as the (fake) user's one managed Page (or none, if `page` is
/// `None` -- for testing the "page not managed by this user" error path), and anything else (the
/// `/{page_id}/feed` post) returns `post_id`. Returns the `http://127.0.0.1:<port>` base URL to
/// pass as `logic::facebook_sync`'s `base_url` param.
pub fn serve_facebook_graph_api(page: Option<(&str, &str, &str)>, post_id: &str) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener =
        TcpListener::bind("127.0.0.1:0").expect("failed to bind test Facebook Graph API server");
    let port = listener
        .local_addr()
        .expect("failed to read test Facebook Graph API server port")
        .port();
    let page = page.map(|(id, name, token)| (id.to_string(), name.to_string(), token.to_string()));
    let post_id = post_id.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]);
            let request_line = request.lines().next().unwrap_or("").to_string();

            let body = if request_line.contains("/oauth/access_token") {
                serde_json::json!({
                    "access_token": "long-lived-user-token",
                    "token_type": "bearer",
                    "expires_in": 5_184_000,
                })
            } else if request_line.contains("/me/accounts") {
                let data = match &page {
                    Some((id, name, token)) => {
                        serde_json::json!([{ "id": id, "name": name, "access_token": token }])
                    }
                    None => serde_json::json!([]),
                };
                serde_json::json!({ "data": data })
            } else {
                serde_json::json!({ "id": post_id })
            };
            let body = body.to_string();
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// A minimal mock of the Facebook Graph API endpoints `logic::facebook_sync`'s Instagram functions
/// hit -- routes by request line, mirroring `serve_facebook_graph_api`: a
/// `fields=instagram_business_account{id,username}` lookup returns `instagram_account` (or just
/// `{"id": ...}` with no linked account, if `None`) for `get_linked_instagram_business_account_at`;
/// `/media_publish` and `fields=permalink` requests both return `media_id` (the /publish response
/// as `id`, the permalink lookup as `https://www.instagram.com/p/{media_id}-permalink/`); anything
/// else (the `/media` creation-container POST) returns a synthetic creation ID -- for
/// `post_to_instagram_at`.
pub fn serve_facebook_graph_api_instagram(
    instagram_account: Option<(&str, &str)>,
    media_id: &str,
) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0")
        .expect("failed to bind test Instagram Graph API server");
    let port = listener
        .local_addr()
        .expect("failed to read test Instagram Graph API server port")
        .port();
    let instagram_account =
        instagram_account.map(|(id, username)| (id.to_string(), username.to_string()));
    let media_id = media_id.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]);
            let request_line = request.lines().next().unwrap_or("").to_string();

            let body = if request_line.contains("instagram_business_account") {
                match &instagram_account {
                    Some((id, username)) => serde_json::json!({
                        "instagram_business_account": { "id": id, "username": username },
                        "id": "123"
                    }),
                    None => serde_json::json!({ "id": "123" }),
                }
            } else if request_line.contains("/media_publish") {
                serde_json::json!({ "id": media_id })
            } else if request_line.contains("fields=permalink") {
                serde_json::json!({
                    "permalink": format!("https://www.instagram.com/p/{media_id}-permalink/")
                })
            } else {
                serde_json::json!({ "id": format!("{media_id}-creation") })
            };
            let body = body.to_string();
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// A minimal mock of the Mastodon REST API's `verify_credentials`/`statuses` endpoints for
/// `logic::mastodon_sync` specs -- routes by request line and always responds `200` unless
/// `valid_token` is `false` (simulating a rejected/invalid Personal Access Token, `401`) or
/// `post_succeeds` is `false` (simulating a too-long status, `422`).
pub fn serve_mastodon_api(
    username: &str,
    valid_token: bool,
    post_succeeds: bool,
    status_id: &str,
    status_url: &str,
) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener =
        TcpListener::bind("127.0.0.1:0").expect("failed to bind test Mastodon API server");
    let port = listener
        .local_addr()
        .expect("failed to read test Mastodon API server port")
        .port();
    let username = username.to_string();
    let status_id = status_id.to_string();
    let status_url = status_url.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]);
            let request_line = request.lines().next().unwrap_or("").to_string();

            let (status_line, body) = if request_line.contains("/api/v1/accounts/verify_credentials")
            {
                if valid_token {
                    (
                        "HTTP/1.1 200 OK",
                        serde_json::json!({ "username": username }),
                    )
                } else {
                    (
                        "HTTP/1.1 401 Unauthorized",
                        serde_json::json!({ "error": "The access token is invalid" }),
                    )
                }
            } else if post_succeeds {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "id": status_id, "url": status_url }),
                )
            } else {
                (
                    "HTTP/1.1 422 Unprocessable Entity",
                    serde_json::json!({ "error": "Text character limit exceeded" }),
                )
            };
            let body = body.to_string();
            let response = format!(
                "{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status_line,
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// A minimal mock of the Threads Graph API endpoints `logic::threads_sync` hits for
/// `oauth/access_token` (code exchange), `access_token` (long-lived exchange), `fields=username`
/// (username lookup), `/threads` (media container creation), `/threads_publish`, and
/// `fields=permalink` (permalink lookup) -- routes by request line, mirroring
/// `serve_facebook_graph_api`. `valid` gates the code-exchange step (simulating an invalid/expired
/// authorization code, `400`); everything past that always succeeds with the given canned values.
pub fn serve_threads_api(
    valid: bool,
    threads_user_id: &str,
    username: &str,
    post_id: &str,
    permalink: &str,
) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0").expect("failed to bind test Threads API server");
    let port = listener
        .local_addr()
        .expect("failed to read test Threads API server port")
        .port();
    let threads_user_id = threads_user_id.to_string();
    let username = username.to_string();
    let post_id = post_id.to_string();
    let permalink = permalink.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]);
            let request_line = request.lines().next().unwrap_or("").to_string();

            let (status_line, body) = if request_line.contains("/oauth/access_token") {
                if valid {
                    (
                        "HTTP/1.1 200 OK",
                        serde_json::json!({
                            "access_token": "short-lived-threads-token",
                            "user_id": threads_user_id,
                        }),
                    )
                } else {
                    (
                        "HTTP/1.1 400 Bad Request",
                        serde_json::json!({ "error": "invalid authorization code" }),
                    )
                }
            } else if request_line.contains("grant_type=th_exchange_token") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "access_token": "long-lived-threads-token" }),
                )
            } else if request_line.contains("fields=username") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "username": username }),
                )
            } else if request_line.contains("fields=permalink") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "permalink": permalink }),
                )
            } else if request_line.contains("/threads_publish") {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "id": post_id }),
                )
            } else {
                // `/{threads_user_id}/threads` media container creation.
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "id": format!("{post_id}-creation") }),
                )
            };
            let body = body.to_string();
            let response = format!(
                "{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status_line,
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// Starts a background thread that captures the raw text (request line + headers + body -- since
/// the mock only does one `read()` call, this can miss the tail of a request larger than the
/// buffer, which is fine for the small form/JSON bodies these specs send) of every request it
/// receives into the returned `Arc<Mutex<Vec<String>>>`, in receipt order, replying to each with
/// whatever `respond` returns given the *other* requests already captured before it (so a response
/// can vary by call index, e.g. a photo-upload endpoint hit multiple times). Generalizes the
/// per-platform mock servers above (`serve_facebook_graph_api`/`serve_mastodon_api`/
/// `serve_bluesky_api`/`serve_threads_api`) for specs that need to assert on request *shape* --
/// which endpoint got hit, in what order, with what body -- rather than just canned response
/// wiring; see `facebook_sync_tests`/`mastodon_sync_tests`/`bluesky_sync_tests`' media-attachment
/// specs for example usage.
pub fn serve_capturing(
    respond: impl Fn(&str, &[String]) -> (&'static str, serde_json::Value) + Send + 'static,
) -> (String, std::sync::Arc<std::sync::Mutex<Vec<String>>>) {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};

    let listener = TcpListener::bind("127.0.0.1:0").expect("failed to bind test capturing server");
    let port = listener
        .local_addr()
        .expect("failed to read test capturing server port")
        .port();
    let captured: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
    let captured_thread = captured.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 16384];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]).to_string();

            let (status_line, body) = {
                let mut captured = captured_thread.lock().unwrap();
                let result = respond(&request, &captured);
                captured.push(request.clone());
                result
            };
            let body = body.to_string();
            let response = format!(
                "{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status_line,
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    (format!("http://127.0.0.1:{port}"), captured)
}

/// A minimal mock of the Bluesky (AT Protocol) `createSession`/`createRecord` XRPC endpoints for
/// `logic::bluesky_sync` specs -- routes by request line, mirroring `serve_mastodon_api`:
/// `valid_credentials: false` simulates a rejected handle/app-password (`401`), `post_succeeds:
/// false` simulates a `createRecord` failure (`400`).
pub fn serve_bluesky_api(
    did: &str,
    access_jwt: &str,
    valid_credentials: bool,
    post_succeeds: bool,
    record_uri: &str,
) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener =
        TcpListener::bind("127.0.0.1:0").expect("failed to bind test Bluesky API server");
    let port = listener
        .local_addr()
        .expect("failed to read test Bluesky API server port")
        .port();
    let did = did.to_string();
    let access_jwt = access_jwt.to_string();
    let record_uri = record_uri.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let read = stream.read(&mut buf).unwrap_or(0);
            let request = String::from_utf8_lossy(&buf[..read]);
            let request_line = request.lines().next().unwrap_or("").to_string();

            let (status_line, body) = if request_line.contains("createSession") {
                if valid_credentials {
                    (
                        "HTTP/1.1 200 OK",
                        serde_json::json!({ "did": did, "accessJwt": access_jwt }),
                    )
                } else {
                    (
                        "HTTP/1.1 401 Unauthorized",
                        serde_json::json!({ "error": "AuthenticationRequired" }),
                    )
                }
            } else if post_succeeds {
                (
                    "HTTP/1.1 200 OK",
                    serde_json::json!({ "uri": record_uri }),
                )
            } else {
                (
                    "HTTP/1.1 400 Bad Request",
                    serde_json::json!({ "error": "InvalidRequest" }),
                )
            };
            let body = body.to_string();
            let response = format!(
                "{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status_line,
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// A minimal mock of Nominatim's `/search` endpoint for `logic::geocoding` specs. Always returns
/// `result` (if `Some`) as the single element of the JSON array Nominatim's real API returns, or
/// `[]` (simulating "no results found") if `None`. Returns the `http://127.0.0.1:<port>` base URL
/// to pass as `logic::resolve_timezone_at`'s `base_url` param.
pub fn serve_nominatim_api(result: Option<(&str, &str)>) -> String {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0").expect("failed to bind test Nominatim server");
    let port = listener
        .local_addr()
        .expect("failed to read test Nominatim server port")
        .port();
    let result = result.map(|(lat, lon)| (lat.to_string(), lon.to_string()));
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let _ = stream.read(&mut buf).unwrap_or(0);

            let body = match &result {
                Some((lat, lon)) => serde_json::json!([{ "lat": lat, "lon": lon }]),
                None => serde_json::json!([]),
            };
            let body = body.to_string();
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}
