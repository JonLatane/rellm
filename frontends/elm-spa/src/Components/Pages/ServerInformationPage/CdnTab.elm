module Components.Pages.ServerInformationPage.CdnTab exposing (Model, Msg, init, update, view)

{-| The CDN tab of `Components.Pages.ServerInformationPage` -- `ExternalCDNConfig` (see that
message's own doc in `server_configuration.proto`), editable by an admin as one unit (a single
Edit/Save/Cancel, like every other section on this page), with two exceptions: `secureMedia` and
`mediaIpv4Allowlist`/`mediaIpv6Allowlist` aren't shown at all yet (still `(TODO)` on the backend --
see the proto doc), and `cdnGrpc` is shown but always read-only (also still `(TODO)` there).

The "External CDN HTTP Support" toggle is what sets/nulls out `externalCdnConfig` on the
`ServerConfiguration` entirely (see `applyCdnConfig`) -- "Frontend Host"/"Backend Host" are only
meaningful (and only enabled in the UI) while it's on.

Below the form, a "DNS setup" card (`dnsSetupView`, pure logic in `CdnTab.DnsSetup`, widgets shared with
the Sign In & Contact tab via `Dns.View`) turns the entered (or, outside edit mode, saved) hosts into the
exact records to create -- computed live as the admin types -- with copyable name/type/value blocks, a
`GET /backend_host` check, and gentle warnings for look-alike mistakes. With no hosts it shows the
pattern with `example.com` placeholders.

-}

import Components.Pages.ServerInformationPage.CdnTab.DnsSetup as DnsSetup exposing (Plan, Step)
import Components.Pages.ServerInformationPage.Common as Common
import Components.Pages.ServerInformationPage.Dns.View as DnsView
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, a, button, div, h3, input, li, p, span, strong, text, ul)
import Html.Attributes exposing (class, disabled, href, placeholder, rel, target, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (ExternalCDNConfig, ServerConfiguration, defaultExternalCDNConfig)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task
import UI.Glyph as Glyph



-- MODEL


type alias Model =
    { configEdit : Maybe CdnConfigEdit
    , copied : Maybe String
    , explainerOpen : Bool
    }


type Msg
    = CdnEditClicked
    | CdnEnabledToggled
    | CdnFrontendHostChanged String
    | CdnBackendHostChanged String
    | CdnCancelClicked
    | CdnSaveClicked
    | GotCdnSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | CopyClicked String
    | CopiedReset String
    | ExplainerToggled


{-| Live only while the CDN config is being edited by an admin -- `enabled` mirrors whether
`externalCdnConfig` itself should be `Just`/`Nothing` on save (see `applyCdnConfig`);
`frontendHost`/`backendHost` are only meaningful (and only enabled in `cdnEditView`) while `enabled`
is `True`. `secureMedia`/`mediaIpv4Allowlist`/`mediaIpv6Allowlist`/`cdnGrpc` aren't part of this
edit at all -- `applyCdnConfig` carries forward whatever a freshly re-fetched config already has for
them, untouched.
-}
type alias CdnConfigEdit =
    { enabled : Bool
    , frontendHost : String
    , backendHost : String
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { configEdit = Nothing, copied = Nothing, explainerOpen = False }



-- UPDATE


update : Shared.Model -> String -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost maybeServer msg model =
    case msg of
        CdnEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        cdnConfig : Maybe ExternalCDNConfig
                        cdnConfig =
                            (RellmServers.configurationOf server).externalCdnConfig
                    in
                    ( { model
                        | configEdit =
                            Just
                                { enabled = cdnConfig /= Nothing
                                , frontendHost = cdnConfig |> Maybe.map .frontendHost |> Maybe.withDefault ""
                                , backendHost = cdnConfig |> Maybe.map .backendHost |> Maybe.withDefault ""
                                , status = AccountsPanel.Idle
                                }
                      }
                    , Effect.none
                    )

                Nothing ->
                    ( model, Effect.none )

        CdnEnabledToggled ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        CdnFrontendHostChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | frontendHost = text }) }, Effect.none )

        CdnBackendHostChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | backendHost = text }) }, Effect.none )

        CdnCancelClicked ->
            ( { model | configEdit = Nothing }, Effect.none )

        CdnSaveClicked ->
            case ( model.configEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | configEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyCdnConfig edit)
                        |> Task.attempt GotCdnSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotCdnSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | configEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotCdnSaveResult (Err err) ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        CopyClicked text ->
            ( { model | copied = Just text }, DnsView.copyEffect CopiedReset text )

        CopiedReset text ->
            if model.copied == Just text then
                ( { model | copied = Nothing }, Effect.none )

            else
                ( model, Effect.none )

        ExplainerToggled ->
            ( { model | explainerOpen = not model.explainerOpen }, Effect.none )


{-| `CdnSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way every
other editor's transform is -- when `enabled` is off, nulls `externalCdnConfig` out entirely (that's
what the "External CDN HTTP Support" toggle means); when on, overlays `frontendHost`/`backendHost`
onto whatever a freshly re-fetched config already has for `externalCdnConfig`
(`defaultExternalCDNConfig` the first time it's ever set), leaving `secureMedia`/
`mediaIpv4Allowlist`/`mediaIpv6Allowlist`/`cdnGrpc` untouched.
-}
applyCdnConfig : CdnConfigEdit -> ServerConfiguration -> ServerConfiguration
applyCdnConfig edit config =
    if edit.enabled then
        let
            existing : ExternalCDNConfig
            existing =
                Maybe.withDefault defaultExternalCDNConfig config.externalCdnConfig
        in
        { config | externalCdnConfig = Just { existing | frontendHost = edit.frontendHost, backendHost = edit.backendHost } }

    else
        { config | externalCdnConfig = Nothing }



-- VIEW


view : RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view server maybeAdminAccount model =
    let
        cdnConfig : Maybe ExternalCDNConfig
        cdnConfig =
            (RellmServers.configurationOf server).externalCdnConfig
    in
    div [ class "server-details-tab-content server-details-cdn sc-root" ]
        (case model.configEdit of
            Just edit ->
                cdnEditView cdnConfig edit ++ [ dnsSetupView model (enteredHosts cdnConfig (Just edit)) ]

            Nothing ->
                cdnDisplayView maybeAdminAccount cdnConfig ++ [ dnsSetupView model (enteredHosts cdnConfig Nothing) ]
        )


{-| The hosts (and secure-media flag) the DNS setup card is written for: what's being typed while
editing (blank while the toggle is off), otherwise what's saved.
-}
enteredHosts : Maybe ExternalCDNConfig -> Maybe CdnConfigEdit -> { frontendHost : String, backendHost : String, secureMedia : Bool }
enteredHosts cdnConfig maybeEdit =
    let
        secureMedia : Bool
        secureMedia =
            cdnConfig |> Maybe.map .secureMedia |> Maybe.withDefault False
    in
    case maybeEdit of
        Just edit ->
            if edit.enabled then
                { frontendHost = edit.frontendHost, backendHost = edit.backendHost, secureMedia = secureMedia }

            else
                { frontendHost = "", backendHost = "", secureMedia = secureMedia }

        Nothing ->
            { frontendHost = cdnConfig |> Maybe.map .frontendHost |> Maybe.withDefault ""
            , backendHost = cdnConfig |> Maybe.map .backendHost |> Maybe.withDefault ""
            , secureMedia = secureMedia
            }


{-| The "DNS setup" card: a collapsible "How does this work?", gentle warnings, and the numbered steps
from `DnsSetup.plan`, each with a one-line why and copyable records/lines.
-}
dnsSetupView : Model -> { frontendHost : String, backendHost : String, secureMedia : Bool } -> Html Msg
dnsSetupView model entered =
    let
        plan : Plan
        plan =
            DnsSetup.plan entered
    in
    div [ class "dns-setup" ]
        [ h3 [ class "dns-setup-title" ] [ text "DNS setup" ]
        , p [ class "dns-setup-lead" ] [ text "Two DNS records make this work. Create them where each domain's DNS lives." ]
        , DnsView.explainer { title = "How does this work?", open = model.explainerOpen, onToggle = ExplainerToggled }
            [ p [] [ strong [] [ text "Frontend host " ], text "is the address people visit. Your CDN owns it and forwards visitors to Rellm." ]
            , p [] [ strong [] [ text "Backend host " ], text "is where Rellm really runs. Apps connect to it directly, not through the CDN." ]
            , p [] [ strong [] [ text "Discovery: " ], text "apps ask the frontend host at /backend_host which backend to use." ]
            ]
        , div [] (List.map (\warning -> div [ class "dns-warning" ] [ text warning ]) plan.warnings)
        , if plan.frontendIsExample || plan.backendIsExample then
            span [ class "dns-example" ] [ text "Example values -- enter your hosts above to fill these in." ]

          else
            text ""
        , div [] (List.indexedMap (stepView model) plan.steps)
        ]


stepView : Model -> Int -> Step -> Html Msg
stepView model index step =
    div [ class "dns-step" ]
        [ p [ class "dns-step-title" ]
            (span [ class "dns-step-num" ] [ text (String.fromInt (index + 1)) ]
                :: text step.title
                :: (case step.badge of
                        Just badge ->
                            [ span [ class "dns-badge" ] [ text badge ] ]

                        Nothing ->
                            []
                   )
            )
        , p [ class "dns-step-why" ] [ text step.why ]
        , div [] (List.map (DnsView.recordBlock CopyClicked model.copied Nothing) step.records)
        , div [] (List.map (DnsView.codeLine CopyClicked model.copied) step.codeLines)
        , case step.links of
            [] ->
                text ""

            links ->
                ul [ class "dns-links" ]
                    (List.map
                        (\( label, url ) ->
                            li [] [ a [ href url, target "_blank", rel "noopener noreferrer" ] [ text (label ++ " " ++ Glyph.externalLink) ] ]
                        )
                        links
                    )
        , case step.note of
            Just note ->
                p [ class "dns-step-note" ] [ text note ]

            Nothing ->
                text ""
        ]


cdnDisplayView : Maybe RellmAccount -> Maybe ExternalCDNConfig -> List (Html Msg)
cdnDisplayView maybeAdminAccount cdnConfig =
    [ Common.settingsRow "External CDN HTTP Support" (Common.switchDisplay (cdnConfig /= Nothing))
    , Common.settingsRow "Frontend Host" (span [ class "server-details-feature-settings-value" ] [ text (cdnConfig |> Maybe.map .frontendHost |> Maybe.withDefault "—") ])
    , Common.settingsRow "Backend Host" (span [ class "server-details-feature-settings-value" ] [ text (cdnConfig |> Maybe.map .backendHost |> Maybe.withDefault "—") ])
    , Common.settingsRow "External CDN gRPC Support" (Common.switchDisplay (cdnConfig |> Maybe.map .cdnGrpc |> Maybe.withDefault False))
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick CdnEditClicked ] [ text "Edit CDN Settings" ]

        Nothing ->
            text ""
    ]


{-| `frontendHost`/`backendHost` are only `disabled False` (editable) while `edit.enabled` is on --
turning the main toggle off is the "null the whole config out" action, so there's nothing useful to
type into them until it's back on. `cdnGrpc` stays a `Common.switchDisplay` even here -- it's not
part of `CdnConfigEdit` at all (see that type's own doc), so this always reads its value straight
off `cdnConfig` (the config as last fetched, not `edit`'s own pending state).
-}
cdnEditView : Maybe ExternalCDNConfig -> CdnConfigEdit -> List (Html Msg)
cdnEditView cdnConfig edit =
    [ Common.settingsRow "External CDN HTTP Support" (Common.flagSwitch edit.enabled CdnEnabledToggled)
    , Common.settingsRow "Frontend Host"
        (input
            [ class "server-details-rename-input"
            , placeholder "jonline.io"
            , value edit.frontendHost
            , onInput CdnFrontendHostChanged
            , disabled (not edit.enabled || edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Backend Host"
        (input
            [ class "server-details-rename-input"
            , placeholder "jonline.io.itsj.online"
            , value edit.backendHost
            , onInput CdnBackendHostChanged
            , disabled (not edit.enabled || edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "External CDN gRPC Support" (Common.switchDisplay (cdnConfig |> Maybe.map .cdnGrpc |> Maybe.withDefault False))
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton CdnSaveClicked edit.status
        , Common.editCancelButton CdnCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]
