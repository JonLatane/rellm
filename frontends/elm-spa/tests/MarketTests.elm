module MarketTests exposing (suite)

{-| Tests for `Components.Market.priceLabel`/`productName`/`productDescription` -- the
price/name/Markdown-description trio shown on `MarketPage`'s tier cards (price + name only) and
`ProductPage`'s detail view (all three). `productName`/`productDescription` are implicit
(Elm-computed from the product's own details) for every `PurchaseType` except
`PURCHASE_TYPE_PERMISSIONS_ACCESS`, which is admin-authored (`PermissionsAccessSubscriptionDetails.name`/
`.description`) since a permissions bundle has no generically-derivable name.
-}

import Components.Market as Market
import Expect
import Proto.Rellm exposing (MarketProduct, defaultMarketProduct)
import Proto.Rellm.FulfillmentStatus exposing (FulfillmentStatus(..))
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
    describe "Components.Market"
        [ describe "priceLabel"
            [ test "monthly price gets a /mo suffix" <|
                \_ ->
                    product PURCHASETYPEMEDIASTORAGE
                        PURCHASEPERIODMONTHLY
                        100
                        Market.usdCurrencyCode
                        (ProductDetails.MediaStorageSubscriptionDetails
                            { allocationBytes = Conversions.int64FromInt (1024 * 1024 * 1024) }
                        )
                        |> Market.priceLabel
                        |> Expect.equal "$1/mo"
            , test "indefinite (one-time) price has no suffix" <|
                \_ ->
                    product PURCHASETYPEMEDIASTORAGE
                        PURCHASEPERIODINDEFINITE
                        1000000
                        Market.usdCurrencyCode
                        (ProductDetails.MediaStorageSubscriptionDetails
                            { allocationBytes = Conversions.int64FromInt (1024 * 1024 * 1024) }
                        )
                        |> Market.priceLabel
                        |> Expect.equal "$10,000"
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
                        |> Market.priceLabel
                        |> Expect.equal "10 EUR/mo"
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
                        |> Market.priceLabel
                        |> Expect.equal "500 JPY/mo"
            ]
        , describe "productName"
            [ test "media storage" <|
                \_ ->
                    product PURCHASETYPEMEDIASTORAGE
                        PURCHASEPERIODMONTHLY
                        100
                        Market.usdCurrencyCode
                        (ProductDetails.MediaStorageSubscriptionDetails
                            { allocationBytes = Conversions.int64FromInt (5 * 1024 * 1024 * 1024) }
                        )
                        |> Market.productName
                        |> Expect.equal "5GB Media Storage"
            , test "AI grants joins multiple model display names with an Oxford comma" <|
                \_ ->
                    product PURCHASETYPEAIGRANTS
                        PURCHASEPERIODMONTHLY
                        200
                        Market.usdCurrencyCode
                        (ProductDetails.AiGrantSubscriptionDetails
                            { aiProviderId = "prov1"
                            , modelNames = [ "gemini-3-pro-image", "gemini-3.1-flash-image", "gemini-2.5-flash-image" ]
                            , tokens = Conversions.int64FromInt 100000
                            }
                        )
                        |> Market.productName
                        |> Expect.equal "100k tokens for Nano Banana Pro, Nano Banana Flash, and Nano Banana"
            , test "Rellm hosting" <|
                \_ ->
                    product PURCHASETYPERELLMHOSTING
                        PURCHASEPERIODMONTHLY
                        1500
                        Market.usdCurrencyCode
                        (ProductDetails.RellmHostingSubscriptionDetails
                            { dbSizeBytes = Conversions.int64FromInt (1024 * 1024 * 1024)
                            , minioSizeBytes = Conversions.int64FromInt (5 * 1024 * 1024 * 1024)
                            , additionalDescription = ""
                            , domain = ""
                            , contactEmail = ""
                            , additionalInformation = ""
                            , fulfillmentStatus = FULFILLMENTSTATUSAWAITINGHOSTADMIN
                            , fulfillmentNotes = []
                            }
                        )
                        |> Market.productName
                        |> Expect.equal "1GB DB + 5GB Object Storage"
            , test "permissions access uses the admin-authored name verbatim" <|
                \_ ->
                    product PURCHASETYPEPERMISSIONSACCESS
                        PURCHASEPERIODMONTHLY
                        500
                        Market.usdCurrencyCode
                        (ProductDetails.PermissionsAccessSubscriptionDetails
                            { permissions = [ SYNCEVENTSTOFACEBOOK, SYNCPOSTSTOFACEBOOK ]
                            , name = "Facebook Sync Access"
                            , description = "Sync your posts and events to Facebook."
                            }
                        )
                        |> Market.productName
                        |> Expect.equal "Facebook Sync Access"
            ]
        , describe "productDescription"
            [ test "media storage fills in the actual size" <|
                \_ ->
                    product PURCHASETYPEMEDIASTORAGE
                        PURCHASEPERIODMONTHLY
                        100
                        Market.usdCurrencyCode
                        (ProductDetails.MediaStorageSubscriptionDetails
                            { allocationBytes = Conversions.int64FromInt (5 * 1024 * 1024 * 1024) }
                        )
                        |> Market.productDescription
                        |> Expect.equal
                            "Extra room for photos, videos, and other media uploads -- includes **5GB** of storage, replacing (not adding to) whatever quota you already have."
            , test "AI grants fills in tokens and model names" <|
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
                        |> Market.productDescription
                        |> Expect.equal
                            "Tokens for AI-powered image generation -- includes **100k** tokens for Nano Banana Pro, replacing (not adding to) any existing balance for these models."
            , test "Rellm hosting appends the admin's additional description as an extra paragraph" <|
                \_ ->
                    product PURCHASETYPERELLMHOSTING
                        PURCHASEPERIODMONTHLY
                        1500
                        Market.usdCurrencyCode
                        (ProductDetails.RellmHostingSubscriptionDetails
                            { dbSizeBytes = Conversions.int64FromInt (1024 * 1024 * 1024)
                            , minioSizeBytes = Conversions.int64FromInt (5 * 1024 * 1024 * 1024)
                            , additionalDescription = "Comes with a free .rellm.org subdomain for the first year."
                            , domain = ""
                            , contactEmail = ""
                            , additionalInformation = ""
                            , fulfillmentStatus = FULFILLMENTSTATUSAWAITINGHOSTADMIN
                            , fulfillmentNotes = []
                            }
                        )
                        |> Market.productDescription
                        |> Expect.equal
                            ("Your own Rellm instance, hosted and fully admin-controlled by you -- includes a **1GB** database and **5GB** of object storage.\n\n"
                                ++ "You get full admin access to your own Rellm instance -- e.g. you can pay-gate features like Facebook sync "
                                ++ "yourself, if you set up your own Facebook developer account.\n\n"
                                ++ "Comes with a free .rellm.org subdomain for the first year."
                            )
            , test "Rellm hosting with no additional description omits the extra paragraph" <|
                \_ ->
                    product PURCHASETYPERELLMHOSTING
                        PURCHASEPERIODMONTHLY
                        1500
                        Market.usdCurrencyCode
                        (ProductDetails.RellmHostingSubscriptionDetails
                            { dbSizeBytes = Conversions.int64FromInt (1024 * 1024 * 1024)
                            , minioSizeBytes = Conversions.int64FromInt (5 * 1024 * 1024 * 1024)
                            , additionalDescription = ""
                            , domain = ""
                            , contactEmail = ""
                            , additionalInformation = ""
                            , fulfillmentStatus = FULFILLMENTSTATUSAWAITINGHOSTADMIN
                            , fulfillmentNotes = []
                            }
                        )
                        |> Market.productDescription
                        |> Expect.equal
                            ("Your own Rellm instance, hosted and fully admin-controlled by you -- includes a **1GB** database and **5GB** of object storage.\n\n"
                                ++ "You get full admin access to your own Rellm instance -- e.g. you can pay-gate features like Facebook sync "
                                ++ "yourself, if you set up your own Facebook developer account."
                            )
            , test "permissions access uses the admin-authored description verbatim" <|
                \_ ->
                    product PURCHASETYPEPERMISSIONSACCESS
                        PURCHASEPERIODMONTHLY
                        500
                        Market.usdCurrencyCode
                        (ProductDetails.PermissionsAccessSubscriptionDetails
                            { permissions = [ SYNCEVENTSTOFACEBOOK, SYNCPOSTSTOFACEBOOK ]
                            , name = "Facebook Sync Access"
                            , description = "Sync your posts and events to Facebook."
                            }
                        )
                        |> Market.productDescription
                        |> Expect.equal "Sync your posts and events to Facebook."
            ]
        ]
