module FulfillmentThreadsTests exposing (suite)

{-| Tests for `Components.FulfillmentThreads`' pure parts: what counts as an *unread* fulfillment note
(someone other than the buyer wrote it, and it's newer than the buyer's `notesLastRead` marker), which
subscriptions form threads (only Rellm hosting ones that have notes -- what makes the Messages page's
Fulfillment tab appear), and the `?subscription_messages=` deep link.
-}

import Components.FulfillmentThreads as Fulfillment
import Expect
import Protobuf.Types.Int64 as Int64
import Proto.Google.Protobuf
import Proto.Rellm exposing (FulfillmentNote, MarketSubscription, defaultAuthor, defaultFulfillmentNote, defaultMarketSubscription, defaultMediaStorageSubscriptionDetails, defaultRellmHostingSubscriptionDetails)
import Proto.Rellm.MarketSubscription.Details as SubscriptionDetails
import Proto.Rellm.PurchaseType exposing (PurchaseType(..))
import Test exposing (Test, describe, test)


at : Int -> Maybe Proto.Google.Protobuf.Timestamp
at seconds =
    Just { seconds = Int64.fromInts 0 seconds, nanos = 0 }


note : String -> Int -> FulfillmentNote
note userId seconds =
    { defaultFulfillmentNote | userId = userId, note = "text", createdAt = at seconds }


hosting : Maybe Int -> List FulfillmentNote -> MarketSubscription
hosting readAt notes =
    { defaultMarketSubscription
        | id = "sub1"
        , type_ = PURCHASETYPERELLMHOSTING
        , buyer = Just { defaultAuthor | userId = "buyer" }
        , details =
            Just
                (SubscriptionDetails.RellmHostingSubscriptionDetails
                    { defaultRellmHostingSubscriptionDetails
                        | fulfillmentNotes = notes
                        , notesLastRead = readAt |> Maybe.andThen at
                    }
                )
    }


{-| Every purchase type has a chat, not just Rellm hosting.
-}
mediaStorage : Maybe Int -> List FulfillmentNote -> MarketSubscription
mediaStorage readAt notes =
    { defaultMarketSubscription
        | id = "media1"
        , type_ = PURCHASETYPEMEDIASTORAGE
        , buyer = Just { defaultAuthor | userId = "buyer" }
        , details =
            Just
                (SubscriptionDetails.MediaStorageSubscriptionDetails
                    { defaultMediaStorageSubscriptionDetails
                        | fulfillmentNotes = notes
                        , notesLastRead = readAt |> Maybe.andThen at
                    }
                )
    }


suite : Test
suite =
    describe "Components.FulfillmentThreads"
        [ describe "unreadCount"
            [ test "every admin note is unread before the buyer has ever read the thread" <|
                \_ ->
                    hosting Nothing [ note "admin" 10, note "admin" 20 ]
                        |> Fulfillment.unreadCount
                        |> Expect.equal 2
            , test "the buyer's own notes are never unread" <|
                \_ ->
                    hosting Nothing [ note "buyer" 10, note "admin" 20 ]
                        |> Fulfillment.unreadCount
                        |> Expect.equal 1
            , test "only notes newer than notesLastRead count" <|
                \_ ->
                    hosting (Just 15) [ note "admin" 10, note "admin" 20, note "admin" 30 ]
                        |> Fulfillment.unreadCount
                        |> Expect.equal 2
            , test "a note exactly at the marker is read" <|
                \_ ->
                    hosting (Just 20) [ note "admin" 20 ]
                        |> Fulfillment.unreadCount
                        |> Expect.equal 0
            , test "no notes means nothing unread" <|
                \_ ->
                    hosting Nothing []
                        |> Fulfillment.unreadCount
                        |> Expect.equal 0
            ]
        , describe "other purchase types"
            [ test "a media storage subscription's admin notes are unread until the buyer reads them" <|
                \_ ->
                    ( mediaStorage Nothing [ note "admin" 10, note "buyer" 12 ] |> Fulfillment.unreadCount
                    , mediaStorage (Just 11) [ note "admin" 10, note "admin" 20 ] |> Fulfillment.unreadCount
                    )
                        |> Expect.equal ( 1, 1 )
            , test "and it gets a thread link once it has notes, like Rellm hosting" <|
                \_ ->
                    Fulfillment.subscriptionLinks "" "main.example" "main.example" [ mediaStorage Nothing [ note "admin" 10 ], mediaStorage Nothing [] ]
                        |> List.map .unread
                        |> Expect.equal [ 1 ]
            ]
        , describe "subscriptionLinks"
            [ test "a subscription with no notes gets no thread link" <|
                \_ ->
                    Fulfillment.subscriptionLinks "" "main.example" "main.example" [ hosting Nothing [], { defaultMarketSubscription | id = "media", type_ = PURCHASETYPEMEDIASTORAGE } ]
                        |> List.length
                        |> Expect.equal 0
            , test "a hosting subscription with notes links to its thread, carrying its unread count" <|
                \_ ->
                    Fulfillment.subscriptionLinks "" "main.example" "main.example" [ hosting (Just 15) [ note "admin" 10, note "admin" 20 ] ]
                        |> List.map (\link -> ( link.url, link.unread ))
                        |> Expect.equal [ ( "/messages?subscription_messages=sub1", 1 ) ]
            ]
        , describe "threadUrl"
            [ test "an id on the main frontend host has no @host suffix" <|
                \_ ->
                    Fulfillment.threadUrl "" "main.example" "main.example" "sub1" Nothing
                        |> Expect.equal "/messages?subscription_messages=sub1"
            , test "an id on any other host carries it, like ?messaging_group=" <|
                \_ ->
                    Fulfillment.threadUrl "" "main.example" "other.example" "sub1" Nothing
                        |> Expect.equal "/messages?subscription_messages=sub1@other.example"
            , test "a note index becomes a #subscription-message-<n> fragment" <|
                \_ ->
                    Fulfillment.threadUrl "" "main.example" "main.example" "sub1" (Just 3)
                        |> Expect.equal "/messages?subscription_messages=sub1#subscription-message-3"
            , test "an admin order link carries the server and the mount prefix, so a remote order opens on its own server" <|
                \_ ->
                    ( Fulfillment.orderUrl "/elm" "main.example" "other.example" "sub1"
                    , Fulfillment.orderUrl "" "main.example" "main.example" "sub1"
                    )
                        |> Expect.equal
                            ( "/elm/messages?fulfillment_order=sub1@other.example"
                            , "/messages?fulfillment_order=sub1"
                            )
            , test "the mount prefix is carried by subscription thread links too" <|
                \_ ->
                    Fulfillment.threadUrl "/elm" "main.example" "main.example" "sub1" Nothing
                        |> Expect.equal "/elm/messages?subscription_messages=sub1"
            , test "threadKey is unique across hosts" <|
                \_ ->
                    Fulfillment.threadKey "a.example" "1"
                        |> Expect.notEqual (Fulfillment.threadKey "b.example" "1")
            ]
        , describe "empty model"
            [ test "has no subscriptions, so the Subscriptions tab is hidden" <|
                \_ ->
                    Fulfillment.hasSubscriptions Fulfillment.empty
                        |> Expect.equal False
            , test "has no admin orders, so the Fulfillment tab is hidden" <|
                \_ ->
                    Fulfillment.hasAdminOrders Fulfillment.empty
                        |> Expect.equal False
            , test "and no unread or awaiting counts" <|
                \_ ->
                    ( Fulfillment.totalUnread Fulfillment.empty, Fulfillment.awaitingCount Fulfillment.empty )
                        |> Expect.equal ( 0, 0 )
            ]
        ]
