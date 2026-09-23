module Components.Market exposing
    ( HostingForm
    , PurchaseState(..)
    , aiModelDisplayName
    , allCurrencies
    , allPurchaseTypes
    , amountInputLabel
    , cancelMarketSubscription
    , createMarketProduct
    , currencyLabel
    , defaultHostingForm
    , formatAmount
    , getMarketProducts
    , getMarketSubscriptionsForFulfillment
    , hostingDetailsFromForm
    , isSoldOut
    , makeMarketPurchase
    , periodSortOrder
    , permissionsForProduct
    , priceLabel
    , productDescription
    , productName
    , purchasePeriodLabel
    , purchaseTypeDescription
    , purchaseTypeEmoji
    , purchaseTypeLabel
    , slotsAvailableText
    , updateMarketProduct
    , updateMarketSubscription
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
        , GetMarketSubscriptionsResponse
        , MakeMarketPurchaseRequest
        , MakeMarketPurchaseResponse
        , MarketProduct
        , MarketSubscription
        , RellmHostingPurchaseDetails
        , defaultGetMarketProductsRequest
        , defaultRellmHostingPurchaseDetails
        )
import Proto.Rellm.GetMarketSubscriptionsRequestType exposing (GetMarketSubscriptionsRequestType(..))
import Proto.Rellm.MarketProduct.Details as ProductDetails
import Proto.Rellm.Permission exposing (Permission)
import Proto.Rellm.PurchasePeriod exposing (PurchasePeriod(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Shared.ByteFormat as ByteFormat
import Shared.Conversions as Conversions
import Task exposing (Task)


{-| ISO 4217 numeric code 840 -- the default currency for a freshly-opened admin product form (see
`allCurrencies`).
-}
usdCurrencyCode : Int
usdCurrencyCode =
    840


{-| The currencies an admin can pick in the product form's currency selector -- matches
`backend/src/logic/stripe_sync.rs`'s `currency_code` exactly (a small, common-currency set Stripe
supports well), so every currency offered here is actually purchasable. `formatAmount` falls back to
a generic "<amount> (currency <code>)" for any other currency code (e.g. a product created by some
other client with a currency not in this list).
-}
allCurrencies : List { code : Int, alpha : String, name : String }
allCurrencies =
    [ { code = 840, alpha = "USD", name = "US Dollar" }
    , { code = 978, alpha = "EUR", name = "Euro" }
    , { code = 826, alpha = "GBP", name = "British Pound" }
    , { code = 124, alpha = "CAD", name = "Canadian Dollar" }
    , { code = 36, alpha = "AUD", name = "Australian Dollar" }
    , { code = 392, alpha = "JPY", name = "Japanese Yen" }
    , { code = 756, alpha = "CHF", name = "Swiss Franc" }
    ]


{-| A currency's dropdown-option label, e.g. "USD - US Dollar". Falls back to a bare numeric code
for anything not in `allCurrencies`.
-}
currencyLabel : Int -> String
currencyLabel code =
    allCurrencies
        |> List.filter (\c -> c.code == code)
        |> List.head
        |> Maybe.map (\c -> c.alpha ++ " - " ++ c.name)
        |> Maybe.withDefault (String.fromInt code)


{-| Whether `currency` has no minor unit (e.g. Japanese yen has no "cents") -- mirrors
`backend/src/logic/stripe_sync.rs`'s `is_zero_decimal_currency` exactly. `MarketProduct.amount` is
still always a plain integer either way -- for a zero-decimal currency it's simply the whole-unit
amount itself (e.g. `500` = &yen;500). Used both by `formatAmount` (so a zero-decimal amount isn't
divided by 100) and `amountInputLabel` (so the admin form's amount field is clearly labeled).
-}
isZeroDecimalCurrency : Int -> Bool
isZeroDecimalCurrency currency =
    currency == 392


{-| The admin product form's amount-input placeholder/label -- makes it explicit whether the number
typed there means cents (every currency except a zero-decimal one) or whole units (e.g. "Amount (in
yen, no decimal)" for JPY, not "Amount (in cents)").
-}
amountInputLabel : Int -> String
amountInputLabel currency =
    if isZeroDecimalCurrency currency then
        "Amount (whole units, no decimal -- e.g. 500 = ¥500)"

    else
        "Amount (in cents -- e.g. 500 = $5.00)"


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


{-| Cancels a `MarketSubscription` -- only ever sets `canceledAt` on the returned subscription; it
does _not_ revoke the subscription's entitlement (media storage quota/granted permissions) right
away. That only happens once the server's `renew_market_subscriptions` background job later
processes it (once both `canceledAt` and `renewsAt` have passed) and sets `serviceTerminatedAt`, so
a canceled-but-not-yet-terminated subscription still functions normally until its current billing
period actually runs out.
-}
cancelMarketSubscription :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MarketSubscription
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription )
cancelMarketSubscription accountsPanelModel maybeAccountServer subscription =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.cancelMarketSubscription subscription
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Every `PURCHASE_TYPE_RELLM_HOSTING` `MarketSubscription` across _every_ buyer on the server --
admin-only server-side (see `GetMarketSubscriptionsRequestType.GETMARKETSUBSCRIPTIONSREQUESTFORFULFILLMENTADMIN`'s
own proto doc; a non-admin caller gets a permission error). Backs
`Components.Pages.MarketFulfillmentPage`'s `/market/fulfillment` table -- the admin-only "what Rellm
Hosting orders still need setting up" view, as opposed to `getMarketProducts`'/a profile's own
`GETMARKETSUBSCRIPTIONSREQUESTFORPURCHASE`-scoped (self-only) subscriptions list.
-}
getMarketSubscriptionsForFulfillment :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMarketSubscriptionsResponse )
getMarketSubscriptionsForFulfillment accountsPanelModel maybeAccountServer =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getMarketSubscriptions
                { requestType = GETMARKETSUBSCRIPTIONSREQUESTFORFULFILLMENTADMIN }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| Admin-only (server-side gated; even the subscription's own buyer is rejected) -- sets
`RellmHostingSubscriptionDetails.fulfilled` and/or appends to `fulfillmentNotes` on a
`PURCHASE_TYPE_RELLM_HOSTING` subscription (rejected for any other type). See
`Rellm.updateMarketSubscription`'s own proto doc for the full append-only contract: `subscription`'s
`fulfillmentNotes` must carry every note already stored, byte-for-byte, in order, with at most new
ones appended (each new note's `userId` must equal the calling admin's own id, and its `note` can't
be blank) -- the server rejects any edit/reorder/removal of an existing note, and always overwrites
`createdAt` on new notes itself. Callers should always start from the subscription's last-fetched
`fulfillmentNotes` list and only ever append, never reconstruct it.
-}
updateMarketSubscription :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> MarketSubscription
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription )
updateMarketSubscription accountsPanelModel maybeAccountServer subscription =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.updateMarketSubscription subscription
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


{-| The 4 sections `Components.Pages.MarketPage` always renders for an admin (and, for a regular
user, renders only when non-empty) -- fixed display order, not the proto enum's own declaration
order. Extra Features sits right under Media Storage (Jon's own preferred ordering), ahead of AI
Access/Rellm Hosting.
-}
allPurchaseTypes : List PurchaseType
allPurchaseTypes =
    [ PURCHASETYPEMEDIASTORAGE, PURCHASETYPEPERMISSIONSACCESS, PURCHASETYPEAIGRANTS, PURCHASETYPERELLMHOSTING ]


purchaseTypeLabel : PurchaseType -> String
purchaseTypeLabel type_ =
    case type_ of
        PURCHASETYPEMEDIASTORAGE ->
            "Media Storage"

        PURCHASETYPEAIGRANTS ->
            "AI Access"

        PURCHASETYPERELLMHOSTING ->
            "Rellm Hosting"

        PURCHASETYPEPERMISSIONSACCESS ->
            "Extra Features"

        PurchaseTypeUnrecognized_ _ ->
            "Unknown"


{-| A large "product image"-sized glyph for a `PurchaseType` section heading on `MarketPage`/a
product's icon on `ProductPage` -- this app has no actual product photography (`MarketProduct` has
no image field), so a big emoji stands in, the same way `Shared.AccountsPanel.RellmServers`' own
`.server-logo-emoji` treatment stands in for a server's real logo.
-}
purchaseTypeEmoji : PurchaseType -> String
purchaseTypeEmoji type_ =
    case type_ of
        PURCHASETYPEMEDIASTORAGE ->
            "💾"

        PURCHASETYPEAIGRANTS ->
            "🤖"

        PURCHASETYPERELLMHOSTING ->
            "🌐"

        PURCHASETYPEPERMISSIONSACCESS ->
            "✨"

        PurchaseTypeUnrecognized_ _ ->
            "📦"


{-| A one-line blurb under each `MarketPage` section heading, explaining what that `PurchaseType`
actually is before its tiers are shown.
-}
purchaseTypeDescription : PurchaseType -> String
purchaseTypeDescription type_ =
    case type_ of
        PURCHASETYPEMEDIASTORAGE ->
            "Extra room for photos, videos, and other media uploads."

        PURCHASETYPEAIGRANTS ->
            "Tokens for AI-powered image generation."

        PURCHASETYPERELLMHOSTING ->
            "Your own Rellm instance, hosted and fully admin-controlled by you."

        PURCHASETYPEPERMISSIONSACCESS ->
            "Unlock additional permissions and capabilities on this server."

        PurchaseTypeUnrecognized_ _ ->
            ""


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


{-| Sort key for `MarketPage`'s per-section tier row -- cheapest monthly first, then annual tiers by
price, then indefinite (lifetime) tiers by price, matching how a shopper actually compares "$/mo"
options before "one-time" ones. Pair with `product.amount` as a secondary sort key (smallest to
largest) to get the full ordering Jon asked for.
-}
periodSortOrder : PurchasePeriod -> Int
periodSortOrder period =
    case period of
        PURCHASEPERIODMONTHLY ->
            0

        PURCHASEPERIODANNUAL ->
            1

        PURCHASEPERIODINDEFINITE ->
            2

        PurchasePeriodUnrecognized_ _ ->
            3


{-| `amount` is in the currency's smallest unit (e.g. USD cents; already the whole-unit amount for a
zero-decimal currency like JPY -- see `isZeroDecimalCurrency`), matching how Stripe itself wants
amounts -- see `MarketProduct.amount`'s own proto doc. Mirrors
`backend/src/logic/market_summary.rs`'s `format_price` exactly (`$` for USD, "<amount> <ALPHA3>" for
every other currency in `allCurrencies`, comma-grouped major-unit thousands, minor-unit part dropped
entirely when zero -- `100` -> `"$1"`, not `"$1.00"`), so the in-app product page and the SSR preview
read identically. Falls back to a generic "<amount> (currency <code>)" for any currency not in
`allCurrencies`.
-}
formatAmount : Int -> Int -> String
formatAmount amount currency =
    let
        formatted : String
        formatted =
            formatAmountWithCommas amount currency
    in
    case currency of
        840 ->
            "$" ++ formatted

        978 ->
            formatted ++ " EUR"

        826 ->
            formatted ++ " GBP"

        124 ->
            formatted ++ " CAD"

        36 ->
            formatted ++ " AUD"

        392 ->
            formatted ++ " JPY"

        756 ->
            formatted ++ " CHF"

        _ ->
            formatted ++ " (currency " ++ String.fromInt currency ++ ")"


formatAmountWithCommas : Int -> Int -> String
formatAmountWithCommas amount currency =
    if isZeroDecimalCurrency currency then
        groupWithCommas amount

    else
        let
            major : Int
            major =
                amount // 100

            minor : Int
            minor =
                abs (remainderBy 100 amount)

            majorGrouped : String
            majorGrouped =
                groupWithCommas major
        in
        if minor == 0 then
            majorGrouped

        else
            majorGrouped ++ "." ++ String.padLeft 2 '0' (String.fromInt minor)


{-| `1234567` -> `"1,234,567"` -- mirrors `market_summary.rs`'s own comma-grouping loop exactly.
-}
groupWithCommas : Int -> String
groupWithCommas n =
    String.fromInt n
        |> String.reverse
        |> String.toList
        |> List.indexedMap
            (\i c ->
                if i /= 0 && modBy 3 i == 0 then
                    [ ',', c ]

                else
                    [ c ]
            )
        |> List.concat
        |> String.fromList
        |> String.reverse


{-| `formatAmount` plus its billing-cycle suffix, e.g. "$15/mo", "$120/yr", "$1" (no suffix for a
`PURCHASE_PERIOD_INDEFINITE` one-time product). Shown as the large, top-of-tier price on
`MarketPage`'s tier cards and `ProductPage`'s detail view -- see those modules' own doc for why the
price and `productName` are now two separate, deliberately terse lines rather than the old single
pedantic sentence.
-}
priceLabel : MarketProduct -> String
priceLabel product =
    formatAmount product.amount product.currency ++ periodSuffix product.period


{-| A short, one-line product name -- explicit (admin-authored) for `PURCHASE_TYPE_PERMISSIONS_ACCESS`
(`PermissionsAccessSubscriptionDetails.name`, since a permissions bundle can be any admin-chosen set
with no generically-derivable name -- see that field's own proto doc), implicitly computed from the
product's own details for the other three types (e.g. "5GB Media Storage", "100k tokens for Nano
Banana Pro", "1GB DB + 5GB Object Storage"). Shown below the price on `MarketPage`'s tier cards and
`ProductPage`'s detail view.
-}
productName : MarketProduct -> String
productName product =
    case product.details of
        Just (ProductDetails.MediaStorageSubscriptionDetails details) ->
            ByteFormat.humanizeBytes (Conversions.int64ToInt details.allocationBytes) ++ " Media Storage"

        Just (ProductDetails.AiGrantSubscriptionDetails details) ->
            humanizeCount (Conversions.int64ToInt details.tokens) ++ " tokens for " ++ aiModelNamesJoined details.modelNames

        Just (ProductDetails.RellmHostingSubscriptionDetails details) ->
            ByteFormat.humanizeBytes (Conversions.int64ToInt details.dbSizeBytes)
                ++ " DB + "
                ++ ByteFormat.humanizeBytes (Conversions.int64ToInt details.minioSizeBytes)
                ++ " Object Storage"

        Just (ProductDetails.PermissionsAccessSubscriptionDetails details) ->
            details.name

        Nothing ->
            "Rellm Market Product"


{-| A Markdown-formatted product description (see `Components.Markdown.view`) -- explicit
(admin-authored) for `PURCHASE_TYPE_PERMISSIONS_ACCESS` (`PermissionsAccessSubscriptionDetails.description`),
implicitly canned text (with the actual size/token/model amounts filled in) for the other three
types. `PURCHASE_TYPE_RELLM_HOSTING` additionally appends
`RellmHostingSubscriptionDetails.additionalDescription`, if the admin's set one, as an extra
paragraph below the canned text. Shown on `ProductPage`'s detail view only -- deliberately not on
`MarketPage`'s tier cards, which only ever show `priceLabel`/`productName` (see that module's own
doc).
-}
productDescription : MarketProduct -> String
productDescription product =
    case product.details of
        Just (ProductDetails.MediaStorageSubscriptionDetails details) ->
            "Extra room for photos, videos, and other media uploads -- includes **"
                ++ ByteFormat.humanizeBytes (Conversions.int64ToInt details.allocationBytes)
                ++ "** of storage, replacing (not adding to) whatever quota you already have."

        Just (ProductDetails.AiGrantSubscriptionDetails details) ->
            "Tokens for AI-powered image generation -- includes **"
                ++ humanizeCount (Conversions.int64ToInt details.tokens)
                ++ "** tokens for "
                ++ aiModelNamesJoined details.modelNames
                ++ ", replacing (not adding to) any existing balance for these models."

        Just (ProductDetails.RellmHostingSubscriptionDetails details) ->
            let
                canned : String
                canned =
                    "Your own Rellm instance, hosted and fully admin-controlled by you -- includes a **"
                        ++ ByteFormat.humanizeBytes (Conversions.int64ToInt details.dbSizeBytes)
                        ++ "** database and **"
                        ++ ByteFormat.humanizeBytes (Conversions.int64ToInt details.minioSizeBytes)
                        ++ "** of object storage.\n\n"
                        ++ "You get full admin access to your own Rellm instance -- e.g. you can pay-gate "
                        ++ "features like Facebook sync yourself, if you set up your own Facebook developer account."
            in
            if String.trim details.additionalDescription == "" then
                canned

            else
                canned ++ "\n\n" ++ details.additionalDescription

        Just (ProductDetails.PermissionsAccessSubscriptionDetails details) ->
            details.description

        Nothing ->
            ""


{-| "Nano Banana Pro" / "Nano Banana Pro and Nano Banana Flash" / "Nano Banana Pro, Nano Banana
Flash, and Nano Banana" -- an Oxford-comma join of `aiModelDisplayName`-nicknamed model names, used
by both `productName`/`productDescription` above. Falls back to "AI models" for a product with no
models configured yet (an incompletely-filled-out admin form).
-}
aiModelNamesJoined : List String -> String
aiModelNamesJoined modelNames =
    case List.map aiModelDisplayName modelNames of
        [] ->
            "AI models"

        [ only ] ->
            only

        [ first, second ] ->
            first ++ " and " ++ second

        many ->
            case List.reverse many of
                last_ :: rest ->
                    (List.reverse rest |> String.join ", ") ++ ", and " ++ last_

                [] ->
                    "AI models"


{-| "X Slots Available" (`availableCount - soldCount`, floored at 0) -- `Nothing` when
`availableCount == 0`, which means no cap at all (see that field's own proto doc), so there's
nothing worth showing. Shown as small text on both `MarketPage`'s tier cards and `ProductPage`'s
detail view.
-}
slotsAvailableText : MarketProduct -> Maybe String
slotsAvailableText product =
    if product.availableCount == 0 then
        Nothing

    else
        Just (String.fromInt (max 0 (product.availableCount - product.soldCount)) ++ " Slots Available")


{-| Mirrors `backend/src/rpcs/market/make_market_purchase.rs`'s own `product_sold_out` check
exactly -- `availableCount == 0` means no cap, so it's never sold out. Used to hide/replace the Buy
button client-side, same as `product.delistedAt /= Nothing` already does -- the server enforces this
regardless, this is just so a buyer doesn't hit an avoidable error.
-}
isSoldOut : MarketProduct -> Bool
isSoldOut product =
    product.availableCount > 0 && product.soldCount >= product.availableCount


{-| The `Permission`s a `PURCHASE_TYPE_PERMISSIONS_ACCESS` product grants -- `[]` for every other
`PurchaseType` (nothing to badge). Used by `MarketPage`'s tier cards to show the extra permissions
each Extra Features tier grants, as the same read-only badge chips `UserProfilePage`'s own
permissions section uses.
-}
permissionsForProduct : MarketProduct -> List Permission
permissionsForProduct product =
    case product.details of
        Just (ProductDetails.PermissionsAccessSubscriptionDetails details) ->
            details.permissions

        _ ->
            []


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
