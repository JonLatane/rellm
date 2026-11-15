//! Syncs Events/Occasions from a site running [The Events Calendar](https://theeventscalendar.com/)
//! (a StellarWP WordPress plugin), following the plugin's `paged=N` pagination.
//!
//! The plugin's iCal export (`?post_type=tribe_events&ical=1&eventDisplay=list`) returns at most
//! its "events per page" setting's worth of events (30 on many sites) -- a plain
//! `ics_subscription_url` source on a busy calendar therefore only ever sees the next couple of
//! weeks. The same URL with `&paged=2`, `&paged=3`, ... returns the following pages, and a page past
//! the end is an HTTP 200 with an *empty* body. Pages overlap heavily: `paged` steps through the
//! list by the site's "events per page" *display* setting (12 on thetriangleweekender.com) while
//! each iCal response is always 30 events long, so every page repeats most of the previous one and
//! events are de-duplicated (a feed's reach is ~12 events per page fetched, not 30). [`collect_pages`] fetches pages until one of those, merges them
//! into one [`Calendar`], and hands it to `event_sync::sync_source_calendar` -- everything after
//! the fetch (recurrence expansion, upserting, missing-grace-period pruning) is shared with plain
//! ICS sources.
//!
//! The list view only shows *upcoming* events, so an event drops out of the feed the moment it ends.
//! Unlike a plain ICS file, that doesn't mean it was removed: the sync is told the feed is
//! `upcoming_only` (see `FeedCoverage`) and never prunes occasions that have already ended, so past
//! events stay in the data set.
//!
//! A feed that's still returning new events at [`MAX_PAGES`] is treated as *truncated*: the merged
//! calendar's `coverage_horizon` (the latest start seen) is passed along so occasions beyond it
//! aren't mistaken for deleted ones. Any failed page fails the whole sync -- a partially fetched
//! feed is never reconciled as though it were complete.
//!
//! Creating/updating a source (an RPC, so a human is waiting) syncs only the first page inline
//! ([`sync_source_stellarwp_first_page`]); `logic::sync_source_after_edit` finishes the rest on a
//! background thread.

use std::collections::HashSet;
use std::time::Duration;

use chrono::{DateTime, Utc};
use icalendar::{Calendar, Component};
use reqwest::Url;
use tonic::{Code, Status};

use super::event_sync::{
    get_date_property, parse_calendar, sync_source_calendar, FeedCoverage,
};
use crate::db_connection::PgPooledConnection;
use crate::models;

/// The most pages one sync fetches. Because pages overlap (see the module doc), each adds only ~10-12
/// new events, so this bounds a sync at roughly 1,000 events; the real calendars seen so far run out
/// at 26-37 pages (thetriangleweekender.com: 453 events through May 2027; downtowndurham.com: 256
/// through Sept 2027).
pub const MAX_PAGES: u32 = 80;
/// Pages fetched concurrently. Small, so a sync stays polite to a (usually small, shared-hosting)
/// WordPress site while still finishing in a fraction of the time a purely sequential fetch takes
/// (pages can take several seconds each).
const PAGES_PER_BATCH: u32 = 4;
/// How many more pages, one at a time, to look at for an empty one after a page that added nothing new.
const STALL_PROBE_PAGES: u32 = 6;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

/// Syncs every page of `source`'s StellarWP iCal URL (up to [`MAX_PAGES`]).
pub fn sync_source_stellarwp(
    source: &models::SyncSource,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    sync_pages(source, MAX_PAGES, conn)
}

/// Syncs only the first page of `source`'s StellarWP iCal URL -- what a create/update RPC does
/// inline before handing the remaining pages to a background sync. Occasions past the first page's
/// coverage are left alone rather than treated as missing.
pub fn sync_source_stellarwp_first_page(
    source: &models::SyncSource,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    sync_pages(source, 1, conn)
}

fn sync_pages(
    source: &models::SyncSource,
    max_pages: u32,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let paged = fetch_stellarwp_pages(source, max_pages)?;
    sync_source_stellarwp_fetched(source, &paged, conn)
}

/// Fetches up to `max_pages` pages of `source`'s StellarWP iCal URL and merges them -- the network
/// half of a sync, which needs no database connection (so a caller that checks one out only for
/// the DB work doesn't hold it through a fetch that can take a minute).
pub fn fetch_stellarwp_pages(
    source: &models::SyncSource,
    max_pages: u32,
) -> Result<PagedCalendar, Status> {
    let endpoint = stellarwp_ics_subscription_url(source)?;
    crate::init_crypto();
    in_blocking_context(|| {
        let client = super::client_builder(source)
            .timeout(REQUEST_TIMEOUT)
            .build()
            .map_err(|e| {
                log::error!("Failed to build HTTP client for StellarWP sync: {:?}", crate::logic::log_redaction::safe_error(&e));
                Status::new(Code::Internal, "stellarwp_fetch_failed")
            })?;
        collect_pages(max_pages, |page| {
            fetch_page(&client, &stellarwp_page_url(endpoint, page)?)
        })
    })
}

/// The database half of a sync: upserts what [`fetch_stellarwp_pages`] fetched for `source`.
pub fn sync_source_stellarwp_fetched(
    source: &models::SyncSource,
    paged: &PagedCalendar,
    conn: &mut PgPooledConnection,
) -> Result<(), Status> {
    let coverage = FeedCoverage {
        truncated_after: paged.coverage_horizon,
        upcoming_only: true,
    };
    sync_source_calendar(source, &paged.calendar, coverage, conn)
}

/// Whether `source` is a StellarWP source (has a non-empty `stellarwp_ics_subscription_url`).
pub fn is_stellarwp_source(source: &models::SyncSource) -> bool {
    stellarwp_ics_subscription_url(source).is_ok()
}

fn stellarwp_ics_subscription_url(source: &models::SyncSource) -> Result<&str, Status> {
    source
        .configuration
        .get("stellarwp_ics_subscription_url")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| Status::new(Code::FailedPrecondition, "stellarwp_ics_url_required"))
}

/// `endpoint` with its `paged` query parameter set to `page` (replacing any `paged` it already
/// carried). Page 1 omits `paged` entirely: WordPress redirects `?paged=1` to the canonical URL.
/// Also what create/update use to validate a new endpoint.
pub fn stellarwp_page_url(endpoint: &str, page: u32) -> Result<Url, Status> {
    let mut url = Url::parse(endpoint.trim()).map_err(|_| invalid_endpoint())?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err(invalid_endpoint());
    }
    let kept: Vec<(String, String)> = url
        .query_pairs()
        .filter(|(key, _)| key != "paged")
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect();
    {
        let mut pairs = url.query_pairs_mut();
        pairs.clear().extend_pairs(&kept);
        if page > 1 {
            pairs.append_pair("paged", &page.to_string());
        }
    }
    Ok(url)
}

fn invalid_endpoint() -> Status {
    Status::new(Code::InvalidArgument, "stellarwp_ics_subscription_url_invalid")
}

/// Same reasoning as `event_sync::fetch_ics`: handlers are plain sync functions but still run
/// inside Rocket's Tokio runtime in production, and `reqwest::blocking` panics if it builds or
/// drops its nested runtime directly in an async context.
fn in_blocking_context<T>(f: impl FnOnce() -> T) -> T {
    if tokio::runtime::Handle::try_current().is_ok() {
        tokio::task::block_in_place(f)
    } else {
        f()
    }
}

/// One page's body, retried once on a transient failure.
fn fetch_page(client: &reqwest::blocking::Client, url: &Url) -> Result<String, Status> {
    let mut last_error = None;
    for _attempt in 0..2 {
        match client
            .get(url.clone())
            .send()
            .and_then(|response| response.error_for_status())
            .and_then(|response| response.text())
        {
            Ok(text) => return Ok(text),
            Err(e) => {
                log::warn!("Failed to fetch StellarWP page {}: {:?}", crate::logic::log_redaction::redact_url(&url), crate::logic::log_redaction::safe_error(&e));
                last_error = Some(e);
            }
        }
    }
    log::error!(
        "Giving up fetching StellarWP page {}: {:?}",
        crate::logic::log_redaction::redact_url(&url),
        crate::logic::log_redaction::safe_error(&last_error)
    );
    Err(Status::new(Code::FailedPrecondition, "stellarwp_fetch_failed"))
}

#[derive(Debug)]
pub struct PagedCalendar {
    /// Every distinct VEVENT across the fetched pages.
    pub calendar: Calendar,
    /// `Some(latest event start seen)` unless the fetch positively reached the end of the feed (an
    /// empty page): it stopped at `max_pages`, or at a page that repeated earlier ones. `None` if it
    /// reached the end.
    pub coverage_horizon: Option<DateTime<Utc>>,
}

/// The VEVENTs gathered across pages so far.
struct Merger {
    calendar: Calendar,
    seen_keys: HashSet<String>,
    latest_start: Option<DateTime<Utc>>,
}

impl Merger {
    /// Adds `page`'s VEVENTs that haven't been seen on an earlier page, returning how many there were.
    fn absorb(&mut self, page: &Calendar) -> usize {
        let mut new_events = 0;
        for component in page.iter() {
            let Some(event) = component.as_event() else {
                continue;
            };
            if !self.seen_keys.insert(event_key(event)) {
                continue;
            }
            new_events += 1;
            if let Some(start) = get_date_property(event, "DTSTART") {
                self.latest_start = Some(self.latest_start.map_or(start, |latest| latest.max(start)));
            }
            self.calendar.push(event.clone());
        }
        new_events
    }
}

/// What one fetched page turned out to be.
enum Page {
    /// Past the end of the feed: an empty body.
    End,
    Calendar(Calendar),
}

/// Fetches pages `1..=max_pages` with `fetch_page` (called with the 1-based page number, possibly
/// from several threads at once), merging their VEVENTs and stopping at the first page that's past
/// the end of the feed (an empty body, for pages after the first) or adds nothing new (the latter
/// guards against a site that ignores `paged` and serves the same page forever -- which leaves the
/// feed treated as truncated, since a repeated page doesn't prove nothing lies beyond it).
pub fn collect_pages<F>(max_pages: u32, fetch_page: F) -> Result<PagedCalendar, Status>
where
    F: Fn(u32) -> Result<String, Status> + Sync,
{
    let mut merger = Merger {
        calendar: Calendar::new(),
        seen_keys: HashSet::new(),
        latest_start: None,
    };
    // Only an actual "past the end" response (an empty body) proves the feed is complete.
    let mut reached_end = false;
    // A page that added nothing new: the feed has either run out or -- for a site that ignores
    // `paged` and serves the same page forever -- never paginated at all. Stops fetching more
    // batches, but is *not* by itself proof of completeness.
    let mut stalled = false;
    let mut last_page_fetched = 0;

    let mut batch_start = 1;
    'batches: while batch_start <= max_pages && !stalled {
        let batch: Vec<u32> = (batch_start..=max_pages.min(batch_start + PAGES_PER_BATCH - 1)).collect();
        batch_start += PAGES_PER_BATCH;
        last_page_fetched = *batch.last().unwrap_or(&last_page_fetched);

        // Fetched concurrently but examined strictly in order, so a failure in a page past the
        // end of the feed (a speculative overshoot of the batch) is never even looked at.
        let bodies: Vec<Result<String, Status>> = if batch.len() == 1 {
            vec![fetch_page(batch[0])]
        } else {
            std::thread::scope(|scope| {
                let handles: Vec<_> = batch
                    .iter()
                    .map(|&page| {
                        let fetch_page = &fetch_page;
                        scope.spawn(move || fetch_page(page))
                    })
                    .collect();
                handles
                    .into_iter()
                    .map(|handle| {
                        handle.join().unwrap_or_else(|_| {
                            Err(Status::new(Code::Internal, "stellarwp_fetch_failed"))
                        })
                    })
                    .collect()
            })
        };

        for (&page_number, body) in batch.iter().zip(bodies) {
            let calendar = match classify_page(page_number, &body?)? {
                Page::End => {
                    reached_end = true;
                    break 'batches;
                }
                Page::Calendar(calendar) => calendar,
            };

            let new_events = merger.absorb(&calendar);
            if new_events == 0 {
                // Keep examining the rest of this (already fetched) batch for an empty page.
                stalled = true;
            }
        }
    }

    // Stalled without having seen an empty page. The tail of a feed can repeat for a few pages
    // before the empty one (each page is longer than the step between pages), so keep going a few
    // more pages looking for it -- one at a time, and only in this unusual case. Anything but a
    // genuine empty body leaves the feed treated as truncated, which is also what a site that
    // ignores `paged` ends up as.
    if stalled && !reached_end {
        for page_number in last_page_fetched + 1..=last_page_fetched + STALL_PROBE_PAGES {
            let Ok(body) = fetch_page(page_number) else {
                break;
            };
            match classify_page(page_number, &body) {
                Ok(Page::End) => {
                    reached_end = true;
                    break;
                }
                Ok(Page::Calendar(calendar)) => {
                    merger.absorb(&calendar);
                }
                Err(_) => break,
            }
        }
    }

    Ok(PagedCalendar {
        calendar: merger.calendar,
        coverage_horizon: if reached_end {
            None
        } else {
            Some(merger.latest_start.unwrap_or_else(Utc::now))
        },
    })
}

/// An empty body means "past the end" for any page after the first. Anything else must parse as a
/// calendar -- in particular a non-empty non-calendar body (a Cloudflare challenge page, say) is an
/// error rather than a silent end of the feed, which would make everything beyond it look deleted.
fn classify_page(page_number: u32, body: &str) -> Result<Page, Status> {
    if body.trim().is_empty() {
        return if page_number > 1 {
            Ok(Page::End)
        } else {
            Err(Status::new(Code::FailedPrecondition, "stellarwp_empty_response"))
        };
    }
    parse_calendar(body).map(Page::Calendar)
}

/// Identifies one VEVENT across overlapping pages: for a recurring series every occurrence shares
/// a `UID`, and each is told apart by `RECURRENCE-ID`/`DTSTART`.
fn event_key(event: &icalendar::Event) -> String {
    format!(
        "{}\u{1f}{}\u{1f}{}",
        event.property_value("UID").unwrap_or(""),
        event.property_value("RECURRENCE-ID").unwrap_or(""),
        event.property_value("DTSTART").unwrap_or(""),
    )
}
