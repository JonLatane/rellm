module Components.Pages.MarketPage exposing (Model, Msg, fromShared, init, subscriptions, update, view)

{-| `/market` -- Rellm's Stripe-backed marketplace (`market.proto`). Lists every non-delisted
`MarketProduct` on `Model.host` (an Admin *on that host* additionally sees delisted ones, per
`GetMarketProductsResponse.marketProducts`' own proto doc), with a "Buy" button per product that
starts a Stripe Checkout flow (`Components.Market.makeMarketPurchase`) and, on success, redirects
the browser straight to the returned `checkoutUrl` (`Browser.Navigation.load` -- a plain external
redirect, not an Elm route: see that field's own doc on why no `MarketPurchase`/`MarketSubscription`
exists yet at this point). An Admin also gets inline create/edit affordances for `MarketProduct`s
right on this list -- there's deliberately no separate admin page for it, to keep this feature's
scope tight (see the plan this was built from).

`init`'s own `String` argument is the host this particular instance is scoped to -- see `Pages.Market`
for why there can be more than one `MarketPage.Model` alive at once (federated multi-server Market
browsing, per `rellm.proto`'s own "Federated Markets" doc section): `Pages.Market` mounts one instance
per connected, enabled server (`ServerConfiguration.market_settings.enabled`), the browsed host's own
always first. A product tile links internally (`Route.toHref`) only when `host` is the app's own
`browsingHost`; for any other host it's a plain external `https://{host}/market/product/{id}` link
(see `productHref`), since buying always has to happen *on* that host (Stripe Checkout is scoped to
whichever server the buyer authenticates against).

Mirrors `Components.Pages.PostsPage`/`Components.Pages.EventsPage`'s overall shape (a thin
`Pages.Market` wrapper around this module, `init`/`update`/`view`/`subscriptions`/`fromShared`), just
without those modules' own feed-paging/filtering machinery -- a marketplace's product list is small
and never paged.
-}

import Browser.Navigation
import Components.AIProviders as AIProviders
import Components.Market as Market
import Components.Users as Users
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Route as Route
import Grpc
import Html exposing (Html, button, div, h1, input, label, option, p, select, span, text, textarea)
import Html.Attributes exposing (checked, class, disabled, placeholder, selected, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm
    exposing
        ( AIModel
        , AIProvider
        , MarketProduct
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
import Proto.Rellm.Permission exposing (Permission)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers
import Shared.Breadcrumbs as Breadcrumbs
import Shared.ByteFormat as ByteFormat
import Shared.Conversions as Conversions
import Task
import Time
import UI.Classes exposing (classes, openClosedClass)



-- MODEL


type alias Model =
    { host : String
    , products : ProductsState
    , productsFetchStarted : Bool
    , addForm : Maybe ProductForm
    , rowEdits : Dict String ProductForm
    , purchases : Dict String Market.PurchaseState
    , hostingForms : Dict String Market.HostingForm
    , aiProviders : AiProvidersState
    , aiProvidersFetchStarted : Bool
    }


type ProductsState
    = ProductsLoading
    | ProductsLoaded (List MarketProduct)
    | ProductsErrored String


{-| The current Admin's own `AIProvider`s/`AIModel`s (`Components.AIProviders.getAIProviders` with
`targetUserId = ""`) -- fetched only for an Admin (see `init`), and used to back the AI Access
product form's provider `<select>` + model checkboxes (`productFormView`) instead of the raw
provider-id/comma-separated-model-names text fields this form used to have.
-}
type AiProvidersState
    = AiProvidersNotLoaded
    | AiProvidersLoading
    | AiProvidersLoaded (List AIProvider) (List AIModel)
    | AiProvidersErrored String


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
    , currency : Int
    , availableCountText : String
    , mediaAllocationText : String
    , mediaAllocationUnit : ByteFormat.ByteUnit
    , aiProviderId : String
    , aiModelNames : List String
    , aiTokens : String
    , hostingDbSizeText : String
    , hostingDbSizeUnit : ByteFormat.ByteUnit
    , hostingMinioSizeText : String
    , hostingMinioSizeUnit : ByteFormat.ByteUnit
    , hostingAdditionalDescription : String
    , permissions : List Permission
    , permissionAddSelection : Maybe Permission
    , permissionsName : String
    , permissionsDescription : String
    , status : AccountsPanel.FormStatus
    }


defaultProductForm : ProductForm
defaultProductForm =
    { type_ = PURCHASETYPEMEDIASTORAGE
    , period = PURCHASEPERIODMONTHLY
    , amountText = ""
    , currency = Market.usdCurrencyCode
    , availableCountText = ""
    , mediaAllocationText = ""
    , mediaAllocationUnit = ByteFormat.GB
    , aiProviderId = ""
    , aiModelNames = []
    , aiTokens = ""
    , hostingDbSizeText = ""
    , hostingDbSizeUnit = ByteFormat.GB
    , hostingMinioSizeText = ""
    , hostingMinioSizeUnit = ByteFormat.GB
    , hostingAdditionalDescription = ""
    , permissions = []
    , permissionAddSelection = List.head Users.allPermissions
    , permissionsName = ""
    , permissionsDescription = ""
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
                , currency = product.currency
                , availableCountText =
                    if product.availableCount == 0 then
                        ""

                    else
                        String.fromInt product.availableCount
            }
    in
    case product.details of
        Just (ProductDetails.MediaStorageSubscriptionDetails details) ->
            let
                bytes : Int
                bytes =
                    Conversions.int64ToInt details.allocationBytes

                unit : ByteFormat.ByteUnit
                unit =
                    marketBytesToUnit bytes
            in
            { base
                | mediaAllocationText = String.fromFloat (toFloat bytes / toFloat (marketUnitBytes unit))
                , mediaAllocationUnit = unit
            }

        Just (ProductDetails.AiGrantSubscriptionDetails details) ->
            { base
                | aiProviderId = details.aiProviderId
                , aiModelNames = details.modelNames
                , aiTokens = String.fromInt (Conversions.int64ToInt details.tokens)
            }

        Just (ProductDetails.RellmHostingSubscriptionDetails details) ->
            let
                dbBytes : Int
                dbBytes =
                    Conversions.int64ToInt details.dbSizeBytes

                dbUnit : ByteFormat.ByteUnit
                dbUnit =
                    marketBytesToUnit dbBytes

                minioBytes : Int
                minioBytes =
                    Conversions.int64ToInt details.minioSizeBytes

                minioUnit : ByteFormat.ByteUnit
                minioUnit =
                    marketBytesToUnit minioBytes
            in
            { base
                | hostingDbSizeText = String.fromFloat (toFloat dbBytes / toFloat (marketUnitBytes dbUnit))
                , hostingDbSizeUnit = dbUnit
                , hostingMinioSizeText = String.fromFloat (toFloat minioBytes / toFloat (marketUnitBytes minioUnit))
                , hostingMinioSizeUnit = minioUnit
                , hostingAdditionalDescription = details.additionalDescription
            }

        Just (ProductDetails.PermissionsAccessSubscriptionDetails details) ->
            { base
                | permissions = details.permissions
                , permissionAddSelection = resolveAddSelection Nothing details.permissions
                , permissionsName = details.name
                , permissionsDescription = details.description
            }

        Nothing ->
            base


{-| Binary (1024-based) bytes-per-unit -- deliberately `Shared.ByteFormat`'s own type
(`ByteFormat.ByteUnit`, reused so `mediaAllocationUnit`/`hostingDbSizeUnit`/`hostingMinioSizeUnit`'s
`<select>`s can stay the exact same KB/MB/GB widget `Components.Pages.UserProfilePage`'s storage
quota editor uses) but *not* `ByteFormat.byteUnitBytes`'s decimal (1000-based) math:
`Market.humanizeBytes`/`backend/src/logic/market_summary.rs::humanize_bytes` (the display side of
every `MarketProduct` size, including these same fields once saved) are both binary -- entering "5"
+ "GB" needs to round-trip back to exactly "5GB" on `MarketPage`'s tier card, not "4.7GB" (what
`ByteFormat`'s decimal GB would silently produce, since `ByteFormat` is tuned for `du`-style OS
reporting, not this precise a round-trip -- see that module's own doc).
-}
marketUnitBytes : ByteFormat.ByteUnit -> Int
marketUnitBytes unit =
    case unit of
        ByteFormat.Bytes ->
            1

        ByteFormat.KB ->
            1024

        ByteFormat.MB ->
            1024 * 1024

        ByteFormat.GB ->
            1024 * 1024 * 1024


{-| The largest unit `n` is at least 1 whole one of, using `marketUnitBytes`' binary sizes -- the
binary counterpart of `ByteFormat.bytesToUnit`, used to seed `mediaAllocationUnit` when opening
"Edit" on an existing product (see `productFormFromProduct`).
-}
marketBytesToUnit : Int -> ByteFormat.ByteUnit
marketBytesToUnit n =
    if n >= marketUnitBytes ByteFormat.GB then
        ByteFormat.GB

    else if n >= marketUnitBytes ByteFormat.MB then
        ByteFormat.MB

    else if n >= marketUnitBytes ByteFormat.KB then
        ByteFormat.KB

    else
        ByteFormat.Bytes


{-| The binary counterpart of `ByteFormat.parseBytes` -- the inverse of `marketBytesToUnit`.
-}
marketParseBytes : ByteFormat.ByteUnit -> String -> Maybe Int
marketParseBytes unit input =
    String.toFloat (String.trim input) |> Maybe.map (\n -> round (n * toFloat (marketUnitBytes unit)))


{-| `<select>`-driven unit change for `mediaAllocationUnit` (mirrors
`Components.Pages.UserProfilePage`'s `StorageQuotaUnitChanged` handler exactly) -- falls back to
`current` for any unrecognized `<option>` value, which never actually happens since the `<select>`
this feeds only ever offers `ByteFormat.byteUnitText`'s own output.
-}
byteUnitFromText : String -> ByteFormat.ByteUnit -> ByteFormat.ByteUnit
byteUnitFromText text current =
    case text of
        "B" ->
            ByteFormat.Bytes

        "KB" ->
            ByteFormat.KB

        "MB" ->
            ByteFormat.MB

        "GB" ->
            ByteFormat.GB

        _ ->
            current


{-| A number input + KB/MB/GB unit `<select>` for one byte-size `ProductForm` field -- shared by
`mediaAllocationText`/`hostingDbSizeText`/`hostingMinioSizeText` (all three use the same binary
`marketUnitBytes` math via `marketParseBytes`/`marketBytesToUnit`, and the same widget shape
`Components.Pages.UserProfilePage`'s storage quota editor established). `getText`/`setText` and
`getUnit`/`setUnit` pick out which of the three fields this particular instance edits.
-}
byteSizeSelectorView :
    ((ProductForm -> String -> ProductForm) -> String -> msg)
    -> String
    -> ProductForm
    -> (ProductForm -> String)
    -> (ProductForm -> String -> ProductForm)
    -> (ProductForm -> ByteFormat.ByteUnit)
    -> (ProductForm -> ByteFormat.ByteUnit -> ProductForm)
    -> Html msg
byteSizeSelectorView change placeholderText form getText setText getUnit setUnit =
    span [ class "market-form-size-row" ]
        [ input
            [ type_ "number"
            , placeholder placeholderText
            , value (getText form)
            , onInput (change setText)
            ]
            []
        , select [ onInput (change (\f text -> setUnit f (byteUnitFromText text (getUnit f)))) ]
            ([ ByteFormat.KB, ByteFormat.MB, ByteFormat.GB ]
                |> List.map
                    (\unit ->
                        option
                            [ value (ByteFormat.byteUnitText unit), selected (getUnit form == unit) ]
                            [ text (ByteFormat.byteUnitText unit) ]
                    )
            )
        ]


init : Shared.Model -> String -> ( Model, Effect Msg )
init shared host =
    let
        initialModel : Model
        initialModel =
            { host = host
            , products = ProductsLoading
            , productsFetchStarted = False
            , addForm = Nothing
            , rowEdits = Dict.empty
            , purchases = Dict.empty
            , hostingForms = Dict.empty
            , aiProviders =
                if isAdminOn shared host then
                    AiProvidersLoading

                else
                    AiProvidersNotLoaded
            , aiProvidersFetchStarted = False
            }

        ( readyModel, fetchEffect ) =
            attemptFetches shared initialModel
    in
    ( readyModel
    , Effect.batch
        [ fetchEffect
        , Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost host) host []))
        ]
    )


isAdminOn : Shared.Model -> String -> Bool
isAdminOn shared host =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host
        |> Maybe.map RellmAccounts.isAdmin
        |> Maybe.withDefault False


{-| Fires `fetchProducts`/`fetchAiProviders` the first time `model.host` is a known, *connected*
server -- see `RellmServers.knownConnectedRellmServer`'s own doc: `Shared.AccountsPanel.init` seeds
every persisted server disconnected before its own reconnect attempt resolves, so firing these
fetches unconditionally in `init` (the original bug here -- a cold app load raced that reconnect and
failed instantly with "Couldn't reach the server", before the real connection ever landed) doesn't
work. Safe to call repeatedly (from `init` and every `SharedMsgReceived`, mirroring
`Components.Pages.PostOrEventPage.fetchIfReady`'s exact pattern) -- each fetch's own `*FetchStarted`
flag makes every call after the first a no-op.
-}
attemptFetches : Shared.Model -> Model -> ( Model, Effect Msg )
attemptFetches shared model =
    let
        serverReady : Bool
        serverReady =
            RellmServers.knownConnectedRellmServer shared.accounts.servers model.host /= Nothing

        ( model1, productsEffect ) =
            if serverReady && not model.productsFetchStarted then
                ( { model | productsFetchStarted = True }, fetchProducts shared model.host )

            else
                ( model, Effect.none )

        ( model2, aiProvidersEffect ) =
            if serverReady && model1.aiProviders /= AiProvidersNotLoaded && not model1.aiProvidersFetchStarted then
                ( { model1 | aiProvidersFetchStarted = True }, fetchAiProviders shared model1.host )

            else
                ( model1, Effect.none )
    in
    ( model2, Effect.batch [ productsEffect, aiProvidersEffect ] )


fetchProducts : Shared.Model -> String -> Effect Msg
fetchProducts shared host =
    Market.getMarketProducts shared.accounts (maybeAccountServer shared host)
        |> Task.attempt GotProductsResult
        |> Effect.fromCmd


{-| The Admin's own `AIProvider`s/`AIModel`s, for the AI Access product form's provider/model
pickers (`aiGrantsFormView`) -- `targetUserId = ""` asks for the caller's own providers (see
`Components.AIProviders.getAIProviders`'s own doc), which is always right here since only an Admin
ever opens this form (see `isAdminOn`'s callers).
-}
fetchAiProviders : Shared.Model -> String -> Effect Msg
fetchAiProviders shared host =
    AIProviders.getAIProviders shared.accounts (maybeAccountServer shared host) ""
        |> Task.attempt GotAIProvidersResult
        |> Effect.fromCmd


maybeAccountServer : Shared.Model -> String -> AccountsPanel.MaybeAccountServer
maybeAccountServer shared host =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId
    , host
    )



-- UPDATE


type Msg
    = GotProductsResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetMarketProductsResponse ))
    | RefreshClicked
    | GotAIProvidersResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetAIProvidersResponse ))
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
    | LoginClicked
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
            attemptFetches shared { model | products = ProductsLoading, productsFetchStarted = False }

        GotAIProvidersResult (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | aiProviders = AiProvidersLoaded response.providers response.aiModels }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAIProvidersResult (Err err) ->
            ( { model | aiProviders = AiProvidersErrored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        AddProductClicked ->
            ( { model
                | addForm =
                    if model.addForm == Nothing then
                        Just defaultProductForm

                    else
                        Nothing
              }
            , Effect.none
            )

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
                    , Market.createMarketProduct shared.accounts (maybeAccountServer shared model.host) (productFromForm defaultMarketProduct addForm)
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
                    , Market.updateMarketProduct shared.accounts (maybeAccountServer shared model.host) (productFromForm product edit)
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
            , Market.updateMarketProduct shared.accounts (maybeAccountServer shared model.host) updated
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
                (maybeAccountServer shared model.host)
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

        LoginClicked ->
            ( model, Effect.fromShared (Shared.AccountsPanelMsg AccountsPanel.ToggleAccountsPanel) )

        SharedMsgReceived subMsg ->
            let
                ( retriedModel, retryEffect ) =
                    attemptFetches shared model
            in
            ( retriedModel, Effect.batch [ Effect.fromShared subMsg, retryEffect ] )


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
        , currency = form.currency
        , availableCount = Maybe.withDefault 0 (String.toInt form.availableCountText)
        , details = detailsFromForm form
    }


detailsFromForm : ProductForm -> Maybe Details
detailsFromForm form =
    case form.type_ of
        PURCHASETYPEMEDIASTORAGE ->
            Just
                (ProductDetails.MediaStorageSubscriptionDetails
                    { defaultMediaStorageSubscriptionDetails
                        | allocationBytes =
                            Conversions.int64FromInt
                                (marketParseBytes form.mediaAllocationUnit form.mediaAllocationText |> Maybe.withDefault 0)
                    }
                )

        PURCHASETYPEAIGRANTS ->
            Just
                (ProductDetails.AiGrantSubscriptionDetails
                    { defaultAIGrantSubscriptionDetails
                        | aiProviderId = form.aiProviderId
                        , modelNames = form.aiModelNames
                        , tokens = Conversions.int64FromInt (Maybe.withDefault 0 (String.toInt form.aiTokens))
                    }
                )

        PURCHASETYPERELLMHOSTING ->
            Just
                (ProductDetails.RellmHostingSubscriptionDetails
                    { defaultRellmHostingSubscriptionDetails
                        | dbSizeBytes =
                            Conversions.int64FromInt
                                (marketParseBytes form.hostingDbSizeUnit form.hostingDbSizeText |> Maybe.withDefault 0)
                        , minioSizeBytes =
                            Conversions.int64FromInt
                                (marketParseBytes form.hostingMinioSizeUnit form.hostingMinioSizeText |> Maybe.withDefault 0)
                        , additionalDescription = form.hostingAdditionalDescription
                    }
                )

        PURCHASETYPEPERMISSIONSACCESS ->
            Just
                (ProductDetails.PermissionsAccessSubscriptionDetails
                    { defaultPermissionsAccessSubscriptionDetails
                        | permissions = form.permissions
                        , name = form.permissionsName
                        , description = form.permissionsDescription
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


{-| `embeddedPage` still only ever applies to the browsed host's own instance (see
`Pages.UsernameOrCustomTab_`'s embedding, which never mounts a second server's Market) --
`isPrimary` (`model.host == shared.accounts.browsingHost`) is the independent question of whether
*this particular instance*, among however many `Pages.Market` has mounted, is the browsed server's
own -- see module doc.
-}
view : Shared.Model -> Bool -> Model -> Html Msg
view shared embeddedPage model =
    let
        isAdmin : Bool
        isAdmin =
            isAdminOn shared model.host

        isPrimary : Bool
        isPrimary =
            model.host == shared.accounts.browsingHost
    in
    div [ class "market-page" ]
        (headerRowView embeddedPage isPrimary model.host isAdmin
            :: (if isAdmin then
                    [ addProductPanelView model.aiProviders model.addForm ]

                else
                    []
               )
            ++ (case model.products of
                    ProductsLoading ->
                        [ p [] [ text "Loading products…" ] ]

                    ProductsErrored err ->
                        [ p [ class "market-error" ] [ text ("Couldn't load products: " ++ err) ]
                        , button [ onClick RefreshClicked ] [ text "Retry" ]
                        ]

                    ProductsLoaded products ->
                        let
                            visible : List MarketProduct
                            visible =
                                List.filter (visibleProduct isAdmin) products
                        in
                        [ div [ class "market-sections" ]
                            (Market.allPurchaseTypes |> List.map (sectionView shared isPrimary isAdmin model visible))
                        ]
               )
        )


{-| The "Market" heading (hidden while embedded on `UsernameOrCustomTab_`, same as before, for the
browsed server's own primary instance only) and, for an Admin *on this instance's own host*, a
"+ New Product" button and a link to `/market/fulfillment` -- all on the same row, pinned to the
right by `.market-header-row`'s `justify-content: space-between` (see `market.css`). The button stays
visible even while `addProductPanelView`'s form is already open, rather than disappearing -- a
second click toggles the form closed again (see `AddProductClicked`), same as `AddFormCancelClicked`.
The fulfillment link only ever makes sense for the browsed server's own primary instance (an Admin
manages *their own* server's Rellm Hosting orders here, not some other federated server's), so it's
gated on `isPrimary` too, unlike the "+ New Product" button.

A non-primary instance (another server's Market, shown alongside the browsed server's own -- see
module doc) always gets a heading, even while `embeddedPage`, naming which server it's for ("Market
on other-server.com") -- there's no ambiguity to resolve for the primary instance, but stacking two
bare "Market" headings would be.
-}
headerRowView : Bool -> Bool -> String -> Bool -> Html Msg
headerRowView embeddedPage isPrimary host isAdmin =
    div [ class "market-header-row" ]
        [ if embeddedPage && isPrimary then
            text ""

          else if isPrimary then
            h1 [] [ text "Market" ]

          else
            h1 [] [ text ("Market on " ++ host) ]
        , if isAdmin then
            div [ class "market-header-row-admin-actions" ]
                ((if isPrimary then
                    [ Html.a
                        [ Html.Attributes.href (Route.toHref Route.Market__Fulfillment), class "market-fulfillment-link" ]
                        [ text "Rellm Hosting Fulfillment" ]
                    ]

                  else
                    []
                 )
                    ++ [ button [ class "market-add-product-button", onClick AddProductClicked ] [ text "+ New Product" ] ]
                )

          else
            text ""
        ]


{-| The "New Product" form -- always mounted (even while closed) so `.market-add-product-panel`'s
`grid-template-rows` 0fr/1fr trick (`market.css`) can animate it open/closed, the same mechanism
`Components.Pages.UserProfilePage.expandableProfileSection` uses (see that function's own doc on why
"always mounted" is required for the CSS transition to have something to animate). Right-aligned via
the outer panel's own `margin-left: auto`. While closed, `form` is just a throwaway
`defaultProductForm` -- invisible (clipped to ~0 height) and inert (`.is-closed` sets
`pointer-events: none`), never actually submitted.
-}
addProductPanelView : AiProvidersState -> Maybe ProductForm -> Html Msg
addProductPanelView aiProviders maybeAddForm =
    let
        isOpen : Bool
        isOpen =
            maybeAddForm /= Nothing

        addForm : ProductForm
        addForm =
            Maybe.withDefault defaultProductForm maybeAddForm
    in
    div [ classes [ "market-add-product-panel", openClosedClass isOpen ] ]
        [ div [ class "market-add-product-panel-inner" ]
            [ div [ class "market-add-product-panel-content market-tier-editing" ]
                (typeAndPeriodSelectors addForm
                    ++ productFormView aiProviders AddFormFieldChanged addForm
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
            ]
        ]


visibleProduct : Bool -> MarketProduct -> Bool
visibleProduct isAdmin product =
    isAdmin || product.delistedAt == Nothing


{-| One of the 4 `PurchaseType` sections (Media Storage / AI Access / Rellm Hosting / Extra
Features) -- an Admin always sees all 4 (empty ones read "You have not added any products of this
type yet."), a regular user only sees ones with at least one tier (see `Model` type's own module
doc on why: browsing is public, buying isn't). Tiers within a section are sorted cheapest-monthly
first, then annual by price, then indefinite/lifetime by price (`Market.periodSortOrder`).
-}
sectionView : Shared.Model -> Bool -> Bool -> Model -> List MarketProduct -> PurchaseType -> Html Msg
sectionView shared isPrimary isAdmin model products type_ =
    let
        tiers : List MarketProduct
        tiers =
            products
                |> List.filter (\p -> p.type_ == type_)
                |> List.sortWith
                    (\a b ->
                        case compare (Market.periodSortOrder a.period) (Market.periodSortOrder b.period) of
                            EQ ->
                                compare a.amount b.amount

                            order ->
                                order
                    )
    in
    if not isAdmin && List.isEmpty tiers then
        text ""

    else
        div [ class "market-section" ]
            [ div [ class "market-section-header" ]
                [ span [ class "market-section-emoji" ] [ text (Market.purchaseTypeEmoji type_) ]
                , div [ class "market-section-heading" ]
                    [ Html.h2 [] [ text (Market.purchaseTypeLabel type_) ]
                    , p [ class "market-section-description" ] [ text (Market.purchaseTypeDescription type_) ]
                    ]
                ]
            , if List.isEmpty tiers then
                p [ class "market-section-empty" ] [ text "You have not added any products of this type yet." ]

              else
                div [ class "market-tier-row" ] (List.map (tierCardView shared isPrimary isAdmin model) tiers)
            ]


{-| `isPrimary` decides how a tier's own link is built (see module doc): the browsed server's own
products link internally (`Route.toHref`, resolves against `browsingHost` for free by being a plain
relative URL); any other server's products link straight to that server's own
`https://{host}/market/product/{id}` instead, a real page navigation -- buying always has to happen
*on* that server, not this one.
-}
productHref : Shared.Model -> Bool -> String -> MarketProduct -> String
productHref shared isPrimary host product =
    if isPrimary then
        shared.basePath ++ Route.toHref (Route.Market__Product__ProductId_ { productId = product.id })

    else
        "https://" ++ host ++ "/market/product/" ++ product.id


tierCardView : Shared.Model -> Bool -> Bool -> Model -> MarketProduct -> Html Msg
tierCardView shared isPrimary isAdmin model product =
    case Dict.get product.id model.rowEdits of
        Just edit ->
            div [ class "market-tier market-tier-editing" ]
                (productFormView model.aiProviders (RowEditFieldChanged product.id) edit ++ [ rowEditActionsView product edit ])

        Nothing ->
            div [ class "market-tier" ]
                [ Html.a
                    [ class "market-tier-link"
                    , Html.Attributes.href (productHref shared isPrimary model.host product)
                    ]
                    [ span [ class "market-tier-price" ] [ text (Market.priceLabel product) ]
                    , span [ class "market-tier-name" ] [ text (Market.productName product) ]
                    , case Market.slotsAvailableText product of
                        Just slotsText ->
                            span [ class "market-tier-slots" ] [ text slotsText ]

                        Nothing ->
                            text ""
                    ]
                , permissionBadgesView (Market.permissionsForProduct product)
                , if product.delistedAt /= Nothing then
                    span [ class "market-tier-delisted" ] [ text "Delisted" ]

                  else if Market.isSoldOut product then
                    span [ class "market-tier-delisted" ] [ text "Sold Out" ]

                  else
                    text ""
                , if isAdmin then
                    div [ class "market-tier-admin-actions" ]
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

                  else if Market.isSoldOut product then
                    text ""

                  else
                    buyView shared model product
                ]


{-| The extra `Permission`s a tier grants, as the same read-only badge chips
`Components.Pages.UserProfilePage`'s own permissions section uses -- `text ""` (nothing rendered)
for a tier with none (every `PurchaseType` except `PERMISSIONS_ACCESS`).
-}
permissionBadgesView : List Permission -> Html msg
permissionBadgesView permissions =
    if List.isEmpty permissions then
        text ""

    else
        div [ class "permission-badges market-tier-permissions" ]
            (permissions |> List.map (\permission -> span [ class "permission-badge" ] [ text (Users.permissionText permission) ]))


{-| Whether anyone is signed in on `host` at all -- gates `buyView`'s "Buy" button (a signed-out
click would otherwise just fail with a confusing `NetworkError`, since `Market.makeMarketPurchase`
is always authenticated -- see `Shared.AccountsPanel.performWithAccountServer`).
-}
signedIn : Shared.Model -> String -> Bool
signedIn shared host =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host /= Nothing


{-| Whether Market itself is open for `host` at all -- `market_settings.enabled` (see that field's
own proto doc). Checked first in `buyView`, ahead of `stripeConfigured` and `signedIn`, since a
closed Market makes both of those moot. Defaults to `True` (don't block the Buy button) whenever
`host` isn't yet a known/connected server or hasn't reported `marketSettings` at all -- mirrors
`Components.Pages.ProductPage.stripeConfigured`'s own "unknown isn't the same as definitely not
configured" reasoning. In practice this only ever matters for the primary (browsed) host's own
instance -- `Pages.Market.marketEnabledHosts` already filters any *other* federated server out of
the page entirely once its own `market_settings.enabled` goes false, so a `MarketPage` instance for
one only exists here while it's still enabled.
-}
marketEnabled : Shared.Model -> String -> Bool
marketEnabled shared host =
    RellmServers.knownConnectedRellmServer shared.accounts.servers host
        |> Maybe.map
            (\server ->
                (RellmServers.configurationOf server).marketSettings
                    |> Maybe.map .enabled
                    |> Maybe.withDefault True
            )
        |> Maybe.withDefault True


{-| Whether Stripe is actually usable on `host` right now -- `market_settings.stripe_configured`.
Mirrors `Components.Pages.ProductPage.stripeConfigured` exactly, just parameterized over `host`
(a `MarketPage` instance can be for any federated server, not just the one being browsed) instead of
always reading `shared.accounts.browsingHost`.
-}
stripeConfigured : Shared.Model -> String -> Bool
stripeConfigured shared host =
    RellmServers.knownConnectedRellmServer shared.accounts.servers host
        |> Maybe.map
            (\server ->
                (RellmServers.configurationOf server).marketSettings
                    |> Maybe.map .stripeConfigured
                    |> Maybe.withDefault True
            )
        |> Maybe.withDefault True


buyView : Shared.Model -> Model -> MarketProduct -> Html Msg
buyView shared model product =
    if not (marketEnabled shared model.host) then
        div [ class "market-tier-buy" ]
            [ button [ disabled True ] [ text "Buy" ]
            , p [ class "market-tier-buy-note" ] [ text "Market is not currently open." ]
            ]

    else if not (stripeConfigured shared model.host) then
        div [ class "market-tier-buy" ]
            [ button [ disabled True ] [ text "Buy" ]
            , p [ class "market-tier-buy-note" ] [ text "Stripe is not configured." ]
            ]

    else if not (signedIn shared model.host) then
        loginPromptView

    else
        let
            purchaseState : Market.PurchaseState
            purchaseState =
                Dict.get product.id model.purchases |> Maybe.withDefault Market.PurchaseIdle
        in
        div [ class "market-tier-buy" ]
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


{-| Shown instead of a "Buy" button (and, for `RELLM_HOSTING`, its domain/contact/notes form) when
nobody's signed in -- mirrors `Components.ServerDependentView`'s own "connect to proceed" prompt
styling, but opens the Accounts Panel (the app's only Login/Create Account entry point -- there's no
dedicated route) rather than connecting a server.
-}
loginPromptView : Html Msg
loginPromptView =
    div [ class "market-tier-login-prompt" ]
        [ p [] [ text "Create Account or Login to proceed." ]
        , button [ onClick LoginClicked ] [ text "Login" ]
        ]


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


typeAndPeriodSelectors : ProductForm -> List (Html Msg)
typeAndPeriodSelectors form =
    [ select [ onInput AddFormTypeChanged ]
        (Market.allPurchaseTypes
            |> List.map (\t -> option [ value (purchaseTypeToString t), selected (form.type_ == t) ] [ text (Market.purchaseTypeLabel t) ])
        )
    , select [ onInput AddFormPeriodChanged ]
        [ option [ value (purchasePeriodToString PURCHASEPERIODMONTHLY), selected (form.period == PURCHASEPERIODMONTHLY) ] [ text "Monthly" ]
        , option [ value (purchasePeriodToString PURCHASEPERIODANNUAL), selected (form.period == PURCHASEPERIODANNUAL) ] [ text "Yearly" ]
        , option [ value (purchasePeriodToString PURCHASEPERIODINDEFINITE), selected (form.period == PURCHASEPERIODINDEFINITE) ] [ text "One-Time" ]
        ]
    ]


{-| The fields common to every `ProductForm` use, whether creating (`AddFormFieldChanged`, no
`productId`) or editing an existing row (`RowEditFieldChanged productId`) -- `change` abstracts over
that difference, same shape as `AIProviderGrantForm`'s own per-provider `Dict` update helpers.
-}
productFormView : AiProvidersState -> ((ProductForm -> String -> ProductForm) -> String -> msg) -> ProductForm -> List (Html msg)
productFormView aiProviders change form =
    span [ class "market-form-price-row" ]
        [ input
            [ placeholder (Market.amountInputLabel form.currency)
            , value form.amountText
            , onInput (change (\f text -> { f | amountText = text }))
            ]
            []
        , select [ onInput (change (\f text -> { f | currency = String.toInt text |> Maybe.withDefault f.currency })) ]
            (Market.allCurrencies
                |> List.map
                    (\c ->
                        option [ value (String.fromInt c.code), selected (c.code == form.currency) ] [ text (Market.currencyLabel c.code) ]
                    )
            )
        ]
        :: input
            [ type_ "number"
            , placeholder "Available Slots (blank/0 = unlimited)"
            , value form.availableCountText
            , onInput (change (\f text -> { f | availableCountText = text }))
            ]
            []
        :: (case form.type_ of
                PURCHASETYPEMEDIASTORAGE ->
                    [ byteSizeSelectorView change
                        "Storage Allocation"
                        form
                        .mediaAllocationText
                        (\f text -> { f | mediaAllocationText = text })
                        .mediaAllocationUnit
                        (\f unit -> { f | mediaAllocationUnit = unit })
                    ]

                PURCHASETYPEAIGRANTS ->
                    aiGrantsFormView aiProviders change form

                PURCHASETYPERELLMHOSTING ->
                    [ byteSizeSelectorView change
                        "Database Size"
                        form
                        .hostingDbSizeText
                        (\f text -> { f | hostingDbSizeText = text })
                        .hostingDbSizeUnit
                        (\f unit -> { f | hostingDbSizeUnit = unit })
                    , byteSizeSelectorView change
                        "Object Storage Size"
                        form
                        .hostingMinioSizeText
                        (\f text -> { f | hostingMinioSizeText = text })
                        .hostingMinioSizeUnit
                        (\f unit -> { f | hostingMinioSizeUnit = unit })
                    , textarea
                        [ placeholder "Additional Description (Markdown, shown below the canned description)"
                        , value form.hostingAdditionalDescription
                        , onInput (change (\f text -> { f | hostingAdditionalDescription = text }))
                        ]
                        []
                    ]

                PURCHASETYPEPERMISSIONSACCESS ->
                    permissionsFormView change form

                PurchaseTypeUnrecognized_ _ ->
                    []
           )


{-| The AI Access form fields: a `<select>` of the Admin's own `AIProvider`s (from
`Components.AIProviders.getAIProviders`, fetched once at `init` -- see `AiProvidersState`), then a
checkbox per `AIModel` that provider offers (multi-select, per Jon's own ask), then the Tokens
field. Replaces the old raw "AI Provider ID"/"Model Names (comma-separated)" text inputs -- an
Admin picks from what they actually have instead of hand-typing an id/name that has to match
exactly. Picking a different provider clears any already-checked models (a model name is only
meaningful relative to its own provider).
-}
aiGrantsFormView : AiProvidersState -> ((ProductForm -> String -> ProductForm) -> String -> msg) -> ProductForm -> List (Html msg)
aiGrantsFormView aiProviders change form =
    case aiProviders of
        AiProvidersNotLoaded ->
            [ p [ class "market-form-hint" ] [ text "AI providers aren't loaded." ] ]

        AiProvidersLoading ->
            [ p [ class "market-form-hint" ] [ text "Loading your AI providers…" ] ]

        AiProvidersErrored err ->
            [ p [ class "market-form-error" ] [ text ("Couldn't load AI providers: " ++ err) ] ]

        AiProvidersLoaded [] _ ->
            [ p [ class "market-form-hint" ] [ text "You have no AI providers configured yet -- add one on your profile first." ] ]

        AiProvidersLoaded providers aiModels ->
            [ select
                [ onInput (change (\f id -> { f | aiProviderId = id, aiModelNames = [] })) ]
                (option [ value "", selected (form.aiProviderId == "") ] [ text "Select an AI Provider" ]
                    :: (providers |> List.map (\provider -> option [ value provider.id, selected (provider.id == form.aiProviderId) ] [ text provider.name ]))
                )
            , if form.aiProviderId == "" then
                text ""

              else
                let
                    modelsForSelectedProvider : List AIModel
                    modelsForSelectedProvider =
                        aiModels |> List.filter (\m -> (m.provider |> Maybe.map .id) == Just form.aiProviderId)
                in
                if List.isEmpty modelsForSelectedProvider then
                    p [ class "market-form-hint" ] [ text "This provider has no models yet." ]

                else
                    div [ class "market-form-ai-models" ]
                        (modelsForSelectedProvider
                            |> List.map
                                (\aiModel ->
                                    label [ class "market-form-ai-model-option" ]
                                        [ input
                                            [ type_ "checkbox"
                                            , checked (List.member aiModel.modelName form.aiModelNames)
                                            , onClick (change (\f _ -> toggleAiModel aiModel.modelName f) "")
                                            ]
                                            []
                                        , text (Market.aiModelDisplayName aiModel.modelName)
                                        ]
                                )
                        )
            , input [ placeholder "Tokens", value form.aiTokens, onInput (change (\f text -> { f | aiTokens = text })) ] []
            ]


{-| Toggles `modelName` in `form.aiModelNames` -- add if absent, remove if present. Used by
`aiGrantsFormView`'s per-model checkboxes.
-}
toggleAiModel : String -> ProductForm -> ProductForm
toggleAiModel modelName form =
    { form
        | aiModelNames =
            if List.member modelName form.aiModelNames then
                List.filter ((/=) modelName) form.aiModelNames

            else
                form.aiModelNames ++ [ modelName ]
    }


{-| The Extra Features form -- a Name field and a Markdown Description field (both required
server-side: `CreateMarketProduct`/`UpdateMarketProduct` reject a blank `name` with `name_required`,
see `PermissionsAccessSubscriptionDetails.name`'s own proto doc), since unlike the other three
`PurchaseType`s' implicitly-computed display name/description (`Components.Market.productName`/
`productDescription`), a permissions bundle can be any admin-chosen set with no generically-derivable
name -- an admin has to author both by hand here. Followed by the permissions editor itself: the
same add-via-dropdown/remove-via-×-badge pattern `Components.Pages.UserProfilePage.permissionsSection`'s
edit mode uses (mirrors `permissionEditBadge`/the "Add Permission" `<select>`+button there almost
exactly), rather than the free-text comma-separated field this used to be -- picking from
`Components.Users.allPermissions` means an admin can't typo a permission name into something that
silently grants nothing.
-}
permissionsFormView : ((ProductForm -> String -> ProductForm) -> String -> msg) -> ProductForm -> List (Html msg)
permissionsFormView change form =
    [ input
        [ placeholder "Name (e.g. \"Facebook Sync Access\")"
        , value form.permissionsName
        , onInput (change (\f text -> { f | permissionsName = text }))
        ]
        []
    , textarea
        [ placeholder "Description (Markdown)"
        , value form.permissionsDescription
        , onInput (change (\f text -> { f | permissionsDescription = text }))
        ]
        []
    , div [ class "permission-badges" ]
        (form.permissions
            |> List.map
                (\permission ->
                    span [ class "permission-badge editable" ]
                        [ text (Users.permissionText permission)
                        , button
                            [ class "permission-remove"
                            , onClick (change (\f _ -> removePermission permission f) "")
                            , title ("Remove " ++ Users.permissionText permission)
                            ]
                            [ text "×" ]
                        ]
                )
        )
    , div [ class "market-form-permissions-add" ]
        [ select [ onInput (change (\f text -> { f | permissionAddSelection = Users.permissionFromText text })) ]
            (addablePermissions form.permissions
                |> List.map
                    (\permission ->
                        option
                            [ value (Users.permissionText permission), selected (form.permissionAddSelection == Just permission) ]
                            [ text (Users.permissionText permission) ]
                    )
            )
        , button
            [ onClick (change (\f _ -> addSelectedPermission f) "")
            , disabled (form.permissionAddSelection == Nothing)
            ]
            [ text "Add Permission" ]
        ]
    ]


{-| Mirrors `Components.Pages.UserProfilePage.resolveAddSelection`/`addablePermissions` exactly --
keeps the "Add Permission" `<select>`'s selection valid as `form.permissions` changes (falls back to
the first still-addable permission, `Nothing` once every permission's already added).
-}
removePermission : Permission -> ProductForm -> ProductForm
removePermission permission form =
    let
        remaining : List Permission
        remaining =
            List.filter ((/=) permission) form.permissions
    in
    { form | permissions = remaining, permissionAddSelection = resolveAddSelection form.permissionAddSelection remaining }


addSelectedPermission : ProductForm -> ProductForm
addSelectedPermission form =
    case form.permissionAddSelection of
        Just permission ->
            let
                updated : List Permission
                updated =
                    form.permissions ++ [ permission ]
            in
            { form | permissions = updated, permissionAddSelection = resolveAddSelection Nothing updated }

        Nothing ->
            form


addablePermissions : List Permission -> List Permission
addablePermissions pending =
    Users.allPermissions |> List.filter (\permission -> not (List.member permission pending))


resolveAddSelection : Maybe Permission -> List Permission -> Maybe Permission
resolveAddSelection current pending =
    let
        available : List Permission
        available =
            addablePermissions pending
    in
    case current of
        Just permission ->
            if List.member permission available then
                Just permission

            else
                List.head available

        Nothing ->
            List.head available


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
subscriptions =
    always Sub.none


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
