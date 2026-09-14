module Components.PinnedPosts exposing (Model, Msg, init, syncIds, update, view)

{-| Fetches and renders `CustomHomePage.pinned_post_ids` -- the Posts `mainFrontendHost`'s admin has
pinned to the top of the Home page, above whatever `Pages.Home_`'s `home.target` otherwise renders
there (`Feed`/`HomeEvents`/`HomePosts`/`HomePost`/`HomePostWithEvents` alike -- pinned posts aren't a
*target*, just an overlay every one of those renders above itself, see `Pages.Home_`'s own doc). Only
ever pins Posts on `mainFrontendHost` itself (`Pages.Home_.homeConfigFor` only ever reads that one
server's own `customTabs`, and `Components.Pages.PostsPage.customNavPostIds`'s own doc makes the same
assumption for the tab/post-id case) -- so unlike `Shared.StarredPanel` (which can star Posts on any
federated server, and so groups fetches by host), this fetches everything from that one host.

Loaded the same way `Shared.StarredPanel` loads its own starred posts (see `protos/server_configuration.proto`'s
own doc comment on `pinned_post_ids`): one `GetPost` per id (there's no batch-by-ids RPC for Posts --
`GetPostsRequest.post_ids` exists in the proto but is never read by the backend), then, for any pinned
post that turns out to be about an `Event` (`context == OCCASION`), one batched `GetEvents` request
(`Components.Events.fetchEventsByOccasionPostIds`) for all of them together. Deliberately much
thinner than `StarredPanel` otherwise -- no starring/reordering/localStorage/FLIP-reorder machinery,
none of which applies here (an admin, not this browser's viewer, controls the set and its order); a
pinned post can still be starred/unstarred by the viewer via the ordinary star button `view` renders,
same as any other post, but that's `Shared.StarredPanel`'s own concern, threaded through here only via
the `isStarred`/`onStarClicked` callbacks `view` takes.

Renders each plain (non-`OCCASION`) pinned post via `Components.Posts.postDetail` (the same full
title/content/media treatment `Components.Pages.PostPage`/`Pages.Post.PostId_` use for a post's own
dedicated page) rather than `postCard`'s compact preview -- a deliberate step up from every other
listing this app renders posts in, since a pin is meant to read as something the admin is
foregrounding, not just another feed entry. Always passed `readOnly = True`, though (see
`postDetail`'s own doc) -- there's no `PostPage.Model`-style editing state
(`visibilityEdit`/`moderationEdit`/etc.) here to wire Edit Content/Media/visibility/moderation up to,
so rather than show a post's own author a half-wired Edit button that does nothing, none of that UI
renders at all; its title instead links to the post's own `/post/:id` page, where editing (already
fully wired there) actually works.

-}

import Components.Events as Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (Event, GetEventsResponse, GetPostsResponse, Occasion, Post)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers exposing (RellmServer)
import Shared.Time as SharedTime
import Task
import UI.Classes exposing (classes, openClosedClass)


type alias Model =
    { host : String
    , postIds : List String
    , posts : Dict String PostFetchStatus
    , events : Dict String EventFetchStatus

    -- Whether the viewer has collapsed this section -- `view`'s own concern to render (a header
    -- with a toggle button, above a `grid-template-rows`-animated body, mirroring
    -- `UI.accountAvatarMenuView`'s identical collapse trick), tracked here (rather than in
    -- `Pages.Home_`) so it isn't lost across `syncIds`' own reconciliation.
    , collapsed : Bool
    }


{-| Mirrors `Shared.StarredPanel.PostFetchStatus`, minus its `ServerUnavailable` case -- pinned
posts only ever come from `mainFrontendHost`, the same server this whole frontend is already
talking to, so there's no "server not currently connected" state distinct from an ordinary failure
worth retrying differently.
-}
type PostFetchStatus
    = FetchingPost
    | PostFetchLoaded Post
    | PostFetchFailed


{-| Mirrors `Shared.StarredPanel.EventFetchStatus` -- only ever populated for a pinned post already
`PostFetchLoaded` with `context == OCCASION`, see `kickOffEventFetches`.
-}
type EventFetchStatus
    = FetchingEvent
    | EventFetchLoaded Event Occasion
    | EventFetchFailed


type Msg
    = GotPinnedPost String (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetPostsResponse ))
    | GotPinnedEvents (List String) (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetEventsResponse ))
    | ToggleCollapsed


{-| Kicks off a fetch for every id in `postIds` (on `shared.accounts.mainFrontendHost`) right away --
mirrors `Shared.StarredPanel.kickOffFetches`'s "eager, not on-demand" loading, since (unlike the
Starred panel) this is always visible, not tucked behind a togglable panel.
-}
init : Shared.Model -> List String -> ( Model, Effect Msg )
init shared postIds =
    syncIds shared
        postIds
        { host = shared.accounts.mainFrontendHost, postIds = [], posts = Dict.empty, events = Dict.empty, collapsed = False }


{-| Reconciles `model` with a freshly re-read `home.pinnedPostIds` -- `Pages.Home_` calls this on
every incoming `Shared.Msg` (alongside its own `homeConfigFor` re-check for `home.target`), since
`mainFrontendHost`'s `ServerConfiguration` -- and so `pinnedPostIds` itself -- can still be arriving
asynchronously the first time a page mounts (see `Pages.Home_.homeConfigFor`'s own doc). Cheap/no-op
to call when `postIds` hasn't actually changed: every already-`PostFetchLoaded`/in-flight id is left
alone, only ids newly added are fetched, and ids no longer pinned are dropped from `model` entirely
(no fade-out animation -- an admin's pin list is expected to change rarely, and abruptly, not as part
of this browser's own interaction the way starring/unstarring is).
-}
syncIds : Shared.Model -> List String -> Model -> ( Model, Effect Msg )
syncIds shared postIds model =
    let
        host : String
        host =
            shared.accounts.mainFrontendHost

        keep : Dict String a -> Dict String a
        keep dict =
            Dict.filter (\postId _ -> List.member postId postIds) dict

        pending : List String
        pending =
            List.filter (\postId -> needsFetch model.posts postId) postIds

        newModel : Model
        newModel =
            { host = host
            , postIds = postIds
            , posts = List.foldl (\postId -> Dict.insert postId FetchingPost) (keep model.posts) pending
            , events = keep model.events
            , collapsed = model.collapsed
            }

        maybeAccountServer : AccountsPanel.MaybeAccountServer
        maybeAccountServer =
            ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId, host )

        fetchEffects : List (Effect Msg)
        fetchEffects =
            pending
                |> List.map
                    (\postId ->
                        Posts.fetchPost shared.accounts maybeAccountServer postId
                            |> Task.attempt (GotPinnedPost postId)
                            |> Effect.fromCmd
                    )

        ( eventModel, eventEffect ) =
            kickOffEventFetches shared newModel
    in
    ( eventModel, Effect.batch (eventEffect :: fetchEffects) )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotPinnedPost postId (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    maybeAccountsPanelMsg
                        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                        |> Maybe.withDefault Effect.none

                newStatus : PostFetchStatus
                newStatus =
                    List.head response.posts |> Maybe.map PostFetchLoaded |> Maybe.withDefault PostFetchFailed

                ( eventModel, eventEffect ) =
                    kickOffEventFetches shared { model | posts = Dict.insert postId newStatus model.posts }
            in
            ( eventModel, Effect.batch [ accountEffect, eventEffect ] )

        GotPinnedPost postId (Err _) ->
            ( { model | posts = Dict.insert postId PostFetchFailed model.posts }, Effect.none )

        GotPinnedEvents postIds (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    maybeAccountsPanelMsg
                        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
                        |> Maybe.withDefault Effect.none

                loadedByPostId : Dict String ( Event, Occasion )
                loadedByPostId =
                    Events.occasionPairs response
                        |> List.filterMap (\( event, occasion ) -> occasion.post |> Maybe.map (\post -> ( post.id, ( event, occasion ) )))
                        |> Dict.fromList

                newEvents : Dict String EventFetchStatus
                newEvents =
                    List.foldl
                        (\postId events ->
                            case Dict.get postId loadedByPostId of
                                Just ( event, occasion ) ->
                                    Dict.insert postId (EventFetchLoaded event occasion) events

                                Nothing ->
                                    Dict.insert postId EventFetchFailed events
                        )
                        model.events
                        postIds
            in
            ( { model | events = newEvents }, accountEffect )

        GotPinnedEvents postIds (Err _) ->
            ( { model | events = List.foldl (\postId -> Dict.insert postId EventFetchFailed) model.events postIds }, Effect.none )

        ToggleCollapsed ->
            ( { model | collapsed = not model.collapsed }, Effect.none )


{-| Mirrors `Shared.StarredPanel.kickOffEventFetches` exactly, minus the per-host grouping (see the
module doc -- everything here is already on one host). Run after every change to `model.posts`
(`syncIds`, `GotPinnedPost`), same "safe/cheap to call unconditionally" convention.
-}
kickOffEventFetches : Shared.Model -> Model -> ( Model, Effect Msg )
kickOffEventFetches shared model =
    let
        pending : List String
        pending =
            model.posts
                |> Dict.toList
                |> List.filterMap
                    (\( postId, status ) ->
                        case status of
                            PostFetchLoaded post ->
                                if post.context == OCCASION && needsEventFetch model.events postId then
                                    Just postId

                                else
                                    Nothing

                            _ ->
                                Nothing
                    )
    in
    if List.isEmpty pending then
        ( model, Effect.none )

    else
        let
            maybeAccountServer : AccountsPanel.MaybeAccountServer
            maybeAccountServer =
                ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.host |> Maybe.map .userId, model.host )

            fetchEffect : Effect Msg
            fetchEffect =
                Events.fetchEventsByOccasionPostIds shared.accounts maybeAccountServer pending
                    |> Task.attempt (GotPinnedEvents pending)
                    |> Effect.fromCmd
        in
        ( { model | events = List.foldl (\postId -> Dict.insert postId FetchingEvent) model.events pending }, fetchEffect )


needsFetch : Dict String PostFetchStatus -> String -> Bool
needsFetch posts postId =
    not (Dict.member postId posts)


needsEventFetch : Dict String EventFetchStatus -> String -> Bool
needsEventFetch events postId =
    not (Dict.member postId events)



-- VIEW


{-| The pinned posts section, in `model.postIds`' own order -- `text ""` (renders nothing) once
`model.postIds` is empty, so callers can render this unconditionally above their own content without
an extra "any pinned posts?" check of their own. Otherwise a header (the "Pinned Posts" label plus a
collapse/expand toggle) above the cards themselves, collapsible via `model.collapsed`
(`ToggleCollapsed`) -- the whole section (cards and the margin below them alike) animates open/closed
via the `grid-template-rows` 0fr/1fr trick `UI.accountAvatarMenuView`'s own collapsible menu already
uses in this app (see `pinned-posts.css`'s own doc), rather than any per-item `UI.Flip` animation --
there's nothing here being individually added/removed/reordered, just one section's overall height.

Every argument besides `model`/`toMsg` mirrors `Components.Posts.postDetail`'s/`Components.Events.eventCard`'s
own -- callers already build these same closures for their own posts (see e.g.
`Components.Pages.PostPage.view`/`Components.Pages.PostsPage.postCardView`), so `Pages.Home_` builds
them once and passes them through here too, keeping pinned posts' star/media-click behavior identical
to every other post in the app.
-}
view :
    { time : SharedTime.Model
    , basePath : String
    , viewingServerHost : String
    , maybeServer : Maybe RellmServer
    , maybeAccount : Maybe RellmAccount
    , isStarred : Post -> Bool
    , onStarClicked : Post -> Maybe msg
    , onMediaClicked : Post -> String -> msg

    -- Overlays a pinned post's freshest known copy before rendering -- typically
    -- `Shared.StarredPanel.freshestPost`, so a just-toggled star's updated count shows immediately
    -- without waiting on a fresh fetch, mirroring `Components.Pages.PostsPage.postCardView`'s/
    -- `Shared.StarredPanel.starredOccasionView`'s own identical overlay.
    , freshenPost : Post -> Post

    -- Unreachable placeholder for `Posts.postDetail`'s/`Events.eventCard`'s own `onPush`/`onDelete`
    -- (also reused for `postDetail`'s edit-related callbacks, see the module doc) -- this section
    -- always passes `availableSyncDestinations = Nothing` (see `pinnedPostView`), so neither
    -- is ever actually rendered/clickable, same convention as `Shared.StarredPanel`'s own `NoOp`.
    , noOp : msg

    -- Wraps this module's own `Msg` (just `ToggleCollapsed`, from the header button below) into the
    -- caller's -- same convention as `Components.PostReplies.view`'s identical `toMsg`.
    , toMsg : Msg -> msg
    }
    -> Model
    -> Html msg
view config model =
    if List.isEmpty model.postIds then
        text ""

    else
        div [ class "pinned-posts" ]
            [ button
                [ class "pinned-posts-header"
                , onClick (config.toMsg ToggleCollapsed)
                , type_ "button"
                ]
                [ span [ class "pinned-posts-title" ] [ text "Pinned Posts" ]
                , span
                    [ classes ("pinned-posts-chevron" :: openChevronClass model.collapsed) ]
                    [ text "▼" ]
                ]
            , div
                [ classes [ "pinned-posts-content", openClosedClass (not model.collapsed) ] ]
                [ div [ class "pinned-posts-list" ]
                    (List.filterMap (pinnedPostView config model) model.postIds)
                ]
            ]


openChevronClass : Bool -> List String
openChevronClass collapsed =
    if collapsed then
        []

    else
        [ "open" ]


pinnedPostView :
    { r
        | time : SharedTime.Model
        , basePath : String
        , viewingServerHost : String
        , maybeServer : Maybe RellmServer
        , maybeAccount : Maybe RellmAccount
        , isStarred : Post -> Bool
        , onStarClicked : Post -> Maybe msg
        , onMediaClicked : Post -> String -> msg
        , freshenPost : Post -> Post
        , noOp : msg
    }
    -> Model
    -> String
    -> Maybe (Html msg)
pinnedPostView config model postId =
    case Dict.get postId model.posts of
        Just (PostFetchLoaded rawPost) ->
            if rawPost.context == OCCASION then
                pinnedOccasionView config model postId rawPost

            else
                let
                    post : Post
                    post =
                        config.freshenPost rawPost
                in
                Just
                    (div [ class "pinned-post-entry" ]
                        [ Posts.postDetail
                            config.time
                            config.basePath
                            config.viewingServerHost
                            model.host
                            config.maybeServer
                            config.maybeAccount
                            (config.onMediaClicked post)
                            True
                            config.noOp
                            Nothing
                            (\_ -> config.noOp)
                            (config.isStarred post)
                            (config.onStarClicked post)
                            config.noOp
                            (text "")
                            (text "")
                            Nothing
                            (\_ -> False)
                            (\_ -> Nothing)
                            (\_ -> config.noOp)
                            (\_ _ -> config.noOp)
                            post
                        ]
                    )

        Just FetchingPost ->
            Just (div [ class "pinned-post-entry post-loading" ] [ text "Loading…" ])

        Just PostFetchFailed ->
            Just (div [ class "pinned-post-entry post-error" ] [ text ("Couldn't load pinned Post " ++ postId ++ ".") ])

        Nothing ->
            Nothing


pinnedOccasionView :
    { r
        | time : SharedTime.Model
        , basePath : String
        , viewingServerHost : String
        , maybeServer : Maybe RellmServer
        , maybeAccount : Maybe RellmAccount
        , isStarred : Post -> Bool
        , onStarClicked : Post -> Maybe msg
        , onMediaClicked : Post -> String -> msg
        , freshenPost : Post -> Post
        , noOp : msg
    }
    -> Model
    -> String
    -> Post
    -> Maybe (Html msg)
pinnedOccasionView config model postId rawPost =
    case Dict.get postId model.events of
        Just (EventFetchLoaded event occasion) ->
            let
                post : Post
                post =
                    config.freshenPost rawPost

                displayOccasion : Occasion
                displayOccasion =
                    { occasion | post = Just post }
            in
            Just
                (div [ class "pinned-post-entry" ]
                    [ Events.eventCard
                        config.time
                        config.basePath
                        config.viewingServerHost
                        model.host
                        config.maybeServer
                        config.maybeAccount
                        (config.onMediaClicked post)
                        MediaRenderer.ExtraSmall
                        (config.isStarred post)
                        (config.onStarClicked post)
                        False
                        False
                        False
                        Nothing
                        (\_ -> False)
                        (\_ -> Nothing)
                        (\_ -> config.noOp)
                        (\_ _ -> config.noOp)
                        event
                        displayOccasion
                    ]
                )

        Just FetchingEvent ->
            Just (div [ class "pinned-post-entry post-loading" ] [ text "Loading…" ])

        Just EventFetchFailed ->
            Just (div [ class "pinned-post-entry post-error" ] [ text ("Couldn't load Event for pinned Post " ++ postId ++ ".") ])

        Nothing ->
            Just (div [ class "pinned-post-entry post-loading" ] [ text "Loading…" ])
