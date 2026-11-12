module Components.FulfillmentThreads exposing
    ( Model
    , Msg(..)
    , empty
    , fetchAll
    , hasNotes
    , openCmd
    , subscriptionLinks
    , threadByKey
    , threadKey
    , threadUrl
    , totalUnread
    , unreadCount
    , update
    , view
    )

{-| The "Fulfillment" side of `Components.Pages.MessagesPage` (and so of `Shared.MessagingPanel`,
which embeds it): the signed-in user's own `PURCHASE_TYPE_RELLM_HOSTING` subscriptions, each one a
chat thread made of its `fulfillmentNotes` (`market.proto`) -- the host admin's updates about
setting up the order. Self-contained on purpose (`MessagesPage` is already huge): its own fetch per
signed-in account (`GetMarketSubscriptions`, the caller's own), its own unread math, its own view.
Like `MessagesPage` it can't import `Shared` (the panel embeds it).

*Unread* is the buyer's own marker, `RellmHostingSubscriptionDetails.notesLastRead`: a note counts
if somebody other than the buyer wrote it and it's newer than that marker (or the marker is unset).
Opening a thread with unread notes calls `MarkFulfillmentNotesRead` (`markReadCmd`).

-}

import Dict exposing (Dict)
import Grpc
import Html exposing (Html, a, button, div, p, span, text)
import Html.Attributes exposing (class, disabled, href)
import Html.Events exposing (onClick, preventDefaultOn)
import Json.Decode as Decode
import Proto.Google.Protobuf
import Proto.Rellm exposing (FulfillmentNote, MarketSubscription, defaultMarkFulfillmentNotesReadRequest, defaultMarketSubscriptionPushRequest)
import Proto.Rellm.FulfillmentStatus exposing (FulfillmentStatus(..))
import Proto.Rellm.GetMarketSubscriptionsRequestType exposing (GetMarketSubscriptionsRequestType(..))
import Proto.Rellm.MarketSubscription.Details as SubscriptionDetails
import Proto.Rellm.MarketSubscriptionState exposing (MarketSubscriptionState(..))
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers exposing (withAccessToken)
import Shared.Conversions as Conversions
import Shared.Time as SharedTime
import Task exposing (Task)
import Time
import UI.Classes exposing (classes)


type Status
    = Loading
    | Loaded (List MarketSubscription)
    | Failed


{-| One signed-in account's own subscriptions. Keyed in `Model.feeds` by `rellmAccountId`, so two
accounts on the same server (or one on each of several servers) never overwrite each other.
-}
type alias Feed =
    { host : String
    , accountId : String
    , status : Status
    }


type alias Model =
    { feeds : Dict String Feed

    -- Per `threadKey`: whether *this browser's* push subscription is opted in to that thread's
    -- notifications (`GetMarketSubscriptionPushStatus`); absent until checked.
    , pushOptIn : Dict String Bool
    , pushBusy : Dict String ()
    }


type Msg
    = GotSubscriptions String (Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ))
    | GotMarkedRead (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | GotPushStatus String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Bool ))
    | PushToggleClicked Thread Bool
    | GotPushToggled String Bool (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))


empty : Model
empty =
    { feeds = Dict.empty, pushOptIn = Dict.empty, pushBusy = Dict.empty }


{-| A subscription plus where it lives. `key` is unique across servers (ids are per-server).
-}
type alias Thread =
    { key : String
    , host : String
    , accountId : String
    , subscription : MarketSubscription
    }


threadKey : String -> String -> String
threadKey host subscriptionId =
    host ++ "/" ++ subscriptionId


{-| `/messages?subscription_messages=<id>[@host]` -- deep link to one thread, the subscription
counterpart of `?messaging_group=`. `mainFrontendHost`'s own ids carry no `@host` suffix, same as
`Components.Messages.groupRouteId`. `noteIndex` (0-based) adds `#subscription-message-<n>` to scroll
to one note.
-}
threadUrl : String -> String -> String -> Maybe Int -> String
threadUrl mainFrontendHost host subscriptionId noteIndex =
    "/messages?subscription_messages="
        ++ (if host == mainFrontendHost then
                subscriptionId

            else
                subscriptionId ++ "@" ++ host
           )
        ++ (case noteIndex of
                Just index ->
                    "#subscription-message-" ++ String.fromInt index

                Nothing ->
                    ""
           )



-- DATA


notesOf : MarketSubscription -> List FulfillmentNote
notesOf subscription =
    case subscription.details of
        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            details.fulfillmentNotes

        _ ->
            []


notesLastRead : MarketSubscription -> Maybe Proto.Google.Protobuf.Timestamp
notesLastRead subscription =
    case subscription.details of
        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            details.notesLastRead

        _ ->
            Nothing


buyerId : MarketSubscription -> String
buyerId subscription =
    subscription.buyer |> Maybe.map .userId |> Maybe.withDefault ""


millis : Proto.Google.Protobuf.Timestamp -> Int
millis =
    Conversions.timestampToPosix >> Time.posixToMillis


{-| See this module's doc: written by someone other than the buyer, and newer than `notesLastRead`.
-}
isUnreadNote : MarketSubscription -> FulfillmentNote -> Bool
isUnreadNote subscription note =
    note.userId
        /= buyerId subscription
        && (case ( notesLastRead subscription, note.createdAt ) of
                ( Nothing, _ ) ->
                    True

                ( Just _, Nothing ) ->
                    False

                ( Just read, Just created ) ->
                    millis created > millis read
           )


unreadCount : MarketSubscription -> Int
unreadCount subscription =
    notesOf subscription |> List.filter (isUnreadNote subscription) |> List.length


{-| Every loaded Rellm hosting subscription that has at least one note, oldest order first --
what the Fulfillment tab lists. A subscription with no notes isn't a conversation yet.
-}
threads : Model -> List Thread
threads model =
    model.feeds
        |> Dict.values
        |> List.concatMap
            (\feed ->
                case feed.status of
                    Loaded subscriptions ->
                        subscriptions
                            |> List.filter (\s -> s.type_ == PURCHASETYPERELLMHOSTING && not (List.isEmpty (notesOf s)))
                            |> List.map (\s -> { key = threadKey feed.host s.id, host = feed.host, accountId = feed.accountId, subscription = s })

                    _ ->
                        []
            )
        |> List.sortBy (\t -> t.subscription.createdAt |> Maybe.map millis |> Maybe.withDefault 0)


{-| Whether the Fulfillment tab should exist at all: only once there's something to read.
-}
hasNotes : Model -> Bool
hasNotes model =
    not (List.isEmpty (threads model))


totalUnread : Model -> Int
totalUnread model =
    threads model |> List.map (.subscription >> unreadCount) |> List.sum



-- FETCH


{-| Refetches the caller's own subscriptions from every signed-in account's (connected) server.
Cheap (one small RPC per account), so callers just call it on every poll.
-}
fetchAll : AccountsPanel.Model -> Model -> ( Model, Cmd Msg )
fetchAll accountsPanelModel model =
    let
        entries : List ( RellmAccounts.RellmAccount, String )
        entries =
            AccountsPanel.enabledAccounts accountsPanelModel
                |> List.filterMap
                    (\account ->
                        RellmServers.knownConnectedRellmServer accountsPanelModel.servers account.server
                            |> Maybe.map (\_ -> ( account, RellmAccounts.rellmAccountId account ))
                    )

        withFeed : ( RellmAccounts.RellmAccount, String ) -> Dict String Feed -> Dict String Feed
        withFeed ( account, id ) feeds =
            if Dict.member id feeds then
                feeds

            else
                Dict.insert id { host = account.server, accountId = id, status = Loading } feeds

        liveIds : List String
        liveIds =
            List.map Tuple.second entries
    in
    ( { model
        | feeds =
            List.foldl withFeed model.feeds entries
                |> Dict.filter (\id _ -> List.member id liveIds)
      }
    , entries
        |> List.map
            (\( account, id ) ->
                AccountsPanel.performWithAccountServer accountsPanelModel ( Just account.userId, account.server ) (\server token ->
                    Grpc.new Rellm.getMarketSubscriptions { requestType = GETMARKETSUBSCRIPTIONSREQUESTFORPURCHASE }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                    )
                    |> Task.map (\( m, response ) -> ( m, response.marketSubscriptions ))
                    |> Task.attempt (GotSubscriptions id)
            )
        |> Cmd.batch
    )


rpcFor :
    AccountsPanel.Model
    -> Thread
    -> (RellmServers.RellmServer -> String -> Task Grpc.Error a)
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, a )
rpcFor accountsPanelModel thread call =
    AccountsPanel.performWithAccountServer accountsPanelModel ( accountUserId thread.accountId, thread.host ) call


{-| `rellmAccountId` is `server|userId`.
-}
accountUserId : String -> Maybe String
accountUserId accountId =
    case String.split "|" accountId of
        [ _, userId ] ->
            Just userId

        _ ->
            Nothing


{-| Stamps the thread's notes read (`MarkFulfillmentNotesRead`) -- a no-op `Cmd.none` if there's
nothing unread, so callers can fire it unconditionally on opening a thread.
-}
markReadCmd : AccountsPanel.Model -> Thread -> Cmd Msg
markReadCmd accountsPanelModel thread =
    if unreadCount thread.subscription == 0 then
        Cmd.none

    else
        rpcFor accountsPanelModel
            thread
            (\server token ->
                Grpc.new Rellm.markFulfillmentNotesRead { defaultMarkFulfillmentNotesReadRequest | marketSubscriptionId = thread.subscription.id }
                    |> Grpc.setHost (RellmServers.rellmServerUrl server)
                    |> withAccessToken (Just token)
                    |> Grpc.toTask
            )
            |> Task.attempt GotMarkedRead


{-| One row per Rellm hosting subscription that has notes, among `subscriptions` (already-fetched,
e.g. `RellmAccount.marketSubscriptions`/`User.marketSubscriptions`, all on `host`): a title, its unread
count and a link to its thread on the Messages page. What the Accounts panel and the profile page's
Subscriptions lists show.
-}
subscriptionLinks : String -> String -> List MarketSubscription -> List { subscription : MarketSubscription, title : String, unread : Int, url : String }
subscriptionLinks mainFrontendHost host subscriptions =
    subscriptions
        |> List.filter (\s -> s.type_ == PURCHASETYPERELLMHOSTING && not (List.isEmpty (notesOf s)))
        |> List.map
            (\s ->
                { subscription = s
                , title = threadTitle s
                , unread = unreadCount s
                , url = threadUrl mainFrontendHost host s.id Nothing
                }
            )


threadByKey : Model -> String -> Maybe Thread
threadByKey model key =
    threads model |> List.filter (\t -> t.key == key) |> List.head


{-| What opening a thread does: mark its unread notes read, and (once) look up whether this browser
is opted in to its push notifications.
-}
openCmd : AccountsPanel.Model -> Model -> Thread -> Cmd Msg
openCmd accountsPanelModel model thread =
    Cmd.batch
        [ markReadCmd accountsPanelModel thread
        , if Dict.member thread.key model.pushOptIn then
            Cmd.none

          else
            pushStatusCmd accountsPanelModel thread
        ]


pushRequest : AccountsPanel.Model -> Thread -> Maybe String
pushRequest accountsPanelModel thread =
    Dict.get thread.accountId accountsPanelModel.pushSubscriptions


pushStatusCmd : AccountsPanel.Model -> Thread -> Cmd Msg
pushStatusCmd accountsPanelModel thread =
    case pushRequest accountsPanelModel thread of
        Nothing ->
            Cmd.none

        Just endpoint ->
            rpcFor accountsPanelModel
                thread
                (\server token ->
                    Grpc.new Rellm.getMarketSubscriptionPushStatus { defaultMarketSubscriptionPushRequest | marketSubscriptionId = thread.subscription.id, endpoint = endpoint }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                )
                |> Task.map (\( m, response ) -> ( m, response.registered ))
                |> Task.attempt (GotPushStatus thread.key)



-- UPDATE


{-| `selected` is the currently open thread's `threadKey`, if any: once its notes load/refresh, a
still-unread open thread is marked read straight away (so a deep link, or a note arriving while it's
open, doesn't leave a stale badge), and its push opt-in status is looked up.
-}
update : AccountsPanel.Model -> Maybe String -> Msg -> Model -> ( Model, Cmd Msg, Maybe AccountsPanel.Msg )
update accountsPanelModel selected msg model =
    case msg of
        GotSubscriptions id (Ok ( maybeMsg, subscriptions )) ->
            let
                updated : Model
                updated =
                    { model | feeds = Dict.update id (Maybe.map (\f -> { f | status = Loaded subscriptions })) model.feeds }
            in
            ( updated
            , selected
                |> Maybe.andThen (threadByKey updated)
                |> Maybe.map (openCmd accountsPanelModel updated)
                |> Maybe.withDefault Cmd.none
            , maybeMsg
            )

        GotSubscriptions id (Err _) ->
            ( { model | feeds = Dict.update id (Maybe.map (\f -> { f | status = Failed })) model.feeds }, Cmd.none, Nothing )

        GotMarkedRead (Ok ( maybeMsg, updatedSubscription )) ->
            ( { model | feeds = Dict.map (\_ feed -> replaceSubscription updatedSubscription feed) model.feeds }
            , Cmd.none
            , maybeMsg
            )

        GotMarkedRead (Err _) ->
            ( model, Cmd.none, Nothing )

        GotPushStatus key (Ok ( maybeMsg, registered )) ->
            ( { model | pushOptIn = Dict.insert key registered model.pushOptIn }, Cmd.none, maybeMsg )

        GotPushStatus _ (Err _) ->
            ( model, Cmd.none, Nothing )

        PushToggleClicked thread wanted ->
            case pushRequest accountsPanelModel thread of
                Nothing ->
                    ( model, Cmd.none, Nothing )

                Just endpoint ->
                    ( { model | pushBusy = Dict.insert thread.key () model.pushBusy }
                    , rpcFor accountsPanelModel
                        thread
                        (\server token ->
                            let
                                request : Proto.Rellm.MarketSubscriptionPushRequest
                                request =
                                    { defaultMarketSubscriptionPushRequest | marketSubscriptionId = thread.subscription.id, endpoint = endpoint }
                            in
                            (if wanted then
                                Grpc.new Rellm.registerMarketSubscriptionPush request

                             else
                                Grpc.new Rellm.unregisterMarketSubscriptionPush request
                            )
                                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                                |> withAccessToken (Just token)
                                |> Grpc.toTask
                        )
                        |> Task.map (\( m, _ ) -> ( m, () ))
                        |> Task.attempt (GotPushToggled thread.key wanted)
                    , Nothing
                    )

        GotPushToggled key wanted (Ok ( maybeMsg, () )) ->
            ( { model | pushBusy = Dict.remove key model.pushBusy, pushOptIn = Dict.insert key wanted model.pushOptIn }, Cmd.none, maybeMsg )

        GotPushToggled key _ (Err _) ->
            ( { model | pushBusy = Dict.remove key model.pushBusy }, Cmd.none, Nothing )


replaceSubscription : MarketSubscription -> Feed -> Feed
replaceSubscription updated feed =
    case feed.status of
        Loaded subscriptions ->
            { feed | status = Loaded (List.map (\s -> if s.id == updated.id then updated else s) subscriptions) }

        _ ->
            feed



-- VIEW


{-| The Fulfillment tab's body. `selected` is the open thread's key. `onSelect` is how a row asks to
open (page: select in place; the embedded panel passes `Nothing` and rows become plain links to the
real page instead). `pushAvailable`: this account has a registered Web Push subscription on this
browser (otherwise the notification toggle explains how to enable it).
-}
view :
    { time : SharedTime.Model
    , accountsPanelModel : AccountsPanel.Model
    , model : Model
    , selected : Maybe String
    , onSelect : Maybe (String -> msg)
    , toMsg : Msg -> msg
    }
    -> Html msg
view config =
    case threads config.model of
        [] ->
            p [ class "posts-empty" ] [ text "No fulfillment messages yet." ]

        all ->
            div [ class "fulfillment-thread-list" ] (List.map (threadView config) all)


threadView :
    { time : SharedTime.Model
    , accountsPanelModel : AccountsPanel.Model
    , model : Model
    , selected : Maybe String
    , onSelect : Maybe (String -> msg)
    , toMsg : Msg -> msg
    }
    -> Thread
    -> Html msg
threadView config thread =
    let
        subscription : MarketSubscription
        subscription =
            thread.subscription

        unread : Int
        unread =
            unreadCount subscription

        isSelected : Bool
        isSelected =
            config.selected == Just thread.key

        notes : List FulfillmentNote
        notes =
            notesOf subscription

        url : String
        url =
            threadUrl config.accountsPanelModel.mainFrontendHost thread.host subscription.id Nothing

        headerAttrs : List (Html.Attribute msg)
        headerAttrs =
            case config.onSelect of
                Just select ->
                    [ class "fulfillment-thread-header"
                    , href url
                    , preventDefaultOn "click" (Decode.succeed ( select thread.key, True ))
                    ]

                Nothing ->
                    [ class "fulfillment-thread-header", href url ]
    in
    div
        [ classes [ "fulfillment-thread", if isSelected then "fulfillment-thread-selected" else "" ]
        , Html.Attributes.id ("subscription-thread-" ++ subscription.id)
        ]
        [ a headerAttrs
            [ span [ class "fulfillment-thread-title" ] [ text (threadTitle subscription) ]
            , stateBadge subscription.state
            , if unread > 0 then
                span [ class "unread-count-badge", Html.Attributes.title "Unread notes" ] [ text (String.fromInt unread) ]

              else
                text ""
            ]
        , if isSelected then
            div [ class "fulfillment-thread-body" ]
                (List.indexedMap (noteView config.time subscription) notes
                    ++ [ pushToggleView config thread ]
                )

          else
            case List.reverse notes |> List.head of
                Just last ->
                    p [ class "fulfillment-thread-preview" ] [ text (notePreview last) ]

                Nothing ->
                    text ""
        ]


threadTitle : MarketSubscription -> String
threadTitle subscription =
    case subscription.details of
        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            "Rellm Hosting"
                ++ (if String.isEmpty details.domain then
                        ""

                    else
                        " · " ++ details.domain
                   )

        _ ->
            "Rellm Hosting"


stateBadge : MarketSubscriptionState -> Html msg
stateBadge state =
    case state of
        SUBSCRIPTIONACTIVE ->
            text ""

        SUBSCRIPTIONACTIVEBUTCANCELED ->
            span [ class "fulfillment-thread-state" ] [ text "Canceled · active until period ends" ]

        _ ->
            span [ class "fulfillment-thread-state" ] [ text "Canceled" ]


statusLabel : FulfillmentStatus -> String
statusLabel status =
    case status of
        FULFILLMENTSTATUSFULFILLED ->
            "Fulfilled"

        FULFILLMENTSTATUSINPROGRESS ->
            "In Progress"

        _ ->
            "Awaiting Host Admin"


notePreview : FulfillmentNote -> String
notePreview note =
    if String.isEmpty (String.trim note.note) then
        "Status: " ++ statusLabel note.fulfillmentStatus

    else
        note.note
            |> String.lines
            |> List.map String.trim
            |> List.filter (not << String.isEmpty)
            |> List.head
            |> Maybe.withDefault ""


noteView : SharedTime.Model -> MarketSubscription -> Int -> FulfillmentNote -> Html msg
noteView time subscription index note =
    let
        mine : Bool
        mine =
            note.userId == buyerId subscription
    in
    div
        [ classes [ "fulfillment-note", if mine then "fulfillment-note-mine" else "", if isUnreadNote subscription note then "fulfillment-note-unread" else "" ]
        , Html.Attributes.id ("subscription-message-" ++ String.fromInt index)
        ]
        [ div [ class "fulfillment-note-meta" ]
            [ span [ class "fulfillment-note-author" ]
                [ text
                    (if mine then
                        "You"

                     else
                        "Host admin"
                    )
                ]
            , span [ class "fulfillment-note-status" ] [ text (statusLabel note.fulfillmentStatus) ]
            , span [ class "fulfillment-note-time" ]
                [ text
                    (note.createdAt
                        |> Maybe.map (Conversions.timestampToPosix >> SharedTime.formatDate time.browserTimeZone.zone)
                        |> Maybe.withDefault ""
                    )
                ]
            ]
        , if String.isEmpty note.note then
            text ""

          else
            p [ class "fulfillment-note-text" ] [ text note.note ]
        ]


pushToggleView :
    { a | accountsPanelModel : AccountsPanel.Model, model : Model, toMsg : Msg -> msg }
    -> Thread
    -> Html msg
pushToggleView config thread =
    case pushRequest config.accountsPanelModel thread of
        Nothing ->
            p [ class "market-form-hint" ] [ text "Enable notifications for this account in the Accounts panel to be notified of new updates here." ]

        Just _ ->
            let
                optedIn : Bool
                optedIn =
                    Dict.get thread.key config.model.pushOptIn |> Maybe.withDefault False

                busy : Bool
                busy =
                    Dict.member thread.key config.model.pushBusy
            in
            div [ class "fulfillment-push-toggle" ]
                [ button
                    [ Html.Attributes.type_ "button"
                    , onClick (config.toMsg (PushToggleClicked thread (not optedIn)))
                    , disabled busy
                    ]
                    [ text
                        (if optedIn then
                            "Turn off notifications for this order"

                         else
                            "Notify me of updates to this order"
                        )
                    ]
                ]
