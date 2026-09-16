module Components.Pages.ServerInformationPage.IntegrationsTab exposing (Model, Msg, activated, init, update, view)

{-| The Integrations tab of `Components.Pages.ServerInformationPage` -- Twilio (`TwilioConfig`),
Bird (`BirdConfig`, see that message's own doc in `server_configuration.proto` -- a cheaper Twilio
alternative for SMS verification), and Stripe (`StripeConfig`, Rellm's Market payment provider --
see `market.proto`), each editable by an admin as its own unit (a single Edit/Save/Cancel per
provider, mirroring `CdnTab`'s Edit/Save/Cancel shape), plus a "Preferred Verification Providers"
selector choosing which of Twilio/Bird is tried first when both are enabled
(`preferredVerificationApis`) -- Stripe has no such selector, since it's the only payment provider.

Unlike `CdnTab`, though, this tab **can't** just read `RellmServers.configurationOf server` for its
display -- `twilioConfig`/`birdConfig`/`preferredVerificationApis` are all admin-only-serialized
(see their own proto docs), stripped from the unauthenticated `GetServerConfiguration` probe
`RellmServers.configurationOf` reflects (the same one used for the initial "can we connect at all"
check and every reconnect). So, exactly like `ClusterTab` (`cluster_resources` is admin-only the
same way), this tab fires its own authenticated `GetServerConfiguration`
(`fetchAuthenticatedServerConfiguration`/`AdminIntegrationsStatus`) once an admin account is
present, and displays *that* instead, via the exposed `activated` message --
`Components.Pages.ServerInformationPage` dispatches it from every point its own connectivity state
could plausibly have changed (`TabSelected`, `GotOwnServerResult`'s success branch, `init`'s
already-known-connected branch, and every `SharedMsg`), via `activateIntegrationsTab`, since firing
it before the account's server connection has actually finished settling races ahead of it and
fails with a `Grpc.NetworkError` -- see `ClusterTab`'s own doc for the full "why so many call
sites" explanation, which applies here verbatim.

Unlike `CdnTab`'s "External CDN HTTP Support" toggle (which nulls `externalCdnConfig` out entirely
when off), each provider's "Enabled" toggle here only ever flips its own `*Enabled` field -- the
rest of the config (account identifiers, and whatever's currently stored for the write-only secret)
is left alone on disable, so re-enabling later doesn't lose the credentials that were already
entered. `twilioApiKeySecret`/`birdAccessKey` are write-only secrets -- `GetServerConfiguration`
always blanks them (mirroring `WebPushConfig.privateVapidKey`), so `*EditClicked` naturally seeds
the secret field blank with no special-casing, and each input's placeholder makes clear that
leaving it blank on Save keeps whatever's already stored.

The non-secret fields (`twilioAccountSid`/`twilioApiKeySid`/`twilioFromNumber`/`birdFrom`/
`birdRegion`) aren't secret
among admins (just not shown to non-admins, since `twilioConfig`/`bird_config` are themselves
admin-only-serialized -- see `ServerInformationPage`'s tab bar gating), so they're shown in plain
text even in the read-only display view, same as CDN's `frontendHost`/`backendHost`.

The Preferred Providers selector mirrors `SettingsTab`'s Permissions editor (removable badges + an
Add `<select>` + Save/Cancel) -- with only two possible values, "reordering" just means
remove-then-re-add at the end, same as that editor offers no drag-and-drop either.
-}

import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h3, input, option, select, span, text)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (BirdConfig, ServerConfiguration, StripeConfig, TwilioConfig, defaultBirdConfig, defaultStripeConfig, defaultTwilioConfig)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.VerificationAPI exposing (VerificationAPI(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers
import Task



-- MODEL


type alias Model =
    { configEdit : Maybe TwilioConfigEdit
    , birdConfigEdit : Maybe BirdConfigEdit
    , stripeConfigEdit : Maybe StripeConfigEdit
    , preferredProvidersEdit : Maybe PreferredProvidersEdit
    , adminIntegrations : AdminIntegrationsStatus
    }


{-| The result of this tab's own authenticated `GetServerConfiguration` fetch -- see this module's
own doc for why it can't just read `RellmServers.configurationOf server` like most other tabs.
Mirrors `ClusterTab.AdminClusterResourcesStatus` exactly, just holding the whole fetched
`ServerConfiguration` (since this tab needs three admin-only fields off of it --
`twilioConfig`/`birdConfig`/`preferredVerificationApis` -- rather than ClusterTab's one).
-}
type AdminIntegrationsStatus
    = AdminIntegrationsNotFetched
    | FetchingAdminIntegrations
    | AdminIntegrationsLoaded ServerConfiguration
    | AdminIntegrationsFetchFailed String


type Msg
    = TwilioEditClicked
    | TwilioEnabledToggled
    | TwilioAccountSidChanged String
    | TwilioApiKeySidChanged String
    | TwilioApiKeySecretChanged String
    | TwilioFromNumberChanged String
    | TwilioCancelClicked
    | TwilioSaveClicked
    | GotTwilioSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | BirdEditClicked
    | BirdEnabledToggled
    | BirdAccessKeyChanged String
    | BirdFromChanged String
    | BirdRegionChanged String
    | BirdCancelClicked
    | BirdSaveClicked
    | GotBirdSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | StripeEditClicked
    | StripeEnabledToggled
    | StripePublishableKeyChanged String
    | StripeSecretKeyChanged String
    | StripeWebhookSigningSecretChanged String
    | StripeCancelClicked
    | StripeSaveClicked
    | GotStripeSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | PreferredProvidersEditClicked
    | PreferredProviderRemoveClicked VerificationAPI
    | PreferredProviderAddSelectionChanged String
    | PreferredProviderAddClicked
    | PreferredProvidersCancelClicked
    | PreferredProvidersSaveClicked
    | GotPreferredProvidersSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | IntegrationsTabActivated
    | GotAuthenticatedServerConfiguration (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))


{-| Live only while the Twilio config is being edited by an admin. `apiKeySecret` always starts
blank (see module doc) -- leaving it blank on Save means "keep whatever's already stored" (the
backend splices the existing value back in when the incoming `twilio_api_key_secret` is empty,
mirroring `WebPushConfig.privateVapidKey`'s own merge rule). `accountSid`/`apiKeySid` are Twilio's
Account SID and API Key SID respectively -- see `TwilioConfig`'s own proto doc for why
authentication uses the API Key pair, never the account's own Auth Token.
-}
type alias TwilioConfigEdit =
    { enabled : Bool
    , accountSid : String
    , apiKeySid : String
    , apiKeySecret : String
    , fromNumber : String
    , status : AccountsPanel.FormStatus
    }


{-| Same as `TwilioConfigEdit`, but for Bird -- `accessKey` always starts blank the same way
`apiKeySecret` does.
-}
type alias BirdConfigEdit =
    { enabled : Bool
    , accessKey : String
    , from : String
    , region : String
    , status : AccountsPanel.FormStatus
    }


{-| Live only while the Stripe config is being edited by an admin. `secretKey`/`webhookSigningSecret`
always start blank (same "write-only, `Enter to change` placeholder" convention as
`TwilioConfigEdit.apiKeySecret`) -- both are blanked by the server's own `to_proto` (see
`StripeConfig`'s own proto doc). `publishableKey` is plain text (not secret), shown/edited normally.
-}
type alias StripeConfigEdit =
    { enabled : Bool
    , publishableKey : String
    , secretKey : String
    , webhookSigningSecret : String
    , status : AccountsPanel.FormStatus
    }


{-| Live only while `preferredVerificationApis` is being edited by an admin -- mirrors
`SettingsTab.PermissionsEdit` exactly, just over `VerificationAPI` instead of `Permission`.
`pending`'s order IS the preference order (see module doc).
-}
type alias PreferredProvidersEdit =
    { pending : List VerificationAPI
    , addSelection : Maybe VerificationAPI
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { configEdit = Nothing
    , birdConfigEdit = Nothing
    , stripeConfigEdit = Nothing
    , preferredProvidersEdit = Nothing
    , adminIntegrations = AdminIntegrationsNotFetched
    }


{-| `Components.Pages.ServerInformationPage` dispatches this (via `IntegrationsTab.update`)
whenever this tab becomes the active one -- on `TabSelected TabIntegrations`, and at every point
this page's own connectivity state could plausibly have changed (see module doc) -- to kick off the
authenticated fetch this module's own doc describes. `IntegrationsTabActivated`'s own constructor
isn't exposed (like every other `Msg` here), so this is the one blessed way a parent triggers it.
Mirrors `ClusterTab.activated` exactly.
-}
activated : Msg
activated =
    IntegrationsTabActivated


{-| `twilioConfig`/`birdConfig`/`preferredVerificationApis` off of `model.adminIntegrations`'s own
freshly-authenticated fetch (see module doc) -- `Nothing`/`[]` whenever that fetch hasn't completed
yet (or failed), same as `ClusterTab`'s own accessors.
-}
adminTwilioConfig : Model -> Maybe TwilioConfig
adminTwilioConfig model =
    case model.adminIntegrations of
        AdminIntegrationsLoaded config ->
            config.twilioConfig

        _ ->
            Nothing


adminBirdConfig : Model -> Maybe BirdConfig
adminBirdConfig model =
    case model.adminIntegrations of
        AdminIntegrationsLoaded config ->
            config.birdConfig

        _ ->
            Nothing


adminStripeConfig : Model -> Maybe StripeConfig
adminStripeConfig model =
    case model.adminIntegrations of
        AdminIntegrationsLoaded config ->
            config.stripeConfig

        _ ->
            Nothing


adminPreferredProviders : Model -> List VerificationAPI
adminPreferredProviders model =
    case model.adminIntegrations of
        AdminIntegrationsLoaded config ->
            config.preferredVerificationApis

        _ ->
            []



-- UPDATE


update : Shared.Model -> String -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost msg model =
    case msg of
        TwilioEditClicked ->
            let
                twilioConfig : Maybe TwilioConfig
                twilioConfig =
                    adminTwilioConfig model
            in
            ( { model
                | configEdit =
                    Just
                        { enabled = twilioConfig |> Maybe.map .twilioEnabled |> Maybe.withDefault False
                        , accountSid = twilioConfig |> Maybe.map .twilioAccountSid |> Maybe.withDefault ""
                        , apiKeySid = twilioConfig |> Maybe.map .twilioApiKeySid |> Maybe.withDefault ""
                        , apiKeySecret = ""
                        , fromNumber = twilioConfig |> Maybe.map .twilioFromNumber |> Maybe.withDefault ""
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        TwilioEnabledToggled ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        TwilioAccountSidChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | accountSid = text }) }, Effect.none )

        TwilioApiKeySidChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | apiKeySid = text }) }, Effect.none )

        TwilioApiKeySecretChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | apiKeySecret = text }) }, Effect.none )

        TwilioFromNumberChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | fromNumber = text }) }, Effect.none )

        TwilioCancelClicked ->
            ( { model | configEdit = Nothing }, Effect.none )

        TwilioSaveClicked ->
            case ( model.configEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | configEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyTwilioConfig edit)
                        |> Task.attempt GotTwilioSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotTwilioSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | configEdit = Nothing, adminIntegrations = AdminIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotTwilioSaveResult (Err err) ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        BirdEditClicked ->
            let
                birdConfig : Maybe BirdConfig
                birdConfig =
                    adminBirdConfig model
            in
            ( { model
                | birdConfigEdit =
                    Just
                        { enabled = birdConfig |> Maybe.map .birdEnabled |> Maybe.withDefault False
                        , accessKey = ""
                        , from = birdConfig |> Maybe.map .birdFrom |> Maybe.withDefault ""
                        , region = birdConfig |> Maybe.map .birdRegion |> Maybe.withDefault ""
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        BirdEnabledToggled ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        BirdAccessKeyChanged text ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | accessKey = text }) }, Effect.none )

        BirdFromChanged text ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | from = text }) }, Effect.none )

        BirdRegionChanged text ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | region = text }) }, Effect.none )

        BirdCancelClicked ->
            ( { model | birdConfigEdit = Nothing }, Effect.none )

        BirdSaveClicked ->
            case ( model.birdConfigEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | birdConfigEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyBirdConfig edit)
                        |> Task.attempt GotBirdSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotBirdSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | birdConfigEdit = Nothing, adminIntegrations = AdminIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotBirdSaveResult (Err err) ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

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
            ( { model | stripeConfigEdit = Nothing, adminIntegrations = AdminIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotStripeSaveResult (Err err) ->
            ( { model | stripeConfigEdit = model.stripeConfigEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        PreferredProvidersEditClicked ->
            let
                current : List VerificationAPI
                current =
                    adminPreferredProviders model
            in
            ( { model | preferredProvidersEdit = Just { pending = current, addSelection = resolveAddSelection Nothing current, status = AccountsPanel.Idle } }
            , Effect.none
            )

        PreferredProviderRemoveClicked provider ->
            ( { model
                | preferredProvidersEdit =
                    model.preferredProvidersEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    pending : List VerificationAPI
                                    pending =
                                        List.filter ((/=) provider) edit.pending
                                in
                                { edit | pending = pending, addSelection = resolveAddSelection edit.addSelection pending }
                            )
              }
            , Effect.none
            )

        PreferredProviderAddSelectionChanged text ->
            ( { model | preferredProvidersEdit = model.preferredProvidersEdit |> Maybe.map (\edit -> { edit | addSelection = verificationApiFromText text }) }
            , Effect.none
            )

        PreferredProviderAddClicked ->
            ( { model
                | preferredProvidersEdit =
                    model.preferredProvidersEdit
                        |> Maybe.map
                            (\edit ->
                                case edit.addSelection of
                                    Just provider ->
                                        let
                                            pending : List VerificationAPI
                                            pending =
                                                edit.pending ++ [ provider ]
                                        in
                                        { edit | pending = pending, addSelection = resolveAddSelection Nothing pending }

                                    Nothing ->
                                        edit
                            )
              }
            , Effect.none
            )

        PreferredProvidersCancelClicked ->
            ( { model | preferredProvidersEdit = Nothing }, Effect.none )

        PreferredProvidersSaveClicked ->
            case ( model.preferredProvidersEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | preferredProvidersEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts
                        ( Just account.userId, targetHost )
                        (\config -> { config | preferredVerificationApis = edit.pending })
                        |> Task.attempt GotPreferredProvidersSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPreferredProvidersSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | preferredProvidersEdit = Nothing, adminIntegrations = AdminIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotPreferredProvidersSaveResult (Err err) ->
            ( { model | preferredProvidersEdit = model.preferredProvidersEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        IntegrationsTabActivated ->
            case ( model.adminIntegrations, Common.adminAccountFor shared targetHost ) of
                ( AdminIntegrationsNotFetched, Just account ) ->
                    ( { model | adminIntegrations = FetchingAdminIntegrations }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                ( AdminIntegrationsFetchFailed _, Just account ) ->
                    ( { model | adminIntegrations = FetchingAdminIntegrations }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                _ ->
                    ( model, Effect.none )

        GotAuthenticatedServerConfiguration (Ok ( maybeAccountsPanelMsg, config )) ->
            ( { model | adminIntegrations = AdminIntegrationsLoaded config }
            , Common.accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAuthenticatedServerConfiguration (Err err) ->
            ( { model | adminIntegrations = AdminIntegrationsFetchFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )


{-| `cluster_resources`/`twilio_config`/`bird_config`/`preferred_verification_apis` are all
stripped from the unauthenticated `GetServerConfiguration` every other tab reads via
`RellmServers.configurationOf` (see module doc) -- this fetches it fresh, authenticated as
`account`, the same way `AccountsPanel.updateServerConfig` does before writing. Mirrors
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


{-| `TwilioSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way every
other editor's transform is. Unlike `CdnTab.applyCdnConfig` (which nulls `externalCdnConfig` out
entirely when its toggle is off), this never nulls `twilioConfig` out -- `twilioEnabled` is itself
the field that means "off," so disabling just flips that bool while `accountSid`/`apiKeySid`/
`fromNumber` (and whatever's stored for `apiKeySecret`, left untouched when `edit.apiKeySecret` is
blank) stay put, letting an admin flip Twilio off and back on without re-entering credentials.
-}
applyTwilioConfig : TwilioConfigEdit -> ServerConfiguration -> ServerConfiguration
applyTwilioConfig edit config =
    let
        existing : TwilioConfig
        existing =
            Maybe.withDefault defaultTwilioConfig config.twilioConfig
    in
    { config
        | twilioConfig =
            Just
                { existing
                    | twilioEnabled = edit.enabled
                    , twilioAccountSid = edit.accountSid
                    , twilioApiKeySid = edit.apiKeySid
                    , twilioApiKeySecret = edit.apiKeySecret
                    , twilioFromNumber = edit.fromNumber
                }
    }


{-| Same as `applyTwilioConfig`, but for Bird.
-}
applyBirdConfig : BirdConfigEdit -> ServerConfiguration -> ServerConfiguration
applyBirdConfig edit config =
    let
        existing : BirdConfig
        existing =
            Maybe.withDefault defaultBirdConfig config.birdConfig
    in
    { config
        | birdConfig =
            Just
                { existing
                    | birdEnabled = edit.enabled
                    , birdAccessKey = edit.accessKey
                    , birdFrom = edit.from
                    , birdRegion = edit.region
                }
    }


{-| Same as `applyTwilioConfig`, but for Stripe -- `secretKey`/`webhookSigningSecret` are sent as
typed (blank if left untouched), and the backend splices the existing stored value back in when
the incoming field is empty, same as `twilio_api_key_secret`. `publishableKey` is not secret, so
it's always applied straight across.
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


{-| Every `VerificationAPI` value, in a fixed display order -- used both for the Add dropdown's
full option list and (indirectly, via `addablePreferredProviders`) for what's left to add.
-}
allVerificationApis : List VerificationAPI
allVerificationApis =
    [ VERIFICATIONAPITWILIO, VERIFICATIONAPIBIRD ]


addablePreferredProviders : List VerificationAPI -> List VerificationAPI
addablePreferredProviders pending =
    List.filter (\api -> not (List.member api pending)) allVerificationApis


{-| The first still-addable provider, preferring to keep `current` selected if it's still
addable -- mirrors `SettingsTab.resolveAddSelection` exactly.
-}
resolveAddSelection : Maybe VerificationAPI -> List VerificationAPI -> Maybe VerificationAPI
resolveAddSelection current pending =
    let
        addable : List VerificationAPI
        addable =
            addablePreferredProviders pending
    in
    case current of
        Just api ->
            if List.member api addable then
                Just api

            else
                List.head addable

        Nothing ->
            List.head addable


verificationApiText : VerificationAPI -> String
verificationApiText api =
    case api of
        VERIFICATIONAPITWILIO ->
            "Twilio"

        VERIFICATIONAPIBIRD ->
            "Bird"

        VerificationAPIUnrecognized_ _ ->
            "Unknown"


verificationApiFromText : String -> Maybe VerificationAPI
verificationApiFromText text_ =
    allVerificationApis |> List.filter (\api -> verificationApiText api == text_) |> List.head



-- VIEW


view : Maybe RellmAccount -> Model -> Html Msg
view maybeAdminAccount model =
    div [ class "server-details-tab-content server-details-integrations" ]
        (case model.adminIntegrations of
            FetchingAdminIntegrations ->
                [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

            AdminIntegrationsNotFetched ->
                [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

            AdminIntegrationsFetchFailed err ->
                [ span [ class "server-details-feature-settings-value" ] [ text ("Failed to load integration settings: " ++ err) ] ]

            AdminIntegrationsLoaded _ ->
                [ div []
                    (case model.configEdit of
                        Just edit ->
                            twilioEditView edit

                        Nothing ->
                            twilioDisplayView maybeAdminAccount (adminTwilioConfig model)
                    )
                , div []
                    (case model.birdConfigEdit of
                        Just edit ->
                            birdEditView edit

                        Nothing ->
                            birdDisplayView maybeAdminAccount (adminBirdConfig model)
                    )
                , div []
                    (case model.stripeConfigEdit of
                        Just edit ->
                            stripeEditView edit

                        Nothing ->
                            stripeDisplayView maybeAdminAccount (adminStripeConfig model)
                    )
                , preferredProvidersSection maybeAdminAccount model.preferredProvidersEdit (adminPreferredProviders model)
                ]
        )


twilioDisplayView : Maybe RellmAccount -> Maybe TwilioConfig -> List (Html Msg)
twilioDisplayView maybeAdminAccount twilioConfig =
    [ h3 [ class "section-title" ] [ text "Twilio" ]
    , Common.settingsRow "Twilio Enabled" (Common.switchDisplay (twilioConfig |> Maybe.map .twilioEnabled |> Maybe.withDefault False))
    , Common.settingsRow "Account SID" (span [ class "server-details-feature-settings-value" ] [ text (twilioConfig |> Maybe.map .twilioAccountSid |> Maybe.withDefault "—") ])
    , Common.settingsRow "API Key SID" (span [ class "server-details-feature-settings-value" ] [ text (twilioConfig |> Maybe.map .twilioApiKeySid |> Maybe.withDefault "—") ])
    , Common.settingsRow "From Number" (span [ class "server-details-feature-settings-value" ] [ text (twilioConfig |> Maybe.map .twilioFromNumber |> Maybe.withDefault "—") ])
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick TwilioEditClicked ] [ text "Edit Twilio Settings" ]

        Nothing ->
            text ""
    ]


{-| Twilio's own IAM docs (https://www.twilio.com/docs/iam/api-keys/restricted-api-keys) recommend
creating a Restricted API Key scoped to just `/twilio/messaging/messages/create` for exactly this
use case, rather than using the account's own (unscoped) Auth Token -- see `TwilioConfig`'s own
proto doc for the full reasoning.
-}
twilioEditView : TwilioConfigEdit -> List (Html Msg)
twilioEditView edit =
    [ h3 [ class "section-title" ] [ text "Twilio" ]
    , Common.settingsRow "Twilio Enabled" (Common.flagSwitch edit.enabled TwilioEnabledToggled)
    , Common.settingsRow "Account SID"
        (input
            [ class "server-details-rename-input"
            , placeholder "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            , value edit.accountSid
            , onInput TwilioAccountSidChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "API Key SID"
        (input
            [ class "server-details-rename-input"
            , placeholder "SKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            , value edit.apiKeySid
            , onInput TwilioApiKeySidChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "API Key Secret"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change"
            , value edit.apiKeySecret
            , onInput TwilioApiKeySecretChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "From Number"
        (input
            [ class "server-details-rename-input"
            , placeholder "+15555550100"
            , value edit.fromNumber
            , onInput TwilioFromNumberChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton TwilioSaveClicked edit.status
        , Common.editCancelButton TwilioCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]


birdDisplayView : Maybe RellmAccount -> Maybe BirdConfig -> List (Html Msg)
birdDisplayView maybeAdminAccount birdConfig =
    [ h3 [ class "section-title" ] [ text "Bird" ]
    , Common.settingsRow "Bird Enabled" (Common.switchDisplay (birdConfig |> Maybe.map .birdEnabled |> Maybe.withDefault False))
    , Common.settingsRow "From" (span [ class "server-details-feature-settings-value" ] [ text (birdConfig |> Maybe.map .birdFrom |> Maybe.withDefault "—") ])
    , Common.settingsRow "Region" (span [ class "server-details-feature-settings-value" ] [ text (birdConfig |> Maybe.map .birdRegion |> Maybe.andThen emptyToNothing |> Maybe.withDefault "us1 (default)") ])
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick BirdEditClicked ] [ text "Edit Bird Settings" ]

        Nothing ->
            text ""
    ]


birdEditView : BirdConfigEdit -> List (Html Msg)
birdEditView edit =
    [ h3 [ class "section-title" ] [ text "Bird" ]
    , Common.settingsRow "Bird Enabled" (Common.flagSwitch edit.enabled BirdEnabledToggled)
    , Common.settingsRow "Access Key"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change"
            , value edit.accessKey
            , onInput BirdAccessKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "From"
        (input
            [ class "server-details-rename-input"
            , placeholder "Bird (or an owned number/short code)"
            , value edit.from
            , onInput BirdFromChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Region"
        (input
            [ class "server-details-rename-input"
            , placeholder "us1"
            , value edit.region
            , onInput BirdRegionChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton BirdSaveClicked edit.status
        , Common.editCancelButton BirdCancelClicked edit.status
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


{-| `secretKey`/`webhookSigningSecret` are the two write-only fields (`type_ "password"`,
`placeholder "Enter to change"`, always seeded blank -- see `StripeConfigEdit`'s own doc);
`publishableKey` is plain text.
-}
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


{-| The "Preferred Verification Providers" selector -- plain badges (plus an Edit button, for an
admin) when not being edited, or the removable-badges + Add Provider + Save/Cancel editor while
being edited. Mirrors `SettingsTab.permissionsSection` exactly (see module doc).
-}
preferredProvidersSection : Maybe RellmAccount -> Maybe PreferredProvidersEdit -> List VerificationAPI -> Html Msg
preferredProvidersSection maybeAdminAccount maybeEdit preferred =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-permissions server-details-permissions-edit" ]
                [ h3 [ class "section-title" ] [ text "Preferred Verification Providers" ]
                , div [ class "permission-badges" ] (edit.pending |> List.map preferredProviderEditBadge)
                , div [ class "server-details-permissions-add" ]
                    [ select [ onInput PreferredProviderAddSelectionChanged ]
                        (addablePreferredProviders edit.pending
                            |> List.map
                                (\api ->
                                    option
                                        [ value (verificationApiText api)
                                        , selected (edit.addSelection == Just api)
                                        ]
                                        [ text (verificationApiText api) ]
                                )
                        )
                    , button
                        [ class "server-details-rename-button"
                        , onClick PreferredProviderAddClicked
                        , disabled (edit.addSelection == Nothing || edit.status == AccountsPanel.Submitting)
                        ]
                        [ text "Add Provider" ]
                    ]
                , div [ class "server-details-permissions-actions" ]
                    [ Common.editSaveButton PreferredProvidersSaveClicked edit.status
                    , Common.editCancelButton PreferredProvidersCancelClicked edit.status
                    ]
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-permissions" ]
                [ h3 [ class "section-title" ] [ text "Preferred Verification Providers" ]
                , if List.isEmpty preferred then
                    Html.p [] [ text "None set -- falls back to whichever provider is enabled (Twilio first, then Bird)." ]

                  else
                    div [ class "permission-badges" ]
                        (preferred |> List.map (\api -> span [ class "permission-badge" ] [ text (verificationApiText api) ]))
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick PreferredProvidersEditClicked ] [ text "Edit Preferred Providers" ]

                    Nothing ->
                        text ""
                ]


preferredProviderEditBadge : VerificationAPI -> Html Msg
preferredProviderEditBadge api =
    span [ class "permission-badge editable" ]
        [ text (verificationApiText api)
        , button
            [ class "permission-remove"
            , onClick (PreferredProviderRemoveClicked api)
            , Html.Attributes.title ("Remove " ++ verificationApiText api)
            ]
            [ text "×" ]
        ]
