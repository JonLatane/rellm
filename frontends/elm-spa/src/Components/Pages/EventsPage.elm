module Components.Pages.EventsPage exposing
    ( EventsDisplayMode
    , Model
    , Msg
    , fromShared
    , init
    , searchTextChanged
    , showSyncDestinationsChanged
    , showSyncSourcesChanged
    , subscriptions
    , update
    , view
    )

{-| The shared guts of an "upcoming events" page: fetching upcoming
`Occasion`s from every enabled server and rendering them with fade
in/out animations -- mirrors `Components.Pages.PostsPage` almost exactly
(`ServerFeed`/`fetchNewServers`/`refetchServers`/`syncAnimations`/
`setBreadcrumbsRoot` all follow the same shape, just over
`(Event, Occasion)` pairs instead of `Post`s), reused by `Pages.Events`
(which passes `author = Nothing`) and `Pages.UsernameOrCustomTab_.Events`/
`Pages.User.UserId_.Events` (which pass the already-resolved profile `User`,
restricting the feed to that user's own events), same as `PostsPage` is
reused by `Pages.Home_`/`Pages.UsernameOrCustomTab_.Posts`/`Pages.User.UserId_.Posts`.

The one real departure from `PostsPage`: this listing is itself centered on
the `Occasion` (every `Event` can have many, see `Components.Events`'
own module doc), and it supports three interchangeable layouts
(`EventsDisplayMode`) with a smooth FLIP-animated transition _between_
layouts, not just item enter/exit -- `VerticalList`'s cards are full-width
(mirrors `PostsPage`'s own `.post-card`), `Grid`/`HorizontalList`'s are a
fixed tile width (see `events.css`), so a layout switch is a genuine
position-_and_-resize, not just a reflow. That transition reuses `UI.Flip`'s
`MoveState`/`startMoveScaled`/`moveAttributes` machinery (`startMove`'s
scaled sibling, added alongside it for exactly this) -- see
`DisplayModeChanged`'s handling below for the actual "measure old
position/size, switch layout, measure new position/size, animate the
difference away" FLIP recipe.

-}

import Animation
import Browser.Dom as Dom
import Browser.Navigation
import Components.Events as Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.Users exposing (usernameHref)
import Components.Users.ProfileHeading as ProfileHeading
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, h2, h3, input, p, span, text)
import Html.Attributes exposing (class, href, id, placeholder, style, target, title, type_, value)
import Html.Events exposing (onClick, onInput, onMouseDown, preventDefaultOn)
import Html.Keyed
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Process
import Proto.Google.Protobuf exposing (Timestamp)
import Proto.Rellm exposing (Event, Occasion, SyncDestination, User)
import Proto.Rellm.CalendarDisplayMode as CalendarDisplayMode exposing (CalendarDisplayMode(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Conversions as Conversions
import Shared.CreateNewPanel as CreateNewPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.StarredPanel as StarredPanel
import Shared.Time as SharedTime
import Shared.UserPreferences as UserPreferences
import Task
import Time
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.Flip
import UI.Modal
import Url.Builder



-- MODEL


type alias Model =
    { eventsByServer : Dict String ServerFeed
    , eventAnimations : Dict String EventAnimation

    -- `Calendar` mode's own single-item enter/leave fade, alongside
    -- `eventAnimations`' per-card ones -- always either empty or a single
    -- entry keyed `calendarAnimationKey`, reconciled by
    -- `syncCalendarAnimations` (mirrors `syncAnimations` exactly, just via
    -- `UI.Flip.syncAnimations`' own generic form instead of a bespoke one,
    -- since there's no per-item data to thread through here) whenever
    -- `mode` changes. Kept as its own dict (rather than folded into
    -- `eventAnimations`) because `EventAnimation` is typed around a real
    -- `(Event, Occasion)` pair, which a calendar view has none of --
    -- see `eventsListView`'s own doc for how the two dicts render as one
    -- combined list regardless.
    , calendarAnimations : Dict String CalendarAnimation

    -- The `eventAnimationKey` of the `Calendar`-mode event most recently
    -- tapped (via `Ports.calendarEventClicked`/`CalendarEventClicked`) --
    -- `Nothing` means `calendarPreviewModalView`'s own modal is closed.
    -- Doubles as its own scroll target: opening it (or re-tapping a
    -- different event while it's already open) always re-fires
    -- `scrollToCalendarPreviewCard` for whatever key this currently is. See
    -- `calendarPreviewModalView`'s own doc for why this needs no per-card
    -- animation dict of its own, unlike `eventAnimations`/`calendarAnimations`.
    -- Persisted as `?calendar_preview=<key>` (see `queryParams`), round-tripped
    -- back out of it at `init` -- always via `replaceUrl` (`pushUrl`), never
    -- `pushUrl` the navigation function, so opening/closing it never itself
    -- spams browser history (mirrors every other filter this page persists).
    , calendarPreview : Maybe String

    -- A `calendarPreviewCardView` key waiting for `calendarPreviewEvents` to
    -- actually contain it before `scrollToCalendarPreviewCard` can do
    -- anything with it -- seeded at `init` from either the `#calendar-preview-<key>`
    -- URL fragment or (absent one) `calendarPreview` itself, `Nothing`
    -- otherwise. Exists because `init` sets `calendarPreview` (and thus opens
    -- the modal) well before `eventsByServer` has any data to search for that
    -- key in -- mirrors `Components.Pages.MessagesPage.Model.pendingScrollMessageId`/
    -- `Pages.Messages`' own `#message-<id>` handling exactly, including the
    -- "retried by every relevant `update`, cleared only once the attempt
    -- actually fires" lifecycle -- see `pendingCalendarPreviewScrollEffect`.
    --
    -- The fragment (rather than always just `calendarPreview` itself) is what
    -- lets `calendarPreviewCardView`'s own `onClick` (`CalendarPreviewCardNavigated`)
    -- capture "which card, _within_ an already-open modal, was actually
    -- clicked" separately from "which event opened the modal in the first
    -- place" -- so leaving via that click and returning via the back button
    -- lands back on `?calendar_preview=<original>#calendar-preview-<clicked>`,
    -- restoring the modal centered on the original tap but scrolled to
    -- wherever the user had actually scrolled to before clicking away.
    , pendingCalendarPreviewScroll : Maybe String
    , mode : EventsDisplayMode

    -- The `EventsDisplayMode` `mode` defaults to absent an explicit
    -- `?display=` -- computed once, at `init` (see `defaultMode`), from
    -- `embeddedPage` and the then-current `Shared.UserPreferences.prefersCalendar`,
    -- and kept around (rather than re-derived from those on every call) so
    -- `queryParams` can compare `mode` against exactly the default `init`
    -- actually seeded it with, even if `prefersCalendar` itself changes
    -- later in this same session (see `DisplayModeChanged`).
    , defaultDisplayMode : EventsDisplayMode

    -- `True` for embedded copies of this model whose own default `mode` is
    -- `HorizontalList`/"row" rather than `VerticalList`/"list" (currently
    -- `Pages.Home_`'s and `Components.Pages.UserProfilePage`'s, passed via
    -- `init`'s own `embeddedPage` argument) -- changes `queryParams`' notion
    -- of `mode`'s default (see `defaultMode`) so an embedded copy's own
    -- default doesn't round-trip to an explicit `?display=row`. Also gates
    -- `setBreadcrumbsRoot` off entirely (see its own doc) -- an embedded
    -- copy's embedding page (`Pages.Home_`, `Components.Pages.UserProfilePage`)
    -- owns `Shared.Breadcrumbs` itself, so this copy asserting a root of its
    -- own on every `update` (including every animation tick, e.g. from
    -- `eventAnimations`) would otherwise fight the real owner for it.
    , embeddedPage : Bool

    -- A modifier of `embeddedPage`, not an independent flag (see `searchRowView`'s own
    -- `embeddedPage && embeddingPageSearchesPosts` check) -- whether an embedded copy's search box
    -- also searches a *paired* `PostsPage` feed shown alongside it (`Pages.Home_`'s `Feed`,
    -- `Components.Pages.UserProfilePage`'s combined view), reading the placeholder "Search posts and
    -- events…" instead of plain "Search events…" when it does. `Pages.Home_.HomePostWithEvents` (a
    -- fixed Post with an Events strip above it) is the first `embeddedPage = True` copy with no such
    -- paired feed -- just the one fixed Post -- hence needing this as its own field rather than
    -- reusing `embeddedPage` alone the way `searchRowView` used to. Meaningless (never read on its
    -- own) whenever `embeddedPage` is `False`; `False` everywhere except `Feed`'s/`UserProfilePage`'s
    -- own two copies.
    , embeddingPageSearchesPosts : Bool

    -- Whether switching `mode` into/out of `Calendar` (see `DisplayModeChanged`)
    -- writes `Shared.UserPreferences.prefersCalendar` -- `True` only for
    -- `Pages.Home_`'s and `Pages.Events`' own copies (passed via `init`'s own
    -- `syncsCalendarPreference` argument), so switching layouts while looking
    -- at just one user's events (`Components.Pages.UserProfilePage`,
    -- `Pages.UsernameOrCustomTab_.Events`, `Pages.User.UserId_.Events`) never overwrites
    -- the preference every copy's own `defaultMode` reads back (see that
    -- field's own doc) -- it's still *read* there regardless of this flag,
    -- just never *written*.
    , syncsCalendarPreference : Bool
    , measurementPhase : MeasurementPhase
    , author : Maybe ( String, User )
    , navKey : Browser.Navigation.Key
    , path : String
    , tab : EventsTab

    -- The search box's text (see `searchRowView`), sent as `Components.Events.fetchEvents`' own
    -- `searchText` -- mirrors `PostsPage.Model.searchText` exactly, including
    -- `searchGeneration`'s debounce below.
    , searchText : String
    , searchGeneration : Int

    -- The cutoff actually sent as `Components.Events.fetchEvents`' own
    -- `endsAfter` -- `Nothing` only ever transiently, at startup, until
    -- either the very first `GotNow` (`UpcomingEvents`) or a parsed
    -- `?ends_after=` query param (`EventsAfterDate`) resolves it, so this
    -- page never fetches at all until it has a real cutoff in hand. Fetching
    -- before that (this page used to seed a placeholder `Time.millisToPosix
    -- 0`, i.e. the UNIX epoch, so its very first request asked for events
    -- "ending after 1970") was the actual cause of very old events
    -- occasionally flashing up on first load. Switching to `EventsAfterDate`
    -- for the first time this session (`TabChanged`) instead seeds this from
    -- `Shared.UserPreferences.eventsAfter`, if set, rather than wherever
    -- `UpcomingEvents`' live clock last left it -- see that field's own doc.
    , endsAfter : Maybe Time.Posix

    -- Debounces `EndsAfterInputChanged` (500ms) -- mirrors
    -- `PostsPage.Model.searchGeneration`/`SearchDebounceElapsed` exactly,
    -- just for the date input instead of the search box: bumped on every
    -- keystroke/picker tick, so a `EndsAfterDebounceElapsed` timer that
    -- fires after a later edit already moved this past it knows to ignore
    -- itself as stale.
    , endsAfterInputGeneration : Int

    -- Whether the "Export" button's ICS-subscription-link popover (see
    -- `exportButtonView`) is currently open -- closed by clicking its own
    -- backdrop (`ExportPopoverClosed`), same "backdrop closes it" idea
    -- `UI.Modal` uses for full dialogs, just anchored under the button
    -- instead of centered.
    , exportPopoverOpen : Bool

    -- Whether `CopyLinkClicked` most recently fired within the last 5s --
    -- `exportButtonView`'s "Copy Link" button reads this to show "Link
    -- Copied!" for that stretch instead. `copyLinkGeneration` mirrors
    -- `searchGeneration`'s own debounce convention: bumped on every click, so
    -- a `CopyLinkCopyTimeoutElapsed` timer from an earlier click (superseded
    -- by clicking Copy Link again before its own 5s was up) knows to leave
    -- the flag alone rather than clearing a copy that hasn't actually been
    -- showing for 5s yet.
    , copyLinkCopied : Bool
    , copyLinkGeneration : Int

    -- Whether `syncAnimations` should hide `UpcomingEvents`-tab occasions
    -- that have already started (see `hiddenAsStarted`) -- defaults (`init`)
    -- to `not (showStartedOrLongEventsByDefault shared)`, i.e. `True` unless
    -- `mainFrontendHost`'s own `EventSettings.show_started_or_long_events_by_default`
    -- is set, and has no effect on `EventsAfterDate`. Means something
    -- different while `model.mode == Calendar`, though: there, it instead
    -- hides occasions spanning more than `longEventThresholdHours` (see
    -- `hiddenAsLong`) -- a multi-day event is exactly what makes `Calendar`'s
    -- day-by-day grid unreadable, with no equivalent problem in any card
    -- layout, and "already started" has no such problem there either. The
    -- button that toggles it (`hideStartedOrLongButtonView`) is only ever
    -- shown while `UpcomingEvents` is active *and* there's actually something
    -- for it to hide, in whichever sense currently applies (see
    -- `anyStartedEvents`/`view`) -- nothing to filter, nothing to show a
    -- toggle for.
    , hideStartedOrLongEvents : Bool

    -- Whether `eventCardView` shows each card's `Events.syncSourceView`/
    -- `Events.eventSyncDestinationsView` -- both default to `False` (`init`),
    -- set via `ShowSyncSourcesChanged`/`ShowSyncDestinationsChanged`.
    -- `Components.Pages.UserProfilePage`'s embedded copy keeps these in sync
    -- with its own `syncSourcesExpanded`/`eventSyncDestinationsExpanded`
    -- section toggles; no other caller ever sets them, so they stay `False`
    -- (and these lines don't render) everywhere else.
    , showSyncSources : Bool
    , showSyncDestinations : Bool

    -- Threaded straight into `Events.eventCard`'s own `availableSyncDestinations`
    -- param (see that function's own doc) -- set once at `init` (unlike
    -- `showSyncSources`/`showSyncDestinations`, this only ever needs to
    -- change when the whole page gets re-inited anyway, since it comes from
    -- a resolved `User`, not a live UI toggle). `Nothing` for every caller
    -- except `Components.Pages.UserProfilePage`, which passes
    -- `Just user.eventSyncDestinations` -- see `init`'s own doc.
    , availableSyncDestinations : Maybe (List SyncDestination)

    -- Overrides `calendarDisplayMode shared`'s own server-wide `EventSettings.default_calendar_display_mode`
    -- for this copy's `Calendar` mode alone -- `Nothing` everywhere except `Pages.Home_`'s own
    -- embedded strip(s), which pass `Just customTabs.home.default_events_strip_calendar_display_mode`
    -- once an admin's actually configured `home` (see `Pages.Home_.eventsStripCalendarDisplayModeOverride`),
    -- so the home page's own strip can open to a different granularity (e.g. "Week") than the
    -- standalone Events page's own server-wide default (e.g. "Month") without changing that global
    -- setting. Read only by `calendarRenderEffect`.
    , calendarDisplayModeOverride : Maybe CalendarDisplayMode

    -- `Submitting`/`SubmitFailed` push status per `occasionId ++ "|" ++
    -- destinationId` (many occasions on screen at once, unlike
    -- `Pages.Event.PostId_`'s own single-occasion `pushStatuses`, which
    -- only needs to key by `destinationId`) -- drives the `isPushing`/
    -- `pushError` closures `eventCardView` builds for `Events.eventCard`.
    , pushStatuses : Dict String SubmitStatus
    }


type Msg
    = GotServerEvents String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetEventsResponse ))
    | GotNow Time.Posix
    | Poll
    | Animate Animation.Msg
    | AnimateMove Animation.Msg
    | RemoveEvent String
    | RemoveCalendarAnimation
    | MoveSettled String
    | SharedMsg Shared.Msg
      -- Switches `model.mode` -- see this branch's own handling below for
      -- the FLIP "measure old positions, switch, measure new positions,
      -- animate the difference away" recipe.
    | DisplayModeChanged EventsDisplayMode
      -- `Ports.elementsMeasured` firing -- which half of the FLIP round-trip
      -- this is (if any) is read off `model.measurementPhase`, not this
      -- `Msg`'s own (untargeted, port-delivered) payload. A payload that
      -- fails to decode is treated the same as `measurementPhase` already
      -- being `NotMeasuring` -- give up silently, same fallback
      -- `PostId_.scrollToOccasion` already relies on for its own
      -- `Dom`-adjacent calls.
    | GotMeasuredRects Decode.Value
      -- One deliberate `requestAnimationFrame` wait (via a throwaway
      -- `Browser.Dom.getViewport` task -- see this branch's own handling
      -- below for why) between the mode switch actually landing in the
      -- model and firing the *second* `measureElementsEffect` -- Elm's own
      -- `Browser.application` runtime (`_Browser_makeAnimator` in the
      -- compiled output) defers painting a model change to the *next* rAF
      -- rather than doing it synchronously when `update` returns, so
      -- measuring immediately (as a first cut of this port-based rewrite
      -- did) could race ahead of the DOM actually having the new mode's
      -- classes applied yet -- silently measuring the *old* layout twice
      -- and animating a zero delta, which read as "no animation at all"
      -- (confirmed live: barely any `AnimateMove` ticks, `MoveSettled`
      -- firing almost immediately). This costs exactly one frame,
      -- regardless of how many cards there are -- nothing like the
      -- original N-frames-per-element `Browser.Dom.getElement` bug this
      -- whole port replaced.
    | ReadyToMeasureNew
      -- Switches `model.tab` -- a no-op if already active. Mirrors
      -- `DisplayModeChanged` in spirit but needs none of its FLIP
      -- machinery: there's no shared layout to slide between, just a
      -- different fetch cutoff, so this just updates `model.tab`/refetches/
      -- persists the URL directly. See `tabsView`. Switching into
      -- `EventsAfterDate` for the first time this session also seeds
      -- `model.endsAfter` from `Shared.UserPreferences.eventsAfter`, if set
      -- -- see that field's own doc -- rather than leaving it wherever
      -- `UpcomingEvents`' live clock last left it.
    | TabChanged EventsTab
      -- The `EventsAfterDate` tab's `<input type="datetime-local">` firing
      -- -- parsed via `Shared.Time.posixFromDateTimeLocalInput`;
      -- an unparseable (e.g. momentarily incomplete while typing) value is
      -- just ignored, same "give up silently" convention as everywhere
      -- else in this module. A valid one switches to that tab too (even if
      -- `UpcomingEvents` was active), per `tabsView`'s own doc. Updates
      -- `model.endsAfter` (so the input/tab reflect it immediately) but
      -- only *fetches*, debounced 500ms -- see `EndsAfterDebounceElapsed`,
      -- which also persists it as `Shared.UserPreferences.eventsAfter` once
      -- the debounce settles.
    | EndsAfterInputChanged String
      -- `EndsAfterInputChanged`'s debounce timer elapsing -- mirrors
      -- `PostsPage.SearchDebounceElapsed` exactly: a no-op if a later edit
      -- already bumped `model.endsAfterInputGeneration` past this timer's
      -- own (i.e. this one's stale).
    | EndsAfterDebounceElapsed Int
      -- The search box firing (see `searchRowView`) -- mirrors
      -- `PostsPage.SearchTextChanged`/`SearchDebounceElapsed`/
      -- `ClearSearchClicked` exactly, just against `Events.fetchEvents`'
      -- `searchText` instead of `Posts.fetchPosts`'.
    | SearchTextChanged String
    | SearchDebounceElapsed Int
    | ClearSearchClicked
      -- The "hide started events" filter button (see `hideStartedOrLongButtonView`)
      -- toggling `model.hideStartedUpcomingOrLongEvents` -- purely a local
      -- filter over already-fetched data (see `hiddenAsStarted`/
      -- `syncAnimations`), so there's nothing to fetch here.
    | HideStartedEventsToggled
      -- Sets `model.showSyncSources`/`model.showSyncDestinations` -- driven
      -- by `Components.Pages.UserProfilePage`'s own "Sync Sources"/
      -- "Sync Destinations" section-expanded toggles (see
      -- `Model.showSyncSources`'s own doc), not by anything in this page's
      -- own UI.
    | ShowSyncSourcesChanged Bool
    | ShowSyncDestinationsChanged Bool
      -- Opens/closes the "Export" button's ICS-subscription-link popover
      -- (see `exportButtonView`).
    | ExportClicked
    | ExportPopoverClosed
      -- Copies `icsUrl`'s link to the clipboard via `Ports.copyToClipboard`
      -- and shows "Link Copied!" (`model.copyLinkCopied`) for 5s.
    | CopyLinkClicked
      -- That 5s elapsing -- mirrors `EndsAfterDebounceElapsed`'s own stale-
      -- generation guard: a no-op if a later `CopyLinkClicked` already bumped
      -- `copyLinkGeneration` past this timer's own.
    | CopyLinkCopyTimeoutElapsed Int
      -- The Push button on a card's `Events.eventCard`-rendered sync
      -- destination row (see `Model.availableSyncDestinations`'s own doc) --
      -- host/occasionId/eventSyncDestinationId, keyed into
      -- `Model.pushStatuses` via `pushStatusKey`.
    | PushOccasionToDestination String String String
    | GotPushResult String String String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Occasion ))
      -- FullCalendar's own `eventClick` firing over `Ports.calendarEventClicked`
      -- -- opens `calendarPreviewModalView`'s modal (`model.calendarPreview`)
      -- to the tapped event's key and kicks off `scrollToCalendarPreviewCard`.
      -- A no-op-but-still-rescrolls if the modal's already open to a
      -- *different* event (just updates which one, see `Model.calendarPreview`'s
      -- own doc).
    | CalendarEventClicked String
      -- Closes `calendarPreviewModalView`'s modal -- its own close button or
      -- backdrop click.
    | CalendarPreviewClosed
      -- `scrollToCalendarPreviewCard`'s measurement resolving -- mirrors
      -- `Pages.Event.PostId_.GotScrollTarget` exactly, including giving up
      -- silently (`Err`) if the strip/card aren't found (e.g. the modal was
      -- closed again before this resolved). Also clears `model.pendingCalendarPreviewScroll`
      -- unconditionally (mirrors `Components.Pages.MessagesPage.ScrollAttempted`'s
      -- own doc) -- whichever key it was waiting for, this was its one-shot
      -- attempt.
    | GotCalendarPreviewScrollTarget (Result Dom.Error Float)
      -- A `calendarPreviewCardView` fired via its own `onMouseDown` -- attached
      -- to the whole card (not just its inner nav-overlay link) since the exact
      -- element pressed doesn't matter here, only that a `mousedown` on this
      -- card means a `click` (and, for the nav-overlay link, the browser's own
      -- `<a href>` navigation) is about to follow. Deliberately `onMouseDown`,
      -- not `onClick`: elm/browser's own internal-link interception (what
      -- turns that `<a href>` click into `Main.ClickedLink`/`Nav.pushUrl`) is
      -- registered on `document` for `"click"` *and* calls `stopPropagation`,
      -- so an `onClick` here would never even fire for a click that actually
      -- lands on the nav-overlay -- confirmed live (`run-elm`'s `driver.mjs`):
      -- the fragment this handler writes only ever showed up for clicks that
      -- *didn't* trigger real navigation. `mousedown` fires as an earlier,
      -- separate event `click` interception has no hook into at all, so this
      -- always gets to run first. Fires a `replaceUrl` that bakes the pressed
      -- card's own key into a `#calendar-preview-<key>` fragment *before* the
      -- `click`/navigation that follows -- both are plain `Browser.Navigation`
      -- commands, processed synchronously in the order issued, so the
      -- fragment is reliably part of the URL entry `Main.backStack` captures
      -- for this page. See `Model.pendingCalendarPreviewScroll`'s own doc for
      -- what reads that fragment back on return.
    | CalendarPreviewCardNavigated String


{-| Mirrors `Pages.Post.PostId_.SubmitStatus`/`Pages.Event.PostId_.SubmitStatus`
exactly -- see `Model.pushStatuses`.
-}
type SubmitStatus
    = Submitting
    | SubmitFailed String


{-| The four interchangeable layouts `eventsListView` can render its cards
in -- `VerticalList` (the default, a single full-width column, mirroring
`PostsPage.postsListView`'s `.flip-animated-column`), `Grid` (a wrapping
fixed-tile-width grid, reusing `flip.css`'s existing `.flip-animated-grid`,
built for `Shared.MyMediaPanel`'s media tiles), `HorizontalList` (a
single horizontally-scrolling row of that same fixed tile width, mirroring
`Pages.Event.PostId_`'s own date-picker strip), and `Calendar` (a
[FullCalendar](https://fullcalendar.io/) view rendered by JS via
`Ports.renderCalendar` -- see `calendarView`/`calendarEvents`). `Grid`/
`HorizontalList` share one card size, but `VerticalList`'s is genuinely
different (full-width vs. a fixed tile), so switching to/from it is a
position-_and_-resize FLIP, not just a reflow -- see `DisplayModeChanged`.
`Calendar` isn't a card layout at all -- switching to/from it skips
`DisplayModeChanged`'s move-slide FLIP (nothing sized/positioned like a card
to measure), but still renders as `VerticalList`'s own single-column
container, holding the real cards (fading out, via `eventAnimations`/
`syncAnimations`) alongside one more item: the calendar view itself, fading
in the opposite direction via its own `Model.calendarAnimations`/
`syncCalendarAnimations` -- see `eventsListView`'s own doc.
-}
type EventsDisplayMode
    = HorizontalList
    | VerticalList
    | Grid
    | Calendar


type ServerEvents
    = Loading
    | Loaded (List ( Event, Occasion ))
    | Failed


{-| `accountId` is the enabled account (if any) the events were/are being
fetched with, so a later account enable/disable on the same server can be
detected as "the acting credential changed" and trigger a re-fetch -- mirrors
`Components.Pages.PostsPage.ServerFeed` exactly.
-}
type alias ServerFeed =
    { status : ServerEvents
    , accountId : Maybe String
    }


{-| One card's fade in/out state (`flip`, keyed in `eventAnimations` by
`eventAnimationKey` so it survives independently of `eventsByServer` -- see
`Components.Pages.PostsPage.PostAnimation` for why) plus its move-slide state
(`move`) for `DisplayModeChanged`'s layout-switch animation -- kept as a
_separate_ `UI.Flip.MoveState` (rather than folded into `flip`) so the two
never fight over the same node's `transform` style: `flip`'s opacity/scale
renders on this card's outer wrapper (see `eventAnimationView`), `move`'s
translate renders on a nested inner one.
-}
type alias EventAnimation =
    { host : String
    , event : Event
    , occasion : Occasion
    , flip : UI.Flip.State Msg
    , move : UI.Flip.MoveState Msg
    }


{-| `Model.calendarAnimations`' own per-entry type -- just a `flip` (no
`move`, unlike `EventAnimation`: `Calendar` mode never slides position/size
the way a card layout switch does, it only ever fades in/out, see
`eventsListView`'s own doc) and none of `EventAnimation`'s per-card data,
since there's only ever at most one entry (keyed `calendarAnimationKey`) and
nothing about it varies per-occasion.
-}
type alias CalendarAnimation =
    { flip : UI.Flip.State Msg
    }


{-| Which of `tabsView`'s two tabs is active -- `UpcomingEvents` (the
default) filters by the live current time, refreshed on every `Poll` (see
its own handling below); `EventsAfterDate` filters by a fixed, user-picked
cutoff (`model.endsAfter`), editable via its own `<input type="datetime-local">`.
Persisted to the URL as an `ends_after` query param (see `queryParams`) --
its mere presence/absence on load is what `init` uses to decide which tab to
start on.
-}
type EventsTab
    = UpcomingEvents
    | EventsAfterDate


{-| Which half of `DisplayModeChanged`'s FLIP measurement round-trip (if any)
`GotMeasuredRects` is currently waiting on -- unlike the old `Task.attempt`-based
version (which baked this into the `Msg` itself, via `GotPreModeMeasurements
newMode`/`GotPostModeMeasurements oldRects`'s own arguments), a port's
incoming `Sub` is a single, untargeted `Msg`, so there's nothing to pattern
match on except state carried in the `Model` -- this is that state. See
`measureElementsEffect`/`Ports.measureElements`'s own doc for why a port
(rather than `Browser.Dom.getElement`) measures at all.
-}
type MeasurementPhase
    = NotMeasuring
    | AwaitingOldRects EventsDisplayMode
    | AwaitingNewRects (Dict String Rect)


{-| A card's measured position/size (page coordinates, matching
`Browser.Dom.Element.element`'s own convention) -- the "First"/"Last"
measurement step of FLIP, used both before and after `DisplayModeChanged`
switches `model.mode` (see that branch's own doc for the full recipe).
Deliberately not `Browser.Dom.Element` itself: that type carries `scene`/
`viewport` fields this module never needs, and (more importantly) is what
`Ports.measureElements` exists to avoid depending on `Browser.Dom.getElement`
for at all -- see that port's own doc comment.
-}
type alias Rect =
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    }


{-| `author`, if given, restricts the feed to that user's own events (see
`Components.Events.fetchEvents`) and adds an "Events | <name>" heading
(see `authorHeadingView`) -- `Pages.Events` passes `Nothing`,
`Pages.UsernameOrCustomTab_.Events`/`Pages.User.UserId_.Events` pass their
already-resolved profile `User` paired with the host it was resolved from --
mirrors `Components.Pages.PostsPage.init`'s own `author` param exactly,
including `navKey`/`path` (this module's own URL persistence, see
`pushUrl`, needs the same thing `PostsPage`'s search persistence does) and
`query` (seeding `mode` back out of a `?display=` param, and `tab`/`endsAfter`
back out of a `?ends_after=` one, on load).

A parseable `?ends_after=` starts on the `EventsAfterDate` tab with that
exact cutoff -- already resolved, so this fetches right away, no need to
wait on anything. Without one, this starts on `UpcomingEvents` with
`endsAfter = Nothing` -- deliberately not yet fetching at all (see
`refetchServers`'s own guard) until the `Task.perform GotNow Time.now`
below resolves and supplies a real cutoff; see `Model.endsAfter`'s own doc
for why that matters.

`embeddedPage` is `True` only for `Pages.Home_`'s and
`Components.Pages.UserProfilePage`'s own embedded copies of this model (see
`Model.embeddedPage`'s own doc for why it's tracked at all) -- absent an
explicit `?display=`, it (together with the current
`Shared.UserPreferences.prefersCalendar`) decides `mode`'s own default here,
via `defaultMode`/`Model.defaultDisplayMode`.

`syncsCalendarPreference` is `True` only for `Pages.Home_`'s and `Pages.Events`'
own copies -- see `Model.syncsCalendarPreference`'s own doc.

`availableSyncDestinations` seeds `Model.availableSyncDestinations` directly
-- `Nothing` for every caller except `Components.Pages.UserProfilePage`,
which passes `Just user.eventSyncDestinations` (see that field's own doc).

`fragment` is the raw URL fragment (`Url.fragment`, e.g. from `req.url.fragment`)
-- seeds `Model.pendingCalendarPreviewScroll` alongside `calendarPreview`
itself (see that field's own doc for the full `#calendar-preview-<key>`
round-trip); `Nothing` for `Components.Pages.UserProfilePage`'s two embedded-preview
copies (no `req`/`Url` in scope there to read one back out of, and a small
preview widget restoring its exact scroll position across a full navigation
is far lower value than the standalone `/events`-like pages this actually
matters for).

-}
init : Shared.Model -> Maybe ( String, User ) -> Browser.Navigation.Key -> String -> Dict String String -> Maybe String -> Bool -> Bool -> Maybe (List SyncDestination) -> Maybe CalendarDisplayMode -> Bool -> ( Model, Effect Msg )
init shared author navKey path query fragment embeddedPage syncsCalendarPreference availableSyncDestinations calendarDisplayModeOverride embeddingPageSearchesPosts =
    let
        ( tab, endsAfter ) =
            case Dict.get "ends_after" query |> Maybe.andThen Conversions.posixFromIsoUtcString of
                Just customEndsAfter ->
                    ( EventsAfterDate, Just customEndsAfter )

                Nothing ->
                    ( UpcomingEvents, Nothing )

        computedDefaultDisplayMode : EventsDisplayMode
        computedDefaultDisplayMode =
            defaultMode embeddedPage shared.userPreferences.prefersCalendar

        calendarPreview : Maybe String
        calendarPreview =
            Dict.get "calendar_preview" query

        -- See `Model.pendingCalendarPreviewScroll`'s own doc -- the
        -- `#calendar-preview-<key>` fragment (if any and if it parses)
        -- wins over `calendarPreview` itself as the initial scroll target,
        -- since it's the more specific "exactly where the user was" one.
        pendingCalendarPreviewScroll : Maybe String
        pendingCalendarPreviewScroll =
            calendarPreview
                |> Maybe.map (\key -> Maybe.withDefault key (calendarPreviewKeyFromFragment fragment))

        ( fetchedModel, fetchEffect ) =
            fetchNewServers shared
                { eventsByServer = Dict.empty
                , eventAnimations = Dict.empty
                , calendarAnimations = Dict.empty
                , calendarPreview = calendarPreview
                , pendingCalendarPreviewScroll = pendingCalendarPreviewScroll
                , mode = Dict.get "display" query |> Maybe.andThen displayModeFromParam |> Maybe.withDefault computedDefaultDisplayMode
                , defaultDisplayMode = computedDefaultDisplayMode
                , embeddedPage = embeddedPage
                , syncsCalendarPreference = syncsCalendarPreference
                , measurementPhase = NotMeasuring
                , author = author
                , navKey = navKey
                , path = path
                , tab = tab
                , searchText = Dict.get "search_text" query |> Maybe.withDefault ""
                , searchGeneration = 0
                , endsAfter = endsAfter
                , endsAfterInputGeneration = 0
                , exportPopoverOpen = False
                , copyLinkCopied = False
                , copyLinkGeneration = 0
                , hideStartedOrLongEvents = not (showStartedOrLongEventsByDefault shared)
                , showSyncSources = False
                , showSyncDestinations = False
                , availableSyncDestinations = availableSyncDestinations
                , embeddingPageSearchesPosts = embeddingPageSearchesPosts
                , calendarDisplayModeOverride = calendarDisplayModeOverride
                , pushStatuses = Dict.empty
                }
                |> Tuple.mapFirst syncCalendarAnimations
    in
    ( fetchedModel
      -- Closes any open panel (Accounts, Starred, etc.) unconditionally
      -- on load -- mirrors `Components.Pages.PostsPage.init`'s own
      -- unconditional close, see its doc comment for why `setBreadcrumbsRoot`
      -- alone isn't enough here.
    , Effect.batch
        [ fetchEffect
        , Effect.fromShared Shared.CloseAllPanels
        , setBreadcrumbsRoot shared fetchedModel
        , Task.perform GotNow Time.now |> Effect.fromCmd
        ]
    )


{-| Unlike `Components.Pages.PostsPage.subscriptions`/`Components.Pages.UsersPage.subscriptions`
(whose 30s `Poll` is just a distrustful account-change fallback, see
`PostsPage.fetchNewServers`'s own doc -- normally a no-op), this page's `Poll`
does real work every time on the default `UpcomingEvents` tab: it's what
advances `model.endsAfter` to the live "now" (via `GotNow`) so the listing
keeps dropping events as they pass, which also re-fetches every relevant
server (see `GotNow`/`refetchServers`). 60s (rather than 30s) is deliberately
slower here since that's a real, visible, unavoidable-per-tick network
round-trip rather than a cheap local check -- see `refetchServers`'s own doc
for how the same-account `status`-preserving departure it already has keeps
even this from flickering the list.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 60000 (\_ -> Poll)
        , Ports.elementsMeasured GotMeasuredRects
        , UI.Flip.subscription Animate (List.map .flip (Dict.values model.eventAnimations) ++ List.map .flip (Dict.values model.calendarAnimations))
        , UI.Flip.moveSubscription AnimateMove (List.map .move (Dict.values model.eventAnimations))
        , Ports.calendarEventClicked CalendarEventClicked
        ]



-- UPDATE


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page
(see `Main.notifyPageOfSharedMsg`) into `update`'s `SharedMsg` branch --
mirrors `Components.Pages.PostsPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


{-| Lets a sibling page (`Pages.Home_`, keeping this module's search box in sync with its embedded
`PostsPage`'s own `model.searchText` behind the scenes) feed a search-text change in from outside
exactly as if the user had typed it into this module's own search box -- same
`SearchTextChanged`/`SearchDebounceElapsed` round-trip, same independent debounce timer -- mirrors
`Components.Pages.PostsPage.searchTextChanged` exactly.
-}
searchTextChanged : String -> Msg
searchTextChanged =
    SearchTextChanged


{-| Lets `Components.Pages.UserProfilePage` keep this page's `showSyncSources`
in sync with its own "Sync Sources" section's `syncSourcesExpanded`
toggle -- same "expose a `Bool -> Msg`/`String -> Msg` wrapper, round-trip it
through `update`" convention as `searchTextChanged` itself.
-}
showSyncSourcesChanged : Bool -> Msg
showSyncSourcesChanged =
    ShowSyncSourcesChanged


{-| Like `showSyncSourcesChanged`, for `UserProfilePage`'s "Sync
Destinations" section's `syncDestinationsExpanded` toggle.
-}
showSyncDestinationsChanged : Bool -> Msg
showSyncDestinationsChanged =
    ShowSyncDestinationsChanged


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect Msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    let
        ( newModel, effect ) =
            updateInner shared msg model
    in
    ( newModel
    , Effect.batch
        [ effect
        , setBreadcrumbsRoot shared newModel
        , calendarRenderEffect shared model newModel
        , pendingCalendarPreviewScrollEffect model newModel
        ]
    )


updateInner : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared msg model =
    case msg of
        GotServerEvents frontendHost (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model
                | eventsByServer =
                    Dict.update frontendHost
                        (Maybe.map (\feed -> { feed | status = Loaded (Events.occasionPairs response) }))
                        model.eventsByServer
              }
                |> syncAnimations
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotServerEvents frontendHost (Err _) ->
            ( { model
                | eventsByServer =
                    Dict.update frontendHost (Maybe.map (\feed -> { feed | status = Failed })) model.eventsByServer
              }
                |> syncAnimations
            , Effect.none
            )

        GotNow now ->
            -- Only `UpcomingEvents` ever wants the live clock -- a stale
            -- `Task.perform GotNow Time.now` still in flight from before the
            -- user switched to `EventsAfterDate` (or a fixed `?ends_after=`
            -- on load) must not clobber their fixed cutoff.
            if model.tab == UpcomingEvents then
                refetchServers shared { model | endsAfter = Just now } (relevantServers shared model)

            else
                ( model, Effect.none )

        Poll ->
            if model.tab == UpcomingEvents then
                -- Refreshes the live cutoff first (via `GotNow`, which
                -- itself refetches) rather than just re-fetching with
                -- whatever `endsAfter` was captured last -- otherwise
                -- "upcoming" would silently stop advancing after the
                -- initial load.
                ( model, Task.perform GotNow Time.now |> Effect.fromCmd )

            else
                fetchNewServers shared model

        Animate animMsg ->
            let
                step : String -> { a | flip : UI.Flip.State Msg } -> ( Dict String { a | flip : UI.Flip.State Msg }, List (Cmd Msg) ) -> ( Dict String { a | flip : UI.Flip.State Msg }, List (Cmd Msg) )
                step key anim ( animations, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert key { anim | flip = newFlip } animations, cmd :: accCmds )

                ( newAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.eventAnimations

                ( newCalendarAnimations, calendarCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.calendarAnimations
            in
            ( { model | eventAnimations = newAnimations, calendarAnimations = newCalendarAnimations }
            , Effect.batch (List.map Effect.fromCmd (cmds ++ calendarCmds))
            )

        AnimateMove animMsg ->
            let
                step : String -> EventAnimation -> ( Dict String EventAnimation, List (Cmd Msg) ) -> ( Dict String EventAnimation, List (Cmd Msg) )
                step key anim ( animations, accCmds ) =
                    let
                        ( newMove, cmd ) =
                            UI.Flip.moveAnimate animMsg anim.move
                    in
                    ( Dict.insert key { anim | move = newMove } animations, cmd :: accCmds )

                ( newAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.eventAnimations
            in
            ( { model | eventAnimations = newAnimations }, Effect.batch (List.map Effect.fromCmd cmds) )

        RemoveEvent key ->
            ( { model | eventAnimations = Dict.remove key model.eventAnimations }, Effect.none )

        RemoveCalendarAnimation ->
            ( { model | calendarAnimations = Dict.remove calendarAnimationKey model.calendarAnimations }, Effect.none )

        MoveSettled key ->
            let
                newModel : Model
                newModel =
                    { model
                        | eventAnimations =
                            Dict.update key (Maybe.map (\anim -> { anim | move = { moving = False, style = anim.move.style } })) model.eventAnimations
                    }
            in
            ( newModel, pushUrlWhenIdle newModel )

        SharedMsg subMsg ->
            let
                ( fetchedModel, fetchEffect ) =
                    case subMsg of
                        Shared.AccountsPanelMsg _ ->
                            fetchNewServers shared model

                        -- The Delete button on a card's sync destination row
                        -- (`Shared.RequestDelete`/`Shared.ConfirmOccasionSyncDestinationDelete`,
                        -- see `eventCardView`'s own `onDelete`) resolving --
                        -- mirrors `GotPushResult`'s own Ok branch (re-scoped
                        -- refetch of just `host`'s server), since a
                        -- successful un-sync changes `occasion.syncDestinations`
                        -- behind this already-fetched copy's back the same way.
                        Shared.GotOccasionSyncDestinationDeleteResult host (Ok _) ->
                            case RellmServers.rellmServerForHost shared.accounts.servers host of
                                Just server ->
                                    refetchServers shared model [ server ]

                                Nothing ->
                                    ( model, Effect.none )

                        Shared.CreateNewPanelMsg (CreateNewPanel.GotSaveResult (Ok ( _, createdItem ))) ->
                            applyCreatedItem shared createdItem model

                        _ ->
                            ( model, Effect.none )
            in
            ( fetchedModel, Effect.batch [ Effect.fromShared subMsg, fetchEffect ] )

        DisplayModeChanged newMode ->
            if newMode == model.mode then
                ( model, Effect.none )

            else if newMode == Calendar then
                -- Switching *into* `Calendar` renders instantly, with no
                -- cross-fade at all -- unlike leaving it (below), there's no
                -- good place for the outgoing cards to visually go: they'd
                -- have to collapse away underneath a calendar that's already
                -- occupying their old spot (`calendar-flip-item`'s own
                -- `order: -1`, events.css), which is exactly the "cards
                -- linger below the calendar for a beat" lag this was worth
                -- avoiding. Skips `syncAnimations`/`syncCalendarAnimations`
                -- entirely: `eventAnimations` is cleared outright (no fade,
                -- no `remove` to wait on) and `calendarAnimations` seeds
                -- straight into `UI.Flip.restingState` (already fully
                -- visible/settled, not `enter`'s fade-in). `update`'s own
                -- `calendarRenderEffect` still separately picks up actually
                -- rendering the calendar's contents regardless of this
                -- shortcut.
                let
                    newModel : Model
                    newModel =
                        { model
                            | mode = newMode
                            , eventAnimations = Dict.empty
                            , calendarAnimations = Dict.singleton calendarAnimationKey { flip = UI.Flip.restingState }
                        }

                    preferenceEffect : Effect Msg
                    preferenceEffect =
                        if model.syncsCalendarPreference then
                            Effect.fromShared (Shared.UserPreferencesMsg (UserPreferences.SetPrefersCalendar True))

                        else
                            Effect.none
                in
                ( newModel, Effect.batch [ pushUrl newModel, preferenceEffect ] )

            else if model.mode == Calendar then
                -- Switching *out of* `Calendar` still cross-fades, same as
                -- ever -- `Calendar` isn't a card layout, so there's nothing
                -- to measure/slide via `measureElementsEffect`'s FLIP
                -- round-trip (that's still exactly what the `else` branch
                -- below handles, for a switch among `VerticalList`/`Grid`/
                -- `HorizontalList`). `syncAnimations` fades every real card
                -- back in, `syncCalendarAnimations` fades the calendar view
                -- itself out -- see `eventsListView`'s own doc for how the
                -- two dicts render as one combined, cross-fading list. Also,
                -- if `model.syncsCalendarPreference` (`Pages.Home_`'s/
                -- `Pages.Events`'s own copies only), persists this switch out
                -- of `Calendar` as `Shared.UserPreferences.prefersCalendar`
                -- -- see that field's own doc.
                let
                    newModel : Model
                    newModel =
                        { model | mode = newMode }
                            |> syncAnimations
                            |> syncCalendarAnimations

                    preferenceEffect : Effect Msg
                    preferenceEffect =
                        if model.syncsCalendarPreference then
                            Effect.fromShared (Shared.UserPreferencesMsg (UserPreferences.SetPrefersCalendar False))

                        else
                            Effect.none
                in
                ( newModel, Effect.batch [ pushUrl newModel, preferenceEffect ] )

            else
                ( { model | measurementPhase = AwaitingOldRects newMode }
                , measureElementsEffect (List.map Tuple.first (visibleAnimations model))
                )

        GotMeasuredRects value ->
            case Decode.decodeValue rectsDecoder value of
                Err _ ->
                    applyMeasurementFailure model

                Ok rects ->
                    case model.measurementPhase of
                        NotMeasuring ->
                            -- A stray/late result with nothing pending -- ignore.
                            ( model, Effect.none )

                        AwaitingOldRects newMode ->
                            let
                                newModel : Model
                                newModel =
                                    { model | mode = newMode, measurementPhase = AwaitingNewRects rects }
                            in
                            ( newModel, Task.attempt (\_ -> ReadyToMeasureNew) Dom.getViewport |> Effect.fromCmd )

                        AwaitingNewRects oldRects ->
                            let
                                startMoveFor : String -> Rect -> Dict String EventAnimation -> Dict String EventAnimation
                                startMoveFor key oldRect animations =
                                    case ( Dict.get key rects, Dict.get key animations ) of
                                        ( Just newRect, Just anim ) ->
                                            let
                                                delta : ( Float, Float )
                                                delta =
                                                    ( oldRect.x - newRect.x, oldRect.y - newRect.y )

                                                scale : ( Float, Float )
                                                scale =
                                                    ( oldRect.width / newRect.width, oldRect.height / newRect.height )
                                            in
                                            Dict.insert key { anim | move = UI.Flip.startMoveScaled (MoveSettled key) delta scale anim.move } animations

                                        _ ->
                                            animations

                                newModel : Model
                                newModel =
                                    { model
                                        | eventAnimations = Dict.foldl startMoveFor model.eventAnimations oldRects
                                        , measurementPhase = NotMeasuring
                                    }
                            in
                            ( newModel, pushUrlWhenIdle newModel )

        ReadyToMeasureNew ->
            case model.measurementPhase of
                AwaitingNewRects oldRects ->
                    ( model, measureElementsEffect (Dict.keys oldRects) )

                _ ->
                    -- Nothing pending anymore (e.g. superseded by another
                    -- `DisplayModeChanged` in the meantime) -- nothing to do.
                    ( model, Effect.none )

        TabChanged UpcomingEvents ->
            if model.tab == UpcomingEvents then
                ( model, Effect.none )

            else
                let
                    newModel : Model
                    newModel =
                        { model | tab = UpcomingEvents }
                in
                ( newModel
                , Effect.batch
                    [ Task.perform GotNow Time.now |> Effect.fromCmd
                    , pushUrl newModel
                    ]
                )

        TabChanged EventsAfterDate ->
            if model.tab == EventsAfterDate then
                ( model, Effect.none )

            else
                case shared.userPreferences.eventsAfter of
                    Just preferredEndsAfter ->
                        -- The user has a remembered cutoff from a previous
                        -- session (see `Shared.UserPreferences.eventsAfter`'s
                        -- own doc) -- start the picker there instead of
                        -- wherever `UpcomingEvents`' live clock last left
                        -- `endsAfter`, and (since the cutoff is actually
                        -- changing this time) refetch with it.
                        let
                            ( refetchedModel, refetchEffect ) =
                                refetchServers shared { model | tab = EventsAfterDate, endsAfter = Just preferredEndsAfter } (relevantServers shared model)
                        in
                        ( refetchedModel, Effect.batch [ refetchEffect, pushUrl refetchedModel ] )

                    Nothing ->
                        -- `endsAfter` itself isn't changing (this just starts the
                        -- picker off wherever `UpcomingEvents`' live clock last left
                        -- it) so there's nothing to refetch, just the tab/URL.
                        let
                            newModel : Model
                            newModel =
                                { model | tab = EventsAfterDate }
                        in
                        ( newModel, pushUrl newModel )

        EndsAfterInputChanged raw ->
            case SharedTime.posixFromDateTimeLocalInput shared.time.browserTimeZone.zone raw of
                Nothing ->
                    ( model, Effect.none )

                Just newEndsAfter ->
                    let
                        generation : Int
                        generation =
                            model.endsAfterInputGeneration + 1
                    in
                    ( { model | tab = EventsAfterDate, endsAfter = Just newEndsAfter, endsAfterInputGeneration = generation }
                    , Process.sleep 500
                        |> Task.perform (\_ -> EndsAfterDebounceElapsed generation)
                        |> Effect.fromCmd
                    )

        EndsAfterDebounceElapsed generation ->
            if generation == model.endsAfterInputGeneration then
                let
                    ( refetchedModel, refetchEffect ) =
                        refetchServers shared model (relevantServers shared model)
                in
                ( refetchedModel
                , Effect.batch
                    [ refetchEffect
                    , pushUrl refetchedModel
                    , Effect.fromShared (Shared.UserPreferencesMsg (UserPreferences.SetEventsAfter model.endsAfter))
                    ]
                )

            else
                -- A later edit already bumped `endsAfterInputGeneration`
                -- past this timer's -- it's stale, ignore it.
                ( model, Effect.none )

        SearchTextChanged text ->
            let
                generation : Int
                generation =
                    model.searchGeneration + 1
            in
            ( { model | searchText = text, searchGeneration = generation }
            , Process.sleep 311
                |> Task.perform (\_ -> SearchDebounceElapsed generation)
                |> Effect.fromCmd
            )

        SearchDebounceElapsed generation ->
            if generation == model.searchGeneration then
                applySearchChange shared model

            else
                -- A later edit (or ClearSearchClicked) already bumped
                -- searchGeneration past this timer's -- it's stale, ignore it.
                ( model, Effect.none )

        ClearSearchClicked ->
            applySearchChange shared { model | searchText = "", searchGeneration = model.searchGeneration + 1 }

        HideStartedEventsToggled ->
            ( { model | hideStartedOrLongEvents = not model.hideStartedOrLongEvents } |> syncAnimations, Effect.none )

        ShowSyncSourcesChanged showSyncSources ->
            ( { model | showSyncSources = showSyncSources }, Effect.none )

        ShowSyncDestinationsChanged showSyncDestinations ->
            ( { model | showSyncDestinations = showSyncDestinations }, Effect.none )

        ExportClicked ->
            ( { model | exportPopoverOpen = not model.exportPopoverOpen }, Effect.none )

        ExportPopoverClosed ->
            ( { model | exportPopoverOpen = False }, Effect.none )

        CopyLinkClicked ->
            let
                generation : Int
                generation =
                    model.copyLinkGeneration + 1
            in
            ( { model | copyLinkCopied = True, copyLinkGeneration = generation }
            , Effect.batch
                [ Ports.copyToClipboard (icsUrl shared model) |> Effect.fromCmd
                , Process.sleep 5000
                    |> Task.perform (\_ -> CopyLinkCopyTimeoutElapsed generation)
                    |> Effect.fromCmd
                ]
            )

        CopyLinkCopyTimeoutElapsed generation ->
            if generation == model.copyLinkGeneration then
                ( { model | copyLinkCopied = False }, Effect.none )

            else
                ( model, Effect.none )

        PushOccasionToDestination host occasionId eventSyncDestinationId ->
            let
                key : String
                key =
                    pushStatusKey occasionId eventSyncDestinationId

                maybeAccountServer : ( Maybe String, String )
                maybeAccountServer =
                    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId, host )
            in
            ( { model | pushStatuses = Dict.insert key Submitting model.pushStatuses }
            , Events.syncOccasion shared.accounts maybeAccountServer occasionId eventSyncDestinationId
                |> Task.attempt (GotPushResult host occasionId eventSyncDestinationId)
                |> Effect.fromCmd
            )

        GotPushResult host occasionId eventSyncDestinationId result ->
            let
                key : String
                key =
                    pushStatusKey occasionId eventSyncDestinationId

                clearedModel : Model
                clearedModel =
                    { model | pushStatuses = Dict.remove key model.pushStatuses }
            in
            case result of
                Ok ( maybeAccountsPanelMsg, _ ) ->
                    let
                        ( refetchedModel, refetchEffect ) =
                            case RellmServers.rellmServerForHost shared.accounts.servers host of
                                Just server ->
                                    refetchServers shared clearedModel [ server ]

                                Nothing ->
                                    ( clearedModel, Effect.none )
                    in
                    ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

                Err err ->
                    ( { clearedModel | pushStatuses = Dict.insert key (SubmitFailed (AccountsPanel.grpcErrorToString err)) clearedModel.pushStatuses }
                    , Effect.none
                    )

        CalendarEventClicked key ->
            let
                newModel : Model
                newModel =
                    { model | calendarPreview = Just key, pendingCalendarPreviewScroll = Nothing }
            in
            ( newModel, Effect.batch [ scrollToCalendarPreviewCard 60 key, pushUrl newModel ] )

        CalendarPreviewClosed ->
            let
                newModel : Model
                newModel =
                    { model | calendarPreview = Nothing, pendingCalendarPreviewScroll = Nothing }
            in
            ( newModel, pushUrl newModel )

        GotCalendarPreviewScrollTarget (Ok target) ->
            ( { model | pendingCalendarPreviewScroll = Nothing }
            , Ports.scrollElementLeft
                (Encode.object
                    [ ( "id", Encode.string calendarPreviewStripDomId )
                    , ( "left", Encode.float (max 0 target) )
                    ]
                )
                |> Effect.fromCmd
            )

        GotCalendarPreviewScrollTarget (Err _) ->
            ( { model | pendingCalendarPreviewScroll = Nothing }, Effect.none )

        CalendarPreviewCardNavigated key ->
            ( model, pushCalendarPreviewHash model key )


{-| `GotMeasuredRects`'s fallback for a payload that failed to decode (should
never actually happen -- `Ports.measureElements`'s JS side always sends a
well-formed array -- but mirrors `PostId_.GotScrollTarget (Err _)`'s "give
up silently" convention regardless): still applies a pending mode switch if
`model.measurementPhase` had one in flight, just with no slide animation,
rather than leaving the click seemingly do nothing.
-}
applyMeasurementFailure : Model -> ( Model, Effect Msg )
applyMeasurementFailure model =
    case model.measurementPhase of
        NotMeasuring ->
            ( model, Effect.none )

        AwaitingOldRects newMode ->
            let
                newModel : Model
                newModel =
                    { model | mode = newMode, measurementPhase = NotMeasuring }
            in
            ( newModel, pushUrlWhenIdle newModel )

        AwaitingNewRects _ ->
            let
                newModel : Model
                newModel =
                    { model | measurementPhase = NotMeasuring }
            in
            ( newModel, pushUrlWhenIdle newModel )



-- URL PERSISTENCE


{-| `grid`/`row`, sent/read as a `?display=` URL query param --
`VerticalList` (the default) round-trips to/from its absence entirely,
mirroring `PostsPage.postContextParam`'s own default-omission convention.
-}
displayModeParam : EventsDisplayMode -> String
displayModeParam mode =
    case mode of
        Grid ->
            "grid"

        HorizontalList ->
            "row"

        VerticalList ->
            "list"

        Calendar ->
            "calendar"


{-| Case-insensitive inverse of `displayModeParam` -- mirrors
`PostsPage.postContextFromParam`.
-}
displayModeFromParam : String -> Maybe EventsDisplayMode
displayModeFromParam param =
    case String.toLower param of
        "grid" ->
            Just Grid

        "row" ->
            Just HorizontalList

        "list" ->
            Just VerticalList

        "calendar" ->
            Just Calendar

        _ ->
            Nothing


{-| The `EventsDisplayMode` a copy of this model defaults to absent an
explicit `?display=` -- `Calendar` if `prefersCalendar` (the current
`Shared.UserPreferences.prefersCalendar`) is set, regardless of `embeddedPage`
(every copy -- including ones that never themselves write that preference,
see `Model.syncsCalendarPreference` -- still reads it back here); otherwise
`HorizontalList` for `Pages.Home_`'s own embedded copy (`embeddedPage = True`),
`VerticalList` everywhere else. Only ever called once, from `init` -- see
`Model.defaultDisplayMode`'s own doc for why the result is cached there rather
than re-derived later (`prefersCalendar` can itself change mid-session).
-}
defaultMode : Bool -> Bool -> EventsDisplayMode
defaultMode embeddedPage prefersCalendar =
    if prefersCalendar then
        Calendar

    else if embeddedPage then
        HorizontalList

    else
        VerticalList


{-| Every query param this page persists, read fresh off `model` -- `display`
(see `displayModeParam`; omitted while `model.mode` is still exactly
`model.defaultDisplayMode`, the default `init` seeded it with -- see that
field's own doc), `search_text`
(mirrors `PostsPage.pushSearchUrl`'s own omit-when-blank convention),
`ends_after` (a standard `YYYY-MM-DDTHH:mm:ssZ` UTC timestamp, via
`Shared.Conversions.isoUtcString`, only while `EventsAfterDate` is the
active tab; `UpcomingEvents` -- the default -- omits it entirely, same
"round-trip to/from absence" convention `display` already uses for its own
default), and `calendar_preview` (`model.calendarPreview`'s own key, omitted
whenever that's `Nothing` i.e. the modal is closed -- see that field's own
doc). Built as one combined list (rather than each concern pushing its
own `replaceUrl` independently) because
`Browser.Navigation.replaceUrl`/`Url.Builder.toQuery` replace the _whole_
query string -- independent single-param pushes would each silently wipe
out whatever the others had just set.
-}
queryParams : Model -> List Url.Builder.QueryParameter
queryParams model =
    (if model.mode == model.defaultDisplayMode then
        []

     else
        [ Url.Builder.string "display" (displayModeParam model.mode) ]
    )
        ++ (if String.isEmpty (String.trim model.searchText) then
                []

            else
                [ Url.Builder.string "search_text" model.searchText ]
           )
        ++ (case ( model.tab, model.endsAfter ) of
                ( EventsAfterDate, Just endsAfter ) ->
                    [ Url.Builder.string "ends_after" (Conversions.isoUtcString endsAfter) ]

                _ ->
                    []
           )
        ++ (case model.calendarPreview of
                Just key ->
                    [ Url.Builder.string "calendar_preview" key ]

                Nothing ->
                    []
           )


{-| `pushUrl`, but only once every card has actually finished its
`DisplayModeChanged` slide (`Effect.none` otherwise) -- deliberately _not_
fired the instant `model.mode` itself changes (`GotPreModeMeasurements`'s
`Ok` branch used to call this directly there), because that `replaceUrl`
call triggers `Main.elm`'s own `ChangedUrl`, which -- even though it doesn't
re-init this page for a query-only change -- still forces a full top-level
`view`/diff/patch pass. Landing that extra render in the one genuinely
vulnerable window this FLIP recipe has (after `model.mode` flips but before
`GotPostModeMeasurements` has actually applied each card's invert transform,
during which every card is still sitting at its plain, un-inverted resting
position) gave the browser an extra chance to actually paint that
in-between frame -- visible as the whole layout "glitching" to its final
position before the slide-back-into-place ever played. Deferring the URL
write until nothing is `moving` removes that extra render from the window
entirely, rather than just narrowing it. Every branch that can leave
`model.mode` changed with nothing left to animate (a failed measurement, or
a mode switch with no cards to move at all) calls this too, so the URL
still ends up correct even when there's no slide to wait on.

Tab/`endsAfter` changes have no such animation to race, so `TabChanged`/
`EndsAfterInputChanged` call `pushUrl` directly instead.

-}
pushUrlWhenIdle : Model -> Effect Msg
pushUrlWhenIdle model =
    if List.any (\anim -> anim.move.moving) (Dict.values model.eventAnimations) then
        Effect.none

    else
        pushUrl model


{-| Persists `queryParams model` to the URL via `replaceUrl` (not `pushUrl`
the navigation function -- switching layouts/tabs/dates shouldn't spam
browser history) -- mirrors `PostsPage.pushSearchUrl`.
-}
pushUrl : Model -> Effect Msg
pushUrl model =
    Browser.Navigation.replaceUrl model.navKey (model.path ++ Url.Builder.toQuery (queryParams model))
        |> Effect.fromCmd


{-| The URL fragment `calendarPreviewCardView`'s own `onClick` writes --
`"calendar-preview-" ++ key`, parsed back out by `calendarPreviewKeyFromFragment`.
Kept as one shared prefix constant (rather than each side hand-typing it) so
`init`'s own parsing and `CalendarPreviewCardNavigated`'s own writing can't
quietly drift apart -- mirrors `Pages.Messages`' own `"message-"` prefix
convention for `#message-<id>`.
-}
calendarPreviewFragmentPrefix : String
calendarPreviewFragmentPrefix =
    "calendar-preview-"


{-| Inverse of `calendarPreviewFragmentPrefix`'s own construction -- `Nothing`
for a fragment that isn't one of these (including no fragment at all), same
"give up silently" convention as everywhere else a URL is parsed back into
state in this module.
-}
calendarPreviewKeyFromFragment : Maybe String -> Maybe String
calendarPreviewKeyFromFragment fragment =
    fragment
        |> Maybe.andThen
            (\value ->
                if String.startsWith calendarPreviewFragmentPrefix value then
                    Just (String.dropLeft (String.length calendarPreviewFragmentPrefix) value)

                else
                    Nothing
            )


{-| `CalendarPreviewCardNavigated`'s own effect -- `replaceUrl`s `queryParams model`
(so `calendar_preview` itself is left exactly as-is, still the originally-tapped
key) plus a `#calendar-preview-<key>` fragment for whichever card was just
clicked, _before_ that click's own `<a href>` navigation runs -- see the `Msg`'s
own doc for why the ordering between the two is safe to rely on. Deliberately
its own function rather than a `pushUrl` variant that always includes the
fragment: every other caller of `pushUrl` (`CalendarPreviewClosed`, tab/mode/search
changes, ...) should keep dropping any stale fragment a previous click left
behind, not preserve it forever.
-}
pushCalendarPreviewHash : Model -> String -> Effect Msg
pushCalendarPreviewHash model key =
    Browser.Navigation.replaceUrl model.navKey
        (model.path ++ Url.Builder.toQuery (queryParams model) ++ "#" ++ calendarPreviewFragmentPrefix ++ key)
        |> Effect.fromCmd


{-| Mirrors `Components.Pages.PostsPage.relevantServers` exactly: every
enabled server for an unfiltered feed (`Pages.Events`), or just `author`'s own
resolved host once there is one (`Pages.UsernameOrCustomTab_.Events`/
`Pages.User.UserId_.Events`).
-}
relevantServers : Shared.Model -> Model -> List RellmServer
relevantServers shared model =
    case model.author of
        Just ( host, _ ) ->
            RellmServers.rellmServerForHost shared.accounts.servers host
                |> Maybe.map List.singleton
                |> Maybe.withDefault []

        Nothing ->
            AccountsPanel.enabledServers shared.accounts


{-| `calendarLookbackDays`'s fallback -- 14 days (2 weeks), used whenever
`shared.accounts`' main server hasn't set `event_settings.calendar_lookback_days`
(or hasn't finished connecting yet) -- the same default `server_configuration.proto`
itself documents for that field.
-}
calendarLookbackDaysDefault : Int
calendarLookbackDaysDefault =
    14


{-| How many days before "now" `queryEndsAfter` widens `UpcomingEvents`-tab
queries, so `Calendar` mode has something to actually show for the days
before today -- reads `shared.accounts`' main server's own
`event_settings.calendar_lookback_days` (mirroring
`Shared.AccountsPanel.recommendedFederatedServers`'s own
`serverForHost .. mainFrontendHost |> Maybe.map configurationOf` idiom),
falling back to `calendarLookbackDaysDefault` if that server, its
configuration, or `eventSettings` itself isn't known yet.
-}
calendarLookbackDays : Shared.Model -> Int
calendarLookbackDays shared =
    RellmServers.rellmServerForHost shared.accounts.servers shared.accounts.mainFrontendHost
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .eventSettings
        |> Maybe.andThen .calendarLookbackDays
        |> Maybe.withDefault calendarLookbackDaysDefault


{-| The cutoff actually sent as `Components.Events.fetchEvents`' own
`endsAfter` -- widens `endsAfter` back `calendarLookbackDays` while
`UpcomingEvents` is the active tab, _regardless_ of `model.mode`: switching
`mode` (`DisplayModeChanged`) never itself refetches, so a query scoped to
just `Calendar`-mode-only would leave `Calendar` with nothing to show for the
days before today until the next unrelated refetch happened to land after
the switch. Querying this broadly at all times instead means `Calendar` can
show its lookback the instant it's switched to -- see `hiddenAsEnded` for the
client-side filter that keeps those extra past occasions out of every
non-`Calendar` layout in the meantime. `EventsAfterDate`'s own fixed,
user-picked cutoff is never widened -- "look back from today" has no meaning
against a cutoff that isn't "today" to begin with.
-}
queryEndsAfter : Shared.Model -> Model -> Time.Posix -> Time.Posix
queryEndsAfter shared model endsAfter =
    if model.tab == UpcomingEvents then
        Time.millisToPosix (Time.posixToMillis endsAfter - calendarLookbackDays shared * 24 * 60 * 60 * 1000)

    else
        endsAfter


{-| The `GetEvents` fetch (as an `Effect`, ready to batch/return directly)
for one `server`, using `endsAfter` (the already-unwrapped `model.endsAfter`,
widened via `queryEndsAfter` -- see its own doc -- before actually being sent
-- see `refetchServers`'s own guard for why this never runs while that's
still `Nothing`) -- mirrors `Components.Pages.PostsPage.refetchServers`'s
inline `fetchEffect`, just factored out since `GotNow` also needs to kick
every relevant server's fetch off again once a real cutoff lands.
-}
fetchServerEffect : Shared.Model -> Model -> Time.Posix -> RellmServer -> Effect Msg
fetchServerEffect shared model endsAfter server =
    Events.fetchEvents
        shared.accounts
        ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost |> Maybe.map .userId
        , server.frontendHost
        )
        (model.author |> Maybe.map (Tuple.second >> .id))
        model.searchText
        (queryEndsAfter shared model endsAfter)
        |> Task.attempt (GotServerEvents server.frontendHost)
        |> Effect.fromCmd


{-| Mirrors `Components.Pages.PostsPage.refetchServers`, with one deliberate
departure: a server already `Loaded` under the _same_ acting account keeps
showing its last-known events (`status` untouched) while the re-fetch is in
flight, rather than being reset to `Loading` first. `Loading` isn't rendered
as its own state anywhere in this module -- the only thing it actually does
is drop that server out of `syncAnimations`' `currentEvents`, which reads as
every one of its events fading out and back in a moment later. That's exactly
what `GotNow`'s poll-driven "advance the live cutoff" re-fetch was causing
every 60s on the default `UpcomingEvents` tab, with no actual data change to
justify it. A genuinely new server, or one whose acting account just changed
(sign-in/out), still resets to `Loading` -- its previous events (fetched
under a different or no account) are stale/invalid, not just "not yet
refreshed," so they should disappear rather than linger. Drops any
already-fetched server that's no longer `relevantServers`. A no-op (nothing
touched, no fetch fired) while `model.endsAfter` is still `Nothing` -- see
its own doc comment for why this page must never fetch before that's
resolved.
-}
refetchServers : Shared.Model -> Model -> List RellmServer -> ( Model, Effect Msg )
refetchServers shared model serversToFetch =
    case model.endsAfter of
        Nothing ->
            ( model, Effect.none )

        Just endsAfter ->
            let
                enabledServers : List RellmServer
                enabledServers =
                    relevantServers shared model

                currentAccountId : RellmServer -> Maybe String
                currentAccountId server =
                    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost
                        |> Maybe.map RellmAccounts.rellmAccountId

                prunedEventsByServer : Dict String ServerFeed
                prunedEventsByServer =
                    Dict.filter (\host _ -> List.member host (List.map .frontendHost enabledServers)) model.eventsByServer

                markServer : RellmServer -> Dict String ServerFeed -> Dict String ServerFeed
                markServer server dict =
                    let
                        accountId : Maybe String
                        accountId =
                            currentAccountId server

                        statusIfSameAccount : Maybe ServerEvents
                        statusIfSameAccount =
                            Dict.get server.frontendHost dict
                                |> Maybe.andThen
                                    (\feed ->
                                        if feed.accountId == accountId then
                                            Just feed.status

                                        else
                                            Nothing
                                    )
                    in
                    Dict.insert server.frontendHost
                        { status = Maybe.withDefault Loading statusIfSameAccount, accountId = accountId }
                        dict
            in
            ( { model
                | eventsByServer =
                    List.foldl markServer prunedEventsByServer serversToFetch
              }
            , Effect.batch (List.map (fetchServerEffect shared model endsAfter) serversToFetch)
            )
                |> Tuple.mapFirst syncAnimations


{-| Re-fetches every relevant server (unconditionally -- unlike
`fetchNewServers`, a changed search has to override every already-Loaded
feed, not just servers whose acting account changed) and persists the new
`searchText` to the URL -- mirrors `Components.Pages.PostsPage.applySearchChange`
exactly. The single path `SearchDebounceElapsed`/`ClearSearchClicked` both
funnel through. A no-op fetch-wise (via `refetchServers`' own guard) while
`model.endsAfter` is still `Nothing`, same as every other fetch on this page.
-}
applySearchChange : Shared.Model -> Model -> ( Model, Effect Msg )
applySearchChange shared model =
    let
        ( refetchedModel, refetchEffect ) =
            refetchServers shared model (relevantServers shared model)
    in
    ( refetchedModel, Effect.batch [ refetchEffect, pushUrl refetchedModel ] )


{-| Reacts to `Shared.CreateNewPanel`'s own `GotSaveResult` succeeding --
splices a freshly-created `CreateNewPanel.CreatedEvent` straight into this
page's already-fetched `eventsByServer` (so the creator sees their own new
event immediately, no round-trip needed) rather than waiting on the next
`Poll`/account-change refetch to surface it -- `syncAnimations` still applies
its usual `hiddenAsStarted`/`hiddenAsLong` filtering on top, same as any other
fetch result. Mirrors `Components.Pages.PostsPage.applyCreatedItem` exactly,
just over `(Event, Occasion)` pairs instead of `Post`s: ignored entirely
for a `CreatedPost` (irrelevant here -- `PostsPage` handles that half), a host
that isn't one of `relevantServers`, or `model.tab == EventsAfterDate` (an
explicit past-cutoff view a just-created "now" event has no business
appearing under). While there's active search text, falls back to
`applySearchChange`'s own full re-fetch instead, since a locally-spliced-in
event wouldn't actually match the search server-side.
-}
applyCreatedItem : Shared.Model -> CreateNewPanel.CreatedItem -> Model -> ( Model, Effect Msg )
applyCreatedItem shared createdItem model =
    case createdItem of
        CreateNewPanel.CreatedPost _ _ ->
            ( model, Effect.none )

        CreateNewPanel.CreatedEvent host event ->
            if model.tab == UpcomingEvents && List.member host (List.map .frontendHost (relevantServers shared model)) then
                if String.isEmpty (String.trim model.searchText) then
                    ( { model
                        | eventsByServer =
                            Dict.update host (Maybe.map (\feed -> { feed | status = prependEvent event feed.status })) model.eventsByServer
                      }
                        |> syncAnimations
                    , Effect.none
                    )

                else
                    applySearchChange shared model

            else
                ( model, Effect.none )


prependEvent : Event -> ServerEvents -> ServerEvents
prependEvent event status =
    case status of
        Loaded pairs ->
            Loaded (List.map (\occasion -> ( event, occasion )) event.occasions ++ pairs)

        _ ->
            status


{-| Mirrors `Components.Pages.PostsPage.fetchNewServers` exactly: same
drop-stale-servers/re-fetch-on-account-change/poll-fallback approach, just
against `GetEvents` instead of `GetPosts`.
-}
fetchNewServers : Shared.Model -> Model -> ( Model, Effect Msg )
fetchNewServers shared model =
    let
        currentAccountId : RellmServer -> Maybe String
        currentAccountId server =
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost
                |> Maybe.map RellmAccounts.rellmAccountId

        serversToFetch : List RellmServer
        serversToFetch =
            relevantServers shared model
                |> List.filter
                    (\server ->
                        case Dict.get server.frontendHost model.eventsByServer of
                            Nothing ->
                                True

                            Just feed ->
                                feed.accountId /= currentAccountId server
                    )
    in
    refetchServers shared model serversToFetch


{-| Mirrors `Components.Pages.PostsPage.setBreadcrumbsRoot` exactly, keyed
off this feed's own `author` -- including always being `Effect.none` for an
embedded copy (`model.embeddedPage`), see that doc for why.
-}
setBreadcrumbsRoot : Shared.Model -> Model -> Effect Msg
setBreadcrumbsRoot shared model =
    if model.embeddedPage then
        Effect.none

    else
        let
            ( root, host ) =
                case model.author of
                    Just ( authorHost, user ) ->
                        ( Breadcrumbs.FromUser user, authorHost )

                    Nothing ->
                        ( Breadcrumbs.FromServerHost shared.accounts.mainFrontendHost, shared.accounts.mainFrontendHost )
        in
        if shared.breadcrumbs.root == Just root then
            Effect.none

        else
            Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot root host []))



-- ANIMATION


{-| Identifies one `(host, Occasion)` pair independently of which server
fetched it, for `eventAnimations` -- also used verbatim (prefixed) as the
card's DOM `id`, so `DisplayModeChanged`'s FLIP measurement can look the same
element back up after a layout switch. Mirrors `PostsPage.postAnimationKey`,
just keyed on the `Occasion`'s own `Post` id (this listing's own unit,
see the module doc) rather than `Post.id` directly.
-}
eventAnimationKey : String -> Occasion -> String
eventAnimationKey host occasion =
    host ++ "@" ++ (occasion.post |> Maybe.map .id |> Maybe.withDefault "")


eventCardDomId : String -> String
eventCardDomId key =
    "event-card-" ++ key


pushStatusKey : String -> String -> String
pushStatusKey occasionId eventSyncDestinationId =
    occasionId ++ "|" ++ eventSyncDestinationId


{-| Whether `occasion` has already started as of `model.endsAfter` -- only
ever `True` while `UpcomingEvents` is the active tab, since that's the only
tab whose `endsAfter` _is_ the live "now" (kept fresh by `GotNow`/`Poll`, see
their own docs); `EventsAfterDate`'s fixed cutoff isn't "now" in that sense,
so this is unconditionally `False` there regardless of `occasion`'s own
timing. Compares `occasion`'s own start time via `Events.occasionStartsOrEndsAt`
(the same field `visibleAnimations` already sorts by). Independent of
`Model.hideStartedUpcomingOrLongEvents` itself -- see `hiddenAsStarted` (the actual
filter predicate) and `anyStartedEvents` (whether `hideStartedOrLongButtonView` has
anything to offer at all) for the two things that flag/count actually feed.
-}
occasionHasStarted : Model -> Occasion -> Bool
occasionHasStarted model occasion =
    case ( model.endsAfter, Events.occasionStartsOrEndsAt occasion ) of
        ( Just now, Just startsAt ) ->
            Time.posixToMillis startsAt <= Time.posixToMillis now

        _ ->
            False


{-| Whether `occasion` has already ended as of `model.endsAfter` -- mirrors
`occasionHasStarted` exactly, just against `Events.occasionEndsOrStartsAt`
(the field that prefers `endsAt`) instead of `occasionStartsOrEndsAt`. Only
ever relevant while `UpcomingEvents` is active: `queryEndsAfter` is the only
thing that ever asks a server for an already-ended occasion in the first
place (widening that tab's query back `calendarLookbackDays` for `Calendar`
mode's sake), so this is what `hiddenAsEnded` reads to keep those extra
occasions out of every other layout.
-}
occasionHasEnded : Model -> Occasion -> Bool
occasionHasEnded model occasion =
    case ( model.endsAfter, Events.occasionEndsOrStartsAt occasion ) of
        ( Just now, Just endsAt ) ->
            Time.posixToMillis endsAt <= Time.posixToMillis now

        _ ->
            False


{-| Whether `occasion` should be treated as absent from `syncAnimations`' own
`currentEvents` by the "hide started events" filter (see
`Model.hideStartedUpcomingOrLongEvents`/`hideStartedOrLongButtonView`) --
`occasionHasStarted`, gated on the filter actually being on, so an event
crossing its own start time mid-session fades out on the very next poll
(`refetchServers` already calls `syncAnimations`), same as
`HideStartedEventsToggled` fades the whole already-started set out/in on
toggle. Only ever called from `syncAnimations`' own non-`Calendar` branch --
`calendarEvents` deliberately never calls this (see its own doc): in
`Calendar` mode the same toggle means "hide long occasions" (`hiddenAsLong`)
instead, a genuinely different filter, not this one extended to cover
`Calendar` too.
-}
hiddenAsStarted : Model -> Occasion -> Bool
hiddenAsStarted model occasion =
    model.hideStartedOrLongEvents && occasionHasStarted model occasion


{-| Whether `occasion` should be treated as absent from `syncAnimations`' own
`currentEvents` because it's already ended -- unlike `hiddenAsStarted`, not
gated on any toggle: `queryEndsAfter` widens every `UpcomingEvents`-tab query
`calendarLookbackDays` back regardless of `model.mode` (see its own doc for
why), so every non-`Calendar` layout needs this to claw back out the past,
already-ended occasions that widening pulled in purely for `Calendar` mode's
benefit -- restoring the pre-lookback "only ever shows events that haven't
ended" behavior everywhere except `Calendar` itself.
-}
hiddenAsEnded : Model -> Occasion -> Bool
hiddenAsEnded model occasion =
    model.mode /= Calendar && occasionHasEnded model occasion


{-| Whether any currently `Loaded` occasion is something
`model.hideStartedUpcomingOrLongEvents` could actually hide -- what that
means depends on `model.mode`, same as the toggle itself (see
`hiddenAsStarted`/`hiddenAsLong`'s own docs): `occasionIsLong` while
`model.mode == Calendar`, `occasionHasStarted` without already being
`hiddenAsEnded` everywhere else. `view` only renders
`hideStartedOrLongButtonView` when this is `True` (on top of its own
`UpcomingEvents`-only gate), so the button itself never appears with nothing
for it to actually hide -- without the `Calendar`-mode branch, a listing made
up entirely of not-yet-started multi-day events would hide the button and
leave the toggle permanently stuck on its `init` default, with no way to turn
it off. The `hiddenAsEnded` exclusion on the non-`Calendar` branch keeps
`queryEndsAfter`'s lookback occasions that are _only_ ever shown to
`Calendar` mode (already long since started, and already unconditionally
filtered from every non-`Calendar` layout regardless of this toggle -- see
`hiddenAsEnded`'s own doc) from making the button falsely claim there's
something left to hide while looking at, say, `Grid`. Deliberately reads
straight off `model.eventsByServer` rather than
`model.eventAnimations`/`visibleAnimations` -- once the filter is on, a
started occasion is exactly what `syncAnimations` excludes from (or fades out
of) that dict, so checking there instead would make the button disappear the
moment it successfully hid everything, rather than staying available to
toggle back.
-}
anyStartedEvents : Model -> Bool
anyStartedEvents model =
    model.eventsByServer
        |> Dict.values
        |> List.any
            (\feed ->
                case feed.status of
                    Loaded pairs ->
                        List.any
                            (\( _, occasion ) ->
                                if model.mode == Calendar then
                                    occasionIsLong occasion

                                else
                                    occasionHasStarted model occasion && not (hiddenAsEnded model occasion)
                            )
                            pairs

                    _ ->
                        False
            )


{-| Reconciles `eventAnimations` with the `(Event, Occasion)` pairs
currently `Loaded` in `eventsByServer` -- mirrors
`Components.Pages.PostsPage.syncAnimations` exactly (starts a fade-in for
newly-seen occasions, a fade-out for ones that dropped out, leaves `move`
alone either way -- a content refresh never needs a position slide, only
`DisplayModeChanged` does), with two additions: an occasion `hiddenAsStarted`
or `hiddenAsEnded` is treated the same as one the server stopped returning --
excluded from `currentEvents`, so it fades out (or, symmetrically, fades back
in via `reappear` if both stop being true for it before its fade-out
finishes) exactly like any other add/remove this function already handles --
and, while `model.mode == Calendar`, `currentEvents` is unconditionally empty
regardless of what's actually `Loaded`, so every card fades out (per
`eventsListView`'s own "cards fade out as the calendar fades in" doc) the
moment `Calendar` becomes active, and fades back in the moment it stops being
active (`currentEvents` becoming non-empty again is itself already a
`reappear`, no different from any other card reappearing before its own
fade-out finished).
-}
syncAnimations : Model -> Model
syncAnimations model =
    let
        currentEvents : Dict String ( String, Event, Occasion )
        currentEvents =
            if model.mode == Calendar then
                Dict.empty

            else
                model.eventsByServer
                    |> Dict.toList
                    |> List.concatMap
                        (\( host, feed ) ->
                            case feed.status of
                                Loaded pairs ->
                                    pairs
                                        |> List.filter (\( _, occasion ) -> not (hiddenAsStarted model occasion) && not (hiddenAsEnded model occasion))
                                        |> List.map (\( event, occasion ) -> ( eventAnimationKey host occasion, ( host, event, occasion ) ))

                                _ ->
                                    []
                        )
                    |> Dict.fromList
    in
    { model
        | eventAnimations =
            UI.Flip.syncAnimations
                RemoveEvent
                (\( host, event, occasion ) -> { host = host, event = event, occasion = occasion, flip = UI.Flip.enter, move = UI.Flip.atRestScaled })
                (\( host, event, occasion ) anim -> { anim | host = host, event = event, occasion = occasion })
                currentEvents
                model.eventAnimations
    }


{-| `Model.calendarAnimations`' own reconciler -- mirrors `syncAnimations`
exactly (fade in a newly-`Just`-appeared item, fade out one that's gone),
just via `UI.Flip.syncAnimations`'s own fully generic form directly, rather
than a bespoke wrapper, since there's no per-item data to refresh here beyond
`flip` itself: `currentCalendar` is a single-entry `Dict` (keyed
`calendarAnimationKey`) while `model.mode == Calendar`, empty otherwise, so
this only ever holds 0 or 1 entries. Called from `DisplayModeChanged` (mode
is the only thing this ever depends on) and once more from `init` (a page
loaded straight into `?display=calendar` needs this seeded before its very
first render, same reasoning as `fetchNewServers`' own initial `syncAnimations`
call for `eventAnimations`).
-}
syncCalendarAnimations : Model -> Model
syncCalendarAnimations model =
    let
        currentCalendar : Dict String ()
        currentCalendar =
            if model.mode == Calendar then
                Dict.singleton calendarAnimationKey ()

            else
                Dict.empty
    in
    { model
        | calendarAnimations =
            UI.Flip.syncAnimations
                (\_ -> RemoveCalendarAnimation)
                (\_ -> { flip = UI.Flip.enter })
                (\_ anim -> anim)
                currentCalendar
                model.calendarAnimations
    }


{-| The most events `eventsListView` ever renders (and the only ones
`DisplayModeChanged` ever measures/animates) -- a long recurring `Event` can
rack up hundreds of future occasions (`Pages.Event.PostId_` has the same
concern for its own date-picker strip), and rendering/measuring/sliding all
of them at once on every mode switch is both wasteful and, empirically, the
reason a switch into `HorizontalList` could visibly "glitch" -- a card whose
FLIP invert-offset was large (e.g. one that used to sit far down a long
`VerticalList` column) spent most of its slide clipped out of view by
`.events-strip`'s own `overflow-y: hidden` (see `events.css`), so only the
tail end of its animation, once back within the strip's bounds, was ever
visible. Capping the working set keeps every card's invert-offset small
enough that this is far less likely to matter in practice, on top of just
being less to measure/animate.
-}
maxDisplayedEvents : Model -> Int
maxDisplayedEvents model =
    if model.embeddedPage then
        20

    else
        60


{-| `model.eventAnimations`, truncated to `maxDisplayedEvents` -- both
`eventsListView`'s rendering and `DisplayModeChanged`'s FLIP measurement work
from this exact same list, so a card excluded here is never measured or
animated either.

Only sorted soonest-to-start (mirrors `PostsPage.postsListView`'s own per-item
sort key) when `model.searchText` is empty -- an active text search's results
come back relevance-ranked, and re-sorting by start time here would throw
that ranking away. Sorts by `Events.occasionStartsAtOrEndsAt`, not `occasionMoment`
-- the latter prefers `endsAt` (its own "is this still current" reasoning),
which would order this list by end time instead.

-}
visibleAnimations : Model -> List ( String, EventAnimation )
visibleAnimations model =
    model.eventAnimations
        |> Dict.toList
        |> (if String.isEmpty (String.trim model.searchText) then
                List.sortBy
                    (\( _, anim ) ->
                        Events.occasionStartsOrEndsAt anim.occasion
                            |> Maybe.withDefault (Time.millisToPosix 0)
                            |> Time.posixToMillis
                    )

            else
                identity
           )
        |> List.take (maxDisplayedEvents model)


{-| Decodes `Ports.elementsMeasured`'s payload -- keyed by each entry's own
`key` field (see that port's own doc comment: deliberately _not_ the DOM
`id`, so this dict's keys always match `model.eventAnimations`' own keys
directly, with no reverse-derivation needed).
-}
rectsDecoder : Decode.Decoder (Dict String Rect)
rectsDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.map4 Rect
            (Decode.field "x" Decode.float)
            (Decode.field "y" Decode.float)
            (Decode.field "width" Decode.float)
            (Decode.field "height" Decode.float)
        )
        |> Decode.list
        |> Decode.map Dict.fromList


{-| Fires off `Ports.measureElements` for every one of `keys`' cards --
sending each as a `{ key, id }` pair (`id` via `eventCardDomId`) so
`rectsDecoder`'s result comes back keyed the same way `keys` itself already
is. See that port's own doc for why this replaces a `Task.sequence` over
`Browser.Dom.getElement` calls.
-}
measureElementsEffect : List String -> Effect Msg
measureElementsEffect keys =
    keys
        |> Encode.list
            (\key ->
                Encode.object
                    [ ( "key", Encode.string key )
                    , ( "id", Encode.string (eventCardDomId key) )
                    ]
            )
        |> Ports.measureElements
        |> Effect.fromCmd



-- CALENDAR


{-| The DOM `id` of `calendarView`'s container `div` -- the element
`Ports.renderCalendar`'s JS side looks up (and, on a later call, reuses if
it's still the same element) to actually mount/refresh FullCalendar.
-}
calendarContainerId : String
calendarContainerId =
    "events-calendar"


{-| `Model.calendarAnimations`' one and only possible key -- mirrors
`eventAnimationKey`'s role for `eventAnimations`, just constant rather than
derived, since `Calendar` mode has exactly one "item" to animate (the whole
calendar view), not one per `(host, Occasion)`.
-}
calendarAnimationKey : String
calendarAnimationKey =
    "calendar"


{-| How many hours long `occasionIsLong` treats as the threshold for "too
long to usefully show on `Calendar` mode's day-by-day grid" -- a plain `Int`
(hours, not milliseconds) so it reads as the one obviously-adjustable knob
here, mirroring `calendarLookbackDaysDefault`.
-}
longEventThresholdHours : Int
longEventThresholdHours =
    24


{-| Whether `occasion` spans more than `longEventThresholdHours` -- `False`
(never "long") unless both `startsAt`/`endsAt` are set, since there's no
duration to measure otherwise.
-}
occasionIsLong : Occasion -> Bool
occasionIsLong occasion =
    case ( occasion.startsAt, occasion.endsAt ) of
        ( Just startsAt, Just endsAt ) ->
            Time.posixToMillis (Conversions.timestampToPosix endsAt)
                - Time.posixToMillis (Conversions.timestampToPosix startsAt)
                > longEventThresholdHours
                * 60
                * 60
                * 1000

        _ ->
            False


{-| Whether `occasion` should be treated as absent from `calendarEvents` for
being `occasionIsLong` -- gated on `model.hideStartedUpcomingOrLongEvents`
(the same toggle `hiddenAsStarted` reads) _and_ `model.mode == Calendar`: a
multi-day event is exactly what makes `Calendar`'s day-by-day grid
unreadable, but has no equivalent problem in any card layout, so this never
hides anything outside `Calendar` mode.
-}
hiddenAsLong : Model -> Occasion -> Bool
hiddenAsLong model occasion =
    model.hideStartedOrLongEvents && model.mode == Calendar && occasionIsLong occasion


{-| Every `(host, Event, Occasion)` `Calendar` mode should plot -- reads
straight off `model.eventsByServer` (unlike `visibleAnimations`, this has no
`eventAnimations`/FLIP dict to go through, since `Calendar` isn't a card
layout -- see `EventsDisplayMode`'s own doc) and, unlike `visibleAnimations`'
own `maxDisplayedEvents` cap (a FLIP measurement/render cost concern that
doesn't apply here), includes every currently `Loaded` occasion -- "show all
events", per this mode's own purpose. Filters out `hiddenAsLong` occasions --
`model.hideStartedUpcomingOrLongEvents` means something different in
`Calendar` mode than everywhere else: `syncAnimations`' own `currentEvents`
reads it (via `hiddenAsStarted`) as "hide already-started occasions", but
`calendarEvents` deliberately never calls `hiddenAsStarted` at all -- a
day-by-day grid has no readability problem with an already-started event the
way a card listing arguably does, so here the same toggle means "hide
occasions spanning more than `longEventThresholdHours`" instead. Also
deliberately doesn't filter `hiddenAsEnded`, which is unconditionally `False`
while `model.mode == Calendar` anyway (see its own doc): `Calendar` is meant
to show its whole `queryEndsAfter`/`calendarLookbackDays` window, including
already-ended occasions, regardless of anything else on screen.
-}
calendarEvents : Model -> List ( String, Event, Occasion )
calendarEvents model =
    model.eventsByServer
        |> Dict.toList
        |> List.concatMap
            (\( host, feed ) ->
                case feed.status of
                    Loaded pairs ->
                        pairs
                            |> List.filter (\( _, occasion ) -> not (hiddenAsLong model occasion))
                            |> List.map (\( event, occasion ) -> ( host, event, occasion ))

                    _ ->
                        []
            )


{-| One `calendarEvents` entry as a FullCalendar
[`EventInput`](https://fullcalendar.io/docs/event-parsing) object -- `id` is
`eventAnimationKey` (unique across servers, mirrors the card layouts' own DOM
id convention), `title` is `event.post`'s own display title (via
`Posts.postTitleText`, same title the card layouts show as
`.event-card-title` -- see `eventCardView`'s doc for why that's `event.post`,
not `occasion.post`), falling back to a plain "Event" for the
practically-never case `event.post` is unset. `start`/`end` are ISO 8601 UTC
strings (via `Conversions.isoUtcString`), omitted individually when unset --
at least one of `occasion.startsAt`/`occasion.endsAt` should always be set in
practice, but neither is required by FullCalendar itself.

`classNames` is `[ hostnameToCSSClass host, "background-color-primary" ]` --
the same two-class combo every other per-server-colored element in this app
uses (see `UI.EmittedStylesheet`'s own doc), rather than computing/encoding
color hex strings here: `UI.EmittedStylesheet.view` (rendered once, app-wide,
in `UI.layout`) already emits `.server-X.background-color-primary {
background-color: ...; color: ...; }` for every connected server, kept fresh
with dark/light mode and any live branding changes, so this just opts each
event into that existing rule instead of duplicating `AccountsPanel`/
`UI.ServerTheme` color math into this port payload. `Ports.renderCalendar`'s
JS side passes `classNames` straight through to FullCalendar's own
`EventInput.classNames`, and `public/index.html`'s `eventDisplay: "block"`
option (set once, calendar-wide) is what makes those classes' `background-color`
actually visible -- FullCalendar's default month-view style is a small
`border-color`-only dot otherwise, which a `background-color` class alone
wouldn't paint.

-}
calendarEventEncoder : ( String, Event, Occasion ) -> Encode.Value
calendarEventEncoder ( host, event, occasion ) =
    let
        title : String
        title =
            event.post
                |> Maybe.map Posts.postTitleText
                |> Maybe.withDefault "Event"

        isoField : String -> Maybe Timestamp -> Maybe ( String, Encode.Value )
        isoField fieldName =
            Maybe.map (\ts -> ( fieldName, Encode.string (Conversions.isoUtcString (Conversions.timestampToPosix ts)) ))

        timeFields : List ( String, Encode.Value )
        timeFields =
            List.filterMap identity
                [ occasion.startsAt |> isoField "start"
                , occasion.endsAt |> isoField "end"
                ]
    in
    Encode.object
        ([ ( "id", Encode.string (eventAnimationKey host occasion) )
         , ( "title", Encode.string title )
         , ( "classNames", Encode.list Encode.string [ hostnameToCSSClass host, "background-color-primary" ] )
         ]
            ++ timeFields
        )


{-| `shared.accounts`' main server's `event_settings.default_calendar_display_mode`
-- mirrors `calendarLookbackDays`'s own `serverForHost .. mainFrontendHost |>
Maybe.map configurationOf` lookup, but falls back to
`CalendarDisplayMode.defaultCalendarDisplayMode` (`CALENDARDISPLAYWEEK`)
rather than a locally-defined constant, since that field (unlike
`calendar_lookback_days`) isn't `optional` in the proto -- every server
config already carries a real value once `eventSettings` itself is known.
-}
calendarDisplayMode : Shared.Model -> CalendarDisplayMode
calendarDisplayMode shared =
    RellmServers.rellmServerForHost shared.accounts.servers shared.accounts.mainFrontendHost
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .eventSettings
        |> Maybe.map .defaultCalendarDisplayMode
        |> Maybe.withDefault CalendarDisplayMode.defaultCalendarDisplayMode


{-| `shared.accounts`' main server's `event_settings.show_started_or_long_events_by_default` --
mirrors `calendarDisplayMode`'s own `serverForHost .. mainFrontendHost |> Maybe.map configurationOf`
lookup and, like that field, isn't `optional` in the proto, so this falls back to `False` (the
proto3 default for an unset `bool`) rather than a locally-defined constant. `init` reads this as
`hideStartedOrLongEvents`'s initial value, inverted -- see that field's own doc.
-}
showStartedOrLongEventsByDefault : Shared.Model -> Bool
showStartedOrLongEventsByDefault shared =
    RellmServers.rellmServerForHost shared.accounts.servers shared.accounts.mainFrontendHost
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .eventSettings
        |> Maybe.map .showStartedOrLongEventsByDefault
        |> Maybe.withDefault False


{-| `calendarDisplayMode`'s value, as the FullCalendar `initialView` string
`public/index.html`'s `renderCalendar` subscriber passes straight to
`FullCalendar.Calendar`'s own `initialView` option -- names match that same
subscriber's `headerToolbar` buttons (`dayGridMonth`/`timeGridWeek`/
`timeGridDay`), so switching view via this default vs. clicking a header
button lands on the identical FullCalendar view either way.
-}
fullCalendarInitialView : CalendarDisplayMode -> String
fullCalendarInitialView mode =
    case mode of
        CALENDARDISPLAYMONTH ->
            "dayGridMonth"

        CALENDARDISPLAYDAY ->
            "timeGridDay"

        _ ->
            "timeGridWeek"


{-| Fires `Ports.renderCalendar` with `calendarEvents newModel`, but only
when that could actually differ from what's already on screen -- `Calendar`
mode is (or was) newly active (`oldModel.mode /= Calendar`, covering both
`DisplayModeChanged` into it and this page's very first `init`-driven
render), or the underlying data `calendarEvents` reads from changed
(`eventsByServer`/`hideStartedUpcomingOrLongEvents`). Deliberately compares those
two fields rather than gating on `Msg` identity -- `update` calls this
unconditionally on every message (mirroring `setBreadcrumbsRoot`'s own
"recompute and let equality no-op it" convention), and `eventAnimations`
(unlike `eventsByServer`) changes on every single `Animate`/`AnimateMove`
tick, so keying off that instead would re-send the whole event list to JS 60
times a second while any card animation is running. `initialView` (via
`calendarDisplayMode`/`fullCalendarInitialView`) only actually matters the
first time a given container mounts -- `public/index.html`'s reused-element
branch never re-reads it -- but is sent on every call anyway, same as `id`.
-}
calendarRenderEffect : Shared.Model -> Model -> Model -> Effect Msg
calendarRenderEffect shared oldModel newModel =
    if
        newModel.mode
            == Calendar
            && (oldModel.mode /= Calendar || oldModel.eventsByServer /= newModel.eventsByServer || oldModel.hideStartedOrLongEvents /= newModel.hideStartedOrLongEvents)
    then
        Ports.renderCalendar
            (Encode.object
                [ ( "id", Encode.string calendarContainerId )
                , ( "events", Encode.list calendarEventEncoder (calendarEvents newModel) )
                , ( "initialView"
                  , Encode.string
                        (fullCalendarInitialView
                            (newModel.calendarDisplayModeOverride |> Maybe.withDefault (calendarDisplayMode shared))
                        )
                  )
                ]
            )
            |> Effect.fromCmd

    else
        Effect.none


{-| `model.pendingCalendarPreviewScroll`'s own retry loop -- mirrors
`Components.Pages.MessagesPage.scrollToPendingMessageCmd`'s "gate on presence,
only fire (and only then let the target get cleared, via `GotCalendarPreviewScrollTarget`)
once the data actually contains it" shape exactly, just re-checked here on
every `update` (like `calendarRenderEffect`) rather than from a handful of
specific fetch-completion branches -- there's no harm in re-checking on
messages that can't possibly have changed `eventsByServer` (the `oldModel.eventsByServer
/= newModel.eventsByServer` guard makes those an immediate `Effect.none`), and
this way nothing has to remember to call it from every place a fetch can land.

Deliberately searches `calendarPreviewEvents newModel` (the small window
already centered on `newModel.calendarPreview`), not the full `calendarEvents
newModel` -- a pending target from a `#calendar-preview-<key>` fragment can
only ever be a card the user actually saw and clicked from within that same
window in the first place (see `Model.pendingCalendarPreviewScroll`'s own
doc), so it's guaranteed to already be in range.

-}
pendingCalendarPreviewScrollEffect : Model -> Model -> Effect Msg
pendingCalendarPreviewScrollEffect oldModel newModel =
    case newModel.pendingCalendarPreviewScroll of
        Nothing ->
            Effect.none

        Just key ->
            if oldModel.eventsByServer == newModel.eventsByServer then
                Effect.none

            else if List.any (\( host, _, occasion ) -> eventAnimationKey host occasion == key) (calendarPreviewEvents newModel) then
                scrollToCalendarPreviewCard 60 key

            else
                Effect.none


{-| `Calendar` mode's container -- an outer `div` sized to span the full
width of the page (mirrors `.events-grid`/`.events-strip`'s own
`.container`-breakout convention, see `events.css`'s `.events-calendar`) and,
for a standalone page, `calc(100vh - 72px)` tall -- an embedded copy
(`embeddedPage`, `Pages.Home_`/`Components.Pages.UserProfilePage`, see
`modeButtonsView`'s own doc) instead gets a fixed, widget-sized 320px (the
`"embedded"` class, `events.css`), since `100vh` there would blow the
embedding page's own layout up to full viewport height for what's meant to
be one card-sized section among several. Either way this wraps a single
empty inner `div` (this is the one whose id `Ports.renderCalendar`'s JS side
actually mounts FullCalendar into, via `calendarContainerId`). Two nested
elements, not one, because FullCalendar's own `height: "100%"` option (set in
`public/index.html`) sets an inline `style="height: 100%"` directly on
whichever element it mounts into -- inline style always wins over
`events.css`'s own height rules regardless of specificity, so putting both on
the same element would leave FullCalendar's `100%` resolving against a parent
with no definite height of its own (collapsing to just its toolbar's
intrinsic height, confirmed live). The outer `div` carries the real, CSS-set
height instead, so the inner one's `100%` has something concrete to fill.
-}
calendarView : Bool -> Html Msg
calendarView embeddedPage =
    div
        [ classes
            ("events-calendar"
                :: (if embeddedPage then
                        [ "embedded" ]

                    else
                        []
                   )
            )
        ]
        [ div [ id calendarContainerId ] [] ]



-- CALENDAR PREVIEW


{-| The DOM id `calendarPreviewModalView`'s horizontal strip is rendered with
-- paired with `calendarPreviewCardDomId` by `scrollToCalendarPreviewCard`,
mirroring `Pages.Event.PostId_.occasionStripDomId`/`occasionChipDomId`
exactly.
-}
calendarPreviewStripDomId : String
calendarPreviewStripDomId =
    "calendar-preview-strip"


calendarPreviewCardDomId : String -> String
calendarPreviewCardDomId key =
    "calendar-preview-card-" ++ key


{-| Scrolls `calendarPreviewStripDomId`'s strip horizontally so `key`'s own
card is centered in view -- fired whenever `CalendarEventClicked` opens the
modal (or re-targets it to a different event while already open). Mirrors
`Pages.Event.PostId_.scrollToOccasion` exactly (see its own doc for why this
measures via `Dom.getElement`/`Dom.getViewportOf` then applies the result via
`Ports.scrollElementLeft` rather than `Browser.Dom.setViewportOf`), just with
a much shorter delay: `PostId_`'s own delay is there to let a FLIP
enter/grow transition clear before measuring, but `calendarPreviewCardView`
renders its cards directly (no FLIP, no `eventAnimations` involved -- see
`calendarPreviewModalView`'s own doc for why), so the only thing this delay
needs to cover is the one frame between `CalendarEventClicked` landing in the
model and the modal's own `is-open` class (and thus its non-zero layout)
actually painting.
-}
scrollToCalendarPreviewCard : Float -> String -> Effect Msg
scrollToCalendarPreviewCard delayMs key =
    Process.sleep delayMs
        |> Task.andThen
            (\_ ->
                Task.map3 (\card strip viewport -> ( card, strip, viewport ))
                    (Dom.getElement (calendarPreviewCardDomId key))
                    (Dom.getElement calendarPreviewStripDomId)
                    (Dom.getViewportOf calendarPreviewStripDomId)
            )
        |> Task.map
            (\( card, strip, viewport ) ->
                let
                    cardLeftWithinStrip : Float
                    cardLeftWithinStrip =
                        card.element.x - strip.element.x
                in
                viewport.viewport.x
                    + cardLeftWithinStrip
                    - (viewport.viewport.width / 2)
                    + (card.element.width / 2)
            )
        |> Task.attempt GotCalendarPreviewScrollTarget
        |> Effect.fromCmd


{-| `Calendar` mode's own "tap an event to preview it" modal -- opened by
`CalendarEventClicked` (`model.calendarPreview`), closed by its own close
button or backdrop click. Reuses `UI.Modal.backdrop` for the backdrop layer
(same fade/click-to-close convention as every other modal in the app), but a
bespoke body rather than `UI.Modal.view` -- that's a small, fixed-width
dialog frame (confirm/cancel style); this instead wants the
already-established embedded `HorizontalList` strip look (mirrors
`.events-strip`/`eventAnimationView`'s own card list), just centered as an
overlay, with no heading, and with wider cards (`.calendar-preview-card`,
`events.css`) than that strip's own fixed 280px tile.

Deliberately renders `calendarPreviewEvents model` (a small window around
whichever card was tapped, not the full `calendarEvents model`) directly via
`eventCardView` -- not through `eventAnimations`/`UI.Flip`'s enter/leave fade
the way `eventAnimationView` wraps it for the real card layouts -- because
this modal's own content never needs that: it isn't reconciling a changing
server fetch frame to frame the way the live listing is, it's a fixed
snapshot of "what's nearby", rendered fresh (open or closed -- an empty list
while closed, see `calendarPreviewEvents`' own doc) each time
`model.calendarPreview` changes, so `scrollToCalendarPreviewCard` has real,
measurable card elements to find without waiting on any enter animation to
clear first.

-}
calendarPreviewModalView : Shared.Model -> Model -> Html Msg
calendarPreviewModalView shared model =
    let
        isOpen : Bool
        isOpen =
            model.calendarPreview /= Nothing
    in
    div []
        [ UI.Modal.backdrop isOpen CalendarPreviewClosed
        , div [ classes [ "calendar-preview-modal", openClosedClass isOpen ] ]
            [ button
                [ class "calendar-preview-close"
                , onClick CalendarPreviewClosed
                , type_ "button"
                ]
                [ text "╳" ]
            , div [ id calendarPreviewStripDomId, class "calendar-preview-strip" ]
                (List.map (calendarPreviewCardView shared model) (calendarPreviewEvents model))
            ]
        ]


{-| How many cards `calendarPreviewEvents` keeps on either side of the tapped
one -- 5 each way, 11 total. Rendering `calendarEvents model` in full (every
currently-`Loaded` event, potentially hundreds -- see that function's own
doc) made `scrollToCalendarPreviewCard` unreliable for anything tapped far
into a long month: confirmed live, a card deep into a list that size either
measured wrong or just took long enough to lay out that the scroll fired
before it settled. A card only ever needs to scroll a _little_ into view
relative to its own near neighbors, never the _whole_ list, so bounding how
much this ever has to render fixes both the measurement and the cost of
building it in the first place.
-}
calendarPreviewWindowRadius : Int
calendarPreviewWindowRadius =
    5


{-| `calendarEvents model`, sorted chronologically (mirrors `visibleAnimations`'
own sort key) and windowed down to `calendarPreviewWindowRadius` entries on
either side of `model.calendarPreview`'s own tapped key -- empty while the
modal is closed (`Nothing`) or, in the practically-never case the tapped
event isn't found in the current fetch anymore, empty too (nothing sensible
to center a window on).
-}
calendarPreviewEvents : Model -> List ( String, Event, Occasion )
calendarPreviewEvents model =
    case model.calendarPreview of
        Nothing ->
            []

        Just key ->
            let
                sorted : List ( String, Event, Occasion )
                sorted =
                    calendarEvents model
                        |> List.sortBy
                            (\( _, _, occasion ) ->
                                Events.occasionStartsOrEndsAt occasion
                                    |> Maybe.withDefault (Time.millisToPosix 0)
                                    |> Time.posixToMillis
                            )

                targetIndex : Maybe Int
                targetIndex =
                    sorted
                        |> List.indexedMap (\i ( host, _, occasion ) -> ( i, eventAnimationKey host occasion ))
                        |> List.filter (\( _, k ) -> k == key)
                        |> List.head
                        |> Maybe.map Tuple.first
            in
            case targetIndex of
                Nothing ->
                    []

                Just idx ->
                    sorted
                        |> List.indexedMap Tuple.pair
                        |> List.filter (\( i, _ ) -> i >= idx - calendarPreviewWindowRadius && i <= idx + calendarPreviewWindowRadius)
                        |> List.map Tuple.second


{-| `onMouseDown (CalendarPreviewCardNavigated key)` is attached to the whole
card, not just its own inner nav-overlay link, and deliberately fires on
`mousedown` rather than `click` -- see that `Msg`'s own doc for why.
-}
calendarPreviewCardView : Shared.Model -> Model -> ( String, Event, Occasion ) -> Html Msg
calendarPreviewCardView shared model ( host, event, occasion ) =
    let
        key : String
        key =
            eventAnimationKey host occasion

        current : Bool
        current =
            model.calendarPreview == Just key
    in
    div [ id (calendarPreviewCardDomId key), class "calendar-preview-card", onMouseDown (CalendarPreviewCardNavigated key) ]
        [ eventCardView shared False current model.showSyncSources model.showSyncDestinations model.availableSyncDestinations model.pushStatuses ( host, event, occasion ) ]



-- VIEW


{-| `model.embeddedPage` (`True` only for `Pages.Home_`'s and
`Components.Pages.UserProfilePage`'s own copies of this view, fixed to
`HorizontalList`/"Row" -- see `Model.embeddedPage`) together with
`shared.accounts.debugTab.showAllEventLayouts` decides which (if any) of
`modeButtonsView`'s layout buttons show; see that function's own doc for the
full visibility rules.

`showAuthorHeading` hides `authorHeadingView` (the "Events | <name>" heading) when
`False` -- used by `Components.Pages.UserProfilePage`, which (like `Pages.Home_`) embeds
this module in its own `HorizontalList` row, a level below its own already-shown
username/avatar header (see `profileDetail`), so a second copy of the same name would be
redundant. Every other caller passes `True`, preserving the previous always-shown (whenever
`model.author` is `Just`) behavior.

An embedded copy (`model.embeddedPage`) keeps its own bespoke
`.events-controls-row`/`.events-controls-trailing` layout (`events.css`) --
its own `tabsView` is just a heading + `hideStartedOrLongButtonView`, not a real
tab strip, so it has nothing to gain from `.filter-tabs-bar`'s scrolling.
Every other (standalone) copy instead assembles the generic two-row "filter
area" `PostsPage.view`/`UsersPage.view` also use (`ui/filter_bar.css`): row 1
is `tabsView`'s own `.filter-tabs-bar`, row 2 is `.filter-controls-row`
holding `searchRowView` plus `.filter-controls-trailing` (the layout-switch
and export buttons).

-}
view : Shared.Model -> Bool -> Model -> Html Msg
view shared showAuthorHeading model =
    div []
        [ if showAuthorHeading then
            authorHeadingView shared model.author

          else
            text ""
        , if model.embeddedPage then
            div []
                [ searchRowView model
                , div [ class "events-controls-row" ]
                    [ tabsView shared model
                    , div [ class "events-controls-trailing" ]
                        [ modeButtonsView shared model.embeddedPage model.mode
                        , exportButtonView shared model
                        ]
                    ]
                ]

          else
            div []
                [ tabsView shared model
                , div [ class "filter-controls-row" ]
                    [ searchRowView model
                    , div [ class "filter-controls-trailing" ]
                        [ modeButtonsView shared model.embeddedPage model.mode
                        , exportButtonView shared model
                        ]
                    ]
                ]
        , eventsListView shared model
        , calendarPreviewModalView shared model
        ]


{-| "Events" alone once there's an `author` to filter by, upgraded to
"Events | <name>"-style via `Components.Users.ProfileHeading.nameHeader`
-- absent entirely for `Pages.Events`' unfiltered feed (`author == Nothing`),
which supplies its own heading instead. Mirrors
`Components.Pages.PostsPage.authorHeadingView`, minus the POST/REPLY-style
context this listing has no equivalent of.
-}
authorHeadingView : Shared.Model -> Maybe ( String, User ) -> Html Msg
authorHeadingView shared maybeAuthor =
    case maybeAuthor of
        Nothing ->
            text ""

        Just ( host, author ) ->
            let
                profileUrl : String
                profileUrl =
                    usernameHref "" shared.accounts.mainFrontendHost host author.username
            in
            div [ class "posts-page-heading" ]
                [ h2 [] [ text "Events" ]
                , a [ href profileUrl, class <| hostnameToCSSClass host ]
                    [ case RellmServers.rellmServerForHost shared.accounts.servers host of
                        Just server ->
                            ProfileHeading.nameHeader server (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host) author

                        Nothing ->
                            ProfileHeading.usernameHeading author
                    ]
                ]


{-| The "hide started (or long) events" filter icon button -- self-gating
rather than gated by its `tabsView` callers: renders `text ""` unless
`UpcomingEvents` is the active tab _and_ `anyStartedEvents` (`EventsAfterDate`'s
fixed cutoff has no "already started" notion to filter by, and there's
nothing to toggle when nothing's started yet). Toggles
`model.hideStartedUpcomingOrLongEvents` (see `HideStartedEventsToggled`), but
what that toggle actually hides depends on `model.mode` -- outside
`Calendar`, `hiddenAsStarted`/`syncAnimations` read it to fade already-started
occasions out of the listing; while `model.mode == Calendar`, `hiddenAsLong`
reads it instead, hiding occasions spanning more than
`longEventThresholdHours` -- a genuinely different filter, not an addition to
the "started" one (see `calendarEvents`' own doc). The `title` text below is
worded to match whichever one is actually in effect. Styled as a circular
icon button (`.filter-icon-button`, `ui/filter_bar.css`) mirroring
`exportButtonView`'s own; `background-color-primary` (matching `tabsView`'s
own active-tab convention) is added while the filter is on.
-}
hideStartedOrLongButtonView : Model -> Html Msg
hideStartedOrLongButtonView model =
    if anyStartedEvents model then
        button
            [ classes
                ("filter-icon-button"
                    :: (if model.hideStartedOrLongEvents then
                            [ "background-color-primary" ]

                        else
                            []
                       )
                )
            , onClick HideStartedEventsToggled
            , title
                (if model.mode == Calendar then
                    if model.hideStartedOrLongEvents then
                        "Showing events that are under " ++ String.fromInt longEventThresholdHours ++ " hours"

                    else
                        "Hide events that are " ++ String.fromInt longEventThresholdHours ++ "+ hours"

                 else if model.hideStartedOrLongEvents then
                    "Showing only events that haven't started"

                 else
                    "Hide events that have already started"
                )
            , type_ "button"
            ]
            [ text "▽" ]

    else
        text ""


{-| The 2 tabs (see `EventsTab`) -- "Upcoming Events" (a plain pill button,
mirrors `modeButtonView`'s own styling) and "Events After <date>",
which -- since it has to contain a real `<input type="datetime-local">`,
and nesting interactive content inside a `<button>` is invalid HTML -- is a
plain `div` with its own `onClick` instead. Clicking anywhere in that
second tab (including to open the date input's native picker, since the
click still bubbles up to the wrapping `div`) or actually changing the date
both switch to it, per `EventsTab`'s own doc -- `onClick`/`onInput` are
otherwise independent (a plain `TabChanged EventsAfterDate` is a no-op once
already active, so the two never conflict). The input's own `value` reflects
`model.endsAfter` (falling back to the UNIX epoch only for the brief instant
before the very first `GotNow`/`?ends_after=` resolves one -- see
`Model.endsAfter`'s own doc) formatted in the viewer's own local time zone,
so the picker shows/accepts wall-clock time the viewer actually recognizes
rather than raw UTC. The standalone (non-embedded) branch sits its tabs (plus
`hideStartedOrLongButtonView`) directly in the generic, horizontally-scrolling
`.filter-tabs-bar` (`ui/filter_bar.css`, shared with `PostsPage`'s own tabs)
-- the embedded branch keeps its own bespoke `.upcoming-events-tab-controls`
heading instead, see `view`'s own doc for why.
-}
tabsView : Shared.Model -> Model -> Html Msg
tabsView shared model =
    if model.embeddedPage then
        span [ class "upcoming-events-tab-controls" ]
            [ hideStartedOrLongButtonView model
            , h3 [] [ text "Upcoming Events" ]
            ]

    else
        div [ class "filter-tabs-bar" ]
            [ hideStartedOrLongButtonView model
            , button
                [ classes
                    ("filter-tab"
                        :: "filter-tab-primary"
                        :: (if model.tab == UpcomingEvents then
                                [ "background-color-primary" ]

                            else
                                []
                           )
                    )
                , onClick (TabChanged UpcomingEvents)
                ]
                [ text "Upcoming Events" ]
            , div
                [ classes
                    ("filter-tab"
                        :: (if model.tab == EventsAfterDate then
                                [ "background-color-primary" ]

                            else
                                []
                           )
                    )
                , onClick (TabChanged EventsAfterDate)
                ]
                [ text "Events After "
                , input
                    [ type_ "datetime-local"
                    , class "filter-tab-date-input"
                    , value
                        (SharedTime.formatDateTimeLocalInput
                            shared.time.browserTimeZone.zone
                            (Maybe.withDefault (Time.millisToPosix 0) model.endsAfter)
                        )
                    , onInput EndsAfterInputChanged
                    ]
                    []
                ]
            ]


{-| Search box (debounced, see `SearchTextChanged`/`SearchDebounceElapsed`) --
sits alongside `modeButtonsView`/`exportButtonView` (`view`'s own
`.filter-controls-trailing`) in the generic `.filter-controls-row`
(`ui/filter_bar.css`), row 2 of the standalone "filter area" below `tabsView`'s
own `.filter-tabs-bar`, so search still visibly respects whichever time-filter
tab is active (see `Components.Events.fetchEvents`'s own doc for why the
request itself still enforces that too, not just the UI placement). Mirrors
`Components.Pages.PostsPage.searchRowView`/`Components.Pages.UsersPage.searchRowView`
closely, minus a context chooser -- this listing has no equivalent.
-}
searchRowView : Model -> Html Msg
searchRowView model =
    div [ class "filter-search-field" ]
        [ input
            [ type_ "text"
            , class "filter-search-input"
            , placeholder <|
                if model.embeddedPage && model.embeddingPageSearchesPosts then
                    "Search posts and events..."

                else
                    "Search events..."
            , value model.searchText
            , onInput SearchTextChanged
            , onEscape ClearSearchClicked
            ]
            []
        , if String.isEmpty model.searchText then
            text ""

          else
            button
                [ type_ "button"
                , class "field-clear-button"
                , onClick ClearSearchClicked
                , title "Clear search"
                ]
                [ text "╳" ]
        ]


{-| Fires `msg` (and suppresses the key's default effect) when Escape is pressed in a text input
-- mirrors `Components.Pages.PostsPage.onEscape` exactly.
-}
onEscape : msg -> Html.Attribute msg
onEscape msg =
    preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Escape" then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not the Escape key"
                )
        )


{-| The layout-switch buttons (see `EventsDisplayMode`), highlighted
(`background-color-nav` -- unlike `tabsView`'s own tabs, which use
`background-color-primary`, so the two rows read as visually distinct kinds
of control sharing one row) for `current`, and pushed to the row's right edge
(see `view`'s `.filter-controls-trailing`/`.events-controls-trailing`, plus
`.events-mode-buttons` here in `events.css`) -- mirrors
`Pages.Event.PostId_.historyButtonView`'s pill styling.

Which buttons show (if any) depends on `embeddedPage` (`model.embeddedPage`,
see `view`'s own doc) and the "Show all event layouts" admin setting
(`shared.accounts.debugTab.showAllEventLayouts`, see `Shared.AccountsPanel.DebugTab`):

  - The setting on: all 4, everywhere -- the same as this used to always
    render (`VerticalList`/`Grid`/`HorizontalList`) before `embeddedPage`/the
    setting existed, plus `Calendar`.
  - An embedded copy (`Pages.Home_`, `Components.Pages.UserProfilePage`),
    setting off: `HorizontalList`/`Calendar` -- those copies default to (and
    can't switch away from) `HorizontalList`/"Row" for their card layout (see
    `init`'s own `embeddedPage` argument), but can still switch to `Calendar`,
    which renders at a fixed, embed-sized 320px tall there rather than
    `calc(100vh - 72px)` -- see `calendarView`'s own doc.
  - Every other (standalone) page, setting off: `VerticalList`/`Grid`/
    `Calendar` -- "Row" is the embedded copies' own look; hidden elsewhere so
    it doesn't read as an equally-supported standalone layout.

-}
modeButtonsView : Shared.Model -> Bool -> EventsDisplayMode -> Html Msg
modeButtonsView shared embeddedPage current =
    let
        visibleModes : List EventsDisplayMode
        visibleModes =
            if shared.accounts.debugTab.showAllEventLayouts then
                [ VerticalList, Grid, HorizontalList, Calendar ]

            else if embeddedPage then
                [ HorizontalList, Calendar ]

            else
                [ VerticalList, Grid, Calendar ]
    in
    if List.isEmpty visibleModes then
        text ""

    else
        div [ class "events-mode-buttons" ]
            (List.map (modeButtonView current) visibleModes)


modeButtonView : EventsDisplayMode -> EventsDisplayMode -> Html Msg
modeButtonView current target =
    button
        [ classes
            ("events-mode-button"
                :: (if target == current then
                        [ "background-color-accent" ]

                    else
                        []
                   )
            )
        , onClick (DisplayModeChanged target)
        ]
        [ text (modeLabel target) ]


modeLabel : EventsDisplayMode -> String
modeLabel mode =
    case mode of
        VerticalList ->
            "List"

        Grid ->
            "Grid"

        HorizontalList ->
            "Row"

        Calendar ->
            "Calendar"


{-| The backend's iCalendar/RFC5545 subscription endpoint
(`GET /calendar.ics`, `GET /calendar.ics?user_id={id}` -- see
`backend/src/web/ical_subscription.rs`) for whatever this listing is
currently showing: `model.author`'s own host + that user's id when this is a
per-user feed, or `shared.accounts.mainFrontendHost` (no `user_id`) for
the unfiltered feed -- mirrors `UI.elm`'s own `"https://" ++ server.frontendHost`
convention for linking to a Rellm server's own pages.
-}
icsUrl : Shared.Model -> Model -> String
icsUrl shared model =
    case model.author of
        Just ( host, user ) ->
            "https://" ++ host ++ "/calendar.ics" ++ Url.Builder.toQuery [ Url.Builder.string "user_id" user.id ]

        Nothing ->
            "https://" ++ shared.accounts.mainFrontendHost ++ "/calendar.ics"


{-| The "Export" icon button always shown at the end of `.filter-controls-trailing`
(next to `modeButtonsView`, unlike that one not gated by `embeddedPage` -- it
belongs on every copy of this listing, embedded or not, per its own request).
Toggles a small popover (`ExportClicked`/`ExportPopoverClosed`) anchored
under the button showing `icsUrl`'s link and a "Copy Link" button
(`CopyLinkClicked`, via `Ports.copyToClipboard`, showing "Link Copied!" for
5s afterward -- see `Model.copyLinkCopied`) -- built on `ui/popover.css`'s
generic `.popover-anchor`/`.popover-toggle`/`.popover`/`.popover-backdrop`
(always rendered, `openClosedClass`-driven fade+slide-down transition, button
corners squaring off to meet the popover -- see that stylesheet's own doc),
so any later button that wants a small anchored popover under itself can
reuse the same pieces. The backdrop `div` behind it closes it on click, same
"backdrop closes an open panel" idea `UI.Modal` uses for full-screen dialogs,
just anchored instead of centered. The button itself is `.filter-icon-button`
(`ui/filter_bar.css`), same circular sizing `hideStartedOrLongButtonView` uses.
-}
exportButtonView : Shared.Model -> Model -> Html Msg
exportButtonView shared model =
    div [ classes [ "events-export", "popover-anchor" ] ]
        [ button
            [ classes [ "filter-icon-button", "popover-toggle", "background-color-nav", openClosedClass model.exportPopoverOpen ]
            , onClick ExportClicked
            , title "Export calendar (ICS)"
            , type_ "button"
            ]
            [ text "⤓" ]
        , div [ classes [ "popover-backdrop", openClosedClass model.exportPopoverOpen ], onClick ExportPopoverClosed ] []
        , div [ classes [ "events-export-popover", "popover", openClosedClass model.exportPopoverOpen ] ]
            [ h3 [ class "events-export-popover-heading" ]
                [ text "Subscribe with iCal" ]
            , p [] [ text "Works with Google Calendar, macOS Calendar, Outlook, and more." ]
            , a
                [ href (icsUrl shared model)
                , target "_blank"
                , class "events-export-popover-link"
                ]
                [ text (icsUrl shared model) ]
            , button
                [ classes [ "events-export-popover-copy", "background-color-primary" ]
                , onClick CopyLinkClicked
                , type_ "button"
                ]
                [ span [ class "events-export-popover-copy-icon" ] [ text "⎘" ]
                , text
                    (if model.copyLinkCopied then
                        "Link Copied!"

                     else
                        "Copy Link"
                    )
                ]
            ]
        ]


{-| `model.mode`'s own container class + `UI.Flip.Axis` -- `VerticalList`
collapses/reflows vertically (mirrors `PostsPage.postsListView`'s own
`.flip-animated-column`), `Grid`/`HorizontalList` both collapse/reflow
horizontally (mirrors `PostId_.occasionContainerAttributes`' own choice for
its strip/grid).

While any card is still mid `DisplayModeChanged` slide (`anim.move.moving`),
an extra `events-mode-transitioning` class is added -- `events.css` uses it
to lift `.events-strip`'s normal `overflow-x: auto; overflow-y: hidden` for
just that moment, since a card's FLIP invert-offset can visually place it
well outside the settled layout's own box (e.g. sliding in from a
`VerticalList` position far below a single-row strip), and CSS's overflow-x/
overflow-y pairing rule means a lone `overflow-x: auto` already forces the
other axis to clip too (just optionally with a scrollbar) -- only `visible`
on both actually avoids clipping a card mid-flight. See `maxDisplayedEvents`'
own doc for how this was diagnosed.

The rendered `Html.Keyed.node` list itself is `animations` (real cards, via
`eventAnimationView`) followed by `calendarItems` (`Model.calendarAnimations`,
via `calendarAnimationView`) -- normally one or the other is empty (cards
while `model.mode /= Calendar`, the calendar item while it is), but both can
be simultaneously non-empty for the short window `syncAnimations`/
`syncCalendarAnimations` are cross-fading them (`DisplayModeChanged`'s own
handling for any transition to/from `Calendar` calls both): switching _into_
`Calendar`, every real card starts its own `remove` fade-out (`currentEvents`
going empty) at the same moment the calendar item starts its `enter` fade-in,
so they're both present -- one shrinking away, one growing in -- sharing this
same single-column list/container the whole time, which is what makes it
read as one list cross-fading rather than two unrelated views hard-cutting.
Switching _out_ of `Calendar` runs the same thing in reverse (cards
`reappear`, the calendar item `remove`s).

-}
eventsListView : Shared.Model -> Model -> Html Msg
eventsListView shared model =
    if Dict.isEmpty model.eventsByServer then
        p [ class "posts-empty" ]
            [ text <|
                case model.tab of
                    UpcomingEvents ->
                        "Connect to a server to see upcoming events."

                    EventsAfterDate ->
                        "Connect to a server to see events."
            ]

    else
        let
            animations : List ( String, EventAnimation )
            animations =
                visibleAnimations model

            calendarItems : List ( String, CalendarAnimation )
            calendarItems =
                Dict.toList model.calendarAnimations
        in
        if List.isEmpty animations && List.isEmpty calendarItems then
            p [ class "posts-empty" ]
                [ text <|
                    case model.tab of
                        UpcomingEvents ->
                            "No upcoming events."

                        EventsAfterDate ->
                            "No events."
                ]

        else
            let
                transitioning : Bool
                transitioning =
                    List.any (\( _, anim ) -> anim.move.moving) animations

                ( modeClass, axis ) =
                    case model.mode of
                        VerticalList ->
                            ( "events-list flip-animated-column", UI.Flip.Vertical )

                        Grid ->
                            ( "events-grid flip-animated-grid", UI.Flip.Horizontal )

                        HorizontalList ->
                            ( "events-strip flip-animated-row", UI.Flip.Horizontal )

                        Calendar ->
                            -- `Calendar` reuses `VerticalList`'s own
                            -- container class/axis outright (per this
                            -- module's own doc on `Calendar` -- "just use
                            -- `VerticalList`, with the calendar as its one
                            -- member" -- rather than a bespoke `.events-*`
                            -- class of its own).
                            ( "events-list flip-animated-column", UI.Flip.Vertical )

                containerClass : String
                containerClass =
                    if transitioning then
                        modeClass ++ " events-mode-transitioning"

                    else
                        modeClass
            in
            Html.Keyed.node "div"
                [ class containerClass ]
                (List.map
                    (eventAnimationView shared model.embeddedPage model.showSyncSources model.showSyncDestinations model.availableSyncDestinations model.pushStatuses axis)
                    animations
                    ++ List.map (calendarAnimationView model.embeddedPage) calendarItems
                )


{-| `calendarView` wrapped in the same fading/scaling/collapsing animated
`<div>` convention as a real card (`eventAnimationView`'s own outer layer,
via `anim.flip`/`UI.Flip.itemAttributes`) -- no inner `moveAttributes` layer
though, unlike a card: `Calendar` never needs a position/size _slide_ the way
switching among `VerticalList`/`Grid`/`HorizontalList` does (there's nothing
for it to slide relative to, it's the container's only item -- see
`eventsListView`'s own `Calendar ->` branch), just the fade/collapse `flip`
already gives it entering/leaving.

Always `UI.Flip.Vertical` regardless of the container's own current `axis` --
unlike a real card (which shares whatever axis `eventsListView` derives from
`model.mode` for the whole container), this can still be rendering while
`model.mode` has already moved on to `Grid`/`HorizontalList` (mid fade-out,
via `syncCalendarAnimations`), and `flip.css`'s row-axis collapse/`flex-shrink:0`
rules are aimed at fixed-width tiles, not this full-height view -- hardcoding
`Vertical` here sidesteps that regardless of which container it's
transiently sitting inside (the _container's_ own ancestor class, not this
item's, is what actually picks which grid axis collapses -- see
`flip.css`'s `.flip-animated-row .flip-animated-item.flip-collapsed`/
`.flip-animated-column .flip-animated-item.flip-collapsed`, so this still
collapses correctly along whichever axis the container it's inside actually
is).

Kept as the _last_ entry in `eventsListView`'s own keyed list (rather than
listed first, to visually lead) -- `UI.Flip.remove`'s own doc warns that
relocating a still-present item in that list (even just to sneak this one in
ahead of it) cancels its CSS collapse transition outright, since the browser
has nothing to transition _from_ once a keyed node's actually moved in the
DOM. `calendar-flip-item` (see `events.css`) instead reorders this one item
_visually_ to the front via the flex container's own `order`, leaving every
real card's DOM position (and thus its collapse transition) untouched.

-}
calendarAnimationView : Bool -> ( String, CalendarAnimation ) -> ( String, Html Msg )
calendarAnimationView embeddedPage ( key, anim ) =
    ( key
    , div (class "calendar-flip-item" :: UI.Flip.itemAttributes UI.Flip.Vertical anim.flip False) [ calendarView embeddedPage ]
    )


{-| Wraps `eventCardView` in a fading/scaling/collapsing animated `<div>`
(`anim.flip`, see `syncAnimations`) around an inner move-and-resize-sliding
`<div>` (`anim.move`, see `DisplayModeChanged`) -- mirrors
`Components.Pages.PostsPage.postAnimationView`'s own two-level structure,
just with the extra inner `moveAttributes` layer. The outer `div`'s `id` (see
`eventCardDomId`) is what `measureAll` looks up on a mode switch; it's safe
to measure regardless of `anim.flip`'s own state since that only ever
contributes an inert `scale(1)`/`opacity 1` unless actively entering/removing.
The inner div's `event-card-move` class (see `events.css`) sets
`transform-origin: top left` -- see `UI.Flip.startMoveScaled`'s own doc for
why that's needed alongside a scale.
-}
eventAnimationView : Shared.Model -> Bool -> Bool -> Bool -> Maybe (List SyncDestination) -> Dict String SubmitStatus -> UI.Flip.Axis -> ( String, EventAnimation ) -> ( String, Html Msg )
eventAnimationView shared embeddedPage showSyncSources showSyncDestinations availableSyncDestinations pushStatuses axis ( key, anim ) =
    let
        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if anim.flip.removing then
                [ style "pointer-events" "none" ]

            else
                []
    in
    ( key
    , div (id (eventCardDomId key) :: UI.Flip.itemAttributes axis anim.flip anim.move.moving)
        [ div (class "event-card-move" :: pointerEventsAttr ++ UI.Flip.moveAttributes anim.move)
            [ eventCardView shared embeddedPage False showSyncSources showSyncDestinations availableSyncDestinations pushStatuses ( anim.host, anim.event, anim.occasion ) ]
        ]
    )


{-| The occasion's own comment/star count is based on `occasion.post`, not
`event.post` (see `Components.Events.eventCard`'s own doc) -- swaps in
`StarredPanel.freshestPost`'s copy of it (same "the freshest known copy always
wins" convention `Components.Pages.PostsPage.postCardView` uses for a plain
`Post`) before handing `occasion` to `eventCard`, so both the star button's
`starred` state and the count it (and the comment count) displays come from
the same post, rather than `starred` alone reflecting a just-toggled state
the rendered count doesn't yet.
-}
eventCardView : Shared.Model -> Bool -> Bool -> Bool -> Bool -> Maybe (List SyncDestination) -> Dict String SubmitStatus -> ( String, Event, Occasion ) -> Html Msg
eventCardView shared embeddedPage current showSyncSources showSyncDestinations availableSyncDestinations pushStatuses ( host, event, occasion ) =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost shared.accounts.servers host

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host

        onMediaClicked : String -> Msg
        onMediaClicked mediaId =
            case event.post of
                Just eventPost ->
                    SharedMsg (Shared.MediaViewerPanelMsg (MediaViewerPanel.Open eventPost.media (Just eventPost) mediaId host))

                Nothing ->
                    SharedMsg Shared.NoOp

        onMediaPlayClicked : String -> Msg
        onMediaPlayClicked mediaId =
            SharedMsg (Shared.MediaRendererMsg (MediaRenderer.PlayClicked mediaId))

        displayOccasion : Occasion
        displayOccasion =
            case occasion.post of
                Just occasionPost ->
                    { occasion | post = Just (StarredPanel.freshestPost host occasionPost shared.panels.starredPanel) }

                Nothing ->
                    occasion

        starred : Bool
        starred =
            case displayOccasion.post of
                Just occasionPost ->
                    StarredPanel.isStarred host occasionPost shared.panels.starredPanel

                Nothing ->
                    False

        onStarClicked : Maybe Msg
        onStarClicked =
            displayOccasion.post
                |> Maybe.andThen (StarredPanel.toggleStarMsg shared.accounts host)
                |> Maybe.map (Shared.StarredPanelMsg >> SharedMsg)

        mediaSizing : MediaRenderer.MediaSize
        mediaSizing =
            if embeddedPage then
                MediaRenderer.ExtraSmall

            else
                MediaRenderer.Small

        occasionPostId : String
        occasionPostId =
            occasion.post |> Maybe.map .id |> Maybe.withDefault ""

        isPushing : String -> Bool
        isPushing destinationId =
            Dict.get (pushStatusKey occasionPostId destinationId) pushStatuses == Just Submitting

        pushError : String -> Maybe String
        pushError destinationId =
            case Dict.get (pushStatusKey occasionPostId destinationId) pushStatuses of
                Just (SubmitFailed err) ->
                    Just err

                _ ->
                    Nothing

        onPush : String -> Msg
        onPush destinationId =
            PushOccasionToDestination host occasionPostId destinationId

        onDelete : String -> String -> Msg
        onDelete destinationId destinationLabel =
            SharedMsg (Shared.RequestDelete (Shared.ConfirmOccasionSyncDestinationDelete occasion destinationId destinationLabel host))
    in
    Events.eventCard
        shared.time
        shared.basePath
        shared.accounts.mainFrontendHost
        host
        maybeServer
        maybeAccount
        onMediaClicked
        shared.mediaRenderer
        onMediaPlayClicked
        mediaSizing
        starred
        onStarClicked
        current
        showSyncSources
        showSyncDestinations
        availableSyncDestinations
        isPushing
        pushError
        onPush
        onDelete
        event
        displayOccasion
