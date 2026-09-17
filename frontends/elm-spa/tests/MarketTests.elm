module MarketTests exposing (suite)

{-| Tests for `Components.Market.productSummary` -- the pedantically-clear "what am I buying"
sentence shown on `ProductPage`/`MarketPage` (and mirrored server-side by
`backend/src/logic/market_summary.rs` for the `/market/product/:id` SSR preview; these cases
mirror that module's own Rust tests so the two stay in sync).
-}

import Components.Market as Market
import Expect
import Proto.Rellm exposing (MarketProduct, defaultMarketProduct)
import Proto.Rellm.MarketProduct exposing (Details)
import Proto.Rellm.MarketProduct.Details as ProductDetails
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PurchasePeriod exposing (PurchasePeriod(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Shared.Conversions as Conversions
import Test exposing (Test, describe, test)


product : PurchaseType -> PurchasePeriod -> Int -> Int -> Details -> MarketProduct
product type_ period amount currency details =
    { defaultMarketProduct
        | type_ = type_
        , period = period
        , amount = amount
        , currency = currency
        , details = Just details
    }


suite : Test
suite =
    describe "Components.Market.productSummary"
        [ test "monthly media storage" <|
            \_ ->
                product PURCHASETYPEMEDIASTORAGE
                    PURCHASEPERIODMONTHLY
                    100
                    Market.usdCurrencyCode
                    (ProductDetails.MediaStorageSubscriptionDetails
                        { allocationBytes = Conversions.int64FromInt (1024 * 1024 * 1024 + 512 * 1024 * 1024) }
                    )
                    |> Market.productSummary
                    |> Expect.equal "1.5GB storage for $1/mo"
        , test "indefinite media storage reads lifetime" <|
            \_ ->
                product PURCHASETYPEMEDIASTORAGE
                    PURCHASEPERIODINDEFINITE
                    1000000
                    Market.usdCurrencyCode
                    (ProductDetails.MediaStorageSubscriptionDetails
                        { allocationBytes = Conversions.int64FromInt (1024 * 1024 * 1024) }
                    )
                    |> Market.productSummary
                    |> Expect.equal "1GB lifetime storage for $10,000"
        , test "monthly AI grants uses Nano Banana display name" <|
            \_ ->
                product PURCHASETYPEAIGRANTS
                    PURCHASEPERIODMONTHLY
                    200
                    Market.usdCurrencyCode
                    (ProductDetails.AiGrantSubscriptionDetails
                        { aiProviderId = "prov1"
                        , modelNames = [ "gemini-3-pro-image" ]
                        , tokens = Conversions.int64FromInt 100000
                        }
                    )
                    |> Market.productSummary
                    |> Expect.equal "100k tokens of Nano Banana Pro image generation for $2/mo"
        , test "monthly Rellm hosting includes the admin-access note" <|
            \_ ->
                product PURCHASETYPERELLMHOSTING
                    PURCHASEPERIODMONTHLY
                    1500
                    Market.usdCurrencyCode
                    (ProductDetails.RellmHostingSubscriptionDetails
                        { dbSizeBytes = Conversions.int64FromInt (1024 * 1024 * 1024)
                        , minioSizeBytes = Conversions.int64FromInt (5 * 1024 * 1024 * 1024)
                        , domain = ""
                        , contactEmail = ""
                        , additionalInformation = ""
                        }
                    )
                    |> Market.productSummary
                    |> Expect.equal
                        ("Rellm hosting, 1GB DB + 5GB MinIO for $15/mo You get full admin access to "
                            ++ "your own Rellm instance -- e.g. you can pay-gate features like Facebook sync "
                            ++ "yourself, if you set up your own Facebook developer account."
                        )
        , test "monthly permissions access lists humanized permission names" <|
            \_ ->
                product PURCHASETYPEPERMISSIONSACCESS
                    PURCHASEPERIODMONTHLY
                    500
                    Market.usdCurrencyCode
                    (ProductDetails.PermissionsAccessSubscriptionDetails
                        { permissions = [ SYNCEVENTSTOFACEBOOK, SYNCPOSTSTOFACEBOOK ] }
                    )
                    |> Market.productSummary
                    |> Expect.equal "access to Sync Events To Facebook, Sync Posts To Facebook for $5/mo"
        , test "non-USD currency uses alpha code, not symbol" <|
            \_ ->
                product PURCHASETYPEMEDIASTORAGE
                    PURCHASEPERIODMONTHLY
                    1000
                    978
                    -- EUR
                    (ProductDetails.MediaStorageSubscriptionDetails
                        { allocationBytes = Conversions.int64FromInt (1024 * 1024 * 1024) }
                    )
                    |> Market.productSummary
                    |> Expect.equal "1GB storage for 10 EUR/mo"
        , test "zero-decimal currency (JPY) is not divided by 100" <|
            \_ ->
                product PURCHASETYPEMEDIASTORAGE
                    PURCHASEPERIODMONTHLY
                    500
                    392
                    -- JPY -- zero-decimal, so 500 means 500 yen, not 5 yen
                    (ProductDetails.MediaStorageSubscriptionDetails
                        { allocationBytes = Conversions.int64FromInt (1024 * 1024 * 1024) }
                    )
                    |> Market.productSummary
                    |> Expect.equal "1GB storage for 500 JPY/mo"
        ]
