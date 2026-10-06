module RellmServersTests exposing (suite)

{-| Tests for how `Shared.AccountsPanel.RellmServers` finds a server's backend: which hosts count as
local / LAN development machines, the order port detection tries candidates in, and the per-server
"how I connected last time" hint it persists so the next visit can skip detection.
-}

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Proto.Rellm exposing (defaultServerConfiguration)
import Shared.AccountsPanel.RellmServers as RellmServers
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "RellmServers"
        [ describe "isLocalNetworkHost"
            [ test "recognizes local and LAN development hosts" <|
                \_ ->
                    [ "localhost", "localhost:1234", "armothy", "armothy.local", "Armothy.LOCAL:8000", "printer.lan", "nas.home.arpa", "127.0.0.1", "10.1.2.3", "192.168.4.44", "172.16.0.1", "172.31.255.255", "169.254.1.1", "[::1]", "[fe80::1]:80" ]
                        |> List.filter (not << RellmServers.isLocalNetworkHost)
                        |> Expect.equal []
            , test "does not treat public hosts as local" <|
                \_ ->
                    [ "rellm.org", "jonline.io", "bullcity.social", "neurospicysteve.bullcity.social", "ato.band", "8.8.8.8", "172.32.0.1", "172.15.0.1", "192.169.0.1", "11.0.0.1", "mastodon.world:443", "local.example.com", "foo.locale" ]
                        |> List.filter RellmServers.isLocalNetworkHost
                        |> Expect.equal []
            ]
        , describe "candidatePorts"
            [ test "a local dev host tries plaintext first, so it connects on the first guess" <|
                \_ ->
                    RellmServers.candidatePorts False "armothy.local"
                        |> Expect.equal [ ( 27707, False ), ( 80, False ), ( 8000, False ), ( 27707, True ), ( 443, True ) ]
            , test "a public host on an insecure page still tries TLS first" <|
                \_ ->
                    RellmServers.candidatePorts False "bullcity.social"
                        |> Expect.equal [ ( 27707, True ), ( 443, True ), ( 27707, False ), ( 80, False ), ( 8000, False ) ]
            , test "a secure page only ever uses TLS, for any host" <|
                \_ ->
                    ( RellmServers.candidatePorts True "armothy.local", RellmServers.candidatePorts True "rellm.org" )
                        |> Expect.equal ( [ ( 27707, True ), ( 443, True ) ], [ ( 27707, True ), ( 443, True ) ] )
            ]
        , describe "persisted servers"
            [ test "round-trips how a connected server was last reached" <|
                \_ ->
                    let
                        server : RellmServers.RellmServer
                        server =
                            RellmServers.rellmServerFrom
                                { frontendHost = "armothy.local", backendHost = "armothy.local", port_ = 27707, tls = False }
                                True
                                defaultServerConfiguration
                    in
                    Encode.encode 0 (RellmServers.encodePersistedRellmServer server)
                        |> Decode.decodeString RellmServers.persistedRellmServerDecoder
                        |> Result.map .lastConnection
                        |> Expect.equal (Ok (Just { backendHost = "armothy.local", port_ = 27707, tls = False }))
            , test "a disconnected server persists no hint" <|
                \_ ->
                    RellmServers.disconnectedRellmServer { frontendHost = "x.example", enabled = True, sortOrder = 3, lastConnection = Nothing }
                        |> RellmServers.encodePersistedRellmServer
                        |> Encode.encode 0
                        |> Decode.decodeString RellmServers.persistedRellmServerDecoder
                        |> Result.map .lastConnection
                        |> Expect.equal (Ok Nothing)
            , test "state saved before the hint existed still loads, with no hint" <|
                \_ ->
                    "{\"frontendHost\":\"jonline.io\",\"enabled\":true,\"sortOrder\":2}"
                        |> Decode.decodeString RellmServers.persistedRellmServerDecoder
                        |> Expect.equal (Ok { frontendHost = "jonline.io", enabled = True, sortOrder = 2, lastConnection = Nothing })
            ]
        ]
