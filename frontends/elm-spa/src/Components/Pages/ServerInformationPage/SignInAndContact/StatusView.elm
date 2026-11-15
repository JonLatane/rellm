module Components.Pages.ServerInformationPage.SignInAndContact.StatusView exposing
    ( Handlers
    , domainsSection
    , emailExplainer
    , levelPill
    , providerStatusBlock
    , shimmerLine
    , shimmerPill
    )

{-| The HTML half of the Sign In & Contact tab's live status display (see `Status` for the pure
half): level pills, a provider's summary/metrics/checks, and the Email Domains section with its
prominent DMARC card. Everything is generic over `msg` -- `SignInAndContactTab` passes in the two
messages these views can fire (`Handlers`) -- and styled by `public/style/sign_in_and_contact.css`.

An expandable list of checks (`checksList`) is always mounted and folded with a CSS grid-rows
transition (`.sc-collapse.is-open`/`.is-closed`), like the rest of this tab's collapsibles.

-}

import Components.Pages.ServerInformationPage.SignInAndContact.Status as Status exposing (Chip)
import Components.Pages.ServerInformationPage.Dns.Glossary as Glossary
import Components.Pages.ServerInformationPage.Dns.Record exposing (DnsRecord, HintPart(..))
import Components.Pages.ServerInformationPage.Dns.View as DnsView
import Html exposing (Html, a, button, code, div, h4, li, p, span, strong, text, ul)
import Html.Attributes exposing (class, href, rel, target, title, type_)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (ContactIntegrationsStatus, DmarcStatus, EmailDomainStatus, ProviderStatus, StatusCheck, StatusMetric)
import Proto.Rellm.StatusLevel exposing (StatusLevel)
import Set exposing (Set)
import UI.Classes exposing (classes, openClosedClass)
import UI.Glyph as Glyph


{-| The messages these views can fire -- toggling a folding section (a checks list, a chip's
explanation, the DNS explainer; keyed by string) and copying text -- plus which text was last copied.
-}
type alias Handlers msg =
    { toggleChecks : String -> msg
    , copy : String -> msg
    , copied : Maybe String
    }


levelClass : StatusLevel -> String
levelClass level =
    "sc-level-" ++ Status.levelKey level


{-| A colored status pill: glyph + `label` (defaults to the level's own name when `Nothing`).
-}
levelPill : StatusLevel -> Maybe String -> Html msg
levelPill level maybeLabel =
    span [ classes [ "sc-pill", levelClass level ] ]
        [ span [ class "sc-pill-glyph", Html.Attributes.attribute "aria-hidden" "true" ] [ text (Status.levelGlyph level) ]
        , text (Maybe.withDefault (Status.levelLabel level) maybeLabel)
        ]


levelDot : StatusLevel -> Html msg
levelDot level =
    span
        [ classes [ "sc-dot", levelClass level ]
        , title (Status.levelLabel level)
        ]
        [ text (Status.levelGlyph level) ]


{-| A pill-sized placeholder shimmering while a status check is in flight.
-}
shimmerPill : Html msg
shimmerPill =
    span [ classes [ "sc-pill", "sc-shimmer", "sc-shimmer-pill" ], Html.Attributes.attribute "aria-label" "Checking…" ] [ text "Checking" ]


{-| A text-line-sized shimmering placeholder, `widthPercent` wide.
-}
shimmerLine : Int -> Html msg
shimmerLine widthPercent =
    div
        [ classes [ "sc-shimmer", "sc-shimmer-line" ]
        , Html.Attributes.style "width" (String.fromInt widthPercent ++ "%")
        ]
        []



-- PROVIDERS


{-| One provider's live status: the summary sentence, its metrics as stat tiles, its checks (folded
unless something needs attention -- `Status.checksDefaultOpen`; `toggledChecks` holds the keys the
admin flipped from that default) and a link to the provider's own dashboard.
-}
providerStatusBlock : Handlers msg -> Set String -> String -> ProviderStatus -> Html msg
providerStatusBlock handlers toggledChecks key provider =
    div [ class "sc-status-block" ]
        [ div [ class "sc-status-summary" ]
            [ levelDot provider.level
            , span [ class "sc-status-summary-text" ] [ text provider.summary ]
            ]
        , metricsView provider.metrics
        , checksList handlers toggledChecks Nothing key provider.checks
        , case provider.dashboardUrl |> Maybe.andThen Status.safeLink of
            Just url ->
                a
                    [ class "sc-dashboard-link"
                    , href url
                    , target "_blank"
                    , rel "noopener noreferrer"
                    ]
                    [ text ("Open " ++ provider.displayName ++ " dashboard " ++ Glyph.externalLink) ]

            Nothing ->
                text ""
        ]


metricsView : List StatusMetric -> Html msg
metricsView metrics =
    if List.isEmpty metrics then
        text ""

    else
        div [ class "sc-metrics" ] (List.map metricTile metrics)


metricTile : StatusMetric -> Html msg
metricTile metric =
    div [ class "sc-metric" ]
        [ span [ class "sc-metric-value" ] [ text metric.value ]
        , span [ class "sc-metric-label" ] [ text metric.label ]
        , case metric.detail of
            Just detail ->
                span [ class "sc-metric-detail" ] [ text detail ]

            Nothing ->
                text ""
        ]


{-| A toggle row ("3 checks" + chevron) over a folding list of `StatusCheck`s. For a domain's checks
(`Just domain`) each check that names SPF/DKIM/DMARC/MX gets a one-line plain-English meaning, and record
record names in fix hints get a "just type ..." hint when they sit under that domain.
-}
checksList : Handlers msg -> Set String -> Maybe String -> String -> List StatusCheck -> Html msg
checksList handlers toggledChecks maybeDomain key checks =
    if List.isEmpty checks then
        text ""

    else
        let
            open : Bool
            open =
                if Set.member key toggledChecks then
                    not (Status.checksDefaultOpen checks)

                else
                    Status.checksDefaultOpen checks

            countLabel : String
            countLabel =
                String.fromInt (List.length checks)
                    ++ (if List.length checks == 1 then
                            " check"

                        else
                            " checks"
                       )
        in
        div [ class "sc-checks" ]
            [ button
                [ type_ "button"
                , class "sc-checks-toggle"
                , onClick (handlers.toggleChecks key)
                , Html.Attributes.attribute "aria-expanded"
                    (if open then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ classes [ "expandable-section-arrow", openClosedClass open ] ] [ text "▼" ]
                , text countLabel
                ]
            , div [ classes [ "sc-collapse", openClosedClass open ] ]
                [ ul [ class "sc-check-list" ] (List.map (checkRow handlers maybeDomain) checks) ]
            ]


checkRow : Handlers msg -> Maybe String -> StatusCheck -> Html msg
checkRow handlers maybeDomain check =
    li [ class "sc-check" ]
        [ levelDot check.level
        , div [ class "sc-check-body" ]
            [ span [ class "sc-check-name" ] [ text check.name ]
            , case ( maybeDomain, Glossary.meaningOf check.name ) of
                ( Just _, Just meaning ) ->
                    span [ class "sc-check-meaning" ] [ text meaning ]

                _ ->
                    text ""
            , if String.isEmpty check.detail then
                text ""

              else
                span [ class "sc-check-detail" ] [ text check.detail ]
            , case check.fixHint of
                Just hint ->
                    DnsView.fixHint handlers.copy handlers.copied maybeDomain hint

                Nothing ->
                    text ""
            ]
        ]



-- EMAIL DOMAINS


{-| The collapsible "What do these DNS records do?" box: SPF, DKIM, DMARC and MX in a line or two each.
`toggled` is the tab's set of flipped sections (closed by default).
-}
emailExplainer : Handlers msg -> Set String -> Html msg
emailExplainer handlers toggled =
    DnsView.explainer
        { title = "What do these DNS records do?"
        , open = Set.member explainerKey toggled
        , onToggle = handlers.toggleChecks explainerKey
        }
        (List.map
            (\( label, sentence, extra ) ->
                p [ class "sc-explainer-item" ]
                    [ strong [] [ text (label ++ " ") ]
                    , text (String.dropLeft (String.length label + 1) sentence ++ " " ++ extra |> String.trim)
                    ]
            )
            Glossary.emailExplainer
        )


explainerKey : String
explainerKey =
    "explainer/email"


{-| The "Email Domains" subsection's body: a card per sending domain (see `domainCard`), or a
friendly empty state when the report has none.
-}
domainsSection : Handlers msg -> Set String -> ContactIntegrationsStatus -> Html msg
domainsSection handlers toggled report =
    if List.isEmpty report.emailDomains then
        div [ class "sc-empty" ]
            [ span [ class "sc-empty-title" ] [ text "No sending domains yet" ]
            , span [ class "sc-empty-text" ]
                [ text "Once an email provider is on and has a From address, its domain shows up here with SPF, DKIM and DMARC checks." ]
            ]

    else
        div [ class "sc-domains" ]
            (List.map (domainCard handlers toggled report.emailProviders) report.emailDomains)


domainCard : Handlers msg -> Set String -> List ProviderStatus -> EmailDomainStatus -> Html msg
domainCard handlers toggled providers domain =
    div [ classes [ "sc-domain-card", levelClass domain.level ] ]
        [ div [ class "sc-domain-header" ]
            [ span [ class "sc-domain-name" ] [ text domain.domain ]
            , levelPill domain.level Nothing
            ]
        , if List.isEmpty domain.usedBy then
            text ""

          else
            div [ class "sc-used-by" ]
                (span [ class "sc-used-by-label" ] [ text "Sent by" ]
                    :: List.map (\provider -> span [ class "sc-chip" ] [ text (Status.providerDisplayName providers provider) ]) domain.usedBy
                )
        , if String.isEmpty domain.summary then
            text ""

          else
            p [ class "sc-domain-summary" ] [ text domain.summary ]
        , authChips handlers toggled domain
        , case domain.dmarc of
            Just dmarc ->
                dmarcCard handlers domain.domain dmarc

            Nothing ->
                text ""
        , checksList handlers toggled (Just domain.domain) ("domain/" ++ domain.domain) domain.checks
        ]


chipKey : String -> Chip -> String
chipKey domainName chip =
    "chip/" ++ domainName ++ "/" ++ chip.label


{-| SPF / DKIM / DMARC / MX as tappable chips: tapping one shows its one-line meaning underneath (so
it works on phones, unlike a hover tooltip -- which it also gets, as `title`).
-}
authChips : Handlers msg -> Set String -> EmailDomainStatus -> Html msg
authChips handlers toggled domain =
    let
        chips : List Chip
        chips =
            Status.domainChips domain

        open : List Chip
        open =
            List.filter (\chip -> Set.member (chipKey domain.domain chip) toggled) chips
    in
    div [ class "sc-auth-block" ]
        [ div [ class "sc-auth-chips" ] (List.map (authChip handlers toggled domain.domain) chips)
        , if List.isEmpty open then
            p [ class "sc-chip-hint" ] [ text "Tap a chip to see what it checks." ]

          else
            div [ class "sc-chip-meanings" ]
                (List.map
                    (\chip ->
                        p [ class "sc-chip-meaning" ] [ text (Maybe.withDefault "" (Glossary.meaningOf chip.label)) ]
                    )
                    open
                )
        ]


authChip : Handlers msg -> Set String -> String -> Chip -> Html msg
authChip handlers toggled domainName chip =
    let
        isOpen : Bool
        isOpen =
            Set.member (chipKey domainName chip) toggled
    in
    button
        [ type_ "button"
        , classes [ "sc-auth-chip", levelClass chip.level ]
        , title (chip.label ++ " (" ++ Status.levelLabel chip.level ++ "): " ++ Maybe.withDefault "" (Glossary.meaningOf chip.label))
        , onClick (handlers.toggleChecks (chipKey domainName chip))
        , Html.Attributes.attribute "aria-expanded"
            (if isOpen then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "sc-auth-chip-glyph" ] [ text (Status.levelGlyph chip.level) ]
        , text chip.label
        ]


{-| The prominent DMARC panel: the policy as a pill (`Status.dmarcPill`) with what it means in plain
words, the server's summary, the parsed tags, the raw record in a copyable line, and -- when the policy
only watches or there's no record -- a "How to fix" box with the exact record to publish.
-}
dmarcCard : Handlers msg -> String -> DmarcStatus -> Html msg
dmarcCard handlers domainName dmarc =
    let
        pill : Chip
        pill =
            Status.dmarcPill dmarc

        tagRow : String -> Html msg -> Html msg
        tagRow label value =
            div [ class "sc-dmarc-row" ]
                [ span [ class "sc-dmarc-label" ] [ text label ]
                , span [ class "sc-dmarc-value" ] [ value ]
                ]

        uriList : List String -> Html msg
        uriList uris =
            if List.isEmpty uris then
                span [ class "sc-muted" ] [ text "None" ]

            else
                span [ class "sc-uri-list" ] (List.map (\uri -> code [ class "sc-uri" ] [ text uri ]) uris)
    in
    div [ classes [ "sc-dmarc-card", levelClass pill.level ] ]
        [ div [ class "sc-dmarc-header" ]
            [ h4 [ class "sc-dmarc-title" ] [ text "DMARC" ]
            , levelPill pill.level (Just pill.label)
            ]
        , -- The server's own summary already says what the policy does; our plain-words line is the fallback.
          if String.isEmpty dmarc.summary then
            p [ class "sc-dmarc-meaning" ] [ text (Status.dmarcMeaning dmarc) ]

          else
            p [ class "sc-dmarc-summary" ] [ text dmarc.summary ]
        , if dmarc.recordFound then
            div [ class "sc-dmarc-tags" ]
                [ tagRow "Applies to" (text (String.fromInt dmarc.percentage ++ "% of failing mail"))
                , tagRow "Subdomains"
                    (if String.isEmpty dmarc.subdomainPolicy then
                        span [ class "sc-muted" ] [ text "Same as the domain" ]

                     else
                        text dmarc.subdomainPolicy
                    )
                , tagRow "DKIM alignment" (text (alignmentLabel dmarc.dkimAlignment))
                , tagRow "SPF alignment" (text (alignmentLabel dmarc.spfAlignment))
                , tagRow "Reports (rua)" (uriList dmarc.aggregateReportUris)
                , tagRow "Forensic (ruf)" (uriList dmarc.forensicReportUris)
                ]

          else
            text ""
        , if String.isEmpty dmarc.rawRecord then
            text ""

          else
            DnsView.codeLine handlers.copy handlers.copied dmarc.rawRecord
        , dmarcFix handlers domainName dmarc
        ]


alignmentLabel : String -> String
alignmentLabel alignment =
    case String.toLower alignment of
        "" ->
            "Relaxed (default)"

        "r" ->
            "Relaxed"

        "s" ->
            "Strict"

        other ->
            String.toUpper (String.left 1 other) ++ String.dropLeft 1 other


{-| A tiny "How to fix" under the DMARC card -- only when there is something to do, with the exact
record to publish.
-}
dmarcFix : Handlers msg -> String -> DmarcStatus -> Html msg
dmarcFix handlers domainName dmarc =
    let
        fix : String -> DnsRecord -> Html msg
        fix sentence record =
            DnsView.fixBox handlers.copy handlers.copied (Just domainName) [ HintText sentence, HintRecord record ]
    in
    if not dmarc.recordFound then
        fix "Publish a DMARC record that just watches for now."
            { recordType = "TXT", name = "_dmarc." ++ domainName, value = Status.dmarcStarterRecord domainName }

    else if (Status.dmarcPill dmarc).label == "Monitoring only" then
        fix "Once the reports look clean, move to quarantine (then reject)."
            { recordType = "TXT", name = "_dmarc." ++ domainName, value = Status.strengthenDmarc dmarc.rawRecord }

    else
        text ""
