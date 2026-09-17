module Pages.Market exposing (Model, Msg, fromShared, page)

{-| `/market` -- Rellm's Stripe-backed marketplace. Can show more than one server's Market side by
side -- the browsed server's own (`shared.accounts.browsingHost`, always first) plus any other
connected, enabled server whose `ServerConfiguration.market_settings.enabled` is set (in Accounts
panel order after that) -- see `rellm.proto`'s own "Federated Markets" doc section for why (and why
buying is never seamless across servers the way most other federated features are). Each section is
a full, independent `Components.Pages.MarketPage.Model` instance, scoped to its own host -- product
tiles for a non-browsed host link straight out to that server's own product page (see
`MarketPage.productHref`), since buying always has to happen *on* the target server.

Mirrors `Pages.Posts`'s own direct-alias shape around `Components.Pages.PostsPage` in spirit, but
`Model`/`Msg` here wrap a *list* of `MarketPage` instances (keyed by host) rather than a single one.
`embeddedPage = False` (`MarketPage.view`'s second argument) for every instance, since this route
owns its own heading(s) directly, same reasoning as `Pages.Posts`'s own doc on that argument.
-}

import Components.Pages.MarketPage as MarketPage
import Effect exposing (Effect)
import Gen.Params.Market exposing (Params)
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
        { init = init shared
        , update = update shared
        , view = view shared req
        , subscriptions = subscriptions
        }


type alias Model =
    { instances : List ( String, MarketPage.Model )
    }


type Msg
    = InstanceMsg String MarketPage.Msg
    | SharedMsgReceived Shared.Msg


{-| The browsed server's own host, always first, followed by every other connected+enabled server
with `market_settings.enabled` set, in Accounts panel (`sortOrder`) order -- see module doc. The
browsed host is included unconditionally (regardless of its own `market_settings.enabled`), matching
this route's own pre-existing behavior before federated Market browsing existed: visiting `/market`
directly always shows *something* for the server you're actually on.
-}
marketEnabledHosts : Shared.Model -> List String
marketEnabledHosts shared =
    let
        browsingHost : String
        browsingHost =
            shared.accounts.browsingHost

        marketEnabled : RellmServers.RellmServer -> Bool
        marketEnabled server =
            (RellmServers.configurationOf server).marketSettings
                |> Maybe.map .enabled
                |> Maybe.withDefault False

        others : List String
        others =
            shared.accounts.servers
                |> List.filter (\s -> s.enabled && s.frontendHost /= browsingHost)
                |> List.filter marketEnabled
                |> List.sortBy .sortOrder
                |> List.map .frontendHost
    in
    browsingHost :: others


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    let
        inits : List ( ( String, MarketPage.Model ), Effect Msg )
        inits =
            marketEnabledHosts shared
                |> List.map
                    (\host ->
                        let
                            ( instanceModel, instanceEffect ) =
                                MarketPage.init shared host
                        in
                        ( ( host, instanceModel ), Effect.map (InstanceMsg host) instanceEffect )
                    )
    in
    ( { instances = List.map Tuple.first inits }
    , Effect.batch (List.map Tuple.second inits)
    )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        InstanceMsg host instanceMsg ->
            case findInstance host model.instances of
                Just instanceModel ->
                    let
                        ( updatedInstance, instanceEffect ) =
                            MarketPage.update shared instanceMsg instanceModel
                    in
                    ( { model | instances = replaceInstance host updatedInstance model.instances }
                    , Effect.map (InstanceMsg host) instanceEffect
                    )

                Nothing ->
                    ( model, Effect.none )

        SharedMsgReceived subMsg ->
            -- Fanned out to every instance (rather than just one, like `InstanceMsg` above) --
            -- a reconnect/account change can affect any (or all) of them, e.g. retrying a
            -- still-pending fetch (see `MarketPage.attemptFetches`) once a server actually connects.
            let
                updated : List ( ( String, MarketPage.Model ), Effect Msg )
                updated =
                    model.instances
                        |> List.map
                            (\( host, instanceModel ) ->
                                let
                                    ( updatedInstance, instanceEffect ) =
                                        MarketPage.update shared (MarketPage.fromShared subMsg) instanceModel
                                in
                                ( ( host, updatedInstance ), Effect.map (InstanceMsg host) instanceEffect )
                            )
            in
            ( { model | instances = List.map Tuple.first updated }
            , Effect.batch (List.map Tuple.second updated)
            )


findInstance : String -> List ( String, MarketPage.Model ) -> Maybe MarketPage.Model
findInstance host instances =
    instances |> List.filter (\( h, _ ) -> h == host) |> List.head |> Maybe.map Tuple.second


replaceInstance : String -> MarketPage.Model -> List ( String, MarketPage.Model ) -> List ( String, MarketPage.Model )
replaceInstance host updatedInstance instances =
    instances |> List.map (\( h, m ) -> if h == host then ( h, updatedInstance ) else ( h, m ))


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "Market" ]
    , body =
        UI.layout shared
            req.route
            fromShared
            (model.instances
                |> List.map (\( host, instanceModel ) -> Html.map (InstanceMsg host) (MarketPage.view shared False instanceModel))
            )
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    model.instances
        |> List.map (\( host, instanceModel ) -> Sub.map (InstanceMsg host) (MarketPage.subscriptions instanceModel))
        |> Sub.batch


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- fanned out to every
instance (see `SharedMsgReceived` above), unlike `Components.Pages.MarketPage.fromShared`'s own
single-instance forwarding.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
