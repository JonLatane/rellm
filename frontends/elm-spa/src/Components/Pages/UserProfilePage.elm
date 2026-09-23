module Components.Pages.UserProfilePage exposing
    ( Model
    , Msg
    , fromShared
    , init
    , subscriptions
    , titleFor
    , update
    , view
    )

{-| The shared guts of a user profile page: fetching a `Proto.Rellm.User`
from a specific (possibly not-yet-connected) server, by id or by username, and
rendering it -- reused by both `Pages.User.UserId_` (`/user/:id[@host]`) and
`Pages.UsernameOrCustomTab_` (`/:username[@host]`), which differ only in which `Lookup`
they parse out of their route and (for `Pages.UsernameOrCustomTab_`) whether the username
is even routable at all (see `Components.Users.isReservedUsername`, checked by
the page itself before ever constructing this module's `Model`).

Mirrors `Pages.Post.PostId_`, generalized over the `Lookup` since (unlike
Posts, which are only ever looked up by id) a `User` can be fetched by either
id or username.

The actual "fetch a `User` once its server is connected, retry until it is"
state machine lives in `Components.Users.Resolver` (`model.resolver`), shared
with `Pages.UsernameOrCustomTab_.Posts`, which needs the same username -> id resolution
but none of this module's profile-editing machinery.

-}

import Browser.Dom as Dom
import Browser.Navigation
import Components.AIProviders as AIProviders
import Components.Markdown as Markdown
import Components.Market as Market
import Components.Pages.EventsPage as EventsPage
import Components.Pages.PostsPage as PostsPage
import Components.Posts as Posts
import Components.ServerDependentView as ServerDependentView
import Components.SyncDestinations as SyncDestinations
import Components.SyncSources as SyncSources
import Components.Users as Users
import Components.Users.FollowStatusAndButton as FollowStatusAndButton
import Components.Users.ProfileHeading as ProfileHeading
import Components.Users.Resolver as Resolver
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Route
import Grpc
import Html exposing (Html, a, button, div, h2, h3, input, label, li, option, p, select, span, text, ul)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, href, id, name, novalidate, placeholder, readonly, selected, tabindex, title, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Json.Decode as Decode
import Ports
import Process
import Proto.Google.Protobuf
import Proto.Rellm exposing (AIProvider, AIProviderGrant, ContactConsentChange, ContactMethod, FederatedAccount, MarketPurchase, MarketPurchase_, MarketSubscription, SyncDestination, SyncSource, User, defaultAIProvider, defaultDigitalOceanCredentials, defaultGeminiCredentials, defaultMediaReference, defaultOpenAICredentials, defaultSyncDestination, defaultSyncSource, unwrapMarketPurchase)
import Proto.Rellm.AIProvider.Provider as AIProviderProvider
import Proto.Rellm.ContactConsentState exposing (ContactConsentState(..))
import Proto.Rellm.Moderation exposing (Moderation(..))
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.SyncDestination.Configuration as DestinationConfiguration
import Proto.Rellm.SyncSource.Configuration as Configuration
import Proto.Rellm.Visibility exposing (Visibility(..))
import Set
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.ByteFormat as ByteFormat
import Shared.Conversions as Conversions exposing (timestampToPosix)
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MyMediaPanel as MyMediaPanel
import Shared.Time as SharedTime
import Task
import UI
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.HtmlEvents exposing (stopPropagationAndPreventDefaultOnClick)
import Url


type alias Model =
    { resolver : Resolver.Model
    , connectStatus : ServerDependentView.ConnectStatus
    , pageIsSecure : Bool
    , federatedProfiles : Dict String FederatedProfileStatus
    , realNameEdit : Maybe RealNameEdit
    , avatarEdit : Maybe AvatarEdit
    , visibilityEdit : Maybe VisibilityEdit
    , moderationEdit : Maybe ModerationEdit
    , followModerationStatus : SubmitStatus
    , contactMethodsExpanded : Bool
    , phoneEdit : Maybe PhoneEdit
    , emailEdit : Maybe EmailEdit
    , phoneConsentStatus : SubmitStatus
    , emailConsentStatus : SubmitStatus
    , phoneHistoryExpanded : Bool
    , emailHistoryExpanded : Bool
    , phoneVerification : Maybe PhoneVerification
    , storageQuotaEdit : Maybe StorageQuotaEdit
    , storageQuotaExpanded : Bool
    , subscriptionsExpanded : Bool
    , cancelingSubscriptions : Dict String SubmitStatus
    , permissionsEdit : Maybe PermissionsEdit
    , permissionsExpanded : Bool
    , federatedProfilesEdit : Maybe FederatedProfilesEdit
    , passwordResetEdit : Maybe PasswordResetEdit
    , syncSources : SyncSourcesState
    , syncSourcesExpanded : Bool
    , syncDestinations : SyncDestinationsState
    , syncDestinationsExpanded : Bool
    , aiProviders : AIProvidersState
    , aiProvidersExpanded : Bool
    , aiProviderGrantsExpanded : Bool
    , followStatusAndButton : FollowStatusAndButton.Model

    -- Embedded, row-laid-out `EventsPage`/search-box-less `PostsPage` copies of this
    -- user's own events/posts, mirroring `Pages.Home_.Model`'s own `posts`/`events`
    -- pair -- see `view`'s own doc. Both start `Nothing` (there's no resolved `User`
    -- to filter by yet) and are only ever initialized once, the first time `resolver`
    -- reports `Resolver.Loaded` (see `updateInner`'s `ResolverMsg` branch) -- a later
    -- refetch (e.g. after a follow/unfollow) re-`Loaded`s `resolver` again, but must
    -- *not* re-`init` either of these, which would wipe out their own in-progress
    -- search text/scroll position for no reason.
    , posts : Maybe PostsPage.Model
    , events : Maybe EventsPage.Model
    , navKey : Browser.Navigation.Key
    , path : String
    , query : Dict String String

    -- A `#subscriptions`/`#sync-sources`/`#sync-destinations`/`#ai-providers`/`#ai-models`
    -- fragment (see `init`'s own `fragment` handling), consumed once the first
    -- `Resolver.Loaded` actually mounts that section's real DOM `id` (`updateInner`'s
    -- `ResolverMsg` branch) -- cleared right after, so a later refetch (e.g. after a
    -- follow/unfollow) doesn't keep re-scrolling the page back to it.
    , pendingScrollSectionId : Maybe String
    }


type Msg
    = ResolverMsg Resolver.Msg
    | PostsMsg PostsPage.Msg
    | EventsMsg EventsPage.Msg
    | ConnectClicked
    | GotConnectResult (Result Grpc.Error RellmServer)
    | EnableClicked
    | SharedMsg Shared.Msg
    | GotFederatedServer FederatedAccount (Result Grpc.Error RellmServer)
    | GotFederatedUser String (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetUsersResponse ))
    | RealNameEditClicked
    | RealNameInputChanged String
    | RealNameCancelClicked
    | RealNameSaveClicked
    | GotRealNameSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | AvatarEditClicked
    | AvatarRemoveClicked
    | AvatarCancelClicked
    | AvatarSaveClicked
    | GotAvatarSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | BioEditClicked
    | VisibilityEditClicked
    | VisibilityChanged String
    | VisibilityCancelClicked
    | VisibilitySaveClicked
    | GotVisibilitySaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | ModerationEditClicked
    | ModerationChanged String
    | ModerationCancelClicked
    | ModerationSaveClicked
    | GotModerationSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | FollowModerationToggled
    | GotFollowModerationSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | ContactMethodsExpandedToggled
    | PhoneEditClicked
    | PhoneInputChanged String
    | PhoneVisibilityChanged String
    | PhoneCancelClicked
    | PhoneSaveClicked
    | GotPhoneSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | PhoneConsentToggled
    | GotPhoneConsentSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | PhoneHistoryToggled
    | EmailEditClicked
    | EmailInputChanged String
    | EmailVisibilityChanged String
    | EmailCancelClicked
    | EmailSaveClicked
    | GotEmailSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | EmailConsentToggled
    | GotEmailConsentSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | EmailHistoryToggled
    | StartPhoneVerificationClicked
    | GotStartPhoneVerificationResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ContactMethod ))
    | PhoneVerificationCooldownElapsed
    | PhoneVerificationCodeChanged String
    | VerifyPhoneCodeClicked
    | GotVerifyPhoneCodeResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ContactMethod ))
    | StorageQuotaExpandedToggled
    | StorageQuotaEditClicked
    | StorageQuotaPendingChanged String
    | StorageQuotaUnitChanged String
    | StorageQuotaUnlimitedToggled
    | StorageQuotaCancelClicked
    | StorageQuotaSaveClicked
    | GotStorageQuotaSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | ShowMyMediaClicked
    | SubscriptionsExpandedToggled
    | CancelSubscriptionClicked MarketSubscription
    | GotCancelSubscriptionResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, MarketSubscription ))
    | PermissionsExpandedToggled
    | PermissionsEditClicked
    | PermissionRemoveClicked Permission
    | PermissionAddSelectionChanged String
    | PermissionAddClicked
    | PermissionsCancelClicked
    | PermissionsSaveClicked
    | GotPermissionsSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, User ))
    | FederatedProfilesEditClicked
    | FederatedProfilesDoneClicked
    | FederatedProfileAddSelectionChanged String
    | FederatedProfileAddClicked
    | GotFederatedProfileAddResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, FederatedAccount ))
    | FederatedProfileRemoveClicked FederatedAccount
    | GotFederatedProfileRemoveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty ))
    | FollowStatusAndButtonMsg FollowStatusAndButton.Msg
    | SyncSourceRowUrlChanged SyncSource String
    | SyncSourceRowIntervalChanged SyncSource Int
    | SyncSourceRowSaveClicked SyncSource
    | SyncSourceRowRefreshClicked SyncSource
    | GotSyncSourceRowSaveResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncSource ))
    | SyncSourceAddUrlChanged String
    | SyncSourceAddKindChanged SyncSourceKind
    | SyncSourceAddIntervalChanged Int
    | SyncSourceAddClicked
    | GotSyncSourceAddResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncSource ))
    | SyncSourceDeleteClicked SyncSource Bool
    | SyncSourcesExpandedToggled
    | SyncSourcesRefreshClicked
    | GotSyncSourcesRefreshResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetSyncSourcesResponse ))
    | SyncDestinationsExpandedToggled
    | FacebookLoginClicked
    | InstagramLoginClicked
    | GotFacebookLoginResult Decode.Value
    | GotFacebookPagesResult (Result Http.Error (List FacebookPageOption))
    | FacebookPageChosen FacebookPageOption
    | GotFacebookLinkResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncDestination ))
    | MastodonConnectClicked
    | MastodonInstanceHostChanged String
    | MastodonAccessTokenChanged String
    | MastodonConnectCancelled
    | MastodonConnectSubmitted
    | GotMastodonLinkResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncDestination ))
    | BlueskyConnectClicked
    | BlueskyHandleChanged String
    | BlueskyAppPasswordChanged String
    | BlueskyConnectCancelled
    | BlueskyConnectSubmitted
    | GotBlueskyLinkResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncDestination ))
    | ThreadsLoginClicked
    | GotThreadsLoginResult Decode.Value
    | GotThreadsLinkResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncDestination ))
    | XTwitterLoginClicked
    | GotXTwitterLoginResult Decode.Value
    | GotXTwitterLinkResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, SyncDestination ))
    | SyncDestinationDeleteClicked SyncDestination
    | GotSyncDestinationDeleteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
    | AIProviderRowNameChanged AIProvider String
    | AIProviderRowApiKeyChanged AIProvider String
    | AIProviderRowSaveClicked AIProvider
    | AIProviderRowCancelClicked AIProvider
    | GotAIProviderRowSaveResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, AIProvider ))
    | AIProviderAddProviderTypeChanged String
    | AIProviderAddNameChanged String
    | AIProviderAddApiKeyChanged String
    | AIProviderAddClicked
    | GotAIProviderAddResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, AIProvider ))
    | AIProviderDeleteClicked AIProvider
    | GotAIProviderDeleteResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
    | AIProvidersExpandedToggled
    | AIProvidersRefreshClicked
    | GotAIProvidersRefreshResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Rellm.GetAIProvidersResponse ))
    | AIProviderGrantsToggled String
    | AIProviderGrantUserIdChanged String String
    | AIProviderGrantTokensChanged String String
    | AIProviderGrantModelNamesChanged String String
    | AIProviderGrantEditClicked AIProvider AIProviderGrant
    | AIProviderGrantClicked AIProvider
    | GotAIProviderGrantResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, AIProviderGrant ))
    | AIProviderRevokeClicked AIProvider AIProviderGrant
    | GotAIProviderRevokeResult String (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
    | AIProviderGrantsSectionToggled
    | PasswordResetEditClicked
    | PasswordResetInputChanged String
    | PasswordResetCancelClicked
    | PasswordResetSaveClicked
    | GotPasswordResetSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Proto.Google.Protobuf.Empty ))
    | DeleteUserClicked
    | ScrollToProfileSectionAttempted


{-| The fetch state of one entry in a loaded `User.federatedProfiles`, keyed
by `federatedKey` -- mirrors `Shared.StarredPanel.PostFetchStatus`, minus
that module's `ServerUnavailable`/poll-retry distinction, since an unreachable
federated server here just reads the same as any other failure (there's no
polling loop kicking these fetches off again).
-}
type FederatedProfileStatus
    = FederatedProfileLoading
    | FederatedProfileLoaded User
    | FederatedProfileFailed


{-| Shared by `RealNameEdit`/`PermissionsEdit` -- mirrors `Shared.MarkdownPanel`'s
own `SubmitStatus`, kept separate since these two edits are local to this page
rather than routed through that shared panel.
-}
type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Live only while the Real Name field (see `Model.realNameEdit`) is being
edited -- `input` is the in-progress value, independent of `status.user.realName`
until `RealNameSaveClicked` succeeds.
-}
type alias RealNameEdit =
    { input : String
    , status : SubmitStatus
    }


{-| Live only while the "Reset Password" form (see `Model.passwordResetEdit`) is open -- swapped in
for both the "Reset Password" and "Delete User" buttons at once (see `accountActionsSection`),
mirroring `RealNameEdit` except there's nothing to prefill `input` with (a password never round-trips
back from the server) so it always starts empty, same as `AccountsPanel`'s own password fields.
-}
type alias PasswordResetEdit =
    { input : String
    , status : SubmitStatus
    }


{-| Live only while the Phone field (see `Model.phoneEdit`) is being edited -- mirrors
`RealNameEdit` exactly, plus `visibility` for the visibility `<select>` shown alongside the input
(see `contactMethodVisibilities`). `input` holds just the raw phone number, with the `tel:` scheme
stripped back off (see `contactMethodEditValue`) -- re-added on save (see `PhoneSaveClicked`).
Changing `visibility` alone (leaving `input` at the currently-saved number) doesn't reset
verification status on save -- only an actual number change does, per
`update_user.rs`'s `apply_contact_method_update`, which resets `verified_at`/
`verification_in_progress` only when `value` itself changed.
-}
type alias PhoneEdit =
    { input : String
    , visibility : Visibility
    , status : SubmitStatus
    }


{-| Live only while the Email field (see `Model.emailEdit`) is being edited -- mirrors `PhoneEdit`
exactly, just for the `mailto:` scheme instead of `tel:`. Email verification is out of scope this
iteration (only SMS/phone), so unlike `PhoneEdit` there's no corresponding `PhoneVerification`-style
sibling type for this one.
-}
type alias EmailEdit =
    { input : String
    , visibility : Visibility
    , status : SubmitStatus
    }


{-| Live once phone verification has been started (`StartPhoneVerificationClicked`) -- independent
of `PhoneEdit`, since verification always targets whatever phone number is currently saved on the
user, not any in-progress edit. `sendStatus` tracks the in-flight (or most recently failed)
`StartContactMethodVerification` call; `code`/`verifyStatus` track the code-entry
`VerifyContactMethod` call once at least one send has gone out; `cooldownActive` disables "Resend"
for 60 seconds after each successful send, cleared by a `Process.sleep`-scheduled
`PhoneVerificationCooldownElapsed`.
-}
type alias PhoneVerification =
    { sendStatus : SubmitStatus
    , code : String
    , verifyStatus : SubmitStatus
    , cooldownActive : Bool
    }


{-| What `AvatarSaveClicked` should do to `user.avatar` (see `applyAvatarChoice`) --
`AvatarUnchanged` leaves it alone (the default, entering edit mode), `AvatarChosen
mediaId` overwrites it with that media (set by picking a tile in the shared
`Shared.MyMediaPanel`, opened in `SingleSelect` mode -- see `AvatarEditClicked`
and the `SharedMsg` handling of `MyMediaPanel.MediaItemClicked`), and `AvatarRemoved`
(the "✕" button, see `avatarView`) clears it entirely.
-}
type AvatarChoice
    = AvatarUnchanged
    | AvatarChosen String
    | AvatarRemoved


{-| Live only while the avatar (see `Model.avatarEdit`) is being edited --
mirrors `RealNameEdit`, except there's no in-progress text input, just
`choice` (see `AvatarChoice`), driven by taps on the avatar itself/its "✕"
button/the `Shared.MyMediaPanel` chooser this opens rather than typing.
-}
type alias AvatarEdit =
    { choice : AvatarChoice
    , status : SubmitStatus
    }


{-| Live only while the Visibility picker (see `Model.visibilityEdit`) is
being edited by the profile's own owner or an Admin (see `canEditProfile`,
the same gate `backend/src/rpcs/users/update_user.rs`'s `admin || self_update`
branch enforces server-side, which is also what actually applies
`visibility`) -- mirrors `Pages.Post.PostId_.VisibilityEdit`.
-}
type alias VisibilityEdit =
    { pending : Visibility
    , status : SubmitStatus
    }


{-| Live only while the Moderation picker (see `Model.moderationEdit`) is
being edited by an Admin or a `MODERATEUSERS` holder (see `canModerateUser`,
mirroring `update_user.rs`'s own `admin || moderator` branch, which is also
what actually applies `moderation`) -- mirrors `VisibilityEdit` exactly, just
for `Moderation` instead of `Visibility`.
-}
type alias ModerationEdit =
    { pending : Moderation
    , status : SubmitStatus
    }


{-| Live only while the storage quota (see `Model.storageQuotaEdit`) is being edited by an Admin
(only an Admin may ever open this -- see `update_user.rs`'s own `admin`-only
`media_storage_limit_bytes` branch). `pending`/`unit` are the in-progress number/unit pair (e.g.
`"5"` + `GB`), only meaningful while `unlimited == False`; `unlimited` mirrors an unset
`User.mediaStorageLimitBytes` (`Nothing`) and, while `True`, disables/ignores `pending`/`unit`
entirely on save.
-}
type alias StorageQuotaEdit =
    { pending : String
    , unit : ByteFormat.ByteUnit
    , unlimited : Bool
    , status : SubmitStatus
    }


{-| Live only while the permissions list (see `Model.permissionsEdit`) is
being edited by an admin -- `pending` is the in-progress set (already
reflecting any `PermissionRemoveClicked`/`PermissionAddClicked` since editing
started), `addSelection` is whatever the "Add Permission" `<select>` currently
has chosen (always one of `Components.Users.allPermissions` not already in
`pending`, see `resolveAddSelection`).
-}
type alias PermissionsEdit =
    { pending : List Permission
    , addSelection : Maybe Permission
    , status : SubmitStatus
    }


{-| Live only while the federated profiles list (see `Model.federatedProfilesEdit`)
is being edited by the profile's own owner (see `isOwnProfile` -- unlike
`PermissionsEdit`, there's no `pending`/Save step: `FederateProfile`/
`DefederateProfile` (see `Components.Users.federateProfile`/`defederateProfile`)
each commit immediately, one account at a time, so `user.federatedProfiles`
itself stays the single source of truth throughout editing. `addSelection` is
whichever of the viewer's own other-server accounts (see `federableAccounts`)
the "Link Account" `<select>` currently has chosen.
-}
type alias FederatedProfilesEdit =
    { addSelection : Maybe RellmAccount
    , status : SubmitStatus
    }


{-| A row's in-progress edit -- created (from the source's own current
values, see `eventSyncRowEditFor`) the moment the URL/interval input is first
touched, and dropped again once a save actually lands (see
`GotSyncSourceRowSaveResult`). A row with no entry here just renders
straight from its `SyncSource` and shows "Refresh" rather than "Save"
(see `syncSourceIsDirty`).
-}
type alias EventSyncRowEdit =
    { pendingUrl : String
    , pendingIntervalSeconds : Int
    , status : SubmitStatus
    }


type alias EventSyncAddForm =
    { url : String
    , kind : SyncSourceKind
    , intervalSeconds : Int
    , status : SubmitStatus
    }


defaultEventSyncAddForm : EventSyncAddForm
defaultEventSyncAddForm =
    { url = "", kind = Ics, intervalSeconds = 3600, status = Idle }


{-| Which `SyncSource.configuration` variant (`protos/sync.proto`) a new source's subscription
URL should be created as -- picked via `syncSourceAddRowView`'s type selector. An existing row's
own kind is never re-chosen (only its URL text/interval are editable, see
`SyncSourceRowSaveClicked`) -- it's implied by whichever variant `source.configuration` already
is, via `configurationForKindOf`.
-}
type SyncSourceKind
    = Ics
    | Rss
    | Atom


syncSourceKindLabel : SyncSourceKind -> String
syncSourceKindLabel kind =
    case kind of
        Ics ->
            "iCal"

        Rss ->
            "RSS"

        Atom ->
            "Atom"


syncSourceKindFromLabel : String -> SyncSourceKind
syncSourceKindFromLabel label =
    case label of
        "RSS" ->
            Rss

        "Atom" ->
            Atom

        _ ->
            Ics


syncSourceKindOf : SyncSource -> SyncSourceKind
syncSourceKindOf source =
    case source.configuration of
        Just (Configuration.RssSubscriptionUrl _) ->
            Rss

        Just (Configuration.AtomSubscriptionUrl _) ->
            Atom

        _ ->
            Ics


{-| Builds the `Configuration` variant for a fresh source of `kind` with `url`, or -- for
`SyncSourceRowSaveClicked`, editing an existing row -- rebuilds whichever variant `existing`
already had (an existing source's kind is never changed by this UI) with a new `url`, falling
back to `kind` only if `existing` somehow has no configuration set at all.
-}
configurationForKindOf : Maybe (Configuration.Configuration String String String) -> SyncSourceKind -> String -> Configuration.Configuration String String String
configurationForKindOf existing kind url =
    case existing of
        Just (Configuration.IcsSubscriptionUrl _) ->
            Configuration.IcsSubscriptionUrl url

        Just (Configuration.RssSubscriptionUrl _) ->
            Configuration.RssSubscriptionUrl url

        Just (Configuration.AtomSubscriptionUrl _) ->
            Configuration.AtomSubscriptionUrl url

        Nothing ->
            case kind of
                Ics ->
                    Configuration.IcsSubscriptionUrl url

                Rss ->
                    Configuration.RssSubscriptionUrl url

                Atom ->
                    Configuration.AtomSubscriptionUrl url


{-| The permission (`protos/permissions.proto`) that gates creating/updating a `SyncSource` of
`kind` -- `SYNC_EVENTS_FROM_ICS`/`SYNC_POSTS_FROM_RSS`/`SYNC_POSTS_FROM_ATOM`, mirroring
`backend/src/marshaling/sync_marshaling.rs`'s own `required_sync_source_permission` exactly.
-}
syncSourceKindPermission : SyncSourceKind -> Permission
syncSourceKindPermission kind =
    case kind of
        Ics ->
            SYNCEVENTSFROMICS

        Rss ->
            SYNCPOSTSFROMRSS

        Atom ->
            SYNCPOSTSFROMATOM


{-| Whether `maybeAccount` holds `kind`'s own permission (or `ADMIN`) -- gates that one option in
`syncSourceKindSelect`'s type selector (see `availableSyncSourceKinds`).
-}
hasSyncSourceKindPermission : SyncSourceKind -> Maybe RellmAccount -> Bool
hasSyncSourceKindPermission kind maybeAccount =
    maybeAccount
        |> Maybe.map
            (\account ->
                List.member (syncSourceKindPermission kind) account.permissions
                    || List.member ADMIN account.permissions
            )
        |> Maybe.withDefault False


{-| The `SyncSourceKind`s `maybeAccount` may create a new source as -- `syncSourceAddRowView`'s
type selector only ever offers these (see `syncSourceKindSelect`), same as `canUseSyncSources`
gating the add row/section as a whole on there being at least one.
-}
availableSyncSourceKinds : Maybe RellmAccount -> List SyncSourceKind
availableSyncSourceKinds maybeAccount =
    [ Ics, Rss, Atom ] |> List.filter (\kind -> hasSyncSourceKindPermission kind maybeAccount)


{-| Whether `maybeAccount` holds _any_ of the 3 SyncSource permissions (or `ADMIN`) -- gates
whether the "add a source" affordance is shown at all, mirroring `canUseSyncDestinations`'s same
any-of-N-permissions gate for the "Sync Destinations" section.
-}
canUseSyncSources : Maybe RellmAccount -> Bool
canUseSyncSources maybeAccount =
    not (List.isEmpty (availableSyncSourceKinds maybeAccount))


{-| `kind` itself, if it's one of `availableKinds` -- otherwise `availableKinds`' own first entry
(falling back to `kind` unchanged only if `availableKinds` is somehow empty, which shouldn't
happen in practice since the add row is only ever shown when `canUseSyncSources` is `True`).
Keeps `addForm.kind`'s stored value and the type selector's rendered/submitted value in sync
even when the viewer's permissions don't include `EventSyncAddForm`'s own default (`Ics`) -- e.g.
an RSS-only account would otherwise have the selector visually default to "RSS" (the first
available option) while `SyncSourceAddClicked` silently built an ICS configuration underneath.
-}
effectiveSyncSourceAddKind : List SyncSourceKind -> SyncSourceKind -> SyncSourceKind
effectiveSyncSourceAddKind availableKinds kind =
    if List.member kind availableKinds then
        kind

    else
        List.head availableKinds |> Maybe.withDefault kind


{-| The "Sync Sources" section's own state -- basic CRUD over
`SyncSource` (`protos/sync.proto`) for this profile's own user (or,
for an Admin viewing someone else's profile, that user's sources). Bundled
into its own record (rather than flattened into `Model` alongside
`realNameEdit`/`permissionsEdit`/etc) since, unlike those, it needs several
fields at once (`rowEdits`/`addForm`) that all change together.

Unlike its own past self, the source list itself is **not** fetched/held
here at all -- `Components.Users.Resolver` already resolves this profile's
own `User` (via `GetUsers`), which (self-or-Admin gated server-side, see
`protos/users.proto`'s own doc on `User.sync_sources`) already carries
it, so `syncSourcesSection` just reads `user.syncSources` directly
-- mirrors `SyncDestinationsState`'s own doc on `user.syncDestinations`
exactly, just extended to this construct too.

Used to live in `Shared.Model` (`Shared.SyncSourcesPanel`, since
removed) despite being shown only here, on this one page -- solely because
the delete confirmation dialog (`Shared.DeleteConfirmation`) is a global
overlay that can only resolve back into a Shared-owned submodel. Deletes now
follow the same shape `ConfirmPostDelete`/`ConfirmEventDelete` already used:
`Shared.update`'s `ConfirmDelete` fires the `DeleteSyncSource` RPC
directly (see `Shared.ConfirmSyncSourceDelete`), and its result
(`Shared.GotSyncSourceDeleteResult`) is forwarded back here like any
other `Shared.Msg` (see `updateInner`'s `SharedMsg` branch) -- so this state
has no reason to live anywhere but here. Unlike that old module, there's no
`targetHost`/`viewedUserId` staleness guard: this `Model` (unlike a
Shared-owned singleton) never outlives one profile.

-}
type alias SyncSourcesState =
    { rowEdits : Dict String EventSyncRowEdit
    , addForm : EventSyncAddForm

    -- Manual "Refresh" button state (`SyncSourcesRefreshClicked`) -- overlays a fresh
    -- `GetSyncSources` result onto the resolved `User` without a whole-profile `refetch`.
    , refreshStatus : SubmitStatus
    }


initSyncSources : SyncSourcesState
initSyncSources =
    { rowEdits = Dict.empty, addForm = defaultEventSyncAddForm, refreshStatus = Idle }


{-| One Facebook Page returned by the Graph API's `/me/accounts` after a successful Facebook
login (`fetchFacebookPages`) -- `id`/`name` only. The per-page access token that endpoint also
returns is never used: the backend re-derives its own long-lived Page token server-side from the
short-lived _user_ token this page already has, via `FacebookPage.shortLivedUserAccessToken` (see
`logic::facebook_sync::connect_facebook_page` on the backend).
-}
type alias FacebookPageOption =
    { id : String
    , name : String
    }


{-| Which platform a `FacebookLoginStatus` popup flow is connecting for -- Facebook and Instagram
share the exact same OAuth popup/"choose a Page" flow (Instagram Business posting piggybacks on a
linked Facebook Page's access token), so this is threaded through the shared states rather than
duplicating the whole state machine. Set once when the flow starts (`FacebookLoginClicked`/
`InstagramLoginClicked`) and read back in `FacebookPageChosen` to decide which `Configuration`
variant to build.
-}
type FacebookConnectPlatform
    = ConnectFacebook
    | ConnectInstagram


{-| The Facebook/Instagram "Sign in to Facebook Page" flow's own state machine (see
`FacebookLoginClicked`/`InstagramLoginClicked` and `syncDestinationsSection`). Each step
commits straight to the next -- there's no "form" to independently edit/cancel the way
`RealNameEdit`/`EventSyncAddForm` have:

  - `FacebookLoginNotStarted`: no platform button for this flow has been clicked, nothing in flight.
  - `FacebookLoginPopupOpen platform`: waiting on the `Ports.facebookLoginResult` port (the popup
    opened by `Ports.facebookLoginPopup` is open, or the user just closed it -- see
    `GotFacebookLoginResult`).
  - `FacebookLoginFetchingPages platform token`: got a short-lived user access token back, now
    calling the Graph API's `/me/accounts` (`fetchFacebookPages`) to list the Pages it can link.
  - `FacebookLoginChoosingPage platform token pages`: `/me/accounts` returned at least one Page --
    `pages` is shown as a plain clickable list (`FacebookPageChosen`) rather than picking one
    automatically, even when there's only one, so the user always sees what they're linking.
  - `FacebookLoginNoPagesFound`: `/me/accounts` returned zero Pages -- nothing to link, for either
    platform.
  - `FacebookLoginLinking platform page`: `CreateSyncDestination` is in flight for `page`.
  - `FacebookLoginFailed message`: the popup, the Graph API call, or the create RPC failed.

-}
type FacebookLoginStatus
    = FacebookLoginNotStarted
    | FacebookLoginPopupOpen FacebookConnectPlatform
    | FacebookLoginFetchingPages FacebookConnectPlatform String
    | FacebookLoginChoosingPage FacebookConnectPlatform String (List FacebookPageOption)
    | FacebookLoginNoPagesFound
    | FacebookLoginLinking FacebookConnectPlatform FacebookPageOption
    | FacebookLoginFailed String


{-| The Mastodon "Connect" flow's own state machine -- simpler than `FacebookLoginStatus` since
there's no popup/page-list step, just two pasted text fields (instance host + Personal Access
Token) and a submit. See `MastodonConnectClicked`/`mastodonConnectView`.
-}
type MastodonConnectStatus
    = MastodonConnectNotStarted
    | MastodonConnectEditing { instanceHost : String, accessToken : String }
    | MastodonConnectLinking { instanceHost : String, accessToken : String }
    | MastodonConnectFailed String


{-| The Bluesky "Connect" flow's own state machine -- identical shape to `MastodonConnectStatus`,
just a handle + "App Password" instead of an instance host + PAT. See
`BlueskyConnectClicked`/`blueskyConnectView`.
-}
type BlueskyConnectStatus
    = BlueskyConnectNotStarted
    | BlueskyConnectEditing { handle : String, appPassword : String }
    | BlueskyConnectLinking { handle : String, appPassword : String }
    | BlueskyConnectFailed String


{-| The Threads "Connect" flow's own state machine -- popup-based like `FacebookLoginStatus` (it
rides the same `Ports.facebookLoginPopup`/`facebookLoginResult` plumbing, see
`Ports.facebookLoginPopup`'s own doc), but doesn't fit that type: Threads OAuth authorizes the
user's single Threads account directly, with no "choose a Page" step, so there's no equivalent of
`FacebookLoginFetchingPages`/`FacebookLoginChoosingPage`/`FacebookLoginNoPagesFound` -- a popup
result goes straight from "got a code" to "create the destination." Doesn't fit
`MastodonConnectStatus`/`BlueskyConnectStatus`'s paste-a-credential form shape either, since
there's no form, just a popup. See `ThreadsLoginClicked`/`threadsConnectView`.

  - `ThreadsConnectNotStarted`: no button clicked, nothing in flight.
  - `ThreadsConnectPopupOpen`: waiting on `Ports.facebookLoginResult` (see `GotThreadsLoginResult`).
  - `ThreadsConnectLinking`: got an authorization code back, `CreateSyncDestination` in flight.
  - `ThreadsConnectFailed message`: the popup or the create RPC failed.

-}
type ThreadsConnectStatus
    = ThreadsConnectNotStarted
    | ThreadsConnectPopupOpen
    | ThreadsConnectLinking
    | ThreadsConnectFailed String


{-| The X (Twitter) "Connect" flow's own state machine -- same popup-based shape as
`ThreadsConnectStatus` (see its own doc), with one addition: X mandates PKCE, so the popup also has
to hand back the `code_verifier` it generated alongside the authorization code (see
`Ports.facebookLoginPopup`'s own doc on the `"x_twitter"` provider and why it uses the weaker
`plain` PKCE method rather than `S256`) -- carried through `XTwitterConnectPopupOpen`'s payload so
`GotXTwitterLoginResult` can thread it into the `CreateSyncDestination` request alongside the code.

  - `XTwitterConnectNotStarted`: no button clicked, nothing in flight.
  - `XTwitterConnectPopupOpen`: waiting on `Ports.facebookLoginResult` (see `GotXTwitterLoginResult`).
  - `XTwitterConnectLinking`: got a code + verifier back, `CreateSyncDestination` in flight.
  - `XTwitterConnectFailed message`: the popup or the create RPC failed.

-}
type XTwitterConnectStatus
    = XTwitterConnectNotStarted
    | XTwitterConnectPopupOpen
    | XTwitterConnectLinking
    | XTwitterConnectFailed String


{-| The "Sync Destinations" section's own state -- mirrors `SyncSourcesState`'s doc
(bundled into one record for the same reason), but far simpler: no per-row edits (a destination's
only mutable-from-here field, in effect, is "does it exist"), so this is just the four connect
flows' own state machines (`login` for Facebook/Instagram's shared popup flow, `mastodon`/
`bluesky` for their own inline paste-a-credential forms, `threads` for Threads' own simpler popup
flow -- see `ThreadsConnectStatus`), plus a per-destination-id `SubmitStatus` for
`SyncDestinationDeleteClicked` (`Dict` rather than a single field since, in principle,
more than one delete could be in flight -- e.g. an Admin clicking two rows quickly). At most one of
`login`/`mastodon`/`bluesky`/`threads` is ever not-`NotStarted` at a time -- see
`platformConnectView`, which renders whichever one is in progress (or a platform-picker row of
buttons if none are). The destinations themselves are no longer fetched/held here at all --
`Components.Users.Resolver` already resolves this profile's own `User` (via `GetUsers`), which
(self-or-Admin gated server-side, see `protos/users.proto`'s own doc on `User.sync_destinations`)
already carries them, so `syncDestinationsSection` just reads `user.syncDestinations` directly.

Unlike `SyncSourcesState`, deletes are NOT routed through `Shared.DeleteConfirmation`: unlinking
a connected account is a low-stakes, easily-reversible action (nothing else gets deleted --
`deleteSyncedPosts` is always sent `False`, see `Components.SyncDestinations`), so there's no
need for the global "are you sure?" overlay here.

-}
type alias SyncDestinationsState =
    { login : FacebookLoginStatus
    , mastodon : MastodonConnectStatus
    , bluesky : BlueskyConnectStatus
    , threads : ThreadsConnectStatus
    , xTwitter : XTwitterConnectStatus
    , deleteStatuses : Dict String SubmitStatus
    }


initSyncDestinations : SyncDestinationsState
initSyncDestinations =
    { login = FacebookLoginNotStarted
    , mastodon = MastodonConnectNotStarted
    , bluesky = BlueskyConnectNotStarted
    , threads = ThreadsConnectNotStarted
    , xTwitter = XTwitterConnectNotStarted
    , deleteStatuses = Dict.empty
    }


{-| A row's in-progress edit -- created (from the provider's own current name, plus a blank API
key, see `aiProviderRowEditFor`) the moment its "Edit" button is clicked. `pendingApiKey` is
**never** pre-filled from the provider's own credentials -- the server never sends the real key
back (see `GeminiCredentials.geminiApiKey`'s own doc), so a blank key here just means "leave the
stored key alone" (see `AIProviderRowSaveClicked`, which only includes a new `provider` in the
request when `pendingApiKey` is non-blank) -- the same "blank means unchanged" convention
`ServerInformationPage.FederationTab` uses for `FacebookAuthConfig.appSecret`/etc.
-}
type alias AIProviderRowEdit =
    { pendingName : String
    , pendingApiKey : String
    , status : SubmitStatus
    }


{-| Which credentials variant a new `AIProvider` is being created with -- all three are
currently creatable (see `AIProvider`'s own proto doc); `Anthropic` isn't included here since
it isn't yet.
-}
type AddAIProviderType
    = AddGeminiProvider
    | AddOpenAIProvider
    | AddDigitalOceanProvider


type alias AIProviderAddForm =
    { providerType : AddAIProviderType
    , name : String
    , apiKey : String
    , status : SubmitStatus
    }


defaultAIProviderAddForm : AIProviderAddForm
defaultAIProviderAddForm =
    { providerType = AddGeminiProvider, name = "", apiKey = "", status = Idle }


{-| The in-progress "grant access" form for one AIProvider's expanded grants list -- a target
user id plus a token budget, submitted via `GrantAIProvider`. Keyed by provider id in
`AIProvidersState.grantForms` since more than one provider's grants list may be expanded at
once.
-}
type alias AIProviderGrantForm =
    { userId : String
    , tokens : String

    -- Comma-separated model names (see `AIProviderGrant.modelNames`'s own doc) -- blank
    -- means "any model this provider supports".
    , modelNames : String
    , status : SubmitStatus
    }


defaultAIProviderGrantForm : AIProviderGrantForm
defaultAIProviderGrantForm =
    { userId = "", tokens = "", modelNames = "", status = Idle }


{-| Splits a comma-separated `AIProviderGrantForm.modelNames` input into the `List String`
`GrantAIProviderRequest.modelNames`/`AIProviderGrant.modelNames` expect -- trims each
entry and drops blanks (so "gpt-4, , gpt-3.5" and "gpt-4,gpt-3.5" behave the same), and a fully
blank input becomes `[]` (any model).
-}
parseModelNames : String -> List String
parseModelNames input =
    input
        |> String.split ","
        |> List.map String.trim
        |> List.filter (String.isEmpty >> not)


{-| The "AI Providers" section's own state -- mirrors `SyncSourcesState`'s doc: neither
the owned-providers list nor the granted-to-you list is fetched/held here -- both are _derived_ at
render time from the resolved `User.aiModels` (see `ownedAIProviders`/
`grantedAIModelAccess`), since `AIModel`s are self-or-Admin gated the same way
`sync_sources` is (see that field's own proto doc, and `AIModel`'s). `expandedGrants`/
`grantForms` track which providers' grant lists are open and their own in-progress "grant access"
forms; `deleteStatuses`/`revokeStatuses` are `Dict`s (keyed by provider id, and by
`"<providerId>:<granteeUserId>"` respectively) rather than single fields since, in principle, more
than one delete/revoke could be in flight at once (mirrors `SyncDestinationsState.deleteStatuses`).
Deletes/revokes are NOT routed through `Shared.DeleteConfirmation` -- same reasoning as
`SyncDestinationsState`'s own doc: removing a provider only drops its own credentials and grants,
nothing else.
-}
type alias AIProvidersState =
    { rowEdits : Dict String AIProviderRowEdit
    , addForm : AIProviderAddForm
    , expandedGrants : List String
    , grantForms : Dict String AIProviderGrantForm
    , deleteStatuses : Dict String SubmitStatus
    , revokeStatuses : Dict String SubmitStatus

    -- Manual "Refresh" button state (`AIProvidersRefreshClicked`) -- overlays a fresh
    -- `GetAIProviders` result onto the resolved `User` without a whole-profile `refetch`.
    , refreshStatus : SubmitStatus
    }


initAIProviders : AIProvidersState
initAIProviders =
    { rowEdits = Dict.empty
    , addForm = defaultAIProviderAddForm
    , expandedGrants = []
    , grantForms = Dict.empty
    , deleteStatuses = Dict.empty
    , revokeStatuses = Dict.empty
    , refreshStatus = Idle
    }


{-| This profile's own `AIProvider`s -- de-duplicated from `user.aiModels` (one entry
per model an owned provider supports, see that field's own proto doc), keeping each provider's full
detail (including its own `grants` list, needed by `aiProviderGrantsView`) from whichever entry
is encountered first. Empty for any viewer who isn't the profile's own user or an Admin, since the
backend never populates `ai_models` for anyone else.
-}
ownedAIProviders : User -> List AIProvider
ownedAIProviders user =
    user.aiModels
        |> List.filterMap
            (\available ->
                if available.grant == Nothing then
                    available.provider

                else
                    Nothing
            )
        |> List.foldl
            (\provider ( seen, acc ) ->
                if Set.member provider.id seen then
                    ( seen, acc )

                else
                    ( Set.insert provider.id seen, acc ++ [ provider ] )
            )
            ( Set.empty, [] )
        |> Tuple.second


{-| Access granted _to_ this profile's own user, on any provider (their own or someone else's) --
one `(provider, grant)` pair per distinct grant, de-duplicated from `user.aiModels` the
same way `ownedAIProviders` de-duplicates owned providers (each grant's own `modelNames`/
`tokensRemaining` already describes everything it covers, so there's no need to keep every
per-model `AIModel` row -- just one representative each). Empty for any viewer who isn't
the profile's own user or an Admin.
-}
grantedAIModelAccess : User -> List ( AIProvider, AIProviderGrant )
grantedAIModelAccess user =
    user.aiModels
        |> List.filterMap (\available -> Maybe.map2 Tuple.pair available.provider available.grant)
        |> List.foldl
            (\( provider, grant ) ( seen, acc ) ->
                let
                    key : String
                    key =
                        aiProviderGrantKey provider.id (grant.aiModelGrantee |> Maybe.map .userId |> Maybe.withDefault "")
                in
                if Set.member key seen then
                    ( seen, acc )

                else
                    ( Set.insert key seen, acc ++ [ ( provider, grant ) ] )
            )
            ( Set.empty, [] )
        |> Tuple.second


{-| `pageIsSecure` is `Shared.AccountsPanel.RellmServers.isSecure req` from the calling
page's own `Request` -- needed for `ConnectClicked` (see `RellmServers.connectToRellmServer`),
but not otherwise derivable from `Shared.Model` alone. `navKey`/`path`/`query` are
the calling page's own `Request.With Params`' `key`/`url.path`/`query` -- kept around
(rather than threaded through some other way) so the embedded `PostsPage`/`EventsPage`
copies (see `Model.posts`/`Model.events`) can be `init`ed later, once `resolver` actually
resolves a `User` to filter them by -- mirrors `PostsPage.init`/`EventsPage.init`'s own
`navKey`/`path`/`query` params exactly. `fragment` is the raw URL fragment (`req.url.fragment`),
mirroring `EventsPage.init`'s own `fragment` param -- here just checked for an exact
`"contact-methods"` match (unlike `EventsPage`'s `calendarPreviewKeyFromFragment` prefix parse) to
seed `contactMethodsExpanded`, so a `#contact-methods` link opens straight to that section already
expanded. `subscriptionsExpanded`/`syncSourcesExpanded`/`syncDestinationsExpanded`/
`aiProvidersExpanded`/`aiProviderGrantsExpanded` get the same treatment against their own
`"subscriptions"`/`"sync-sources"`/`"sync-destinations"`/`"ai-providers"`/`"ai-models"` fragments,
each also seeding `pendingScrollSectionId` (that field's own doc covers the scroll itself, which
-- unlike the plain expand-on-load above -- needs to wait for `Resolver.Loaded`, since the section
it targets isn't in the DOM at all until then).
-}
init : Shared.Model -> Bool -> String -> Resolver.Lookup -> Browser.Navigation.Key -> String -> Dict String String -> Maybe String -> ( Model, Effect Msg )
init shared pageIsSecure targetHost lookup navKey path query fragment =
    let
        ( resolverModel, resolverEffect ) =
            Resolver.init shared targetHost lookup

        model : Model
        model =
            { resolver = resolverModel
            , connectStatus = ServerDependentView.NotConnected
            , pageIsSecure = pageIsSecure
            , federatedProfiles = Dict.empty
            , realNameEdit = Nothing
            , avatarEdit = Nothing
            , visibilityEdit = Nothing
            , moderationEdit = Nothing
            , followModerationStatus = Idle
            , contactMethodsExpanded = fragment == Just "contact-methods"
            , phoneEdit = Nothing
            , emailEdit = Nothing
            , phoneConsentStatus = Idle
            , emailConsentStatus = Idle
            , phoneHistoryExpanded = False
            , emailHistoryExpanded = False
            , phoneVerification = Nothing
            , storageQuotaEdit = Nothing
            , storageQuotaExpanded = False
            , subscriptionsExpanded = fragment == Just "subscriptions"
            , cancelingSubscriptions = Dict.empty
            , permissionsEdit = Nothing
            , permissionsExpanded = False
            , federatedProfilesEdit = Nothing
            , passwordResetEdit = Nothing
            , syncSources = initSyncSources
            , syncSourcesExpanded = fragment == Just "sync-sources"
            , syncDestinations = initSyncDestinations
            , syncDestinationsExpanded = fragment == Just "sync-destinations"
            , aiProviders = initAIProviders
            , aiProvidersExpanded = fragment == Just "ai-providers"
            , aiProviderGrantsExpanded = fragment == Just "ai-models"
            , followStatusAndButton = FollowStatusAndButton.init
            , posts = Nothing
            , events = Nothing
            , navKey = navKey
            , path = path
            , query = query
            , pendingScrollSectionId =
                if List.member fragment (List.map Just [ "subscriptions", "sync-sources", "sync-destinations", "ai-providers", "ai-models" ]) then
                    fragment

                else
                    Nothing
            }
    in
    ( model
      -- Closes the Accounts Panel if it happened to be open -- landing on a
      -- profile page always shows the info an open panel would otherwise
      -- duplicate (see `Components.Pages.ServerInformationPage.init`, same
      -- reasoning).
    , Effect.batch
        [ Effect.map ResolverMsg resolverEffect
        , Effect.fromShared Shared.CloseAllPanels
        , setBreadcrumbsHost shared model
        ]
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Sub.map ResolverMsg (Resolver.subscriptions model.resolver)
        , model.posts |> Maybe.map (PostsPage.subscriptions >> Sub.map PostsMsg) |> Maybe.withDefault Sub.none
        , model.events |> Maybe.map (EventsPage.subscriptions >> Sub.map EventsMsg) |> Maybe.withDefault Sub.none
        , Ports.facebookLoginResult GotFacebookLoginResult
        , Ports.facebookLoginResult GotThreadsLoginResult
        , Ports.facebookLoginResult GotXTwitterLoginResult
        ]



-- UPDATE


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page
into `update`'s `SharedMsg` branch -- see `Pages.Post.PostId_.fromShared`.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg


{-| Turns a `Maybe AccountsPanel.Msg` (as returned by `Components.Users`'
requests, if a token refresh happened) into an `Effect` to forward it,
`Effect.none` otherwise.
-}
accountsPanelEffect : Maybe AccountsPanel.Msg -> Effect Msg
accountsPanelEffect maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


{-| `update`, plus keeping `Shared.Breadcrumbs` pointed at this profile's own
`FromServerHost targetHost` -- mirrors `Pages.Home_.setBreadcrumbsHost`
(reissued after every `update`, a no-op once already in sync via the same
equality check), except keyed to `model.resolver.targetHost` rather than
`mainFrontendHost`, since a profile page (unlike the home feed) always
belongs to one specific server. `targetHost` is already known from the route
by `init` (see `Pages.User.UserId_.init`/`Pages.UsernameOrCustomTab_.init`), so this
covers both the very first paint and any later host change (e.g.
`ConnectClicked` connecting a not-yet-connected `targetHost`).

This is the _only_ thing here allowed to touch `Shared.Breadcrumbs` --
`model.posts`/`model.events` are embedded `PostsPage`/`EventsPage` copies
(both `init`ed with `embeddedPage = True`), which leaves their own
`setBreadcrumbsRoot` a permanent no-op (see those docs).
Before that, both copies independently asserted their own root (`FromUser
user`) on every `update`, including every animation tick from
`model.events.eventAnimations` -- fighting this function's own
`FromServerHost` assertion right back on the very next tick, a continuous
flicker between the two roots.

-}
update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    let
        ( newModel, effect ) =
            updateInner shared msg model
    in
    ( newModel, Effect.batch [ effect, setBreadcrumbsHost shared newModel ] )


setBreadcrumbsHost : Shared.Model -> Model -> Effect Msg
setBreadcrumbsHost shared model =
    let
        host : String
        host =
            model.resolver.targetHost
    in
    if shared.breadcrumbs.root == Just (Breadcrumbs.FromServerHost host) then
        Effect.none

    else
        Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost host) host []))


{-| How many times `scrollToProfileSectionStep` will re-measure and re-correct before giving up
regardless of whether the target has settled -- `profileSectionScrollPollMs` apart, so ~1.8s of
total budget, comfortably past both a `UI.Flip` entrance (`flipDurationMs` = 250ms) and an
ordinary same-host network fetch (the embedded `EventsPage`/`PostsPage` copies' own data,
kicked off the same moment `sectionId` first shows -- see `Resolver.Loaded`'s own handling
below -- can still be loading in and growing/shrinking everything below it).
-}
profileSectionScrollMaxAttempts : Int
profileSectionScrollMaxAttempts =
    12


{-| The poll interval `scrollToProfileSectionStep` re-checks at once its very first, immediate
measurement is in.
-}
profileSectionScrollPollMs : Float
profileSectionScrollPollMs =
    150


{-| Scrolls the page (`Dom.setViewport`, not some inner pane -- unlike
`MessagesPage.scrollToPendingMessageCmd`, this section sits in the ordinary
page flow with nothing else to scroll) so `sectionId`'s own `expandableProfileSection`
`domId` lands at the top of the viewport -- the `Model.pendingScrollSectionId` half of a
`#subscriptions`/`#sync-sources`/`#sync-destinations`/`#ai-providers`/`#ai-models` deep
link, the other half being that same fragment seeding the section's own `*Expanded` flag
directly in `init` so it's already open by the time this runs.

Polls (`scrollToProfileSectionStep`) rather than a single measurement: content above `sectionId`
can keep changing height for a while after this first fires (a `UI.Flip`-entering embedded
calendar card, or `EventsPage`/`PostsPage`'s own async fetch still landing), so a single
snapshot can be stale by the time it's applied. Re-measuring and re-correcting on an interval,
stopping once two consecutive measurements agree (within a pixel) or
`profileSectionScrollMaxAttempts` runs out, adapts to however long _this_ load actually takes
instead of guessing one fixed number.

-}
scrollToProfileSectionCmd : String -> Cmd Msg
scrollToProfileSectionCmd sectionId =
    scrollToProfileSectionStep sectionId Nothing profileSectionScrollMaxAttempts
        |> Task.attempt (\_ -> ScrollToProfileSectionAttempted)


{-| One measure-and-correct pass for `scrollToProfileSectionCmd`'s own poll -- see that function's
doc for the full reasoning. `previousTarget` is the absolute document position the _last_ pass
computed (`Nothing` on the very first call), compared against this pass's own freshly-measured
`target` to decide whether to stop (settled) or schedule another pass `profileSectionScrollPollMs`
later (still moving, and `attemptsLeft` hasn't run out).

`el.element.y` (`Dom.getElement`'s own doc) is, despite its name, already an _absolute_ document
position -- the kernel computes it as `window.pageYOffset + rect.top`, the current scroll offset
already baked in -- so it's the whole target on its own, straight into `Dom.setViewport`. This
used to _also_ add `Dom.getViewport`'s own `.viewport.y` (the same current scroll offset, read a
second time) on top, double-counting it: harmless from a resting scroll position of `0` (where
doubling zero is still zero, so every one-off manual verification of this code happened to look
correct), but from anywhere else it inflated the target by exactly the current scroll position
-- worse with each successive poll as that error compounded into the next reading, which is what
was actually behind every "scrolls too far"/"lands one section past the target" report this
mechanism produced, independent of any content-still-growing timing story.

-}
scrollToProfileSectionStep : String -> Maybe Float -> Int -> Task.Task Dom.Error ()
scrollToProfileSectionStep sectionId previousTarget attemptsLeft =
    Dom.getElement sectionId
        |> Task.andThen
            (\el ->
                let
                    target : Float
                    target =
                        el.element.y
                in
                Dom.setViewport 0 target
                    |> Task.andThen
                        (\_ ->
                            let
                                settled : Bool
                                settled =
                                    previousTarget
                                        |> Maybe.map (\prev -> abs (prev - target) < 1)
                                        |> Maybe.withDefault False
                            in
                            if settled || attemptsLeft <= 0 then
                                Task.succeed ()

                            else
                                Process.sleep profileSectionScrollPollMs
                                    |> Task.andThen (\_ -> scrollToProfileSectionStep sectionId (Just target) (attemptsLeft - 1))
                        )
            )


{-| The dynamic counterpart to `init`'s own `fragment == Just "..."` seeding -- sets whichever
`*Expanded` flag `sectionId` (one of `expandableProfileSection`'s own `domId`s) names, a no-op for
any other string. Used by `Shared.ProfileSectionLinkClicked`'s handling below, where -- unlike
`init` -- the target section may already be mounted and just needs expanding in place, no fresh
`Resolver.Loaded` involved at all.
-}
expandProfileSection : String -> Model -> Model
expandProfileSection sectionId model =
    case sectionId of
        "subscriptions" ->
            { model | subscriptionsExpanded = True }

        "sync-sources" ->
            { model | syncSourcesExpanded = True }

        "sync-destinations" ->
            { model | syncDestinationsExpanded = True }

        "ai-providers" ->
            { model | aiProvidersExpanded = True }

        "ai-models" ->
            { model | aiProviderGrantsExpanded = True }

        _ ->
            model


{-| `expandProfileSection`'s own missing half for `"sync-sources"`/`"sync-destinations"`
specifically: those two sections' expanded state _also_ drives extra per-card sync UI inside the
embedded `EventsPage` (and, for destinations, `PostsPage` too) copies -- `eventCardView`'s own
`showSyncSources`/`showSyncDestinations` params, which change each card's height and so the whole
embedded calendar/feed's height, shifting everything below it (including the very section this
scroll is heading for). The ordinary header-click path (`SyncSourcesExpandedToggled`/
`SyncDestinationsExpandedToggled` above) already keeps `model.events`/`model.posts` in sync this
way; `Shared.ProfileSectionLinkClicked`'s own handling below needs the identical propagation, or
`scrollToProfileSectionCmd` ends up measuring `sectionId`'s position _before_ the calendar/feed
has actually grown into its expanded state -- reported as "doesn't scroll all the way up to Sync
Sources/Sync Destinations" when the viewer started further down the page than that stale,
pre-growth position.

Always forces the flag `True` (never toggles) -- unlike the header click, a section link is only
ever asking to _open_ the section, never close an already-open one.

-}
syncEmbeddedSyncToggles : Shared.Model -> String -> Model -> ( Model, Effect Msg )
syncEmbeddedSyncToggles shared sectionId model =
    case sectionId of
        "sync-sources" ->
            case model.events of
                Just eventsModel ->
                    let
                        ( newEventsModel, eventsEffect ) =
                            EventsPage.update shared (EventsPage.showSyncSourcesChanged True) eventsModel
                    in
                    ( { model | events = Just newEventsModel }, Effect.map EventsMsg eventsEffect )

                Nothing ->
                    ( model, Effect.none )

        "sync-destinations" ->
            let
                ( eventsUpdatedModel, eventsEffect ) =
                    case model.events of
                        Just eventsModel ->
                            let
                                ( newEventsModel, effect ) =
                                    EventsPage.update shared (EventsPage.showSyncDestinationsChanged True) eventsModel
                            in
                            ( { model | events = Just newEventsModel }, effect )

                        Nothing ->
                            ( model, Effect.none )

                ( postsUpdatedModel, postsEffect ) =
                    case eventsUpdatedModel.posts of
                        Just postsModel ->
                            let
                                ( newPostsModel, effect ) =
                                    PostsPage.update shared (PostsPage.showSyncDestinationsChanged True) postsModel
                            in
                            ( { eventsUpdatedModel | posts = Just newPostsModel }, effect )

                        Nothing ->
                            ( eventsUpdatedModel, Effect.none )
            in
            ( postsUpdatedModel, Effect.batch [ Effect.map EventsMsg eventsEffect, Effect.map PostsMsg postsEffect ] )

        _ ->
            ( model, Effect.none )


updateInner : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared msg model =
    case msg of
        ResolverMsg subMsg ->
            let
                ( newResolver, resolverEffect ) =
                    Resolver.update shared subMsg model.resolver

                newModel : Model
                newModel =
                    { model | resolver = newResolver }
            in
            case ( subMsg, newResolver.status ) of
                ( Resolver.GotUser (Ok _), Resolver.Loaded user ) ->
                    let
                        ( federatedModel, federatedEffect ) =
                            kickOffFederatedFetches shared user newModel

                        -- Only ever `init`ed once -- see `Model.posts`/`Model.events`'
                        -- own doc for why a later refetch (which re-fires this same
                        -- `Loaded` case) must leave an already-`Just` copy alone.
                        ( postsInitedModel, postsInitEffect ) =
                            case federatedModel.posts of
                                Just _ ->
                                    ( federatedModel, Effect.none )

                                Nothing ->
                                    let
                                        ( postsModel, postsEffect ) =
                                            PostsPage.init shared (Just ( newResolver.targetHost, user )) federatedModel.navKey federatedModel.path federatedModel.query True (Just user.syncDestinations) Nothing
                                    in
                                    ( { federatedModel
                                        | posts =
                                            Just { postsModel | showSyncDestinations = model.syncDestinationsExpanded }
                                      }
                                    , Effect.map PostsMsg postsEffect
                                    )

                        ( eventsInitedModel, eventsInitEffect ) =
                            case postsInitedModel.events of
                                Just _ ->
                                    ( postsInitedModel, Effect.none )

                                Nothing ->
                                    let
                                        ( eventsModel, eventsEffect ) =
                                            EventsPage.init shared (Just ( newResolver.targetHost, user )) postsInitedModel.navKey postsInitedModel.path postsInitedModel.query Nothing True False (Just user.syncDestinations) Nothing True
                                    in
                                    ( { postsInitedModel
                                        | events =
                                            Just
                                                { eventsModel
                                                    | showSyncSources = model.syncSourcesExpanded
                                                    , showSyncDestinations = model.syncDestinationsExpanded
                                                }
                                      }
                                    , Effect.map EventsMsg eventsEffect
                                    )

                        -- A *refetch* (not just the first load) needs this too --
                        -- the `Just _ -> (postsInitedModel, Effect.none)` guard
                        -- above deliberately leaves an already-`init`ed
                        -- `EventsPage.Model` alone, so its own `availableSyncDestinations`
                        -- (seeded once, at `init` time) would otherwise go stale
                        -- after e.g. linking/unlinking a Facebook Page (see
                        -- `refetch`'s own call sites below). Harmless/redundant on
                        -- the very first load, where `init` above already got the
                        -- right value directly.
                        eventsResyncedModel : Model
                        eventsResyncedModel =
                            { eventsInitedModel
                                | events =
                                    eventsInitedModel.events
                                        |> Maybe.map (\em -> { em | availableSyncDestinations = Just user.syncDestinations })
                            }

                        -- Same reasoning as `eventsResyncedModel` above, just for the
                        -- embedded `PostsPage.Model`'s own `availableSyncDestinations`.
                        postsResyncedModel : Model
                        postsResyncedModel =
                            { eventsResyncedModel
                                | posts =
                                    eventsResyncedModel.posts
                                        |> Maybe.map (\pm -> { pm | availableSyncDestinations = Just user.syncDestinations })
                            }

                        -- `Model.pendingScrollSectionId`'s own doc: only set on the very
                        -- first `Loaded` (from `init`'s own fragment), and always cleared
                        -- right after, so a later refetch's re-`Loaded` (e.g. after a
                        -- follow/unfollow) doesn't keep scrolling back to it.
                        scrollEffect : Effect Msg
                        scrollEffect =
                            case model.pendingScrollSectionId of
                                Just sectionId ->
                                    Effect.fromCmd (scrollToProfileSectionCmd sectionId)

                                Nothing ->
                                    Effect.none
                    in
                    ( { postsResyncedModel | pendingScrollSectionId = Nothing }
                    , Effect.batch
                        [ Effect.map ResolverMsg resolverEffect
                        , federatedEffect
                        , postsInitEffect
                        , eventsInitEffect
                        , scrollEffect
                        ]
                    )

                _ ->
                    ( newModel, Effect.map ResolverMsg resolverEffect )

        PostsMsg subMsg ->
            case model.posts of
                Just postsModel ->
                    let
                        ( newPosts, postsEffect ) =
                            PostsPage.update shared subMsg postsModel

                        -- Keeps `EventsPage`'s own search box (the only one actually
                        -- shown, see `view`'s `showSearchRow = False`) in sync with
                        -- this hidden copy's `searchText` -- mirrors
                        -- `Pages.Home_.update`'s identical `PostsMsg`/`EventsMsg`
                        -- cross-sync exactly, just over `Maybe`-wrapped models.
                        ( syncedEvents, syncEffect ) =
                            case model.events of
                                Just eventsModel ->
                                    if newPosts.searchText /= eventsModel.searchText then
                                        EventsPage.update shared (EventsPage.searchTextChanged newPosts.searchText) eventsModel
                                            |> Tuple.mapFirst Just

                                    else
                                        ( model.events, Effect.none )

                                Nothing ->
                                    ( model.events, Effect.none )
                    in
                    ( { model | posts = Just newPosts, events = syncedEvents }
                    , Effect.batch [ Effect.map PostsMsg postsEffect, Effect.map EventsMsg syncEffect ]
                    )

                Nothing ->
                    ( model, Effect.none )

        EventsMsg subMsg ->
            case model.events of
                Just eventsModel ->
                    let
                        ( newEvents, eventsEffect ) =
                            EventsPage.update shared subMsg eventsModel

                        ( syncedPosts, syncEffect ) =
                            case model.posts of
                                Just postsModel ->
                                    if newEvents.searchText /= postsModel.searchText then
                                        PostsPage.update shared (PostsPage.searchTextChanged newEvents.searchText) postsModel
                                            |> Tuple.mapFirst Just

                                    else
                                        ( model.posts, Effect.none )

                                Nothing ->
                                    ( model.posts, Effect.none )
                    in
                    ( { model | events = Just newEvents, posts = syncedPosts }
                    , Effect.batch [ Effect.map EventsMsg eventsEffect, Effect.map PostsMsg syncEffect ]
                    )

                Nothing ->
                    ( model, Effect.none )

        ConnectClicked ->
            ( { model | connectStatus = ServerDependentView.Connecting }
            , RellmServers.connectToRellmServer model.pageIsSecure model.resolver.targetHost
                |> Task.attempt GotConnectResult
                |> Effect.fromCmd
            )

        GotConnectResult (Ok server) ->
            let
                ( newResolver, resolverEffect ) =
                    Resolver.fetchIfReady shared model.resolver
            in
            ( { model | connectStatus = ServerDependentView.NotConnected, resolver = newResolver }
            , Effect.batch
                [ Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ServerConnected server))
                , Effect.map ResolverMsg resolverEffect
                ]
            )

        GotConnectResult (Err err) ->
            ( { model | connectStatus = ServerDependentView.ConnectFailed (AccountsPanel.grpcErrorToString err) }
            , Effect.none
            )

        EnableClicked ->
            ( model, Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ToggleServerEnabled model.resolver.targetHost)) )

        SharedMsg subMsg ->
            let
                ( resolvedModel, resolverEffect ) =
                    Resolver.update shared (Resolver.fromShared subMsg) model.resolver
                        |> Tuple.mapFirst (\newResolver -> { model | resolver = newResolver })
                        |> Tuple.mapSecond (Effect.map ResolverMsg)

                ( fetchedModel, fetchEffect ) =
                    case subMsg of
                        Shared.MarkdownPanelMsg (MarkdownPanel.GotSaveResult (Ok _)) ->
                            refetch shared resolvedModel

                        -- The shared `Shared.MyMediaPanel` chooser (opened by
                        -- `AvatarEditClicked`) reports a tap this way -- see
                        -- `Shared.MyMediaPanel`'s own module doc on why this
                        -- forwarded `Shared.Msg`, not some closure/callback,
                        -- is what delivers the pick back here. Gated on
                        -- `avatarEdit` already being `Just` so an unrelated
                        -- Browse-mode tap (e.g. from the Accounts Panel)
                        -- elsewhere can't be mistaken for an avatar pick.
                        Shared.MyMediaPanelMsg (MyMediaPanel.MediaItemClicked mediaId) ->
                            ( { resolvedModel
                                | avatarEdit =
                                    resolvedModel.avatarEdit |> Maybe.map (\edit -> { edit | choice = AvatarChosen mediaId })
                              }
                            , Effect.none
                            )

                        -- A successful delete of a Sync Source (fired
                        -- directly from `Shared.update`'s `ConfirmDelete`,
                        -- see `Shared.ConfirmSyncSourceDelete`'s own
                        -- doc) can remove Events/Occasions behind the
                        -- already-`init`ed `EventsPage` copy's back --
                        -- refresh it so the change shows up without a manual
                        -- page reload. Also refetches the resolved `User`
                        -- itself (see `refetch`) so `user.syncSources`
                        -- (the section's own list, no longer held locally --
                        -- see `SyncSourcesState`'s own doc) drops the
                        -- deleted source too. (A successful row Save/Refresh
                        -- triggers the same pair directly from
                        -- `GotSyncSourceRowSaveResult` below, since that
                        -- request -- unlike a delete -- is fired from this
                        -- page's own `Msg`, not routed through `Shared`.)
                        Shared.GotSyncSourceDeleteResult (Ok _) ->
                            let
                                ( eventsRefetchedModel, eventsRefetchEffect ) =
                                    refetchEvents shared resolvedModel

                                ( refetchedModel, refetchEffect ) =
                                    refetch shared eventsRefetchedModel
                            in
                            ( refetchedModel, Effect.batch [ eventsRefetchEffect, refetchEffect ] )

                        -- This page's own `DeleteUserClicked` (via
                        -- `Shared.RequestDelete`/`Shared.ConfirmDelete`)
                        -- resolving successfully -- the profile being
                        -- viewed no longer exists, so navigate away, same
                        -- as `Pages.Post.PostId_`'s own
                        -- `Shared.GotPostDeleteResult` handling. Signing
                        -- out locally, if it was the viewer's own account
                        -- being deleted, happens in `Shared.update`'s own
                        -- handling of this same result, not here --
                        -- `Main.notifyPageOfSharedMsg` (which is what
                        -- delivers a top-level-originated `Shared.Msg` like
                        -- this one to a page) silently drops any *new*
                        -- `Shared.Msg` a page's own `SharedMsg` branch
                        -- forwards back in response, on the assumption
                        -- that only an echo of the incoming message itself
                        -- is ever forwarded that way -- see its own doc.
                        Shared.GotUserDeleteResult _ _ (Ok _) ->
                            ( resolvedModel
                            , Browser.Navigation.pushUrl resolvedModel.navKey (Gen.Route.toHref Gen.Route.Home_) |> Effect.fromCmd
                            )

                        -- `Shared.ProfileSectionLinkClicked`'s own doc: reaches every
                        -- currently-mounted page, but only actually expand + scroll
                        -- if `account` names *this* page's own resolved profile -- an
                        -- Admin viewing someone else's profile while another account's
                        -- chip fires this (or a page mounted for a different user
                        -- entirely) leaves it untouched, same as `init`'s own fragment
                        -- handling would for a profile that isn't the one it loads.
                        Shared.ProfileSectionLinkClicked account sectionId ->
                            case resolvedModel.resolver.status of
                                Resolver.Loaded user ->
                                    if account.server == resolvedModel.resolver.targetHost && account.userId == user.id then
                                        let
                                            ( syncedModel, syncEffect ) =
                                                syncEmbeddedSyncToggles shared sectionId (expandProfileSection sectionId resolvedModel)
                                        in
                                        ( syncedModel
                                        , Effect.batch [ syncEffect, Effect.fromCmd (scrollToProfileSectionCmd sectionId) ]
                                        )

                                    else
                                        ( resolvedModel, Effect.none )

                                _ ->
                                    ( resolvedModel, Effect.none )

                        _ ->
                            ( resolvedModel, Effect.none )

                -- Forwarded on into the embedded `PostsPage`/`EventsPage` copies (if
                -- already `init`ed) the same way `Pages.Home_.update`'s own `SharedMsg`
                -- branch does -- e.g. an `AccountsPanelMsg` re-fetches both against the
                -- newly (dis)connected/(dis)abled server. `Effect.partitionShared`
                -- drops each one's own echoed re-broadcast of `subMsg` (see
                -- `PostsPage.update`/`EventsPage.update`'s own `SharedMsg` branch,
                -- which unconditionally re-emits it) -- `resolverEffect` above is
                -- already the one canonical copy of that echo; keeping either of
                -- these too would apply the same `Shared.Msg` several times over in
                -- one pass, harmless for most but a net-zero no-op for a toggle (see
                -- `Pages.Home_`'s own doc comment for the full "can't open the
                -- Accounts Panel" story this mirrors).
                ( postsSyncedModel, postsSyncEffect ) =
                    case fetchedModel.posts of
                        Just postsModel ->
                            let
                                ( newPosts, postsEffectRaw ) =
                                    PostsPage.update shared (PostsPage.fromShared subMsg) postsModel

                                ( _, postsEffect ) =
                                    Effect.partitionShared postsEffectRaw
                            in
                            ( { fetchedModel | posts = Just newPosts }, Effect.map PostsMsg postsEffect )

                        Nothing ->
                            ( fetchedModel, Effect.none )

                ( eventsSyncedModel, eventsSyncEffect ) =
                    case postsSyncedModel.events of
                        Just eventsModel ->
                            let
                                ( newEvents, eventsEffectRaw ) =
                                    EventsPage.update shared (EventsPage.fromShared subMsg) eventsModel

                                ( _, eventsEffect ) =
                                    Effect.partitionShared eventsEffectRaw
                            in
                            ( { postsSyncedModel | events = Just newEvents }, Effect.map EventsMsg eventsEffect )

                        Nothing ->
                            ( postsSyncedModel, Effect.none )
            in
            ( eventsSyncedModel, Effect.batch [ resolverEffect, fetchEffect, postsSyncEffect, eventsSyncEffect ] )

        RealNameEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model | realNameEdit = Just { input = user.realName, status = Idle } }, Effect.none )

                _ ->
                    ( model, Effect.none )

        RealNameInputChanged input ->
            ( { model | realNameEdit = model.realNameEdit |> Maybe.map (\edit -> { edit | input = input }) }
            , Effect.none
            )

        RealNameCancelClicked ->
            ( { model | realNameEdit = Nothing }, Effect.none )

        RealNameSaveClicked ->
            case ( model.resolver.status, model.realNameEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | realNameEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts ( Just account.userId, server.frontendHost ) user.id (\freshUser -> { freshUser | realName = edit.input })
                        |> Task.attempt GotRealNameSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotRealNameSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, realNameEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotRealNameSaveResult (Err err) ->
            ( { model
                | realNameEdit =
                    model.realNameEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        AvatarEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model
                        | avatarEdit =
                            -- Preserves an already-in-progress `choice`/`status`
                            -- rather than resetting it -- this same message
                            -- doubles as "re-open the picker" (see `avatarView`'s
                            -- tap-the-avatar-while-editing handler), which
                            -- shouldn't discard whatever's already been picked.
                            case model.avatarEdit of
                                Just edit ->
                                    Just edit

                                Nothing ->
                                    Just { choice = AvatarUnchanged, status = Idle }
                      }
                    , Effect.fromShared
                        (Shared.MyMediaPanelMsg
                            (MyMediaPanel.Open
                                (Just (MyMediaPanel.SingleSelect { imagesOnly = True, initialSelection = user.avatar }))
                                model.resolver.targetHost
                            )
                        )
                    )

                _ ->
                    ( model, Effect.none )

        AvatarRemoveClicked ->
            ( { model | avatarEdit = model.avatarEdit |> Maybe.map (\edit -> { edit | choice = AvatarRemoved }) }
            , Effect.none
            )

        AvatarCancelClicked ->
            ( { model | avatarEdit = Nothing }
            , Effect.fromShared (Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked)
            )

        AvatarSaveClicked ->
            case ( model.resolver.status, model.avatarEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | avatarEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts ( Just account.userId, server.frontendHost ) user.id (applyAvatarChoice edit.choice)
                        |> Task.attempt GotAvatarSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotAvatarSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, avatarEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAvatarSaveResult (Err err) ->
            ( { model
                | avatarEdit =
                    model.avatarEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        BioEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.UserBio user) model.resolver.targetHost)) )

                _ ->
                    ( model, Effect.none )

        VisibilityEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model | visibilityEdit = Just { pending = user.visibility, status = Idle } }, Effect.none )

                _ ->
                    ( model, Effect.none )

        VisibilityChanged text ->
            ( { model
                | visibilityEdit =
                    model.visibilityEdit
                        |> Maybe.map (\edit -> { edit | pending = Users.visibilityFromText text |> Maybe.withDefault edit.pending })
              }
            , Effect.none
            )

        VisibilityCancelClicked ->
            ( { model | visibilityEdit = Nothing }, Effect.none )

        VisibilitySaveClicked ->
            case ( model.resolver.status, model.visibilityEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | visibilityEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts ( Just account.userId, server.frontendHost ) user.id (\freshUser -> { freshUser | visibility = edit.pending })
                        |> Task.attempt GotVisibilitySaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotVisibilitySaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, visibilityEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotVisibilitySaveResult (Err err) ->
            ( { model
                | visibilityEdit =
                    model.visibilityEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        ModerationEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model | moderationEdit = Just { pending = user.moderation, status = Idle } }, Effect.none )

                _ ->
                    ( model, Effect.none )

        ModerationChanged text ->
            ( { model
                | moderationEdit =
                    model.moderationEdit
                        |> Maybe.map (\edit -> { edit | pending = Users.moderationFromText text |> Maybe.withDefault edit.pending })
              }
            , Effect.none
            )

        ModerationCancelClicked ->
            ( { model | moderationEdit = Nothing }, Effect.none )

        ModerationSaveClicked ->
            case ( model.resolver.status, model.moderationEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | moderationEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts ( Just account.userId, server.frontendHost ) user.id (\freshUser -> { freshUser | moderation = edit.pending })
                        |> Task.attempt GotModerationSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotModerationSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, moderationEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotModerationSaveResult (Err err) ->
            ( { model
                | moderationEdit =
                    model.moderationEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        FollowModerationToggled ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    let
                        newModeration : Moderation
                        newModeration =
                            if user.defaultFollowModeration == PENDING then
                                UNMODERATED

                            else
                                PENDING
                    in
                    ( { model | followModerationStatus = Submitting }
                    , Users.updateUser shared.accounts ( Just account.userId, server.frontendHost ) user.id (\freshUser -> { freshUser | defaultFollowModeration = newModeration })
                        |> Task.attempt GotFollowModerationSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFollowModerationSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, followModerationStatus = Idle }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotFollowModerationSaveResult (Err err) ->
            ( { model | followModerationStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        ContactMethodsExpandedToggled ->
            ( { model | contactMethodsExpanded = not model.contactMethodsExpanded }, Effect.none )

        PhoneEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model
                        | phoneEdit =
                            Just
                                { input = contactMethodEditValue "tel:" user.phone
                                , visibility = user.phone |> Maybe.map .visibility |> Maybe.withDefault PRIVATE
                                , status = Idle
                                }
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        PhoneInputChanged input ->
            ( { model | phoneEdit = model.phoneEdit |> Maybe.map (\edit -> { edit | input = input }) }
            , Effect.none
            )

        PhoneVisibilityChanged text ->
            ( { model
                | phoneEdit =
                    model.phoneEdit
                        |> Maybe.map (\edit -> { edit | visibility = Posts.visibilityFromText text |> Maybe.withDefault edit.visibility })
              }
            , Effect.none
            )

        PhoneCancelClicked ->
            ( { model | phoneEdit = Nothing }, Effect.none )

        PhoneSaveClicked ->
            case ( model.resolver.status, model.phoneEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | phoneEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts
                        ( Just account.userId, server.frontendHost )
                        user.id
                        (\freshUser ->
                            { freshUser
                                | phone =
                                    Just
                                        { value = Just ("tel:" ++ edit.input)
                                        , visibility = edit.visibility
                                        , supportedByServer = False
                                        , verifiedAt = Nothing
                                        , verificationInProgress = Nothing

                                        -- Consent is edited separately (`PhoneConsentToggled`) --
                                        -- changing the number/visibility here must not silently
                                        -- grant or revoke it, so it's always carried forward from
                                        -- whatever `freshUser.phone` (the just-refetched, current
                                        -- copy) already has.
                                        , consentState = freshUser.phone |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED
                                        , consentHistory = freshUser.phone |> Maybe.map .consentHistory |> Maybe.withDefault []
                                        }
                            }
                        )
                        |> Task.attempt GotPhoneSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPhoneSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, phoneEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotPhoneSaveResult (Err err) ->
            ( { model
                | phoneEdit =
                    model.phoneEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        PhoneConsentToggled ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    let
                        newConsent : ContactConsentState
                        newConsent =
                            if (user.phone |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED) == CONTACTCONSENTGRANTED then
                                CONTACTCONSENTREVOKED

                            else
                                CONTACTCONSENTGRANTED
                    in
                    ( { model | phoneConsentStatus = Submitting }
                    , Users.updateUser shared.accounts
                        ( Just account.userId, server.frontendHost )
                        user.id
                        (\freshUser ->
                            { freshUser
                                | phone = freshUser.phone |> Maybe.map (\cm -> { cm | consentState = newConsent })
                            }
                        )
                        |> Task.attempt GotPhoneConsentSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPhoneConsentSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, phoneConsentStatus = Idle }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotPhoneConsentSaveResult (Err err) ->
            ( { model | phoneConsentStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        PhoneHistoryToggled ->
            ( { model | phoneHistoryExpanded = not model.phoneHistoryExpanded }, Effect.none )

        EmailEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model
                        | emailEdit =
                            Just
                                { input = contactMethodEditValue "mailto:" user.email
                                , visibility = user.email |> Maybe.map .visibility |> Maybe.withDefault PRIVATE
                                , status = Idle
                                }
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        EmailInputChanged input ->
            ( { model | emailEdit = model.emailEdit |> Maybe.map (\edit -> { edit | input = input }) }
            , Effect.none
            )

        EmailVisibilityChanged text ->
            ( { model
                | emailEdit =
                    model.emailEdit
                        |> Maybe.map (\edit -> { edit | visibility = Posts.visibilityFromText text |> Maybe.withDefault edit.visibility })
              }
            , Effect.none
            )

        EmailCancelClicked ->
            ( { model | emailEdit = Nothing }, Effect.none )

        EmailSaveClicked ->
            case ( model.resolver.status, model.emailEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | emailEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts
                        ( Just account.userId, server.frontendHost )
                        user.id
                        (\freshUser ->
                            { freshUser
                                | email =
                                    Just
                                        { value = Just ("mailto:" ++ edit.input)
                                        , visibility = edit.visibility
                                        , supportedByServer = False
                                        , verifiedAt = Nothing
                                        , verificationInProgress = Nothing

                                        -- Same reasoning as `PhoneSaveClicked` -- consent is edited
                                        -- separately (`EmailConsentToggled`), so it's always
                                        -- carried forward unchanged here.
                                        , consentState = freshUser.email |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED
                                        , consentHistory = freshUser.email |> Maybe.map .consentHistory |> Maybe.withDefault []
                                        }
                            }
                        )
                        |> Task.attempt GotEmailSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotEmailSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, emailEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotEmailSaveResult (Err err) ->
            ( { model
                | emailEdit =
                    model.emailEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        EmailConsentToggled ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    let
                        newConsent : ContactConsentState
                        newConsent =
                            if (user.email |> Maybe.map .consentState |> Maybe.withDefault CONTACTCONSENTREVOKED) == CONTACTCONSENTGRANTED then
                                CONTACTCONSENTREVOKED

                            else
                                CONTACTCONSENTGRANTED
                    in
                    ( { model | emailConsentStatus = Submitting }
                    , Users.updateUser shared.accounts
                        ( Just account.userId, server.frontendHost )
                        user.id
                        (\freshUser ->
                            { freshUser
                                | email = freshUser.email |> Maybe.map (\cm -> { cm | consentState = newConsent })
                            }
                        )
                        |> Task.attempt GotEmailConsentSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotEmailConsentSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, emailConsentStatus = Idle }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotEmailConsentSaveResult (Err err) ->
            ( { model | emailConsentStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        EmailHistoryToggled ->
            ( { model | emailHistoryExpanded = not model.emailHistoryExpanded }, Effect.none )

        StartPhoneVerificationClicked ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    case user.phone of
                        Just contactMethod ->
                            let
                                pendingVerification : PhoneVerification
                                pendingVerification =
                                    model.phoneVerification
                                        |> Maybe.map (\pv -> { pv | sendStatus = Submitting })
                                        |> Maybe.withDefault { sendStatus = Submitting, code = "", verifyStatus = Idle, cooldownActive = False }
                            in
                            ( { model | phoneVerification = Just pendingVerification }
                            , Users.startContactMethodVerification shared.accounts ( Just account.userId, server.frontendHost ) contactMethod
                                |> Task.attempt GotStartPhoneVerificationResult
                                |> Effect.fromCmd
                            )

                        Nothing ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotStartPhoneVerificationResult (Ok ( maybeAccountsPanelMsg, updatedContactMethod )) ->
            ( { model
                | resolver = withResolvedUserPhone updatedContactMethod model.resolver
                , phoneVerification =
                    model.phoneVerification |> Maybe.map (\pv -> { pv | sendStatus = Idle, cooldownActive = True })
              }
            , Effect.batch
                [ accountsPanelEffect maybeAccountsPanelMsg
                , Process.sleep 60000 |> Task.perform (\_ -> PhoneVerificationCooldownElapsed) |> Effect.fromCmd
                ]
            )

        GotStartPhoneVerificationResult (Err err) ->
            ( { model
                | phoneVerification =
                    model.phoneVerification |> Maybe.map (\pv -> { pv | sendStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        PhoneVerificationCooldownElapsed ->
            ( { model | phoneVerification = model.phoneVerification |> Maybe.map (\pv -> { pv | cooldownActive = False }) }
            , Effect.none
            )

        PhoneVerificationCodeChanged code ->
            ( { model | phoneVerification = model.phoneVerification |> Maybe.map (\pv -> { pv | code = code }) }
            , Effect.none
            )

        VerifyPhoneCodeClicked ->
            case ( model.resolver.status, model.phoneVerification, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just pendingVerification, Just ( server, account ) ) ->
                    case user.phone |> Maybe.andThen .value of
                        Just phoneValue ->
                            ( { model | phoneVerification = Just { pendingVerification | verifyStatus = Submitting } }
                            , Users.verifyContactMethod shared.accounts
                                ( Just account.userId, server.frontendHost )
                                { value = phoneValue, code = pendingVerification.code }
                                |> Task.attempt GotVerifyPhoneCodeResult
                                |> Effect.fromCmd
                            )

                        Nothing ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotVerifyPhoneCodeResult (Ok ( maybeAccountsPanelMsg, updatedContactMethod )) ->
            ( { model
                | resolver = withResolvedUserPhone updatedContactMethod model.resolver
                , phoneVerification = Nothing
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotVerifyPhoneCodeResult (Err err) ->
            ( { model
                | phoneVerification =
                    model.phoneVerification |> Maybe.map (\pv -> { pv | verifyStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        StorageQuotaExpandedToggled ->
            ( { model | storageQuotaExpanded = not model.storageQuotaExpanded }, Effect.none )

        StorageQuotaEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    let
                        used : Int
                        used =
                            Conversions.int64ToInt user.mediaStorageBytesUsed

                        limit : Maybe Int
                        limit =
                            Maybe.map Conversions.int64ToInt user.mediaStorageLimitBytes

                        unit : ByteFormat.ByteUnit
                        unit =
                            ByteFormat.bytesToUnit (Maybe.withDefault used limit)
                    in
                    ( { model
                        | storageQuotaEdit =
                            Just
                                { pending = limit |> Maybe.map (\l -> String.fromFloat (toFloat l / toFloat (ByteFormat.byteUnitBytes unit))) |> Maybe.withDefault ""
                                , unit = unit
                                , unlimited = limit == Nothing
                                , status = Idle
                                }
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        StorageQuotaPendingChanged text ->
            ( { model | storageQuotaEdit = model.storageQuotaEdit |> Maybe.map (\edit -> { edit | pending = text }) }, Effect.none )

        StorageQuotaUnitChanged text ->
            ( { model
                | storageQuotaEdit =
                    model.storageQuotaEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | unit =
                                        case text of
                                            "B" ->
                                                ByteFormat.Bytes

                                            "KB" ->
                                                ByteFormat.KB

                                            "MB" ->
                                                ByteFormat.MB

                                            "GB" ->
                                                ByteFormat.GB

                                            _ ->
                                                edit.unit
                                }
                            )
              }
            , Effect.none
            )

        StorageQuotaUnlimitedToggled ->
            ( { model | storageQuotaEdit = model.storageQuotaEdit |> Maybe.map (\edit -> { edit | unlimited = not edit.unlimited }) }, Effect.none )

        StorageQuotaCancelClicked ->
            ( { model | storageQuotaEdit = Nothing }, Effect.none )

        StorageQuotaSaveClicked ->
            case ( model.resolver.status, model.storageQuotaEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    let
                        newLimit : Maybe Int
                        newLimit =
                            if edit.unlimited then
                                Nothing

                            else
                                ByteFormat.parseBytes edit.unit edit.pending
                    in
                    if not edit.unlimited && newLimit == Nothing then
                        ( { model | storageQuotaEdit = Just { edit | status = SubmitFailed "Enter a valid number." } }, Effect.none )

                    else
                        ( { model | storageQuotaEdit = Just { edit | status = Submitting } }
                        , Users.updateUser shared.accounts
                            ( Just account.userId, server.frontendHost )
                            user.id
                            (\freshUser -> { freshUser | mediaStorageLimitBytes = Maybe.map Conversions.int64FromInt newLimit })
                            |> Task.attempt GotStorageQuotaSaveResult
                            |> Effect.fromCmd
                        )

                _ ->
                    ( model, Effect.none )

        GotStorageQuotaSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, storageQuotaEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotStorageQuotaSaveResult (Err err) ->
            ( { model
                | storageQuotaEdit =
                    model.storageQuotaEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        ShowMyMediaClicked ->
            ( model, Effect.fromShared (Shared.MyMediaPanelMsg (MyMediaPanel.Open Nothing model.resolver.targetHost)) )

        SubscriptionsExpandedToggled ->
            ( { model | subscriptionsExpanded = not model.subscriptionsExpanded }, Effect.none )

        CancelSubscriptionClicked subscription ->
            case serverAndAccount shared model of
                Just ( server, account ) ->
                    ( { model | cancelingSubscriptions = Dict.insert subscription.id Submitting model.cancelingSubscriptions }
                    , Market.cancelMarketSubscription shared.accounts ( Just account.userId, server.frontendHost ) subscription
                        |> Task.attempt (GotCancelSubscriptionResult subscription.id)
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        GotCancelSubscriptionResult subscriptionId (Ok ( maybeAccountsPanelMsg, updated )) ->
            ( { model
                | cancelingSubscriptions = Dict.remove subscriptionId model.cancelingSubscriptions
                , resolver = withResolvedSubscription updated model.resolver
              }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotCancelSubscriptionResult subscriptionId (Err err) ->
            ( { model
                | cancelingSubscriptions =
                    Dict.insert subscriptionId (SubmitFailed (AccountsPanel.grpcErrorToString err)) model.cancelingSubscriptions
              }
            , Effect.none
            )

        PermissionsExpandedToggled ->
            ( { model | permissionsExpanded = not model.permissionsExpanded }, Effect.none )

        PermissionsEditClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( { model | permissionsEdit = Just (newPermissionsEdit user.permissions) }, Effect.none )

                _ ->
                    ( model, Effect.none )

        PermissionRemoveClicked permission ->
            ( { model
                | permissionsEdit =
                    model.permissionsEdit
                        |> Maybe.map
                            (\edit ->
                                let
                                    pending : List Permission
                                    pending =
                                        List.filter ((/=) permission) edit.pending
                                in
                                { edit | pending = pending, addSelection = resolveAddSelection edit.addSelection pending }
                            )
              }
            , Effect.none
            )

        PermissionAddSelectionChanged text ->
            ( { model
                | permissionsEdit =
                    model.permissionsEdit |> Maybe.map (\edit -> { edit | addSelection = Users.permissionFromText text })
              }
            , Effect.none
            )

        PermissionAddClicked ->
            ( { model
                | permissionsEdit =
                    model.permissionsEdit
                        |> Maybe.map
                            (\edit ->
                                case edit.addSelection of
                                    Just permission ->
                                        let
                                            pending : List Permission
                                            pending =
                                                edit.pending ++ [ permission ]
                                        in
                                        { edit | pending = pending, addSelection = resolveAddSelection Nothing pending }

                                    Nothing ->
                                        edit
                            )
              }
            , Effect.none
            )

        PermissionsCancelClicked ->
            ( { model | permissionsEdit = Nothing }, Effect.none )

        PermissionsSaveClicked ->
            case ( model.resolver.status, model.permissionsEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | permissionsEdit = Just { edit | status = Submitting } }
                    , Users.updateUser shared.accounts ( Just account.userId, server.frontendHost ) user.id (\freshUser -> { freshUser | permissions = edit.pending })
                        |> Task.attempt GotPermissionsSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPermissionsSaveResult (Ok ( maybeAccountsPanelMsg, updatedUser )) ->
            ( { model | resolver = withResolvedUser updatedUser model.resolver, permissionsEdit = Nothing }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotPermissionsSaveResult (Err err) ->
            ( { model
                | permissionsEdit =
                    model.permissionsEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        FederatedProfilesEditClicked ->
            ( { model
                | federatedProfilesEdit =
                    Just { addSelection = resolveFederatedAddSelection Nothing (federableAccountsFor shared model), status = Idle }
              }
            , Effect.none
            )

        FederatedProfilesDoneClicked ->
            ( { model | federatedProfilesEdit = Nothing }, Effect.none )

        FederatedProfileAddSelectionChanged key ->
            ( { model
                | federatedProfilesEdit =
                    model.federatedProfilesEdit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | addSelection =
                                        federableAccountsFor shared model
                                            |> List.filter (\account -> accountKey account == key)
                                            |> List.head
                                }
                            )
              }
            , Effect.none
            )

        FederatedProfileAddClicked ->
            case ( model.federatedProfilesEdit, serverAndAccount shared model ) of
                ( Just edit, Just ( server, account ) ) ->
                    case edit.addSelection of
                        Just selected ->
                            ( { model | federatedProfilesEdit = Just { edit | status = Submitting } }
                            , Users.federateProfile shared.accounts ( Just account.userId, server.frontendHost ) { host = selected.server, userId = selected.userId }
                                |> Task.attempt GotFederatedProfileAddResult
                                |> Effect.fromCmd
                            )

                        Nothing ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotFederatedProfileAddResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                clearedModel : Model
                clearedModel =
                    { model
                        | federatedProfilesEdit =
                            model.federatedProfilesEdit
                                |> Maybe.map (\edit -> { edit | status = Idle, addSelection = resolveFederatedAddSelection Nothing (federableAccountsFor shared model) })
                    }

                ( refetchedModel, refetchEffect ) =
                    refetch shared clearedModel
            in
            ( refetchedModel
            , Effect.batch
                [ accountsPanelEffect maybeAccountsPanelMsg
                , refetchEffect
                ]
            )

        GotFederatedProfileAddResult (Err err) ->
            ( { model
                | federatedProfilesEdit =
                    model.federatedProfilesEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        FederatedProfileRemoveClicked account ->
            case ( model.federatedProfilesEdit, serverAndAccount shared model ) of
                ( Just edit, Just ( server, signedInAccount ) ) ->
                    ( { model | federatedProfilesEdit = Just { edit | status = Submitting } }
                    , Users.defederateProfile shared.accounts ( Just signedInAccount.userId, server.frontendHost ) account
                        |> Task.attempt GotFederatedProfileRemoveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFederatedProfileRemoveResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                clearedModel : Model
                clearedModel =
                    { model
                        | federatedProfilesEdit =
                            model.federatedProfilesEdit
                                |> Maybe.map (\edit -> { edit | status = Idle, addSelection = resolveFederatedAddSelection edit.addSelection (federableAccountsFor shared model) })
                    }

                ( refetchedModel, refetchEffect ) =
                    refetch shared clearedModel
            in
            ( refetchedModel
            , Effect.batch
                [ accountsPanelEffect maybeAccountsPanelMsg
                , refetchEffect
                ]
            )

        GotFederatedProfileRemoveResult (Err err) ->
            ( { model
                | federatedProfilesEdit =
                    model.federatedProfilesEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        FollowStatusAndButtonMsg subMsg ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    let
                        ( newFollowStatusAndButton, followEffect ) =
                            FollowStatusAndButton.update shared server account user subMsg model.followStatusAndButton

                        newModel : Model
                        newModel =
                            { model | followStatusAndButton = newFollowStatusAndButton }

                        mappedFollowEffect : Effect Msg
                        mappedFollowEffect =
                            Effect.map FollowStatusAndButtonMsg followEffect
                    in
                    case subMsg of
                        FollowStatusAndButton.GotFollowResult (Ok _) ->
                            refetch shared newModel |> Tuple.mapSecond (\effect -> Effect.batch [ mappedFollowEffect, effect ])

                        FollowStatusAndButton.GotUnfollowResult (Ok _) ->
                            refetch shared newModel |> Tuple.mapSecond (\effect -> Effect.batch [ mappedFollowEffect, effect ])

                        FollowStatusAndButton.GotModerationResult (Ok _) ->
                            refetch shared newModel |> Tuple.mapSecond (\effect -> Effect.batch [ mappedFollowEffect, effect ])

                        _ ->
                            ( newModel, mappedFollowEffect )

                _ ->
                    ( model, Effect.none )

        SyncSourceRowUrlChanged source url ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources

                edit : EventSyncRowEdit
                edit =
                    eventSyncRowEditFor source es
            in
            ( { model | syncSources = { es | rowEdits = Dict.insert source.id { edit | pendingUrl = url } es.rowEdits } }, Effect.none )

        SyncSourceRowIntervalChanged source seconds ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources

                edit : EventSyncRowEdit
                edit =
                    eventSyncRowEditFor source es
            in
            ( { model | syncSources = { es | rowEdits = Dict.insert source.id { edit | pendingIntervalSeconds = seconds } es.rowEdits } }, Effect.none )

        SyncSourceRowSaveClicked source ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources

                edit : EventSyncRowEdit
                edit =
                    eventSyncRowEditFor source es

                updated : SyncSource
                updated =
                    { source
                        | configuration = Just (configurationForKindOf source.configuration Ics edit.pendingUrl)
                        , syncIntervalSeconds = Conversions.int64FromInt edit.pendingIntervalSeconds
                    }
            in
            ( { model | syncSources = { es | rowEdits = Dict.insert source.id { edit | status = Submitting } es.rowEdits } }
            , performForOwner shared model (\accountServer -> SyncSources.updateSyncSource shared.accounts accountServer updated)
                |> Task.attempt (GotSyncSourceRowSaveResult source.id)
                |> Effect.fromCmd
            )

        SyncSourceRowRefreshClicked source ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources
            in
            ( { model
                | syncSources =
                    { es
                        | rowEdits =
                            Dict.insert source.id
                                { pendingUrl = eventSyncUrl source, pendingIntervalSeconds = Conversions.int64ToInt source.syncIntervalSeconds, status = Submitting }
                                es.rowEdits
                    }
              }
            , performForOwner shared model (\accountServer -> SyncSources.updateSyncSource shared.accounts accountServer source)
                |> Task.attempt (GotSyncSourceRowSaveResult source.id)
                |> Effect.fromCmd
            )

        GotSyncSourceRowSaveResult id (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources

                savedModel : Model
                savedModel =
                    { model | syncSources = { es | rowEdits = Dict.remove id es.rowEdits } }

                ( eventsRefetchedModel, eventsRefetchEffect ) =
                    refetchEvents shared savedModel

                ( refetchedModel, refetchEffect ) =
                    refetch shared eventsRefetchedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, eventsRefetchEffect, refetchEffect ] )

        GotSyncSourceRowSaveResult id (Err err) ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources
            in
            ( { model | syncSources = { es | rowEdits = Dict.update id (Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })) es.rowEdits } }
            , Effect.none
            )

        SyncSourceAddUrlChanged url ->
            ( { model | syncSources = mapEventSyncAddForm (\f -> { f | url = url }) model.syncSources }, Effect.none )

        SyncSourceAddKindChanged kind ->
            ( { model | syncSources = mapEventSyncAddForm (\f -> { f | kind = kind }) model.syncSources }, Effect.none )

        SyncSourceAddIntervalChanged seconds ->
            ( { model | syncSources = mapEventSyncAddForm (\f -> { f | intervalSeconds = seconds }) model.syncSources }, Effect.none )

        SyncSourceAddClicked ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources

                maybeAccount : Maybe RellmAccount
                maybeAccount =
                    serverAndAccount shared model |> Maybe.map Tuple.second

                effectiveKind : SyncSourceKind
                effectiveKind =
                    effectiveSyncSourceAddKind (availableSyncSourceKinds maybeAccount) es.addForm.kind

                newSource : SyncSource
                newSource =
                    { defaultSyncSource
                        | configuration = Just (configurationForKindOf Nothing effectiveKind es.addForm.url)
                        , syncIntervalSeconds = Conversions.int64FromInt es.addForm.intervalSeconds
                    }
            in
            ( { model | syncSources = mapEventSyncAddForm (\f -> { f | status = Submitting }) es }
            , performForOwner shared model (\accountServer -> SyncSources.createSyncSource shared.accounts accountServer newSource)
                |> Task.attempt GotSyncSourceAddResult
                |> Effect.fromCmd
            )

        GotSyncSourceAddResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                addedModel : Model
                addedModel =
                    { model | syncSources = mapEventSyncAddForm (always defaultEventSyncAddForm) model.syncSources }

                ( refetchedModel, refetchEffect ) =
                    refetch shared addedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, refetchEffect ] )

        GotSyncSourceAddResult (Err err) ->
            ( { model | syncSources = mapEventSyncAddForm (\f -> { f | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }) model.syncSources }, Effect.none )

        -- Doesn't delete anything itself -- just opens the shared "are you
        -- sure?" dialog (`Shared.RequestDelete`), same as
        -- `AvatarEditClicked`/etc do for their own confirmations. The actual
        -- `DeleteSyncSource` call happens in `Shared.update`'s
        -- `ConfirmDelete` (see `Shared.ConfirmSyncSourceDelete`'s own
        -- doc for why this is fired from there rather than from a page-owned
        -- `Task`), whose result comes back here as
        -- `Shared.GotSyncSourceDeleteResult` (see `SharedMsg` above).
        SyncSourceDeleteClicked source deleteSyncedEvents ->
            ( model
            , Effect.fromShared (Shared.RequestDelete (Shared.ConfirmSyncSourceDelete source deleteSyncedEvents model.resolver.targetHost))
            )

        SyncSourcesExpandedToggled ->
            let
                expanded : Bool
                expanded =
                    not model.syncSourcesExpanded
            in
            case model.events of
                Just eventsModel ->
                    let
                        ( newEventsModel, eventsEffect ) =
                            EventsPage.update shared (EventsPage.showSyncSourcesChanged expanded) eventsModel
                    in
                    ( { model | syncSourcesExpanded = expanded, events = Just newEventsModel }
                    , Effect.map EventsMsg eventsEffect
                    )

                Nothing ->
                    ( { model | syncSourcesExpanded = expanded }, Effect.none )

        -- Manual refresh -- overlays just `syncSources` onto the resolved `User` (see
        -- `withResolvedUser`) rather than a whole-profile `refetch`, since that's all this
        -- section's data actually needs.
        SyncSourcesRefreshClicked ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    let
                        es : SyncSourcesState
                        es =
                            model.syncSources
                    in
                    ( { model | syncSources = { es | refreshStatus = Submitting } }
                    , SyncSources.getSyncSources shared.accounts ( Just account.userId, server.frontendHost ) user.id
                        |> Task.attempt GotSyncSourcesRefreshResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotSyncSourcesRefreshResult (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources

                refreshedModel : Model
                refreshedModel =
                    case model.resolver.status of
                        Resolver.Loaded user ->
                            { model | resolver = withResolvedUser { user | syncSources = response.sources } model.resolver }

                        _ ->
                            model
            in
            ( { refreshedModel | syncSources = { es | refreshStatus = Idle } }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotSyncSourcesRefreshResult (Err err) ->
            let
                es : SyncSourcesState
                es =
                    model.syncSources
            in
            ( { model | syncSources = { es | refreshStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) } }
            , Effect.none
            )

        SyncDestinationsExpandedToggled ->
            let
                expanded : Bool
                expanded =
                    not model.syncDestinationsExpanded

                ( eventsUpdatedModel, eventsEffect ) =
                    case model.events of
                        Just eventsModel ->
                            let
                                ( newEventsModel, effect ) =
                                    EventsPage.update shared (EventsPage.showSyncDestinationsChanged expanded) eventsModel
                            in
                            ( { model | syncDestinationsExpanded = expanded, events = Just newEventsModel }, effect )

                        Nothing ->
                            ( { model | syncDestinationsExpanded = expanded }, Effect.none )

                -- Same toggle also drives the embedded `PostsPage.Model`'s own
                -- `showSyncDestinations` -- mirrors the `model.events` handling just
                -- above exactly, since "Sync Destinations" now covers both Events and
                -- Posts (see `syncDestinationsSection`'s own doc).
                ( postsUpdatedModel, postsEffect ) =
                    case eventsUpdatedModel.posts of
                        Just postsModel ->
                            let
                                ( newPostsModel, effect ) =
                                    PostsPage.update shared (PostsPage.showSyncDestinationsChanged expanded) postsModel
                            in
                            ( { eventsUpdatedModel | posts = Just newPostsModel }, effect )

                        Nothing ->
                            ( eventsUpdatedModel, Effect.none )
            in
            ( postsUpdatedModel
            , Effect.batch [ Effect.map EventsMsg eventsEffect, Effect.map PostsMsg postsEffect ]
            )

        -- Opens the popup (see `Ports.facebookLoginPopup`'s own doc for why this happens
        -- synchronously here rather than after some other async step) -- the result arrives via
        -- `GotFacebookLoginResult`. Instagram reuses this exact same popup/"choose a Page" flow
        -- (see `FacebookConnectPlatform`'s own doc), just tagging which platform it's connecting
        -- for so `FacebookPageChosen` knows which `Configuration` variant to build.
        FacebookLoginClicked ->
            startFacebookLogin shared model ConnectFacebook

        InstagramLoginClicked ->
            startFacebookLogin shared model ConnectInstagram

        -- Guarded on `login` actually being `FacebookLoginPopupOpen` -- `Ports.facebookLoginResult`
        -- is one shared port subscribed to by both this Msg and `GotThreadsLoginResult` (see
        -- `Ports.facebookLoginPopup`'s own doc), so a result meant for the Threads flow arrives
        -- here too and must be ignored rather than misrouted into this state machine.
        GotFacebookLoginResult value ->
            case model.syncDestinations.login of
                FacebookLoginPopupOpen platform ->
                    case facebookLoginResultDecoder value of
                        Ok accessToken ->
                            ( setSyncDestinationsLogin (FacebookLoginFetchingPages platform accessToken) model
                            , fetchFacebookPages accessToken |> Effect.fromCmd
                            )

                        -- The user just closed the popup -- quietly go back to not-logged-in rather
                        -- than showing an "error" for a deliberate cancel (see
                        -- `Ports.facebookLoginResult`'s own doc).
                        Err "cancelled" ->
                            ( setSyncDestinationsLogin FacebookLoginNotStarted model, Effect.none )

                        Err message ->
                            ( setSyncDestinationsLogin (FacebookLoginFailed message) model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotFacebookPagesResult (Ok pages) ->
            case model.syncDestinations.login of
                FacebookLoginFetchingPages platform accessToken ->
                    ( setSyncDestinationsLogin
                        (if List.isEmpty pages then
                            FacebookLoginNoPagesFound

                         else
                            FacebookLoginChoosingPage platform accessToken pages
                        )
                        model
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        GotFacebookPagesResult (Err _) ->
            ( setSyncDestinationsLogin (FacebookLoginFailed "Couldn't load your Facebook Pages.") model, Effect.none )

        FacebookPageChosen page ->
            case model.syncDestinations.login of
                FacebookLoginChoosingPage platform accessToken _ ->
                    let
                        newDestination : SyncDestination
                        newDestination =
                            { defaultSyncDestination
                                | configuration =
                                    Just
                                        (case platform of
                                            ConnectFacebook ->
                                                DestinationConfiguration.FacebookPage
                                                    { pageId = page.id
                                                    , pageName = page.name
                                                    , shortLivedUserAccessToken = Just accessToken
                                                    }

                                            -- The empty-string fields are fine -- the server
                                            -- populates them (looking up the Page's linked
                                            -- Instagram Business account); this local value is
                                            -- only used to build the outgoing request, not
                                            -- rendered directly.
                                            ConnectInstagram ->
                                                DestinationConfiguration.InstagramAccount
                                                    { instagramBusinessAccountId = ""
                                                    , username = ""
                                                    , pageId = page.id
                                                    , shortLivedUserAccessToken = Just accessToken
                                                    }
                                        )
                            }
                    in
                    ( setSyncDestinationsLogin (FacebookLoginLinking platform page) model
                    , performForOwner shared model (\accountServer -> SyncDestinations.createSyncDestination shared.accounts accountServer newDestination)
                        |> Task.attempt GotFacebookLinkResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotFacebookLinkResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations

                loginResetModel : Model
                loginResetModel =
                    { model | syncDestinations = { ed | login = FacebookLoginNotStarted } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared loginResetModel
            in
            ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

        GotFacebookLinkResult (Err err) ->
            ( setSyncDestinationsLogin (FacebookLoginFailed (facebookLinkErrorMessage err)) model, Effect.none )

        MastodonConnectClicked ->
            ( setSyncDestinationsMastodon (MastodonConnectEditing { instanceHost = "", accessToken = "" }) model, Effect.none )

        MastodonInstanceHostChanged instanceHost ->
            ( updateMastodonEditing (\form -> { form | instanceHost = instanceHost }) model, Effect.none )

        MastodonAccessTokenChanged accessToken ->
            ( updateMastodonEditing (\form -> { form | accessToken = accessToken }) model, Effect.none )

        MastodonConnectCancelled ->
            ( setSyncDestinationsMastodon MastodonConnectNotStarted model, Effect.none )

        MastodonConnectSubmitted ->
            case model.syncDestinations.mastodon of
                MastodonConnectEditing form ->
                    let
                        newDestination : SyncDestination
                        newDestination =
                            { defaultSyncDestination
                                | configuration =
                                    Just
                                        (DestinationConfiguration.MastodonAccount
                                            { instanceHost = form.instanceHost
                                            , username = ""
                                            , accessToken = Just form.accessToken
                                            }
                                        )
                            }
                    in
                    ( setSyncDestinationsMastodon (MastodonConnectLinking form) model
                    , performForOwner shared model (\accountServer -> SyncDestinations.createSyncDestination shared.accounts accountServer newDestination)
                        |> Task.attempt GotMastodonLinkResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotMastodonLinkResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations

                mastodonResetModel : Model
                mastodonResetModel =
                    { model | syncDestinations = { ed | mastodon = MastodonConnectNotStarted } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared mastodonResetModel
            in
            ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

        GotMastodonLinkResult (Err err) ->
            ( setSyncDestinationsMastodon (MastodonConnectFailed (AccountsPanel.grpcErrorToString err)) model, Effect.none )

        BlueskyConnectClicked ->
            ( setSyncDestinationsBluesky (BlueskyConnectEditing { handle = "", appPassword = "" }) model, Effect.none )

        BlueskyHandleChanged handle ->
            ( updateBlueskyEditing (\form -> { form | handle = handle }) model, Effect.none )

        BlueskyAppPasswordChanged appPassword ->
            ( updateBlueskyEditing (\form -> { form | appPassword = appPassword }) model, Effect.none )

        BlueskyConnectCancelled ->
            ( setSyncDestinationsBluesky BlueskyConnectNotStarted model, Effect.none )

        BlueskyConnectSubmitted ->
            case model.syncDestinations.bluesky of
                BlueskyConnectEditing form ->
                    let
                        newDestination : SyncDestination
                        newDestination =
                            { defaultSyncDestination
                                | configuration =
                                    Just
                                        (DestinationConfiguration.BlueskyAccount
                                            { handle = form.handle
                                            , did = ""
                                            , appPassword = Just form.appPassword
                                            }
                                        )
                            }
                    in
                    ( setSyncDestinationsBluesky (BlueskyConnectLinking form) model
                    , performForOwner shared model (\accountServer -> SyncDestinations.createSyncDestination shared.accounts accountServer newDestination)
                        |> Task.attempt GotBlueskyLinkResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotBlueskyLinkResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations

                blueskyResetModel : Model
                blueskyResetModel =
                    { model | syncDestinations = { ed | bluesky = BlueskyConnectNotStarted } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared blueskyResetModel
            in
            ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

        GotBlueskyLinkResult (Err err) ->
            ( setSyncDestinationsBluesky (BlueskyConnectFailed (AccountsPanel.grpcErrorToString err)) model, Effect.none )

        -- Opens the Threads popup (see `Ports.facebookLoginPopup`'s own doc) -- Threads rides the
        -- same Meta App as Facebook/Instagram, so this reuses `facebookAppId` the same way
        -- `startFacebookLogin` does, just pointed at the `"threads"` provider and this flow's own
        -- simpler state machine (no page-picker, see `ThreadsConnectStatus`).
        ThreadsLoginClicked ->
            case facebookAppId shared model.resolver.targetHost of
                Just appId ->
                    ( setSyncDestinationsThreads ThreadsConnectPopupOpen model
                    , Ports.facebookLoginPopup { provider = "threads", appId = appId, instanceHost = "" } |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        -- Guarded on `threads` actually being `ThreadsConnectPopupOpen` -- see
        -- `GotFacebookLoginResult`'s own doc on why this shared port needs a guard on both sides.
        -- Unlike Facebook/Instagram, a successful result goes straight to building the create
        -- request -- there's no page-picker step to land on first.
        GotThreadsLoginResult value ->
            case model.syncDestinations.threads of
                ThreadsConnectPopupOpen ->
                    case facebookLoginResultDecoder value of
                        Ok code ->
                            let
                                newDestination : SyncDestination
                                newDestination =
                                    { defaultSyncDestination
                                        | configuration =
                                            Just
                                                -- The empty-string fields are fine -- the server
                                                -- populates them; this local value is only used to
                                                -- build the outgoing request, not rendered directly
                                                -- (mirrors how Instagram's create request is built).
                                                (DestinationConfiguration.ThreadsAccount
                                                    { threadsUserId = ""
                                                    , username = ""
                                                    , authorizationCode = Just code
                                                    }
                                                )
                                    }
                            in
                            ( setSyncDestinationsThreads ThreadsConnectLinking model
                            , performForOwner shared model (\accountServer -> SyncDestinations.createSyncDestination shared.accounts accountServer newDestination)
                                |> Task.attempt GotThreadsLinkResult
                                |> Effect.fromCmd
                            )

                        -- The user just closed the popup -- quietly go back to not-connected
                        -- rather than showing an "error" for a deliberate cancel (see
                        -- `Ports.facebookLoginResult`'s own doc).
                        Err "cancelled" ->
                            ( setSyncDestinationsThreads ThreadsConnectNotStarted model, Effect.none )

                        Err message ->
                            ( setSyncDestinationsThreads (ThreadsConnectFailed message) model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotThreadsLinkResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations

                threadsResetModel : Model
                threadsResetModel =
                    { model | syncDestinations = { ed | threads = ThreadsConnectNotStarted } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared threadsResetModel
            in
            ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

        GotThreadsLinkResult (Err err) ->
            ( setSyncDestinationsThreads (ThreadsConnectFailed (AccountsPanel.grpcErrorToString err)) model, Effect.none )

        -- Opens the X (Twitter) popup (see `Ports.facebookLoginPopup`'s own doc on the
        -- `"x_twitter"` provider) -- `xTwitterAppId` reads the admin-configured X Developer App's
        -- Client ID from `federationInfo.xTwitterAuthConfig`, a separate app from Facebook's (see
        -- `XTwitterConnectStatus`'s own doc on why the popup also has to hand back a PKCE
        -- `code_verifier`).
        XTwitterLoginClicked ->
            case xTwitterAppId shared model.resolver.targetHost of
                Just clientId ->
                    ( setSyncDestinationsXTwitter XTwitterConnectPopupOpen model
                    , Ports.facebookLoginPopup { provider = "x_twitter", appId = clientId, instanceHost = "" } |> Effect.fromCmd
                    )

                Nothing ->
                    ( model, Effect.none )

        -- Guarded on `xTwitter` actually being `XTwitterConnectPopupOpen` -- see
        -- `GotFacebookLoginResult`'s own doc on why this shared port needs a guard on both sides.
        GotXTwitterLoginResult value ->
            case model.syncDestinations.xTwitter of
                XTwitterConnectPopupOpen ->
                    case xTwitterLoginResultDecoder value of
                        Ok ( code, codeVerifier ) ->
                            let
                                newDestination : SyncDestination
                                newDestination =
                                    { defaultSyncDestination
                                        | configuration =
                                            Just
                                                -- The empty-string fields are fine -- the server
                                                -- populates them; this local value is only used to
                                                -- build the outgoing request, not rendered directly
                                                -- (mirrors how Threads' create request is built).
                                                (DestinationConfiguration.XTwitterAccount
                                                    { username = ""
                                                    , xUserId = ""
                                                    , authorizationCode = Just code
                                                    , codeVerifier = Just codeVerifier
                                                    }
                                                )
                                    }
                            in
                            ( setSyncDestinationsXTwitter XTwitterConnectLinking model
                            , performForOwner shared model (\accountServer -> SyncDestinations.createSyncDestination shared.accounts accountServer newDestination)
                                |> Task.attempt GotXTwitterLinkResult
                                |> Effect.fromCmd
                            )

                        -- The user just closed the popup -- quietly go back to not-connected
                        -- rather than showing an "error" for a deliberate cancel (see
                        -- `Ports.facebookLoginResult`'s own doc).
                        Err "cancelled" ->
                            ( setSyncDestinationsXTwitter XTwitterConnectNotStarted model, Effect.none )

                        Err message ->
                            ( setSyncDestinationsXTwitter (XTwitterConnectFailed message) model, Effect.none )

                _ ->
                    ( model, Effect.none )

        GotXTwitterLinkResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations

                xTwitterResetModel : Model
                xTwitterResetModel =
                    { model | syncDestinations = { ed | xTwitter = XTwitterConnectNotStarted } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared xTwitterResetModel
            in
            ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

        GotXTwitterLinkResult (Err err) ->
            ( setSyncDestinationsXTwitter (XTwitterConnectFailed (AccountsPanel.grpcErrorToString err)) model, Effect.none )

        -- Unlike `SyncSourceDeleteClicked`, this deletes immediately rather than opening
        -- the shared confirmation dialog -- see `SyncDestinationsState`'s own doc for why.
        SyncDestinationDeleteClicked destination ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations
            in
            ( { model | syncDestinations = { ed | deleteStatuses = Dict.insert destination.id Submitting ed.deleteStatuses } }
            , performForOwner shared model (\accountServer -> SyncDestinations.deleteSyncDestination shared.accounts accountServer destination)
                |> Task.attempt (GotSyncDestinationDeleteResult destination.id)
                |> Effect.fromCmd
            )

        GotSyncDestinationDeleteResult id (Ok ( maybeAccountsPanelMsg, () )) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations

                clearedModel : Model
                clearedModel =
                    { model | syncDestinations = { ed | deleteStatuses = Dict.remove id ed.deleteStatuses } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared clearedModel
            in
            ( refetchedModel, Effect.batch [ refetchEffect, accountsPanelEffect maybeAccountsPanelMsg ] )

        GotSyncDestinationDeleteResult id (Err err) ->
            let
                ed : SyncDestinationsState
                ed =
                    model.syncDestinations
            in
            ( { model | syncDestinations = { ed | deleteStatuses = Dict.insert id (SubmitFailed (AccountsPanel.grpcErrorToString err)) ed.deleteStatuses } }
            , Effect.none
            )

        AIProviderRowNameChanged provider name ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                edit : AIProviderRowEdit
                edit =
                    aiProviderRowEditFor provider ap
            in
            ( { model | aiProviders = { ap | rowEdits = Dict.insert provider.id { edit | pendingName = name } ap.rowEdits } }, Effect.none )

        AIProviderRowApiKeyChanged provider apiKey ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                edit : AIProviderRowEdit
                edit =
                    aiProviderRowEditFor provider ap
            in
            ( { model | aiProviders = { ap | rowEdits = Dict.insert provider.id { edit | pendingApiKey = apiKey } ap.rowEdits } }, Effect.none )

        AIProviderRowSaveClicked provider ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                edit : AIProviderRowEdit
                edit =
                    aiProviderRowEditFor provider ap

                -- A blank `pendingApiKey` leaves `provider` unset on the request entirely, which
                -- the backend reads as "keep the stored credentials" (see
                -- `update_ai_provider.rs`'s `if let Some(provider) = &request.provider`
                -- gate) -- the same convention `AIProviderRowEdit`'s own doc explains. A
                -- non-blank key rotates *this* provider's own existing credentials variant (see
                -- `provider.provider`'s own pattern match below) -- never forces it back to Gemini,
                -- so rotating an OpenAI provider's key doesn't silently reconfigure it as one.
                updated : AIProvider
                updated =
                    { provider
                        | name = edit.pendingName
                        , provider =
                            if String.isEmpty (String.trim edit.pendingApiKey) then
                                Nothing

                            else
                                case provider.provider of
                                    Just (AIProviderProvider.OpenaiCredentials _) ->
                                        Just (AIProviderProvider.OpenaiCredentials { defaultOpenAICredentials | openaiApiKey = Just edit.pendingApiKey })

                                    Just (AIProviderProvider.DigitaloceanCredentials _) ->
                                        Just (AIProviderProvider.DigitaloceanCredentials { defaultDigitalOceanCredentials | digitaloceanApiKey = Just edit.pendingApiKey })

                                    _ ->
                                        Just (AIProviderProvider.GeminiCredentials { defaultGeminiCredentials | geminiApiKey = Just edit.pendingApiKey })
                    }
            in
            ( { model | aiProviders = { ap | rowEdits = Dict.insert provider.id { edit | status = Submitting } ap.rowEdits } }
            , performForOwner shared model (\accountServer -> AIProviders.updateAIProvider shared.accounts accountServer updated)
                |> Task.attempt (GotAIProviderRowSaveResult provider.id)
                |> Effect.fromCmd
            )

        AIProviderRowCancelClicked provider ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders
            in
            ( { model | aiProviders = { ap | rowEdits = Dict.remove provider.id ap.rowEdits } }, Effect.none )

        GotAIProviderRowSaveResult id (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                savedModel : Model
                savedModel =
                    { model | aiProviders = { ap | rowEdits = Dict.remove id ap.rowEdits } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared savedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, refetchEffect ] )

        GotAIProviderRowSaveResult id (Err err) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders
            in
            ( { model | aiProviders = { ap | rowEdits = Dict.update id (Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })) ap.rowEdits } }
            , Effect.none
            )

        AIProviderAddProviderTypeChanged typeString ->
            let
                providerType : AddAIProviderType
                providerType =
                    if typeString == "openai" then
                        AddOpenAIProvider

                    else if typeString == "digitalocean" then
                        AddDigitalOceanProvider

                    else
                        AddGeminiProvider
            in
            ( { model | aiProviders = mapAIProviderAddForm (\f -> { f | providerType = providerType }) model.aiProviders }, Effect.none )

        AIProviderAddNameChanged name ->
            ( { model | aiProviders = mapAIProviderAddForm (\f -> { f | name = name }) model.aiProviders }, Effect.none )

        AIProviderAddApiKeyChanged apiKey ->
            ( { model | aiProviders = mapAIProviderAddForm (\f -> { f | apiKey = apiKey }) model.aiProviders }, Effect.none )

        AIProviderAddClicked ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                newProvider : AIProvider
                newProvider =
                    { defaultAIProvider
                        | name = ap.addForm.name
                        , provider =
                            case ap.addForm.providerType of
                                AddGeminiProvider ->
                                    Just (AIProviderProvider.GeminiCredentials { defaultGeminiCredentials | geminiApiKey = Just ap.addForm.apiKey })

                                AddOpenAIProvider ->
                                    Just (AIProviderProvider.OpenaiCredentials { defaultOpenAICredentials | openaiApiKey = Just ap.addForm.apiKey })

                                AddDigitalOceanProvider ->
                                    Just (AIProviderProvider.DigitaloceanCredentials { defaultDigitalOceanCredentials | digitaloceanApiKey = Just ap.addForm.apiKey })
                    }
            in
            ( { model | aiProviders = mapAIProviderAddForm (\f -> { f | status = Submitting }) ap }
            , performForOwner shared model (\accountServer -> AIProviders.createAIProvider shared.accounts accountServer newProvider)
                |> Task.attempt GotAIProviderAddResult
                |> Effect.fromCmd
            )

        GotAIProviderAddResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                addedModel : Model
                addedModel =
                    { model | aiProviders = mapAIProviderAddForm (always defaultAIProviderAddForm) model.aiProviders }

                ( refetchedModel, refetchEffect ) =
                    refetch shared addedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, refetchEffect ] )

        GotAIProviderAddResult (Err err) ->
            ( { model | aiProviders = mapAIProviderAddForm (\f -> { f | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }) model.aiProviders }, Effect.none )

        -- Deletes immediately, same as `SyncDestinationDeleteClicked` -- see
        -- `AIProvidersState`'s own doc for why this skips the shared confirmation dialog.
        AIProviderDeleteClicked provider ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders
            in
            ( { model | aiProviders = { ap | deleteStatuses = Dict.insert provider.id Submitting ap.deleteStatuses } }
            , performForOwner shared model (\accountServer -> AIProviders.deleteAIProvider shared.accounts accountServer provider)
                |> Task.attempt (GotAIProviderDeleteResult provider.id)
                |> Effect.fromCmd
            )

        GotAIProviderDeleteResult id (Ok ( maybeAccountsPanelMsg, () )) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                clearedModel : Model
                clearedModel =
                    { model | aiProviders = { ap | deleteStatuses = Dict.remove id ap.deleteStatuses } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared clearedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, refetchEffect ] )

        GotAIProviderDeleteResult id (Err err) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders
            in
            ( { model | aiProviders = { ap | deleteStatuses = Dict.insert id (SubmitFailed (AccountsPanel.grpcErrorToString err)) ap.deleteStatuses } }
            , Effect.none
            )

        AIProvidersExpandedToggled ->
            ( { model | aiProvidersExpanded = not model.aiProvidersExpanded }, Effect.none )

        -- Manual refresh -- overlays just `aiModels` onto the resolved `User` (see
        -- `withResolvedUser`, and `SyncSourcesRefreshClicked`'s identical shape) rather than a
        -- whole-profile `refetch`. `response.providers` is a convenience duplicate of data already
        -- in `response.aiModels` (see `GetAIProvidersResponse`'s own proto doc) --
        -- `ownedAIProviders` re-derives it from `user.aiModels` the same way it
        -- always does, so there's nothing else to overlay here.
        AIProvidersRefreshClicked ->
            case ( model.resolver.status, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just ( server, account ) ) ->
                    let
                        ap : AIProvidersState
                        ap =
                            model.aiProviders
                    in
                    ( { model | aiProviders = { ap | refreshStatus = Submitting } }
                    , AIProviders.getAIProviders shared.accounts ( Just account.userId, server.frontendHost ) user.id
                        |> Task.attempt GotAIProvidersRefreshResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotAIProvidersRefreshResult (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                refreshedModel : Model
                refreshedModel =
                    case model.resolver.status of
                        Resolver.Loaded user ->
                            { model | resolver = withResolvedUser { user | aiModels = response.aiModels } model.resolver }

                        _ ->
                            model
            in
            ( { refreshedModel | aiProviders = { ap | refreshStatus = Idle } }
            , accountsPanelEffect maybeAccountsPanelMsg
            )

        GotAIProvidersRefreshResult (Err err) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders
            in
            ( { model | aiProviders = { ap | refreshStatus = SubmitFailed (AccountsPanel.grpcErrorToString err) } }
            , Effect.none
            )

        AIProviderGrantsSectionToggled ->
            ( { model | aiProviderGrantsExpanded = not model.aiProviderGrantsExpanded }, Effect.none )

        AIProviderGrantsToggled providerId ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                expanded : List String
                expanded =
                    if List.member providerId ap.expandedGrants then
                        List.filter ((/=) providerId) ap.expandedGrants

                    else
                        providerId :: ap.expandedGrants
            in
            ( { model | aiProviders = { ap | expandedGrants = expanded } }, Effect.none )

        AIProviderGrantUserIdChanged providerId userId ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                form : AIProviderGrantForm
                form =
                    aiProviderGrantFormFor providerId ap
            in
            ( { model | aiProviders = { ap | grantForms = Dict.insert providerId { form | userId = userId } ap.grantForms } }, Effect.none )

        AIProviderGrantTokensChanged providerId tokens ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                form : AIProviderGrantForm
                form =
                    aiProviderGrantFormFor providerId ap
            in
            ( { model | aiProviders = { ap | grantForms = Dict.insert providerId { form | tokens = tokens } ap.grantForms } }, Effect.none )

        AIProviderGrantModelNamesChanged providerId modelNames ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                form : AIProviderGrantForm
                form =
                    aiProviderGrantFormFor providerId ap
            in
            ( { model | aiProviders = { ap | grantForms = Dict.insert providerId { form | modelNames = modelNames } ap.grantForms } }, Effect.none )

        -- Pre-fills the provider's grant form with `grant`'s own current values (rather than a
        -- blank "add a new grant" form) -- submitting it (`AIProviderGrantClicked`) then just
        -- re-grants the same user, which upserts in place (see `GrantAIProviderRequest`'s own
        -- doc: same `(ai_provider_id, user_id)` pair replaces, not adds to, the existing grant).
        AIProviderGrantEditClicked provider grant ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                granteeId : String
                granteeId =
                    grant.aiModelGrantee |> Maybe.map .userId |> Maybe.withDefault ""

                form : AIProviderGrantForm
                form =
                    { userId = granteeId
                    , tokens = String.fromInt (Conversions.int64ToInt grant.tokensRemaining)
                    , modelNames = String.join ", " grant.modelNames
                    , status = Idle
                    }
            in
            ( { model | aiProviders = { ap | grantForms = Dict.insert provider.id form ap.grantForms } }, Effect.none )

        AIProviderGrantClicked provider ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                form : AIProviderGrantForm
                form =
                    aiProviderGrantFormFor provider.id ap

                request : Proto.Rellm.GrantAIProviderRequest
                request =
                    { userId = form.userId
                    , aiProviderId = provider.id
                    , tokens = Conversions.int64FromInt (String.toInt form.tokens |> Maybe.withDefault 0)
                    , modelNames = parseModelNames form.modelNames
                    }
            in
            ( { model | aiProviders = { ap | grantForms = Dict.insert provider.id { form | status = Submitting } ap.grantForms } }
            , performForOwner shared model (\accountServer -> AIProviders.grantAIProvider shared.accounts accountServer request)
                |> Task.attempt (GotAIProviderGrantResult provider.id)
                |> Effect.fromCmd
            )

        GotAIProviderGrantResult providerId (Ok ( maybeAccountsPanelMsg, _ )) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                grantedModel : Model
                grantedModel =
                    { model | aiProviders = { ap | grantForms = Dict.remove providerId ap.grantForms } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared grantedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, refetchEffect ] )

        GotAIProviderGrantResult providerId (Err err) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                form : AIProviderGrantForm
                form =
                    aiProviderGrantFormFor providerId ap
            in
            ( { model | aiProviders = { ap | grantForms = Dict.insert providerId { form | status = SubmitFailed (AccountsPanel.grpcErrorToString err) } ap.grantForms } }
            , Effect.none
            )

        AIProviderRevokeClicked provider grant ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                granteeId : String
                granteeId =
                    grant.aiModelGrantee |> Maybe.map .userId |> Maybe.withDefault ""

                key : String
                key =
                    aiProviderGrantKey provider.id granteeId

                request : Proto.Rellm.RevokeAIProviderRequest
                request =
                    { userId = granteeId, aiProviderId = provider.id }
            in
            ( { model | aiProviders = { ap | revokeStatuses = Dict.insert key Submitting ap.revokeStatuses } }
            , performForOwner shared model (\accountServer -> AIProviders.revokeAIProvider shared.accounts accountServer request)
                |> Task.attempt (GotAIProviderRevokeResult key)
                |> Effect.fromCmd
            )

        GotAIProviderRevokeResult key (Ok ( maybeAccountsPanelMsg, () )) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders

                revokedModel : Model
                revokedModel =
                    { model | aiProviders = { ap | revokeStatuses = Dict.remove key ap.revokeStatuses } }

                ( refetchedModel, refetchEffect ) =
                    refetch shared revokedModel
            in
            ( refetchedModel, Effect.batch [ accountsPanelEffect maybeAccountsPanelMsg, refetchEffect ] )

        GotAIProviderRevokeResult key (Err err) ->
            let
                ap : AIProvidersState
                ap =
                    model.aiProviders
            in
            ( { model | aiProviders = { ap | revokeStatuses = Dict.insert key (SubmitFailed (AccountsPanel.grpcErrorToString err)) ap.revokeStatuses } }
            , Effect.none
            )

        PasswordResetEditClicked ->
            ( { model | passwordResetEdit = Just { input = "", status = Idle } }, Effect.none )

        PasswordResetInputChanged input ->
            ( { model | passwordResetEdit = model.passwordResetEdit |> Maybe.map (\edit -> { edit | input = input }) }
            , Effect.none
            )

        PasswordResetCancelClicked ->
            ( { model | passwordResetEdit = Nothing }, Effect.none )

        PasswordResetSaveClicked ->
            case ( model.resolver.status, model.passwordResetEdit, serverAndAccount shared model ) of
                ( Resolver.Loaded user, Just edit, Just ( server, account ) ) ->
                    ( { model | passwordResetEdit = Just { edit | status = Submitting } }
                    , Users.resetPassword shared.accounts ( Just account.userId, server.frontendHost ) user edit.input
                        |> Task.attempt GotPasswordResetSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotPasswordResetSaveResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            ( { model | passwordResetEdit = Nothing }, accountsPanelEffect maybeAccountsPanelMsg )

        GotPasswordResetSaveResult (Err err) ->
            ( { model
                | passwordResetEdit =
                    model.passwordResetEdit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) })
              }
            , Effect.none
            )

        -- Same shape as `SyncSourceDeleteClicked`: just opens the
        -- shared "are you sure?" dialog -- the actual `DeleteUser` call
        -- happens in `Shared.update`'s `ConfirmDelete` (see
        -- `Shared.ConfirmUserDelete`'s own doc), whose result comes back
        -- here as `Shared.GotUserDeleteResult` (see `SharedMsg` above).
        DeleteUserClicked ->
            case model.resolver.status of
                Resolver.Loaded user ->
                    ( model
                    , Effect.fromShared (Shared.RequestDelete (Shared.ConfirmUserDelete user model.resolver.targetHost))
                    )

                _ ->
                    ( model, Effect.none )

        -- Discards the `Dom.setViewport` result either way (see
        -- `scrollToProfileSectionCmd`) -- a missing/not-yet-rendered target (the
        -- viewer can't actually see the section at all, e.g. an Admin's own
        -- `#ai-providers` link to a non-owner's profile) just leaves the page
        -- wherever it already was, same "harmless no-op" convention as
        -- `MessagesPage.ScrollAttempted`.
        ScrollToProfileSectionAttempted ->
            ( model, Effect.none )

        GotFederatedServer account (Ok server) ->
            -- Registers the federated user's server into `shared.accounts.servers`
            -- (same as `ConnectClicked`'s own `GotConnectResult` does for
            -- `targetHost`) -- needed so `UI.EmittedStylesheet` actually emits
            -- this host's `background-color-primary` rule for `federatedProfileLink`.
            ( model
            , Effect.batch
                [ Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ServerConnected server))
                , fetchFederatedUserEffect shared account
                ]
            )

        GotFederatedServer account (Err _) ->
            ( { model | federatedProfiles = Dict.insert (federatedKey account) FederatedProfileFailed model.federatedProfiles }
            , Effect.none
            )

        GotFederatedUser key (Ok ( maybeAccountsPanelMsg, response )) ->
            let
                accountEffect : Effect Msg
                accountEffect =
                    accountsPanelEffect maybeAccountsPanelMsg

                newStatus : FederatedProfileStatus
                newStatus =
                    response.users
                        |> List.head
                        |> Maybe.map FederatedProfileLoaded
                        |> Maybe.withDefault FederatedProfileFailed
            in
            ( { model | federatedProfiles = Dict.insert key newStatus model.federatedProfiles }, accountEffect )

        GotFederatedUser key (Err _) ->
            ( { model | federatedProfiles = Dict.insert key FederatedProfileFailed model.federatedProfiles }
            , Effect.none
            )


{-| The connected `Server`/signed-in `Account` for `model.resolver.targetHost`, if
both exist -- what `RealNameSaveClicked`/`PermissionsSaveClicked` need to
actually submit their `Users.updateUser` task.
-}
serverAndAccount : Shared.Model -> Model -> Maybe ( RellmServer, RellmAccount )
serverAndAccount shared model =
    Maybe.map2 Tuple.pair
        (RellmServers.rellmServerForHost shared.accounts.servers model.resolver.targetHost)
        (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.resolver.targetHost)


{-| Starts a `PermissionsEdit` off `currentPermissions` (the user's own, as
loaded) -- `addSelection` defaults to the first grantable permission not
already in that list, same as `resolveAddSelection` picks after every
add/remove.
-}
newPermissionsEdit : List Permission -> PermissionsEdit
newPermissionsEdit currentPermissions =
    { pending = currentPermissions
    , addSelection = resolveAddSelection Nothing currentPermissions
    , status = Idle
    }


{-| Keeps the "Add Permission" `<select>`'s selection valid as `pending`
changes: keeps `current` if it's still addable (not already in `pending`),
otherwise falls back to the first still-addable permission (`Nothing` if
every permission's already been added).
-}
resolveAddSelection : Maybe Permission -> List Permission -> Maybe Permission
resolveAddSelection current pending =
    let
        available : List Permission
        available =
            addablePermissions pending
    in
    case current of
        Just permission ->
            if List.member permission available then
                Just permission

            else
                List.head available

        Nothing ->
            List.head available


addablePermissions : List Permission -> List Permission
addablePermissions pending =
    Users.allPermissions |> List.filter (\permission -> not (List.member permission pending))


{-| Whether the currently signed-in account on `user`'s own server (`maybeAccount`)
_is_ `user` -- unlike `canEditProfile`, admins don't get a pass here, since
`FederateProfile`/`DefederateProfile` (see `Components.Users.federateProfile`/
`defederateProfile`) always act on whichever account's auth token made the
call, not any user id in the request (see
`backend/src/rpcs/federation/federate_profile.rs`) -- an admin editing this
list would only ever federate _their own_ profile, not `user`'s.
-}
isOwnProfile : Maybe RellmAccount -> User -> Bool
isOwnProfile maybeAccount user =
    case maybeAccount of
        Just account ->
            account.userId == user.id

        Nothing ->
            False


{-| The signed-in `RellmAccount`s (across every connected server,
see `Shared.AccountsPanel.Model.accounts`) that `user` could still federate
with: not `user`'s own account on `server` (that'd be federating with itself),
and not already listed in `user.federatedProfiles` -- mirrors the Tamagui
app's `federableAccounts` computation in
`frontends/tamagui/packages/app/features/user/federated_profiles.tsx`.
-}
federableAccounts : Shared.Model -> RellmServer -> User -> List RellmAccount
federableAccounts shared server user =
    shared.accounts.accounts
        |> List.filter
            (\account ->
                not (account.userId == user.id && account.server == server.frontendHost)
                    && not (List.any (\profile -> profile.host == account.server && profile.userId == account.userId) user.federatedProfiles)
            )


{-| `federableAccounts`, pulling `user`/`server` out of `model` itself --
what the update branches (which don't have a `User`/`Server` in hand directly)
need.
-}
federableAccountsFor : Shared.Model -> Model -> List RellmAccount
federableAccountsFor shared model =
    case ( model.resolver.status, serverAndAccount shared model ) of
        ( Resolver.Loaded user, Just ( server, _ ) ) ->
            federableAccounts shared server user

        _ ->
            []


{-| Keeps the "Link Account" `<select>`'s selection valid as the federated
profiles list changes: keeps `current` if it's still federable, otherwise
falls back to the first still-federable account (`Nothing` if there aren't
any) -- mirrors `resolveAddSelection`.
-}
resolveFederatedAddSelection : Maybe RellmAccount -> List RellmAccount -> Maybe RellmAccount
resolveFederatedAddSelection current available =
    case current of
        Just account ->
            if List.member account available then
                Just account

            else
                List.head available

        Nothing ->
            List.head available


{-| The `<select>` option value (and its reverse-lookup key, see
`FederatedProfileAddSelectionChanged`) for one federable `RellmAccount`
-- same `userId@host` shape as `federatedKey`, just over the other record type.
-}
accountKey : RellmAccount -> String
accountKey account =
    account.userId ++ "@" ++ account.server


{-| The "Link Account" `<select>`'s display label for one federable
`RellmAccount` -- unlike `accountKey`, leads with the human-readable
`username`, with the `userId` parenthesized for disambiguation (two accounts
on the same server could theoretically share nothing else at a glance).
-}
accountLabel : RellmAccount -> String
accountLabel account =
    account.username ++ "@" ++ account.server ++ " (" ++ account.userId ++ ")"


{-| Kicks off a fetch for every entry in `user.federatedProfiles` that isn't
already loading/loaded/failed -- grouping isn't needed the way
`Shared.StarredPanel.kickOffFetches` groups by host, since a `User`
rarely lists more than a couple of federated accounts, and each is on its own
(likely not-yet-connected) server anyway.
-}
kickOffFederatedFetches : Shared.Model -> User -> Model -> ( Model, Effect Msg )
kickOffFederatedFetches shared user model =
    let
        pending : List FederatedAccount
        pending =
            user.federatedProfiles
                |> List.filter (\account -> not (Dict.member (federatedKey account) model.federatedProfiles))

        ( newFederatedProfiles, effects ) =
            List.foldl (fetchFederated shared model.pageIsSecure) ( model.federatedProfiles, [] ) pending
    in
    ( { model | federatedProfiles = newFederatedProfiles }, Effect.batch effects )


{-| Either fetches `account`'s `User` directly (its server is already known --
see `RellmServers.rellmServerForHost`) or first connects to that server anonymously
(mirrors `ConnectClicked`/`GotConnectResult` above), deferring the actual
`User` fetch to `GotFederatedServer`'s success branch.
-}
fetchFederated :
    Shared.Model
    -> Bool
    -> FederatedAccount
    -> ( Dict String FederatedProfileStatus, List (Effect Msg) )
    -> ( Dict String FederatedProfileStatus, List (Effect Msg) )
fetchFederated shared pageIsSecure account ( statuses, effects ) =
    let
        newStatuses : Dict String FederatedProfileStatus
        newStatuses =
            Dict.insert (federatedKey account) FederatedProfileLoading statuses
    in
    case RellmServers.rellmServerForHost shared.accounts.servers account.host of
        Just _ ->
            ( newStatuses, effects ++ [ fetchFederatedUserEffect shared account ] )

        Nothing ->
            ( newStatuses
            , effects
                ++ [ RellmServers.connectToRellmServer pageIsSecure account.host
                        |> Task.attempt (GotFederatedServer account)
                        |> Effect.fromCmd
                   ]
            )


fetchFederatedUserEffect : Shared.Model -> FederatedAccount -> Effect Msg
fetchFederatedUserEffect shared account =
    Users.fetchUserById
        shared.accounts
        ( RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts account.host |> Maybe.map .userId
        , account.host
        )
        account.userId
        |> Task.attempt (GotFederatedUser (federatedKey account))
        |> Effect.fromCmd


{-| The `model.federatedProfiles` key for one `User.federatedProfiles` entry --
mirrors `Shared.StarredPanel.starKey`.
-}
federatedKey : FederatedAccount -> String
federatedKey account =
    account.userId ++ "@" ++ account.host


{-| Re-fetches the user unconditionally -- called once the shared Markdown
panel (see `Shared.MarkdownPanel`) reports a successful bio save, mirroring
`Pages.Post.PostId_.refetch`.
-}
refetch : Shared.Model -> Model -> ( Model, Effect Msg )
refetch shared model =
    Resolver.refetch shared model.resolver
        |> Tuple.mapFirst (\newResolver -> { model | resolver = newResolver })
        |> Tuple.mapSecond (Effect.map ResolverMsg)


{-| Re-`init`s the embedded `EventsPage` copy against `model.resolver`'s
already-loaded user -- called after a successful Sync Source
sync/update/delete (see `GotSyncSourceRowSaveResult` and `SharedMsg`'s
`Shared.GotSyncSourceDeleteResult` case), since a source's sync can
create, update, or remove Events/Occasions that the already-`init`ed
`EventsPage.Model` has no way to know about on its own. Mirrors the
resolver-loaded `init` branch's own `EventsPage.init` call. A no-op if the
profile's own user hasn't loaded yet.
-}
refetchEvents : Shared.Model -> Model -> ( Model, Effect Msg )
refetchEvents shared model =
    case model.resolver.status of
        Resolver.Loaded user ->
            let
                ( eventsModel, eventsEffect ) =
                    EventsPage.init shared (Just ( model.resolver.targetHost, user )) model.navKey model.path model.query Nothing True False (Just user.syncDestinations) Nothing True
            in
            ( { model
                | events =
                    Just
                        { eventsModel
                            | showSyncSources = model.syncSourcesExpanded
                            , showSyncDestinations = model.syncDestinationsExpanded
                        }
              }
            , Effect.map EventsMsg eventsEffect
            )

        _ ->
            ( model, Effect.none )


setSyncDestinationsLogin : FacebookLoginStatus -> Model -> Model
setSyncDestinationsLogin login model =
    let
        ed : SyncDestinationsState
        ed =
            model.syncDestinations
    in
    { model | syncDestinations = { ed | login = login } }


setSyncDestinationsMastodon : MastodonConnectStatus -> Model -> Model
setSyncDestinationsMastodon mastodon model =
    let
        ed : SyncDestinationsState
        ed =
            model.syncDestinations
    in
    { model | syncDestinations = { ed | mastodon = mastodon } }


{-| Applies `f` to the in-progress Mastodon connect form's fields (a no-op if `mastodon` isn't
currently `MastodonConnectEditing`, e.g. a stray keystroke event after submit) -- used by
`MastodonInstanceHostChanged`/`MastodonAccessTokenChanged`.
-}
updateMastodonEditing : ({ instanceHost : String, accessToken : String } -> { instanceHost : String, accessToken : String }) -> Model -> Model
updateMastodonEditing f model =
    case model.syncDestinations.mastodon of
        MastodonConnectEditing form ->
            setSyncDestinationsMastodon (MastodonConnectEditing (f form)) model

        _ ->
            model


setSyncDestinationsBluesky : BlueskyConnectStatus -> Model -> Model
setSyncDestinationsBluesky bluesky model =
    let
        ed : SyncDestinationsState
        ed =
            model.syncDestinations
    in
    { model | syncDestinations = { ed | bluesky = bluesky } }


{-| Applies `f` to the in-progress Bluesky connect form's fields -- mirrors
`updateMastodonEditing` exactly, see its own doc.
-}
updateBlueskyEditing : ({ handle : String, appPassword : String } -> { handle : String, appPassword : String }) -> Model -> Model
updateBlueskyEditing f model =
    case model.syncDestinations.bluesky of
        BlueskyConnectEditing form ->
            setSyncDestinationsBluesky (BlueskyConnectEditing (f form)) model

        _ ->
            model


setSyncDestinationsThreads : ThreadsConnectStatus -> Model -> Model
setSyncDestinationsThreads threads model =
    let
        ed : SyncDestinationsState
        ed =
            model.syncDestinations
    in
    { model | syncDestinations = { ed | threads = threads } }


setSyncDestinationsXTwitter : XTwitterConnectStatus -> Model -> Model
setSyncDestinationsXTwitter xTwitter model =
    let
        ed : SyncDestinationsState
        ed =
            model.syncDestinations
    in
    { model | syncDestinations = { ed | xTwitter = xTwitter } }


{-| Opens the Facebook/Instagram popup for `platform` (see `FacebookLoginClicked`'s own doc for
why this happens synchronously rather than after some other async step) -- shared by
`FacebookLoginClicked`/`InstagramLoginClicked`, which differ only in which platform they pass.
-}
startFacebookLogin : Shared.Model -> Model -> FacebookConnectPlatform -> ( Model, Effect Msg )
startFacebookLogin shared model platform =
    case facebookAppId shared model.resolver.targetHost of
        Just appId ->
            ( setSyncDestinationsLogin (FacebookLoginPopupOpen platform) model
            , Ports.facebookLoginPopup { provider = "facebook", appId = appId, instanceHost = "" } |> Effect.fromCmd
            )

        Nothing ->
            ( model, Effect.none )


{-| `GotFacebookLinkResult (Err err)`'s message, with one friendlier substitution: the server's
raw `instagram_no_linked_business_account` `FailedPrecondition` message (see
`logic::facebook_sync::get_linked_instagram_business_account` on the backend) becomes an
actionable sentence instead of a bare error code -- every other failure (including any other
Instagram/Facebook error) falls through to the same `AccountsPanel.grpcErrorToString` rendering
every other RPC failure in this file uses.
-}
facebookLinkErrorMessage : Grpc.Error -> String
facebookLinkErrorMessage err =
    let
        raw : String
        raw =
            AccountsPanel.grpcErrorToString err
    in
    if String.contains "instagram_no_linked_business_account" raw then
        "That Facebook Page doesn't have a linked Instagram Business account."

    else
        raw


{-| Whether the "Sync Destinations" section should be shown at all -- the viewer holding _any_ of
the 10 `SYNC_EVENTS_TO_*`/`SYNC_POSTS_TO_*` permission pairs (or `ADMIN`) is enough to show the
section (each platform's own button within it applies its own, more specific gate -- see
`hasSyncToFacebookPermission` and friends, plus `facebookAppConfigured` for Facebook/Instagram
specifically).
-}
canUseSyncDestinations : Maybe RellmAccount -> Bool
canUseSyncDestinations maybeAccount =
    hasSyncToFacebookPermission maybeAccount
        || hasSyncToInstagramPermission maybeAccount
        || hasSyncToMastodonPermission maybeAccount
        || hasSyncToBlueskyPermission maybeAccount
        || hasSyncToXTwitterPermission maybeAccount
        || hasSyncToThreadsPermission maybeAccount


{-| Whether `maybeAccount` holds either half of one platform's `SYNC_EVENTS_TO_*`/
`SYNC_POSTS_TO_*` permission pair (or `ADMIN`) -- a generic `SyncDestination` can serve either
content type, so either permission alone is enough to use that platform. Shared by
`hasSyncToFacebookPermission`/`hasSyncToInstagramPermission`/`hasSyncToMastodonPermission`/
`hasSyncToBlueskyPermission`/`hasSyncToXTwitterPermission`/`hasSyncToThreadsPermission` below, one
per platform.
-}
hasSyncPermissionPair : Permission -> Permission -> Maybe RellmAccount -> Bool
hasSyncPermissionPair eventsPermission postsPermission maybeAccount =
    maybeAccount
        |> Maybe.map
            (\account ->
                List.member eventsPermission account.permissions
                    || List.member postsPermission account.permissions
                    || List.member ADMIN account.permissions
            )
        |> Maybe.withDefault False


hasSyncToFacebookPermission : Maybe RellmAccount -> Bool
hasSyncToFacebookPermission =
    hasSyncPermissionPair SYNCEVENTSTOFACEBOOK SYNCPOSTSTOFACEBOOK


hasSyncToInstagramPermission : Maybe RellmAccount -> Bool
hasSyncToInstagramPermission =
    hasSyncPermissionPair SYNCEVENTSTOINSTAGRAM SYNCPOSTSTOINSTAGRAM


hasSyncToMastodonPermission : Maybe RellmAccount -> Bool
hasSyncToMastodonPermission =
    hasSyncPermissionPair SYNCEVENTSTOMASTODON SYNCPOSTSTOMASTODON


hasSyncToBlueskyPermission : Maybe RellmAccount -> Bool
hasSyncToBlueskyPermission =
    hasSyncPermissionPair SYNCEVENTSTOBLUESKY SYNCPOSTSTOBLUESKY


hasSyncToXTwitterPermission : Maybe RellmAccount -> Bool
hasSyncToXTwitterPermission =
    hasSyncPermissionPair SYNCEVENTSTOXTWITTER SYNCPOSTSTOXTWITTER


hasSyncToThreadsPermission : Maybe RellmAccount -> Bool
hasSyncToThreadsPermission =
    hasSyncPermissionPair SYNCEVENTSTOTHREADS SYNCPOSTSTOTHREADS


{-| Whether `host` has a Facebook App configured -- gates the Facebook _and_ Instagram buttons
specifically (both ride on the same Facebook App/popup, see `FacebookConnectPlatform`'s own doc),
not Mastodon/Bluesky, which need no server-side app config at all to be usable.
-}
facebookAppConfigured : Shared.Model -> String -> Bool
facebookAppConfigured shared host =
    facebookAppId shared host /= Nothing


{-| `host`'s configured Facebook App ID (`Just id`, non-empty), or `Nothing` if that server
hasn't set one up (`ConfigureServer`'s `federationInfo.facebookAuthConfig`, see
`Components.Pages.ServerInformationPage`'s Federation tab, where an admin sets this).
-}
facebookAppId : Shared.Model -> String -> Maybe String
facebookAppId shared host =
    RellmServers.rellmServerForHost shared.accounts.servers host
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .federationInfo
        |> Maybe.andThen .facebookAuthConfig
        |> Maybe.map .appId
        |> Maybe.andThen
            (\id ->
                if String.isEmpty id then
                    Nothing

                else
                    Just id
            )


{-| Whether `host` has an X Developer App configured -- mirrors `facebookAppConfigured` exactly,
gating the X (Twitter) button, against `federationInfo.xTwitterAuthConfig` instead (a separate app
from Facebook's -- X requires its own registered app, see `protos/federation.proto`'s doc on
`XTwitterAuthConfig`).
-}
xTwitterAppConfigured : Shared.Model -> String -> Bool
xTwitterAppConfigured shared host =
    xTwitterAppId shared host /= Nothing


{-| `host`'s configured X Developer App Client ID (`Just id`, non-empty), or `Nothing` if that
server hasn't set one up (`ConfigureServer`'s `federationInfo.xTwitterAuthConfig`, see
`Components.Pages.ServerInformationPage`'s Federation tab, where an admin sets this). Mirrors
`facebookAppId` exactly.
-}
xTwitterAppId : Shared.Model -> String -> Maybe String
xTwitterAppId shared host =
    RellmServers.rellmServerForHost shared.accounts.servers host
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .federationInfo
        |> Maybe.andThen .xTwitterAuthConfig
        |> Maybe.map .clientId
        |> Maybe.andThen
            (\id ->
                if String.isEmpty id then
                    Nothing

                else
                    Just id
            )


{-| Decodes a `facebookLoginResult` payload (`{ ok : Bool, value : String }`, see that port's own
doc) the same way `Shared.FederatedAuth.resultDecoder` does for its own `{ok, value}` ports --
`Ok accessToken` on success, `Err "cancelled"` or `Err message` otherwise.
-}
facebookLoginResultDecoder : Decode.Value -> Result String String
facebookLoginResultDecoder value =
    case
        Decode.decodeValue
            (Decode.map2 Tuple.pair (Decode.field "ok" Decode.bool) (Decode.field "value" Decode.string))
            value
    of
        Ok ( True, token ) ->
            Ok token

        Ok ( False, err ) ->
            Err err

        Err err ->
            Err (Decode.errorToString err)


{-| Decodes an X (Twitter) `facebookLoginResult` payload (`{ ok : Bool, value : String, codeVerifier
: String }` on success -- see `Ports.facebookLoginPopup`'s own doc on the `"x_twitter"` provider --
or plain `{ ok : False, value : String }` on failure/cancel, same as `facebookLoginResultDecoder`).
`Ok ( code, codeVerifier )` on success; `codeVerifier` missing despite `ok: True` is treated as a
decode failure (shouldn't happen -- the popup always attaches it alongside a successful `code`).
-}
xTwitterLoginResultDecoder : Decode.Value -> Result String ( String, String )
xTwitterLoginResultDecoder value =
    case
        Decode.decodeValue
            (Decode.map3 (\ok v codeVerifier -> ( ok, v, codeVerifier ))
                (Decode.field "ok" Decode.bool)
                (Decode.field "value" Decode.string)
                (Decode.maybe (Decode.field "codeVerifier" Decode.string))
            )
            value
    of
        Ok ( True, code, Just codeVerifier ) ->
            Ok ( code, codeVerifier )

        Ok ( True, _, Nothing ) ->
            Err "X login popup didn't return a PKCE code verifier."

        Ok ( False, err, _ ) ->
            Err err

        Err err ->
            Err (Decode.errorToString err)


{-| Lists the Facebook Pages the just-logged-in account manages, straight from the Graph API
(`GET /me/accounts`) -- a plain client-side HTTP call, not routed through the Rellm backend at
all, since it's Facebook's own API being asked "which Pages can this token manage," not anything
Rellm-specific. Only `id`/`name` are read out of each entry (see `FacebookPageOption`'s own doc
for why the per-page access token Facebook also returns here isn't used).
-}
fetchFacebookPages : String -> Cmd Msg
fetchFacebookPages accessToken =
    Http.get
        { url = "https://graph.facebook.com/v19.0/me/accounts?fields=id,name&access_token=" ++ Url.percentEncode accessToken
        , expect = Http.expectJson GotFacebookPagesResult facebookPagesDecoder
        }


facebookPagesDecoder : Decode.Decoder (List FacebookPageOption)
facebookPagesDecoder =
    Decode.field "data"
        (Decode.list
            (Decode.map2 FacebookPageOption
                (Decode.field "id" Decode.string)
                (Decode.field "name" Decode.string)
            )
        )


{-| The `SyncSourceRowSaveClicked`/`SyncSourceRowRefreshClicked`/
`SyncSourceAddClicked` requests' shared "who's acting" resolution --
mirrors the old `Shared.SyncSourcesPanel.performForOwner` exactly, just
reading `model.resolver.targetHost` (this page's own target server) instead
of a bare `targetHost` field. Its failure mode (not signed in on that server
anymore) has no dedicated `SubmitFailed` slot to land in from here, so it's
folded into a `Grpc.NetworkError` for the caller's own `Err` branch to
render via `AccountsPanel.grpcErrorToString`, same as any other failed RPC.
-}
performForOwner :
    Shared.Model
    -> Model
    -> (AccountsPanel.MaybeAccountServer -> Task.Task Grpc.Error a)
    -> Task.Task Grpc.Error a
performForOwner shared model req =
    case RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts model.resolver.targetHost of
        Just account ->
            req ( Just account.userId, model.resolver.targetHost )

        Nothing ->
            Task.fail Grpc.NetworkError


{-| Optimistically applies a just-saved `User` (as returned by
`Users.updateUser`) straight to `model.resolver.status`, without a round-trip
refetch -- used by `GotRealNameSaveResult`/`GotPermissionsSaveResult`.
-}
withResolvedUser : User -> Resolver.Model -> Resolver.Model
withResolvedUser user resolver =
    { resolver | status = Resolver.Loaded user }


{-| Merges a just-updated `phone` `ContactMethod` (as returned by
`Users.startContactMethodVerification`/`Users.verifyContactMethod`, which only ever echo back the
one `ContactMethod` they acted on, not a whole `User`) into `model.resolver`'s currently loaded
`User` -- mirrors `withResolvedUser`, but reads the rest of the `User` back off `resolver.status`
itself (a no-op if it's not `Loaded`, which shouldn't happen in practice since verification is only
reachable once a `User` is loaded) rather than replacing it wholesale.
-}
withResolvedUserPhone : ContactMethod -> Resolver.Model -> Resolver.Model
withResolvedUserPhone phone resolver =
    case resolver.status of
        Resolver.Loaded user ->
            { resolver | status = Resolver.Loaded { user | phone = Just phone } }

        _ ->
            resolver


{-| Merges a just-updated `MarketSubscription` (as returned by `Components.Market.cancelMarketSubscription`,
which only ever echoes back the one `MarketSubscription` it acted on, not a whole `User`) into
`model.resolver`'s currently loaded `User` -- mirrors `withResolvedUserPhone`, replacing the
matching-`id` entry in `user.marketSubscriptions` rather than the whole `User` (a no-op if
`resolver.status` isn't `Loaded`).
-}
withResolvedSubscription : MarketSubscription -> Resolver.Model -> Resolver.Model
withResolvedSubscription updated resolver =
    case resolver.status of
        Resolver.Loaded user ->
            { resolver
                | status =
                    Resolver.Loaded
                        { user
                            | marketSubscriptions =
                                List.map
                                    (\s ->
                                        if s.id == updated.id then
                                            updated

                                        else
                                            s
                                    )
                                    user.marketSubscriptions
                        }
            }

        _ ->
            resolver


{-| `AvatarSaveClicked`'s transform, passed to `Users.updateUser` the same way
`RealNameSaveClicked`'s inline lambda is -- applied to a freshly re-fetched
`User`, not `model.resolver`'s own possibly-stale one (see `Users.updateUser`'s
own doc). `AvatarChosen mediaId` only ever needs to set `avatar.id` --
`backend/src/rpcs/users/update_user.rs`'s `update_user` reads nothing else off
it -- so the rest of `MediaReference` is left at `defaultMediaReference`'s
placeholders.
-}
applyAvatarChoice : AvatarChoice -> User -> User
applyAvatarChoice choice freshUser =
    case choice of
        AvatarUnchanged ->
            freshUser

        AvatarChosen mediaId ->
            { freshUser | avatar = Just { defaultMediaReference | id = mediaId } }

        AvatarRemoved ->
            { freshUser | avatar = Nothing }



-- VIEW


{-| Renders a `Lookup` (plus the server it's being looked up on) the way it'd
appear in a route: `username@server.com` for `ByUsername`, or
`id:theUserId@server.com` for `ById`.
-}
lookupToString : String -> Resolver.Lookup -> String
lookupToString targetHost lookup =
    case lookup of
        Resolver.ByUsername username ->
            username ++ "@" ++ targetHost

        Resolver.ById userId ->
            "id:" ++ userId ++ "@" ++ targetHost


{-| Before the `User` has loaded, falls back to whatever the route itself
already told us: the username for `ByUsername` (`Pages.UsernameOrCustomTab_`), or else
"User <id>" for `ById` (`Pages.User.UserId_`, which has no username to show
yet).
-}
titleFor : Model -> String
titleFor model =
    case model.resolver.status of
        Resolver.Loaded user ->
            Users.titleName user

        _ ->
            case model.resolver.lookup of
                Resolver.ByUsername username ->
                    username

                Resolver.ById userId ->
                    "User " ++ userId


view : Shared.Model -> Model -> Html Msg
view shared model =
    ServerDependentView.view
        { hostname = model.resolver.targetHost
        , servers = shared.accounts.servers
        , accounts = shared.accounts.accounts
        , connectStatus = model.connectStatus
        , onConnectClicked = ConnectClicked
        , onEnableClicked = EnableClicked
        }
        (\server maybeAccount ->
            case model.resolver.status of
                Resolver.Loading ->
                    p [ class "profile-loading" ] [ text "Loading…" ]

                Resolver.Failed ->
                    p [ class "profile-error" ] [ text ("Couldn't load the profile for " ++ lookupToString model.resolver.targetHost model.resolver.lookup ++ ". Maybe they don't exist, or maybe you need to be logged in?") ]

                Resolver.Loaded user ->
                    profileDetail shared model server maybeAccount user
        )


profileDetail : Shared.Model -> Model -> RellmServer -> Maybe RellmAccount -> User -> Html Msg
profileDetail shared model server maybeAccount user =
    let
        canEdit : Bool
        canEdit =
            canEditProfile maybeAccount user

        isAdmin : Bool
        isAdmin =
            isAdminAccount maybeAccount

        baseHref : String
        baseHref =
            Users.profileHref shared.basePath
                shared.accounts.mainFrontendHost
                server.frontendHost
                { userId = user.id, username = user.username }

        postsHref : String
        postsHref =
            baseHref ++ "/posts"

        repliesHref : String
        repliesHref =
            baseHref ++ "/posts?context=reply"

        followersHref : String
        followersHref =
            baseHref ++ "/followers"

        followingHref : String
        followingHref =
            baseHref ++ "/following"

        friendsHref : String
        friendsHref =
            baseHref ++ "/friends"

        eventsHref : String
        eventsHref =
            baseHref ++ "/events"
    in
    div [ classes [ "profile-detail", hostnameToCSSClass server.frontendHost, "border-color-primary-anchor-50" ] ]
        [ div [ class "profile-header-row" ]
            [ div [ class "profile-header" ]
                [ avatarView canEdit server maybeAccount model.avatarEdit user
                , div [ class "profile-header-names" ]
                    [ ProfileHeading.usernameHeading user
                    , realNameView canEdit model.realNameEdit user
                    ]

                -- , otherServerIndicator shared server
                ]
            , Html.map FollowStatusAndButtonMsg (FollowStatusAndButton.view model.followStatusAndButton maybeAccount user)
            ]
        , federatedProfilesSection shared model server (isOwnProfile maybeAccount user) user
        , div [ class "profile-meta" ]
            ([ visibilityView canEdit maybeAccount model.visibilityEdit user
             , moderationView (canModerateUser maybeAccount) model.moderationEdit user
             ]
                ++ (user.createdAt
                        |> Maybe.map (\ts -> text (" · Joined " ++ SharedTime.formatDate shared.time.browserTimeZone.zone (timestampToPosix ts)))
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
                   )
            )
        , contactMethodsSection shared.time.browserTimeZone canEdit (isOwnProfile maybeAccount user) model.contactMethodsExpanded model user
        , followModerationToggleView canEdit model.followModerationStatus user
        , profileCounts postsHref repliesHref followersHref followingHref friendsHref eventsHref user
        , bioSection canEdit user
        , case model.events of
            Just eventsModel ->
                Html.map EventsMsg (EventsPage.view shared False eventsModel)

            Nothing ->
                text ""
        , syncSourcesSection shared model canEdit maybeAccount user
        , syncDestinationsSection shared model maybeAccount user
        , case model.posts of
            Just postsModel ->
                div [ class "posts-embedded-heading-row" ]
                    [ h3 [] [ text (postsHeading model.posts) ]
                    , Html.map PostsMsg (PostsPage.exportButtonView shared postsModel)
                    ]

            Nothing ->
                h3 [] [ text (postsHeading model.posts) ]
        , case model.posts of
            Just postsModel ->
                Html.map PostsMsg (PostsPage.view shared False False postsModel)

            Nothing ->
                text ""
        , aiProvidersSection model canEdit (isOwnProfile maybeAccount user) user
        , aiProviderGrantedSection model canEdit user
        , storageQuotaSection isAdmin (isOwnProfile maybeAccount user) model.storageQuotaExpanded model.storageQuotaEdit user
        , subscriptionsSection shared.time.browserTimeZone isAdmin (isOwnProfile maybeAccount user) model.subscriptionsExpanded model.cancelingSubscriptions user
        , permissionsSection isAdmin model.permissionsExpanded model.permissionsEdit user
        , accountActionsSection canEdit model.passwordResetEdit user
        ]


{-| "Recent Posts"/"Recent Replies", matching `model.posts`' own `PostContext` --
mirrors `Pages.Home_.heading` exactly, just over a `Maybe PostsPage.Model` (not yet
`init`ed for the brief moment before `resolver` first resolves, see `Model.posts`'
own doc) -- defaults to "Recent Posts" both then and for the ordinary `POST` case,
same as `Pages.Home_.heading` does.
-}
postsHeading : Maybe PostsPage.Model -> String
postsHeading maybePosts =
    case maybePosts |> Maybe.map .context of
        Just REPLY ->
            "Recent Replies"

        _ ->
            "Recent Posts"


{-| Whether the currently signed-in account on `user`'s own server (`maybeAccount`,
`profileDetail`'s own -- the enabled account for the target host, not
necessarily `user` itself) may edit `user`'s Real Name/bio: `user` themself,
or an `ADMIN` -- matches `backend/src/rpcs/users/update_user.rs`'s own
`self_update || admin` check (see `Shared.MarkdownPanel.resolve`'s `UserBio`
case, which re-verifies this server-side gate right before a bio save).
-}
canEditProfile : Maybe RellmAccount -> User -> Bool
canEditProfile maybeAccount user =
    case maybeAccount of
        Just account ->
            account.userId == user.id || List.member ADMIN account.permissions

        Nothing ->
            False


{-| Whether the currently signed-in account on this profile's server is an
`ADMIN` -- gates the permissions editor (`permissionsSection`), which only
`update_user.rs`'s own `admin` branch is ever allowed to change.
-}
isAdminAccount : Maybe RellmAccount -> Bool
isAdminAccount maybeAccount =
    case maybeAccount of
        Just account ->
            List.member ADMIN account.permissions

        Nothing ->
            False


{-| Whether the currently signed-in account on this profile's server may
moderate `user` -- an `ADMIN`, or a `MODERATEUSERS` holder, matching
`backend/src/rpcs/users/update_user.rs`'s own `admin || moderator` check
(the branch that actually applies `moderation`), gating `moderationView`'s
"Moderate" button. Unlike `canEditProfile`, `user` themself doesn't get a
pass here unless they also hold one of these permissions.
-}
canModerateUser : Maybe RellmAccount -> Bool
canModerateUser maybeAccount =
    case maybeAccount of
        Just account ->
            List.member ADMIN account.permissions || List.member MODERATEUSERS account.permissions

        Nothing ->
            False


{-| The avatar, plus (only for `canEdit`) its editing affordance below it: an
"Edit" button when `model.avatarEdit == Nothing`, or -- while editing -- a "✕"
button over the avatar's top-right corner (`AvatarRemoveClicked`, clears the
avatar entirely) and a Save/Cancel row underneath it (mirrors `editSaveButton`/
`editCancelButton`'s use elsewhere on this page). The avatar image itself
previews `edit.choice` (see `avatarPreviewUrl`) rather than `user.avatar`
once editing's started, and -- while editing -- is itself clickable
(`AvatarEditClicked` again, which re-opens `Shared.MyMediaPanel` without
resetting `choice`/`status`, see its own doc) so the user can pick again
without hunting for a smaller "change" link. A non-`canEdit` viewer just gets
the plain avatar, same as before this existed.
-}
avatarView : Bool -> RellmServer -> Maybe RellmAccount -> Maybe AvatarEdit -> User -> Html Msg
avatarView canEdit server maybeAccount maybeEdit user =
    if not canEdit then
        UI.imageOrInitial [ "profile-avatar" ] user.username (Users.avatarUrl server maybeAccount user)

    else
        div [ class "profile-avatar-wrapper" ]
            [ div
                (case maybeEdit of
                    Just _ ->
                        [ classes [ "profile-avatar-frame", "editable" ], onClick AvatarEditClicked, title "Change avatar" ]

                    Nothing ->
                        [ classes [ "profile-avatar-frame" ] ]
                )
                [ UI.imageOrInitial [ "profile-avatar" ] user.username (avatarPreviewUrl server maybeAccount maybeEdit user)
                , case maybeEdit of
                    Just edit ->
                        button
                            [ class "profile-avatar-remove"
                            , stopPropagationAndPreventDefaultOnClick AvatarRemoveClicked
                            , disabled (edit.status == Submitting)
                            , title "Remove avatar"
                            ]
                            [ text "✕" ]

                    Nothing ->
                        text ""
                ]
            , case maybeEdit of
                Just edit ->
                    div [ class "profile-avatar-edit-actions" ]
                        [ editSaveButton AvatarSaveClicked edit.status
                        , editCancelButton AvatarCancelClicked edit.status
                        , editErrorView edit.status
                        ]

                Nothing ->
                    button [ class "profile-edit-button", onClick AvatarEditClicked ] [ text "Edit Avatar" ]
            ]


{-| The avatar URL `avatarView` should actually preview: `user.avatar` itself
(same as `Users.avatarUrl`) once no edit's in progress or nothing's changed
yet (`AvatarUnchanged`), the just-picked media once one has (`AvatarChosen`,
built via `Users.mediaReferenceUrl` off a throwaway `MediaReference` wrapping
just that id -- nothing else about it is known/needed for a preview `<img>`),
or `Nothing` (falling back to `UI.imageOrInitial`'s initial-letter
placeholder) once the "✕" button's been hit (`AvatarRemoved`).
-}
avatarPreviewUrl : RellmServer -> Maybe RellmAccount -> Maybe AvatarEdit -> User -> Maybe String
avatarPreviewUrl server maybeAccount maybeEdit user =
    case maybeEdit |> Maybe.map .choice of
        Nothing ->
            Users.avatarUrl server maybeAccount user

        Just AvatarUnchanged ->
            Users.avatarUrl server maybeAccount user

        Just (AvatarChosen mediaId) ->
            Users.mediaReferenceUrl server maybeAccount (Just { defaultMediaReference | id = mediaId })

        Just AvatarRemoved ->
            Nothing


{-| The Real Name line -- plain text (plus an Edit button, if `canEdit`) when
`model.realNameEdit == Nothing`, or an inline input/Save/Cancel form while
being edited. Shown (with just the Edit button, no text) even when `user`
has no Real Name yet, so `canEdit` viewers can add one.
-}
realNameView : Bool -> Maybe RealNameEdit -> User -> Html Msg
realNameView canEdit maybeEdit user =
    case maybeEdit of
        Just edit ->
            div [ class "profile-real-name-edit" ]
                [ input
                    [ class "profile-real-name-input"
                    , value edit.input
                    , onInput RealNameInputChanged
                    , placeholder "Real Name"
                    ]
                    []
                , editSaveButton RealNameSaveClicked edit.status
                , editCancelButton RealNameCancelClicked edit.status
                , editErrorView edit.status
                ]

        Nothing ->
            if String.isEmpty (String.trim user.realName) && not canEdit then
                text ""

            else
                div [ class "profile-real-name-display" ]
                    [ if String.isEmpty (String.trim user.realName) then
                        text ""

                      else
                        span [ class "profile-real-name" ] [ text user.realName ]
                    , if canEdit then
                        button [ class "profile-edit-button", onClick RealNameEditClicked ] [ text "Edit Name" ]

                      else
                        text ""
                    ]


{-| The Visibility segment of `profileDetail`'s meta line -- plain text
(`Users.visibilityText`) plus an Edit button when `model.visibilityEdit ==
Nothing`, shown only to `canEdit` viewers (mirrors `Pages.Post.PostId_.
visibilityView`'s own `isAuthor`-gated Edit button, just gated on
`canEditProfile` here instead); an inline `<select>` + Save/Cancel once
editing, with its options narrowed to whatever `maybeAccount` is actually
allowed to pick (`Users.allowedVisibilities`, mirroring
`backend/src/rpcs/users/update_user.rs`'s own `PUBLISHUSERSGLOBALLY` check).
-}
visibilityView : Bool -> Maybe RellmAccount -> Maybe VisibilityEdit -> User -> Html Msg
visibilityView canEdit maybeAccount maybeEdit user =
    case maybeEdit of
        Just edit ->
            let
                options : List Visibility
                options =
                    maybeAccount
                        |> Maybe.map (\account -> Users.allowedVisibilities account.permissions user.visibility)
                        |> Maybe.withDefault [ edit.pending ]
            in
            span [ class "profile-visibility-edit" ]
                [ select [ onInput VisibilityChanged ]
                    (options
                        |> List.map
                            (\visibility ->
                                option
                                    [ value (Users.visibilityText visibility)
                                    , selected (edit.pending == visibility)
                                    ]
                                    [ text (Users.visibilityText visibility) ]
                            )
                    )
                , editSaveButton VisibilitySaveClicked edit.status
                , editCancelButton VisibilityCancelClicked edit.status
                , editErrorView edit.status
                ]

        Nothing ->
            span [ class "profile-visibility-display" ]
                [ text (Users.visibilityText user.visibility)
                , if canEdit then
                    button [ class "profile-edit-button", onClick VisibilityEditClicked ] [ text "Edit Visibility" ]

                  else
                    text ""
                ]


{-| The Moderation segment of `profileDetail`'s meta line -- mirrors
`visibilityView` exactly, just for `Moderation` instead of `Visibility`,
shown to an Admin/`MODERATEUSERS` holder instead of `canEditProfile` (see
`canModerateUser`), and its own "Edit" button reads "Moderate" instead,
mirroring `Pages.Post.PostId_.moderationView`'s own convention.
-}
moderationView : Bool -> Maybe ModerationEdit -> User -> Html Msg
moderationView canModerate maybeEdit user =
    case maybeEdit of
        Just edit ->
            span [ class "profile-moderation-edit" ]
                [ text " · "
                , select [ onInput ModerationChanged ]
                    (Users.allModerations
                        |> List.map
                            (\moderation ->
                                option
                                    [ value (Users.moderationText moderation)
                                    , selected (edit.pending == moderation)
                                    ]
                                    [ text (Users.moderationText moderation) ]
                            )
                    )
                , editSaveButton ModerationSaveClicked edit.status
                , editCancelButton ModerationCancelClicked edit.status
                , editErrorView edit.status
                ]

        Nothing ->
            span [ class "profile-moderation-display" ]
                [ text (" · " ++ Users.moderationText user.moderation)
                , if canModerate then
                    button [ class "profile-edit-button", onClick ModerationEditClicked ] [ text "Moderate" ]

                  else
                    text ""
                ]


{-| The "Requires permission to follow" toggle -- a bare on/off switch
(`profileSwitch`) rather than a Save/Cancel edit like `visibilityView`/
`moderationView`, since it's just one boolean: "on" sets
`user.defaultFollowModeration` to `PENDING` (a follow request needs
approval), "off" sets it to `UNMODERATED` (anyone can follow outright).
Treats any moderation value other than `PENDING` (e.g. a legacy `APPROVED`/
`REJECTED`) as "off", matching `Components.Users.moderationPasses`' own
`UNMODERATED`-or-`APPROVED` "in effect" reasoning -- there's no third state
to round-trip here. Always shown (unlike `visibilityView`/`moderationView`'s
Edit/Moderate buttons, which disappear entirely for a viewer who can't use
them), just disabled for a `not canEdit` viewer -- mirrors
`Components.Pages.ServerInformationPage.switchDisplay`'s "show the state,
disable the control" treatment for a setting this viewer can see but not
change.
-}
followModerationToggleView : Bool -> SubmitStatus -> User -> Html Msg
followModerationToggleView canEdit status user =
    div [ class "profile-follow-moderation-toggle" ]
        [ span [ class "profile-follow-moderation-label" ] [ text "Requires permission to follow" ]
        , profileSwitch (user.defaultFollowModeration == PENDING) (not canEdit || status == Submitting) FollowModerationToggled
        , editErrorView status
        ]


{-| The "Contact Methods" section -- Phone/Email, each with a Verified/Not Verified badge (see
`contactMethodVerifiedBadge`) and (for `canEdit` viewers) an Edit button, plus (phone only, and only
for the profile's own owner) the SMS verification flow (see `phoneVerificationView`). Collapsed by
default (`expanded`, `Model.contactMethodsExpanded`) behind `expandableProfileSection`'s own header,
same as `permissionsSection`/`syncSourcesSection` -- except a `#contact-methods` link (see `init`'s
own `fragment` handling) opens it pre-expanded. Hidden entirely for a non-`canEdit` viewer if there's
nothing to show (mirrors `permissionsSection`'s own "hide if nothing to show and can't add anything"
gate) -- a `User` this viewer can't see either contact method on simply won't have them populated at
all (enforced server-side via each `ContactMethod`'s own `visibility`), so there'd be nothing here.
-}
contactMethodsSection : SharedTime.BrowserTimeZone -> Bool -> Bool -> Bool -> Model -> User -> Html Msg
contactMethodsSection browserTimeZone canEdit isOwn expanded model user =
    if user.phone == Nothing && user.email == Nothing && not canEdit then
        text ""

    else
        expandableProfileSection "profile-contact-methods-section"
            "profile-contact-methods-section"
            "Contact Methods"
            Nothing
            expanded
            ContactMethodsExpandedToggled
            [ phoneView canEdit model.phoneEdit user
            , contactMethodConsentView browserTimeZone
                "SMS"
                canEdit
                model.phoneConsentStatus
                model.phoneHistoryExpanded
                PhoneConsentToggled
                PhoneHistoryToggled
                user.phone
            , if isOwn then
                phoneVerificationView model.phoneVerification user.phone

              else
                text ""
            , emailView canEdit model.emailEdit user
            , contactMethodConsentView browserTimeZone
                "email"
                canEdit
                model.emailConsentStatus
                model.emailHistoryExpanded
                EmailConsentToggled
                EmailHistoryToggled
                user.email
            ]


{-| The Phone line -- mirrors `realNameView` exactly (plain text plus an Edit button when
`maybeEdit == Nothing`, an inline input/Save/Cancel form while editing), plus a Verified/Not Verified
badge (`contactMethodVerifiedBadge`) next to the display value. Shown (with just the Edit button, no
value) even when `user.phone` is unset, so `canEdit` viewers can add one -- `PhoneSaveClicked` is
what actually writes it (see `update`).
-}
phoneView : Bool -> Maybe PhoneEdit -> User -> Html Msg
phoneView canEdit maybeEdit user =
    case maybeEdit of
        Just edit ->
            div [ class "profile-contact-method-edit" ]
                [ span [ class "profile-contact-method-label" ] [ text "Phone" ]
                , input
                    [ class "profile-real-name-input"
                    , value edit.input
                    , onInput PhoneInputChanged
                    , placeholder "+15555550100"
                    ]
                    []
                , contactMethodVisibilitySelector PhoneVisibilityChanged edit.visibility
                , editSaveButton PhoneSaveClicked edit.status
                , editCancelButton PhoneCancelClicked edit.status
                , editErrorView edit.status
                ]

        Nothing ->
            if user.phone == Nothing && not canEdit then
                text ""

            else
                div [ class "profile-contact-method-display" ]
                    ([ span [ class "profile-contact-method-label" ] [ text "Phone: " ]
                     , span [ class "profile-contact-method-value" ] [ text (contactMethodDisplayValue "tel:" user.phone) ]
                     ]
                        ++ (user.phone |> Maybe.map (\cm -> [ contactMethodVerifiedBadge cm ]) |> Maybe.withDefault [])
                        ++ (if canEdit then
                                [ button [ class "profile-edit-button", onClick PhoneEditClicked ] [ text "Edit Phone" ] ]

                            else
                                []
                           )
                    )


{-| The Email line -- mirrors `phoneView` exactly, just for the `mailto:` scheme instead of `tel:`.
Email verification is out of scope this iteration, so (unlike `phoneView`) there's no corresponding
verification affordance here -- only the Verified/Not Verified badge, reflecting whatever
`verifiedAt` the server happens to report.
-}
emailView : Bool -> Maybe EmailEdit -> User -> Html Msg
emailView canEdit maybeEdit user =
    case maybeEdit of
        Just edit ->
            div [ class "profile-contact-method-edit" ]
                [ span [ class "profile-contact-method-label" ] [ text "Email" ]
                , input
                    [ class "profile-real-name-input"
                    , value edit.input
                    , onInput EmailInputChanged
                    , placeholder "you@example.com"
                    ]
                    []
                , contactMethodVisibilitySelector EmailVisibilityChanged edit.visibility
                , editSaveButton EmailSaveClicked edit.status
                , editCancelButton EmailCancelClicked edit.status
                , editErrorView edit.status
                ]

        Nothing ->
            if user.email == Nothing && not canEdit then
                text ""

            else
                div [ class "profile-contact-method-display" ]
                    ([ span [ class "profile-contact-method-label" ] [ text "Email: " ]
                     , span [ class "profile-contact-method-value" ] [ text (contactMethodDisplayValue "mailto:" user.email) ]
                     ]
                        ++ (user.email |> Maybe.map (\cm -> [ contactMethodVerifiedBadge cm ]) |> Maybe.withDefault [])
                        ++ (if canEdit then
                                [ button [ class "profile-edit-button", onClick EmailEditClicked ] [ text "Edit Email" ] ]

                            else
                                []
                           )
                    )


{-| The contact-consent checkbox shown under `phoneView`/`emailView` for `canEdit` viewers, plus a
(sub-)expandable "History" list of every `ContactConsentChange` in `contactMethod.consentHistory`
(oldest last -- see `contactConsentChangeView`). `methodLabel` (`"SMS"`/`"email"`) fills in the
disclaimer text so it reads correctly for either method -- the checkbox/behavior itself is
otherwise identical between Phone and Email (per `docs/contact_integrations.md`).

Checking/unchecking calls `toggleMsg` (`PhoneConsentToggled`/`EmailConsentToggled`), which
`UpdateUser`s just `consentState` (see `update`); the server appends the resulting
`ContactConsentChange` to `consentHistory` (`apply_contact_method_update` on the backend), and that
updated `User` flows back into `model.resolver` same as any other save -- so the History list, if
already expanded, updates as a pure byproduct of the checkbox's own save, no separate fetch needed.

Hidden entirely if `contactMethod` is unset (nothing to consent to yet) or `not canEdit` -- mirrors
`phoneVerificationView`'s own "nothing to show" gate.

-}
contactMethodConsentView : SharedTime.BrowserTimeZone -> String -> Bool -> SubmitStatus -> Bool -> Msg -> Msg -> Maybe ContactMethod -> Html Msg
contactMethodConsentView browserTimeZone methodLabel canEdit status historyExpanded toggleMsg historyToggleMsg maybeContactMethod =
    case ( canEdit, maybeContactMethod ) of
        ( True, Just contactMethod ) ->
            div [ class "profile-contact-method-consent" ]
                [ label [ class "profile-contact-method-consent-label" ]
                    [ input
                        [ type_ "checkbox"
                        , checked (contactMethod.consentState == CONTACTCONSENTGRANTED)
                        , disabled (status == Submitting)
                        , onClick toggleMsg
                        ]
                        []
                    , text (" Checking this box indicates I consent to be contacted via " ++ methodLabel ++ ".")
                    ]
                , editErrorView status
                , if List.isEmpty contactMethod.consentHistory then
                    text ""

                  else
                    div [ class "profile-contact-method-consent-history" ]
                        [ button
                            [ class "profile-edit-button", onClick historyToggleMsg ]
                            [ text
                                (if historyExpanded then
                                    "Hide History"

                                 else
                                    "Show History"
                                )
                            ]
                        , if historyExpanded then
                            ul [ class "profile-contact-method-consent-history-list" ]
                                (contactMethod.consentHistory
                                    |> List.reverse
                                    |> List.map (contactConsentChangeView browserTimeZone)
                                )

                          else
                            text ""
                        ]
                ]

        _ ->
            text ""


{-| One `li` in `contactMethodConsentView`'s History list -- "Granted"/"Revoked" plus the
server-timestamped `changedAt`, formatted the same way `syncSourceRowView` formats its own
timestamps (`SharedTime.formatDateTime`).
-}
contactConsentChangeView : SharedTime.BrowserTimeZone -> ContactConsentChange -> Html msg
contactConsentChangeView browserTimeZone change =
    let
        label : String
        label =
            if change.state == CONTACTCONSENTGRANTED then
                "Granted"

            else
                "Revoked"

        when : String
        when =
            change.changedAt
                |> Maybe.map (timestampToPosix >> SharedTime.formatDateTime browserTimeZone)
                |> Maybe.withDefault ""
    in
    li [] [ text (label ++ " " ++ when) ]


{-| The visibility options offered by `phoneView`/`emailView`'s visibility `<select>` -- narrower than
`Components.Posts.allVisibilities`: excludes `LIMITED` (explicit-user/group sharing doesn't apply to
a contact method) and `DIRECT` (same `[TODO]`/unimplemented reason `allVisibilities` itself excludes
it), leaving just the three options a contact method's visibility can meaningfully take.
-}
contactMethodVisibilities : List Visibility
contactMethodVisibilities =
    [ PRIVATE, SERVERPUBLIC, GLOBALPUBLIC ]


{-| The visibility `<select>` shown alongside `phoneView`/`emailView`'s input while editing -- reuses
`Components.Posts`' own `visibilityText`/`visibilityFromText` for display/round-tripping, narrowed to
`contactMethodVisibilities`. Selecting a new option only ever updates the in-progress edit's
`visibility` (see `PhoneVisibilityChanged`/`EmailVisibilityChanged`); nothing is sent to the server
until the corresponding Save button is clicked.
-}
contactMethodVisibilitySelector : (String -> Msg) -> Visibility -> Html Msg
contactMethodVisibilitySelector onChange currentVisibility =
    select [ onInput onChange ]
        (contactMethodVisibilities
            |> List.map
                (\visibility ->
                    option
                        [ value (Posts.visibilityText visibility)
                        , selected (visibility == currentVisibility)
                        ]
                        [ text (Posts.visibilityText visibility) ]
                )
        )


{-| The Verified/Not Verified badge next to a displayed contact method -- plain Unicode glyphs (no
icon font in this app), mirroring `Components.UserPicker`'s own "✓" and `Shared.MyMediaPanel`'s own
"✕" usage.
-}
contactMethodVerifiedBadge : ContactMethod -> Html msg
contactMethodVerifiedBadge contactMethod =
    if contactMethod.verifiedAt /= Nothing then
        span [ class "profile-contact-method-verified" ] [ text "✓ Verified" ]

    else
        span [ class "profile-contact-method-not-verified" ] [ text "✕ Not Verified" ]


{-| `phoneView`/`emailView`'s display value -- `contactMethod.value` with its `tel:`/`mailto:`
scheme stripped back off (`"—"` when unset), mirroring how `Components.Pages.ServerInformationPage.
CdnTab` falls back to an em dash for an unset field.
-}
contactMethodDisplayValue : String -> Maybe ContactMethod -> String
contactMethodDisplayValue prefix maybeContactMethod =
    maybeContactMethod
        |> Maybe.andThen .value
        |> Maybe.map (stripContactMethodPrefix prefix)
        |> Maybe.withDefault "—"


{-| `PhoneEditClicked`/`EmailEditClicked`'s seed value for their edit input -- same as
`contactMethodDisplayValue`, just defaulting to `""` (an editable blank) rather than `"—"` (a
display-only placeholder) when unset.
-}
contactMethodEditValue : String -> Maybe ContactMethod -> String
contactMethodEditValue prefix maybeContactMethod =
    maybeContactMethod
        |> Maybe.andThen .value
        |> Maybe.map (stripContactMethodPrefix prefix)
        |> Maybe.withDefault ""


stripContactMethodPrefix : String -> String -> String
stripContactMethodPrefix prefix rawValue =
    if String.startsWith prefix rawValue then
        String.dropLeft (String.length prefix) rawValue

    else
        rawValue


{-| The phone-only SMS verification flow, shown under `phoneView`/`contactMethodConsentView` for the
profile's own owner -- gated on `ContactMethod.supportedByServer` (the server-computed "can this be
verified right now" signal, reflecting Twilio/Bird/Telnyx's enabled state without exposing any
config details to a non-admin viewer) and on not already being verified. Also requires
`consentState == CONTACT_CONSENT_GRANTED` -- the verification code is itself an outbound SMS, so
`start_contact_method_verification_at` rejects it with `contact_consent_not_granted` otherwise (see
that function's own doc); rather than let the user hit that error, the "Start Verification" button
is simply replaced with a hint to grant consent above first. `Nothing` (`model.phoneVerification`)
shows a bare "Start Verification" button (`StartPhoneVerificationClicked`); `Just pv` shows a
code-entry input plus Verify/Resend once at least one send has been attempted, with "Resend"
disabled during `pv.cooldownActive`'s 60-second window (see `update`'s
`GotStartPhoneVerificationResult`/`PhoneVerificationCooldownElapsed`).
-}
phoneVerificationView : Maybe PhoneVerification -> Maybe ContactMethod -> Html Msg
phoneVerificationView maybePhoneVerification maybePhone =
    let
        eligibleToVerify : Bool
        eligibleToVerify =
            maybePhone
                |> Maybe.map (\cm -> cm.supportedByServer && cm.verifiedAt == Nothing)
                |> Maybe.withDefault False
    in
    if not eligibleToVerify then
        text ""

    else
        let
            consentGranted : Bool
            consentGranted =
                maybePhone
                    |> Maybe.map (\cm -> cm.consentState == CONTACTCONSENTGRANTED)
                    |> Maybe.withDefault False
        in
        if not consentGranted then
            p [ class "profile-contact-method-verify-disclaimer" ]
                [ text "Grant SMS consent above to verify your phone number -- the verification code itself is sent by SMS." ]

        else
            case maybePhoneVerification of
                Nothing ->
                    div [ class "profile-contact-method-verify" ]
                        [ button [ class "profile-edit-button", onClick StartPhoneVerificationClicked ] [ text "Start Verification" ] ]

                Just pv ->
                    div [ class "profile-contact-method-verify" ]
                        [ if pv.sendStatus == Submitting then
                            span [ class "profile-contact-method-verify-status" ] [ text "Sending code…" ]

                          else
                            div [ class "profile-contact-method-verify-code" ]
                                [ input
                                    [ class "profile-real-name-input"
                                    , placeholder "Enter code"
                                    , value pv.code
                                    , onInput PhoneVerificationCodeChanged
                                    , disabled (pv.verifyStatus == Submitting)
                                    ]
                                    []
                                , button
                                    [ class "profile-edit-save"
                                    , onClick VerifyPhoneCodeClicked
                                    , disabled (pv.verifyStatus == Submitting || String.isEmpty pv.code)
                                    ]
                                    [ text
                                        (if pv.verifyStatus == Submitting then
                                            "Verifying…"

                                         else
                                            "Verify"
                                        )
                                    ]
                                , button
                                    [ class "profile-edit-cancel"
                                    , onClick StartPhoneVerificationClicked
                                    , disabled pv.cooldownActive
                                    ]
                                    [ text "Resend" ]
                                ]
                        , editErrorView pv.sendStatus
                        , editErrorView pv.verifyStatus
                        ]


{-| A checkbox styled as a toggle switch -- same `.switch`/`.slider` classes
as `UI.switchInput`, not reused directly since that function's `toggleMsg` is
hard-coded to `Shared.Msg` (mirrors `Components.Pages.ServerInformationPage.
flagSwitch`, which duplicates it for the same reason).
-}
profileSwitch : Bool -> Bool -> Msg -> Html Msg
profileSwitch isChecked isDisabled toggleMsg =
    label [ classList [ ( "switch", True ), ( "disabled", isDisabled ) ] ]
        [ input [ type_ "checkbox", checked isChecked, disabled isDisabled, onClick toggleMsg ] []
        , span [ class "slider" ] []
        ]


{-| The bio, rendered as Markdown, with an Edit button (opening the shared
`Shared.MarkdownPanel` panel via `BioEditClicked`, targeting `MarkdownPanel.UserBio`)
if `canEdit` -- shown (with just the Edit button) even with no bio yet, so
`canEdit` viewers can add one.
-}
bioSection : Bool -> User -> Html Msg
bioSection canEdit user =
    if String.isEmpty (String.trim user.bio) && not canEdit then
        text ""

    else
        div [ class "profile-bio-section" ]
            [ if String.isEmpty (String.trim user.bio) then
                text ""

              else
                Markdown.view [ class "profile-bio" ] user.bio
            , if canEdit then
                button [ class "profile-edit-button", onClick BioEditClicked ] [ text "Edit Bio" ]

              else
                text ""
            ]


editSaveButton : Msg -> SubmitStatus -> Html Msg
editSaveButton onSave status =
    button
        [ classes [ "profile-edit-save", "background-color-primary" ]
        , onClick onSave
        , disabled (status == Submitting)
        ]
        [ text
            (if status == Submitting then
                "Saving…"

             else
                "Save"
            )
        ]


editCancelButton : Msg -> SubmitStatus -> Html Msg
editCancelButton onCancel status =
    button [ class "profile-edit-cancel", onClick onCancel, disabled (status == Submitting) ] [ text "Cancel" ]


editErrorView : SubmitStatus -> Html msg
editErrorView status =
    case status of
        SubmitFailed err ->
            div [ class "profile-edit-error" ] [ text err ]

        _ ->
            text ""


{-| `postsHref`/`followersHref`/`followingHref`/`friendsHref` (see `profileDetail`) link the
"Posts"/"Followers"/"Following"/"Friends" counts to `Pages.UsernameOrCustomTab_.Posts`/
`Pages.UsernameOrCustomTab_.Followers`/`Pages.UsernameOrCustomTab_.Following`/`Pages.UsernameOrCustomTab_.Friends`
(or their `Pages.User.UserId_.*` equivalents) -- the other counts have no page of their
own (yet) to link to.
-}
profileCounts : String -> String -> String -> String -> String -> String -> User -> Html Msg
profileCounts postsHref repliesHref followersHref followingHref friendsHref eventsHref user =
    let
        counts : List ( String, Int, Maybe String )
        counts =
            [ ( "Followers", user.followerCount, Just followersHref )
            , ( "Following", user.followingCount, Just followingHref )
            , ( "Friends", user.friendCount, Just friendsHref )

            -- , ( "Groups", user.groupCount, Nothing )
            , ( "Posts", user.postCount, Just postsHref )
            , ( "Replies", user.responseCount, Just repliesHref )
            , ( "Events", user.occasionCount, Just eventsHref )
            ]
                |> List.filterMap (\( label, maybeCount, maybeHref ) -> maybeCount |> Maybe.map (\c -> ( label, c, maybeHref )))
    in
    if List.isEmpty counts then
        text ""

    else
        div [ class "profile-counts" ] (counts |> List.map profileCountView)


profileCountView : ( String, Int, Maybe String ) -> Html Msg
profileCountView ( label, count, maybeHref ) =
    let
        content : List (Html Msg)
        content =
            [ div [ class "profile-count-value" ] [ text (String.fromInt count) ]
            , div [ class "profile-count-label" ] [ text label ]
            ]
    in
    case maybeHref of
        Just linkHref ->
            a [ class "profile-count", href linkHref ] content

        Nothing ->
            div [ class "profile-count" ] content


{-| A `.section-title` header that also toggles a collapsed/expanded body below it -- shared by
`contactMethodsSection`/`storageQuotaSection`/`permissionsSection`/`syncSourcesSection`/
`syncDestinationsSection`/`aiProvidersSection`/`aiProviderGrantedSection`, most of which start
collapsed (see e.g. `Model.permissionsExpanded`/`syncSourcesExpanded`, both `False` in `init`) so
none dumps a wall of mostly-admin-only content onto every profile visit by default.

`content` is always mounted (unlike before this doc was last touched, when an unexpanded section
omitted it from the vdom outright) so `.expandable-section-content`'s own `grid-template-rows` 0fr/1fr
trick (`profiles.css`) can animate it open/closed -- the same mechanism, and the same tweaked rotation
values, as `Components.PinnedPosts.view`'s own collapsible section (`posts.css`'s
`.pinned-posts-content`/`.pinned-posts-chevron`) -- rather than the instant appear/disappear this
helper used to do. `expandable-section-arrow`'s glyph is now a single static `"▼"`, rotated via
`.expandable-section-arrow.is-open` instead of swapped for a different glyph per state, so the same
CSS transition drives both directions.

`maybeHeaderAction`, if given, renders inside the header itself (`.expandable-section-title`,
pushed to its far right via `.profile-section-refresh`'s own `margin-left: auto`) -- currently only
`syncSourcesSection`/`aiProvidersSection`'s "↻ Refresh" button (`refreshButtonView`), since that's
useful without expanding the section first to find it. Faded in/out via CSS (`.is-open`/`.is-closed`,
opacity + `pointer-events: none`) rather than conditionally mounted, same "always in the DOM, purely
CSS-driven" convention as `content`/the arrow above -- and its own `onClick` must stop propagation
(see `refreshButtonView`), or a click on it would bubble up to this same header's `toggleMsg` and
collapse the section it just refreshed.

`domId` is the section's real DOM `id` -- separate from `sectionClass` since `aiProvidersSection`/
`aiProviderGrantedSection` deliberately share one `sectionClass` (`"ai-model-providers-section"`,
for shared styling) but need distinct ids to both be independently linkable. Named to match the
`#subscriptions`/`#sync-sources`/`#sync-destinations`/`#ai-providers`/`#ai-models` fragments
`Model.pendingScrollSectionId` scrolls to (see that field's own doc) -- ordinary web `#dom-id`
anchors otherwise, so the other three sections just reuse their own `sectionClass` here since
nothing needs to link to them yet.

-}
expandableProfileSection : String -> String -> String -> Maybe (Html Msg) -> Bool -> Msg -> List (Html Msg) -> Html Msg
expandableProfileSection sectionClass domId title maybeHeaderAction expanded toggleMsg content =
    div [ class sectionClass, id domId ]
        [ h2
            [ classes [ "section-title", "expandable-section-title" ]
            , onClick toggleMsg
            ]
            [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
            , text title
            , Maybe.withDefault (text "") maybeHeaderAction
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ class "expandable-section-content-inner" ] content ]
        ]


{-| "Media Storage" -- shown to an Admin (viewing anyone's profile, to set their quota -- see
`update_user.rs`'s own admin-only `media_storage_limit_bytes` branch) or to the profile's own
owner (viewing their own percent-used readout and a "Show My Media" button to open
`Shared.MyMediaPanel` -- see `ShowMyMediaClicked`). Hidden entirely for anyone else, same
"nothing to show" convention `permissionsSection` uses. Collapsed by default, right above
`permissionsSection` -- both edit admin-only, rarely-touched `User` settings most viewers never
need to see.
-}
storageQuotaSection : Bool -> Bool -> Bool -> Maybe StorageQuotaEdit -> User -> Html Msg
storageQuotaSection isAdmin isOwn expanded maybeEdit user =
    if not (isAdmin || isOwn) then
        text ""

    else
        expandableProfileSection "profile-storage-quota-section"
            "profile-storage-quota-section"
            "Media Storage"
            Nothing
            expanded
            StorageQuotaExpandedToggled
            ((if isOwn then
                storageUsageView user

              else
                text ""
             )
                :: (if isAdmin then
                        [ storageQuotaEditView maybeEdit user ]

                    else
                        []
                   )
            )


{-| The profile owner's own used/available readout -- "42% used (2.1 GB of 5.0 GB)" when
`mediaStorageLimitBytes` is set, or "2.1 GB used (no limit)" otherwise -- plus the "Show My Media"
button (`ShowMyMediaClicked`, opening `Shared.MyMediaPanel` in plain Browse mode, same as
`UI.accountRow`'s own media button).
-}
storageUsageView : User -> Html Msg
storageUsageView user =
    let
        used : Int
        used =
            Conversions.int64ToInt user.mediaStorageBytesUsed

        usedText : String
        usedText =
            case Maybe.map Conversions.int64ToInt user.mediaStorageLimitBytes of
                Just limit ->
                    let
                        percent : Int
                        percent =
                            if limit <= 0 then
                                100

                            else
                                round (100 * toFloat used / toFloat limit)
                    in
                    String.fromInt percent ++ "% used (" ++ ByteFormat.formatBytes used ++ " of " ++ ByteFormat.formatBytes limit ++ ")"

                Nothing ->
                    ByteFormat.formatBytes used ++ " used (no limit)"
    in
    div [ class "profile-storage-usage" ]
        [ span [ class "profile-storage-usage-text" ] [ text usedText ]
        , button [ class "profile-edit-button", onClick ShowMyMediaClicked ] [ text "Show My Media" ]
        ]


{-| The Admin-only quota editor -- plain text (current limit, or "Unlimited") plus an Edit button
when `maybeEdit == Nothing`; a number input + unit `<select>` + an "Unlimited" checkbox (disabling
the number/unit inputs) + Save/Cancel while editing.
-}
storageQuotaEditView : Maybe StorageQuotaEdit -> User -> Html Msg
storageQuotaEditView maybeEdit user =
    case maybeEdit of
        Just edit ->
            div [ class "profile-storage-quota-edit" ]
                [ label []
                    [ input [ type_ "checkbox", checked edit.unlimited, onClick StorageQuotaUnlimitedToggled ] []
                    , text " Unlimited"
                    ]
                , if edit.unlimited then
                    text ""

                  else
                    span [ class "profile-storage-quota-input" ]
                        [ input
                            [ type_ "number"
                            , placeholder "Quota"
                            , value edit.pending
                            , onInput StorageQuotaPendingChanged
                            ]
                            []
                        , select [ onInput StorageQuotaUnitChanged ]
                            ([ ByteFormat.KB, ByteFormat.MB, ByteFormat.GB ]
                                |> List.map
                                    (\unit ->
                                        option
                                            [ value (ByteFormat.byteUnitText unit), selected (edit.unit == unit) ]
                                            [ text (ByteFormat.byteUnitText unit) ]
                                    )
                            )
                        ]
                , editSaveButton StorageQuotaSaveClicked edit.status
                , editCancelButton StorageQuotaCancelClicked edit.status
                , editErrorView edit.status
                ]

        Nothing ->
            div [ class "profile-storage-quota-display" ]
                [ span [ class "profile-storage-quota-display-text" ]
                    [ text
                        (case Maybe.map Conversions.int64ToInt user.mediaStorageLimitBytes of
                            Just limit ->
                                "Quota: " ++ ByteFormat.formatBytes limit

                            Nothing ->
                                "Quota: Unlimited"
                        )
                    ]
                , button [ class "profile-edit-button", onClick StorageQuotaEditClicked ] [ text "Edit Quota" ]
                ]


{-| "Subscriptions" -- a read-only readout of `user.marketSubscriptions` (`market.proto`), each
with its type/period/amount, whichever of `renewsAt`/`canceledAt`/`serviceTerminatedAt` are
actually set (see `timestampLineView`), and (for the profile's own owner or an Admin, same gating
below) a "Cancel Subscription" button while it's not yet canceled. Unlike `storageQuotaSection`/
`permissionsSection`, there's no edit mode here at all -- subscriptions are only ever created via
`Components.Pages.MarketPage`'s "Buy" flow (a real Stripe Checkout redirect), never by editing a
`User` directly; cancellation is the one mutation this section supports, via
`Components.Market.cancelMarketSubscription`. Shown to the profile's own owner or an Admin, same
gating (and same "hide if nothing to show" convention) as `storageQuotaSection` -- matches how
`User.marketSubscriptions` itself is only ever populated for those two viewers (see that field's
own proto doc). Collapsed by default, alongside `storageQuotaSection`/`permissionsSection`.
-}
subscriptionsSection : SharedTime.BrowserTimeZone -> Bool -> Bool -> Bool -> Dict String SubmitStatus -> User -> Html Msg
subscriptionsSection browserTimeZone isAdmin isOwn expanded cancelingSubscriptions user =
    if not (isAdmin || isOwn) then
        text ""

    else
        expandableProfileSection "profile-subscriptions-section"
            "subscriptions"
            "Subscriptions"
            Nothing
            expanded
            SubscriptionsExpandedToggled
            (if List.isEmpty user.marketSubscriptions then
                [ span [ class "profile-subscriptions-empty" ] [ text "No subscriptions." ] ]

             else
                List.map (subscriptionRowView browserTimeZone (isAdmin || isOwn) cancelingSubscriptions) user.marketSubscriptions
            )


{-| A `renewsAt`/`canceledAt`/`serviceTerminatedAt` readout line, shown only when `maybeTimestamp`
is actually set -- e.g. a subscription that's been canceled but whose entitlement hasn't been
revoked yet (see `Components.Market.cancelMarketSubscription`'s own doc) shows both a "Canceled
<date>" and (until `renewMarketSubscriptions` catches up) still its "Renews <date>" line, since
`renewsAt` isn't cleared on cancellation. `label` already includes its own trailing verb, e.g.
"Renews"/"Canceled"/"Service ended".
-}
timestampLineView : String -> SharedTime.BrowserTimeZone -> Maybe Proto.Google.Protobuf.Timestamp -> Html msg
timestampLineView label browserTimeZone maybeTimestamp =
    case maybeTimestamp of
        Just t ->
            span [ class "profile-subscription-row-status" ]
                [ text (label ++ " " ++ SharedTime.formatDate browserTimeZone.zone (timestampToPosix t)) ]

        Nothing ->
            text ""


subscriptionRowView : SharedTime.BrowserTimeZone -> Bool -> Dict String SubmitStatus -> MarketSubscription -> Html Msg
subscriptionRowView browserTimeZone canCancel cancelingSubscriptions subscription =
    div [ class "profile-subscription-row" ]
        [ span [ class "profile-subscription-row-title" ]
            [ text
                (Market.purchaseTypeLabel subscription.type_
                    ++ " · "
                    ++ Market.purchasePeriodLabel subscription.period
                    ++ " · "
                    ++ Market.formatAmount subscription.amount subscription.currency
                )
            ]
        , timestampLineView "Renews" browserTimeZone subscription.renewsAt
        , timestampLineView "Canceled" browserTimeZone subscription.canceledAt
        , timestampLineView "Service ended" browserTimeZone subscription.serviceTerminatedAt
        , if canCancel && subscription.canceledAt == Nothing then
            let
                cancelStatus : SubmitStatus
                cancelStatus =
                    Dict.get subscription.id cancelingSubscriptions |> Maybe.withDefault Idle
            in
            div [ class "profile-subscription-cancel" ]
                [ button
                    [ class "profile-edit-button"
                    , onClick (CancelSubscriptionClicked subscription)
                    , disabled (cancelStatus == Submitting)
                    ]
                    [ text
                        (if cancelStatus == Submitting then
                            "Canceling…"

                         else
                            "Cancel Subscription"
                        )
                    ]
                , editErrorView cancelStatus
                ]

          else
            text ""
        , billingHistoryView browserTimeZone subscription.billingHistory
        ]


{-| One row per `MarketPurchase` in a subscription's `billingHistory` -- amount, date, and (when
Stripe resolved one) the card actually charged/refunded, e.g. "Visa •••• 4242". No purchasing
happens here (per `market.proto`'s own design note) -- this is read-only, same as the rest of
`subscriptionsSection`.
-}
billingHistoryView : SharedTime.BrowserTimeZone -> List MarketPurchase_ -> Html Msg
billingHistoryView browserTimeZone purchases =
    if List.isEmpty purchases then
        text ""

    else
        div [ class "profile-subscription-billing-history" ]
            (purchases |> List.map unwrapMarketPurchase |> List.map (billingHistoryRowView browserTimeZone))


billingHistoryRowView : SharedTime.BrowserTimeZone -> MarketPurchase -> Html Msg
billingHistoryRowView browserTimeZone purchase =
    let
        dateText : String
        dateText =
            purchase.createdAt
                |> Maybe.map (timestampToPosix >> SharedTime.formatDate browserTimeZone.zone)
                |> Maybe.withDefault ""

        amountAndCardText : String
        amountAndCardText =
            case ( purchase.marketPayments, purchase.marketRefunds ) of
                ( payment :: _, _ ) ->
                    Market.formatAmount payment.amount payment.currency ++ cardSuffix payment.method

                ( [], refund :: _ ) ->
                    "Refund " ++ Market.formatAmount refund.amount refund.currency ++ cardSuffix refund.method

                ( [], [] ) ->
                    ""

        cardSuffix : Maybe { a | cardBrand : String, cardLast4 : String } -> String
        cardSuffix maybeMethod =
            maybeMethod |> Maybe.map (\m -> " · " ++ formatCardMethod m) |> Maybe.withDefault ""
    in
    div [ class "profile-subscription-billing-history-row" ]
        [ span [ class "profile-subscription-billing-history-date" ] [ text dateText ]
        , span [ class "profile-subscription-billing-history-amount" ] [ text amountAndCardText ]
        ]


{-| E.g. "Visa •••• 4242" -- works for both `MarketPaymentMethod` and `MarketRefundMethod` (same
`cardBrand`/`cardLast4` fields, structurally, just distinct generated types -- see
`market.proto`'s own doc on why they're kept separate).
-}
formatCardMethod : { a | cardBrand : String, cardLast4 : String } -> String
formatCardMethod method =
    capitalizeWord method.cardBrand ++ " •••• " ++ method.cardLast4


capitalizeWord : String -> String
capitalizeWord word =
    case String.uncons word of
        Just ( first, rest ) ->
            String.cons (Char.toUpper first) rest

        Nothing ->
            word


{-| The Permissions list -- plain badges (plus an Edit button, if `isAdmin`)
when `permissionsEdit == Nothing`, or the removable-badges + Add Permission +
Save/Cancel editor while being edited by an admin. Shown (with just the Edit
button) even with no permissions yet, so an admin can grant the first one.
Collapsed by default (`expanded`, `Model.permissionsExpanded`) behind
`expandableProfileSection`'s own header -- an admin must expand it before the
Edit button (and thus `PermissionsEditClicked`) is even reachable.
-}
permissionsSection : Bool -> Bool -> Maybe PermissionsEdit -> User -> Html Msg
permissionsSection isAdmin expanded maybeEdit user =
    if List.isEmpty user.permissions && not isAdmin then
        text ""

    else
        expandableProfileSection "profile-permissions-section"
            "profile-permissions-section"
            "Permissions"
            Nothing
            expanded
            PermissionsExpandedToggled
            [ case maybeEdit of
                Just edit ->
                    div [ class "profile-permissions-edit" ]
                        [ div [ class "permission-badges" ] (edit.pending |> List.map permissionEditBadge)
                        , div [ class "profile-permissions-add" ]
                            [ select [ onInput PermissionAddSelectionChanged ]
                                (addablePermissions edit.pending
                                    |> List.map
                                        (\permission ->
                                            option
                                                [ value (Users.permissionText permission)
                                                , selected (edit.addSelection == Just permission)
                                                ]
                                                [ text (Users.permissionText permission) ]
                                        )
                                )
                            , button
                                [ class "profile-permission-add-button"
                                , onClick PermissionAddClicked
                                , disabled (edit.addSelection == Nothing)
                                ]
                                [ text "Add Permission" ]
                            ]
                        , div [ class "profile-permissions-actions" ]
                            [ editSaveButton PermissionsSaveClicked edit.status
                            , editCancelButton PermissionsCancelClicked edit.status
                            ]
                        , editErrorView edit.status
                        ]

                Nothing ->
                    div [ class "profile-permissions-view" ]
                        [ div [ class "permission-badges" ]
                            (user.permissions
                                |> List.map (\permission -> span [ class "permission-badge" ] [ text (Users.permissionText permission) ])
                            )
                        , if isAdmin then
                            button [ class "profile-edit-button", onClick PermissionsEditClicked ] [ text "Edit Permissions" ]

                          else
                            text ""
                        ]
            ]


{-| The "Reset Password"/"Delete User" action row -- shown only to `canEdit` viewers (the profile's
own owner, or an Admin), matching both `backend/src/rpcs/authentication/reset_password.rs`'s and
`backend/src/rpcs/users/delete_user.rs`'s own self-or-Admin gates (`canEditProfile`). "Reset
Password" and "Delete User" sit side by side until "Reset Password" is clicked
(`PasswordResetEditClicked`), which swaps both of them out for a New Password field plus Set
Password/Cancel -- all five pieces (`Reset Password`, a visually-hidden username field for password
managers, the password field, the Set/Cancel pair, and `Delete User`) are always rendered, in that
fixed order, in one `Html.form`; which side is showing is animated purely via each direct child's own
`max-width` (see `.profile-account-actions` in profiles.css), exactly the trick
`UI.addAccountServerHeaderRow` uses for the "Add Account/Server..." button vs. its tabs, rather than
either side being mounted/unmounted outright. A real `<form>` (not a `div`), the hidden username
field, and a `type_ "submit"` Set Password button (`Html.Events.onSubmit` always calls
`preventDefault`, so this is safe) are what let Chrome/Safari's own "Save password?" prompt recognize
this as a credential pair worth offering to save, mirroring `UI.formView`'s own Login/Create Account
form. `PasswordResetSaveClicked` itself is a no-op while `model.passwordResetEdit == Nothing` (see
`update`), so wiring every submit here to that one message unconditionally is safe even though the
form's other (non-editing) state also technically contains a `type_ "submit"` button -- it's
`pointer-events: none`/zero-width then, so it's never actually reachable to trigger one.
-}
accountActionsSection : Bool -> Maybe PasswordResetEdit -> User -> Html Msg
accountActionsSection canEdit maybePasswordResetEdit user =
    if not canEdit then
        text ""

    else
        let
            isEditing : Bool
            isEditing =
                maybePasswordResetEdit /= Nothing

            status : SubmitStatus
            status =
                maybePasswordResetEdit |> Maybe.map .status |> Maybe.withDefault Idle

            pendingPassword : String
            pendingPassword =
                maybePasswordResetEdit |> Maybe.map .input |> Maybe.withDefault ""

            submitting : Bool
            submitting =
                status == Submitting
        in
        div [ class "profile-account-actions-section" ]
            [ Html.form
                [ classes [ "profile-account-actions", openClosedClass isEditing ]
                , novalidate True
                , onSubmit PasswordResetSaveClicked
                ]
                [ button
                    [ type_ "button"
                    , classes
                        [ "profile-edit-button"
                        , "border-color-primary-anchor"
                        , "text-color-primary-anchor"
                        , "profile-account-action"
                        , "profile-account-actions-reset-toggle"
                        ]
                    , onClick PasswordResetEditClicked
                    ]
                    [ text "Reset Password" ]

                -- Visually hidden (not `display: none` -- some password managers ignore fields that
                -- way) rather than absent: gives Chrome/Safari's save-password prompt the username to
                -- pair the new password with, without a second visible field cluttering this row.
                -- Left permanently at this row's own default collapsed state (no `.is-open` override
                -- below ever targets it) rather than toggled -- it only needs to *exist* in the form.
                , input
                    [ type_ "text"
                    , name "username"
                    , attribute "autocomplete" "username"
                    , value user.username
                    , readonly True
                    , tabindex -1
                    , class "profile-account-actions-username"
                    ]
                    []
                , div [ classes [ "profile-account-action", "profile-account-actions-password-field" ] ]
                    [ input
                        [ type_ "password"
                        , name "new-password"
                        , attribute "autocomplete" "new-password"
                        , placeholder "New Password"
                        , value pendingPassword
                        , onInput PasswordResetInputChanged
                        , disabled submitting
                        , class "profile-account-actions-password-input"
                        ]
                        []
                    ]
                , div [ classes [ "profile-account-action", "profile-account-actions-buttongroup" ] ]
                    [ button
                        [ type_ "submit"
                        , classes [ "profile-edit-save", "background-color-primary" ]
                        , disabled (submitting || String.isEmpty pendingPassword)
                        ]
                        [ text
                            (if submitting then
                                "Setting…"

                             else
                                "Set Password"
                            )
                        ]
                    , button
                        [ type_ "button"
                        , class "profile-edit-cancel"
                        , onClick PasswordResetCancelClicked
                        , disabled submitting
                        ]
                        [ text "Cancel" ]
                    ]
                , button
                    [ type_ "button"
                    , classes [ "profile-delete-button", "profile-account-action", "profile-account-actions-delete-toggle" ]
                    , onClick DeleteUserClicked
                    ]
                    [ text "Delete User" ]
                ]
            , editErrorView status
            ]


permissionEditBadge : Permission -> Html Msg
permissionEditBadge permission =
    span [ class "permission-badge editable" ]
        [ text (Users.permissionText permission)
        , button
            [ class "permission-remove"
            , onClick (PermissionRemoveClicked permission)
            , title ("Remove " ++ Users.permissionText permission)
            ]
            [ text "×" ]
        ]


{-| The Federated Profiles list -- read-only links (each upgraded with a
`crossCheckBadge` once loaded, see `federatedProfileLink`) when
`federatedProfilesEdit == Nothing`, plus (only for `canEdit`, i.e.
`isOwnProfile`) an Edit button; while being edited, each entry additionally
gets a remove (×) button, and a "Link Account" `<select>`+button lets the
owner federate any of their other signed-in accounts (see
`federableAccounts`) that isn't listed yet. Shown (with just the Edit button)
even with no federated profiles yet, so the owner can add the first one.
-}
federatedProfilesSection : Shared.Model -> Model -> RellmServer -> Bool -> User -> Html Msg
federatedProfilesSection shared model server canEdit user =
    if List.isEmpty user.federatedProfiles && not canEdit then
        text ""

    else
        div [ class "profile-federated" ]
            (h2 [ class "section-title" ] [ text "Federated Profiles" ]
                :: (user.federatedProfiles
                        |> List.map (federatedProfileEntry shared model server user model.federatedProfilesEdit)
                   )
                ++ federatedProfilesEditControls shared model server canEdit user
            )


{-| One federated profile entry: its `federatedProfileLink`, plus (only while
`maybeEdit` is `Just`, i.e. the owner is actively editing) a remove (×)
button that fires `FederatedProfileRemoveClicked` -- mirrors
`permissionEditBadge`, except the remove button sits alongside the link
rather than inside a single badge, since the link itself needs to stay
clickable.
-}
federatedProfileEntry : Shared.Model -> Model -> RellmServer -> User -> Maybe FederatedProfilesEdit -> FederatedAccount -> Html Msg
federatedProfileEntry shared model server user maybeEdit account =
    div [ class "profile-federated-entry" ]
        (federatedProfileLink shared model server user account
            :: (case maybeEdit of
                    Just edit ->
                        [ button
                            [ class "profile-federated-remove"
                            , onClick (FederatedProfileRemoveClicked account)
                            , title ("Unlink " ++ account.userId ++ "@" ++ account.host)
                            , disabled (edit.status == Submitting)
                            ]
                            [ text "×" ]
                        ]

                    Nothing ->
                        []
               )
        )


{-| The Edit button (`federatedProfilesEdit == Nothing`) or the "Link
Account" `<select>`+button/Done/error (while editing) -- `[]` entirely
when `not canEdit`, same "no controls for a viewer who can't act" shape as
`permissionsSection`'s admin gate.
-}
federatedProfilesEditControls : Shared.Model -> Model -> RellmServer -> Bool -> User -> List (Html Msg)
federatedProfilesEditControls shared model server canEdit user =
    if not canEdit then
        []

    else
        case model.federatedProfilesEdit of
            Just edit ->
                let
                    available : List RellmAccount
                    available =
                        federableAccounts shared server user
                in
                [ div [ class "profile-federated-add" ]
                    (if List.isEmpty available then
                        [ span [ class "profile-federated-add-empty" ] [ text "No other linkable accounts available." ] ]

                     else
                        [ select [ onInput FederatedProfileAddSelectionChanged ]
                            (available
                                |> List.map
                                    (\account ->
                                        option
                                            [ value (accountKey account)
                                            , selected (edit.addSelection == Just account)
                                            ]
                                            [ text (accountLabel account) ]
                                    )
                            )
                        , button
                            [ class "profile-permission-add-button"
                            , onClick FederatedProfileAddClicked
                            , disabled (edit.addSelection == Nothing || edit.status == Submitting)
                            ]
                            [ text "Link Account" ]
                        ]
                    )
                , div [ class "profile-permissions-actions" ]
                    [ button [ class "profile-edit-cancel", onClick FederatedProfilesDoneClicked ] [ text "Done" ]
                    ]
                , editErrorView edit.status
                ]

            Nothing ->
                [ button [ class "profile-edit-button", onClick FederatedProfilesEditClicked ] [ text "Edit Federated Profiles" ] ]


{-| One federated profile's link/button -- always links out via
`Users.userIdHref` (the "still just a link" baseline behavior), but once its
`User` has actually loaded (see `kickOffFederatedFetches`), it's upgraded to
show that user's avatar, their username on that server, their real name (if
set), a `crossCheckBadge`, and -- via `federatedServer`'s CSS class, see
`UI.EmittedStylesheet` -- that server's own colors.
-}
federatedProfileLink : Shared.Model -> Model -> RellmServer -> User -> FederatedAccount -> Html Msg
federatedProfileLink shared model server user account =
    let
        maybeFederatedServer : Maybe RellmServer
        maybeFederatedServer =
            RellmServers.rellmServerForHost shared.accounts.servers account.host

        colorClasses : List String
        colorClasses =
            case maybeFederatedServer of
                Just federatedServer ->
                    [ hostnameToCSSClass federatedServer.frontendHost, "background-color-primary" ]

                Nothing ->
                    []
    in
    a
        [ classes ("profile-federated-link" :: colorClasses)
        , href
            (Users.userIdHref shared.basePath
                shared.accounts.mainFrontendHost
                account.host
                account.userId
            )
        ]
        (case ( maybeFederatedServer, Dict.get (federatedKey account) model.federatedProfiles ) of
            ( Just federatedServer, Just (FederatedProfileLoaded federatedUser) ) ->
                [ UI.imageOrInitial [ "profile-federated-avatar" ]
                    federatedUser.username
                    (Users.avatarUrl federatedServer
                        (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts account.host)
                        federatedUser
                    )
                , div [ class "profile-federated-names" ]
                    [ span [ class "profile-federated-username" ] [ text (federatedUser.username ++ "@" ++ account.host) ]
                    , if String.isEmpty (String.trim federatedUser.realName) then
                        text ""

                      else
                        span [ class "profile-federated-realname" ] [ text federatedUser.realName ]
                    ]
                , crossCheckBadge server user federatedUser
                ]

            _ ->
                [ text (account.userId ++ "@" ++ account.host) ]
        )


{-| ✅ if `federatedUser` (fetched from its own server) also lists `user`
back -- one of its own `federatedProfiles` names `server.frontendHost`/
`user.id` -- confirming the two profiles actually link to _each other_, not
just this one linking out. ⚠️ otherwise (e.g. still pending on the other
side, or never confirmed).
-}
crossCheckBadge : RellmServer -> User -> User -> Html Msg
crossCheckBadge server user federatedUser =
    let
        reciprocated : Bool
        reciprocated =
            List.any (\account -> account.host == server.frontendHost && account.userId == user.id)
                federatedUser.federatedProfiles
    in
    if reciprocated then
        span [ class "profile-federated-badge", title "Both profiles link to each other" ] [ text "✅" ]

    else
        span [ class "profile-federated-badge", title "This profile doesn't link back" ] [ text "⚠️" ]



-- SYNC SOURCES


{-| The in-progress edit for `source`'s row -- an existing one from
`es.rowEdits` if the user's touched it, otherwise a fresh, clean one derived
straight from `source`'s own current values (so a first keystroke in either
field has something correct to diff against/build on).
-}
eventSyncRowEditFor : SyncSource -> SyncSourcesState -> EventSyncRowEdit
eventSyncRowEditFor source es =
    Dict.get source.id es.rowEdits
        |> Maybe.withDefault { pendingUrl = eventSyncUrl source, pendingIntervalSeconds = Conversions.int64ToInt source.syncIntervalSeconds, status = Idle }


{-| `source`'s current subscription URL, whichever `Configuration` variant (ICS, RSS, or Atom)
it actually is -- an existing row's kind is never re-chosen in this UI (see `SyncSourceKind`'s
own doc), so its edit form only ever needs the URL text, not which variant it's in.
-}
eventSyncUrl : SyncSource -> String
eventSyncUrl source =
    case source.configuration of
        Just (Configuration.IcsSubscriptionUrl url) ->
            url

        Just (Configuration.RssSubscriptionUrl url) ->
            url

        Just (Configuration.AtomSubscriptionUrl url) ->
            url

        Nothing ->
            ""


syncSourceIsDirty : SyncSource -> EventSyncRowEdit -> Bool
syncSourceIsDirty source edit =
    edit.pendingUrl /= eventSyncUrl source || edit.pendingIntervalSeconds /= Conversions.int64ToInt source.syncIntervalSeconds


mapEventSyncAddForm : (EventSyncAddForm -> EventSyncAddForm) -> SyncSourcesState -> SyncSourcesState
mapEventSyncAddForm fn es =
    { es | addForm = fn es.addForm }


aiProviderRowEditFor : AIProvider -> AIProvidersState -> AIProviderRowEdit
aiProviderRowEditFor provider ap =
    Dict.get provider.id ap.rowEdits
        |> Maybe.withDefault { pendingName = provider.name, pendingApiKey = "", status = Idle }


mapAIProviderAddForm : (AIProviderAddForm -> AIProviderAddForm) -> AIProvidersState -> AIProvidersState
mapAIProviderAddForm fn ap =
    { ap | addForm = fn ap.addForm }


aiProviderGrantFormFor : String -> AIProvidersState -> AIProviderGrantForm
aiProviderGrantFormFor providerId ap =
    Dict.get providerId ap.grantForms
        |> Maybe.withDefault defaultAIProviderGrantForm


aiProviderGrantKey : String -> String -> String
aiProviderGrantKey providerId granteeId =
    providerId ++ ":" ++ granteeId


{-| Labels a row's "delete along with its events" button with exactly what
it'll take with it, so this doubles as the only warning the user gets before
those rows are gone for good. Also used (via `SyncSources.syncedCountsLabel`)
in `UI`'s confirmation dialog for the same source. A row's other, plain
"Delete" button leaves those events/instances alone -- see
`UI.deleteConfirmationModal`'s own message for that case.
-}
syncSourceDeleteButtonLabel : SyncSource -> String
syncSourceDeleteButtonLabel source =
    "Delete along with " ++ SyncSources.syncedCountsLabel source


{-| `canManage` is self-or-Admin (owner may always manage their own; an
Admin may manage anyone's) -- gates the whole section's edit/delete
affordances (a caller with neither shouldn't even see this section, but this
doesn't assume that's already been checked). The add row is shown only on the
viewer's own profile (an Admin still can't create a source _for_ someone
else, see `create_sync_source.rs`) _and_ only if `maybeAccount` holds at
least one of the 3 SyncSource permissions (or `ADMIN`) -- see
`canUseSyncSources` -- mirroring `syncDestinationsSection`'s own
`canUseSyncDestinations` gate, just as an addition on top of the existing
`canManage`/add split rather than replacing it (existing sources should stay
manageable even if the viewer's permissions were later revoked). Collapsed by
default (`model.syncSourcesExpanded`) behind `expandableProfileSection`'s
own header.
-}
syncSourcesSection : Shared.Model -> Model -> Bool -> Maybe RellmAccount -> User -> Html Msg
syncSourcesSection shared model canManage maybeAccount user =
    if not canManage then
        text ""

    else
        let
            canAdd : Bool
            canAdd =
                isOwnProfile maybeAccount user && canUseSyncSources maybeAccount
        in
        expandableProfileSection "sync-sources-section"
            "sync-sources"
            "Sync Sources"
            (Just (refreshButtonView model.syncSourcesExpanded SyncSourcesRefreshClicked model.syncSources.refreshStatus))
            model.syncSourcesExpanded
            SyncSourcesExpandedToggled
            (refreshErrorView model.syncSources.refreshStatus
                :: div [ class "sync-sources-list" ] (syncSourcesContentView model.resolver.targetHost shared.time.browserTimeZone model.syncSources user.syncSources)
                :: (if canAdd then
                        [ syncSourceAddRowView model.resolver.targetHost (availableSyncSourceKinds maybeAccount) model.syncSources.addForm ]

                    else
                        []
                   )
            )


{-| The manual "Refresh" button shared by every section that has one (`SyncSourcesRefreshClicked`/
`AIProvidersRefreshClicked`) -- these overlay just their own field onto the resolved `User` (see
`withResolvedUser`) rather than the whole-profile `refetch` every mutation already triggers, for a
cheaper "did something change on another device" check.

Lives in `expandableProfileSection`'s own header now (its `maybeHeaderAction`), not the collapsible
body -- see that function's own doc. `expanded` only drives the CSS fade/`pointer-events` (via
`openClosedClass`, `profiles.css`'s `.profile-section-refresh.is-open`/`.is-closed`); this button is
always mounted regardless, same "CSS-driven, not conditionally-mounted" convention as the rest of
that header. `stopPropagationAndPreventDefaultOnClick`, not a plain `onClick`, since this sits inside
the same `h2` as the header's own `toggleMsg` handler -- without it, a click here would also bubble up
and collapse the section it just refreshed.

-}
refreshButtonView : Bool -> Msg -> SubmitStatus -> Html Msg
refreshButtonView expanded msg status =
    button
        [ classes [ "profile-section-refresh", openClosedClass expanded ]
        , stopPropagationAndPreventDefaultOnClick msg
        , disabled (status == Submitting)
        ]
        [ text
            (if status == Submitting then
                "Refreshing…"

             else
                "↻ Refresh"
            )
        ]


{-| `refreshButtonView`'s own error message -- unlike the button itself, this stays in the
collapsible body (so it doesn't permanently occupy header space, and so it's only visible once the
section carrying the failure is actually opened).
-}
refreshErrorView : SubmitStatus -> Html Msg
refreshErrorView status =
    case status of
        SubmitFailed err ->
            div [ class "profile-section-refresh-error" ] [ text err ]

        _ ->
            text ""


syncSourcesContentView : String -> SharedTime.BrowserTimeZone -> SyncSourcesState -> List SyncSource -> List (Html Msg)
syncSourcesContentView targetHost browserTimeZone es sources =
    if not (List.isEmpty sources) then
        List.map (syncSourceRowView targetHost browserTimeZone es) sources

    else
        [ div [ class "sync-sources-message" ] [ text "No sync sources yet." ] ]


syncSourceRowView : String -> SharedTime.BrowserTimeZone -> SyncSourcesState -> SyncSource -> Html Msg
syncSourceRowView targetHost browserTimeZone es source =
    let
        edit : EventSyncRowEdit
        edit =
            eventSyncRowEditFor source es

        dirty : Bool
        dirty =
            syncSourceIsDirty source edit

        submitting : Bool
        submitting =
            edit.status == Submitting

        lastSyncedText : String
        lastSyncedText =
            case source.lastSyncedAt of
                Just ts ->
                    SharedTime.formatDateTime browserTimeZone (Conversions.timestampToPosix ts)

                Nothing ->
                    "Never"
    in
    div [ classes [ "sync-source-row", hostnameToCSSClass targetHost, "list-item-bordered-color-primary" ] ]
        [ span [ class "sync-source-kind-label" ] [ text (syncSourceKindLabel (syncSourceKindOf source)) ]
        , input
            [ class "sync-source-url"
            , type_ "text"
            , value edit.pendingUrl
            , placeholder (syncSourceKindLabel (syncSourceKindOf source) ++ " subscription URL")
            , disabled submitting
            , onInput (SyncSourceRowUrlChanged source)
            ]
            []
        , eventSyncIntervalSelect (SyncSourceRowIntervalChanged source) edit.pendingIntervalSeconds submitting
        , div [ class "sync-source-actions" ]
            [ span [ class "sync-source-last-synced" ] [ text ("Last synced: " ++ lastSyncedText) ]
            , if dirty then
                button
                    [ classes [ "sync-source-save", "background-color-nav" ], onClick (SyncSourceRowSaveClicked source), disabled submitting ]
                    [ text
                        (if submitting then
                            "Saving…"

                         else
                            "Save"
                        )
                    ]

              else
                button
                    [ classes [ "sync-source-refresh", "background-color-nav" ], onClick (SyncSourceRowRefreshClicked source), disabled submitting ]
                    [ text
                        (if submitting then
                            "Refreshing…"

                         else
                            "Refresh"
                        )
                    ]
            , button
                [ class "sync-source-delete-plain", onClick (SyncSourceDeleteClicked source False) ]
                [ text "Delete" ]
            , button
                [ class "sync-source-delete", onClick (SyncSourceDeleteClicked source True) ]
                [ text (syncSourceDeleteButtonLabel source) ]
            ]
        , case edit.status of
            SubmitFailed err ->
                div [ class "sync-source-error" ] [ text err ]

            _ ->
                text ""
        ]


syncSourceAddRowView : String -> List SyncSourceKind -> EventSyncAddForm -> Html Msg
syncSourceAddRowView targetHost availableKinds addForm =
    let
        effectiveKind : SyncSourceKind
        effectiveKind =
            effectiveSyncSourceAddKind availableKinds addForm.kind
    in
    div [ classes [ "sync-source-row", "sync-source-add-row", hostnameToCSSClass targetHost ] ]
        [ syncSourceKindSelect SyncSourceAddKindChanged availableKinds effectiveKind (addForm.status == Submitting)
        , input
            [ class "sync-source-url"
            , type_ "text"
            , value addForm.url
            , placeholder ("New " ++ syncSourceKindLabel effectiveKind ++ " subscription URL")
            , disabled (addForm.status == Submitting)
            , onInput SyncSourceAddUrlChanged
            ]
            []
        , eventSyncIntervalSelect SyncSourceAddIntervalChanged addForm.intervalSeconds (addForm.status == Submitting)
        , button
            [ classes [ "sync-source-add", "background-color-primary" ]
            , onClick SyncSourceAddClicked
            , disabled (addForm.status == Submitting || String.isEmpty (String.trim addForm.url))
            ]
            [ text
                (if addForm.status == Submitting then
                    "Adding…"

                 else
                    "+ Create New Source"
                )
            ]
        , case addForm.status of
            SubmitFailed err ->
                div [ class "sync-source-error" ] [ text err ]

            _ ->
                text ""
        ]


{-| `canManage` is self-or-Admin (an Admin may rename/rekey/delete anyone's provider) -- mirrors
`syncSourcesSection`'s own split. `canAdd` is self-only (create -- and, by extension,
grant/revoke, which are owner-only server-side regardless of who's viewing -- is always for the
current user, matching `create_ai_provider.rs`'s "always for `current_user`" behavior), and
also gates the Delete button, since only the owner (or an Admin, already covered by `canManage`)
should be deleting their own providers.
-}
aiProvidersSection : Model -> Bool -> Bool -> User -> Html Msg
aiProvidersSection model canManage canAdd user =
    if not canManage then
        text ""

    else
        expandableProfileSection "ai-model-providers-section"
            "ai-providers"
            "AI Providers"
            (Just (refreshButtonView model.aiProvidersExpanded AIProvidersRefreshClicked model.aiProviders.refreshStatus))
            model.aiProvidersExpanded
            AIProvidersExpandedToggled
            (refreshErrorView model.aiProviders.refreshStatus
                :: div [ class "ai-model-providers-list" ] (aiProvidersContentView canAdd model.aiProviders (ownedAIProviders user))
                :: (if canAdd then
                        [ aiProviderAddRowView model.aiProviders.addForm ]

                    else
                        []
                   )
            )


aiProvidersContentView : Bool -> AIProvidersState -> List AIProvider -> List (Html Msg)
aiProvidersContentView canAdd ap providers =
    if not (List.isEmpty providers) then
        List.map (aiProviderRowView canAdd ap) providers

    else
        [ div [ class "ai-model-providers-message" ] [ text "No AI model providers yet." ] ]


{-| `gemini_credentials`/`openai_credentials`/`digitalocean_credentials` are all creatable (see
`AIProvider`'s own proto doc); this covers all four variants for whenever an
`anthropic_credentials` connect flow is added.
-}
aiProviderProviderLabel : AIProvider -> String
aiProviderProviderLabel provider =
    case provider.provider of
        Just (AIProviderProvider.GeminiCredentials _) ->
            "Gemini"

        Just (AIProviderProvider.OpenaiCredentials _) ->
            "OpenAI"

        Just (AIProviderProvider.AnthropicCredentials _) ->
            "Anthropic"

        Just (AIProviderProvider.DigitaloceanCredentials _) ->
            "DigitalOcean"

        Nothing ->
            "AI Provider"


{-| A row is either its plain read-only display (name, provider type, "API Key: Never shown" --
the server never sends the real key back, same convention as
`ServerInformationPage.FederationTab`'s `facebookAppSecretRow`) or, once "Edit" is clicked (which
just fires `AIProviderRowNameChanged` with the provider's own current name, lazily seeding
`rowEdits` via `aiProviderRowEditFor` -- see that Msg's handling), an editable Name field plus
a blank password-type API Key field (see `AIProviderRowEdit`'s own doc on why blank means
"leave the stored key alone"). Clicking a row's grants-count button toggles its
`AIProviderGrantsView` open/closed (`ap.expandedGrants`).
-}
aiProviderRowView : Bool -> AIProvidersState -> AIProvider -> Html Msg
aiProviderRowView canAdd ap provider =
    let
        editing : Bool
        editing =
            Dict.member provider.id ap.rowEdits

        grantsExpanded : Bool
        grantsExpanded =
            List.member provider.id ap.expandedGrants
    in
    div [ class "ai-model-provider-row-wrapper" ]
        (div [ classes [ "ai-model-provider-row", "list-item-bordered-color-primary" ] ]
            (if editing then
                let
                    edit : AIProviderRowEdit
                    edit =
                        aiProviderRowEditFor provider ap

                    submitting : Bool
                    submitting =
                        edit.status == Submitting
                in
                [ input
                    [ class "ai-model-provider-name"
                    , type_ "text"
                    , value edit.pendingName
                    , placeholder "Name"
                    , disabled submitting
                    , onInput (AIProviderRowNameChanged provider)
                    ]
                    []
                , input
                    [ class "ai-model-provider-api-key"
                    , type_ "password"
                    , value edit.pendingApiKey
                    , placeholder "New API Key (leave blank to keep current)"
                    , disabled submitting
                    , onInput (AIProviderRowApiKeyChanged provider)
                    ]
                    []
                , div [ class "ai-model-provider-actions" ]
                    [ button
                        [ classes [ "ai-model-provider-save", "background-color-nav" ]
                        , onClick (AIProviderRowSaveClicked provider)
                        , disabled (submitting || String.isEmpty (String.trim edit.pendingName))
                        ]
                        [ text
                            (if submitting then
                                "Saving…"

                             else
                                "Save"
                            )
                        ]
                    , button
                        [ class "ai-model-provider-cancel", onClick (AIProviderRowCancelClicked provider), disabled submitting ]
                        [ text "Cancel" ]
                    ]
                , case edit.status of
                    SubmitFailed err ->
                        div [ class "ai-model-provider-error" ] [ text err ]

                    _ ->
                        text ""
                ]

             else
                let
                    deleteStatus : SubmitStatus
                    deleteStatus =
                        Dict.get provider.id ap.deleteStatuses |> Maybe.withDefault Idle

                    grantsLabel : String
                    grantsLabel =
                        String.fromInt (List.length provider.grants)
                            ++ (if List.length provider.grants == 1 then
                                    " grant"

                                else
                                    " grants"
                               )
                in
                [ span [ class "ai-model-provider-name" ] [ text provider.name ]
                , span [ class "ai-model-provider-type" ] [ text (aiProviderProviderLabel provider) ]
                , span [ class "ai-model-provider-key-status" ] [ text "API Key: Never shown" ]
                , div [ class "ai-model-provider-actions" ]
                    [ button
                        [ class "ai-model-provider-edit", onClick (AIProviderRowNameChanged provider provider.name) ]
                        [ text "Edit AI Provider" ]
                    , button
                        [ class "ai-model-provider-grants-toggle", onClick (AIProviderGrantsToggled provider.id) ]
                        [ text grantsLabel ]
                    , if canAdd then
                        button
                            [ class "ai-model-provider-delete"
                            , onClick (AIProviderDeleteClicked provider)
                            , disabled (deleteStatus == Submitting)
                            ]
                            [ text
                                (if deleteStatus == Submitting then
                                    "Deleting…"

                                 else
                                    "Delete"
                                )
                            ]

                      else
                        text ""
                    ]
                , case deleteStatus of
                    SubmitFailed err ->
                        div [ class "ai-model-provider-error" ] [ text err ]

                    _ ->
                        text ""
                ]
            )
            :: (if grantsExpanded then
                    [ aiProviderGrantsView ap provider ]

                else
                    []
               )
        )


{-| A provider's own grant list -- one row per `AIProviderGrant` (via the shared
`aiProviderGrantRowView`, with Edit/Revoke controls since this is always the owner's own view
of their own provider -- see that view's own doc) plus a "grant access" form (grantee user id,
token budget, and allowed models), submitted via `AIProviderGrantClicked`. Clicking an
existing row's Edit button (`AIProviderGrantEditClicked`) pre-fills this same form with that
grant's current values rather than opening a separate editor -- see that Msg's own doc. Only ever
shown once a row's grants toggle is clicked (`AIProviderGrantsToggled`), and only reachable
for the provider's owner in the first place (`GetAIProviders` never returns another user's
providers to a non-Admin caller -- see that RPC's own doc) -- matches
`GrantAIProvider`/`RevokeAIProvider` being owner-only server-side.
-}
aiProviderGrantsView : AIProvidersState -> AIProvider -> Html Msg
aiProviderGrantsView ap provider =
    let
        form : AIProviderGrantForm
        form =
            aiProviderGrantFormFor provider.id ap

        revokeStatusFor : AIProviderGrant -> SubmitStatus
        revokeStatusFor grant =
            let
                granteeId : String
                granteeId =
                    grant.aiModelGrantee |> Maybe.map .userId |> Maybe.withDefault ""
            in
            Dict.get (aiProviderGrantKey provider.id granteeId) ap.revokeStatuses |> Maybe.withDefault Idle
    in
    div [ class "ai-model-provider-grants" ]
        (List.map
            (\grant -> aiProviderGrantRowView { showProviderName = False, canManage = True } provider (revokeStatusFor grant) grant)
            provider.grants
            ++ [ div [ class "ai-model-provider-grant-add-row" ]
                    [ input
                        [ class "ai-model-provider-grant-user-id"
                        , type_ "text"
                        , value form.userId
                        , placeholder "User ID to grant access to"
                        , disabled (form.status == Submitting)
                        , onInput (AIProviderGrantUserIdChanged provider.id)
                        ]
                        []
                    , input
                        [ class "ai-model-provider-grant-tokens"
                        , type_ "number"
                        , value form.tokens
                        , placeholder "Tokens"
                        , disabled (form.status == Submitting)
                        , onInput (AIProviderGrantTokensChanged provider.id)
                        ]
                        []
                    , input
                        [ class "ai-model-provider-grant-models"
                        , type_ "text"
                        , value form.modelNames
                        , placeholder "Models (comma-separated, blank = all)"
                        , disabled (form.status == Submitting)
                        , onInput (AIProviderGrantModelNamesChanged provider.id)
                        ]
                        []
                    , button
                        [ classes [ "ai-model-provider-grant-add", "background-color-primary" ]
                        , onClick (AIProviderGrantClicked provider)
                        , disabled (form.status == Submitting || String.isEmpty (String.trim form.userId) || String.toInt form.tokens == Nothing)
                        ]
                        [ text
                            (if form.status == Submitting then
                                "Granting…"

                             else
                                "Grant Access"
                            )
                        ]
                    , case form.status of
                        SubmitFailed err ->
                            div [ class "ai-model-provider-error" ] [ text err ]

                        _ ->
                            text ""
                    ]
               ]
        )


{-| Shared by both places an `AIProviderGrant` is shown -- nested under its own
`AIProvider` (`aiProviderGrantsView`, above: the owner's view of who they've granted
access to) and standalone in `aiProviderGrantedSection` (below: a grantee's own view of the
access they've been given, possibly on providers they don't own). Always shows the grantee's name,
the models it covers (`AIProviderGrant.modelNames`, or "All models" if empty), and tokens
remaining. `showProviderName` additionally shows which provider this grant is for (needed once it's
not nested under that provider already); `canManage` shows Edit/Revoke controls (only true for the
owner's own view -- `GrantAIProvider`/`RevokeAIProvider` are owner-only server-side
regardless, so a grantee viewing their own access has nothing to manage here).
-}
aiProviderGrantRowView : { showProviderName : Bool, canManage : Bool } -> AIProvider -> SubmitStatus -> AIProviderGrant -> Html Msg
aiProviderGrantRowView config provider revokeStatus grant =
    let
        granteeName : String
        granteeName =
            case grant.aiModelGrantee of
                Just grantee ->
                    grantee.username |> Maybe.withDefault grantee.userId

                Nothing ->
                    "unknown user"

        modelsLabel : String
        modelsLabel =
            if List.isEmpty grant.modelNames then
                "All models"

            else
                String.join ", " grant.modelNames
    in
    div [ class "ai-model-provider-grant-row" ]
        (span [ class "ai-model-provider-grant-user" ] [ text granteeName ]
            :: (if config.showProviderName then
                    [ span [ class "ai-model-provider-grant-provider-name" ] [ text provider.name ] ]

                else
                    []
               )
            ++ [ span [ class "ai-model-provider-grant-models" ] [ text ("Models: " ++ modelsLabel) ]
               , span [ class "ai-model-provider-grant-tokens" ]
                    [ text
                        (String.fromInt (Conversions.int64ToInt grant.tokensRemaining)
                            ++ " tokens remaining"
                            ++ (if Conversions.int64ToInt grant.overage > 0 then
                                    " (" ++ String.fromInt (Conversions.int64ToInt grant.overage) ++ " over budget)"

                                else
                                    ""
                               )
                        )
                    ]
               ]
            ++ (if config.canManage then
                    [ div [ class "ai-model-provider-grant-actions" ]
                        [ button [ class "ai-model-provider-grant-edit", onClick (AIProviderGrantEditClicked provider grant) ] [ text "Edit Grant" ]
                        , button
                            [ class "ai-model-provider-grant-revoke"
                            , onClick (AIProviderRevokeClicked provider grant)
                            , disabled (revokeStatus == Submitting)
                            ]
                            [ text
                                (if revokeStatus == Submitting then
                                    "Revoking…"

                                 else
                                    "Revoke"
                                )
                            ]
                        ]
                    , case revokeStatus of
                        SubmitFailed err ->
                            div [ class "ai-model-provider-error" ] [ text err ]

                        _ ->
                            text ""
                    ]

                else
                    []
               )
        )


{-| "Gemini"/"OpenAI" -- `addAIProviderTypeLabel`'s own counterpart for the add-form's `<select>`
`value`s (`AIProviderAddProviderTypeChanged`'s own string decoding), kept distinct from
`aiProviderProviderLabel` (which reads an already-created `AIProvider`'s real `provider`,
not this in-progress form's own choice of what to create).
-}
addAIProviderTypeValue : AddAIProviderType -> String
addAIProviderTypeValue providerType =
    case providerType of
        AddGeminiProvider ->
            "gemini"

        AddOpenAIProvider ->
            "openai"

        AddDigitalOceanProvider ->
            "digitalocean"


addAIProviderTypeLabel : AddAIProviderType -> String
addAIProviderTypeLabel providerType =
    case providerType of
        AddGeminiProvider ->
            "Gemini"

        AddOpenAIProvider ->
            "OpenAI"

        AddDigitalOceanProvider ->
            "DigitalOcean"


aiProviderAddRowView : AIProviderAddForm -> Html Msg
aiProviderAddRowView addForm =
    div [ classes [ "ai-model-provider-row", "ai-model-provider-add-row" ] ]
        [ select
            [ class "ai-model-provider-add-type"
            , disabled (addForm.status == Submitting)
            , onInput AIProviderAddProviderTypeChanged
            ]
            (List.map
                (\providerType ->
                    option
                        [ value (addAIProviderTypeValue providerType)
                        , selected (providerType == addForm.providerType)
                        ]
                        [ text (addAIProviderTypeLabel providerType) ]
                )
                [ AddGeminiProvider, AddOpenAIProvider, AddDigitalOceanProvider ]
            )
        , input
            [ class "ai-model-provider-name"
            , type_ "text"
            , value addForm.name
            , placeholder "Name"
            , disabled (addForm.status == Submitting)
            , onInput AIProviderAddNameChanged
            ]
            []
        , input
            [ class "ai-model-provider-api-key"
            , type_ "password"
            , value addForm.apiKey
            , placeholder (addAIProviderTypeLabel addForm.providerType ++ " API Key")
            , disabled (addForm.status == Submitting)
            , onInput AIProviderAddApiKeyChanged
            ]
            []
        , button
            [ classes [ "ai-model-provider-add", "background-color-primary" ]
            , onClick AIProviderAddClicked
            , disabled (addForm.status == Submitting || String.isEmpty (String.trim addForm.name) || String.isEmpty (String.trim addForm.apiKey))
            ]
            [ text
                (if addForm.status == Submitting then
                    "Adding…"

                 else
                    "+ Add " ++ addAIProviderTypeLabel addForm.providerType ++ " Provider"
                )
            ]
        , case addForm.status of
            SubmitFailed err ->
                div [ class "ai-model-provider-error" ] [ text err ]

            _ ->
                text ""
        ]


{-| "AI Model Access" -- the access _granted to_ this profile's own user, on any provider (their
own or someone else's), as opposed to `aiProvidersSection` (the providers _they themselves_
own). Read-only: renders each `(AIProvider, AIProviderGrant)` pair (see
`grantedAIModelAccess`) via the same `aiProviderGrantRowView` used under a provider's own row,
just with `showProviderName = True` (there's no parent `AIProvider` here to already show it)
and `canManage = False` (granting/revoking one's own access isn't something a grantee can do -- see
that view's own doc). `canView` mirrors `aiProvidersSection`'s own `canManage` (self-or-Admin,
matching `GetAIProviders`' own gate).
-}
aiProviderGrantedSection : Model -> Bool -> User -> Html Msg
aiProviderGrantedSection model canView user =
    if not canView then
        text ""

    else
        expandableProfileSection "ai-model-providers-section"
            "ai-models"
            "AI Model Access"
            Nothing
            model.aiProviderGrantsExpanded
            AIProviderGrantsSectionToggled
            [ div [ class "ai-model-providers-list" ] (aiProviderGrantedContentView (grantedAIModelAccess user)) ]


aiProviderGrantedContentView : List ( AIProvider, AIProviderGrant ) -> List (Html Msg)
aiProviderGrantedContentView granted =
    if not (List.isEmpty granted) then
        List.map (\( provider, grant ) -> aiProviderGrantRowView { showProviderName = True, canManage = False } provider Idle grant) granted

    else
        [ div [ class "ai-model-providers-message" ] [ text "No AI model access granted to you yet." ] ]


{-| Unlike `syncSourcesSection`, this is shown (or not) as a single all-or-nothing check --
own profile, holding any of the 10 `SYNC_EVENTS_TO_*`/`SYNC_POSTS_TO_*` permission pairs (or
`ADMIN`) (see `canUseSyncDestinations`) -- rather than a separate `canManage`/`canAdd` split
(individual platform buttons within the section apply their own, more specific gate -- see
`platformPickerView`). There's no "view-only for an Admin visiting someone else's profile" case the
way sources have: a linked destination is always the _caller's own_
(`create_sync_destination.rs` always creates for `current_user`), so there's nothing for
anyone else to usefully see here.
-}
syncDestinationsSection : Shared.Model -> Model -> Maybe RellmAccount -> User -> Html Msg
syncDestinationsSection shared model maybeAccount user =
    if not (isOwnProfile maybeAccount user && canUseSyncDestinations maybeAccount) then
        text ""

    else
        expandableProfileSection "sync-destinations-section"
            "sync-destinations"
            "Sync Destinations"
            Nothing
            model.syncDestinationsExpanded
            SyncDestinationsExpandedToggled
            [ div [ class "sync-destinations-list" ] (syncDestinationsContentView model.syncDestinations user.syncDestinations)
            , platformConnectView shared model.resolver.targetHost maybeAccount model.syncDestinations
            ]


{-| Reads `destinations` straight off the profile's already-resolved `User`
(`user.syncDestinations`, self-or-Admin gated server-side -- see
`protos/users.proto`'s own doc on that field) rather than a separately
fetched/tracked status -- no "Loading…" state needed, same as nothing
elsewhere shows a "loading permissions" spinner for other `User` fields.
-}
syncDestinationsContentView : SyncDestinationsState -> List SyncDestination -> List (Html Msg)
syncDestinationsContentView ed destinations =
    if List.isEmpty destinations then
        [ div [ class "sync-destinations-message" ] [ text "No sync destinations linked yet." ] ]

    else
        List.map (syncDestinationRowView ed) destinations


syncDestinationRowView : SyncDestinationsState -> SyncDestination -> Html Msg
syncDestinationRowView ed destination =
    let
        platformLabel : String
        platformLabel =
            case destination.configuration of
                Just (DestinationConfiguration.FacebookPage _) ->
                    "Facebook Page"

                Just (DestinationConfiguration.InstagramAccount _) ->
                    "Instagram"

                Just (DestinationConfiguration.MastodonAccount _) ->
                    "Mastodon"

                Just (DestinationConfiguration.BlueskyAccount _) ->
                    "Bluesky"

                Just (DestinationConfiguration.XTwitterAccount _) ->
                    "X (Twitter)"

                Just (DestinationConfiguration.ThreadsAccount _) ->
                    "Threads"

                Nothing ->
                    "Sync Destination"

        destinationName : String
        destinationName =
            case destination.configuration of
                Just (DestinationConfiguration.FacebookPage page) ->
                    page.pageName

                Just (DestinationConfiguration.InstagramAccount account) ->
                    "@" ++ account.username

                Just (DestinationConfiguration.MastodonAccount account) ->
                    account.username ++ "@" ++ account.instanceHost

                Just (DestinationConfiguration.BlueskyAccount account) ->
                    account.handle

                Just (DestinationConfiguration.XTwitterAccount account) ->
                    "@" ++ account.username

                Just (DestinationConfiguration.ThreadsAccount account) ->
                    "@" ++ account.username

                Nothing ->
                    platformLabel

        count : Int
        count =
            destination.syncedOccasionCount |> Maybe.map Conversions.int64ToInt |> Maybe.withDefault 0

        deleting : Bool
        deleting =
            Dict.get destination.id ed.deleteStatuses == Just Submitting
    in
    div [ class "sync-destination-row list-item-bordered-color-primary" ]
        [ span [ class "sync-destination-name" ] [ text destinationName ]
        , span [ class "sync-destination-count" ] [ text (pluralCount count "event" ++ " synced") ]
        , button
            [ class "sync-destination-delete", onClick (SyncDestinationDeleteClicked destination), disabled deleting ]
            [ text
                (if deleting then
                    "Unlinking…"

                 else
                    "Unlink " ++ platformLabel
                )
            ]
        , case Dict.get destination.id ed.deleteStatuses of
            Just (SubmitFailed err) ->
                div [ class "sync-destination-error" ] [ text err ]

            _ ->
                text ""
        ]


pluralCount : Int -> String -> String
pluralCount count noun =
    String.fromInt count
        ++ " "
        ++ noun
        ++ (if count == 1 then
                ""

            else
                "s"
           )


{-| Renders whichever of the three connect flows (`login`/`mastodon`/`bluesky`) is currently in
progress, or -- if none are -- `platformPickerView`'s row of platform buttons. At most one flow is
ever in progress at a time (starting one doesn't clear the others' state, but the UI only ever
lets one be started, since the picker itself is hidden once any is in progress) -- see
`SyncDestinationsState`'s own doc.
-}
platformConnectView : Shared.Model -> String -> Maybe RellmAccount -> SyncDestinationsState -> Html Msg
platformConnectView shared host maybeAccount ed =
    if ed.login /= FacebookLoginNotStarted then
        facebookLoginView ed.login

    else if ed.mastodon /= MastodonConnectNotStarted then
        mastodonConnectView ed.mastodon

    else if ed.bluesky /= BlueskyConnectNotStarted then
        blueskyConnectView ed.bluesky

    else if ed.threads /= ThreadsConnectNotStarted then
        threadsConnectView ed.threads

    else if ed.xTwitter /= XTwitterConnectNotStarted then
        xTwitterConnectView ed.xTwitter

    else
        platformPickerView shared host maybeAccount


{-| The platform picker row -- one button per platform the viewer can use (each gated on that
platform's own `SYNC_EVENTS_TO_*`/`SYNC_POSTS_TO_*` permission pair, mirroring
`hasSyncToFacebookPermission` and friends; Facebook/Instagram/Threads additionally require the
server having a Facebook App configured, see `facebookAppConfigured` -- Threads rides on that same
Meta App; X (Twitter) requires its own separate app, see `xTwitterAppConfigured`).
-}
platformPickerView : Shared.Model -> String -> Maybe RellmAccount -> Html Msg
platformPickerView shared host maybeAccount =
    let
        facebookAppReady : Bool
        facebookAppReady =
            facebookAppConfigured shared host

        xTwitterAppReady : Bool
        xTwitterAppReady =
            xTwitterAppConfigured shared host
    in
    div [ class "sync-destination-platform-picker" ]
        [ platformButton (hasSyncToFacebookPermission maybeAccount && facebookAppReady) FacebookLoginClicked "Sign in to Facebook Page"
        , platformButton (hasSyncToInstagramPermission maybeAccount && facebookAppReady) InstagramLoginClicked "Sign in to Instagram"
        , platformButton (hasSyncToMastodonPermission maybeAccount) MastodonConnectClicked "Connect Mastodon"
        , platformButton (hasSyncToBlueskyPermission maybeAccount) BlueskyConnectClicked "Connect Bluesky"
        , platformButton (hasSyncToThreadsPermission maybeAccount && facebookAppReady) ThreadsLoginClicked "Connect Threads"
        , platformButton (hasSyncToXTwitterPermission maybeAccount && xTwitterAppReady) XTwitterLoginClicked "Connect X (Twitter)"
        ]


platformButton : Bool -> Msg -> String -> Html Msg
platformButton visible msg buttonText =
    if visible then
        button
            [ classes [ "sync-destination-login", "background-color-primary" ], onClick msg ]
            [ text buttonText ]

    else
        text ""


{-| Every step of `FacebookLoginStatus` (see its own doc) -- covers both the Facebook and
Instagram flows, since they share this one popup/page-list state machine.
-}
facebookLoginView : FacebookLoginStatus -> Html Msg
facebookLoginView login =
    case login of
        FacebookLoginNotStarted ->
            text ""

        FacebookLoginPopupOpen platform ->
            div [ class "sync-destinations-message" ] [ text ("Waiting for " ++ connectPlatformLabel platform ++ "…") ]

        FacebookLoginFetchingPages _ _ ->
            div [ class "sync-destinations-message" ] [ text "Loading your Facebook Pages…" ]

        FacebookLoginChoosingPage _ _ pages ->
            div [ class "sync-destination-page-picker" ]
                (div [ class "sync-destinations-message" ] [ text "Choose a Page to link:" ]
                    :: List.map
                        (\page ->
                            button
                                [ class "sync-destination-page-option", onClick (FacebookPageChosen page) ]
                                [ text page.name ]
                        )
                        pages
                )

        FacebookLoginNoPagesFound ->
            div [ class "sync-destinations-message" ] [ text "That Facebook account doesn't manage any Pages." ]

        FacebookLoginLinking platform page ->
            div [ class "sync-destinations-message" ] [ text ("Linking " ++ page.name ++ " for " ++ connectPlatformLabel platform ++ "…") ]

        FacebookLoginFailed err ->
            div [ class "sync-destination-error" ] [ text err ]


connectPlatformLabel : FacebookConnectPlatform -> String
connectPlatformLabel platform =
    case platform of
        ConnectFacebook ->
            "Facebook"

        ConnectInstagram ->
            "Instagram"


{-| The Mastodon "Connect" form -- instance host + Personal Access Token, see
`MastodonConnectStatus`'s own doc.
-}
mastodonConnectView : MastodonConnectStatus -> Html Msg
mastodonConnectView status =
    case status of
        MastodonConnectNotStarted ->
            text ""

        MastodonConnectEditing form ->
            div [ class "sync-destination-connect-form" ]
                [ div [ class "sync-destinations-message" ] [ text "Connect a Mastodon account:" ]
                , input
                    [ class "sync-destination-connect-input"
                    , placeholder "Instance host, e.g. mastodon.world"
                    , value form.instanceHost
                    , onInput MastodonInstanceHostChanged
                    ]
                    []
                , input
                    [ class "sync-destination-connect-input"
                    , type_ "password"
                    , placeholder "Personal Access Token"
                    , value form.accessToken
                    , onInput MastodonAccessTokenChanged
                    ]
                    []
                , button
                    [ classes [ "sync-destination-login", "background-color-primary" ]
                    , onClick MastodonConnectSubmitted
                    , disabled (String.isEmpty form.instanceHost || String.isEmpty form.accessToken)
                    ]
                    [ text "Connect" ]
                , button [ class "sync-destination-connect-cancel", onClick MastodonConnectCancelled ] [ text "Cancel" ]
                ]

        MastodonConnectLinking form ->
            div [ class "sync-destinations-message" ] [ text ("Linking " ++ form.instanceHost ++ "…") ]

        MastodonConnectFailed err ->
            div []
                [ div [ class "sync-destination-error" ] [ text err ]
                , button [ class "sync-destination-connect-cancel", onClick MastodonConnectClicked ] [ text "Try Again" ]
                ]


{-| The Bluesky "Connect" form -- handle + "App Password", see `BlueskyConnectStatus`'s own doc.
-}
blueskyConnectView : BlueskyConnectStatus -> Html Msg
blueskyConnectView status =
    case status of
        BlueskyConnectNotStarted ->
            text ""

        BlueskyConnectEditing form ->
            div [ class "sync-destination-connect-form" ]
                [ div [ class "sync-destinations-message" ] [ text "Connect a Bluesky account:" ]
                , input
                    [ class "sync-destination-connect-input"
                    , placeholder "Handle, e.g. jon.bsky.social"
                    , value form.handle
                    , onInput BlueskyHandleChanged
                    ]
                    []
                , input
                    [ class "sync-destination-connect-input"
                    , type_ "password"
                    , placeholder "App Password"
                    , value form.appPassword
                    , onInput BlueskyAppPasswordChanged
                    ]
                    []
                , button
                    [ classes [ "sync-destination-login", "background-color-primary" ]
                    , onClick BlueskyConnectSubmitted
                    , disabled (String.isEmpty form.handle || String.isEmpty form.appPassword)
                    ]
                    [ text "Connect" ]
                , button [ class "sync-destination-connect-cancel", onClick BlueskyConnectCancelled ] [ text "Cancel" ]
                ]

        BlueskyConnectLinking form ->
            div [ class "sync-destinations-message" ] [ text ("Linking " ++ form.handle ++ "…") ]

        BlueskyConnectFailed err ->
            div []
                [ div [ class "sync-destination-error" ] [ text err ]
                , button [ class "sync-destination-connect-cancel", onClick BlueskyConnectClicked ] [ text "Try Again" ]
                ]


{-| Every step of `ThreadsConnectStatus` (see its own doc) -- much shorter than
`facebookLoginView` since there's no page-picker step.
-}
threadsConnectView : ThreadsConnectStatus -> Html Msg
threadsConnectView status =
    case status of
        ThreadsConnectNotStarted ->
            text ""

        ThreadsConnectPopupOpen ->
            div [ class "sync-destinations-message" ] [ text "Waiting for Threads…" ]

        ThreadsConnectLinking ->
            div [ class "sync-destinations-message" ] [ text "Linking Threads…" ]

        ThreadsConnectFailed err ->
            div []
                [ div [ class "sync-destination-error" ] [ text err ]
                , button [ class "sync-destination-connect-cancel", onClick ThreadsLoginClicked ] [ text "Try Again" ]
                ]


{-| Every step of `XTwitterConnectStatus` (see its own doc) -- mirrors `threadsConnectView`
exactly.
-}
xTwitterConnectView : XTwitterConnectStatus -> Html Msg
xTwitterConnectView status =
    case status of
        XTwitterConnectNotStarted ->
            text ""

        XTwitterConnectPopupOpen ->
            div [ class "sync-destinations-message" ] [ text "Waiting for X (Twitter)…" ]

        XTwitterConnectLinking ->
            div [ class "sync-destinations-message" ] [ text "Linking X (Twitter)…" ]

        XTwitterConnectFailed err ->
            div []
                [ div [ class "sync-destination-error" ] [ text err ]
                , button [ class "sync-destination-connect-cancel", onClick XTwitterLoginClicked ] [ text "Try Again" ]
                ]


eventSyncIntervalSelect : (Int -> Msg) -> Int -> Bool -> Html Msg
eventSyncIntervalSelect onChange selectedSeconds disabledAttr =
    select
        [ class "sync-source-interval"
        , disabled disabledAttr
        , onInput (\s -> onChange (String.toInt s |> Maybe.withDefault selectedSeconds))
        ]
        (SyncSources.intervalOptions
            |> List.map
                (\( seconds, label ) ->
                    option [ value (String.fromInt seconds), selected (seconds == selectedSeconds) ] [ text label ]
                )
        )


{-| The new-source "type" selector (`syncSourceAddRowView` only -- an existing row's kind is
never re-chosen, see `SyncSourceKind`'s own doc) picking which `Configuration` variant the
URL below it will be saved as. Only offers `availableKinds` (see `availableSyncSourceKinds`) --
a viewer with just the RSS permission, say, never sees "iCal"/"Atom" options they couldn't
actually submit.
-}
syncSourceKindSelect : (SyncSourceKind -> Msg) -> List SyncSourceKind -> SyncSourceKind -> Bool -> Html Msg
syncSourceKindSelect onChange availableKinds selectedKind disabledAttr =
    select
        [ class "sync-source-kind"
        , disabled disabledAttr
        , onInput (\s -> onChange (syncSourceKindFromLabel s))
        ]
        (availableKinds
            |> List.map
                (\kind ->
                    option [ value (syncSourceKindLabel kind), selected (kind == selectedKind) ] [ text (syncSourceKindLabel kind) ]
                )
        )
