module Components.PinnedPosts exposing (Model, Msg, init, subscriptions, syncIds, update, view)

{-| Fetches and renders `CustomHomePage.pinned_post_ids` -- the Posts `mainFrontendHost`'s admin has
pinned to the top of the Home page, above whatever `Pages.Home_`'s `home.target` otherwise renders
there (`Feed`/`HomeEvents`/`HomePosts`/`HomePost`/`HomePostWithEvents` alike -- pinned posts aren't a
_target_, just an overlay every one of those renders above itself, see `Pages.Home_`'s own doc). Only
ever pins Posts on `mainFrontendHost` itself (`Pages.Home_.homeConfigFor` only ever reads that one
server's own `customTabs`, and `Components.Pages.PostsPage.customNavPostIds`'s own doc makes the same
assumption for the tab/post-id case) -- so unlike `Shared.StarredPanel` (which can star Posts on any
federated server, and so groups fetches by host), this fetches everything from that one host.

Loaded the same way `Shared.StarredPanel` loads its own starred posts (see `protos/server_configuration.proto`'s
own doc comment on `pinned_post_ids`): one `GetPost` per id (there's no batch-by-ids RPC for Posts --
`GetPostsRequest.post_ids` exists in the proto but is never read by the backend), then, for any pinned
post that turns out to be about an `Event` (`context == OCCASION`), one batched `GetEvents` request
(`Components.Events.fetchEventsByOccasionPostIds`) for all of them together. Deliberately much
thinner than `StarredPanel` otherwise -- no starring/reordering/FLIP-reorder machinery, none of which
applies here (an admin, not this browser's viewer, controls the set and its order); a pinned post can
still be starred/unstarred by the viewer via the ordinary star button `view` renders, same as any
other post, but that's `Shared.StarredPanel`'s own concern, threaded through here only via the
`isStarred`/`onStarClicked` callbacks `view` takes. The viewer's own collapse choices (whole-section
and per-post alike -- see `isSectionCollapsed`/`expandedPostIds`) are the one piece of local state this
module does keep, the whole-section half of it persisted via `Shared.UserPreferences`'s own
`pinnedPostsCollapsedToHidePostIds` the same way `prefersCalendar`/`postsBefore`/`eventsAfter` are.

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

import Browser.Dom as Dom
import Components.Events as Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Proto.Rellm exposing (Event, GetEventsResponse, GetPostsResponse, Occasion, Post)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers exposing (RellmServer)
import Shared.Time as SharedTime
import Shared.UserPreferences as UserPreferences
import Task
import UI.Classes exposing (classes, openClosedClass)


type alias Model =
    { host : String
    , postIds : List String
    , posts : Dict String PostFetchStatus
    , events : Dict String EventFetchStatus

    -- Every plain (non-`OCCASION`) `PostFetchLoaded` post's own `Posts.postDetail` content, once
    -- measured (see `kickOffContentMeasurements`) -- its real, full (unclamped) rendered height in
    -- px, keyed by postId. Drives `pinnedPostView`'s own `Posts.ContentCollapse` -- a post only ever
    -- gets a "Show more" toggle once its own entry here exceeds `Posts.postDetailContentPreviewHeight`
    -- (see that constant's own doc for why raw Markdown length alone can't decide this reliably), so
    -- absent here just means "not measured yet" (renders full, no toggle, same as before this existed)
    -- exactly as much as it means "measured and short enough to skip the toggle entirely".
    , contentHeights : Dict String Float

    -- Ids (a subset of `postIds`) the viewer has clicked "Show more" on -- each renders its own
    -- `Posts.postDetail` content in full rather than `contentHeights`'s own short preview (see
    -- `ToggleContentExpanded`). Session-only (unlike the whole section's own collapse state, see
    -- `isSectionCollapsed`) -- reconciled the same "drop ids no longer pinned" way `posts`/`events`
    -- are in `syncIds`.
    , expandedPostIds : List String
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
    | ToggleSectionCollapsed
    | ToggleContentExpanded String
      -- One deliberate `requestAnimationFrame` wait (via a throwaway `Dom.getViewport` task) between
      -- a newly-loaded post's content actually landing in the DOM and measuring it -- same
      -- "`Browser.application` defers painting to the *next* frame" race `Components.Pages.EventsPage`'s
      -- own `ReadyToMeasureNew` exists to dodge (see that constructor's own doc); measuring
      -- `kickOffContentMeasurements`'s `pending` ids synchronously in the same update that inserts
      -- them risks measuring the *not-yet-rendered* DOM and getting back nothing/stale rects.
    | ReadyToMeasureContent (List String)
      -- `Ports.elementsMeasured` firing for a `measureContentEffect` call -- see `subscriptions`.
    | GotContentHeights Decode.Value


{-| Kicks off a fetch for every id in `postIds` (on `shared.accounts.mainFrontendHost`) right away --
mirrors `Shared.StarredPanel.kickOffFetches`'s "eager, not on-demand" loading, since (unlike the
Starred panel) this is always visible, not tucked behind a togglable panel.
-}
init : Shared.Model -> List String -> ( Model, Effect Msg )
init shared postIds =
    syncIds shared
        postIds
        { host = shared.accounts.mainFrontendHost
        , postIds = []
        , posts = Dict.empty
        , events = Dict.empty
        , contentHeights = Dict.empty
        , expandedPostIds = []
        }


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
            , contentHeights = keep model.contentHeights
            , expandedPostIds = List.filter (\postId -> List.member postId postIds) model.expandedPostIds
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

        ( changedModel, changedEffect ) =
            afterPostsChanged shared newModel
    in
    ( changedModel, Effect.batch (changedEffect :: fetchEffects) )


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

                ( changedModel, changedEffect ) =
                    afterPostsChanged shared { model | posts = Dict.insert postId newStatus model.posts }
            in
            ( changedModel, Effect.batch [ accountEffect, changedEffect ] )

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

        ToggleSectionCollapsed ->
            let
                -- Collapsing records the current `postIds` themselves (not just `True`) so
                -- `isSectionCollapsed` can tell a still-current collapse from a stale one a newly
                -- pinned/unpinned post has since invalidated; expanding just clears it.
                newPinnedPostsCollapsedToHidePostIds : List String
                newPinnedPostsCollapsedToHidePostIds =
                    if isSectionCollapsed shared model then
                        []

                    else
                        model.postIds
            in
            ( model
            , Effect.fromShared
                (Shared.UserPreferencesMsg (UserPreferences.SetPinnedPostsCollapsedToHidePostIds newPinnedPostsCollapsedToHidePostIds))
            )

        ToggleContentExpanded postId ->
            let
                expandedPostIds : List String
                expandedPostIds =
                    if List.member postId model.expandedPostIds then
                        List.filter ((/=) postId) model.expandedPostIds

                    else
                        postId :: model.expandedPostIds
            in
            ( { model | expandedPostIds = expandedPostIds }, Effect.none )

        ReadyToMeasureContent postIds ->
            ( model, measureContentEffect postIds )

        GotContentHeights value ->
            case Decode.decodeValue contentHeightsDecoder value of
                Ok entries ->
                    ( { model | contentHeights = List.foldl (\( postId, height ) -> Dict.insert postId height) model.contentHeights entries }
                    , Effect.none
                    )

                Err _ ->
                    ( model, Effect.none )


{-| Runs both "something in `model.posts` changed" follow-ups -- `kickOffEventFetches` and
`kickOffContentMeasurements` -- together, since every call site that changes `model.posts`
(`syncIds`, `GotPinnedPost`'s `Ok` branch) needs both.
-}
afterPostsChanged : Shared.Model -> Model -> ( Model, Effect Msg )
afterPostsChanged shared model =
    let
        ( eventModel, eventEffect ) =
            kickOffEventFetches shared model

        ( measuredModel, measureEffect ) =
            kickOffContentMeasurements eventModel
    in
    ( measuredModel, Effect.batch [ eventEffect, measureEffect ] )


{-| Mirrors `Shared.StarredPanel.kickOffEventFetches` exactly, minus the per-host grouping (see the
module doc -- everything here is already on one host). Run after every change to `model.posts`
(via `afterPostsChanged`), same "safe/cheap to call unconditionally" convention.
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


{-| Kicks off measuring every plain (non-`OCCASION`) `PostFetchLoaded` post's own content that isn't
already in `model.contentHeights` -- see that field's own doc, and `Posts.postDetailContentView`'s for
why this can't just be decided from `post.content` itself. Deliberately routes through
`ReadyToMeasureContent` rather than firing `measureContentEffect pending` directly -- see that
constructor's own doc for the DOM-not-painted-yet race that guards against.
-}
kickOffContentMeasurements : Model -> ( Model, Effect Msg )
kickOffContentMeasurements model =
    let
        pending : List String
        pending =
            model.posts
                |> Dict.toList
                |> List.filterMap
                    (\( postId, status ) ->
                        case status of
                            PostFetchLoaded post ->
                                if post.context /= OCCASION && not (Dict.member postId model.contentHeights) then
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
        ( model, Task.attempt (\_ -> ReadyToMeasureContent pending) Dom.getViewport |> Effect.fromCmd )


{-| Fires `Ports.measureElements` for every one of `postIds`' own `Posts.postDetailContentDomId` --
mirrors `Components.Pages.EventsPage.measureElementsEffect` exactly (see that function's own doc for
why this replaces a `Task.sequence` over `Browser.Dom.getElement` calls), just keyed by postId
directly rather than a separate animation key (there's only ever one measurement per post here, no
FLIP-style before/after pair to keep apart).
-}
measureContentEffect : List String -> Effect Msg
measureContentEffect postIds =
    postIds
        |> Encode.list
            (\postId ->
                Encode.object
                    [ ( "key", Encode.string postId )
                    , ( "id", Encode.string (Posts.postDetailContentDomId postId) )
                    ]
            )
        |> Ports.measureElements
        |> Effect.fromCmd


{-| Decodes `Ports.elementsMeasured`'s payload for a `measureContentEffect` call -- `key` is the
postId `measureContentEffect` sent, `height` its measured content's own real, unclamped rendered
height. Mirrors `Components.Pages.EventsPage.rectsDecoder`, minus the `x`/`y`/`width` this doesn't
need.
-}
contentHeightsDecoder : Decode.Decoder (List ( String, Float ))
contentHeightsDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.field "height" Decode.float)
        |> Decode.list


{-| `Ports.elementsMeasured`'s own `Sub` for `measureContentEffect`'s results -- a stray/late result
for a postId no longer in `model.postIds` is harmless (`Dict.insert` just adds a `contentHeights`
entry `syncIds` will drop on its own next pass), so unlike `Components.Pages.EventsPage`'s FLIP
round-trip there's no `model`-tracked phase to check this against.
-}
subscriptions : Sub Msg
subscriptions =
    Ports.elementsMeasured GotContentHeights


needsFetch : Dict String PostFetchStatus -> String -> Bool
needsFetch posts postId =
    not (Dict.member postId posts)


needsEventFetch : Dict String EventFetchStatus -> String -> Bool
needsEventFetch events postId =
    not (Dict.member postId events)


{-| Whether the whole section should render collapsed -- `True` only once
`shared.userPreferences.pinnedPostsCollapsedToHidePostIds` (see that field's own doc) exactly matches
`model.postIds`, i.e. the viewer collapsed it and nothing pinned has changed since. Any other pinned
set -- including one the viewer has never touched, or one a newly-pinned/-unpinned post has since
moved on from -- renders expanded, which is what re-opens the section the moment an admin pins
something new without `PinnedPosts` needing to notice that happened itself; `syncIds` does nothing
special for it, this is simply recomputed from the two lists on every `view`.
-}
isSectionCollapsed : Shared.Model -> Model -> Bool
isSectionCollapsed shared model =
    not (List.isEmpty model.postIds) && shared.userPreferences.pinnedPostsCollapsedToHidePostIds == model.postIds



-- VIEW


{-| The pinned posts section, in `model.postIds`' own order -- `text ""` (renders nothing) once
`model.postIds` is empty, so callers can render this unconditionally above their own content without
an extra "any pinned posts?" check of their own. Otherwise a header (the "Pinned Posts" label plus a
collapse/expand toggle) above the cards themselves, collapsible via `isSectionCollapsed`
(`ToggleSectionCollapsed`) -- the whole section (cards and the margin below them alike) animates
open/closed via the `grid-template-rows` 0fr/1fr trick `UI.accountAvatarMenuView`'s own collapsible
menu already uses in this app (see `pinned-posts.css`'s own doc), rather than any per-item `UI.Flip`
animation -- there's nothing here being individually added/removed/reordered, just one section's
overall height. Independent of that whole-section collapse, each plain (non-`OCCASION`) pinned post's
own content can also be individually shown as a short preview or expanded in full -- see
`model.expandedPostIds`/`ToggleContentExpanded`, threaded into `Posts.postDetail`'s own
`contentCollapse`.

Every argument besides `shared`/`model`/`toMsg` mirrors `Components.Posts.postDetail`'s/
`Components.Events.eventCard`'s own -- callers already build these same closures for their own posts
(see e.g. `Components.Pages.PostPage.view`/`Components.Pages.PostsPage.postCardView`), so `Pages.Home_`
builds them once and passes them through here too, keeping pinned posts' star/media-click behavior
identical to every other post in the app. `shared` itself is only read for `isSectionCollapsed`'s own
`shared.userPreferences.pinnedPostsCollapsedToHidePostIds` check.

-}
view :
    Shared.Model
    ->
        { time : SharedTime.Model
        , basePath : String
        , viewingServerHost : String
        , maybeServer : Maybe RellmServer
        , maybeAccount : Maybe RellmAccount
        , isStarred : Post -> Bool
        , onStarClicked : Post -> Maybe msg
        , onMediaClicked : Post -> String -> msg

        -- `Components.MediaRenderer`'s own click-to-play state/action -- see its module doc.
        -- `mediaPlayState` is just `shared.mediaRenderer`, passed straight through the same way
        -- `isStarred`/`onStarClicked` are built from `Shared.StarredPanel`'s state, since this module
        -- can't reach `Shared.Model` itself either (it only ever sees the pieces `config` hands it).
        , mediaPlayState : MediaRenderer.Model
        , onMediaPlayClicked : String -> msg

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

        -- Wraps this module's own `Msg` (`ToggleSectionCollapsed`, from the header button below, and
        -- `ToggleContentExpanded`, from each plain pinned post's own "Show more"/"Show less") into the
        -- caller's -- same convention as `Components.PostReplies.view`'s identical `toMsg`.
        , toMsg : Msg -> msg
        }
    -> Model
    -> Html msg
view shared config model =
    if List.isEmpty model.postIds then
        text ""

    else
        let
            collapsed : Bool
            collapsed =
                isSectionCollapsed shared model
        in
        div [ class "pinned-posts" ]
            [ button
                [ class "pinned-posts-header"
                , onClick (config.toMsg ToggleSectionCollapsed)
                , type_ "button"
                ]
                [ span [ class "pinned-posts-title" ] [ text "Pinned Posts" ]
                , span
                    [ classes ("pinned-posts-chevron" :: openChevronClass collapsed) ]
                    [ text "▼" ]
                ]
            , div
                [ classes [ "pinned-posts-content", openClosedClass (not collapsed) ] ]
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
        , mediaPlayState : MediaRenderer.Model
        , onMediaPlayClicked : String -> msg
        , freshenPost : Post -> Post
        , noOp : msg
        , toMsg : Msg -> msg
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

                    -- `Nothing` until (and unless) `model.contentHeights` confirms this post's own
                    -- content actually measured taller than `Posts.postDetailContentPreviewHeight` --
                    -- see that field's own doc, and `Posts.postDetail`'s own `contentCollapse` doc for
                    -- why a not-yet-measured/short post gets no toggle at all rather than a guess.
                    contentCollapse : Maybe (Posts.ContentCollapse msg)
                    contentCollapse =
                        Dict.get postId model.contentHeights
                            |> Maybe.andThen
                                (\naturalHeight ->
                                    if naturalHeight > Posts.postDetailContentPreviewHeight then
                                        Just
                                            { collapsed = not (List.member postId model.expandedPostIds)
                                            , toggle = config.toMsg (ToggleContentExpanded postId)
                                            , naturalHeight = naturalHeight
                                            }

                                    else
                                        Nothing
                                )
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
                            config.mediaPlayState
                            config.onMediaPlayClicked
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
                            contentCollapse
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
        , mediaPlayState : MediaRenderer.Model
        , onMediaPlayClicked : String -> msg
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
                        config.mediaPlayState
                        config.onMediaPlayClicked
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
