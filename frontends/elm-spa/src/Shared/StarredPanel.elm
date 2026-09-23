module Shared.StarredPanel exposing (Model, Msg(..), freshestPost, init, isStarred, rawKey, refreshHosts, subscriptions, toggleStarMsg, update, view)

{-| Tracks which Posts the user has starred, in this browser. `StarPost`/
`UnstarPost` (see `protos/rellm.proto`) are auth-less, "friendly" counters
with no per-user state on the server at all (see `Post.unauthenticated_star_count`)
-- the _only_ record of "did I star this" is this module's `starredPostIds`,
persisted to localStorage (see `Ports.persistStarredPosts`) keyed by
`postId@frontendHost` (see `starKey`) so it survives reloads and tells posts
from different servers apart.

All `StarPost`/`UnstarPost` calls -- from `Pages.Home_`/`Pages.Post.PostId_`,
via `Shared.StarredPanelMsg` -- route through here so the persisted set
and the RPC can't drift apart. The starred count itself isn't optimistically
adjusted client-side; instead, `GotStarResult`'s `Post` (the RPC's response,
which already carries the server's fresh `unauthenticated_star_count`) is
cached here, and `freshestPost` lets `Pages.Home_`/`Pages.Post.PostId_` read
it back out for immediate feedback. They can't just pattern-match
`GotStarResult` out of a `Shared.Msg` they see in their own `update` --
`Main.elm` fires the gRPC call's `Cmd` from `Shared.update` directly, so its
eventual reply lands back in `Main.elm`'s top-level `Shared` branch, never
passing back through a page's own `update` the way the initiating `ToggleStar`
click did.

This module also owns fetching+rendering the actual starred `Post`s for the
nav's Starred panel (`view`) -- `posts` is a cache of that fetched data,
separate from `starredPostIds` itself so a re-star/unstar doesn't need a
round-trip to redisplay a post we already have in hand (see `ToggleStar`).

-}

import Animation
import Browser.Dom as Dom
import Components.Events as Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.ServerDependentView as ServerDependentView
import Dict exposing (Dict)
import Grpc
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class, id, style)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Proto.Rellm exposing (Event, GetEventsResponse, GetPostsResponse, Occasion, Post, defaultPost)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Rellm as Rellm
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.Time as SharedTime
import Task
import UI.Classes exposing (classes, escapeCSSClass, hostnameToCSSClass, openClosedClass)
import UI.Flip


type alias Model =
    { starredPostIds : Set String

    -- Same keys as `starredPostIds`, but ordered -- newest-star-first until
    -- the user drags that order around with `MoveStarUpClicked`/
    -- `MoveStarDownClicked` -- `starredPostIds` is a `Set` (unordered) so it
    -- can't drive display order itself. Kept in lockstep with
    -- `starredPostIds` by every mutation below.
    , starOrder : List String
    , showStarredPanel : Bool
    , posts : Dict String PostFetchStatus

    -- The owning `Event`/`Occasion` for every starred post whose own
    -- `Post` (in `posts`, above) turned out to be an `Occasion`'s --
    -- see `EventFetchStatus`'s own doc and `kickOffEventFetches`.
    , events : Dict String EventFetchStatus

    -- In-flight/settling FLIP slide animations for starred posts just
    -- reordered via `MoveStarUpClicked`/`MoveStarDownClicked` (see
    -- `UI.Flip.MoveState`), keyed the same as `starOrder`/`posts`. An entry
    -- with no key here (the common case) just renders at rest.
    , moveAnimations : Dict String (UI.Flip.MoveState Msg)

    -- Each starred post's enter/leave `UI.Flip.State`, keyed the same as
    -- `starOrder`/`posts` -- `update`'s very last step (see
    -- `syncItemAnimations`) is always `UI.Flip.syncEnter identity
    -- model.starOrder`, which inserts a fresh `UI.Flip.enter` for any key
    -- that doesn't have an entry yet, so a newly-starred post animates in
    -- with no need to hunt down every "this added a star" code path by hand.
    -- A post mid fade-out after being unstarred (see `ToggleStar`) stays in
    -- `starredPostIds`/`starOrder` -- and its entry here keeps `removing =
    -- True` -- until its fade actually finishes (`FinishUnstar`), so it keeps
    -- rendering (fading/collapsing) in the panel instead of just vanishing.
    -- `init` seeds this with a plain `UI.Flip.restingState` (not `enter`) for
    -- every persisted star, so reloading the app doesn't replay their
    -- entrances.
    , starAnimations : Dict String (UI.Flip.State Msg)

    -- Which half (if any) of `OrganizeStarred`'s FLIP measure-reorder-measure
    -- round trip is in flight -- see `GroupMeasurementPhase`'s own doc.
    , groupMeasurementPhase : GroupMeasurementPhase
    }


type Msg
    = ToggleStar RellmServer Post
    | GotStarResult String Bool (Result Grpc.Error Post)
    | ToggleStarredPanel
    | CloseStarredPanel
    | EnableServerClicked String
      -- Unstars a starred post whose own fetch (`PostFetchStatus`) already
      -- permanently failed -- see `starredPostView`'s `PostFetchFailed`
      -- branch. Unlike `ToggleStar`, there's no fetched `Post` in hand to
      -- pass the RPC (that's exactly why this exists), so this carries just
      -- the failed entry's `key` and rebuilds a minimal `Post` (only `id`
      -- matters -- `unstar_post.rs` looks up everything else server-side)
      -- to hand off to the same `ToggleStar` flow.
    | UnstarFailedPost String
      -- Reorders `starOrder` so starred Events and Posts are grouped
      -- together -- see `groupStarredOrder`. Only ever dispatched when both
      -- are present in the list (`starredPanelHasBothGroups`). Kicks off the
      -- "measure old positions" half of the FLIP round trip -- see
      -- `GroupMeasurementPhase`.
    | OrganizeStarred
      -- `Ports.elementsMeasured` firing -- which half of `OrganizeStarred`'s
      -- FLIP round trip this is (if any) is read off `model.groupMeasurementPhase`,
      -- not this `Msg`'s own (untargeted, port-delivered) payload.
    | GotMeasuredGroupRects Decode.Value
      -- One deliberate `requestAnimationFrame` wait between the reorder
      -- actually landing in the model and firing the *second*
      -- `UI.Flip.measureElementsCmd` -- see that function's own doc for why.
    | ReadyToMeasureNewGroupPositions
    | GotStarredPost String (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetPostsResponse ))
      -- `kickOffEventFetches`'s batched `GetEvents` reply for one server's
      -- worth of `OCCASION`-context starred posts -- `host`/the
      -- requested post ids are carried on the `Msg` itself (rather than
      -- looked up from `Model`) since a request that comes back empty still
      -- needs to mark every one of them `EventFetchFailed` (see this
      -- branch's own handling).
    | GotStarredEvents String (List String) (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetEventsResponse ))
    | PollStarredPosts
    | MoveStarUpClicked String
    | MoveStarDownClicked String
    | GotPreMoveStarPositions String String Int (Result Dom.Error ( Dom.Element, Dom.Element ))
    | AnimateMove Animation.Msg
    | MoveSettled String
    | FinishUnstar String
    | AnimateItemFlip Animation.Msg
    | MediaClicked String Post String
      -- A starred post/occasion's video preview play button tapped -- see `Components.MediaRenderer`'s
      -- own "Click-to-play video previews" doc. Same forwarding convention as `MediaClicked`
      -- above (this module doesn't own the actual click-to-play state, `Shared.Model.mediaRenderer`
      -- does) -- `sendUpdate` no-ops it, `update` surfaces it via the 3rd escape-hatch slot below.
    | MediaRendererMsg MediaRenderer.Msg
    | StarredPostsBroadcastReceived Decode.Value
    | PostUpdated String Post
      -- Unreachable placeholder passed as `Events.eventCard`'s/`Posts.postCard`'s
      -- `onPush`/`onDelete` -- this panel always passes `Nothing` for
      -- `availableSyncDestinations` (see `starredPostView`'s own `eventCard`/
      -- `postCard` calls), so no Push/Delete button ever renders to actually
      -- produce this.
    | NoOp


{-| The fetch state of one starred post, keyed by its `starKey` -- see
`kickOffFetches`. `ServerUnavailable` (its server isn't currently connected)
is kept distinct from `Failed` (the fetch itself came back an error, e.g. the
post is private and we're not signed in) so polling only keeps retrying the
former -- a server reconnecting is worth another try; a request that already
failed against a reachable server generally won't succeed just by asking
again.
-}
type PostFetchStatus
    = FetchingPost
    | PostFetchLoaded String Post
    | PostFetchFailed
    | ServerUnavailable


{-| The fetch state of one starred post's owning `Event`/`Occasion` --
only ever populated for a starred post whose `PostFetchStatus` is
`PostFetchLoaded` with `context == OCCASION` (see `kickOffEventFetches`),
keyed the same (`starKey`/`rawKey`) as `posts` itself. A plain `POST`/`REPLY`
starred post never gets an entry here at all -- `starredPostView` only reads
this dict once it already knows (from `posts`) that the entry needs it.
-}
type EventFetchStatus
    = FetchingEvent
    | EventFetchLoaded Event Occasion
    | EventFetchFailed


{-| Which half of `OrganizeStarred`'s FLIP measurement round-trip (if any)
`GotMeasuredGroupRects` is currently waiting on -- a port's incoming `Sub` is
a single, untargeted `Msg`, so there's nothing to pattern match on except
state carried in the `Model`, same reasoning as
`Components.Pages.EventsPage.MeasurementPhase` (which this mirrors).
`AwaitingOldGroupRects` carries the reorder to apply once those rects are in
hand; `AwaitingNewGroupRects` carries the old rects to diff the eventual new
ones against.
-}
type GroupMeasurementPhase
    = NotMeasuringGroup
    | AwaitingOldGroupRects (List String)
    | AwaitingNewGroupRects (Dict String UI.Flip.Rect)


{-| `flags` is the raw, persisted `List String` (see `Ports.persistStarredPosts`)
handed down from `Shared.init`, un-decoded -- same convention as
`AccountsPanel.init`'s `flags` argument.
-}
init : Decode.Value -> Model
init flags =
    let
        persistedOrder : List String
        persistedOrder =
            Decode.decodeValue (Decode.list Decode.string) flags
                |> Result.withDefault []
    in
    { starredPostIds = Set.fromList persistedOrder
    , starOrder = persistedOrder
    , showStarredPanel = False
    , posts = Dict.empty
    , events = Dict.empty
    , moveAnimations = Dict.empty

    -- Seeded with a *resting* (not `enter`) state for every persisted star,
    -- so `syncItemAnimations` -- which would otherwise treat any key with no
    -- entry as "just appeared" -- doesn't replay every star's entrance on
    -- every reload.
    , starAnimations = persistedOrder |> List.map (\key -> ( key, UI.Flip.restingState )) |> Dict.fromList
    , groupMeasurementPhase = NotMeasuringGroup
    }


{-| Just the starred posts' reorder-slide animations (see `moveAnimations`)
-- only while the panel's actually open, same reasoning as `Shared.subscriptions`'
own poll for this module.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.showStarredPanel then
            UI.Flip.moveSubscription AnimateMove (Dict.values model.moveAnimations)

          else
            Sub.none

        -- `OrganizeStarred`'s own FLIP round trip (see `GroupMeasurementPhase`)
        -- -- like `AnimateMove` above, only dispatchable from the open panel
        -- (`OrganizeStarred`'s button only renders there), so gated the same
        -- way.
        , if model.showStarredPanel then
            Ports.elementsMeasured GotMeasuredGroupRects

          else
            Sub.none

        -- Unlike the reorder-only `AnimateMove` above, this can't be gated on
        -- the panel being open -- `ToggleStar` (and so a pending `FinishUnstar`)
        -- can be triggered from anywhere a post card renders (Home, Post
        -- detail, ...), not just from here, so this needs to keep ticking
        -- regardless in order to ever actually fire.
        , UI.Flip.subscription AnimateItemFlip (Dict.values model.starAnimations)
        , Ports.starredPostsUpdated StarredPostsBroadcastReceived
        ]


{-| `update` also needs `AccountsPanel.Model` (to resolve starred posts' hosts
to actual connected `Server`s/signed-in `Account`s -- see `kickOffFetches`)
and can itself surface an `AccountsPanel.Msg` it needs forwarded on its behalf
-- either an `AccessTokenResponseReceived` (from fetching a starred post
whose access token needed renewing first -- see
`Shared.AccountsPanel.performWithOptionalAccountServer`, which already
builds it), or a disabled server's owner re-enabling it
(`EnableServerClicked`), forwarded as `AccountsPanel.ToggleServerEnabled` --
for `Shared.update` to actually dispatch. This module can't dispatch either
itself without importing `Shared` (a cycle, since `Shared` imports this
module).

Same reasoning covers the trailing `Maybe MediaViewerPanel.Msg` (paired with
the `Maybe AccountsPanel.Msg` above -- Elm tuples top out at three items, so
the two forwards share the last slot rather than this being a 4-tuple):
`MediaClicked` (a starred post's media tapped, see `starredPostView`) doesn't
change this module's own `Model` at all (see `sendUpdate`'s no-op branch for
it) -- it just needs `Shared.update` to open `Shared.MediaViewerPanel` on its
behalf, same forwarding convention as the `AccountsPanel.Msg` case, just
computed directly from `msg` here rather than from `sendUpdate`'s result,
since there's no `Model` state involved.

-}
update : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Maybe MediaViewerPanel.Msg, Maybe MediaRenderer.Msg ) )
update accountsPanelModel msg model =
    let
        ( newModel, cmd, maybeAccountsPanelMsg ) =
            sendUpdate accountsPanelModel msg model

        maybeMediaViewerPanelMsg : Maybe MediaViewerPanel.Msg
        maybeMediaViewerPanelMsg =
            case msg of
                MediaClicked host post mediaId ->
                    Just (MediaViewerPanel.Open post.media (Just post) mediaId host)

                _ ->
                    Nothing

        maybeMediaRendererMsg : Maybe MediaRenderer.Msg
        maybeMediaRendererMsg =
            case msg of
                MediaRendererMsg subMsg ->
                    Just subMsg

                _ ->
                    Nothing
    in
    ( syncItemAnimations newModel, cmd, ( maybeAccountsPanelMsg, maybeMediaViewerPanelMsg, maybeMediaRendererMsg ) )


sendUpdate : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, Maybe AccountsPanel.Msg )
sendUpdate accountsPanelModel msg model =
    case msg of
        ToggleStar server post ->
            let
                key : String
                key =
                    starKey server.frontendHost post

                starring : Bool
                starring =
                    not (Set.member key model.starredPostIds)

                rpc : Grpc.Rpc Post Post
                rpc =
                    if starring then
                        Rellm.starPost

                    else
                        Rellm.unstarPost

                rpcCmd : Cmd Msg
                rpcCmd =
                    Grpc.new rpc post
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> Grpc.toTask
                        |> Task.attempt (GotStarResult key starring)

                -- We already have this Post in hand -- cache it so the panel can show
                -- it immediately without a redundant fetch.
                newPosts : Dict String PostFetchStatus
                newPosts =
                    Dict.insert key (PostFetchLoaded server.frontendHost post) model.posts
            in
            if starring then
                let
                    newStarredPostIds : Set String
                    newStarredPostIds =
                        Set.insert key model.starredPostIds

                    newStarOrder : List String
                    newStarOrder =
                        key :: model.starOrder
                in
                ( { model | starredPostIds = newStarredPostIds, starOrder = newStarOrder, posts = newPosts }
                , Cmd.batch [ persistCmd newStarOrder, rpcCmd ]
                , Nothing
                )

            else
                -- Doesn't actually unstar (remove from `starredPostIds`/`starOrder`)
                -- yet -- starts its fade-out in the panel (see `starAnimations`),
                -- which sends `FinishUnstar` once that finishes to do the real
                -- removal. The RPC itself still fires immediately either way.
                let
                    currentState : UI.Flip.State Msg
                    currentState =
                        Dict.get key model.starAnimations |> Maybe.withDefault UI.Flip.restingState
                in
                ( { model
                    | posts = newPosts
                    , starAnimations = Dict.insert key (UI.Flip.remove (FinishUnstar key) currentState) model.starAnimations
                  }
                , rpcCmd
                , Nothing
                )

        GotStarResult key _ (Ok updatedPost) ->
            let
                newPosts : Dict String PostFetchStatus
                newPosts =
                    case parseStarKey key of
                        Just ( _, host ) ->
                            Dict.insert key (PostFetchLoaded host updatedPost) model.posts

                        Nothing ->
                            model.posts
            in
            ( { model | posts = newPosts }, Cmd.none, Nothing )

        GotStarResult key starring (Err _) ->
            if starring then
                -- Starring failed -- we DID optimistically add it, so revert that.
                let
                    revertedStarredPostIds : Set String
                    revertedStarredPostIds =
                        Set.remove key model.starredPostIds

                    revertedStarOrder : List String
                    revertedStarOrder =
                        List.filter ((/=) key) model.starOrder
                in
                ( { model | starredPostIds = revertedStarredPostIds, starOrder = revertedStarOrder }
                , persistCmd revertedStarOrder
                , Nothing
                )

            else
                -- Unstarring failed -- we deferred actually removing it (see
                -- `ToggleStar`), so it's still in `starredPostIds`/`starOrder`
                -- either way; just undo whatever we started.
                case Dict.get key model.starAnimations of
                    Just _ ->
                        -- Still fading out -- cancel that, fading back in instead
                        -- (`UI.Flip.reappear`), same as a post that was mid
                        -- fade-out reappearing elsewhere (see `Pages.Home_`).
                        ( { model | starAnimations = Dict.update key (Maybe.map UI.Flip.reappear) model.starAnimations }
                        , Cmd.none
                        , Nothing
                        )

                    Nothing ->
                        -- The fade (and the real removal, `FinishUnstar`) already
                        -- finished before this reply arrived -- re-add it, same as
                        -- if freshly starred again.
                        let
                            revertedStarredPostIds : Set String
                            revertedStarredPostIds =
                                Set.insert key model.starredPostIds

                            revertedStarOrder : List String
                            revertedStarOrder =
                                key :: model.starOrder
                        in
                        ( { model | starredPostIds = revertedStarredPostIds, starOrder = revertedStarOrder }
                        , persistCmd revertedStarOrder
                        , Nothing
                        )

        FinishUnstar key ->
            let
                newStarredPostIds : Set String
                newStarredPostIds =
                    Set.remove key model.starredPostIds

                newStarOrder : List String
                newStarOrder =
                    List.filter ((/=) key) model.starOrder
            in
            ( { model | starredPostIds = newStarredPostIds, starOrder = newStarOrder, starAnimations = Dict.remove key model.starAnimations }
            , persistCmd newStarOrder
            , Nothing
            )

        AnimateItemFlip animMsg ->
            let
                step : String -> UI.Flip.State Msg -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) )
                step key state ( states, accCmds ) =
                    let
                        ( newState, cmd ) =
                            UI.Flip.animate animMsg state
                    in
                    ( Dict.insert key newState states, cmd :: accCmds )

                ( newStarAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.starAnimations
            in
            ( { model | starAnimations = newStarAnimations }, Cmd.batch cmds, Nothing )

        ToggleStarredPanel ->
            let
                toggledModel : Model
                toggledModel =
                    { model | showStarredPanel = not model.showStarredPanel }
            in
            if toggledModel.showStarredPanel then
                let
                    ( fetchedModel, cmd ) =
                        kickOffFetches accountsPanelModel toggledModel
                in
                ( fetchedModel, cmd, Nothing )

            else
                ( toggledModel, Cmd.none, Nothing )

        -- Unlike `ToggleStarredPanel`, always closes rather than
        -- flipping -- dispatched by the Home link (`UI.navLink`) on every
        -- click, so navigating Home also dismisses this panel if it happened
        -- to be open, same as `AccountsPanel.CloseAccountsPanel`'s `i`-button.
        CloseStarredPanel ->
            ( { model | showStarredPanel = False }, Cmd.none, Nothing )

        EnableServerClicked host ->
            -- Just forwards to `AccountsPanel.ToggleServerEnabled` -- once
            -- `Shared.update` dispatches it and the server's `enabled` flips
            -- back on, `refreshHosts` re-fetches this post the same as any
            -- other reconnect (see `Shared.starredPostsRefreshHosts`).
            ( model, Cmd.none, Just (AccountsPanel.ToggleServerEnabled host) )

        UnstarFailedPost key ->
            -- Rebuilds just enough of a `Post` (only `id` matters -- see this
            -- constructor's own doc) to hand off to `ToggleStar`'s existing
            -- unstar path (RPC + fade-out), same as clicking "unstar" on a
            -- post we actually managed to load.
            case
                parseStarKey key
                    |> Maybe.andThen (\( postId, host ) -> toggleStarMsg accountsPanelModel host { defaultPost | id = postId })
            of
                Just toggleMsg ->
                    sendUpdate accountsPanelModel toggleMsg model

                Nothing ->
                    ( model, Cmd.none, Nothing )

        OrganizeStarred ->
            ( { model | groupMeasurementPhase = AwaitingOldGroupRects (groupStarredOrder model) }
            , UI.Flip.measureElementsCmd starEntryDomId model.starOrder
            , Nothing
            )

        GotMeasuredGroupRects value ->
            case Decode.decodeValue UI.Flip.rectsDecoder value of
                Err _ ->
                    let
                        ( newModel, cmd ) =
                            applyGroupMeasurementFailure model
                    in
                    ( newModel, cmd, Nothing )

                Ok rects ->
                    case model.groupMeasurementPhase of
                        NotMeasuringGroup ->
                            -- A stray/late result with nothing pending (e.g.
                            -- from some other `UI.Flip.measureElementsCmd`
                            -- caller elsewhere in the app, since
                            -- `Ports.elementsMeasured` is a single shared
                            -- port) -- ignore.
                            ( model, Cmd.none, Nothing )

                        AwaitingOldGroupRects newOrder ->
                            let
                                newModel : Model
                                newModel =
                                    { model | starOrder = newOrder, groupMeasurementPhase = AwaitingNewGroupRects rects }
                            in
                            ( newModel
                            , Cmd.batch
                                [ persistCmd newOrder
                                , Task.attempt (\_ -> ReadyToMeasureNewGroupPositions) Dom.getViewport
                                ]
                            , Nothing
                            )

                        AwaitingNewGroupRects oldRects ->
                            let
                                startMoveFor : String -> UI.Flip.Rect -> Dict String (UI.Flip.MoveState Msg) -> Dict String (UI.Flip.MoveState Msg)
                                startMoveFor key oldRect anims =
                                    case Dict.get key rects of
                                        Just newRect ->
                                            Dict.insert key
                                                (UI.Flip.startMove (MoveSettled key)
                                                    ( oldRect.x - newRect.x, oldRect.y - newRect.y )
                                                    (Dict.get key anims |> Maybe.withDefault UI.Flip.atRest)
                                                )
                                                anims

                                        Nothing ->
                                            anims
                            in
                            ( { model
                                | moveAnimations = Dict.foldl startMoveFor model.moveAnimations oldRects
                                , groupMeasurementPhase = NotMeasuringGroup
                              }
                            , Cmd.none
                            , Nothing
                            )

        ReadyToMeasureNewGroupPositions ->
            case model.groupMeasurementPhase of
                AwaitingNewGroupRects oldRects ->
                    ( model, UI.Flip.measureElementsCmd starEntryDomId (Dict.keys oldRects), Nothing )

                _ ->
                    -- Nothing pending anymore -- ignore.
                    ( model, Cmd.none, Nothing )

        PollStarredPosts ->
            let
                ( fetchedModel, cmd ) =
                    kickOffFetches accountsPanelModel model
            in
            ( fetchedModel, cmd, Nothing )

        GotStarredPost key (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                newStatus : PostFetchStatus
                newStatus =
                    case ( parseStarKey key, List.head response.posts ) of
                        ( Just ( _, host ), Just post ) ->
                            PostFetchLoaded host post

                        _ ->
                            PostFetchFailed

                ( eventModel, eventCmd ) =
                    kickOffEventFetches accountsPanelModel { model | posts = Dict.insert key newStatus model.posts }
            in
            ( eventModel, eventCmd, maybeAccountsPanelMsg )

        GotStarredPost key (Err _) ->
            ( { model | posts = Dict.insert key PostFetchFailed model.posts }, Cmd.none, Nothing )

        GotStarredEvents host postIds (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                loadedByPostId : Dict String ( Event, Occasion )
                loadedByPostId =
                    Events.occasionPairs response
                        |> List.filterMap
                            (\( event, occasion ) ->
                                occasion.post |> Maybe.map (\occasionPost -> ( occasionPost.id, ( event, occasion ) ))
                            )
                        |> Dict.fromList

                newEvents : Dict String EventFetchStatus
                newEvents =
                    List.foldl
                        (\postId events ->
                            case Dict.get postId loadedByPostId of
                                Just ( event, occasion ) ->
                                    Dict.insert (rawKey postId host) (EventFetchLoaded event occasion) events

                                Nothing ->
                                    Dict.insert (rawKey postId host) EventFetchFailed events
                        )
                        model.events
                        postIds
            in
            ( { model | events = newEvents }, Cmd.none, maybeAccountsPanelMsg )

        GotStarredEvents host postIds (Err _) ->
            ( { model
                | events = List.foldl (\postId -> Dict.insert (rawKey postId host) EventFetchFailed) model.events postIds
              }
            , Cmd.none
            , Nothing
            )

        MoveStarUpClicked key ->
            ( model, UI.Flip.beginReorder identity starEntryDomId GotPreMoveStarPositions -1 key model.starOrder, Nothing )

        MoveStarDownClicked key ->
            ( model, UI.Flip.beginReorder identity starEntryDomId GotPreMoveStarPositions 1 key model.starOrder, Nothing )

        GotPreMoveStarPositions key _ offset (Err _) ->
            -- Couldn't measure -- e.g. an entry not actually mounted -- fall
            -- back to reordering without a slide animation, same end state
            -- either way.
            let
                newOrder : List String
                newOrder =
                    UI.Flip.moveListItemBy identity offset key model.starOrder
            in
            ( { model | starOrder = newOrder }, persistCmd newOrder, Nothing )

        GotPreMoveStarPositions key neighborKey offset (Ok ( entryEl, neighborEl )) ->
            -- Both `key` and `neighborKey` are adjacent, so their post-swap
            -- positions are derivable from this one (pre-swap) measurement --
            -- see `UI.Flip.applyReorder`/`swapDeltas`. Computing it this way
            -- (rather than reordering first, then measuring again after the
            -- next render) means the pinned "Invert" transform is set in the
            -- very same update as the reorder, so there's no frame where the
            -- reordered list renders at rest before the animation kicks in.
            let
                newOrder : List String
                newOrder =
                    UI.Flip.moveListItemBy identity offset key model.starOrder

                newModel : Model
                newModel =
                    { model | starOrder = newOrder }
            in
            ( { newModel
                | moveAnimations =
                    UI.Flip.applyReorder UI.Flip.Vertical MoveSettled key neighborKey entryEl neighborEl newModel.moveAnimations
              }
            , persistCmd newOrder
            , Nothing
            )

        AnimateMove animMsg ->
            let
                step : String -> UI.Flip.MoveState Msg -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) )
                step key state ( states, cmds ) =
                    let
                        ( newState, cmd ) =
                            UI.Flip.moveAnimate animMsg state
                    in
                    ( Dict.insert key newState states, cmd :: cmds )

                ( newMoveAnimations, moveCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.moveAnimations
            in
            ( { model | moveAnimations = newMoveAnimations }
            , Cmd.batch moveCmds
            , Nothing
            )

        MoveSettled key ->
            ( { model | moveAnimations = Dict.update key (Maybe.map (\state -> { state | moving = False })) model.moveAnimations }
            , Cmd.none
            , Nothing
            )

        MediaClicked _ _ _ ->
            -- Handled by `update`, above -- see its own doc comment. Doesn't
            -- touch this module's `Model`, so nothing to do here.
            ( model, Cmd.none, Nothing )

        MediaRendererMsg _ ->
            -- Handled by `update`, above -- see its own doc comment. The actual click-to-play
            -- state lives in `Shared.Model.mediaRenderer`, not here.
            ( model, Cmd.none, Nothing )

        -- A page that owns `post` fully saved a new copy of it (see
        -- `freshestPost`'s doc) -- only overwrites an existing cache entry,
        -- never creates one, since a `Post` that was never starred/fetched
        -- into this panel has no stale copy here to correct in the first
        -- place.
        PostUpdated frontendHost post ->
            let
                key : String
                key =
                    starKey frontendHost post
            in
            ( { model | posts = Dict.update key (Maybe.map (\_ -> PostFetchLoaded frontendHost post)) model.posts }
            , Cmd.none
            , Nothing
            )

        NoOp ->
            ( model, Cmd.none, Nothing )

        StarredPostsBroadcastReceived value ->
            case Decode.decodeValue (Decode.list Decode.string) value of
                Err _ ->
                    ( model, Cmd.none, Nothing )

                Ok newOrder ->
                    let
                        stillStarred : String -> a -> Bool
                        stillStarred key _ =
                            List.member key newOrder

                        ( fetchedModel, cmd ) =
                            kickOffFetches accountsPanelModel
                                { model
                                    | starredPostIds = Set.fromList newOrder
                                    , starOrder = newOrder

                                    -- Drops any cached fetch/animation state for a post no
                                    -- longer starred (removed in the broadcasting tab) -- this
                                    -- tab never ran its own fade-out (`FinishUnstar`) for it, so
                                    -- nothing else would otherwise clear these.
                                    , posts = Dict.filter stillStarred model.posts
                                    , starAnimations = Dict.filter stillStarred model.starAnimations
                                    , moveAnimations = Dict.filter stillStarred model.moveAnimations
                                }
                    in
                    ( fetchedModel, cmd, Nothing )


{-| Inserts a fresh `UI.Flip.enter` into `starAnimations` for any starred
post that doesn't have an entry yet -- see that field's own doc, and
`UI.Flip.syncEnter`. Run unconditionally after every message (see `update`),
same reasoning as `AccountsPanel.syncItemAnimations`.
-}
syncItemAnimations : Model -> Model
syncItemAnimations model =
    { model | starAnimations = UI.Flip.syncEnter identity model.starOrder model.starAnimations }


{-| Fetches every starred post that isn't already loaded, in flight, or
permanently failed (see `PostFetchStatus`) -- grouped by host first, so each
server's connected `Server`/signed-in `Account` (from `AccountsPanel.Model`,
see `Shared.RellmAccounts.enabledRellmAccountForServer`) is only looked up once per
server rather than once per post, and posts on a server we're not signed into
are still fetched anonymously (same as `Pages.Home_`/`Pages.Post.PostId_`),
just without any `LIMITED`/`PRIVATE` visibility they'd need an account for.
-}
kickOffFetches : AccountsPanel.Model -> Model -> ( Model, Cmd Msg )
kickOffFetches accountsPanelModel model =
    let
        pending : List ( String, String )
        pending =
            model.starredPostIds
                |> Set.toList
                |> List.filterMap parseStarKey
                |> List.filter (\( postId, host ) -> needsFetch model.posts (rawKey postId host))

        ( newPosts, cmds ) =
            pending
                |> groupByHost
                |> List.foldl (fetchGroup accountsPanelModel) ( model.posts, [] )

        ( eventModel, eventCmd ) =
            kickOffEventFetches accountsPanelModel { model | posts = newPosts }
    in
    ( eventModel, Cmd.batch (eventCmd :: cmds) )


{-| Fetches the owning `Event`/`Occasion` (see `EventFetchStatus`'s own
doc) for every starred post already `PostFetchLoaded` with `context ==
OCCASION` that doesn't have one yet -- always run right after `posts`
changes (`kickOffFetches`, `GotStarredPost`), same "grouped by host, one
request per server" batching `kickOffFetches` uses for the posts themselves
(see `fetchEventGroup`), via `Components.Events.fetchEventsByOccasionPostIds`'
own `occasion_post_ids` batch RPC. Doesn't need `fetchGroup`'s own
`ServerDependentView.availableServer` check -- a post already loaded from
`host` proves that server is currently reachable.
-}
kickOffEventFetches : AccountsPanel.Model -> Model -> ( Model, Cmd Msg )
kickOffEventFetches accountsPanelModel model =
    let
        pending : List ( String, String )
        pending =
            model.posts
                |> Dict.toList
                |> List.filterMap
                    (\( key, status ) ->
                        case status of
                            PostFetchLoaded host post ->
                                if post.context == OCCASION && needsEventFetch model.events key then
                                    Just ( post.id, host )

                                else
                                    Nothing

                            _ ->
                                Nothing
                    )

        ( newEvents, cmds ) =
            pending
                |> groupByHost
                |> List.foldl (fetchEventGroup accountsPanelModel) ( model.events, [] )
    in
    ( { model | events = newEvents }, Cmd.batch cmds )


{-| Clears any cached fetched Posts/Events (see `posts`/`events`) on `hosts`
and kicks off fresh fetches for whichever of those are still starred -- for
`Shared.update` to call when the signed-in account for a server changes
(comparing `RellmAccounts.enabledRellmAccountForServer` before/after an
`AccountsPanelMsg`), since a starred post's visibility -- and its cached
`freshestPost` snapshot -- can depend on which account fetched it. A no-op if
`hosts` is empty, the common case for most `AccountsPanel.Msg`s.
-}
refreshHosts : AccountsPanel.Model -> List String -> Model -> ( Model, Cmd Msg )
refreshHosts accountsPanelModel hosts model =
    if List.isEmpty hosts then
        ( model, Cmd.none )

    else
        let
            hostSet : Set String
            hostSet =
                Set.fromList hosts

            notOnRefreshedHost : String -> Bool
            notOnRefreshedHost key =
                case parseStarKey key of
                    Just ( _, host ) ->
                        not (Set.member host hostSet)

                    Nothing ->
                        True

            clearedPosts : Dict String PostFetchStatus
            clearedPosts =
                Dict.filter (\key _ -> notOnRefreshedHost key) model.posts

            clearedEvents : Dict String EventFetchStatus
            clearedEvents =
                Dict.filter (\key _ -> notOnRefreshedHost key) model.events
        in
        kickOffFetches accountsPanelModel { model | posts = clearedPosts, events = clearedEvents }


{-| `GotMeasuredGroupRects`'s fallback for a payload that failed to decode
(should never actually happen -- `Ports.measureElements`'s JS side always
sends a well-formed array -- but mirrors
`Components.Pages.EventsPage.applyMeasurementFailure`'s "give up silently"
convention regardless): still applies a pending reorder if
`model.groupMeasurementPhase` had one in flight, just with no slide
animation, rather than leaving the click seemingly do nothing.
-}
applyGroupMeasurementFailure : Model -> ( Model, Cmd Msg )
applyGroupMeasurementFailure model =
    case model.groupMeasurementPhase of
        NotMeasuringGroup ->
            ( model, Cmd.none )

        AwaitingOldGroupRects newOrder ->
            let
                newModel : Model
                newModel =
                    { model | starOrder = newOrder, groupMeasurementPhase = NotMeasuringGroup }
            in
            ( newModel, persistCmd newOrder )

        AwaitingNewGroupRects _ ->
            ( { model | groupMeasurementPhase = NotMeasuringGroup }, Cmd.none )


persistCmd : List String -> Cmd Msg
persistCmd starOrder =
    Ports.persistStarredPosts (Encode.list Encode.string starOrder)


{-| `ServerDependentView.availableServer` -- not the raw
`RellmServers.rellmServerForHost` -- so a starred post whose server is known but
disabled (see `Shared.AccountsPanel`'s `Server.enabled`) is treated the same
as one whose server was never connected at all: marked `ServerUnavailable`
below rather than fetched, matching the panel's own `starredPostView`, which
shows the same "server isn't reachable" message either way.
-}
fetchGroup :
    AccountsPanel.Model
    -> ( String, List String )
    -> ( Dict String PostFetchStatus, List (Cmd Msg) )
    -> ( Dict String PostFetchStatus, List (Cmd Msg) )
fetchGroup accountsPanelModel ( host, postIds ) ( posts, cmds ) =
    case ServerDependentView.availableServer accountsPanelModel.servers host of
        Nothing ->
            ( List.foldl (\postId -> Dict.insert (rawKey postId host) ServerUnavailable) posts postIds
            , cmds
            )

        Just _ ->
            let
                maybeAccountServer : AccountsPanel.MaybeAccountServer
                maybeAccountServer =
                    ( RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host |> Maybe.map .userId, host )

                fetchCmds : List (Cmd Msg)
                fetchCmds =
                    List.map
                        (\postId ->
                            Posts.fetchPost accountsPanelModel maybeAccountServer postId
                                |> Task.attempt (GotStarredPost (rawKey postId host))
                        )
                        postIds
            in
            ( List.foldl (\postId -> Dict.insert (rawKey postId host) FetchingPost) posts postIds
            , cmds ++ fetchCmds
            )


{-| `fetchGroup`'s counterpart for `kickOffEventFetches` -- one batched
`GetEvents` request per server (`Components.Events.fetchEventsByOccasionPostIds`)
covering every `postIds` entry needing one, rather than `fetchGroup`'s own
one-`GetPosts`-per-post. No `ServerDependentView.availableServer` check here
(unlike `fetchGroup`) -- see `kickOffEventFetches`'s own doc for why a
starred post already `PostFetchLoaded` from `host` already proves that
server's reachable.
-}
fetchEventGroup :
    AccountsPanel.Model
    -> ( String, List String )
    -> ( Dict String EventFetchStatus, List (Cmd Msg) )
    -> ( Dict String EventFetchStatus, List (Cmd Msg) )
fetchEventGroup accountsPanelModel ( host, postIds ) ( events, cmds ) =
    let
        maybeAccountServer : AccountsPanel.MaybeAccountServer
        maybeAccountServer =
            ( RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host |> Maybe.map .userId, host )

        fetchCmd : Cmd Msg
        fetchCmd =
            Events.fetchEventsByOccasionPostIds accountsPanelModel maybeAccountServer postIds
                |> Task.attempt (GotStarredEvents host postIds)
    in
    ( List.foldl (\postId -> Dict.insert (rawKey postId host) FetchingEvent) events postIds
    , fetchCmd :: cmds
    )



-- VIEW


{-| The Starred panel's content -- always rendered (even "closed"), same
as `UI.elm`'s Accounts/Admin panels, so opening/closing can be a plain CSS
transition. Returns `Html Msg` (this module's own `Msg`, mapped into
`Shared.Msg` by `UI.elm`'s `starredPostsMenu`) rather than `Html Shared.Msg`
directly -- unlike those other panels' view code, which lives in `UI.elm`
itself and so can reach `Shared.Msg` freely, this one can't (`Shared` imports
`Shared.StarredPanel`, so the reverse import would be a cycle).
-}
view : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> Html Msg
view time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel =
    let
        stateClass : String
        stateClass =
            openClosedClass model.showStarredPanel
    in
    div [ classes [ "starred-panel", "nav-panel", stateClass ] ]
        (div [ class "starred-panel-header" ]
            (text "Starred"
                :: (if starredPanelHasBothGroups model then
                        [ button
                            [ classes [ "starred-panel-organize-button", "background-color-nav" ]
                            , onClick OrganizeStarred
                            ]
                            [ text "Organize" ]
                        ]

                    else
                        []
                   )
            )
            :: (if Set.isEmpty model.starredPostIds then
                    [ div [ class "starred-panel-empty" ] [ text "No starred posts yet." ] ]

                else
                    let
                        count : Int
                        count =
                            List.length model.starOrder
                    in
                    -- `starOrder` starts newest-star-first (see `Model`), but the user
                    -- can then drag it around from there via `MoveStarUpClicked`/
                    -- `MoveStarDownClicked`.
                    [ Html.Keyed.node "div"
                        [ classes [ "starred-panel-list", "flip-animated-column" ] ]
                        (List.indexedMap
                            (\index key -> ( key, starredPostRowFlip time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel count index key ))
                            model.starOrder
                        )
                    ]
               )
        )


{-| Wraps `starredPostRow` in a fading/scaling/collapsing animated outer
`div` (entering when freshly starred, removing when unstarred -- see
`starAnimations`/`UI.Flip`), same two-layer reasoning as `UI.accountRowFlip`
(fade/collapse here vs. `starredPostRow`'s own, independent reorder-slide).
-}
starredPostRowFlip : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> Int -> Int -> String -> Html Msg
starredPostRowFlip time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel count index key =
    let
        flipState : UI.Flip.State Msg
        flipState =
            Dict.get key model.starAnimations |> Maybe.withDefault UI.Flip.restingState

        isMoving : Bool
        isMoving =
            Dict.get key model.moveAnimations |> Maybe.map .moving |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if flipState.removing then
                [ style "pointer-events" "none" ]

            else
                []
    in
    div (UI.Flip.itemAttributes UI.Flip.Vertical flipState isMoving)
        [ div pointerEventsAttr [ starredPostRow time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel count index key ] ]


{-| Wraps `starredPostView`'s content with `UI.Flip`'s slide-on-reorder
transform and the up/down reorder buttons -- mirrors `UI.accountRow`'s
equivalent for Accounts.
-}
starredPostRow : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> Int -> Int -> String -> Html Msg
starredPostRow time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel count index key =
    let
        moveAttrs : List (Html.Attribute Msg)
        moveAttrs =
            model.moveAnimations
                |> Dict.get key
                |> Maybe.map UI.Flip.moveAttributes
                |> Maybe.withDefault []
    in
    div
        (id (starEntryDomId key)
            :: class "starred-post-row"
            :: moveAttrs
        )
        [ UI.Flip.reorderButtons
            { moveUp = MoveStarUpClicked key
            , moveDown = MoveStarDownClicked key
            , canMoveUp = index > 0
            , canMoveDown = index < count - 1
            }
        , starredPostView time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel key
        ]


starredPostView : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> String -> Html Msg
starredPostView time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel key =
    case Dict.get key model.posts of
        Just (PostFetchLoaded host post) ->
            if post.context == OCCASION then
                starredOccasionView time basePath accountsPanelModel currentOccasionId model mediaRendererModel key host post

            else
                let
                    starred : Bool
                    starred =
                        isStarred host post model

                    current : Bool
                    current =
                        currentPostKey == Just key

                    onStarClicked : Maybe Msg
                    onStarClicked =
                        toggleStarMsg accountsPanelModel host post

                    maybeServer : Maybe RellmServer
                    maybeServer =
                        RellmServers.rellmServerForHost accountsPanelModel.servers host

                    maybeAccount : Maybe RellmAccount
                    maybeAccount =
                        RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host

                    onMediaClicked : String -> Msg
                    onMediaClicked mediaId =
                        MediaClicked host post mediaId

                    onMediaPlayClicked : String -> Msg
                    onMediaPlayClicked mediaId =
                        MediaRendererMsg (MediaRenderer.PlayClicked mediaId)
                in
                div [ class "starred-post-entry" ]
                    [ case Posts.postContextLabel post.context of
                        Just contextLabel ->
                            div [ class "starred-post-context" ] [ text contextLabel ]

                        Nothing ->
                            text ""
                    , Posts.postCard time basePath accountsPanelModel.mainFrontendHost host maybeServer maybeAccount onMediaClicked mediaRendererModel onMediaPlayClicked True current starred onStarClicked False Nothing (\_ -> False) (\_ -> Nothing) (\_ -> NoOp) (\_ _ -> NoOp) post
                    ]

        Just FetchingPost ->
            div [ class "starred-post-entry post-loading" ] [ text "Loading…" ]

        Just PostFetchFailed ->
            let
                host : String
                host =
                    String.split "@" key
                        |> List.reverse
                        |> List.head
                        |> Maybe.withDefault ""
            in
            div [ classes [ hostnameToCSSClass host, "starred-post-entry", "post-error" ] ]
                [ text ("Couldn't load Post " ++ key ++ ". Maybe it doesn't exist, or maybe you need to be logged in?")
                , button [ onClick (UnstarFailedPost key), classes [ "background-color-primary", hostnameToCSSClass host ] ] [ text "Unstar" ]
                ]

        Just ServerUnavailable ->
            let
                -- `ServerUnavailable` covers both "server not connected at
                -- all" and "server connected but disabled" (see `fetchGroup`'s
                -- use of `ServerDependentView.availableServer`) -- only the
                -- latter has anything to offer a button for, so re-derive the
                -- actual `Server` (if disabled) from `key`'s host.
                maybeDisabledServer : Maybe RellmServer
                maybeDisabledServer =
                    parseStarKey key
                        |> Maybe.andThen (\( _, host ) -> RellmServers.rellmServerForHost accountsPanelModel.servers host)
                        |> Maybe.andThen
                            (\server ->
                                if server.enabled then
                                    Nothing

                                else
                                    Just server
                            )
            in
            div [ class "starred-post-entry post-error" ]
                (text "That post's server isn't reachable right now."
                    :: (case maybeDisabledServer of
                            Just server ->
                                [ button [ onClick (EnableServerClicked server.frontendHost) ] [ text ("Enable " ++ server.frontendHost) ] ]

                            Nothing ->
                                []
                       )
                )

        Nothing ->
            text ""


{-| `starredPostView`'s branch for a starred post whose own `context` is
`OCCASION` -- renders `Components.Events.eventCard` (the same card
`Components.Pages.EventsPage` uses for its own listing) instead of
`Posts.postCard`, sourcing the `Event`/`Occasion` data it needs from
`model.events` (see `kickOffEventFetches`). `post` here is always the
freshest known copy of the `Occasion`'s own Post (`Dict.get key
model.posts`, same as `starredPostView`'s own `PostFetchLoaded` branch) --
overlaid onto the fetched `occasion.post` (via `displayOccasion`, below)
before rendering, so a just-toggled star's fresh count (see `GotStarResult`,
which updates `model.posts` directly) shows immediately without waiting on a
whole fresh `GetEvents` round-trip, mirroring
`Components.Pages.EventsPage.eventCardView`'s own `displayOccasion` swap.
-}
starredOccasionView : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Model -> MediaRenderer.Model -> String -> String -> Post -> Html Msg
starredOccasionView time basePath accountsPanelModel currentOccasionId model mediaRendererModel key host post =
    case Dict.get key model.events of
        Just (EventFetchLoaded event occasion) ->
            let
                starred : Bool
                starred =
                    isStarred host post model

                current : Bool
                current =
                    currentOccasionId == (occasion.post |> Maybe.map .id)

                onStarClicked : Maybe Msg
                onStarClicked =
                    toggleStarMsg accountsPanelModel host post

                maybeServer : Maybe RellmServer
                maybeServer =
                    RellmServers.rellmServerForHost accountsPanelModel.servers host

                maybeAccount : Maybe RellmAccount
                maybeAccount =
                    RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host

                displayOccasion : Occasion
                displayOccasion =
                    { occasion | post = Just post }

                onMediaClicked : String -> Msg
                onMediaClicked mediaId =
                    case event.post of
                        Just eventPost ->
                            MediaClicked host eventPost mediaId

                        Nothing ->
                            MediaClicked host post mediaId

                onMediaPlayClicked : String -> Msg
                onMediaPlayClicked mediaId =
                    MediaRendererMsg (MediaRenderer.PlayClicked mediaId)
            in
            div [ class "starred-post-entry" ]
                [ case Posts.postContextLabel post.context of
                    Just contextLabel ->
                        div [ class "starred-post-context" ] [ text contextLabel ]

                    Nothing ->
                        text ""
                , Events.eventCard time basePath accountsPanelModel.mainFrontendHost host maybeServer maybeAccount onMediaClicked mediaRendererModel onMediaPlayClicked MediaRenderer.ExtraSmall starred onStarClicked current False False Nothing (\_ -> False) (\_ -> Nothing) (\_ -> NoOp) (\_ _ -> NoOp) event displayOccasion
                ]

        Just FetchingEvent ->
            div [ class "starred-post-entry post-loading" ] [ text "Loading…" ]

        Just EventFetchFailed ->
            div [ class "starred-post-entry post-error" ]
                [ text ("Couldn't load Event for Post " ++ key ++ ".")
                , button [ onClick (UnstarFailedPost key), classes [ "background-color-primary", hostnameToCSSClass host ] ] [ text "Unstar" ]
                ]

        Nothing ->
            div [ class "starred-post-entry post-loading" ] [ text "Loading…" ]


{-| The persisted key for a Post on `frontendHost`. Always includes the host
explicitly -- unlike `Components.Posts.postHref`'s "bare id implies
mainFrontendHost" convention -- since `mainFrontendHost` can change later
(`AccountsPanel.ResetMainFrontendHost`) and a starred post needs to keep
pointing at the server it actually came from regardless.
-}
starKey : String -> Post -> String
starKey frontendHost post =
    post.id ++ "@" ++ frontendHost


{-| The DOM `id` a starred post's entry is rendered with (see
`starredPostEntry`) -- purely so `MoveStarUpClicked`/`MoveStarDownClicked` can
measure its position before/after a reorder (`Browser.Dom.getElement`) to
drive its `UI.Flip` slide.
-}
starEntryDomId : String -> String
starEntryDomId key =
    "starred-post-entry-" ++ escapeCSSClass key


rawKey : String -> String -> String
rawKey postId host =
    postId ++ "@" ++ host


isStarred : String -> Post -> Model -> Bool
isStarred frontendHost post model =
    Set.member (starKey frontendHost post) model.starredPostIds


{-| The freshest known version of `post` -- if it's ever been starred/unstarred
this session (see `ToggleStar`), `model.posts` holds either the optimistic
snapshot from that click or (once the RPC replies) the server's actual updated
`Post`, complete with its current star count. Falls back to `post` itself
(whatever the caller fetched it as) if it's never been touched.

Because this always wins over whatever `Post` a page fetched for itself, a
page that edits and re-saves a `Post` (e.g. `Pages.Post.PostId_`'s visibility/
content editors) must also feed its freshly-saved copy back in here (see
`PostUpdated`), or this cache entry goes stale and `freshestPost` keeps
serving the old one right back to it.

-}
freshestPost : String -> Post -> Model -> Post
freshestPost frontendHost post model =
    case Dict.get (starKey frontendHost post) model.posts of
        Just (PostFetchLoaded _ freshPost) ->
            freshPost

        _ ->
            post


groupByHost : List ( String, String ) -> List ( String, List String )
groupByHost pairs =
    pairs
        |> List.foldl
            (\( postId, host ) -> Dict.update host (\existing -> Just (postId :: Maybe.withDefault [] existing)))
            Dict.empty
        |> Dict.toList


needsFetch : Dict String PostFetchStatus -> String -> Bool
needsFetch posts key =
    case Dict.get key posts of
        Just (PostFetchLoaded _ _) ->
            False

        Just FetchingPost ->
            False

        Just PostFetchFailed ->
            False

        Just ServerUnavailable ->
            True

        Nothing ->
            True


{-| `needsFetch`'s counterpart for `events` -- simpler than `needsFetch`
itself since there's no `ServerUnavailable` state to retry here (see
`kickOffEventFetches`'s own doc: a starred post already `PostFetchLoaded`
already proves its server is reachable, so nothing here ever needs that
retry path).
-}
needsEventFetch : Dict String EventFetchStatus -> String -> Bool
needsEventFetch events key =
    case Dict.get key events of
        Just (EventFetchLoaded _ _) ->
            False

        Just FetchingEvent ->
            False

        Just EventFetchFailed ->
            False

        Nothing ->
            True


{-| The inverse of `starKey ++ "@" ++ host` -- a starred post's id and the
host it was starred from.
-}
parseStarKey : String -> Maybe ( String, String )
parseStarKey key =
    case String.split "@" key of
        [ postId, host ] ->
            Just ( postId, host )

        _ ->
            Nothing


{-| `ToggleStar`, if `host` currently resolves to a connected `Server` --
`Nothing` if it doesn't (nothing to star it against). Shared by every page
that renders a `postCard`/`postDetail` (`Pages.Home_`, `Pages.Post.PostId_`,
and this module's own `starredPostView`) so each doesn't re-derive the same
"look up the server, then wrap `ToggleStar`" logic.
-}
toggleStarMsg : AccountsPanel.Model -> String -> Post -> Maybe Msg
toggleStarMsg accountsPanelModel host post =
    RellmServers.rellmServerForHost accountsPanelModel.servers host
        |> Maybe.map (\server -> ToggleStar server post)


{-| Whether the starred entry `key` is a starred Event (i.e. its fetched
`Post`'s `context` is `OCCASION` -- see `starredOccasionView`).
An entry that's still loading, failed, or unavailable is treated as not an
Event -- its actual context isn't known yet, and `groupStarredOrder` needs
_some_ answer for every key in `starOrder`.
-}
isEventKey : Model -> String -> Bool
isEventKey model key =
    case Dict.get key model.posts of
        Just (PostFetchLoaded _ post) ->
            post.context == OCCASION

        _ ->
            False


{-| Whether the "Organize" button (`OrganizeStarred`) should show at all -- only
worth offering when `starOrder` actually mixes both kinds, per `isEventKey`.
-}
starredPanelHasBothGroups : Model -> Bool
starredPanelHasBothGroups model =
    List.any (isEventKey model) model.starOrder && List.any (not << isEventKey model) model.starOrder


{-| `OrganizeStarred`'s reorder: partitions `starOrder` into Events and Posts,
each keeping its original relative order (`List.partition` is stable) --
then, if `starOrder` isn't already exactly "all Events, then all Posts",
returns that arrangement. If it already is (i.e. this is a second click),
flips to "all Posts, then all Events" instead, so the button toggles between
the two groupings rather than being a no-op once already grouped.
-}
groupStarredOrder : Model -> List String
groupStarredOrder model =
    let
        ( events, posts ) =
            List.partition (isEventKey model) model.starOrder

        eventsFirst : List String
        eventsFirst =
            events ++ posts
    in
    if model.starOrder == eventsFirst then
        posts ++ events

    else
        eventsFirst
