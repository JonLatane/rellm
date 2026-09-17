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
email, and a read-only `fulfilled` badge; clicking it expands an editable `fulfilled` toggle, the
buyer's own (immutable) `additionalInformation`, the oldest-first `fulfillmentNotes` conversation, and
a form to append a new note -- both the toggle and the note form call
`Components.Market.updateMarketSubscription` directly (see that function's own doc on the
append-only note contract: always send back the subscription's last-fetched `fulfillmentNotes`
verbatim, plus at most one new entry).
-}

import Components.Authors as Authors
import Components.Market as Market
import Dict exposing (Dict)
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h1, input, label, p, span, text, textarea)
import Html.Attributes exposing (checked, class, disabled, href, placeholder, rel, target, type_, value)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
import Json.Decode as Decode
import Proto.Rellm exposing (FulfillmentNote, GetMarketSubscriptionsResponse, MarketSubscription, RellmHostingSubscriptionDetails, defaultFulfillmentNote)
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
import UI.Classes exposing (classes, openClosedClass)



-- MODEL


type alias Model =
    { host : String
    , subscriptions : SubscriptionsState
    , fetchStarted : Bool
    , expandedRows : Set String
    , fulfilledToggles : Dict String AccountsPanel.FormStatus
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
                , fulfilledToggles = Dict.empty
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


{-| Fires `fetchSubscriptions` the first time `model.host` is both a known, *connected* server
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



-- UPDATE


type Msg
    = GotSubscriptionsResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMarketSubscriptionsResponse ))
    | RefreshClicked
    | RowToggled String
    | RowLinkClicked
    | FulfilledToggleClicked MarketSubscription
    | GotFulfilledToggleResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | NoteDraftChanged String String
    | SaveNoteClicked MarketSubscription
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
            ( { model
                | expandedRows =
                    if Set.member subscriptionId model.expandedRows then
                        Set.remove subscriptionId model.expandedRows

                    else
                        Set.insert subscriptionId model.expandedRows
              }
            , Effect.none
            )

        RowLinkClicked ->
            -- Just stops a domain link's click from also toggling its row -- see `domainLinkView`.
            ( model, Effect.none )

        FulfilledToggleClicked subscription ->
            case hostingDetailsOf subscription of
                Just details ->
                    ( { model | fulfilledToggles = Dict.insert subscription.id AccountsPanel.Submitting model.fulfilledToggles }
                    , Market.updateMarketSubscription shared.accounts
                        (maybeAccountServer shared model.host)
                        { subscription
                            | details =
                                Just (SubscriptionDetails.RellmHostingSubscriptionDetails { details | fulfilled = not details.fulfilled })
                        }
                        |> Task.attempt (GotFulfilledToggleResult subscription.id)
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        GotFulfilledToggleResult subscriptionId (Ok ( maybeAccountsPanelMsg, updated )) ->
            ( { model
                | fulfilledToggles = Dict.remove subscriptionId model.fulfilledToggles
                , subscriptions = replaceSubscription updated model.subscriptions
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotFulfilledToggleResult subscriptionId (Err err) ->
            ( { model | fulfilledToggles = Dict.insert subscriptionId (AccountsPanel.Errored (AccountsPanel.grpcErrorToString err)) model.fulfilledToggles }
            , Effect.none
            )

        NoteDraftChanged subscriptionId text ->
            ( { model | noteDrafts = Dict.insert subscriptionId text model.noteDrafts }, Effect.none )

        SaveNoteClicked subscription ->
            case ( hostingDetailsOf subscription, currentAdminUserId shared model.host ) of
                ( Just details, Just userId ) ->
                    let
                        draft : String
                        draft =
                            Dict.get subscription.id model.noteDrafts |> Maybe.withDefault ""
                    in
                    if String.isEmpty (String.trim draft) then
                        ( model, Effect.none )

                    else
                        let
                            updatedDetails : RellmHostingSubscriptionDetails
                            updatedDetails =
                                { details
                                    | fulfillmentNotes =
                                        details.fulfillmentNotes ++ [ { defaultFulfillmentNote | userId = userId, note = draft } ]
                                }
                        in
                        ( { model | noteSaves = Dict.insert subscription.id AccountsPanel.Submitting model.noteSaves }
                        , Market.updateMarketSubscription shared.accounts
                            (maybeAccountServer shared model.host)
                            { subscription | details = Just (SubscriptionDetails.RellmHostingSubscriptionDetails updatedDetails) }
                            |> Task.attempt (GotSaveNoteResult subscription.id)
                            |> Effect.fromCmd
                        )

                _ ->
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


accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


replaceSubscription : MarketSubscription -> SubscriptionsState -> SubscriptionsState
replaceSubscription updated subscriptionsState =
    case subscriptionsState of
        SubscriptionsLoaded existing ->
            SubscriptionsLoaded (List.map (\s -> if s.id == updated.id then updated else s) existing)

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
                    , domainLinkView details.domain
                    , span [ class "market-fulfillment-row-contact" ] [ text details.contactEmail ]
                    , span
                        [ classes
                            [ "market-fulfillment-badge"
                            , if details.fulfilled then
                                "market-fulfillment-badge-fulfilled"

                              else
                                "market-fulfillment-badge-pending"
                            ]
                        ]
                        [ text
                            (if details.fulfilled then
                                "\u{2713} Fulfilled"

                             else
                                "Pending"
                            )
                        ]
                    ]
                , if expanded then
                    expandedRowView shared model subscription details

                  else
                    text ""
                ]


{-| Stops its own click from bubbling up to `rowView`'s summary `onClick` (which would otherwise
also toggle the row every time this link is followed) -- same `stopPropagationOn` mechanism
`UI.navLink`/`UI.homeLink` use for their own nested-clickable-inside-clickable cases.
-}
domainLinkView : String -> Html Msg
domainLinkView domain =
    Html.a
        [ href ("https://" ++ domain)
        , target "_blank"
        , rel "noopener noreferrer"
        , class "market-fulfillment-row-domain"
        , stopPropagationOn "click" (Decode.succeed ( RowLinkClicked, True ))
        ]
        [ text domain ]


expandedRowView : Shared.Model -> Model -> MarketSubscription -> RellmHostingSubscriptionDetails -> Html Msg
expandedRowView shared model subscription details =
    let
        fulfilledStatus : AccountsPanel.FormStatus
        fulfilledStatus =
            Dict.get subscription.id model.fulfilledToggles |> Maybe.withDefault AccountsPanel.Idle

        noteSaveStatus : AccountsPanel.FormStatus
        noteSaveStatus =
            Dict.get subscription.id model.noteSaves |> Maybe.withDefault AccountsPanel.Idle

        draft : String
        draft =
            Dict.get subscription.id model.noteDrafts |> Maybe.withDefault ""

        maybeCurrentUserId : Maybe String
        maybeCurrentUserId =
            currentAdminUserId shared model.host
    in
    div [ class "market-fulfillment-row-details" ]
        [ div [ class "market-fulfillment-fulfilled-toggle" ]
            [ label []
                [ input
                    [ type_ "checkbox"
                    , checked details.fulfilled
                    , onClick (FulfilledToggleClicked subscription)
                    , disabled (fulfilledStatus == AccountsPanel.Submitting)
                    ]
                    []
                , text " Fulfilled"
                ]
            , statusErrorView fulfilledStatus
            ]
        , if String.isEmpty details.additionalInformation then
            text ""

          else
            div [ class "market-fulfillment-additional-info" ]
                [ span [ class "market-fulfillment-additional-info-label" ] [ text "Buyer's notes at purchase:" ]
                , p [] [ text details.additionalInformation ]
                ]
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
            , button
                [ onClick (SaveNoteClicked subscription)
                , disabled (noteSaveStatus == AccountsPanel.Submitting || String.isEmpty (String.trim draft) || maybeCurrentUserId == Nothing)
                ]
                [ text
                    (if noteSaveStatus == AccountsPanel.Submitting then
                        "Saving…"

                     else
                        "Save"
                    )
                ]
            , statusErrorView noteSaveStatus
            ]
        ]


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
            , span [ class "market-fulfillment-note-time" ]
                [ text
                    (note.createdAt
                        |> Maybe.map (Conversions.timestampToPosix >> SharedTime.formatDate browserTimeZone.zone)
                        |> Maybe.withDefault ""
                    )
                ]
            ]
        , p [ class "market-fulfillment-note-text" ] [ text note.note ]
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived
