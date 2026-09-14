module Components.PostReplies exposing (Model, Msg, ReplyLoadStatus, init, refresh, subscriptions, update, view)

{-| Threaded replies for a single Post (see `Pages.Post.PostId_`) -- the
`Post` proto is itself recursive/graph-shaped via its own `replies` field (see
`Proto.Rellm.Post`'s doc comment), so `Model` just wraps a `root` Post and
tracks, per-node (`statuses`, keyed by Post id), whether that node's own
`replies` have been explicitly (re-)loaded via `GetPosts`'s `reply_depth`.

`init` eagerly loads the first few levels (`initialReplyDepth`) if `root`
didn't already come with `replies` attached (e.g. from a `GetPosts` call that
itself requested some `reply_depth`) -- from then on, an individual reply
whose own `replies` are incomplete (`replyCount` more than were returned --
see the proto doc comment: fewer than `replyCount` can come back if some are
hidden by moderation/visibility) gets its own "Load replies" button
(`Components.Posts.replyCard`), which fetches just that subtree
(`LoadRepliesClicked`).

The whole tree is flattened (`flattenReplies`) into a single depth-tagged list
for display -- a caller wanting an actually-nested visual layout still gets it
via each item's own `depth` (see `Components.Posts.replyCard`'s indentation)
rather than nested HTML, which is what lets the whole thing render as one flat,
FLIP-animated list (`UI.Flip`) the same way `Pages.Home_`'s recent-posts feed
and the Starred panel already do for their own (non-nested) post lists.

-}

import Animation
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class, style)
import Html.Keyed
import Proto.Rellm exposing (GetPostsResponse, Post, unwrapPost, wrapPost)
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers exposing (RellmServer)
import Task
import UI.Flip as Flip


type alias Model =
    { root : Post
    , host : String
    , statuses : Dict String ReplyLoadStatus
    , replyAnimations : Dict String ReplyAnimation
    , collapsedReplies : Set String
    }


type Msg
    = LoadRepliesClicked String
    | GotReplies String (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetPostsResponse ))
    | Animate Animation.Msg
    | RemoveReply String
    | ToggleCollapsed String


{-| Per-node (keyed by Post id) reply-loading state -- `ReplyLoaded` suppresses
`Components.Posts.replyCard`'s "Load replies" button even if `replyCount` still disagrees with
the actual `replies` array size (moderation/visibility can hide some -- see
this module's doc comment), since that mismatch is then expected rather than
"not loaded yet".
-}
type ReplyLoadStatus
    = ReplyLoading
    | ReplyLoaded
    | ReplyLoadFailed


{-| One flattened reply's own FLIP animation state, alongside the `Post`/
`depth` it was flattened at -- mirrors `Pages.Home_`'s `PostAnimation`
(`{ host, post, flip }`), just with `depth` standing in for `host` here.
-}
type alias ReplyAnimation =
    { post : Post
    , depth : Int
    , flip : Flip.State Msg
    }


{-| Sets up a fresh `Model` for `post` (the Post currently being viewed, e.g.
`Pages.Post.PostId_`'s own `PostLoaded` post) on `host` -- if it already came
with `replies` attached, those are used as-is; otherwise, if it has any
replies at all (`replyCount`/`responseCount` > 0), kicks off a fetch
`initialReplyDepth` levels deep.
-}
init : AccountsPanel.Model -> Maybe String -> String -> Post -> ( Model, Effect Msg )
init accountsPanelModel maybeUserId host post =
    let
        model : Model
        model =
            syncAnimations
                { root = post
                , host = host
                , statuses = Dict.empty
                , replyAnimations = Dict.empty
                , collapsedReplies = Set.empty
                }
    in
    if List.isEmpty post.replies && (post.replyCount > 0 || post.responseCount > 0) then
        loadReplies accountsPanelModel maybeUserId initialReplyDepth post.id model

    else
        ( model, Effect.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Flip.subscription Animate (List.map .flip (Dict.values model.replyAnimations))


update : AccountsPanel.Model -> Maybe String -> Msg -> Model -> ( Model, Effect Msg )
update accountsPanelModel maybeUserId msg model =
    case msg of
        LoadRepliesClicked postId ->
            loadReplies accountsPanelModel maybeUserId initialReplyDepth postId model

        GotReplies postId (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    maybeAccountsPanelMsg
                        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                        |> Maybe.withDefault Effect.none

                newModel : Model
                newModel =
                    { model
                        | root = setRepliesAt postId response.posts model.root
                        , statuses = Dict.insert postId ReplyLoaded model.statuses
                    }
                        |> syncAnimations
            in
            ( newModel, accountEffect )

        GotReplies postId (Err _) ->
            ( { model | statuses = Dict.insert postId ReplyLoadFailed model.statuses }, Effect.none )

        Animate animMsg ->
            let
                step : String -> ReplyAnimation -> ( Dict String ReplyAnimation, List (Cmd Msg) ) -> ( Dict String ReplyAnimation, List (Cmd Msg) )
                step key anim ( animations, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert key { anim | flip = newFlip } animations, cmd :: accCmds )

                ( newAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.replyAnimations
            in
            ( { model | replyAnimations = newAnimations }, Effect.batch (List.map Effect.fromCmd cmds) )

        RemoveReply key ->
            ( { model | replyAnimations = Dict.remove key model.replyAnimations }, Effect.none )

        ToggleCollapsed postId ->
            let
                collapsedReplies : Set String
                collapsedReplies =
                    if Set.member postId model.collapsedReplies then
                        Set.remove postId model.collapsedReplies

                    else
                        Set.insert postId model.collapsedReplies
            in
            ( syncAnimations { model | collapsedReplies = collapsedReplies }, Effect.none )


{-| Re-fetches `root`'s own direct replies (unconditionally, `initialReplyDepth`
deep again) -- for `Pages.Post.PostId_` to call once the Markdown panel reports
a successful save: either `root`'s content just changed, or (more relevantly
here) a brand new reply to it was just posted, and needs to show up. Any
deeper subtree a user had individually expanded past `initialReplyDepth` (via
`LoadRepliesClicked`) gets collapsed back down by this, same trade-off
`PostId_`'s old flat `refetch` already made for the (until now, single-level)
replies list.
-}
refresh : AccountsPanel.Model -> Maybe String -> Post -> Model -> ( Model, Effect Msg )
refresh accountsPanelModel maybeUserId post model =
    loadReplies accountsPanelModel maybeUserId initialReplyDepth post.id { model | root = post }


loadReplies : AccountsPanel.Model -> Maybe String -> Int -> String -> Model -> ( Model, Effect Msg )
loadReplies accountsPanelModel maybeUserId depth postId model =
    ( { model | statuses = Dict.insert postId ReplyLoading model.statuses }
    , Posts.fetchReplies accountsPanelModel ( maybeUserId, model.host ) depth postId
        |> Task.attempt (GotReplies postId)
        |> Effect.fromCmd
    )


{-| Reconciles `replyAnimations` with `model.root`'s current flattened tree --
starts a fade-in for newly-seen replies, a fade-out for any that dropped out
(e.g. a reply subtree collapsed back down by `refresh`), and un-interrupts a
still-fading-out reply that reappeared -- same reconciliation
`Pages.Home_.syncAnimations` does for its own recent-posts feed. Safe/cheap to
call after every change to `model.root`, so `update`/`init` just call it
unconditionally.
-}
syncAnimations : Model -> Model
syncAnimations model =
    let
        current : Dict String ( Int, Post )
        current =
            flattenReplies model.collapsedReplies model.root
                |> List.map (\( depth, post ) -> ( post.id, ( depth, post ) ))
                |> Dict.fromList

        addOrRefresh : String -> ( Int, Post ) -> Dict String ReplyAnimation -> Dict String ReplyAnimation
        addOrRefresh key ( depth, post ) animations =
            case Dict.get key animations of
                Nothing ->
                    Dict.insert key { post = post, depth = depth, flip = Flip.enter } animations

                Just anim ->
                    if anim.flip.removing then
                        Dict.insert key { anim | post = post, depth = depth, flip = Flip.reappear anim.flip } animations

                    else
                        Dict.insert key { anim | post = post, depth = depth } animations

        withCurrent : Dict String ReplyAnimation
        withCurrent =
            Dict.foldl addOrRefresh model.replyAnimations current

        startRemovingIfGone : String -> ReplyAnimation -> Dict String ReplyAnimation -> Dict String ReplyAnimation
        startRemovingIfGone key anim animations =
            if anim.flip.removing || Dict.member key current then
                animations

            else
                Dict.insert key { anim | flip = Flip.remove (RemoveReply key) anim.flip } animations
    in
    { model | replyAnimations = Dict.foldl startRemovingIfGone withCurrent withCurrent }



-- VIEW


{-| Renders `model`'s whole (flattened) reply tree as one FLIP-animated list
(see `syncAnimations`) -- `text ""` if there are none. `onReplyClicked`/
`onEditClicked` build this page's own reply-composing/editing messages for a
given reply Post (same as `postDetail`'s own `onEditClicked`); `onMediaClicked`
likewise takes the reply itself so a click can be attributed to the right
Post. `toMsg` wraps this module's own `Msg` into the caller's.
-}
view :
    { basePath : String
    , viewingServerHost : String
    , postServerHost : String
    , maybeServer : Maybe RellmServer
    , maybeAccount : Maybe RellmAccount
    , onMediaClicked : Post -> String -> msg
    , mediaPlayState : MediaRenderer.Model
    , onMediaPlayClicked : String -> msg
    , onReplyClicked : Post -> msg
    , toMsg : Msg -> msg
    }
    -> Model
    -> Html msg
view config model =
    let
        items : List ( Int, Post, Flip.State Msg )
        items =
            flattenReplies model.collapsedReplies model.root
                |> List.filterMap
                    (\( depth, post ) ->
                        Dict.get post.id model.replyAnimations
                            |> Maybe.map (\anim -> ( depth, post, anim.flip ))
                    )
    in
    if List.isEmpty items then
        if Dict.get model.root.id model.statuses == Just ReplyLoading then
            div [ class "post-replies" ]
                [ div [ class "post-replies-header" ] [ text "Replies" ]
                , span [ class "post-reply-loading" ] [ text "Loading replies…" ]
                ]

        else
            text ""

    else
        div [ class "post-replies" ]
            [ div [ class "post-replies-header" ] [ text "Replies" ]
            , Html.Keyed.node "div"
                [ class "post-replies-list flip-animated-column" ]
                (List.map (replyAnimationView config model) items)
            ]


replyAnimationView :
    { r
        | basePath : String
        , viewingServerHost : String
        , postServerHost : String
        , maybeServer : Maybe RellmServer
        , maybeAccount : Maybe RellmAccount
        , onMediaClicked : Post -> String -> msg
        , mediaPlayState : MediaRenderer.Model
        , onMediaPlayClicked : String -> msg
        , onReplyClicked : Post -> msg
        , toMsg : Msg -> msg
    }
    -> Model
    -> ( Int, Post, Flip.State Msg )
    -> ( String, Html msg )
replyAnimationView config model ( depth, post, flip ) =
    let
        loaded : Bool
        loaded =
            Dict.get post.id model.statuses == Just ReplyLoaded

        loading : Bool
        loading =
            Dict.get post.id model.statuses == Just ReplyLoading

        collapsed : Bool
        collapsed =
            Set.member post.id model.collapsedReplies

        pointerEventsAttr : List (Html.Attribute msg)
        pointerEventsAttr =
            if flip.removing then
                [ style "pointer-events" "none" ]

            else
                []
    in
    ( post.id
    , div (Flip.itemAttributes Flip.Vertical flip False)
        [ div pointerEventsAttr
            [ Posts.replyCard
                config.basePath
                config.viewingServerHost
                config.postServerHost
                config.maybeServer
                config.maybeAccount
                (config.onMediaClicked post)
                config.mediaPlayState
                config.onMediaPlayClicked
                (depth - 1)
                loaded
                loading
                collapsed
                (Just (config.onReplyClicked post))
                (Just (config.toMsg (LoadRepliesClicked post.id)))
                (Just (config.toMsg (ToggleCollapsed post.id)))
                post
            ]
        ]
    )


{-| How deep `init` loads the reply tree in one shot when `root` shows up
without any `replies` of its own already attached.
-}
initialReplyDepth : Int
initialReplyDepth =
    3


{-| Replaces the node matching `targetId` anywhere in `post`'s own tree with
`newReplies` as its `replies` -- used to merge a `GetPosts` response for one
particular reply (or `root` itself) back into the tree it came from, without
disturbing any of that node's siblings/ancestors/already-loaded cousins.
-}
setRepliesAt : String -> List Post -> Post -> Post
setRepliesAt targetId newReplies post =
    if post.id == targetId then
        { post | replies = List.map wrapPost newReplies }

    else
        { post
            | replies =
                List.map
                    (\wrapped -> wrapPost (setRepliesAt targetId newReplies (unwrapPost wrapped)))
                    post.replies
        }


{-| Depth-first, pre-order flattening of `post`'s own reply tree (not
including `post` itself -- the page already shows that via its own
`postDetail`) -- direct replies at depth 1, their own replies at depth 2, etc.
This (not `Dict` iteration order, which is alphabetical by id) is what decides
the on-screen order every list/animation below actually renders in.

A reply whose id is in `collapsedReplies` (see `Model.collapsedReplies`,
toggled by its own `replyStatusButton`) still appears itself, but its
descendants are skipped -- `syncAnimations` then sees them drop out of the
flattened tree and fades them out via `Flip.remove` exactly like it would for
a reply that stopped coming back from the server, giving the collapse/expand
toggle its animation for free.

-}
flattenReplies : Set String -> Post -> List ( Int, Post )
flattenReplies collapsedReplies post =
    flattenAt 1 collapsedReplies post


flattenAt : Int -> Set String -> Post -> List ( Int, Post )
flattenAt depth collapsedReplies post =
    post.replies
        |> List.map unwrapPost
        |> List.concatMap
            (\reply ->
                ( depth, reply )
                    :: (if Set.member reply.id collapsedReplies then
                            []

                        else
                            flattenAt (depth + 1) collapsedReplies reply
                       )
            )
