module Components.Pages.ServerInformationPage.ContactIntegrationsTab exposing (Model, Msg, activated, init, update, view)

{-| The Contact Integrations tab of `Components.Pages.ServerInformationPage` -- Telnyx
(`TelnyxConfig`), Twilio (`TwilioConfig`), and Bird (`BirdConfig`, see that message's own doc in
`server_configuration.proto` -- a cheaper Twilio alternative for SMS verification), each editable
by an admin as its own unit (a single Edit/Save/Cancel per provider, mirroring `CdnTab`'s
Edit/Save/Cancel shape), plus a "Preferred Verification Providers" selector choosing which of
Telnyx/Twilio/Bird is tried first when more than one is enabled (`preferredVerificationApis`).
Split out of a single "Integrations" tab (see `Components.Pages.ServerInformationPage.MarketTab`
for the other half, Stripe/Market) once that combined tab grew unwieldy -- these two provider
groups have nothing to do with each other beyond both once having lived in the same file.

Unlike `CdnTab`, though, this tab **can't** just read `RellmServers.configurationOf server` for its
display -- `telnyxConfig`/`twilioConfig`/`birdConfig`/`preferredVerificationApis` are all
admin-only-serialized (see their own proto docs), stripped from the unauthenticated `GetServerConfiguration` probe
`RellmServers.configurationOf` reflects (the same one used for the initial "can we connect at all"
check and every reconnect). So, exactly like `ClusterTab` (`cluster_resources` is admin-only the
same way), this tab fires its own authenticated `GetServerConfiguration`
(`fetchAuthenticatedServerConfiguration`/`AdminContactIntegrationsStatus`) once an admin account is
present, and displays *that* instead, via the exposed `activated` message --
`Components.Pages.ServerInformationPage` dispatches it from every point its own connectivity state
could plausibly have changed (`TabSelected`, `GotOwnServerResult`'s success branch, `init`'s
already-known-connected branch, and every `SharedMsg`), via `activateContactIntegrationsTab`, since
firing it before the account's server connection has actually finished settling races ahead of it
and fails with a `Grpc.NetworkError` -- see `ClusterTab`'s own doc for the full "why so many call
sites" explanation, which applies here verbatim. `Components.Pages.ServerInformationPage.MarketTab`
does the exact same thing independently, with its own separate fetch -- the two tabs don't share
this fetched `ServerConfiguration`, same as any other pair of admin tabs in this app.

Unlike `CdnTab`'s "External CDN HTTP Support" toggle (which nulls `externalCdnConfig` out entirely
when off), each provider's "Enabled" toggle here only ever flips its own `*Enabled` field -- the
rest of the config (account identifiers, and whatever's currently stored for the write-only secret)
is left alone on disable, so re-enabling later doesn't lose the credentials that were already
entered. `telnyxApiKey`/`twilioApiKeySecret`/`birdAccessKey` are write-only secrets --
`GetServerConfiguration` always blanks them (mirroring `WebPushConfig.privateVapidKey`), so
`*EditClicked` naturally seeds the secret field blank with no special-casing, and each input's
placeholder makes clear that leaving it blank on Save keeps whatever's already stored.

The non-secret fields (`telnyxFromNumber`/`telnyxMessagingProfileId`/`twilioAccountSid`/
`twilioApiKeySid`/`twilioFromNumber`/`birdFrom`/`birdRegion`) aren't secret among admins (just not
shown to non-admins, since `telnyxConfig`/`twilioConfig`/`bird_config` are themselves
admin-only-serialized -- see `ServerInformationPage`'s tab bar gating), so they're shown in plain
text even in the read-only display view, same as CDN's `frontendHost`/`backendHost`.

The Preferred Providers selector mirrors `SettingsTab`'s Permissions editor (removable badges + an
Add `<select>` + Save/Cancel) -- "reordering" just means remove-then-re-add at the end, same as
that editor offers no drag-and-drop either.

Also hosts the Web Push VAPID public/private key editor (`WebPushConfig`) -- moved here from
`FederationTab` purely for topical consistency (it's another "contact/notification-delivery
credential" alongside Telnyx/Twilio/Bird, not because it shares their admin-only-stripped
visibility). Unlike Telnyx/Twilio/Bird/Preferred Providers, `webPushConfig` is NOT stripped from
the unauthenticated `GetServerConfiguration` probe (only `privateVapidKey` itself is always
blanked, mirroring `FacebookAuthConfig.appSecret`) -- so its display reads straight off
`RellmServers.configurationOf server` (the `server` this module's own `update`/`view` now take,
exactly like `FederationTab` already does for its own similarly-public Facebook/X (Twitter)
fields), independent of `adminContactIntegrations`'s own fetch.

Preferred Providers/Telnyx/Twilio/Bird are grouped under a collapsible "External Integrations"
section (`externalIntegrationsSection`), with Telnyx, Twilio, and Bird each *also* independently
collapsible inside it (`telnyxSection`/`twilioSection`/`birdSection`) -- four nested levels of the
same `expandable-section-title`/`-arrow`/`-content` idiom
`SettingsTab.featureSettingsSection`/`UserProfilePage.expandableProfileSection` already establish
(see `collapsedIntegrationsSections`, a `Set String` exactly like
`SettingsTab.Model.collapsedFeatureSettings`). `telnyxSection` is rendered above `twilioSection`
(newest provider first, since it's the one currently being onboarded), and everything starts
expanded except Bird (the least commonly configured of the three SMS providers -- see
`BirdConfig`'s own proto doc). Since
`ServerInformationPage.view` mounts each tab's content under a *different* `Html.Keyed` key per tab
(`tabParam model.activeTab`), switching away from and back to this tab always tears down and
rebuilds this whole subtree from scratch (never patches it in place) -- so a freshly-collapsed
Bird section (or a freshly-toggled anything) always mounts already in its final CSS state, with no
"is-open" -> "is-closed" class flip for the browser to animate; the `grid-template-rows` transition
`profiles.css` defines only ever fires from a live *click* while this tab stays active, never from
a tab switch. This only holds because each collapsible section's own wrapper node stays at a fixed
position in its parent's child list across every state this module renders (Loading/Failed/Loaded,
display/edit) -- if one were ever conditionally omitted instead of always-mounted-but-collapsed,
Elm's positional diffing could reuse a DOM node meant for a different section and misfire a
transition; every section here follows the established "always mounted, CSS-driven" convention
specifically to avoid that.
-}

import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h2, h3, input, option, select, span, text)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (BirdConfig, ServerConfiguration, TelnyxConfig, TwilioConfig, defaultBirdConfig, defaultTelnyxConfig, defaultTwilioConfig)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.VerificationAPI exposing (VerificationAPI(..))
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task
import UI.Classes exposing (classes, openClosedClass)



-- MODEL


type alias Model =
    { configEdit : Maybe TwilioConfigEdit
    , birdConfigEdit : Maybe BirdConfigEdit
    , telnyxConfigEdit : Maybe TelnyxConfigEdit
    , preferredProvidersEdit : Maybe PreferredProvidersEdit
    , webPushPublicKeyEdit : Maybe TextFieldEdit
    , webPushPrivateKeyEdit : Maybe TextFieldEdit
    , adminContactIntegrations : AdminContactIntegrationsStatus
    , collapsedIntegrationsSections : Set String
    }


{-| The three nested collapsible sections `view` builds under "External Integrations" --
`ExternalIntegrationsSection` is the outer wrapper (Preferred Providers/Twilio/Bird all live
inside it), `TwilioIntegrationSection`/`BirdIntegrationSection` are each provider's own nested
collapsible. See `Model.collapsedIntegrationsSections` and this module's own doc for why nesting
this is safe against `ServerInformationPage`'s per-tab `Html.Keyed` remounting.
-}
type IntegrationsSection
    = ExternalIntegrationsSection
    | TelnyxIntegrationSection
    | TwilioIntegrationSection
    | BirdIntegrationSection


{-| The `collapsedIntegrationsSections` key each `IntegrationsSection` stores itself under --
distinct from its own display label the same way `SettingsTab.featureSettingsKey` is.
-}
integrationsSectionKey : IntegrationsSection -> String
integrationsSectionKey section =
    case section of
        ExternalIntegrationsSection ->
            "external"

        TelnyxIntegrationSection ->
            "telnyx"

        TwilioIntegrationSection ->
            "twilio"

        BirdIntegrationSection ->
            "bird"


integrationsSectionExpanded : Model -> IntegrationsSection -> Bool
integrationsSectionExpanded model section =
    not (Set.member (integrationsSectionKey section) model.collapsedIntegrationsSections)


{-| Toggles a single `Set` member -- mirrors `SettingsTab.toggleSetMember` exactly.
-}
toggleSetMember : comparable -> Set comparable -> Set comparable
toggleSetMember key set =
    if Set.member key set then
        Set.remove key set

    else
        Set.insert key set


{-| The result of this tab's own authenticated `GetServerConfiguration` fetch -- see this module's
own doc for why it can't just read `RellmServers.configurationOf server` like most other tabs.
Mirrors `ClusterTab.AdminClusterResourcesStatus` exactly, just holding the whole fetched
`ServerConfiguration` (since this tab needs three admin-only fields off of it --
`twilioConfig`/`birdConfig`/`preferredVerificationApis` -- rather than ClusterTab's one).
-}
type AdminContactIntegrationsStatus
    = AdminContactIntegrationsNotFetched
    | FetchingAdminContactIntegrations
    | AdminContactIntegrationsLoaded ServerConfiguration
    | AdminContactIntegrationsFetchFailed String


type Msg
    = TelnyxEditClicked
    | TelnyxEnabledToggled
    | TelnyxApiKeyChanged String
    | TelnyxFromNumberChanged String
    | TelnyxMessagingProfileIdChanged String
    | TelnyxCancelClicked
    | TelnyxSaveClicked
    | GotTelnyxSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | TwilioEditClicked
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
    | PreferredProvidersEditClicked
    | PreferredProviderRemoveClicked VerificationAPI
    | PreferredProviderAddSelectionChanged String
    | PreferredProviderAddClicked
    | PreferredProvidersCancelClicked
    | PreferredProvidersSaveClicked
    | GotPreferredProvidersSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | WebPushPublicKeyEditClicked
    | WebPushPublicKeyChanged String
    | WebPushPublicKeyCancelClicked
    | WebPushPublicKeySaveClicked
    | GotWebPushPublicKeySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | WebPushPrivateKeyEditClicked
    | WebPushPrivateKeyChanged String
    | WebPushPrivateKeyCancelClicked
    | WebPushPrivateKeySaveClicked
    | GotWebPushPrivateKeySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | ContactIntegrationsTabActivated
    | GotAuthenticatedServerConfiguration (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | IntegrationsSectionToggled IntegrationsSection


{-| Live only while the Telnyx config is being edited by an admin. `apiKey` always starts blank
(see module doc) -- leaving it blank on Save means "keep whatever's already stored" (the backend
splices the existing value back in when the incoming `telnyx_api_key` is empty, mirroring
`WebPushConfig.privateVapidKey`'s own merge rule). `fromNumber`/`messagingProfileId` are Telnyx's
sending number and the Messaging Profile ID it's assigned to -- see `TelnyxConfig`'s own proto doc.
-}
type alias TelnyxConfigEdit =
    { enabled : Bool
    , apiKey : String
    , fromNumber : String
    , messagingProfileId : String
    , status : AccountsPanel.FormStatus
    }


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


{-| Live only while `preferredVerificationApis` is being edited by an admin -- mirrors
`SettingsTab.PermissionsEdit` exactly, just over `VerificationAPI` instead of `Permission`.
`pending`'s order IS the preference order (see module doc).
-}
type alias PreferredProvidersEdit =
    { pending : List VerificationAPI
    , addSelection : Maybe VerificationAPI
    , status : AccountsPanel.FormStatus
    }


{-| Live only while the Web Push public or private VAPID key is being edited by an admin --
`pending` is the in-progress `<input>` value. The private key always starts this at `""` (never
pre-filled), since it's never actually sent back by the server (see `ToProtoServerConfiguration` on
the backend) -- saving with `pending == ""` is a deliberate no-op there (leaves whatever's already
stored alone), same as leaving a "change password" field blank. The public key isn't secret, so its
own edit starts pre-filled with the current value instead.
-}
type alias TextFieldEdit =
    { pending : String
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { configEdit = Nothing
    , birdConfigEdit = Nothing
    , telnyxConfigEdit = Nothing
    , preferredProvidersEdit = Nothing
    , webPushPublicKeyEdit = Nothing
    , webPushPrivateKeyEdit = Nothing
    , adminContactIntegrations = AdminContactIntegrationsNotFetched
    , collapsedIntegrationsSections = Set.singleton (integrationsSectionKey BirdIntegrationSection)
    }


{-| `Components.Pages.ServerInformationPage` dispatches this (via `ContactIntegrationsTab.update`)
whenever this tab becomes the active one -- on `TabSelected TabContactIntegrations`, and at every
point this page's own connectivity state could plausibly have changed (see module doc) -- to kick
off the authenticated fetch this module's own doc describes. `ContactIntegrationsTabActivated`'s
own constructor isn't exposed (like every other `Msg` here), so this is the one blessed way a
parent triggers it. Mirrors `ClusterTab.activated` exactly.
-}
activated : Msg
activated =
    ContactIntegrationsTabActivated


{-| `telnyxConfig`/`twilioConfig`/`birdConfig`/`preferredVerificationApis` off of
`model.adminContactIntegrations`'s own freshly-authenticated fetch (see module doc) -- `Nothing`/`[]`
whenever that fetch hasn't completed yet (or failed), same as `ClusterTab`'s own accessors.
-}
adminTelnyxConfig : Model -> Maybe TelnyxConfig
adminTelnyxConfig model =
    case model.adminContactIntegrations of
        AdminContactIntegrationsLoaded config ->
            config.telnyxConfig

        _ ->
            Nothing


adminTwilioConfig : Model -> Maybe TwilioConfig
adminTwilioConfig model =
    case model.adminContactIntegrations of
        AdminContactIntegrationsLoaded config ->
            config.twilioConfig

        _ ->
            Nothing


adminBirdConfig : Model -> Maybe BirdConfig
adminBirdConfig model =
    case model.adminContactIntegrations of
        AdminContactIntegrationsLoaded config ->
            config.birdConfig

        _ ->
            Nothing


adminPreferredProviders : Model -> List VerificationAPI
adminPreferredProviders model =
    case model.adminContactIntegrations of
        AdminContactIntegrationsLoaded config ->
            config.preferredVerificationApis

        _ ->
            []



-- UPDATE


update : Shared.Model -> String -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost maybeServer msg model =
    case msg of
        TelnyxEditClicked ->
            let
                telnyxConfig : Maybe TelnyxConfig
                telnyxConfig =
                    adminTelnyxConfig model
            in
            ( { model
                | telnyxConfigEdit =
                    Just
                        { enabled = telnyxConfig |> Maybe.map .telnyxEnabled |> Maybe.withDefault False
                        , apiKey = ""
                        , fromNumber = telnyxConfig |> Maybe.map .telnyxFromNumber |> Maybe.withDefault ""
                        , messagingProfileId = telnyxConfig |> Maybe.map .telnyxMessagingProfileId |> Maybe.withDefault ""
                        , status = AccountsPanel.Idle
                        }
              }
            , Effect.none
            )

        TelnyxEnabledToggled ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | enabled = not edit.enabled }) }, Effect.none )

        TelnyxApiKeyChanged text ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | apiKey = text }) }, Effect.none )

        TelnyxFromNumberChanged text ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | fromNumber = text }) }, Effect.none )

        TelnyxMessagingProfileIdChanged text ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | messagingProfileId = text }) }, Effect.none )

        TelnyxCancelClicked ->
            ( { model | telnyxConfigEdit = Nothing }, Effect.none )

        TelnyxSaveClicked ->
            case ( model.telnyxConfigEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | telnyxConfigEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyTelnyxConfig edit)
                        |> Task.attempt GotTelnyxSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotTelnyxSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | telnyxConfigEdit = Nothing, adminContactIntegrations = AdminContactIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotTelnyxSaveResult (Err err) ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

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
            ( { model | configEdit = Nothing, adminContactIntegrations = AdminContactIntegrationsLoaded newConfig }
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
            ( { model | birdConfigEdit = Nothing, adminContactIntegrations = AdminContactIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotBirdSaveResult (Err err) ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
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
            ( { model | preferredProvidersEdit = Nothing, adminContactIntegrations = AdminContactIntegrationsLoaded newConfig }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotPreferredProvidersSaveResult (Err err) ->
            ( { model | preferredProvidersEdit = model.preferredProvidersEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        WebPushPublicKeyEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        currentPublicKey : String
                        currentPublicKey =
                            (RellmServers.configurationOf server).webPushConfig
                                |> Maybe.map .publicVapidKey
                                |> Maybe.withDefault ""
                    in
                    ( { model | webPushPublicKeyEdit = Just { pending = currentPublicKey, status = AccountsPanel.Idle } }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        WebPushPublicKeyChanged text ->
            ( { model | webPushPublicKeyEdit = model.webPushPublicKeyEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        WebPushPublicKeyCancelClicked ->
            ( { model | webPushPublicKeyEdit = Nothing }, Effect.none )

        WebPushPublicKeySaveClicked ->
            case ( model.webPushPublicKeyEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | webPushPublicKeyEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyWebPushPublicKey edit.pending)
                        |> Task.attempt GotWebPushPublicKeySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotWebPushPublicKeySaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | webPushPublicKeyEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotWebPushPublicKeySaveResult (Err err) ->
            ( { model | webPushPublicKeyEdit = model.webPushPublicKeyEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        WebPushPrivateKeyEditClicked ->
            ( { model | webPushPrivateKeyEdit = Just { pending = "", status = AccountsPanel.Idle } }, Effect.none )

        WebPushPrivateKeyChanged text ->
            ( { model | webPushPrivateKeyEdit = model.webPushPrivateKeyEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        WebPushPrivateKeyCancelClicked ->
            ( { model | webPushPrivateKeyEdit = Nothing }, Effect.none )

        WebPushPrivateKeySaveClicked ->
            case ( model.webPushPrivateKeyEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | webPushPrivateKeyEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyWebPushPrivateKey edit.pending)
                        |> Task.attempt GotWebPushPrivateKeySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotWebPushPrivateKeySaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | webPushPrivateKeyEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotWebPushPrivateKeySaveResult (Err err) ->
            ( { model | webPushPrivateKeyEdit = model.webPushPrivateKeyEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        ContactIntegrationsTabActivated ->
            case ( model.adminContactIntegrations, Common.adminAccountFor shared targetHost ) of
                ( AdminContactIntegrationsNotFetched, Just account ) ->
                    ( { model | adminContactIntegrations = FetchingAdminContactIntegrations }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                ( AdminContactIntegrationsFetchFailed _, Just account ) ->
                    ( { model | adminContactIntegrations = FetchingAdminContactIntegrations }
                    , fetchAuthenticatedServerConfiguration shared targetHost account
                    )

                _ ->
                    ( model, Effect.none )

        GotAuthenticatedServerConfiguration (Ok ( maybeAccountsPanelMsg, config )) ->
            ( { model | adminContactIntegrations = AdminContactIntegrationsLoaded config }
            , Common.accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAuthenticatedServerConfiguration (Err err) ->
            ( { model | adminContactIntegrations = AdminContactIntegrationsFetchFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        IntegrationsSectionToggled section ->
            ( { model | collapsedIntegrationsSections = toggleSetMember (integrationsSectionKey section) model.collapsedIntegrationsSections }
            , Effect.none
            )


{-| `twilio_config`/`bird_config`/`preferred_verification_apis` are all stripped from the
unauthenticated `GetServerConfiguration` every other tab reads via `RellmServers.configurationOf`
(see module doc) -- this fetches it fresh, authenticated as `account`, the same way
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


{-| `TelnyxSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way every
other editor's transform is. Unlike `CdnTab.applyCdnConfig` (which nulls `externalCdnConfig` out
entirely when its toggle is off), this never nulls `telnyxConfig` out -- `telnyxEnabled` is itself
the field that means "off," so disabling just flips that bool while `fromNumber`/
`messagingProfileId` (and whatever's stored for `apiKey`, left untouched when `edit.apiKey` is
blank) stay put, letting an admin flip Telnyx off and back on without re-entering credentials.
-}
applyTelnyxConfig : TelnyxConfigEdit -> ServerConfiguration -> ServerConfiguration
applyTelnyxConfig edit config =
    let
        existing : TelnyxConfig
        existing =
            Maybe.withDefault defaultTelnyxConfig config.telnyxConfig
    in
    { config
        | telnyxConfig =
            Just
                { existing
                    | telnyxEnabled = edit.enabled
                    , telnyxApiKey = edit.apiKey
                    , telnyxFromNumber = edit.fromNumber
                    , telnyxMessagingProfileId = edit.messagingProfileId
                }
    }


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


{-| `WebPushPublicKeySaveClicked`'s transform -- overlays a new `publicVapidKey` onto a freshly
re-fetched `ServerConfiguration`'s `webPushConfig`. `privateVapidKey` is always sent blank here:
same "blank means leave it alone" merge every other write-only field on this page relies on, this
time in `ConfigureServer`'s `WebPushConfig`-specific merge block (see that RPC's own doc comment).
-}
applyWebPushPublicKey : String -> ServerConfiguration -> ServerConfiguration
applyWebPushPublicKey publicKey config =
    { config | webPushConfig = Just { publicVapidKey = publicKey, privateVapidKey = "" } }


{-| `WebPushPrivateKeySaveClicked`'s transform -- mirrors `applyWebPushPublicKey`, just overlaying a
new `privateVapidKey` (this time actually non-blank, since this _is_ the save that's meant to change
it) instead. Keeps whatever `publicVapidKey` the freshly re-fetched config already has.
-}
applyWebPushPrivateKey : String -> ServerConfiguration -> ServerConfiguration
applyWebPushPrivateKey privateKey config =
    let
        existingPublicKey : String
        existingPublicKey =
            config.webPushConfig |> Maybe.map .publicVapidKey |> Maybe.withDefault ""
    in
    { config | webPushConfig = Just { publicVapidKey = existingPublicKey, privateVapidKey = privateKey } }


{-| Every `VerificationAPI` value, in a fixed display order -- used both for the Add dropdown's
full option list and (indirectly, via `addablePreferredProviders`) for what's left to add.
-}
allVerificationApis : List VerificationAPI
allVerificationApis =
    [ VERIFICATIONAPITWILIO, VERIFICATIONAPIBIRD, VERIFICATIONAPITELNYX ]


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
        VERIFICATIONAPITELNYX ->
            "Telnyx"

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


{-| `server` is only needed for `webPushConfigSection` (see module doc -- `webPushConfig` isn't
admin-only-stripped, so it doesn't need to wait on `adminContactIntegrations`'s own fetch the way
Twilio/Bird/Preferred Providers below it do), mirroring exactly how `FederationTab.view` takes its
own `server` for the same reason.
-}
view : RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view server maybeAdminAccount model =
    div [ class "server-details-tab-content server-details-integrations" ]
        [ webPushConfigSection server model maybeAdminAccount
        , externalIntegrationsSection model maybeAdminAccount
        ]


{-| The collapsible "External Integrations" group -- Preferred Providers/Twilio/Bird, each always
mounted (even while collapsed, or before/during the admin fetch) so this section's own
`expanded`/`is-open`/`is-closed` toggle stays purely CSS-driven, per this module's own doc. Twilio
and Bird are each their own nested collapsible inside it (`twilioSection`/`birdSection`) -- see
`IntegrationsSection`.
-}
externalIntegrationsSection : Model -> Maybe RellmAccount -> Html Msg
externalIntegrationsSection model maybeAdminAccount =
    let
        expanded : Bool
        expanded =
            integrationsSectionExpanded model ExternalIntegrationsSection
    in
    div [ class "server-details-external-integrations" ]
        [ h2
            [ classes [ "expandable-section-title", "server-details-group-title" ]
            , onClick (IntegrationsSectionToggled ExternalIntegrationsSection)
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , text "External Integrations"
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ class "expandable-section-content-inner" ]
                (case model.adminContactIntegrations of
                    FetchingAdminContactIntegrations ->
                        [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

                    AdminContactIntegrationsNotFetched ->
                        [ span [ class "server-details-feature-settings-value" ] [ text "Loading…" ] ]

                    AdminContactIntegrationsFetchFailed err ->
                        [ span [ class "server-details-feature-settings-value" ] [ text ("Failed to load integration settings: " ++ err) ] ]

                    AdminContactIntegrationsLoaded _ ->
                        [ preferredProvidersSection maybeAdminAccount model.preferredProvidersEdit (adminPreferredProviders model)
                        , telnyxSection model maybeAdminAccount
                        , twilioSection model maybeAdminAccount
                        , birdSection model maybeAdminAccount
                        ]
                )
            ]
        ]


telnyxSection : Model -> Maybe RellmAccount -> Html Msg
telnyxSection model maybeAdminAccount =
    let
        expanded : Bool
        expanded =
            integrationsSectionExpanded model TelnyxIntegrationSection
    in
    div [ class "server-details-feature-settings" ]
        [ h3
            [ classes [ "section-title", "expandable-section-title" ]
            , onClick (IntegrationsSectionToggled TelnyxIntegrationSection)
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , text "Telnyx"
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ class "expandable-section-content-inner" ]
                (case model.telnyxConfigEdit of
                    Just edit ->
                        telnyxEditView edit

                    Nothing ->
                        telnyxDisplayView maybeAdminAccount (adminTelnyxConfig model)
                )
            ]
        ]


twilioSection : Model -> Maybe RellmAccount -> Html Msg
twilioSection model maybeAdminAccount =
    let
        expanded : Bool
        expanded =
            integrationsSectionExpanded model TwilioIntegrationSection
    in
    div [ class "server-details-feature-settings" ]
        [ h3
            [ classes [ "section-title", "expandable-section-title" ]
            , onClick (IntegrationsSectionToggled TwilioIntegrationSection)
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , text "Twilio"
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ class "expandable-section-content-inner" ]
                (case model.configEdit of
                    Just edit ->
                        twilioEditView edit

                    Nothing ->
                        twilioDisplayView maybeAdminAccount (adminTwilioConfig model)
                )
            ]
        ]


birdSection : Model -> Maybe RellmAccount -> Html Msg
birdSection model maybeAdminAccount =
    let
        expanded : Bool
        expanded =
            integrationsSectionExpanded model BirdIntegrationSection
    in
    div [ class "server-details-feature-settings" ]
        [ h3
            [ classes [ "section-title", "expandable-section-title" ]
            , onClick (IntegrationsSectionToggled BirdIntegrationSection)
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , text "Bird"
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ class "expandable-section-content-inner" ]
                (case model.birdConfigEdit of
                    Just edit ->
                        birdEditView edit

                    Nothing ->
                        birdDisplayView maybeAdminAccount (adminBirdConfig model)
                )
            ]
        ]


telnyxDisplayView : Maybe RellmAccount -> Maybe TelnyxConfig -> List (Html Msg)
telnyxDisplayView maybeAdminAccount telnyxConfig =
    [ Common.settingsRow "Telnyx Enabled" (Common.switchDisplay (telnyxConfig |> Maybe.map .telnyxEnabled |> Maybe.withDefault False))
    , Common.settingsRow "From Number" (span [ class "server-details-feature-settings-value" ] [ text (telnyxConfig |> Maybe.map .telnyxFromNumber |> Maybe.withDefault "—") ])
    , Common.settingsRow "Messaging Profile ID" (span [ class "server-details-feature-settings-value" ] [ text (telnyxConfig |> Maybe.map .telnyxMessagingProfileId |> Maybe.withDefault "—") ])
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick TelnyxEditClicked ] [ text "Edit Telnyx Settings" ]

        Nothing ->
            text ""
    ]


{-| Telnyx's Messaging API (`POST /v2/messages`) authenticates with a single v2 API Key as a Bearer
token -- see `TelnyxConfig`'s own proto doc for why there's no separate account SID the way
Twilio's auth model needs one.
-}
telnyxEditView : TelnyxConfigEdit -> List (Html Msg)
telnyxEditView edit =
    [ Common.settingsRow "Telnyx Enabled" (Common.flagSwitch edit.enabled TelnyxEnabledToggled)
    , Common.settingsRow "API Key"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change"
            , value edit.apiKey
            , onInput TelnyxApiKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "From Number"
        (input
            [ class "server-details-rename-input"
            , placeholder "+15555550100"
            , value edit.fromNumber
            , onInput TelnyxFromNumberChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Messaging Profile ID"
        (input
            [ class "server-details-rename-input"
            , placeholder "4001xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            , value edit.messagingProfileId
            , onInput TelnyxMessagingProfileIdChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton TelnyxSaveClicked edit.status
        , Common.editCancelButton TelnyxCancelClicked edit.status
        ]
    , Common.editErrorView edit.status
    ]


twilioDisplayView : Maybe RellmAccount -> Maybe TwilioConfig -> List (Html Msg)
twilioDisplayView maybeAdminAccount twilioConfig =
    [ Common.settingsRow "Twilio Enabled" (Common.switchDisplay (twilioConfig |> Maybe.map .twilioEnabled |> Maybe.withDefault False))
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
    [ Common.settingsRow "Twilio Enabled" (Common.flagSwitch edit.enabled TwilioEnabledToggled)
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
    [ Common.settingsRow "Bird Enabled" (Common.switchDisplay (birdConfig |> Maybe.map .birdEnabled |> Maybe.withDefault False))
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
    [ Common.settingsRow "Bird Enabled" (Common.flagSwitch edit.enabled BirdEnabledToggled)
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
                    Html.p [] [ text "None set -- falls back to whichever provider is enabled (Twilio first, then Bird, then Telnyx)." ]

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


{-| Mirrors `FederationTab`'s old `facebookAuthConfigSection`: the read-only Public VAPID key
(needed by any browser calling `pushManager.subscribe`, see `Shared.AccountsPanel`'s "Enable
notifications") is shown to everyone, same as Facebook's App ID; the Private VAPID key (needed only
to sign outgoing pushes, see `backend/src/web_push`) is admin-only, same as Facebook's App Secret.
-}
webPushConfigSection : RellmServer -> Model -> Maybe RellmAccount -> Html Msg
webPushConfigSection server model maybeAdminAccount =
    let
        currentPublicKey : String
        currentPublicKey =
            (RellmServers.configurationOf server).webPushConfig
                |> Maybe.map .publicVapidKey
                |> Maybe.withDefault ""
    in
    div [ class "server-details-facebook-auth" ]
        (h3 [ class "section-title" ] [ text "Web Push Configuration" ]
            :: webPushPublicKeyRow currentPublicKey model.webPushPublicKeyEdit maybeAdminAccount
            :: (case maybeAdminAccount of
                    Just _ ->
                        [ webPushPrivateKeyRow model.webPushPrivateKeyEdit maybeAdminAccount ]

                    Nothing ->
                        []
               )
        )


webPushPublicKeyRow : String -> Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
webPushPublicKeyRow currentPublicKey maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Public VAPID Key" ]
                , input
                    [ class "server-details-rename-input"
                    , value edit.pending
                    , onInput WebPushPublicKeyChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton WebPushPublicKeySaveClicked edit.status
                , Common.editCancelButton WebPushPublicKeyCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Public VAPID Key" ]
                , span [ class "server-details-color-hex" ]
                    [ text
                        (if String.isEmpty currentPublicKey then
                            "Not set."

                         else
                            currentPublicKey
                        )
                    ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick WebPushPublicKeyEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| Unlike `webPushPublicKeyRow`, there's no "current value" to show when not editing -- the server
never sends the real `privateVapidKey` back (see `TextFieldEdit`'s doc), so the placeholder below is
shown regardless of whether a key is actually configured. Clicking Edit always starts from a blank
`<input>`; saving it blank is a no-op on the backend, same as leaving a "change password" field
untouched.
-}
webPushPrivateKeyRow : Maybe TextFieldEdit -> Maybe RellmAccount -> Html Msg
webPushPrivateKeyRow maybeEdit maybeAdminAccount =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Private VAPID Key" ]
                , input
                    [ type_ "password"
                    , class "server-details-rename-input"
                    , placeholder "New Private VAPID Key"
                    , value edit.pending
                    , onInput WebPushPrivateKeyChanged
                    , disabled (edit.status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton WebPushPrivateKeySaveClicked edit.status
                , Common.editCancelButton WebPushPrivateKeyCancelClicked edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Private VAPID Key" ]
                , span [ class "server-details-color-hex" ] [ text "Never shown" ]
                , case maybeAdminAccount of
                    Just _ ->
                        button [ class "server-details-rename-button", onClick WebPushPrivateKeyEditClicked ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]
