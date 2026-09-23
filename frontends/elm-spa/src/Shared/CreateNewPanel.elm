module Shared.CreateNewPanel exposing (CreatedItem(..), Mode, Model, Msg(..), allTimezoneNames, hasEligibleAccount, init, isOpen, update, view)

{-| A single, app-wide "New Post"/"New Event" composer -- title (the only
field required in both modes), an optional link, optional media (picked via
`Shared.MyMediaPanel`'s `MultiSelect` mode), and optional Markdown content
(edited via `Shared.MarkdownPanel`, shown here only as a rendered preview + an
Edit button), plus -- in `EventMode` only -- a required start/end date/time
pair. Wired into `Shared.Model`/`UI.elm` the same way `Shared.MarkdownPanel`/
`Shared.MyMediaPanel` are, but toggled open/closed like the Accounts/Starred
Posts panels (`ToggleOpen`) rather than opened for a specific already-in-hand
entity -- there's no Post/Event yet, this panel _is_ the not-yet-created
draft.

`Model.mode` (switched via the header's "New Post"/"New Event" tabs, see
`modeTabsView`) picks which RPC `SaveClicked` actually calls
(`Rellm.createPost` vs `Rellm.createEvent`) and which permission
(`CREATEPOSTS` vs `CREATEEVENTS`) gates `postingAsSelector`/`resolve` --
title/link/media/content are shared by both modes, submitted as-is either as
the Post itself (`PostMode`) or as the `Event`'s own underlying Post
(`EventMode`). An `EventMode` save always creates exactly one `Occasion`
(`startsAt`/`endsAt`, the two extra fields), with no `Post` of its own --
its `visibility` is inherited from the `Event`'s own Post by the backend
(`create_event.rs`) leaving `Occasion.post` unset, so there's nothing
else for this panel to set on it.

Cancel/the shared backdrop/`CloseAllPanels` all just close this panel
(`CloseClicked`) without touching any of the draft fields -- the draft is
retained across opens until an actual `SaveClicked` succeeds, so accidentally
tapping outside or hitting Cancel can't lose it.

Since editing the Markdown content or picking media both hand off to another
app-wide panel (`Shared.MarkdownPanel`/`Shared.MyMediaPanel`) rather than
embedding their own editor/picker here, `update` returns not just a possible
`AccountsPanel.Msg` to forward (same convention as every other panel here,
for a token refresh mid-save) but also a possible `MarkdownPanel.Msg`/
`MyMediaPanel.Msg` -- `EditContentClicked`/`EditMediaClicked`'s own request to
actually open one of those, for `Shared.update` to dispatch on this panel's
behalf (it can't do so directly without importing `Shared`, which would
cycle). Their own results flow back the same way every other cross-panel
result does here: `Shared.update`'s own `MarkdownPanelMsg`/`MyMediaPanelMsg`
branches recognize a save meant for this panel and feed it back in via
`ContentSaved`/`MediaSaved`, rather than this module reaching into either
panel's state directly.

-}

import Components.Markdown as Markdown
import Components.MediaRenderer as MediaRenderer
import Components.MultiMediaRenderer as MultiMediaRenderer
import Components.Posts as Posts
import Dict
import Grpc
import Html exposing (Html, button, div, img, input, label, option, select, span, text)
import Html.Attributes exposing (alt, attribute, class, disabled, placeholder, selected, src, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (MediaReference, defaultEvent, defaultEventInfo, defaultOccasion, defaultPost)
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.Conversions exposing (posixToTimestamp)
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MyMediaPanel as MyMediaPanel
import Shared.Time as SharedTime
import Task exposing (Task)
import Time
import TimeZone
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)


type alias Model =
    { open : Bool
    , mode : Mode

    -- `Just (RellmAccounts.rellmAccountId account)` once the user's explicitly
    -- switched who they're posting as (see `postingAsSelector`) -- `Nothing`
    -- means "whichever eligible account `resolvedAccount` picks by default",
    -- so a lone eligible account never needs an explicit selection at all.
    , postingAs : Maybe String

    -- `Just visibility` once the user's explicitly picked one (see
    -- `visibilityField`) -- `Nothing` means "whichever `defaultVisibilityFor`
    -- picks for the resolved account/mode", mirroring `postingAs`.
    , visibility : Maybe Visibility
    , title : String
    , link : String
    , media : List MediaReference
    , content : String

    -- `EventMode`-only, both required -- see module doc.
    , startsAt : Maybe Time.Posix
    , endsAt : Maybe Time.Posix

    -- `EventMode`-only -- `Nothing` means "the browser's own timezone" (see `resolvedTimezone`),
    -- mirroring `visibility`/`postingAs`'s own "unset means default" convention.
    , timezone : Maybe String
    , status : SubmitStatus

    -- Every Post/Event this panel has successfully created this session
    -- (newest first), tagged with the `frontendHost` it was created on --
    -- `GotSaveResult`'s own successful `Ok` appends to this rather than
    -- `saveTask`/`GotSaveResult` just discarding the RPC's response the way
    -- they used to. Lets `PostsPage`/`EventsPage` (reading this via
    -- `shared.panels.createNewPanel.createdItems`, or more precisely
    -- reacting to the very `GotSaveResult` that appended to it as it passes
    -- through their own `SharedMsg`) splice a just-created Post/Event
    -- straight into an already-fetched feed instead of needing a full
    -- refetch to see your own new post/event appear.
    , createdItems : List CreatedItem
    }


type Msg
    = ToggleOpen
    | CloseClicked
    | CancelClicked
    | ModeChanged Mode
    | TitleChanged String
    | LinkChanged String
    | StartsAtChanged String
    | EndsAtChanged String
    | TimezoneChanged String
    | PostingAsSelected String
    | VisibilityChanged String
    | EditContentClicked
    | EditMediaClicked
      -- Fed back in by `Shared.update` once `Shared.MarkdownPanel`/
      -- `Shared.MyMediaPanel` (opened by the two messages above) report a
      -- save meant for this panel -- see module doc.
    | ContentSaved String
    | MediaSaved (List MediaReference)
    | SaveClicked
    | GotSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, CreatedItem ))


type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Which kind of thing this panel's draft is right now -- switched via the
header's tabs (`modeTabsView`). See module doc.
-}
type Mode
    = PostMode
    | EventMode


{-| One entry of `Model.createdItems` -- `String` is the `frontendHost` of
the server the Post/Event was created on (`Resolved.server.frontendHost`,
same as everywhere else in this module), needed alongside the Post/Event
itself since neither carries its own server host.
-}
type CreatedItem
    = CreatedPost String Proto.Rellm.Post
    | CreatedEvent String Proto.Rellm.Event


type alias Resolved =
    { server : RellmServer
    , account : RellmAccount
    }


init : Model
init =
    { open = False
    , mode = PostMode
    , postingAs = Nothing
    , visibility = Nothing
    , title = ""
    , link = ""
    , media = []
    , content = ""
    , startsAt = Nothing
    , endsAt = Nothing
    , timezone = Nothing
    , status = Idle
    , createdItems = []
    }


isOpen : Model -> Bool
isOpen model =
    model.open


noForward : ( Maybe AccountsPanel.Msg, Maybe MarkdownPanel.Msg, Maybe MyMediaPanel.Msg )
noForward =
    ( Nothing, Nothing, Nothing )


{-| See module doc for why this needs to return not just a possible
`AccountsPanel.Msg` (a token refresh mid-`SaveClicked`, same convention as
every other panel here) but also a possible `MarkdownPanel.Msg`/
`MyMediaPanel.Msg` for `Shared.update` to dispatch on this panel's behalf.

Takes the viewer's own `Shared.Model.time.browserTimeZone` purely to parse
`StartsAtChanged`/`EndsAtChanged`'s raw `<input type="datetime-local">`
strings (always local wall-clock time, no timezone of their own) back into
absolute `Time.Posix` (via its `.zone` -- see
`Shared.Time.posixFromDateTimeLocalInput`) and to default `timezone`'s
selector to its `.name` (see `resolvedTimezone`). Also takes the viewer's
current `now` (`Shared.Model.time.now`), used only by `ToggleOpen` to default
a blank `startsAt`/`endsAt` when opening into `EventMode` -- see below.

-}
update : SharedTime.BrowserTimeZone -> Time.Posix -> AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Maybe MarkdownPanel.Msg, Maybe MyMediaPanel.Msg ) )
update browserTimeZone now accountsPanelModel msg model =
    let
        zone : Time.Zone
        zone =
            browserTimeZone.zone
    in
    case msg of
        ToggleOpen ->
            let
                opening : Bool
                opening =
                    not model.open

                -- Opening into `EventMode` with no `startsAt` yet (either a
                -- fresh `init` or a prior draft that never got a start time)
                -- defaults it to an hour from now, mirroring
                -- `StartsAtChanged`'s own "no prior end" default of an hour
                -- after `startsAt` for `endsAt`.
                withDefaultTimes : Model
                withDefaultTimes =
                    if opening && model.mode == EventMode && model.startsAt == Nothing then
                        let
                            defaultStartsAt : Time.Posix
                            defaultStartsAt =
                                Time.millisToPosix (Time.posixToMillis now + 3600000)
                        in
                        { model
                            | startsAt = Just defaultStartsAt
                            , endsAt = Just (Time.millisToPosix (Time.posixToMillis defaultStartsAt + 3600000))
                        }

                    else
                        model
            in
            ( { withDefaultTimes | open = opening }, Cmd.none, noForward )

        CloseClicked ->
            ( { model | open = False }, Cmd.none, noForward )

        CancelClicked ->
            ( { model | open = False }, Cmd.none, noForward )

        ModeChanged mode ->
            ( { model | mode = mode }, Cmd.none, noForward )

        TitleChanged title ->
            ( { model | title = title }, Cmd.none, noForward )

        LinkChanged link ->
            ( { model | link = link }, Cmd.none, noForward )

        StartsAtChanged raw ->
            let
                newStartsAt : Maybe Time.Posix
                newStartsAt =
                    SharedTime.posixFromDateTimeLocalInput zone raw

                -- Keeps `endsAt` sane relative to the new `startsAt`: if
                -- there was already a valid start/end pair, shift `endsAt` by
                -- the same delta so the event's duration is preserved --
                -- otherwise (the first time a start is picked, or no end was
                -- set yet) default `endsAt` to an hour after the new start,
                -- so a not-yet-touched end never reads as blank/before the
                -- start once a start exists.
                newEndsAt : Maybe Time.Posix
                newEndsAt =
                    case ( newStartsAt, model.startsAt, model.endsAt ) of
                        ( Just newStart, Just oldStart, Just oldEnd ) ->
                            Just (Time.millisToPosix (Time.posixToMillis oldEnd + (Time.posixToMillis newStart - Time.posixToMillis oldStart)))

                        ( Just newStart, _, _ ) ->
                            Just (Time.millisToPosix (Time.posixToMillis newStart + 3600000))

                        ( Nothing, _, _ ) ->
                            model.endsAt
            in
            ( { model | startsAt = newStartsAt, endsAt = newEndsAt }, Cmd.none, noForward )

        EndsAtChanged raw ->
            let
                newEndsAt : Maybe Time.Posix
                newEndsAt =
                    SharedTime.posixFromDateTimeLocalInput zone raw

                -- Enforces `endsAt` is always at least a minute after
                -- `startsAt` (when one's set) -- clamps rather than rejecting
                -- outright, so picking an end too close to (or before) the
                -- start still lands on the nearest valid value instead of
                -- silently not applying the change.
                clampedEndsAt : Maybe Time.Posix
                clampedEndsAt =
                    case ( newEndsAt, model.startsAt ) of
                        ( Just newEnd, Just startsAt ) ->
                            Just (Time.millisToPosix (max (Time.posixToMillis newEnd) (Time.posixToMillis startsAt + 60000)))

                        _ ->
                            newEndsAt
            in
            ( { model | endsAt = clampedEndsAt }, Cmd.none, noForward )

        TimezoneChanged tz ->
            ( { model | timezone = Just tz }, Cmd.none, noForward )

        PostingAsSelected accountId ->
            ( { model | postingAs = Just accountId }, Cmd.none, noForward )

        VisibilityChanged text ->
            ( { model | visibility = Posts.visibilityFromText text }, Cmd.none, noForward )

        EditContentClicked ->
            ( model
            , Cmd.none
            , ( Nothing, Just (MarkdownPanel.Open (MarkdownPanel.NewPostContent model.content) (postingAsHost accountsPanelModel model)), Nothing )
            )

        EditMediaClicked ->
            ( model
            , Cmd.none
            , ( Nothing
              , Nothing
              , Just (MyMediaPanel.Open (Just (MyMediaPanel.MultiSelect { initialSelection = model.media })) (postingAsHost accountsPanelModel model))
              )
            )

        ContentSaved content ->
            ( { model | content = content }, Cmd.none, noForward )

        MediaSaved media ->
            ( { model | media = media }, Cmd.none, noForward )

        SaveClicked ->
            case resolve accountsPanelModel model of
                Ok resolved ->
                    ( { model | status = Submitting }
                    , saveTask browserTimeZone accountsPanelModel resolved model |> Task.attempt GotSaveResult
                    , noForward
                    )

                Err err ->
                    ( { model | status = SubmitFailed err }, Cmd.none, noForward )

        GotSaveResult (Ok ( maybeAccountsPanelMsg, createdItem )) ->
            ( { init | createdItems = createdItem :: model.createdItems }, Cmd.none, ( maybeAccountsPanelMsg, Nothing, Nothing ) )

        GotSaveResult (Err err) ->
            ( { model | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Cmd.none, noForward )


{-| The permission (`CREATEPOSTS`/`CREATEEVENTS`) `eligibleAccounts` requires
for `mode`, mirroring `backend/src/rpcs/posts/create_post.rs`'s/
`backend/src/rpcs/events/create_event.rs`'s own `validate_permission` calls.
-}
requiredPermission : Mode -> Permission
requiredPermission mode =
    case mode of
        PostMode ->
            CREATEPOSTS

        EventMode ->
            CREATEEVENTS


{-| Signed-in accounts that could actually create a Post/Event (per `mode`)
somewhere -- `ADMIN` or `requiredPermission mode`, which -- like every
permission check on the backend -- also accepts `ADMIN` as a blanket bypass.
What `postingAsSelector` lists, and what `resolvedAccount` picks a default
from.
-}
eligibleAccounts : Mode -> AccountsPanel.Model -> List RellmAccount
eligibleAccounts mode accountsPanelModel =
    AccountsPanel.enabledAccounts accountsPanelModel
        |> List.filter (\account -> RellmAccounts.isAdmin account || List.member (requiredPermission mode) account.permissions)


{-| Whether the New Post/Event nav toggle should even show -- no point
offering a composer nobody signed in could actually submit, in either mode.
-}
hasEligibleAccount : AccountsPanel.Model -> Bool
hasEligibleAccount accountsPanelModel =
    not (List.isEmpty (eligibleAccounts PostMode accountsPanelModel))
        || not (List.isEmpty (eligibleAccounts EventMode accountsPanelModel))


{-| `model.postingAs`, resolved against `model.mode`'s current
`eligibleAccounts` -- falls back to the first eligible account whenever
`postingAs` is unset, or no longer resolves to one (e.g. that account was
signed out since it was picked, or the user just switched `mode` to one that
account isn't eligible for), so this panel always has _some_ sensible account
to show/post as whenever at least one exists for the current mode, without
`update` needing to eagerly keep `postingAs` in sync with every account list
(or `mode`) change itself -- this is the only coordination `ModeChanged`
needs with the account selector.
-}
resolvedAccount : AccountsPanel.Model -> Model -> Maybe RellmAccount
resolvedAccount accountsPanelModel model =
    let
        eligible : List RellmAccount
        eligible =
            eligibleAccounts model.mode accountsPanelModel
    in
    case model.postingAs |> Maybe.andThen (\id -> List.filter (\account -> RellmAccounts.rellmAccountId account == id) eligible |> List.head) of
        Just account ->
            Just account

        Nothing ->
            List.head eligible


{-| The `frontendHost` of `resolvedAccount`'s server -- what tints this panel
(`hostnameToCSSClass`, see `view`) and what `EditContentClicked`/
`EditMediaClicked` open `MarkdownPanel`/`MyMediaPanel` against, same
`targetHost` convention those panels use for themselves. `""` (no known
server, matching e.g. `MyMediaPanel.Model.targetHost`'s own "not open"
convention) if there's no eligible account at all.
-}
postingAsHost : AccountsPanel.Model -> Model -> String
postingAsHost accountsPanelModel model =
    resolvedAccount accountsPanelModel model |> Maybe.map .server |> Maybe.withDefault ""


{-| Verifies a `SaveClicked` is actually submittable right now: `title` isn't
blank (the one field required in both modes), `EventMode` also has both
`startsAt`/`endsAt` set with `endsAt` after `startsAt`, there's an eligible
account (for `model.mode`) to post as, and its server is still connected/
enabled. Used both by `SaveClicked` (to gate the RPC) and by `view` (to show
the same problem inline, and disable Save, before the user even tries) --
mirrors `MarkdownPanel.resolve`/`MyMediaPanel.resolve`'s own dual use.
-}
resolve : AccountsPanel.Model -> Model -> Result String Resolved
resolve accountsPanelModel model =
    if String.isEmpty (String.trim model.title) then
        Err "A title is required."

    else
        case model.mode of
            PostMode ->
                resolveAccount accountsPanelModel model

            EventMode ->
                case ( model.startsAt, model.endsAt ) of
                    ( Nothing, _ ) ->
                        Err "A start date/time is required."

                    ( _, Nothing ) ->
                        Err "An end date/time is required."

                    ( Just startsAt, Just endsAt ) ->
                        if Time.posixToMillis endsAt < Time.posixToMillis startsAt + 60000 then
                            Err "The end date/time must be at least a minute after the start date/time."

                        else
                            resolveAccount accountsPanelModel model


resolveAccount : AccountsPanel.Model -> Model -> Result String Resolved
resolveAccount accountsPanelModel model =
    case resolvedAccount accountsPanelModel model of
        Nothing ->
            case model.mode of
                PostMode ->
                    Err "You're not signed in anywhere with permission to create posts."

                EventMode ->
                    Err "You're not signed in anywhere with permission to create events."

        Just account ->
            case RellmServers.rellmServerForHost accountsPanelModel.servers account.server of
                Nothing ->
                    Err "That server isn't connected."

                Just server ->
                    if not server.enabled then
                        Err (server.frontendHost ++ " is disabled.")

                    else
                        Ok { server = server, account = account }


{-| `SERVERPUBLIC`/`GLOBALPUBLIC` each need their own extra publish
permission, `PUBLISHPOSTSGLOBALLY`/`PUBLISHPOSTSLOCALLY` in `PostMode` or
`PUBLISHEVENTSGLOBALLY`/`PUBLISHEVENTSLOCALLY` in `EventMode`
(`backend/src/rpcs/posts/create_post.rs`/`backend/src/rpcs/events/create_event.rs`),
same `ADMIN`-bypasses-everything reasoning as `eligibleAccounts` -- mirrors
`frontends/tamagui`'s `base_create_post_sheet.tsx` picking the most-public
default visibility `account` can actually publish at. What `visibilityField`
seeds its `<select>` with before the user's made an explicit choice of their
own (`model.visibility == Nothing`), and what `resolvedVisibility` falls back
to.
-}
defaultVisibilityFor : Mode -> RellmAccount -> Visibility
defaultVisibilityFor mode account =
    let
        ( globalPermission, localPermission ) =
            case mode of
                PostMode ->
                    ( PUBLISHPOSTSGLOBALLY, PUBLISHPOSTSLOCALLY )

                EventMode ->
                    ( PUBLISHEVENTSGLOBALLY, PUBLISHEVENTSLOCALLY )
    in
    if RellmAccounts.isAdmin account || List.member globalPermission account.permissions then
        GLOBALPUBLIC

    else if List.member localPermission account.permissions then
        SERVERPUBLIC

    else
        LIMITED


{-| `mode`'s `PostContext`, for `Posts.allowedVisibilities` -- an `EventMode`
draft submits its Post as the `Event`'s own underlying Post (see module doc),
so its context is `EVENT` rather than `POST`, same as `saveTask`'s own
`{ post | context = EVENT }`.
-}
visibilityContext : Mode -> PostContext
visibilityContext mode =
    case mode of
        PostMode ->
            POST

        EventMode ->
            EVENT


{-| Which `Visibility` values `visibilityField` offers `account` for `mode` --
`Posts.allowedVisibilities` gated on `account`'s publish permissions, always
including `defaultVisibilityFor` itself so there's at least one option even
for an account with neither publish permission.
-}
allowedVisibilitiesFor : Mode -> RellmAccount -> List Visibility
allowedVisibilitiesFor mode account =
    Posts.allowedVisibilities account.permissions (visibilityContext mode) (defaultVisibilityFor mode account)


{-| `model.visibility`, resolved against `account`/`mode`'s current
`allowedVisibilitiesFor` -- falls back to `defaultVisibilityFor` whenever
`visibility` is unset, or no longer allowed (e.g. `mode` was switched to one
`account` can't publish as widely for), mirroring `resolvedAccount`'s own
fallback. What `visibilityField` shows as selected and what `saveTask` submits.
-}
resolvedVisibility : Mode -> RellmAccount -> Model -> Visibility
resolvedVisibility mode account model =
    case model.visibility of
        Just visibility ->
            if List.member visibility (allowedVisibilitiesFor mode account) then
                visibility

            else
                defaultVisibilityFor mode account

        Nothing ->
            defaultVisibilityFor mode account


{-| `model.timezone`, resolved against `browserTimeZone`'s own IANA `.name` --
falls back to the browser's own timezone whenever `timezone` is unset,
mirroring `resolvedAccount`/`resolvedVisibility`'s own "unset means default"
fallback. What `timezoneField` shows as selected and what `saveTask` submits
as `Occasion.timezone`.
-}
resolvedTimezone : SharedTime.BrowserTimeZone -> Model -> String
resolvedTimezone browserTimeZone model =
    model.timezone |> Maybe.withDefault browserTimeZone.name


nonEmptyTrimmed : String -> Maybe String
nonEmptyTrimmed value =
    let
        trimmed : String
        trimmed =
            String.trim value
    in
    if String.isEmpty trimmed then
        Nothing

    else
        Just trimmed


{-| `PostMode` calls `Rellm.createPost` exactly as before; `EventMode`
calls `Rellm.createEvent` with a single `Occasion` (`startsAt`/
`endsAt`, this panel's own two date fields) and no `Post` of its own -- see
module doc for why that occasion needs no visibility of its own. Both
branches tag their own RPC's response (the server-populated Post/Event
itself, `id`/`createdAt`/etc. included) as a `CreatedItem` with
`resolved.server.frontendHost` -- what `GotSaveResult` appends to
`Model.createdItems` -- needed so both branches of this `case` agree on a
single result type for `performWithAccountServer`'s own callback.
-}
saveTask : SharedTime.BrowserTimeZone -> AccountsPanel.Model -> Resolved -> Model -> Task Grpc.Error ( Maybe AccountsPanel.Msg, CreatedItem )
saveTask browserTimeZone accountsPanelModel resolved model =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        ( Just resolved.account.userId, resolved.server.frontendHost )
        (\server token ->
            let
                post : Proto.Rellm.Post
                post =
                    { defaultPost
                        | title = Just (String.trim model.title)
                        , link = nonEmptyTrimmed model.link
                        , content = nonEmptyTrimmed model.content
                        , media = model.media
                        , visibility = resolvedVisibility model.mode resolved.account model
                    }
            in
            case model.mode of
                PostMode ->
                    Grpc.new Rellm.createPost { post | context = POST }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                        |> Task.map (CreatedPost resolved.server.frontendHost)

                EventMode ->
                    Grpc.new Rellm.createEvent
                        { defaultEvent
                            | post = Just { post | context = EVENT }
                            , info = Just defaultEventInfo
                            , occasions =
                                [ { defaultOccasion
                                    | startsAt = Maybe.map posixToTimestamp model.startsAt
                                    , endsAt = Maybe.map posixToTimestamp model.endsAt
                                    , timezone = Just (resolvedTimezone browserTimeZone model)
                                  }
                                ]
                        }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                        |> Task.map (CreatedEvent resolved.server.frontendHost)
        )



-- VIEW


{-| Always rendered (even "closed"), same as every other panel here -- see
`UI.Classes.openClosedClass`. Tinted with `postingAsHost`'s own
`hostnameToCSSClass` (see module doc) so its Save button/mode chrome matches
the server the draft will actually be posted to.
-}
view : SharedTime.BrowserTimeZone -> AccountsPanel.Model -> Model -> Html Msg
view browserTimeZone accountsPanelModel model =
    let
        host : String
        host =
            postingAsHost accountsPanelModel model

        resolution : Result String Resolved
        resolution =
            resolve accountsPanelModel model

        canSave : Bool
        canSave =
            case resolution of
                Ok _ ->
                    True

                Err _ ->
                    False

        errorMessage : Maybe String
        errorMessage =
            case model.status of
                SubmitFailed err ->
                    Just err

                _ ->
                    case resolution of
                        Err err ->
                            Just err

                        Ok _ ->
                            Nothing
    in
    div [ classes [ "create-new-panel", "nav-panel", openClosedClass model.open, hostnameToCSSClass host ] ]
        [ div [ class "create-new-panel-header" ]
            [ modeTabsView model
            , div [ class "create-new-panel-header-meta" ]
                [ postingAsSelector accountsPanelModel model
                , visibilityField accountsPanelModel model
                ]
            ]
        , div [ class "create-new-panel-body" ]
            (List.concat
                [ [ titleField model ]
                , case model.mode of
                    PostMode ->
                        []

                    EventMode ->
                        [ startsAtField browserTimeZone.zone model, endsAtField browserTimeZone.zone model, timezoneField browserTimeZone model ]
                , [ linkField model
                  , mediaField accountsPanelModel model host
                  , contentField model
                  ]
                ]
            )
        , case errorMessage of
            Just err ->
                div [ class "create-new-panel-error" ] [ text err ]

            Nothing ->
                text ""
        , div [ class "create-new-panel-actions" ]
            [ button
                [ class "create-new-panel-cancel"
                , onClick CancelClicked
                , disabled (model.status == Submitting)
                ]
                [ text "Cancel" ]
            , button
                [ classes [ "create-new-panel-save", host, "background-color-primary" ]
                , onClick SaveClicked
                , disabled (model.status == Submitting || not canSave)
                ]
                [ text
                    (case ( model.status == Submitting, model.mode ) of
                        ( True, PostMode ) ->
                            "Posting…"

                        ( True, EventMode ) ->
                            "Creating…"

                        ( False, PostMode ) ->
                            "Post"

                        ( False, EventMode ) ->
                            "Create Event"
                    )
                ]
            ]
        ]


{-| "New Post"/"New Event" -- replaces what used to be a static title, now
that this panel has two modes (see module doc). Both tabs always show
regardless of which the signed-in accounts here are actually eligible for --
picking an ineligible one just surfaces `resolve`'s own inline error (e.g.
"You're not signed in anywhere with permission to create events."), same as
picking one with no eligible account at all already did before `EventMode`
existed.
-}
modeTabsView : Model -> Html Msg
modeTabsView model =
    div [ class "create-new-panel-tabs" ]
        [ modeTabView model PostMode "New Post"
        , modeTabView model EventMode "New Event"
        ]


modeTabView : Model -> Mode -> String -> Html Msg
modeTabView model mode label_ =
    span
        [ classes
            ("create-new-panel-tab"
                :: (if model.mode == mode then
                        [ "create-new-panel-tab-selected" ]

                    else
                        []
                   )
            )
        , onClick (ModeChanged mode)
        ]
        [ text label_ ]


titleField : Model -> Html Msg
titleField model =
    div [ class "create-new-panel-field" ]
        [ label [ class "create-new-panel-label" ] [ text "Title" ]
        , input
            [ type_ "text"
            , class "create-new-panel-title-input"
            , value model.title
            , onInput TitleChanged
            , placeholder
                (case model.mode of
                    EventMode ->
                        "What's the name of your event?"

                    _ ->
                        "What's this about?"
                )
            ]
            []
        ]


{-| `EventMode`-only, both required -- see module doc. Blank (rather than
falling back to e.g. the current time) whenever `Nothing`, so a not-yet-picked
required field actually reads as empty instead of a misleadingly already-filled-in
default the user might not notice needs changing.
-}
startsAtField : Time.Zone -> Model -> Html Msg
startsAtField zone model =
    dateField zone "Starts" model.startsAt StartsAtChanged


endsAtField : Time.Zone -> Model -> Html Msg
endsAtField zone model =
    dateField zone "Ends" model.endsAt EndsAtChanged


{-| `EventMode`-only -- a `<select>` of every IANA zone `TimeZone.zones` knows
about (the same dataset `Shared.getBrowserZone` itself is backed by), always
defaulted to the browser's own timezone (`resolvedTimezone`) until the user
picks a different one.
-}
timezoneField : SharedTime.BrowserTimeZone -> Model -> Html Msg
timezoneField browserTimeZone model =
    let
        selectedTimezone : String
        selectedTimezone =
            resolvedTimezone browserTimeZone model
    in
    div [ class "create-new-panel-field" ]
        [ label [ class "create-new-panel-label" ] [ text "Timezone" ]
        , select [ class "create-new-panel-timezone-select", onInput TimezoneChanged ]
            (List.map
                (\name ->
                    option [ value name, selected (name == selectedTimezone) ] [ text name ]
                )
                allTimezoneNames
            )
        ]


{-| Every IANA zone name `justinmimbs/timezone-data` bundles (the same
dataset `Shared.getBrowserZone` itself resolves against), sorted for a
sensible `<select>` order -- what `timezoneField` (here) and
`Components.Pages.EventPage.occasionTimezoneField` both offer.
-}
allTimezoneNames : List String
allTimezoneNames =
    TimeZone.zones |> Dict.keys |> List.sort


dateField : Time.Zone -> String -> Maybe Time.Posix -> (String -> Msg) -> Html Msg
dateField zone labelText posix toMsg =
    div [ class "create-new-panel-field" ]
        [ label [ class "create-new-panel-label" ] [ text labelText ]
        , input
            [ type_ "datetime-local"
            , class "create-new-panel-date-input"
            , value (posix |> Maybe.map (SharedTime.formatDateTimeLocalInput zone) |> Maybe.withDefault "")
            , onInput toMsg
            ]
            []
        ]


linkField : Model -> Html Msg
linkField model =
    div [ class "create-new-panel-field" ]
        [ label [ class "create-new-panel-label" ] [ text "Link (optional)" ]
        , input
            [ type_ "url"
            , class "create-new-panel-link-input"
            , value model.link
            , onInput LinkChanged
            , placeholder "https://…"
            ]
            []
        ]


{-| A small preview strip of `model.media` (if any) plus an Edit/+ Add button
that opens `Shared.MyMediaPanel` in `MultiSelect` mode -- see
`EditMediaClicked`. Needs a resolved `Server` (from `postingAsHost`) purely to
render `MultiMediaRenderer`'s preview; renders just the button, no preview
strip, until one's resolved (e.g. no eligible account yet).
-}
mediaField : AccountsPanel.Model -> Model -> String -> Html Msg
mediaField accountsPanelModel model host =
    div [ class "create-new-panel-field" ]
        [ div [ class "create-new-panel-field-header" ]
            [ label [ class "create-new-panel-label" ] [ text "Media (optional)" ]
            , button [ class "create-new-panel-edit-button", onClick EditMediaClicked ]
                [ text
                    (if List.isEmpty model.media then
                        "+ Add Media"

                     else
                        "Edit Media"
                    )
                ]
            ]
        , if List.isEmpty model.media then
            text ""

          else
            case RellmServers.rellmServerForHost accountsPanelModel.servers host of
                Just server ->
                    MultiMediaRenderer.previewExtraSmall server (RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host) MediaRenderer.init (\_ -> EditMediaClicked) (\_ -> EditMediaClicked) model.media

                Nothing ->
                    text ""
        ]


{-| A rendered-Markdown preview of `model.content` (if any) plus an Edit/+ Add
button that opens `Shared.MarkdownPanel` -- see `EditContentClicked`. No
editor of its own here at all, unlike `Shared.MarkdownPanel` itself -- see
module doc.
-}
contentField : Model -> Html Msg
contentField model =
    div [ class "create-new-panel-field" ]
        [ div [ class "create-new-panel-field-header" ]
            [ label [ class "create-new-panel-label" ] [ text "Content (optional)" ]
            , button [ class "create-new-panel-edit-button", onClick EditContentClicked ]
                [ text
                    (if String.isEmpty (String.trim model.content) then
                        "+ Add Content"

                     else
                        "Edit Content"
                    )
                ]
            ]
        , if String.isEmpty (String.trim model.content) then
            text ""

          else
            Markdown.view [ class "create-new-panel-content-preview" ] model.content
        ]


{-| "Posting as <avatar> username" when there's exactly one eligible account
(no point offering a one-item dropdown), or an avatar for the currently
`resolvedAccount` plus a `<select>` of every eligible account (see
`eligibleAccounts`) once there's more than one to switch between -- e.g. an
admin signed into several servers, or with two accounts on the same one.
Blank if there's no eligible account (for `model.mode`) at all (`resolve`'s
own "You're not signed in anywhere..." error, shown inline below, already
covers that case).
-}
postingAsSelector : AccountsPanel.Model -> Model -> Html Msg
postingAsSelector accountsPanelModel model =
    case eligibleAccounts model.mode accountsPanelModel of
        [] ->
            text ""

        [ onlyAccount ] ->
            div [ class "create-new-panel-account" ]
                [ text "Posting as "
                , accountAvatar accountsPanelModel.servers onlyAccount
                , span [ class "create-new-panel-account-name" ] [ text (RellmAccounts.rellmAccountDisplayName onlyAccount) ]
                ]

        eligible ->
            let
                selectedAccount : Maybe RellmAccount
                selectedAccount =
                    resolvedAccount accountsPanelModel model

                selectedId : String
                selectedId =
                    selectedAccount |> Maybe.map RellmAccounts.rellmAccountId |> Maybe.withDefault ""
            in
            div [ class "create-new-panel-account" ]
                [ case selectedAccount of
                    Just account ->
                        accountAvatar accountsPanelModel.servers account

                    Nothing ->
                        text ""
                , select [ class "create-new-panel-account-select", onInput PostingAsSelected ]
                    (List.map
                        (\account ->
                            option
                                [ value (RellmAccounts.rellmAccountId account)
                                , selected (RellmAccounts.rellmAccountId account == selectedId)
                                ]
                                [ text (RellmAccounts.rellmAccountDisplayName account ++ " on " ++ account.server) ]
                        )
                        eligible
                    )
                ]


{-| A `<select>` of `allowedVisibilitiesFor` (`resolvedAccount`/`model.mode`),
same `<select>`/`option`/`selected` shape and `visibilityText`/
`visibilityFromText` round-trip `Pages.Post.PostId_`'s own visibility editor
uses -- but always shown (no separate Edit/Save/Cancel step) since this
panel's Cancel/Save already govern the whole draft. Blank if there's no
resolved account yet (`resolvedAccount`'s own "no eligible account" case,
already covered elsewhere).
-}
visibilityField : AccountsPanel.Model -> Model -> Html Msg
visibilityField accountsPanelModel model =
    case resolvedAccount accountsPanelModel model of
        Nothing ->
            text ""

        Just account ->
            let
                selectedVisibility : Visibility
                selectedVisibility =
                    resolvedVisibility model.mode account model
            in
            div [ class "create-new-panel-visibility" ]
                [ text "Visible to "
                , select [ class "create-new-panel-visibility-select", onInput VisibilityChanged ]
                    (List.map
                        (\visibility ->
                            option
                                [ value (Posts.visibilityText visibility)
                                , selected (visibility == selectedVisibility)
                                ]
                                [ text (Posts.visibilityText visibility) ]
                        )
                        (allowedVisibilitiesFor model.mode account)
                    )
                ]


{-| A trimmed-down copy of `UI.imageOrInitial`/`MarkdownPanel.accountAvatar` --
`UI` itself imports this module (to embed `CreateNewPanel.view`), so importing
it back here to reuse that helper would be a circular import.
-}
accountAvatar : List RellmServer -> RellmAccount -> Html msg
accountAvatar servers account =
    case RellmAccounts.rellmAccountAvatarUrl servers account of
        Just url ->
            img [ class "create-new-panel-account-avatar", src url, alt account.username, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes [ "create-new-panel-account-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter account.username) ]
