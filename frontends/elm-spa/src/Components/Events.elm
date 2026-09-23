module Components.Events exposing
    ( createNewOccasions
    , deleteEvent
    , deleteOccasionSyncDestination
    , deleteRemovedOccasions
    , eventCard
    , eventSyncDestinationsView
    , fetchEvent
    , fetchEvents
    , fetchEventsByOccasionPostIds
    , findOccasion
    , hasIcsSyncSource
    , locationText
    , meaningfulPost
    , occasionEndsOrStartsAt
    , occasionHref
    , occasionPairs
    , occasionStartsOrEndsAt
    , occasionWhenText
    , parseEventRouteId
    , siblingOccasionWhenText
    , syncOccasion
    , syncSourceView
    , updateOccasions
    )

{-| Shared building blocks for displaying `Proto.Rellm.Event`s/`Occasion`s
-- used by `Pages.Event.PostId_` (a single-occasion detail view: building a
`GetEvents` request scoped to a single `Occasion`'s own `Post` id via
`Shared.MaybeAccountRequest`, parsing/building the `/event/:postId` route's
`id`/`id@host` segment, which is genuinely an `Occasion`'s own `Post`
id -- see that module's own doc) and by `Components.Pages.EventsPage` (a
multi-`Event` listing: `fetchEvents`/`occasionPairs`/`eventCard`), plus
the `Post`/timing rendering helpers both share.
-}

import Components.Authors as Authors
import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.Posts as Posts
import Components.SyncDestinations as SyncDestinations
import Gen.Route
import Grpc
import Html exposing (Html, a, div, span, text)
import Html.Attributes exposing (attribute, class, href, rel, target)
import Proto.Rellm exposing (Event, GetEventsRequest, GetEventsResponse, Location, Occasion, Post, SyncDestination, defaultEvent, defaultGetEventsRequest, defaultPost, defaultTimeFilter)
import Proto.Rellm.EventListingType exposing (EventListingType(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.SyncSource.Configuration as SyncSourceConfiguration
import Shared.AccountsPanel as AccountsPanel exposing (performWithOptionalAccountServer)
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.Conversions exposing (posixToTimestamp, timestampToPosix)
import Shared.Time as SharedTime
import Task exposing (Task)
import Time
import UI.Classes exposing (classes, hostnameToCSSClass)


{-| Fetches the `Event` (with all its `Occasion`s -- see
`GetEventsResponse`'s own doc: a request scoped to one `post_id` matching an
`Occasion`'s own `Post` id gets every occasion of that occasion's parent
`Event` back, not just the one asked for) containing the `Occasion`
whose own `Post` id is `occasionPostId`, from `maybeAccountServer`'s
server, authenticated as its account if any, anonymous otherwise -- same
auth/refresh handling as `Components.Posts.fetchPost`.
-}
fetchEvent :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetEventsResponse )
fetchEvent accountsPanelModel maybeAccountServer occasionPostId =
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getEvents { defaultGetEventsRequest | postId = Just occasionPostId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Deletes the `Event` whose own `Post` id is `eventPostId` outright
(`DeleteEvent`, owner-or-Admin gated server-side, see
`backend/src/rpcs/events/delete_event.rs`) -- nothing to overlay onto a fresh
copy first, so this just sends the id straight through (wrapped in a bare
`post`, since an `Event`'s identity now lives there -- see this module's own
top-of-file doc), mirroring `Components.Posts.deletePost`. Used by
`Pages.Event.PostId_`'s own Delete button, via `Shared.ConfirmEventDelete`.
-}
deleteEvent :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Event )
deleteEvent accountsPanelModel maybeAccountServer eventPostId =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteEvent { defaultEvent | post = Just { defaultPost | id = eventPostId } }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Pushes (cross-posts) `occasionId` to `syncDestinationId` (`SyncOccasion`,
owner-or-Admin gated server-side, see
`backend/src/rpcs/events/sync_occasion.rs`) -- mirrors `deleteEvent`'s
shape exactly. The returned `Occasion` carries a freshly updated `syncDestinations`, but
callers here just reuse their own existing full refetch (`Pages.Event.PostId_.refetch`/
`Components.Pages.EventsPage.refetchServers`) rather than patching it in by hand.
-}
syncOccasion :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Occasion )
syncOccasion accountsPanelModel maybeAccountServer occasionId syncDestinationId =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.syncOccasion
                { occasionId = occasionId, syncDestinationId = syncDestinationId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Removes `occasionId`'s sync (cross-post) to `syncDestinationId` (`DeleteOccasionSyncDestination`,
owner-or-Admin gated server-side, see
`backend/src/rpcs/events/delete_occasion_sync_destination.rs`) -- the reverse of
`syncOccasion`, same shape. Doesn't delete the post already made on the destination (e.g. the Facebook Page
post), only the local sync record, so the row goes back to its unsynced "Push" state (see
`Components.SyncDestinations.syncDestinationsView`'s `notYetSyncedRows`). Used by that view's Delete button, via
`Shared.ConfirmOccasionSyncDestinationDelete`.
-}
deleteOccasionSyncDestination :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> String
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deleteOccasionSyncDestination accountsPanelModel maybeAccountServer occasionId syncDestinationId =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteOccasionSyncDestination
                { occasionId = occasionId, syncDestinationId = syncDestinationId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| Updates, in place, every `Occasion` in `event.occasions` that's
already on the event (matched by its own `post.id`) -- any other occasion in
`event.occasions` is silently ignored rather than created
(`UpdateOccasions`, owner-or-`MODERATEEVENTS`/`MODERATEPOSTS`/`ADMIN`
gated server-side, see `backend/src/rpcs/events/update_occasions.rs`).
Used by `Pages.Event.PostId_`'s "Edit Time"/"Edit Location" saves, each
sending the whole currently-loaded `Event` (its own `post`/`info`/
`syncSource` identify it, since it has no id of its own anymore) plus a
single-element `occasions` list built from the currently-loaded
`Occasion` with only the field(s) being edited overridden -- carrying
the rest of that `Occasion` (notably its own `post`) along unchanged
matters here: the backend treats an update entry with no `post` as an
explicit request to reset that occasion's own Post to `PRIVATE` (see that
file's own doc comment), not "leave visibility alone".
-}
updateOccasions :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Event
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Event )
updateOccasions accountsPanelModel maybeAccountServer event =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.updateOccasions event
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Creates a new `Occasion` for every entry in `event.occasions` that
isn't already on the event -- since a not-yet-created occasion has no `id` of
its own to match against, every entry sent here ends up created
(`CreateNewOccasions`, same owner-or-moderator gating as
`updateOccasions`, see
`backend/src/rpcs/events/create_new_occasions.rs`). Used by
`Pages.Event.PostId_`'s "Add More" recurrence menu, which builds
`event.occasions` as a batch of new `Occasion`s (see
`buildRecurringOccasions`) all in one call, rather than one RPC per occasion.
-}
createNewOccasions :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Event
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Event )
createNewOccasions accountsPanelModel maybeAccountServer event =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.createNewOccasions event
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Deletes every `Occasion` currently on the event that _isn't_ in
`event.occasions` -- i.e. `event.occasions` is the "keep" list, not a batch to
delete (`DeleteRemovedOccasions`, same owner-or-moderator gating as
`updateOccasions`/`createNewOccasions`, see
`backend/src/rpcs/events/delete_removed_occasions.rs`). Used by
`Shared.update`'s `ConfirmOccasionDelete` handling to delete a single
`Occasion`: the caller passes every _other_ occasion the `Event`
currently has, so this ends up deleting just the one omitted.
-}
deleteRemovedOccasions :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Event
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Event )
deleteRemovedOccasions accountsPanelModel maybeAccountServer event =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.deleteRemovedOccasions event
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Fetches `Event`s ending after `endsAfter` from `maybeAccountServer`'s
server, authenticated as its account if any -- for
`Components.Pages.EventsPage`'s listing, rather than `fetchEvent`'s single
`Occasion` lookup. `authorUserId`, if given, restricts the results to
that user's own events (mirrors `Components.Posts.fetchPosts`' own
`authorUserId` param), for that module's use on a user's own events page.

`GetEventsRequest.timeFilter.endsAfter` is the only time filter
`backend/src/rpcs/events/get_events.rs` actually implements (see its
`query_visible_events!` macro), excluding any `Occasion` that's already
ended as of `endsAfter` -- `EventsPage` passes the live current time for its
default "Upcoming Events" tab, or a user-picked cutoff for its "Events After
<date>" one, so this is deliberately not called `now` (it isn't,
always). This time filter is sent -- and still enforced -- regardless of
`searchText`; see below. `GetEventsResponse` isn't itself flattened
per-`Occasion` -- see `occasionPairs`.

`searchText`, if non-blank (leading/trailing whitespace is trimmed, and a
blank string is treated the same as empty), switches the request to
`EVENT_TEXT_SEARCH` -- mirrors `Components.Posts.fetchPosts`' own
`searchText` param. Unlike `fetchPosts`, `timeFilter` is still sent either
way -- `get_search_events` (the `EVENT_TEXT_SEARCH` branch of
`backend/src/rpcs/events/get_events.rs`) still filters on it, so a search
made while on the "Upcoming Events" tab only searches upcoming events, not
every event ever.

-}
fetchEvents :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Maybe String
    -> String
    -> Time.Posix
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetEventsResponse )
fetchEvents accountsPanelModel maybeAccountServer authorUserId searchText endsAfter =
    let
        trimmedSearchText : String
        trimmedSearchText =
            String.trim searchText

        baseRequest : GetEventsRequest
        baseRequest =
            { defaultGetEventsRequest
                | authorUserId = authorUserId
                , timeFilter = Just { defaultTimeFilter | endsAfter = Just (posixToTimestamp endsAfter) }
            }

        request : GetEventsRequest
        request =
            if String.isEmpty trimmedSearchText then
                baseRequest

            else
                { baseRequest
                    | listingType = EVENTTEXTSEARCH
                    , searchText = Just trimmedSearchText
                }
    in
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getEvents request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Fetches the `Event`/`Occasion` data for a batch of `Occasion`
Post ids on `maybeAccountServer`'s server, authenticated as its account if
any -- for `Shared.StarredPanel`, which already has a flat list of starred
`Post` ids (fetched individually via `Components.Posts.fetchPost`, see that
module's own doc) and, for whichever of those turn out to be an
`Occasion`'s own Post (`PostContext.OCCASION`), wants back the
`Event`/`Occasion` data `Components.Events.eventCard` needs to render
them -- one batched request per server rather than one per starred
`Occasion` post. Unlike `fetchEvent`'s single `occasion_id`
request (which returns the whole parent `Event` with _every_ one of its
occasions, for the single-event detail page's date-picker strip), this
mirrors `fetchEvents`' own "one `Event` entry per matching `Occasion`"
shape (see `occasionPairs`) -- each requested post id resolves to
exactly one `(Event, Occasion)` pair, not a whole recurring series (see
`backend/src/rpcs/events/get_events.rs`'s `get_events_by_occasion_post_ids`,
which this calls into via `GetEventsRequest.occasion_post_ids`).
-}
fetchEventsByOccasionPostIds :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> List String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetEventsResponse )
fetchEventsByOccasionPostIds accountsPanelModel maybeAccountServer occasionPostIds =
    performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getEvents { defaultGetEventsRequest | occasionPostIds = occasionPostIds }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Flattens a `GetEventsResponse` into `(Event, Occasion)` pairs -- for
any listing request (unlike `fetchEvent`'s single-`occasion_id` request,
which returns one `Event` with every one of its occasions),
`get_public_and_following_events`/`get_user_events` each return **one `Event`
per matching `Occasion` row**, with `occasions` holding just that one
occasion (see `events.proto`'s own doc comment on `GetEventsResponse`: "the
response will carry duplicate `Event`s with the same ID" -- one entry per
occasion in the requested time frame). `Components.Pages.EventsPage` centers
its whole listing on the `Occasion`, same as `Pages.Event.PostId_`'s own
detail view, so this is written generically (flat-mapping every `Event`'s
`occasions`, however many there are) rather than assuming exactly one.
-}
occasionPairs : GetEventsResponse -> List ( Event, Occasion )
occasionPairs response =
    response.events
        |> List.concatMap (\event -> List.map (\occasion -> ( event, occasion )) event.occasions)



-- ROUTE / LINKS


{-| `rawEventId` is either a bare `Occasion` id (an event on
`mainFrontendHost`) or `id@host` (one on some other, federated server) --
mirrors `Components.Posts.parsePostRouteId` exactly.
-}
parseEventRouteId : String -> String -> ( String, String )
parseEventRouteId mainFrontendHost rawEventId =
    case String.split "@" rawEventId of
        [ id, host ] ->
            ( id, host )

        _ ->
            ( rawEventId, mainFrontendHost )


{-| Finds the `Occasion` (of `event.occasions`) whose own `Post` id
matches the given id -- `Pages.Event.PostId_` uses this to pick out, from the
full `Event` a `GetEvents` response carries, the one specific occasion the
page's own route was asking for.
-}
findOccasion : String -> Event -> Maybe Occasion
findOccasion occasionPostId event =
    event.occasions
        |> List.filter (\occasion -> (occasion.post |> Maybe.map .id) == Just occasionPostId)
        |> List.head


{-| The href for `occasion`, as seen from `viewingServerHost` -- mirrors
`Components.Posts.postHref`, just keyed on an `Occasion`'s own `Post`
id (the route segment, matching `Gen.Route`/`Gen.Params`'s own "postId"
naming) rather than the `Event`'s. Used by `Pages.Event.PostId_`'s
date-picker strip to link between sibling `Occasion`s of the same
`Event`. Renders an empty (self) link if `occasion.post` is somehow unset --
shouldn't happen in practice, same as `eventCard`'s own handling.
-}
occasionHref : String -> String -> String -> Occasion -> String
occasionHref basePath viewingServerHost eventServerHost occasion =
    let
        occasionPostId : String
        occasionPostId =
            occasion.post |> Maybe.map .id |> Maybe.withDefault ""

        routeId : String
        routeId =
            if eventServerHost == viewingServerHost then
                occasionPostId

            else
                occasionPostId ++ "@" ++ eventServerHost
    in
    basePath ++ Gen.Route.toHref (Gen.Route.Event__PostId_ { postId = routeId })



-- DISPLAY


{-| The instant that best represents "when" an `Occasion` is -- `endsAt`
if set (an occasion stays current until it actually ends), falling back to
`startsAt` (at least one of the two should always be set), `Nothing` only if
neither is. Used both for filtering/sorting an `Event`'s occasions by
recency (see `Pages.Event.PostId_`'s `OccasionHistoryDisplay`) and, via
`occasionDateText`, for display.
-}
occasionEndsOrStartsAt : Occasion -> Maybe Time.Posix
occasionEndsOrStartsAt occasion =
    case occasion.endsAt of
        Just ts ->
            Just (timestampToPosix ts)

        Nothing ->
            occasion.startsAt |> Maybe.map timestampToPosix


{-| The instant `occasion` begins -- `startsAt` if set, falling back to
`endsAt` (at least one of the two should always be set), `Nothing` only if
neither is. Unlike `occasionMoment` (which prefers `endsAt`, so an ongoing
event still counts as "current"), this is for chronological sorting -- e.g.
`Components.Pages.EventsPage.visibleAnimations`, which lists soonest-to-start
first.
-}
occasionStartsOrEndsAt : Occasion -> Maybe Time.Posix
occasionStartsOrEndsAt occasion =
    case occasion.startsAt of
        Just ts ->
            Just (timestampToPosix ts)

        Nothing ->
            occasion.endsAt |> Maybe.map timestampToPosix


{-| A human-friendly "when" label for `occasion`, e.g. "August 1, 6-7PM",
"June 1, 10PM - June 8, 3AM", or "December 31, 2025, 9PM - January 1, 2AM" --
used identically by `eventCard`'s own "when" line, `Pages.Event.PostId_`'s
detail view (the currently-viewed occasion's own when line), and that same
page's date-picker strip chips (see `occasionHistoryView`), so every place an
`Occasion`'s date/time shows reads the same way. `time.now` supplies
"the viewer's own current year" (see `Shared.Time.Model.now`), which
`SharedTime.formatRange`/`formatMoment` use to drop a redundant year --
see their own docs for the full set of examples this is designed against
(same-day ranges, cross-day ranges, and ranges crossing into a different
year on either side).

Both `startsAt` and `endsAt` are normally set (a merged range, via
`SharedTime.formatRange`); this falls back to just whichever one is set
(via `SharedTime.formatMoment`, prefixed "Until " if only `endsAt` is,
since that's the unusual case) or a placeholder if somehow neither is.

-}
occasionWhenText : SharedTime.Model -> Occasion -> String
occasionWhenText time occasion =
    case ( occasion.startsAt, occasion.endsAt ) of
        ( Just startTs, Just endTs ) ->
            SharedTime.formatRange time (timestampToPosix startTs) (timestampToPosix endTs)

        ( Just startTs, Nothing ) ->
            SharedTime.formatMoment time (timestampToPosix startTs)

        ( Nothing, Just endTs ) ->
            "Until " ++ SharedTime.formatMoment time (timestampToPosix endTs)

        ( Nothing, Nothing ) ->
            "Time TBD"


{-| Like `occasionWhenText`, for a date-picker strip chip (see
`Pages.Event.PostId_.occasionChipView`) offering `occasion` as an
alternative to `currentOccasion` (the one the page is currently showing).
Drops the time-of-day entirely -- e.g. "March 7" rather than "March 7,
6-7PM" -- whenever `occasion` starts and ends at the same time-of-day (in
`browserTimeZone`) as `currentOccasion` itself, since a recurring event's
sibling occasions usually share one time slot and repeating it on every
chip is just noise; the date(s) alone already distinguish one chip from
another. Falls back to the full `occasionWhenText` the moment either side
lacks a full start/end pair, or their time-of-day actually differs (e.g. an
irregular one-off that moved to a different hour).
-}
siblingOccasionWhenText : SharedTime.Model -> Occasion -> Occasion -> String
siblingOccasionWhenText time currentOccasion occasion =
    let
        zone : Time.Zone
        zone =
            time.browserTimeZone.zone

        sameTimeOfDay : Time.Posix -> Time.Posix -> Bool
        sameTimeOfDay a b =
            Time.toHour zone a == Time.toHour zone b && Time.toMinute zone a == Time.toMinute zone b

        sharesCurrentTimeOfDay : Bool
        sharesCurrentTimeOfDay =
            case ( currentOccasion.startsAt, currentOccasion.endsAt ) of
                ( Just currentStartTs, Just currentEndTs ) ->
                    case ( occasion.startsAt, occasion.endsAt ) of
                        ( Just startTs, Just endTs ) ->
                            sameTimeOfDay (timestampToPosix currentStartTs) (timestampToPosix startTs)
                                && sameTimeOfDay (timestampToPosix currentEndTs) (timestampToPosix endTs)

                        _ ->
                            False

                _ ->
                    False
    in
    case ( sharesCurrentTimeOfDay, occasion.startsAt, occasion.endsAt ) of
        ( True, Just startTs, Just endTs ) ->
            SharedTime.formatDateRange time (timestampToPosix startTs) (timestampToPosix endTs)

        _ ->
            occasionWhenText time occasion


{-| `location.uniformlyFormattedAddress`, trimmed -- `Nothing` if blank, same
convention as `Components.Posts.postLinkText`.
-}
locationText : Location -> Maybe String
locationText location =
    let
        trimmed : String
        trimmed =
            String.trim location.uniformlyFormattedAddress
    in
    if String.isEmpty trimmed then
        Nothing

    else
        Just trimmed


{-| `post` itself, unless it has nothing an `Occasion`'s own override
`Post` would actually add over the parent `Event`'s -- no title, link,
content, or media, just the empty shell every `Occasion` carries whether
or not its creator actually filled one in. `Pages.Event.PostId_.eventDetailView`
uses this to skip its own secondary post section entirely for one of these;
`eventCard` uses it the same way, to skip an occasion-specific note line.
-}
meaningfulPost : Post -> Maybe Post
meaningfulPost post =
    let
        hasTitle : Bool
        hasTitle =
            post.title |> Maybe.map (String.trim >> String.isEmpty >> not) |> Maybe.withDefault False

        hasContent : Bool
        hasContent =
            post.content |> Maybe.map (String.trim >> String.isEmpty >> not) |> Maybe.withDefault False

        hasLink : Bool
        hasLink =
            Posts.postLinkText post /= Nothing

        hasMedia : Bool
        hasMedia =
            not (List.isEmpty post.media)
    in
    if hasTitle || hasContent || hasLink || hasMedia then
        Just post

    else
        Nothing


{-| Whether `event` is pulled in from an ICS/iCal subscription (i.e. its own
`Post.syncSource` -- see `posts.proto`'s `Post.sync_source`, which any Post
can carry now, not just an `Event`'s -- has an `IcsSubscriptionUrl`
configuration) -- such an `Event` is re-synced from that feed on every run of
the backend's `sync_sources` job, so any local edit to its title/link/content
would just be clobbered the next time that happens. Used by
`Pages.Event.PostId_` to hide those fields' own edit buttons for a synced
`Event`.
-}
hasIcsSyncSource : Event -> Bool
hasIcsSyncSource event =
    case event.post |> Maybe.andThen .syncSource |> Maybe.andThen .configuration of
        Just (SyncSourceConfiguration.IcsSubscriptionUrl _) ->
            True

        _ ->
            False


{-| One small-text, clipped-not-wrapped line crediting the source `event` was
synced from (e.g. an ICS feed) -- see `Components.Pages.UserProfilePage`'s
"Sync Sources" section. Renders nothing for a normal, non-synced event.
Shared by `Pages.Event.PostId_`'s detail view and `eventCard` (gated on
`showSyncSource`).
-}
syncSourceView : Event -> Html msg
syncSourceView event =
    case event.post |> Maybe.andThen .syncSource |> Maybe.andThen .configuration of
        Just (SyncSourceConfiguration.IcsSubscriptionUrl url) ->
            div [ class "event-synced-from" ]
                [ text "synced from "
                , a [ href url, class "event-synced-from-link" ] [ text url ]
                ]

        _ ->
            text ""


{-| Thin wrapper over `Components.SyncDestinations.syncDestinationsView`, extracting
`occasion.syncDestinations` (and `occasion.post`'s media, if any, for that view's `hasMedia`,
which gates Instagram rows' Push button) -- see that function's own doc for the full
already-synced/available-to-sync-to union and rendering rules; only
`Components.Pages.UserProfilePage`'s embedded events feed ever passes `Just`
for `availableSyncDestinations`, giving every other caller a read-only,
no-push-controls rendering.
-}
eventSyncDestinationsView :
    Maybe (List SyncDestination)
    -> (String -> Bool)
    -> (String -> Maybe String)
    -> (String -> msg)
    -> (String -> String -> msg)
    -> Occasion
    -> Html msg
eventSyncDestinationsView availableSyncDestinations isPushing pushError onPush onDelete occasion =
    let
        hasMedia : Bool
        hasMedia =
            occasion.post |> Maybe.map (\post -> not (List.isEmpty post.media)) |> Maybe.withDefault False
    in
    SyncDestinations.syncDestinationsView occasion.syncDestinations availableSyncDestinations hasMedia isPushing pushError onPush onDelete


{-| A compact, read-only card for one `(Event, Occasion)` pair --
`Components.Pages.EventsPage`'s per-item rendering, centered on `occasion`
(its own start/end/location) the same way `Pages.Event.PostId_`'s detail view
is, but titled/linked/media'd off `event.post` (the `Event`'s own name/link/
media -- the "primary" `Post`, same primacy `eventDetailView` gives it),
mirroring `Components.Posts.postCard`'s stretched-link-overlay card shape.
Renders nothing if `event.post` is unset (shouldn't happen in practice --
every `Event` is created with one -- but the field is optional on the wire).

`starred`/`onStarClicked` drive the bottom-right star button, same as
`Components.Posts.postCard`'s own -- but keyed on `occasion.post` (the
`Occasion`'s own `Post`), not `event.post`: an `Event`'s recurring
occasions each get their own independent star/comment count, the same way
each one gets its own `Post` row in the database (see `events.proto`'s own
doc). Renders neither the star button nor the comment count if
`occasion.post` is unset (shouldn't happen in practice, same as `event.post`
above, but the field is optional on the wire).

`mediaSizing` picks how big `eventPost.media` renders (see
`Components.MediaRenderer.Sizing`) -- `ExtraSmall` renders via
`MultiMediaRenderer.previewExtraSmall`, anything else via
`MultiMediaRenderer.preview` (`Small` sizing). `Shared.StarredPanel` always
passes `ExtraSmall` (its post rows are tight on vertical space);
`Components.Pages.EventsPage` passes `ExtraSmall` only for its embedded copy,
`Small` otherwise (see its own `eventCardView`).

`current` mirrors `Components.Posts.postCard`'s own -- `True` swaps the card's
background for `background-color-primary` (plus an `event-card-current`
class, mirroring `post-card-current`) instead of the default
`background-color-primary-5`, highlighting the one matching whatever
`Occasion` the viewer is already on. `Shared.StarredPanel` is the only
caller that ever passes `True` (see `UI.currentStarredOccasionKey`);
`Components.Pages.EventsPage`'s own listing always passes `False`.

`showSyncSource`/`showSyncDestinations` gate `syncSourceView event`/
`eventSyncDestinationsView` at the bottom of the card -- mirrors
`Components.Pages.EventsPage.Model`'s own `showSyncSources`/
`showSyncDestinations` fields, which `EventsPage.eventCardView` threads
straight through.

`availableSyncDestinations`/`isPushing`/`pushError`/`onPush`/`onDelete` thread
straight into `eventSyncDestinationsView`'s own params of the same name/shape
-- see that function's own doc. `availableSyncDestinations` is `Nothing` for
every caller except `Components.Pages.UserProfilePage`'s embedded events feed,
so push/delete controls render nowhere else.

-}
eventCard :
    SharedTime.Model
    -> String
    -> String
    -> String
    -> Maybe RellmServer
    -> Maybe RellmAccount
    -> (String -> msg)
    -> MediaRenderer.Model
    -> (String -> msg)
    -> MediaRenderer.MediaSize
    -> Bool
    -> Maybe msg
    -> Bool
    -> Bool
    -> Bool
    -> Maybe (List SyncDestination)
    -> (String -> Bool)
    -> (String -> Maybe String)
    -> (String -> msg)
    -> (String -> String -> msg)
    -> Event
    -> Occasion
    -> Html msg
eventCard time basePath viewingServerHost eventServerHost maybeServer maybeAccount onMediaClicked mediaPlayState onMediaPlayClicked mediaSizing starred onStarClicked current showSyncSource showSyncDestinations availableSyncDestinations isPushing pushError onPush onDelete event occasion =
    case event.post of
        Nothing ->
            text ""

        Just eventPost ->
            div
                [ classes
                    ([ "event-card"
                     , hostnameToCSSClass eventServerHost
                     , "border-color-primary-anchor-50"
                     , "hover-border-color-primary-anchor"
                     ]
                        ++ (if current then
                                [ "event-card-current", "background-color-primary" ]

                            else
                                [ "background-color-primary-5" ]
                           )
                    )
                ]
                [ a
                    [ href (occasionHref basePath viewingServerHost eventServerHost occasion)
                    , class "event-card-link-overlay"
                    , attribute "aria-label" (Posts.postTitleText eventPost)
                    ]
                    []
                , div [ class "event-card-title" ] [ text (Posts.postTitleText eventPost) ]
                , case Posts.postLinkText eventPost of
                    Just link ->
                        a
                            [ href link
                            , target "_blank"
                            , rel "noopener noreferrer"
                            , classes [ hostnameToCSSClass eventServerHost, "event-card-link" ]
                            ]
                            [ text (Posts.stripLinkScheme link) ]

                    Nothing ->
                        text ""
                , div [ class "event-card-when" ] [ text "📅 ", span [ class "event-occasion-time" ] [ text (occasionWhenText time occasion) ] ]
                , case occasion.location |> Maybe.andThen locationText of
                    Just locationLine ->
                        div [ class "event-card-where" ] [ text "📍 ", text locationLine ]

                    Nothing ->
                        text ""
                , case maybeServer of
                    Just server ->
                        case mediaSizing of
                            MediaRenderer.ExtraSmall ->
                                MultiMediaRenderer.previewExtraSmall server maybeAccount mediaPlayState onMediaPlayClicked onMediaClicked eventPost.media

                            _ ->
                                MultiMediaRenderer.preview server maybeAccount mediaPlayState onMediaPlayClicked onMediaClicked eventPost.media

                    Nothing ->
                        text ""
                , case eventPost.content of
                    Just content ->
                        Markdown.view
                            [ classes
                                (if String.length content > Posts.contentPreviewFadeThreshold then
                                    [ "event-card-content-preview", "event-card-content-preview-fade" ]

                                 else
                                    [ "event-card-content-preview" ]
                                )
                            ]
                            content

                    Nothing ->
                        text ""
                , case occasion.post |> Maybe.andThen meaningfulPost of
                    Just occasionPost ->
                        div [ class "event-card-occasion-note" ] [ text (Posts.postTitleText occasionPost) ]

                    Nothing ->
                        text ""
                , div [ class "event-card-meta" ]
                    [ span [ class "post-meta-left" ]
                        [ Authors.link basePath viewingServerHost eventServerHost maybeServer maybeAccount eventPost.author
                        , if Posts.showPostVisibility maybeAccount eventPost then
                            text (" · " ++ Posts.postVisibilityText eventPost)

                          else
                            text ""
                        ]
                    , case occasion.post of
                        Just occasionPost ->
                            span [ class "post-meta-right" ]
                                [ Posts.starButton eventServerHost starred onStarClicked occasionPost
                                , text (Posts.commentCountText occasionPost)
                                ]

                        Nothing ->
                            text ""
                    ]
                , if showSyncSource then
                    syncSourceView event

                  else
                    text ""
                , if showSyncDestinations then
                    eventSyncDestinationsView availableSyncDestinations isPushing pushError onPush onDelete occasion

                  else
                    text ""
                ]
