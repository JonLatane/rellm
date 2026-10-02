module Components.Mastodon.MastodonUserProfilePage exposing (Model, Msg, fromShared, init, subscriptions, title, update, view)

{-| A single Mastodon account's profile, read-only -- avatar/display name/bio/follower-and-following
counts, plus that account's own authored posts (embedding `Components.Pages.PostsPage`, scoped to
just this account via its `MastodonAccountFeed` `FeedSource`). No follow/moderation/permissions/sync
affordances, no Events/Sync Sources/Sync Destinations/AI Providers sections -- none of that
makes sense for an account Rellm doesn't own, mirroring `Components.Mastodon.MastodonPostPage`'s own
read-only scope one level up (a whole profile instead of a single post).

Routed to from `Pages.UsernameOrCustomTab_`/`Pages.User.UserId_` once
`Components.Users.parseFederatedUserId` recognizes the route's host as Mastodon's -- see that
function's own doc, and `Components.Bluesky.BlueskyUserProfilePage` for the AT Protocol counterpart.
Followers/following lists live at their own routes (`/:username@host/followers`/`/following`), backed
by `Components.Pages.MastodonUsersPage` -- see `Components.Users.followersHref`/`followingHref`.

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
import Shared.Federation.Mastodon as Mastodon
import Task


type alias Model =
    { instanceHost : String
    , username : String
    , profileStatus : ProfileStatus
    , posts : Maybe PostsPage.Model
    , navKey : Browser.Navigation.Key
    , path : String
    , query : Dict String String
    }


type ProfileStatus
    = LoadingProfile
    | ProfileLoaded Mastodon.Account
    | ProfileFailed


type Msg
    = GotAccount (Result Http.Error Mastodon.Account)
    | PostsMsg PostsPage.Msg
    | SharedMsgReceived Shared.Msg


{-| `instanceHost`/`username` come straight from `Components.Users.parseFederatedUserId`'s
`MastodonUserId` -- see that type's own doc on how they're picked back apart from the route.
`navKey`/`path`/`query` are threaded straight through to the embedded `PostsPage`, once
`Mastodon.lookupAccount` resolves an `Account` to actually scope it to (see `update`) -- mirrors
`Components.Pages.UserProfilePage`'s own deferred `PostsPage.init` (also only called once its own
`Resolver` finishes).
-}
init : String -> String -> Browser.Navigation.Key -> String -> Dict String String -> ( Model, Effect Msg )
init instanceHost username navKey path query =
    ( { instanceHost = instanceHost
      , username = username
      , profileStatus = LoadingProfile
      , posts = Nothing
      , navKey = navKey
      , path = path
      , query = query
      }
    , Mastodon.lookupAccount instanceHost username
        |> Task.attempt GotAccount
        |> Effect.fromCmd
    )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotAccount (Ok account) ->
            let
                ( postsModel, postsEffect ) =
                    PostsPage.init shared
                        Nothing
                        model.navKey
                        model.path
                        model.query
                        True
                        Nothing
                        (Just (PostsPage.MastodonAccountFeed { instanceHost = model.instanceHost, accountId = account.id, username = account.username }))
            in
            ( { model | profileStatus = ProfileLoaded account, posts = Just postsModel }
            , Effect.map PostsMsg postsEffect
            )

        GotAccount (Err _) ->
            ( { model | profileStatus = ProfileFailed }, Effect.none )

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
            -- The embedded `PostsPage`, once it exists, already re-emits `Effect.fromShared subMsg`
            -- as part of its own `SharedMsg` handling (see that module's own doc) -- forwarding
            -- through it there is enough. Before it exists (`model.posts == Nothing`, still waiting
            -- on `GotAccount`), there's nothing to forward through, so this does it directly --
            -- mirrors `Pages.Post.PostId_`'s own `SharedMsgReceived` handling for the same reason.
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
            p [ class "post-error" ] [ text "Couldn't load this profile. It may not exist, or that instance may be unreachable." ]

        ProfileLoaded account ->
            let
                handle : String
                handle =
                    account.username ++ "@" ++ model.instanceHost
            in
            div [ class "profile-detail" ]
                [ div [ class "federated-service-label" ] [ text "⇄ Mastodon" ]
                , div [ class "profile-header-row" ]
                    [ div [ class "profile-header" ]
                        [ Authors.avatar handle account.avatarUrl
                        , div [ class "profile-header-names" ]
                            [ h1 [ class "profile-username" ] [ text ("@" ++ handle) ]
                            , case account.displayName of
                                Just displayName ->
                                    div [ class "profile-real-name-display" ] [ span [ class "profile-real-name" ] [ text displayName ] ]

                                Nothing ->
                                    text ""
                            ]
                        ]
                    ]
                , div [ class "profile-counts" ]
                    [ profileCountView Nothing "Posts" account.statusesCount
                    , profileCountView (Just (Users.followersHref "" shared.accounts.mainFrontendHost ("mastodon:" ++ model.instanceHost) account.username)) "Followers" account.followersCount
                    , profileCountView (Just (Users.followingHref "" shared.accounts.mainFrontendHost ("mastodon:" ++ model.instanceHost) account.username)) "Following" account.followingCount
                    ]
                , case account.note of
                    Just note ->
                        div [ class "profile-bio-section" ] [ Markdown.view [ class "profile-bio" ] note ]

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


{-| Just the subtitle -- the loaded account's own handle, or "Profile" before it's loaded -- for the
calling page's own `UI.pageTitle`. Mirrors `Components.Mastodon.MastodonPostPage.title`.
-}
title : Model -> String
title model =
    case model.profileStatus of
        ProfileLoaded account ->
            "@" ++ account.username ++ "@" ++ model.instanceHost

        _ ->
            "Profile"


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
