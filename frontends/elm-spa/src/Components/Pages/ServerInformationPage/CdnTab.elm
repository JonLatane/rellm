module Components.Pages.ServerInformationPage.CdnTab exposing (Model, Msg, init, update, view)

{-| The CDN tab of `Components.Pages.ServerInformationPage` -- `ExternalCDNConfig` (see that
message's own doc in `server_configuration.proto`), editable by an admin as one unit (a single
Edit/Save/Cancel, like every other section on this page), with two exceptions: `secureMedia` and
`mediaIpv4Allowlist`/`mediaIpv6Allowlist` aren't shown at all yet (still `(TODO)` on the backend --
see the proto doc), and `cdnGrpc` is shown but always read-only (also still `(TODO)` there).

The "External CDN HTTP Support" toggle is what sets/nulls out `externalCdnConfig` on the
`ServerConfiguration` entirely (see `applyCdnConfig`) -- "Frontend Host"/"Backend Host" are only
meaningful (and only enabled in the UI) while it's on.

-}

import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (class, disabled, placeholder, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (ExternalCDNConfig, ServerConfiguration, defaultExternalCDNConfig)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task



-- MODEL


type alias Model =
    { configEdit : Maybe CdnConfigEdit
    }


type Msg
    = CdnEditClicked
    | CdnEnabledToggled
    | CdnFrontendHostChanged String
    | CdnBackendHostChanged String
    | CdnCancelClicked
    | CdnSaveClicked
    | GotCdnSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))


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
    { configEdit = Nothing }



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
    div [ class "server-details-tab-content server-details-cdn" ]
        (case model.configEdit of
            Just edit ->
                cdnEditView cdnConfig edit

            Nothing ->
                cdnDisplayView maybeAdminAccount cdnConfig
        )


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
