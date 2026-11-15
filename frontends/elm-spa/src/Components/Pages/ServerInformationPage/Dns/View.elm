module Components.Pages.ServerInformationPage.Dns.View exposing
    ( codeLine
    , copyEffect
    , explainer
    , fixBox
    , fixHint
    , recordBlock
    )

{-| The HTML for DNS help, shared by the Sign In & Contact tab (email domains) and the CDN tab (DNS
setup): a copyable name/type/value record block, a single copyable line (a URL, a command), a
collapsible "what does this mean?" explainer, and a "How to fix" box that renders a server fix hint
(`Dns.Record.parseFixHint`) as text plus record blocks. Generic over `msg`; styled by
`public/style/dns.css`. The caller owns the two bits of state these need -- which text was last
copied, and which explainers are open -- see `copyEffect`.
-}

import Components.Pages.ServerInformationPage.Dns.Record as Record exposing (DnsRecord, HintPart(..))
import Effect exposing (Effect)
import Html exposing (Html, button, code, div, p, span, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Ports
import Process
import Task
import UI.Classes exposing (classes, openClosedClass)


{-| Copies `copied` to the clipboard and, two seconds later, sends `reset copied` so the "Copied" label
can go back to "Copy" (the caller clears its `Maybe String` if it still holds that text).
-}
copyEffect : (String -> msg) -> String -> Effect msg
copyEffect reset copied =
    Effect.batch
        [ Effect.fromCmd (Ports.copyToClipboard copied)
        , Process.sleep 2000 |> Task.perform (\_ -> reset copied) |> Effect.fromCmd
        ]


copyButton : (String -> msg) -> Maybe String -> String -> Html msg
copyButton copy copied content =
    button
        [ type_ "button"
        , class "dns-copy"
        , onClick (copy content)
        , attribute "aria-label" ("Copy " ++ content)
        ]
        [ text
            (if copied == Just content then
                "Copied ✓"

             else
                "Copy"
            )
        ]


{-| One record as labelled rows (Type / Name / Value) in monospace, each of Name and Value with its own
Copy button -- the shape every DNS dashboard asks for. With a `domain` the record's name is relative to
(`@`, `_dmarc`), a "Full name" row spells out the complete name too, since DNS panels differ on which
they want.
-}
recordBlock : (String -> msg) -> Maybe String -> Maybe String -> DnsRecord -> Html msg
recordBlock copy copied maybeDomain record =
    let
        row : String -> String -> Maybe (Html msg) -> Html msg
        row label content maybeCopy =
            div [ class "dns-record-row" ]
                [ span [ class "dns-record-label" ] [ text label ]
                , code [ class "dns-record-value" ] [ text content ]
                , Maybe.withDefault (text "") maybeCopy
                ]
    in
    div [ class "dns-record" ]
        [ row "Type" record.recordType Nothing
        , row "Name" record.name (Just (copyButton copy copied record.name))
        , case maybeDomain of
            Just domain ->
                let
                    full : String
                    full =
                        Record.fullName domain record.name
                in
                if full == record.name then
                    text ""

                else
                    row "Full name" full (Just (copyButton copy copied full))

            Nothing ->
                text ""
        , row "Value" record.value (Just (copyButton copy copied record.value))
        ]


{-| A single monospace line with a Copy button (a URL to open, a command to run).
-}
codeLine : (String -> msg) -> Maybe String -> String -> Html msg
codeLine copy copied content =
    div [ class "dns-code-line" ]
        [ code [ class "dns-code-text" ] [ text content ]
        , copyButton copy copied content
        ]


{-| A collapsible "What does this mean?" box -- a toggle row over a folding body (always mounted,
folded with a CSS grid-rows transition like the rest of these tabs' collapsibles).
-}
explainer : { title : String, open : Bool, onToggle : msg } -> List (Html msg) -> Html msg
explainer config body =
    div [ class "dns-explainer" ]
        [ button
            [ type_ "button"
            , class "dns-explainer-toggle"
            , onClick config.onToggle
            , attribute "aria-expanded"
                (if config.open then
                    "true"

                 else
                    "false"
                )
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass config.open ] ] [ text "▼" ]
            , text config.title
            ]
        , div [ classes [ "dns-collapse", openClosedClass config.open ] ]
            [ div [ class "dns-explainer-body" ] body ]
        ]


{-| A tiny "How to fix" box for a server fix hint: its sentences as text, each exact-record line as a
copyable `recordBlock` (names are relative to `maybeDomain`, see there).
-}
fixHint : (String -> msg) -> Maybe String -> Maybe String -> String -> Html msg
fixHint copy copied maybeDomain hint =
    fixBox copy copied maybeDomain (Record.parseFixHint hint)


{-| The same box from already-built parts (for fixes the tab generates itself).
-}
fixBox : (String -> msg) -> Maybe String -> Maybe String -> List HintPart -> Html msg
fixBox copy copied maybeDomain parts =
    div [ class "dns-fix" ]
        (span [ class "dns-fix-label" ] [ text "How to fix" ]
            :: List.map
                (\part ->
                    case part of
                        HintText sentence ->
                            p [ class "dns-fix-text" ] [ text sentence ]

                        HintRecord record ->
                            recordBlock copy copied maybeDomain record
                )
                parts
        )
