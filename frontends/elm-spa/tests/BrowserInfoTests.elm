module BrowserInfoTests exposing (suite)

{-| `Shared.BrowserInfo.fromUserAgent` -- display-only user-agent sniffing. The interesting cases
are the Chromium/WebKit lookalikes: nearly every browser's user agent also says "Chrome/" and/or
"Safari/", so ordering is what's actually under test.
-}

import Expect
import Shared.BrowserInfo as BrowserInfo exposing (Browser(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Shared.BrowserInfo"
        [ describe "fromUserAgent"
            (List.map
                (\( label, userAgent, expected ) ->
                    test label <|
                        \_ -> BrowserInfo.fromUserAgent userAgent |> Expect.equal expected
                )
                [ ( "desktop Chrome"
                  , "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
                  , Chrome
                  )
                , ( "Chrome on iOS (CriOS)"
                  , "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.0.0 Mobile/15E148 Safari/604.1"
                  , Chrome
                  )
                , ( "desktop Safari"
                  , "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
                  , Safari
                  )
                , ( "Mobile Safari"
                  , "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
                  , Safari
                  )
                , ( "Firefox"
                  , "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:127.0) Gecko/20100101 Firefox/127.0"
                  , Firefox
                  )
                , ( "Firefox on iOS (FxiOS)"
                  , "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/127.0 Mobile/15E148 Safari/605.1.15"
                  , Firefox
                  )
                , ( "Edge (also says Chrome/ and Safari/)"
                  , "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0"
                  , Edge
                  )
                , ( "Opera (also says Chrome/ and Safari/)"
                  , "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 OPR/111.0.0.0"
                  , Opera
                  )
                , ( "Samsung Internet (also says Chrome/ and Safari/)"
                  , "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36"
                  , SamsungInternet
                  )
                , ( "an unrecognized user agent"
                  , "curl/8.4.0"
                  , UnknownBrowser
                  )
                , ( "an empty user agent"
                  , ""
                  , UnknownBrowser
                  )
                ]
            )
        , describe "name"
            [ test "names each known browser" <|
                \_ ->
                    [ Chrome, Safari, Firefox, Edge, Opera, SamsungInternet ]
                        |> List.map BrowserInfo.name
                        |> Expect.equal [ "Chrome", "Safari", "Firefox", "Edge", "Opera", "Samsung Internet" ]
            , test "falls back to a generic word that still reads in \"<name> notifications are enabled\"" <|
                \_ ->
                    BrowserInfo.name UnknownBrowser
                        |> Expect.equal "Browser"
            ]
        ]
