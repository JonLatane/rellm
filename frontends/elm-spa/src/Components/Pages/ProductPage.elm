module Components.Pages.ProductPage exposing (Model, Msg, fromShared, init, subscriptions, titleFor, update, view)

{-| `/market/product/:id` -- a single `MarketProduct`'s detail page (`market.proto`), reached from
`Components.Pages.MarketPage`'s list. There's no single-product RPC (`GetProducts` only ever returns
the whole list -- see that RPC's own proto doc), so this page just calls
`Components.Market.getMarketProducts` the same way the list page does and picks out the one product
matching `productId` -- fine for the "up to 9 products" scale this feature targets (see the plan
this was built from). A non-admin visiting a delisted product's URL directly sees "Not Found",
matching `GetProducts`' own admin-only visibility for delisted products.

The "Buy" button (and, for a `RELLM_HOSTING` product, its domain/contact/notes form) mirrors
`Components.Pages.MarketPage.buyView`/`hostingFormView` exactly -- both pages share the actual
`Components.Market.makeMarketPurchase` call and `Components.Market.PurchaseState`/`HostingForm`
types, just each keeps its own single-product-shaped copy of the surrounding `Model` plumbing
(a `Dict` keyed by product id would be pure overhead here, unlike the list page).
-}

import Browser.Navigation
import Components.Market as Market
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h1, p, span, text, textarea)
import Html.Attributes exposing (class, disabled, placeholder, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (MarketProduct, RellmHostingPurchaseDetails)
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.Breadcrumbs as Breadcrumbs
import Task



-- MODEL


type alias Model =
    { productId : String
    , fetch : ProductFetchState
    , purchase : Market.PurchaseState
    , hostingForm : Market.HostingForm
    }


type ProductFetchState
    = Fetching
    | Found MarketProduct
    | NotFound
    | FetchErrored String


init : Shared.Model -> String -> ( Model, Effect Msg )
init shared productId =
    ( { productId = productId
      , fetch = Fetching
      , purchase = Market.PurchaseIdle
      , hostingForm = Market.defaultHostingForm
      }
    , Effect.batch
        [ fetchProduct shared productId
        , Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost shared.accounts.mainFrontendHost) shared.accounts.mainFrontendHost []))
        ]
    )


fetchProduct : Shared.Model -> String -> Effect Msg
fetchProduct shared productId =
    Market.getMarketProducts shared.accounts (maybeAccountServer shared)
        |> Task.attempt (GotProductsResult productId)
        |> Effect.fromCmd


maybeAccountServer : Shared.Model -> AccountsPanel.MaybeAccountServer
maybeAccountServer shared =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts shared.accounts.mainFrontendHost |> Maybe.map .userId
    , shared.accounts.mainFrontendHost
    )


titleFor : Model -> String
titleFor model =
    case model.fetch of
        Found product ->
            Market.purchaseTypeLabel product.type_

        Fetching ->
            "Market"

        NotFound ->
            "Not Found"

        FetchErrored _ ->
            "Market"



-- UPDATE


type Msg
    = GotProductsResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetMarketProductsResponse ))
    | HostingFieldChanged (Market.HostingForm -> String -> Market.HostingForm) String
    | BuyClicked MarketProduct
    | GotPurchaseResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.MakeMarketPurchaseResponse ))
    | SharedMsgReceived Shared.Msg


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotProductsResult productId (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model
                | fetch =
                    case List.filter (\p -> p.id == productId) response.marketProducts of
                        product :: _ ->
                            Found product

                        [] ->
                            NotFound
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotProductsResult _ (Err err) ->
            ( { model | fetch = FetchErrored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        HostingFieldChanged setter text ->
            ( { model | hostingForm = setter model.hostingForm text }, Effect.none )

        BuyClicked product ->
            let
                hostingDetails : Maybe RellmHostingPurchaseDetails
                hostingDetails =
                    if product.type_ == PURCHASETYPERELLMHOSTING then
                        Just (Market.hostingDetailsFromForm model.hostingForm)

                    else
                        Nothing
            in
            ( { model | purchase = Market.PurchaseSubmitting }
            , Market.makeMarketPurchase shared.accounts
                (maybeAccountServer shared)
                { marketProductId = product.id, rellmHostingDetails = hostingDetails }
                |> Task.attempt GotPurchaseResult
                |> Effect.fromCmd
            )

        GotPurchaseResult (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | purchase = Market.PurchaseIdle }
            , Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, Effect.fromCmd (Browser.Navigation.load response.checkoutUrl) ]
            )

        GotPurchaseResult (Err err) ->
            ( { model | purchase = Market.PurchaseErrored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        SharedMsgReceived subMsg ->
            ( model, Effect.fromShared subMsg )


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "product-page" ]
        (case model.fetch of
            Fetching ->
                [ p [] [ text "Loading product…" ] ]

            NotFound ->
                [ p [ class "product-error" ] [ text "That product doesn't exist, or isn't listed." ] ]

            FetchErrored err ->
                [ p [ class "product-error" ] [ text ("Couldn't load this product: " ++ err) ] ]

            Found product ->
                [ h1 [] [ text (Market.purchaseTypeLabel product.type_) ]
                , p [ class "product-period" ] [ text (Market.purchasePeriodLabel product.period) ]
                , p [ class "product-amount" ] [ text (Market.formatAmount product.amount product.currency) ]
                , if product.delistedAt /= Nothing then
                    p [ class "product-delisted" ] [ text "This product is no longer available for purchase." ]

                  else
                    buyView model product
                ]
        )


buyView : Model -> MarketProduct -> Html Msg
buyView model product =
    div [ class "product-buy" ]
        ((if product.type_ == PURCHASETYPERELLMHOSTING then
            [ hostingFormView model.hostingForm ]

          else
            []
         )
            ++ [ button
                    [ onClick (BuyClicked product), disabled (model.purchase == Market.PurchaseSubmitting) ]
                    [ text
                        (if model.purchase == Market.PurchaseSubmitting then
                            "Starting checkout…"

                         else
                            "Buy"
                        )
                    ]
               , case model.purchase of
                    Market.PurchaseErrored err ->
                        span [ class "product-purchase-error" ] [ text err ]

                    _ ->
                        text ""
               ]
        )


hostingFormView : Market.HostingForm -> Html Msg
hostingFormView hostingForm =
    div [ class "product-hosting-form" ]
        [ Html.input
            [ placeholder "Domain (e.g. myband.rellm.org)"
            , value hostingForm.domain
            , onInput (HostingFieldChanged (\f text -> { f | domain = text }))
            ]
            []
        , Html.input
            [ placeholder "Contact Email"
            , value hostingForm.contactEmail
            , onInput (HostingFieldChanged (\f text -> { f | contactEmail = text }))
            ]
            []
        , textarea
            [ placeholder "Additional Information"
            , value hostingForm.additionalInformation
            , onInput (HostingFieldChanged (\f text -> { f | additionalInformation = text }))
            ]
            []
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
