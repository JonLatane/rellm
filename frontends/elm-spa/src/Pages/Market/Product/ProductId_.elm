module Pages.Market.Product.ProductId_ exposing (Model, Msg, fromShared, page)

{-| `/market/product/:id` -- a single `MarketProduct`, by id. Thin wrapper around
`Components.Pages.ProductPage`, which does all the actual work -- mirrors `Pages.About`'s own
direct-alias shape around `Components.Pages.ServerInformationPage`.
-}

import Components.Pages.ProductPage as ProductPage
import Effect exposing (Effect)
import Gen.Params.Market.Product.ProductId_ exposing (Params)
import Page
import Request
import Shared
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared
        , view = view shared req
        , subscriptions = ProductPage.subscriptions
        }


type alias Model =
    ProductPage.Model


type alias Msg =
    ProductPage.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    ProductPage.init shared req.params.productId


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    ProductPage.update shared msg model


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ ProductPage.titleFor model ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ ProductPage.view shared model
            ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see
`Components.Pages.ProductPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    ProductPage.fromShared
