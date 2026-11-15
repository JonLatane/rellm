module Components.Pages.ServerInformationPage.SignInAndContact.Status exposing
    ( Chip
    , ageLabel
    , checkedAtLabel
    , checksDefaultOpen
    , dmarcMeaning
    , dmarcPill
    , dmarcStarterRecord
    , domainChips
    , findProvider
    , levelGlyph
    , levelKey
    , levelLabel
    , providerDisplayName
    , replyIsFresh
    , safeLink
    , sectionHealth
    , strengthenDmarc
    , worstLevel
    )

{-| The pure half of the Sign In & Contact tab's live status display (`ContactIntegrationsStatus`,
from `GetContactIntegrationsStatus`) -- everything that decides _what to say_ about a status report,
so it can be unit-tested (`tests/SignInAndContactStatusTests.elm`) without rendering anything.
`SignInAndContact.StatusView` turns these into HTML.

"Worst" level: `severity` orders `StatusLevel`s for aggregation (`ERROR` > `WARNING` > `UNKNOWN` >
`INFO` > `OK` > `DISABLED`) -- deliberately _not_ the enum's own numeric order, which is "roughly best
to worst" with `DISABLED` last. An enabled provider whose status couldn't be determined should look
worse than a healthy one, and a disabled provider never drags a section's health down.

-}

import Proto.Google.Protobuf exposing (Timestamp)
import Proto.Rellm exposing (DmarcStatus, EmailDomainStatus, ProviderStatus, StatusCheck)
import Proto.Rellm.StatusLevel exposing (StatusLevel(..))
import Shared.Conversions exposing (timestampToPosix)
import Time


{-| A small labelled traffic light, e.g. `SPF` + `OK`.
-}
type alias Chip =
    { label : String
    , level : StatusLevel
    }


severity : StatusLevel -> Int
severity level =
    case level of
        STATUSLEVELERROR ->
            5

        STATUSLEVELWARNING ->
            4

        STATUSLEVELUNKNOWN ->
            3

        StatusLevelUnrecognized_ _ ->
            3

        STATUSLEVELINFO ->
            2

        STATUSLEVELOK ->
            1

        STATUSLEVELDISABLED ->
            0


{-| The most severe of `levels` -- `STATUSLEVELDISABLED` for an empty list (nothing to check).
-}
worstLevel : List StatusLevel -> StatusLevel
worstLevel levels =
    List.foldl
        (\level worst ->
            if severity level > severity worst then
                level

            else
                worst
        )
        STATUSLEVELDISABLED
        levels


{-| Short pill text.
-}
levelLabel : StatusLevel -> String
levelLabel level =
    case level of
        STATUSLEVELOK ->
            "OK"

        STATUSLEVELINFO ->
            "Info"

        STATUSLEVELWARNING ->
            "Warning"

        STATUSLEVELERROR ->
            "Error"

        STATUSLEVELDISABLED ->
            "Disabled"

        STATUSLEVELUNKNOWN ->
            "Unknown"

        StatusLevelUnrecognized_ _ ->
            "Unknown"


{-| The suffix of the `sc-level-*` CSS classes (`sign_in_and_contact.css`).
-}
levelKey : StatusLevel -> String
levelKey level =
    case level of
        STATUSLEVELOK ->
            "ok"

        STATUSLEVELINFO ->
            "info"

        STATUSLEVELWARNING ->
            "warning"

        STATUSLEVELERROR ->
            "error"

        STATUSLEVELDISABLED ->
            "disabled"

        STATUSLEVELUNKNOWN ->
            "unknown"

        StatusLevelUnrecognized_ _ ->
            "unknown"


{-| A one-character glyph per level. Plain letters/symbols with no emoji presentation (see
`UI.Glyph`), so iOS never swaps them for color emoji.
-}
levelGlyph : StatusLevel -> String
levelGlyph level =
    case level of
        STATUSLEVELOK ->
            "✓"

        STATUSLEVELINFO ->
            "i"

        STATUSLEVELWARNING ->
            "!"

        STATUSLEVELERROR ->
            "✕"

        STATUSLEVELDISABLED ->
            "–"

        STATUSLEVELUNKNOWN ->
            "?"

        StatusLevelUnrecognized_ _ ->
            "?"


findProvider : String -> List ProviderStatus -> Maybe ProviderStatus
findProvider provider providers =
    providers |> List.filter (\p -> p.provider == provider) |> List.head


{-| The display name for a provider id (`ProviderStatus.provider`, also what
`EmailDomainStatus.usedBy` holds) -- the report's own `displayName` when `providers` has it,
otherwise the id with its first letter capitalized.
-}
providerDisplayName : List ProviderStatus -> String -> String
providerDisplayName providers provider =
    case findProvider provider providers of
        Just p ->
            if String.isEmpty p.displayName then
                capitalize provider

            else
                p.displayName

        Nothing ->
            capitalize provider


capitalize : String -> String
capitalize text =
    case String.uncons text of
        Just ( first, rest ) ->
            String.cons (Char.toUpper first) rest

        Nothing ->
            text


{-| Only `http(s)` links are ever rendered as links -- `dashboard_url` comes off the wire.
-}
safeLink : String -> Maybe String
safeLink url =
    let
        lower : String
        lower =
            String.toLower url
    in
    if String.startsWith "https://" lower || String.startsWith "http://" lower then
        Just url

    else
        Nothing


{-| The one-line health summary shown beside a section's (SMS/Email) master toggle: the worst level
among its _enabled_ providers, and a sentence explaining it.
-}
sectionHealth : List ProviderStatus -> { level : StatusLevel, summary : String }
sectionHealth providers =
    let
        enabled : List ProviderStatus
        enabled =
            List.filter .enabled providers
    in
    if List.isEmpty enabled then
        { level = STATUSLEVELDISABLED, summary = "No provider is switched on yet" }

    else
        { level = worstLevel (List.map .level enabled)
        , summary = enabledSummary enabled
        }


{-| The sentence for a non-empty list of enabled providers: the worst news first.
-}
enabledSummary : List ProviderStatus -> String
enabledSummary enabled =
    let
        count : (StatusLevel -> Bool) -> Int
        count matches =
            enabled |> List.filter (\p -> matches p.level) |> List.length

        problems : List ( Int, String, String )
        problems =
            [ ( count ((==) STATUSLEVELERROR), "provider has a problem", "providers have problems" )
            , ( count ((==) STATUSLEVELWARNING), "provider needs attention", "providers need attention" )
            , ( count (\level -> severity level == severity STATUSLEVELUNKNOWN), "provider couldn't be verified", "providers couldn't be verified" )
            ]
    in
    case List.filter (\( n, _, _ ) -> n > 0) problems of
        ( n, singular, pluralForm ) :: _ ->
            plural n singular pluralForm

        [] ->
            if List.length enabled == 1 then
                "Your provider looks healthy"

            else
                "All " ++ String.fromInt (List.length enabled) ++ " enabled providers look healthy"


plural : Int -> String -> String -> String
plural n singular pluralForm =
    String.fromInt n
        ++ " "
        ++ (if n == 1 then
                singular

            else
                pluralForm
           )


{-| The DMARC policy as a pill: `p=none` is only "Monitoring only" (a warning -- mail failing
authentication is still delivered), `quarantine`/`reject` actually enforce (OK). A partial `pct=`
is spelled out. No record at all is a warning too. The level is the server's own (it sees things the
policy text doesn't, like several records), falling back to what the policy implies only when the
server reported `UNKNOWN`.
-}
dmarcPill : DmarcStatus -> Chip
dmarcPill dmarc =
    let
        -- The parsed `pct=` is authoritative whenever a record exists (the server defaults an absent
        -- tag to 100), so even 0 is spelled out.
        partial : String -> String
        partial label =
            if dmarc.percentage < 100 then
                label ++ " · " ++ String.fromInt dmarc.percentage ++ "%"

            else
                label

        -- The server's own verdict wins (it knows about multiple records, partial `pct`, ...); only an
        -- `UNKNOWN` (older server) falls back to what the policy alone implies.
        levelOr : StatusLevel -> StatusLevel
        levelOr fallback =
            if severity dmarc.level == severity STATUSLEVELUNKNOWN then
                fallback

            else
                dmarc.level
    in
    if not dmarc.recordFound then
        { label = "No DMARC record", level = STATUSLEVELWARNING }

    else
        case String.toLower (String.trim dmarc.policy) of
            "none" ->
                { label = "Monitoring only", level = levelOr STATUSLEVELWARNING }

            "quarantine" ->
                { label = partial "Quarantine", level = levelOr STATUSLEVELOK }

            "reject" ->
                { label = partial "Reject", level = levelOr STATUSLEVELOK }

            _ ->
                { label = "Unrecognized policy", level = dmarc.level }


{-| The at-a-glance SPF / DKIM / DMARC / MX row for a domain. SPF, DKIM and MX are found by name in
the domain's `checks` (any check whose lower-cased name mentions it; several matches -- e.g. one
DKIM check per selector -- collapse to the worst), `UNKNOWN` when no check mentions it. DMARC comes
from the parsed record (`dmarcPill`).
-}
domainChips : EmailDomainStatus -> List Chip
domainChips domain =
    let
        checkChip : String -> String -> Chip
        checkChip label needle =
            { label = label
            , level =
                case List.filter (checkMentions needle) domain.checks of
                    [] ->
                        STATUSLEVELUNKNOWN

                    matches ->
                        worstLevel (List.map .level matches)
            }
    in
    [ checkChip "SPF" "spf"
    , checkChip "DKIM" "dkim"
    , { label = "DMARC"
      , level =
            domain.dmarc
                |> Maybe.map (dmarcPill >> .level)
                |> Maybe.withDefault STATUSLEVELUNKNOWN
      }
    , checkChip "MX" "mx"
    ]


checkMentions : String -> StatusCheck -> Bool
checkMentions needle check =
    String.contains needle (String.toLower check.name)


{-| "just now", "5 minutes ago", "1 hour ago", "3 days ago" for an age in milliseconds (negative
ages -- the browser's clock being a little behind the server's -- read as "just now").
-}
ageLabel : Int -> String
ageLabel ageMs =
    let
        minutes : Int
        minutes =
            ageMs // 60000

        unit : Int -> String -> String
        unit n name =
            String.fromInt n
                ++ " "
                ++ name
                ++ (if n == 1 then
                        ""

                    else
                        "s"
                   )
                ++ " ago"
    in
    if minutes < 1 then
        "just now"

    else if minutes < 60 then
        unit minutes "minute"

    else if minutes < 60 * 24 then
        unit (minutes // 60) "hour"

    else
        unit (minutes // (60 * 24)) "day"


{-| "Checked 2 minutes ago" for a report's `checkedAt` as of `now`.
-}
checkedAtLabel : Time.Posix -> Maybe Timestamp -> String
checkedAtLabel now maybeCheckedAt =
    case maybeCheckedAt of
        Just checkedAt ->
            "Checked " ++ ageLabel (Time.posixToMillis now - Time.posixToMillis (timestampToPosix checkedAt))

        Nothing ->
            "Checked just now"


{-| Whether a provider's/domain's list of checks starts out expanded: only when something in it needs
an admin's attention (a warning or an error) -- an all-green list stays folded away.
-}
checksDefaultOpen : List StatusCheck -> Bool
checksDefaultOpen checks =
    List.any (\check -> severity check.level >= severity STATUSLEVELWARNING && check.level /= STATUSLEVELUNKNOWN) checks


{-| Whether a status reply should be applied: only if its request id is newer than the newest reply
already applied -- a slow pre-save check must not overwrite a later one (or its error).
-}
replyIsFresh : Int -> Int -> Bool
replyIsFresh appliedId replyId =
    replyId > appliedId


{-| What the DMARC policy means in plain words (shown under the DMARC pill).
-}
dmarcMeaning : DmarcStatus -> String
dmarcMeaning dmarc =
    if not dmarc.recordFound then
        "Receivers have no instructions for forged mail."

    else
        case String.toLower (String.trim dmarc.policy) of
            "none" ->
                "Failing mail is still delivered (monitoring only)."

            "quarantine" ->
                "Failing mail goes to spam."

            "reject" ->
                "Failing mail is rejected."

            _ ->
                "The policy isn't one receivers recognise."


{-| A starter DMARC record that only watches and sends reports to `postmaster@<domain>`.
-}
dmarcStarterRecord : String -> String
dmarcStarterRecord domain =
    "v=DMARC1; p=none; rua=mailto:postmaster@" ++ domain


{-| The same DMARC record with its own `p=none` raised to `p=quarantine` (the `sp=` tag, if any, is
left alone). Records whose `p=` isn't `none` come back unchanged.
-}
strengthenDmarc : String -> String
strengthenDmarc record =
    record
        |> String.split ";"
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)
        |> List.map
            (\tag ->
                if String.toLower (String.replace " " "" tag) == "p=none" then
                    "p=quarantine"

                else
                    tag
            )
        |> String.join "; "
