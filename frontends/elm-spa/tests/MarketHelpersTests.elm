module MarketHelpersTests exposing (suite)

{-| Tests for `Components.Market`'s smaller pure helpers -- everything `MarketTests.elm` doesn't
already cover via `priceLabel`/`productName`/`productDescription` (which exercise `formatAmount`
indirectly, end to end). These are the bits `MarketPage`/`ProductPage`/the admin product form call
directly: currency/type/period labels, slot-counting, sold-out detection, and the AI model nickname
lookup.
-}

import Components.Market as Market
import Expect
import Proto.Rellm exposing (MarketProduct, defaultMarketProduct)
import Proto.Rellm.MarketProduct exposing (Details)
import Proto.Rellm.MarketProduct.Details as ProductDetails
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PurchasePeriod exposing (PurchasePeriod(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Components.Market"
        [ currencyLabelSuite
        , amountInputLabelSuite
        , formatAmountSuite
        , purchaseTypeLabelSuite
        , purchaseTypeEmojiSuite
        , purchaseTypeDescriptionSuite
        , purchasePeriodLabelSuite
        , periodSortOrderSuite
        , slotsAvailableTextSuite
        , isSoldOutSuite
        , permissionsForProductSuite
        , aiModelDisplayNameSuite
        ]


currencyLabelSuite : Test
currencyLabelSuite =
    describe "currencyLabel"
        [ test "known code returns alpha code and name" <|
            \_ -> Market.currencyLabel 840 |> Expect.equal "USD - US Dollar"
        , test "another known code" <|
            \_ -> Market.currencyLabel 392 |> Expect.equal "JPY - Japanese Yen"
        , test "unknown code falls back to the bare numeric code" <|
            \_ -> Market.currencyLabel 999 |> Expect.equal "999"
        ]


amountInputLabelSuite : Test
amountInputLabelSuite =
    describe "amountInputLabel"
        [ test "zero-decimal currency (JPY) explains whole units, no decimal" <|
            \_ ->
                Market.amountInputLabel 392
                    |> Expect.equal "Amount (whole units, no decimal -- e.g. 500 = ¥500)"
        , test "every other currency explains cents" <|
            \_ ->
                Market.amountInputLabel 840
                    |> Expect.equal "Amount (in cents -- e.g. 500 = $5.00)"
        , test "an unrecognized currency still gets the cents label (only JPY is zero-decimal)" <|
            \_ ->
                Market.amountInputLabel 999
                    |> Expect.equal "Amount (in cents -- e.g. 500 = $5.00)"
        ]


formatAmountSuite : Test
formatAmountSuite =
    describe "formatAmount"
        [ test "USD whole-dollar amount drops the minor-unit part entirely" <|
            \_ -> Market.formatAmount 500 Market.usdCurrencyCode |> Expect.equal "$5"
        , test "USD amount with cents keeps a zero-padded minor-unit part" <|
            \_ -> Market.formatAmount 1050 Market.usdCurrencyCode |> Expect.equal "$10.50"
        , test "USD amount comma-groups large major-unit thousands" <|
            \_ -> Market.formatAmount 100000000 Market.usdCurrencyCode |> Expect.equal "$1,000,000"
        , test "non-USD currency appends its alpha code instead of a symbol" <|
            \_ -> Market.formatAmount 1000 978 |> Expect.equal "10 EUR"
        , test "zero-decimal currency (JPY) is not divided by 100" <|
            \_ -> Market.formatAmount 500 392 |> Expect.equal "500 JPY"
        , test "a currency outside allCurrencies falls back to a bare numeric-code label" <|
            \_ -> Market.formatAmount 500 999 |> Expect.equal "5 (currency 999)"
        ]


purchaseTypeLabelSuite : Test
purchaseTypeLabelSuite =
    describe "purchaseTypeLabel"
        [ test "media storage" <| \_ -> Market.purchaseTypeLabel PURCHASETYPEMEDIASTORAGE |> Expect.equal "Media Storage"
        , test "AI grants" <| \_ -> Market.purchaseTypeLabel PURCHASETYPEAIGRANTS |> Expect.equal "AI Access"
        , test "Rellm hosting" <| \_ -> Market.purchaseTypeLabel PURCHASETYPERELLMHOSTING |> Expect.equal "Rellm Hosting"
        , test "permissions access" <| \_ -> Market.purchaseTypeLabel PURCHASETYPEPERMISSIONSACCESS |> Expect.equal "Extra Features"
        , test "an unrecognized value falls back to Unknown" <|
            \_ -> Market.purchaseTypeLabel (PurchaseTypeUnrecognized_ 99) |> Expect.equal "Unknown"
        ]


purchaseTypeEmojiSuite : Test
purchaseTypeEmojiSuite =
    describe "purchaseTypeEmoji"
        [ test "every known PurchaseType has a distinct, non-empty emoji" <|
            \_ ->
                let
                    emojis : List String
                    emojis =
                        Market.allPurchaseTypes |> List.map Market.purchaseTypeEmoji
                in
                Expect.all
                    [ \_ -> emojis |> List.all (\e -> not (String.isEmpty e)) |> Expect.equal True
                    , \_ -> List.length (List.foldl (\e acc -> if List.member e acc then acc else e :: acc) [] emojis) |> Expect.equal (List.length emojis)
                    ]
                    ()
        ]


purchaseTypeDescriptionSuite : Test
purchaseTypeDescriptionSuite =
    describe "purchaseTypeDescription"
        [ test "every known PurchaseType has a non-empty description" <|
            \_ ->
                Market.allPurchaseTypes
                    |> List.map Market.purchaseTypeDescription
                    |> List.all (\d -> not (String.isEmpty d))
                    |> Expect.equal True
        , test "an unrecognized value falls back to an empty string" <|
            \_ -> Market.purchaseTypeDescription (PurchaseTypeUnrecognized_ 99) |> Expect.equal ""
        ]


purchasePeriodLabelSuite : Test
purchasePeriodLabelSuite =
    describe "purchasePeriodLabel"
        [ test "indefinite" <| \_ -> Market.purchasePeriodLabel PURCHASEPERIODINDEFINITE |> Expect.equal "One-Time"
        , test "annual" <| \_ -> Market.purchasePeriodLabel PURCHASEPERIODANNUAL |> Expect.equal "Yearly"
        , test "monthly" <| \_ -> Market.purchasePeriodLabel PURCHASEPERIODMONTHLY |> Expect.equal "Monthly"
        , test "an unrecognized value falls back to Unknown" <|
            \_ -> Market.purchasePeriodLabel (PurchasePeriodUnrecognized_ 99) |> Expect.equal "Unknown"
        ]


periodSortOrderSuite : Test
periodSortOrderSuite =
    describe "periodSortOrder"
        [ test "monthly sorts before annual, which sorts before indefinite" <|
            \_ ->
                [ PURCHASEPERIODINDEFINITE, PURCHASEPERIODANNUAL, PURCHASEPERIODMONTHLY ]
                    |> List.sortBy Market.periodSortOrder
                    |> Expect.equal [ PURCHASEPERIODMONTHLY, PURCHASEPERIODANNUAL, PURCHASEPERIODINDEFINITE ]
        ]


product : PurchaseType -> Int -> Int -> Maybe Details -> MarketProduct
product type_ availableCount soldCount details =
    { defaultMarketProduct
        | type_ = type_
        , availableCount = availableCount
        , soldCount = soldCount
        , details = details
    }


slotsAvailableTextSuite : Test
slotsAvailableTextSuite =
    describe "slotsAvailableText"
        [ test "availableCount 0 means no cap -- nothing to show" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 0 0 Nothing |> Market.slotsAvailableText |> Expect.equal Nothing
        , test "shows the remaining count when slots are capped" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 5 2 Nothing |> Market.slotsAvailableText |> Expect.equal (Just "3 Slots Available")
        , test "floors at 0 once every slot is sold, never goes negative" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 5 7 Nothing |> Market.slotsAvailableText |> Expect.equal (Just "0 Slots Available")
        ]


isSoldOutSuite : Test
isSoldOutSuite =
    describe "isSoldOut"
        [ test "availableCount 0 (no cap) is never sold out, regardless of soldCount" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 0 1000 Nothing |> Market.isSoldOut |> Expect.equal False
        , test "soldCount below availableCount is not sold out" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 5 4 Nothing |> Market.isSoldOut |> Expect.equal False
        , test "soldCount equal to availableCount is sold out" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 5 5 Nothing |> Market.isSoldOut |> Expect.equal True
        , test "soldCount past availableCount is still sold out" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 5 6 Nothing |> Market.isSoldOut |> Expect.equal True
        ]


permissionsForProductSuite : Test
permissionsForProductSuite =
    describe "permissionsForProduct"
        [ test "a PERMISSIONS_ACCESS product returns its granted permissions" <|
            \_ ->
                product PURCHASETYPEPERMISSIONSACCESS
                    0
                    0
                    (Just
                        (ProductDetails.PermissionsAccessSubscriptionDetails
                            { permissions = [ SYNCEVENTSTOFACEBOOK, SYNCPOSTSTOFACEBOOK ]
                            , name = "Facebook Sync Access"
                            , description = "Sync your posts and events to Facebook."
                            }
                        )
                    )
                    |> Market.permissionsForProduct
                    |> Expect.equal [ SYNCEVENTSTOFACEBOOK, SYNCPOSTSTOFACEBOOK ]
        , test "any other product type has nothing to badge, even with details set" <|
            \_ -> product PURCHASETYPEMEDIASTORAGE 0 0 Nothing |> Market.permissionsForProduct |> Expect.equal []
        , test "a product with no details at all has nothing to badge" <|
            \_ -> product PURCHASETYPEPERMISSIONSACCESS 0 0 Nothing |> Market.permissionsForProduct |> Expect.equal []
        ]


aiModelDisplayNameSuite : Test
aiModelDisplayNameSuite =
    describe "aiModelDisplayName"
        [ test "gemini-3-pro-image gets its Nano Banana Pro nickname" <|
            \_ -> Market.aiModelDisplayName "gemini-3-pro-image" |> Expect.equal "Nano Banana Pro"
        , test "gemini-2.5-flash-image gets its Nano Banana nickname" <|
            \_ -> Market.aiModelDisplayName "gemini-2.5-flash-image" |> Expect.equal "Nano Banana"
        , test "an unrecognized model name passes through unchanged" <|
            \_ -> Market.aiModelDisplayName "some-future-model" |> Expect.equal "some-future-model"
        ]
