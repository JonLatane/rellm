module Shared.StarredPanel exposing (Model, Msg(..), freshestPost, hasAnyStars, hasPendingFetches, init, isStarred, rawKey, refreshHosts, refreshServerStars, subscriptions, toggleStarMsg, totalStarCount, update, view)

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

Mastodon/Bluesky posts additionally sync with the connected account's own _server-side_ favourites/
likes (`serverStars`): starring/unstarring one from Rellm's UI also favourites/unfavourites it on the
service (when an account for it -- the same instance's, for Mastodon, or the enabled Bluesky one -- is
connected), `isStarred` counts a server-side star as starred too, and when there's anything starred on
the server the panel shows a "Browser"/"Server" tab pair (see `view`). Starring is two independent
records kept in step only by this module's own toggles -- flipping accounts around can leave them
disagreeing, which is deliberately left to the user.

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
import Html exposing (Html, button, div, img, span, text)
import Html.Attributes exposing (alt, attribute, class, id, src, style, title)
import Html.Events exposing (onClick)
import Html.Keyed
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Process
import Proto.Rellm exposing (Event, GetEventsResponse, GetPostsResponse, Occasion, Post, defaultPost)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Rellm as Rellm
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.MastodonAccounts as MastodonAccounts exposing (MastodonAccount)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Federation.Bluesky as Bluesky
import Shared.Federation.Mastodon as Mastodon
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.Time as SharedTime
import Task
import UI.Classes exposing (classes, escapeCSSClass, hostnameToCSSClass, openClosedClass)
import UI.Drag
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

    -- The connected Mastodon/Bluesky accounts' own server-side stars, keyed by the same
    -- `"mastodon:" ++ instanceHost`/`"bluesky:"` host string a federated post's star key uses.
    -- See `ServerStars`.
    , serverStars : Dict String ServerStars
    , activeTab : StarredTab

    -- Server-tab account sections (by host) the user has collapsed -- see `ViewChange`.
    , collapsedServerGroups : Set String

    -- Bumped by every finished server-side star push; only the `RefetchServerStars` carrying the
    -- latest value actually refetches (a trailing-edge debounce -- see `GotServerStarPushed`).
    , serverRefetchCounter : Int

    -- Per-post collapse animation for a collapsed Server-tab section -- in place, so the posts
    -- fade/shrink away through `UI.Flip`'s own item collapse. Kept apart from `starAnimations`
    -- (enter/unstar-fade), which stays authoritative while an unstar fade is running -- see
    -- `effectiveFlipState`.
    , collapseAnimations : Dict String (UI.Flip.State Msg)

    -- Drag-to-reorder by the ▲/▼ arrows (Browser tab only) -- see `UI.Drag`.
    , drag : UI.Drag.State

    -- Set for the length of a tab switch's simultaneous leave/enter -- see `TabTransition`.
    , transition : Maybe TabTransition
    }


{-| A tab switch while it's mid-flight: the outgoing tab's own items collapse in place at the same
moment the incoming tab's items expand, rather than one after the other. `activeTab` already names
the _new_ tab, but the one keyed list keeps rendering in `order` (below) until things settle, because
any DOM move cancels a CSS transition on the moved node (see `UI.Flip.remove`). So the incoming items
(hidden, so no visible change) are first pre-placed where they'll end up -- a DOM reorder that may
well shuffle nodes (Elm's keyed diff is free to move the old ones rather than the new ones) -- and
only a frame later, once that's done, do the outgoing items start collapsing and the incoming ones
expanding (`enterStarted`), with no DOM move left to cancel anything. Only afterwards does the final
reorder run -- the usual measure/reorder/measure slide for the posts both tabs share.

`from` is the old tab (outgoing items keep its row styling while collapsing); `leaving`/`entering` are
`itemKey`s; `order` is every key that stays mounted-and-visible during the transition, in render order.
-}
type alias TabTransition =
    { from : StarredTab
    , leaving : Set String
    , entering : List String
    , order : List String
    , enterStarted : Bool
    }


type StarredTab
    = BrowserTab
    | ServerTab


{-| `account` identifies whichever connected account `status` was fetched for (see
`serverAccountKey`) -- a fetch for an account that's since been switched away from is discarded
rather than shown under the new one.
-}
type alias ServerStars =
    { account : String
    , status : ServerStarsStatus
    }


type ServerStarsStatus
    = ServerStarsFetching
    | ServerStarsLoaded (List Post)
    | ServerStarsFailed


type Msg
    = ToggleStar RellmServer Post
    | GotStarResult String Bool (Result Grpc.Error Post)
      -- `ToggleStar`'s counterpart for a Mastodon/Bluesky post (`host` is
      -- the `"mastodon:"`/`"bluesky:"`-tagged host string -- see
      -- `Components.Posts.isFederatedHost`) -- there's no
      -- `StarPost`/`UnstarPost` RPC to call for either service, so this is a
      -- purely local bookmark: same `starredPostIds`/`starOrder`/`posts`
      -- mutation `ToggleStar` does, just with no `rpcCmd` (and so no
      -- `GotStarResult` reply either -- the optimistic update here is never
      -- reverted).
    | ToggleFederatedStar String Post
      -- `GotStarredPost`'s counterpart for re-fetching a starred Mastodon/
      -- Bluesky post (see `fetchFederatedGroup`) -- carries a plain `Post`
      -- (dropping the `Bool` "sensitive" flag `Mastodon.fetchStatus`/
      -- `Bluesky.fetchPost` also return, which only matters for gating
      -- media on the dedicated post-detail pages, not this panel's card)
      -- rather than `GotStarredPost`'s Jonline-specific `GetPostsResponse`.
    | GotStarredFederatedPost String (Result Http.Error Post)
      -- A connected account's server-side star list arriving -- `host`, then `serverAccountKey`
      -- of the account it was fetched for. The `Maybe AccountsPanel.Msg` is a rotated-token
      -- persist, forwarded the same way `GotStarredPost`'s is.
    | GotServerStars String String (Result Http.Error ( Maybe AccountsPanel.Msg, List Post ))
      -- A favourite/like push finishing -- only ever carries a token-persist/reauth-flag to forward;
      -- a failed push is otherwise dropped (the local star stands regardless).
    | GotServerStarPushed (Maybe AccountsPanel.Msg)
      -- The trailing edge of `GotServerStarPushed`'s debounce -- carries the counter value it was
      -- scheduled under.
    | RefetchServerStars Int
    | SetStarredTab StarredTab
    | ToggleServerGroupCollapsed String
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
    | TabLeaveFinished ViewChange
      -- One frame after a tab switch starts (the incoming items having been moved into place,
      -- collapsed): the outgoing items collapse and the incoming ones expand, together -- see
      -- `TabTransition`.
    | EnterTabItems ViewChange
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
    | DragMsg UI.Drag.Msg
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


{-| A change to which items the one unified list shows -- applied between `OrganizeStarred`-style
measure-before/measure-after FLIP steps, so every post that's still shown slides to its new place.
-}
type ViewChange
    = SwitchTab StarredTab


{-| Which half of `OrganizeStarred`'s FLIP measurement round-trip (if any)
`GotMeasuredGroupRects` is currently waiting on -- a port's incoming `Sub` is
a single, untargeted `Msg`, so there's nothing to pattern match on except
state carried in the `Model`, same reasoning as
`Components.Pages.EventsPage.MeasurementPhase` (which this mirrors).
`AwaitingOldGroupRects` carries the reorder to apply once those rects are in
hand (`AwaitingOldViewRects`, the tab switch/collapse to apply); `AwaitingNewGroupRects` carries the old rects to diff the eventual new
ones against.
-}
type GroupMeasurementPhase
    = NotMeasuringGroup
    | AwaitingOldGroupRects (List String)
      -- A tab switch: the old positions of every post staying visible are in
      -- flight; the change is applied once they arrive (see `beginViewChange`).
    | AwaitingOldViewRects ViewChange
      -- A tab switch whose outgoing items are fading/collapsing in place (they can't also be
      -- reordered in the same patch -- see `UI.Flip.remove`); once that's had time to run,
      -- `TabLeaveFinished` carries on with the measure round trip.
    | AwaitingTabLeave ViewChange
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
                |> List.map canonicalKey
                |> List.foldl
                    (\key acc ->
                        if List.member key acc then
                            acc

                        else
                            acc ++ [ key ]
                    )
                    []
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
    , serverStars = Dict.empty
    , activeTab = BrowserTab
    , collapsedServerGroups = Set.empty
    , serverRefetchCounter = 0
    , collapseAnimations = Dict.empty
    , drag = UI.Drag.init
    , transition = Nothing
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
        -- the panel being open outright -- `ToggleStar`/`ToggleFederatedStar`
        -- only skip starting a fade in the first place while the panel's
        -- closed (see `finishUnstar`'s own doc); an unstar fade already in
        -- flight when the panel gets closed mid-animation (`CloseStarredPanel`/
        -- `ToggleStarredPanel` don't cancel one) still needs this to keep
        -- ticking so its own `FinishUnstar` ever actually fires.
        , if model.showStarredPanel then
            Sub.map DragMsg (UI.Drag.subscriptions model.drag)

          else
            Sub.none
        , UI.Flip.subscription AnimateItemFlip (Dict.values model.starAnimations ++ Dict.values model.collapseAnimations)
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

            else if model.showStarredPanel then
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

            else
                -- Panel's closed -- see `finishUnstar`'s own doc on why
                -- there's nothing to fade out for something nobody can see.
                let
                    ( finishedModel, finishCmd ) =
                        finishUnstar key { model | posts = newPosts }
                in
                ( finishedModel, Cmd.batch [ finishCmd, rpcCmd ], Nothing )

        ToggleFederatedStar host post ->
            let
                key : String
                key =
                    starKey host post

                -- Counts a server-side star too -- see `isStarred`.
                starring : Bool
                starring =
                    not (isStarred host post model)

                account : Maybe ServerAccount
                account =
                    serverAccountFor accountsPanelModel host

                newPosts : Dict String PostFetchStatus
                newPosts =
                    Dict.insert key (PostFetchLoaded host post) model.posts

                pushCmd : Cmd Msg
                pushCmd =
                    case account of
                        Just acct ->
                            pushServerStar host acct starring post

                        Nothing ->
                            Cmd.none
            in
            if starring then
                let
                    -- Where the account's own server-side stars are filed (a Mastodon post from some
                    -- other instance still goes under the account's).
                    serverHost : String
                    serverHost =
                        account |> Maybe.map serverHostOf |> Maybe.withDefault host

                    newStarredPostIds : Set String
                    newStarredPostIds =
                        Set.insert key model.starredPostIds

                    newStarOrder : List String
                    newStarOrder =
                        key :: model.starOrder
                in
                -- Lands at the top of both tabs: `starOrder`'s head, and the head of its account's
                -- server-side list.
                ( { model
                    | starredPostIds = newStarredPostIds
                    , starOrder = newStarOrder
                    , posts = newPosts
                    , serverStars = updateServerStars serverHost True post model.serverStars
                  }
                , Cmd.batch [ persistCmd newStarOrder, pushCmd ]
                , Nothing
                )

            else
                let
                    inBrowser : Bool
                    inBrowser =
                        Set.member key model.starredPostIds

                    inServer : Bool
                    inServer =
                        serverStarContains host post model
                in
                if not inBrowser && not inServer then
                    ( model, pushCmd, Nothing )

                else
                    let
                        -- On unstarring, a server-side entry for this same post under a *different* key
                        -- (the same status on the account's own instance) goes right away; the same-key one
                        -- is removed with the fade, by `finishUnstar`.
                        withoutOtherKeyCopies : Dict String ServerStars -> Dict String ServerStars
                        withoutOtherKeyCopies =
                            Dict.map
                                (\listHost stars ->
                                    case stars.status of
                                        ServerStarsLoaded posts ->
                                            { stars
                                                | status =
                                                    ServerStarsLoaded
                                                        (List.filter
                                                            (\p -> starKey listHost p == key || not (sameStarredPost (canonicalHost host) post listHost p))
                                                            posts
                                                        )
                                            }

                                        _ ->
                                            stars
                                )
                    in
                    if model.showStarredPanel then
                        -- Fades out (in whichever tab it's showing in); `FinishUnstar` does the real
                        -- removal from both the browser and server-side lists -- see `finishUnstar`.
                        let
                            currentState : UI.Flip.State Msg
                            currentState =
                                Dict.get key model.starAnimations |> Maybe.withDefault UI.Flip.restingState
                        in
                        ( { model
                            | posts = newPosts
                            , serverStars = withoutOtherKeyCopies model.serverStars
                            , starAnimations = Dict.insert key (UI.Flip.remove (FinishUnstar key) currentState) model.starAnimations
                          }
                        , pushCmd
                        , Nothing
                        )

                    else
                        let
                            ( finishedModel, finishCmd ) =
                                finishUnstar key { model | posts = newPosts, serverStars = withoutOtherKeyCopies model.serverStars }
                        in
                        ( finishedModel, Cmd.batch [ finishCmd, pushCmd ], Nothing )

        GotServerStars host account (Ok ( maybeAccountsPanelMsg, posts )) ->
            ( if Dict.get host model.serverStars |> Maybe.map .account |> (==) (Just account) then
                { model | serverStars = Dict.insert host { account = account, status = ServerStarsLoaded posts } model.serverStars }

              else
                model
            , Cmd.none
            , maybeAccountsPanelMsg
            )

        GotServerStars host account (Err _) ->
            ( if Dict.get host model.serverStars |> Maybe.map .account |> (==) (Just account) then
                { model | serverStars = Dict.insert host { account = account, status = ServerStarsFailed } model.serverStars }

              else
                model
            , Cmd.none
            , Nothing
            )

        GotServerStarPushed maybeAccountsPanelMsg ->
            -- Trailing-edge debounce: a quick run of stars/unstars only refetches once, after the
            -- last one's push finishes and 800ms pass with no further one.
            let
                counter : Int
                counter =
                    model.serverRefetchCounter + 1
            in
            ( { model | serverRefetchCounter = counter }
            , Process.sleep 800 |> Task.perform (\_ -> RefetchServerStars counter)
            , maybeAccountsPanelMsg
            )

        RefetchServerStars counter ->
            if counter /= model.serverRefetchCounter then
                ( model, Cmd.none, Nothing )

            else
                -- Refetches in place (no clearing -- the lists keep showing meanwhile) so the
                -- panel reflects what the services actually have.
                ( model
                , Cmd.batch (List.map (\( host, account ) -> fetchServerStars host account) (serverStarSources accountsPanelModel))
                , Nothing
                )

        ToggleServerGroupCollapsed host ->
            let
                collapsing : Bool
                collapsing =
                    not (Set.member host model.collapsedServerGroups)

                groupKeys : List String
                groupKeys =
                    serverGroups model
                        |> List.filter (\( groupHost, _ ) -> groupHost == host)
                        |> List.concatMap (\( _, posts ) -> List.map (starKey host) posts)

                -- Animated in place: the posts keep their spot in the list (collapsed ones aren't
                -- reordered), which is what lets `UI.Flip`'s CSS collapse transition run -- see
                -- `UI.Flip.remove`'s doc.
                step : String -> Dict String (UI.Flip.State Msg) -> Dict String (UI.Flip.State Msg)
                step key animations =
                    let
                        current : UI.Flip.State Msg
                        current =
                            Dict.get key animations |> Maybe.withDefault UI.Flip.restingState
                    in
                    Dict.insert key
                        (if collapsing then
                            UI.Flip.remove NoOp current

                         else
                            UI.Flip.reappear current
                        )
                        animations
            in
            ( { model
                | collapsedServerGroups =
                    if collapsing then
                        Set.insert host model.collapsedServerGroups

                    else
                        Set.remove host model.collapsedServerGroups
                , collapseAnimations = List.foldl step model.collapseAnimations groupKeys
              }
            , Cmd.none
            , Nothing
            )

        SetStarredTab tab ->
            if tab == model.activeTab || model.groupMeasurementPhase /= NotMeasuringGroup then
                ( model, Cmd.none, Nothing )

            else
                beginViewChange (SwitchTab tab) model

        EnterTabItems change ->
            case ( model.groupMeasurementPhase == AwaitingTabLeave change, model.transition ) of
                ( True, Just transition ) ->
                    let
                        collapsed : String -> Bool
                        collapsed key =
                            Dict.get key model.collapseAnimations |> Maybe.map .removing |> Maybe.withDefault False
                    in
                    ( { model
                        | transition = Just { transition | enterStarted = True }
                        , starAnimations =
                            transition.entering
                                |> List.filter (not << collapsed)
                                |> List.foldl (\key acc -> Dict.insert key UI.Flip.enter acc) (collapseKeys (Set.toList transition.leaving) model.starAnimations)
                      }
                    , Cmd.none
                    , Nothing
                    )

                _ ->
                    ( model, Cmd.none, Nothing )

        TabLeaveFinished change ->
            if model.groupMeasurementPhase == AwaitingTabLeave change then
                ( { model | groupMeasurementPhase = AwaitingOldViewRects change }
                , UI.Flip.measureElementsCmd measureOwner starEntryDomId (sharedPostKeys change model)
                , Nothing
                )

            else
                ( model, Cmd.none, Nothing )

        GotStarredFederatedPost key (Ok post) ->
            let
                newStatus : PostFetchStatus
                newStatus =
                    case parseStarKey key of
                        Just ( _, host ) ->
                            PostFetchLoaded host post

                        Nothing ->
                            PostFetchFailed
            in
            ( { model | posts = Dict.insert key newStatus model.posts }, Cmd.none, Nothing )

        GotStarredFederatedPost key (Err _) ->
            ( { model | posts = Dict.insert key PostFetchFailed model.posts }, Cmd.none, Nothing )

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
                ( finishedModel, cmd ) =
                    finishUnstar key model
            in
            ( finishedModel, cmd, Nothing )

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

                ( newCollapseAnimations, collapseCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.collapseAnimations
            in
            ( { model | starAnimations = newStarAnimations, collapseAnimations = newCollapseAnimations }
            , Cmd.batch (cmds ++ collapseCmds)
            , Nothing
            )

        ToggleStarredPanel ->
            let
                toggledModel : Model
                toggledModel =
                    { model | showStarredPanel = not model.showStarredPanel }
            in
            if toggledModel.showStarredPanel then
                let
                    -- Opening the panel is the one place a previously-failed server-side fetch
                    -- gets another try (see `kickOffServerFetches`).
                    retryableModel : Model
                    retryableModel =
                        { toggledModel | serverStars = Dict.filter (\_ stars -> stars.status /= ServerStarsFailed) toggledModel.serverStars }

                    ( fetchedModel, cmd ) =
                        kickOffFetches accountsPanelModel retryableModel
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
            , UI.Flip.measureElementsCmd measureOwner starEntryDomId model.starOrder
            , Nothing
            )

        GotMeasuredGroupRects value ->
            -- `Ports.elementsMeasured` is shared with other components that measure things; one
            -- of theirs landing between this FLIP's two measurements would otherwise be mistaken
            -- for the "after" half (animating nothing), so only results tagged `measureOwner` count.
            case UI.Flip.measuredResults measureOwner value of
                Nothing ->
                    ( model, Cmd.none, Nothing )

                Just results ->
                    case Decode.decodeValue UI.Flip.rectsDecoder results of
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

                                AwaitingTabLeave _ ->
                                    -- Still fading the outgoing items; not our measurement.
                                    ( model, Cmd.none, Nothing )

                                AwaitingOldViewRects change ->
                                    let
                                        changedModel : Model
                                        changedModel =
                                            applyViewChange change { model | transition = Nothing }
                                                |> enterNewlyShownItems model
                                    in
                                    ( { changedModel | groupMeasurementPhase = AwaitingNewGroupRects rects }
                                    , Task.attempt (\_ -> ReadyToMeasureNewGroupPositions) Dom.getViewport
                                    , Nothing
                                    )

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
                    ( model, UI.Flip.measureElementsCmd measureOwner starEntryDomId (Dict.keys oldRects), Nothing )

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

        DragMsg dragMsg ->
            let
                ( newDrag, dragCmd, outputs ) =
                    UI.Drag.update (dragConfig model) dragMsg model.drag

                applyOutput : UI.Drag.Output -> ( Model, List (Cmd Msg) ) -> ( Model, List (Cmd Msg) )
                applyOutput output ( current, cmds ) =
                    case output of
                        UI.Drag.Reordered newOrder ->
                            ( { current | starOrder = newOrder }, persistCmd newOrder :: cmds )

                        UI.Drag.Slide slides ->
                            ( { current | moveAnimations = UI.Drag.applySlides MoveSettled slides current.moveAnimations }, cmds )

                ( newModel, persistCmds ) =
                    List.foldl applyOutput ( { model | drag = newDrag }, [] ) outputs
            in
            ( newModel, Cmd.batch (Cmd.map DragMsg dragCmd :: persistCmds), Nothing )

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
same reasoning as `AccountsPanel.syncItemAnimations` -- except while the
panel's closed, when a newly-starred post seeds straight to `restingState`
instead (same as `init` does for every persisted star): there's nothing to
animate for a panel nobody can currently see (`opacity: 0`, still fully
mounted -- see `view`'s own doc), so `UI.Flip.enter`'s fade-in would just run
invisibly in the background for however long its spring takes to settle,
and -- unlike `finishUnstar`'s equivalent skip for unstarring -- there isn't
even a later message this would need to arrive before doing something
functionally different; it'd be pure waste. Opening the panel later then
shows every star made while it was closed already at rest, exactly like a
reload would.
-}
syncItemAnimations : Model -> Model
syncItemAnimations model =
    let
        keys : List String
        keys =
            allItemKeys model
    in
    { model
        | starAnimations =
            if model.showStarredPanel then
                UI.Flip.syncEnter identity keys model.starAnimations

            else
                List.foldl
                    (\key acc ->
                        if Dict.member key acc then
                            acc

                        else
                            Dict.insert key UI.Flip.restingState acc
                    )
                    model.starAnimations
                    keys
    }


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

        ( serverModel, serverCmd ) =
            refreshServerStars accountsPanelModel eventModel
    in
    ( serverModel, Cmd.batch (serverCmd :: eventCmd :: cmds) )


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

        AwaitingOldViewRects change ->
            let
                changedModel : Model
                changedModel =
                    applyViewChange change model
            in
            ( { changedModel | groupMeasurementPhase = NotMeasuringGroup, transition = Nothing }, Cmd.none )

        AwaitingTabLeave change ->
            ( { model | groupMeasurementPhase = NotMeasuringGroup, transition = Nothing } |> applyViewChange change, Cmd.none )

        AwaitingNewGroupRects _ ->
            ( { model | groupMeasurementPhase = NotMeasuringGroup }, Cmd.none )


{-| The Browser tab's list as `UI.Drag` sees it: one free-for-all column of every starred post.
-}
dragConfig : Model -> UI.Drag.Config
dragConfig model =
    { axis = UI.Flip.Vertical
    , owner = "starred-panel"
    , domId = starEntryDomId
    , keys = model.starOrder
    , groupOf = \_ -> ""
    }


persistCmd : List String -> Cmd Msg
persistCmd starOrder =
    Ports.persistStarredPosts (Encode.list Encode.string starOrder)


{-| The actual `starredPostIds`/`starOrder` removal `FinishUnstar` applies
once a fade-out finishes -- factored out so `ToggleStar`/`ToggleFederatedStar`
can also call it directly, synchronously, when the Starred panel is closed:
`starAnimations` only exists to animate this panel's own (always-mounted,
just `opacity: 0`-and-`pointer-events: none` while closed -- see `view`'s own
doc) rendering, so unstarring while it's closed has nothing to fade out for
-- registering one anyway would just tick `AnimateItemFlip` in the background
for however long the spring takes to settle, entirely unseen, before
`FinishUnstar` eventually arrived to do exactly this. Going straight there
instead is the same end state, immediately, with no wasted animation.
-}
finishUnstar : String -> Model -> ( Model, Cmd Msg )
finishUnstar key model =
    let
        newStarredPostIds : Set String
        newStarredPostIds =
            Set.remove key model.starredPostIds

        newStarOrder : List String
        newStarOrder =
            List.filter ((/=) key) model.starOrder
    in
    ( { model
        | starredPostIds = newStarredPostIds
        , starOrder = newStarOrder
        , starAnimations = Dict.remove key model.starAnimations
        , collapseAnimations = Dict.remove key model.collapseAnimations

        -- A federated post unstarred from either tab leaves both (see `ToggleFederatedStar`).
        , serverStars =
            Dict.map
                (\host stars ->
                    case stars.status of
                        ServerStarsLoaded posts ->
                            { stars | status = ServerStarsLoaded (List.filter (\p -> starKey host p /= key) posts) }

                        _ ->
                            stars
                )
                model.serverStars
      }
    , persistCmd newStarOrder
    )


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
    if Posts.isFederatedHost host then
        fetchFederatedGroup accountsPanelModel ( host, postIds ) ( posts, cmds )

    else
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


{-| `fetchGroup`'s branch for a Mastodon/Bluesky `host` -- there's no
"connected server" to check (`ServerDependentView.availableServer` is
Jonline-only), so this just fetches directly: `Mastodon.fetchStatus` for a
`"mastodon:"` host (no auth needed), or `Bluesky.fetchPost` using whichever
connected Bluesky account comes first for a `"bluesky:"` host (same
"any connected token works" reasoning as `Components.Bluesky.BlueskyPostPage.init`
-- reading a public post doesn't need to be that account's own). With no
Bluesky account connected at all, AT Protocol has no anonymous read, so those
posts are marked `ServerUnavailable` same as an unreachable Jonline server.
-}
fetchFederatedGroup :
    AccountsPanel.Model
    -> ( String, List String )
    -> ( Dict String PostFetchStatus, List (Cmd Msg) )
    -> ( Dict String PostFetchStatus, List (Cmd Msg) )
fetchFederatedGroup accountsPanelModel ( host, postIds ) ( posts, cmds ) =
    if String.startsWith "mastodon:" host then
        let
            instanceHost : String
            instanceHost =
                String.dropLeft 9 host

            fetchCmds : List (Cmd Msg)
            fetchCmds =
                List.map
                    (\postId ->
                        Mastodon.fetchStatus instanceHost postId
                            |> Task.map Tuple.first
                            |> Task.attempt (GotStarredFederatedPost (rawKey postId host))
                    )
                    postIds
        in
        ( List.foldl (\postId -> Dict.insert (rawKey postId host) FetchingPost) posts postIds
        , cmds ++ fetchCmds
        )

    else
        case accountsPanelModel.blueskyAccounts of
            account :: _ ->
                let
                    fetchCmds : List (Cmd Msg)
                    fetchCmds =
                        List.map
                            (\postId ->
                                BlueskyAccounts.performWithBlueskyAccount account (\accessToken -> Bluesky.fetchPost accessToken postId)
                                    |> Task.map (Tuple.second >> Tuple.first)
                                    |> Task.attempt (GotStarredFederatedPost (rawKey postId host))
                            )
                            postIds
                in
                ( List.foldl (\postId -> Dict.insert (rawKey postId host) FetchingPost) posts postIds
                , cmds ++ fetchCmds
                )

            -- No connected account -- public posts still read fine anonymously (an empty token,
            -- see `Bluesky.fetchPost`).
            [] ->
                ( List.foldl (\postId -> Dict.insert (rawKey postId host) FetchingPost) posts postIds
                , cmds
                    ++ List.map
                        (\postId ->
                            Bluesky.fetchPost "" postId
                                |> Task.map Tuple.first
                                |> Task.attempt (GotStarredFederatedPost (rawKey postId host))
                        )
                        postIds
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



-- SERVER-SIDE STARS (Mastodon favourites / Bluesky likes)


type ServerAccount
    = MastodonServerAccount MastodonAccount
    | BlueskyServerAccount BlueskyAccount


{-| The connected account (if any) `host`'s server-side stars live under: a Mastodon `host` prefers an
account on that very instance (a status id is only meaningful to the instance it came from) but
otherwise falls back to the first usable one -- `pushServerStar` then resolves the post onto that
account's own instance; a Bluesky one needs the enabled account. Accounts flagged `needsReauth` don't
count.
-}
serverAccountFor : AccountsPanel.Model -> String -> Maybe ServerAccount
serverAccountFor accountsPanelModel host =
    if String.startsWith "mastodon:" host then
        let
            usable : List MastodonAccount
            usable =
                List.filter (not << .needsReauth) accountsPanelModel.mastodonAccounts
        in
        usable
            |> List.filter (\account -> account.instanceHost == String.dropLeft 9 host)
            |> List.head
            |> orElseMaybe (List.head usable)
            |> Maybe.map MastodonServerAccount

    else if String.startsWith "bluesky:" host then
        accountsPanelModel.blueskyAccounts
            |> List.filter (\account -> account.enabled && not account.needsReauth)
            |> List.head
            |> Maybe.map BlueskyServerAccount

    else
        Nothing


orElseMaybe : Maybe a -> Maybe a -> Maybe a
orElseMaybe fallback maybe =
    case maybe of
        Just _ ->
            maybe

        Nothing ->
            fallback


{-| The host a `ServerAccount`'s own server-side stars are filed under in `serverStars`.
-}
serverHostOf : ServerAccount -> String
serverHostOf account =
    case account of
        MastodonServerAccount a ->
            "mastodon:" ++ a.instanceHost

        BlueskyServerAccount _ ->
            "bluesky:"


serverAccountKey : ServerAccount -> String
serverAccountKey account =
    case account of
        MastodonServerAccount a ->
            a.instanceHost ++ "/" ++ a.username

        BlueskyServerAccount a ->
            a.handle


{-| Every host with a connected account to fetch server-side stars for, and that account.
-}
serverStarSources : AccountsPanel.Model -> List ( String, ServerAccount )
serverStarSources accountsPanelModel =
    let
        hosts : List String
        hosts =
            (accountsPanelModel.mastodonAccounts |> List.map (\a -> "mastodon:" ++ a.instanceHost))
                ++ [ "bluesky:" ]
                |> List.foldl
                    (\host acc ->
                        if List.member host acc then
                            acc

                        else
                            acc ++ [ host ]
                    )
                    []
    in
    hosts
        |> List.filterMap (\host -> serverAccountFor accountsPanelModel host |> Maybe.map (Tuple.pair host))


{-| Drops cached server-side star lists for hosts that no longer have a usable connected account (or
whose account changed), and fetches whichever sources are missing one -- idempotent, so
`kickOffFetches`/`Shared.update` can call it freely. A `ServerStarsFailed` entry stays put (it's
only cleared by opening the panel, see `ToggleStarredPanel`) so a persistently failing fetch isn't
retried on every account message.
-}
refreshServerStars : AccountsPanel.Model -> Model -> ( Model, Cmd Msg )
refreshServerStars accountsPanelModel model =
    let
        sources : List ( String, ServerAccount )
        sources =
            serverStarSources accountsPanelModel

        stillValid : String -> ServerStars -> Bool
        stillValid host stars =
            sources
                |> List.any (\( sourceHost, account ) -> sourceHost == host && serverAccountKey account == stars.account)

        kept : Dict String ServerStars
        kept =
            Dict.filter stillValid model.serverStars

        missing : List ( String, ServerAccount )
        missing =
            List.filter (\( host, _ ) -> not (Dict.member host kept)) sources
    in
    ( { model
        | serverStars =
            List.foldl
                (\( host, account ) -> Dict.insert host { account = serverAccountKey account, status = ServerStarsFetching })
                kept
                missing
      }
    , Cmd.batch (List.map (\( host, account ) -> fetchServerStars host account) missing)
    )


fetchServerStars : String -> ServerAccount -> Cmd Msg
fetchServerStars host account =
    case account of
        MastodonServerAccount a ->
            MastodonAccounts.performWithMastodonAccount a (\token -> Mastodon.fetchFavourites a.instanceHost token)
                |> Task.map (\( refreshed, posts ) -> ( rotatedMastodon a refreshed, posts ))
                |> Task.attempt (GotServerStars host (serverAccountKey account))

        BlueskyServerAccount a ->
            BlueskyAccounts.performWithBlueskyAccount a (\token -> Bluesky.fetchLikes token a.handle)
                |> Task.map (\( refreshed, posts ) -> ( rotatedBluesky a refreshed, posts ))
                |> Task.attempt (GotServerStars host (serverAccountKey account))


{-| Favourites (`starring`) or unfavourites `post` on the service. A failure is dropped, except that
a 401/403 from Mastodon (a token connected before `write:favourites` was requested -- see
`public/index.html`) flags the account `needsReauth` so it shows its "Reconnect" affordance.
-}
pushServerStar : String -> ServerAccount -> Bool -> Post -> Cmd Msg
pushServerStar host account starring post =
    case account of
        MastodonServerAccount a ->
            let
                -- The post's id on the account's own instance: as-is if that's where it came from,
                -- else looked up by its public URL (see `Mastodon.resolveStatusId`).
                localId : String -> Task.Task Http.Error String
                localId token =
                    if host == "mastodon:" ++ a.instanceHost then
                        Task.succeed post.id

                    else
                        case post.link of
                            Just url ->
                                Mastodon.resolveStatusId a.instanceHost token url

                            Nothing ->
                                Task.fail (Http.BadStatus 404)
            in
            MastodonAccounts.performWithMastodonAccount a
                (\token ->
                    localId token
                        |> Task.andThen (\id -> Mastodon.setFavourite starring a.instanceHost token id)
                )
                |> Task.map (\( refreshed, () ) -> rotatedMastodon a refreshed)
                |> Task.onError
                    (\err ->
                        if MastodonAccounts.isReauthError err then
                            Task.succeed (Just (AccountsPanel.MarkMastodonAccountNeedsReauth a.instanceHost a.accessToken))

                        else
                            Task.succeed Nothing
                    )
                |> Task.perform GotServerStarPushed

        BlueskyServerAccount a ->
            BlueskyAccounts.performWithBlueskyAccount a (\token -> Bluesky.setLike starring a.handle token post.id)
                |> Task.map (\( refreshed, () ) -> rotatedBluesky a refreshed)
                |> Task.onError (\_ -> Task.succeed Nothing)
                |> Task.perform GotServerStarPushed


rotatedMastodon : MastodonAccount -> MastodonAccount -> Maybe AccountsPanel.Msg
rotatedMastodon before after =
    if after.accessToken == before.accessToken then
        Nothing

    else
        Just (AccountsPanel.MastodonAccountRefreshed after)


rotatedBluesky : BlueskyAccount -> BlueskyAccount -> Maybe AccountsPanel.Msg
rotatedBluesky before after =
    if after.accessToken == before.accessToken then
        Nothing

    else
        Just (AccountsPanel.BlueskyAccountRefreshed after)


{-| Whether any connected account's server-side star list has `post` -- by its id on `host`, or by its
public `link` (a Mastodon status has a different id on every instance, so one viewed through its
origin instance only matches the copy in a favourites list from the account's own by its URL).
-}
serverStarContains : String -> Post -> Model -> Bool
serverStarContains host post model =
    serverStarredPosts model
        |> List.any (\( listHost, p ) -> sameStarredPost (canonicalHost host) post listHost p)


sameStarredPost : String -> Post -> String -> Post -> Bool
sameStarredPost host post otherHost other =
    (host == otherHost && post.id == other.id) || (post.link /= Nothing && post.link == other.link)


{-| Keeps a loaded server-side list in step with a just-made toggle (no-op for a host with no loaded
list).
-}
updateServerStars : String -> Bool -> Post -> Dict String ServerStars -> Dict String ServerStars
updateServerStars host starring post serverStars =
    Dict.update (canonicalHost host)
        (Maybe.map
            (\stars ->
                case stars.status of
                    ServerStarsLoaded posts ->
                        let
                            others : List Post
                            others =
                                List.filter (\p -> not (sameStarredPost (canonicalHost host) post (canonicalHost host) p)) posts
                        in
                        { stars
                            | status =
                                ServerStarsLoaded
                                    (if starring then
                                        post :: others

                                     else
                                        others
                                    )
                        }

                    _ ->
                        stars
            )
        )
        serverStars


{-| Every loaded server-side star, with its host.
-}
serverStarredPosts : Model -> List ( String, Post )
serverStarredPosts model =
    model.serverStars
        |> Dict.toList
        |> List.concatMap
            (\( host, stars ) ->
                case stars.status of
                    ServerStarsLoaded posts ->
                        List.map (Tuple.pair host) posts

                    _ ->
                        []
            )


{-| Whether there's anything to show in the panel at all (browser- or server-side).
-}
hasAnyStars : Model -> Bool
hasAnyStars model =
    not (Set.isEmpty model.starredPostIds) || not (List.isEmpty (serverStarredPosts model))


{-| Browser stars plus server-side stars not also starred here -- the nav badge's count.
-}
totalStarCount : Model -> Int
totalStarCount model =
    Set.size model.starredPostIds
        + (serverStarredPosts model
            |> List.filter (\( host, post ) -> not (Set.member (starKey host post) model.starredPostIds))
            |> List.length
          )



-- THE UNIFIED LIST


{-| One row of the panel's single FLIP list -- both tabs render from it (see `view`): a post, or
(Server tab only) an account's heading chip.
-}
type StarredItem
    = PostRowItem String
    | ChipRowItem String


itemKey : StarredItem -> String
itemKey item =
    case item of
        PostRowItem key ->
            key

        ChipRowItem host ->
            "chip:" ++ host


postItemKey : StarredItem -> Maybe String
postItemKey item =
    case item of
        PostRowItem key ->
            Just key

        ChipRowItem _ ->
            Nothing


{-| Every connected account's loaded, non-empty server-side stars, in host order.
-}
serverGroups : Model -> List ( String, List Post )
serverGroups model =
    model.serverStars
        |> Dict.toList
        |> List.filterMap
            (\( host, stars ) ->
                case stars.status of
                    ServerStarsLoaded ((_ :: _) as posts) ->
                        Just ( host, posts )

                    _ ->
                        Nothing
            )


{-| Which tab is actually showing: both kinds of star -> the user's pick; only server-side ones ->
those; otherwise the browser's.
-}
effectiveTab : Model -> StarredTab
effectiveTab model =
    let
        hasBrowser : Bool
        hasBrowser =
            not (Set.isEmpty model.starredPostIds)

        hasServer : Bool
        hasServer =
            not (List.isEmpty (serverGroups model))
    in
    if hasBrowser && hasServer then
        model.activeTab

    else if hasServer then
        ServerTab

    else
        BrowserTab


{-| What `tab` shows, in order: the browser tab is just `starOrder`; the server tab is each account's
chip followed by its posts (a collapsed section's stay in place, rendered collapsed -- see
`effectiveFlipState`).
-}
tabItems : StarredTab -> Model -> List StarredItem
tabItems tab model =
    case tab of
        BrowserTab ->
            List.map PostRowItem model.starOrder

        ServerTab ->
            serverGroups model
                |> List.concatMap
                    (\( host, posts ) ->
                        ChipRowItem host :: List.map (\post -> PostRowItem (starKey host post)) posts
                    )


{-| Every item in either tab, collapsed sections' posts included -- what has to stay mounted so it
can come back.
-}
allItems : Model -> List StarredItem
allItems model =
    let
        serverPostItems : List StarredItem
        serverPostItems =
            serverGroups model
                |> List.concatMap (\( host, posts ) -> List.map (\post -> PostRowItem (starKey host post)) posts)

        chips : List StarredItem
        chips =
            serverGroups model |> List.map (\( host, _ ) -> ChipRowItem host)
    in
    List.map PostRowItem model.starOrder ++ serverPostItems ++ chips


allItemKeys : Model -> List String
allItemKeys model =
    allItems model
        |> List.map itemKey
        |> List.foldl
            (\k acc ->
                if List.member k acc then
                    acc

                else
                    k :: acc
            )
            []
        |> List.reverse


{-| Render order for the one keyed list: whatever the showing tab shows, in its order, then
everything else (rendered instantly hidden -- see `view`). Each `Bool` is "shown".
-}
orderedItems : Model -> List ( StarredItem, Bool )
orderedItems model =
    let
        shownWithFlags : List ( StarredItem, Bool )
        shownWithFlags =
            case model.transition of
                Just transition ->
                    let
                        byKey : Dict String StarredItem
                        byKey =
                            allItems model |> List.map (\item -> ( itemKey item, item )) |> Dict.fromList
                    in
                    -- Incoming items stay hidden until `EnterTabItems` -- see `TabTransition`.
                    transition.order
                        |> List.filterMap
                            (\key ->
                                Dict.get key byKey
                                    |> Maybe.map (\item -> ( item, transition.enterStarted || not (List.member key transition.entering) ))
                            )

                Nothing ->
                    tabItems (effectiveTab model) model |> List.map (\item -> ( item, True ))

        shownKeys : Set String
        shownKeys =
            shownWithFlags |> List.map (Tuple.first >> itemKey) |> Set.fromList

        rest : List StarredItem
        rest =
            allItems model
                |> List.filter (\item -> not (Set.member (itemKey item) shownKeys))
                |> List.foldl
                    (\item ( seen, acc ) ->
                        if Set.member (itemKey item) seen then
                            ( seen, acc )

                        else
                            ( Set.insert (itemKey item) seen, item :: acc )
                    )
                    ( Set.empty, [] )
                |> Tuple.second
                |> List.reverse
    in
    shownWithFlags ++ List.map (\item -> ( item, False )) rest


applyViewChange : ViewChange -> Model -> Model
applyViewChange change model =
    case change of
        SwitchTab tab ->
            { model | activeTab = tab }


{-| Starts a tab switch as a FLIP: measure where every post that'll still be
shown afterwards is now; `GotMeasuredGroupRects` then applies `change`, waits a frame, and measures
again so each of those posts slides from its old spot to its new one -- the same round trip
`OrganizeStarred` does. Posts that stop being shown first collapse in place (`AwaitingTabLeave`), since
animating their collapse while also moving them in the DOM gets cancelled by the browser -- see
`UI.Flip.remove`'s doc.
-}
beginViewChange : ViewChange -> Model -> ( Model, Cmd Msg, Maybe AccountsPanel.Msg )
beginViewChange change model =
    let
        leavingKeys : List String
        leavingKeys =
            tabChangeKeys model (applyViewChange change model)
    in
    if List.isEmpty leavingKeys then
        ( { model | groupMeasurementPhase = AwaitingOldViewRects change }
        , UI.Flip.measureElementsCmd measureOwner starEntryDomId (sharedPostKeys change model)
        , Nothing
        )

    else
        -- The outgoing items collapse where they are while the incoming ones expand -- both at once;
        -- the reorder slide for the posts both tabs share waits until they're done. See `TabTransition`.
        let
            switched : Model
            switched =
                applyViewChange change model

            keysOf : Model -> List String
            keysOf m =
                tabItems (effectiveTab m) m |> List.map itemKey

            enteringKeys : List String
            enteringKeys =
                tabChangeKeys switched model

            -- Everything outgoing stays put, in its old order; each incoming item goes right after
            -- whichever item precedes it in the new tab (or at the very front), i.e. close to where
            -- it'll finally sit.
            order : List String
            order =
                List.foldl
                    (\key ( acc, previous ) ->
                        if List.member key acc then
                            ( acc, Just key )

                        else
                            ( insertAfter previous key acc, Just key )
                    )
                    ( keysOf model, Nothing )
                    (keysOf switched)
                    |> Tuple.first
        in
        ( { switched
            | groupMeasurementPhase = AwaitingTabLeave change
            , transition =
                Just
                    { from = effectiveTab model
                    , leaving = Set.fromList leavingKeys
                    , entering = enteringKeys
                    , order = order
                    , enterStarted = False
                    }
          }
        , Cmd.batch
            [ Task.attempt (\_ -> EnterTabItems change) Dom.getViewport
            , Process.sleep (UI.Flip.flipDurationMs + 60) |> Task.perform (\_ -> TabLeaveFinished change)
            ]
        , Nothing
        )


{-| Starts the collapse-in-place of every one of `keys` (`UI.Flip.remove`; an already-removing one is
left alone).
-}
collapseKeys : List String -> Dict String (UI.Flip.State Msg) -> Dict String (UI.Flip.State Msg)
collapseKeys keys animations =
    List.foldl
        (\key acc ->
            case Dict.get key acc of
                Just state ->
                    if state.removing then
                        acc

                    else
                        Dict.insert key (UI.Flip.remove NoOp state) acc

                Nothing ->
                    acc
        )
        animations
        keys


{-| `key` inserted right after `previous` in `keys` (at the front if `previous` is `Nothing` or absent).
-}
insertAfter : Maybe String -> String -> List String -> List String
insertAfter previous key keys =
    case previous |> Maybe.andThen (\p -> indexOf p keys) of
        Just i ->
            List.take (i + 1) keys ++ key :: List.drop (i + 1) keys

        Nothing ->
            key :: keys


indexOf : String -> List String -> Maybe Int
indexOf target keys =
    keys
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, key ) -> key == target)
        |> List.head
        |> Maybe.map Tuple.first


{-| Keys of the items `before` shows that `after` doesn't.
-}
tabChangeKeys : Model -> Model -> List String
tabChangeKeys before after =
    let
        keysOf : Model -> List String
        keysOf m =
            tabItems (effectiveTab m) m |> List.map itemKey
    in
    List.filter (\key -> not (List.member key (keysOf after))) (keysOf before)


{-| Posts shown both before and after `change` -- the ones that slide.
-}
sharedPostKeys : ViewChange -> Model -> List String
sharedPostKeys change model =
    let
        shownPostKeys : Model -> List String
        shownPostKeys m =
            tabItems (effectiveTab m) m |> List.filterMap postItemKey

        afterKeys : List String
        afterKeys =
            shownPostKeys (applyViewChange change model)
    in
    List.filter (\key -> List.member key afterKeys) (shownPostKeys model)


{-| Gives every item `after` shows that `before` didn't a fresh `UI.Flip.enter`, so it fades/expands in
once it's been moved into place (still collapsed, so the move doesn't cancel the transition). Posts in
a collapsed Server-tab section stay collapsed.
-}
enterNewlyShownItems : Model -> Model -> Model
enterNewlyShownItems before after =
    let
        collapsed : String -> Bool
        collapsed key =
            Dict.get key after.collapseAnimations |> Maybe.map .removing |> Maybe.withDefault False
    in
    { after
        | starAnimations =
            tabChangeKeys after before
                |> List.filter (not << collapsed)
                |> List.foldl (\key acc -> Dict.insert key UI.Flip.enter acc) after.starAnimations
    }


{-| The post `key` is showing as: its browser-side fetch if that's loaded, else a server-side list's
copy of it (a server-only star has no browser-side entry at all).
-}
postStatusFor : Model -> String -> Maybe PostFetchStatus
postStatusFor model key =
    case Dict.get key model.posts of
        Just (PostFetchLoaded host post) ->
            Just (PostFetchLoaded host post)

        other ->
            case
                serverGroups model
                    |> List.filterMap
                        (\( host, posts ) ->
                            posts
                                |> List.filter (\post -> starKey host post == key)
                                |> List.head
                                |> Maybe.map (PostFetchLoaded host)
                        )
                    |> List.head
            of
                Just loaded ->
                    Just loaded

                Nothing ->
                    other



-- VIEW


{-| The Starred panel's content -- always rendered (even "closed"), same
as `UI.elm`'s Accounts/Admin panels, so opening/closing can be a plain CSS
transition. Returns `Html Msg` (this module's own `Msg`, mapped into
`Shared.Msg` by `UI.elm`'s `starredPostsMenu`) rather than `Html Shared.Msg`
directly -- unlike those other panels' view code, which lives in `UI.elm`
itself and so can reach `Shared.Msg` freely, this one can't (`Shared` imports
`Shared.StarredPanel`, so the reverse import would be a cycle).
-}
view : SharedTime.Model -> String -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> Html Msg
view time basePath browserName accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel =
    let
        stateClass : String
        stateClass =
            openClosedClass model.showStarredPanel

        hasBrowser : Bool
        hasBrowser =
            not (Set.isEmpty model.starredPostIds)

        hasServer : Bool
        hasServer =
            not (List.isEmpty (serverGroups model))

        tab : StarredTab
        tab =
            effectiveTab model
    in
    div [ classes [ "starred-panel", "nav-panel", stateClass ] ]
        (div [ class "starred-panel-header" ]
            (text "Starred"
                :: (if hasBrowser && hasServer then
                        [ div [ class "starred-panel-tabs" ]
                            [ starredTabButton tab BrowserTab browserName
                            , starredTabButton tab ServerTab "Server"
                            ]
                        ]

                    else
                        []
                   )
                -- Always mounted, toggling `hidden` (which animates it to nothing) rather than
                -- appearing/disappearing -- same as `EventsPage`'s filter button.
                ++ (let
                        shown : Bool
                        shown =
                            tab == BrowserTab && starredPanelHasBothGroups model
                    in
                    [ button
                        ([ classes
                            ("starred-panel-organize-button"
                                :: "background-color-nav"
                                :: (if shown then
                                        []

                                    else
                                        [ "hidden" ]
                                   )
                            )
                         , onClick OrganizeStarred
                         , title "Organize"
                         , attribute "aria-label" "Organize"
                         ]
                            ++ (if shown then
                                    []

                                else
                                    [ attribute "tabindex" "-1", attribute "aria-hidden" "true" ]
                               )
                        )
                        [ text "⇅" ]
                    ]
                   )
            )
            :: (if not hasBrowser && not hasServer then
                    [ div [ class "starred-panel-empty" ] [ text "No starred posts yet." ] ]

                else
                    -- One FLIP list for both tabs: every item of either tab stays mounted, the
                    -- showing tab's first (in its own order) and the rest instantly hidden, so
                    -- switching tabs is just a reorder + show/hide -- see `beginViewChange`.
                    [ Html.Keyed.node "div"
                        [ classes [ "starred-panel-list", "flip-animated-column" ] ]
                        (List.map
                            (\( item, shown ) -> renderStarredItem time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel (rowTab model tab item) shown item)
                            (orderedItems model)
                        )
                    ]
               )
            ++ UI.Drag.overlay DragMsg UI.Flip.Vertical model.drag
        )


starredTabButton : StarredTab -> StarredTab -> String -> Html Msg
starredTabButton activeTab tab label =
    button
        [ classes
            ("starred-panel-tab"
                :: (if activeTab == tab then
                        [ "active" ]

                    else
                        []
                   )
            )
        , onClick (SetStarredTab tab)
        ]
        [ text label ]


{-| The tab whose row styling `item` renders with: an item still collapsing out during a `TabTransition`
keeps its old tab's look until it's gone, everything else uses the (already switched) showing tab.
-}
rowTab : Model -> StarredTab -> StarredItem -> StarredTab
rowTab model tab item =
    case model.transition of
        Just transition ->
            if Set.member (itemKey item) transition.leaving then
                transition.from

            else
                tab

        Nothing ->
            tab


{-| An instantly-collapsed, invisible `UI.Flip.State` -- how an item the showing tab doesn't show
renders (see `orderedItems`).
-}
hiddenFlipState : UI.Flip.State Msg
hiddenFlipState =
    { removing = True
    , entering = False
    , style = Animation.style [ Animation.opacity 0, Animation.scale 0.92 ]
    }


{-| The enter/leave state `key`'s row renders with: instantly hidden if the showing tab doesn't show it;
else its own (enter / unstar-fade) state while that's removing; else, on the Server tab, its section's
collapse state (if it has one); else its own.
-}
effectiveFlipState : Model -> StarredTab -> Bool -> String -> UI.Flip.State Msg
effectiveFlipState model tab shown key =
    if not shown then
        hiddenFlipState

    else
        let
            own : UI.Flip.State Msg
            own =
                Dict.get key model.starAnimations |> Maybe.withDefault UI.Flip.restingState
        in
        if own.removing || own.entering || tab /= ServerTab then
            own

        else
            Dict.get key model.collapseAnimations |> Maybe.withDefault own


{-| One row of the unified list, wrapped in `UI.Flip`'s enter/leave item (fading/scaling/collapsing
on star/unstar, or `hiddenFlipState` when the showing tab doesn't show it), same two-layer reasoning
as `UI.accountRowFlip` (that fade/collapse vs. `starredPostRow`'s own, independent slide).
-}
renderStarredItem : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> StarredTab -> Bool -> StarredItem -> ( String, Html Msg )
renderStarredItem time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel tab shown item =
    let
        key : String
        key =
            itemKey item

        flipState : UI.Flip.State Msg
        flipState =
            effectiveFlipState model tab shown key

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
    ( key
    , div (UI.Flip.itemAttributes UI.Flip.Vertical flipState isMoving)
        [ div pointerEventsAttr
            [ case item of
                PostRowItem postKey ->
                    starredPostRow time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel tab postKey

                ChipRowItem host ->
                    serverChipView accountsPanelModel model host
            ]
        ]
    )


{-| An account's heading on the Server tab: avatar + name + instance/handle, styled with
`accounts_panel.css`' own `.account-row` classes so it reads like the Accounts panel's row (see
`UI.mastodonAccountRow`/`blueskyAccountRow`), plus the collapse chevron -- one static glyph rotated
by CSS (`.expandable-section-arrow`, as in `SettingsTab`'s collapsible sections). Clicking collapses
or expands that account's posts (`ToggleServerGroupCollapsed`).
-}
serverChipView : AccountsPanel.Model -> Model -> String -> Html Msg
serverChipView accountsPanelModel model host =
    let
        mainHostClass : String
        mainHostClass =
            hostnameToCSSClass accountsPanelModel.mainFrontendHost

        collapsed : Bool
        collapsed =
            Set.member host model.collapsedServerGroups

        chip : ( Maybe String, String, String ) -> Html Msg
        chip ( avatarUrl, name, badge ) =
            div
                [ classes [ "starred-server-account-chip", "account-row", "federated-account-row", mainHostClass, "background-color-nav", "border-color-accent" ]
                , onClick (ToggleServerGroupCollapsed host)
                ]
                [ div [ class "account-row-main" ]
                    [ case avatarUrl of
                        Just url ->
                            img [ class "account-avatar", src url, alt name ] []

                        Nothing ->
                            div [ classes [ "placeholder", "account-avatar" ] ] [ text (RellmServers.initialLetter name) ]
                    , div [ class "account-row-label" ]
                        [ div [ class "account-row-username" ] [ text ("⇄ " ++ name) ]
                        , div [ classes [ "account-row-server-badge", mainHostClass, "background-color-primary" ] ] [ text badge ]
                        ]
                    , div [ class "starred-server-group-arrow" ]
                        [ span [ classes [ "expandable-section-arrow", openClosedClass (not collapsed) ] ] [ text "▼" ] ]
                    ]
                ]
    in
    case serverAccountFor accountsPanelModel host of
        Just (MastodonServerAccount a) ->
            chip ( Nothing, "@" ++ a.username, a.instanceHost )

        Just (BlueskyServerAccount a) ->
            chip ( a.avatarUrl, a.displayName |> Maybe.withDefault ("@" ++ a.handle), "@" ++ a.handle )

        Nothing ->
            chip ( Nothing, String.dropLeft 1 (String.fromList (List.drop 8 (String.toList host))), host )


{-| Wraps `starredPostView`'s content with `UI.Flip`'s slide-on-reorder
transform and the up/down reorder buttons (mirrors `UI.accountRow`'s equivalent for Accounts). On the
Server tab those buttons fade out and the same left slot shows the section's colored bar instead.
-}
starredPostRow : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> StarredTab -> String -> Html Msg
starredPostRow time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel tab key =
    let
        moveAttrs : List (Html.Attribute Msg)
        moveAttrs =
            model.moveAnimations
                |> Dict.get key
                |> Maybe.map UI.Flip.moveAttributes
                |> Maybe.withDefault []

        count : Int
        count =
            List.length model.starOrder

        index : Int
        index =
            model.starOrder
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, k ) -> k == key)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault 0
    in
    div
        (id (starEntryDomId key)
            :: classes
                ("starred-post-row"
                    :: (if UI.Drag.isDragging model.drag key then
                            [ "reorder-dragging" ]

                        else
                            []
                       )
                    ++ (if tab == ServerTab then
                            [ "starred-post-row-grouped", "border-color-primary-anchor-50" ]

                        else
                            []
                       )
                )
            :: moveAttrs
        )
        -- The same two children on both tabs, so a post in both is literally the same FLIP row: the
        -- left slot holds the sort arrows on the Browser tab and (via CSS, `-grouped`) the section's
        -- colored bar on the Server tab, leaving the card's own x position unchanged -- it just
        -- slides up/down.
        [ UI.Flip.reorderButtons
            { moveUp = UI.Drag.onClick model.drag (MoveStarUpClicked key)
            , moveDown = UI.Drag.onClick model.drag (MoveStarDownClicked key)
            , canMoveUp = index > 0
            , canMoveDown = index < count - 1

            -- The Server tab hides these arrows (the section's colored bar takes their slot).
            , dragAttrs =
                if tab == BrowserTab then
                    UI.Drag.handleAttrs DragMsg UI.Flip.Vertical key model.drag

                else
                    []
            }
        , starredPostView time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel key
        ]


starredPostView : SharedTime.Model -> String -> AccountsPanel.Model -> Maybe String -> Maybe String -> Model -> MediaRenderer.Model -> String -> Html Msg
starredPostView time basePath accountsPanelModel currentPostKey currentOccasionId model mediaRendererModel key =
    case postStatusFor model key of
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
                , Events.eventCard time basePath accountsPanelModel.mainFrontendHost host maybeServer maybeAccount onMediaClicked mediaRendererModel onMediaPlayClicked MediaRenderer.ExtraSmall starred onStarClicked current False False Nothing (\_ -> False) (\_ -> Nothing) (\_ -> NoOp) (\_ _ -> NoOp) Events.noCardSlots event displayOccasion
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
    post.id ++ "@" ++ canonicalHost frontendHost


{-| Every Bluesky post is the one host, `"bluesky:"` -- a Bluesky post reached from a feed carries
`"bluesky:" ++ handle` (see `Components.Pages.PostsPage.feedSourceKey`) while one from its own page or
the server-side likes list carries bare `"bluesky:"`, and the same post must be the same star (and the
same row in the unified list) whichever way it was reached. A Mastodon host is already just its
instance, and a Rellm server's its own.
-}
canonicalHost : String -> String
canonicalHost host =
    if String.startsWith "bluesky:" host then
        "bluesky:"

    else
        host


{-| `canonicalHost` applied to the host half of a persisted `postId@host` key -- migrates keys saved
before it existed.
-}
canonicalKey : String -> String
canonicalKey key =
    case String.split "@" key of
        [ postId, host ] ->
            postId ++ "@" ++ canonicalHost host

        _ ->
            key


{-| This panel's "self" for `UI.Flip.measure`/`measuredResults` -- see them for why a component sharing
`Ports.elementsMeasured` tags its measurements.
-}
measureOwner : String
measureOwner =
    "starred-panel"


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
    postId ++ "@" ++ canonicalHost host


{-| Starred in this browser _or_ on the connected Mastodon/Bluesky account's own server -- see
`serverStars`.
-}
isStarred : String -> Post -> Model -> Bool
isStarred frontendHost post model =
    Set.member (starKey frontendHost post) model.starredPostIds
        || serverStarContains frontendHost post model


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


{-| Whether any starred post or occasion is still waiting on a fetch that `PollStarredPosts` would
(re)try -- what `Shared.subscriptions` gates its poll timer on, so an open panel with everything
loaded (or permanently failed) isn't woken (and re-rendered) every 1.5s for nothing.
-}
hasPendingFetches : Model -> Bool
hasPendingFetches model =
    let
        postPending : Bool
        postPending =
            model.starredPostIds
                |> Set.toList
                |> List.filterMap parseStarKey
                |> List.any (\( postId, host ) -> needsFetch model.posts (rawKey postId host))

        eventPending : Bool
        eventPending =
            model.posts
                |> Dict.toList
                |> List.any
                    (\( key, status ) ->
                        case status of
                            PostFetchLoaded _ post ->
                                post.context == OCCASION && needsEventFetch model.events key

                            _ ->
                                False
                    )
    in
    postPending || eventPending


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
falls back to `ToggleFederatedStar` if `host` is a Mastodon/Bluesky host
instead (see `Components.Posts.isFederatedHost`), and only `Nothing` if
it's neither (nothing to star it against). Shared by every page that
renders a `postCard`/`postDetail` (`Pages.Home_`, `Pages.Post.PostId_`,
`Components.Mastodon.MastodonPostPage`/`BlueskyPostPage`, and this module's own
`starredPostView`) so each doesn't re-derive the same "look up the server,
then wrap `ToggleStar`" logic.
-}
toggleStarMsg : AccountsPanel.Model -> String -> Post -> Maybe Msg
toggleStarMsg accountsPanelModel host post =
    case RellmServers.rellmServerForHost accountsPanelModel.servers host of
        Just server ->
            Just (ToggleStar server post)

        Nothing ->
            if Posts.isFederatedHost host then
                Just (ToggleFederatedStar host post)

            else
                Nothing


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
