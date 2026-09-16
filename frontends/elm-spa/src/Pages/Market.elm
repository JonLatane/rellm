module Pages.Market exposing (Model, Msg, fromShared, page)

{-| `/market` -- Rellm's Stripe-backed marketplace. Thin wrapper around
`Components.Pages.MarketPage`, which does all the actual work -- mirrors `Pages.Posts`'s own
direct-alias shape around `Components.Pages.PostsPage`. `embeddedPage = False` (`view`'s second
argument), since this route owns its own "Market" heading directly, same reasoning as
`Pages.Posts`'s own doc on that argument.
-}

import Components.Pages.MarketPage as MarketPage
import Effect exposing (Effect)
import Gen.Params.Market exposing (Params)
import Page
import Request
import Shared
import UI
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = MarketPage.init shared
        , update = update shared
        , view = view shared req
        , subscriptions = MarketPage.subscriptions
        }


type alias Model =
    MarketPage.Model


type alias Msg =
    MarketPage.Msg


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    MarketPage.update shared msg model


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared [ "Market" ]
    , body =
        UI.layout shared
            req.route
            fromShared
            [ MarketPage.view shared False model
            ]
    }


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see
`Components.Pages.MarketPage.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    MarketPage.fromShared
