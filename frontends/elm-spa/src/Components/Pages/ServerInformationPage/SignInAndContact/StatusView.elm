module Components.Pages.ServerInformationPage.SignInAndContact.StatusView exposing
    ( Handlers
    , domainsSection
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
import Html exposing (Html, a, button, code, div, h4, li, p, span, text, ul)
import Html.Attributes exposing (class, href, rel, target, title, type_)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (ContactIntegrationsStatus, DmarcStatus, EmailDomainStatus, ProviderStatus, StatusCheck, StatusMetric)
import Proto.Rellm.StatusLevel exposing (StatusLevel(..))
import Set exposing (Set)
import UI.Classes exposing (classes, openClosedClass)
import UI.Glyph as Glyph


{-| The messages these views can fire: toggling a checks list (keyed by `checksKey`'s strings), and
copying text (the raw DMARC record) to the clipboard.
-}
type alias Handlers msg =
    { toggleChecks : String -> msg
    , copy : String -> msg
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
        , checksList handlers toggledChecks key provider.checks
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


{-| A toggle row ("3 checks" + chevron) over a folding list of `StatusCheck`s.
-}
checksList : Handlers msg -> Set String -> String -> List StatusCheck -> Html msg
checksList handlers toggledChecks key checks =
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
                [ ul [ class "sc-check-list" ] (List.map checkRow checks) ]
            ]


checkRow : StatusCheck -> Html msg
checkRow check =
    li [ class "sc-check" ]
        [ levelDot check.level
        , div [ class "sc-check-body" ]
            [ span [ class "sc-check-name" ] [ text check.name ]
            , if String.isEmpty check.detail then
                text ""

              else
                span [ class "sc-check-detail" ] [ text check.detail ]
            , case check.fixHint of
                Just hint ->
                    p [ class "sc-check-fix" ] [ span [ class "sc-check-fix-label" ] [ text "How to fix: " ], text hint ]

                Nothing ->
                    text ""
            ]
        ]



-- EMAIL DOMAINS


{-| The "Email Domains" subsection's body: a card per sending domain (see `domainCard`), or a
friendly empty state when the report has none. `toggledChecks`/`copied` are the tab's own view
state (see `Handlers`).
-}
domainsSection : Handlers msg -> Set String -> Maybe String -> ContactIntegrationsStatus -> Html msg
domainsSection handlers toggledChecks copied report =
    if List.isEmpty report.emailDomains then
        div [ class "sc-empty" ]
            [ span [ class "sc-empty-title" ] [ text "No sending domains yet" ]
            , span [ class "sc-empty-text" ]
                [ text "Once an email provider is switched on and has a From address, the domain it sends from shows up here with its SPF, DKIM and DMARC checks." ]
            ]

    else
        div [ class "sc-domains" ]
            (List.map (domainCard handlers toggledChecks copied report.emailProviders) report.emailDomains)


domainCard : Handlers msg -> Set String -> Maybe String -> List ProviderStatus -> EmailDomainStatus -> Html msg
domainCard handlers toggledChecks copied providers domain =
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
        , div [ class "sc-auth-chips" ] (List.map authChip (Status.domainChips domain))
        , case domain.dmarc of
            Just dmarc ->
                dmarcCard handlers copied dmarc

            Nothing ->
                text ""
        , checksList handlers toggledChecks ("domain/" ++ domain.domain) domain.checks
        ]


authChip : Chip -> Html msg
authChip chip =
    span [ classes [ "sc-auth-chip", levelClass chip.level ], title (chip.label ++ ": " ++ Status.levelLabel chip.level) ]
        [ span [ class "sc-auth-chip-glyph" ] [ text (Status.levelGlyph chip.level) ]
        , text chip.label
        ]


{-| The prominent DMARC panel: the policy as a pill (`Status.dmarcPill`), the server's one-sentence
summary, the parsed tags, and the raw record in a copyable monospace block.
-}
dmarcCard : Handlers msg -> Maybe String -> DmarcStatus -> Html msg
dmarcCard handlers copied dmarc =
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
        , if String.isEmpty dmarc.summary then
            text ""

          else
            p [ class "sc-dmarc-summary" ] [ text dmarc.summary ]
        , if dmarc.recordFound then
            div [ class "sc-dmarc-tags" ]
                [ tagRow "Applies to"
                    (text
                        (if dmarc.percentage <= 0 || dmarc.percentage >= 100 then
                            "100% of failing mail"

                         else
                            String.fromInt dmarc.percentage ++ "% of failing mail"
                        )
                    )
                , tagRow "Subdomains"
                    (if String.isEmpty dmarc.subdomainPolicy then
                        span [ class "sc-muted" ] [ text "Same as the domain" ]

                     else
                        text dmarc.subdomainPolicy
                    )
                , tagRow "DKIM alignment" (text (alignmentLabel dmarc.dkimAlignment))
                , tagRow "SPF alignment" (text (alignmentLabel dmarc.spfAlignment))
                , tagRow "Aggregate reports (rua)" (uriList dmarc.aggregateReportUris)
                , tagRow "Forensic reports (ruf)" (uriList dmarc.forensicReportUris)
                ]

          else
            text ""
        , if String.isEmpty dmarc.rawRecord then
            text ""

          else
            div [ class "sc-record" ]
                [ code [ class "sc-record-text" ] [ text dmarc.rawRecord ]
                , button
                    [ type_ "button"
                    , class "sc-record-copy"
                    , onClick (handlers.copy dmarc.rawRecord)
                    ]
                    [ text
                        (if copied == Just dmarc.rawRecord then
                            "Copied ✓"

                         else
                            "Copy"
                        )
                    ]
                ]
        , dmarcAdvice dmarc
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


{-| A friendly nudge under the DMARC card -- only when there is something to do.
-}
dmarcAdvice : DmarcStatus -> Html msg
dmarcAdvice dmarc =
    if not dmarc.recordFound then
        p [ class "sc-dmarc-advice" ]
            [ text "Without a DMARC record, mailbox providers can't tell whether mail claiming to be from this domain is really yours, and Gmail/Yahoo expect one from bulk senders. Publish a TXT record at "
            , code [] [ text "_dmarc.<your domain>" ]
            , text ", starting with "
            , code [] [ text "v=DMARC1; p=none; rua=mailto:you@your-domain" ]
            , text " to watch reports before enforcing."
            ]

    else if (Status.dmarcPill dmarc).level == STATUSLEVELWARNING then
        p [ class "sc-dmarc-advice" ]
            [ text "A policy of "
            , code [] [ text "none" ]
            , text " only monitors: spoofed mail is still delivered. Once the aggregate reports look clean, move to "
            , code [] [ text "quarantine" ]
            , text ", then "
            , code [] [ text "reject" ]
            , text "."
            ]

    else
        text ""
