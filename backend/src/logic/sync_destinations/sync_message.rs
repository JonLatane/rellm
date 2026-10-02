//! Builds the platform-agnostic `SyncMessage` pushed to every `SyncDestination` type
//! (`facebook_sync::post_post`/`post_occasion`/`post_to_instagram`, `mastodon_sync::post_status`,
//! `bluesky_sync::post_record`). `rpcs::posts::sync_post`/`rpcs::events::sync_occasion` each
//! build one of these *once*, from the raw Post/Occasion fields, *before* dispatching on
//! `destination.configuration`'s variant -- so per-platform posting code only ever deals with
//! already-formatted content, not bespoke per-content-type structs (the old `OccasionPost`/
//! `PostFacebookContent`, now folded into the two builders below).

use chrono::DateTime;
use chrono::Utc;

/// Platform-agnostic content to push to a `SyncDestination`.
#[derive(Debug, Clone)]
pub struct SyncMessage {
    /// Already-formatted body text -- see `build_occasion_message`/`build_post_message` for
    /// how title/content/date-time-range/location get folded into this once, up front, instead of
    /// being reformatted per platform.
    pub text: String,
    /// Link back to this content (preferring this Rellm server's own frontend URL for it, falling
    /// back to the author's own external `link` -- see the builders below). Also already folded
    /// into `text` (as a bare link for an Occasion, "View post:" for a Post), since most
    /// platforms (Mastodon, Bluesky)
    /// have no separate link-preview mechanism and just expect it inline; kept here too since
    /// Facebook's Graph API *does* have a separate `link` param it uses for its preview card.
    pub link: Option<String>,
    /// The content's attached media (public download URL + content type), in the same order as
    /// the underlying Post/Occasion's `media` field. Empty for text-only content. Carrying
    /// `content_type` alongside each URL (rather than a bare `Vec<String>`) lets each platform's
    /// posting code pick the right upload mechanism/param (e.g. Instagram/Threads' `image_url` vs
    /// `video_url`, Facebook's `/photos` vs `/videos` endpoints) without re-fetching metadata.
    pub media: Vec<MediaAttachment>,
}

/// One piece of media attached to a `SyncMessage` -- see `SyncMessage.media`.
#[derive(Debug, Clone, PartialEq)]
pub struct MediaAttachment {
    /// This Rellm server's own public download URL for the media (`https://{backend_host}/media/{id}`).
    pub url: String,
    /// The media's MIME type (e.g. `"image/jpeg"`, `"video/mp4"`), from `models::MediaReference` --
    /// lets callers distinguish images from video without a network round-trip.
    pub content_type: String,
}

impl MediaAttachment {
    pub fn is_image(&self) -> bool {
        self.content_type.starts_with("image/")
    }

    pub fn is_video(&self) -> bool {
        self.content_type.starts_with("video/")
    }
}

/// Raw fields `build_occasion_message` folds into a `SyncMessage.text` -- mirrors the old
/// `facebook_sync::OccasionPost`.
pub struct OccasionMessageInput<'a> {
    pub title: &'a Option<String>,
    pub content: &'a Option<String>,
    /// Arbitrary external link the organizer set on the underlying `Post` (e.g. a ticketing site).
    /// Used only if `event_url` isn't set.
    pub link: &'a Option<String>,
    pub starts_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
    /// `Occasion.location`'s `uniformly_formatted_address`, if any.
    pub location: &'a Option<String>,
    /// The IANA timezone `location` resolves to, if `logic::resolve_timezone` could geocode it.
    /// `starts_at`/`ends_at` are shown in this zone if set, otherwise in UTC.
    pub timezone: Option<chrono_tz::Tz>,
    /// Link to this event on this Rellm server's own frontend, if buildable (see
    /// `sync_occasion`'s caller).
    pub event_url: &'a Option<String>,
    /// The underlying Post's attached media.
    pub media: Vec<MediaAttachment>,
}

/// Builds an Occasion's `SyncMessage` -- title, date/time range (in `timezone` if resolved,
/// else UTC), location, description, and a link back to the event, in that order. Mirrors what
/// `facebook_sync::format_message` used to build directly for Facebook; now shared by every
/// platform.
pub fn build_occasion_message(input: OccasionMessageInput) -> SyncMessage {
    let mut lines = vec![];
    if let Some(title) = input.title.as_ref().filter(|t| !t.trim().is_empty()) {
        lines.push(title.clone());
    }
    let time_range = match input.timezone {
        Some(tz) => format_time_range(
            Utc::now().with_timezone(&tz),
            input.starts_at.with_timezone(&tz),
            input.ends_at.with_timezone(&tz),
        ),
        None => format_time_range(Utc::now(), input.starts_at, input.ends_at),
    };
    lines.push(time_range);
    if let Some(location) = input.location.as_ref().filter(|l| !l.trim().is_empty()) {
        lines.push(format!("📍 {location}"));
    }
    if let Some(content) = input.content.as_ref().filter(|c| !c.trim().is_empty()) {
        lines.push(content.clone());
    }
    let link = input
        .event_url
        .as_ref()
        .filter(|l| !l.trim().is_empty())
        .or_else(|| input.link.as_ref().filter(|l| !l.trim().is_empty()))
        .cloned();
    if let Some(link) = &link {
        lines.push(link.to_string());
    }
    SyncMessage {
        text: lines.join("\n\n"),
        link,
        media: input.media,
    }
}

/// Raw fields `build_post_message` folds into a `SyncMessage.text` -- mirrors the old
/// `facebook_sync::PostFacebookContent`. Simpler than `OccasionMessageInput`: a `Post` has no
/// start/end time, timezone, or location.
pub struct PostMessageInput<'a> {
    pub title: &'a Option<String>,
    pub content: &'a Option<String>,
    /// Arbitrary external link the author set on the `Post` (e.g. an article/ticketing link). Used
    /// only if `post_url` isn't set.
    pub link: &'a Option<String>,
    /// Link to this `Post` on this Rellm server's own frontend, if buildable (see `sync_post`'s
    /// caller).
    pub post_url: &'a Option<String>,
    /// The Post's attached media.
    pub media: Vec<MediaAttachment>,
}

/// Builds a Post's `SyncMessage` -- title, content, and a link back to it. Mirrors what
/// `facebook_sync::format_post_message` used to build directly for Facebook.
pub fn build_post_message(input: PostMessageInput) -> SyncMessage {
    let mut lines = vec![];
    if let Some(title) = input.title.as_ref().filter(|t| !t.trim().is_empty()) {
        lines.push(title.clone());
    }
    if let Some(content) = input.content.as_ref().filter(|c| !c.trim().is_empty()) {
        lines.push(content.clone());
    }
    let link = input
        .post_url
        .as_ref()
        .filter(|l| !l.trim().is_empty())
        .or_else(|| input.link.as_ref().filter(|l| !l.trim().is_empty()))
        .cloned();
    if let Some(link) = &link {
        lines.push(format!("View post: {link}"));
    }
    SyncMessage {
        text: lines.join("\n\n"),
        link,
        media: input.media,
    }
}

/// Generic over the timezone (`Utc` or a `chrono_tz::Tz` the caller already converted `starts_at`
/// and `ends_at` into) so this doesn't need to duplicate itself for each.
///
/// Mirrors the "friendliness" rules of the Elm UI's `Shared.Time.formatMoment`/`formatRange` (the
/// live, viewer-facing renderer for the same start/end pair): no weekday name, the year is dropped
/// when it matches the current year, and a same-day range with both sides in the same AM/PM period
/// merges onto one suffix (e.g. "August 1, 6-7PM" rather than "August 1, 6:00 PM - 7:00 PM").
/// Deliberately does **not** mirror `formatMoment`'s "Today"/"Yesterday"/"Tomorrow" relative-day
/// prefixes -- those are correct for a live UI that re-renders on every view, but a synced social
/// post is written once and read forever after, so a relative-day label baked into its text would
/// go stale (and wrong) the moment "today" isn't today anymore.
fn format_time_range<Tz: chrono::TimeZone>(
    now: DateTime<Tz>,
    starts_at: DateTime<Tz>,
    ends_at: DateTime<Tz>,
) -> String
where
    Tz::Offset: std::fmt::Display,
{
    let current_year = now.format("%Y").to_string();
    let date_label = |at: &DateTime<Tz>| {
        let month_day = at.format("%B %-d").to_string();
        if at.format("%Y").to_string() == current_year {
            month_day
        } else {
            format!("{month_day}, {}", at.format("%Y"))
        }
    };
    let time_label = |at: &DateTime<Tz>| {
        if at.format("%M").to_string() == "00" {
            at.format("%-I%p").to_string()
        } else {
            at.format("%-I:%M%p").to_string()
        }
    };
    let zone = starts_at.format("%Z").to_string();

    if ends_at <= starts_at {
        return format!("{}, {} {zone}", date_label(&starts_at), time_label(&starts_at));
    }
    if starts_at.date_naive() == ends_at.date_naive() {
        let same_period = starts_at.format("%p").to_string() == ends_at.format("%p").to_string();
        let start_time = if same_period {
            // Drop the AM/PM suffix on the start side when both sides share one -- "6-7PM", not
            // "6PM-7PM" -- mirroring `Shared.Time.timeRangeLabel`'s `bareTime12`/`timeWithPeriod`
            // split.
            if starts_at.format("%M").to_string() == "00" {
                starts_at.format("%-I").to_string()
            } else {
                starts_at.format("%-I:%M").to_string()
            }
        } else {
            time_label(&starts_at)
        };
        format!(
            "{}, {start_time}-{} {zone}",
            date_label(&starts_at),
            time_label(&ends_at)
        )
    } else {
        // Matches `formatRange`'s different-day shape exactly: "StartDate, StartTime -
        // EndDate, EndTime" (plain hyphen, not the same-day case's en dash-free merge). Elm
        // doesn't need a timezone abbreviation here (the browser already renders in the
        // viewer's own zone, so it's implicit) -- appended once at the end here since a
        // synced post has no such implicit context for its reader.
        format!(
            "{}, {} - {}, {} {zone}",
            date_label(&starts_at),
            time_label(&starts_at),
            date_label(&ends_at),
            time_label(&ends_at)
        )
    }
}

/// Truncates `text` to at most 300 characters (Bluesky's real limit is 300 *grapheme clusters*,
/// but plain char-count with a safety margin is a reasonable approximation without pulling in a
/// grapheme-segmentation crate) -- see `bluesky_sync::post_record`, the one platform that truncates
/// proactively rather than surfacing the API's own rejection.
pub fn truncate_for_bluesky(text: &str) -> String {
    truncate_to(text, 300)
}

/// Same as `truncate_for_bluesky`, but for X/Twitter's 280-character limit -- see
/// `x_twitter_sync::post_tweet`.
pub fn truncate_for_x_twitter(text: &str) -> String {
    truncate_to(text, 280)
}

fn truncate_to(text: &str, max_chars: usize) -> String {
    let char_count = text.chars().count();
    if char_count <= max_chars {
        return text.to_string();
    }
    let truncated: String = text.chars().take(max_chars - 4).collect();
    format!("{truncated}\u{2026}")
}
