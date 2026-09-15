module Components.Pages.PostPage exposing
    ( Model
    , Msg
    , fromShared
    , init
    , subscriptions
    , titleFor
    , update
    , view
    )

{-| The shared guts of a single Post's page: fetching a `Proto.Rellm.Post` (by id, from a specific
possibly-not-yet-connected server) and rendering it, including its threaded replies -- reused by
both `Pages.Post.PostId_` (`/post/:id[@host]`) and `Pages.UsernameOrCustomTab_` (once a custom tab's
own `path` resolves to a `TargetPost`, see that module's `initEmbedded`), which differ only in
whether the post id comes from the route directly or from a matched `CustomNavigationTab`'s own
`postId`. Mirrors `Components.Pages.UserProfilePage`'s own split from its two callers.

`pageIsSecure`/`navKey` are captured once, at `init` (same reasoning as
`UserProfilePage.Model.pageIsSecure`/`navKey`) -- needed later by `ConnectClicked`
(`RellmServers.connectToRellmServer`) and `update`'s own `Shared.GotPostDeleteResult` handling
(navigating Home once the viewed Post no longer exists), neither of which otherwise has access to
the calling page's own `Request`.
-}

import Browser.Navigation
import Components.AIProviders as AIProviders
import Components.PostReplies as PostReplies
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Components.ServerDependentView as ServerDependentView
import Components.SyncDestinations as SyncDestinations
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Route
import Grpc
import Html exposing (Html, button, div, option, p, select, span, text)
import Html.Attributes exposing (class, disabled, selected, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (GetSyncDestinationsResponse, Post, SyncDestination)
import Proto.Rellm.Moderation exposing (Moderation)
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MediaGeneratorPanel as MediaGeneratorPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.MyMediaPanel as MyMediaPanel
import Shared.StarredPanel as StarredPanel
import Task
import Time
import UI.Classes exposing (classes)



-- MODEL


type alias Model =
    { targetHost : String
    , postId : String
    , postStatus : PostStatus
    , repliesModel : Maybe PostReplies.Model
    , connectStatus : ServerDependentView.ConnectStatus
    , fetchStarted : Bool

    -- The `RellmAccounts.rellmAccountId` of whichever account was signed in on
    -- `targetHost` (the Post's own server) when the currently-held
    -- `postStatus` was last fetched, if any -- what `update`'s `SharedMsg`
    -- branch compares `currentAccountId` against to notice an
    -- `AccountsPanel.ToggleAccountEnabled`/`ToggleServerEnabled` changed
    -- who's signed in here, and `refetch` accordingly, so the Post (and any
    -- author-only fields on it) stays in sync with the credentials it's
    -- fetched with.
    , fetchedAccountId : Maybe String
    , visibilityEdit : Maybe VisibilityEdit
    , moderationEdit : Maybe ModerationEdit

    -- Set by `MediaEditClicked`, until the `Shared.MyMediaPanel` it opens
    -- reports back a `SaveMediaClicked`/`CloseClicked` -- same "am I mid-edit"
    -- gating `Components.Pages.UserProfilePage.avatarEdit` uses for its own
    -- `MyMediaPanel.MediaItemClicked` pickup (see that module's doc), needed
    -- here for the same reason: `MyMediaPanel`'s `Shared.Msg`s are forwarded
    -- to whichever page is current regardless of who opened the panel, so
    -- without this an unrelated Browse-mode/other-page save could be
    -- mistaken for this page's own.
    , mediaEditActive : Bool

    -- Set by `GenerateMediaClicked`, until `Shared.MediaGeneratorPanel` reports back a
    -- `GotGenerateResult`/`CancelClicked` -- same "am I mid-edit" gating `mediaEditActive` uses for
    -- `Shared.MyMediaPanel`, needed here for the same reason (see that panel's own module doc on why
    -- this lives at the page level rather than inside the panel itself).
    , mediaGeneratorActive : Bool

    -- Captured once at `init` -- see the module doc.
    , pageIsSecure : Bool
    , navKey : Browser.Navigation.Key

    -- `Submitting`/`SubmitFailed` push status per `syncDestinationId`, for the
    -- "synced to" listing's own Push/Push-again button (see
    -- `Posts.postSyncDestinationsView`'s `isPushing`/`pushError`) -- mirrors
    -- `Pages.Event.PostId_.Model.syncDestinationPushStatuses` exactly, since
    -- this page too only ever shows one Post's own sync status at a time.
    , syncDestinationPushStatuses : Dict String SubmitStatus

    -- The viewer's own `SyncDestination`s, fetched once `GotPost` confirms they're this Post's
    -- author (or Admin) -- mirrors `Pages.Event.PostId_.Model.availableSyncDestinations` exactly,
    -- including the `Nothing`-until-fetched/non-author fallback to a read-only view. See that
    -- field's own doc.
    , availableSyncDestinations : Maybe (List SyncDestination)
    }



-- UPDATE


type Msg
    = GotPost (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetPostsResponse ))
    | GotBreadcrumbAncestors Post (Result Grpc.Error ( Maybe AccountsPanel.Msg, List Post ))
    | PostRepliesMsg PostReplies.Msg
    | ConnectClicked
    | GotConnectResult (Result Grpc.Error RellmServer)
    | EnableClicked
    | EditClicked Post
    | ReplyClicked Post
    | MediaClicked Post String
    | MediaEditClicked Post
    | GenerateMediaClicked Post
    | GotMediaUpdateResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- `Components.Posts.mediaLayoutSelector`'s `onMediaLayoutChanged` --
      -- unlike `MediaEditClicked`, this saves straight away (no picker panel,
      -- no `mediaEditActive`-style "am I mid-edit" state) since a layout
      -- choice is a plain `<select>`, not something with its own open/close
      -- lifecycle.
    | MediaLayoutChanged Post String
    | GotMediaLayoutSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
    | VisibilityEditClicked Post
    | VisibilityChanged String
    | VisibilityCancelClicked
    | VisibilitySaveClicked Post
    | GotVisibilitySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- The moderation-status selector (see `moderationView`) -- mirrors
      -- the `Visibility*` messages just above exactly, for an Admin/
      -- `MODERATEPOSTS` holder instead of the post's own author. Its own
      -- "Edit" button reads "Moderate" instead, per this feature's own
      -- request.
    | ModerationEditClicked Post
    | ModerationChanged String
    | ModerationCancelClicked
    | ModerationSaveClicked Post
    | GotModerationSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- The Delete button (see `deleteButtonView`), shown to the post's own
      -- owner -- opens the shared "are you sure?" dialog
      -- (`Shared.ConfirmPostDelete`); its result (`Shared.GotPostDeleteResult`)
      -- is picked up in `SharedMsg` below.
    | DeleteClicked Post
      -- The Push button on `postDetailView`'s `Posts.postSyncDestinationsView`
      -- row (see `Model.syncDestinationPushStatuses`'s own doc) -- the Delete
      -- button on that same row instead goes straight through
      -- `Shared.RequestDelete`/`Shared.ConfirmPostSyncDestinationDelete`
      -- (see `postDetailView`), mirroring `Pages.Event.PostId_`'s identical
      -- split exactly.
    | PushSyncDestinationClicked String
    | GotSyncDestinationPushResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Post ))
      -- `Model.availableSyncDestinations`'s own fetch (see `GotPost`'s Ok branch) resolving --
      -- mirrors `Pages.Event.PostId_.GotSyncDestinationsResult` exactly, including the
      -- no-error-banner-on-failure behavior.
    | GotSyncDestinationsResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetSyncDestinationsResponse ))
    | Poll
    | SharedMsg Shared.Msg


type PostStatus
    = LoadingPost
    | PostLoaded Post
    | PostFailed


{-| Mirrors `Components.UserProfilePage.SubmitStatus` -- kept separate since
this page's visibility edit is local to it rather than routed through
`Shared.MarkdownPanel`.
-}
type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Live only while the visibility picker (see `Model.visibilityEdit`) is
being edited by the post's own author -- `pending` is the in-progress
`<select>` value, independent of the loaded Post's own `visibility` until
`VisibilitySaveClicked` succeeds. Mirrors `Components.UserProfilePage`'s
`RealNameEdit`.
-}
type alias VisibilityEdit =
    { pending : Visibility
    , status : SubmitStatus
    }


{-| Live only while the moderation-status picker (see `Model.moderationEdit`)
is being edited by an Admin/`MODERATEPOSTS` holder -- mirrors `VisibilityEdit`
exactly, just for `Moderation` instead of `Visibility`.
-}
type alias ModerationEdit =
    { pending : Moderation
    , status : SubmitStatus
    }


{-| `rawPostId` is the unparsed `:id[@host]` route segment (or a `CustomNavigationTab.postId`,
which is always a bare id with no `@host` suffix -- `Posts.parsePostRouteId` handles both the same
way, since a bare id with no `@` just falls back to `mainFrontendHost`).

A Mastodon/Bluesky post never reaches this module at all -- `Pages.Post.PostId_` routes those
straight to `Components.Pages.MastodonPostPage`/`BlueskyPostPage` instead (see
`Posts.parseFederatedPostId`, and that dispatcher's own doc) -- so everything below can assume a real
Rellm post on some (possibly not-yet-connected) `RellmServer`.
-}
init : Shared.Model -> Bool -> String -> Browser.Navigation.Key -> ( Model, Effect Msg )
init shared pageIsSecure rawPostId navKey =
    let
        ( postId, targetHost ) =
            Posts.parsePostRouteId shared.accounts.mainFrontendHost rawPostId

        baseModel : Model
        baseModel =
            { targetHost = targetHost
            , postId = postId
            , postStatus = LoadingPost
            , repliesModel = Nothing
            , connectStatus = ServerDependentView.NotConnected
            , fetchStarted = False
            , fetchedAccountId = Nothing
            , visibilityEdit = Nothing
            , moderationEdit = Nothing
            , mediaEditActive = False
            , mediaGeneratorActive = False
            , pageIsSecure = pageIsSecure
            , navKey = navKey
            , syncDestinationPushStatuses = Dict.empty
            , availableSyncDestinations = Nothing
            }

        ( fetchedModel, fetchEffect ) =
            fetchIfReady shared baseModel
    in
    ( fetchedModel
      -- Clears any breadcrumb trail left over from whichever Post was
      -- viewed before this one -- `GotPost` below repopulates it once this
      -- Post's own data (and, if it's a reply, its ancestor chain) is back,
      -- so there's no stale trail shown in the meantime.
    , Effect.batch [ fetchEffect, Effect.fromShared (Shared.BreadcrumbsMsg Breadcrumbs.Clear) ]
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.fetchStarted then
            Sub.none

          else
            Time.every 30000 (\_ -> Poll)
        , model.repliesModel
            |> Maybe.map (PostReplies.subscriptions >> Sub.map PostRepliesMsg)
            |> Maybe.withDefault Sub.none
        ]


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotPost (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    accountsPanelEffect maybeAccountsPanelMsg

                maybeUserId : Maybe String
                maybeUserId =
                    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost |> Maybe.map .userId

                ( repliesModel, repliesEffect ) =
                    case ( List.head response.posts, model.repliesModel ) of
                        ( Just post, Nothing ) ->
                            PostReplies.init shared.accounts maybeUserId model.targetHost post
                                |> Tuple.mapFirst Just
                                |> Tuple.mapSecond (Effect.map PostRepliesMsg)

                        ( Just post, Just existing ) ->
                            PostReplies.refresh shared.accounts maybeUserId post existing
                                |> Tuple.mapFirst Just
                                |> Tuple.mapSecond (Effect.map PostRepliesMsg)

                        ( Nothing, existing ) ->
                            ( existing, Effect.none )

                -- A Post reached via a reply chain (`REPLY` context) fetches
                -- its ancestors first -- see `GotBreadcrumbAncestors` for
                -- where `Shared.Breadcrumbs` actually gets set once that
                -- resolves. A plain top-level Post has no chain to fetch, but
                -- still sets `Shared.Breadcrumbs` to its own `targetHost` (as
                -- a `FromServerHost`, same as `Pages.Home_`), so the trail
                -- still shows a `hostSegment` server chip when it's on a
                -- server other than `mainFrontendHost` (see
                -- `Shared.Breadcrumbs.bar`) -- not just cleared outright.
                breadcrumbsEffect : Effect Msg
                breadcrumbsEffect =
                    case List.head response.posts of
                        Just post ->
                            if post.context == REPLY then
                                Posts.fetchAncestors shared.accounts (maybeAccountServerFor shared model) post
                                    |> Task.attempt (GotBreadcrumbAncestors post)
                                    |> Effect.fromCmd

                            else
                                Effect.fromShared
                                    (Shared.BreadcrumbsMsg
                                        (Breadcrumbs.SetRoot (Breadcrumbs.FromPost post) model.targetHost [])
                                    )

                        Nothing ->
                            Effect.none

                ( postUpdatedModel, postUpdatedEffect ) =
                    case List.head response.posts of
                        Just post ->
                            applyUpdatedPost model post

                        Nothing ->
                            ( { model | postStatus = PostFailed }, Effect.none )

                -- Only the Post's author (or an Admin) can ever push it to a `SyncDestination` --
                -- mirrors `Pages.Event.PostId_.GotEvent`'s identical
                -- `syncDestinationsFetchEffect`/`isOwner` gate exactly, including the
                -- guard-on-`Nothing` so a post-edit refetch doesn't re-issue this.
                syncDestinationsFetchEffect : Effect Msg
                syncDestinationsFetchEffect =
                    case ( List.head response.posts, model.availableSyncDestinations, serverAndAccount shared model ) of
                        ( Just post, Nothing, Just ( server, account ) ) ->
                            if Posts.isAuthor account post || List.member ADMIN account.permissions then
                                SyncDestinations.getSyncDestinations shared.accounts ( Just account.userId, server.frontendHost ) ""
                                    |> Task.attempt GotSyncDestinationsResult
                                    |> Effect.fromCmd

                            else
                                Effect.none

                        _ ->
                            Effect.none
            in
            ( { postUpdatedModel | repliesModel = repliesModel }
            , Effect.batch [ accountEffect, repliesEffect, breadcrumbsEffect, postUpdatedEffect, syncDestinationsFetchEffect ]
            )

        GotPost (Err _) ->
            ( { model | postStatus = PostFailed }, Effect.none )

        GotSyncDestinationsResult (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | availableSyncDestinations = Just response.destinations }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSyncDestinationsResult (Err _) ->
            ( model, Effect.none )

        GotBreadcrumbAncestors post (Ok ( maybeAccountsPanelMsg, ancestors )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    accountsPanelEffect maybeAccountsPanelMsg

                -- `ancestors` is root-first and excludes `post` itself (see
                -- `Posts.fetchAncestors`) -- its first entry is the root
                -- (this Post's own reply chain can't be empty, since this is
                -- only ever kicked off for a `REPLY`-context Post), and
                -- everything after it, plus `post` itself, is the rest of the
                -- chain shown as reply segments.
                root : Post
                root =
                    List.head ancestors |> Maybe.withDefault post

                replies : List Post
                replies =
                    List.drop 1 ancestors ++ [ post ]
            in
            ( model
            , Effect.batch
                [ accountEffect
                , Effect.fromShared
                    (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromPost root) model.targetHost replies))
                ]
            )

        GotBreadcrumbAncestors _ (Err _) ->
            ( model, Effect.none )

        PostRepliesMsg subMsg ->
            case model.repliesModel of
                Just repliesModel ->
                    let
                        maybeUserId : Maybe String
                        maybeUserId =
                            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost |> Maybe.map .userId

                        ( newRepliesModel, effect ) =
                            PostReplies.update shared.accounts maybeUserId subMsg repliesModel
                    in
                    ( { model | repliesModel = Just newRepliesModel }, Effect.map PostRepliesMsg effect )

                Nothing ->
                    ( model, Effect.none )

        EditClicked post ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.PostContent post) model.targetHost)) )

        ReplyClicked post ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.NewReply post) model.targetHost)) )

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

        GenerateMediaClicked post ->
            ( { model | mediaGeneratorActive = True }
            , Effect.fromShared
                (Shared.MediaGeneratorPanelMsg
                    (MediaGeneratorPanel.Open (Just (MediaGeneratorPanel.TargetPost post)) model.targetHost shared.basePath)
                )
            )

        GotMediaUpdateResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            let
                ( postUpdatedModel, postUpdatedEffect ) =
                    applyUpdatedPost model updatedPost
            in
            ( postUpdatedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, postUpdatedEffect ] )

        GotMediaUpdateResult (Err _) ->
            ( model, Effect.none )

        MediaLayoutChanged post text ->
            case ( Posts.postMediaLayoutFromText text, serverAndAccount shared model ) of
                ( Just layout, Just ( server, account ) ) ->
                    ( model
                    , Posts.updatePost
                        shared.accounts
                        ( Just account.userId, server.frontendHost )
                        post.id
                        (\freshPost -> { freshPost | postMediaLayout = layout })
                        |> Task.attempt GotMediaLayoutSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotMediaLayoutSaveResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            let
                ( postUpdatedModel, postUpdatedEffect ) =
                    applyUpdatedPost model updatedPost
            in
            ( postUpdatedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, postUpdatedEffect ] )

        GotMediaLayoutSaveResult (Err _) ->
            ( model, Effect.none )

        VisibilityEditClicked post ->
            ( { model | visibilityEdit = Just { pending = post.visibility, status = Idle } }, Effect.none )

        VisibilityChanged text ->
            ( { model
                | visibilityEdit =
                    model.visibilityEdit
                        |> Maybe.map
                            (\edit -> { edit | pending = Posts.visibilityFromText text |> Maybe.withDefault edit.pending })
              }
            , Effect.none
            )

        VisibilityCancelClicked ->
            ( { model | visibilityEdit = Nothing }, Effect.none )

        VisibilitySaveClicked post ->
            case ( model.visibilityEdit, serverAndAccount shared model ) of
                ( Just edit, Just ( server, account ) ) ->
                    ( { model | visibilityEdit = Just { edit | status = Submitting } }
                    , Posts.updatePost shared.accounts ( Just account.userId, server.frontendHost ) post.id (\freshPost -> { freshPost | visibility = edit.pending })
                        |> Task.attempt GotVisibilitySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotVisibilitySaveResult (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            let
                ( postUpdatedModel, postUpdatedEffect ) =
                    applyUpdatedPost model updatedPost
            in
            ( { postUpdatedModel | visibilityEdit = Nothing }
            , Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, postUpdatedEffect ]
            )

        GotVisibilitySaveResult (Err err) ->
            ( { model
                | visibilityEdit =
                    model.visibilityEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        ModerationEditClicked post ->
            ( { model | moderationEdit = Just { pending = post.moderation, status = Idle } }, Effect.none )

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

        ModerationSaveClicked post ->
            case ( model.moderationEdit, serverAndAccount shared model ) of
                ( Just edit, Just ( server, account ) ) ->
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
                ( postUpdatedModel, postUpdatedEffect ) =
                    applyUpdatedPost model updatedPost
            in
            ( { postUpdatedModel | moderationEdit = Nothing }
            , Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, postUpdatedEffect ]
            )

        GotModerationSaveResult (Err err) ->
            ( { model
                | moderationEdit =
                    model.moderationEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        DeleteClicked post ->
            ( model, Effect.fromShared (Shared.RequestDelete (Shared.ConfirmPostDelete post model.targetHost)) )

        PushSyncDestinationClicked destinationId ->
            case ( model.postStatus, serverAndAccount shared model ) of
                ( PostLoaded post, Just ( server, account ) ) ->
                    ( { model | syncDestinationPushStatuses = Dict.insert destinationId Submitting model.syncDestinationPushStatuses }
                    , Posts.syncPost shared.accounts ( Just account.userId, server.frontendHost ) post.id destinationId
                        |> Task.attempt (GotSyncDestinationPushResult destinationId)
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotSyncDestinationPushResult destinationId (Ok ( maybeAccountsPanelMsg, updatedPost )) ->
            ( { model
                | syncDestinationPushStatuses = Dict.remove destinationId model.syncDestinationPushStatuses
                , postStatus = PostLoaded updatedPost
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSyncDestinationPushResult destinationId (Err err) ->
            ( { model | syncDestinationPushStatuses = Dict.insert destinationId (SubmitFailed (AccountsPanel.grpcErrorToString err)) model.syncDestinationPushStatuses }
            , Effect.none
            )

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

        Poll ->
            fetchIfReady shared model

        SharedMsg subMsg ->
            let
                ( fetchedModel, fetchEffect ) =
                    case subMsg of
                        -- Also covers logging in/out of an Account for this
                        -- Post's own server (`AccountsPanel.
                        -- ToggleAccountEnabled`/`ToggleServerEnabled`) --
                        -- when that changes who's signed in on `targetHost`,
                        -- `refetch` so the Post reflects the new (or
                        -- withdrawn) credentials, rather than `fetchIfReady`,
                        -- which no-ops once `fetchStarted` is already `True`.
                        Shared.AccountsPanelMsg _ ->
                            if model.fetchStarted && currentAccountId shared model /= model.fetchedAccountId then
                                refetch shared model

                            else
                                fetchIfReady shared model

                        Shared.MarkdownPanelMsg (MarkdownPanel.GotSaveResult (Ok _)) ->
                            refetch shared model

                        -- `Shared.MyMediaPanel`'s own module doc covers why
                        -- this arrives as a forwarded `Shared.Msg` rather
                        -- than a callback -- gated on `mediaEditActive` (set
                        -- by `MediaEditClicked`) so a Save from some
                        -- unrelated use of the panel elsewhere can't be
                        -- mistaken for this page's own edit.
                        Shared.MyMediaPanelMsg (MyMediaPanel.SaveMediaClicked mediaRefs) ->
                            if model.mediaEditActive then
                                case serverAndAccount shared model of
                                    Just ( server, account ) ->
                                        ( { model | mediaEditActive = False }
                                        , Posts.updatePost
                                            shared.accounts
                                            ( Just account.userId, server.frontendHost )
                                            model.postId
                                            (\freshPost -> { freshPost | media = mediaRefs })
                                            |> Task.attempt GotMediaUpdateResult
                                            |> Effect.fromCmd
                                        )

                                    Nothing ->
                                        ( { model | mediaEditActive = False }, Effect.none )

                            else
                                ( model, Effect.none )

                        Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked ->
                            ( { model | mediaEditActive = False }, Effect.none )

                        -- `Shared.MediaGeneratorPanel`'s own module doc covers why this arrives as
                        -- a forwarded `Shared.Msg` rather than a callback -- gated on
                        -- `mediaGeneratorActive` (set by `GenerateMediaClicked`) for the same
                        -- "don't mistake some unrelated use of the panel for this page's own"
                        -- reasoning `mediaEditActive` above already gives. Only refetches on `Ok`
                        -- (a new `Media` was actually attached to this post) -- an `Err` leaves the
                        -- panel open showing the error, so this page has nothing new to pick up yet.
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
                        Shared.GotPostDeleteResult (Ok _) ->
                            ( model, Browser.Navigation.pushUrl model.navKey (Gen.Route.toHref Gen.Route.Home_) |> Effect.fromCmd )

                        -- The "synced to" listing's own Delete button (see
                        -- `Model.syncDestinationPushStatuses`'s own doc) resolving
                        -- successfully -- mirrors `Pages.Event.PostId_`'s identical
                        -- branch: refetch, since a successful un-sync changes
                        -- `post.syncDestinations` behind this already-fetched copy's
                        -- back the same way, and the result carries no destination id
                        -- to patch it out by hand with.
                        Shared.GotPostSyncDestinationDeleteResult _ (Ok _) ->
                            refetch shared model

                        _ ->
                            ( model, Effect.none )
            in
            ( fetchedModel, Effect.batch [ Effect.fromShared subMsg, fetchEffect ] )


{-| Kicks off the actual `GetPosts` fetch the first time `targetHost` is a
known, connected server -- whether that was already true at `init`, or only
became true later because the user connected it (`ConnectClicked`) or it
auto-reconnected in the background.

This is event-driven -- any `AccountsPanel` message passing through `update`'s
`SharedMsg` branch triggers a call, since that covers a server
connecting/being added, including reconnecting persisted servers on app
startup (`Main.notifyPageOfSharedMsg` forwards those top-level `Shared`
messages into whichever page is active). `subscriptions`' poll is just a
distrustful fallback in case some future state change doesn't route through
`SharedMsg`, so it can be slow.

-}
fetchIfReady : Shared.Model -> Model -> ( Model, Effect Msg )
fetchIfReady shared model =
    if model.fetchStarted then
        ( model, Effect.none )

    else
        case RellmServers.knownConnectedRellmServer shared.accounts.servers model.targetHost of
            Just _ ->
                ( { model | fetchStarted = True, fetchedAccountId = currentAccountId shared model }
                , Posts.fetchPost shared.accounts (maybeAccountServerFor shared model) model.postId
                    |> Task.attempt GotPost
                    |> Effect.fromCmd
                )

            Nothing ->
                ( model, Effect.none )


{-| Re-fetches the post unconditionally (unlike `fetchIfReady`, not gated on
`fetchStarted`, which is already `True` by the time this is ever called) --
for `update`'s `SharedMsg` branch to call once the Markdown panel (see
`Shared.MarkdownPanel`) reports a successful save: either this post's content
just changed (`MarkdownPanel.PostContent`) or a new reply to it was just
posted (`MarkdownPanel.NewReply`) -- either way, `GotPost`'s own handler
re-syncs `repliesModel` too (via `PostReplies.refresh`, since it's already
`Just` by the time any save could have happened), so there's nothing else to
trigger here.
-}
refetch : Shared.Model -> Model -> ( Model, Effect Msg )
refetch shared model =
    case RellmServers.rellmServerForHost shared.accounts.servers model.targetHost of
        Just _ ->
            ( { model | fetchedAccountId = currentAccountId shared model }
            , Posts.fetchPost shared.accounts (maybeAccountServerFor shared model) model.postId
                |> Task.attempt GotPost
                |> Effect.fromCmd
            )

        Nothing ->
            ( model, Effect.none )


{-| Fully applies a just-fetched/-saved `post` to this page -- the one place
any save (or refetch) completion should route through so the page's own
`postDetailView` reflects it immediately rather than only after a reload.
Handles both halves of that: sets `model.postStatus` itself, _and_ pushes
`post` into `Shared.StarredPanel`'s cache (see its `PostUpdated`/
`freshestPost`) so that cache -- which `postDetailView` prefers over
whatever's passed to it whenever this Post has ever been starred -- can't go
on serving a stale copy back out from under this update.

Used by both `GotPost` (the initial load, and content-edit saves via
`refetch`) and `GotVisibilitySaveResult`; any future per-field edit on this
page (mirroring `VisibilitySaveClicked`'s `Posts.updatePost` pattern) should
route its own successful save through this too rather than hand-rolling the
same two updates again.

-}
applyUpdatedPost : Model -> Post -> ( Model, Effect Msg )
applyUpdatedPost model post =
    ( { model | postStatus = PostLoaded post }
    , Effect.fromShared (Shared.StarredPanelMsg (StarredPanel.PostUpdated model.targetHost post))
    )


{-| Turns a `Maybe AccountsPanel.Msg` (as returned by `Components.PostCard`/
`Components.PostReplies`' requests, if a token refresh happened) into an
`Effect` to forward it, `Effect.none` otherwise.
-}
accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect Msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none



-- VIEW


{-| Just the body content -- the calling page wraps this in `UI.layout`/its own title (via
`titleFor`), same split as `Components.Pages.EventsPage.view`/etc.
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
            case model.postStatus of
                LoadingPost ->
                    p [ class "post-loading" ] [ text "Loading…" ]

                PostFailed ->
                    p [ class "post-error" ] [ text ("Couldn't load Post " ++ model.postId ++ "@" ++ model.targetHost ++ ". Maybe it doesn't exist, or maybe you need to be logged in?") ]

                PostLoaded post ->
                    div []
                        [ postDetailView shared model post
                        , postActionsView shared model post
                        , repliesView shared model
                        ]
        )


postDetailView : Shared.Model -> Model -> Post -> Html Msg
postDetailView shared model post =
    let
        displayPost : Post
        displayPost =
            StarredPanel.freshestPost model.targetHost post shared.panels.starredPanel

        starred : Bool
        starred =
            StarredPanel.isStarred model.targetHost displayPost shared.panels.starredPanel

        onStarClicked : Maybe Msg
        onStarClicked =
            StarredPanel.toggleStarMsg shared.accounts model.targetHost displayPost
                |> Maybe.map (Shared.StarredPanelMsg >> SharedMsg)

        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost shared.accounts.servers model.targetHost

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost

        onMediaClicked : String -> Msg
        onMediaClicked mediaId =
            MediaClicked displayPost mediaId

        onMediaPlayClicked : String -> Msg
        onMediaPlayClicked mediaId =
            SharedMsg (Shared.MediaRendererMsg (MediaRenderer.PlayClicked mediaId))

        -- `Nothing` when the viewer has no image-capable `AIModel` at all -- see
        -- `Posts.generateMediaButton`'s own doc on why this decision lives at the call site rather
        -- than inside `Components.Posts`.
        onGenerateMediaClicked : Maybe Msg
        onGenerateMediaClicked =
            case maybeAccount of
                Just account ->
                    if List.any AIProviders.hasAnyImageCapability account.aiModels then
                        Just (GenerateMediaClicked displayPost)

                    else
                        Nothing

                Nothing ->
                    Nothing
    in
    Posts.postDetail shared.time
        shared.basePath
        shared.accounts.mainFrontendHost
        model.targetHost
        maybeServer
        maybeAccount
        onMediaClicked
        shared.mediaRenderer
        onMediaPlayClicked
        False
        (MediaEditClicked displayPost)
        onGenerateMediaClicked
        (MediaLayoutChanged displayPost)
        starred
        onStarClicked
        (EditClicked post)
        (visibilityView maybeAccount model.visibilityEdit displayPost)
        (moderationView maybeAccount model.moderationEdit displayPost)
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
            SharedMsg (Shared.RequestDelete (Shared.ConfirmPostSyncDestinationDelete displayPost destinationId destinationLabel model.targetHost))
        )
        Nothing
        displayPost


{-| The visibility segment of `postDetail`'s meta line (see `postDetail`'s own
`visibilityView` parameter) -- plain text (`Posts.postVisibilityText`) plus an
Edit button when `model.visibilityEdit == Nothing`, shown only to `post`'s own
author (mirrors `Posts.editButton`'s own `isAuthor` gate, matching
`backend/src/rpcs/posts/update_post.rs`'s `self_update` check); an inline
`<select>` + Save/Cancel once editing, with its options narrowed to whatever
`maybeAccount` is actually allowed to pick (`Posts.allowedVisibilities`,
mirroring that same file's `PUBLISHPOSTS*`/`PUBLISHEVENTS*` permission check),
plus a `setsPublishedAtPermanently` warning below the controls when relevant.
-}
visibilityView : Maybe RellmAccount -> Maybe VisibilityEdit -> Post -> Html Msg
visibilityView maybeAccount maybeEdit post =
    case ( maybeEdit, maybeAccount ) of
        ( Just edit, Just account ) ->
            let
                options : List Visibility
                options =
                    Posts.allowedVisibilities account.permissions post.context post.visibility
            in
            span [ class "post-visibility-edit" ]
                [ text " · "
                , span [ class "post-visibility-edit-controls" ]
                    [ select [ onInput VisibilityChanged ]
                        (options
                            |> List.map
                                (\visibility ->
                                    option
                                        [ value (Posts.visibilityText visibility)
                                        , selected (edit.pending == visibility)
                                        ]
                                        [ text (Posts.visibilityText visibility) ]
                                )
                        )
                    , button
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
                    , case edit.status of
                        SubmitFailed err ->
                            span [ class "post-visibility-error" ] [ text err ]

                        _ ->
                            text ""
                    ]
                , if setsPublishedAtPermanently post edit.pending then
                    span [ class "post-visibility-publish-warning" ]
                        [ text "Saving will permanently set this post's publication time." ]

                  else
                    text ""
                ]

        _ ->
            if Posts.showPostVisibility maybeAccount post then
                span [ class "post-visibility-display" ]
                    [ text (" · " ++ Posts.postVisibilityText post)
                    , case maybeAccount of
                        Just account ->
                            if Posts.isAuthor account post then
                                button [ class "post-visibility-edit-button", onClick (VisibilityEditClicked post) ] [ text "Edit Visibility" ]

                            else
                                text ""

                        Nothing ->
                            text ""
                    ]

            else
                text ""


{-| The moderation-status segment of `postDetail`'s meta line (see
`postDetail`'s own `moderationView` parameter) -- mirrors `visibilityView`
exactly, just for `Moderation` instead of `Visibility`, shown only to an
Admin or a `MODERATEPOSTS` holder (unlike `visibilityView`, not gated on
authorship), and its own "Edit" button reads "Moderate" instead, per this
feature's own request.
-}
moderationView : Maybe RellmAccount -> Maybe ModerationEdit -> Post -> Html Msg
moderationView maybeAccount maybeEdit post =
    case maybeAccount of
        Nothing ->
            text ""

        Just account ->
            if not (List.member ADMIN account.permissions || List.member MODERATEPOSTS account.permissions) then
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
                                , onClick (ModerationSaveClicked post)
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
                            , button [ class "post-moderation-edit-button", onClick (ModerationEditClicked post) ] [ text "Moderate" ]
                            ]


{-| A Reply button, shown to any signed-in account with `REPLYTOPOSTS`, and
(for the post's own owner) a Delete button, using the shared "are you sure?"
dialog via `DeleteClicked`/`Shared.ConfirmPostDelete` -- opens the shared
Markdown editor panel (see `Shared.MarkdownPanel`), targeting this Post
(`ReplyClicked`). The Edit button lives in `Posts.postDetail` itself now (see
`postDetailView`), below its Markdown content.
-}
postActionsView : Shared.Model -> Model -> Post -> Html Msg
postActionsView shared model post =
    case RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost of
        Just account ->
            div [ class "post-actions" ]
                [ if List.member REPLYTOPOSTS account.permissions then
                    button [ class "post-reply-button", onClick (ReplyClicked post) ] [ text "Reply" ]

                  else
                    text ""
                , if Posts.isAuthor account post then
                    button [ class "post-delete-button", onClick (DeleteClicked post) ] [ text "Delete" ]

                  else
                    text ""
                ]

        Nothing ->
            text ""


{-| This post's whole threaded-replies tree (see `Components.PostReplies`) --
updates whenever a new reply is posted through the Reply button here (see
`refetch`) or a reply's own subtree is expanded.
-}
repliesView : Shared.Model -> Model -> Html Msg
repliesView shared model =
    case model.repliesModel of
        Just repliesModel ->
            PostReplies.view
                { basePath = shared.basePath
                , viewingServerHost = shared.accounts.mainFrontendHost
                , postServerHost = model.targetHost
                , maybeServer = RellmServers.rellmServerForHost shared.accounts.servers model.targetHost
                , maybeAccount = RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost
                , onMediaClicked = MediaClicked
                , mediaPlayState = shared.mediaRenderer
                , onMediaPlayClicked = \mediaId -> SharedMsg (Shared.MediaRendererMsg (MediaRenderer.PlayClicked mediaId))
                , onReplyClicked = ReplyClicked
                , toMsg = PostRepliesMsg
                }
                repliesModel

        Nothing ->
            text ""


{-| Just the subtitle -- the loaded Post's own title, or "Post &lt;id&gt;" before it's loaded --
for the calling page's own `UI.pageTitle`. Mirrors `Components.Pages.UserProfilePage.titleFor`.
-}
titleFor : Model -> String
titleFor model =
    case model.postStatus of
        PostLoaded post ->
            Posts.postTitleText post

        _ ->
            "Post " ++ model.postId


{-| `model.targetHost` paired with whatever account (if any) is currently
signed in on it -- what `Components.PostCard`/`Components.PostReplies`'
`Model`/`Msg`-free fetch helpers need instead of a live `Server`/`Account`.
-}
maybeAccountServerFor : Shared.Model -> Model -> AccountsPanel.MaybeAccountServer
maybeAccountServerFor shared model =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost |> Maybe.map .userId
    , model.targetHost
    )


{-| The `RellmAccounts.rellmAccountId` of whichever account is currently signed in
on `model.targetHost` (the Post's own server), if any -- compared against
`model.fetchedAccountId` by `update`'s `SharedMsg` branch to notice an
`AccountsPanel.ToggleAccountEnabled`/`ToggleServerEnabled` changed who's
signed in here (i.e. logging in/out of that account on that server), and
`refetch` accordingly.
-}
currentAccountId : Shared.Model -> Model -> Maybe String
currentAccountId shared model =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost
        |> Maybe.map RellmAccounts.rellmAccountId


{-| The connected `Server`/signed-in `Account` for `model.targetHost`, if
both exist -- what `VisibilitySaveClicked` needs to actually submit its
`Posts.updatePost` task. Mirrors `Components.UserProfilePage.serverAndAccount`.
-}
serverAndAccount : Shared.Model -> Model -> Maybe ( RellmServer, RellmAccount )
serverAndAccount shared model =
    Maybe.map2 Tuple.pair
        (RellmServers.rellmServerForHost shared.accounts.servers model.targetHost)
        (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.targetHost)


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page
(see `Main.notifyPageOfSharedMsg`) into `update`'s `SharedMsg` branch, without
exposing the `SharedMsg` constructor itself (and thus every other constructor
of this otherwise-opaque `Msg`) outside this module.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


{-| Whether saving `pending` for `post` would permanently set its
`publishedAt` -- mirrors `backend/src/rpcs/posts/update_post.rs`'s own check,
which fills in `published_at` (once, irreversibly) the first time a post
becomes `SERVERPUBLIC`/`GLOBALPUBLIC` while it's still unset.
-}
setsPublishedAtPermanently : Post -> Visibility -> Bool
setsPublishedAtPermanently post pending =
    post.publishedAt
        == Nothing
        && (pending == SERVERPUBLIC || pending == GLOBALPUBLIC)
