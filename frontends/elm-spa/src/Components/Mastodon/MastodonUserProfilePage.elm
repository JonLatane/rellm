module Components.Mastodon.MastodonUserProfilePage exposing (Model, Msg, fromShared, init, subscriptions, title, update, view)

{-| A single Mastodon account's profile, -- avatar/display name/bio/follower-and-following
counts, plus that account's own authored posts (embedding `Components.Pages.PostsPage`, scoped to
just this account via its `MastodonAccountFeed` `FeedSource`). When a Mastodon account is connected (see
`Shared.Federation.Actions`), it also offers Follow/Unfollow on someone else's profile and "Edit Profile"
(display name and bio) on the connected account's own. No moderation/permissions/sync
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
import Html exposing (Html, a, button, div, h1, h3, input, p, span, text, textarea)
import Html.Attributes exposing (class, disabled, href, placeholder, rows, value)
import Html.Events exposing (onClick, onInput)
import Http
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.MastodonAccounts exposing (MastodonAccount)
import Shared.Federation.Actions as Actions
import Shared.Federation.Mastodon as Mastodon
import Task
import UI.Classes exposing (classes)


type alias Model =
    { instanceHost : String
    , username : String
    , profileStatus : ProfileStatus
    , posts : Maybe PostsPage.Model
    , navKey : Browser.Navigation.Key
    , path : String
    , query : Dict String String

    -- The connected account's relationship to this profile (`Nothing` until known, or when there's
    -- no connected account / this is its own profile).
    --
    -- It's the relationship *for `relationshipFor`* -- the `Actions.accountId` of the account acting when it was
    -- fetched: switching accounts clears it and fetches again (`syncRelationship`), and replies from the previous
    -- account are dropped, so one account's relationship is never used as another's.
    , relationshipFor : Maybe String
    , relationship : Maybe Mastodon.Relationship
    , followBusy : Bool

    -- `Just` while the connected account's own profile is being edited.
    , profileEdit : Maybe ProfileEdit
    , actionError : Maybe String
    }


type alias ProfileEdit =
    { displayName : String
    , note : String

    -- `False` while the current values are still being fetched.
    , loaded : Bool
    , saving : Bool
    }


type ProfileStatus
    = LoadingProfile
    | ProfileLoaded Mastodon.Account
    | ProfileFailed


type Msg
    = GotAccount (Result Http.Error Mastodon.Account)
    | PostsMsg PostsPage.Msg
    | SharedMsgReceived Shared.Msg
    | GotFollowState String (Result Http.Error ( Maybe AccountsPanel.Msg, Mastodon.Relationship ))
    | FollowClicked
    | GotFollowResult String (Result Http.Error ( Maybe AccountsPanel.Msg, Mastodon.Relationship ))
    | EditProfileClicked
    | GotOwnProfile (Result Http.Error ( Maybe AccountsPanel.Msg, Mastodon.OwnProfile ))
    | DisplayNameChanged String
    | NoteChanged String
    | SaveProfileClicked
    | CancelProfileClicked
    | GotProfileSaved (Result Http.Error (Maybe AccountsPanel.Msg))
    | GotRefreshedAccount (Result Http.Error Mastodon.Account)


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
      , relationshipFor = Nothing
      , relationship = Nothing
      , followBusy = False
      , profileEdit = Nothing
      , actionError = Nothing
      }
    , Mastodon.lookupAccount instanceHost username
        |> Task.attempt GotAccount
        |> Effect.fromCmd
    )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    updateInner shared msg model |> syncRelationship shared


{-| The `Actions.accountId` of a connected Mastodon account.
-}
accountKey : MastodonAccount -> String
accountKey account =
    Actions.accountId (Actions.MastodonServerAccount account)


{-| Keeps the relationship for the account that is acting *now*: when that isn't the one it was fetched for
(another account became the acting one, or the profile just loaded), it's cleared and fetched for the new one.
Nothing for your own profile or with no account.
-}
syncRelationship : Shared.Model -> ( Model, Effect Msg ) -> ( Model, Effect Msg )
syncRelationship shared ( model, effect ) =
    case model.profileStatus of
        ProfileLoaded account ->
            let
                acting : Maybe MastodonAccount
                acting =
                    actingAccount shared model
                        |> Maybe.filter (\a -> not (Actions.isOwnMastodonProfile a (targetOf model account)))

                wanted : Maybe String
                wanted =
                    Maybe.map accountKey acting
            in
            if wanted == model.relationshipFor then
                ( model, effect )

            else
                ( { model | relationshipFor = wanted, relationship = Nothing, followBusy = False }
                , Effect.batch
                    [ effect
                    , case acting of
                        Just a ->
                            Actions.fetchMastodonFollowState a (targetOf model account)
                                |> Task.attempt (GotFollowState (accountKey a))
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

        GotFollowState key (Ok ( maybeAccountsPanelMsg, relationship )) ->
            if Just key == model.relationshipFor then
                ( { model | relationship = Just relationship }, forwardRotated maybeAccountsPanelMsg )

            else
                ( model, forwardRotated maybeAccountsPanelMsg )

        GotFollowState _ (Err _) ->
            -- Not being able to tell (e.g. the instance doesn't know the account) just means no button.
            ( model, Effect.none )

        FollowClicked ->
            case ( model.profileStatus, actingAccount shared model, model.relationship ) of
                ( ProfileLoaded account, Just acting, Just relationship ) ->
                    if model.relationshipFor /= Just (accountKey acting) then
                        ( model, Effect.none )

                    else
                        ( { model | followBusy = True, actionError = Nothing }
                        , Actions.setMastodonFollowing (not (relationship.following || relationship.requested)) acting (targetOf model account)
                            |> Task.attempt (GotFollowResult (accountKey acting))
                            |> Effect.fromCmd
                        )

                _ ->
                    ( model, Effect.none )

        GotFollowResult key (Ok ( maybeAccountsPanelMsg, relationship )) ->
            if Just key == model.relationshipFor then
                ( { model | relationship = Just relationship, followBusy = False }, forwardRotated maybeAccountsPanelMsg )

            else
                ( model, forwardRotated maybeAccountsPanelMsg )

        GotFollowResult key (Err err) ->
            if Just key == model.relationshipFor then
                ( { model | followBusy = False, actionError = Just (Actions.writeErrorText err) }, Effect.none )

            else
                ( model, Effect.none )

        EditProfileClicked ->
            case actingAccount shared model of
                Just acting ->
                    ( { model | profileEdit = Just { displayName = "", note = "", loaded = False, saving = False }, actionError = Nothing }
                    , Actions.fetchMastodonOwnProfile acting
                        |> Task.attempt GotOwnProfile
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        GotOwnProfile (Ok ( maybeAccountsPanelMsg, profile )) ->
            ( { model | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | displayName = profile.displayName, note = profile.note, loaded = True }) }
            , forwardRotated maybeAccountsPanelMsg
            )

        GotOwnProfile (Err err) ->
            ( { model | profileEdit = Nothing, actionError = Just (Actions.writeErrorText err) }, Effect.none )

        DisplayNameChanged text ->
            ( { model | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | displayName = text }) }, Effect.none )

        NoteChanged text ->
            ( { model | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | note = text }) }, Effect.none )

        SaveProfileClicked ->
            case ( model.profileEdit, actingAccount shared model ) of
                ( Just edit, Just acting ) ->
                    ( { model | profileEdit = Just { edit | saving = True }, actionError = Nothing }
                    , Actions.updateMastodonOwnProfile acting { displayName = edit.displayName, note = edit.note }
                        |> Task.attempt GotProfileSaved
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        CancelProfileClicked ->
            ( { model | profileEdit = Nothing, actionError = Nothing }, Effect.none )

        GotProfileSaved (Ok maybeAccountsPanelMsg) ->
            ( { model | profileEdit = Nothing }
            , Effect.batch
                [ forwardRotated maybeAccountsPanelMsg
                , Mastodon.lookupAccount model.instanceHost model.username
                    |> Task.attempt GotRefreshedAccount
                    |> Effect.fromCmd
                ]
            )

        GotProfileSaved (Err err) ->
            ( { model
                | profileEdit = model.profileEdit |> Maybe.map (\edit -> { edit | saving = False })
                , actionError = Just (Actions.writeErrorText err)
              }
            , Effect.none
            )

        GotRefreshedAccount (Ok account) ->
            -- Just the profile card -- the embedded posts list is left alone.
            ( { model | profileStatus = ProfileLoaded account }, Effect.none )

        GotRefreshedAccount (Err _) ->
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


{-| The connected Mastodon account that acts on this profile's instance, if any (preferring one on that
very instance -- see `Actions.serverAccountFor`).
-}
actingAccount : Shared.Model -> Model -> Maybe MastodonAccount
actingAccount shared model =
    case Actions.serverAccountFor shared.accounts ("mastodon:" ++ model.instanceHost) of
        Just (Actions.MastodonServerAccount account) ->
            Just account

        _ ->
            Nothing


targetOf : Model -> Mastodon.Account -> Actions.MastodonProfileTarget
targetOf model account =
    { instanceHost = model.instanceHost, username = account.username, accountId = account.id }


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
                , profileActionsView shared model account
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


{-| Follow/Unfollow on someone else's profile, or "Edit Profile" (display name and bio) on the connected
account's own -- nothing at all without a connected Mastodon account.
-}
profileActionsView : Shared.Model -> Model -> Mastodon.Account -> Html Msg
profileActionsView shared model account =
    case actingAccount shared model of
        Nothing ->
            text ""

        Just acting ->
            div [ class "profile-actions" ]
                [ if Actions.isOwnMastodonProfile acting (targetOf model account) then
                    case model.profileEdit of
                        Nothing ->
                            button [ class "server-details-rename-button", onClick EditProfileClicked ] [ text "Edit Profile" ]

                        Just edit ->
                            profileEditForm edit

                  else
                    case ( model.relationshipFor == Just (accountKey acting), model.relationship ) of
                        ( True, Just relationship ) ->
                            let
                                label : String
                                label =
                                    if relationship.following then
                                        "Unfollow"

                                    else if relationship.requested then
                                        "Requested — cancel"

                                    else
                                        "Follow"
                            in
                            button
                                [ classes
                                    (if relationship.following || relationship.requested then
                                        [ "server-details-rename-button" ]

                                     else
                                        [ "server-details-rename-save", "background-color-primary" ]
                                    )
                                , onClick FollowClicked
                                , disabled model.followBusy
                                ]
                                [ text label ]

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
    if not edit.loaded then
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
                , value edit.note
                , onInput NoteChanged
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
