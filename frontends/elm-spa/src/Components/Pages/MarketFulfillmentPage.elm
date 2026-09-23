module Components.Pages.MarketFulfillmentPage exposing (Model, Msg, fromShared, init, subscriptions, titleFor, update, view)

{-| `/market/fulfillment` -- Admin-only order-management table for every
`PURCHASE_TYPE_RELLM_HOSTING` `MarketSubscription` across every buyer on `Model.host`
(`Components.Market.getMarketSubscriptionsForFulfillment`). Buying one of these products means the
buyer wants their own Rellm instance manually stood up (see `market.proto`'s own top-of-file notes --
this is never automated); until this page existed there was no admin UI at all for seeing/managing
those orders. Mirrors `Components.Pages.ProductPage`'s overall shape (thin `Pages.Market.Fulfillment`
wrapper, single `attemptFetch`/`fetchStarted` cold-load-race guard via
`RellmServers.knownConnectedRellmServer`) and routes to `shared.accounts.browsingHost` (not
`mainFrontendHost`), same as every other Market page -- see that module's own doc on why.

Each row (one `MarketSubscription`) is collapsed by default, showing the buyer, domain, contact
email, and a `fulfillmentStatus` badge (Awaiting Host Admin/In Progress/✓ Fulfilled -- see
`FulfillmentStatus`'s own proto doc); clicking it expands, in order: the buyer's own purchase
details (immutable `additionalInformation`), the fulfillment notes conversation (oldest-first, with
"Add Note"/"Add and Mark as Fulfilled" -- see `appendFulfillmentNote`'s own doc), the
subscription's own cancellation details (only when actually canceled), and its full payment/refund
history. Every status-affecting action (including expanding a still-`AWAITING_HOST_ADMIN` row, which
auto-transitions it to `IN_PROGRESS` -- see `RowToggled`'s own doc) goes through
`Components.Market.updateMarketSubscription`'s append-only `fulfillment_notes` contract: always send
back the subscription's last-fetched `fulfillmentNotes` verbatim, plus exactly one new entry. The
expand/collapse itself animates via the same `grid-template-rows` 0fr/1fr trick
`Components.Pages.ServerInformationPage.SettingsTab.featureSettingsSection` uses (`expandedRowView`'s
own doc has the details) -- `rowView`'s details wrapper is always mounted, never appearing/
disappearing outright.

-}

import Components.Authors as Authors
import Components.Market as Market
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h1, h4, p, span, text, textarea)
import Html.Attributes exposing (class, disabled, href, placeholder, rel, target, value)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
import Json.Decode as Decode
import Proto.Google.Protobuf
import Proto.Rellm
    exposing
        ( FulfillmentNote
        , GetMarketSubscriptionsResponse
        , MarketPurchase
        , MarketSubscription
        , RellmHostingSubscriptionDetails
        , defaultFulfillmentNote
        , unwrapMarketPurchase
        )
import Proto.Rellm.FulfillmentStatus exposing (FulfillmentStatus(..))
import Proto.Rellm.MarketSubscription.Details as SubscriptionDetails
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers
import Shared.Breadcrumbs as Breadcrumbs
import Shared.Conversions as Conversions
import Shared.Time as SharedTime
import Task
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)



-- MODEL


type alias Model =
    { host : String
    , subscriptions : SubscriptionsState
    , fetchStarted : Bool
    , expandedRows : Set String
    , noteDrafts : Dict String String
    , noteSaves : Dict String AccountsPanel.FormStatus
    }


type SubscriptionsState
    = SubscriptionsLoading
    | SubscriptionsLoaded (List MarketSubscription)
    | SubscriptionsErrored String


init : Shared.Model -> ( Model, Effect Msg )
init shared =
    let
        host : String
        host =
            shared.accounts.browsingHost

        ( readyModel, fetchEffect ) =
            attemptFetch shared
                { host = host
                , subscriptions = SubscriptionsLoading
                , fetchStarted = False
                , expandedRows = Set.empty
                , noteDrafts = Dict.empty
                , noteSaves = Dict.empty
                }
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


{-| Fires `fetchSubscriptions` the first time `model.host` is both a known, _connected_ server
(`RellmServers.knownConnectedRellmServer` -- see `Components.Pages.ProductPage.attemptFetch`'s own
doc on why this guard exists at all) and the signed-in account there is an Admin -- a non-admin
never fires this fetch (it would just fail with a permission error, per
`Market.getMarketSubscriptionsForFulfillment`'s own doc). Safe to call repeatedly (from `init` and
every `SharedMsgReceived`) -- `fetchStarted` makes every call after the first a no-op.
-}
attemptFetch : Shared.Model -> Model -> ( Model, Effect Msg )
attemptFetch shared model =
    if model.fetchStarted || not (isAdminOn shared model.host) || RellmServers.knownConnectedRellmServer shared.accounts.servers model.host == Nothing then
        ( model, Effect.none )

    else
        ( { model | fetchStarted = True }, fetchSubscriptions shared model.host )


fetchSubscriptions : Shared.Model -> String -> Effect Msg
fetchSubscriptions shared host =
    Market.getMarketSubscriptionsForFulfillment shared.accounts (maybeAccountServer shared host)
        |> Task.attempt GotSubscriptionsResult
        |> Effect.fromCmd


maybeAccountServer : Shared.Model -> String -> AccountsPanel.MaybeAccountServer
maybeAccountServer shared host =
    ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId
    , host
    )


currentAdminUserId : Shared.Model -> String -> Maybe String
currentAdminUserId shared host =
    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host |> Maybe.map .userId


{-| Always the same title -- unlike `ProductPage.titleFor` (which varies by the fetched product),
this page's title doesn't depend on anything fetched, so there's no `Model` to branch on.
-}
titleFor : String
titleFor =
    "Rellm Hosting Fulfillment"


{-| The `RellmHostingSubscriptionDetails` out of `subscription.details` -- every subscription this
page ever sees is `PURCHASE_TYPE_RELLM_HOSTING` (`getMarketSubscriptionsForFulfillment` only ever
returns those), so this should always be `Just`; `Nothing` (some other details variant) is only
reachable in principle and just means that row renders nothing.
-}
hostingDetailsOf : MarketSubscription -> Maybe RellmHostingSubscriptionDetails
hostingDetailsOf subscription =
    case subscription.details of
        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            Just details

        _ ->
            Nothing


findSubscription : String -> SubscriptionsState -> Maybe MarketSubscription
findSubscription subscriptionId subscriptionsState =
    case subscriptionsState of
        SubscriptionsLoaded subs ->
            subs |> List.filter (\s -> s.id == subscriptionId) |> List.head

        _ ->
            Nothing



-- UPDATE


type Msg
    = GotSubscriptionsResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMarketSubscriptionsResponse ))
    | RefreshClicked
    | RowToggled String
    | RowLinkClicked
    | NoteDraftChanged String String
    | SaveNoteClicked MarketSubscription
    | MarkAsFulfilledClicked MarketSubscription
    | GotSaveNoteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | SharedMsgReceived Shared.Msg


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        GotSubscriptionsResult (Ok ( maybeAccountsPanelMsg, response )) ->
            ( { model | subscriptions = SubscriptionsLoaded response.marketSubscriptions }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSubscriptionsResult (Err err) ->
            ( { model | subscriptions = SubscriptionsErrored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        RefreshClicked ->
            attemptFetch shared { model | subscriptions = SubscriptionsLoading, fetchStarted = False }

        RowToggled subscriptionId ->
            let
                nowExpanded : Bool
                nowExpanded =
                    not (Set.member subscriptionId model.expandedRows)

                newModel : Model
                newModel =
                    { model
                        | expandedRows =
                            if nowExpanded then
                                Set.insert subscriptionId model.expandedRows

                            else
                                Set.remove subscriptionId model.expandedRows
                    }
            in
            -- Expanding a still-untouched order auto-transitions it to In Progress (a status change,
            -- so no note text is required -- see `appendFulfillmentNote`'s own doc) -- an admin
            -- opening the row to look at it *is* the first step of working the order. Never fires on
            -- a collapse, and never fires again once it's past `AWAITING_HOST_ADMIN`.
            case ( nowExpanded, findSubscription subscriptionId model.subscriptions |> Maybe.andThen (\s -> hostingDetailsOf s |> Maybe.map (Tuple.pair s)) ) of
                ( True, Just ( subscription, details ) ) ->
                    if details.fulfillmentStatus == FULFILLMENTSTATUSAWAITINGHOSTADMIN then
                        appendFulfillmentNote shared newModel subscription details "" FULFILLMENTSTATUSINPROGRESS

                    else
                        ( newModel, Effect.none )

                _ ->
                    ( newModel, Effect.none )

        RowLinkClicked ->
            -- Just stops a domain/contact-email link's click from also toggling its row -- see
            -- `domainLinkView`/`contactEmailLinkView`.
            ( model, Effect.none )

        NoteDraftChanged subscriptionId text ->
            ( { model | noteDrafts = Dict.insert subscriptionId text model.noteDrafts }, Effect.none )

        SaveNoteClicked subscription ->
            case hostingDetailsOf subscription of
                Just details ->
                    let
                        draft : String
                        draft =
                            Dict.get subscription.id model.noteDrafts |> Maybe.withDefault ""
                    in
                    if String.isEmpty (String.trim draft) then
                        ( model, Effect.none )

                    else
                        appendFulfillmentNote shared model subscription details draft details.fulfillmentStatus

                Nothing ->
                    ( model, Effect.none )

        MarkAsFulfilledClicked subscription ->
            case hostingDetailsOf subscription of
                Just details ->
                    let
                        draft : String
                        draft =
                            Dict.get subscription.id model.noteDrafts |> Maybe.withDefault ""
                    in
                    appendFulfillmentNote shared model subscription details draft FULFILLMENTSTATUSFULFILLED

                Nothing ->
                    ( model, Effect.none )

        GotSaveNoteResult subscriptionId (Ok ( maybeAccountsPanelMsg, updated )) ->
            ( { model
                | noteSaves = Dict.remove subscriptionId model.noteSaves
                , noteDrafts = Dict.remove subscriptionId model.noteDrafts
                , subscriptions = replaceSubscription updated model.subscriptions
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSaveNoteResult subscriptionId (Err err) ->
            ( { model | noteSaves = Dict.insert subscriptionId (AccountsPanel.Errored (AccountsPanel.grpcErrorToString err)) model.noteSaves }
            , Effect.none
            )

        SharedMsgReceived subMsg ->
            let
                ( retriedModel, retryEffect ) =
                    attemptFetch shared model
            in
            ( retriedModel, Effect.batch [ Effect.fromShared subMsg, retryEffect ] )


{-| Appends one new `FulfillmentNote` (`noteText`, possibly blank -- see `FulfillmentNote.note`'s own
proto doc on when that's allowed -- attributed to the signed-in admin, with `newStatus` as its own
`fulfillmentStatus`) to `details.fulfillmentNotes` and sends the whole updated subscription through
`Market.updateMarketSubscription`. Shared by `SaveNoteClicked` (`newStatus` = whatever it already
is -- a plain note), `MarkAsFulfilledClicked` (`newStatus` = Fulfilled), and `RowToggled`'s own
auto-transition to In Progress -- the only three ways this page ever changes a subscription. A no-op
if nobody's actually signed in as an admin here (shouldn't happen in practice -- this page is
admin-gated to begin with -- but there's no admin id to attribute the note to otherwise).
-}
appendFulfillmentNote : Shared.Model -> Model -> MarketSubscription -> RellmHostingSubscriptionDetails -> String -> FulfillmentStatus -> ( Model, Effect Msg )
appendFulfillmentNote shared model subscription details noteText newStatus =
    case currentAdminUserId shared model.host of
        Nothing ->
            ( model, Effect.none )

        Just userId ->
            let
                updatedDetails : RellmHostingSubscriptionDetails
                updatedDetails =
                    { details
                        | fulfillmentNotes =
                            details.fulfillmentNotes
                                ++ [ { defaultFulfillmentNote | userId = userId, note = noteText, fulfillmentStatus = newStatus } ]
                    }
            in
            ( { model | noteSaves = Dict.insert subscription.id AccountsPanel.Submitting model.noteSaves }
            , Market.updateMarketSubscription shared.accounts
                (maybeAccountServer shared model.host)
                { subscription | details = Just (SubscriptionDetails.RellmHostingSubscriptionDetails updatedDetails) }
                |> Task.attempt (GotSaveNoteResult subscription.id)
                |> Effect.fromCmd
            )


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


replaceSubscription : MarketSubscription -> SubscriptionsState -> SubscriptionsState
replaceSubscription updated subscriptionsState =
    case subscriptionsState of
        SubscriptionsLoaded existing ->
            SubscriptionsLoaded
                (List.map
                    (\s ->
                        if s.id == updated.id then
                            updated

                        else
                            s
                    )
                    existing
                )

        other ->
            other



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    div [ class "market-fulfillment-page" ]
        (h1 [] [ text "Rellm Hosting Fulfillment" ]
            :: (if not (isAdminOn shared model.host) then
                    [ p [ class "market-fulfillment-admin-only" ] [ text "Admins only." ] ]

                else
                    case model.subscriptions of
                        SubscriptionsLoading ->
                            [ p [] [ text "Loading orders…" ] ]

                        SubscriptionsErrored err ->
                            [ p [ class "market-error" ] [ text ("Couldn't load orders: " ++ err) ]
                            , button [ onClick RefreshClicked ] [ text "Retry" ]
                            ]

                        SubscriptionsLoaded [] ->
                            [ p [ class "market-section-empty" ] [ text "No Rellm Hosting orders yet." ] ]

                        SubscriptionsLoaded subs ->
                            [ div [ class "market-fulfillment-table" ] (List.map (rowView shared model) subs) ]
               )
        )


rowView : Shared.Model -> Model -> MarketSubscription -> Html Msg
rowView shared model subscription =
    case hostingDetailsOf subscription of
        Nothing ->
            text ""

        Just details ->
            let
                expanded : Bool
                expanded =
                    Set.member subscription.id model.expandedRows

                maybeServer : Maybe RellmServers.RellmServer
                maybeServer =
                    RellmServers.rellmServerForHost shared.accounts.servers model.host

                maybeAccount : Maybe RellmAccounts.RellmAccount
                maybeAccount =
                    RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.host
            in
            div [ classes [ "market-fulfillment-row", openClosedClass expanded ] ]
                [ div [ class "market-fulfillment-row-summary", onClick (RowToggled subscription.id) ]
                    [ span [ class "market-fulfillment-row-buyer" ]
                        [ Authors.link shared.basePath model.host model.host maybeServer maybeAccount subscription.buyer ]
                    , domainLinkView model.host details.domain
                    , contactEmailLinkView model.host details.contactEmail
                    , fulfillmentStatusBadge details.fulfillmentStatus
                    ]
                , div [ classes [ "market-fulfillment-row-details-wrap", openClosedClass expanded ] ]
                    [ expandedRowView shared model subscription details ]
                ]


fulfillmentStatusBadge : FulfillmentStatus -> Html msg
fulfillmentStatusBadge status =
    span [ classes [ "market-fulfillment-badge", fulfillmentBadgeClass status ] ] [ text (fulfillmentStatusLabel status) ]


fulfillmentStatusLabel : FulfillmentStatus -> String
fulfillmentStatusLabel status =
    case status of
        FULFILLMENTSTATUSAWAITINGHOSTADMIN ->
            "Awaiting Host Admin"

        FULFILLMENTSTATUSINPROGRESS ->
            "In Progress"

        FULFILLMENTSTATUSFULFILLED ->
            "✓ Fulfilled"

        FulfillmentStatusUnrecognized_ _ ->
            "Unknown"


fulfillmentBadgeClass : FulfillmentStatus -> String
fulfillmentBadgeClass status =
    case status of
        FULFILLMENTSTATUSFULFILLED ->
            "market-fulfillment-badge-fulfilled"

        FULFILLMENTSTATUSINPROGRESS ->
            "market-fulfillment-badge-in-progress"

        _ ->
            "market-fulfillment-badge-pending"


{-| Stops its own click from bubbling up to `rowView`'s summary `onClick` (which would otherwise
also toggle the row every time this link is followed) -- same `stopPropagationOn` mechanism
`UI.navLink`/`UI.homeLink` use for their own nested-clickable-inside-clickable cases. `host`'s own
`hostnameToCSSClass` (mirroring e.g. `Components.Posts.postCardView`'s own external post link) is
what actually makes this look like a real link -- see `UI.EmittedStylesheet`'s `a.server-<host>`
rule, which colors it with that server's own theme `primaryAnchorColor`.
-}
domainLinkView : String -> String -> Html Msg
domainLinkView host domain =
    Html.a
        [ href ("https://" ++ domain)
        , target "_blank"
        , rel "noopener noreferrer"
        , classes [ hostnameToCSSClass host, "market-fulfillment-row-domain" ]
        , stopPropagationOn "click" (Decode.succeed ( RowLinkClicked, True ))
        ]
        [ text domain ]


{-| Same idea as `domainLinkView`, as a `mailto:` link instead of `https:`.
-}
contactEmailLinkView : String -> String -> Html Msg
contactEmailLinkView host contactEmail =
    Html.a
        [ href ("mailto:" ++ contactEmail)
        , classes [ hostnameToCSSClass host, "market-fulfillment-row-contact" ]
        , stopPropagationOn "click" (Decode.succeed ( RowLinkClicked, True ))
        ]
        [ text contactEmail ]


{-| Wrapped by `rowView` in a `.market-fulfillment-row-details-wrap` that's always mounted (open or
closed) so `grid-template-rows` can animate its height between `0fr` (closed) and `1fr` (open) --
the same trick `Components.Pages.ServerInformationPage.SettingsTab.featureSettingsSection`/
`Components.Pages.UserProfilePage`'s own `expandableProfileSection` use, and (within this same file)
`Components.Pages.MarketPage.addProductPanelView` -- including the same "no vertical padding/border
on the outer animated wrapper, its direct `> *` child gets `overflow: hidden; min-height: 0`, the
real padding/border/background live one level deeper" structure that trick needs to actually reach 0
height instead of stopping at its own padding+border. This function's own top-level `div` (below) is
that deeper level -- it keeps its existing padding/border unconditionally, whether open or closed.

Four sections, in order: the buyer's own purchase details, the fulfillment notes conversation (with
its compose form), the subscription's own cancellation details (only when actually canceled), and
its full payment/refund history.

-}
expandedRowView : Shared.Model -> Model -> MarketSubscription -> RellmHostingSubscriptionDetails -> Html Msg
expandedRowView shared model subscription details =
    div [ class "market-fulfillment-row-details" ]
        [ purchaseDetailsView details
        , notesView shared model subscription details
        , cancellationDetailsView shared.time.browserTimeZone subscription
        , billingHistoryView shared.time.browserTimeZone subscription
        ]


{-| The buyer's own request, captured once at purchase time and never editable afterward (see
`RellmHostingSubscriptionDetails.additionalInformation`'s own proto doc) -- domain/contact are
already shown in the row summary above, so this is just their free-form notes.
-}
purchaseDetailsView : RellmHostingSubscriptionDetails -> Html Msg
purchaseDetailsView details =
    if String.isEmpty details.additionalInformation then
        text ""

    else
        div [ class "market-fulfillment-section" ]
            [ h4 [ class "market-fulfillment-section-title" ] [ text "Purchase Details" ]
            , div [ class "market-fulfillment-additional-info" ]
                [ span [ class "market-fulfillment-additional-info-label" ] [ text "Buyer's notes at purchase:" ]
                , p [] [ text details.additionalInformation ]
                ]
            ]


notesView : Shared.Model -> Model -> MarketSubscription -> RellmHostingSubscriptionDetails -> Html Msg
notesView shared model subscription details =
    let
        noteSaveStatus : AccountsPanel.FormStatus
        noteSaveStatus =
            Dict.get subscription.id model.noteSaves |> Maybe.withDefault AccountsPanel.Idle

        draft : String
        draft =
            Dict.get subscription.id model.noteDrafts |> Maybe.withDefault ""

        maybeCurrentUserId : Maybe String
        maybeCurrentUserId =
            currentAdminUserId shared model.host

        submitting : Bool
        submitting =
            noteSaveStatus == AccountsPanel.Submitting

        draftIsBlank : Bool
        draftIsBlank =
            String.isEmpty (String.trim draft)
    in
    div [ class "market-fulfillment-section" ]
        [ h4 [ class "market-fulfillment-section-title" ] [ text "Notes" ]
        , fulfillmentStatusBadge details.fulfillmentStatus
        , div [ class "market-fulfillment-notes" ]
            (if List.isEmpty details.fulfillmentNotes then
                [ p [ class "market-form-hint" ] [ text "No fulfillment notes yet." ] ]

             else
                List.map (noteRowView shared.time.browserTimeZone maybeCurrentUserId) details.fulfillmentNotes
            )
        , div [ class "market-fulfillment-note-form" ]
            [ textarea
                [ placeholder "Add a note…"
                , value draft
                , onInput (NoteDraftChanged subscription.id)
                ]
                []
            , div [ class "market-fulfillment-note-form-actions" ]
                [ button
                    [ onClick (SaveNoteClicked subscription)
                    , disabled (submitting || draftIsBlank || maybeCurrentUserId == Nothing)
                    ]
                    [ text
                        (if submitting then
                            "Saving…"

                         else
                            "Add Note"
                        )
                    ]
                , button
                    [ onClick (MarkAsFulfilledClicked subscription)
                    , disabled
                        (submitting
                            || maybeCurrentUserId
                            == Nothing
                            || (details.fulfillmentStatus == FULFILLMENTSTATUSFULFILLED && draftIsBlank)
                        )
                    ]
                    [ text
                        (if submitting then
                            "Saving…"

                         else
                            "Add and Mark as Fulfilled"
                        )
                    ]
                ]
            , statusErrorView noteSaveStatus
            ]
        ]


{-| Only rendered once the subscription's actually been canceled -- see this message's own proto
doc: `canceledAt`/`serviceTerminatedAt` stay unset for the (overwhelmingly common) still-active case,
so there's nothing worth a whole section for otherwise.
-}
cancellationDetailsView : SharedTime.BrowserTimeZone -> MarketSubscription -> Html msg
cancellationDetailsView browserTimeZone subscription =
    if subscription.canceledAt == Nothing then
        text ""

    else
        div [ class "market-fulfillment-section" ]
            [ h4 [ class "market-fulfillment-section-title" ] [ text "Subscription Cancellation" ]
            , timestampLineView "Canceled" browserTimeZone subscription.canceledAt
            , timestampLineView "Service ended" browserTimeZone subscription.serviceTerminatedAt
            ]


timestampLineView : String -> SharedTime.BrowserTimeZone -> Maybe Proto.Google.Protobuf.Timestamp -> Html msg
timestampLineView label browserTimeZone maybeTimestamp =
    case maybeTimestamp of
        Just t ->
            p [ class "market-fulfillment-timestamp-line" ]
                [ text (label ++ " " ++ SharedTime.formatDate browserTimeZone.zone (Conversions.timestampToPosix t)) ]

        Nothing ->
            text ""


{-| The full payment/refund ledger for this order -- one row per `MarketPurchase` in
`billingHistory` (newest first, per that field's own proto doc), plus the aggregate totals and an
initial-vs-current price comparison. `MarketSubscription.amount` is captured once at subscription
creation and never drifts on its own in this codebase today (see that field's own proto doc), so
"current" only ever differs from "initially purchased" if some future admin tool starts editing it
directly -- shown defensively either way, since there's no cost to it being right if that ever
changes.
-}
billingHistoryView : SharedTime.BrowserTimeZone -> MarketSubscription -> Html msg
billingHistoryView browserTimeZone subscription =
    let
        purchases : List MarketPurchase
        purchases =
            List.map unwrapMarketPurchase subscription.billingHistory
    in
    div [ class "market-fulfillment-section" ]
        [ h4 [ class "market-fulfillment-section-title" ] [ text "Payment History" ]
        , if List.isEmpty purchases then
            p [ class "market-form-hint" ] [ text "No payments recorded yet." ]

          else
            billingHistoryContentView browserTimeZone subscription purchases
        ]


billingHistoryContentView : SharedTime.BrowserTimeZone -> MarketSubscription -> List MarketPurchase -> Html msg
billingHistoryContentView browserTimeZone subscription purchases =
    let
        allPayments : List Proto.Rellm.MarketPayment
        allPayments =
            List.concatMap .marketPayments purchases

        allRefunds : List Proto.Rellm.MarketRefund
        allRefunds =
            List.concatMap .marketRefunds purchases

        totalPaid : Int
        totalPaid =
            allPayments |> List.map .amount |> List.sum

        totalRefunded : Int
        totalRefunded =
            allRefunds |> List.map .amount |> List.sum

        currency : Int
        currency =
            allPayments |> List.head |> Maybe.map .currency |> Maybe.withDefault (allRefunds |> List.head |> Maybe.map .currency |> Maybe.withDefault 0)

        initialAmount : Maybe ( Int, Int )
        initialAmount =
            purchases
                |> List.reverse
                |> List.head
                |> Maybe.andThen (\p -> List.head p.marketPayments)
                |> Maybe.map (\payment -> ( payment.amount, payment.currency ))
    in
    div []
        [ p [ class "market-fulfillment-billing-totals" ]
            [ text ("Total Paid: " ++ Market.formatAmount totalPaid currency) ]
        , if totalRefunded > 0 then
            p [ class "market-fulfillment-billing-totals" ]
                [ text ("Total Refunded: " ++ Market.formatAmount totalRefunded currency) ]

          else
            text ""
        , case initialAmount of
            Just ( amount, initialCurrency ) ->
                div []
                    [ p [ class "market-fulfillment-billing-totals" ]
                        [ text ("Initially Purchased: " ++ Market.formatAmount amount initialCurrency) ]
                    , if ( amount, initialCurrency ) /= ( subscription.amount, subscription.currency ) then
                        p [ class "market-fulfillment-billing-totals" ]
                            [ text
                                ("Current Subscription Amount: "
                                    ++ Market.formatAmount subscription.amount subscription.currency
                                )
                            ]

                      else
                        text ""
                    ]

            Nothing ->
                text ""
        , div [ class "market-fulfillment-billing-history" ]
            (purchases |> List.map (billingHistoryRowView browserTimeZone))
        ]


billingHistoryRowView : SharedTime.BrowserTimeZone -> MarketPurchase -> Html msg
billingHistoryRowView browserTimeZone purchase =
    let
        dateText : String
        dateText =
            purchase.createdAt
                |> Maybe.map (Conversions.timestampToPosix >> SharedTime.formatDate browserTimeZone.zone)
                |> Maybe.withDefault ""

        paymentLines : List (Html msg)
        paymentLines =
            purchase.marketPayments
                |> List.map
                    (\payment ->
                        p [ class "market-fulfillment-billing-history-line" ]
                            [ text (Market.formatAmount payment.amount payment.currency ++ cardSuffix payment.method) ]
                    )

        refundLines : List (Html msg)
        refundLines =
            purchase.marketRefunds
                |> List.map
                    (\refund ->
                        p [ class "market-fulfillment-billing-history-line market-fulfillment-billing-history-refund" ]
                            [ text ("Refund " ++ Market.formatAmount refund.amount refund.currency ++ cardSuffix refund.method) ]
                    )

        cardSuffix : Maybe { a | cardBrand : String, cardLast4 : String } -> String
        cardSuffix maybeMethod =
            maybeMethod |> Maybe.map (\m -> " · " ++ formatCardMethod m) |> Maybe.withDefault ""
    in
    div [ class "market-fulfillment-billing-history-row" ]
        (span [ class "market-fulfillment-billing-history-date" ] [ text dateText ] :: paymentLines ++ refundLines)


{-| E.g. "Visa •••• 4242" -- works for both `MarketPaymentMethod` and `MarketRefundMethod` (same
`cardBrand`/`cardLast4` fields, structurally, just distinct generated types -- see `market.proto`'s
own doc on why they're kept separate).
-}
formatCardMethod : { a | cardBrand : String, cardLast4 : String } -> String
formatCardMethod method =
    capitalizeWord method.cardBrand ++ " •••• " ++ method.cardLast4


capitalizeWord : String -> String
capitalizeWord word =
    case String.uncons word of
        Just ( first, rest ) ->
            String.cons (Char.toUpper first) rest

        Nothing ->
            word


statusErrorView : AccountsPanel.FormStatus -> Html msg
statusErrorView status =
    case status of
        AccountsPanel.Errored err ->
            span [ class "market-form-error" ] [ text err ]

        _ ->
            text ""


{-| "You" for the signed-in admin's own notes (cheap to resolve, since `maybeCurrentUserId` is
already on hand -- see `currentAdminUserId`), the bare `userId` otherwise. Resolving every other
admin's id to a display name would need a whole extra `GetUsers` fetch this page has no other reason
to make, so a raw id is an acceptable fallback for someone else's note.
-}
noteAuthorLabel : Maybe String -> String -> String
noteAuthorLabel maybeCurrentUserId userId =
    if maybeCurrentUserId == Just userId then
        "You"

    else
        userId


noteRowView : SharedTime.BrowserTimeZone -> Maybe String -> FulfillmentNote -> Html msg
noteRowView browserTimeZone maybeCurrentUserId note =
    div [ class "market-fulfillment-note" ]
        [ div [ class "market-fulfillment-note-meta" ]
            [ span [ class "market-fulfillment-note-author" ] [ text (noteAuthorLabel maybeCurrentUserId note.userId) ]
            , span [ classes [ "market-fulfillment-badge", "market-fulfillment-note-status", fulfillmentBadgeClass note.fulfillmentStatus ] ]
                [ text (fulfillmentStatusLabel note.fulfillmentStatus) ]
            , span [ class "market-fulfillment-note-time" ]
                [ text
                    (note.createdAt
                        |> Maybe.map (Conversions.timestampToPosix >> SharedTime.formatDate browserTimeZone.zone)
                        |> Maybe.withDefault ""
                    )
                ]
            ]
        , if String.isEmpty note.note then
            text ""

          else
            p [ class "market-fulfillment-note-text" ] [ text note.note ]
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
