module PushNotificationLinkTests exposing (suite)

{-| `Shared.PushNotificationLink.toInAppPath` -- rewrites a push notification's absolute deep link
(`https://<frontend_host>/messages?messaging_group=<id>#message-<id>`, see
`backend/src/web_push/mod.rs`'s `notification_url`) into a path the already-running app can route
to itself, adding the `id@host` suffix (`Components.Messages.groupRouteId`) when the notification is
for a server other than `mainFrontendHost`.
-}

import Expect
import Shared.PushNotificationLink exposing (toInAppPath)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Shared.PushNotificationLink.toInAppPath"
        [ test "a notification from the main host keeps its bare ids" <|
            \_ ->
                toInAppPath "a.example" "https://a.example/messages?messaging_group=G1#message-M1"
                    |> Expect.equal (Just "/messages?messaging_group=G1#message-M1")
        , test "a notification from another server gets an @host suffix on the group id" <|
            \_ ->
                toInAppPath "a.example" "https://b.example/messages?messaging_group=G1#message-M1"
                    |> Expect.equal (Just "/messages?messaging_group=G1@b.example#message-M1")
        , test "the message fragment passes through untouched (only query ids are host-qualified)" <|
            \_ ->
                toInAppPath "a.example" "https://b.example/messages?messaging_group=G1#message-M9"
                    |> Maybe.map (String.split "#" >> List.drop 1 >> String.join "#")
                    |> Expect.equal (Just "message-M9")
        , test "a non-default port is part of the host" <|
            \_ ->
                toInAppPath "a.example" "https://b.example:8443/messages?messaging_group=G1"
                    |> Expect.equal (Just "/messages?messaging_group=G1@b.example:8443")
        , test "the ?message= form is host-qualified too" <|
            \_ ->
                toInAppPath "a.example" "https://b.example/messages?message=M1"
                    |> Expect.equal (Just "/messages?message=M1@b.example")
        , test "a value that already names its host is left alone" <|
            \_ ->
                toInAppPath "a.example" "https://b.example/messages?messaging_group=G1@c.example"
                    |> Expect.equal (Just "/messages?messaging_group=G1@c.example")
        , test "unrelated params are preserved, and only the id params change" <|
            \_ ->
                toInAppPath "a.example" "https://b.example/messages?foo=bar&messaging_group=G1&baz=1"
                    |> Expect.equal (Just "/messages?foo=bar&messaging_group=G1@b.example&baz=1")
        , test "a link with no query or fragment is just its path" <|
            \_ ->
                toInAppPath "a.example" "https://b.example/messages"
                    |> Expect.equal (Just "/messages")
        , test "a root link with no path becomes /" <|
            \_ ->
                toInAppPath "a.example" "https://b.example"
                    |> Expect.equal (Just "/")
        , test "something that isn't an absolute URL is rejected" <|
            \_ ->
                toInAppPath "a.example" "/messages?messaging_group=G1"
                    |> Expect.equal Nothing
        , test "an empty string is rejected" <|
            \_ ->
                toInAppPath "a.example" ""
                    |> Expect.equal Nothing
        ]
