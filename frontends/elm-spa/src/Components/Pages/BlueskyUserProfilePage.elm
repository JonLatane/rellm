module Components.Pages.BlueskyUserProfilePage exposing (Model, Msg, fromShared, init, subscriptions, title, update, view)

{-| A single Bluesky account's profile, read-only -- avatar/display name/bio/follower-and-following
counts, plus that account's own authored posts (embedding `Components.Pages.PostsPage`, scoped to
just this account via its `BlueskyAuthorFeed` `FeedSource`). No follow/moderation/permissions/sync
affordances, no Events/Sync Sources/Sync Destinations/AI Providers sections -- none of that
makes sense for an account Rellm doesn't own, mirroring `Components.Pages.BlueskyPostPage`'s own
read-only scope one level up (a whole profile instead of a single post).

Routed to from `Pages.UsernameOrCustomTab_`/`Pages.User.UserId_` once
`Components.Users.parseFederatedUserId` recognizes the route's host as Bluesky's -- see that
function's own doc, and `Components.Pages.MastodonUserProfilePage` for the ActivityPub counterpart.
Followers/following lists live at their own routes (`/:handle@bluesky:.../followers`/`/following`),
backed by `Components.Pages.BlueskyUsersPage` -- see `Components.Users.followersHref`/`followingHref`.

Fails outright (mirrors `Components.Pages.BlueskyPostPage.init`) if no Bluesky account is connected at
all -- AT Protocol has no anonymous access to anything, so there's no way to view _any_ profile
without at least one connected account to authenticate the request with.

-}

import Browser.Navigation
import Components.Authors as Authors
import Components.Markdown as Markdown
import Components.Pages.PostsPage as PostsPage
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Html exposing (Html, a, div, h1, h3, p, span, text)
import Html.Attributes exposing (class, href)
import Http
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.Federation.Bluesky as Bluesky
import Task


type alias Model =
    { handle : String
    , profileStatus : ProfileStatus
    , posts : Maybe PostsPage.Model
    , navKey : Browser.Navigation.Key
    , path : String
    , query : Dict String String
    }


type ProfileStatus
    = LoadingProfile
    | ProfileLoaded Bluesky.ActorProfile
    | ProfileFailed


type Msg
    = GotProfile (Result Http.Error ( BlueskyAccount, Bluesky.ActorProfile ))
    | PostsMsg PostsPage.Msg
    | SharedMsgReceived Shared.Msg


{-| `handle` comes straight from `Components.Users.parseFederatedUserId`'s `BlueskyUserId` -- see
that type's own doc on how it's picked back apart from the route. `navKey`/`path`/`query` are
threaded straight through to the embedded `PostsPage`, once `Bluesky.fetchActorProfile` resolves (see
`update`) -- mirrors `Components.Pages.MastodonUserProfilePage.init` exactly, just authenticated
against whichever connected Bluesky account comes first (see this module's own doc on why one has to
be connected at all).
-}
init : Shared.Model -> String -> Browser.Navigation.Key -> String -> Dict String String -> ( Model, Effect Msg )
init shared handle navKey path query =
    let
        fetchTask : Task.Task Http.Error ( BlueskyAccount, Bluesky.ActorProfile )
        fetchTask =
            case shared.accounts.blueskyAccounts of
                account :: _ ->
                    BlueskyAccounts.performWithBlueskyAccount account (\accessToken -> Bluesky.fetchActorProfile accessToken handle)

                [] ->
                    Task.fail (Http.BadStatus 401)
    in
    ( { handle = handle
      , profileStatus = LoadingProfile
      , posts = Nothing
      , navKey = navKey
      , path = path
      , query = query
      }
    , fetchTask
        |> Task.attempt GotProfile
        |> Effect.fromCmd
    )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotProfile (Ok ( account, profile )) ->
            let
                ( postsModel, postsEffect ) =
                    PostsPage.init shared
                        Nothing
                        model.navKey
                        model.path
                        model.query
                        True
                        Nothing
                        (Just (PostsPage.BlueskyAuthorFeed { handle = model.handle }))
            in
            ( { model | profileStatus = ProfileLoaded profile, posts = Just postsModel }
            , Effect.batch
                [ Effect.map PostsMsg postsEffect
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.BlueskyAccountRefreshed account))
                ]
            )

        GotProfile (Err err) ->
            ( { model | profileStatus = ProfileFailed }
            , case shared.accounts.blueskyAccounts of
                account :: _ ->
                    if BlueskyAccounts.isReauthError err then
                        Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.MarkBlueskyAccountNeedsReauth account.handle))

                    else
                        Effect.none

                [] ->
                    Effect.none
            )

        PostsMsg subMsg ->
            case model.posts of
                Just postsModel ->
                    let
                        ( newPostsModel, postsEffect ) =
                            PostsPage.update shared subMsg postsModel
                    in
                    ( { model | posts = Just newPostsModel }, Effect.map PostsMsg postsEffect )

                Nothing ->
                    ( model, Effect.none )

        SharedMsgReceived subMsg ->
            -- See `Components.Pages.MastodonUserProfilePage.update`'s identical `SharedMsgReceived`
            -- doc -- the embedded `PostsPage` re-emits `Effect.fromShared subMsg` on its own once it
            -- exists; before that, this does it directly.
            case model.posts of
                Just postsModel ->
                    let
                        ( newPostsModel, postsEffect ) =
                            PostsPage.update shared (PostsPage.fromShared subMsg) postsModel
                    in
                    ( { model | posts = Just newPostsModel }, Effect.map PostsMsg postsEffect )

                Nothing ->
                    ( model, Effect.fromShared subMsg )


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.posts of
        Just postsModel ->
            Sub.map PostsMsg (PostsPage.subscriptions postsModel)

        Nothing ->
            Sub.none


view : Shared.Model -> Model -> Html Msg
view shared model =
    case model.profileStatus of
        LoadingProfile ->
            p [ class "post-loading" ] [ text "Loading…" ]

        ProfileFailed ->
            p [ class "post-error" ]
                [ text
                    (if List.isEmpty shared.accounts.blueskyAccounts then
                        "Connect a Bluesky account to view this profile."

                     else
                        "Couldn't load this profile. It may not exist, or the account may be unreachable."
                    )
                ]

        ProfileLoaded profile ->
            div [ class "profile-detail" ]
                [ div [ class "federated-service-label" ] [ text "⇄ Bluesky" ]
                , div [ class "profile-header-row" ]
                    [ div [ class "profile-header" ]
                        [ Authors.avatar profile.handle profile.avatarUrl
                        , div [ class "profile-header-names" ]
                            [ h1 [ class "profile-username" ] [ text ("@" ++ profile.handle) ]
                            , case profile.displayName of
                                Just displayName ->
                                    div [ class "profile-real-name-display" ] [ span [ class "profile-real-name" ] [ text displayName ] ]

                                Nothing ->
                                    text ""
                            ]
                        ]
                    ]
                , div [ class "profile-counts" ]
                    [ profileCountView Nothing "Posts" profile.postsCount
                    , profileCountView (Just (Users.followersHref "" shared.accounts.mainFrontendHost ("bluesky:" ++ profile.handle) profile.handle)) "Followers" profile.followersCount
                    , profileCountView (Just (Users.followingHref "" shared.accounts.mainFrontendHost ("bluesky:" ++ profile.handle) profile.handle)) "Following" profile.followsCount
                    ]
                , case profile.description of
                    Just description ->
                        div [ class "profile-bio-section" ] [ Markdown.view [ class "profile-bio" ] description ]

                    Nothing ->
                        text ""
                , h3 [] [ text "Recent Posts" ]
                , case model.posts of
                    Just postsModel ->
                        Html.map PostsMsg (PostsPage.view shared False False postsModel)

                    Nothing ->
                        text ""
                ]


{-| Mirrors `Components.Pages.UserProfilePage.profileCountView` exactly (not exposed there, so
duplicated here rather than imported) -- the same "big number, small label below" `.profile-count`
styling every profile page's follower/following/post counts use.
-}
profileCountView : Maybe String -> String -> Int -> Html Msg
profileCountView maybeHref label count =
    let
        content : List (Html Msg)
        content =
            [ div [ class "profile-count-value" ] [ text (String.fromInt count) ]
            , div [ class "profile-count-label" ] [ text label ]
            ]
    in
    case maybeHref of
        Just linkHref ->
            a [ class "profile-count", href linkHref ] content

        Nothing ->
            div [ class "profile-count" ] content


{-| Just the subtitle -- the loaded profile's own handle, or "Profile" before it's loaded -- for the
calling page's own `UI.pageTitle`. Mirrors `Components.Pages.BlueskyPostPage.title`.
-}
title : Model -> String
title model =
    case model.profileStatus of
        ProfileLoaded profile ->
            "@" ++ profile.handle

        _ ->
            "Profile"


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
