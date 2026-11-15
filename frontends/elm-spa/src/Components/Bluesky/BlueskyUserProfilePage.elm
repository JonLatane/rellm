module Components.Bluesky.BlueskyUserProfilePage exposing (Model, Msg, fromShared, init, subscriptions, title, update, view)

{-| A single Bluesky account's profile -- avatar/display name/bio/follower-and-following
counts, plus that account's own authored posts (embedding `Components.Pages.PostsPage`, scoped to
just this account via its `BlueskyAuthorFeed` `FeedSource`). When a Bluesky account is connected (see
`Shared.Federation.Actions`), it also offers Follow/Unfollow on someone else's profile and "Edit Profile"
(display name and bio) on the connected account's own. No moderation/permissions/sync
affordances, no Events/Sync Sources/Sync Destinations/AI Providers sections -- none of that
makes sense for an account Rellm doesn't own, mirroring `Components.Bluesky.BlueskyPostPage`'s own
read-only scope one level up (a whole profile instead of a single post).

Routed to from `Pages.UsernameOrCustomTab_`/`Pages.User.UserId_` once
`Components.Users.parseFederatedUserId` recognizes the route's host as Bluesky's -- see that
function's own doc, and `Components.Mastodon.MastodonUserProfilePage` for the ActivityPub counterpart.
Followers/following lists live at their own routes (`/:handle@bluesky:.../followers`/`/following`),
backed by `Components.Pages.BlueskyUsersPage` -- see `Components.Users.followersHref`/`followingHref`.

Reads as the active connected account (`AccountsPanel.activeBlueskyAccount`) if there is one, and
anonymously otherwise (`AccountsPanel.browsedBlueskyAuth` -- a profile is public data an AppView serves
with no login), mirroring `Components.Bluesky.BlueskyPostPage.init`.

-}

import Browser.Navigation
import Components.Authors as Authors
import Components.Markdown as Markdown
import Components.Pages.PostsPage as PostsPage
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Html exposing (Html, a, button, div, h1, h3, input, p, span, text, textarea)
import Html.Attributes exposing (class, disabled, href, placeholder, rows, value)
import Html.Events exposing (onClick, onInput)
import Http
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.Federation.Actions as Actions
import Shared.Federation.Bluesky as Bluesky
import Task
import UI.Classes exposing (classes)


type alias Model =
    { handle : String
    , profileStatus : ProfileStatus
    , posts : Maybe PostsPage.Model
    , navKey : Browser.Navigation.Key
    , path : String
    , query : Dict String String

    -- Whether the connected account follows this profile (`Nothing` until known, or when there's no
    -- connected account / this is its own profile). It's the state *for `followFor`* -- the handle of the account
    -- acting when it was fetched: switching accounts clears it and fetches again (`syncFollow`), and replies
    -- from the previous account are dropped, so one account's follow record is never used as another's.
    , followFor : Maybe String
    , followState : Maybe Bluesky.FollowState
    , followBusy : Bool

    -- `Just` while the connected account's own profile is being edited.
    , profileEdit : Maybe ProfileEdit
    , actionError : Maybe String
    }


type alias ProfileEdit =
    { displayName : String
    , description : String

    -- The record the values above were read from -- `Nothing` while still being fetched.
    , record : Maybe Bluesky.OwnProfileRecord
    , saving : Bool
    }


type ProfileStatus
    = LoadingProfile
    | ProfileLoaded Bluesky.ActorProfile
    | ProfileFailed


type Msg
    = GotProfile ( String, String ) (Result Http.Error ( Maybe BlueskyAccount, Bluesky.ActorProfile ))
    | PostsMsg PostsPage.Msg
    | SharedMsgReceived Shared.Msg
    | GotFollowState String (Result Http.Error ( Maybe AccountsPanel.Msg, Bluesky.FollowState ))
    | FollowClicked
    | GotFollowResult String (Result Http.Error ( Maybe AccountsPanel.Msg, Bluesky.FollowState ))
    | EditProfileClicked
    | GotOwnProfile (Result Http.Error ( Maybe AccountsPanel.Msg, Bluesky.OwnProfileRecord ))
    | DisplayNameChanged String
    | DescriptionChanged String
    | SaveProfileClicked
    | CancelProfileClicked
    | GotProfileSaved (Result Http.Error (Maybe AccountsPanel.Msg))
    | GotRefreshedProfile (Result Http.Error ( BlueskyAccount, Bluesky.ActorProfile ))


{-| `handle` comes straight from `Components.Users.parseFederatedUserId`'s `BlueskyUserId` -- see
that type's own doc on how it's picked back apart from the route. `navKey`/`path`/`query` are
threaded straight through to the embedded `PostsPage`, once `Bluesky.fetchActorProfile` resolves (see
`update`) -- mirrors `Components.Mastodon.MastodonUserProfilePage.init` exactly, just authenticated
against whichever connected Bluesky account comes first (see this module's own doc on why one has to
be connected at all).
-}
init : Shared.Model -> String -> Browser.Navigation.Key -> String -> Dict String String -> ( Model, Effect Msg )
init shared handle navKey path query =
    let
        -- Handle + refresh token this fetch starts with, for `MarkBlueskyAccountNeedsReauth`.
        actingAccount : ( String, String )
        actingAccount =
            AccountsPanel.activeBlueskyAccount shared.accounts
                |> Maybe.map (\a -> ( a.handle, a.refreshToken ))
                |> Maybe.withDefault ( "", "" )

        fetchTask : Task.Task Http.Error ( Maybe BlueskyAccount, Bluesky.ActorProfile )
        fetchTask =
            case AccountsPanel.activeBlueskyAccount shared.accounts of
                Just account ->
                    BlueskyAccounts.performWithBlueskyAccount account (\auth -> Bluesky.fetchActorProfile auth handle)
                        |> Task.map (Tuple.mapFirst Just)

                Nothing ->
                    -- No connected account: a profile is public, so read it anonymously from the
                    -- browsed AppView.
                    Bluesky.fetchActorProfile (AccountsPanel.browsedBlueskyAuth shared.accounts) handle
                        |> Task.map (Tuple.pair Nothing)
    in
    ( { handle = handle
      , profileStatus = LoadingProfile
      , posts = Nothing
      , navKey = navKey
      , path = path
      , query = query
      , followFor = Nothing
      , followState = Nothing
      , followBusy = False
      , profileEdit = Nothing
      , actionError = Nothing
      }
    , fetchTask
        |> Task.attempt (GotProfile actingAccount)
        |> Effect.fromCmd
    )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    updateInner shared msg model |> syncFollow shared


{-| Keeps the follow state for the account that is acting *now*: when that isn't the one it was fetched for
(another account was enabled, or the profile just loaded), it's cleared and fetched for the new one. Nothing for
your own profile or with no account.
-}
syncFollow : Shared.Model -> ( Model, Effect Msg ) -> ( Model, Effect Msg )
syncFollow shared ( model, effect ) =
    case model.profileStatus of
        ProfileLoaded profile ->
            let
                acting : Maybe BlueskyAccount
                acting =
                    AccountsPanel.activeBlueskyAccount shared.accounts
                        |> Maybe.filter (\account -> not (Actions.isOwnBlueskyProfile account profile.handle))

                wanted : Maybe String
                wanted =
                    Maybe.map .handle acting
            in
            if wanted == model.followFor then
                ( model, effect )

            else
                ( { model | followFor = wanted, followState = Nothing, followBusy = False }
                , Effect.batch
                    [ effect
                    , case acting of
                        Just account ->
                            Actions.fetchBlueskyFollowState account profile.handle
                                |> Task.attempt (GotFollowState account.handle)
                                |> Effect.fromCmd

                        Nothing ->
                            Effect.none
                    ]
                )

        _ ->
            ( model, effect )


updateInner : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared msg model =
    case msg of
        GotProfile _ (Ok ( account, profile )) ->
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
                (Effect.map PostsMsg postsEffect
                    :: (case account of
                            Just connectedAccount ->
                                [ Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.BlueskyAccountRefreshed connectedAccount)) ]

                            Nothing ->
                                []
                       )
                )
            )

        GotProfile ( accountHandle, refreshToken ) (Err err) ->
            ( { model | profileStatus = ProfileFailed }
            , if BlueskyAccounts.isReauthError err && accountHandle /= "" then
                Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.MarkBlueskyAccountNeedsReauth accountHandle refreshToken))

              else
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

        GotFollowState accountHandle (Ok ( maybeAccountsPanelMsg, state )) ->
            if Just accountHandle == model.followFor then
                ( { model | followState = Just state }, forwardRotated maybeAccountsPanelMsg )

            else
                ( model, forwardRotated maybeAccountsPanelMsg )

        GotFollowState _ (Err _) ->
            -- Not being able to tell just means no button.
            ( model, Effect.none )

        FollowClicked ->
            case ( AccountsPanel.activeBlueskyAccount shared.accounts, model.followState ) of
                ( Just acting, Just state ) ->
                    if model.followFor /= Just acting.handle then
                        ( model, Effect.none )

                    else
                        ( { model | followBusy = True, actionError = Nothing }
                        , Actions.setBlueskyFollowing (state.followUri == Nothing) acting state
                            |> Task.attempt (GotFollowResult acting.handle)
                            |> Effect.fromCmd
                        )

                _ ->
                    ( model, Effect.none )

        GotFollowResult accountHandle (Ok ( maybeAccountsPanelMsg, state )) ->
            if Just accountHandle == model.followFor then
                ( { model | followState = Just state, followBusy = False }, forwardRotated maybeAccountsPanelMsg )

            else
                ( model, forwardRotated maybeAccountsPanelMsg )

        GotFollowResult accountHandle (Err err) ->
            if Just accountHandle == model.followFor then
                ( { model | followBusy = False, actionError = Just (Actions.writeErrorText err) }, Effect.none )

            else
                ( model, Effect.none )

        EditProfileClicked ->
            case AccountsPanel.activeBlueskyAccount shared.accounts of
                Just acting ->
                    ( { model | profileEdit = Just { displayName = "", description = "", record = Nothing, saving = False }, actionError = Nothing }
                    , Actions.fetchBlueskyOwnProfile acting
                        |> Task.attempt GotOwnProfile
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        GotOwnProfile (Ok ( maybeAccountsPanelMsg, record )) ->
            ( { model
                | profileEdit =
                    model.profileEdit
                        |> Maybe.map (\edit -> { edit | displayName = record.displayName, description = record.description, record = Just record })
              }
            , forwardRotated maybeAccountsPanelMsg
            )

        GotOwnProfile (Err err) ->
            ( { model | profileEdit = Nothing, actionError = Just (Actions.writeErrorText err) }, Effect.none )

        DisplayNameChanged text ->
            ( { model | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | displayName = text }) }, Effect.none )

        DescriptionChanged text ->
            ( { model | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | description = text }) }, Effect.none )

        SaveProfileClicked ->
            case ( model.profileEdit, AccountsPanel.activeBlueskyAccount shared.accounts ) of
                ( Just ({ record } as edit), Just acting ) ->
                    case record of
                        Just loadedRecord ->
                            ( { model | profileEdit = Just { edit | saving = True }, actionError = Nothing }
                            , Actions.updateBlueskyOwnProfile acting loadedRecord { displayName = edit.displayName, description = edit.description }
                                |> Task.attempt GotProfileSaved
                                |> Effect.fromCmd
                            )

                        Nothing ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        CancelProfileClicked ->
            ( { model | profileEdit = Nothing, actionError = Nothing }, Effect.none )

        GotProfileSaved (Ok maybeAccountsPanelMsg) ->
            ( { model | profileEdit = Nothing }
            , Effect.batch
                [ forwardRotated maybeAccountsPanelMsg
                , case AccountsPanel.activeBlueskyAccount shared.accounts of
                    Just acting ->
                        BlueskyAccounts.performWithBlueskyAccount acting (\auth -> Bluesky.fetchActorProfile auth model.handle)
                            |> Task.attempt GotRefreshedProfile
                            |> Effect.fromCmd

                    Nothing ->
                        Effect.none
                ]
            )

        GotProfileSaved (Err err) ->
            ( { model
                | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | saving = False })
                , actionError = Just (Actions.writeErrorText err)
              }
            , Effect.none
            )

        GotRefreshedProfile (Ok ( account, profile )) ->
            -- Just the profile card -- the embedded posts list is left alone.
            ( { model | profileStatus = ProfileLoaded profile }
            , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.BlueskyAccountRefreshed account))
            )

        GotRefreshedProfile (Err _) ->
            ( model, Effect.none )

        SharedMsgReceived subMsg ->
            -- See `Components.Mastodon.MastodonUserProfilePage.update`'s identical `SharedMsgReceived`
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


forwardRotated : Maybe AccountsPanel.Msg -> Effect Msg
forwardRotated maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


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
                    "Couldn't load this profile. It may not exist, or the account may be unreachable."
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
                , profileActionsView shared model profile
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


{-| Follow/Unfollow on someone else's profile, or "Edit Profile" (display name and bio) on the connected
account's own -- nothing at all without a connected Bluesky account.
-}
profileActionsView : Shared.Model -> Model -> Bluesky.ActorProfile -> Html Msg
profileActionsView shared model profile =
    case AccountsPanel.activeBlueskyAccount shared.accounts of
        Nothing ->
            text ""

        Just acting ->
            div [ class "profile-actions" ]
                [ if Actions.isOwnBlueskyProfile acting profile.handle then
                    case model.profileEdit of
                        Nothing ->
                            button [ class "server-details-rename-button", onClick EditProfileClicked ] [ text "Edit Profile" ]

                        Just edit ->
                            profileEditForm edit

                  else
                    case ( model.followFor == Just acting.handle, model.followState ) of
                        ( True, Just state ) ->
                            let
                                following : Bool
                                following =
                                    state.followUri /= Nothing
                            in
                            button
                                [ classes
                                    (if following then
                                        [ "server-details-rename-button" ]

                                     else
                                        [ "server-details-rename-save", "background-color-primary" ]
                                    )
                                , onClick FollowClicked
                                , disabled model.followBusy
                                ]
                                [ text
                                    (if following then
                                        "Unfollow"

                                     else
                                        "Follow"
                                    )
                                ]

                        _ ->
                            text ""
                , case model.actionError of
                    Just err ->
                        div [ class "server-details-rename-error" ] [ text err ]

                    Nothing ->
                        text ""
                ]


profileEditForm : ProfileEdit -> Html Msg
profileEditForm edit =
    if edit.record == Nothing then
        p [ class "post-loading" ] [ text "Loading…" ]

    else
        div [ class "server-details-federation-edit" ]
            [ input
                [ class "server-details-rename-input"
                , value edit.displayName
                , onInput DisplayNameChanged
                , placeholder "Display name"
                ]
                []
            , textarea
                [ class "server-details-rename-input"
                , value edit.description
                , onInput DescriptionChanged
                , placeholder "Bio"
                , rows 4
                ]
                []
            , div [ class "server-details-permissions-actions" ]
                [ button
                    [ classes [ "server-details-rename-save", "background-color-primary" ]
                    , onClick SaveProfileClicked
                    , disabled edit.saving
                    ]
                    [ text
                        (if edit.saving then
                            "Saving…"

                         else
                            "Save"
                        )
                    ]
                , button [ class "server-details-rename-cancel", onClick CancelProfileClicked, disabled edit.saving ] [ text "Cancel" ]
                ]
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
calling page's own `UI.pageTitle`. Mirrors `Components.Bluesky.BlueskyPostPage.title`.
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
