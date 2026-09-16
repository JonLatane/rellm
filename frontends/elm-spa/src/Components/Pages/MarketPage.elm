module Components.Pages.MarketPage exposing (Model, Msg, fromShared, init, subscriptions, update, view)

{-| `/market` -- Rellm's Stripe-backed marketplace (`market.proto`). Lists every non-delisted
`MarketProduct` on `mainFrontendHost` (an Admin additionally sees delisted ones, per
`GetMarketProductsResponse.marketProducts`' own proto doc), with a "Buy" button per product that
starts a Stripe Checkout flow (`Components.Market.makeMarketPurchase`) and, on success, redirects
the browser straight to the returned `checkoutUrl` (`Browser.Navigation.load` -- a plain external
redirect, not an Elm route: see that field's own doc on why no `MarketPurchase`/`MarketSubscription`
exists yet at this point). An Admin also gets inline create/edit affordances for `MarketProduct`s
right on this list -- there's deliberately no separate admin page for it, to keep this feature's
scope tight (see the plan this was built from).

Always scoped to `shared.accounts.mainFrontendHost` -- like `Pages.Posts`/`Pages.Events`, there's no
federated "market on some other server" browsing here.

Mirrors `Components.Pages.PostsPage`/`Components.Pages.EventsPage`'s overall shape (a thin
`Pages.Market` wrapper around this module, `init`/`update`/`view`/`subscriptions`/`fromShared`), just
without those modules' own feed-paging/filtering machinery -- a marketplace's product list is small
and never paged.
-}

import Browser.Navigation
import Components.Market as Market
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Route as Route
import Grpc
import Html exposing (Html, button, div, h1, input, option, p, select, span, text, textarea)
import Html.Attributes exposing (class, disabled, placeholder, selected, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm
    exposing
        ( MarketProduct
        , RellmHostingPurchaseDetails
        , defaultAIGrantSubscriptionDetails
        , defaultMarketProduct
        , defaultMediaStorageSubscriptionDetails
        , defaultPermissionsAccessSubscriptionDetails
        , defaultRellmHostingSubscriptionDetails
        )
import Proto.Rellm.MarketProduct exposing (Details)
import Proto.Rellm.MarketProduct.Details as ProductDetails
import Proto.Rellm.PurchasePeriod exposing (PurchasePeriod(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Conversions as Conversions
import Task
import Time



-- MODEL


type alias Model =
    { products : ProductsState
    , addForm : Maybe ProductForm
    , rowEdits : Dict String ProductForm
    , purchases : Dict String Market.PurchaseState
    , hostingForms : Dict String Market.HostingForm
    }


type ProductsState
    = ProductsLoading
    | ProductsLoaded (List MarketProduct)
    | ProductsErrored String


{-| The Admin create/edit form for a `MarketProduct` -- every possible field across all three
`PurchaseType`s at once (only the ones relevant to `type_` are ever shown -- see `productFormView`),
kept as plain `String` inputs (parsed on Save) same as `StorageQuotaEdit`'s own pending-text
convention elsewhere in this app. `type_`/`period` are only actually editable while creating a new
product (`Model.addForm`) -- both are immutable after creation (see `MarketProduct`'s own proto doc),
so `rowEdits` entries never change them.
-}
type alias ProductForm =
    { type_ : PurchaseType
    , period : PurchasePeriod
    , amountText : String
    , mediaAllocationMB : String
    , aiProviderId : String
    , aiModelNames : String
    , aiTokens : String
    , hostingDbSizeMB : String
    , hostingMinioSizeMB : String
    , permissionsText : String
    , status : AccountsPanel.FormStatus
    }


defaultProductForm : ProductForm
defaultProductForm =
    { type_ = PURCHASETYPEMEDIASTORAGE
    , period = PURCHASEPERIODMONTHLY
    , amountText = ""
    , mediaAllocationMB = ""
    , aiProviderId = ""
    , aiModelNames = ""
    , aiTokens = ""
    , hostingDbSizeMB = ""
    , hostingMinioSizeMB = ""
    , permissionsText = ""
    , status = AccountsPanel.Idle
    }


{-| Rebuilds a `ProductForm` from an existing `MarketProduct` -- seeds every text field from
whatever `details` variant (if any) it currently has, so opening "Edit" never starts from blank.
-}
productFormFromProduct : MarketProduct -> ProductForm
productFormFromProduct product =
    let
        base : ProductForm
        base =
            { defaultProductForm
                | type_ = product.type_
                , period = product.period
                , amountText = String.fromInt product.amount
            }
    in
    case product.details of
        Just (ProductDetails.MediaStorageSubscriptionDetails details) ->
            { base | mediaAllocationMB = String.fromInt (bytesToMB (Conversions.int64ToInt details.allocationBytes)) }

        Just (ProductDetails.AiGrantSubscriptionDetails details) ->
            { base
                | aiProviderId = details.aiProviderId
                , aiModelNames = String.join ", " details.modelNames
                , aiTokens = String.fromInt (Conversions.int64ToInt details.tokens)
            }

        Just (ProductDetails.RellmHostingSubscriptionDetails details) ->
            { base
                | hostingDbSizeMB = String.fromInt (bytesToMB (Conversions.int64ToInt details.dbSizeBytes))
                , hostingMinioSizeMB = String.fromInt (bytesToMB (Conversions.int64ToInt details.minioSizeBytes))
            }

        Just (ProductDetails.PermissionsAccessSubscriptionDetails details) ->
            { base | permissionsText = String.join ", " (List.map Users.permissionText details.permissions) }

        Nothing ->
            base


bytesToMB : Int -> Int
bytesToMB bytes =
    bytes // (1024 * 1024)


mbToBytes : Int -> Int
mbToBytes mb =
    mb * 1024 * 1024


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    ( { products = ProductsLoading
      , addForm = Nothing
      , rowEdits = Dict.empty
      , purchases = Dict.empty
      , hostingForms = Dict.empty
      }
    , Effect.batch
        [ fetchProducts shared
        , Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost shared.accounts.mainFrontendHost) shared.accounts.mainFrontendHost []))
        ]
    )


fetchProducts : Shared.Model -> Effect Msg
fetchProducts shared =
    Market.getMarketProducts shared.accounts (maybeAccountServer shared)
        |> Task.attempt GotProductsResult
        |> Effect.fromCmd


maybeAccountServer : Shared.Model -> AccountsPanel.MaybeAccountServer
maybeAccountServer shared =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts shared.accounts.mainFrontendHost |> Maybe.map .userId
    , shared.accounts.mainFrontendHost
    )



-- UPDATE


type Msg
    = GotProductsResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetMarketProductsResponse ))
    | RefreshClicked
      -- Admin: create form
    | AddProductClicked
    | AddFormCancelClicked
    | AddFormTypeChanged String
    | AddFormPeriodChanged String
    | AddFormFieldChanged (ProductForm -> String -> ProductForm) String
    | AddFormSubmitClicked
    | GotAddProductResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketProduct ))
      -- Admin: per-row edit
    | EditProductClicked MarketProduct
    | RowEditFieldChanged String (ProductForm -> String -> ProductForm) String
    | RowEditCancelClicked String
    | RowEditSaveClicked MarketProduct
    | RowDelistToggleClicked MarketProduct
    | GotRowEditResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketProduct ))
      -- Buying
    | HostingFieldChanged String (Market.HostingForm -> String -> Market.HostingForm) String
    | BuyClicked MarketProduct
    | GotPurchaseResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.MakeMarketPurchaseResponse ))
    | SharedMsgReceived Shared.Msg


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotProductsResult (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | products = ProductsLoaded response.marketProducts }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotProductsResult (Err err) ->
            ( { model | products = ProductsErrored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        RefreshClicked ->
            ( { model | products = ProductsLoading }, fetchProducts shared )

        AddProductClicked ->
            ( { model | addForm = Just defaultProductForm }, Effect.none )

        AddFormCancelClicked ->
            ( { model | addForm = Nothing }, Effect.none )

        AddFormTypeChanged text ->
            ( { model | addForm = model.addForm |> Maybe.map (\f -> { f | type_ = purchaseTypeFromString text }) }, Effect.none )

        AddFormPeriodChanged text ->
            ( { model | addForm = model.addForm |> Maybe.map (\f -> { f | period = purchasePeriodFromString text }) }, Effect.none )

        AddFormFieldChanged setter text ->
            ( { model | addForm = model.addForm |> Maybe.map (\f -> setter f text) }, Effect.none )

        AddFormSubmitClicked ->
            case model.addForm of
                Just addForm ->
                    ( { model | addForm = Just { addForm | status = AccountsPanel.Submitting } }
                    , Market.createMarketProduct shared.accounts (maybeAccountServer shared) (productFromForm defaultMarketProduct addForm)
                        |> Task.attempt GotAddProductResult
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        GotAddProductResult (Ok ( maybeAccountsPanelMsg, product )) ->
            ( { model
                | addForm = Nothing
                , products = prependProduct product model.products
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAddProductResult (Err err) ->
            ( { model | addForm = model.addForm |> Maybe.map (\f -> { f | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        EditProductClicked product ->
            ( { model | rowEdits = Dict.insert product.id (productFormFromProduct product) model.rowEdits }, Effect.none )

        RowEditFieldChanged productId setter text ->
            ( { model | rowEdits = Dict.update productId (Maybe.map (\f -> setter f text)) model.rowEdits }, Effect.none )

        RowEditCancelClicked productId ->
            ( { model | rowEdits = Dict.remove productId model.rowEdits }, Effect.none )

        RowEditSaveClicked product ->
            case Dict.get product.id model.rowEdits of
                Just edit ->
                    ( { model | rowEdits = Dict.insert product.id { edit | status = AccountsPanel.Submitting } model.rowEdits }
                    , Market.updateMarketProduct shared.accounts (maybeAccountServer shared) (productFromForm product edit)
                        |> Task.attempt (GotRowEditResult product.id)
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        RowDelistToggleClicked product ->
            let
                updated : MarketProduct
                updated =
                    { product
                        | delistedAt =
                            -- The actual timestamp value is ignored server-side -- only whether
                            -- `delistedAt` is set at all matters (see `MarketProduct`'s own proto
                            -- doc, "though the actual date supplied by the client is ignored").
                            if product.delistedAt == Nothing then
                                Just (Conversions.posixToTimestamp (Time.millisToPosix 0))

                            else
                                Nothing
                    }
            in
            ( model
            , Market.updateMarketProduct shared.accounts (maybeAccountServer shared) updated
                |> Task.attempt (GotRowEditResult product.id)
                |> Effect.fromCmd
            )

        GotRowEditResult productId (Ok ( maybeAccountsPanelMsg, product )) ->
            ( { model
                | rowEdits = Dict.remove productId model.rowEdits
                , products = replaceProduct product model.products
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotRowEditResult productId (Err err) ->
            ( { model | rowEdits = Dict.update productId (Maybe.map (\f -> { f | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) })) model.rowEdits }
            , Effect.none
            )

        HostingFieldChanged productId setter text ->
            ( { model
                | hostingForms =
                    Dict.update productId
                        (\maybeForm -> Just (setter (Maybe.withDefault Market.defaultHostingForm maybeForm) text))
                        model.hostingForms
              }
            , Effect.none
            )

        BuyClicked product ->
            let
                hostingDetails : Maybe RellmHostingPurchaseDetails
                hostingDetails =
                    if product.type_ == PURCHASETYPERELLMHOSTING then
                        Just (Market.hostingDetailsFromForm (Dict.get product.id model.hostingForms |> Maybe.withDefault Market.defaultHostingForm))

                    else
                        Nothing
            in
            ( { model | purchases = Dict.insert product.id Market.PurchaseSubmitting model.purchases }
            , Market.makeMarketPurchase shared.accounts
                (maybeAccountServer shared)
                { marketProductId = product.id, rellmHostingDetails = hostingDetails }
                |> Task.attempt (GotPurchaseResult product.id)
                |> Effect.fromCmd
            )

        GotPurchaseResult productId (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | purchases = Dict.insert productId Market.PurchaseIdle model.purchases }
            , Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, Effect.fromCmd (Browser.Navigation.load response.checkoutUrl) ]
            )

        GotPurchaseResult productId (Err err) ->
            ( { model | purchases = Dict.insert productId (Market.PurchaseErrored (AccountsPanel.grpcErrorToString err)) model.purchases }
            , Effect.none
            )

        SharedMsgReceived subMsg ->
            ( model, Effect.fromShared subMsg )


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


prependProduct : MarketProduct -> ProductsState -> ProductsState
prependProduct product products =
    case products of
        ProductsLoaded existing ->
            ProductsLoaded (product :: existing)

        _ ->
            ProductsLoaded [ product ]


replaceProduct : MarketProduct -> ProductsState -> ProductsState
replaceProduct product products =
    case products of
        ProductsLoaded existing ->
            ProductsLoaded (List.map (\p -> if p.id == product.id then product else p) existing)

        other ->
            other


{-| Builds the `MarketProduct` to actually submit -- `existing` supplies `id`/`createdAt`/
`delistedAt` (never edited by this form itself; delisting has its own dedicated toggle,
`RowDelistToggleClicked`), `form` supplies everything else.
-}
productFromForm : MarketProduct -> ProductForm -> MarketProduct
productFromForm existing form =
    { existing
        | type_ = form.type_
        , period = form.period
        , amount = Maybe.withDefault 0 (String.toInt form.amountText)
        , currency = Market.usdCurrencyCode
        , details = detailsFromForm form
    }


detailsFromForm : ProductForm -> Maybe Details
detailsFromForm form =
    case form.type_ of
        PURCHASETYPEMEDIASTORAGE ->
            Just
                (ProductDetails.MediaStorageSubscriptionDetails
                    { defaultMediaStorageSubscriptionDetails
                        | allocationBytes = Conversions.int64FromInt (mbToBytes (Maybe.withDefault 0 (String.toInt form.mediaAllocationMB)))
                    }
                )

        PURCHASETYPEAIGRANTS ->
            Just
                (ProductDetails.AiGrantSubscriptionDetails
                    { defaultAIGrantSubscriptionDetails
                        | aiProviderId = form.aiProviderId
                        , modelNames = form.aiModelNames |> String.split "," |> List.map String.trim |> List.filter (not << String.isEmpty)
                        , tokens = Conversions.int64FromInt (Maybe.withDefault 0 (String.toInt form.aiTokens))
                    }
                )

        PURCHASETYPERELLMHOSTING ->
            Just
                (ProductDetails.RellmHostingSubscriptionDetails
                    { defaultRellmHostingSubscriptionDetails
                        | dbSizeBytes = Conversions.int64FromInt (mbToBytes (Maybe.withDefault 0 (String.toInt form.hostingDbSizeMB)))
                        , minioSizeBytes = Conversions.int64FromInt (mbToBytes (Maybe.withDefault 0 (String.toInt form.hostingMinioSizeMB)))
                    }
                )

        PURCHASETYPEPERMISSIONSACCESS ->
            Just
                (ProductDetails.PermissionsAccessSubscriptionDetails
                    { defaultPermissionsAccessSubscriptionDetails
                        | permissions =
                            form.permissionsText
                                |> String.split ","
                                |> List.map String.trim
                                |> List.filterMap Users.permissionFromText
                    }
                )

        PurchaseTypeUnrecognized_ _ ->
            Nothing


purchaseTypeFromString : String -> PurchaseType
purchaseTypeFromString text =
    case text of
        "AI_GRANTS" ->
            PURCHASETYPEAIGRANTS

        "RELLM_HOSTING" ->
            PURCHASETYPERELLMHOSTING

        "PERMISSIONS_ACCESS" ->
            PURCHASETYPEPERMISSIONSACCESS

        _ ->
            PURCHASETYPEMEDIASTORAGE


purchaseTypeToString : PurchaseType -> String
purchaseTypeToString type_ =
    case type_ of
        PURCHASETYPEMEDIASTORAGE ->
            "MEDIA_STORAGE"

        PURCHASETYPEAIGRANTS ->
            "AI_GRANTS"

        PURCHASETYPERELLMHOSTING ->
            "RELLM_HOSTING"

        PURCHASETYPEPERMISSIONSACCESS ->
            "PERMISSIONS_ACCESS"

        PurchaseTypeUnrecognized_ _ ->
            "MEDIA_STORAGE"


purchasePeriodFromString : String -> PurchasePeriod
purchasePeriodFromString text =
    case text of
        "INDEFINITE" ->
            PURCHASEPERIODINDEFINITE

        "ANNUAL" ->
            PURCHASEPERIODANNUAL

        _ ->
            PURCHASEPERIODMONTHLY


purchasePeriodToString : PurchasePeriod -> String
purchasePeriodToString period =
    case period of
        PURCHASEPERIODINDEFINITE ->
            "INDEFINITE"

        PURCHASEPERIODANNUAL ->
            "ANNUAL"

        PURCHASEPERIODMONTHLY ->
            "MONTHLY"

        PurchasePeriodUnrecognized_ _ ->
            "MONTHLY"



-- VIEW


view : Shared.Model -> Bool -> Model -> Html Msg
view shared embeddedPage model =
    div [ class "market-page" ]
        (( if embeddedPage then
            text ""

           else
            h1 [] [ text "Market" ]
         )
            :: (case model.products of
                    ProductsLoading ->
                        [ p [] [ text "Loading products…" ] ]

                    ProductsErrored err ->
                        [ p [ class "market-error" ] [ text ("Couldn't load products: " ++ err) ]
                        , button [ onClick RefreshClicked ] [ text "Retry" ]
                        ]

                    ProductsLoaded products ->
                        let
                            isAdmin : Bool
                            isAdmin =
                                RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts shared.accounts.mainFrontendHost
                                    |> Maybe.map RellmAccounts.isAdmin
                                    |> Maybe.withDefault False
                        in
                        (if isAdmin then
                            [ addProductView model.addForm ]

                         else
                            []
                        )
                            ++ [ div [ class "market-products" ]
                                    (List.map (productRowView shared.basePath isAdmin model) (List.filter (visibleProduct isAdmin) products))
                               ]
               )
        )


visibleProduct : Bool -> MarketProduct -> Bool
visibleProduct isAdmin product =
    isAdmin || product.delistedAt == Nothing


productRowView : String -> Bool -> Model -> MarketProduct -> Html Msg
productRowView basePath isAdmin model product =
    case Dict.get product.id model.rowEdits of
        Just edit ->
            div [ class "market-product market-product-editing" ] (productFormView (RowEditFieldChanged product.id) edit ++ [ rowEditActionsView product edit ])

        Nothing ->
            div [ class "market-product" ]
                [ Html.a [ class "market-product-link", Html.Attributes.href (basePath ++ Route.toHref (Route.Market__Product__ProductId_ { productId = product.id })) ]
                    [ span [ class "market-product-title" ] [ text (Market.purchaseTypeLabel product.type_) ]
                    , span [ class "market-product-summary" ] [ text (Market.productSummary product) ]
                    ]
                , if product.delistedAt /= Nothing then
                    span [ class "market-product-delisted" ] [ text "Delisted" ]

                  else
                    text ""
                , if isAdmin then
                    div [ class "market-product-admin-actions" ]
                        [ button [ onClick (EditProductClicked product) ] [ text "Edit" ]
                        , button [ onClick (RowDelistToggleClicked product) ]
                            [ text
                                (if product.delistedAt == Nothing then
                                    "Delist"

                                 else
                                    "Relist"
                                )
                            ]
                        ]

                  else
                    buyView model product
                ]


buyView : Model -> MarketProduct -> Html Msg
buyView model product =
    let
        purchaseState : Market.PurchaseState
        purchaseState =
            Dict.get product.id model.purchases |> Maybe.withDefault Market.PurchaseIdle
    in
    div [ class "market-product-buy" ]
        ((if product.type_ == PURCHASETYPERELLMHOSTING then
            [ hostingFormView product.id (Dict.get product.id model.hostingForms |> Maybe.withDefault Market.defaultHostingForm) ]

          else
            []
         )
            ++ [ button
                    [ onClick (BuyClicked product), disabled (purchaseState == Market.PurchaseSubmitting) ]
                    [ text
                        (if purchaseState == Market.PurchaseSubmitting then
                            "Starting checkout…"

                         else
                            "Buy"
                        )
                    ]
               , case purchaseState of
                    Market.PurchaseErrored err ->
                        span [ class "market-purchase-error" ] [ text err ]

                    _ ->
                        text ""
               ]
        )


hostingFormView : String -> Market.HostingForm -> Html Msg
hostingFormView productId hostingForm =
    div [ class "market-hosting-form" ]
        [ input
            [ placeholder "Domain (e.g. myband.rellm.org)"
            , value hostingForm.domain
            , onInput (HostingFieldChanged productId (\f text -> { f | domain = text }))
            ]
            []
        , input
            [ placeholder "Contact Email"
            , value hostingForm.contactEmail
            , onInput (HostingFieldChanged productId (\f text -> { f | contactEmail = text }))
            ]
            []
        , textarea
            [ placeholder "Additional Information"
            , value hostingForm.additionalInformation
            , onInput (HostingFieldChanged productId (\f text -> { f | additionalInformation = text }))
            ]
            []
        ]


addProductView : Maybe ProductForm -> Html Msg
addProductView maybeAddForm =
    case maybeAddForm of
        Nothing ->
            div [ class "market-add-product" ] [ button [ onClick AddProductClicked ] [ text "+ New Product" ] ]

        Just addForm ->
            div [ class "market-add-product market-product-editing" ]
                (typeAndPeriodSelectors addForm
                    ++ productFormView AddFormFieldChanged addForm
                    ++ [ div [ class "market-form-actions" ]
                            [ button [ onClick AddFormSubmitClicked, disabled (addForm.status == AccountsPanel.Submitting) ] [ text "Create" ]
                            , button [ onClick AddFormCancelClicked ] [ text "Cancel" ]
                            ]
                       , case addForm.status of
                            AccountsPanel.Errored err ->
                                span [ class "market-form-error" ] [ text err ]

                            _ ->
                                text ""
                       ]
                )


typeAndPeriodSelectors : ProductForm -> List (Html Msg)
typeAndPeriodSelectors form =
    [ select [ onInput AddFormTypeChanged ]
        [ option [ value (purchaseTypeToString PURCHASETYPEMEDIASTORAGE), selected (form.type_ == PURCHASETYPEMEDIASTORAGE) ] [ text "Media Storage" ]
        , option [ value (purchaseTypeToString PURCHASETYPEAIGRANTS), selected (form.type_ == PURCHASETYPEAIGRANTS) ] [ text "AI Model Access" ]
        , option [ value (purchaseTypeToString PURCHASETYPERELLMHOSTING), selected (form.type_ == PURCHASETYPERELLMHOSTING) ] [ text "Rellm Hosting" ]
        , option [ value (purchaseTypeToString PURCHASETYPEPERMISSIONSACCESS), selected (form.type_ == PURCHASETYPEPERMISSIONSACCESS) ] [ text "Permissions Access" ]
        ]
    , select [ onInput AddFormPeriodChanged ]
        [ option [ value (purchasePeriodToString PURCHASEPERIODINDEFINITE), selected (form.period == PURCHASEPERIODINDEFINITE) ] [ text "One-Time" ]
        , option [ value (purchasePeriodToString PURCHASEPERIODMONTHLY), selected (form.period == PURCHASEPERIODMONTHLY) ] [ text "Monthly" ]
        , option [ value (purchasePeriodToString PURCHASEPERIODANNUAL), selected (form.period == PURCHASEPERIODANNUAL) ] [ text "Yearly" ]
        ]
    ]


{-| The fields common to every `ProductForm` use, whether creating (`AddFormFieldChanged`, no
`productId`) or editing an existing row (`RowEditFieldChanged productId`) -- `change` abstracts over
that difference, same shape as `AIProviderGrantForm`'s own per-provider `Dict` update helpers.
-}
productFormView : ((ProductForm -> String -> ProductForm) -> String -> msg) -> ProductForm -> List (Html msg)
productFormView change form =
    input [ placeholder "Amount (cents, USD)", value form.amountText, onInput (change (\f text -> { f | amountText = text })) ] []
        :: (case form.type_ of
                PURCHASETYPEMEDIASTORAGE ->
                    [ input
                        [ placeholder "Storage Allocation (MB)"
                        , value form.mediaAllocationMB
                        , onInput (change (\f text -> { f | mediaAllocationMB = text }))
                        ]
                        []
                    ]

                PURCHASETYPEAIGRANTS ->
                    [ input [ placeholder "AI Provider ID", value form.aiProviderId, onInput (change (\f text -> { f | aiProviderId = text })) ] []
                    , input
                        [ placeholder "Model Names (comma-separated)"
                        , value form.aiModelNames
                        , onInput (change (\f text -> { f | aiModelNames = text }))
                        ]
                        []
                    , input [ placeholder "Tokens", value form.aiTokens, onInput (change (\f text -> { f | aiTokens = text })) ] []
                    ]

                PURCHASETYPERELLMHOSTING ->
                    [ input
                        [ placeholder "Database Size (MB)"
                        , value form.hostingDbSizeMB
                        , onInput (change (\f text -> { f | hostingDbSizeMB = text }))
                        ]
                        []
                    , input
                        [ placeholder "Object Storage Size (MB)"
                        , value form.hostingMinioSizeMB
                        , onInput (change (\f text -> { f | hostingMinioSizeMB = text }))
                        ]
                        []
                    ]

                PURCHASETYPEPERMISSIONSACCESS ->
                    [ input
                        [ placeholder "Permissions (comma-separated, e.g. Sync Events To Facebook)"
                        , value form.permissionsText
                        , onInput (change (\f text -> { f | permissionsText = text }))
                        ]
                        []
                    ]

                PurchaseTypeUnrecognized_ _ ->
                    []
           )


rowEditActionsView : MarketProduct -> ProductForm -> Html Msg
rowEditActionsView product edit =
    div [ class "market-form-actions" ]
        [ button [ onClick (RowEditSaveClicked product), disabled (edit.status == AccountsPanel.Submitting) ] [ text "Save" ]
        , button [ onClick (RowEditCancelClicked product.id) ] [ text "Cancel" ]
        , case edit.status of
            AccountsPanel.Errored err ->
                span [ class "market-form-error" ] [ text err ]

            _ ->
                text ""
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
