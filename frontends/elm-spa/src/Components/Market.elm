module Components.Market exposing
    ( HostingForm
    , PurchaseState(..)
    , createMarketProduct
    , defaultHostingForm
    , formatAmount
    , getMarketProducts
    , hostingDetailsFromForm
    , makeMarketPurchase
    , productSummary
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

import Components.Users as Users
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
import Proto.Rellm.MarketProduct.Details as ProductDetails
import Proto.Rellm.PurchasePeriod exposing (PurchasePeriod(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Shared.Conversions as Conversions
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


{-| The full, pedantically-clear "what am I buying" sentence for a `MarketProduct`, e.g. "1.5GB
storage for $1.00/mo", "100k tokens of Nano Banana Pro image generation for $2.00/mo", "Rellm
hosting, 1GB DB + 5GB MinIO for $15.00/mo. You get full admin access...". Mirrors
`backend/src/logic/market_summary.rs`'s `market_product_summary` (used server-side for the
`/market/product/:id` SSR preview) as closely as Elm's own formatting conventions allow, so the
in-app product page and a shared link's preview read the same way. Shown on `ProductPage`'s detail
view and `MarketPage`'s list rows.
-}
productSummary : MarketProduct -> String
productSummary product =
    resourceDescription product
        ++ " for "
        ++ formatAmount product.amount product.currency
        ++ periodSuffix product.period
        ++ additionalNote product.type_


{-| The resource being sold, without its price -- see `productSummary`'s own doc.
`PURCHASE_TYPE_MEDIA_STORAGE` gets a "lifetime" qualifier for an indefinite (non-recurring)
product specifically -- the other types don't need an equivalent qualifier, since the summary
sentence already omits any `/mo`/`/yr` suffix for a one-off purchase.
-}
resourceDescription : MarketProduct -> String
resourceDescription product =
    case product.details of
        Just (ProductDetails.MediaStorageSubscriptionDetails details) ->
            let
                size : String
                size =
                    humanizeBytes (Conversions.int64ToInt details.allocationBytes)
            in
            if product.period == PURCHASEPERIODINDEFINITE then
                size ++ " lifetime storage"

            else
                size ++ " storage"

        Just (ProductDetails.AiGrantSubscriptionDetails details) ->
            let
                tokens : String
                tokens =
                    humanizeCount (Conversions.int64ToInt details.tokens)

                models : String
                models =
                    if List.isEmpty details.modelNames then
                        "AI"

                    else
                        details.modelNames |> List.map aiModelDisplayName |> String.join "/"
            in
            tokens ++ " tokens of " ++ models ++ " image generation"

        Just (ProductDetails.RellmHostingSubscriptionDetails details) ->
            "Rellm hosting, "
                ++ humanizeBytes (Conversions.int64ToInt details.dbSizeBytes)
                ++ " DB + "
                ++ humanizeBytes (Conversions.int64ToInt details.minioSizeBytes)
                ++ " MinIO"

        Just (ProductDetails.PermissionsAccessSubscriptionDetails details) ->
            if List.isEmpty details.permissions then
                "access to server features"

            else
                "access to " ++ String.join ", " (List.map Users.permissionText details.permissions)

        Nothing ->
            "Rellm Market product"


{-| Rellm's own "Nano Banana" nicknames for the Gemini image model family -- mirrors
`backend/src/logic/ai_model_catalog.rs`'s `display_name` exactly. Falls back to the raw
provider-API model name for every other model, which has no comparable nickname in common use.
-}
aiModelDisplayName : String -> String
aiModelDisplayName modelName =
    case modelName of
        "gemini-3-pro-image" ->
            "Nano Banana Pro"

        "gemini-3.1-flash-image" ->
            "Nano Banana Flash"

        "gemini-3.1-flash-lite-image" ->
            "Nano Banana Flash Lite"

        "gemini-2.5-flash-image" ->
            "Nano Banana"

        other ->
            other


periodSuffix : PurchasePeriod -> String
periodSuffix period =
    case period of
        PURCHASEPERIODMONTHLY ->
            "/mo"

        PURCHASEPERIODANNUAL ->
            "/yr"

        PURCHASEPERIODINDEFINITE ->
            ""

        PurchasePeriodUnrecognized_ _ ->
            ""


{-| An explanatory sentence appended after the price, for a type where the bare resource+price
summary alone doesn't convey what's actually being sold -- mirrors
`backend/src/logic/market_summary.rs`'s `additional_note`. `PURCHASE_TYPE_RELLM_HOSTING` is the
only one that needs this today: the buyer becomes a full admin of their own new Rellm instance,
which is worth spelling out -- e.g. they can pay-gate features like Facebook sync themselves, the
same way this very server might, if they set up their own Facebook developer account.
-}
additionalNote : PurchaseType -> String
additionalNote type_ =
    case type_ of
        PURCHASETYPERELLMHOSTING ->
            " You get full admin access to your own Rellm instance -- e.g. you can pay-gate features like Facebook sync yourself, if you set up your own Facebook developer account."

        PURCHASETYPEMEDIASTORAGE ->
            ""

        PURCHASETYPEAIGRANTS ->
            ""

        PURCHASETYPEPERMISSIONSACCESS ->
            ""

        PurchaseTypeUnrecognized_ _ ->
            ""


{-| A byte count -> "1.5GB"/"100MB"/"512KB"/"3B" -- binary (1024-based) units, mirroring
`backend/src/logic/market_summary.rs`'s `humanize_bytes` exactly.
-}
humanizeBytes : Int -> String
humanizeBytes bytes =
    let
        kb : Int
        kb =
            1024

        mb : Int
        mb =
            kb * 1024

        gb : Int
        gb =
            mb * 1024
    in
    if bytes >= gb then
        formatTrimmedDecimal (toFloat bytes / toFloat gb) ++ "GB"

    else if bytes >= mb then
        formatTrimmedDecimal (toFloat bytes / toFloat mb) ++ "MB"

    else if bytes >= kb then
        formatTrimmedDecimal (toFloat bytes / toFloat kb) ++ "KB"

    else
        String.fromInt bytes ++ "B"


{-| A token count -> "100k"/"1.5M"/"500" -- decimal (1000-based) units, since these are tokens,
not bytes. Mirrors `backend/src/logic/market_summary.rs`'s `humanize_count`.
-}
humanizeCount : Int -> String
humanizeCount count =
    let
        k : Int
        k =
            1000

        m : Int
        m =
            k * 1000
    in
    if count >= m then
        formatTrimmedDecimal (toFloat count / toFloat m) ++ "M"

    else if count >= k then
        formatTrimmedDecimal (toFloat count / toFloat k) ++ "k"

    else
        String.fromInt count


{-| One decimal place, trailing ".0" dropped ("1.0" -> "1", "1.5" -> "1.5").
-}
formatTrimmedDecimal : Float -> String
formatTrimmedDecimal value =
    let
        rounded : Float
        rounded =
            toFloat (round (value * 10)) / 10

        whole : Int
        whole =
            floor rounded

        tenths : Int
        tenths =
            round ((rounded - toFloat whole) * 10)
    in
    if tenths == 0 then
        String.fromInt whole

    else
        String.fromInt whole ++ "." ++ String.fromInt tenths
