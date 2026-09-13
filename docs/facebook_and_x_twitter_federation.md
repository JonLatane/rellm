# Facebook and X (Twitter) Sync

Rellm's "Sync Destinations" feature lets a user connect one of their Facebook Pages as a
[`SyncDestination`](https://rellm.org/docs/protocol#rellm-SyncDestination), so calling [`SyncOccasion`](https://rellm.org/docs/protocol#grpc-api-SyncOccasion) or [`SyncPost`](https://rellm.org/docs/protocol#grpc-api-SyncPost) posts the [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion)/[`Post`](https://rellm.org/docs/protocol#rellm-Post) to
that Page. Implementation: [`backend/src/logic/facebook_sync.rs`](../backend/src/logic/facebook_sync.rs),
invoked from [`SyncOccasion`](../backend/src/rpcs/events/sync_occasion.rs) and
[`SyncPost`](../backend/src/rpcs/posts/sync_post.rs) alike (both dispatch through the same
`post_to_facebook_page`, sharing every Facebook-specific detail below regardless of content type).

This doc also covers X (Twitter) sync (see "X (Twitter)" below) since the two share a section for
now - unlike Facebook, X sync isn't functional yet, so there isn't much to say about it on its
own. (Instagram, Mastodon, Bluesky, and Threads sync each have their own quirks worth documenting
separately if this file grows unwieldy - for now, see each platform's own message doc comment in
[`protos/sync.proto`](../protos/sync.proto) and `protos/rellm.proto`'s `##### SyncDestination`
section for the rest.)

## It posts to the Page's feed, not a real Facebook Event

Posting an [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion) creates a Facebook **Page post** (`POST /{page-id}/feed`) formatted to
read like an event announcement, or attaches its media (see "What's in the post" below) - it does
**not** create an actual Facebook **Event** object (the kind users can RSVP to natively on
Facebook), because the Graph API no longer allows that for ordinary third-party apps:

- `POST /{page-id}/events` (and update/delete) has been locked down since Graph API v3.3 (2018).
  Meta's own reference for the `event` node states creation isn't supported on that endpoint at
  all.
- Even *reading* Page/User events via the Graph API is restricted to approved **Facebook Marketing
  Partners** - a vetted-agency program (minimum ad spend/message volume, ongoing compliance
  review) that isn't a realistic fit for a self-hosted Rellm server.
- Real integrations that appear to "create a Facebook Event" (e.g. Eventbrite) don't do it via a
  server-side API call either - they deep-link the user's own browser into Facebook's native
  "Create Event" UI, pre-filled, and the human finishes it themselves.
- Meta does have an [Official Events API](https://developers.facebook.com/products/official-events-api/)
  product that *can* create real Events at scale, but it's gated behind a partner application
  (aimed at large ticketing/event platforms, not individual self-hosted servers) - and as of this
  writing that page's own "Apply Now" link (`facebook.com/help/contact/FacebookEventsPartnerInquiryForm`)
  404s, with stale "pausing onboarding due to COVID-19" copy still up. Not a viable path.

So the Page-post approach here is the best available server-side option, not an oversight. (This
limitation is specific to *Events* - a [`Post`](https://rellm.org/docs/protocol#rellm-Post) has no such native-object alternative to begin with,
so its Page post is simply the whole feature for Posts.)

## What's in the post

`logic::sync_message::build_occasion_message`/`build_post_message` build one
platform-agnostic `SyncMessage` per sync (shared by every [`SyncDestination`](https://rellm.org/docs/protocol#rellm-SyncDestination) platform, not just
Facebook) from the content's own [`Post`](https://rellm.org/docs/protocol#rellm-Post) (`title`/`content`/`link`) and, for an [`Occasion`](https://rellm.org/docs/protocol#rellm-Occasion),
also its `starts_at`/`ends_at`/`location`:

1. Title - for an Occasion, `rpcs::events::sync_occasion` combines the parent Event's
   own title with the Occasion's own (only if the Occasion actually overrides it) as
   `"{event_title}: {occasion_title}"`, e.g. "Run Club" or "Run Club: Special Holiday Edition" (see
   `combine_title`/`combine_content` in that file)
2. *(Occasion only)* Date/time range (single timestamp if `ends_at` isn't after `starts_at`,
   otherwise a friendly `start-end` range mirroring the Elm UI's own `Shared.Time.formatRange`;
   shown in the event location's local timezone if it could be resolved, else UTC - see below)
3. *(Occasion only)* Location (`Occasion.location.uniformly_formatted_address`), if set,
   prefixed with 📍
4. Content/description - for an Occasion, the same combine-with-a-`---`-separator treatment
   as the title (`"{event_content}\n\n---\n\n{occasion_content}"`)
5. The Rellm link (`event_url`/`post_url`), bare (Occasion) or prefixed `View post:` (Post),
   if one could be built (see below)

`post_to_facebook_page` (in `facebook_sync.rs`) then decides how to send that `SyncMessage` to the
Page: text+link only if there's no attached media, one or more unpublished-photo uploads followed
by a `/feed` post referencing them (`attached_media[N]`) if there are images, or a dedicated
`/videos` post if there's a video (video wins if both are present - the Graph API can't mix photo
attachments and a video in one Page post). The `link` param (which drives a text-only post's
link-preview card) prefers the Rellm URL; if that isn't available it falls back to the arbitrary
external `link` the author/organizer set on the [`Post`](https://rellm.org/docs/protocol#rellm-Post) itself (e.g. an article or ticketing site).

## Local-timezone times via free-text address geocoding

`Occasion.location` only stores a free-text `uniformly_formatted_address` (no lat/lng --
see `protos/location.proto`), so showing times in the event's local timezone instead of UTC needs
resolving that address to a timezone first. `logic::geocoding` (`resolve_timezone`) does this in
two keyless, free steps, chained on every sync (never cached/persisted - see "future work"
below):

1. **Address -> lat/lng**: OpenStreetMap's public Nominatim API (`nominatim.openstreetmap.org`) --
   the same service the Tamagui frontend's location picker already calls client-side
   (`packages/app/hooks/use_nominatim.ts`), just used server-side here too. Its response already
   includes `lat`/`lon`, which the Tamagui picker currently fetches and discards - only
   `display_name` gets saved into the [`Location`](https://rellm.org/docs/protocol#rellm-Location).
2. **lat/lng -> IANA timezone**: the [`tzf-rs`](https://github.com/ringsaturn/tzf-rs) crate, an
   offline polygon-based dataset bundled into the binary - no second network call, no rate limit,
   actively maintained.

Nominatim's [usage policy](https://operations.osmfoundation.org/policies/nominatim/) caps public
API use at roughly 1 request/second and requires a descriptive `User-Agent`, which is fine for
this on-demand, per-sync-click call but not for bulk/automated geocoding.

This is entirely best-effort: any failure (bad address, network error, unparseable response, no
geocoding match) makes `resolve_timezone` return `None`, and the post just falls back to UTC --
never a reason to fail the sync itself.

**Possible future work**: since Tamagui's Nominatim call already has `lat`/`lon` in hand at
location-pick time, persisting those on [`Location`](https://rellm.org/docs/protocol#rellm-Location) (proto + DB + both frontends) would let syncs
skip the live geocoding call entirely and use `tzf-rs` directly - faster, no dependency on
Nominatim's uptime/policy, and it would also cover Elm-created locations if Elm ever gains its own
address picker (today Elm's location field is plain free text with no geocoding at all).

## The Rellm link needs CDN/frontend config

The `event_url`/`post_url` (`https://{frontend_host}/event/{occasion_id}` or
`https://{frontend_host}/post/{post_id}`) is only built when this server has
`ServerConfiguration.external_cdn_config.frontend_host` configured. Unlike Rocket web routes
(`configured_frontend_domain` in `backend/src/web/external_cdn.rs`), the [`SyncOccasion`](https://rellm.org/docs/protocol#grpc-api-SyncOccasion)/
[`SyncPost`](https://rellm.org/docs/protocol#grpc-api-SyncPost) RPCs have no HTTP `Host` header to fall back on, so on servers without `frontend_host`
set, the post simply omits the Rellm link (falling back to the author's own `Post.link`, if any)
rather than guessing a domain. This is an accepted current limitation, not a bug - set
`frontend_host` if you want synced posts to link back to their Rellm page.

## Connecting a Page (OAuth/token flow)

1. The client does Facebook Login and gets a short-lived **user** access token, passed to
   [`CreateSyncDestination`](https://rellm.org/docs/protocol#grpc-api-CreateSyncDestination) (or [`UpdateSyncDestination`](https://rellm.org/docs/protocol#grpc-api-UpdateSyncDestination) to reconnect).
2. The server loads its own Facebook App ID/Secret (admin-configured via [`ConfigureServer`](https://rellm.org/docs/protocol#grpc-api-ConfigureServer) ->
   `ServerConfiguration.federation_info.facebook_auth_config`) and exchanges the short-lived user
   token for a long-lived one (`connect_facebook_page` -> `exchange_long_lived_user_token`).
3. It then looks up the specific Page's own access token via `/me/accounts`
   (`find_page_access_token`), which only lists Pages the user administers.
4. The resulting long-lived **Page** access token is stored in
   `SyncDestination.configuration.facebook_page.access_token` and reused indefinitely - Page
   tokens obtained this way don't expire on a timer, only if the user revokes access or changes
   their Facebook password.

Note this token only has permission to post to the Page's feed - posting to a user's personal
timeline isn't possible via the Graph API at all (Facebook deprecated `publish_actions` in 2018).
(Instagram sync reuses this exact same connect flow and Page token - see `protos/rellm.proto`'s
`##### SyncDestination` doc for how each platform's connect flow differs.)

## X (Twitter)

Implementation: [`backend/src/logic/x_twitter_sync.rs`](../backend/src/logic/x_twitter_sync.rs) - architecturally closest to
`threads_sync.rs` among the existing platforms (a `response_type=code` authorize-then-exchange
flow, no "choose a Page" step), with two real differences of its own:

- **PKCE is mandatory.** The connect popup generates a `code_verifier` and sends its paired
  `code_challenge` to X's authorize endpoint, then the server exchanges `authorization_code` +
  `code_verifier` for a token. The popup uses `code_challenge_method=plain` (challenge ==
  verifier) rather than the stronger `S256` - computing a SHA-256 challenge needs `crypto.subtle`,
  which is only ever available asynchronously in a browser, and the popup has to open
  *synchronously* in direct response to the click to survive mobile Safari's async-popup blocking
  (the same constraint `public/index.html`'s `facebookLoginPopup` port handler already works
  around for Facebook/Threads). `plain` is a real, spec-sanctioned PKCE mode, just a weaker one --
  an honest, documented tradeoff, not an oversight.
- **Access tokens expire in 2 hours**, unlike Threads' ~60-day token - too short to punt on
  refreshing the way `threads_sync`'s module doc explicitly does for Threads. `post_tweet`
  refreshes proactively via the stored `refresh_token` (no user interaction needed) before every
  post when the stored token is expired or close to it, persisting the new token pair back to the
  `sync_destinations` row - the one platform-specific `post_*` function in this codebase that
  needs a DB connection for that reason.

Like Facebook (whose app credentials also cover Instagram and Threads, since all three are Meta
products), X requires its **own** registered X Developer App - one admin sets
`ServerConfiguration.federation_info.x_twitter_auth_config` (an `XTwitterAuthConfig { client_id,
client_secret }`, mirroring `facebook_auth_config`'s shape and its own admin UI, "X (Twitter)
Authentication Configuration" on the Server Information page's Federation tab) once, and every
user on the server connects their own X account through it via OAuth - no per-user API keys
needed. Until an admin sets it, every RPC touching an `XTwitterAccount` destination fails with
`x_twitter_app_not_configured`. Note X's current API pricing tiers gate meaningful write access
behind a paid plan - that's between the server admin and X, not something Rellm's code can work
around.

**Known limitation**: only *images* are uploaded (up to 4, downloaded from this server's own media
URL and re-uploaded as raw bytes to `/2/media/upload`, mirroring `mastodon_sync`'s fetch-then-
reupload shape since X's media endpoint also takes bytes, not a remote URL like Facebook/
Instagram/Threads'). Video/GIF is not yet supported - X's video upload requires a chunked
INIT/APPEND/FINALIZE-plus-processing-status-poll flow (mirrors `bluesky_sync`'s own documented
video gap) not yet built; a video attachment on a synced Post/Occasion is silently skipped.

## Testing

`facebook_sync.rs`'s functions all take a `base_url` so specs
(`backend/src/tests/facebook_sync_tests.rs`) can run against a local mock
(`factories::serve_facebook_graph_api`) instead of the real Graph API. There is currently no real
Facebook App wired up for local dev, so the full connect/create flow against the real API can only
be exercised in production - see the mock-based specs for what's covered locally.

`x_twitter_sync.rs`'s functions follow the exact same `base_url` pattern (see
`backend/src/tests/x_twitter_sync_tests.rs` and `factories::serve_x_twitter_api`) - same caveat,
no real X Developer App wired up for local dev, so the real API is only exercised once an admin
configures one on an actual deployment.
