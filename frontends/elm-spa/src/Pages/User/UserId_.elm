module Pages.User.UserId_ exposing (Model, Msg, fromShared, page)

{-| `/user/:id[@host]` -- a user profile looked up by (permanent) id, on
`mainFrontendHost` or, with an `@host` suffix, some other federated server. Dispatches to one of
three underlying pages, based on `Components.Users.parseFederatedUserId`: a real Rellm user goes to
`Components.Pages.UserProfilePage` (mirrors `Pages.Post.PostId_`'s own three-way dispatch), a
Mastodon account to `Components.Mastodon.MastodonUserProfilePage`, a Bluesky account to
`Components.Bluesky.BlueskyUserProfilePage`. See `Pages.UsernameOrCustomTab_` for the `/:username[@host]`
counterpart (the one every federated author link actually generates -- see
`Components.Users.parseFederatedUserId`'s own doc); this route's federated cases are reachable in
principle (`id` doubles as the username for a Mastodon/Bluesky account, same as a real Rellm user's
`/user/:id` fallback), just not one this app ever links to directly itself.
-}

import Components.Bluesky.BlueskyUserProfilePage as BlueskyUserProfilePage
import Components.Mastodon.MastodonUserProfilePage as MastodonUserProfilePage
import Components.Pages.UserProfilePage as UserProfilePage
import Components.Users as Users
import Components.Users.Resolver as Resolver
import Effect exposing (Effect)
import Gen.Params.User.UserId_ exposing (Params)
import Html
import Page
import Request
import Shared
import Shared.AccountsPanel.RellmServers as RellmServers
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared
        , view = view shared req
        , subscriptions = subscriptions
        }


type Model
    = RellmUser UserProfilePage.Model
    | MastodonUser MastodonUserProfilePage.Model
    | BlueskyUser BlueskyUserProfilePage.Model


type Msg
    = RellmUserMsg UserProfilePage.Msg
    | MastodonUserMsg MastodonUserProfilePage.Msg
    | BlueskyUserMsg BlueskyUserProfilePage.Msg
    | SharedMsgReceived Shared.Msg


{-| Parses the route's `:id[@host]` once, up front, to decide which of the three pages this visit is
actually for -- see `Components.Users.parseFederatedUserId`'s own doc on the id-namespacing this
detects. Mirrors `Pages.Post.PostId_.init` exactly.
-}
init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        ( userId, targetHost ) =
            Users.parseUserRouteId shared.accounts.mainFrontendHost req.params.userId
    in
    case Users.parseFederatedUserId userId targetHost of
        Just (Users.MastodonUserId mastodonUser) ->
            MastodonUserProfilePage.init mastodonUser.instanceHost mastodonUser.username req.key req.url.path req.query
                |> Tuple.mapFirst MastodonUser
                |> Tuple.mapSecond (Effect.map MastodonUserMsg)

        Just (Users.BlueskyUserId { handle }) ->
            BlueskyUserProfilePage.init shared handle req.key req.url.path req.query
                |> Tuple.mapFirst BlueskyUser
                |> Tuple.mapSecond (Effect.map BlueskyUserMsg)

        Nothing ->
            UserProfilePage.init shared (RellmServers.isSecure req) targetHost (Resolver.ById userId) req.key req.url.path req.query req.url.fragment
                |> Tuple.mapFirst RellmUser
                |> Tuple.mapSecond (Effect.map RellmUserMsg)


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case ( msg, model ) of
        ( RellmUserMsg subMsg, RellmUser subModel ) ->
            UserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst RellmUser
                |> Tuple.mapSecond (Effect.map RellmUserMsg)

        ( MastodonUserMsg subMsg, MastodonUser subModel ) ->
            MastodonUserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst MastodonUser
                |> Tuple.mapSecond (Effect.map MastodonUserMsg)

        ( BlueskyUserMsg subMsg, BlueskyUser subModel ) ->
            BlueskyUserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst BlueskyUser
                |> Tuple.mapSecond (Effect.map BlueskyUserMsg)

        ( SharedMsgReceived subMsg, RellmUser subModel ) ->
            UserProfilePage.update shared (UserProfilePage.fromShared subMsg) subModel
                |> Tuple.mapFirst RellmUser
                |> Tuple.mapSecond (Effect.map RellmUserMsg)

        ( SharedMsgReceived subMsg, MastodonUser subModel ) ->
            MastodonUserProfilePage.update shared (MastodonUserProfilePage.fromShared subMsg) subModel
                |> Tuple.mapFirst MastodonUser
                |> Tuple.mapSecond (Effect.map MastodonUserMsg)

        ( SharedMsgReceived subMsg, BlueskyUser subModel ) ->
            BlueskyUserProfilePage.update shared (BlueskyUserProfilePage.fromShared subMsg) subModel
                |> Tuple.mapFirst BlueskyUser
                |> Tuple.mapSecond (Effect.map BlueskyUserMsg)

        _ ->
            ( model, Effect.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        RellmUser subModel ->
            Sub.map RellmUserMsg (UserProfilePage.subscriptions subModel)

        MastodonUser subModel ->
            Sub.map MastodonUserMsg (MastodonUserProfilePage.subscriptions subModel)

        BlueskyUser subModel ->
            Sub.map BlueskyUserMsg (BlueskyUserProfilePage.subscriptions subModel)


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    let
        pageTitle : String
        pageTitle =
            case model of
                RellmUser subModel ->
                    UserProfilePage.titleFor subModel

                MastodonUser subModel ->
                    MastodonUserProfilePage.title subModel

                BlueskyUser subModel ->
                    BlueskyUserProfilePage.title subModel

        body : Html.Html Msg
        body =
            case model of
                RellmUser subModel ->
                    Html.map RellmUserMsg (UserProfilePage.view shared subModel)

                MastodonUser subModel ->
                    Html.map MastodonUserMsg (MastodonUserProfilePage.view shared subModel)

                BlueskyUser subModel ->
                    Html.map BlueskyUserMsg (BlueskyUserProfilePage.view shared subModel)
    in
    { title = UI.pageTitle shared [ pageTitle ]
    , body = UI.layout shared req.route fromShared [ body ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see
`Pages.Post.PostId_.fromShared`'s identical doc on why this always wraps as `SharedMsgReceived`
rather than picking one underlying page's own wrapper up front.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
