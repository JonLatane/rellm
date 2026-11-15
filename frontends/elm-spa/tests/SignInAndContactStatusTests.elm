module SignInAndContactStatusTests exposing (suite)

import Components.Pages.ServerInformationPage.SignInAndContact.ProviderOrder as ProviderOrder
import Components.Pages.ServerInformationPage.SignInAndContact.Status as Status
import Expect
import Proto.Rellm
    exposing
        ( DmarcStatus
        , EmailDomainStatus
        , ProviderStatus
        , StatusCheck
        , defaultDmarcStatus
        , defaultEmailDomainStatus
        , defaultProviderStatus
        , defaultStatusCheck
        )
import Proto.Rellm.StatusLevel exposing (StatusLevel(..))
import Shared.Conversions exposing (posixToTimestamp)
import Test exposing (Test, describe, test)
import Time


provider : String -> Bool -> StatusLevel -> ProviderStatus
provider id enabled level =
    { defaultProviderStatus | provider = id, displayName = String.toUpper id, enabled = enabled, level = level }


check : String -> StatusLevel -> StatusCheck
check name level =
    { defaultStatusCheck | name = name, level = level }


dmarc : String -> DmarcStatus
dmarc policy =
    { defaultDmarcStatus | recordFound = True, policy = policy, percentage = 100 }


suite : Test
suite =
    describe "Sign In & Contact status helpers"
        [ describe "worstLevel"
            [ test "empty list means nothing to check" <|
                \_ -> Status.worstLevel [] |> Expect.equal STATUSLEVELDISABLED
            , test "error beats everything" <|
                \_ ->
                    Status.worstLevel [ STATUSLEVELOK, STATUSLEVELERROR, STATUSLEVELWARNING, STATUSLEVELUNKNOWN ]
                        |> Expect.equal STATUSLEVELERROR
            , test "warning beats unknown, which beats info, which beats ok" <|
                \_ ->
                    Expect.equal
                        [ Status.worstLevel [ STATUSLEVELUNKNOWN, STATUSLEVELWARNING ]
                        , Status.worstLevel [ STATUSLEVELINFO, STATUSLEVELUNKNOWN ]
                        , Status.worstLevel [ STATUSLEVELOK, STATUSLEVELINFO ]
                        ]
                        [ STATUSLEVELWARNING, STATUSLEVELUNKNOWN, STATUSLEVELINFO ]
            , test "disabled never wins over ok" <|
                \_ -> Status.worstLevel [ STATUSLEVELDISABLED, STATUSLEVELOK ] |> Expect.equal STATUSLEVELOK
            ]
        , describe "sectionHealth"
            [ test "no enabled provider" <|
                \_ ->
                    Status.sectionHealth [ provider "twilio" False STATUSLEVELDISABLED ]
                        |> Expect.equal { level = STATUSLEVELDISABLED, summary = "No provider is switched on yet" }
            , test "disabled providers are ignored when picking the worst level" <|
                \_ ->
                    Status.sectionHealth [ provider "twilio" True STATUSLEVELOK, provider "bird" False STATUSLEVELERROR ]
                        |> Expect.equal { level = STATUSLEVELOK, summary = "Your provider looks healthy" }
            , test "errors are counted first" <|
                \_ ->
                    Status.sectionHealth
                        [ provider "twilio" True STATUSLEVELERROR
                        , provider "bird" True STATUSLEVELERROR
                        , provider "telnyx" True STATUSLEVELWARNING
                        ]
                        |> Expect.equal { level = STATUSLEVELERROR, summary = "2 providers have problems" }
            , test "a single warning" <|
                \_ ->
                    Status.sectionHealth [ provider "twilio" True STATUSLEVELWARNING, provider "bird" True STATUSLEVELOK ]
                        |> Expect.equal { level = STATUSLEVELWARNING, summary = "1 provider needs attention" }
            , test "all healthy" <|
                \_ ->
                    Status.sectionHealth [ provider "twilio" True STATUSLEVELOK, provider "bird" True STATUSLEVELOK ]
                        |> Expect.equal { level = STATUSLEVELOK, summary = "All 2 enabled providers look healthy" }
            ]
        , describe "dmarcPill"
            [ test "no record is a warning" <|
                \_ ->
                    Status.dmarcPill defaultDmarcStatus
                        |> Expect.equal { label = "No DMARC record", level = STATUSLEVELWARNING }
            , test "p=none is monitoring only, a warning" <|
                \_ ->
                    Status.dmarcPill (dmarc "none")
                        |> Expect.equal { label = "Monitoring only", level = STATUSLEVELWARNING }
            , test "quarantine and reject are OK" <|
                \_ ->
                    [ Status.dmarcPill (dmarc "quarantine"), Status.dmarcPill (dmarc "REJECT") ]
                        |> Expect.equal
                            [ { label = "Quarantine", level = STATUSLEVELOK }
                            , { label = "Reject", level = STATUSLEVELOK }
                            ]
            , test "a partial percentage is spelled out" <|
                \_ ->
                    Status.dmarcPill { policy = "reject", percentage = 25, recordFound = True, rawRecord = "", subdomainPolicy = "", aggregateReportUris = [], forensicReportUris = [], dkimAlignment = "", spfAlignment = "", level = STATUSLEVELOK, summary = "" }
                        |> Expect.equal { label = "Reject · 25%", level = STATUSLEVELOK }
            , test "an unrecognized policy falls back to the server's level" <|
                \_ ->
                    Status.dmarcPill { defaultDmarcStatus | recordFound = True, policy = "bogus", level = STATUSLEVELERROR }
                        |> Expect.equal { label = "Unrecognized policy", level = STATUSLEVELERROR }
            ]
        , describe "domainChips"
            [ test "SPF/DKIM/DMARC/MX in order, found by check name" <|
                \_ ->
                    let
                        domain : EmailDomainStatus
                        domain =
                            { defaultEmailDomainStatus
                                | domain = "example.com"
                                , dmarc = Just (dmarc "reject")
                                , checks =
                                    [ check "SPF record" STATUSLEVELOK
                                    , check "DKIM (selector a)" STATUSLEVELOK
                                    , check "DKIM (selector b)" STATUSLEVELERROR
                                    , check "MX records" STATUSLEVELWARNING
                                    ]
                            }
                    in
                    Status.domainChips domain
                        |> Expect.equal
                            [ { label = "SPF", level = STATUSLEVELOK }
                            , { label = "DKIM", level = STATUSLEVELERROR }
                            , { label = "DMARC", level = STATUSLEVELOK }
                            , { label = "MX", level = STATUSLEVELWARNING }
                            ]
            , test "missing checks and DMARC are unknown" <|
                \_ ->
                    Status.domainChips defaultEmailDomainStatus
                        |> List.map .level
                        |> Expect.equal [ STATUSLEVELUNKNOWN, STATUSLEVELUNKNOWN, STATUSLEVELUNKNOWN, STATUSLEVELUNKNOWN ]
            ]
        , describe "checksDefaultOpen"
            [ test "folded when everything is fine" <|
                \_ -> Status.checksDefaultOpen [ check "a" STATUSLEVELOK, check "b" STATUSLEVELINFO ] |> Expect.equal False
            , test "open when something needs attention" <|
                \_ -> Status.checksDefaultOpen [ check "a" STATUSLEVELOK, check "b" STATUSLEVELWARNING ] |> Expect.equal True
            ]
        , describe "ageLabel / checkedAtLabel"
            [ test "ages" <|
                \_ ->
                    [ -5000, 0, 59000, 60000, 5 * 60000, 59 * 60000, 60 * 60000, 3 * 3600000, 24 * 3600000, 3 * 86400000 ]
                        |> List.map Status.ageLabel
                        |> Expect.equal
                            [ "just now"
                            , "just now"
                            , "just now"
                            , "1 minute ago"
                            , "5 minutes ago"
                            , "59 minutes ago"
                            , "1 hour ago"
                            , "3 hours ago"
                            , "1 day ago"
                            , "3 days ago"
                            ]
            , test "checkedAtLabel is relative to now" <|
                \_ ->
                    Status.checkedAtLabel (Time.millisToPosix 1000000) (Just (posixToTimestamp (Time.millisToPosix (1000000 - 120000))))
                        |> Expect.equal "Checked 2 minutes ago"
            , test "no timestamp reads as just now" <|
                \_ -> Status.checkedAtLabel (Time.millisToPosix 0) Nothing |> Expect.equal "Checked just now"
            ]
        , describe "safeLink"
            [ test "only http(s) links" <|
                \_ ->
                    [ "https://postmarkapp.com/x", "HTTP://x.test", "javascript:alert(1)", "//evil.test" ]
                        |> List.map Status.safeLink
                        |> Expect.equal [ Just "https://postmarkapp.com/x", Just "HTTP://x.test", Nothing, Nothing ]
            ]
        , describe "providerDisplayName"
            [ test "uses the report's name, else capitalizes the id" <|
                \_ ->
                    [ Status.providerDisplayName [ { defaultProviderStatus | provider = "sendgrid", displayName = "SendGrid" } ] "sendgrid"
                    , Status.providerDisplayName [] "mailgun"
                    ]
                        |> Expect.equal [ "SendGrid", "Mailgun" ]
            ]
        , describe "ProviderOrder"
            [ test "moveUp/moveDown swap neighbours and clamp at the ends" <|
                \_ ->
                    Expect.equal
                        [ ProviderOrder.moveUp 1 [ 1, 2, 3 ]
                        , ProviderOrder.moveUp 0 [ 1, 2, 3 ]
                        , ProviderOrder.moveDown 1 [ 1, 2, 3 ]
                        , ProviderOrder.moveDown 2 [ 1, 2, 3 ]
                        , ProviderOrder.moveUp 9 [ 1, 2, 3 ]
                        ]
                        [ [ 2, 1, 3 ], [ 1, 2, 3 ], [ 1, 3, 2 ], [ 1, 2, 3 ], [ 1, 2, 3 ] ]
            , test "removeAt and append" <|
                \_ ->
                    Expect.equal
                        [ ProviderOrder.removeAt 1 [ 'a', 'b', 'c' ], ProviderOrder.append 'a' [ 'a', 'b' ], ProviderOrder.append 'c' [ 'a', 'b' ] ]
                        [ [ 'a', 'c' ], [ 'a', 'b' ], [ 'a', 'b', 'c' ] ]
            , test "addSelectionAfter keeps a still-addable choice, else the first addable" <|
                \_ ->
                    Expect.equal
                        [ ProviderOrder.addSelectionAfter [ 1, 2, 3 ] (Just 3) [ 1 ]
                        , ProviderOrder.addSelectionAfter [ 1, 2, 3 ] (Just 1) [ 1 ]
                        , ProviderOrder.addSelectionAfter [ 1, 2, 3 ] Nothing [ 1, 2, 3 ]
                        ]
                        [ Just 3, Just 2, Nothing ]
            ]
        ]
