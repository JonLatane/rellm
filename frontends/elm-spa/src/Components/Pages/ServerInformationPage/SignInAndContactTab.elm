module Components.Pages.ServerInformationPage.SignInAndContactTab exposing (Model, Msg, activated, init, subscriptions, update, view)

{-| The Sign In & Contact tab of `Components.Pages.ServerInformationPage`: how people sign in and sign
up, and how this server contacts them. From the top: a **Sign in & sign up** section toggling the
`AuthenticationFeature`s (password first -- always on for now -- then SMS, then email); then two big
channel sections -- **SMS** (Twilio, Bird, Telnyx) and **Email** (Postmark, SendGrid, Mailgun,
Stalwart) -- each with a master toggle ("Enable SMS Sending"/"Enable Email Sending",
`ServerConfiguration.supportedContactProtocols`), a one-line health pill, a provider preference order
(`preferredVerificationApis`/`preferredEmailApis`) and one collapsible card per provider; the
**Email Domains** health view (SPF/DKIM/DMARC) under Email; and finally the Web Push (VAPID) key
editor.

## Live status

Every card (and the section/domain summaries) can show _live_ health -- coloured level pill,
summary, checks, metrics, dashboard link -- from `GetContactIntegrationsStatus`
(`ContactIntegrationsStatus`). That RPC is admin-only and slow (the server calls every provider's own
API and looks up DNS), so it is fetched once, when an admin first activates the tab
(`LiveStatus.requested`), then only on an explicit Refresh or after saving a provider's config. The
last report stays on screen (dimmed, with a spinner on the button) while a refresh is in flight; a
failed check -- including an older server answering `Unimplemented` -- is reported inline and never
blocks the settings forms. `SignInAndContact.Status` holds the pure decisions (worst level,
DMARC pill, domain chips, "Checked 2 minutes ago"), `SignInAndContact.StatusView` the HTML,
`subscriptions` a 30s tick that keeps the age label honest.

## Configuration fetch

Unlike `CdnTab`, this tab **can't** read `RellmServers.configurationOf server` for its display --
every provider config, `supportedContactProtocols`, `authenticationFeatures` and both preference
lists are admin-only-serialized, stripped from the unauthenticated `GetServerConfiguration` probe
`RellmServers.configurationOf` reflects. So, exactly like `ClusterTab`, this tab fires its own
authenticated `GetServerConfiguration` once an admin account is present, and displays _that_, via the
exposed `activated` message -- `Components.Pages.ServerInformationPage` dispatches it from every
point its own connectivity state could plausibly have changed (see `ClusterTab`'s doc for why there
are so many call sites; firing before the account's server connection has settled races ahead of it
and fails with a `Grpc.NetworkError`). `webPushConfig` is the exception: it is public (only
`privateVapidKey` is blanked), so that section reads straight off `RellmServers.configurationOf
server`.

## Editing conventions

Each provider is edited as its own unit (Edit/Save/Cancel). A provider's "Enabled" toggle only
flips its own `*Enabled` field -- the rest of its config is never nulled out, so re-enabling later
loses nothing. API keys and tokens are write-only secrets: `GetServerConfiguration` always blanks
them, so edits seed them blank and each input's placeholder says that leaving it blank on Save keeps
what's stored. Non-secret fields are shown in plain text (they are admin-only anyway). The pure
edit/apply logic for the email providers lives in `SignInAndContact.EmailEdits`; Stalwart's
_receiving_ flag is an instant toggle that only touches that one field (it shares `StalwartConfig`
with the sending settings, which it must never wipe).

## Collapsing and keyed remounting

Provider cards are collapsible (`ProviderSection`, stored as a `Set String` of collapsed keys
exactly like `SettingsTab.collapsedFeatureSettings`) using the `.sc-collapse`
`grid-template-rows` transition. Before the admin fetch resolves, all cards default to expanded;
once it lands, `initialCollapsedProviderSections` collapses the providers with nothing
configured yet. A later manual toggle always wins. `ServerInformationPage.view` mounts each tab under a
_different_ `Html.Keyed` key, so switching tabs rebuilds this subtree from scratch -- a freshly
collapsed card mounts already in its final CSS state, with no class flip to animate. That only
holds because every collapsible's wrapper stays at a fixed position in its parent's child list
across all states (always mounted, CSS-driven) -- keep it that way.

-}

import Components.Pages.ServerInformationPage.Common as Common
import Components.Pages.ServerInformationPage.Dns.View as DnsView
import Components.Pages.ServerInformationPage.SignInAndContact.EmailEdits as EmailEdits
    exposing
        ( MailgunField(..)
        , MailgunForm
        , PostmarkField(..)
        , PostmarkForm
        , SendgridField(..)
        , SendgridForm
        , StalwartField(..)
        , StalwartForm
        )
import Components.Pages.ServerInformationPage.SignInAndContact.ProviderOrder as ProviderOrder
import Components.Pages.ServerInformationPage.SignInAndContact.Status as Status
import Components.Pages.ServerInformationPage.SignInAndContact.StatusView as StatusView
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h2, h3, h4, input, option, p, select, span, text)
import Html.Attributes exposing (attribute, class, disabled, placeholder, selected, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm
    exposing
        ( BirdConfig
        , ContactIntegrationsStatus
        , ProviderStatus
        , ServerConfiguration
        , TelnyxConfig
        , TwilioConfig
        , defaultBirdConfig
        , defaultTelnyxConfig
        , defaultTwilioConfig
        )
import Proto.Rellm.AuthenticationFeature exposing (AuthenticationFeature(..))
import Proto.Rellm.ContactProtocol exposing (ContactProtocol(..))
import Proto.Rellm.ContactVerificationAPI exposing (ContactVerificationAPI(..))
import Proto.Rellm.EmailVerificationAPI exposing (EmailVerificationAPI(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.StatusLevel exposing (StatusLevel(..))
import Set exposing (Set)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task
import Time
import UI.Classes exposing (classes, openClosedClass)
import UI.Glyph as Glyph



-- MODEL


type alias Model =
    { configEdit : Maybe TwilioConfigEdit
    , birdConfigEdit : Maybe BirdConfigEdit
    , telnyxConfigEdit : Maybe TelnyxConfigEdit
    , postmarkEdit : Maybe (Editing PostmarkForm)
    , sendgridEdit : Maybe (Editing SendgridForm)
    , mailgunEdit : Maybe (Editing MailgunForm)
    , stalwartEdit : Maybe (Editing StalwartForm)
    , preferredProvidersEdit : Maybe (OrderEdit ContactVerificationAPI)
    , preferredEmailProvidersEdit : Maybe (OrderEdit EmailVerificationAPI)
    , webPushPublicKeyEdit : Maybe TextFieldEdit
    , webPushPrivateKeyEdit : Maybe TextFieldEdit
    , adminSignInAndContact : AdminSignInAndContactConfig
    , collapsedProviderSections : Set String
    , smsContactProtocolStatus : AccountsPanel.FormStatus
    , emailContactProtocolStatus : AccountsPanel.FormStatus
    , stalwartReceivingStatus : AccountsPanel.FormStatus
    , authFeaturesStatus : AccountsPanel.FormStatus
    , liveStatus : LiveStatus
    , toggledChecks : Set String
    , copied : Maybe String
    }


{-| The live `GetContactIntegrationsStatus` report and its fetch state. `report` outlives a refresh
(it stays visible while another fetch is `inFlight`); `requestSeq`/`appliedSeq` tag each request and drop replies older than one already applied
(`Status.replyIsFresh`); `requested` makes "fetch once on first activation" stick
even if that first fetch failed (the Refresh button retries); `now` is the browser clock as of the
last report landing or tick (`Time.every`), for "Checked 2 minutes ago".
-}
type alias LiveStatus =
    { report : Maybe ContactIntegrationsStatus
    , inFlight : Int
    , requestSeq : Int
    , appliedSeq : Int
    , requested : Bool
    , error : Maybe String
    , now : Time.Posix
    }


{-| An in-progress provider edit: the pure `form` (see `SignInAndContact.EmailEdits`) plus its
save status.
-}
type alias Editing form =
    { form : form
    , status : AccountsPanel.FormStatus
    }


{-| Live only while a provider preference order (`preferredVerificationApis`/`preferredEmailApis`)
is being edited -- `pending`'s order IS the preference order. The `ProviderOrder` module has the
pure list operations.
-}
type alias OrderEdit api =
    { pending : List api
    , addSelection : Maybe api
    , status : AccountsPanel.FormStatus
    }


{-| The collapsible provider cards -- see `Model.collapsedProviderSections` and this module's
own doc for why a card's wrapper must always stay mounted.
-}
type ProviderSection
    = TwilioIntegrationSection
    | BirdIntegrationSection
    | TelnyxIntegrationSection
    | PostmarkIntegrationSection
    | SendgridIntegrationSection
    | MailgunIntegrationSection
    | StalwartIntegrationSection


{-| The `collapsedProviderSections` key each `ProviderSection` stores itself under --
distinct from its own display label the same way `SettingsTab.featureSettingsKey` is.
-}
providerSectionKey : ProviderSection -> String
providerSectionKey section =
    case section of
        TwilioIntegrationSection ->
            "twilio"

        BirdIntegrationSection ->
            "bird"

        TelnyxIntegrationSection ->
            "telnyx"

        PostmarkIntegrationSection ->
            "postmark"

        SendgridIntegrationSection ->
            "sendgrid"

        MailgunIntegrationSection ->
            "mailgun"

        StalwartIntegrationSection ->
            "stalwart"


{-| The `collapsedProviderSections` to start with once `config` (the tab's own authenticated
fetch) first loads: each provider pre-expands iff it already has at least one non-default value
entered (see the `*HasValues` helpers), so an admin actively using a provider sees it open right
away while an unconfigured one stays out of the way, collapsed. Only ever computed once per fetch
(`GotAuthenticatedServerConfiguration`'s success branch).
-}
initialCollapsedProviderSections : ServerConfiguration -> Set String
initialCollapsedProviderSections config =
    [ ( TwilioIntegrationSection, config.twilioConfig |> Maybe.map twilioConfigHasValues )
    , ( BirdIntegrationSection, config.birdConfig |> Maybe.map birdConfigHasValues )
    , ( TelnyxIntegrationSection, config.telnyxConfig |> Maybe.map telnyxConfigHasValues )
    , ( PostmarkIntegrationSection, config.postmarkConfig |> Maybe.map EmailEdits.postmarkHasValues )
    , ( SendgridIntegrationSection, config.sendgridConfig |> Maybe.map EmailEdits.sendgridHasValues )
    , ( MailgunIntegrationSection, config.mailgunConfig |> Maybe.map EmailEdits.mailgunHasValues )
    , ( StalwartIntegrationSection, config.stalwartConfig |> Maybe.map EmailEdits.stalwartHasValues )
    ]
        |> List.filter (\( _, hasValues ) -> hasValues /= Just True)
        |> List.map (\( section, _ ) -> providerSectionKey section)
        |> Set.fromList


twilioConfigHasValues : TwilioConfig -> Bool
twilioConfigHasValues config =
    config.twilioEnabled
        || not (String.isEmpty config.twilioAccountSid)
        || not (String.isEmpty config.twilioApiKeySid)
        || not (String.isEmpty config.twilioFromNumber)
        || config.useTwilioWebhookSigningKey


birdConfigHasValues : BirdConfig -> Bool
birdConfigHasValues config =
    config.birdEnabled
        || not (String.isEmpty config.birdFrom)
        || not (String.isEmpty config.birdRegion)
        || config.useBirdWebhookSigningKey


telnyxConfigHasValues : TelnyxConfig -> Bool
telnyxConfigHasValues config =
    config.telnyxEnabled
        || not (String.isEmpty config.telnyxFromNumber)
        || not (String.isEmpty config.telnyxMessagingProfileId)
        || config.useTelnyxWebhookSigningKey


providerSectionExpanded : Model -> ProviderSection -> Bool
providerSectionExpanded model section =
    not (Set.member (providerSectionKey section) model.collapsedProviderSections)


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
Mirrors `ClusterTab.AdminClusterResourcesStatus` exactly.
-}
type AdminSignInAndContactConfig
    = AdminSignInAndContactNotFetched
    | FetchingAdminSignInAndContact
    | AdminSignInAndContactLoaded ServerConfiguration
    | AdminSignInAndContactFetchFailed String


type Msg
    = TelnyxEditClicked
    | TelnyxEnabledToggled
    | TelnyxApiKeyChanged String
    | TelnyxFromNumberChanged String
    | TelnyxMessagingProfileIdChanged String
    | TelnyxWebhookSigningKeyChanged String
    | TelnyxUseWebhookSigningKeyToggled
    | TelnyxCancelClicked
    | TelnyxSaveClicked
    | GotTelnyxSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | TwilioEditClicked
    | TwilioEnabledToggled
    | TwilioAccountSidChanged String
    | TwilioApiKeySidChanged String
    | TwilioApiKeySecretChanged String
    | TwilioFromNumberChanged String
    | TwilioWebhookSigningKeyChanged String
    | TwilioUseWebhookSigningKeyToggled
    | TwilioCancelClicked
    | TwilioSaveClicked
    | GotTwilioSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | BirdEditClicked
    | BirdEnabledToggled
    | BirdAccessKeyChanged String
    | BirdFromChanged String
    | BirdRegionChanged String
    | BirdWebhookSigningKeyChanged String
    | BirdUseWebhookSigningKeyToggled
    | BirdCancelClicked
    | BirdSaveClicked
    | GotBirdSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | PostmarkEditClicked
    | PostmarkEnabledToggled
    | PostmarkFieldChanged PostmarkField String
    | PostmarkCancelClicked
    | PostmarkSaveClicked
    | GotPostmarkSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | SendgridEditClicked
    | SendgridEnabledToggled
    | SendgridFieldChanged SendgridField String
    | SendgridCancelClicked
    | SendgridSaveClicked
    | GotSendgridSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | MailgunEditClicked
    | MailgunEnabledToggled
    | MailgunFieldChanged MailgunField String
    | MailgunCancelClicked
    | MailgunSaveClicked
    | GotMailgunSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | StalwartEditClicked
    | StalwartSendingToggled
    | StalwartFieldChanged StalwartField String
    | StalwartCancelClicked
    | StalwartSaveClicked
    | GotStalwartSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | SmsOrderMsg OrderMsg
    | GotPreferredProvidersSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | EmailOrderMsg OrderMsg
    | GotPreferredEmailProvidersSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
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
    | SmsContactProtocolToggled
    | GotSmsContactProtocolSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | EmailContactProtocolToggled
    | GotEmailContactProtocolSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | StalwartReceivingToggled
    | GotStalwartReceivingSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | AuthFeatureToggled AuthenticationFeature
    | GotAuthFeatureSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | SignInAndContactTabActivated
    | GotAuthenticatedServerConfiguration (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | ProviderSectionToggled ProviderSection
    | StatusRefreshClicked
    | GotLiveStatus Int (Result Grpc.Error ( Maybe AccountsPanel.Msg, Time.Posix, ContactIntegrationsStatus ))
    | StatusChecksToggled String
    | StatusTick Time.Posix
    | CopyClicked String
    | CopiedReset String


{-| What a provider-preference editor can do -- shared by the SMS (`SmsOrderMsg`) and email
(`EmailOrderMsg`) editors. Indices refer to the editor's `pending` list.
-}
type OrderMsg
    = OrderEditClicked
    | OrderRemoveClicked Int
    | OrderMoveUpClicked Int
    | OrderMoveDownClicked Int
    | OrderAddSelectionChanged String
    | OrderAddClicked
    | OrderCancelClicked
    | OrderSaveClicked


{-| Live only while the Telnyx config is being edited by an admin. `apiKey`/`webhookSigningKey`
always start blank (see module doc) -- leaving either blank on Save means "keep whatever's already
stored" (the backend splices the existing value back in when the incoming
`telnyx_api_key`/`telnyx_webhook_signing_key` is empty, mirroring `WebPushConfig.privateVapidKey`'s
own merge rule). `fromNumber`/`messagingProfileId` are Telnyx's sending number and the Messaging
Profile ID it's assigned to -- see `TelnyxConfig`'s own proto doc. `webhookSigningKey` is Telnyx's
account-level public key, used only to verify inbound `/contact_integrations/telnyx/receive`
deliveries -- see that field's own proto doc and `docs/contact_integrations.md`. `useWebhookSigningKey`
is the "Use Webhook Signing Key" toggle (`TelnyxConfig.use_telnyx_webhook_signing_key`) -- unlike
`webhookSigningKey` itself, it's not secret, so it starts pre-filled with whatever's currently
stored, not blank.
-}
type alias TelnyxConfigEdit =
    { enabled : Bool
    , apiKey : String
    , fromNumber : String
    , messagingProfileId : String
    , webhookSigningKey : String
    , useWebhookSigningKey : Bool
    , status : AccountsPanel.FormStatus
    }


{-| Live only while the Twilio config is being edited by an admin. `apiKeySecret`/
`webhookSigningKey` always start blank (see module doc) -- leaving either blank on Save means "keep
whatever's already stored" (the backend splices the existing value back in when the incoming
`twilio_api_key_secret`/`twilio_webhook_signing_key` is empty, mirroring
`WebPushConfig.privateVapidKey`'s own merge rule). `accountSid`/`apiKeySid` are Twilio's Account SID
and API Key SID respectively -- see `TwilioConfig`'s own proto doc for why authentication uses the
API Key pair, never the account's own Auth Token. `webhookSigningKey` is that Auth Token, used
_only_ to verify inbound `/contact_integrations/twilio/receive` deliveries (see that field's own
proto doc and `docs/contact_integrations.md`) -- the one place the Auth Token is ever accepted here.
`useWebhookSigningKey` is the "Use Webhook Signing Key" toggle
(`TwilioConfig.use_twilio_webhook_signing_key`) -- unlike `webhookSigningKey` itself, it's not
secret, so it starts pre-filled with whatever's currently stored, not blank.
-}
type alias TwilioConfigEdit =
    { enabled : Bool
    , accountSid : String
    , apiKeySid : String
    , apiKeySecret : String
    , fromNumber : String
    , webhookSigningKey : String
    , useWebhookSigningKey : Bool
    , status : AccountsPanel.FormStatus
    }


{-| Same as `TwilioConfigEdit`, but for Bird -- `accessKey`/`webhookSigningKey` always start blank
the same way `apiKeySecret`/`webhookSigningKey` do there. `webhookSigningKey` is the Standard
Webhooks signing secret (`whsec_...`) for the SMS channel subscription delivering to
`/contact_integrations/bird/receive` -- see `BirdConfig.bird_webhook_signing_key`'s own proto doc.
`useWebhookSigningKey` is the "Use Webhook Signing Key" toggle
(`BirdConfig.use_bird_webhook_signing_key`) -- same "not secret, starts pre-filled" treatment as
`TwilioConfigEdit.useWebhookSigningKey`.
-}
type alias BirdConfigEdit =
    { enabled : Bool
    , accessKey : String
    , from : String
    , region : String
    , webhookSigningKey : String
    , useWebhookSigningKey : Bool
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
    , postmarkEdit = Nothing
    , sendgridEdit = Nothing
    , mailgunEdit = Nothing
    , stalwartEdit = Nothing
    , preferredProvidersEdit = Nothing
    , preferredEmailProvidersEdit = Nothing
    , webPushPublicKeyEdit = Nothing
    , webPushPrivateKeyEdit = Nothing
    , adminSignInAndContact = AdminSignInAndContactNotFetched
    , collapsedProviderSections = Set.empty
    , smsContactProtocolStatus = AccountsPanel.Idle
    , emailContactProtocolStatus = AccountsPanel.Idle
    , stalwartReceivingStatus = AccountsPanel.Idle
    , authFeaturesStatus = AccountsPanel.Idle
    , liveStatus =
        { report = Nothing
        , inFlight = 0
        , requestSeq = 0
        , appliedSeq = 0
        , requested = False
        , error = Nothing
        , now = Time.millisToPosix 0
        }
    , toggledChecks = Set.empty
    , copied = Nothing
    }


{-| `Components.Pages.ServerInformationPage` dispatches this (via `SignInAndContactTab.update`)
whenever this tab becomes the active one -- on `TabSelected TabSignInAndContact`, and at every
point this page's own connectivity state could plausibly have changed (see module doc) -- to kick
off the authenticated fetches this module's own doc describes (the configuration, and -- only the
first time -- the live status). `SignInAndContactTabActivated`'s own constructor isn't exposed
(like every other `Msg` here), so this is the one blessed way a parent triggers it. Mirrors
`ClusterTab.activated` exactly.
-}
activated : Msg
activated =
    SignInAndContactTabActivated


{-| A 30-second tick (only while a report is on screen) so "Checked 2 minutes ago" stays honest.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    case model.liveStatus.report of
        Just _ ->
            Time.every 30000 StatusTick

        Nothing ->
            Sub.none


{-| `telnyxConfig`/`twilioConfig`/... off of `model.adminSignInAndContact`'s own
freshly-authenticated fetch (see module doc) -- `Nothing`/`[]` whenever that fetch hasn't completed
yet (or failed), same as `ClusterTab`'s own accessors.
-}
adminConfig : Model -> Maybe ServerConfiguration
adminConfig model =
    case model.adminSignInAndContact of
        AdminSignInAndContactLoaded config ->
            Just config

        _ ->
            Nothing


adminTelnyxConfig : Model -> Maybe TelnyxConfig
adminTelnyxConfig model =
    adminConfig model |> Maybe.andThen .telnyxConfig


adminTwilioConfig : Model -> Maybe TwilioConfig
adminTwilioConfig model =
    adminConfig model |> Maybe.andThen .twilioConfig


adminBirdConfig : Model -> Maybe BirdConfig
adminBirdConfig model =
    adminConfig model |> Maybe.andThen .birdConfig


adminPreferredProviders : Model -> List ContactVerificationAPI
adminPreferredProviders model =
    adminConfig model |> Maybe.map .preferredVerificationApis |> Maybe.withDefault []


adminPreferredEmailProviders : Model -> List EmailVerificationAPI
adminPreferredEmailProviders model =
    adminConfig model |> Maybe.map .preferredEmailApis |> Maybe.withDefault []



-- UPDATE


update : Shared.Model -> String -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost maybeServer msg model =
    let
        -- Fires `updateServerConfig` with `transform` as the signed-in admin (a no-op without one) --
        -- `markSubmitting` puts the owning editor/toggle into its "Saving…" state first, `toResult`
        -- is the `Got…SaveResult` constructor that comes back.
        save :
            (Model -> Model)
            -> (ServerConfiguration -> ServerConfiguration)
            -> (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ) -> Msg)
            -> ( Model, Effect Msg )
        save markSubmitting transform toResult =
            case Common.adminAccountFor shared targetHost of
                Just account ->
                    ( markSubmitting model
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) transform
                        |> Task.attempt toResult
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        -- A successful save: show the returned config, tell the Accounts Panel about it, and (for
        -- provider/protocol saves) re-run the live status check, since what it reports just changed.
        saved : Bool -> Maybe AccountsPanel.Msg -> ServerConfiguration -> Model -> ( Model, Effect Msg )
        saved refreshStatus maybeAccountsPanelMsg newConfig newModel =
            let
                ( refreshedModel, statusEffect ) =
                    if refreshStatus then
                        startStatusFetch shared targetHost { newModel | adminSignInAndContact = AdminSignInAndContactLoaded newConfig }

                    else
                        ( { newModel | adminSignInAndContact = AdminSignInAndContactLoaded newConfig }, Effect.none )
            in
            ( refreshedModel
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                , statusEffect
                ]
            )

        submitting : Maybe { a | status : AccountsPanel.FormStatus } -> Maybe { a | status : AccountsPanel.FormStatus }
        submitting =
            Maybe.map (\edit -> { edit | status = AccountsPanel.Submitting })

        failed : Grpc.Error -> Maybe { a | status : AccountsPanel.FormStatus } -> Maybe { a | status : AccountsPanel.FormStatus }
        failed err =
            Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) })

        mapForm : (form -> form) -> Maybe (Editing form) -> Maybe (Editing form)
        mapForm f =
            Maybe.map (\edit -> { edit | form = f edit.form })

        idle : form -> Maybe (Editing form)
        idle form =
            Just { form = form, status = AccountsPanel.Idle }
    in
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
                        , webhookSigningKey = ""
                        , useWebhookSigningKey = telnyxConfig |> Maybe.map .useTelnyxWebhookSigningKey |> Maybe.withDefault False
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

        TelnyxWebhookSigningKeyChanged text ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | webhookSigningKey = text }) }, Effect.none )

        TelnyxUseWebhookSigningKeyToggled ->
            ( { model | telnyxConfigEdit = model.telnyxConfigEdit |> Maybe.map (\edit -> { edit | useWebhookSigningKey = not edit.useWebhookSigningKey }) }, Effect.none )

        TelnyxCancelClicked ->
            ( { model | telnyxConfigEdit = Nothing }, Effect.none )

        TelnyxSaveClicked ->
            case model.telnyxConfigEdit of
                Just edit ->
                    save (\m -> { m | telnyxConfigEdit = submitting m.telnyxConfigEdit }) (applyTelnyxConfig edit) GotTelnyxSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotTelnyxSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | telnyxConfigEdit = Nothing }

        GotTelnyxSaveResult (Err err) ->
            ( { model | telnyxConfigEdit = failed err model.telnyxConfigEdit }, Effect.none )

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
                        , webhookSigningKey = ""
                        , useWebhookSigningKey = twilioConfig |> Maybe.map .useTwilioWebhookSigningKey |> Maybe.withDefault False
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

        TwilioWebhookSigningKeyChanged text ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | webhookSigningKey = text }) }, Effect.none )

        TwilioUseWebhookSigningKeyToggled ->
            ( { model | configEdit = model.configEdit |> Maybe.map (\edit -> { edit | useWebhookSigningKey = not edit.useWebhookSigningKey }) }, Effect.none )

        TwilioCancelClicked ->
            ( { model | configEdit = Nothing }, Effect.none )

        TwilioSaveClicked ->
            case model.configEdit of
                Just edit ->
                    save (\m -> { m | configEdit = submitting m.configEdit }) (applyTwilioConfig edit) GotTwilioSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotTwilioSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | configEdit = Nothing }

        GotTwilioSaveResult (Err err) ->
            ( { model | configEdit = failed err model.configEdit }, Effect.none )

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
                        , webhookSigningKey = ""
                        , useWebhookSigningKey = birdConfig |> Maybe.map .useBirdWebhookSigningKey |> Maybe.withDefault False
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

        BirdWebhookSigningKeyChanged text ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | webhookSigningKey = text }) }, Effect.none )

        BirdUseWebhookSigningKeyToggled ->
            ( { model | birdConfigEdit = model.birdConfigEdit |> Maybe.map (\edit -> { edit | useWebhookSigningKey = not edit.useWebhookSigningKey }) }, Effect.none )

        BirdCancelClicked ->
            ( { model | birdConfigEdit = Nothing }, Effect.none )

        BirdSaveClicked ->
            case model.birdConfigEdit of
                Just edit ->
                    save (\m -> { m | birdConfigEdit = submitting m.birdConfigEdit }) (applyBirdConfig edit) GotBirdSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotBirdSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | birdConfigEdit = Nothing }

        GotBirdSaveResult (Err err) ->
            ( { model | birdConfigEdit = failed err model.birdConfigEdit }, Effect.none )

        PostmarkEditClicked ->
            ( { model | postmarkEdit = idle (EmailEdits.postmarkFormFrom (adminConfig model |> Maybe.andThen .postmarkConfig)) }, Effect.none )

        PostmarkEnabledToggled ->
            ( { model | postmarkEdit = model.postmarkEdit |> mapForm (\form -> { form | enabled = not form.enabled }) }, Effect.none )

        PostmarkFieldChanged field text ->
            ( { model | postmarkEdit = model.postmarkEdit |> mapForm (EmailEdits.setPostmarkField field text) }, Effect.none )

        PostmarkCancelClicked ->
            ( { model | postmarkEdit = Nothing }, Effect.none )

        PostmarkSaveClicked ->
            case model.postmarkEdit of
                Just edit ->
                    save (\m -> { m | postmarkEdit = submitting m.postmarkEdit }) (EmailEdits.applyPostmark edit.form) GotPostmarkSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotPostmarkSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | postmarkEdit = Nothing }

        GotPostmarkSaveResult (Err err) ->
            ( { model | postmarkEdit = failed err model.postmarkEdit }, Effect.none )

        SendgridEditClicked ->
            ( { model | sendgridEdit = idle (EmailEdits.sendgridFormFrom (adminConfig model |> Maybe.andThen .sendgridConfig)) }, Effect.none )

        SendgridEnabledToggled ->
            ( { model | sendgridEdit = model.sendgridEdit |> mapForm (\form -> { form | enabled = not form.enabled }) }, Effect.none )

        SendgridFieldChanged field text ->
            ( { model | sendgridEdit = model.sendgridEdit |> mapForm (EmailEdits.setSendgridField field text) }, Effect.none )

        SendgridCancelClicked ->
            ( { model | sendgridEdit = Nothing }, Effect.none )

        SendgridSaveClicked ->
            case model.sendgridEdit of
                Just edit ->
                    save (\m -> { m | sendgridEdit = submitting m.sendgridEdit }) (EmailEdits.applySendgrid edit.form) GotSendgridSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotSendgridSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | sendgridEdit = Nothing }

        GotSendgridSaveResult (Err err) ->
            ( { model | sendgridEdit = failed err model.sendgridEdit }, Effect.none )

        MailgunEditClicked ->
            ( { model | mailgunEdit = idle (EmailEdits.mailgunFormFrom (adminConfig model |> Maybe.andThen .mailgunConfig)) }, Effect.none )

        MailgunEnabledToggled ->
            ( { model | mailgunEdit = model.mailgunEdit |> mapForm (\form -> { form | enabled = not form.enabled }) }, Effect.none )

        MailgunFieldChanged field text ->
            ( { model | mailgunEdit = model.mailgunEdit |> mapForm (EmailEdits.setMailgunField field text) }, Effect.none )

        MailgunCancelClicked ->
            ( { model | mailgunEdit = Nothing }, Effect.none )

        MailgunSaveClicked ->
            case model.mailgunEdit of
                Just edit ->
                    save (\m -> { m | mailgunEdit = submitting m.mailgunEdit }) (EmailEdits.applyMailgun edit.form) GotMailgunSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotMailgunSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | mailgunEdit = Nothing }

        GotMailgunSaveResult (Err err) ->
            ( { model | mailgunEdit = failed err model.mailgunEdit }, Effect.none )

        StalwartEditClicked ->
            ( { model | stalwartEdit = idle (EmailEdits.stalwartFormFrom (adminConfig model |> Maybe.andThen .stalwartConfig)) }, Effect.none )

        StalwartSendingToggled ->
            ( { model | stalwartEdit = model.stalwartEdit |> mapForm (\form -> { form | sendingEnabled = not form.sendingEnabled }) }, Effect.none )

        StalwartFieldChanged field text ->
            ( { model | stalwartEdit = model.stalwartEdit |> mapForm (EmailEdits.setStalwartField field text) }, Effect.none )

        StalwartCancelClicked ->
            ( { model | stalwartEdit = Nothing }, Effect.none )

        StalwartSaveClicked ->
            case model.stalwartEdit of
                Just edit ->
                    save (\m -> { m | stalwartEdit = submitting m.stalwartEdit }) (EmailEdits.applyStalwart edit.form) GotStalwartSaveResult

                Nothing ->
                    ( model, Effect.none )

        GotStalwartSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | stalwartEdit = Nothing }

        GotStalwartSaveResult (Err err) ->
            ( { model | stalwartEdit = failed err model.stalwartEdit }, Effect.none )

        SmsOrderMsg OrderSaveClicked ->
            case model.preferredProvidersEdit of
                Just edit ->
                    save
                        (\m -> { m | preferredProvidersEdit = submitting m.preferredProvidersEdit })
                        (\config -> { config | preferredVerificationApis = edit.pending })
                        GotPreferredProvidersSaveResult

                Nothing ->
                    ( model, Effect.none )

        SmsOrderMsg orderMsg ->
            ( { model
                | preferredProvidersEdit =
                    updateOrderEdit allVerificationApis (adminPreferredProviders model) orderMsg model.preferredProvidersEdit
              }
            , Effect.none
            )

        GotPreferredProvidersSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved False maybeAccountsPanelMsg newConfig { model | preferredProvidersEdit = Nothing }

        GotPreferredProvidersSaveResult (Err err) ->
            ( { model | preferredProvidersEdit = failed err model.preferredProvidersEdit }, Effect.none )

        EmailOrderMsg OrderSaveClicked ->
            case model.preferredEmailProvidersEdit of
                Just edit ->
                    save
                        (\m -> { m | preferredEmailProvidersEdit = submitting m.preferredEmailProvidersEdit })
                        (\config -> { config | preferredEmailApis = edit.pending })
                        GotPreferredEmailProvidersSaveResult

                Nothing ->
                    ( model, Effect.none )

        EmailOrderMsg orderMsg ->
            ( { model
                | preferredEmailProvidersEdit =
                    updateOrderEdit allEmailApis (adminPreferredEmailProviders model) orderMsg model.preferredEmailProvidersEdit
              }
            , Effect.none
            )

        GotPreferredEmailProvidersSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved False maybeAccountsPanelMsg newConfig { model | preferredEmailProvidersEdit = Nothing }

        GotPreferredEmailProvidersSaveResult (Err err) ->
            ( { model | preferredEmailProvidersEdit = failed err model.preferredEmailProvidersEdit }, Effect.none )

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

        SmsContactProtocolToggled ->
            save (\m -> { m | smsContactProtocolStatus = AccountsPanel.Submitting }) (toggleContactProtocol CONTACTPROTOCOLTEL) GotSmsContactProtocolSaveResult

        GotSmsContactProtocolSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved False maybeAccountsPanelMsg newConfig { model | smsContactProtocolStatus = AccountsPanel.Idle }

        GotSmsContactProtocolSaveResult (Err err) ->
            ( { model | smsContactProtocolStatus = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        EmailContactProtocolToggled ->
            save (\m -> { m | emailContactProtocolStatus = AccountsPanel.Submitting }) (toggleContactProtocol CONTACTPROTOCOLMAILTO) GotEmailContactProtocolSaveResult

        GotEmailContactProtocolSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved False maybeAccountsPanelMsg newConfig { model | emailContactProtocolStatus = AccountsPanel.Idle }

        GotEmailContactProtocolSaveResult (Err err) ->
            ( { model | emailContactProtocolStatus = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        StalwartReceivingToggled ->
            save (\m -> { m | stalwartReceivingStatus = AccountsPanel.Submitting }) EmailEdits.toggleStalwartReceiving GotStalwartReceivingSaveResult

        GotStalwartReceivingSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved True maybeAccountsPanelMsg newConfig { model | stalwartReceivingStatus = AccountsPanel.Idle }

        GotStalwartReceivingSaveResult (Err err) ->
            ( { model | stalwartReceivingStatus = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        AuthFeatureToggled feature ->
            if model.authFeaturesStatus == AccountsPanel.Submitting then
                ( model, Effect.none )

            else
                save (\m -> { m | authFeaturesStatus = AccountsPanel.Submitting }) (toggleAuthFeature feature) GotAuthFeatureSaveResult

        GotAuthFeatureSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            saved False maybeAccountsPanelMsg newConfig { model | authFeaturesStatus = AccountsPanel.Idle }

        GotAuthFeatureSaveResult (Err err) ->
            ( { model | authFeaturesStatus = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }, Effect.none )

        SignInAndContactTabActivated ->
            case Common.adminAccountFor shared targetHost of
                Just account ->
                    let
                        ( configModel, configEffect ) =
                            case model.adminSignInAndContact of
                                AdminSignInAndContactNotFetched ->
                                    ( { model | adminSignInAndContact = FetchingAdminSignInAndContact }
                                    , fetchAuthenticatedServerConfiguration shared targetHost account
                                    )

                                AdminSignInAndContactFetchFailed _ ->
                                    ( { model | adminSignInAndContact = FetchingAdminSignInAndContact }
                                    , fetchAuthenticatedServerConfiguration shared targetHost account
                                    )

                                _ ->
                                    ( model, Effect.none )

                        -- The live status is slow and expensive: asked for once, on first activation.
                        ( statusModel, statusEffect ) =
                            if configModel.liveStatus.requested then
                                ( configModel, Effect.none )

                            else
                                startStatusFetch shared targetHost configModel
                    in
                    ( statusModel, Effect.batch [ configEffect, statusEffect ] )

                Nothing ->
                    ( model, Effect.none )

        GotAuthenticatedServerConfiguration (Ok ( maybeAccountsPanelMsg, config )) ->
            let
                loadedModel : Model
                loadedModel =
                    { model
                        | adminSignInAndContact = AdminSignInAndContactLoaded config
                        , collapsedProviderSections = initialCollapsedProviderSections config
                    }

                -- The configuration landing proves the server connection has settled, so this is the
                -- reliable moment for the first status check if activation's own attempt lost the race
                -- (see `GotLiveStatus`'s `Err`).
                ( statusModel, statusEffect ) =
                    if loadedModel.liveStatus.requested then
                        ( loadedModel, Effect.none )

                    else
                        startStatusFetch shared targetHost loadedModel
            in
            ( statusModel, Effect.batch [ Common.accountsPanelEffect maybeAccountsPanelMsg, statusEffect ] )

        GotAuthenticatedServerConfiguration (Err err) ->
            ( { model | adminSignInAndContact = AdminSignInAndContactFetchFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        ProviderSectionToggled section ->
            ( { model | collapsedProviderSections = toggleSetMember (providerSectionKey section) model.collapsedProviderSections }
            , Effect.none
            )

        StatusRefreshClicked ->
            if isFetchingStatus model.liveStatus then
                ( model, Effect.none )

            else
                startStatusFetch shared targetHost model

        GotLiveStatus requestId (Ok ( maybeAccountsPanelMsg, now, report )) ->
            let
                live : LiveStatus
                live =
                    model.liveStatus

                settled : LiveStatus
                settled =
                    { live | inFlight = max 0 (live.inFlight - 1) }
            in
            ( { model
                | liveStatus =
                    -- A reply to a request older than one already applied (a pre-save check landing
                    -- after the post-save one) only settles the in-flight count.
                    if Status.replyIsFresh live.appliedSeq requestId then
                        { settled | report = Just report, error = Nothing, now = now, appliedSeq = requestId }

                    else
                        settled
              }
              -- The token refresh must be kept even from a stale reply.
            , Common.accountsPanelEffect maybeAccountsPanelMsg
            )

        GotLiveStatus requestId (Err err) ->
            let
                live : LiveStatus
                live =
                    model.liveStatus

                settled : LiveStatus
                settled =
                    { live | inFlight = max 0 (live.inFlight - 1) }
            in
            ( { model
                | liveStatus =
                    if Status.replyIsFresh live.appliedSeq requestId then
                        { settled
                            | error = Just (statusErrorText err)
                            , appliedSeq = requestId

                            -- A `NetworkError` is the connection not having settled yet (see module
                            -- doc), not an answer: let the next activation/config landing try again.
                            , requested = live.requested && err /= Grpc.NetworkError
                        }

                    else
                        settled
              }
            , Effect.none
            )

        StatusChecksToggled key ->
            ( { model | toggledChecks = toggleSetMember key model.toggledChecks }, Effect.none )

        StatusTick now ->
            let
                live : LiveStatus
                live =
                    model.liveStatus
            in
            ( { model | liveStatus = { live | now = now } }, Effect.none )

        CopyClicked text ->
            ( { model | copied = Just text }, DnsView.copyEffect CopiedReset text )

        CopiedReset text ->
            if model.copied == Just text then
                ( { model | copied = Nothing }, Effect.none )

            else
                ( model, Effect.none )


{-| Whether a `GetContactIntegrationsStatus` call is currently in flight.
-}
isFetchingStatus : LiveStatus -> Bool
isFetchingStatus live =
    live.inFlight > 0


{-| Marks a status fetch as started and fires it -- a no-op without an admin account (the RPC is
admin-only). Always fires, even if one is already in flight (a provider save just changed what it
would report); `inFlight` counts them so "fetching" only clears once the last one lands.
-}
startStatusFetch : Shared.Model -> String -> Model -> ( Model, Effect Msg )
startStatusFetch shared targetHost model =
    case Common.adminAccountFor shared targetHost of
        Just account ->
            let
                live : LiveStatus
                live =
                    model.liveStatus
            in
            ( { model | liveStatus = { live | inFlight = live.inFlight + 1, requestSeq = live.requestSeq + 1, requested = True, error = Nothing } }
            , fetchLiveStatus shared targetHost account (live.requestSeq + 1)
            )

        Nothing ->
            ( model, Effect.none )


{-| `GetContactIntegrationsStatus` as `account` -- slow (the server calls each provider's API and
does DNS lookups), hence the generous timeout, and stamped with the browser clock on arrival for
"Checked 2 minutes ago".
-}
fetchLiveStatus : Shared.Model -> String -> RellmAccount -> Int -> Effect Msg
fetchLiveStatus shared targetHost account requestId =
    AccountsPanel.performWithAccountServer shared.accounts
        ( Just account.userId, targetHost )
        (\server token ->
            Grpc.new Rellm.getContactIntegrationsStatus {}
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> Grpc.setTimeout 90000
                |> RellmServers.withAccessToken (Just token)
                |> Grpc.toTask
        )
        |> Task.andThen (\( maybeAccountsPanelMsg, report ) -> Time.now |> Task.map (\now -> ( maybeAccountsPanelMsg, now, report )))
        |> Task.attempt (GotLiveStatus requestId)
        |> Effect.fromCmd


{-| A friendly sentence for a failed status check -- most notably an older server that doesn't have
the RPC yet (`Unimplemented`).
-}
statusErrorText : Grpc.Error -> String
statusErrorText err =
    case err of
        Grpc.BadStatus { status } ->
            case status of
                Grpc.Unimplemented ->
                    "This server doesn't support live status checks yet -- it may need to be updated."

                Grpc.PermissionDenied ->
                    "Only server admins can run status checks."

                _ ->
                    AccountsPanel.grpcErrorToString err

        _ ->
            AccountsPanel.grpcErrorToString err


{-| Applies a non-save `OrderMsg` to a preference editor. `current` is what's stored (what Edit
starts from), `all` every provider that may appear in the list.
-}
updateOrderEdit : List api -> List api -> OrderMsg -> Maybe (OrderEdit api) -> Maybe (OrderEdit api)
updateOrderEdit all current orderMsg maybeEdit =
    case orderMsg of
        OrderEditClicked ->
            Just { pending = current, addSelection = ProviderOrder.addSelectionAfter all Nothing current, status = AccountsPanel.Idle }

        OrderCancelClicked ->
            Nothing

        OrderSaveClicked ->
            maybeEdit

        OrderRemoveClicked index ->
            maybeEdit |> Maybe.map (withPending all (ProviderOrder.removeAt index))

        OrderMoveUpClicked index ->
            maybeEdit |> Maybe.map (withPending all (ProviderOrder.moveUp index))

        OrderMoveDownClicked index ->
            maybeEdit |> Maybe.map (withPending all (ProviderOrder.moveDown index))

        OrderAddSelectionChanged text ->
            maybeEdit |> Maybe.map (\edit -> { edit | addSelection = all |> List.filter (\api -> orderKey all api == text) |> List.head })

        OrderAddClicked ->
            maybeEdit
                |> Maybe.map
                    (\edit ->
                        case edit.addSelection of
                            Just api ->
                                withPending all (ProviderOrder.append api) edit

                            Nothing ->
                                edit
                    )


{-| The `<option value>` of a provider in `all` -- its position, so it works for any enum.
-}
orderKey : List api -> api -> String
orderKey all api =
    all
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, candidate ) -> candidate == api)
        |> List.head
        |> Maybe.map (Tuple.first >> String.fromInt)
        |> Maybe.withDefault ""


withPending : List api -> (List api -> List api) -> OrderEdit api -> OrderEdit api
withPending all f edit =
    let
        pending : List api
        pending =
            f edit.pending
    in
    { edit | pending = pending, addSelection = ProviderOrder.addSelectionAfter all edit.addSelection pending }


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
                    , telnyxWebhookSigningKey = edit.webhookSigningKey
                    , useTelnyxWebhookSigningKey = edit.useWebhookSigningKey
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
                    , twilioWebhookSigningKey = edit.webhookSigningKey
                    , useTwilioWebhookSigningKey = edit.useWebhookSigningKey
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
                    , birdWebhookSigningKey = edit.webhookSigningKey
                    , useBirdWebhookSigningKey = edit.useWebhookSigningKey
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

{-| `SmsContactProtocolToggled`/`EmailContactProtocolToggled`'s transform -- flips whether `protocol`
is present in the freshly re-fetched `config.supportedContactProtocols`, leaving every other entry
(and every other field) untouched. The actual invariant enforcement ("TEL only with a configured SMS
provider, MAILTO never") lives entirely server-side (`validate_configuration`'s own `ContactProtocol`
check) -- this just toggles the one bit and lets `GotSmsContactProtocolSaveResult`/
`GotEmailContactProtocolSaveResult` surface whatever `Err` comes back (see `Common.editErrorView`
in `emailConfigurationSection`/`smsConfigurationSection`), per this feature's own "just show the
server error" design.
-}
toggleContactProtocol : ContactProtocol -> ServerConfiguration -> ServerConfiguration
toggleContactProtocol protocol config =
    { config
        | supportedContactProtocols =
            if List.member protocol config.supportedContactProtocols then
                List.filter ((/=) protocol) config.supportedContactProtocols

            else
                protocol :: config.supportedContactProtocols
    }

{-| `AuthFeatureToggled`'s transform -- flips whether `feature` is in the freshly re-fetched
`config.authenticationFeatures`, leaving every other entry alone. (Whether SMS/email sign-in is
_allowed_ -- needs the matching `ContactProtocol` -- is validated server-side; the view just doesn't
offer the switch until the channel is on.)
-}
toggleAuthFeature : AuthenticationFeature -> ServerConfiguration -> ServerConfiguration
toggleAuthFeature feature config =
    { config
        | authenticationFeatures =
            if List.member feature config.authenticationFeatures then
                List.filter ((/=) feature) config.authenticationFeatures

            else
                config.authenticationFeatures ++ [ feature ]
    }


{-| Every `ContactVerificationAPI`, in the server's own fallback order (Telnyx, Bird, Twilio -- see
`preferred_verification_apis`'s proto doc) -- the Add dropdown's option list.
-}
allVerificationApis : List ContactVerificationAPI
allVerificationApis =
    [ CONTACTVERIFICATIONAPITELNYX, CONTACTVERIFICATIONAPIBIRD, CONTACTVERIFICATIONAPITWILIO ]


{-| Every `EmailVerificationAPI`, in the server's fallback order (`preferred_email_apis`'s proto doc).
-}
allEmailApis : List EmailVerificationAPI
allEmailApis =
    [ EMAILVERIFICATIONAPIPOSTMARK, EMAILVERIFICATIONAPISENDGRID, EMAILVERIFICATIONAPIMAILGUN, EMAILVERIFICATIONAPISTALWART ]


verificationApiText : ContactVerificationAPI -> String
verificationApiText api =
    case api of
        CONTACTVERIFICATIONAPITELNYX ->
            "Telnyx"

        CONTACTVERIFICATIONAPITWILIO ->
            "Twilio"

        CONTACTVERIFICATIONAPIBIRD ->
            "Bird"

        ContactVerificationAPIUnrecognized_ _ ->
            "Unknown"


emailApiText : EmailVerificationAPI -> String
emailApiText api =
    case api of
        EMAILVERIFICATIONAPIPOSTMARK ->
            "Postmark"

        EMAILVERIFICATIONAPISENDGRID ->
            "SendGrid"

        EMAILVERIFICATIONAPIMAILGUN ->
            "Mailgun"

        EMAILVERIFICATIONAPISTALWART ->
            "Stalwart"

        EmailVerificationAPIUnrecognized_ _ ->
            "Unknown"


-- VIEW


{-| `server` is only needed for `webPushSection` (see module doc -- `webPushConfig` isn't
admin-only-stripped, so it doesn't need to wait on the admin fetch the way every provider section
does), mirroring exactly how `FederationTab.view` takes its own `server` for the same reason.
-}
view : RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view server maybeAdminAccount model =
    div [ classes [ "server-details-tab-content", "server-details-sign-in-and-contact", "sc-root" ] ]
        (case maybeAdminAccount of
            Nothing ->
                [ div [ class "sc-intro" ]
                    [ h2 [ class "sc-title" ] [ text "Sign in & contact" ]
                    , p [ class "sc-lead" ] [ text "Sign in as an admin of this server to see and manage how people sign in and how it contacts them." ]
                    ]
                , webPushSection server model maybeAdminAccount
                ]

            Just _ ->
                case model.adminSignInAndContact of
                    AdminSignInAndContactLoaded config ->
                        [ introView model
                        , signInSection model config
                        , smsSection model maybeAdminAccount config
                        , emailSection model maybeAdminAccount config
                        , webPushSection server model maybeAdminAccount
                        ]

                    AdminSignInAndContactFetchFailed err ->
                        [ introView model
                        , div [ classes [ "sc-section", "sc-failed" ] ]
                            [ p [] [ text ("Couldn't load the integration settings: " ++ err) ]
                            , button [ type_ "button", class "server-details-rename-button", onClick SignInAndContactTabActivated ] [ text "Try again" ]
                            ]
                        , webPushSection server model maybeAdminAccount
                        ]

                    _ ->
                        [ introView model
                        , loadingSkeleton
                        , webPushSection server model maybeAdminAccount
                        ]
        )


{-| Placeholder blocks while the admin configuration fetch is in flight.
-}
loadingSkeleton : Html Msg
loadingSkeleton =
    div [ class "sc-skeleton", attribute "aria-busy" "true" ]
        (List.repeat 2
            (div [ class "sc-section" ]
                [ StatusView.shimmerLine 35
                , StatusView.shimmerLine 80
                , StatusView.shimmerLine 60
                ]
            )
        )


statusHandlers : Model -> StatusView.Handlers Msg
statusHandlers model =
    { toggleChecks = StatusChecksToggled
    , copy = CopyClicked
    , copied = model.copied
    }


{-| The tab's title, a friendly one-paragraph orientation, and the overall status toolbar
(`statusToolbar`).
-}
introView : Model -> Html Msg
introView model =
    div [ class "sc-intro" ]
        [ h2 [ class "sc-title" ] [ text "Sign in & contact" ]
        , p [ class "sc-lead" ]
            [ text "How people sign in and sign up, and how this server contacts them: verification codes, sign-in codes and notifications by text message and email. Choose the ways people can get in, switch each channel on, pick the providers that send for it, and check that everything is healthy." ]
        , statusToolbar model
        ]


{-| The overall "Check status"/"Refresh" button, a spinner while a check runs, "Checked 2 minutes
ago", and any inline error from the last check.
-}
statusToolbar : Model -> Html Msg
statusToolbar model =
    let
        live : LiveStatus
        live =
            model.liveStatus
    in
    div [ class "sc-toolbar" ]
        [ refreshButton False model
        , case live.report of
            Just report ->
                span [ class "sc-checked-at", title "When the server last gathered this report" ]
                    [ text
                        (Status.checkedAtLabel live.now report.checkedAt
                            ++ (if isFetchingStatus live then
                                    " · refreshing…"

                                else
                                    ""
                               )
                        )
                    ]

            Nothing ->
                text ""
        , case live.error of
            Just err ->
                div [ class "sc-inline-error", attribute "role" "alert" ] [ text ("Couldn't check status: " ++ err) ]

            Nothing ->
                text ""
        ]


refreshButton : Bool -> Model -> Html Msg
refreshButton compact model =
    let
        fetching : Bool
        fetching =
            isFetchingStatus model.liveStatus
    in
    button
        [ type_ "button"
        , classes
            ([ "sc-refresh", "server-details-rename-button" ]
                ++ (if compact then
                        [ "sc-refresh-compact" ]

                    else
                        []
                   )
            )
        , onClick StatusRefreshClicked
        , disabled fetching
        , title "Asks each provider's own API and looks up your domains' DNS records -- this can take a few seconds"
        ]
        [ if fetching then
            span [ class "sc-spinner", attribute "aria-hidden" "true" ] []

          else
            text ""
        , text
            (if fetching then
                "Checking…"

             else if model.liveStatus.report == Nothing then
                "Check status"

             else
                "Refresh"
            )
        ]



-- CHANNEL SECTIONS (SMS / EMAIL)


{-| Everything that differs between the SMS and Email sections.
-}
type alias Channel =
    { id : String
    , glyph : String
    , title : String
    , blurb : String
    , toggleLabel : String
    , enabled : Bool
    , onToggle : Msg
    , toggleStatus : AccountsPanel.FormStatus
    , providers : Maybe (List ProviderStatus)
    , offHint : String
    }


{-| A channel's header (icon, title, blurb, the master toggle), its health row, and then `content`
(the preference order and provider cards, and for Email the domains).
-}
channelSection : Model -> Channel -> List (Html Msg) -> Html Msg
channelSection model channel content =
    div
        [ classes
            ([ "sc-section", "sc-channel-" ++ channel.id ]
                ++ (if isFetchingStatus model.liveStatus && model.liveStatus.report /= Nothing then
                        [ "is-refreshing" ]

                    else
                        []
                   )
            )
        ]
        ([ div [ class "sc-section-header" ]
            [ span [ class "sc-section-icon", attribute "aria-hidden" "true" ] [ text channel.glyph ]
            , h3 [ class "sc-section-title" ] [ text channel.title ]
            , span [ class "sc-master" ]
                [ span [ class "sc-master-label" ] [ text channel.toggleLabel ]
                , if channel.toggleStatus == AccountsPanel.Submitting then
                    Common.switchDisplay channel.enabled

                  else
                    Common.flagSwitch channel.enabled channel.onToggle
                ]
            ]
         , Common.editErrorView channel.toggleStatus
         , p [ class "sc-section-blurb" ]
            [ text
                (if channel.enabled then
                    channel.blurb

                 else
                    channel.offHint
                )
            ]
         , healthRow model channel.providers
         ]
            ++ content
        )


{-| One line: a level pill, what it means, and a compact Refresh button. Shimmers while the first
check is running; a muted "Not checked yet" before it.
-}
healthRow : Model -> Maybe (List ProviderStatus) -> Html Msg
healthRow model maybeProviders =
    div [ class "sc-health-row" ]
        (case maybeProviders of
            Just providers ->
                let
                    health : { level : StatusLevel, summary : String }
                    health =
                        Status.sectionHealth providers
                in
                [ StatusView.levelPill health.level Nothing
                , span [ class "sc-health-summary" ] [ text health.summary ]
                , refreshButton True model
                ]

            Nothing ->
                if isFetchingStatus model.liveStatus then
                    [ StatusView.shimmerPill
                    , StatusView.shimmerLine 40
                    ]

                else
                    [ StatusView.levelPill STATUSLEVELUNKNOWN (Just "Not checked yet")
                    , span [ class "sc-health-summary" ]
                        [ text
                            (if model.liveStatus.error == Nothing then
                                "Run a check to see how things are doing."

                             else
                                "The last check didn't finish."
                            )
                        ]
                    , refreshButton True model
                    ]
        )


smsSection : Model -> Maybe RellmAccount -> ServerConfiguration -> Html Msg
smsSection model maybeAdminAccount config =
    channelSection model
        { id = "sms"
        , glyph = Glyph.textPresentation "☎"
        , title = "Text messages (SMS)"
        , blurb = "Text messages for phone-number verification codes and sign-in. Providers are tried in the order below."
        , toggleLabel = "Enable SMS Sending"
        , enabled = List.member CONTACTPROTOCOLTEL config.supportedContactProtocols
        , onToggle = SmsContactProtocolToggled
        , toggleStatus = model.smsContactProtocolStatus
        , providers = model.liveStatus.report |> Maybe.map .smsProviders
        , offHint = "SMS is switched off, so no texts are sent. Set up a provider below, then switch it on."
        }
        [ orderView
            { title = "Provider order"
            , blurb = "The server tries these first, in this order. Any other enabled provider is a fallback (Telnyx, then Bird, then Twilio)."
            , emptyNote = "No preference set -- the first enabled provider (Telnyx, Bird, Twilio) is used."
            , current = config.preferredVerificationApis
            , editing = model.preferredProvidersEdit
            , all = allVerificationApis
            , label = verificationApiText
            , toMsg = SmsOrderMsg
            , isAdmin = maybeAdminAccount /= Nothing
            }
        , providerCard model
            { section = TwilioIntegrationSection
            , name = "Twilio"
            , tagline = "The classic SMS API"
            , enabled = config.twilioConfig |> Maybe.map .twilioEnabled |> Maybe.withDefault False
            , status = smsProviderStatus model "twilio"
            , body =
                case model.configEdit of
                    Just edit ->
                        twilioEditView edit

                    Nothing ->
                        twilioDisplayView maybeAdminAccount config.twilioConfig
            }
        , providerCard model
            { section = BirdIntegrationSection
            , name = "Bird"
            , tagline = "A cheaper alternative to Twilio"
            , enabled = config.birdConfig |> Maybe.map .birdEnabled |> Maybe.withDefault False
            , status = smsProviderStatus model "bird"
            , body =
                case model.birdConfigEdit of
                    Just edit ->
                        birdEditView edit

                    Nothing ->
                        birdDisplayView maybeAdminAccount config.birdConfig
            }
        , providerCard model
            { section = TelnyxIntegrationSection
            , name = "Telnyx"
            , tagline = "Messaging profiles and a v2 API key"
            , enabled = config.telnyxConfig |> Maybe.map .telnyxEnabled |> Maybe.withDefault False
            , status = smsProviderStatus model "telnyx"
            , body =
                case model.telnyxConfigEdit of
                    Just edit ->
                        telnyxEditView edit

                    Nothing ->
                        telnyxDisplayView maybeAdminAccount config.telnyxConfig
            }
        ]


emailSection : Model -> Maybe RellmAccount -> ServerConfiguration -> Html Msg
emailSection model maybeAdminAccount config =
    let
        stalwart : Maybe Proto.Rellm.StalwartConfig
        stalwart =
            config.stalwartConfig
    in
    channelSection model
        { id = "email"
        , glyph = Glyph.textPresentation "✉"
        , title = "Email"
        , blurb = "Email for address-verification codes and sign-in. Providers are tried in the order below."
        , toggleLabel = "Enable Email Sending"
        , enabled = List.member CONTACTPROTOCOLMAILTO config.supportedContactProtocols
        , onToggle = EmailContactProtocolToggled
        , toggleStatus = model.emailContactProtocolStatus
        , providers = model.liveStatus.report |> Maybe.map .emailProviders
        , offHint = "Email is switched off, so no email is sent. Set up a provider below, then switch it on."
        }
        [ orderView
            { title = "Provider order"
            , blurb = "The server tries these first, in this order. Any other enabled provider is a fallback (Postmark, SendGrid, Mailgun, then Stalwart)."
            , emptyNote = "No preference set -- the first enabled provider (Postmark, SendGrid, Mailgun, Stalwart) is used."
            , current = config.preferredEmailApis
            , editing = model.preferredEmailProvidersEdit
            , all = allEmailApis
            , label = emailApiText
            , toMsg = EmailOrderMsg
            , isAdmin = maybeAdminAccount /= Nothing
            }
        , providerCard model
            { section = PostmarkIntegrationSection
            , name = "Postmark"
            , tagline = "Transactional email API"
            , enabled = config.postmarkConfig |> Maybe.map .postmarkEnabled |> Maybe.withDefault False
            , status = emailProviderStatus model "postmark"
            , body =
                case model.postmarkEdit of
                    Just edit ->
                        postmarkEditView edit

                    Nothing ->
                        postmarkDisplayView maybeAdminAccount config.postmarkConfig
            }
        , providerCard model
            { section = SendgridIntegrationSection
            , name = "SendGrid"
            , tagline = "Twilio SendGrid's v3 Mail Send API"
            , enabled = config.sendgridConfig |> Maybe.map .sendgridEnabled |> Maybe.withDefault False
            , status = emailProviderStatus model "sendgrid"
            , body =
                case model.sendgridEdit of
                    Just edit ->
                        sendgridEditView edit

                    Nothing ->
                        sendgridDisplayView maybeAdminAccount config.sendgridConfig
            }
        , providerCard model
            { section = MailgunIntegrationSection
            , name = "Mailgun"
            , tagline = "Messages API with a sending domain"
            , enabled = config.mailgunConfig |> Maybe.map .mailgunEnabled |> Maybe.withDefault False
            , status = emailProviderStatus model "mailgun"
            , body =
                case model.mailgunEdit of
                    Just edit ->
                        mailgunEditView edit

                    Nothing ->
                        mailgunDisplayView maybeAdminAccount config.mailgunConfig
            }
        , providerCard model
            { section = StalwartIntegrationSection
            , name = "Stalwart"
            , tagline = "Your own in-cluster mail server"
            , enabled = (stalwart |> Maybe.map .stalwartSendingEnabled |> Maybe.withDefault False) || (stalwart |> Maybe.map .stalwartReceivingEnabled |> Maybe.withDefault False)
            , status = emailProviderStatus model "stalwart"
            , body =
                stalwartReceivingRows model stalwart
                    ++ (case model.stalwartEdit of
                            Just edit ->
                                stalwartEditView edit

                            Nothing ->
                                stalwartDisplayView maybeAdminAccount stalwart
                       )
            }
        , emailDomainsView model config
        ]


smsProviderStatus : Model -> String -> Maybe ProviderStatus
smsProviderStatus model provider =
    model.liveStatus.report |> Maybe.andThen (\report -> Status.findProvider provider report.smsProviders)


emailProviderStatus : Model -> String -> Maybe ProviderStatus
emailProviderStatus model provider =
    model.liveStatus.report |> Maybe.andThen (\report -> Status.findProvider provider report.emailProviders)



-- PROVIDER ORDER


type alias OrderView api =
    { title : String
    , blurb : String
    , emptyNote : String
    , current : List api
    , editing : Maybe (OrderEdit api)
    , all : List api
    , label : api -> String
    , toMsg : OrderMsg -> Msg
    , isAdmin : Bool
    }


{-| The provider preference order: numbered chips when displaying, an editor with move-up/move-down/
remove buttons, an Add dropdown and Save/Cancel while editing (`ProviderOrder` has the list logic).
-}
orderView : OrderView api -> Html Msg
orderView config =
    case config.editing of
        Just edit ->
            let
                busy : Bool
                busy =
                    edit.status == AccountsPanel.Submitting
            in
            div [ classes [ "sc-order", "sc-order-editing" ] ]
                [ h4 [ class "sc-order-title" ] [ text config.title ]
                , p [ class "sc-order-blurb" ] [ text config.blurb ]
                , if List.isEmpty edit.pending then
                    p [ class "sc-muted" ] [ text config.emptyNote ]

                  else
                    Html.ol [ class "sc-order-list" ]
                        (edit.pending
                            |> List.indexedMap
                                (\index api ->
                                    Html.li [ class "sc-order-item" ]
                                        [ span [ class "sc-order-num" ] [ text (String.fromInt (index + 1)) ]
                                        , span [ class "sc-order-label" ] [ text (config.label api) ]
                                        , span [ class "sc-order-actions" ]
                                            [ orderButton "↑" "Move up" (config.toMsg (OrderMoveUpClicked index)) (busy || index == 0)
                                            , orderButton "↓" "Move down" (config.toMsg (OrderMoveDownClicked index)) (busy || index == List.length edit.pending - 1)
                                            , orderButton "✕" ("Remove " ++ config.label api) (config.toMsg (OrderRemoveClicked index)) busy
                                            ]
                                        ]
                                )
                        )
                , div [ class "sc-order-add" ]
                    [ select
                        [ onInput (OrderAddSelectionChanged >> config.toMsg)
                        , disabled (busy || List.isEmpty (ProviderOrder.addable config.all edit.pending))
                        , attribute "aria-label" "Provider to add"
                        ]
                        (ProviderOrder.addable config.all edit.pending
                            |> List.map
                                (\api ->
                                    option
                                        [ value (orderKey config.all api)
                                        , selected (edit.addSelection == Just api)
                                        ]
                                        [ text (config.label api) ]
                                )
                        )
                    , button
                        [ type_ "button"
                        , class "server-details-rename-button"
                        , onClick (config.toMsg OrderAddClicked)
                        , disabled (edit.addSelection == Nothing || busy)
                        ]
                        [ text "Add provider" ]
                    ]
                , div [ class "server-details-feature-settings-actions" ]
                    [ Common.editSaveButton (config.toMsg OrderSaveClicked) edit.status
                    , Common.editCancelButton (config.toMsg OrderCancelClicked) edit.status
                    ]
                , Common.editErrorView edit.status
                ]

        Nothing ->
            div [ class "sc-order" ]
                [ div [ class "sc-order-head" ]
                    [ h4 [ class "sc-order-title" ] [ text config.title ]
                    , if config.isAdmin then
                        button [ type_ "button", class "server-details-rename-button", onClick (config.toMsg OrderEditClicked) ] [ text "Change order" ]

                      else
                        text ""
                    ]
                , p [ class "sc-order-blurb" ] [ text config.blurb ]
                , if List.isEmpty config.current then
                    p [ class "sc-muted" ] [ text config.emptyNote ]

                  else
                    Html.ol [ class "sc-order-list" ]
                        (config.current
                            |> List.indexedMap
                                (\index api ->
                                    Html.li [ class "sc-order-item" ]
                                        [ span [ class "sc-order-num" ] [ text (String.fromInt (index + 1)) ]
                                        , span [ class "sc-order-label" ] [ text (config.label api) ]
                                        ]
                                )
                        )
                ]


orderButton : String -> String -> Msg -> Bool -> Html Msg
orderButton glyph label msg isDisabled =
    button
        [ type_ "button"
        , class "sc-icon-button"
        , title label
        , attribute "aria-label" label
        , onClick msg
        , disabled isDisabled
        ]
        [ text glyph ]



-- PROVIDER CARDS


type alias Card =
    { section : ProviderSection
    , name : String
    , tagline : String
    , enabled : Bool
    , status : Maybe ProviderStatus
    , body : List (Html Msg)
    }


{-| One collapsible provider card: header (arrow, name, tagline, level pill), then -- always mounted,
folded by CSS -- its live status block above its configuration rows.
-}
providerCard : Model -> Card -> Html Msg
providerCard model card =
    let
        expanded : Bool
        expanded =
            providerSectionExpanded model card.section

        live : LiveStatus
        live =
            model.liveStatus

        level : StatusLevel
        level =
            case card.status of
                Just status ->
                    status.level

                Nothing ->
                    STATUSLEVELDISABLED
    in
    div [ classes [ "sc-card", "sc-level-" ++ Status.levelKey level ] ]
        [ button
            [ type_ "button"
            , class "sc-card-header"
            , onClick (ProviderSectionToggled card.section)
            , attribute "aria-expanded"
                (if expanded then
                    "true"

                 else
                    "false"
                )
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , span [ class "sc-card-title" ]
                [ span [ class "sc-card-name" ] [ text card.name ]
                , span [ class "sc-card-tagline" ] [ text card.tagline ]
                ]
            , span [ class "sc-card-state" ]
                [ case card.status of
                    Just status ->
                        StatusView.levelPill status.level Nothing

                    Nothing ->
                        if isFetchingStatus live && live.report == Nothing then
                            StatusView.shimmerPill

                        else
                            span
                                [ classes
                                    [ "sc-badge"
                                    , if card.enabled then
                                        "sc-badge-on"

                                      else
                                        "sc-badge-off"
                                    ]
                                ]
                                [ text
                                    (if card.enabled then
                                        "On"

                                     else
                                        "Off"
                                    )
                                ]
                ]
            ]
        , div [ classes [ "sc-collapse", openClosedClass expanded ] ]
            [ div [ class "sc-card-body" ]
                (case card.status of
                    Just status ->
                        StatusView.providerStatusBlock (statusHandlers model) model.toggledChecks (statusKey card.section) status
                            :: card.body

                    Nothing ->
                        if isFetchingStatus live && live.report == Nothing then
                            div [ class "sc-status-block" ] [ StatusView.shimmerLine 70, StatusView.shimmerLine 45 ]
                                :: card.body

                        else
                            card.body
                )
            ]
        ]


statusKey : ProviderSection -> String
statusKey section =
    "provider/" ++ providerSectionKey section



-- EMAIL DOMAINS


{-| The "Email domains" subsection of the Email section: SPF/DKIM/DMARC state per sending domain
(from the live report), with a friendly empty state while no email provider is set up.
-}
emailDomainsView : Model -> ServerConfiguration -> Html Msg
emailDomainsView model config =
    let
        anyProviderOn : Bool
        anyProviderOn =
            (config.postmarkConfig |> Maybe.map .postmarkEnabled |> Maybe.withDefault False)
                || (config.sendgridConfig |> Maybe.map .sendgridEnabled |> Maybe.withDefault False)
                || (config.mailgunConfig |> Maybe.map .mailgunEnabled |> Maybe.withDefault False)
                || (config.stalwartConfig |> Maybe.map .stalwartSendingEnabled |> Maybe.withDefault False)
    in
    div [ class "sc-domains-section" ]
        [ h4 [ class "sc-subsection-title" ] [ text "Email domains" ]
        , p [ class "sc-order-blurb" ]
            [ text "Gmail, Outlook and others check these DNS records before trusting your mail." ]
        , StatusView.emailExplainer (statusHandlers model) model.toggledChecks
        , if not anyProviderOn then
            StatusView.domainsSection (statusHandlers model) model.toggledChecks Proto.Rellm.defaultContactIntegrationsStatus

          else
            case model.liveStatus.report of
                Just report ->
                    StatusView.domainsSection (statusHandlers model) model.toggledChecks report

                Nothing ->
                    if isFetchingStatus model.liveStatus then
                        div [ class "sc-domain-card" ] [ StatusView.shimmerLine 40, StatusView.shimmerLine 85, StatusView.shimmerLine 60 ]

                    else
                        div [ class "sc-empty" ]
                            [ span [ class "sc-empty-text" ] [ text "Run a status check to see your domains' DNS records." ] ]
        ]



-- SIGN-IN & SIGN-UP


{-| "Sign in & sign up": which ways people may create an account or log in. The SMS/email switches
only work once their channel is enabled (and stay editable if one is already on, so it can be
turned off); password sign-in/sign-up always work for now (`authentication_features`' proto doc), so
those two are shown on and locked.
-}
signInSection : Model -> ServerConfiguration -> Html Msg
signInSection model config =
    let
        smsOn : Bool
        smsOn =
            List.member CONTACTPROTOCOLTEL config.supportedContactProtocols

        emailOn : Bool
        emailOn =
            List.member CONTACTPROTOCOLMAILTO config.supportedContactProtocols

        authSwitch : Bool -> AuthenticationFeature -> Html Msg
        authSwitch channelOn feature =
            let
                on : Bool
                on =
                    List.member feature config.authenticationFeatures
            in
            if model.authFeaturesStatus == AccountsPanel.Submitting || (not channelOn && not on) then
                Common.switchDisplay on

            else
                Common.flagSwitch on (AuthFeatureToggled feature)

        authRow : String -> String -> Html Msg -> Html Msg -> Html Msg
        authRow label note signUp signIn =
            div [ class "sc-auth-row" ]
                [ div [ class "sc-auth-what" ]
                    [ span [ class "sc-auth-label" ] [ text label ]
                    , span [ class "sc-auth-note" ] [ text note ]
                    ]
                , span [ class "sc-auth-cell" ] [ signUp ]
                , span [ class "sc-auth-cell" ] [ signIn ]
                ]
    in
    div [ classes [ "sc-section", "sc-channel-auth" ] ]
        [ div [ class "sc-section-header" ]
            [ span [ class "sc-section-icon", attribute "aria-hidden" "true" ] [ text "→" ]
            , h3 [ class "sc-section-title" ] [ text "Sign in & sign up" ]
            ]
        , p [ class "sc-section-blurb" ]
            [ text "Choose how people can create an account and sign in. To use a phone number or email address to sign in, a person first has to verify it -- we send a code and they enter it -- so they'll need to add and verify it under Contact Methods on their profile." ]
        , div [ class "sc-auth-grid" ]
            [ div [ class "sc-auth-row sc-auth-head" ]
                [ span [ class "sc-auth-what" ] []
                , span [ class "sc-auth-cell" ] [ text "Sign up" ]
                , span [ class "sc-auth-cell" ] [ text "Sign in" ]
                ]
            , authRow "Password"
                "Always allowed for now."
                (Common.switchDisplay True)
                (Common.switchDisplay True)
            , authRow "Text message (SMS)"
                (if smsOn then
                    "A code sent to a verified phone number."

                 else
                    "Enable SMS sending below first."
                )
                (authSwitch smsOn CREATEACCOUNTWITHSMS)
                (authSwitch smsOn LOGINWITHSMS)
            , authRow "Email"
                (if emailOn then
                    "A code sent to a verified email address."

                 else
                    "Enable email sending below first."
                )
                (authSwitch emailOn CREATEACCOUNTWITHEMAIL)
                (authSwitch emailOn LOGINWITHEMAIL)
            ]
        , Common.editErrorView model.authFeaturesStatus
        ]



-- WEB PUSH


{-| Mirrors `FederationTab`'s old `facebookAuthConfigSection`: the read-only Public VAPID key
(needed by any browser calling `pushManager.subscribe`, see `Shared.AccountsPanel`'s "Enable
notifications") is shown to everyone, same as Facebook's App ID; the Private VAPID key (needed only
to sign outgoing pushes, see `backend/src/web_push`) is admin-only, same as Facebook's App Secret.
-}
webPushSection : RellmServer -> Model -> Maybe RellmAccount -> Html Msg
webPushSection server model maybeAdminAccount =
    let
        currentPublicKey : String
        currentPublicKey =
            (RellmServers.configurationOf server).webPushConfig
                |> Maybe.map .publicVapidKey
                |> Maybe.withDefault ""
    in
    div [ classes [ "sc-section", "sc-channel-webpush", "server-details-facebook-auth" ] ]
        (div [ class "sc-section-header" ]
            [ span [ class "sc-section-icon", attribute "aria-hidden" "true" ] [ text "•" ]
            , h3 [ class "sc-section-title" ] [ text "Web Push" ]
            ]
            :: p [ class "sc-section-blurb" ] [ text "The VAPID key pair browsers use to receive push notifications from this server." ]
            :: webPushPublicKeyRow currentPublicKey model.webPushPublicKeyEdit maybeAdminAccount
            :: (case maybeAdminAccount of
                    Just _ ->
                        [ webPushPrivateKeyRow model.webPushPrivateKeyEdit maybeAdminAccount ]

                    Nothing ->
                        []
               )
        )



-- PROVIDER FORMS (new providers)


fieldRow :
    { label : String
    , placeholder : String
    , value : String
    , onInput : String -> Msg
    , secret : Bool
    , busy : Bool
    , note : Maybe String
    }
    -> Html Msg
fieldRow config =
    div [ class "sc-field" ]
        [ Common.settingsRow config.label
            (input
                [ type_
                    (if config.secret then
                        "password"

                     else
                        "text"
                    )
                , class "server-details-rename-input"
                , placeholder config.placeholder
                , value config.value
                , onInput config.onInput
                , disabled config.busy
                , attribute "autocomplete" "off"
                ]
                []
            )
        , case config.note of
            Just note ->
                Common.settingsNote note

            Nothing ->
                text ""
        ]


secretRow : String -> String -> Bool -> (String -> Msg) -> String -> Html Msg
secretRow label note busy toMsg current =
    fieldRow
        { label = label
        , placeholder = "Leave blank to keep the current one"
        , value = current
        , onInput = toMsg
        , secret = True
        , busy = busy
        , note =
            if String.isEmpty note then
                Nothing

            else
                Just note
        }


textRow : String -> String -> Bool -> (String -> Msg) -> String -> Html Msg
textRow label placeholder_ busy toMsg current =
    fieldRow { label = label, placeholder = placeholder_, value = current, onInput = toMsg, secret = False, busy = busy, note = Nothing }


regionRow : String -> List ( String, String ) -> String -> Bool -> (String -> Msg) -> Html Msg
regionRow label options current busy toMsg =
    Common.settingsRow label
        (select [ onInput toMsg, disabled busy ]
            (options
                |> List.map
                    (\( optionValue, optionLabel ) ->
                        option [ value optionValue, selected (current == optionValue) ] [ text optionLabel ]
                    )
            )
        )


valueText : String -> Html msg
valueText content =
    span [ class "server-details-feature-settings-value" ]
        [ text
            (if String.isEmpty content then
                "—"

             else
                content
            )
        ]


fromLine : String -> String -> String
fromLine name address =
    if String.isEmpty address then
        ""

    else if String.isEmpty name then
        address

    else
        name ++ " <" ++ address ++ ">"


editButton : Maybe RellmAccount -> Msg -> String -> Html Msg
editButton maybeAdminAccount msg label =
    case maybeAdminAccount of
        Just _ ->
            button [ type_ "button", class "server-details-rename-button", onClick msg ] [ text label ]

        Nothing ->
            text ""


formActions : Msg -> Msg -> AccountsPanel.FormStatus -> List (Html Msg)
formActions onSave onCancel status =
    [ div [ class "server-details-feature-settings-actions" ]
        [ Common.editSaveButton onSave status
        , Common.editCancelButton onCancel status
        ]
    , Common.editErrorView status
    ]


postmarkDisplayView : Maybe RellmAccount -> Maybe Proto.Rellm.PostmarkConfig -> List (Html Msg)
postmarkDisplayView maybeAdminAccount maybeConfig =
    let
        config : Proto.Rellm.PostmarkConfig
        config =
            Maybe.withDefault Proto.Rellm.defaultPostmarkConfig maybeConfig
    in
    [ Common.settingsRow "Postmark Enabled" (Common.switchDisplay config.postmarkEnabled)
    , Common.settingsRow "From" (valueText (fromLine config.postmarkFromName config.postmarkFromAddress))
    , Common.settingsRow "Message Stream" (valueText (if String.isEmpty config.postmarkMessageStream then "outbound (default)" else config.postmarkMessageStream))
    , editButton maybeAdminAccount PostmarkEditClicked "Edit Postmark Settings"
    ]


postmarkEditView : Editing PostmarkForm -> List (Html Msg)
postmarkEditView edit =
    let
        busy : Bool
        busy =
            edit.status == AccountsPanel.Submitting

        form : PostmarkForm
        form =
            edit.form
    in
    [ Common.settingsRow "Postmark Enabled" (Common.flagSwitch form.enabled PostmarkEnabledToggled)
    , secretRow "Server API Token" "Sent as X-Postmark-Server-Token." busy (PostmarkFieldChanged PostmarkServerToken) form.serverToken
    , secretRow "Account API Token" "Optional. Only used to read your domains' DKIM and Return-Path status for the health check." busy (PostmarkFieldChanged PostmarkAccountToken) form.accountToken
    , textRow "From Address" "login@example.com" busy (PostmarkFieldChanged PostmarkFromAddress) form.fromAddress
    , textRow "From Name" "Example (optional)" busy (PostmarkFieldChanged PostmarkFromName) form.fromName
    , textRow "Message Stream" "outbound" busy (PostmarkFieldChanged PostmarkMessageStream) form.messageStream
    ]
        ++ formActions PostmarkSaveClicked PostmarkCancelClicked edit.status


sendgridDisplayView : Maybe RellmAccount -> Maybe Proto.Rellm.SendgridConfig -> List (Html Msg)
sendgridDisplayView maybeAdminAccount maybeConfig =
    let
        config : Proto.Rellm.SendgridConfig
        config =
            Maybe.withDefault Proto.Rellm.defaultSendgridConfig maybeConfig
    in
    [ Common.settingsRow "SendGrid Enabled" (Common.switchDisplay config.sendgridEnabled)
    , Common.settingsRow "From" (valueText (fromLine config.sendgridFromName config.sendgridFromAddress))
    , Common.settingsRow "Region" (valueText (if config.sendgridRegion == "eu" then "EU" else "Global (default)"))
    , editButton maybeAdminAccount SendgridEditClicked "Edit SendGrid Settings"
    ]


sendgridEditView : Editing SendgridForm -> List (Html Msg)
sendgridEditView edit =
    let
        busy : Bool
        busy =
            edit.status == AccountsPanel.Submitting

        form : SendgridForm
        form =
            edit.form
    in
    [ Common.settingsRow "SendGrid Enabled" (Common.flagSwitch form.enabled SendgridEnabledToggled)
    , secretRow "API Key" "Needs \"Mail Send\"; add \"Domain Authentication\" and \"Stats\" read access to light up the health check." busy (SendgridFieldChanged SendgridApiKey) form.apiKey
    , textRow "From Address" "login@example.com" busy (SendgridFieldChanged SendgridFromAddress) form.fromAddress
    , textRow "From Name" "Example (optional)" busy (SendgridFieldChanged SendgridFromName) form.fromName
    , regionRow "Region" [ ( "", "Global (api.sendgrid.com)" ), ( "eu", "EU (api.eu.sendgrid.com)" ) ] form.region busy (SendgridFieldChanged SendgridRegion)
    ]
        ++ formActions SendgridSaveClicked SendgridCancelClicked edit.status


mailgunDisplayView : Maybe RellmAccount -> Maybe Proto.Rellm.MailgunConfig -> List (Html Msg)
mailgunDisplayView maybeAdminAccount maybeConfig =
    let
        config : Proto.Rellm.MailgunConfig
        config =
            Maybe.withDefault Proto.Rellm.defaultMailgunConfig maybeConfig
    in
    [ Common.settingsRow "Mailgun Enabled" (Common.switchDisplay config.mailgunEnabled)
    , Common.settingsRow "Sending Domain" (valueText config.mailgunDomain)
    , Common.settingsRow "From" (valueText (fromLine config.mailgunFromName config.mailgunFromAddress))
    , Common.settingsRow "Region" (valueText (if config.mailgunRegion == "eu" then "EU" else "US (default)"))
    , editButton maybeAdminAccount MailgunEditClicked "Edit Mailgun Settings"
    ]


mailgunEditView : Editing MailgunForm -> List (Html Msg)
mailgunEditView edit =
    let
        busy : Bool
        busy =
            edit.status == AccountsPanel.Submitting

        form : MailgunForm
        form =
            edit.form
    in
    [ Common.settingsRow "Mailgun Enabled" (Common.flagSwitch form.enabled MailgunEnabledToggled)
    , secretRow "API Key" "" busy (MailgunFieldChanged MailgunApiKey) form.apiKey
    , textRow "Sending Domain" "mg.example.com" busy (MailgunFieldChanged MailgunDomain) form.domain
    , regionRow "Region" [ ( "us", "US (api.mailgun.net)" ), ( "eu", "EU (api.eu.mailgun.net)" ) ] (if form.region == "" then "us" else form.region) busy (MailgunFieldChanged MailgunRegion)
    , textRow "From Address" "login@mg.example.com" busy (MailgunFieldChanged MailgunFromAddress) form.fromAddress
    , textRow "From Name" "Example (optional)" busy (MailgunFieldChanged MailgunFromName) form.fromName
    ]
        ++ formActions MailgunSaveClicked MailgunCancelClicked edit.status


{-| Stalwart's instant "receiving" toggle -- separate from the sending form below it, and only ever
touching `stalwartReceivingEnabled` (see `EmailEdits.toggleStalwartReceiving`).
-}
stalwartReceivingRows : Model -> Maybe Proto.Rellm.StalwartConfig -> List (Html Msg)
stalwartReceivingRows model maybeConfig =
    [ Common.settingsRow "Receive Emails from Stalwart"
        (if model.stalwartReceivingStatus == AccountsPanel.Submitting then
            Common.switchDisplay (maybeConfig |> Maybe.map .stalwartReceivingEnabled |> Maybe.withDefault False)

         else
            Common.flagSwitch (maybeConfig |> Maybe.map .stalwartReceivingEnabled |> Maybe.withDefault False) StalwartReceivingToggled
        )
    , Common.settingsNote "Lets a Stalwart server in this cluster hand incoming mail to Rellm (its MTA hook, on the internal :27705/email endpoint)."
    , Common.editErrorView model.stalwartReceivingStatus
    ]


stalwartDisplayView : Maybe RellmAccount -> Maybe Proto.Rellm.StalwartConfig -> List (Html Msg)
stalwartDisplayView maybeAdminAccount maybeConfig =
    let
        config : Proto.Rellm.StalwartConfig
        config =
            Maybe.withDefault Proto.Rellm.defaultStalwartConfig maybeConfig
    in
    [ Common.settingsRow "Sending Enabled" (Common.switchDisplay config.stalwartSendingEnabled)
    , Common.settingsRow "SMTP Server"
        (valueText
            (if String.isEmpty config.stalwartSmtpHost then
                ""

             else
                config.stalwartSmtpHost ++ ":" ++ String.fromInt (if config.stalwartSmtpPort == 0 then 587 else config.stalwartSmtpPort)
            )
        )
    , Common.settingsRow "SMTP Username" (valueText config.stalwartSmtpUsername)
    , Common.settingsRow "From" (valueText (fromLine config.stalwartFromName config.stalwartFromAddress))
    , Common.settingsRow "Management URL" (valueText config.stalwartManagementUrl)
    , editButton maybeAdminAccount StalwartEditClicked "Edit Sending Settings"
    ]


stalwartEditView : Editing StalwartForm -> List (Html Msg)
stalwartEditView edit =
    let
        busy : Bool
        busy =
            edit.status == AccountsPanel.Submitting

        form : StalwartForm
        form =
            edit.form
    in
    [ Common.settingsRow "Sending Enabled" (Common.flagSwitch form.sendingEnabled StalwartSendingToggled)
    , textRow "SMTP Host" "stalwart.email.svc.cluster.local" busy (StalwartFieldChanged StalwartSmtpHost) form.smtpHost
    , textRow "SMTP Port" "587" busy (StalwartFieldChanged StalwartSmtpPort) form.smtpPort
    , textRow "SMTP Username" "rellm" busy (StalwartFieldChanged StalwartSmtpUsername) form.smtpUsername
    , secretRow "SMTP Password" "" busy (StalwartFieldChanged StalwartSmtpPassword) form.smtpPassword
    , textRow "From Address" "login@example.com" busy (StalwartFieldChanged StalwartFromAddress) form.fromAddress
    , textRow "From Name" "Example (optional)" busy (StalwartFieldChanged StalwartFromName) form.fromName
    , textRow "Management URL" "http://stalwart.email.svc.cluster.local:8080" busy (StalwartFieldChanged StalwartManagementUrl) form.managementUrl
    , secretRow "Management Token" "Optional. Read-only access for queue depth, DNS records and DMARC reports in the health check." busy (StalwartFieldChanged StalwartManagementToken) form.managementToken
    ]
        ++ formActions StalwartSaveClicked StalwartCancelClicked edit.status


-- SMS PROVIDER FORMS (Telnyx/Twilio/Bird) AND WEB PUSH ROWS


telnyxDisplayView : Maybe RellmAccount -> Maybe TelnyxConfig -> List (Html Msg)
telnyxDisplayView maybeAdminAccount telnyxConfig =
    [ Common.settingsRow "Telnyx Enabled" (Common.switchDisplay (telnyxConfig |> Maybe.map .telnyxEnabled |> Maybe.withDefault False))
    , Common.settingsRow "From Number" (span [ class "server-details-feature-settings-value" ] [ text (telnyxConfig |> Maybe.map .telnyxFromNumber |> Maybe.withDefault "—") ])
    , Common.settingsRow "Messaging Profile ID" (span [ class "server-details-feature-settings-value" ] [ text (telnyxConfig |> Maybe.map .telnyxMessagingProfileId |> Maybe.withDefault "—") ])
    , Common.settingsRow "Use Webhook Signing Key"
        (span [ class "server-details-feature-settings-value" ]
            [ Common.switchDisplay (telnyxConfig |> Maybe.map .useTelnyxWebhookSigningKey |> Maybe.withDefault False)
            , webhookSigningKeyWarning (telnyxConfig |> Maybe.map .useTelnyxWebhookSigningKey |> Maybe.withDefault False)
            ]
        )
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
    , Common.settingsRow "Webhook Signing Key"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change (optional)"
            , value edit.webhookSigningKey
            , onInput TelnyxWebhookSigningKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Use Webhook Signing Key" (Common.flagSwitch edit.useWebhookSigningKey TelnyxUseWebhookSigningKeyToggled)
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
    , Common.settingsRow "Use Webhook Signing Key"
        (span [ class "server-details-feature-settings-value" ]
            [ Common.switchDisplay (twilioConfig |> Maybe.map .useTwilioWebhookSigningKey |> Maybe.withDefault False)
            , webhookSigningKeyWarning (twilioConfig |> Maybe.map .useTwilioWebhookSigningKey |> Maybe.withDefault False)
            ]
        )
    , case maybeAdminAccount of
        Just _ ->
            button [ class "server-details-rename-button", onClick TwilioEditClicked ] [ text "Edit Twilio Settings" ]

        Nothing ->
            text ""
    ]


{-| Twilio's own IAM docs (<https://www.twilio.com/docs/iam/api-keys/restricted-api-keys>) recommend
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
    , Common.settingsRow "Webhook Signing Key"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change (optional -- the Account Auth Token)"
            , value edit.webhookSigningKey
            , onInput TwilioWebhookSigningKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Use Webhook Signing Key" (Common.flagSwitch edit.useWebhookSigningKey TwilioUseWebhookSigningKeyToggled)
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
    , Common.settingsRow "Use Webhook Signing Key"
        (span [ class "server-details-feature-settings-value" ]
            [ Common.switchDisplay (birdConfig |> Maybe.map .useBirdWebhookSigningKey |> Maybe.withDefault False)
            , webhookSigningKeyWarning (birdConfig |> Maybe.map .useBirdWebhookSigningKey |> Maybe.withDefault False)
            ]
        )
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
    , Common.settingsRow "Webhook Signing Key"
        (input
            [ type_ "password"
            , class "server-details-rename-input"
            , placeholder "Enter to change (optional -- starts with whsec_)"
            , value edit.webhookSigningKey
            , onInput BirdWebhookSigningKeyChanged
            , disabled (edit.status == AccountsPanel.Submitting)
            ]
            []
        )
    , Common.settingsRow "Use Webhook Signing Key" (Common.flagSwitch edit.useWebhookSigningKey BirdUseWebhookSigningKeyToggled)
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


{-| A "▲" warning (with hover title text) shown next to a provider's "Use Webhook Signing Key"
display row when that toggle is off (see `TwilioConfig.use_twilio_webhook_signing_key`'s own proto
doc: `false` means inbound deliveries to that provider's `/contact_integrations/*/receive` endpoint
are accepted without signature verification, per `docs/contact_integrations.md`). Driven purely by
the (non-secret) `use_*_webhook_signing_key` bool now, not by whether a key value happens to be
present -- the key itself is always blanked to `""` before reaching here regardless (see that
field's own doc), so it can no longer answer "is verification actually on" by itself.
-}
webhookSigningKeyWarning : Bool -> Html msg
webhookSigningKeyWarning useWebhookSigningKey =
    if useWebhookSigningKey then
        text ""

    else
        span
            [ class "server-details-webhook-signing-key-warning"
            , title "Webhook signing key verification is off -- inbound deliveries to this provider's receive endpoint are accepted without signature verification. See docs/contact_integrations.md."
            ]
            [ text " ▲" ]

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
