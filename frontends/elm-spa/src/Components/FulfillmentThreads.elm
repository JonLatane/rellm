module Components.FulfillmentThreads exposing
    ( Model
    , Msg(..)
    , Thread
    , ViewConfig
    , adminView
    , awaitingCount
    , detailView
    , empty
    , fetchAll
    , hasAdminOrders
    , hasSubscriptions
    , datesText
    , heading
    , openAdmin
    , openCmd
    , subscriptionLinks
    , threadByKey
    , threadKey
    , orderQuery
    , orderUrl
    , threadQuery
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
caller's own). Every one, of any type, state and whether or not it has notes yet, opens as a chat thread with the
host admin (a canceled or empty one is read-only in practice: only admins write). *Unread* is the buyer's own marker (`notesLastRead` on the details): a note
counts if somebody other than the buyer wrote it and it's newer than that marker (or the marker is
unset). Opening a thread with unread notes calls `MarkFulfillmentNotesRead` (`openCmd`).

**Fulfillment** (`adminView`, server admins only): every subscription of every type on the server
(`GET_MARKET_SUBSCRIPTIONS_REQUEST_FOR_ALL_ADMIN`), seen from the host admin's side -- behaves like
`/market/fulfillment` (`Components.Pages.MarketFulfillmentPage`) for *every* type: opening an
awaiting subscription moves it to In Progress, and an admin can add a note or "Add and Mark as Fulfilled",
through the same append-only `UpdateMarketSubscription` contract. Its badge counts subscriptions still
awaiting a host admin (`awaitingCount`) -- there's no per-admin read marker to count "unread" against.

-}

import Dict exposing (Dict)
import Components.Authors as Authors
import Components.Market as Market
import Grpc
import Html exposing (Html, a, button, div, p, span, text, textarea)
import Html.Attributes exposing (class, disabled, href, placeholder, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Json.Decode as Decode
import Proto.Google.Protobuf
import Proto.Rellm exposing (Author, FulfillmentNote, MarketSubscription, defaultFulfillmentNote, defaultMarkFulfillmentNotesReadRequest)
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
import UI.Classes exposing (classes, hostnameToCSSClass)


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

    -- Admin accounts' view of every subscription of every type (the Fulfillment tab) -- same `Feed` shape.
    , adminFeeds : Dict String Feed

    -- Admin note composer: draft text and in-flight saves, per `Thread.key`.
    , drafts : Dict String String
    , saving : Dict String ()
    }


type Msg
    = GotSubscriptions String (Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ))
    | GotAdminSubscriptions String (Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ))
    | GotMarkedRead String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | DraftChanged String String
    | SaveNoteClicked Thread FulfillmentStatus
    | GotNoteSaved String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | GotAutoProgressSaved String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))


empty : Model
empty =
    { feeds = Dict.empty
    , adminFeeds = Dict.empty
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
threadUrl : String -> String -> String -> String -> Maybe Int -> String
threadUrl basePath mainFrontendHost host subscriptionId noteIndex =
    basePath
        ++ "/messages?"
        ++ threadQuery mainFrontendHost host subscriptionId
        ++ (case noteIndex of
                Just index ->
                    "#subscription-message-" ++ String.fromInt index

                Nothing ->
                    ""
           )



-- DATA


{-| `fulfillment_order=<id>[@host]` -- the query param naming one admin Fulfillment order (no leading `?`),
the Fulfillment tab's counterpart of `threadQuery`. Carries the server, so an order from a remote
server opens on *that* server's thread rather than on whichever server the page is browsing.
-}
orderQuery : String -> String -> String -> String
orderQuery mainFrontendHost host subscriptionId =
    "fulfillment_order="
        ++ (if host == mainFrontendHost then
                subscriptionId

            else
                subscriptionId ++ "@" ++ host
           )


{-| Link to one order on the Messages page's Fulfillment tab.
-}
orderUrl : String -> String -> String -> String -> String
orderUrl basePath mainFrontendHost host subscriptionId =
    basePath ++ "/messages?" ++ orderQuery mainFrontendHost host subscriptionId



{-| `subscription_messages=<id>[@host]` -- the query param naming one thread (no leading `?`).
-}
threadQuery : String -> String -> String -> String
threadQuery mainFrontendHost host subscriptionId =
    "subscription_messages="
        ++ (if host == mainFrontendHost then
                subscriptionId

            else
                subscriptionId ++ "@" ++ host
           )



{-| Every `PurchaseType`'s subscription details carry the fulfillment chat (`fulfillmentStatus`/`fulfillmentNotes`/
`notesLastRead`, same fields on all four), so these three read whichever variant the subscription has.
-}
notesOf : MarketSubscription -> List FulfillmentNote
notesOf subscription =
    case subscription.details of
        Just (SubscriptionDetails.MediaStorageSubscriptionDetails details) ->
            details.fulfillmentNotes

        Just (SubscriptionDetails.AiGrantSubscriptionDetails details) ->
            details.fulfillmentNotes

        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            details.fulfillmentNotes

        Just (SubscriptionDetails.PermissionsAccessSubscriptionDetails details) ->
            details.fulfillmentNotes

        Nothing ->
            []


notesLastRead : MarketSubscription -> Maybe Proto.Google.Protobuf.Timestamp
notesLastRead subscription =
    case subscription.details of
        Just (SubscriptionDetails.MediaStorageSubscriptionDetails details) ->
            details.notesLastRead

        Just (SubscriptionDetails.AiGrantSubscriptionDetails details) ->
            details.notesLastRead

        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            details.notesLastRead

        Just (SubscriptionDetails.PermissionsAccessSubscriptionDetails details) ->
            details.notesLastRead

        Nothing ->
            Nothing


{-| The same subscription with `notes`/`status` as its chat -- what `UpdateMarketSubscription` is sent.
-}
withNotes : List FulfillmentNote -> FulfillmentStatus -> MarketSubscription -> MarketSubscription
withNotes notes status subscription =
    { subscription
        | details =
            case subscription.details of
                Just (SubscriptionDetails.MediaStorageSubscriptionDetails details) ->
                    Just (SubscriptionDetails.MediaStorageSubscriptionDetails { details | fulfillmentNotes = notes, fulfillmentStatus = status })

                Just (SubscriptionDetails.AiGrantSubscriptionDetails details) ->
                    Just (SubscriptionDetails.AiGrantSubscriptionDetails { details | fulfillmentNotes = notes, fulfillmentStatus = status })

                Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
                    Just (SubscriptionDetails.RellmHostingSubscriptionDetails { details | fulfillmentNotes = notes, fulfillmentStatus = status })

                Just (SubscriptionDetails.PermissionsAccessSubscriptionDetails details) ->
                    Just (SubscriptionDetails.PermissionsAccessSubscriptionDetails { details | fulfillmentNotes = notes, fulfillmentStatus = status })

                Nothing ->
                    Nothing
    }


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


{-| Every subscription on the server, of every type (admin accounts only), oldest first -- the Fulfillment
tab's rows, with an `admin/` key prefix so an admin who is also a buyer doesn't get one key for two rows.
-}
adminThreads : Model -> List Thread
adminThreads model =
    loadedSubscriptions model.adminFeeds
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
        Just (SubscriptionDetails.MediaStorageSubscriptionDetails details) ->
            details.fulfillmentStatus

        Just (SubscriptionDetails.AiGrantSubscriptionDetails details) ->
            details.fulfillmentStatus

        Just (SubscriptionDetails.RellmHostingSubscriptionDetails details) ->
            details.fulfillmentStatus

        Just (SubscriptionDetails.PermissionsAccessSubscriptionDetails details) ->
            details.fulfillmentStatus

        Nothing ->
            FULFILLMENTSTATUSAWAITINGHOSTADMIN


{-| Only Rellm hosting is set up by hand, so only it has a status an admin moves (Awaiting Host Admin -> In
Progress -> Fulfilled). Every other type is fulfilled automatically by the server the moment it's bought: it
is always `Fulfilled`, and the backend rejects a note that tries to change that. Its chat is text only.
-}
isHosting : MarketSubscription -> Bool
isHosting subscription =
    subscription.type_ == PURCHASETYPERELLMHOSTING


{-| Subscriptions (of any type) still awaiting a host admin -- the Fulfillment tab's badge. Only hosting ever
is (see `isHosting`), so in practice this is the hosting work queue.
-}
awaitingCount : Model -> Int
awaitingCount model =
    adminThreads model
        |> List.filter (\t -> fulfillmentStatusOf t.subscription == FULFILLMENTSTATUSAWAITINGHOSTADMIN)
        |> List.length



-- FETCH


{-| Refetches the caller's own subscriptions from every signed-in account's (connected) server, plus --
for admin accounts -- every subscription of every type (the Fulfillment tab). Cheap (one small RPC per account
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

        listingTask : ( RellmAccounts.RellmAccount, String ) -> GetMarketSubscriptionsRequestType -> Task Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription )
        listingTask ( account, _ ) requestType =
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

        fetchCmd : GetMarketSubscriptionsRequestType -> (String -> Result Grpc.Error ( Maybe AccountsPanel.Msg, List MarketSubscription ) -> Msg) -> ( RellmAccounts.RellmAccount, String ) -> Cmd Msg
        fetchCmd requestType toMsg ( account, id ) =
            listingTask ( account, id ) requestType
                |> Task.attempt (toMsg id)

        -- A server that hasn't been upgraded yet rejects the all-types listing (`invalid_request_type`): fall
        -- back to the Rellm-hosting-only one it does have, so its existing hosting orders still show (without chats
        -- on the other types, which it can't hold anyway).
        adminFetchCmd : ( RellmAccounts.RellmAccount, String ) -> Cmd Msg
        adminFetchCmd ( account, id ) =
            listingTask ( account, id ) GETMARKETSUBSCRIPTIONSREQUESTFORALLADMIN
                |> Task.onError (\_ -> listingTask ( account, id ) GETMARKETSUBSCRIPTIONSREQUESTFORFULFILLMENTADMIN)
                |> Task.attempt (GotAdminSubscriptions id)
    in
    ( { model | feeds = syncFeeds entries model.feeds, adminFeeds = syncFeeds adminEntries model.adminFeeds }
    , Cmd.batch
        (List.map (fetchCmd GETMARKETSUBSCRIPTIONSREQUESTFORPURCHASE GotSubscriptions) entries
            ++ List.map adminFetchCmd adminEntries
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
            |> Task.attempt (GotMarkedRead thread.key)


{-| One row per subscription (of any type) that has notes, among `subscriptions` (already-fetched,
e.g. `RellmAccount.marketSubscriptions`/`User.marketSubscriptions`, all on `host`): a title, its unread
count and a link to its thread on the Messages page. What the Accounts panel and the profile page's
Subscriptions lists show.
-}
subscriptionLinks : String -> String -> String -> List MarketSubscription -> List { subscription : MarketSubscription, title : String, unread : Int, url : String }
subscriptionLinks basePath mainFrontendHost host subscriptions =
    subscriptions
        |> List.filter (\s -> not (List.isEmpty (notesOf s)))
        |> List.map
            (\s ->
                { subscription = s
                , title = threadTitle { key = "", host = host, accountId = "", subscription = s, admin = False }
                , unread = unreadCount s
                , url = threadUrl basePath mainFrontendHost host s.id Nothing
                }
            )


threadByKey : Model -> String -> Maybe Thread
threadByKey model key =
    (userThreads model ++ adminThreads model) |> List.filter (\t -> t.key == key) |> List.head


{-| What opening a thread does: mark its unread notes read.
-}
openCmd : AccountsPanel.Model -> Thread -> Cmd Msg
openCmd =
    markReadCmd


{-| What opening an order on the Fulfillment tab does, same as expanding its row on
`/market/fulfillment`: an order still awaiting a host admin moves to In Progress (a bare status-change
note, no text needed -- see `FulfillmentNote.note`'s proto doc).
-}
openAdmin : AccountsPanel.Model -> Model -> Thread -> ( Model, Cmd Msg )
openAdmin accountsPanelModel model thread =
    let
        autoProgress : Bool
        autoProgress =
            isHosting thread.subscription && fulfillmentStatusOf thread.subscription == FULFILLMENTSTATUSAWAITINGHOSTADMIN
    in
    ( -- `saving` blocks the composer until the updated notes arrive: a manual save in the meantime would
      -- send the *old* note history back and be rejected by the append-only check.
      if autoProgress then
        { model | saving = Dict.insert thread.key () model.saving }

      else
        model
    , if autoProgress then
        appendNoteCmd accountsPanelModel thread "" FULFILLMENTSTATUSINPROGRESS GotAutoProgressSaved

      else
        Cmd.none
    )


{-| Appends one note (attributed to the acting admin account, with `newStatus`) to the subscription's chat and
sends the whole subscription through `UpdateMarketSubscription` -- its append-only contract wants the
last-fetched notes back verbatim plus the new one, exactly as `MarketFulfillmentPage` does.
-}
appendNoteCmd : AccountsPanel.Model -> Thread -> String -> FulfillmentStatus -> (String -> Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ) -> Msg) -> Cmd Msg
appendNoteCmd accountsPanelModel thread noteText newStatus toMsg =
    case accountUserId thread.accountId of
        Just userId ->
            let
                notes : List FulfillmentNote
                notes =
                    notesOf thread.subscription ++ [ { defaultFulfillmentNote | userId = userId, note = noteText, fulfillmentStatus = newStatus } ]
            in
            Market.updateMarketSubscription accountsPanelModel
                ( Just userId, thread.host )
                (withNotes notes newStatus thread.subscription)
                |> Task.attempt (toMsg thread.key)

        Nothing ->
            Cmd.none


-- UPDATE


{-| `selected` is the currently open thread's `threadKey`, if any: once its notes load/refresh, a
still-unread open thread is marked read straight away (so a deep link, or a note arriving while it's
open, doesn't leave a stale badge).
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
                            Just (openCmd accountsPanelModel thread)
                    )
                |> Maybe.withDefault Cmd.none
            , maybeMsg
            )

        GotAdminSubscriptions id (Ok ( maybeMsg, subscriptions )) ->
            let
                updated : Model
                updated =
                    { model | adminFeeds = Dict.update id (Maybe.map (\f -> { f | status = Loaded subscriptions })) model.adminFeeds }

                -- An order that is selected (by a deep link, or synced from the embedded panel) is opened
                -- as soon as it loads -- once: an order moves out of awaiting on its first open, and
                -- `saving` holds off a second one while that write is in flight.
                openThread : Maybe Thread
                openThread =
                    selected
                        |> Maybe.andThen (threadByKey updated)
                        |> Maybe.andThen
                            (\thread ->
                                if thread.admin && not (Dict.member thread.key updated.saving) then
                                    Just thread

                                else
                                    Nothing
                            )
            in
            case openThread of
                Just thread ->
                    let
                        ( opened, adminOpenCmd ) =
                            openAdmin accountsPanelModel updated thread
                    in
                    ( opened, adminOpenCmd, maybeMsg )

                Nothing ->
                    ( updated, Cmd.none, maybeMsg )

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
            if Dict.member thread.key model.saving || (String.isEmpty (String.trim draft) && newStatus == fulfillmentStatusOf thread.subscription) then
                ( model, Cmd.none, Nothing )

            else
                ( { model | saving = Dict.insert thread.key () model.saving }
                , appendNoteCmd accountsPanelModel thread draft newStatus GotNoteSaved
                , Nothing
                )

        GotNoteSaved key (Ok ( maybeMsg, updatedSubscription )) ->
            ( { model
                | adminFeeds = Dict.map (\_ feed -> replaceSubscription "admin/" key updatedSubscription feed) model.adminFeeds
                , saving = Dict.remove key model.saving
                , drafts = Dict.remove key model.drafts
              }
            , Cmd.none
            , maybeMsg
            )

        -- The automatic In Progress transition from opening an order: swap in the updated order but,
        -- unlike a manual save, leave whatever the admin has already typed in the draft.
        GotAutoProgressSaved key (Ok ( maybeMsg, updatedSubscription )) ->
            ( { model
                | adminFeeds = Dict.map (\_ feed -> replaceSubscription "admin/" key updatedSubscription feed) model.adminFeeds
                , saving = Dict.remove key model.saving
              }
            , Cmd.none
            , maybeMsg
            )

        GotAutoProgressSaved key (Err _) ->
            ( { model | saving = Dict.remove key model.saving }, Cmd.none, Nothing )

        GotNoteSaved key (Err _) ->
            ( { model | saving = Dict.remove key model.saving }, Cmd.none, Nothing )

        GotSubscriptions id (Err _) ->
            ( { model | feeds = Dict.update id (Maybe.map (\f -> { f | status = Failed })) model.feeds }, Cmd.none, Nothing )

        GotMarkedRead key (Ok ( maybeMsg, updatedSubscription )) ->
            ( { model | feeds = Dict.map (\_ feed -> replaceSubscription "" key updatedSubscription feed) model.feeds }
            , Cmd.none
            , maybeMsg
            )

        GotMarkedRead _ (Err _) ->
            ( model, Cmd.none, Nothing )


{-| Swaps `updated` in for the subscription of the *one* thread `key` names (`keyPrefix` is the key
namespace the feed belongs to -- `"admin/"` for the Fulfillment tab). Subscription ids are only unique
per server, so matching on the bare id would let a reply from server A overwrite a same-id thread on B.
-}
replaceSubscription : String -> String -> MarketSubscription -> Feed -> Feed
replaceSubscription keyPrefix key updated feed =
    case feed.status of
        Loaded subscriptions ->
            { feed
                | status =
                    Loaded
                        (List.map
                            (\s ->
                                if keyPrefix ++ threadKey feed.host s.id == key then
                                    updated

                                else
                                    s
                            )
                            subscriptions
                        )
            }

        _ ->
            feed



-- VIEW


type alias ViewConfig msg =
    { time : SharedTime.Model

    -- The app's mount prefix (`""` or `/elm`), for links.
    , basePath : String
    , accountsPanelModel : AccountsPanel.Model
    , model : Model
    , selected : Maybe String

    -- How a row asks to open: the page selects in place; the embedded panel passes `Nothing` and rows
    -- become plain links to the real page instead.
    , onSelect : Maybe (String -> msg)

    -- Embedded panel only: told which thread's link was clicked (the click still navigates -- this just lets
    -- a page already on `/messages` follow along, since a same-path URL change doesn't re-init it).
    , onLinkClick : Maybe (String -> msg)
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


{-| The Fulfillment tab's body (server admins): every subscription. See `threadView`.
-}
adminView : ViewConfig msg -> Html msg
adminView config =
    case adminThreads config.model of
        [] ->
            p [ class "posts-empty" ] [ text "No subscriptions yet." ]

        all ->
            div [ class "fulfillment-thread-list" ] (List.map (threadView config) all)


{-| One row of the list pane: (Fulfillment tab) who bought it, then title, unread count, the state badge, the
fulfillment-status badge of a Rellm hosting order, its dates and the last note's preview. Every row -- whatever
its type, state or notes -- selects into the detail pane (`detailView`) when clicked.
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

        unread : Int
        unread =
            if thread.admin then
                0

            else
                unreadCount subscription

        isSelected : Bool
        isSelected =
            config.selected == Just thread.key

        url : String
        url =
            if thread.admin then
                orderUrl config.basePath config.accountsPanelModel.mainFrontendHost thread.host subscription.id

            else
                threadUrl config.basePath config.accountsPanelModel.mainFrontendHost thread.host subscription.id Nothing

        headerAttrs : List (Html.Attribute msg)
        headerAttrs =
            case config.onSelect of
                Just select ->
                    [ class "fulfillment-thread-header"
                    , href url
                    , preventDefaultOn "click" (Decode.succeed ( select thread.key, True ))
                    ]

                Nothing ->
                    class "fulfillment-thread-header"
                        :: href url
                        :: (case config.onLinkClick of
                                Just linkClicked ->
                                    [ onClick (linkClicked thread.key) ]

                                Nothing ->
                                    []
                           )
    in
    div
        [ classes [ "fulfillment-thread", if isSelected then "fulfillment-thread-selected" else "" ]
        , Html.Attributes.id ("subscription-thread-" ++ subscription.id)
        ]
        [ -- The row is itself one link, so the buyer here is just the avatar and name (the clickable
          -- profile link is in the opened chat's header, `detailHeaderView`).
          a headerAttrs
            [ if thread.admin then
                buyerChip config thread

              else
                text ""
            , div [ class "fulfillment-thread-main" ]
                [ span [ class "fulfillment-thread-title" ] [ text (threadTitle thread) ]
                , if unread > 0 then
                    span [ class "unread-count-badge", Html.Attributes.title "Unread notes" ] [ text (String.fromInt unread) ]

                  else
                    text ""
                ]
            , metaView config.time.browserTimeZone.zone subscription
            ]
        , case List.reverse notes |> List.head of
            Just last ->
                p [ class "fulfillment-thread-preview" ] [ text (notePreview last) ]

            Nothing ->
                text ""
        ]


{-| The buyer's avatar and username, as on a Rellm post's author line, but not a link (for use inside another
link).
-}
buyerChip : ViewConfig msg -> Thread -> Html msg
buyerChip config thread =
    let
        author : Maybe Author
        author =
            thread.subscription.buyer
    in
    span [ class "post-author-link fulfillment-buyer" ]
        [ Authors.avatar (Authors.name author) (Authors.avatarUrl (buyerServer config thread) (buyerAccount config thread) author)
        , text (Authors.name author)
        ]


buyerServer : ViewConfig msg -> Thread -> Maybe RellmServers.RellmServer
buyerServer config thread =
    RellmServers.rellmServerForHost config.accountsPanelModel.servers thread.host


buyerAccount : ViewConfig msg -> Thread -> Maybe RellmAccounts.RellmAccount
buyerAccount config thread =
    RellmAccounts.enabledRellmAccountForServer config.accountsPanelModel.accounts thread.host


{-| The state badge (Active / Canceled, still active / Canceled), the fulfillment-status badge of a Rellm hosting
subscription, and the subscription's dates: one line, wrapping on narrow screens.
-}
metaView : Time.Zone -> MarketSubscription -> Html msg
metaView zone subscription =
    div [ class "fulfillment-thread-meta" ]
        [ stateBadge (Market.effectiveState subscription)
        , if isHosting subscription then
            fulfillmentBadge (fulfillmentStatusOf subscription)

          else
            text ""
        , span [ class "fulfillment-thread-dates" ] [ text (datesText zone subscription) ]
        ]


{-| "Started 2026-11-03 · Renews 2027-11-03" -- when the subscription began and what happens next: the next
renewal while it's active (nothing if it never renews), the date service stops once it's canceled but still paid
up, or the date it ended.
-}
datesText : Time.Zone -> MarketSubscription -> String
datesText zone subscription =
    let
        date : Proto.Google.Protobuf.Timestamp -> String
        date timestamp =
            SharedTime.formatDate zone (Conversions.timestampToPosix timestamp)

        latest : List (Maybe Proto.Google.Protobuf.Timestamp) -> Maybe Proto.Google.Protobuf.Timestamp
        latest times =
            times |> List.filterMap identity |> List.sortBy millis |> List.reverse |> List.head

        ending : Maybe String
        ending =
            case Market.effectiveState subscription of
                SUBSCRIPTIONACTIVE ->
                    case subscription.renewsAt of
                        Just renewsAt ->
                            Just ("Renews " ++ date renewsAt)

                        Nothing ->
                            Just "Doesn't renew"

                SUBSCRIPTIONACTIVEBUTCANCELED ->
                    latest [ subscription.canceledAt, subscription.renewsAt ] |> Maybe.map (\t -> "Ends " ++ date t)

                _ ->
                    (case subscription.serviceTerminatedAt of
                        Just terminated ->
                            Just terminated

                        Nothing ->
                            latest [ subscription.canceledAt, subscription.renewsAt ]
                    )
                        |> Maybe.map (\t -> "Ended " ++ date t)
    in
    [ subscription.createdAt |> Maybe.map (\t -> "Started " ++ date t), ending ]
        |> List.filterMap identity
        |> String.join " · "


{-| The detail pane's heading, in the row above the panes (with the pane toggle): what the thread is about. The
who/state/dates are in the header at the top of the pane itself (`detailHeaderView`).
-}
heading : Thread -> Html msg
heading thread =
    span [ class "fulfillment-detail-heading" ]
        [ span [ class "fulfillment-thread-title" ] [ text (threadTitle thread) ] ]


{-| The top of the detail pane, like a conversation's participants header: (Fulfillment tab) the buyer's avatar and
username linking to their profile, then the state and fulfillment-status badges and the dates.
-}
detailHeaderView : ViewConfig msg -> Thread -> Html msg
detailHeaderView config thread =
    div [ class "fulfillment-detail-header" ]
        [ if thread.admin then
            Authors.link
                config.basePath
                config.accountsPanelModel.mainFrontendHost
                thread.host
                (buyerServer config thread)
                (buyerAccount config thread)
                thread.subscription.buyer

          else
            text ""
        , metaView config.time.browserTimeZone.zone thread.subscription
        ]


{-| The detail pane of the selected thread: its header, its notes, and (admin side) the note composer.
-}
detailView : ViewConfig msg -> Thread -> Html msg
detailView config thread =
    let
        notes : List FulfillmentNote
        notes =
            notesOf thread.subscription
    in
    div [ class "fulfillment-thread-body" ]
        (detailHeaderView config thread
            :: p [ class "market-form-hint fulfillment-process-hint" ] [ text (processHint thread) ]
            :: (if List.isEmpty notes then
                    [ p [ class "market-form-hint" ] [ text "No notes yet." ] ]

                else
                    List.indexedMap (noteView config.time thread) notes
               )
            ++ (if thread.admin then
                    [ composerView config thread ]

                else
                    []
               )
        )


{-| One line at the top of a chat saying what happens with this kind of subscription, so it's clear to both
sides what the status means (or that there is none to wait for).
-}
processHint : Thread -> String
processHint thread =
    case ( isHosting thread.subscription, thread.admin ) of
        ( True, False ) ->
            "Rellm hosting is set up by hand by a host admin. Its status here moves from Awaiting Host Admin to In Progress when they start, and to Fulfilled when your site is ready -- you'll get a note each time."

        ( True, True ) ->
            "Rellm hosting is set up by hand. Opening an order that's awaiting a host admin marks it In Progress; \"Send and mark as Fulfilled\" finishes it. The buyer is notified of each note."

        ( False, False ) ->
            "This subscription takes effect automatically when it's bought or renewed -- there's nothing to wait for. This chat is just for talking with the host admin about it."

        ( False, True ) ->
            "This subscription is fulfilled automatically when it's bought or renewed, so it's never in the Fulfillment count and its status can't be changed. Notes here are just a conversation with the buyer."


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
    -- What was actually bought ("5 GB Media Storage", a permissions bundle's name, ...), not just its type.
    (subscription.marketProduct
        |> Maybe.map Market.productName
        |> Maybe.withDefault (Market.purchaseTypeLabel subscription.type_)
    )
        ++ (if String.isEmpty domain then
                ""

            else
                " · " ++ domain
           )


stateBadge : MarketSubscriptionState -> Html msg
stateBadge state =
    case state of
        SUBSCRIPTIONACTIVE ->
            span [ class "fulfillment-badge fulfillment-badge-active" ] [ text "Active" ]

        SUBSCRIPTIONACTIVEBUTCANCELED ->
            span [ class "fulfillment-badge fulfillment-badge-active-canceled" ] [ text "Active, canceled" ]

        _ ->
            span [ class "fulfillment-badge fulfillment-badge-canceled" ] [ text "Canceled" ]


{-| The fulfillment status of a Rellm hosting subscription -- a badge of its own beside the state badge.
-}
fulfillmentBadge : FulfillmentStatus -> Html msg
fulfillmentBadge status =
    span
        [ class
            ("fulfillment-badge "
                ++ (case status of
                        FULFILLMENTSTATUSFULFILLED ->
                            "fulfillment-badge-fulfilled"

                        FULFILLMENTSTATUSINPROGRESS ->
                            "fulfillment-badge-in-progress"

                        _ ->
                            "fulfillment-badge-awaiting"
                   )
            )
        ]
        [ text (statusLabel status) ]


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
            , if String.isEmpty note.note then
                "fulfillment-note-status-only"

              else
                ""
            ]
        , Html.Attributes.id ("subscription-message-" ++ String.fromInt index)
        ]
        [ div [ class "fulfillment-note-meta" ]
            [ span [ class "fulfillment-note-author" ] [ text (noteAuthorLabel thread note) ]
            , if isHosting subscription then
                span [ class "fulfillment-note-status" ] [ text (statusLabel note.fulfillmentStatus) ]

              else
                text ""
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


{-| The admin's message box, pinned to the bottom of the chat: send keeps the order's status; on a Rellm hosting order
"Send and mark as Fulfilled" also sets it (the same two actions `/market/fulfillment` has).
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
        [ div [ class "fulfillment-composer-row" ]
            [ textarea
                [ class "fulfillment-composer-input"
                , placeholder "Write a note…"
                , Html.Attributes.rows 1
                , value draft
                , onInput (\newText -> config.toMsg (DraftChanged thread.key newText))
                , onEnterToSend (config.toMsg (SaveNoteClicked thread status))
                ]
                []
            , button
                [ Html.Attributes.type_ "button"
                , classes [ "fulfillment-composer-send", hostnameToCSSClass thread.host, "background-color-primary" ]
                , Html.Attributes.title "Send (Enter)"
                , Html.Attributes.attribute "aria-label" "Send note"
                , onClick (config.toMsg (SaveNoteClicked thread status))
                , disabled (saving || blank)
                ]
                [ text
                    (if saving then
                        "…"

                     else
                        "↑"
                    )
                ]
            ]
        , if isHosting thread.subscription then
            button
                [ Html.Attributes.type_ "button"
                , class "fulfillment-composer-fulfill"
                , onClick (config.toMsg (SaveNoteClicked thread FULFILLMENTSTATUSFULFILLED))
                , disabled (saving || (status == FULFILLMENTSTATUSFULFILLED && blank))
                ]
                [ text "Send and mark as Fulfilled" ]

          else
            text ""
        ]


{-| Enter sends the note (Shift+Enter is a newline), like the message box of any chat app. Ignored while an IME
composition is in progress, so confirming a candidate doesn't send.
-}
onEnterToSend : msg -> Html.Attribute msg
onEnterToSend msg =
    preventDefaultOn "keydown"
        (Decode.map3 (\key shift composing -> ( key, shift, composing ))
            (Decode.field "key" Decode.string)
            (Decode.field "shiftKey" Decode.bool)
            (Decode.oneOf [ Decode.field "isComposing" Decode.bool, Decode.succeed False ])
            |> Decode.andThen
                (\( key, shift, composing ) ->
                    if key == "Enter" && not shift && not composing then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not a plain Enter"
                )
        )
