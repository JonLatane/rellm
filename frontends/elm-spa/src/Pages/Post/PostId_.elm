module Pages.Post.PostId_ exposing (Model, Msg, fromShared, page)

{-| `/post/:id[@host]` -- a single Post, by id, on `mainFrontendHost` or (with an `@host` suffix)
some other federated server. Dispatches to one of three underlying pages, based on
`Components.Posts.parseFederatedPostId`: a real Rellm post goes to `Components.Pages.PostPage`
(mirrors `Pages.About`'s own direct-alias shape around `Components.Pages.ServerInformationPage`), a
Mastodon post to `Components.Pages.MastodonPostPage`, a Bluesky post to
`Components.Pages.BlueskyPostPage`. `Components.Pages.PostPage` itself is also reused, unmodified, by
`Pages.UsernameOrCustomTab_` (once a custom tab's own `path` resolves to a `TargetPost`, always a real
Rellm post -- see that module's `initEmbedded`) so a vanity URL like `/weddings` renders
indistinguishably from this page itself.
-}

import Components.Pages.BlueskyPostPage as BlueskyPostPage
import Components.Pages.MastodonPostPage as MastodonPostPage
import Components.Pages.PostPage as PostPage
import Components.Posts as Posts
import Effect exposing (Effect)
import Gen.Params.Post.PostId_ exposing (Params)
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
    = RellmPost PostPage.Model
    | MastodonPost MastodonPostPage.Model
    | BlueskyPost BlueskyPostPage.Model


type Msg
    = RellmPostMsg PostPage.Msg
    | MastodonPostMsg MastodonPostPage.Msg
    | BlueskyPostMsg BlueskyPostPage.Msg
      -- Forwarded from `Main` (see `fromShared`) -- routed by `update` to whichever of the three
      -- underlying pages' own `Shared.Msg` handling (currently just `PostPage`'s -- the Mastodon/
      -- Bluesky pages have nothing of their own to react to here) matches the *current* `Model`,
      -- since a bare `Shared.Msg` carries no notion of which one that is on its own. Regardless of
      -- which page is active, `subMsg` itself always still needs forwarding on to `Shared.update`
      -- (via `Effect.fromShared`) -- it's not just a page-local concern: this is how top-level
      -- state changes like `AccountsPanel.ToggleAccountsPanel` actually take effect at all, so
      -- dropping it while a Mastodon/Bluesky post is open would silently break things like opening
      -- the Accounts Panel from this page.
    | SharedMsgReceived Shared.Msg


{-| Parses the route's `:id[@host]` once, up front, to decide which of the three pages this visit
is actually for -- see `Components.Posts.parseFederatedPostId`'s own doc on the id-namespacing this
detects.
-}
init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        ( postId, targetHost ) =
            Posts.parsePostRouteId shared.accounts.mainFrontendHost req.params.postId
    in
    case Posts.parseFederatedPostId postId targetHost of
        Just (Posts.MastodonPostId { instanceHost, statusId }) ->
            MastodonPostPage.init instanceHost statusId
                |> Tuple.mapFirst MastodonPost
                |> Tuple.mapSecond (Effect.map MastodonPostMsg)

        Just (Posts.BlueskyPostId { uri }) ->
            BlueskyPostPage.init shared uri
                |> Tuple.mapFirst BlueskyPost
                |> Tuple.mapSecond (Effect.map BlueskyPostMsg)

        Nothing ->
            PostPage.init shared (RellmServers.isSecure req) req.params.postId req.key
                |> Tuple.mapFirst RellmPost
                |> Tuple.mapSecond (Effect.map RellmPostMsg)


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case ( msg, model ) of
        ( RellmPostMsg subMsg, RellmPost subModel ) ->
            PostPage.update shared subMsg subModel
                |> Tuple.mapFirst RellmPost
                |> Tuple.mapSecond (Effect.map RellmPostMsg)

        ( MastodonPostMsg subMsg, MastodonPost subModel ) ->
            MastodonPostPage.update subMsg subModel
                |> Tuple.mapFirst MastodonPost
                |> Tuple.mapSecond (Effect.map MastodonPostMsg)

        ( BlueskyPostMsg subMsg, BlueskyPost subModel ) ->
            BlueskyPostPage.update subMsg subModel
                |> Tuple.mapFirst BlueskyPost
                |> Tuple.mapSecond (Effect.map BlueskyPostMsg)

        ( SharedMsgReceived subMsg, RellmPost subModel ) ->
            PostPage.update shared (PostPage.fromShared subMsg) subModel
                |> Tuple.mapFirst RellmPost
                |> Tuple.mapSecond (Effect.map RellmPostMsg)

        ( SharedMsgReceived subMsg, _ ) ->
            -- Neither Mastodon/Bluesky page has any `Shared.Msg` of its own to react to, but
            -- `subMsg` still needs to reach `Shared.update` -- see `Msg`'s own doc.
            ( model, Effect.fromShared subMsg )

        _ ->
            ( model, Effect.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        RellmPost subModel ->
            Sub.map RellmPostMsg (PostPage.subscriptions subModel)

        MastodonPost _ ->
            Sub.none

        BlueskyPost _ ->
            Sub.none


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    let
        pageTitle : String
        pageTitle =
            case model of
                RellmPost subModel ->
                    PostPage.titleFor subModel

                MastodonPost subModel ->
                    MastodonPostPage.title subModel

                BlueskyPost subModel ->
                    BlueskyPostPage.title subModel

        body : Html.Html Msg
        body =
            case model of
                RellmPost subModel ->
                    Html.map RellmPostMsg (PostPage.view shared subModel)

                MastodonPost subModel ->
                    Html.map MastodonPostMsg (MastodonPostPage.view shared subModel)

                BlueskyPost subModel ->
                    Html.map BlueskyPostMsg (BlueskyPostPage.view shared subModel)
    in
    { title = UI.pageTitle shared [ pageTitle ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ body ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see `Msg`'s own
`SharedMsgReceived` doc on why that's routed inside `update` (against the current `Model`) rather
than dispatched to one specific underlying page's own `fromShared` here.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
