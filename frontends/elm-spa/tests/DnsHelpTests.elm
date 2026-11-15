module DnsHelpTests exposing (suite)

import Components.Pages.ServerInformationPage.CdnTab.DnsSetup as DnsSetup exposing (HostProblem(..))
import Components.Pages.ServerInformationPage.Dns.Glossary as Glossary
import Components.Pages.ServerInformationPage.Dns.Record as Record exposing (HintPart(..))
import Components.Pages.ServerInformationPage.SignInAndContact.Status as Status
import Expect
import Proto.Rellm exposing (defaultDmarcStatus)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "DNS help"
        [ describe "Record.parseFixHint"
            [ test "a sentence followed by record lines" <|
                \_ ->
                    Record.parseFixHint "Add a DMARC record.\nTXT _dmarc v=DMARC1; p=none; rua=mailto:postmaster@example.com\nCNAME mail.example.com  mx.provider.net"
                        |> Expect.equal
                            [ HintText "Add a DMARC record."
                            , HintRecord { recordType = "TXT", name = "_dmarc", value = "v=DMARC1; p=none; rua=mailto:postmaster@example.com" }
                            , HintRecord { recordType = "CNAME", name = "mail.example.com", value = "mx.provider.net" }
                            ]
            , test "MX values may hold spaces; A and AAAA are not record lines in a fix hint" <|
                \_ ->
                    [ Record.parseRecordLine "MX example.com 10 mail.example.com"
                    , Record.parseRecordLine "A host.example.com 203.0.113.9"
                    , Record.parseRecordLine "TXT example.com v=spf1 include:spf.mtasv.net ~all"
                    ]
                        |> Expect.equal
                            [ Just { recordType = "MX", name = "example.com", value = "10 mail.example.com" }
                            , Nothing
                            , Just { recordType = "TXT", name = "example.com", value = "v=spf1 include:spf.mtasv.net ~all" }
                            ]
            , test "a sentence that merely starts with A stays text" <|
                \_ ->
                    Record.parseFixHint "A DMARC record is missing."
                        |> Expect.equal [ HintText "A DMARC record is missing." ]
            , test "relativeHint only when the name is under the domain or a parent" <|
                \_ ->
                    [ Record.relativeHint "example.com" "_dmarc.example.com"
                    , Record.relativeHint "mail.example.com" "_dmarc.example.com"
                    , Record.relativeHint "mail.example.com" "s1._domainkey.mail.example.com"
                    , Record.relativeHint "example.com" "example.com"
                    , Record.relativeHint "example.com" "_dmarc.other.net"
                    , Record.relativeHint "example.com" "_dmarc.com"
                    ]
                        |> Expect.equal [ Just "_dmarc", Just "_dmarc", Just "s1._domainkey", Nothing, Nothing, Nothing ]
            , test "fully-qualified names parse as given" <|
                \_ ->
                    Record.parseFixHint "Add this.\nTXT _dmarc.example.com v=DMARC1; p=none\nCNAME s1._domainkey.example.com u1.wl.sendgrid.net"
                        |> Expect.equal
                            [ HintText "Add this."
                            , HintRecord { recordType = "TXT", name = "_dmarc.example.com", value = "v=DMARC1; p=none" }
                            , HintRecord { recordType = "CNAME", name = "s1._domainkey.example.com", value = "u1.wl.sendgrid.net" }
                            ]
            , test "unknown types, missing name or value, and blank lines" <|
                \_ ->
                    Record.parseFixHint "SRV _x y\nTXT onlyname\n\n   \nTXT\nplain"
                        |> Expect.equal [ HintText "SRV _x y", HintText "TXT onlyname", HintText "TXT", HintText "plain" ]
            , test "copyText is the whole line" <|
                \_ ->
                    Record.copyText { recordType = "TXT", name = "_dmarc", value = "v=DMARC1; p=none" }
                        |> Expect.equal "TXT _dmarc v=DMARC1; p=none"
            ]
        , describe "Glossary.meaningOf"
            [ test "finds SPF/DKIM/DMARC/MX by name, case-insensitively" <|
                \_ ->
                    [ "SPF record", "DKIM (selector a)", "dmarc policy", "MX records", "Server token" ]
                        |> List.map (Glossary.meaningOf >> Maybe.map (String.left 12))
                        |> Expect.equal [ Just "SPF lists wh", Just "DKIM adds a ", Just "DMARC tells ", Just "MX records s", Nothing ]
            ]
        , describe "DMARC helpers"
            [ test "strengthenDmarc raises only p=none" <|
                \_ ->
                    [ Status.strengthenDmarc "v=DMARC1; p=none; sp=none; rua=mailto:a@x.com"
                    , Status.strengthenDmarc "v=DMARC1;p = none;pct=50"
                    , Status.strengthenDmarc "v=DMARC1; p=reject"
                    ]
                        |> Expect.equal
                            [ "v=DMARC1; p=quarantine; sp=none; rua=mailto:a@x.com"
                            , "v=DMARC1; p=quarantine; pct=50"
                            , "v=DMARC1; p=reject"
                            ]
            , test "starter record and plain-words meaning" <|
                \_ ->
                    ( Status.dmarcStarterRecord "example.com"
                    , [ { defaultDmarcStatus | recordFound = True, policy = "reject" }, defaultDmarcStatus ]
                        |> List.map Status.dmarcMeaning
                    )
                        |> Expect.equal
                            ( "v=DMARC1; p=none; rua=mailto:postmaster@example.com"
                            , [ "Failing mail is rejected.", "Receivers have no instructions for forged mail." ]
                            )
            ]
        , describe "DnsSetup.validateHost"
            [ test "plausible domains and the empty entry are fine" <|
                \_ ->
                    [ "example.com", "api.example.co.uk", " Example.com ", "" ]
                        |> List.map DnsSetup.validateHost
                        |> Expect.equal [ Nothing, Nothing, Nothing, Nothing ]
            , test "scheme, path, spaces, port, no dot, odd characters" <|
                \_ ->
                    [ "https://example.com", "example.com/about", "exa mple.com", "example.com:443", "localhost", "exa_mple.com", "example..com" ]
                        |> List.map DnsSetup.validateHost
                        |> Expect.equal
                            [ Just HostHasScheme
                            , Just HostHasPath
                            , Just HostHasSpaces
                            , Just HostHasPort
                            , Just HostNoDot
                            , Just HostBadCharacters
                            , Just HostBadCharacters
                            ]
            , test "cleanHost strips scheme and path" <|
                \_ ->
                    DnsSetup.cleanHost " HTTPS://Example.com/a?b#c " |> Expect.equal "example.com"
            , test "isApex" <|
                \_ ->
                    [ "example.com", "example.co.uk", "www.example.com", "api.example.co.uk" ]
                        |> List.map DnsSetup.isApex
                        |> Expect.equal [ True, True, False, False ]
            ]
        , describe "DnsSetup.plan"
            [ test "a subdomain frontend points a CNAME at the backend; backend gets A/AAAA" <|
                \_ ->
                    let
                        p : DnsSetup.Plan
                        p =
                            DnsSetup.plan { frontendHost = "www.example.com", backendHost = "app.example.net", secureMedia = False }
                    in
                    ( p.warnings
                    , p.steps |> List.map (.records >> List.map (\r -> ( r.recordType, r.name, r.value )))
                    )
                        |> Expect.equal
                            ( []
                            , [ [ ( "CNAME", "www.example.com", "app.example.net" ) ]
                              , [ ( "A", "app.example.net", "<your server's IPv4>" ), ( "AAAA", "app.example.net", "<your server's IPv6, if any>" ) ]
                              , []
                              ]
                            )
            , test "an apex frontend uses @ and mentions flattening" <|
                \_ ->
                    let
                        step : Maybe DnsSetup.Step
                        step =
                            DnsSetup.plan { frontendHost = "example.com", backendHost = "app.example.net", secureMedia = False }
                                |> .steps
                                |> List.head
                    in
                    ( step |> Maybe.andThen (.records >> List.head) |> Maybe.map .name
                    , step |> Maybe.andThen .note |> Maybe.map (String.contains "flattens")
                    )
                        |> Expect.equal ( Just "example.com", Just True )
            , test "the check step has the URL and a curl line" <|
                \_ ->
                    DnsSetup.plan { frontendHost = "example.com", backendHost = "app.example.net", secureMedia = False }
                        |> .steps
                        |> List.drop 2
                        |> List.head
                        |> Maybe.map .codeLines
                        |> Expect.equal (Just [ "https://example.com/backend_host", "curl https://example.com/backend_host" ])
            , test "no hosts entered shows example.com placeholders and no warnings" <|
                \_ ->
                    let
                        p : DnsSetup.Plan
                        p =
                            DnsSetup.plan { frontendHost = "", backendHost = "", secureMedia = False }
                    in
                    ( ( p.frontend, p.backend ), ( p.frontendIsExample && p.backendIsExample, p.warnings ) )
                        |> Expect.equal ( ( "example.com", "backend.example.com" ), ( True, [] ) )
            , test "identical hosts warn" <|
                \_ ->
                    DnsSetup.plan { frontendHost = "example.com", backendHost = "Example.com", secureMedia = False }
                        |> .warnings
                        |> List.length
                        |> Expect.equal 1
            , test "an invalid host warns, and a pasted URL still drives the records" <|
                \_ ->
                    let
                        p : DnsSetup.Plan
                        p =
                            DnsSetup.plan { frontendHost = "https://www.example.com/", backendHost = "nodot", secureMedia = False }
                    in
                    ( ( List.length p.warnings, p.frontend ), ( p.frontendIsExample, p.backendIsExample ) )
                        |> Expect.equal ( ( 2, "www.example.com" ), ( False, True ) )
            , test "secure media adds the CDN IP ranges step" <|
                \_ ->
                    DnsSetup.plan { frontendHost = "", backendHost = "", secureMedia = True }
                        |> .steps
                        |> List.map (.links >> List.length)
                        |> Expect.equal [ 0, 0, 0, 2 ]
            ]
        ]
