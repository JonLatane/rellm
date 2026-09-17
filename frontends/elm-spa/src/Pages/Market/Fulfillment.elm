module Pages.Market.Fulfillment exposing (Model, Msg, fromShared, page)

{-| `/market/fulfillment` -- admin-only Rellm Hosting order management. Thin wrapper around
`Components.Pages.MarketFulfillmentPage`, which does all the actual work -- mirrors
`Pages.Market.Product.ProductId_`'s own direct-alias shape around `Components.Pages.ProductPage`.
-}

import Components.Pages.MarketFulfillmentPage as MarketFulfillmentPage
import Effect exposing (Effect)
import Gen.Params.Market.Fulfillment exposing (Params)
import Page
import Request
import Shared
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared
        , update = update shared
        , view = view shared req
        , subscriptions = MarketFulfillmentPage.subscriptions
        }


type alias Model =
    MarketFulfillmentPage.Model


type alias Msg =
    MarketFulfillmentPage.Msg


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    MarketFulfillmentPage.init shared


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    MarketFulfillmentPage.update shared msg model


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ MarketFulfillmentPage.titleFor ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ MarketFulfillmentPage.view shared model
            ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see
`Components.Pages.MarketFulfillmentPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    MarketFulfillmentPage.fromShared
