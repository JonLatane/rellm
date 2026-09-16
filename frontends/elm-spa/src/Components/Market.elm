module Components.Market exposing
    ( HostingForm
    , PurchaseState(..)
    , createMarketProduct
    , defaultHostingForm
    , formatAmount
    , getMarketProducts
    , hostingDetailsFromForm
    , makeMarketPurchase
    , purchasePeriodLabel
    , purchaseTypeLabel
    , updateMarketProduct
    , usdCurrencyCode
    )

{-| RPC wrappers for `MarketProduct`/`MarketSubscription`/`MarketPurchase` (`protos/market.proto`)
-- mirrors `Components.AIProviders` in shape exactly: each takes the calling account/server as an
`AccountsPanel.MaybeAccountServer` and returns a `Task` resolving to `( Maybe AccountsPanel.Msg,
response )`, so a token refresh mid-request can still be forwarded on by the caller (see
`Shared.AccountsPanel.performWithAccountServer`).

`getMarketProducts` is unauthenticated (`GetProducts` in `rellm.proto` -- non-delisted products are
public; an admin caller additionally sees delisted ones), so it goes through
`AccountsPanel.performWithOptionalAccountServer` rather than `performWithAccountServer`, same
reasoning as `Components.Posts.fetchPosts`. Every other RPC here is authenticated.

Also holds the small bits `Components.Pages.MarketPage`/`Components.Pages.ProductPage`/
`Components.Pages.UserProfilePage`'s Subscriptions section all need in common -- `purchaseTypeLabel`/
`purchasePeriodLabel`/`formatAmount` -- so the three don't each grow their own copy.
-}

import Grpc
import Proto.Rellm
    exposing
        ( GetMarketProductsResponse
        , MakeMarketPurchaseRequest
        , MakeMarketPurchaseResponse
        , MarketProduct
        , RellmHostingPurchaseDetails
        , defaultGetMarketProductsRequest
        , defaultRellmHostingPurchaseDetails
        )
import Proto.Rellm.PurchasePeriod exposing (PurchasePeriod(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Task exposing (Task)


{-| For now the only currency `purchase_subscription.rs` actually supports (see `market.proto`'s
own scope note) -- ISO 4217 numeric code 840. Every admin-created `MarketProduct` on this frontend
is created in USD; `formatAmount` falls back to a generic "<amount> (currency <code>)" for anything
else (e.g. a product created by some other client in a different currency).
-}
usdCurrencyCode : Int
usdCurrencyCode =
    840


{-| A "Buy" button's own in-flight state, keyed by product id in whichever `Dict` the calling page
(`Components.Pages.MarketPage`/`Components.Pages.ProductPage`) tracks it in.
-}
type PurchaseState
    = PurchaseIdle
    | PurchaseSubmitting
    | PurchaseErrored String


{-| The buyer-supplied fields a `RELLM_HOSTING` product's "Buy" button collects before submitting
`MakeMarketPurchaseRequest.rellmHostingDetails` (`domain`/`contactEmail`/`additionalInformation` --
see that message's own proto doc). Shared between `Components.Pages.MarketPage`'s list and
`Components.Pages.ProductPage`'s detail view so neither grows its own copy.
-}
type alias HostingForm =
    { domain : String
    , contactEmail : String
    , additionalInformation : String
    }


defaultHostingForm : HostingForm
defaultHostingForm =
    { domain = "", contactEmail = "", additionalInformation = "" }


hostingDetailsFromForm : HostingForm -> RellmHostingPurchaseDetails
hostingDetailsFromForm form =
    { defaultRellmHostingPurchaseDetails
        | domain = form.domain
        , contactEmail = form.contactEmail
        , additionalInformation = form.additionalInformation
    }


getMarketProducts :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMarketProductsResponse )
getMarketProducts accountsPanelModel maybeAccountServer =
    AccountsPanel.performWithOptionalAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server maybeToken ->
            Grpc.new Rellm.getMarketProducts defaultGetMarketProductsRequest
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken maybeToken
                |> Grpc.toTask
        )


{-| Always creates a fresh (non-delisted) `MarketProduct` -- Admin-only server-side (see
`create_product.rs`, gated on `Permission.ADMIN` directly, same as `configure_server.rs`).
-}
createMarketProduct :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MarketProduct
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, MarketProduct )
createMarketProduct accountsPanelModel maybeAccountServer product =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.createMarketProduct product
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| `type_`/`period` are never actually changeable (see `MarketProduct`'s own proto doc) --
callers should only ever vary `amount`/`currency`/`details`/`delistedAt` between fetch and submit.
-}
updateMarketProduct :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MarketProduct
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, MarketProduct )
updateMarketProduct accountsPanelModel maybeAccountServer product =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.updateMarketProduct product
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Starts (or continues) a Stripe Checkout flow for `request.marketProductId` -- the caller
should `Browser.Navigation.load response.checkoutUrl` on success (a plain external redirect, not an
Elm route -- see `MakeMarketPurchaseResponse.checkoutUrl`'s own proto doc). No `MarketPurchase`/
`MarketSubscription` exists yet at this point -- fulfillment only happens once Stripe's own webhook
confirms payment.
-}
makeMarketPurchase :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MakeMarketPurchaseRequest
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, MakeMarketPurchaseResponse )
makeMarketPurchase accountsPanelModel maybeAccountServer request =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.makeMarketPurchase request
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


purchaseTypeLabel : PurchaseType -> String
purchaseTypeLabel type_ =
    case type_ of
        PURCHASETYPEMEDIASTORAGE ->
            "Media Storage"

        PURCHASETYPEAIGRANTS ->
            "AI Model Access"

        PURCHASETYPERELLMHOSTING ->
            "Rellm Hosting"

        PURCHASETYPEPERMISSIONSACCESS ->
            "Permissions Access"

        PurchaseTypeUnrecognized_ _ ->
            "Unknown"


purchasePeriodLabel : PurchasePeriod -> String
purchasePeriodLabel period =
    case period of
        PURCHASEPERIODINDEFINITE ->
            "One-Time"

        PURCHASEPERIODANNUAL ->
            "Yearly"

        PURCHASEPERIODMONTHLY ->
            "Monthly"

        PurchasePeriodUnrecognized_ _ ->
            "Unknown"


{-| `amount` is in the currency's smallest unit (e.g. USD cents), matching how Stripe itself wants
amounts -- see `MarketProduct.amount`'s own proto doc. Only `usdCurrencyCode` is formatted as an
actual price; any other `currency` falls back to a generic "<amount> (currency <code>)" readout
(this frontend never lets an admin pick a different one -- see `usdCurrencyCode`'s own doc).
-}
formatAmount : Int -> Int -> String
formatAmount amount currency =
    if currency == usdCurrencyCode then
        let
            dollars : Int
            dollars =
                amount // 100

            cents : Int
            cents =
                abs (remainderBy 100 amount)

            centsText : String
            centsText =
                if cents < 10 then
                    "0" ++ String.fromInt cents

                else
                    String.fromInt cents
        in
        "$" ++ String.fromInt dollars ++ "." ++ centsText

    else
        String.fromInt amount ++ " (currency " ++ String.fromInt currency ++ ")"
