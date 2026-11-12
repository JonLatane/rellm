module Components.FulfillmentThreads exposing
    ( Model
    , Msg(..)
    , Thread
    , adminView
    , awaitingCount
    , empty
    , fetchAll
    , hasAdminOrders
    , hasSubscriptions
    , openAdminCmd
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

{-| The Subscriptions and Fulfillment sides of `Components.Pages.MessagesPage` (and so of
`Shared.MessagingPanel`, which embeds it). Self-contained on purpose (`MessagesPage` is already huge):
its own fetches, unread math and views. Like `MessagesPage` it can't import `Shared` (the panel embeds
it).

**Subscriptions** (`view`): the signed-in user's own `MarketSubscription`s (`GetMarketSubscriptions`, the
caller's own). A `PURCHASE_TYPE_RELLM_HOSTING` one with `fulfillmentNotes` is a chat thread with the
host admin. *Unread* is the buyer's own marker, `RellmHostingSubscriptionDetails.notesLastRead`: a note
counts if somebody other than the buyer wrote it and it's newer than that marker (or the marker is
unset). Opening a thread with unread notes calls `MarkFulfillmentNotesRead` (`openCmd`).

**Fulfillment** (`adminView`, server admins only): every Rellm hosting order on the server
(`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_FULFILLMENT_ADMIN`), seen from the "setting up customers' sites"
side -- behaves like `/market/fulfillment` (`Components.Pages.MarketFulfillmentPage`): opening an
awaiting order moves it to In Progress, and an admin can add a note or "Add and Mark as Fulfilled",
through the same append-only `UpdateMarketSubscription` contract. Its badge counts orders still
awaiting a host admin (`awaitingCount`) -- there's no per-admin read marker to count "unread" against.

-}

import Dict exposing (Dict)
import Components.Market as Market
import Grpc
import Html exposing (Html, a, button, div, p, span, text, textarea)
import Html.Attributes exposing (class, disabled, href, placeholder, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Json.Decode as Decode
import Proto.Google.Protobuf
import Proto.Rellm exposing (FulfillmentNote, MarketSubscription, defaultFulfillmentNote, defaultMarkFulfillmentNotesReadRequest, defaultMarketSubscriptionPushRequest)
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

    -- Admin accounts' view of every Rellm hosting order (the Fulfillment tab) -- same `Feed` shape.
    , adminFeeds : Dict String Feed

    -- Per `Thread.key`: whether *this browser's* push subscription is opted in to that thread's
    -- notifications (`GetMarketSubscriptionPushStatus`); absent until checked.
    , pushOptIn : Dict String Bool
    , pushBusy : Dict String ()

    -- Admin note composer: draft text and in-flight saves, per `Thread.key`.
    , drafts : Dict String String
    , saving : Dict String ()
    }


type Msg
    = GotSubscriptions String (Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ))
    | GotAdminSubscriptions String (Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ))
    | GotMarkedRead (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | GotPushStatus String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Bool ))
    | PushToggleClicked Thread Bool
    | GotPushToggled String Bool (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
    | DraftChanged String String
    | SaveNoteClicked Thread FulfillmentStatus
    | GotNoteSaved String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))


empty : Model
empty =
    { feeds = Dict.empty
    , adminFeeds = Dict.empty
    , pushOptIn = Dict.empty
    , pushBusy = Dict.empty
    , drafts = Dict.empty
    , saving = Dict.empty
    }


{-| A subscription plus where it lives. `key` is unique across servers (ids are per-server).
-}
type alias Thread =
    { key : String
    , host : String
    , accountId : String
    , subscription : MarketSubscription

    -- On the admin (Fulfillment) tab rather than the user's own Subscriptions tab.
    , admin : Bool
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


loadedSubscriptions : Dict String Feed -> List ( Feed, MarketSubscription )
loadedSubscriptions feeds =
    feeds
        |> Dict.values
        |> List.concatMap
            (\feed ->
                case feed.status of
                    Loaded subscriptions ->
                        List.map (\s -> ( feed, s )) subscriptions

                    _ ->
                        []
            )


createdAtMillis : MarketSubscription -> Int
createdAtMillis subscription =
    subscription.createdAt |> Maybe.map millis |> Maybe.withDefault 0


{-| Every loaded subscription of the user's own (any type), oldest first -- the Subscriptions tab's rows.
-}
userThreads : Model -> List Thread
userThreads model =
    loadedSubscriptions model.feeds
        |> List.map (\( feed, s ) -> { key = threadKey feed.host s.id, host = feed.host, accountId = feed.accountId, subscription = s, admin = False })
        |> List.sortBy (.subscription >> createdAtMillis)


{-| Every Rellm hosting order on the server (admin accounts only), oldest first -- the Fulfillment
tab's rows, with an `admin/` key prefix so an admin who is also a buyer doesn't get one key for two rows.
-}
adminThreads : Model -> List Thread
adminThreads model =
    loadedSubscriptions model.adminFeeds
        |> List.filter (\( _, s ) -> s.type_ == PURCHASETYPERELLMHOSTING)
        |> List.map (\( feed, s ) -> { key = "admin/" ++ threadKey feed.host s.id, host = feed.host, accountId = feed.accountId, subscription = s, admin = True })
        |> List.sortBy (.subscription >> createdAtMillis)


{-| Whether the Subscriptions tab should exist: the user has at least one subscription.
-}
hasSubscriptions : Model -> Bool
hasSubscriptions model =
    not (List.isEmpty (userThreads model))


{-| Whether the Fulfillment tab should exist: some signed-in account is a server admin.
-}
hasAdminOrders : Model -> Bool
hasAdminOrders model =
    not (Dict.isEmpty model.adminFeeds)


{-| Unread notes across the user's own subscriptions -- the Subscriptions tab's badge.
-}
totalUnread : Model -> Int
totalUnread model =
    userThreads model |> List.map (.subscription >> unreadCount) |> List.sum


fulfillmentStatusOf : MarketSubscription -> FulfillmentStatus
fulfillmentStatusOf subscription =
    case subscription.details of
        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            details.fulfillmentStatus

        _ ->
            FULFILLMENTSTATUSAWAITINGHOSTADMIN


{-| Orders still awaiting a host admin -- the Fulfillment tab's badge.
-}
awaitingCount : Model -> Int
awaitingCount model =
    adminThreads model
        |> List.filter (\t -> fulfillmentStatusOf t.subscription == FULFILLMENTSTATUSAWAITINGHOSTADMIN)
        |> List.length



-- FETCH


{-| Refetches the caller's own subscriptions from every signed-in account's (connected) server, plus --
for admin accounts -- every Rellm hosting order (the Fulfillment tab). Cheap (one small RPC per account
per kind), so callers just call it on every poll.
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

        adminEntries : List ( RellmAccounts.RellmAccount, String )
        adminEntries =
            List.filter (\( account, _ ) -> RellmAccounts.isAdmin account) entries

        syncFeeds : List ( RellmAccounts.RellmAccount, String ) -> Dict String Feed -> Dict String Feed
        syncFeeds wanted feeds =
            List.foldl
                (\( account, id ) acc ->
                    if Dict.member id acc then
                        acc

                    else
                        Dict.insert id { host = account.server, accountId = id, status = Loading } acc
                )
                feeds
                wanted
                |> Dict.filter (\id _ -> List.member id (List.map Tuple.second wanted))

        fetchCmd : GetMarketSubscriptionsRequestType -> (String -> Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ) -> Msg) -> ( RellmAccounts.RellmAccount, String ) -> Cmd Msg
        fetchCmd requestType toMsg ( account, id ) =
            AccountsPanel.performWithAccountServer
                accountsPanelModel
                ( Just account.userId, account.server )
                (\server token ->
                    Grpc.new Rellm.getMarketSubscriptions { requestType = requestType }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                )
                |> Task.map (\( m, response ) -> ( m, response.marketSubscriptions ))
                |> Task.attempt (toMsg id)
    in
    ( { model | feeds = syncFeeds entries model.feeds, adminFeeds = syncFeeds adminEntries model.adminFeeds }
    , Cmd.batch
        (List.map (fetchCmd GETMARKETSUBSCRIPTIONSREQUESTFORPURCHASE GotSubscriptions) entries
            ++ List.map (fetchCmd GETMARKETSUBSCRIPTIONSREQUESTFORFULFILLMENTADMIN GotAdminSubscriptions) adminEntries
        )
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
                , title = threadTitle { key = "", host = host, accountId = "", subscription = s, admin = False }
                , unread = unreadCount s
                , url = threadUrl mainFrontendHost host s.id Nothing
                }
            )


threadByKey : Model -> String -> Maybe Thread
threadByKey model key =
    (userThreads model ++ adminThreads model) |> List.filter (\t -> t.key == key) |> List.head


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


{-| What opening an order on the Fulfillment tab does, same as expanding its row on
`/market/fulfillment`: an order still awaiting a host admin moves to In Progress (a bare status-change
note, no text needed -- see `FulfillmentNote.note`'s proto doc).
-}
openAdminCmd : AccountsPanel.Model -> Model -> Thread -> Cmd Msg
openAdminCmd accountsPanelModel model thread =
    Cmd.batch
        [ if fulfillmentStatusOf thread.subscription == FULFILLMENTSTATUSAWAITINGHOSTADMIN then
            appendNoteCmd accountsPanelModel thread "" FULFILLMENTSTATUSINPROGRESS

          else
            Cmd.none
        , if Dict.member thread.key model.pushOptIn then
            Cmd.none

          else
            pushStatusCmd accountsPanelModel thread
        ]


withDetails : MarketSubscription -> Proto.Rellm.RellmHostingSubscriptionDetails -> MarketSubscription
withDetails subscription details =
    { subscription | details = Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) }


{-| Appends one note (attributed to the acting admin account, with `newStatus`) to the order's notes and
sends the whole subscription through `UpdateMarketSubscription` -- its append-only contract wants the
last-fetched notes back verbatim plus the new one, exactly as `MarketFulfillmentPage` does.
-}
appendNoteCmd : AccountsPanel.Model -> Thread -> String -> FulfillmentStatus -> Cmd Msg
appendNoteCmd accountsPanelModel thread noteText newStatus =
    case ( accountUserId thread.accountId, thread.subscription.details ) of
        ( Just userId, Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ) ->
            let
                updatedDetails : Proto.Rellm.RellmHostingSubscriptionDetails
                updatedDetails =
                    { details
                        | fulfillmentNotes =
                            details.fulfillmentNotes
                                ++ [ { defaultFulfillmentNote | userId = userId, note = noteText, fulfillmentStatus = newStatus } ]
                    }
            in
            Market.updateMarketSubscription accountsPanelModel
                ( Just userId, thread.host )
                (withDetails thread.subscription updatedDetails)
                |> Task.attempt (GotNoteSaved thread.key)

        _ ->
            Cmd.none


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
                |> Maybe.andThen
                    (\thread ->
                        if thread.admin then
                            Nothing

                        else
                            Just (openCmd accountsPanelModel updated thread)
                    )
                |> Maybe.withDefault Cmd.none
            , maybeMsg
            )

        GotAdminSubscriptions id (Ok ( maybeMsg, subscriptions )) ->
            ( { model | adminFeeds = Dict.update id (Maybe.map (\f -> { f | status = Loaded subscriptions })) model.adminFeeds }
            , Cmd.none
            , maybeMsg
            )

        GotAdminSubscriptions id (Err _) ->
            ( { model | adminFeeds = Dict.update id (Maybe.map (\f -> { f | status = Failed })) model.adminFeeds }, Cmd.none, Nothing )

        DraftChanged key newText ->
            ( { model | drafts = Dict.insert key newText model.drafts }, Cmd.none, Nothing )

        SaveNoteClicked thread newStatus ->
            let
                draft : String
                draft =
                    Dict.get thread.key model.drafts |> Maybe.withDefault ""
            in
            -- A note with no text is only allowed alongside a real status change (see
            -- `FulfillmentNote.note`'s proto doc) -- anything else would just be rejected.
            if String.isEmpty (String.trim draft) && newStatus == fulfillmentStatusOf thread.subscription then
                ( model, Cmd.none, Nothing )

            else
                ( { model | saving = Dict.insert thread.key () model.saving }
                , appendNoteCmd accountsPanelModel thread draft newStatus
                , Nothing
                )

        GotNoteSaved key (Ok ( maybeMsg, updatedSubscription )) ->
            ( { model
                | adminFeeds = Dict.map (\_ feed -> replaceSubscription updatedSubscription feed) model.adminFeeds
                , saving = Dict.remove key model.saving
                , drafts = Dict.remove key model.drafts
              }
            , Cmd.none
            , maybeMsg
            )

        GotNoteSaved key (Err _) ->
            ( { model | saving = Dict.remove key model.saving }, Cmd.none, Nothing )

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


type alias ViewConfig msg =
    { time : SharedTime.Model
    , accountsPanelModel : AccountsPanel.Model
    , model : Model
    , selected : Maybe String

    -- How a row asks to open: the page selects in place; the embedded panel passes `Nothing` and rows
    -- become plain links to the real page instead.
    , onSelect : Maybe (String -> msg)
    , toMsg : Msg -> msg
    }


{-| The Subscriptions tab's body: the user's own subscriptions. See `threadView`.
-}
view : ViewConfig msg -> Html msg
view config =
    case userThreads config.model of
        [] ->
            p [ class "posts-empty" ] [ text "No subscriptions." ]

        all ->
            div [ class "fulfillment-thread-list" ] (List.map (threadView config) all)


{-| The Fulfillment tab's body (server admins): every Rellm hosting order. See `threadView`.
-}
adminView : ViewConfig msg -> Html msg
adminView config =
    case adminThreads config.model of
        [] ->
            p [ class "posts-empty" ] [ text "No Rellm hosting orders yet." ]

        all ->
            div [ class "fulfillment-thread-list" ] (List.map (threadView config) all)


{-| One row. A user's own Rellm hosting subscription with notes (or any admin-side order) opens into a
chat; any other subscription is just a title and state line.
-}
threadView : ViewConfig msg -> Thread -> Html msg
threadView config thread =
    let
        subscription : MarketSubscription
        subscription =
            thread.subscription

        notes : List FulfillmentNote
        notes =
            notesOf subscription

        isChat : Bool
        isChat =
            thread.admin || (subscription.type_ == PURCHASETYPERELLMHOSTING && not (List.isEmpty notes))

        unread : Int
        unread =
            if thread.admin then
                0

            else
                unreadCount subscription

        isSelected : Bool
        isSelected =
            isChat && config.selected == Just thread.key

        url : String
        url =
            if thread.admin then
                "/market/fulfillment"

            else
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

        headerContent : List (Html msg)
        headerContent =
            [ span [ class "fulfillment-thread-title" ] [ text (threadTitle thread) ]
            , if thread.admin then
                span [ class "fulfillment-thread-state" ] [ text (statusLabel (fulfillmentStatusOf subscription)) ]

              else
                stateBadge subscription.state
            , if unread > 0 then
                span [ class "unread-count-badge", Html.Attributes.title "Unread notes" ] [ text (String.fromInt unread) ]

              else
                text ""
            ]
    in
    div
        [ classes [ "fulfillment-thread", if isSelected then "fulfillment-thread-selected" else "" ]
        , Html.Attributes.id ("subscription-thread-" ++ subscription.id)
        ]
        [ if isChat then
            a headerAttrs headerContent

          else
            div [ class "fulfillment-thread-header" ] (headerContent ++ [ timeLine config subscription ])
        , if isSelected then
            div [ class "fulfillment-thread-body" ]
                ((if List.isEmpty notes then
                    [ p [ class "market-form-hint" ] [ text "No notes yet." ] ]

                  else
                    List.indexedMap (noteView config.time thread) notes
                 )
                    ++ (if thread.admin then
                            [ composerView config thread
                            , a [ class "fulfillment-open-order-link", href "/market/fulfillment" ] [ text "Open in Fulfillment page" ]
                            ]

                        else
                            []
                       )
                    ++ [ pushToggleView config thread ]
                )

          else
            case List.reverse notes |> List.head of
                Just last ->
                    p [ class "fulfillment-thread-preview" ] [ text (notePreview last) ]

                Nothing ->
                    text ""
        ]


{-| "Renews <date>"-style line for a plain (non-chat) subscription row.
-}
timeLine : ViewConfig msg -> MarketSubscription -> Html msg
timeLine config subscription =
    case subscription.renewsAt of
        Just renewsAt ->
            span [ class "fulfillment-thread-state" ]
                [ text
                    ((if subscription.state == SUBSCRIPTIONACTIVE then
                        "Renews "

                      else
                        "Service until "
                     )
                        ++ SharedTime.formatDate config.time.browserTimeZone.zone (Conversions.timestampToPosix renewsAt)
                    )
                ]

        Nothing ->
            text ""


threadTitle : Thread -> String
threadTitle thread =
    let
        subscription : MarketSubscription
        subscription =
            thread.subscription

        domain : String
        domain =
            case subscription.details of
                Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
                    details.domain

                _ ->
                    ""
    in
    Market.purchaseTypeLabel subscription.type_
        ++ (if String.isEmpty domain then
                ""

            else
                " · " ++ domain
           )
        ++ (if thread.admin then
                subscription.buyer |> Maybe.andThen .username |> Maybe.map (\name -> " · " ++ name) |> Maybe.withDefault ""

            else
                ""
           )


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


{-| Who wrote a note, from the viewer's side: on the user's own Subscriptions tab the buyer is "You" and
anyone else is the "Host admin"; on the admin Fulfillment tab the acting admin is "You", the buyer is the
"Customer" and any other admin is "Admin".
-}
noteAuthorLabel : Thread -> FulfillmentNote -> String
noteAuthorLabel thread note =
    if thread.admin then
        if Just note.userId == accountUserId thread.accountId then
            "You"

        else if note.userId == buyerId thread.subscription then
            "Customer"

        else
            "Admin"

    else if note.userId == buyerId thread.subscription then
        "You"

    else
        "Host admin"


noteView : SharedTime.Model -> Thread -> Int -> FulfillmentNote -> Html msg
noteView time thread index note =
    let
        subscription : MarketSubscription
        subscription =
            thread.subscription

        mine : Bool
        mine =
            noteAuthorLabel thread note == "You"
    in
    div
        [ classes
            [ "fulfillment-note"
            , if mine then
                "fulfillment-note-mine"

              else
                ""
            , if not thread.admin && isUnreadNote subscription note then
                "fulfillment-note-unread"

              else
                ""
            ]
        , Html.Attributes.id ("subscription-message-" ++ String.fromInt index)
        ]
        [ div [ class "fulfillment-note-meta" ]
            [ span [ class "fulfillment-note-author" ] [ text (noteAuthorLabel thread note) ]
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


{-| The admin note composer -- "Add Note" keeps the order's status, "Add and Mark as Fulfilled" sets it,
the same two buttons `/market/fulfillment` has.
-}
composerView : ViewConfig msg -> Thread -> Html msg
composerView config thread =
    let
        draft : String
        draft =
            Dict.get thread.key config.model.drafts |> Maybe.withDefault ""

        saving : Bool
        saving =
            Dict.member thread.key config.model.saving

        blank : Bool
        blank =
            String.isEmpty (String.trim draft)

        status : FulfillmentStatus
        status =
            fulfillmentStatusOf thread.subscription
    in
    div [ class "fulfillment-composer" ]
        [ textarea
            [ placeholder "Add a note…"
            , value draft
            , onInput (\newText -> config.toMsg (DraftChanged thread.key newText))
            ]
            []
        , div [ class "fulfillment-composer-actions" ]
            [ button
                [ Html.Attributes.type_ "button"
                , onClick (config.toMsg (SaveNoteClicked thread status))
                , disabled (saving || blank)
                ]
                [ text
                    (if saving then
                        "Saving…"

                     else
                        "Add Note"
                    )
                ]
            , button
                [ Html.Attributes.type_ "button"
                , onClick (config.toMsg (SaveNoteClicked thread FULFILLMENTSTATUSFULFILLED))
                , disabled (saving || (status == FULFILLMENTSTATUSFULFILLED && blank))
                ]
                [ text "Add and Mark as Fulfilled" ]
            ]
        ]


pushToggleView : ViewConfig msg -> Thread -> Html msg
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
