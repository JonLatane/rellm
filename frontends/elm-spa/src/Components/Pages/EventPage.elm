module Components.Pages.EventPage exposing
    ( Model
    , Msg
    , fromShared
    , init
    , subscriptions
    , titleFor
    , update
    , view
    )

{-| The shared guts of a single Event's detail/"invitation" view: the
`Event`'s own `Post` (title, link, media, content) up top, then a
horizontally-scrolling date-picker strip of the `Event`'s other
`Occasion`s (see `occasionHistoryView`) if it has more than one, then
the specific `Occasion` being viewed (its start/end time and location),
then that `Occasion`'s own optional override `Post`. Reused by both
`Pages.Event.PostId_` (`/event/:postId[@host]`) and
`Components.Pages.PostOrEventPage` (once a short-URL id resolves to an
Event/Occasion -- see that module's own doc), and, through it,
`Pages.UsernameOrCustomTab_` (once a segment starting with a reserved
short-URL character resolves this way -- see that module's `initEmbedded`).
Mirrors `Components.Pages.PostPage`'s own split from its two callers.

`postId` (passed to `init`, matching `Components.Pages.PostPage.init`'s own
`rawPostId` naming) is genuinely the viewed `Occasion`'s own `Post` id --
an `Occasion`'s identity is its own `Post`'s id (see
`Proto.Rellm.Occasion`). `GetEventsRequest.post_id` is the only way to
fetch a single Event (see `events.proto`), and looking it up by an
`Occasion`'s own Post id returns that occasion's whole parent `Event`
with _every_ one of its occasions, not just the one asked for -- which is
exactly what makes the date-picker strip possible without a second request.

`pageIsSecure`/`navKey` are captured once, at `init` (same reasoning as
`Components.Pages.PostPage.Model.pageIsSecure`/`navKey`) -- needed later by
`ConnectClicked` (`RellmServers.connectToRellmServer`) and `update`'s own
`Shared.GotEventDeleteResult`/`Shared.GotOccasionDeleteResult` handling
(navigating away once the viewed Event/occasion no longer exists), neither of
which otherwise has access to the calling page's own `Request`.

-}

import Animation
import Browser.Dom as Dom
import Browser.Navigation
import Components.AIProviders as AIProviders
import Components.Authors as Authors
import Components.Events as Events
import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.Posts as Posts
import Components.ServerDependentView as ServerDependentView
import Components.SyncDestinations as SyncDestinations
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Route
import Grpc
import Html exposing (Html, a, button, div, h1, h2, h3, option, p, select, span, text)
import Html.Attributes exposing (attribute, class, disabled, href, id, placeholder, rel, selected, target, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Encode as Encode
import Ports
import Process
import Proto.Rellm exposing (Event, Occasion, GetSyncDestinationsResponse, Location, Post, SyncDestination, defaultOccasion, defaultLocation)
import Proto.Rellm.Moderation exposing (Moderation)
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.Visibility exposing (Visibility)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.CreateNewPanel as CreateNewPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Conversions as Conversions
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MediaGeneratorPanel as MediaGeneratorPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.MyMediaPanel as MyMediaPanel
import Shared.StarredPanel as StarredPanel
import Shared.Time as SharedTime
import Task
import Time
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.Flip


type alias Model =
    { targetHost : String
    , occasionId : String
    , eventStatus : EventStatus
    , connectStatus : ServerDependentView.ConnectStatus
    , fetchStarted : Bool

    -- Mirrors `Components.Pages.PostPage.Model.fetchedAccountId` exactly --
    -- the `RellmAccounts.rellmAccountId` of whichever account was signed in on
    -- `targetHost` (the Event's own server) when the currently-held
    -- `eventStatus` was last fetched, if any.
    , fetchedAccountId : Maybe String
    , occasionHistoryDisplay : OccasionHistoryDisplay
    , occasionLayout : OccasionLayout
    , occasionAnimations : Dict String OccasionAnimation

    -- Set by `MediaEditClicked`, until the `Shared.MyMediaPanel` it opens
    -- reports back a `SaveMediaClicked`/`CloseClicked` -- mirrors
    -- `Components.Pages.PostPage.Model.mediaEditActive` exactly, see its own doc for
    -- why this gating is needed at all.
    , mediaEditActive : Bool

    -- Set by `GenerateMediaClicked`, until `Shared.MediaGeneratorPanel` reports back a
    -- `GotGenerateResult`/`CancelClicked` -- mirrors `Components.Pages.PostPage.Model.mediaGeneratorActive`
    -- exactly, see its own doc for why.
    , mediaGeneratorActive : Bool

    -- Live only while one of the title/link/content editors (see
    -- `postFieldEditFormView`) is open, for the `Event`'s own primary `Post`
    -- -- mirrors `Components.Pages.PostPage.Model.visibilityEdit` (a
    -- `pending`-vs-loaded split, independent until save succeeds), just over
    -- 3 possible fields instead of one, only one live at a time.
    , postFieldEdit : Maybe PostFieldEdit

    -- Live only while the moderation-status selector (see `moderationView`)
    -- is open -- mirrors `postFieldEdit` in shape.
    , moderationEdit : Maybe ModerationEdit

    -- Live only while the Event's own primary `Post`'s visibility selector
    -- (see `visibilityView`) is open -- mirrors `moderationEdit` in shape,
    -- `Components.Pages.PostPage.VisibilityEdit` in spirit.
    , visibilityEdit : Maybe VisibilityEdit

    -- Live only while the currently-viewed `Occasion`'s start/end time
    -- editor (see `occasionTimeEditFormView`) is open -- mirrors
    -- `postFieldEdit` in shape, just with two pending fields instead of one
    -- (mirrors `Shared.CreateNewPanel.Model`'s own `startsAt`/`endsAt` pair).
    , occasionTimeEdit : Maybe OccasionTimeEdit

    -- Live only while the currently-viewed `Occasion`'s location editor
    -- (see `occasionLocationEditFormView`) is open -- mirrors `postFieldEdit`
    -- in shape, just a single free-text address field.
    , occasionLocationEdit : Maybe OccasionLocationEdit

    -- Live only while the "Add More" recurrence popover (see `addMoreView`)
    -- is open -- `Nothing` is "closed", mirroring every other panel here.
    , addMoreMenu : Maybe AddMoreMenu

    -- `Submitting`/`SubmitFailed` push status per `eventSyncDestinationId`,
    -- for the "synced to" listing's own Push/Push-again button (see
    -- `Events.eventSyncDestinationsView`'s `isPushing`/`pushError`) --
    -- mirrors `Components.Pages.EventsPage.Model.pushStatuses`, just keyed by
    -- destination id alone rather than `occasionId ++ "|" ++ destinationId`,
    -- since this page only ever shows one `Occasion` at a time.
    , syncDestinationPushStatuses : Dict String SubmitStatus

    -- The viewer's own `SyncDestination`s, fetched once `GotEvent` confirms they're this Event's
    -- author (or Admin) -- `Nothing` until that fetch resolves (or if the viewer isn't the
    -- author/Admin, in which case it's never fetched at all, same as `Just []`'s effect on
    -- `eventSyncDestinationsView`: no "Push" button, only already-synced rows, if any). See
    -- `Events.eventSyncDestinationsView`'s own doc for how `Just`/`Nothing` here changes rendering.
    , availableSyncDestinations : Maybe (List SyncDestination)

    -- Captured once at `init` -- see the module doc.
    , pageIsSecure : Bool
    , navKey : Browser.Navigation.Key
    }


type Msg
    = GotEvent (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetEventsResponse ))
    | MediaClicked Post String
      -- The Event's own `Post`'s media-edit button (see `eventDetailView`) --
      -- opens the shared `Shared.MyMediaPanel` chooser in `MultiSelect` mode,
      -- mirroring `Components.Pages.PostPage.MediaEditClicked` exactly, including
      -- reusing plain `UpdatePost` (via `Posts.updatePost`) to save -- the
      -- backend's `update_post.rs` already updates `media` unconditionally
      -- for `admin || self_update` regardless of the post's own context
      -- (`Post`, `Event`, `Occasion`, ...), so nothing about `UpdateEvent`
      -- is needed just to change which media this Post carries.
    | MediaEditClicked Post
      -- The Event's own "Generate Media…" button (see `eventDetailView`) -- opens
      -- `Shared.MediaGeneratorPanel` targeting the Event's own Post, mirroring
      -- `Components.Pages.PostPage.GenerateMediaClicked` exactly.
    | GenerateMediaClicked Event Occasion
    | GotMediaUpdateResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- One of the Event's own `Post`'s title/link editors (see
      -- `postFieldEditFormView`) -- each shown to the post's own author or
      -- an Admin via its own "Edit X" button (see `postFieldEditButtonView`),
      -- submitted via plain `UpdatePost` (`Posts.updatePost`) the same way
      -- `MediaEditClicked`'s save is, rather than the heavier `UpdateEvent`
      -- (see that `Msg`'s own doc for why).
    | PostFieldEditClicked PostField Post
    | PostFieldChanged String
    | PostFieldCancelClicked
    | PostFieldSaveClicked Post
    | GotPostFieldSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- The Event's own `Post`'s "Edit Content" button (see
      -- `contentDisplayView`) -- opens the shared Markdown editor panel,
      -- mirroring `Components.Pages.PostPage.EditClicked` exactly (down to reusing
      -- `MarkdownPanel.PostContent`); its result
      -- (`Shared.MarkdownPanelMsg (MarkdownPanel.GotSaveResult (Ok _))`) is
      -- picked up in `SharedMsg` below, the same way `EditClicked`'s is there.
    | EditContentClicked Post
      -- The Event's own `Post`'s moderation-status selector (see
      -- `moderationView`) -- shown to an Admin or a `MODERATEEVENTS` holder,
      -- also submitted via plain `UpdatePost`.
    | ModerationEditClicked Event
    | ModerationChanged String
    | ModerationCancelClicked
    | ModerationSaveClicked Event
    | GotModerationSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- The Event's own `Post`'s visibility selector (see `visibilityView`)
      -- -- shown to the post's own author or an Admin, also submitted via
      -- plain `UpdatePost`, mirroring `Components.Pages.PostPage`'s own
      -- `VisibilityEditClicked`/etc. family.
    | VisibilityEditClicked Post
    | VisibilityChanged String
    | VisibilityCancelClicked
    | VisibilitySaveClicked Post
    | GotVisibilitySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- The currently-viewed `Occasion`'s start/end time editor (see
      -- `occasionTimeEditFormView`) -- unlike the Event's own `Post` fields
      -- above, this *does* need `UpdateOccasions` (there's no
      -- `Occasion`-only equivalent of `UpdatePost`).
    | OccasionTimeEditClicked Occasion
    | OccasionStartsAtChanged String
    | OccasionEndsAtChanged String
    | OccasionTimezoneChanged String
    | OccasionTimeCancelClicked
    | OccasionTimeSaveClicked Occasion
    | GotOccasionTimeSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Event ))
      -- The currently-viewed `Occasion`'s location editor (see
      -- `occasionLocationEditFormView`) -- mirrors the time editor above,
      -- also via `UpdateOccasions`.
    | OccasionLocationEditClicked Occasion
    | OccasionLocationChanged String
    | OccasionLocationCancelClicked
    | OccasionLocationSaveClicked Occasion
    | GotOccasionLocationSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Event ))
      -- The "Add More" recurrence popover (see `addMoreView`) -- a two-step
      -- menu (`AddMoreMenu.step`): first how many more `Occasion`s to
      -- create (`AddMoreCountClicked`), then how far apart to space them
      -- (`AddMoreFrequencyClicked`, which actually submits via
      -- `CreateNewOccasions`).
    | AddMoreClicked
    | AddMoreClosed
    | AddMoreCountClicked Int
    | AddMoreBackClicked
    | AddMoreFrequencyClicked Int SharedTime.RecurrenceUnit
    | GotAddMoreResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Event ))
      -- The Event's own delete button (see `deleteButtonView`), shown to its
      -- owner -- opens the shared "are you sure?" dialog
      -- (`Shared.ConfirmEventDelete`); its result (`Shared.GotEventDeleteResult`)
      -- is picked up in `SharedMsg` below.
    | DeleteClicked Event
      -- The "Delete Occasion" button next to it (see
      -- `deleteOccasionButtonView`), only shown once `event` has more than
      -- one `Occasion` -- opens the same shared dialog
      -- (`Shared.ConfirmOccasionDelete`) for just `occasion`; its result
      -- (`Shared.GotOccasionDeleteResult`) is picked up in `SharedMsg`
      -- below.
    | DeleteOccasionClicked Occasion Event
    | ConnectClicked
    | GotConnectResult (Result Grpc.Error RellmServer)
    | EnableClicked
      -- Switches which of the Event's `Occasion`s the date-picker strip
      -- shows (see `OccasionHistoryDisplay`) -- fired by `historyButtons`.
    | HistoryDisplayChanged OccasionHistoryDisplay
      -- Switches the strip between its scrolling-row and wrapping-grid
      -- layouts (see `OccasionLayout`) -- fired by `occasionLayoutButtonView`.
    | OccasionLayoutChanged OccasionLayout
      -- Steps every date chip's enter/leave fade (`occasionAnimations`)
      -- forward on an animation-frame tick -- mirrors
      -- `Shared.MyMediaPanel.AnimateItemFlip`.
    | AnimateItemFlip Animation.Msg
      -- Fired once a chip that dropped out of the current
      -- `OccasionHistoryDisplay` filter finishes fading/collapsing out (see
      -- `UI.Flip.remove`) -- drops it from `occasionAnimations` for good.
    | RemoveOccasionAnimation String
      -- The scroll-the-current-occasion-into-view measurement (see
      -- `scrollToOccasion`) resolving with the target `scrollLeft` to send
      -- through `Ports.scrollElementLeft` -- `Err` (the chip/strip not
      -- found, e.g. an `Event` with only one occasion) is a pure no-op.
    | GotScrollTarget (Result Dom.Error Float)
    | Poll
      -- The "synced to" listing's own Push/Push-again button (see
      -- `Model.syncDestinationPushStatuses`'s own doc) -- the Delete button
      -- next to it needs no `Msg` of its own, going straight through
      -- `Shared.RequestDelete`/`Shared.ConfirmOccasionSyncDestinationDelete`
      -- like `Components.Pages.EventsPage.eventCardView`'s own `onDelete`
      -- does, picked up in `SharedMsg` below.
    | PushSyncDestinationClicked String
    | GotSyncDestinationPushResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Occasion ))
      -- `Model.availableSyncDestinations`'s own fetch (see `GotEvent`'s Ok branch) resolving --
      -- populates the "Push" button's list of destinations not yet synced. A failure just leaves
      -- `availableSyncDestinations` at `Nothing` (same as never having fetched at all -- only
      -- already-synced rows still render, no error banner for this one, mirroring how the rest of
      -- this page treats its own non-critical fetches).
    | GotSyncDestinationsResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetSyncDestinationsResponse ))
    | SharedMsg Shared.Msg


type EventStatus
    = LoadingEvent
    | EventLoaded Event Occasion
    | EventFailed


{-| Which of an `Event`'s `Occasion`s the date-picker strip (see
`occasionHistoryView`) shows -- starts `OnlyFuture` (see `init`) unless the
`Occasion` this page is actually showing needs a broader mode than that
to even be in the strip at all, in which case it starts there instead (see
`clampHistoryDisplay`): the currently-viewed occasion is never allowed to be
hidden by its own page's date picker. The history buttons above the strip
(see `historyButtons`) switch it to reveal further past dates on request
rather than dumping every occasion of a long-running recurring `Event`
(weekly meetups can rack up hundreds) on the page by default.
-}
type OccasionHistoryDisplay
    = OnlyFuture
    | SinceTwoWeeksAgo
    | ShowAllOccasions


{-| How `occasionHistoryView`'s strip lays out its chips -- `StripLayout`
(the default) is a single horizontally-scrolling row; `GridLayout` wraps
instead, trading the scrollbar for vertical growth. Toggled via
`occasionLayoutButtonView`, only offered at all once there's more than 3
chips to justify it (see `occasionHistoryView`).
-}
type OccasionLayout
    = StripLayout
    | GridLayout


{-| One date-picker chip's data plus its own enter/leave `UI.Flip.State` --
mirrors `Shared.MyMediaPanel.MediaAnimation` (see its own doc): keeping
`occasion` here, not just looking it up from `Event.occasions` by id, means a
chip that just dropped out of `occasionHistoryDisplay`'s current filter still
has something to render for the length of its own fade/collapse-out.
-}
type alias OccasionAnimation =
    { occasion : Occasion
    , flip : UI.Flip.State Msg
    }


{-| Mirrors `Components.Pages.PostPage.SubmitStatus` exactly.
-}
type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Which one of the `Event`'s own primary `Post`'s title/link fields
`postFieldEditFormView` is currently editing -- each gets its own "Edit X"
button (see `postFieldEditButtonView`), so only one of the two is ever live
at a time. Content isn't a `PostField` -- its own "Edit Content" button
(`EditContentClicked`) opens the shared `Shared.MarkdownPanel` instead,
mirroring this page's own content-editing UX exactly rather than this
plain-`<input>` form, which wouldn't suit Markdown well.
-}
type PostField
    = TitleField
    | LinkField


{-| Live only while `postFieldEditFormView` is open for `field`, editing the
`Event`'s own primary `Post` -- `pending` is the in-progress `<input>`
value, independent of the loaded `Post`'s own field until
`PostFieldSaveClicked` succeeds. Mirrors `Components.Pages.PostPage.VisibilityEdit`,
just parameterized over which field it's editing.
-}
type alias PostFieldEdit =
    { field : PostField
    , pending : String
    , status : SubmitStatus
    }


{-| Live only while the moderation-status selector is open -- mirrors
`PostFieldEdit` in shape, `Components.Pages.PostPage.VisibilityEdit` in spirit.
-}
type alias ModerationEdit =
    { pending : Moderation
    , status : SubmitStatus
    }


{-| Live only while the Event's own primary `Post`'s visibility selector is
open -- mirrors `ModerationEdit`/`Components.Pages.PostPage.VisibilityEdit`
exactly, just for `Visibility` instead of `Moderation`.
-}
type alias VisibilityEdit =
    { pending : Visibility
    , status : SubmitStatus
    }


{-| Live only while the currently-viewed `Occasion`'s start/end time
editor is open -- mirrors `PostFieldEdit` in shape, just two pending fields
(`Shared.CreateNewPanel.Model`'s own `startsAt`/`endsAt` pair) instead of
one. Both `Nothing` only transiently, while the raw `<input
type="datetime-local">` text doesn't parse (see `OccasionStartsAtChanged`/
`OccasionEndsAtChanged`) -- `OccasionTimeSaveClicked` no-ops rather than
submitting an incomplete pair.
-}
type alias OccasionTimeEdit =
    { pendingStartsAt : Maybe Time.Posix
    , pendingEndsAt : Maybe Time.Posix

    -- Defaults to the browser's own timezone (see `OccasionTimeEditClicked`), mirroring
    -- `Shared.CreateNewPanel.Model.timezone`'s own "always has a sensible value, never blank"
    -- convention -- unlike `pendingStartsAt`/`pendingEndsAt`, there's no "not yet picked" state
    -- worth showing blank for.
    , pendingTimezone : String
    , status : SubmitStatus
    }


{-| Live only while the currently-viewed `Occasion`'s location editor is
open -- mirrors `PostFieldEdit` exactly, `pending` being the in-progress
`Location.uniformlyFormattedAddress` text (the only field `Location` has
worth editing by hand -- see that message's own proto doc).
-}
type alias OccasionLocationEdit =
    { pending : String
    , status : SubmitStatus
    }


{-| Which half of the "Add More" recurrence popover (`addMoreView`) is
showing -- `ChoosingCount` first (how many more `Occasion`s), then
`ChoosingFrequency count` (how far apart to space them -- see
`availableFrequencies`/`frequencyLabel`), which is what actually submits via
`AddMoreFrequencyClicked`.
-}
type AddMoreStep
    = ChoosingCount
    | ChoosingFrequency Int


{-| Live only while the "Add More" popover (see `addMoreView`) is open --
`Nothing` (rather than this type existing at all) is "closed", mirroring
every other panel/edit-form's own `Maybe`-typed `Model` field here.
-}
type alias AddMoreMenu =
    { step : AddMoreStep
    , status : SubmitStatus
    }


{-| `rawPostId` is the unparsed `:postId[@host]` id (whatever the calling
page derived it from -- a route segment directly, for `Pages.Event.PostId_`,
or a short-URL id with its own reserved leading character stripped, for
`Components.Pages.PostOrEventPage` -- see that module's own doc). Genuinely
the viewed `Occasion`'s own `Post` id -- see the module doc.
-}
init : Shared.Model -> Bool -> String -> Browser.Navigation.Key -> ( Model, Effect Msg )
init shared pageIsSecure rawPostId navKey =
    let
        ( eventId, targetHost ) =
            Events.parseEventRouteId shared.accounts.mainFrontendHost rawPostId

        ( fetchedModel, fetchEffect ) =
            fetchIfReady shared
                { targetHost = targetHost
                , occasionId = eventId
                , eventStatus = LoadingEvent
                , connectStatus = ServerDependentView.NotConnected
                , fetchStarted = False
                , fetchedAccountId = Nothing
                , occasionHistoryDisplay = OnlyFuture
                , occasionLayout = StripLayout
                , occasionAnimations = Dict.empty
                , mediaEditActive = False
                , mediaGeneratorActive = False
                , postFieldEdit = Nothing
                , moderationEdit = Nothing
                , visibilityEdit = Nothing
                , occasionTimeEdit = Nothing
                , occasionLocationEdit = Nothing
                , addMoreMenu = Nothing
                , syncDestinationPushStatuses = Dict.empty
                , availableSyncDestinations = Nothing
                , pageIsSecure = pageIsSecure
                , navKey = navKey
                }
    in
    ( fetchedModel
    , Effect.batch
        [ fetchEffect
        , Effect.fromShared (Shared.BreadcrumbsMsg Breadcrumbs.Clear)
        ]
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.fetchStarted then
            Sub.none

          else
            Time.every 30000 (\_ -> Poll)
        , UI.Flip.subscription AnimateItemFlip (Dict.values model.occasionAnimations |> List.map .flip)
        ]


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotEvent (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    accountsPanelEffect maybeAccountsPanelMsg

                newStatus : EventStatus
                newStatus =
                    case List.head response.events of
                        Just event ->
                            case Events.findOccasion model.occasionId event of
                                Just occasion ->
                                    EventLoaded event occasion

                                Nothing ->
                                    EventFailed

                        Nothing ->
                            EventFailed

                -- `Shared.Breadcrumbs.FromEvent` exists but its `rootSegment`
                -- isn't implemented yet (renders a literal "TODO" -- see its
                -- own doc comment), so this just uses `FromServerHost` like
                -- `Components.Pages.PostPage` does for a non-`REPLY` Post: shows a
                -- server chip in the trail when `targetHost` isn't
                -- `mainFrontendHost`, nothing more.
                breadcrumbsEffect : Effect Msg
                breadcrumbsEffect =
                    Effect.fromShared
                        (Shared.BreadcrumbsMsg
                            (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost model.targetHost) model.targetHost [])
                        )

                scrollEffect : Effect Msg
                scrollEffect =
                    case newStatus of
                        EventLoaded _ _ ->
                            scrollToOccasion 300 model.occasionId |> Effect.fromCmd

                        _ ->
                            Effect.none

                -- Only the Event's author (or an Admin) can ever push it to a `SyncDestination`
                -- (the backend RPC only checks the destination's own ownership, not the content's
                -- -- but showing a "push someone else's Event to my own Page" button here would be
                -- surprising and isn't offered anywhere else in the app, so this page stays
                -- consistent with that). Guarded on `availableSyncDestinations == Nothing` so a
                -- post-edit `refetch` doesn't re-issue this every time.
                syncDestinationsFetchEffect : Effect Msg
                syncDestinationsFetchEffect =
                    case ( newStatus, model.availableSyncDestinations, serverAndAccount shared model ) of
                        ( EventLoaded event _, Nothing, Just ( server, account ) ) ->
                            let
                                isOwner : Bool
                                isOwner =
                                    event.post
                                        |> Maybe.map (Posts.isAuthor account)
                                        |> Maybe.withDefault False
                            in
                            if isOwner || List.member ADMIN account.permissions then
                                SyncDestinations.getSyncDestinations shared.accounts ( Just account.userId, server.frontendHost ) ""
                                    |> Task.attempt GotSyncDestinationsResult
                                    |> Effect.fromCmd

                            else
                                Effect.none

                        _ ->
                            Effect.none

                modelWithNewStatus : Model
                modelWithNewStatus =
                    { model | eventStatus = newStatus }

                clampedModel : Model
                clampedModel =
                    case newStatus of
                        EventLoaded _ loadedOccasion ->
                            clampHistoryDisplay shared.time.now loadedOccasion modelWithNewStatus

                        _ ->
                            modelWithNewStatus
            in
            ( clampedModel |> syncOccasionAnimations shared.time.now
            , Effect.batch [ accountEffect, breadcrumbsEffect, scrollEffect, syncDestinationsFetchEffect ]
            )

        GotEvent (Err _) ->
            ( { model | eventStatus = EventFailed }, Effect.none )

        GotSyncDestinationsResult (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | availableSyncDestinations = Just response.destinations }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSyncDestinationsResult (Err _) ->
            ( model, Effect.none )

        MediaClicked post mediaId ->
            ( model, Effect.fromShared (Shared.MediaViewerPanelMsg (MediaViewerPanel.Open post.media (Just post) mediaId model.targetHost)) )

        MediaEditClicked post ->
            ( { model | mediaEditActive = True }
            , Effect.fromShared
                (Shared.MyMediaPanelMsg
                    (MyMediaPanel.Open
                        (Just (MyMediaPanel.MultiSelect { initialSelection = post.media }))
                        model.targetHost
                    )
                )
            )

        GenerateMediaClicked event occasion ->
            ( { model | mediaGeneratorActive = True }
            , Effect.fromShared
                (Shared.MediaGeneratorPanelMsg
                    (MediaGeneratorPanel.Open (Just (MediaGeneratorPanel.TargetEvent event occasion)) model.targetHost shared.basePath)
                )
            )

        GotMediaUpdateResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            ( applyUpdatedEventPost model updatedPost, accountsPanelEffect maybeAccountsPanelMsg )

        GotMediaUpdateResult (Err _) ->
            ( model, Effect.none )

        PostFieldEditClicked field post ->
            ( { model
                | postFieldEdit =
                    Just
                        { field = field
                        , pending =
                            case field of
                                TitleField ->
                                    Maybe.withDefault "" post.title

                                LinkField ->
                                    Maybe.withDefault "" post.link
                        , status = Idle
                        }
              }
            , Effect.none
            )

        PostFieldChanged text ->
            ( { model | postFieldEdit = model.postFieldEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        PostFieldCancelClicked ->
            ( { model | postFieldEdit = Nothing }, Effect.none )

        PostFieldSaveClicked post ->
            case ( model.postFieldEdit, serverAndAccount shared model ) of
                ( Just edit, Just ( server, account ) ) ->
                    ( { model | postFieldEdit = Just { edit | status = Submitting } }
                    , Posts.updatePost
                        shared.accounts
                        ( Just account.userId, server.frontendHost )
                        post.id
                        (\freshPost ->
                            case edit.field of
                                TitleField ->
                                    { freshPost | title = nonBlank edit.pending }

                                LinkField ->
                                    { freshPost | link = nonBlank edit.pending }
                        )
                        |> Task.attempt GotPostFieldSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPostFieldSaveResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            let
                updatedModel : Model
                updatedModel =
                    applyUpdatedEventPost model updatedPost
            in
            ( { updatedModel | postFieldEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotPostFieldSaveResult (Err err) ->
            ( { model
                | postFieldEdit =
                    model.postFieldEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        EditContentClicked post ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.PostContent post) model.targetHost)) )

        ModerationEditClicked event ->
            case event.post of
                Just post ->
                    ( { model | moderationEdit = Just { pending = post.moderation, status = Idle } }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        ModerationChanged text ->
            ( { model
                | moderationEdit =
                    model.moderationEdit
                        |> Maybe.map (\edit -> { edit | pending = Posts.moderationFromText text |> Maybe.withDefault edit.pending })
              }
            , Effect.none
            )

        ModerationCancelClicked ->
            ( { model | moderationEdit = Nothing }, Effect.none )

        ModerationSaveClicked event ->
            case ( model.moderationEdit, event.post, serverAndAccount shared model ) of
                ( Just edit, Just post, Just ( server, account ) ) ->
                    ( { model | moderationEdit = Just { edit | status = Submitting } }
                    , Posts.updatePost
                        shared.accounts
                        ( Just account.userId, server.frontendHost )
                        post.id
                        (\freshPost -> { freshPost | moderation = edit.pending })
                        |> Task.attempt GotModerationSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotModerationSaveResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            let
                updatedModel : Model
                updatedModel =
                    applyUpdatedEventPost model updatedPost
            in
            ( { updatedModel | moderationEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotModerationSaveResult (Err err) ->
            ( { model
                | moderationEdit =
                    model.moderationEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        VisibilityEditClicked post ->
            ( { model | visibilityEdit = Just { pending = post.visibility, status = Idle } }, Effect.none )

        VisibilityChanged text ->
            ( { model
                | visibilityEdit =
                    model.visibilityEdit
                        |> Maybe.map (\edit -> { edit | pending = Posts.visibilityFromText text |> Maybe.withDefault edit.pending })
              }
            , Effect.none
            )

        VisibilityCancelClicked ->
            ( { model | visibilityEdit = Nothing }, Effect.none )

        VisibilitySaveClicked post ->
            case ( model.visibilityEdit, serverAndAccount shared model ) of
                ( Just edit, Just ( server, account ) ) ->
                    ( { model | visibilityEdit = Just { edit | status = Submitting } }
                    , Posts.updatePost
                        shared.accounts
                        ( Just account.userId, server.frontendHost )
                        post.id
                        (\freshPost -> { freshPost | visibility = edit.pending })
                        |> Task.attempt GotVisibilitySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotVisibilitySaveResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            let
                updatedModel : Model
                updatedModel =
                    applyUpdatedEventPost model updatedPost
            in
            ( { updatedModel | visibilityEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotVisibilitySaveResult (Err err) ->
            ( { model
                | visibilityEdit =
                    model.visibilityEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        OccasionTimeEditClicked occasion ->
            ( { model
                | occasionTimeEdit =
                    Just
                        { pendingStartsAt = occasion.startsAt |> Maybe.map Conversions.timestampToPosix
                        , pendingEndsAt = occasion.endsAt |> Maybe.map Conversions.timestampToPosix
                        , pendingTimezone =
                            occasion.timezone
                                |> Maybe.withDefault shared.time.browserTimeZone.name
                        , status = Idle
                        }
              }
            , Effect.none
            )

        OccasionStartsAtChanged raw ->
            ( { model
                | occasionTimeEdit =
                    model.occasionTimeEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    newStartsAt : Maybe Time.Posix
                                    newStartsAt =
                                        SharedTime.posixFromDateTimeLocalInput shared.time.browserTimeZone.zone raw
                                in
                                { edit
                                    | pendingStartsAt = newStartsAt

                                    -- Mirrors `Shared.CreateNewPanel.update`'s own
                                    -- `StartsAtChanged` exactly: shifts `pendingEndsAt` by
                                    -- the same delta if both were already set, defaults it
                                    -- to an hour after the new start otherwise.
                                    , pendingEndsAt =
                                        case ( newStartsAt, edit.pendingStartsAt, edit.pendingEndsAt ) of
                                            ( Just newStart, Just oldStart, Just oldEnd ) ->
                                                Just (Time.millisToPosix (Time.posixToMillis oldEnd + (Time.posixToMillis newStart - Time.posixToMillis oldStart)))

                                            ( Just newStart, _, _ ) ->
                                                Just (Time.millisToPosix (Time.posixToMillis newStart + 3600000))

                                            ( Nothing, _, _ ) ->
                                                edit.pendingEndsAt
                                }
                            )
              }
            , Effect.none
            )

        OccasionEndsAtChanged raw ->
            ( { model
                | occasionTimeEdit =
                    model.occasionTimeEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    newEndsAt : Maybe Time.Posix
                                    newEndsAt =
                                        SharedTime.posixFromDateTimeLocalInput shared.time.browserTimeZone.zone raw
                                in
                                { edit
                                    -- Mirrors `Shared.CreateNewPanel.update`'s own
                                    -- `EndsAtChanged` exactly: clamps to at least a minute
                                    -- after `pendingStartsAt`, rather than rejecting
                                    -- outright.
                                    | pendingEndsAt =
                                        case ( newEndsAt, edit.pendingStartsAt ) of
                                            ( Just newEnd, Just startsAt ) ->
                                                Just (Time.millisToPosix (max (Time.posixToMillis newEnd) (Time.posixToMillis startsAt + 60000)))

                                            _ ->
                                                newEndsAt
                                }
                            )
              }
            , Effect.none
            )

        OccasionTimezoneChanged tz ->
            ( { model
                | occasionTimeEdit =
                    model.occasionTimeEdit |> Maybe.map (\edit -> { edit | pendingTimezone = tz })
              }
            , Effect.none
            )

        OccasionTimeCancelClicked ->
            ( { model | occasionTimeEdit = Nothing }, Effect.none )

        OccasionTimeSaveClicked occasion ->
            case ( model.occasionTimeEdit, model.eventStatus, serverAndAccount shared model ) of
                ( Just edit, EventLoaded event _, Just ( server, account ) ) ->
                    case ( edit.pendingStartsAt, edit.pendingEndsAt ) of
                        ( Just startsAt, Just endsAt ) ->
                            ( { model | occasionTimeEdit = Just { edit | status = Submitting } }
                            , Events.updateOccasions
                                shared.accounts
                                ( Just account.userId, server.frontendHost )
                                { event
                                    | occasions =
                                        [ { occasion
                                            | startsAt = Just (Conversions.posixToTimestamp startsAt)
                                            , endsAt = Just (Conversions.posixToTimestamp endsAt)
                                            , timezone = Just edit.pendingTimezone
                                          }
                                        ]
                                }
                                |> Task.attempt GotOccasionTimeSaveResult
                                |> Effect.fromCmd
                            )

                        _ ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotOccasionTimeSaveResult (Ok ( maybeAccountsPanelMsg, updatedEvent )) ->
            let
                updatedModel : Model
                updatedModel =
                    applyUpdatedEvent shared.time.now model updatedEvent
            in
            ( { updatedModel | occasionTimeEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotOccasionTimeSaveResult (Err err) ->
            ( { model
                | occasionTimeEdit =
                    model.occasionTimeEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        OccasionLocationEditClicked occasion ->
            ( { model
                | occasionLocationEdit =
                    Just
                        { pending = occasion.location |> Maybe.map .uniformlyFormattedAddress |> Maybe.withDefault ""
                        , status = Idle
                        }
              }
            , Effect.none
            )

        OccasionLocationChanged text ->
            ( { model | occasionLocationEdit = model.occasionLocationEdit |> Maybe.map (\edit -> { edit | pending = text }) }
            , Effect.none
            )

        OccasionLocationCancelClicked ->
            ( { model | occasionLocationEdit = Nothing }, Effect.none )

        OccasionLocationSaveClicked occasion ->
            case ( model.occasionLocationEdit, model.eventStatus, serverAndAccount shared model ) of
                ( Just edit, EventLoaded event _, Just ( server, account ) ) ->
                    let
                        newLocation : Maybe Location
                        newLocation =
                            if String.isEmpty (String.trim edit.pending) then
                                Nothing

                            else
                                Just { defaultLocation | uniformlyFormattedAddress = String.trim edit.pending }
                    in
                    ( { model | occasionLocationEdit = Just { edit | status = Submitting } }
                    , Events.updateOccasions
                        shared.accounts
                        ( Just account.userId, server.frontendHost )
                        { event | occasions = [ { occasion | location = newLocation } ] }
                        |> Task.attempt GotOccasionLocationSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotOccasionLocationSaveResult (Ok ( maybeAccountsPanelMsg, updatedEvent )) ->
            let
                updatedModel : Model
                updatedModel =
                    applyUpdatedEvent shared.time.now model updatedEvent
            in
            ( { updatedModel | occasionLocationEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotOccasionLocationSaveResult (Err err) ->
            ( { model
                | occasionLocationEdit =
                    model.occasionLocationEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        AddMoreClicked ->
            ( { model | addMoreMenu = Just { step = ChoosingCount, status = Idle } }, Effect.none )

        AddMoreClosed ->
            ( { model | addMoreMenu = Nothing }, Effect.none )

        AddMoreCountClicked count ->
            ( { model | addMoreMenu = model.addMoreMenu |> Maybe.map (\menu -> { menu | step = ChoosingFrequency count }) }
            , Effect.none
            )

        AddMoreBackClicked ->
            ( { model | addMoreMenu = model.addMoreMenu |> Maybe.map (\menu -> { menu | step = ChoosingCount }) }
            , Effect.none
            )

        AddMoreFrequencyClicked count unit ->
            case ( model.eventStatus, serverAndAccount shared model ) of
                ( EventLoaded event occasion, Just ( server, account ) ) ->
                    case buildRecurringOccasions shared.time.browserTimeZone.zone count unit occasion of
                        [] ->
                            ( model, Effect.none )

                        newOccasions ->
                            ( { model | addMoreMenu = model.addMoreMenu |> Maybe.map (\menu -> { menu | status = Submitting }) }
                            , Events.createNewOccasions
                                shared.accounts
                                ( Just account.userId, server.frontendHost )
                                { event | occasions = newOccasions }
                                |> Task.attempt GotAddMoreResult
                                |> Effect.fromCmd
                            )

                _ ->
                    ( model, Effect.none )

        GotAddMoreResult (Ok ( maybeAccountsPanelMsg, updatedEvent )) ->
            let
                updatedModel : Model
                updatedModel =
                    applyUpdatedEvent shared.time.now model updatedEvent
            in
            ( { updatedModel | addMoreMenu = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAddMoreResult (Err err) ->
            ( { model
                | addMoreMenu =
                    model.addMoreMenu |> Maybe.map (\menu -> { menu | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        DeleteClicked event ->
            ( model, Effect.fromShared (Shared.RequestDelete (Shared.ConfirmEventDelete event model.targetHost)) )

        DeleteOccasionClicked occasion event ->
            ( model, Effect.fromShared (Shared.RequestDelete (Shared.ConfirmOccasionDelete occasion event model.targetHost)) )

        ConnectClicked ->
            ( { model | connectStatus = ServerDependentView.Connecting }
            , RellmServers.connectToRellmServer model.pageIsSecure model.targetHost
                |> Task.attempt GotConnectResult
                |> Effect.fromCmd
            )

        GotConnectResult (Ok server) ->
            let
                ( newModel, fetchEffect ) =
                    fetchIfReady shared { model | connectStatus = ServerDependentView.NotConnected }
            in
            ( newModel
            , Effect.batch
                [ Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ServerConnected server))
                , fetchEffect
                ]
            )

        GotConnectResult (Err err) ->
            ( { model | connectStatus = ServerDependentView.ConnectFailed (AccountsPanel.grpcErrorToString err) }
            , Effect.none
            )

        EnableClicked ->
            ( model, Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ToggleServerEnabled model.targetHost)) )

        HistoryDisplayChanged mode ->
            if mode == model.occasionHistoryDisplay then
                -- Clicking the already-active mode's button changes nothing
                -- to animate (see `historyButtonView`'s highlighting) -- just
                -- re-centers the strip on the current occasion right away,
                -- e.g. after the user's scrolled it away by hand.
                ( model, scrollToOccasion 0 model.occasionId |> Effect.fromCmd )

            else
                ( { model | occasionHistoryDisplay = mode } |> syncOccasionAnimations shared.time.now
                , scrollToOccasion 1000 model.occasionId |> Effect.fromCmd
                )

        OccasionLayoutChanged layout ->
            ( { model | occasionLayout = layout }, Effect.none )

        AnimateItemFlip animMsg ->
            let
                step : String -> OccasionAnimation -> ( Dict String OccasionAnimation, List (Cmd Msg) ) -> ( Dict String OccasionAnimation, List (Cmd Msg) )
                step id anim ( animations, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert id { anim | flip = newFlip } animations, cmd :: accCmds )

                ( newOccasionAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.occasionAnimations
            in
            ( { model | occasionAnimations = newOccasionAnimations }, Cmd.batch cmds |> Effect.fromCmd )

        RemoveOccasionAnimation id ->
            ( { model | occasionAnimations = Dict.remove id model.occasionAnimations }, Effect.none )

        GotScrollTarget (Ok target) ->
            ( model
            , Ports.scrollElementLeft
                (Encode.object
                    [ ( "id", Encode.string occasionStripDomId )
                    , ( "left", Encode.float (max 0 target) )
                    ]
                )
                |> Effect.fromCmd
            )

        GotScrollTarget (Err _) ->
            ( model, Effect.none )

        Poll ->
            fetchIfReady shared model

        PushSyncDestinationClicked destinationId ->
            case ( model.eventStatus, serverAndAccount shared model ) of
                ( EventLoaded _ occasion, Just ( server, account ) ) ->
                    ( { model | syncDestinationPushStatuses = Dict.insert destinationId Submitting model.syncDestinationPushStatuses }
                    , Events.syncOccasion
                        shared.accounts
                        ( Just account.userId, server.frontendHost )
                        (occasion.post |> Maybe.map .id |> Maybe.withDefault "")
                        destinationId
                        |> Task.attempt (GotSyncDestinationPushResult destinationId)
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotSyncDestinationPushResult destinationId (Ok ( maybeAccountsPanelMsg, updatedOccasion )) ->
            ( { model
                | syncDestinationPushStatuses = Dict.remove destinationId model.syncDestinationPushStatuses
                , eventStatus =
                    case model.eventStatus of
                        EventLoaded event _ ->
                            EventLoaded event updatedOccasion

                        other ->
                            other
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSyncDestinationPushResult destinationId (Err err) ->
            ( { model | syncDestinationPushStatuses = Dict.insert destinationId (SubmitFailed (AccountsPanel.grpcErrorToString err)) model.syncDestinationPushStatuses }
            , Effect.none
            )

        SharedMsg subMsg ->
            let
                ( fetchedModel, fetchEffect ) =
                    case subMsg of
                        -- Also covers logging in/out of an Account for this
                        -- Event's own server (`AccountsPanel.
                        -- ToggleAccountEnabled`/`ToggleServerEnabled`) --
                        -- mirrors `Components.Pages.PostPage`'s identical branch,
                        -- see its own doc for why `refetch` (rather than
                        -- `fetchIfReady`, which no-ops once `fetchStarted` is
                        -- already `True`) is needed here.
                        Shared.AccountsPanelMsg _ ->
                            if model.fetchStarted && currentAccountId shared model /= model.fetchedAccountId then
                                refetch shared model

                            else
                                fetchIfReady shared model

                        -- `EditContentClicked`'s own Markdown panel save
                        -- succeeding -- mirrors `Components.Pages.PostPage`'s
                        -- identical branch, re-fetching the whole Event
                        -- (`refetch`) rather than re-fetching just the Post,
                        -- since there's no lighter-weight fetch for a single
                        -- Post already scoped to this page.
                        Shared.MarkdownPanelMsg (MarkdownPanel.GotSaveResult (Ok _)) ->
                            refetch shared model

                        -- See `Components.Pages.PostPage`'s own identical branch --
                        -- `mediaEditActive` (set by `MediaEditClicked`) gates
                        -- this the same way `avatarEdit`/`mediaEditActive`
                        -- gate their own panels elsewhere, so an unrelated
                        -- Save from some other use of the panel can't be
                        -- mistaken for this page's own Event Post edit.
                        Shared.MyMediaPanelMsg (MyMediaPanel.SaveMediaClicked mediaRefs) ->
                            if model.mediaEditActive then
                                case ( model.eventStatus, serverAndAccount shared model ) of
                                    ( EventLoaded event _, Just ( server, account ) ) ->
                                        case event.post of
                                            Just eventPost ->
                                                ( { model | mediaEditActive = False }
                                                , Posts.updatePost
                                                    shared.accounts
                                                    ( Just account.userId, server.frontendHost )
                                                    eventPost.id
                                                    (\freshPost -> { freshPost | media = mediaRefs })
                                                    |> Task.attempt GotMediaUpdateResult
                                                    |> Effect.fromCmd
                                                )

                                            Nothing ->
                                                ( { model | mediaEditActive = False }, Effect.none )

                                    _ ->
                                        ( { model | mediaEditActive = False }, Effect.none )

                            else
                                ( model, Effect.none )

                        Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked ->
                            ( { model | mediaEditActive = False }, Effect.none )

                        -- See `Components.Pages.PostPage`'s own identical branch -- `mediaGeneratorActive`
                        -- (set by `GenerateMediaClicked`) gates this the same "don't mistake an
                        -- unrelated use of the panel for this page's own" reasoning
                        -- `mediaEditActive` above already gives.
                        Shared.MediaGeneratorPanelMsg (MediaGeneratorPanel.GotGenerateResult (Ok _)) ->
                            if model.mediaGeneratorActive then
                                let
                                    ( refetchedModel, refetchEffect ) =
                                        refetch shared model
                                in
                                ( { refetchedModel | mediaGeneratorActive = False }, refetchEffect )

                            else
                                ( model, Effect.none )

                        Shared.MediaGeneratorPanelMsg MediaGeneratorPanel.CancelClicked ->
                            ( { model | mediaGeneratorActive = False }, Effect.none )

                        -- This page's own `DeleteClicked` (via
                        -- `Shared.RequestDelete`/`Shared.ConfirmDelete`)
                        -- resolving successfully -- navigate away, since
                        -- there's nothing left here to show.
                        Shared.GotEventDeleteResult (Ok _) ->
                            ( model, Browser.Navigation.pushUrl model.navKey (Gen.Route.toHref Gen.Route.Home_) |> Effect.fromCmd )

                        -- This page's own `DeleteOccasionClicked` resolving
                        -- successfully -- unlike `GotEventDeleteResult`
                        -- above, the Event itself still exists (`updatedEvent`
                        -- is `DeleteRemovedOccasions`' own return value,
                        -- carrying every surviving `Occasion`), so
                        -- navigate to one of those instead of bouncing away
                        -- entirely -- `List.head` picks whichever happens to
                        -- come back first, same "no particular ordering
                        -- promised or needed" reasoning `occasionHistoryView`
                        -- already accepts elsewhere on this page. Falls back
                        -- to Home only if that list is somehow empty (deleting
                        -- an occasion never leaves zero behind -- this button
                        -- only shows once there were at least two -- but
                        -- covers it exactly as gracefully as `GotEventDeleteResult`
                        -- would).
                        Shared.GotOccasionDeleteResult (Ok ( _, updatedEvent )) ->
                            case List.head updatedEvent.occasions of
                                Just sibling ->
                                    let
                                        siblingPostId : String
                                        siblingPostId =
                                            sibling.post |> Maybe.map .id |> Maybe.withDefault ""

                                        routeId : String
                                        routeId =
                                            if model.targetHost == shared.accounts.mainFrontendHost then
                                                siblingPostId

                                            else
                                                siblingPostId ++ "@" ++ model.targetHost
                                    in
                                    ( model
                                    , Browser.Navigation.pushUrl model.navKey (Gen.Route.toHref (Gen.Route.Event__PostId_ { postId = routeId }))
                                        |> Effect.fromCmd
                                    )

                                Nothing ->
                                    ( model, Browser.Navigation.pushUrl model.navKey (Gen.Route.toHref Gen.Route.Home_) |> Effect.fromCmd )

                        -- The "synced to" listing's own Delete button (see
                        -- `Model.syncDestinationPushStatuses`'s own doc)
                        -- resolving successfully -- mirrors
                        -- `Components.Pages.EventsPage`'s identical branch:
                        -- refetch, since a successful un-sync changes
                        -- `occasion.syncDestinations` behind this
                        -- already-fetched copy's back the same way, and the
                        -- result carries no destination id to patch it out
                        -- by hand with.
                        Shared.GotOccasionSyncDestinationDeleteResult _ (Ok _) ->
                            refetch shared model

                        _ ->
                            ( model, Effect.none )
            in
            ( fetchedModel, Effect.batch [ Effect.fromShared subMsg, fetchEffect ] )


{-| Mirrors `Components.Pages.PostPage.fetchIfReady` exactly -- kicks off the actual
`GetEvents` fetch the first time `targetHost` is a known, connected server
(see `RellmServers.knownConnectedRellmServer` -- a known-but-still-connecting
`targetHost`, e.g. right after startup, doesn't count).
-}
fetchIfReady : Shared.Model -> Model -> ( Model, Effect Msg )
fetchIfReady shared model =
    if model.fetchStarted then
        ( model, Effect.none )

    else
        case RellmServers.knownConnectedRellmServer shared.accounts.servers model.targetHost of
            Just _ ->
                ( { model | fetchStarted = True, fetchedAccountId = currentAccountId shared model }
                , Events.fetchEvent shared.accounts (maybeAccountServerFor shared model) model.occasionId
                    |> Task.attempt GotEvent
                    |> Effect.fromCmd
                )

            Nothing ->
                ( model, Effect.none )


{-| Mirrors `Components.Pages.PostPage.refetch` exactly -- re-fetches the Event
unconditionally (unlike `fetchIfReady`, not gated on `fetchStarted`, which is
already `True` by the time this is ever called) -- for `update`'s `SharedMsg`
branch to call once the Markdown panel (see `Shared.MarkdownPanel`) reports a
successful save to the Event's own primary `Post`'s content
(`EditContentClicked`/`MarkdownPanel.PostContent`).
-}
refetch : Shared.Model -> Model -> ( Model, Effect Msg )
refetch shared model =
    ( { model | fetchedAccountId = currentAccountId shared model }
    , Events.fetchEvent shared.accounts (maybeAccountServerFor shared model) model.occasionId
        |> Task.attempt GotEvent
        |> Effect.fromCmd
    )


maybeAccountServerFor : Shared.Model -> Model -> AccountsPanel.MaybeAccountServer
maybeAccountServerFor shared model =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost |> Maybe.map .userId
    , model.targetHost
    )


{-| Mirrors `Components.Pages.PostPage.currentAccountId` exactly -- the
`RellmAccounts.rellmAccountId` of whichever account is currently signed in on
`model.targetHost` (the Event's own server), if any -- compared against
`model.fetchedAccountId` by `update`'s `SharedMsg` branch to notice an
`AccountsPanel.ToggleAccountEnabled`/`ToggleServerEnabled` changed who's
signed in here, and `refetch` accordingly.
-}
currentAccountId : Shared.Model -> Model -> Maybe String
currentAccountId shared model =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost
        |> Maybe.map RellmAccounts.rellmAccountId


{-| The connected `Server`/signed-in `Account` for `model.targetHost`, if
both exist -- what `MediaEditClicked`'s own save (via `Shared.MyMediaPanel`'s
`SaveMediaClicked`) needs to actually submit its `Posts.updatePost` task.
Mirrors `Components.Pages.PostPage.serverAndAccount`.
-}
serverAndAccount : Shared.Model -> Model -> Maybe ( RellmServer, RellmAccount )
serverAndAccount shared model =
    Maybe.map2 Tuple.pair
        (RellmServers.rellmServerForHost shared.accounts.servers model.targetHost)
        (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost)


{-| Applies a just-saved `updatedPost` to the currently-loaded `Event`'s own
`post` field (the only one `MediaEditClicked` ever opens the picker for, not
`occasion.post`) -- a no-op if the `Event` isn't loaded at all, which
shouldn't happen in practice (this is only ever called from
`GotMediaUpdateResult`, itself only reachable once `MediaEditClicked` has
already rendered from a loaded `Event`). Mirrors
`Components.Pages.PostPage.applyUpdatedPost`, just updating a nested field rather
than `Model`'s own top-level `postStatus`.
-}
applyUpdatedEventPost : Model -> Post -> Model
applyUpdatedEventPost model updatedPost =
    case model.eventStatus of
        EventLoaded event occasion ->
            { model | eventStatus = EventLoaded { event | post = Just updatedPost } occasion }

        _ ->
            model


{-| Applies a just-saved `updatedEvent` (`UpdateOccasions`'/
`CreateNewOccasions`' own return value -- both hand back the `Event`'s
full current state, not just the touched occasion(s)) as this page's new
`eventStatus` -- mirrors `GotEvent`'s own handling (re-clamping
`occasionHistoryDisplay` and re-syncing `occasionAnimations`, since
`CreateNewOccasions` can change how many occasions there are to animate)
rather than just `applyUpdatedEventPost`'s plain field patch. Re-finds
`model.occasionId` in `updatedEvent.occasions` (`Events.findOccasion`)
for the new "currently-viewed" `Occasion`, falling back to whichever one
was already loaded if -- unexpectedly -- it's gone missing (none of
`OccasionTimeSaveClicked`/`OccasionLocationSaveClicked`/`AddMoreFrequencyClicked`
can actually remove it). A no-op if the `Event` isn't loaded at all, same
"shouldn't happen in practice" reasoning as `applyUpdatedEventPost`.
-}
applyUpdatedEvent : Time.Posix -> Model -> Event -> Model
applyUpdatedEvent now model updatedEvent =
    case model.eventStatus of
        EventLoaded _ currentOccasion ->
            let
                newOccasion : Occasion
                newOccasion =
                    Events.findOccasion model.occasionId updatedEvent |> Maybe.withDefault currentOccasion
            in
            { model | eventStatus = EventLoaded updatedEvent newOccasion }
                |> clampHistoryDisplay now newOccasion
                |> syncOccasionAnimations now

        _ ->
            model


{-| Builds `count` new `Occasion`s to send to `CreateNewOccasions`
(via `AddMoreFrequencyClicked`), each `unit` further from `occasion`'s own
`startsAt`/`endsAt` than the last (`n = 1..count`, via `SharedTime.addRecurrence`
in `zone` -- see that function's own doc for the DST guarantee this relies
on). Every duplicate copies `occasion`'s own `post` (its title/link/content/
visibility override, if any), `location`, and `timezone` verbatim -- nothing
about "add more like this one" should silently drop any of them. Copying `post` along also
copies its own id (an `Occasion`'s identity, post-migration -- see this
module's own top-of-file doc), but that's harmless: `create_occasion` on the
backend ignores whatever `id`/`author` a submitted `post` carries and always
creates a fresh Post authored by the caller, so every duplicate still ends up
a genuinely new `Occasion`, never mistaken for `occasion` itself.
Everything else is left at `defaultOccasion`'s blank defaults.
`[]` (a no-op back in `AddMoreFrequencyClicked`) if `occasion` is missing
either `startsAt` or `endsAt`, which shouldn't happen in practice -- both are
required fields everywhere an `Occasion` is created.
-}
buildRecurringOccasions : Time.Zone -> Int -> SharedTime.RecurrenceUnit -> Occasion -> List Occasion
buildRecurringOccasions zone count unit occasion =
    case ( occasion.startsAt, occasion.endsAt ) of
        ( Just startsAtTimestamp, Just endsAtTimestamp ) ->
            let
                baseStartsAt : Time.Posix
                baseStartsAt =
                    Conversions.timestampToPosix startsAtTimestamp

                baseEndsAt : Time.Posix
                baseEndsAt =
                    Conversions.timestampToPosix endsAtTimestamp
            in
            List.range 1 count
                |> List.map
                    (\n ->
                        { defaultOccasion
                            | post = occasion.post
                            , location = occasion.location
                            , timezone = occasion.timezone
                            , startsAt = Just (Conversions.posixToTimestamp (SharedTime.addRecurrence zone unit n baseStartsAt))
                            , endsAt = Just (Conversions.posixToTimestamp (SharedTime.addRecurrence zone unit n baseEndsAt))
                        }
                    )

        _ ->
            []


{-| `count`'s own "N more" `RecurrenceUnit` options for the "Add More"
popover's second step (`ChoosingFrequency count`, see `addMoreMenuContentView`)
-- `Monthly` is only offered under 12 (per this feature's own request: a
monthly series past a year starts feeling like the wrong tool, and the
day-of-month clamping `SharedTime.addRecurrence`'s own doc describes gets
more noticeable the further out it compounds).
-}
availableFrequencies : Int -> List SharedTime.RecurrenceUnit
availableFrequencies count =
    if count < 12 then
        [ SharedTime.Daily, SharedTime.Weekly, SharedTime.Monthly ]

    else
        [ SharedTime.Daily, SharedTime.Weekly ]


{-| `unit`'s own label for `count`'s "Add More" frequency button
(`addMoreMenuContentView`) -- `count == 1` reads as a plain calendar
shorthand ("Tomorrow"/"Next Week"/"Next Month") rather than "Daily"/"Weekly"/
"Monthly", which would misleadingly suggest an ongoing series for what's
actually a single extra date.
-}
frequencyLabel : Int -> SharedTime.RecurrenceUnit -> String
frequencyLabel count unit =
    case ( count == 1, unit ) of
        ( True, SharedTime.Daily ) ->
            "Tomorrow"

        ( True, SharedTime.Weekly ) ->
            "Next Week"

        ( True, SharedTime.Monthly ) ->
            "Next Month"

        ( False, SharedTime.Daily ) ->
            "Daily"

        ( False, SharedTime.Weekly ) ->
            "Weekly"

        ( False, SharedTime.Monthly ) ->
            "Monthly"


{-| `Just text` unless `text` is blank, `Nothing` otherwise -- used by
`PostFieldSaveClicked` to translate an edit form's plain `String` input into
`Post.title`/`Post.link`/`Post.content`'s own `Maybe String`, matching how an
empty field means "unset" everywhere else these fields are read (e.g.
`Components.Posts.postLinkText`).
-}
nonBlank : String -> Maybe String
nonBlank text =
    if String.isEmpty (String.trim text) then
        Nothing

    else
        Just text


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page
into `update`'s `SharedMsg` branch, without exposing the `SharedMsg`
constructor itself (and thus every other constructor of this otherwise-opaque
`Msg`) outside this module. Mirrors `Components.Pages.PostPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect Msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


{-| Whether `occasion` belongs in the strip under `mode` -- `ShowAllOccasions`
takes everything, `SinceTwoWeeksAgo`/`OnlyFuture` cut off at 14 days before
`now`/`now` itself (via `Components.Events.occasionMoment`). An occasion with
no resolvable time at all (`occasionMoment == Nothing`) always passes, same
"can't tell, so don't hide it" reasoning as `Components.Events.occasionMoment`
falling back to `startsAt`.
-}
occasionMatchesHistoryDisplay : Time.Posix -> OccasionHistoryDisplay -> Occasion -> Bool
occasionMatchesHistoryDisplay now mode occasion =
    case mode of
        ShowAllOccasions ->
            True

        SinceTwoWeeksAgo ->
            occasionAtOrAfter (twoWeeksBefore now) occasion

        OnlyFuture ->
            occasionAtOrAfter now occasion


occasionAtOrAfter : Time.Posix -> Occasion -> Bool
occasionAtOrAfter threshold occasion =
    case Events.occasionEndsOrStartsAt occasion of
        Just moment ->
            Time.posixToMillis moment >= Time.posixToMillis threshold

        Nothing ->
            True


twoWeeksBefore : Time.Posix -> Time.Posix
twoWeeksBefore now =
    Time.millisToPosix (Time.posixToMillis now - 14 * 24 * 60 * 60 * 1000)


{-| `OnlyFuture` < `SinceTwoWeeksAgo` < `ShowAllOccasions`, as an `Int` --
`OnlyFuture`'s own set of occasions is always a subset of `SinceTwoWeeksAgo`'s,
which is always a subset of `ShowAllOccasions`'s, so this ordering is exactly
"how restrictive a mode is" -- used by `minimumHistoryDisplayFor`/
`clampHistoryDisplay`/`historyButtons` to compare modes without a full `case`
each time.
-}
historyDisplayRank : OccasionHistoryDisplay -> Int
historyDisplayRank mode =
    case mode of
        OnlyFuture ->
            0

        SinceTwoWeeksAgo ->
            1

        ShowAllOccasions ->
            2


{-| The least-inclusive `OccasionHistoryDisplay` that still keeps `occasion`
in the strip -- `OnlyFuture` for an upcoming
occasion, `SinceTwoWeeksAgo` for one less than two weeks in the past,
`ShowAllOccasions` for anything older than that. Used by both
`clampHistoryDisplay` (to pick this page's own initial mode) and
`historyButtons` (to never offer a switch that would hide the very occasion
the page is showing) -- see either's own doc.
-}
minimumHistoryDisplayFor : Time.Posix -> Occasion -> OccasionHistoryDisplay
minimumHistoryDisplayFor now occasion =
    if occasionMatchesHistoryDisplay now OnlyFuture occasion then
        OnlyFuture

    else if occasionMatchesHistoryDisplay now SinceTwoWeeksAgo occasion then
        SinceTwoWeeksAgo

    else
        ShowAllOccasions


{-| Raises `model.occasionHistoryDisplay` up to `minimumHistoryDisplayFor
now occasion` if it's currently more restrictive than that -- never lowers
it, so this is safe to call every time the loaded `Event` changes
(`GotEvent`) without ever undoing a broader mode the user already switched
to via `historyButtonView`, whose button for any mode below that same
`minimumHistoryDisplayFor` floor is `disabled` rather than removed, so
there's no way to have reached one of those in the first place. In practice
this is what actually picks this page's initial mode: `init` always starts
`model.occasionHistoryDisplay` at `OnlyFuture` (the most restrictive
possible value) before the `Event` is known, so the first call once it
lands is the one that raises it to wherever the currently-viewed `occasion`
actually needs. `now` is `Shared.Model.time.now` -- see its own doc.
-}
clampHistoryDisplay : Time.Posix -> Occasion -> Model -> Model
clampHistoryDisplay now occasion model =
    let
        minimum : OccasionHistoryDisplay
        minimum =
            minimumHistoryDisplayFor now occasion
    in
    if historyDisplayRank model.occasionHistoryDisplay < historyDisplayRank minimum then
        { model | occasionHistoryDisplay = minimum }

    else
        model


{-| Reconciles `occasionAnimations` with whichever of `event.occasions`
`model.occasionHistoryDisplay` currently selects -- newly-revealed occasions
(switching to a broader mode, e.g. `OnlyFuture` -> `ShowAllOccasions`) fade
in, newly-hidden ones (the reverse) fade/collapse out rather than just
vanishing, and the ones staying visible are left alone. A no-op while the
`Event` itself hasn't loaded yet. Mirrors
`Shared.MyMediaPanel.syncMediaAnimations` -- see its own doc; called from
every `update` branch that can change either input: `GotEvent` and
`HistoryDisplayChanged`. `now` is `Shared.Model.time.now` -- see its own doc.
-}
syncOccasionAnimations : Time.Posix -> Model -> Model
syncOccasionAnimations now model =
    case model.eventStatus of
        EventLoaded event _ ->
            let
                currentOccasions : Dict String Occasion
                currentOccasions =
                    event.occasions
                        |> List.filter (occasionMatchesHistoryDisplay now model.occasionHistoryDisplay)
                        |> List.map (\occasion -> ( occasion.post |> Maybe.map .id |> Maybe.withDefault "", occasion ))
                        |> Dict.fromList
            in
            { model
                | occasionAnimations =
                    UI.Flip.syncAnimations
                        RemoveOccasionAnimation
                        (\occasion -> { occasion = occasion, flip = UI.Flip.enter })
                        (\occasion anim -> { anim | occasion = occasion })
                        currentOccasions
                        model.occasionAnimations
            }

        _ ->
            model


{-| The DOM id `occasionHistoryView`'s scrollable strip is rendered with --
paired with `occasionChipDomId` by `scrollToOccasion`.
-}
occasionStripDomId : String
occasionStripDomId =
    "event-occasion-strip"


occasionChipDomId : String -> String
occasionChipDomId occasionId =
    "event-occasion-chip-" ++ occasionId


{-| Scrolls `occasionStripDomId`'s strip horizontally so `occasionId`'s own
chip is centered in view -- fired both whenever a new `Occasion` becomes
"the current one" (a fresh page load, or the user clicking to a sibling
occasion's own page -- see `GotEvent`) and whenever `HistoryDisplayChanged`
reveals/hides other chips around it, potentially shifting its position.
`Process.sleep delayMs` first in both cases: measuring immediately would read
some chip's still-collapsed (`grid-template-columns: 0fr`, see `flip.css`)
0-width position rather than its real, grown-in one, since a chip's own
`UI.Flip.enter`/`remove` animation is still in progress at the moment either
caller's own model update lands -- `GotEvent` passes 300ms (every chip,
including ones that were already visible, starts a fresh `enter` whenever
`syncOccasionAnimations` rebuilds `occasionAnimations` from scratch, as it
does right after `GotEvent`), `HistoryDisplayChanged` passes 400ms (only the
chips actually entering/leaving are mid-animation, but there's usually more
of them sliding at once than a fresh page load ever has, so a little more
headroom). Either way this clears `flip.css`'s own 0.25s collapse/grow transition.
Silently gives up (`GotScrollTarget`'s `Err` case is a no-op) if the strip or
chip aren't found -- e.g. an `Event` with only one occasion, whose strip
`occasionHistoryView` doesn't render at all.

Only _measures_ here (`Dom.getElement`/`Dom.getViewportOf`) -- the actual
scroll happens back in `update`'s `GotScrollTarget` case, via
`Ports.scrollElementLeft` rather than `Dom.setViewportOf`. See that port's own
doc comment: `Dom.setViewportOf` always assigns `scrollLeft` from inside a
`requestAnimationFrame` callback, which silently fails to take effect at all
on an element with this strip's own `scroll-behavior: smooth` (see
`events.css`), even though the `Task` itself reports success -- confirmed by
instrumenting a real run (a `GotScrollTarget`-equivalent debug message
reported the correct computed target every time, yet `scrollLeft` never
budged) and reproducing it directly (`requestAnimationFrame(() => { el.scrollLeft
= x })`, checked a frame later, silently no-ops the same way). A port
callback is a plain (non-rAF-wrapped) JS callback, and doesn't have the
problem.

-}
scrollToOccasion : Float -> String -> Cmd Msg
scrollToOccasion delayMs occasionId =
    Process.sleep delayMs
        |> Task.andThen
            (\_ ->
                Task.map3 (\chip strip viewport -> ( chip, strip, viewport ))
                    (Dom.getElement (occasionChipDomId occasionId))
                    (Dom.getElement occasionStripDomId)
                    (Dom.getViewportOf occasionStripDomId)
            )
        |> Task.map
            (\( chip, strip, viewport ) ->
                let
                    chipLeftWithinStrip : Float
                    chipLeftWithinStrip =
                        chip.element.x - strip.element.x
                in
                viewport.viewport.x
                    + chipLeftWithinStrip
                    - (viewport.viewport.width / 2)
                    + (chip.element.width / 2)
            )
        |> Task.attempt GotScrollTarget



-- VIEW


{-| Just the body content -- the calling page wraps this in `UI.layout`/its own title (via
`titleFor`), same split as `Components.Pages.PostPage.view`/etc.
-}
view : Shared.Model -> Model -> Html Msg
view shared model =
    ServerDependentView.view
        { hostname = model.targetHost
        , servers = shared.accounts.servers
        , accounts = shared.accounts.accounts
        , connectStatus = model.connectStatus
        , onConnectClicked = ConnectClicked
        , onEnableClicked = EnableClicked
        }
        (\_ _ ->
            case model.eventStatus of
                LoadingEvent ->
                    p [ class "event-loading" ] [ text "Loading…" ]

                EventFailed ->
                    p [ class "event-error" ]
                        [ text
                            ("Couldn't load Event "
                                ++ model.occasionId
                                ++ "@"
                                ++ model.targetHost
                                ++ ". Maybe it doesn't exist, or maybe you need to be logged in?"
                            )
                        ]

                EventLoaded event occasion ->
                    eventDetailView shared model event occasion
        )


{-| Just the subtitle -- the loaded Event's own title, or "Event &lt;id&gt;" before it's loaded --
for the calling page's own `UI.pageTitle`. Mirrors `Components.Pages.PostPage.titleFor`.
-}
titleFor : Model -> String
titleFor model =
    case model.eventStatus of
        EventLoaded event _ ->
            event.post |> Maybe.map Posts.postTitleText |> Maybe.withDefault ("Event " ++ model.occasionId)

        _ ->
            "Event " ++ model.occasionId


eventDetailView : Shared.Model -> Model -> Event -> Occasion -> Html Msg
eventDetailView shared model event occasion =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost shared.accounts.servers model.targetHost

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost
    in
    div [ classes [ "event-detail", hostnameToCSSClass model.targetHost, "border-color-primary-anchor-50" ] ]
        [ case event.post of
            Just eventPost ->
                let
                    -- An `Event` pulled in from an ICS/iCal subscription (see
                    -- `Events.hasIcsSyncSource`) gets re-synced from that feed
                    -- on every run of the backend's `sync_sources`
                    -- job, which would silently clobber any local edit to its
                    -- title/link/content -- so `titleView`/`linkView`/
                    -- `contentDisplayView` hide their own "Edit X" buttons
                    -- entirely for such an `Event` rather than letting one
                    -- through only to have it discarded on the next sync.
                    editable : Bool
                    editable =
                        not (Events.hasIcsSyncSource event)

                    -- Slotted between the byline and the media display in the primary
                    -- (`Event`) post section below -- the currently-viewed
                    -- `Occasion`'s own start/end/location, then (below that) the
                    -- date-picker strip to switch to a sibling one.
                    occasionDetailAndStrip : Html Msg
                    occasionDetailAndStrip =
                        div [ class "event-occasion-detail-and-strip" ]
                            [ div [ class "event-occasion-detail" ]
                                [ div [ class "event-occasion-detail-info" ]
                                    [ occasionTimeView shared maybeAccount model.occasionTimeEdit eventPost occasion
                                    , occasionLocationView maybeAccount model.occasionLocationEdit eventPost occasion
                                    ]
                                , addMoreView maybeAccount model eventPost occasion
                                ]
                            , occasionHistoryView shared model event occasion
                            ]
                in
                div []
                    [ div [ classes [ "event-post-section", hostnameToCSSClass model.targetHost, "event-post-primary" ] ]
                        [ h1 [ class "event-post-title" ] [ titleView editable model.postFieldEdit maybeAccount eventPost ]
                        , linkView editable model.postFieldEdit maybeAccount eventPost
                        , div [ class "event-post-meta" ]
                            [ text "by "
                            , Authors.link shared.basePath shared.accounts.mainFrontendHost model.targetHost maybeServer maybeAccount eventPost.author
                            , visibilityView maybeAccount model.visibilityEdit eventPost
                            , moderationView maybeAccount model.moderationEdit event eventPost
                            ]
                        , occasionDetailAndStrip
                        , case maybeServer of
                            Just server ->
                                let
                                    -- `Nothing` when the viewer has no image-capable `AIModel`
                                    -- at all -- see `Posts.generateMediaButton`'s own doc, mirrors
                                    -- `Components.Pages.PostPage.postDetailView`'s identical
                                    -- `onGenerateMediaClicked`.
                                    onGenerateMediaClicked : Maybe Msg
                                    onGenerateMediaClicked =
                                        case maybeAccount of
                                            Just account ->
                                                if List.any AIProviders.hasAnyImageCapability account.aiModels then
                                                    Just (GenerateMediaClicked event occasion)

                                                else
                                                    Nothing

                                            Nothing ->
                                                Nothing
                                in
                                div []
                                    [ MultiMediaRenderer.view eventPost.postMediaLayout server maybeAccount shared.mediaRenderer (\id -> SharedMsg (Shared.MediaRendererMsg (MediaRenderer.PlayClicked id))) (MediaClicked eventPost) eventPost.media
                                    , div [ class "event-post-media-edit-row" ]
                                        [ Posts.mediaEditButton maybeAccount (MediaEditClicked eventPost) eventPost
                                        , Posts.generateMediaButton maybeAccount onGenerateMediaClicked eventPost
                                        ]
                                    ]

                            Nothing ->
                                text ""
                        , contentDisplayView editable maybeAccount eventPost
                        ]
                    , div [ class "post-detail-edit-row" ]
                        [ deleteButtonView maybeAccount event eventPost
                        , deleteOccasionButtonView maybeAccount event eventPost occasion
                        ]
                    ]

            Nothing ->
                text ""
        , case occasion.post |> Maybe.andThen Events.meaningfulPost of
            Just occasionPost ->
                div [ classes [ "event-post-section", hostnameToCSSClass model.targetHost, "event-post-secondary" ] ]
                    [ h2 [ class "event-post-title" ] [ text (Posts.postTitleText occasionPost) ]
                    , case Posts.postLinkText occasionPost of
                        Just link ->
                            a
                                [ href link
                                , target "_blank"
                                , rel "noopener noreferrer"
                                , classes [ hostnameToCSSClass model.targetHost, "event-post-link" ]
                                ]
                                [ text link ]

                        Nothing ->
                            text ""
                    , div [ class "event-post-meta" ]
                        [ text "by "
                        , Authors.link shared.basePath shared.accounts.mainFrontendHost model.targetHost maybeServer maybeAccount occasionPost.author
                        , if Posts.showPostVisibility maybeAccount occasionPost then
                            text (" · " ++ Posts.postVisibilityText occasionPost)

                          else
                            text ""
                        ]
                    , case maybeServer of
                        Just server ->
                            MultiMediaRenderer.view occasionPost.postMediaLayout server maybeAccount shared.mediaRenderer (\id -> SharedMsg (Shared.MediaRendererMsg (MediaRenderer.PlayClicked id))) (MediaClicked occasionPost) occasionPost.media

                        Nothing ->
                            text ""
                    , case occasionPost.content of
                        Just content ->
                            Markdown.view [ class "event-post-content" ] content

                        Nothing ->
                            text ""
                    ]

            Nothing ->
                text ""
        , occasionMetaView shared model occasion
        , Events.syncSourceView event

        -- `model.availableSyncDestinations` is `Nothing` until `GotEvent` confirms the viewer is
        -- this Event's author (or Admin) and its own fetch resolves (see that Msg's own doc) --
        -- until/unless that happens (including for every non-author, non-Admin viewer, who never
        -- triggers the fetch at all), this falls back to `eventSyncDestinationsView`'s `Nothing`
        -- behavior: plain read-only "synced to <url>" links, no Push/Delete buttons at all -- a
        -- deliberate improvement over this view's pre-`availableSyncDestinations` behavior, which
        -- showed every viewer a Delete button that only ever worked for the destination's actual
        -- owner.
        , Events.eventSyncDestinationsView
            model.availableSyncDestinations
            (\destinationId -> Dict.get destinationId model.syncDestinationPushStatuses == Just Submitting)
            (\destinationId ->
                case Dict.get destinationId model.syncDestinationPushStatuses of
                    Just (SubmitFailed err) ->
                        Just err

                    _ ->
                        Nothing
            )
            PushSyncDestinationClicked
            (\destinationId destinationLabel ->
                SharedMsg (Shared.RequestDelete (Shared.ConfirmOccasionSyncDestinationDelete occasion destinationId destinationLabel model.targetHost))
            )
            occasion
        ]


{-| The primary post section's `<h1>` content (see `eventDetailView`) --
always rendered, even when nothing's being edited, since (per this feature's
own request) there's no shared "edit row" collecting every field's edit
button in one place; each field's own "Edit X" button
(`postFieldEditButtonView`) sits right next to that field instead. Mirrors
`linkView` exactly, just for the title (`contentDisplayView` is the odd one
out among the three -- see its own doc for why it needs no analogous
`contentView` wrapper). The secondary section (`occasionPost`) has no
editable fields, so it renders its title as plain text directly instead of
going through this.
-}
titleView : Bool -> Maybe PostFieldEdit -> Maybe RellmAccount -> Post -> Html Msg
titleView editable maybeEdit maybeAccount post =
    case maybeEdit of
        Just edit ->
            if edit.field == TitleField then
                postFieldEditFormView edit post

            else
                titleDisplayView editable maybeAccount post

        Nothing ->
            titleDisplayView editable maybeAccount post


{-| The title text plus its own "Edit Title" button, shown whenever the
title itself isn't the field currently being edited (see `titleView`) --
`editable` (see `eventDetailView`) hides the button entirely for an
ICS-synced `Event`.
-}
titleDisplayView : Bool -> Maybe RellmAccount -> Post -> Html Msg
titleDisplayView editable maybeAccount post =
    span [ class "event-post-title-display" ]
        [ text (Posts.postTitleText post)
        , if editable then
            postFieldEditButtonView TitleField "Edit Title" maybeAccount post

          else
            text ""
        ]


{-| The primary post section's link-line content (see `eventDetailView`) --
mirrors `titleView` exactly, just for the link:
its own "Edit Link" button sits right after the link (or, if `post` has none
set, right where the link would otherwise sit -- see `linkDisplayView`).
-}
linkView : Bool -> Maybe PostFieldEdit -> Maybe RellmAccount -> Post -> Html Msg
linkView editable maybeEdit maybeAccount post =
    case maybeEdit of
        Just edit ->
            if edit.field == LinkField then
                postFieldEditFormView edit post

            else
                linkDisplayView editable maybeAccount post

        Nothing ->
            linkDisplayView editable maybeAccount post


{-| The link (if `post` has one) plus its own "Edit Link" button, shown
whenever the link itself isn't the field currently being edited (see
`linkView`) -- the button renders regardless of whether `post` actually has
a link set, so there's still something to click to add one. `editable` (see
`eventDetailView`) hides the button entirely for an ICS-synced `Event`.
-}
linkDisplayView : Bool -> Maybe RellmAccount -> Post -> Html Msg
linkDisplayView editable maybeAccount post =
    span [ class "event-post-link-display" ]
        [ case Posts.postLinkText post of
            Just link ->
                a
                    [ href link
                    , target "_blank"
                    , rel "noopener noreferrer"
                    , class "event-post-link"
                    ]
                    [ text link ]

            Nothing ->
                text ""
        , if editable then
            postFieldEditButtonView LinkField "Edit Link" maybeAccount post

          else
            text ""
        ]


{-| The rendered Markdown content (if `post` has any) plus its own
"Edit Content" button, rendered directly in the primary post section (see
`eventDetailView`) -- unlike `titleView`/`linkView`, there's no in-progress
`PostFieldEdit` case to branch on here: the button opens the shared
`Shared.MarkdownPanel` (`EditContentClicked`) rather than an inline form, so
this is always just the display half. The button renders regardless of
whether `post` actually has content set, so there's still something to click
to add some.
-}
contentDisplayView : Bool -> Maybe RellmAccount -> Post -> Html Msg
contentDisplayView editable maybeAccount post =
    div [ class "event-post-content-display" ]
        [ case post.content of
            Just content ->
                Markdown.view [ class "event-post-content" ] content

            Nothing ->
                text ""
        , if editable then
            editButtonView "Edit Content" (EditContentClicked post) maybeAccount post

          else
            text ""
        ]


{-| The actual `<input>` + Save/Cancel controls for whichever of `TitleField`/
`LinkField` `edit.field` names -- mirrors `Components.Pages.PostPage.visibilityView`'s
edit half in spirit (a `pending`-vs-loaded split via `Model.postFieldEdit`),
just with a plain `<input>` instead of a `<select>`. Wraps in a `span`, valid
content for the `<h1>`/plain-link slot each replaces (see
`titleView`/`linkView`).
-}
postFieldEditFormView : PostFieldEdit -> Post -> Html Msg
postFieldEditFormView edit post =
    let
        ( fieldClass, placeholderText ) =
            case edit.field of
                TitleField ->
                    ( "event-post-field-edit-title", "Title" )

                LinkField ->
                    ( "event-post-field-edit-link", "Link (optional)" )
    in
    span [ class "event-post-field-edit" ]
        (Html.input
            [ type_ "text"
            , class fieldClass
            , placeholder placeholderText
            , value edit.pending
            , onInput PostFieldChanged
            ]
            []
            :: postFieldEditActionsView edit post
        )


{-| The Save/Cancel buttons (plus any `SubmitFailed` error) shared by every
`postFieldEditFormView` case -- reuses `Components.Pages.PostPage.visibilityView`'s
own `.post-visibility-save`/`.post-visibility-cancel`/`.post-visibility-error`
classes (posts.css) rather than `event-*` ones of its own.
-}
postFieldEditActionsView : PostFieldEdit -> Post -> List (Html Msg)
postFieldEditActionsView edit post =
    [ span [ class "event-occasion-edit-actions" ]
        [ button
            [ classes [ "post-visibility-save", "background-color-primary" ]
            , onClick (PostFieldSaveClicked post)
            , disabled (edit.status == Submitting)
            ]
            [ text
                (if edit.status == Submitting then
                    "Saving…"

                 else
                    "Save"
                )
            ]
        , button
            [ class "post-visibility-cancel"
            , onClick PostFieldCancelClicked
            , disabled (edit.status == Submitting)
            ]
            [ text "Cancel" ]
        ]
    , case edit.status of
        SubmitFailed err ->
            span [ class "post-visibility-error" ] [ text err ]

        _ ->
            text ""
    ]


{-| `field`'s own "Edit X" button, opening `postFieldEditFormView` for just
that field -- thin wrapper around `editButtonView` for `titleDisplayView`/
`linkDisplayView`'s own `PostFieldEditClicked` buttons.
-}
postFieldEditButtonView : PostField -> String -> Maybe RellmAccount -> Post -> Html Msg
postFieldEditButtonView field label maybeAccount post =
    editButtonView label (PostFieldEditClicked field post) maybeAccount post


{-| A single "Edit X" button, slotted right next to the field it edits (see
`titleDisplayView`/`linkDisplayView`/`contentDisplayView`) rather than
collected into a shared row -- `onClickMsg` is whatever opening that field's
own editor takes (`PostFieldEditClicked` for title/link, via
`postFieldEditButtonView`; `EditContentClicked` directly for content, since
it has no `PostField` of its own -- see that type's doc). Shown to `post`'s
own author or an Admin, mirroring `Components.Pages.PostPage`'s own
`isAuthor account post`-gated edit affordances (media edit, visibility
edit). Reuses `Components.Posts`' `.post-edit-button` class (posts.css)
rather than an `event-*` one of its own, so it looks identical to
`postDetail`'s own "Edit Content" button.
-}
editButtonView : String -> Msg -> Maybe RellmAccount -> Post -> Html Msg
editButtonView label onClickMsg maybeAccount post =
    case maybeAccount of
        Just account ->
            if Posts.isAuthor account post || List.member ADMIN account.permissions then
                button [ class "post-edit-button", onClick onClickMsg ] [ text label ]

            else
                text ""

        Nothing ->
            text ""


{-| The delete button for the Event's own `Post`, shown only to its own
owner (per this feature's own scope -- unlike `postFieldEditButtonView`,
not extended to Admins here) -- opens the shared "are you sure?" dialog via
`DeleteClicked`/`Shared.ConfirmEventDelete`. Labeled "Delete Event" (not just
"Delete") to read distinctly from `deleteOccasionButtonView`'s "Delete
Occasion" beside it -- deleting the whole Event is a much bigger action than
deleting one of its dates. Not tied to any one field (unlike title/link/
content's own edit buttons), so it keeps its own `.post-detail-edit-row`
below the primary post section (see `eventDetailView`) rather than sitting
next to a field -- reuses that row's `.post-edit-button` class rather than
`postActionsView`'s `.post-delete-button` (which only resolves its own
styling via the `.post-actions` parent postDetail wraps it in, and would look
inconsistent here).
-}
deleteButtonView : Maybe RellmAccount -> Event -> Post -> Html Msg
deleteButtonView maybeAccount event post =
    case maybeAccount of
        Just account ->
            if Posts.isAuthor account post then
                button [ class "post-edit-button", onClick (DeleteClicked event) ] [ text "Delete Event" ]

            else
                text ""

        Nothing ->
            text ""


{-| The "Delete Occasion" button next to `deleteButtonView`'s "Delete Event"
(same row, same `.post-edit-button` styling, same owner-only gate) --
only rendered once `event` has more than one `Occasion`: with exactly
one, deleting it *is* deleting the Event (see `ConfirmOccasionDelete`'s
own doc for why), so `deleteButtonView`'s own button already covers that
case and a second one here would be redundant at best, misleading at worst.
Opens the same shared "are you sure?" dialog as `deleteButtonView`, via
`DeleteOccasionClicked`/`Shared.ConfirmOccasionDelete`, for just the
currently-viewed `occasion`.
-}
deleteOccasionButtonView : Maybe RellmAccount -> Event -> Post -> Occasion -> Html Msg
deleteOccasionButtonView maybeAccount event post occasion =
    case maybeAccount of
        Just account ->
            if Posts.isAuthor account post && List.length event.occasions > 1 then
                button [ class "post-edit-button", onClick (DeleteOccasionClicked occasion event) ] [ text "Delete Occasion" ]

            else
                text ""

        Nothing ->
            text ""


{-| The visibility segment slotted into the primary post section's byline
(see `eventDetailView`), right before `moderationView` -- mirrors that
function's own display-vs-editing split (and reuses its exact "Edit"-button
gate, `Posts.isAuthor account post || ADMIN`, via `editButtonView`) but for
`Visibility` instead of `Moderation`, submitted via plain `UpdatePost`
(`VisibilitySaveClicked`) rather than `UpdateOccasions`/
`CreateNewOccasions` -- see `Msg.VisibilityEditClicked`'s own doc for
why the Event's own `Post` fields don't need the heavier RPCs. Options are
narrowed to whatever `maybeAccount` can actually publish at
(`Posts.allowedVisibilities`), mirroring
`Components.Pages.PostPage.visibilityView` exactly.
-}
visibilityView : Maybe RellmAccount -> Maybe VisibilityEdit -> Post -> Html Msg
visibilityView maybeAccount maybeEdit post =
    case ( maybeEdit, maybeAccount ) of
        ( Just edit, Just account ) ->
            span [ class "post-visibility-edit" ]
                [ text " · "
                , span [ class "post-visibility-edit-controls" ]
                    [ select [ onInput VisibilityChanged ]
                        (Posts.allowedVisibilities account.permissions post.context post.visibility
                            |> List.map
                                (\visibility ->
                                    option
                                        [ value (Posts.visibilityText visibility)
                                        , selected (edit.pending == visibility)
                                        ]
                                        [ text (Posts.visibilityText visibility) ]
                                )
                        )
                    , span [ class "event-occasion-edit-actions" ]
                        [ button
                            [ classes [ "post-visibility-save", "background-color-primary" ]
                            , onClick (VisibilitySaveClicked post)
                            , disabled (edit.status == Submitting)
                            ]
                            [ text
                                (if edit.status == Submitting then
                                    "Saving…"

                                 else
                                    "Save"
                                )
                            ]
                        , button
                            [ class "post-visibility-cancel"
                            , onClick VisibilityCancelClicked
                            , disabled (edit.status == Submitting)
                            ]
                            [ text "Cancel" ]
                        ]
                    , case edit.status of
                        SubmitFailed err ->
                            span [ class "post-visibility-error" ] [ text err ]

                        _ ->
                            text ""
                    ]
                ]

        _ ->
            if Posts.showPostVisibility maybeAccount post then
                span [ class "post-visibility-display" ]
                    [ text (" · " ++ Posts.postVisibilityText post)
                    , editButtonView "Edit Visibility" (VisibilityEditClicked post) maybeAccount post
                    ]

            else
                text ""


{-| The moderation-status segment slotted into the primary post section's
byline (see `eventDetailView`) -- shown only to an Admin or a
`MODERATEEVENTS` holder, mirroring `Components.Pages.PostPage.visibilityView`'s
display-vs-editing split, just for `Moderation` instead of `Visibility`, and
its own "Edit" button reading "Moderate" instead (per this feature's own
request, to read distinctly from `postFieldEditButtonView`'s "Edit X"). Reuses
`Components.Pages.PostPage.moderationView`'s own `.post-moderation-*` classes
(posts.css) rather than `event-*` ones of its own, so it looks identical to
`postDetail`'s own moderation controls.
-}
moderationView : Maybe RellmAccount -> Maybe ModerationEdit -> Event -> Post -> Html Msg
moderationView maybeAccount maybeEdit event post =
    case maybeAccount of
        Nothing ->
            text ""

        Just account ->
            if not (List.member ADMIN account.permissions || List.member MODERATEEVENTS account.permissions) then
                text ""

            else
                case maybeEdit of
                    Just edit ->
                        span [ class "post-moderation-edit" ]
                            [ text " · "
                            , select [ onInput ModerationChanged ]
                                (Posts.allModerations
                                    |> List.map
                                        (\moderation ->
                                            option
                                                [ value (Users.moderationText moderation)
                                                , selected (edit.pending == moderation)
                                                ]
                                                [ text (Users.moderationText moderation) ]
                                        )
                                )
                            , button
                                [ classes [ "post-moderation-save", "background-color-primary" ]
                                , onClick (ModerationSaveClicked event)
                                , disabled (edit.status == Submitting)
                                ]
                                [ text
                                    (if edit.status == Submitting then
                                        "Saving…"

                                     else
                                        "Save"
                                    )
                                ]
                            , button
                                [ class "post-moderation-cancel"
                                , onClick ModerationCancelClicked
                                , disabled (edit.status == Submitting)
                                ]
                                [ text "Cancel" ]
                            , case edit.status of
                                SubmitFailed err ->
                                    span [ class "post-moderation-error" ] [ text err ]

                                _ ->
                                    text ""
                            ]

                    Nothing ->
                        span [ class "post-moderation-display" ]
                            [ text (" · " ++ Users.moderationText post.moderation)
                            , button [ class "post-moderation-edit-button", onClick (ModerationEditClicked event) ] [ text "Moderate" ]
                            ]


{-| Whether `occasion`'s own start/end time and location are safe to edit by
hand at all -- an occasion synced in from an ICS feed (`occasion.post.syncSource
/= Nothing`, set by `logic::sync_sources::event_sync::reconcile_occasions` when it creates
an occasion from a feed occurrence) has its `starts_at`/`ends_at`/`location`
silently overwritten back to the feed's own values on every subsequent sync
run (see that function's own `existing_occasion.starts_at != starts_at_db ||
...` check) -- exactly the same "would be clobbered on the next sync" problem
`editable`/`Events.hasIcsSyncSource` already guards title/link/content
against, just decided per-occasion rather than per-`Event`: an `Event` with a
sync source can still have manually-added occasions (via "Add More", which
never sets its occasion `Post`'s `syncSource`) safely alongside feed-sourced
ones, so this checks `occasion` itself rather than reusing `eventDetailView`'s
`editable`. Also gates `addMoreView`'s own button (see its own doc) -- "Add
More" duplicates `occasion`'s own `post`/`location` (see `buildRecurringOccasions`),
which reads as "add more dates like this synced one" in a way that doesn't
make sense for an occasion that isn't itself something the viewer set up by
hand.
-}
occasionEditable : Occasion -> Bool
occasionEditable occasion =
    (occasion.post |> Maybe.andThen .syncSource) == Nothing


{-| The currently-viewed `Occasion`'s own start/end time row (see
`eventDetailView`'s `occasionDetailAndStrip`) -- `Events.occasionWhenText`
plus its own "Edit Time" button when `maybeEdit == Nothing`, gated the same
way `editButtonView` gates every other field here (the Event's own `Post`'s
author, or an Admin -- passing `eventPost`, not `occasion.post`, since
editing an `Occasion`'s time/location is authorized against the
_Event_'s ownership server-side, see
`backend/src/rpcs/events/event_permissions.rs`'s `validate_event_edit_permission`,
not the occasion's own possibly-different-owner override `Post`) *and*
`occasionEditable`; the inline `occasionTimeEditFormView` once
editing.
-}
occasionTimeView : Shared.Model -> Maybe RellmAccount -> Maybe OccasionTimeEdit -> Post -> Occasion -> Html Msg
occasionTimeView shared maybeAccount maybeEdit eventPost occasion =
    case maybeEdit of
        Just edit ->
            div [ class "event-occasion-when" ] [ text "📅 ", occasionTimeEditFormView shared.time.browserTimeZone.zone edit occasion ]

        Nothing ->
            div [ class "event-occasion-when" ]
                [ text "📅 "
                , text (Events.occasionWhenText shared.time occasion)
                , if occasionEditable occasion then
                    editButtonView "Edit Time" (OccasionTimeEditClicked occasion) maybeAccount eventPost

                  else
                    text ""
                ]


{-| The actual start/end `<input type="datetime-local">` pair, a timezone
`<select>` (`CreateNewPanel.allTimezoneNames`, same dataset/convention as
`Shared.CreateNewPanel.timezoneField`), + Save/Cancel controls -- mirrors
`Shared.CreateNewPanel.dateField`'s own `formatDateTimeLocalInput`/`onInput`
round-trip (see `Msg.OccasionStartsAtChanged`/`OccasionEndsAtChanged` for the
parse-back half), reusing `postFieldEditActionsView`'s
`.post-visibility-save`/`.post-visibility-cancel`/`.post-visibility-error`
classes for the controls, same convention that function's own doc explains.
-}
occasionTimeEditFormView : Time.Zone -> OccasionTimeEdit -> Occasion -> Html Msg
occasionTimeEditFormView zone edit occasion =
    span [ class "event-occasion-time-edit" ]
        [ Html.input
            [ type_ "datetime-local"
            , class "event-occasion-time-edit-input"
            , value (edit.pendingStartsAt |> Maybe.map (SharedTime.formatDateTimeLocalInput zone) |> Maybe.withDefault "")
            , onInput OccasionStartsAtChanged
            ]
            []
        , text " to "
        , Html.input
            [ type_ "datetime-local"
            , class "event-occasion-time-edit-input"
            , value (edit.pendingEndsAt |> Maybe.map (SharedTime.formatDateTimeLocalInput zone) |> Maybe.withDefault "")
            , onInput OccasionEndsAtChanged
            ]
            []
        , select [ class "event-occasion-time-edit-timezone-select", onInput OccasionTimezoneChanged ]
            (List.map
                (\name ->
                    option [ value name, selected (name == edit.pendingTimezone) ] [ text name ]
                )
                CreateNewPanel.allTimezoneNames
            )
        , span [ class "event-occasion-edit-actions" ]
            [ button
                [ classes [ "post-visibility-save", "background-color-primary" ]
                , onClick (OccasionTimeSaveClicked occasion)
                , disabled (edit.status == Submitting)
                ]
                [ text
                    (if edit.status == Submitting then
                        "Saving…"

                     else
                        "Save"
                    )
                ]
            , button
                [ class "post-visibility-cancel"
                , onClick OccasionTimeCancelClicked
                , disabled (edit.status == Submitting)
                ]
                [ text "Cancel" ]
            ]
        , case edit.status of
            SubmitFailed err ->
                span [ class "post-visibility-error" ] [ text err ]

            _ ->
                text ""
        ]


{-| The currently-viewed `Occasion`'s own location row -- mirrors
`occasionTimeView` exactly, just for `Location` instead of start/end time
(including the same `occasionEditable` gate), plus one
difference: with no location set yet, the display half reads "+ Add
Location" (no separate location line to show) rather than a plain
"Edit Location" next to existing text -- and, unlike the time row (which
always has *something* to show), renders nothing at all when there's neither
a location to show nor (a synced occasion) a button to add one.
-}
occasionLocationView : Maybe RellmAccount -> Maybe OccasionLocationEdit -> Post -> Occasion -> Html Msg
occasionLocationView maybeAccount maybeEdit eventPost occasion =
    case maybeEdit of
        Just edit ->
            div [ class "event-occasion-where" ] [ text "📍 ", occasionLocationEditFormView edit occasion ]

        Nothing ->
            case ( occasion.location |> Maybe.andThen Events.locationText, occasionEditable occasion ) of
                ( Just locationLine, True ) ->
                    div [ class "event-occasion-where" ]
                        [ text "📍 "
                        , text locationLine
                        , editButtonView "Edit Location" (OccasionLocationEditClicked occasion) maybeAccount eventPost
                        ]

                ( Just locationLine, False ) ->
                    div [ class "event-occasion-where" ] [ text "📍 ", text locationLine ]

                ( Nothing, True ) ->
                    div [ class "event-occasion-where" ]
                        [ editButtonView "+ Add Location" (OccasionLocationEditClicked occasion) maybeAccount eventPost ]

                ( Nothing, False ) ->
                    text ""


{-| The actual address `<input>` + Save/Cancel controls for the location
editor -- mirrors `postFieldEditFormView` exactly (a single plain-text field,
same Save/Cancel/error controls), just editing `Location.uniformlyFormattedAddress`
via `UpdateOccasions` instead of a `Post` field via `UpdatePost`.
-}
occasionLocationEditFormView : OccasionLocationEdit -> Occasion -> Html Msg
occasionLocationEditFormView edit occasion =
    span [ class "event-occasion-location-edit" ]
        [ Html.input
            [ type_ "text"
            , class "event-occasion-location-edit-input"
            , placeholder "Address"
            , value edit.pending
            , onInput OccasionLocationChanged
            ]
            []
        , span [ class "event-occasion-edit-actions" ]
            [ button
                [ classes [ "post-visibility-save", "background-color-primary" ]
                , onClick (OccasionLocationSaveClicked occasion)
                , disabled (edit.status == Submitting)
                ]
                [ text
                    (if edit.status == Submitting then
                        "Saving…"

                     else
                        "Save"
                    )
                ]
            , button
                [ class "post-visibility-cancel"
                , onClick OccasionLocationCancelClicked
                , disabled (edit.status == Submitting)
                ]
                [ text "Cancel" ]
            ]
        , case edit.status of
            SubmitFailed err ->
                span [ class "post-visibility-error" ] [ text err ]

            _ ->
                text ""
        ]


{-| The "+ Add More" button + its popover (see `Model.addMoreMenu`) -- built
on `ui/popover.css`'s generic `.popover-anchor`/`.popover-toggle`/`.popover`/
`.popover-backdrop` pieces, the same way `Components.Pages.EventsPage.exportButtonView`
uses them (see that function's own doc for what each class does). Gated the
same way every other edit affordance in `occasionDetailAndStrip` is (the
Event's own `Post`'s author, or an Admin -- reuses `editButtonView`'s exact
condition rather than rendering a bare button, so "who can add more dates"
always matches "who can edit this date"'s own time/location buttons right
above it) *and* `occasionEditable` (see its own doc for why "Add More" is
gated the same way Edit Time/Edit Location are).
-}
addMoreView : Maybe RellmAccount -> Model -> Post -> Occasion -> Html Msg
addMoreView maybeAccount model eventPost occasion =
    case maybeAccount of
        Nothing ->
            text ""

        Just account ->
            if not ((Posts.isAuthor account eventPost || List.member ADMIN account.permissions) && occasionEditable occasion) then
                text ""

            else
                let
                    isOpen : Bool
                    isOpen =
                        model.addMoreMenu /= Nothing
                in
                div [ classes [ "event-occasion-add-more", "popover-anchor" ] ]
                    [ button
                        [ classes [ "event-occasion-add-more-toggle", "popover-toggle", "background-color-nav", openClosedClass isOpen ]
                        , onClick
                            (if isOpen then
                                AddMoreClosed

                             else
                                AddMoreClicked
                            )
                        , type_ "button"
                        ]
                        [ text "+ Add More" ]
                    , div [ classes [ "popover-backdrop", openClosedClass isOpen ], onClick AddMoreClosed ] []
                    , div [ classes [ "event-occasion-add-more-popover", "popover", openClosedClass isOpen ] ]
                        (model.addMoreMenu
                            |> Maybe.map addMoreMenuContentView
                            |> Maybe.withDefault []
                        )
                    ]


{-| The popover's actual content, per `AddMoreMenu.step` -- `ChoosingCount`
lists every "N more" option `1..52` (per this feature's own request), each
opening `ChoosingFrequency`'s "Daily"/"Weekly"/(`Monthly` under 12) buttons
(`availableFrequencies`/`frequencyLabel`), which is what actually submits
(`AddMoreFrequencyClicked`, via `Components.Events.createNewOccasions`).
`AddMoreFrequencyClicked` doesn't carry the `Event`/`Occasion` it needs
either -- `update` re-reads both from `model.eventStatus` at submit time,
same as every other save handler in this module -- so this needs nothing
beyond `menu` itself.
-}
addMoreMenuContentView : AddMoreMenu -> List (Html Msg)
addMoreMenuContentView menu =
    case menu.step of
        ChoosingCount ->
            [ h3 [ class "event-occasion-add-more-heading" ] [ text "Add more dates" ]
            , div [ class "event-occasion-add-more-counts" ]
                (List.range 1 52
                    |> List.map
                        (\count ->
                            button
                                [ class "event-occasion-add-more-count"
                                , onClick (AddMoreCountClicked count)
                                , type_ "button"
                                ]
                                [ text (String.fromInt count ++ " more") ]
                        )
                )
            ]

        ChoosingFrequency count ->
            [ h3 [ class "event-occasion-add-more-heading" ] [ text (String.fromInt count ++ " more…") ]
            , div [ class "event-occasion-add-more-frequencies" ]
                (availableFrequencies count
                    |> List.map
                        (\unit ->
                            button
                                [ classes [ "event-occasion-add-more-frequency", "background-color-primary" ]
                                , onClick (AddMoreFrequencyClicked count unit)
                                , disabled (menu.status == Submitting)
                                , type_ "button"
                                ]
                                [ text (frequencyLabel count unit) ]
                        )
                )
            , button
                [ class "event-occasion-add-more-back"
                , onClick AddMoreBackClicked
                , disabled (menu.status == Submitting)
                , type_ "button"
                ]
                [ text "← Back" ]
            , case menu.status of
                SubmitFailed err ->
                    span [ class "event-occasion-add-more-error" ] [ text err ]

                Submitting ->
                    span [ class "event-occasion-add-more-status" ] [ text "Creating…" ]

                Idle ->
                    text ""
            ]


{-| The star button + comment count for `occasion`'s own `Post` -- bottom
right of the detail view, mirroring `eventCard`'s own bottom-right meta (see
`Components.Events.eventCard`'s doc) rather than `event.post`'s: each
`Occasion` of a recurring `Event` gets its own independent star/comment
count, the same way it gets its own `Post` row. Renders nothing if
`occasion.post` is unset (shouldn't happen in practice, but the field is
optional on the wire).
-}
occasionMetaView : Shared.Model -> Model -> Occasion -> Html Msg
occasionMetaView shared model occasion =
    case occasion.post of
        Just occasionPost ->
            let
                displayPost : Post
                displayPost =
                    StarredPanel.freshestPost model.targetHost occasionPost shared.panels.starredPanel

                starred : Bool
                starred =
                    StarredPanel.isStarred model.targetHost displayPost shared.panels.starredPanel

                onStarClicked : Maybe Msg
                onStarClicked =
                    StarredPanel.toggleStarMsg shared.accounts model.targetHost displayPost
                        |> Maybe.map (Shared.StarredPanelMsg >> SharedMsg)
            in
            div [ class "event-detail-meta" ]
                [ span [ class "post-meta-right" ]
                    [ Posts.starButton model.targetHost starred onStarClicked displayPost
                    , text (Posts.commentCountText displayPost)
                    ]
                ]

        Nothing ->
            text ""


{-| The date-picker strip: all 3 "switch scope" buttons (see `historyButtons`)
plus, once there's more than 3 chips to justify it, a scroll/grid layout
toggle (see `occasionLayoutButtonView`), above either a
horizontally-scrolling row or a wrapping grid (`model.occasionLayout`) of
every `Occasion` currently selected by `model.occasionHistoryDisplay`,
each linking to that occasion's own page. Renders nothing at all for an
`Event` with only one occasion -- there's no other date to pick.
-}
occasionHistoryView : Shared.Model -> Model -> Event -> Occasion -> Html Msg
occasionHistoryView shared model event occasion =
    if List.length event.occasions <= 1 then
        text ""

    else
        let
            minimumRank : Int
            minimumRank =
                historyDisplayRank (minimumHistoryDisplayFor shared.time.now occasion)

            showLayoutToggle : Bool
            showLayoutToggle =
                List.length event.occasions > 3
        in
        div [ class "event-occasion-history" ]
            [ div [ class "event-occasion-history-buttons" ]
                (List.map (historyButtonView model minimumRank) (historyButtons shared.time.now event)
                    ++ (if showLayoutToggle then
                            [ occasionLayoutButtonView model.occasionLayout ]

                        else
                            []
                       )
                )
            , div
                (id occasionStripDomId :: occasionContainerAttributes model.occasionLayout)
                (event.occasions
                    |> List.filterMap
                        (\otherOccasion ->
                            otherOccasion.post
                                |> Maybe.andThen (\post -> Dict.get post.id model.occasionAnimations)
                        )
                    |> List.map (occasionChipView shared model occasion)
                )
            ]


{-| The strip container's own layout classes -- `StripLayout` is a plain
`UI.Flip.Horizontal` row (`flip-animated-row`/`.event-occasion-strip`,
scrolling), `GridLayout` wraps instead (`flip-animated-grid`/
`.event-occasion-grid`, no scrollbar, grows vertically) -- see `flip.css` for
how each of those first classes drives a chip's own collapse/grow direction
via `UI.Flip.itemAttributes`' `.horizontal` (used for both layouts here; see
`occasionChipView`).
-}
occasionContainerAttributes : OccasionLayout -> List (Html.Attribute Msg)
occasionContainerAttributes layout =
    case layout of
        StripLayout ->
            [ classes [ "event-occasion-strip", "flip-animated-row" ] ]

        GridLayout ->
            [ classes [ "event-occasion-grid", "flip-animated-grid" ] ]


{-| Icon-only toggle between the strip's two layouts (see `OccasionLayout`) --
always the same glyph (☰), rotated 90° via `.event-occasion-layout-icon-rotated`
(a CSS `transition`, see `events.css`) while `GridLayout` is active, rather
than swapping to a second glyph -- labeled (via `aria-label`/`title`, for
accessibility and a hover tooltip since the glyph itself doesn't change) for
whichever layout it would switch _to_, not the current one. Always
right-aligned (`.event-occasion-layout-button`, see `events.css`) in the
buttons row, regardless of how many "switch scope" buttons
(`historyButtonView`) precede it.
-}
occasionLayoutButtonView : OccasionLayout -> Html Msg
occasionLayoutButtonView layout =
    let
        ( targetLayout, targetLabel ) =
            case layout of
                StripLayout ->
                    ( GridLayout, "Grid view" )

                GridLayout ->
                    ( StripLayout, "List view" )
    in
    button
        [ classes [ "event-occasion-history-button", "event-occasion-layout-button" ]
        , onClick (OccasionLayoutChanged targetLayout)
        , attribute "aria-label" targetLabel
        , title targetLabel
        ]
        [ span
            [ classes
                ("event-occasion-layout-icon"
                    :: (if layout == GridLayout then
                            [ "event-occasion-layout-icon-rotated" ]

                        else
                            []
                       )
                )
            ]
            [ text "☰" ]
        ]


{-| One of the 3 "switch scope" buttons -- highlighted (`background-color-primary`)
if `mode` is `model.occasionHistoryDisplay` itself, disabled if `mode` is more
restrictive than `minimumRank` (see `historyButtons`' own doc) since
switching to it would hide `occasion`, the very one this page is showing.
-}
historyButtonView : Model -> Int -> ( OccasionHistoryDisplay, Int ) -> Html Msg
historyButtonView model minimumRank ( mode, count ) =
    let
        isCurrent : Bool
        isCurrent =
            mode == model.occasionHistoryDisplay
    in
    button
        [ classes
            ("event-occasion-history-button"
                :: (if isCurrent then
                        [ "background-color-primary" ]

                    else
                        []
                   )
            )
        , onClick (HistoryDisplayChanged mode)
        , disabled (historyDisplayRank mode < minimumRank)
        ]
        [ text (historyButtonLabel mode count) ]


historyButtonLabel : OccasionHistoryDisplay -> Int -> String
historyButtonLabel mode count =
    let
        dateWord : String
        dateWord =
            if count == 1 then
                "date"

            else
                "dates"
    in
    case mode of
        ShowAllOccasions ->
            String.fromInt count ++ " total " ++ dateWord

        SinceTwoWeeksAgo ->
            String.fromInt count ++ " " ++ dateWord ++ " since 2 weeks ago"

        OnlyFuture ->
            String.fromInt count ++ " upcoming " ++ dateWord


{-| The "switch scope" buttons to show above the strip (see `historyButtonView`
for how the current one is highlighted instead of omitted, and how one more
restrictive than `minimumHistoryDisplayFor now occasion` -- which would hide
`occasion`, the very one this page is showing -- is disabled instead of
hidden). Normally all 3, but a mode is dropped entirely when its count ties a
strictly more restrictive mode's count -- since `OnlyFuture` ⊆
`SinceTwoWeeksAgo` ⊆ `ShowAllOccasions` (see `historyDisplayRank`), a tie
means the wider mode wouldn't reveal anything beyond what the narrower one
already shows, so offering it would just be a second button for the same set
of occasions (e.g. "1 date since 2 weeks ago" alongside "1 upcoming date"
when that's the same single occasion). `OnlyFuture` itself is never dropped
this way, since nothing is more restrictive than it. `now` is
`Shared.Model.time.now` -- see its own doc.
-}
historyButtons : Time.Posix -> Event -> List ( OccasionHistoryDisplay, Int )
historyButtons now event =
    let
        countFor : OccasionHistoryDisplay -> Int
        countFor mode =
            event.occasions |> List.filter (occasionMatchesHistoryDisplay now mode) |> List.length

        allButtons : List ( OccasionHistoryDisplay, Int )
        allButtons =
            [ ShowAllOccasions, SinceTwoWeeksAgo, OnlyFuture ]
                |> List.map (\mode -> ( mode, countFor mode ))

        isRedundant : ( OccasionHistoryDisplay, Int ) -> Bool
        isRedundant ( mode, count ) =
            allButtons
                |> List.any (\( otherMode, otherCount ) -> historyDisplayRank otherMode < historyDisplayRank mode && otherCount == count)
    in
    allButtons
        |> List.filter (\button -> not (isRedundant button))


{-| One date chip -- links to `anim.occasion`'s own page (see
`Components.Events.occasionHref`), highlighted if it's the occasion
currently being viewed (`model.occasionId`). `currentOccasion` is that
currently-viewed occasion (see `occasionHistoryView`'s own `occasion`
parameter) -- passed through to `Components.Events.siblingOccasionWhenText`
so a sibling chip that shares `currentOccasion`'s own time-of-day can drop
its redundant time and show just the date(s). Wrapped in
`UI.Flip.itemAttributes` so it fades/collapses in and out as
`model.occasionHistoryDisplay` changes which occasions `occasionHistoryView`
selects (see `syncOccasionAnimations`).
-}
occasionChipView : Shared.Model -> Model -> Occasion -> OccasionAnimation -> Html Msg
occasionChipView shared model currentOccasion { occasion, flip } =
    let
        occasionPostId : String
        occasionPostId =
            occasion.post |> Maybe.map .id |> Maybe.withDefault ""

        isCurrent : Bool
        isCurrent =
            occasionPostId == model.occasionId
    in
    div (UI.Flip.itemAttributes UI.Flip.Horizontal flip False)
        [ a
            [ href (Events.occasionHref shared.basePath shared.accounts.mainFrontendHost model.targetHost occasion)
            , id (occasionChipDomId occasionPostId)
            , classes
                ([ "event-occasion-chip", hostnameToCSSClass model.targetHost ]
                    ++ (if isCurrent then
                            [ "event-occasion-chip-current", "background-color-primary" ]

                        else
                            []
                       )
                )
            ]
            [ text (Events.siblingOccasionWhenText shared.time currentOccasion occasion) ]
        ]
