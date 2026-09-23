module Components.Pages.ServerInformationPage.MarketTab exposing (Model, Msg, activated, init, update, view)

{-| The Market tab of `Components.Pages.ServerInformationPage` -- Stripe (`StripeConfig`, the
payment processor credentials Rellm's Market checkout/webhook flow uses) and Market
(`MarketSettings.enabled`, the public "is Rellm's Market turned on for this server" toggle that
`Pages.Market`'s multi-server browsing reads off of every federated server). Split out of a single
"Integrations" tab (see `Components.Pages.ServerInformationPage.ContactIntegrationsTab` for the
other half, Twilio/Bird/Preferred Providers) once that combined tab grew unwieldy -- Stripe/Market
have nothing to do with Twilio/Bird beyond both once having lived in the same file.

Unlike `MarketSettings` (deliberately public -- see its own proto doc, and
`marshaling::configuration_marshaling::to_proto`'s explicit choice not to strip it for non-admins,
since federated Market browsing needs every server to expose at least this much), `StripeConfig` is
admin-only-serialized, stripped from the unauthenticated `GetServerConfiguration` probe
`RellmServers.configurationOf` reflects. So, exactly like `ClusterTab` (`cluster_resources` is
admin-only the same way) and `ContactIntegrationsTab` (`twilioConfig`/`birdConfig` likewise), this
tab fires its own authenticated `GetServerConfiguration`
(`fetchAuthenticatedServerConfiguration`/`AdminMarketStatus`) once an admin account is present, and
displays _both_ `stripeConfig` and `marketSettings` off of _that_ fetch, rather than only Stripe --
simplest to keep one fetch covering everything this tab itself needs, even though `marketSettings`
alone would already be visible via the public probe. `Components.Pages.ServerInformationPage.ContactIntegrationsTab`
does the exact same thing independently for its own three fields, with its own separate fetch --
the two tabs don't share this fetched `ServerConfiguration`, same as any other pair of admin tabs
in this app. `Components.Pages.ServerInformationPage` dispatches `activated` (via `MarketTab.update`)
from every point its own connectivity state could plausibly have changed (`TabSelected`,
`GotOwnServerResult`'s success branch, `init`'s already-known-connected branch, and every
`SharedMsg`), via `activateMarketTab` -- see `ClusterTab`'s own doc for the full "why so many call
sites" explanation, which applies here verbatim.

`stripeSecretKey`/`stripeWebhookSigningSecret` are write-only secrets -- `GetServerConfiguration`
always blanks them (mirroring `WebPushConfig.privateVapidKey`), so `StripeEditClicked` naturally
seeds each blank with no special-casing, and each input's placeholder makes clear that leaving it
blank on Save keeps whatever's already stored. `stripePublishableKey` isn't secret (it's meant to
be embedded in client-side JS by design, same as any Stripe integration), so it's shown in plain
text even in the read-only display view.

Market's "Enabled" toggle is the ONLY field on `MarketSettings` today -- unlike Stripe's Edit view,
there's nothing else to seed, so `MarketEditClicked` only ever needs the current `enabled` value.
Turning Market off here doesn't touch `StripeConfig` at all (they're independent switches -- see
`MarketSettings`'s own proto doc) -- an admin could enable Stripe but leave Market off (mid-setup),
or leave Stripe fully unconfigured while Market is nominally "on" (misconfigured, but that's caught
at actual purchase time, not here).

-}

import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h3, input, span, text)
import Html.Attributes exposing (class, disabled, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (MarketSettings, ServerConfiguration, StripeConfig, defaultMarketSettings, defaultStripeConfig)
import Proto.Rellm.Rellm as Rellm
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers
import Task



-- MODEL


type alias Model =
    { stripeConfigEdit : Maybe StripeConfigEdit
    , marketSettingsEdit : Maybe MarketSettingsEdit
    , adminMarket : AdminMarketStatus
    }


{-| The result of this tab's own authenticated `GetServerConfiguration` fetch -- see this module's
own doc for why it can't just read `RellmServers.configurationOf server` for `stripeConfig`.
Mirrors `ClusterTab.AdminClusterResourcesStatus` exactly, just holding the whole fetched
`ServerConfiguration` (since this tab needs both `stripeConfig` and `marketSettings` off of it).
-}
type AdminMarketStatus
    = AdminMarketNotFetched
    | FetchingAdminMarket
    | AdminMarketLoaded ServerConfiguration
    | AdminMarketFetchFailed String


type Msg
    = StripeEditClicked
    | StripeEnabledToggled
    | StripePublishableKeyChanged String
    | StripeSecretKeyChanged String
    | StripeWebhookSigningSecretChanged String
    | StripeCancelClicked
    | StripeSaveClicked
    | GotStripeSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | MarketEditClicked
    | MarketEnabledToggled
    | MarketCancelClicked
    | MarketSaveClicked
    | GotMarketSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | MarketTabActivated
    | GotAuthenticatedServerConfiguration (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))


{-| Live only while the Stripe config is being edited by an admin. `secretKey`/
`webhookSigningSecret` always start blank (see module doc) -- leaving either blank on Save means
"keep whatever's already stored" (the backend splices the existing value back in when the incoming
field is empty, mirroring `WebPushConfig.privateVapidKey`'s own merge rule).
-}
type alias StripeConfigEdit =
    { enabled : Bool
    , publishableKey : String
    , secretKey : String
    , webhookSigningSecret : String
    , status : AccountsPanel.FormStatus
    }


{-| Live only while `marketSettings.enabled` is being edited by an admin.
-}
type alias MarketSettingsEdit =
    { enabled : Bool
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { stripeConfigEdit = Nothing
    , marketSettingsEdit = Nothing
    , adminMarket = AdminMarketNotFetched
    }


{-| `Components.Pages.ServerInformationPage` dispatches this (via `MarketTab.update`) whenever this
tab becomes the active one -- on `TabSelected TabMarket`, and at every point this page's own
connectivity state could plausibly have changed (see module doc) -- to kick off the authenticated
fetch this module's own doc describes. `MarketTabActivated`'s own constructor isn't exposed (like
every other `Msg` here), so this is the one blessed way a parent triggers it. Mirrors
`ClusterTab.activated` exactly.
-}
activated : Msg
activated =
    MarketTabActivated


adminStripeConfig : Model -> Maybe StripeConfig
adminStripeConfig model =
    case model.adminMarket of
        AdminMarketLoaded config ->
            config.stripeConfig

        _ ->
            Nothing


adminMarketSettings : Model -> Maybe MarketSettings
adminMarketSettings model =
    case model.adminMarket of
        AdminMarketLoaded config ->
            config.marketSettings

        _ ->
            Nothing



-- UPDATE


update : Shared.Model -> String -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost msg model =
    case msg of
        StripeEditClicked ->
            let
                stripeConfig : Maybe StripeConfig
                stripeConfig =
                    adminStripeConfig model
            in
            ( { model
                | stripeConfigEdit =
                    Just
                        { enabled = stripeConfig |> Maybe.map .stripeEnabled |> Maybe.withDefault False
                        , publishableKey = stripeConfig |> Maybe.map .stripePublishableKey |> Maybe.withDefault ""
                        , secretKey = ""
                        , webhookSigningSecret = ""
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        StripeEnabledToggled ->
            ( { model | stripeConfigEdit = model.stripeConfigEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        StripePublishableKeyChanged text ->
            ( { model | stripeConfigEdit = model.stripeConfigEdit |> Maybe.map (\edit -> { edit | publishableKey = text }) }, Effect.none )

        StripeSecretKeyChanged text ->
            ( { model | stripeConfigEdit = model.stripeConfigEdit |> Maybe.map (\edit -> { edit | secretKey = text }) }, Effect.none )

        StripeWebhookSigningSecretChanged text ->
            ( { model | stripeConfigEdit = model.stripeConfigEdit |> Maybe.map (\edit -> { edit | webhookSigningSecret = text }) }, Effect.none )

        StripeCancelClicked ->
            ( { model | stripeConfigEdit = Nothing }, Effect.none )

        StripeSaveClicked ->
            case ( model.stripeConfigEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | stripeConfigEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyStripeConfig edit)
                        |> Task.attempt GotStripeSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotStripeSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | stripeConfigEdit = Nothing, adminMarket = AdminMarketLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotStripeSaveResult (Err err) ->
            ( { model | stripeConfigEdit = model.stripeConfigEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        MarketEditClicked ->
            let
                marketSettings : Maybe MarketSettings
                marketSettings =
                    adminMarketSettings model
            in
            ( { model
                | marketSettingsEdit =
                    Just
                        { enabled = marketSettings |> Maybe.map .enabled |> Maybe.withDefault False
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        MarketEnabledToggled ->
            ( { model | marketSettingsEdit = model.marketSettingsEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        MarketCancelClicked ->
            ( { model | marketSettingsEdit = Nothing }, Effect.none )

        MarketSaveClicked ->
            case ( model.marketSettingsEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | marketSettingsEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyMarketSettings edit)
                        |> Task.attempt GotMarketSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotMarketSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | marketSettingsEdit = Nothing, adminMarket = AdminMarketLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotMarketSaveResult (Err err) ->
            ( { model | marketSettingsEdit = model.marketSettingsEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        MarketTabActivated ->
            case ( model.adminMarket, Common.adminAccountFor shared targetHost ) of
                ( AdminMarketNotFetched, Just account ) ->
                    ( { model | adminMarket = FetchingAdminMarket }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                ( AdminMarketFetchFailed _, Just account ) ->
                    ( { model | adminMarket = FetchingAdminMarket }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                _ ->
                    ( model, Effect.none )

        GotAuthenticatedServerConfiguration (Ok ( maybeAccountsPanelMsg, config )) ->
            ( { model | adminMarket = AdminMarketLoaded config }
            , Common.accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAuthenticatedServerConfiguration (Err err) ->
            ( { model | adminMarket = AdminMarketFetchFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )


{-| `stripe_config`/`market_settings` off of the unauthenticated `GetServerConfiguration` every
other tab reads via `RellmServers.configurationOf` are, respectively, stripped and public (see
module doc) -- this fetches both fresh, authenticated as `account`, the same way
`AccountsPanel.updateServerConfig` does before writing. Mirrors
`ClusterTab.fetchAuthenticatedServerConfiguration` exactly.
-}
fetchAuthenticatedServerConfiguration : Shared.Model -> String -> RellmAccount -> Effect Msg
fetchAuthenticatedServerConfiguration shared targetHost account =
    AccountsPanel.performWithAccountServer shared.accounts
        ( Just account.userId, targetHost )
        (\server token ->
            Grpc.new Rellm.getServerConfiguration {}
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> RellmServers.withAccessToken (Just token)
                |> Grpc.toTask
        )
        |> Task.attempt GotAuthenticatedServerConfiguration
        |> Effect.fromCmd


{-| `StripeSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way
every other editor's transform is. Never nulls `stripeConfig` out -- `stripeEnabled` is itself the
field that means "off," so disabling just flips that bool while `publishableKey` (and whatever's
stored for `secretKey`/`webhookSigningSecret`, left untouched when the edit's own field is blank)
stay put, letting an admin flip Stripe off and back on without re-entering credentials.
-}
applyStripeConfig : StripeConfigEdit -> ServerConfiguration -> ServerConfiguration
applyStripeConfig edit config =
    let
        existing : StripeConfig
        existing =
            Maybe.withDefault defaultStripeConfig config.stripeConfig
    in
    { config
        | stripeConfig =
            Just
                { existing
                    | stripeEnabled = edit.enabled
                    , stripePublishableKey = edit.publishableKey
                    , stripeSecretKey = edit.secretKey
                    , stripeWebhookSigningSecret = edit.webhookSigningSecret
                }
    }


applyMarketSettings : MarketSettingsEdit -> ServerConfiguration -> ServerConfiguration
applyMarketSettings edit config =
    let
        existing : MarketSettings
        existing =
            Maybe.withDefault defaultMarketSettings config.marketSettings
    in
    { config | marketSettings = Just { existing | enabled = edit.enabled } }



-- VIEW


view : Maybe RellmAccount -> Model -> Html Msg
view maybeAdminAccount model =
    div [ class "server-details-tab-content server-details-integrations" ]
        (case model.adminMarket of
            FetchingAdminMarket ->
                [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

            AdminMarketNotFetched ->
                [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

            AdminMarketFetchFailed err ->
                [ span [ class "server-details-feature-settings-value" ] [ text ("Failed to load Market settings: " ++ err) ] ]

            AdminMarketLoaded _ ->
                [ div []
                    (case model.marketSettingsEdit of
                        Just edit ->
                            marketEditView edit

                        Nothing ->
                            marketDisplayView maybeAdminAccount (adminMarketSettings model)
                    )
                , div []
                    (case model.stripeConfigEdit of
                        Just edit ->
                            stripeEditView edit

                        Nothing ->
                            stripeDisplayView maybeAdminAccount (adminStripeConfig model)
                    )
                ]
        )


marketDisplayView : Maybe RellmAccount -> Maybe MarketSettings -> List (Html Msg)
marketDisplayView maybeAdminAccount marketSettings =
    [ h3 [ class "section-title" ] [ text "Market" ]
    , Common.settingsRow "Market Enabled" (Common.switchDisplay (marketSettings |> Maybe.map .enabled |> Maybe.withDefault False))
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick MarketEditClicked ] [ text "Edit Market Settings" ]

        Nothing ->
            text ""
    ]


marketEditView : MarketSettingsEdit -> List (Html Msg)
marketEditView edit =
    [ h3 [ class "section-title" ] [ text "Market" ]
    , Common.settingsRow "Market Enabled" (Common.flagSwitch edit.enabled MarketEnabledToggled)
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton MarketSaveClicked edit.status
        , Common.editCancelButton MarketCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]


stripeDisplayView : Maybe RellmAccount -> Maybe StripeConfig -> List (Html Msg)
stripeDisplayView maybeAdminAccount stripeConfig =
    [ h3 [ class "section-title" ] [ text "Stripe" ]
    , Common.settingsRow "Stripe Enabled" (Common.switchDisplay (stripeConfig |> Maybe.map .stripeEnabled |> Maybe.withDefault False))
    , Common.settingsRow "Publishable Key" (span [ class "server-details-feature-settings-value" ] [ text (stripeConfig |> Maybe.map .stripePublishableKey |> Maybe.andThen emptyToNothing |> Maybe.withDefault "—") ])
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick StripeEditClicked ] [ text "Edit Stripe Settings" ]

        Nothing ->
            text ""
    ]


stripeEditView : StripeConfigEdit -> List (Html Msg)
stripeEditView edit =
    [ h3 [ class "section-title" ] [ text "Stripe" ]
    , Common.settingsRow "Stripe Enabled" (Common.flagSwitch edit.enabled StripeEnabledToggled)
    , Common.settingsRow "Publishable Key"
        (input
            [ class "server-details-rename-input"
            , placeholder "pk_live_xxxxxxxxxxxxxxxxxxxxxxxx"
            , value edit.publishableKey
            , onInput StripePublishableKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Secret Key"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change"
            , value edit.secretKey
            , onInput StripeSecretKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Webhook Signing Secret"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change"
            , value edit.webhookSigningSecret
            , onInput StripeWebhookSigningSecretChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton StripeSaveClicked edit.status
        , Common.editCancelButton StripeCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]


emptyToNothing : String -> Maybe String
emptyToNothing str =
    if String.isEmpty str then
        Nothing

    else
        Just str
