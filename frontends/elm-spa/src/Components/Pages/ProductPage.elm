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
import Components.Markdown as Markdown
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
import Shared.AccountsPanel.RellmServers as RellmServers
import Shared.Breadcrumbs as Breadcrumbs
import Task



-- MODEL


type alias Model =
    { productId : String
    , fetch : ProductFetchState
    , fetchStarted : Bool
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
    let
        ( readyModel, fetchEffect ) =
            attemptFetch shared
                { productId = productId
                , fetch = Fetching
                , fetchStarted = False
                , purchase = Market.PurchaseIdle
                , hostingForm = Market.defaultHostingForm
                }
    in
    ( readyModel
    , Effect.batch
        [ fetchEffect
        , Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost shared.accounts.browsingHost) shared.accounts.browsingHost []))
        ]
    )


{-| Fires `fetchProduct` the first time `browsingHost` is a known, *connected* server -- see
`RellmServers.knownConnectedRellmServer`'s own doc: `Shared.AccountsPanel.init` seeds every
persisted server disconnected before its own reconnect attempt resolves, so firing this fetch
unconditionally in `init` (the original bug here -- a cold app load raced that reconnect and failed
instantly with "Couldn't load this product: Couldn't reach the server", with no retry affordance on
this page at all) doesn't work. Safe to call repeatedly (from `init` and every `SharedMsgReceived`,
mirroring `Components.Pages.PostOrEventPage.fetchIfReady`'s exact pattern) -- `fetchStarted` makes
every call after the first a no-op.
-}
attemptFetch : Shared.Model -> Model -> ( Model, Effect Msg )
attemptFetch shared model =
    if model.fetchStarted || RellmServers.knownConnectedRellmServer shared.accounts.servers shared.accounts.browsingHost == Nothing then
        ( model, Effect.none )

    else
        ( { model | fetchStarted = True }, fetchProduct shared model.productId )


fetchProduct : Shared.Model -> String -> Effect Msg
fetchProduct shared productId =
    Market.getMarketProducts shared.accounts (maybeAccountServer shared)
        |> Task.attempt (GotProductsResult productId)
        |> Effect.fromCmd


maybeAccountServer : Shared.Model -> AccountsPanel.MaybeAccountServer
maybeAccountServer shared =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts shared.accounts.browsingHost |> Maybe.map .userId
    , shared.accounts.browsingHost
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
    | LoginClicked
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

        LoginClicked ->
            ( model, Effect.fromShared (Shared.AccountsPanelMsg AccountsPanel.ToggleAccountsPanel) )

        SharedMsgReceived subMsg ->
            let
                ( retriedModel, retryEffect ) =
                    attemptFetch shared model
            in
            ( retriedModel, Effect.batch [ Effect.fromShared subMsg, retryEffect ] )


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    div [ class "product-page" ]
        (case model.fetch of
            Fetching ->
                [ p [] [ text "Loading product…" ] ]

            NotFound ->
                [ p [ class "product-error" ] [ text "That product doesn't exist, or isn't listed." ] ]

            FetchErrored err ->
                [ p [ class "product-error" ] [ text ("Couldn't load this product: " ++ err) ] ]

            Found product ->
                [ div [ class "product-icon" ] [ text (Market.purchaseTypeEmoji product.type_) ]
                , h1 [] [ text (Market.purchaseTypeLabel product.type_) ]
                , p [ class "product-name" ] [ text (Market.productName product) ]
                , p [ class "product-price" ] [ text (Market.priceLabel product) ]
                , Markdown.view [ class "product-description" ] (Market.productDescription product)
                , case Market.slotsAvailableText product of
                    Just slotsText ->
                        p [ class "product-slots" ] [ text slotsText ]

                    Nothing ->
                        text ""
                , if product.delistedAt /= Nothing then
                    p [ class "product-delisted" ] [ text "This product is no longer available for purchase." ]

                  else if Market.isSoldOut product then
                    p [ class "product-delisted" ] [ text "This product is sold out." ]

                  else
                    buyView shared model product
                ]
        )


{-| Whether anyone is signed in on `browsingHost` at all -- gates the "Buy" button below (a
signed-out click would otherwise just fail with a confusing `NetworkError`, since
`Market.makeMarketPurchase` is always authenticated -- see `Shared.AccountsPanel.performWithAccountServer`).
-}
signedIn : Shared.Model -> Bool
signedIn shared =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts shared.accounts.browsingHost /= Nothing


{-| `market_settings.stripe_configured` -- the public "is Stripe actually usable right now" signal
(see that field's own proto doc), read off whatever `RellmServers.configurationOf` already has
cached for `browsingHost` (the same unauthenticated probe `MarketProduct`s themselves came from, via
`fetchProduct`). Defaults to `True` (i.e. don't block the Buy button) whenever `browsingHost` isn't
yet a known/connected server or hasn't reported `marketSettings` at all -- by the time `Found
product` is actually on screen this should never happen in practice (see `attemptFetch`'s own doc:
`fetchProduct` itself doesn't fire until the server is known/connected), but "unknown" shouldn't read
as "definitely not configured" either way.
-}
stripeConfigured : Shared.Model -> Bool
stripeConfigured shared =
    RellmServers.knownConnectedRellmServer shared.accounts.servers shared.accounts.browsingHost
        |> Maybe.map
            (\server ->
                (RellmServers.configurationOf server).marketSettings
                    |> Maybe.map .stripeConfigured
                    |> Maybe.withDefault True
            )
        |> Maybe.withDefault True


buyView : Shared.Model -> Model -> MarketProduct -> Html Msg
buyView shared model product =
    if not (stripeConfigured shared) then
        div [ class "product-buy" ]
            [ button [ disabled True ] [ text "Buy" ]
            , p [ class "product-stripe-not-configured" ] [ text "Stripe is not configured." ]
            ]

    else if not (signedIn shared) then
        loginPromptView

    else
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


{-| Shown instead of a "Buy" button (and, for `RELLM_HOSTING`, its domain/contact/notes form) when
nobody's signed in -- opens the Accounts Panel (the app's only Login/Create Account entry point --
there's no dedicated route).
-}
loginPromptView : Html Msg
loginPromptView =
    div [ class "product-login-prompt" ]
        [ p [] [ text "Create Account or Login to proceed." ]
        , button [ onClick LoginClicked ] [ text "Login" ]
        ]


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
