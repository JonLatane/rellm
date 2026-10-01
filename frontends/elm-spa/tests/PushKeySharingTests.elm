module PushKeySharingTests exposing (suite)

{-| `RellmServers.sharesPushKeyWithAnchor` -- what decides whether an account on some server gets a
"Push Notifications" toggle (see `AccountsPanel.canUsePushNotifications`). The browser's one push
subscription is bound to one VAPID public key, so a server can share it exactly when it advertises
the same key as the server this app runs from.
-}

import Expect
import Shared.AccountsPanel.RellmServers as RellmServers
import Support.RellmServerFactory as Factory
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "RellmServers.sharesPushKeyWithAnchor"
        [ test "the anchor server itself qualifies" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY" ]
                    [ "a.example" ]
                    "a.example"
                    |> Expect.equal True
        , test "another server with the same key qualifies (the multi-server case)" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY"
                    , Factory.connectedWithPushKey "b.example" "KEY"
                    ]
                    [ "a.example" ]
                    "b.example"
                    |> Expect.equal True
        , test "a server with a different key does not" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY"
                    , Factory.connectedWithPushKey "b.example" "OTHER"
                    ]
                    [ "a.example" ]
                    "b.example"
                    |> Expect.equal False
        , test "a server with no push configuration does not" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY"
                    , Factory.connected "b.example"
                    ]
                    [ "a.example" ]
                    "b.example"
                    |> Expect.equal False
        , test "a known-but-disconnected server does not (its configuration isn't known yet)" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY"
                    , Factory.disconnected "b.example"
                    ]
                    [ "a.example" ]
                    "b.example"
                    |> Expect.equal False
        , test "an unknown server does not" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY" ]
                    [ "a.example" ]
                    "nowhere.example"
                    |> Expect.equal False
        , test "nothing qualifies when the anchor itself has no key (even a server that has one)" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connected "a.example"
                    , Factory.connectedWithPushKey "b.example" "KEY"
                    ]
                    [ "a.example" ]
                    "b.example"
                    |> Expect.equal False
        , test "falls through to the next anchor host when the first is unknown (browsingHost -> mainFrontendHost)" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "cdn-public.example" "KEY"
                    , Factory.connectedWithPushKey "b.example" "KEY"
                    ]
                    [ "cdn-internal.example", "cdn-public.example" ]
                    "b.example"
                    |> Expect.equal True
        , test "uses the first anchor that has a key, even if a later one has a different key" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY"
                    , Factory.connectedWithPushKey "main.example" "OTHER"
                    , Factory.connectedWithPushKey "b.example" "OTHER"
                    ]
                    [ "a.example", "main.example" ]
                    "b.example"
                    |> Expect.equal False
        , test "no anchor hosts at all means nothing qualifies" <|
            \_ ->
                RellmServers.sharesPushKeyWithAnchor
                    [ Factory.connectedWithPushKey "a.example" "KEY" ]
                    []
                    "a.example"
                    |> Expect.equal False
        ]
