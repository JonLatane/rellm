module Shared.AccountsPanel exposing
    ( AcceptedCreateAccount
    , AccountForm
    , AccountOrServerFormType(..)
    , AddServerForm
    , BlueskyConnectForm
    , CombinedAccountItem(..)
    , CombinedServerFeedItem(..)
    , FormStatus(..)
    , MaybeAccountServer
    , Model
    , Msg(..)
    , NewAccountType(..)
    , PendingCreateAccount
    , Tab(..)
    , accountRowDomId
    , activeAddAccountServerFormType
    , combinedAccountItemKey
    , combinedAccountItems
    , combinedServerFeedItemKey
    , combinedServerFeedItems
    , connectableMastodonServers
    , createAccountModalBodyId
    , currentFocusedAccountContactMethods
    , enabledAccounts
    , enabledServers
    , freshFocusedAccount
    , grpcErrorToString
    , hasAdminAccount
    , init
    , isFocusedAccount
    , isKnownServer
    , isMainServer
    , mainServerTheme
    , mastodonServerFor
    , performWithAccountServer
    , performWithOptionalAccountServer
    , recommendedFederatedServers
    , recommendedMastodonServers
    , serverFeedItemChipDomId
    , shouldShowAddAccountForm
    , subscriptions
    , unreachableAccountHosts
    , update
    , updateServerConfig
    )

{-| Everything behind the Accounts Panel: known servers, signed-into accounts,
the login/add-server forms, and the connectivity logic (host negotiation,
CDN backend\_host discovery) that gets you from a typed-in hostname to a
working connection.
-}

import Animation
import Browser.Dom as Dom
import Dict exposing (Dict)
import Grpc
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Ports
import Process
import Proto.Rellm exposing (AccessTokenResponse, ContactMethod, FederatedServer, GetPushSubscriptionStatusResponse, MastodonServer, PushSubscription, RefreshTokenResponse, ServerConfiguration, ServerInfo, User)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Proto.Rellm.WebUserInterface exposing (WebUserInterface)
import Request exposing (Request)
import Set
import Shared.AccountsPanel.AdminTab as AdminTab
import Shared.AccountsPanel.BlueskyAccounts as BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.DebugTab as DebugTab
import Shared.AccountsPanel.MastodonAccounts as MastodonAccounts exposing (MastodonAccount)
import Shared.AccountsPanel.MastodonServers as MastodonServers exposing (BrowsedMastodonInstance, MastodonInstanceInfo)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount, RellmContactMethods, contactMethodEditValue, contactMethodVisibilityFromText, rellmAccountId)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (Branding, Connection, PersistedRellmServer, RellmServer)
import Shared.AccountsPanel.SortOrder as SortOrder
import Shared.Conversions as Conversions
import Task exposing (Task)
import Time
import UI.Classes exposing (escapeCSSClass)
import UI.Flip
import UI.ServerTheme


type alias Model =
    { accounts : List RellmAccount
    , servers : List RellmServer
    , accountForm : AccountForm
    , addServerForm : AddServerForm
    , showAccountsPanel : Bool

    -- Whether the "X Recommended Servers..." button (see `UI.recommendedServersStrip`)
    -- has been expanded into its horizontally-scrollable strip of chips.
    -- Purely session-transient UI state, not persisted -- reset to `False`
    -- whenever the Accounts Panel closes (`CloseAccountsPanel`/
    -- `ToggleAccountsPanel`), so it always starts collapsed again next time
    -- the panel opens, same as `addAccountFormExpanded` starting points but
    -- unconditionally rather than only-if-idle.
    , recommendedServersExpanded : Bool

    -- Once-fetched `ServerConfiguration`s (as `RellmServer`s, so the same
    -- `RellmServers.rellmServerNameAndLogo`/branding machinery renders them) for hosts
    -- currently recommended via `recommendedFederatedServers` -- keyed by
    -- `frontendHost`, populated lazily by `ToggleRecommendedServersExpanded`
    -- (a fresh disconnected placeholder inserted immediately, replaced once
    -- `GotRecommendedServerConfig` resolves) rather than eagerly for every
    -- federated server up front. Cleared for a host once it stops being
    -- recommended by getting added (`GotRecommendedServerAddResult`) or by
    -- being removed again (`FinishRemoveServer`, which also immediately
    -- refetches if the strip is still open) -- otherwise the host would
    -- reappear in the strip still pointing at stale/placeholder branding.
    -- Simply closing the panel leaves it in place -- harmless, and means
    -- reopening the strip doesn't re-fetch hosts it already has cached.
    , recommendedServerConnections : Dict String RellmServer

    -- The account whose avatar menu (Media/Sync Sources/Sync Destinations/AI Models -- see
    -- `UI.accountAvatarMenuView`) is currently expanded open, if any -- toggled by clicking that
    -- account's avatar (`AccountAvatarClicked`), and cleared by picking a menu item or closing the
    -- whole Accounts Panel (`CloseAccountsPanel`/`ToggleAccountsPanel`). Only one account's menu can
    -- be open at a time, mirroring `addAccountServerFormType`'s own single-`Maybe` reasoning. Not a
    -- floating popover -- expands the account row itself taller to hold the menu (see
    -- `ui/accounts_panel.css`'s `.account-avatar-menu`), so it needs no positioning/z-index/overflow-
    -- escape logic of its own; the row's existing FLIP-collapse height transition does that for free.
    , focusedAccount : Maybe RellmAccount

    -- `focusedAccount`'s own nested "Contact Methods" item state (see `UI.accountAvatarMenuView`'s
    -- "Contact Methods" item, and `RellmContactMethods`'s own doc for why it's one record rather
    -- than several separate fields here). Kept in lockstep with `focusedAccount` -- `Just
    -- RellmAccounts.emptyRellmContactMethods` whenever that's `Just _`, `Nothing` whenever it's
    -- `Nothing` (see `resetFocusedAccountContactMethods`, run alongside every place `focusedAccount`
    -- itself changes: `AccountAvatarClicked`/`CloseFocusedAccount`/`CloseAccountsPanel`/
    -- `ToggleAccountsPanel`) -- editing only ever targets whichever account's menu is currently open.
    , focusedAccountContactMethods : Maybe RellmContactMethods

    -- Which tab of the merged "Add Account/Server" form (see
    -- `AccountOrServerFormType`) is showing, once there's at least one account
    -- already -- `Nothing` collapses the whole area behind its "Add
    -- Account/Server..." button (see `shouldShowAddAccountForm`), covering
    -- what `addAccountFormExpanded`/`mastodonServerFormOpen`/
    -- `blueskyConnectForm`'s own `Maybe`-as-open/closed each used to track
    -- independently -- only one of the three tabs can be open at a time
    -- anyway, so one shared `Maybe` replaces all three. Irrelevant (the form
    -- always shows, defaulting to `RellmServerFormType` -- see
    -- `activeAddAccountServerFormType`) when `accounts` is empty.
    , addAccountServerFormType : Maybe AccountOrServerFormType

    -- Once the Username field names a known server, whether (and which of)
    -- "Log In"/"Create Account" has been picked -- see `ChooseLoginClicked`/
    -- `ChooseCreateAccountClicked`. `Nothing` while still at the
    -- Username-only step, before either's been picked: the Password field
    -- (see `UI.addAccountForm`) only renders once this is `Just _`, so its
    -- `autocomplete`/`name` can be set to "new-password" or "current-password"
    -- up front, rather than the field existing from the start with an
    -- autocomplete hint that's only a guess. For Log In, set the moment
    -- "Log In" is clicked; for Create Account, only once the policy
    -- confirmation modal's been accepted (`ConfirmCreateAccountClicked`) --
    -- see `acceptedCreateAccount`. Once set, the same button (now alongside a
    -- "<- Back" button, `NewAccountBackClicked`) actually submits via
    -- `LoginClicked`/`CreateAccountClicked`. Reset to `Nothing` by
    -- `NewAccountBackClicked`, a successful `GotAuthResult`, or the RellmServer
    -- field changing (`setServerField`).
    , newAccountType : Maybe NewAccountType

    -- Set once `ChooseCreateAccountClicked` (the Username-step "Create
    -- Account" button) has resolved the target server's configuration, until
    -- the user accepts or cancels -- see `UI.createAccountConfirmationModal`.
    -- `Nothing` the rest of the time. Accepting moves the target
    -- server/username into `acceptedCreateAccount` and reveals the Password
    -- field; nothing here carries a password -- it doesn't exist yet.
    , createAccountConfirmation : Maybe PendingCreateAccount

    -- Set once the policy confirmation modal's been accepted
    -- (`ConfirmCreateAccountClicked`, "Accept and Continue") -- from then on,
    -- until the real `CreateAccount` RPC fires (`CreateAccountClicked`, now
    -- the Password field's own submit) or the flow's abandoned, this is what
    -- that RPC reads its server/username from (see `AcceptedCreateAccount`).
    -- `Nothing` the rest of the time.
    , acceptedCreateAccount : Maybe AcceptedCreateAccount

    -- The host this app is actually being viewed from (immutable for the
    -- session -- it's a plain SPA reload to change it).
    , browsingHost : String

    -- Whether `browsingHost`'s own `ServerConfiguration` request has settled,
    -- success or failure alike -- flips `True` exactly once, in
    -- `GotMainServerResult` (a first-ever visit to this host) or
    -- `GotReconnectResult` for `browsingHost` specifically (an already-known
    -- host, reconnected via `init`'s ordinary per-server sweep). Drives
    -- `Shared.splashHiddenCmd`, which hides `index.html`'s `#splash` overlay
    -- once this is `True` -- the app can still be used before every *other*
    -- server's config has loaded, but not before this one's, since that's
    -- what supplies the page's own theming.
    , browsingHostConfigResolved : Bool

    -- The server that host resolves to, once known: usually `browsingHost`
    -- itself, but corrected to a CDN's public `frontendHost` if `browsingHost`
    -- turns out to be a backend host presenting a different public identity
    -- (see `RellmServers.resolvedFrontendHost`). A mismatch between the two is shown as a
    -- warning (`UI.hostMismatchWarning`), which the user can click to force it
    -- back to `browsingHost` (`ResetMainFrontendHost`) -- same as the brief
    -- window before the main server's first connect resolves, this leaves
    -- `mainFrontendHost` pointing at a host with no `servers` entry until a
    -- reconnect adds one, which `UI.mainServer` already tolerates. This is
    -- also (ordinarily) the one server entry the user isn't allowed to remove
    -- from the Accounts Panel -- see `MainServerSelected` for how an admin
    -- can change it.
    , mainFrontendHost : String

    -- In-flight/settling FLIP slide animations for the combined account list (Rellm accounts,
    -- connected Mastodon accounts, and connected Bluesky accounts together -- see
    -- `CombinedAccountItem`) reordered via `MoveAccountItemUpClicked`/`MoveAccountItemDownClicked`,
    -- keyed by `combinedAccountItemKey`. An item with no entry here (the common case) just renders
    -- at rest.
    , moveAnimations : Dict String (UI.Flip.MoveState Msg)

    -- Same as `moveAnimations`, but for the combined server feed strip (servers and browsed
    -- Mastodon instances together -- see `CombinedServerFeedItem`) reordered via
    -- `MoveServerFeedItemLeftClicked`/`MoveServerFeedItemRightClicked`, keyed by
    -- `combinedServerFeedItemKey`. Kept separate from `moveAnimations` (rather than one dict shared
    -- by both lists) since they're two independent keyed lists -- an account item key and a server
    -- feed item key happening to collide as plain strings would otherwise cross-wire their
    -- animations.
    , serverMoveAnimations : Dict String (UI.Flip.MoveState Msg)

    -- Each combined account item's enter/leave `UI.Flip.State` (see `CombinedAccountItem`), keyed
    -- by `combinedAccountItemKey` -- `update`'s very last step (see `syncItemAnimations`) is always
    -- `UI.Flip.syncEnter combinedAccountItemKey (combinedAccountItems model)`, which inserts a
    -- fresh `UI.Flip.enter` for any item that doesn't have an entry yet, so a newly-added
    -- account/connection animates in with no need to hunt down every single "this added an item"
    -- code path by hand. A Rellm account mid fade-out after `RemoveAccountClicked` (confirmed via
    -- `UI.deleteConfirmationModal`) stays in `accounts` -- and its entry here keeps
    -- `removing = True` -- until its fade actually finishes (`FinishRemoveAccount`), so it keeps
    -- rendering (fading/collapsing) instead of just vanishing; `RemoveBlueskyAccountClicked`/
    -- `FinishRemoveBlueskyAccount` do the same for a Bluesky account. `init` seeds this with a
    -- plain `UI.Flip.restingState` (not `enter`) for every persisted item, so reloading the app
    -- doesn't replay their entrances.
    , accountAnimations : Dict String (UI.Flip.State Msg)

    -- Same as `accountAnimations`, but for the combined server feed strip (servers and browsed
    -- Mastodon instances together -- see `CombinedServerFeedItem`), keyed by
    -- `combinedServerFeedItemKey` -- covers `RemoveServerClicked`/
    -- `RemoveBrowsedMastodonInstanceClicked` and their `Finish*` counterparts, plus
    -- `syncEnter combinedServerFeedItemKey (combinedServerFeedItems model)`. See
    -- `accountAnimations`'s own doc for why these stay separate dicts.
    , serverAnimations : Dict String (UI.Flip.State Msg)

    -- Whether `init`'s startup sweep -- reconnecting to every persisted server
    -- and checking/refreshing every one of its accounts' access tokens (see
    -- `refreshPermissionsForServer`) -- has fully settled. `persist` no-ops
    -- until this flips `True`, so a page load doesn't write (and broadcast to
    -- every other open tab -- see `Ports.persistAccountsAndServers`) a rapid
    -- burst of intermediate "0 servers, 1 server, 2 servers..." states as each
    -- reconnect/refresh trickles in -- see `pendingServerChecks` and
    -- `finishStartupUnit`.
    , accessTokenRefreshChecked : Bool

    -- How many of `init`'s startup reconnect attempts (one per persisted/
    -- missing server, plus the browsing host's own if it's not already known)
    -- haven't yet fully settled -- decremented by `finishStartupUnit` as each
    -- one finishes (immediately, on a failed reconnect; once every one of its
    -- accounts' access tokens has been checked, on a successful one -- see
    -- `GotServerPermissionsRefresh`). `accessTokenRefreshChecked` flips `True`
    -- (see `finishStartupUnit`) once this reaches zero. Meaningless (never
    -- read) once `accessTokenRefreshChecked` is `True`.
    , pendingServerChecks : Int

    -- Which of the Accounts Panel's tabs is showing (see `Tab`), plus the
    -- Debug/Admin tabs' own state -- see `Shared.AccountsPanel.DebugTab`/
    -- `Shared.AccountsPanel.AdminTab`. There's no `accountsAndServersTab` field
    -- alongside these two, since that tab's content is everything else in this
    -- `Model` -- the Accounts & Servers tab *is* the Accounts Panel, as far as
    -- this module's concerned.
    , activeTab : Tab
    , debugTab : DebugTab.Model
    , adminTab : AdminTab.Model

    -- Every account (keyed by `rellmAccountId`) with an active Web Push subscription registered by
    -- this browser -- the value is the subscription's `endpoint`, so `DisableNotificationsClicked`
    -- can pass it back to both `Ports.unsubscribeFromPush` and `UnregisterPushSubscription`. The
    -- Push API allows only *one* active subscription per browser origin, tied to one VAPID key --
    -- but `UI.notificationsButton` is only ever shown for an account on `browsingHost`, so every
    -- account that can appear here shares that same one server, and so that same one key/endpoint:
    -- several entries can (and normally will, once more than one local account on `browsingHost`
    -- has notifications on) legitimately share the exact same `endpoint` value at once, all riding
    -- the browser's one real subscription together. `DisableNotificationsClicked` only actually
    -- tears that subscription down (`Ports.unsubscribeFromPush`) once no other entry here still
    -- points at the same `endpoint` -- see its own `lastAccountOnThisEndpoint`. Not persisted
    -- across page loads -- `Ports.checkPushSubscription` (fired at `init`) tells us the browser's
    -- current `endpoint`, but not *which* local accounts on that server are actually registered
    -- for it (a browser subscription carries no notion of "account") -- so
    -- `resolvePendingPushSubscriptionCheck` verifies each candidate individually via
    -- `GetPushSubscriptionStatus` (see `GotPushSubscriptionStatusResult`) before adding it here,
    -- rather than assuming every local account on that server is registered.
    , pushSubscriptions : Dict String String

    -- Last known reason "Enable notifications" (or the register/unregister RPC that follows it)
    -- failed for a given `rellmAccountId`, if any -- e.g. "Notification permission wasn't granted.",
    -- or a `grpcErrorToString`. Surfaced by `UI.notificationsButton` so a failure (silently
    -- swallowed prior to this field's existence -- see its own git history) is actually visible
    -- instead of the button just doing nothing. Cleared whenever that account's button is clicked
    -- again, so a retry starts from a clean slate.
    , notificationErrors : Dict String String

    -- The `rellmAccountId` `EnableNotificationsClicked`/`DisableNotificationsClicked` most recently
    -- fired for -- `PushSubscriptionPortReceived` already carries its own `rellmAccountId` back, but
    -- `GotRegisterPushSubscriptionResult`/`GotUnregisterPushSubscriptionResult`'s `Err` case is
    -- just a bare `Grpc.Error` with no account info of its own, so this is what lets those two
    -- still know which `notificationErrors` entry to fill in.
    , pendingNotificationAccountId : Maybe String

    -- `Ports.checkPushSubscription`'s result, still waiting to be matched against an account (see
    -- `resolvePendingPushSubscriptionCheck`) -- fired once at `init`, but `model.servers` doesn't
    -- have any `RellmServer.connected`/`webPushConfig` populated yet at that point (reconnects are all
    -- still in flight), so the very first match attempt almost always fails. Kept around (instead
    -- of discarded on that first failed attempt) and retried on every subsequent update until it
    -- either resolves or the app decides there's truly no matching account, so a page refresh
    -- correctly restores the notification toggle's "on" state once the relevant server actually
    -- finishes reconnecting, rather than only working by lucky timing.
    , pendingPushSubscriptionCheck : Maybe PushSubscriptionCheck

    -- The account `FederatedAccountReceived` most recently landed -- either side of the
    -- cross-server SSO hand-off (`Pages.Auth.From.EncryptedAccountAuthTokens_` auto-adding a
    -- transferred account, or `Pages.Auth.To.Key_`'s own "sign back in here" second login), both of
    -- which land the new account with no form submission of their own to react to. `UI.layout`
    -- renders it as a brief "Signed in as ..." notice (reusing `avatarOrPlaceholder`/`displayName`,
    -- same as `UI.accountRow`) so the user has *some* confirmation the hand-off actually worked, even
    -- though it's landed them on a page they didn't navigate to by hand. Cleared by
    -- `DismissFederatedSignInNotice`, fired either by clicking it or a few seconds after it appears.
    , federatedSignInNotice : Maybe RellmAccount

    -- Mastodon accounts connected via `UI.mastodonConnectButton`'s "Connect" button (see
    -- `MastodonConnectClicked`) -- each one's `accessToken` came straight out of an OAuth popup Elm
    -- never touched directly (see `Ports.facebookLoginPopup`'s `"mastodon"` provider). Persisted
    -- alongside `browsedMastodonInstances` via `Ports.persistMastodonAccountsAndServers` -- see that
    -- port's own doc. No remove/disconnect UI yet, unlike `browsedMastodonInstances`/
    -- `blueskyAccounts` -- once connected, an account here now survives reloads with no way to clear
    -- it short of clearing site data, an accepted first-pass limitation.
    , mastodonAccounts : List MastodonAccount

    -- The instance host `MastodonConnectClicked` most recently opened a popup for, until that
    -- popup's `Ports.facebookLoginResult` (`GotMastodonLoginResult`) settles -- `Nothing` the rest
    -- of the time. Since only one such popup can meaningfully be open at once (mirrors
    -- `Components.Pages.UserProfilePage`'s own single-popup-at-a-time flows), this alone is enough
    -- to both disable every "Connect" button while one's in flight and know which `MastodonServer`
    -- the eventual result belongs to.
    , mastodonConnectPopupOpen : Maybe String

    -- Mastodon instances the user just wants to browse the public timeline of -- no OAuth, no
    -- admin-registered app, no account at all (see `Shared.Federation.Mastodon.fetchPosts`'s own
    -- doc: it's a plain unauthenticated `GET`), the same "just add a host" affordance
    -- `AddServerClicked`'s server strip already offers for real Rellm servers. `enabled` mirrors
    -- `RellmServer.enabled`/`BlueskyAccount.enabled` -- a disabled instance stays in this list (so its
    -- chip keeps showing, switched off) but is dropped from
    -- `Components.Pages.PostsPage.relevantFeedSources`, the same as a disabled `RellmServer` is from
    -- `enabledServers`. Persisted alongside `mastodonAccounts` via `Ports.persistMastodonAccountsAndServers`.
    , browsedMastodonInstances : List BrowsedMastodonInstance

    -- `UI.mastodonBrowseSection`'s "add an instance to browse" `<input>` value -- mirrors
    -- `AddServerForm`'s own text-input-plus-button shape, just without needing a whole record
    -- (`hostInput` there also tracks in-flight validation status, which this has none of -- adding
    -- a browsed instance is instant, synchronous, and can't fail, unlike adding a real server).
    , browseMastodonInstanceInput : String

    -- Bluesky accounts connected via the Bluesky tab's form (see
    -- `BlueskyConnectClicked`/`GotBlueskyConnectResult`) -- persisted via
    -- `Ports.persistBlueskyAccounts`, same as `mastodonAccounts`/`browsedMastodonInstances` are via
    -- `Ports.persistMastodonAccountsAndServers` (see that port's own doc).
    , blueskyAccounts : List BlueskyAccount

    -- The Bluesky tab's own handle/App Password fields -- always present (unlike the `Maybe` this
    -- used to be, back when this form's own open/closed state was tracked independently of the
    -- Rellm/Mastodon ones -- see `addAccountServerFormType`), but only rendered/reachable while
    -- `addAccountServerFormType == Just BlueskyAccountFormType`. See `BlueskyConnectForm`'s own doc.
    , blueskyConnectForm : BlueskyConnectForm
    }


type Msg
    = TabSelected Tab
    | DebugTabMsg DebugTab.Msg
    | AdminTabMsg AdminTab.Msg
    | ServerChanged String
    | UsernameChanged String
    | PasswordChanged String
    | PasswordVisibilityToggled
    | LoginClicked
    | CreateAccountClicked
    | ChooseLoginClicked
    | ChooseCreateAccountClicked
    | NewAccountBackClicked
    | HideAddAccountFormClicked
    | GotCreateAccountServerInfo (Result Grpc.Error ( Connection, ServerConfiguration ))
    | GotCreateAccountModalViewport (Result Dom.Error Dom.Viewport)
    | AccessTokenResponseReceived RellmAccount AccessTokenResponse
    | CreateAccountModalScrolled Bool
    | ConfirmCreateAccountClicked
    | GotCreateAccountAcceptedTime Time.Posix
    | CancelCreateAccountClicked
    | GotAuthResult (Result Grpc.Error ( Connection, ServerConfiguration, RefreshTokenResponse ))
    | FederatedAccountReceived RellmAccount
    | GotReconnectResult String Bool Bool (Result Grpc.Error ( Connection, ServerConfiguration ))
    | GotMainServerResult (Result Grpc.Error ( Connection, ServerConfiguration ))
    | AccountsAndServersBroadcastReceived Decode.Value
    | BlueskyAccountsBroadcastReceived Decode.Value
    | MastodonAccountsAndServersBroadcastReceived Decode.Value
    | ToggleAccountEnabled String
    | RemoveAccountClicked String
    | ToggleServerEnabled String
    | ReconnectServerClicked String
    | AddServerClicked
    | GotNewServerResult (Result Grpc.Error ( Connection, ServerConfiguration ))
    | ToggleRecommendedServersExpanded
    | GotRecommendedServerConfig String (Result Grpc.Error ( Connection, ServerConfiguration ))
    | RecommendedServerClicked String
    | GotRecommendedServerAddResult String (Result Grpc.Error ( Connection, ServerConfiguration ))
    | RemoveServerClicked String
    | ToggleAccountsPanel
    | CloseAccountsPanel
    | AccountAvatarClicked RellmAccount
    | CloseFocusedAccount
    | ContactMethodsMenuToggled
    | ContactMethodPhoneEditClicked
    | ContactMethodPhoneInputChanged String
    | ContactMethodPhoneVisibilityChanged String
    | ContactMethodPhoneCancelClicked
    | ContactMethodPhoneHistoryToggled
    | ContactMethodEmailEditClicked
    | ContactMethodEmailInputChanged String
    | ContactMethodEmailVisibilityChanged String
    | ContactMethodEmailCancelClicked
    | ContactMethodEmailHistoryToggled
    | ContactMethodPhoneVerificationCodeChanged String
    | ContactMethodPhoneVerificationCooldownElapsed
    | GotContactMethodPhoneSaveResult (Result Grpc.Error User)
    | GotContactMethodEmailSaveResult (Result Grpc.Error User)
    | GotContactMethodPhoneConsentResult (Result Grpc.Error User)
    | GotContactMethodEmailConsentResult (Result Grpc.Error User)
    | GotContactMethodStartPhoneVerificationResult (Result Grpc.Error ContactMethod)
    | GotContactMethodVerifyPhoneCodeResult (Result Grpc.Error ContactMethod)
    | ShowAddAccountFormClicked
    | ReauthenticateButtonClicked RellmAccount
    | GotPermissionsRefresh String (Result Grpc.Error ( RellmAccount, User ))
    | GotServerPermissionsRefresh (List ( String, Result Grpc.Error ( RellmAccount, User ) ))
    | MainServerSelected String
    | ResetMainFrontendHost
    | ServerChipClicked String
    | SetWebUserInterfaceClicked String WebUserInterface
    | GotSetWebUserInterfaceResult (Result Grpc.Error ( RellmAccount, ServerConfiguration ))
    | RenameServerClicked String String
    | GotRenameServerResult (Result Grpc.Error ( RellmAccount, ServerConfiguration ))
    | ChangeServerShortNameClicked String String
    | GotChangeServerShortNameResult (Result Grpc.Error ( RellmAccount, ServerConfiguration ))
    | GotServerConfigSaveResult String ServerConfiguration
    | FocusInput String
    | ClearFieldClicked String Msg
    | ServerConnected RellmServer
    | MoveAccountItemUpClicked String
    | MoveAccountItemDownClicked String
    | GotPreMoveAccountItemPositions String String (Result Dom.Error ( Dom.Element, Dom.Element ))
    | MoveServerFeedItemLeftClicked String
    | MoveServerFeedItemRightClicked String
    | GotPreMoveServerFeedItemPositions String String (Result Dom.Error ( Dom.Element, Dom.Element ))
    | AnimateMove Animation.Msg
    | AccountItemMoveSettled String
    | ServerFeedItemMoveSettled String
    | FinishRemoveAccount String
    | FinishRemoveServer String
    | AnimateItemFlip Animation.Msg
    | EnableNotificationsClicked RellmAccount
    | DisableNotificationsClicked RellmAccount
    | PushSubscriptionPortReceived Decode.Value
    | GotRegisterPushSubscriptionResult (Result Grpc.Error ( RellmAccount, PushSubscription ))
    | GotUnregisterPushSubscriptionResult (Result Grpc.Error RellmAccount)
    | PushSubscriptionCheckReceived Decode.Value
    | GotPushSubscriptionStatusResult String (Result Grpc.Error ( RellmAccount, GetPushSubscriptionStatusResponse ))
    | PushSubscriptionChangeReceived Decode.Value
    | DismissFederatedSignInNotice
    | MastodonConnectClicked String
    | GotMastodonLoginResult Decode.Value
    | GotMastodonVerifyCredentialsResult String MastodonAccounts.MastodonLoginResult (Result Http.Error String)
    | MastodonAccountRefreshed MastodonAccounts.MastodonAccount
    | MarkMastodonAccountNeedsReauth String
    | AddAccountServerFormTypeSelected AccountOrServerFormType
    | BlueskyHandleChanged String
    | BlueskyAppPasswordChanged String
    | BlueskyConnectClicked
    | GotBlueskyConnectResult (Result Http.Error BlueskyAccount)
    | GotBlueskyProfileResult String (Result Http.Error BlueskyAccounts.BlueskyProfile)
    | RemoveBlueskyAccountClicked String
    | FinishRemoveBlueskyAccount String
    | ToggleBlueskyAccountEnabled String
    | BlueskyAccountRefreshed BlueskyAccount
    | MarkBlueskyAccountNeedsReauth String
    | ReconnectBlueskyAccountClicked String
    | BrowseMastodonInstanceInputChanged String
    | BrowseMastodonInstanceClicked
    | RecommendedMastodonServerClicked String
    | GotMastodonInstanceInfoResult String (Result Http.Error MastodonInstanceInfo)
    | RemoveBrowsedMastodonInstanceClicked String
    | FinishRemoveBrowsedMastodonInstance String
    | ToggleBrowsedMastodonInstanceEnabled String
    | NoOp


{-| The Bluesky tab's own handle/App Password fields and submit status -- see
`Model.blueskyConnectForm`'s own doc for why this is no longer wrapped in a `Maybe`. Reset back to
`emptyBlueskyConnectForm` on a successful `GotBlueskyConnectResult`, same as `newAccountType`
clearing on a successful `GotAuthResult`.
-}
type alias BlueskyConnectForm =
    { handle : String
    , appPassword : String
    , status : FormStatus
    }


emptyBlueskyConnectForm : BlueskyConnectForm
emptyBlueskyConnectForm =
    { handle = "", appPassword = "", status = Idle }



-- `RellmServer`/`ConnectedServer`/`Branding`/`Connection` all live in `RellmServers` now -- see
-- that module's own docs.


type FormStatus
    = Idle
    | Submitting
    | Errored String


{-| Which of the two flows `Model.newAccountType` is mid-way through --
picked by `ChooseLoginClicked`/`ChooseCreateAccountClicked` -- so the Password
field (see `UI.addAccountForm`) knows whether to ask the browser for a
"new-password" (with generation offered) or a "current-password" (with saved
passwords offered) autofill.
-}
type NewAccountType
    = CreateNewAccount
    | LoginToAccount


{-| Which of the three tabs `UI.addAccountServerForm` -- the one merged "Add Account/Server" area,
replacing what used to be three separate forms/toggles (`addAccountFormExpanded`'s Rellm form, the
"+ Bluesky Account" button/form, the "+ Mastodon Server" button/form, and the former
`mastodonServersStrip`'s own "Connect" buttons for admin-registered instances) -- is currently
showing. See
`Model.addAccountServerFormType`'s own doc for how "which tab, or none at all" is actually modeled.
-}
type AccountOrServerFormType
    = RellmServerFormType
    | MastodonServerFormType
    | BlueskyAccountFormType


{-| Which of the Accounts Panel's tabs (see `UI.elm`'s `accountsPanel`/
`accountsPanelTabBar`) is showing -- `TabAccountsAndServers` is the default (and only
one always shown; the other two only appear once `UI.elm`'s `debugCount`/
`hasAdminAccount` say there's something to show). Named inverted from
`Shared.AccountsPanel.DebugTab`/`Shared.AccountsPanel.AdminTab` (`TabDebug`/
`TabAdmin`, not `DebugTab`/`AdminTab`), mirroring
`Components.Pages.ServerInformationPage`'s own `Tab`/`TabAbout`/`TabTheme`/etc.
-}
type Tab
    = TabAccountsAndServers
    | TabDebug
    | TabAdmin


type alias AccountForm =
    { server : String
    , username : String
    , password : String
    , status : FormStatus

    -- Whether the password field (see `UI.addAccountForm`) is currently
    -- rendered as plain text rather than masked -- toggled by its "show
    -- password" button (`PasswordVisibilityToggled`).
    , showPasswordAsText : Bool
    }


{-| The policy confirmation modal's own pending state, captured when
`ChooseCreateAccountClicked` first resolves the server (see
`GotCreateAccountServerInfo`) rather than re-read from `accountForm` later --
so the modal (and the `AcceptedCreateAccount` it produces) always names the
username that was on screen at the moment "Create Account" was clicked, even
if the form's fields somehow changed while the confirmation step
(`UI.createAccountConfirmationModal`) was up. There's no password here yet --
this step happens _before_ the Password field even renders (see
`Model.newAccountType`).
-}
type alias PendingCreateAccount =
    { server : RellmServer
    , username : String

    -- Whether the user has scrolled the confirmation modal's policy text
    -- (see `UI.createAccountConfirmationModal`) to its bottom -- or it never
    -- needed scrolling in the first place, per `GotCreateAccountModalViewport`
    -- -- gating the modal's own "Accept and Continue" button so it can't be
    -- clicked past unread policy text.
    , reachedBottom : Bool
    }


{-| What's kept around once the user's actually accepted the policies
(`ConfirmCreateAccountClicked`, "Accept and Continue") -- from then on, until
the real `CreateAccount` RPC fires (`CreateAccountClicked`, now the Password
field's own submit) or the flow's abandoned (`NewAccountBackClicked`,
`setServerField`, a successful `GotAuthResult`), `server`/`username` are read
from here rather than `accountForm`, same reasoning as `PendingCreateAccount`.

`acceptedAt` is the click time of "Accept and Continue" itself, captured via
`Time.now` (see `GotCreateAccountAcceptedTime`) -- not yet sent with the
`CreateAccount` RPC (the API has no field for it), but kept on hand ready for
when it does.

-}
type alias AcceptedCreateAccount =
    { server : RellmServer
    , username : String
    , acceptedAt : Maybe Time.Posix
    }


{-| The "Add Server" control's own status -- separate from `AccountForm`'s
since adding a server (an unauthenticated `GetServerConfiguration` probe) and
logging in are independent flows that can be in-flight/erroring independently.
The host being added is `AccountForm.server` itself -- the Server field is
shared between the two flows (see `AddServerClicked`).
-}
type alias AddServerForm =
    { status : FormStatus
    }



-- `Token` lives in `RellmAccounts` now -- see that module's own doc.


type alias Flags =
    Decode.Value


type alias PersistedRellmServer =
    { frontendHost : String
    , enabled : Bool
    , sortOrder : Int
    }


type alias PersistedState =
    { accounts : List RellmAccount
    , servers : List PersistedRellmServer
    }


{-| Identifies "act as this account (if any) on this server" by identity --
`( maybe userId, hostname )` -- rather than a live `RellmAccount`/`RellmServer`
snapshot: `( Nothing, host )` means anonymous on `host`; `( Just userId,
host )` means that specific (must be enabled) account. Resolved fresh
against the current `Model` inside `performWithAccountServer`/
`performWithOptionalAccountServer`, so callers elsewhere in the app (see
`Components.PostCard`, `Components.Users`, `Shared.MarkdownPanel`) can store
just this pair -- e.g. across a page's own `Model` -- rather than a copy of
`RellmAccount`/`RellmServer` that can go stale, and never need to know how tokens get
refreshed/persisted (`AccessTokenResponseReceived`) at all.
-}
type alias MaybeAccountServer =
    ( Maybe String, String )


{-| The DOM `id` a combined account item row is rendered with (see `UI.accountRow`/
`UI.mastodonAccountRow`/`UI.blueskyAccountRow`), keyed by its `combinedAccountItemKey` -- purely so
`MoveAccountItemUpClicked`/`MoveAccountItemDownClicked` can measure its position before/after a
reorder (`Browser.Dom.getElement`) to drive its `UI.Flip` slide.
-}
accountRowDomId : String -> String
accountRowDomId key =
    "account-row-" ++ escapeCSSClass key


{-| Whether `account` is the one whose avatar popover menu is currently open (see
`Model.focusedAccount`) -- compared by `rellmAccountId` rather than structural equality, so a
popover stays open across e.g. a permissions refresh landing mid-open and changing some other field
on the same account.
-}
isFocusedAccount : Model -> RellmAccount -> Bool
isFocusedAccount model account =
    model.focusedAccount
        |> Maybe.map (\focused -> rellmAccountId focused == rellmAccountId account)
        |> Maybe.withDefault False


{-| `model.focusedAccount`'s own entry in `model.accounts`, looked up fresh by `rellmAccountId`
rather than trusting `focusedAccount`'s own (possibly stale, see that field's own doc) copy --
`applyPermissionsRefreshResult`/`GotContactMethodPhoneSaveResult`/etc. can all update `model.accounts`
out from under an already-open menu, and reading straight from `focusedAccount` instead would silently
seed an edit from (or clobber a save back onto) out-of-date `phone`/`email`/`username`/etc.
-}
freshFocusedAccount : Model -> Maybe RellmAccount
freshFocusedAccount model =
    model.focusedAccount
        |> Maybe.andThen (\focused -> model.accounts |> List.filter (\a -> rellmAccountId a == rellmAccountId focused) |> List.head)


{-| Puts `focusedAccountContactMethods` back in lockstep with `focusedAccount` -- called (after
`focusedAccount` itself has already been updated in the same record literal) everywhere that field
changes (`AccountAvatarClicked`/`CloseFocusedAccount`/`CloseAccountsPanel`/`ToggleAccountsPanel`'s
closing branch): `Just RellmAccounts.emptyRellmContactMethods` if a (possibly different) account is
now focused, `Nothing` if none is -- either way, none of the old contact-methods state makes sense
once the account it was editing is no longer the one in view.
-}
resetFocusedAccountContactMethods : Model -> Model
resetFocusedAccountContactMethods model =
    { model | focusedAccountContactMethods = model.focusedAccount |> Maybe.map (\_ -> RellmAccounts.emptyRellmContactMethods) }


{-| `focusedAccountContactMethods`'s current value, defaulted -- since that field is only ever
`Nothing` when `focusedAccount` itself is (see `resetFocusedAccountContactMethods`), every
`ContactMethod*` `Msg` handler that only touches one field of it reads the current whole record
through this (rather than pattern-matching `Maybe` at every call site) before writing back
`Just { current | ... }`.
-}
currentFocusedAccountContactMethods : Model -> RellmContactMethods
currentFocusedAccountContactMethods model =
    model.focusedAccountContactMethods |> Maybe.withDefault RellmAccounts.emptyRellmContactMethods


{-| Folds a freshly-saved `User`'s `phone`/`email` back into whichever `RellmAccount` in
`model.accounts` matches `model.focusedAccount` -- the "Contact Methods" counterpart of
`applyPermissionsRefreshResult`, but for a single field pair rather than a whole permissions
refresh, and sourced from an `UpdateUser` response rather than `GetCurrentUser`. A no-op if
`focusedAccount` is somehow unset by the time a save result lands (the menu was closed mid-request).
-}
updateFocusedAccountFromUser : User -> Model -> Model
updateFocusedAccountFromUser updatedUser model =
    case freshFocusedAccount model of
        Just account ->
            { model | accounts = RellmAccounts.upsertRellmAccount { account | phone = updatedUser.phone, email = updatedUser.email } model.accounts }

        Nothing ->
            model


{-| Like `updateFocusedAccountFromUser`, but for the phone-verification flow's own
`StartContactMethodVerification`/`VerifyContactMethod` responses, which echo back just the updated
Phone `ContactMethod` rather than a whole `User`.
-}
updateFocusedAccountPhone : ContactMethod -> Model -> Model
updateFocusedAccountPhone updatedContactMethod model =
    case freshFocusedAccount model of
        Just account ->
            { model | accounts = RellmAccounts.upsertRellmAccount { account | phone = Just updatedContactMethod } model.accounts }

        Nothing ->
            model


{-| The DOM `id` a combined server feed item chip (server or browsed Mastodon instance -- see
`CombinedServerFeedItem`) is rendered with, keyed by its `combinedServerFeedItemKey` -- the
`UI.Flip.Horizontal` counterpart of `accountRowDomId`, for `MoveServerFeedItemLeftClicked`/
`MoveServerFeedItemRightClicked`.
-}
serverFeedItemChipDomId : String -> String
serverFeedItemChipDomId key =
    "server-chip-" ++ escapeCSSClass key


{-| The bookkeeping any reorderable combined-item list built from several otherwise-separate
`Model` lists (`CombinedServerFeedItem`'s server strip, `CombinedAccountItem`'s account list) needs
around its own shared `sortOrder` space: how to read/write one item's `sortOrder` by its own kind of
key, and every _non-main_ item's current `sortOrder` (for `nextFrontSortOrderIn`/`nextBackSortOrderIn`).
Pulled out so the actual swap/next-front/next-back arithmetic is written once instead of twice, even
though each space still has to dispatch into its own, differently-shaped `Model` fields to actually
read or write anything -- see `serverFeedItemSortOrderSpace`/`accountItemSortOrderSpace`, the two
concrete instances.
-}
type alias SortOrderSpace =
    { itemSortOrder : String -> Model -> Maybe Int
    , setItemSortOrder : String -> Int -> Model -> Model
    , nonMainSortOrders : Model -> List Int
    }


{-| Reorders two adjacent items of the same `SortOrderSpace` by swapping their `sortOrder` values --
not their position in whichever underlying list each happens to live in, since e.g. a Rellm server
and a browsed Mastodon instance swapping places can't be expressed as a move within either list
alone. A no-op if either key's current item can't be found.
-}
swapSortOrders : SortOrderSpace -> String -> String -> Model -> Model
swapSortOrders space keyA keyB model =
    case ( space.itemSortOrder keyA model, space.itemSortOrder keyB model ) of
        ( Just orderA, Just orderB ) ->
            model
                |> space.setItemSortOrder keyA orderB
                |> space.setItemSortOrder keyB orderA

        _ ->
            model


{-| The `sortOrder` a brand-new item in `space` should get so it appears first -- "just after the
main item" -- among every other movable item in that same space. One less than the current lowest,
or `-1` if there's nothing else yet.
-}
nextFrontSortOrderIn : SortOrderSpace -> Model -> Int
nextFrontSortOrderIn space model =
    (space.nonMainSortOrders model |> List.minimum |> Maybe.withDefault 0) - 1


{-| Like `nextFrontSortOrderIn`, but for an item that should land at the _end_ of `space` instead.
-}
nextBackSortOrderIn : SortOrderSpace -> Model -> Int
nextBackSortOrderIn space model =
    (space.nonMainSortOrders model |> List.maximum |> Maybe.withDefault -1) + 1


{-| A Rellm server or browsed Mastodon instance, as they appear together in
`UI.combinedServerFeedItemsStrip`'s one merged, reorderable chip strip -- the two underlying lists
(`servers`, `browsedMastodonInstances`) stay separate (each persisted through its own port --
`Ports.persistAccountsAndServers`/`persistMastodonAccountsAndServers`), so this is purely a
rendering-time view over both at once, built by `combinedServerFeedItems`. Connected Bluesky
accounts _don't_ appear here -- unlike a Rellm server or a browsed Mastodon instance, a Bluesky
account has no separate sign-in step of its own (connecting _is_ signing in), so it belongs
alongside the other accounts in `CombinedAccountItem`/`UI.accountsList` instead -- see that type's
own doc.
-}
type CombinedServerFeedItem
    = CombinedRellmServer RellmServer
    | CombinedMastodonInstance BrowsedMastodonInstance


{-| A stable, cross-type identity for one `CombinedServerFeedItem` -- namespaced by kind (`"server:"`/
`"mastodon:"`) so a browsed Mastodon `host` can never collide with a Rellm `frontendHost`, even
though both are plain strings. Used as the shared key for `serverAnimations`/`serverMoveAnimations`
(fade in/out, reorder-slide) and `serverFeedItemChipDomId` (for `UI.Flip.beginReorder`'s DOM
measurement) across both types at once.
-}
combinedServerFeedItemKey : CombinedServerFeedItem -> String
combinedServerFeedItemKey item =
    case item of
        CombinedRellmServer server ->
            "server:" ++ server.frontendHost

        CombinedMastodonInstance instance ->
            "mastodon:" ++ instance.host


combinedServerFeedItemSortOrder : CombinedServerFeedItem -> Int
combinedServerFeedItemSortOrder item =
    case item of
        CombinedRellmServer server ->
            server.sortOrder

        CombinedMastodonInstance instance ->
            instance.sortOrder


{-| The full, ordered contents of `UI.combinedServerFeedItemsStrip`: the `mainFrontendHost` server first
(unmovable, same as `sortMainServerFirst` already pins it within `servers` alone), then every other
server and browsed Mastodon instance together, sorted by `sortOrder` ascending -- the one field that
lets two otherwise-separate lists interleave into a single reorderable order (plain adjacent-swap
reordering, as `UI.Flip.moveListItemBy` already does for a single list, can't reach across both of
them on its own). Lower `sortOrder` sorts earlier, i.e. closer to the main server. See
`nextFrontSortOrder`/`nextBackSortOrder` for how a freshly-added item gets one, and
`swapServerFeedItemSortOrders` for how reordering changes them.
-}
combinedServerFeedItems : Model -> List CombinedServerFeedItem
combinedServerFeedItems model =
    let
        ( mainServers, otherServers ) =
            List.partition (\s -> s.frontendHost == model.mainFrontendHost) model.servers

        others : List CombinedServerFeedItem
        others =
            (otherServers |> List.map CombinedRellmServer)
                ++ (model.browsedMastodonInstances |> List.map CombinedMastodonInstance)
                |> List.sortBy combinedServerFeedItemSortOrder
    in
    (mainServers |> List.map CombinedRellmServer) ++ others


{-| Every non-main item's current `sortOrder`, across both lists -- the main server is excluded
since its `sortOrder` is never meaningful (it's always pinned first regardless of its value), and
including it here would let a stale/arbitrary value skew `nextFrontSortOrder`/`nextBackSortOrder`.
-}
nonMainServerFeedItemSortOrders : Model -> List Int
nonMainServerFeedItemSortOrders model =
    (model.servers |> List.filter (\s -> s.frontendHost /= model.mainFrontendHost) |> List.map .sortOrder)
        ++ (model.browsedMastodonInstances |> List.map .sortOrder)


{-| Looks up one `CombinedServerFeedItem`'s current `sortOrder` by its `combinedServerFeedItemKey`, across
both underlying lists.
-}
serverFeedItemSortOrder : String -> Model -> Maybe Int
serverFeedItemSortOrder key model =
    combinedServerFeedItems model
        |> List.filter (\item -> combinedServerFeedItemKey item == key)
        |> List.head
        |> Maybe.map combinedServerFeedItemSortOrder


{-| Sets one item's `sortOrder` in place, dispatching to whichever of the two underlying lists its
`combinedServerFeedItemKey` namespace names -- a no-op if `key` doesn't match any current item.
-}
setServerFeedItemSortOrder : String -> Int -> Model -> Model
setServerFeedItemSortOrder key newSortOrder model =
    if String.startsWith "server:" key then
        { model
            | servers =
                List.map
                    (\s ->
                        if "server:" ++ s.frontendHost == key then
                            { s | sortOrder = newSortOrder }

                        else
                            s
                    )
                    model.servers
        }

    else
        { model
            | browsedMastodonInstances =
                List.map
                    (\i ->
                        if "mastodon:" ++ i.host == key then
                            { i | sortOrder = newSortOrder }

                        else
                            i
                    )
                    model.browsedMastodonInstances
        }


serverFeedItemSortOrderSpace : SortOrderSpace
serverFeedItemSortOrderSpace =
    { itemSortOrder = serverFeedItemSortOrder
    , setItemSortOrder = setServerFeedItemSortOrder
    , nonMainSortOrders = nonMainServerFeedItemSortOrders
    }


{-| The `sortOrder` a brand-new item (a manually-added server, a newly-browsed Mastodon instance)
should get so it appears first -- "just after the main server" -- among every other movable item,
same as adding a server used to prepend it to `servers` before `sortOrder` existed.
-}
nextFrontSortOrder : Model -> Int
nextFrontSortOrder model =
    nextFrontSortOrderIn serverFeedItemSortOrderSpace model


{-| Like `nextFrontSortOrder`, but for an item that should land at the _end_ instead -- mirrors
`RellmServers.upsertRellmServerAppend`'s pre-`sortOrder` append-to-end behavior, still used for a server discovered via
federation recommendations rather than added deliberately (see `GotReconnectResult`'s `appendToEnd`).
-}
nextBackSortOrder : Model -> Int
nextBackSortOrder model =
    nextBackSortOrderIn serverFeedItemSortOrderSpace model


swapServerFeedItemSortOrders : String -> String -> Model -> Model
swapServerFeedItemSortOrders =
    swapSortOrders serverFeedItemSortOrderSpace


{-| A Rellm account, connected Mastodon account, or connected Bluesky account, as they appear
together in `UI.accountsList`'s one merged, reorderable vertical list -- the three underlying lists
(`accounts`, `mastodonAccounts`, `blueskyAccounts`) stay separate (each persisted through its own
port), so this is purely a rendering-time view over all three at once, built by
`combinedAccountItems`. Mirrors `CombinedServerFeedItem` in every way that matters -- see that
type's own doc -- just one level down: a server/instance is something the app merely _watches_
(browses/federates with), while every kind here is something the app is _signed in as_.
-}
type CombinedAccountItem
    = CombinedRellmAccount RellmAccount
    | CombinedMastodonAccount MastodonAccount
    | CombinedBlueskyAccount BlueskyAccount


{-| A stable, cross-type identity for one `CombinedAccountItem` -- namespaced by kind (`"account:"`/
`"mastodon-account:"`/`"bluesky:"`) so none of the three can ever collide with each other, even
though all three ultimately key off plain strings. Used as the shared key for
`accountAnimations`/`moveAnimations` (fade in/out, reorder-slide) and `accountRowDomId` (for
`UI.Flip.beginReorder`'s DOM measurement) across all three types at once.
-}
combinedAccountItemKey : CombinedAccountItem -> String
combinedAccountItemKey item =
    case item of
        CombinedRellmAccount account ->
            "account:" ++ rellmAccountId account

        CombinedMastodonAccount account ->
            "mastodon-account:" ++ account.instanceHost ++ "|" ++ account.username

        CombinedBlueskyAccount account ->
            "bluesky:" ++ account.handle


combinedAccountItemSortOrder : CombinedAccountItem -> Int
combinedAccountItemSortOrder item =
    case item of
        CombinedRellmAccount account ->
            account.sortOrder

        CombinedMastodonAccount account ->
            account.sortOrder

        CombinedBlueskyAccount account ->
            account.sortOrder


{-| The full, ordered contents of `UI.accountsList`: every account on `mainFrontendHost` first (see
`sortMainServerAccountsFirst`), sorted among themselves by `sortOrder`, then every other Rellm
account, connected Mastodon account, and connected Bluesky account together, also sorted by
`sortOrder` ascending -- the one field that lets three otherwise-separate lists interleave into a
single reorderable order. See `nextFrontAccountSortOrder`/`nextBackAccountSortOrder` for how a
freshly-added item gets one, and `swapAccountItemSortOrders` for how reordering changes them.
-}
combinedAccountItems : Model -> List CombinedAccountItem
combinedAccountItems model =
    let
        ( mainAccounts, otherAccounts ) =
            List.partition (\a -> a.server == model.mainFrontendHost) model.accounts

        mainItems : List CombinedAccountItem
        mainItems =
            mainAccounts |> List.sortBy .sortOrder |> List.map CombinedRellmAccount

        otherItems : List CombinedAccountItem
        otherItems =
            (otherAccounts |> List.map CombinedRellmAccount)
                ++ (model.mastodonAccounts |> List.map CombinedMastodonAccount)
                ++ (model.blueskyAccounts |> List.map CombinedBlueskyAccount)
                |> List.sortBy combinedAccountItemSortOrder
    in
    mainItems ++ otherItems


{-| Every non-main item's current `sortOrder`, across all three lists -- mirrors
`nonMainServerFeedItemSortOrders`'s own reasoning, except main-server _accounts_ aren't excluded for
the same "never meaningful" reason (there can be more than one, and they're still individually
reorderable amongst themselves -- see `combinedAccountItems`); they're excluded purely so a fresh
non-main item's `sortOrder` doesn't get skewed by whatever range the main group happens to occupy.
-}
nonMainAccountItemSortOrders : Model -> List Int
nonMainAccountItemSortOrders model =
    (model.accounts |> List.filter (\a -> a.server /= model.mainFrontendHost) |> List.map .sortOrder)
        ++ (model.mastodonAccounts |> List.map .sortOrder)
        ++ (model.blueskyAccounts |> List.map .sortOrder)


{-| Looks up one `CombinedAccountItem`'s current `sortOrder` by its `combinedAccountItemKey`, across
all three underlying lists.
-}
accountItemSortOrder : String -> Model -> Maybe Int
accountItemSortOrder key model =
    combinedAccountItems model
        |> List.filter (\item -> combinedAccountItemKey item == key)
        |> List.head
        |> Maybe.map combinedAccountItemSortOrder


{-| Sets one item's `sortOrder` in place, dispatching to whichever of the three underlying lists its
`combinedAccountItemKey` namespace names -- a no-op if `key` doesn't match any current item.
-}
setAccountItemSortOrder : String -> Int -> Model -> Model
setAccountItemSortOrder key newSortOrder model =
    if String.startsWith "account:" key then
        { model
            | accounts =
                List.map
                    (\a ->
                        if "account:" ++ rellmAccountId a == key then
                            { a | sortOrder = newSortOrder }

                        else
                            a
                    )
                    model.accounts
        }

    else if String.startsWith "mastodon-account:" key then
        { model
            | mastodonAccounts =
                List.map
                    (\a ->
                        if "mastodon-account:" ++ a.instanceHost ++ "|" ++ a.username == key then
                            { a | sortOrder = newSortOrder }

                        else
                            a
                    )
                    model.mastodonAccounts
        }

    else
        { model
            | blueskyAccounts =
                List.map
                    (\a ->
                        if "bluesky:" ++ a.handle == key then
                            { a | sortOrder = newSortOrder }

                        else
                            a
                    )
                    model.blueskyAccounts
        }


accountItemSortOrderSpace : SortOrderSpace
accountItemSortOrderSpace =
    { itemSortOrder = accountItemSortOrder
    , setItemSortOrder = setAccountItemSortOrder
    , nonMainSortOrders = nonMainAccountItemSortOrders
    }


{-| The `sortOrder` a brand-new account item (a fresh login/`CreateAccount`, a freshly-connected
Mastodon or Bluesky account) should get so it appears first among every other movable account item
-- mirrors `nextFrontSortOrder`'s own reasoning, one level down (see `CombinedAccountItem`'s doc).
-}
nextFrontAccountSortOrder : Model -> Int
nextFrontAccountSortOrder model =
    nextFrontSortOrderIn accountItemSortOrderSpace model


swapAccountItemSortOrders : String -> String -> Model -> Model
swapAccountItemSortOrders =
    swapSortOrders accountItemSortOrderSpace


{-| Pins the `mainFrontendHost` server (if known yet) at the front of
`servers`, preserving the relative order of everything else -- run
unconditionally after every `update` (see its doc) so this holds both right
after app startup resolves `mainFrontendHost` from `browsingHost`
(`GotMainServerResult`) and whenever it's changed afterward
(`MainServerSelected`/`ResetMainFrontendHost`), without needing to fix up
`servers` by hand at each of those call sites. `UI.serverChip` relies on this
to special-case index `0` as the one, unmovable main server.
-}
sortMainServerFirst : Model -> Model
sortMainServerFirst model =
    let
        ( mainServers, otherServers ) =
            List.partition (\s -> s.frontendHost == model.mainFrontendHost) model.servers
    in
    { model | servers = mainServers ++ otherServers }


{-| Same idea as `sortMainServerFirst`, for `accounts` -- pins every account on the
`mainFrontendHost` server at the front, preserving the relative order of everything else. Run at
the same two points (see `sortMainServerFirst`'s doc). `combinedAccountItems` itself re-derives the
main/non-main partition live from `.server` on every call (not from this list's own physical
order), so this is no longer load-bearing for render order the way it once was -- kept purely to
keep `encodeState`'s own on-disk ordering tidy, same as `sortMainServerFirst`'s own doc on that.
-}
sortMainServerAccountsFirst : Model -> Model
sortMainServerAccountsFirst model =
    let
        ( mainAccounts, otherAccounts ) =
            List.partition (\a -> a.server == model.mainFrontendHost) model.accounts
    in
    { model | accounts = mainAccounts ++ otherAccounts }


{-| Whether any _signed-in_ (enabled) account has `ADMIN` on its server --
gates showing the Server Admin Panel button at all.
-}
hasAdminAccount : Model -> Bool
hasAdminAccount model =
    List.any (\a -> a.enabled && RellmAccounts.isAdmin a) model.accounts


{-| Signed-in accounts -- what the accounts-menu toggle button renders as a
row of avatars instead of the "Login" label (see `UI.elm`'s
`accountsMenuButtonContent`).
-}
enabledAccounts : Model -> List RellmAccount
enabledAccounts model =
    List.filter .enabled model.accounts


{-| Like `RellmServers.rellmServerThemeOf`, but looks a server up by `frontendHost` (for e.g. an
account's `server` field).
-}
serverThemeFor : Bool -> Model -> String -> UI.ServerTheme.ServerTheme
serverThemeFor darkMode model frontendHost =
    let
        branding : Branding
        branding =
            RellmServers.brandingFor model.servers frontendHost
    in
    UI.ServerTheme.fromColorMetas darkMode branding.primary branding.nav


{-| The theme for chrome that isn't scoped to any one server/account row (nav
links, form buttons, etc.) -- currently always `mainFrontendHost`'s theme.
-}
mainServerTheme : Bool -> Model -> UI.ServerTheme.ServerTheme
mainServerTheme darkMode model =
    serverThemeFor darkMode model model.mainFrontendHost


{-| `Ports.persistMastodonAccountsAndServers`'s wire format -- `MastodonAccount`s
and `BrowsedMastodonInstance`s bundled into one value, since they're persisted
together (see that port's own doc), even though they're two separate `Model` fields rendered in two
entirely different places -- `mastodonAccounts` in `UI.accountsList` (see `CombinedAccountItem`),
`browsedMastodonInstances` in `UI.combinedServerFeedItemsStrip` (see `CombinedServerFeedItem`).
-}
type alias MastodonAccountsAndServers =
    { accounts : List MastodonAccount
    , browsedInstances : List BrowsedMastodonInstance
    }


emptyMastodonAccountsAndServers : MastodonAccountsAndServers
emptyMastodonAccountsAndServers =
    { accounts = [], browsedInstances = [] }


mastodonAccountsAndServersDecoder : Decoder MastodonAccountsAndServers
mastodonAccountsAndServersDecoder =
    Decode.map2 MastodonAccountsAndServers
        (Decode.field "accounts" (Decode.list MastodonAccounts.mastodonAccountDecoder))
        (Decode.field "browsedInstances" (Decode.list MastodonServers.browsedMastodonInstanceDecoder))


init : Request -> Flags -> Flags -> Flags -> ( Model, Cmd Msg )
init req flags blueskyAccountsFlags mastodonAccountsAndServersFlags =
    let
        rawPersisted : PersistedState
        rawPersisted =
            Decode.decodeValue persistedStateDecoder flags
                |> Result.withDefault emptyPersistedState

        rawBlueskyAccounts : List BlueskyAccount
        rawBlueskyAccounts =
            Decode.decodeValue BlueskyAccounts.decoder blueskyAccountsFlags
                |> Result.withDefault []

        rawMastodon : MastodonAccountsAndServers
        rawMastodon =
            Decode.decodeValue mastodonAccountsAndServersDecoder mastodonAccountsAndServersFlags
                |> Result.withDefault emptyMastodonAccountsAndServers

        -- Assigns real `sortOrder` values (see `migrateServerFeedItemSortOrders`'s/
        -- `migrateAccountItemSortOrders`'s own docs) the first time any of these five lists is seen
        -- without them -- i.e. essentially always, the first time a client loads this version.
        -- Every other binding in this `let` that reads `persisted`/`persistedMastodon`/
        -- `persistedBlueskyAccounts` (rather than the `raw*` values directly) already sees the
        -- migrated ones.
        ( migratedServers, migratedBrowsedInstances ) =
            migrateServerFeedItemSortOrders rawPersisted.servers rawMastodon.browsedInstances

        ( migratedAccounts, migratedMastodonAccounts, persistedBlueskyAccounts ) =
            migrateAccountItemSortOrders rawPersisted.accounts rawMastodon.accounts rawBlueskyAccounts

        persisted : PersistedState
        persisted =
            { rawPersisted | accounts = migratedAccounts, servers = migratedServers }

        persistedMastodon : MastodonAccountsAndServers
        persistedMastodon =
            { rawMastodon | accounts = migratedMastodonAccounts, browsedInstances = migratedBrowsedInstances }

        pageIsSecure : Bool
        pageIsSecure =
            RellmServers.isSecure req

        browsingHost : String
        browsingHost =
            req.url.host

        -- The app is very often served up by a Rellm server itself, so whichever
        -- host it's being viewed from is worth auto-connecting to, same as any other
        -- server. If it's already a known server, this is a no-op -- the persisted
        -- entry (and its enabled flag) wins, and we already know it's not a
        -- backend-only host (see `GotMainServerResult`), so no correction is needed.
        browsingHostAlreadyKnown : Bool
        browsingHostAlreadyKnown =
            List.any (\s -> s.frontendHost == browsingHost) persisted.servers

        mainServerCmd : Cmd Msg
        mainServerCmd =
            if browsingHostAlreadyKnown then
                Cmd.none

            else
                RellmServers.negotiateRellmServerConfig pageIsSecure browsingHost
                    |> Task.attempt GotMainServerResult

        reconnectCmds : List (Cmd Msg)
        reconnectCmds =
            List.map
                (\ps ->
                    RellmServers.negotiateRellmServerConfig pageIsSecure ps.frontendHost
                        |> Task.attempt (GotReconnectResult ps.frontendHost ps.enabled False)
                )
                persisted.servers

        -- Accounts whose server host has no persisted RellmServer entry at all (stale/
        -- corrupted localStorage, a server dropped by an old bug, etc.) would
        -- otherwise never get a reconnect attempt and stay permanently
        -- "unreachable" (see `unreachableAccountHosts`) even though we still have
        -- credentials for them. Treat each such host like any other reconnect,
        -- enabling it if any of its accounts are themselves enabled -- mirrors
        -- `ToggleAccountEnabled` bringing a disabled server along with an account
        -- being re-enabled.
        missingServerHosts : List String
        missingServerHosts =
            persisted.accounts
                |> List.map .server
                |> List.filter (\host -> not (List.any (\s -> s.frontendHost == host) persisted.servers))
                |> Set.fromList
                |> Set.toList

        missingServerCmds : List (Cmd Msg)
        missingServerCmds =
            List.map
                (\host ->
                    RellmServers.negotiateRellmServerConfig pageIsSecure host
                        |> Task.attempt (GotReconnectResult host (List.any (\a -> a.server == host && a.enabled) persisted.accounts) False)
                )
                missingServerHosts

        -- The next back `sortOrder` to hand out to each of `missingServerHosts`' fresh
        -- placeholders below (see `nextBackSortOrder`'s own doc -- this mirrors it, but there's no
        -- `Model` yet to call that with here).
        nextMissingServerSortOrder : Int
        nextMissingServerSortOrder =
            ((persisted.servers |> List.map .sortOrder)
                ++ (persistedMastodon.browsedInstances |> List.map .sortOrder)
                |> List.maximum
                |> Maybe.withDefault -1
            )
                + 1

        -- One "unit" per reconnect attempt just dispatched above -- see
        -- `pendingServerChecks`/`finishStartupUnit`.
        initialPendingServerChecks : Int
        initialPendingServerChecks =
            (if browsingHostAlreadyKnown then
                0

             else
                1
            )
                + List.length persisted.servers
                + List.length missingServerHosts
    in
    ( { accounts = persisted.accounts

      -- Seeded disconnected (see `RellmServer.connected`/`RellmServers.disconnectedRellmServer`), in
      -- persisted order, rather than starting empty -- so a server stays in
      -- its place (and keeps showing, as disconnected, rather than just
      -- vanishing) if `reconnectCmds`/`missingServerCmds` below never bring
      -- it back this session. Each entry gets replaced in place (see
      -- `RellmServers.upsertRellmServer`) once/if its own reconnect actually succeeds
      -- (`GotReconnectResult`).
      , servers =
            (persisted.servers |> List.map RellmServers.disconnectedRellmServer)
                ++ (missingServerHosts
                        |> List.indexedMap
                            (\idx host ->
                                RellmServers.disconnectedRellmServer
                                    { frontendHost = host
                                    , enabled = List.any (\a -> a.server == host && a.enabled) persisted.accounts
                                    , sortOrder = nextMissingServerSortOrder + idx
                                    }
                            )
                   )
      , accountForm = { emptyForm | server = browsingHost }
      , addServerForm = emptyAddServerForm
      , showAccountsPanel = False
      , recommendedServersExpanded = False
      , recommendedServerConnections = Dict.empty
      , focusedAccount = Nothing
      , focusedAccountContactMethods = Nothing
      , addAccountServerFormType = Nothing
      , newAccountType = Nothing
      , createAccountConfirmation = Nothing
      , acceptedCreateAccount = Nothing
      , browsingHost = browsingHost
      , browsingHostConfigResolved = False
      , mainFrontendHost = browsingHost
      , moveAnimations = Dict.empty
      , serverMoveAnimations = Dict.empty

      -- Seeded with a *resting* (not `enter`) state for everything already
      -- persisted, so `syncItemAnimations` -- which would otherwise treat any
      -- id with no entry as "just appeared" -- doesn't replay every account's/
      -- feed item's entrance on every reload. Only genuinely new ones (signed
      -- in, or added, after this) start from `Dict.empty`-implied absence and
      -- so actually animate in. Covers all three `CombinedAccountItem`/both
      -- `CombinedServerFeedItem` kinds -- see `serverAnimations`'s own doc.
      , accountAnimations =
            ((persisted.accounts |> List.map (\account -> "account:" ++ rellmAccountId account))
                ++ (persistedMastodon.accounts |> List.map (\account -> "mastodon-account:" ++ account.instanceHost ++ "|" ++ account.username))
                ++ (persistedBlueskyAccounts |> List.map (\account -> "bluesky:" ++ account.handle))
            )
                |> List.map (\key -> ( key, UI.Flip.restingState ))
                |> Dict.fromList
      , serverAnimations =
            ((persisted.servers |> List.map (\server -> "server:" ++ server.frontendHost))
                ++ (persistedMastodon.browsedInstances |> List.map (\instance -> "mastodon:" ++ instance.host))
            )
                |> List.map (\key -> ( key, UI.Flip.restingState ))
                |> Dict.fromList
      , accessTokenRefreshChecked = initialPendingServerChecks <= 0
      , pendingServerChecks = initialPendingServerChecks
      , activeTab = TabAccountsAndServers
      , debugTab = DebugTab.init
      , adminTab = AdminTab.init
      , pushSubscriptions = Dict.empty
      , notificationErrors = Dict.empty
      , pendingNotificationAccountId = Nothing
      , pendingPushSubscriptionCheck = Nothing
      , federatedSignInNotice = Nothing
      , mastodonAccounts = persistedMastodon.accounts
      , mastodonConnectPopupOpen = Nothing
      , browsedMastodonInstances = persistedMastodon.browsedInstances
      , browseMastodonInstanceInput = ""
      , blueskyAccounts = persistedBlueskyAccounts
      , blueskyConnectForm = emptyBlueskyConnectForm
      }
    , Cmd.batch
        (Ports.checkPushSubscription Encode.null
            :: mainServerCmd
            :: (List.map healthCheckMastodonAccountCmd persistedMastodon.accounts ++ reconnectCmds ++ missingServerCmds)
        )
    )


{-| Just the accounts' reorder-slide animations (see `moveAnimations`) --
`Shared.subscriptions` batches this in with everything else.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ UI.Flip.moveSubscription AnimateMove
            (Dict.values model.moveAnimations ++ Dict.values model.serverMoveAnimations)
        , UI.Flip.subscription AnimateItemFlip
            (Dict.values model.accountAnimations ++ Dict.values model.serverAnimations)
        , Ports.accountsAndServersUpdated AccountsAndServersBroadcastReceived
        , Ports.blueskyAccountsUpdated BlueskyAccountsBroadcastReceived
        , Ports.mastodonAccountsAndServersUpdated MastodonAccountsAndServersBroadcastReceived
        , Ports.pushSubscribed PushSubscriptionPortReceived
        , Ports.pushSubscriptionChecked PushSubscriptionCheckReceived
        , Ports.pushSubscriptionChangeReceived PushSubscriptionChangeReceived
        , Ports.facebookLoginResult GotMastodonLoginResult
        ]


{-| `sendUpdate`'s actual per-`Msg` logic, plus `syncItemAnimations`,
`sortMainServerFirst`, and `sortMainServerAccountsFirst` run unconditionally
afterward -- so every code path that can add an account/server, or change
`mainFrontendHost`, gets its enter animation/correct ordering for free,
without auditing each one by hand. Cheap enough (`accounts`/`servers` are
small) to run after every single message.
-}
update : Request -> Msg -> Model -> ( Model, Cmd Msg )
update req msg model =
    let
        ( updatedModel, cmd ) =
            sendUpdate req msg model
                |> Tuple.mapFirst syncItemAnimations
                |> Tuple.mapFirst sortMainServerFirst
                |> Tuple.mapFirst sortMainServerAccountsFirst

        ( resolvedModel, resolveCmd ) =
            resolvePendingPushSubscriptionCheck updatedModel
    in
    ( resolvedModel, Cmd.batch [ cmd, resolveCmd ] )


{-| Adds `host` (trimmed by the caller) to `model.browsedMastodonInstances` and kicks off its
logo/name fetch (`GotMastodonInstanceInfoResult`) -- shared by `BrowseMastodonInstanceClicked` (a
manually-typed host) and `RecommendedMastodonServerClicked` (one of `recommendedMastodonServers`).
A no-op for a blank host or one already browsed, exactly like `BrowseMastodonInstanceClicked` used
to check inline.
-}
addBrowsedMastodonInstance : Model -> String -> ( Model, Cmd Msg )
addBrowsedMastodonInstance model host =
    if String.isEmpty host || List.any (\i -> i.host == host) model.browsedMastodonInstances then
        ( model, Cmd.none )

    else
        let
            newModel : Model
            newModel =
                { model
                    | browsedMastodonInstances =
                        { host = host, enabled = True, logoUrl = Nothing, displayName = Nothing, sortOrder = nextFrontSortOrder model }
                            :: model.browsedMastodonInstances
                }
        in
        ( newModel
        , Cmd.batch
            [ Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel)
            , Task.attempt (GotMastodonInstanceInfoResult host) (MastodonServers.fetchMastodonInstanceInfoTask host)
            ]
        )


{-| Retries matching `pendingPushSubscriptionCheck` (see its own doc comment) against
`model.accounts`/`model.servers` on every update, not just when it first arrives -- the servers a
`PushSubscriptionCheck`'s `publicKey` needs to match against are usually still reconnecting (no
`RellmServer.connected` yet) at the moment `checkPushSubscription`'s result actually comes back, so the
very first attempt almost always finds nothing. A no-op once there's nothing pending, or once a
match has already been dispatched -- cheap enough to run unconditionally alongside
`syncItemAnimations`/etc.

Doesn't just trust every matching account straight into `pushSubscriptions` -- the browser's
subscription only proves _some_ account on this server is registered for it, not which ones (see
`GetPushSubscriptionStatus`'s own RPC doc comment) -- so instead this fires one verification call
per matching account and lets `GotPushSubscriptionStatusResult` fill in `pushSubscriptions` only
for the ones the server actually confirms.

-}
resolvePendingPushSubscriptionCheck : Model -> ( Model, Cmd Msg )
resolvePendingPushSubscriptionCheck model =
    case model.pendingPushSubscriptionCheck of
        Nothing ->
            ( model, Cmd.none )

        Just check ->
            let
                matchingAccounts : List RellmAccount
                matchingAccounts =
                    model.accounts
                        |> List.filter (\account -> RellmServers.rellmServerWebPushPublicKey model.servers account.server == Just check.publicKey)
            in
            if List.isEmpty matchingAccounts then
                ( model, Cmd.none )

            else
                ( { model | pendingPushSubscriptionCheck = Nothing }
                , matchingAccounts
                    |> List.filterMap
                        (\account ->
                            RellmServers.rellmServerForHost model.servers account.server
                                |> Maybe.andThen RellmServers.connectionOf
                                |> Maybe.map
                                    (\connection ->
                                        RellmAccounts.performWithRellmAccount
                                            connection
                                            account
                                            (\accessToken ->
                                                Grpc.new Rellm.getPushSubscriptionStatus { endpoint = check.endpoint }
                                                    |> Grpc.setHost (RellmServers.connectionUrl connection)
                                                    |> RellmServers.withAccessToken (Just accessToken)
                                                    |> Grpc.toTask
                                            )
                                            |> Task.attempt (GotPushSubscriptionStatusResult check.endpoint)
                                    )
                        )
                    |> Cmd.batch
                )


{-| Inserts a fresh `UI.Flip.enter` into `accountAnimations`/`serverAnimations` for any combined
account item (`CombinedAccountItem`) or combined server feed item (`CombinedServerFeedItem`) that
doesn't have an entry yet -- see those fields' own docs, and `UI.Flip.syncEnter`.
-}
syncItemAnimations : Model -> Model
syncItemAnimations model =
    { model
        | accountAnimations = UI.Flip.syncEnter combinedAccountItemKey (combinedAccountItems model) model.accountAnimations
        , serverAnimations = UI.Flip.syncEnter combinedServerFeedItemKey (combinedServerFeedItems model) model.serverAnimations
    }


sendUpdate : Request -> Msg -> Model -> ( Model, Cmd Msg )
sendUpdate req msg model =
    case msg of
        TabSelected tab ->
            ( { model | activeTab = tab }, Cmd.none )

        DebugTabMsg subMsg ->
            ( { model | debugTab = DebugTab.update subMsg model.debugTab }, Cmd.none )

        AdminTabMsg subMsg ->
            ( { model | adminTab = AdminTab.update subMsg model.adminTab }, Cmd.none )

        ServerChanged server ->
            ( setServerField server model, Cmd.none )

        UsernameChanged username ->
            ( updateForm (\form -> { form | username = username }) model, Cmd.none )

        PasswordChanged password ->
            ( updateForm
                (\form ->
                    { form
                        | password = password
                        , showPasswordAsText = form.showPasswordAsText && not (String.isEmpty password)
                    }
                )
                model
            , Cmd.none
            )

        PasswordVisibilityToggled ->
            ( updateForm (\form -> { form | showPasswordAsText = not form.showPasswordAsText }) model, Cmd.none )

        ChooseLoginClicked ->
            ( { model | newAccountType = Just LoginToAccount }
            , Task.attempt (\_ -> NoOp) (Dom.focus "account-form-password")
            )

        ChooseCreateAccountClicked ->
            let
                form : AccountForm
                form =
                    model.accountForm
            in
            ( model
                |> updateForm (\f -> { f | status = Submitting })
                |> updateAddServerForm (\f -> { f | status = clearErrored f.status })
            , RellmServers.resolveHost (RellmServers.isSecure req) model.servers (String.trim form.server)
                |> Task.attempt GotCreateAccountServerInfo
            )

        NewAccountBackClicked ->
            ( { model | newAccountType = Nothing, acceptedCreateAccount = Nothing }
                |> updateForm (\f -> { f | password = "", showPasswordAsText = False })
            , Cmd.none
            )

        HideAddAccountFormClicked ->
            ( { model | addAccountServerFormType = Nothing }, Cmd.none )

        LoginClicked ->
            let
                form : AccountForm
                form =
                    model.accountForm

                server : String
                server =
                    String.trim form.server
            in
            ( model
                |> updateForm (\f -> { f | status = Submitting })
                |> updateAddServerForm (\f -> { f | status = clearErrored f.status })
            , RellmServers.resolveHost (RellmServers.isSecure req) model.servers server
                |> Task.andThen
                    (\( connection, config ) ->
                        Grpc.new Rellm.login
                            { username = form.username
                            , password = form.password
                            , expiresAt = Nothing
                            , deviceName = Nothing
                            , userId = Nothing
                            }
                            |> Grpc.setHost (RellmServers.connectionUrl connection)
                            |> Grpc.toTask
                            |> Task.map (\resp -> ( connection, config, resp ))
                    )
                |> Task.attempt GotAuthResult
            )

        CreateAccountClicked ->
            case model.acceptedCreateAccount of
                Nothing ->
                    -- The submit button only renders once `newAccountType`
                    -- is `Just CreateNewAccount`, which only happens once
                    -- `acceptedCreateAccount` is set (`ConfirmCreateAccountClicked`)
                    -- -- unreachable in practice.
                    ( model, Cmd.none )

                Just accepted ->
                    case ( RellmServers.connectionOf accepted.server, accepted.server.connected ) of
                        ( Just connection, Just { configuration } ) ->
                            let
                                form : AccountForm
                                form =
                                    model.accountForm
                            in
                            ( model
                                |> updateForm (\f -> { f | status = Submitting })
                            , Grpc.new Rellm.createAccount
                                { username = accepted.username
                                , password = form.password
                                , email = Nothing
                                , phone = Nothing
                                , expiresAt = Nothing
                                , deviceName = Nothing
                                }
                                |> Grpc.setHost (RellmServers.connectionUrl connection)
                                |> Grpc.toTask
                                |> Task.map (\resp -> ( connection, configuration, resp ))
                                |> Task.attempt GotAuthResult
                            )

                        -- `accepted.server` was built by `RellmServers.rellmServerFrom` (see
                        -- `GotCreateAccountServerInfo`), which is always connected --
                        -- unreachable in practice.
                        _ ->
                            ( model, Cmd.none )

        GotCreateAccountServerInfo (Ok ( connection, config )) ->
            let
                form : AccountForm
                form =
                    model.accountForm

                newModel : Model
                newModel =
                    { model
                        | createAccountConfirmation =
                            Just
                                { server = RellmServers.rellmServerFrom connection True config
                                , username = form.username
                                , reachedBottom = False
                                }
                    }
            in
            ( updateForm (\f -> { f | status = Idle }) newModel
            , Task.attempt GotCreateAccountModalViewport (Dom.getViewportOf createAccountModalBodyId)
            )

        GotCreateAccountServerInfo (Err err) ->
            ( updateForm (\f -> { f | status = Errored (grpcErrorToString err) }) model
            , Cmd.none
            )

        GotCreateAccountModalViewport result ->
            case result of
                Ok viewport ->
                    -- The policy text didn't even need scrolling to begin
                    -- with (it all already fits) -- nothing more to wait on.
                    if viewport.scene.height <= viewport.viewport.height + 1 then
                        ( markCreateAccountBottomReached model, Cmd.none )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        CreateAccountModalScrolled atBottom ->
            ( if atBottom then
                markCreateAccountBottomReached model

              else
                model
            , Cmd.none
            )

        CancelCreateAccountClicked ->
            ( { model | createAccountConfirmation = Nothing }, Cmd.none )

        ConfirmCreateAccountClicked ->
            case model.createAccountConfirmation of
                Nothing ->
                    ( model, Cmd.none )

                Just pending ->
                    ( { model
                        | createAccountConfirmation = Nothing
                        , acceptedCreateAccount =
                            Just
                                { server = pending.server
                                , username = pending.username
                                , acceptedAt = Nothing
                                }
                        , newAccountType = Just CreateNewAccount
                      }
                    , Cmd.batch
                        [ Task.perform GotCreateAccountAcceptedTime Time.now
                        , Task.attempt (\_ -> NoOp) (Dom.focus "account-form-password")
                        ]
                    )

        GotCreateAccountAcceptedTime time ->
            ( { model
                | acceptedCreateAccount =
                    Maybe.map (\accepted -> { accepted | acceptedAt = Just time }) model.acceptedCreateAccount
              }
            , Cmd.none
            )

        GotAuthResult (Ok ( connection, config, resp )) ->
            case ( resp.user, resp.refreshToken, resp.accessToken ) of
                ( Just user, Just refreshToken, Just accessToken ) ->
                    let
                        account : RellmAccount
                        account =
                            { server = connection.frontendHost
                            , userId = user.id
                            , username = user.username
                            , refreshToken = RellmAccounts.tokenFromExpirable refreshToken
                            , accessToken = RellmAccounts.tokenFromExpirable accessToken
                            , enabled = True
                            , avatarMediaId = Maybe.map .id user.avatar
                            , permissions = user.permissions
                            , realName = user.realName
                            , needsPassword = False
                            , sortOrder = nextFrontAccountSortOrder model

                            -- Login/CreateAccount's `User` never carries these (only a
                            -- self-or-Admin `GetUsers` lookup does, see `RellmAccount`'s own doc) --
                            -- read straight from `user` anyway rather than hardcoding `[]`, so
                            -- this doesn't have to change if that's ever loosened.
                            , syncDestinations = user.syncDestinations
                            , syncSources = user.syncSources
                            , aiModels = user.aiModels
                            , marketSubscriptions = user.marketSubscriptions
                            , mediaStorageBytesUsed = Conversions.int64ToInt user.mediaStorageBytesUsed
                            , mediaStorageLimitBytes = Maybe.map Conversions.int64ToInt user.mediaStorageLimitBytes
                            , phone = user.phone
                            , email = user.email
                            }

                        newModel : Model
                        newModel =
                            { model
                                | accounts =
                                    RellmAccounts.upsertRellmAccount account model.accounts
                                        |> RellmAccounts.disableOtherRellmAccountsOnServer (rellmAccountId account) account.server
                                , servers =
                                    RellmServers.upsertRellmServer (nextFrontSortOrder model) (RellmServers.rellmServerFrom connection True config) model.servers
                                        |> RellmServers.enableRellmServerFor connection.frontendHost
                                , accountForm =
                                    let
                                        form : AccountForm
                                        form =
                                            model.accountForm
                                    in
                                    { form | password = "", showPasswordAsText = False, status = Idle }
                                , newAccountType = Nothing
                                , acceptedCreateAccount = Nothing
                            }
                    in
                    ( newModel, persist newModel )

                _ ->
                    ( updateForm (\f -> { f | status = Errored "Server response was missing user/token data." }) model
                    , Cmd.none
                    )

        GotAuthResult (Err err) ->
            ( updateForm (\f -> { f | status = Errored (grpcErrorToString err) }) model
            , Cmd.none
            )

        FederatedAccountReceived account ->
            -- Same upsert as `GotAuthResult`, but the account arrived already
            -- signed-in (via `Pages.Auth.From.EncryptedAccountAuthTokens_`'s SSO hand-off, or
            -- `Pages.Auth.To.Key_`'s own "sign back in here" second login) rather than through this
            -- form's own `LoginClicked` -- always enabled once accepted, regardless of what `enabled`
            -- it carried across the wire. Either way there's no form submission of its own for the
            -- user to have watched settle, so `federatedSignInNotice` surfaces a brief confirmation
            -- (see its own doc) that something just happened.
            let
                enabledAccount : RellmAccount
                enabledAccount =
                    -- `account.sortOrder` crossed the wire from whatever it meant in the sending
                    -- origin's own account list -- meaningless here, so it's reassigned fresh
                    -- (unless this account's already known locally, in which case `RellmAccounts.upsertRellmAccount`
                    -- below keeps its existing local `sortOrder` anyway -- see that function's own
                    -- doc).
                    { account | enabled = True, sortOrder = nextFrontAccountSortOrder model }

                newModel : Model
                newModel =
                    { model
                        | accounts =
                            RellmAccounts.upsertRellmAccount enabledAccount model.accounts
                                |> RellmAccounts.disableOtherRellmAccountsOnServer (rellmAccountId enabledAccount) enabledAccount.server
                        , servers = RellmServers.enableRellmServerFor enabledAccount.server model.servers
                        , federatedSignInNotice = Just enabledAccount
                    }

                -- The account's server may not be known (or may be known but
                -- disconnected) on this origin yet -- same situation `init`'s
                -- `missingServerHosts` handles for accounts surviving from stale/
                -- corrupted localStorage. When it's already connected, `GotReconnectResult`
                -- won't fire again the way it does for a fresh reconnect below (which itself
                -- calls `refreshPermissionsForServer` on success) -- so this account's
                -- `permissions`/`syncDestinations`/`syncSources`/`aiModels`
                -- (see `RellmAccount`'s own doc) would otherwise sit stale (whatever `account`
                -- carried across the SSO hand-off) until some later, unrelated reconnect.
                -- Refresh it directly here instead so it's current immediately.
                existingConnectedServer : Maybe RellmServer
                existingConnectedServer =
                    model.servers
                        |> List.filter (\s -> s.frontendHost == enabledAccount.server && s.connected /= Nothing)
                        |> List.head

                refreshCmd : Cmd Msg
                refreshCmd =
                    case existingConnectedServer of
                        Just server ->
                            refreshPermissions server enabledAccount

                        Nothing ->
                            RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) enabledAccount.server
                                |> Task.attempt (GotReconnectResult enabledAccount.server True False)
            in
            ( newModel
            , Cmd.batch
                [ persist newModel
                , refreshCmd
                , Process.sleep federatedSignInNoticeDuration |> Task.perform (\_ -> DismissFederatedSignInNotice)
                ]
            )

        AccessTokenResponseReceived account accessTokenResponse ->
            let
                newModel : Model
                newModel =
                    { model
                        | accounts =
                            List.map
                                (\a ->
                                    if a.userId == account.userId && a.server == account.server then
                                        case ( accessTokenResponse.accessToken, accessTokenResponse.refreshToken ) of
                                            ( Just accessToken, Just refreshToken ) ->
                                                { a
                                                    | accessToken = RellmAccounts.tokenFromExpirable accessToken
                                                    , refreshToken = RellmAccounts.tokenFromExpirable refreshToken
                                                }

                                            ( Just accessToken, Nothing ) ->
                                                { a | accessToken = RellmAccounts.tokenFromExpirable accessToken }

                                            ( Nothing, Just refreshToken ) ->
                                                { a | refreshToken = RellmAccounts.tokenFromExpirable refreshToken }

                                            ( Nothing, Nothing ) ->
                                                a

                                    else
                                        a
                                )
                                model.accounts
                    }
            in
            ( newModel, persist newModel )

        GotReconnectResult frontendHost enabled appendToEnd result ->
            let
                newItemSortOrder : Int
                newItemSortOrder =
                    if appendToEnd then
                        nextBackSortOrder model

                    else
                        nextFrontSortOrder model

                insert : RellmServer -> List RellmServer -> List RellmServer
                insert =
                    if appendToEnd then
                        RellmServers.upsertRellmServerAppend newItemSortOrder

                    else
                        RellmServers.upsertRellmServer newItemSortOrder
            in
            case result of
                Ok ( connection, config ) ->
                    let
                        server : RellmServer
                        server =
                            RellmServers.rellmServerFrom connection enabled config

                        newModel : Model
                        newModel =
                            { model
                                | servers = insert server model.servers
                                , browsingHostConfigResolved = model.browsingHostConfigResolved || frontendHost == model.browsingHost
                            }
                    in
                    -- Replaces (rather than just skipping) any existing entry for this host,
                    -- keeping its place in the list (see `RellmServers.upsertRellmServer`) -- this fires on
                    -- every reconnect (app startup/reload, `init`'s `reconnectCmds`), so an
                    -- unconditional append here would otherwise duplicate the server on each
                    -- successful reconnect. Also refresh permissions for any of its accounts
                    -- now that we can actually reach it -- this is what makes permissions
                    -- (and access tokens -- see `needsPassword`) current on app startup/
                    -- reload, not just after a fresh login. `refreshPermissionsForServer`
                    -- itself persists (this server's own addition included) once that
                    -- settles -- see its own doc.
                    ( newModel
                    , refreshPermissionsForServer server newModel.accounts
                    )

                Err _ ->
                    -- Couldn't reconnect (server's down, moved, etc.). Rather than dropping it
                    -- (which would silently erase it from what's persisted, see
                    -- `RellmServers.encodePersistedRellmServer`, the very next time `persist` fires), mark/keep
                    -- it disconnected in place -- `RellmServers.disconnectedRellmServer` if this host has no
                    -- entry yet at all (e.g. a federated server whose very first negotiation
                    -- failed), otherwise leave any existing entry (already disconnected, or
                    -- about to be replaced by a still-in-flight reconnect for the same host)
                    -- untouched. Still settles this server's startup-sweep unit, if one's
                    -- pending -- see `settleStartupUnit`.
                    let
                        newModel : Model
                        newModel =
                            (if List.any (\s -> s.frontendHost == frontendHost) model.servers then
                                model

                             else
                                { model | servers = insert (RellmServers.disconnectedRellmServer { frontendHost = frontendHost, enabled = enabled, sortOrder = 0 }) model.servers }
                            )
                                |> (\m -> { m | browsingHostConfigResolved = m.browsingHostConfigResolved || frontendHost == m.browsingHost })
                    in
                    settleStartupUnit newModel

        GotMainServerResult result ->
            case result of
                Ok ( connection, config ) ->
                    let
                        -- If the host we're browsing from turns out to be a backend-only
                        -- host presenting a different public identity (e.g. we ended up on
                        -- jonline.io.getj.online, a CDN's backend, when jonline.io is the
                        -- real front door), treat *that* as the main server instead --
                        -- exactly as if the user had typed it in directly.
                        resolvedFrontend : String
                        resolvedFrontend =
                            RellmServers.resolvedFrontendHost model.browsingHost config

                        correctedConnection : Connection
                        correctedConnection =
                            { connection | frontendHost = resolvedFrontend }

                        server : RellmServer
                        server =
                            RellmServers.rellmServerFrom correctedConnection True config

                        -- Mirrors `federatedServerCmds` below, for `FederationInfo.mastodonServers`
                        -- instead of `.servers` -- but unlike a real `FederatedServer`, browsing a
                        -- Mastodon instance needs no negotiation/connection at all (see
                        -- `Shared.Federation.Mastodon.fetchPosts`'s own doc: it's a plain
                        -- unauthenticated `GET`), so this can just fold straight into `newModel`
                        -- rather than firing its own `Cmd`s. `configuredByDefault` alone decides
                        -- whether an instance gets added to the browse list at all;
                        -- `pinnedByDefault` alone decides whether it starts `enabled` (a merely
                        -- `configuredByDefault` one is added but starts switched off, for the user
                        -- to opt into) -- same split `federatedServerCmds` below already makes for
                        -- real `FederatedServer`s.
                        defaultBrowsedMastodonInstances : List BrowsedMastodonInstance
                        defaultBrowsedMastodonInstances =
                            config.federationInfo
                                |> Maybe.map .mastodonServers
                                |> Maybe.withDefault []
                                |> List.filter
                                    (\ms ->
                                        Maybe.withDefault False ms.configuredByDefault || Maybe.withDefault False ms.pinnedByDefault
                                    )
                                |> List.map
                                    (\ms ->
                                        { host = ms.domain
                                        , enabled = Maybe.withDefault False ms.pinnedByDefault
                                        , logoUrl = Nothing
                                        , displayName = Nothing
                                        , sortOrder = 0
                                        }
                                    )

                        -- Appended at the back (like `federatedServerCmds`'s own servers, via
                        -- `appendToEnd`), each getting the next sequential back `sortOrder` so
                        -- they keep their own relative order among themselves too.
                        newlyAddedMastodonInstances : List BrowsedMastodonInstance
                        newlyAddedMastodonInstances =
                            defaultBrowsedMastodonInstances
                                |> List.filter (\di -> not (List.any (\i -> i.host == di.host) model.browsedMastodonInstances))
                                |> List.indexedMap (\idx di -> { di | sortOrder = nextBackSortOrder model + idx })

                        newModel : Model
                        newModel =
                            { model
                                | mainFrontendHost = resolvedFrontend
                                , servers = RellmServers.upsertRellmServer 0 server model.servers
                                , browsingHostConfigResolved = True
                                , browsedMastodonInstances = model.browsedMastodonInstances ++ newlyAddedMastodonInstances
                            }

                        -- Fetches each newly-added default instance's logo/name, same as
                        -- `BrowseMastodonInstanceClicked` does for a manually-added one.
                        mastodonInstanceLogoCmds : List (Cmd Msg)
                        mastodonInstanceLogoCmds =
                            newlyAddedMastodonInstances
                                |> List.map (\i -> Task.attempt (GotMastodonInstanceInfoResult i.host) (MastodonServers.fetchMastodonInstanceInfoTask i.host))

                        -- The base host may recommend other servers to federate with (see
                        -- `federation.proto`'s `FederatedServer`). At this first-setup moment
                        -- (this whole branch only runs the first time we've ever seen this
                        -- browsing host -- see `init`'s `browsingHostAlreadyKnown`), connect to
                        -- each one that's `configuredByDefault`, appending it to the *end* of
                        -- the server list once negotiated (see `RellmServers.upsertRellmServerAppend`) -- unlike
                        -- a server added later (which lands right after the current server, see
                        -- `RellmServers.upsertRellmServer`), these are recommendations the user didn't ask for, so
                        -- they shouldn't jump ahead of any server already in the list.
                        -- `pinnedByDefault` ones are enabled immediately, the rest added
                        -- disabled for the user to opt into.
                        federatedServerCmds : List (Cmd Msg)
                        federatedServerCmds =
                            config.federationInfo
                                |> Maybe.map .servers
                                |> Maybe.withDefault []
                                |> List.filter
                                    (\fs ->
                                        fs.host /= resolvedFrontend && Maybe.withDefault False fs.configuredByDefault
                                    )
                                |> List.map
                                    (\fs ->
                                        RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) fs.host
                                            |> Task.attempt (GotReconnectResult fs.host (Maybe.withDefault False fs.pinnedByDefault) True)
                                    )
                    in
                    -- `refreshPermissionsForServer` persists (this server's own addition/
                    -- `mainFrontendHost` change included) once it settles -- see its own doc.
                    -- `browsedMastodonInstances` uses its own separate port, so its default-browsed
                    -- additions above need their own explicit persist here rather than riding along.
                    ( newModel
                    , Cmd.batch
                        (refreshPermissionsForServer server newModel.accounts
                            :: Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel)
                            :: federatedServerCmds
                            ++ mastodonInstanceLogoCmds
                        )
                    )

                Err _ ->
                    -- Still settles this server's startup-sweep unit, if one's pending -- see
                    -- `settleStartupUnit`.
                    settleStartupUnit { model | browsingHostConfigResolved = True }

        AccountsAndServersBroadcastReceived value ->
            case Decode.decodeValue persistedStateDecoder value of
                Err _ ->
                    ( model, Cmd.none )

                Ok persisted ->
                    let
                        -- Every host the broadcast still lists, keeping this tab's existing
                        -- entry (connected or disconnected -- see `RellmServer.connected`) in place
                        -- if it has one, adopting the broadcasting tab's `enabled` flag;
                        -- otherwise seeding a fresh disconnected placeholder (e.g. a server
                        -- added in another tab this one hasn't reconnected to yet -- mirrors
                        -- `init`'s own seeding). Drops any host this tab knows about that the
                        -- broadcast no longer lists (removed there via `RemoveServerClicked`).
                        keptServers : List RellmServer
                        keptServers =
                            persisted.servers
                                |> List.map
                                    (\ps ->
                                        model.servers
                                            |> List.filter (\s -> s.frontendHost == ps.frontendHost)
                                            |> List.head
                                            |> Maybe.map (\s -> { s | enabled = ps.enabled, sortOrder = ps.sortOrder })
                                            |> Maybe.withDefault (RellmServers.disconnectedRellmServer ps)
                                    )

                        -- Hosts already connected -- no need to attempt another reconnect for
                        -- those; anything else (never known, or known but still disconnected)
                        -- gets one, mirroring `init`'s `reconnectCmds`.
                        connectedHosts : List String
                        connectedHosts =
                            keptServers |> List.filter (\s -> s.connected /= Nothing) |> List.map .frontendHost

                        newServerCmds : List (Cmd Msg)
                        newServerCmds =
                            persisted.servers
                                |> List.filter (\ps -> not (List.member ps.frontendHost connectedHosts))
                                |> List.map
                                    (\ps ->
                                        RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) ps.frontendHost
                                            |> Task.attempt (GotReconnectResult ps.frontendHost ps.enabled False)
                                    )

                        -- Same as `init`'s `missingServerHosts`/`missingServerCmds`: accounts
                        -- whose server host isn't in `persisted.servers` at all (stale/
                        -- corrupted state in the broadcasting tab) still deserve a reconnect
                        -- attempt here.
                        missingServerHosts : List String
                        missingServerHosts =
                            persisted.accounts
                                |> List.map .server
                                |> List.filter (\host -> not (List.any (\ps -> ps.frontendHost == host) persisted.servers))
                                |> Set.fromList
                                |> Set.toList

                        missingServerCmds : List (Cmd Msg)
                        missingServerCmds =
                            List.map
                                (\host ->
                                    RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) host
                                        |> Task.attempt (GotReconnectResult host (List.any (\a -> a.server == host && a.enabled) persisted.accounts) False)
                                )
                                missingServerHosts

                        newModel : Model
                        newModel =
                            { model
                                | accounts = persisted.accounts
                                , servers = keptServers
                            }
                    in
                    ( newModel, Cmd.batch (newServerCmds ++ missingServerCmds) )

        BlueskyAccountsBroadcastReceived value ->
            -- Unlike `AccountsAndServersBroadcastReceived`'s `servers`, a `BlueskyAccount` carries no
            -- separate "connected this session" state to preserve -- the broadcast value is already
            -- the other tab's complete, authoritative list (same shape `persistBlueskyAccounts` itself
            -- persists), so this can just replace `blueskyAccounts` outright.
            case Decode.decodeValue BlueskyAccounts.decoder value of
                Ok accounts ->
                    ( { model | blueskyAccounts = accounts }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        MastodonAccountsAndServersBroadcastReceived value ->
            -- Same reasoning as `BlueskyAccountsBroadcastReceived` -- a full, authoritative
            -- replacement of both fields this port bundles together.
            case Decode.decodeValue mastodonAccountsAndServersDecoder value of
                Ok mastodon ->
                    ( { model | mastodonAccounts = mastodon.accounts, browsedMastodonInstances = mastodon.browsedInstances }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        ToggleAccountEnabled id ->
            let
                toggledAccounts : List RellmAccount
                toggledAccounts =
                    List.map
                        (\account ->
                            if rellmAccountId account == id then
                                { account | enabled = not account.enabled }

                            else
                                account
                        )
                        model.accounts

                justEnabledAccount : Maybe RellmAccount
                justEnabledAccount =
                    toggledAccounts
                        |> List.filter (\a -> rellmAccountId a == id && a.enabled)
                        |> List.head

                -- Only one account per server may be enabled (signed in) at a time --
                -- enabling this one disables any other account already enabled on the
                -- same server.
                exclusiveAccounts : List RellmAccount
                exclusiveAccounts =
                    case justEnabledAccount of
                        Just account ->
                            RellmAccounts.disableOtherRellmAccountsOnServer id account.server toggledAccounts

                        Nothing ->
                            toggledAccounts

                newServers : List RellmServer
                newServers =
                    case justEnabledAccount of
                        Just account ->
                            RellmServers.enableRellmServerFor account.server model.servers

                        Nothing ->
                            model.servers

                newModel : Model
                newModel =
                    { model | accounts = exclusiveAccounts, servers = newServers }

                refreshCmd : Cmd Msg
                refreshCmd =
                    justEnabledAccount
                        |> Maybe.andThen
                            (\account ->
                                RellmServers.rellmServerForHost newModel.servers account.server
                                    |> Maybe.map (\server -> refreshPermissions server account)
                            )
                        |> Maybe.withDefault Cmd.none
            in
            ( newModel, Cmd.batch [ persist newModel, refreshCmd ] )

        RemoveAccountClicked id ->
            -- Doesn't actually remove the account yet -- starts its fade-out
            -- (see `accountAnimations`), which sends `FinishRemoveAccount` once
            -- that finishes to do the real removal. Keyed by `combinedAccountItemKey`'s
            -- `"account:"` namespace, same as every other `CombinedAccountItem` kind sharing this
            -- dict -- `FinishRemoveAccount` itself still takes the bare `id`, since that's what
            -- `rellmAccountId`/`Shared.ConfirmAccountDelete` actually compare against.
            let
                key : String
                key =
                    "account:" ++ id

                currentState : UI.Flip.State Msg
                currentState =
                    Dict.get key model.accountAnimations |> Maybe.withDefault UI.Flip.restingState
            in
            ( { model | accountAnimations = Dict.insert key (UI.Flip.remove (FinishRemoveAccount id) currentState) model.accountAnimations }
            , Cmd.none
            )

        FinishRemoveAccount id ->
            let
                newModel : Model
                newModel =
                    { model
                        | accounts = List.filter (\account -> rellmAccountId account /= id) model.accounts
                        , accountAnimations = Dict.remove ("account:" ++ id) model.accountAnimations
                    }
            in
            ( newModel, persist newModel )

        MoveAccountItemUpClicked id ->
            ( model
            , UI.Flip.beginReorder combinedAccountItemKey
                accountRowDomId
                (\movedId neighborId _ result -> GotPreMoveAccountItemPositions movedId neighborId result)
                -1
                id
                (combinedAccountItems model)
            )

        MoveAccountItemDownClicked id ->
            ( model
            , UI.Flip.beginReorder combinedAccountItemKey
                accountRowDomId
                (\movedId neighborId _ result -> GotPreMoveAccountItemPositions movedId neighborId result)
                1
                id
                (combinedAccountItems model)
            )

        GotPreMoveAccountItemPositions id neighborId (Err _) ->
            let
                newModel : Model
                newModel =
                    swapAccountItemSortOrders id neighborId model
            in
            ( newModel, persistCombinedItemOrder newModel )

        GotPreMoveAccountItemPositions id neighborId (Ok ( movedEl, neighborEl )) ->
            let
                newModel : Model
                newModel =
                    swapAccountItemSortOrders id neighborId model
            in
            ( { newModel
                | moveAnimations =
                    UI.Flip.applyReorder UI.Flip.Vertical AccountItemMoveSettled id neighborId movedEl neighborEl newModel.moveAnimations
              }
            , persistCombinedItemOrder newModel
            )

        MoveServerFeedItemLeftClicked id ->
            ( model
            , UI.Flip.beginReorder combinedServerFeedItemKey
                serverFeedItemChipDomId
                (\movedId neighborId _ result -> GotPreMoveServerFeedItemPositions movedId neighborId result)
                -1
                id
                (combinedServerFeedItems model)
            )

        MoveServerFeedItemRightClicked id ->
            ( model
            , UI.Flip.beginReorder combinedServerFeedItemKey
                serverFeedItemChipDomId
                (\movedId neighborId _ result -> GotPreMoveServerFeedItemPositions movedId neighborId result)
                1
                id
                (combinedServerFeedItems model)
            )

        GotPreMoveServerFeedItemPositions id neighborId (Err _) ->
            let
                newModel : Model
                newModel =
                    swapServerFeedItemSortOrders id neighborId model
            in
            ( newModel, persistCombinedItemOrder newModel )

        GotPreMoveServerFeedItemPositions id neighborId (Ok ( chipEl, neighborEl )) ->
            let
                newModel : Model
                newModel =
                    swapServerFeedItemSortOrders id neighborId model
            in
            ( { newModel
                | serverMoveAnimations =
                    UI.Flip.applyReorder UI.Flip.Horizontal ServerFeedItemMoveSettled id neighborId chipEl neighborEl newModel.serverMoveAnimations
              }
            , persistCombinedItemOrder newModel
            )

        AnimateMove animMsg ->
            let
                step : String -> UI.Flip.MoveState Msg -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) )
                step key state ( states, cmds ) =
                    let
                        ( newState, cmd ) =
                            UI.Flip.moveAnimate animMsg state
                    in
                    ( Dict.insert key newState states, cmd :: cmds )

                ( newMoveAnimations, moveCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.moveAnimations

                ( newServerMoveAnimations, serverMoveCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.serverMoveAnimations
            in
            ( { model | moveAnimations = newMoveAnimations, serverMoveAnimations = newServerMoveAnimations }
            , Cmd.batch (moveCmds ++ serverMoveCmds)
            )

        AccountItemMoveSettled id ->
            ( { model | moveAnimations = Dict.update id (Maybe.map (\state -> { state | moving = False })) model.moveAnimations }
            , Cmd.none
            )

        ServerFeedItemMoveSettled id ->
            ( { model | serverMoveAnimations = Dict.update id (Maybe.map (\state -> { state | moving = False })) model.serverMoveAnimations }
            , Cmd.none
            )

        AnimateItemFlip animMsg ->
            let
                step : String -> UI.Flip.State Msg -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) )
                step key state ( states, cmds ) =
                    let
                        ( newState, cmd ) =
                            UI.Flip.animate animMsg state
                    in
                    ( Dict.insert key newState states, cmd :: cmds )

                ( newAccountAnimations, accountCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.accountAnimations

                ( newServerAnimations, serverCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.serverAnimations
            in
            ( { model | accountAnimations = newAccountAnimations, serverAnimations = newServerAnimations }
            , Cmd.batch (accountCmds ++ serverCmds)
            )

        ToggleServerEnabled frontendHost ->
            let
                wasEnabled : Bool
                wasEnabled =
                    RellmServers.rellmServerForHost model.servers frontendHost
                        |> Maybe.map .enabled
                        |> Maybe.withDefault False

                newModel : Model
                newModel =
                    { model
                        | servers =
                            List.map
                                (\server ->
                                    if server.frontendHost == frontendHost then
                                        { server | enabled = not server.enabled }

                                    else
                                        server
                                )
                                model.servers

                        -- Disabling a server takes its accounts along with it -- an account
                        -- signed into a server that's no longer included in aggregated data
                        -- shouldn't itself keep counting as "signed in" (e.g. for
                        -- `enabledAccounts`, or the Home feed). Re-enabling the server
                        -- doesn't reverse this automatically -- that's a deliberate,
                        -- separate choice per account, same as signing in fresh.
                        , accounts =
                            if wasEnabled then
                                List.map
                                    (\account ->
                                        if account.server == frontendHost then
                                            { account | enabled = False }

                                        else
                                            account
                                    )
                                    model.accounts

                            else
                                model.accounts
                    }
            in
            ( newModel, persist newModel )

        ReconnectServerClicked frontendHost ->
            -- Manual retry for a disconnected server (see `RellmServer.connected`) --
            -- functionally identical to `init`'s own `reconnectCmds`, just fired
            -- on demand rather than at startup. Keeps whatever `enabled` this
            -- host currently has; `GotReconnectResult` replaces the placeholder
            -- in place (preserving its position) on success, or leaves it
            -- disconnected on failure.
            let
                enabled : Bool
                enabled =
                    RellmServers.rellmServerForHost model.servers frontendHost
                        |> Maybe.map .enabled
                        |> Maybe.withDefault False
            in
            ( model
            , RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) frontendHost
                |> Task.attempt (GotReconnectResult frontendHost enabled False)
            )

        AddServerClicked ->
            let
                host : String
                host =
                    String.trim model.accountForm.server
            in
            if String.isEmpty host then
                ( model, Cmd.none )

            else if List.any (\s -> s.frontendHost == host && s.connected /= Nothing) model.servers then
                ( model
                    |> updateAddServerForm (\f -> { f | status = Errored "That server is already in your list." })
                    |> updateForm (\f -> { f | status = clearErrored f.status })
                , Cmd.none
                )

            else
                -- Also reached for a host that's already in the list but currently
                -- disconnected (see `RellmServer.connected`) -- functions as that
                -- placeholder's "Reconnect" (see `ReconnectServerClicked`), just via
                -- the Add Server form instead of a dedicated button.
                ( model
                    |> updateAddServerForm (\f -> { f | status = Submitting })
                    |> updateForm (\f -> { f | status = clearErrored f.status })
                , RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) host
                    |> Task.attempt GotNewServerResult
                )

        GotNewServerResult result ->
            case result of
                Ok ( connection, config ) ->
                    let
                        newModel : Model
                        newModel =
                            { model
                                | servers = RellmServers.upsertRellmServer (nextFrontSortOrder model) (RellmServers.rellmServerFrom connection True config) model.servers
                                , addServerForm = emptyAddServerForm
                            }
                    in
                    -- The server just typed into the (shared) Server field is now valid, so
                    -- Username/Password become enabled -- move focus there, same as if the
                    -- user had hit Enter on an already-known server (see `formView`).
                    ( newModel
                    , Cmd.batch [ persist newModel, Task.attempt (\_ -> NoOp) (Dom.focus "account-form-username") ]
                    )

                Err err ->
                    ( updateAddServerForm (\f -> { f | status = Errored (grpcErrorToString err) }) model
                    , Cmd.none
                    )

        ToggleRecommendedServersExpanded ->
            let
                newlyExpanded : Bool
                newlyExpanded =
                    not model.recommendedServersExpanded

                -- Only fetch hosts we haven't already cached (see
                -- `recommendedServerConnections`'s own doc) -- reopening the
                -- strip after having already expanded it once this session
                -- shouldn't re-fetch everything from scratch.
                hostsToFetch : List String
                hostsToFetch =
                    if newlyExpanded then
                        recommendedFederatedServers model
                            |> List.map .host
                            |> List.filter (\host -> not (Dict.member host model.recommendedServerConnections))

                    else
                        []

                newModel : Model
                newModel =
                    { model
                        | recommendedServersExpanded = newlyExpanded

                        -- Seeded disconnected immediately (same idea as `init`'s own
                        -- `RellmServers.disconnectedRellmServer` seeding), so each chip has something to
                        -- render -- a "loading" look, via the same
                        -- `server-chip-disconnected` styling -- the instant the strip
                        -- expands, rather than staying blank until its fetch resolves.
                        , recommendedServerConnections =
                            List.foldl
                                (\host -> Dict.insert host (RellmServers.disconnectedRellmServer { frontendHost = host, enabled = False, sortOrder = 0 }))
                                model.recommendedServerConnections
                                hostsToFetch
                    }
            in
            ( newModel
            , hostsToFetch
                |> List.map
                    (\host ->
                        RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) host
                            |> Task.attempt (GotRecommendedServerConfig host)
                    )
                |> Cmd.batch
            )

        GotRecommendedServerConfig host result ->
            case result of
                Ok ( connection, config ) ->
                    ( { model | recommendedServerConnections = Dict.insert host (RellmServers.rellmServerFrom connection False config) model.recommendedServerConnections }
                    , Cmd.none
                    )

                Err _ ->
                    -- Leaves the disconnected placeholder `ToggleRecommendedServersExpanded`
                    -- already inserted in place -- same "still shows, just dimmed" treatment
                    -- as any other unreachable server chip.
                    ( model, Cmd.none )

        RecommendedServerClicked host ->
            -- Reuses the connection already cached in `recommendedServerConnections`
            -- (see `RellmServers.resolveHost`) if its fetch already resolved, rather than
            -- renegotiating one from scratch.
            ( model
            , RellmServers.resolveHost (RellmServers.isSecure req) (Dict.values model.recommendedServerConnections) host
                |> Task.attempt (GotRecommendedServerAddResult host)
            )

        GotRecommendedServerAddResult host result ->
            case result of
                Ok ( connection, config ) ->
                    let
                        -- An explicit tap on a recommended-server chip is exactly the
                        -- same kind of deliberate "add this server" action as
                        -- `GotNewServerResult`'s manual Add Server flow -- enabled
                        -- immediately, same as that.
                        newModel : Model
                        newModel =
                            { model
                                | servers = RellmServers.upsertRellmServer (nextFrontSortOrder model) (RellmServers.rellmServerFrom connection True config) model.servers
                                , recommendedServerConnections = Dict.remove host model.recommendedServerConnections
                            }
                    in
                    ( newModel, persist newModel )

                Err _ ->
                    ( model, Cmd.none )

        RemoveServerClicked frontendHost ->
            -- Same "fade first, actually remove once that finishes" deferral as
            -- `RemoveAccountClicked` -- see `serverAnimations`.
            if RellmAccounts.rellmServerHasRellmAccounts model.accounts frontendHost || frontendHost == model.mainFrontendHost then
                ( model, Cmd.none )

            else
                let
                    key : String
                    key =
                        "server:" ++ frontendHost

                    currentState : UI.Flip.State Msg
                    currentState =
                        Dict.get key model.serverAnimations |> Maybe.withDefault UI.Flip.restingState
                in
                ( { model | serverAnimations = Dict.insert key (UI.Flip.remove (FinishRemoveServer frontendHost) currentState) model.serverAnimations }
                , Cmd.none
                )

        FinishRemoveServer frontendHost ->
            let
                removedModel : Model
                removedModel =
                    { model
                        | servers = List.filter (\s -> s.frontendHost /= frontendHost) model.servers
                        , serverAnimations = Dict.remove ("server:" ++ frontendHost) model.serverAnimations

                        -- Drop any stale branding cached from before this host was
                        -- added (see `recommendedServerConnections`'s doc) -- otherwise
                        -- it reappears in the recommended strip still pointing at the
                        -- placeholder left behind by `GotRecommendedServerAddResult`'s
                        -- `Dict.remove`, and never gets refetched.
                        , recommendedServerConnections = Dict.remove frontendHost model.recommendedServerConnections
                    }

                -- If the strip is open right now, the chip for this host is already
                -- back on screen (it just became "recommended" again) -- refetch its
                -- branding immediately instead of waiting on a collapse/re-expand,
                -- mirroring `ToggleRecommendedServersExpanded`'s own fetch.
                needsRefetch : Bool
                needsRefetch =
                    removedModel.recommendedServersExpanded
                        && List.any (\fs -> fs.host == frontendHost) (recommendedFederatedServers removedModel)

                newModel : Model
                newModel =
                    if needsRefetch then
                        { removedModel
                            | recommendedServerConnections =
                                Dict.insert frontendHost
                                    (RellmServers.disconnectedRellmServer { frontendHost = frontendHost, enabled = False, sortOrder = 0 })
                                    removedModel.recommendedServerConnections
                        }

                    else
                        removedModel
            in
            ( newModel
            , Cmd.batch
                [ persist newModel
                , if needsRefetch then
                    RellmServers.negotiateRellmServerConfig (RellmServers.isSecure req) frontendHost
                        |> Task.attempt (GotRecommendedServerConfig frontendHost)

                  else
                    Cmd.none
                ]
            )

        ToggleAccountsPanel ->
            let
                newlyShown : Bool
                newlyShown =
                    not model.showAccountsPanel

                newModel : Model
                newModel =
                    { model | showAccountsPanel = newlyShown }
            in
            ( if newlyShown then
                repopulateBlankServerField newModel

              else
                collapseAddAccountFormIfIdle
                    (resetFocusedAccountContactMethods { newModel | recommendedServersExpanded = False, focusedAccount = Nothing })
            , Cmd.none
            )

        CloseAccountsPanel ->
            ( collapseAddAccountFormIfIdle
                (resetFocusedAccountContactMethods
                    { model
                        | showAccountsPanel = False
                        , createAccountConfirmation = Nothing
                        , acceptedCreateAccount = Nothing
                        , recommendedServersExpanded = False
                        , focusedAccount = Nothing
                    }
                )
            , Cmd.none
            )

        AccountAvatarClicked account ->
            if isFocusedAccount model account then
                ( resetFocusedAccountContactMethods { model | focusedAccount = Nothing }, Cmd.none )

            else
                ( resetFocusedAccountContactMethods { model | focusedAccount = Just account }, Cmd.none )

        CloseFocusedAccount ->
            ( resetFocusedAccountContactMethods { model | focusedAccount = Nothing }, Cmd.none )

        ContactMethodsMenuToggled ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | contactMethodsExpanded = not current.contactMethodsExpanded } }, Cmd.none )

        ContactMethodPhoneEditClicked ->
            case freshFocusedAccount model of
                Just account ->
                    let
                        current : RellmContactMethods
                        current =
                            currentFocusedAccountContactMethods model
                    in
                    ( { model
                        | focusedAccountContactMethods =
                            Just
                                { current
                                    | phoneEdit =
                                        Just
                                            { input = contactMethodEditValue "tel:" account.phone
                                            , visibility = account.phone |> Maybe.map .visibility |> Maybe.withDefault PRIVATE
                                            , status = RellmAccounts.Idle
                                            }
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        ContactMethodPhoneInputChanged input ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | phoneEdit = current.phoneEdit |> Maybe.map (\edit -> { edit | input = input }) } }
            , Cmd.none
            )

        ContactMethodPhoneVisibilityChanged text ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model
                | focusedAccountContactMethods =
                    Just
                        { current
                            | phoneEdit =
                                current.phoneEdit
                                    |> Maybe.map (\edit -> { edit | visibility = contactMethodVisibilityFromText text |> Maybe.withDefault edit.visibility })
                        }
              }
            , Cmd.none
            )

        ContactMethodPhoneCancelClicked ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | phoneEdit = Nothing } }, Cmd.none )

        ContactMethodPhoneHistoryToggled ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | phoneHistoryExpanded = not current.phoneHistoryExpanded } }, Cmd.none )

        ContactMethodEmailEditClicked ->
            case freshFocusedAccount model of
                Just account ->
                    let
                        current : RellmContactMethods
                        current =
                            currentFocusedAccountContactMethods model
                    in
                    ( { model
                        | focusedAccountContactMethods =
                            Just
                                { current
                                    | emailEdit =
                                        Just
                                            { input = contactMethodEditValue "mailto:" account.email
                                            , visibility = account.email |> Maybe.map .visibility |> Maybe.withDefault PRIVATE
                                            , status = RellmAccounts.Idle
                                            }
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        ContactMethodEmailInputChanged input ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | emailEdit = current.emailEdit |> Maybe.map (\edit -> { edit | input = input }) } }
            , Cmd.none
            )

        ContactMethodEmailVisibilityChanged text ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model
                | focusedAccountContactMethods =
                    Just
                        { current
                            | emailEdit =
                                current.emailEdit
                                    |> Maybe.map (\edit -> { edit | visibility = contactMethodVisibilityFromText text |> Maybe.withDefault edit.visibility })
                        }
              }
            , Cmd.none
            )

        ContactMethodEmailCancelClicked ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | emailEdit = Nothing } }, Cmd.none )

        ContactMethodEmailHistoryToggled ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | emailHistoryExpanded = not current.emailHistoryExpanded } }, Cmd.none )

        ContactMethodPhoneVerificationCodeChanged code ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | phoneVerification = current.phoneVerification |> Maybe.map (\pv -> { pv | code = code }) } }
            , Cmd.none
            )

        ContactMethodPhoneVerificationCooldownElapsed ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | phoneVerification = current.phoneVerification |> Maybe.map (\pv -> { pv | cooldownActive = False }) } }
            , Cmd.none
            )

        GotContactMethodPhoneSaveResult (Ok updatedUser) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( updateFocusedAccountFromUser updatedUser { model | focusedAccountContactMethods = Just { current | phoneEdit = Nothing } }
            , Cmd.none
            )

        GotContactMethodPhoneSaveResult (Err err) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model
                | focusedAccountContactMethods =
                    Just { current | phoneEdit = current.phoneEdit |> Maybe.map (\edit -> { edit | status = RellmAccounts.SubmitFailed (grpcErrorToString err) }) }
              }
            , Cmd.none
            )

        GotContactMethodEmailSaveResult (Ok updatedUser) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( updateFocusedAccountFromUser updatedUser { model | focusedAccountContactMethods = Just { current | emailEdit = Nothing } }
            , Cmd.none
            )

        GotContactMethodEmailSaveResult (Err err) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model
                | focusedAccountContactMethods =
                    Just { current | emailEdit = current.emailEdit |> Maybe.map (\edit -> { edit | status = RellmAccounts.SubmitFailed (grpcErrorToString err) }) }
              }
            , Cmd.none
            )

        GotContactMethodPhoneConsentResult (Ok updatedUser) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( updateFocusedAccountFromUser updatedUser { model | focusedAccountContactMethods = Just { current | phoneConsentStatus = RellmAccounts.Idle } }
            , Cmd.none
            )

        GotContactMethodPhoneConsentResult (Err err) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | phoneConsentStatus = RellmAccounts.SubmitFailed (grpcErrorToString err) } }, Cmd.none )

        GotContactMethodEmailConsentResult (Ok updatedUser) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( updateFocusedAccountFromUser updatedUser { model | focusedAccountContactMethods = Just { current | emailConsentStatus = RellmAccounts.Idle } }
            , Cmd.none
            )

        GotContactMethodEmailConsentResult (Err err) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model | focusedAccountContactMethods = Just { current | emailConsentStatus = RellmAccounts.SubmitFailed (grpcErrorToString err) } }, Cmd.none )

        GotContactMethodStartPhoneVerificationResult (Ok updatedContactMethod) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( updateFocusedAccountPhone updatedContactMethod
                { model
                    | focusedAccountContactMethods =
                        Just { current | phoneVerification = current.phoneVerification |> Maybe.map (\pv -> { pv | sendStatus = RellmAccounts.Idle, cooldownActive = True }) }
                }
            , Process.sleep 60000 |> Task.perform (\_ -> ContactMethodPhoneVerificationCooldownElapsed)
            )

        GotContactMethodStartPhoneVerificationResult (Err err) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model
                | focusedAccountContactMethods =
                    Just { current | phoneVerification = current.phoneVerification |> Maybe.map (\pv -> { pv | sendStatus = RellmAccounts.SubmitFailed (grpcErrorToString err) }) }
              }
            , Cmd.none
            )

        GotContactMethodVerifyPhoneCodeResult (Ok updatedContactMethod) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( updateFocusedAccountPhone updatedContactMethod { model | focusedAccountContactMethods = Just { current | phoneVerification = Nothing } }
            , Cmd.none
            )

        GotContactMethodVerifyPhoneCodeResult (Err err) ->
            let
                current : RellmContactMethods
                current =
                    currentFocusedAccountContactMethods model
            in
            ( { model
                | focusedAccountContactMethods =
                    Just { current | phoneVerification = current.phoneVerification |> Maybe.map (\pv -> { pv | verifyStatus = RellmAccounts.SubmitFailed (grpcErrorToString err) }) }
              }
            , Cmd.none
            )

        ShowAddAccountFormClicked ->
            ( { model | addAccountServerFormType = Just RellmServerFormType }, Cmd.none )

        AddAccountServerFormTypeSelected formType ->
            ( { model | addAccountServerFormType = Just formType }, Cmd.none )

        ReauthenticateButtonClicked account ->
            -- Reopens the (possibly-collapsed) Account form pre-filled with this
            -- account's server/username, focused straight on Password -- the
            -- quickest path back to a working access token once its refresh
            -- token's been rejected (see `GotPermissionsRefresh`).
            ( { model
                | addAccountServerFormType = Just RellmServerFormType
                , newAccountType = Just LoginToAccount
                , accountForm =
                    { server = account.server
                    , username = account.username
                    , password = ""
                    , status = Idle
                    , showPasswordAsText = False
                    }
              }
            , Task.attempt (\_ -> NoOp) (Dom.focus "account-form-password")
            )

        GotPermissionsRefresh accId result ->
            let
                newModel : Model
                newModel =
                    { model | accounts = RellmAccounts.applyPermissionsRefreshResult accId result model.accounts }
            in
            ( newModel, persist newModel )

        GotServerPermissionsRefresh results ->
            let
                newModel : Model
                newModel =
                    { model
                        | accounts =
                            List.foldl
                                (\( accId, result ) accounts -> RellmAccounts.applyPermissionsRefreshResult accId result accounts)
                                model.accounts
                                results
                    }
            in
            -- One `persist` for the whole server (every one of its accounts'
            -- results folded in above) rather than one per account -- see
            -- `refreshPermissionsForServer`'s own doc -- and, while `init`'s
            -- startup sweep is still in progress, deferred further still, into
            -- the single sweep-wide `persist` -- see `settleStartupUnit`/
            -- `Model.accessTokenRefreshChecked`.
            settleStartupUnit newModel

        MainServerSelected frontendHost ->
            if List.any (\s -> s.frontendHost == frontendHost) model.servers then
                let
                    newModel : Model
                    newModel =
                        { model | mainFrontendHost = frontendHost }
                            |> setServerField frontendHost
                in
                ( newModel, persist newModel )

            else
                ( model, Cmd.none )

        ResetMainFrontendHost ->
            let
                newModel : Model
                newModel =
                    { model | mainFrontendHost = model.browsingHost }
            in
            ( newModel, persist newModel )

        ServerChipClicked frontendHost ->
            ( setServerField frontendHost model, Cmd.none )

        SetWebUserInterfaceClicked id ui ->
            let
                maybeAccount : Maybe RellmAccount
                maybeAccount =
                    model.accounts |> List.filter (\a -> rellmAccountId a == id) |> List.head

                maybeServer : Maybe RellmServer
                maybeServer =
                    maybeAccount
                        |> Maybe.andThen (\a -> RellmServers.rellmServerForHost model.servers a.server)
            in
            case ( maybeAccount, maybeServer ) of
                ( Just account, Just server ) ->
                    ( model, setWebUserInterface server account ui )

                _ ->
                    ( model, Cmd.none )

        GotSetWebUserInterfaceResult result ->
            case result of
                Ok ( refreshedAccount, newConfig ) ->
                    let
                        newModel : Model
                        newModel =
                            { model
                                | accounts = RellmAccounts.upsertRellmAccount refreshedAccount model.accounts
                                , servers =
                                    List.map
                                        (\s ->
                                            if s.frontendHost == refreshedAccount.server then
                                                RellmServers.updateRellmServerConfiguration newConfig s

                                            else
                                                s
                                        )
                                        model.servers
                            }
                    in
                    ( newModel, persist newModel )

                Err _ ->
                    -- RellmServer unreachable, refresh token rejected, etc. -- the toggle just
                    -- doesn't visibly change; the admin can retry.
                    ( model, Cmd.none )

        RenameServerClicked id newName ->
            let
                maybeAccount : Maybe RellmAccount
                maybeAccount =
                    model.accounts |> List.filter (\a -> rellmAccountId a == id) |> List.head

                maybeServer : Maybe RellmServer
                maybeServer =
                    maybeAccount
                        |> Maybe.andThen (\a -> RellmServers.rellmServerForHost model.servers a.server)
            in
            case ( maybeAccount, maybeServer ) of
                ( Just account, Just server ) ->
                    ( model, renameServer server account newName )

                _ ->
                    ( model, Cmd.none )

        GotRenameServerResult result ->
            case result of
                Ok ( refreshedAccount, newConfig ) ->
                    let
                        newModel : Model
                        newModel =
                            { model
                                | accounts = RellmAccounts.upsertRellmAccount refreshedAccount model.accounts
                                , servers =
                                    List.map
                                        (\s ->
                                            if s.frontendHost == refreshedAccount.server then
                                                RellmServers.updateRellmServerConfiguration newConfig s

                                            else
                                                s
                                        )
                                        model.servers
                            }
                    in
                    ( newModel, persist newModel )

                Err _ ->
                    -- RellmServer unreachable, refresh token rejected, etc. -- surfaced to
                    -- the caller (see `Pages.RellmServer.ServerIdentifier_`) via this same
                    -- `Result` passing through `Main.notifyPageOfSharedMsg`.
                    ( model, Cmd.none )

        ChangeServerShortNameClicked id newShortName ->
            let
                maybeAccount : Maybe RellmAccount
                maybeAccount =
                    model.accounts |> List.filter (\a -> rellmAccountId a == id) |> List.head

                maybeServer : Maybe RellmServer
                maybeServer =
                    maybeAccount
                        |> Maybe.andThen (\a -> RellmServers.rellmServerForHost model.servers a.server)
            in
            case ( maybeAccount, maybeServer ) of
                ( Just account, Just server ) ->
                    ( model, changeServerShortName server account newShortName )

                _ ->
                    ( model, Cmd.none )

        GotChangeServerShortNameResult result ->
            case result of
                Ok ( refreshedAccount, newConfig ) ->
                    let
                        newModel : Model
                        newModel =
                            { model
                                | accounts = RellmAccounts.upsertRellmAccount refreshedAccount model.accounts
                                , servers =
                                    List.map
                                        (\s ->
                                            if s.frontendHost == refreshedAccount.server then
                                                RellmServers.updateRellmServerConfiguration newConfig s

                                            else
                                                s
                                        )
                                        model.servers
                            }
                    in
                    ( newModel, persist newModel )

                Err _ ->
                    -- RellmServer unreachable, refresh token rejected, etc. -- surfaced to
                    -- the caller (see `AboutTab`) via this same `Result` passing
                    -- through `Main.notifyPageOfSharedMsg`, same as `GotRenameServerResult`.
                    ( model, Cmd.none )

        GotServerConfigSaveResult host newConfig ->
            let
                newModel : Model
                newModel =
                    { model
                        | servers =
                            List.map
                                (\s ->
                                    if s.frontendHost == host then
                                        RellmServers.updateRellmServerConfiguration newConfig s

                                    else
                                        s
                                )
                                model.servers
                    }
            in
            ( newModel, persist newModel )

        FocusInput domId ->
            ( model, Task.attempt (\_ -> NoOp) (Dom.focus domId) )

        -- A field's "clear" button (see `UI.elm`'s `fieldClearButton`):
        -- applies the actual clear (`ServerChanged ""`/`UsernameChanged
        -- ""`/`PasswordChanged ""`) and refocuses the now-empty field, so
        -- clearing it doesn't also lose your place in the form.
        ClearFieldClicked domId clearMsg ->
            let
                ( clearedModel, clearCmd ) =
                    sendUpdate req clearMsg model
            in
            ( clearedModel, Cmd.batch [ clearCmd, Task.attempt (\_ -> NoOp) (Dom.focus domId) ] )

        ServerConnected server ->
            if List.any (\s -> s.frontendHost == server.frontendHost && s.connected /= Nothing) model.servers then
                ( model, Cmd.none )

            else
                let
                    newModel : Model
                    newModel =
                        { model | servers = RellmServers.upsertRellmServer (nextFrontSortOrder model) server model.servers }
                in
                ( newModel, persist newModel )

        EnableNotificationsClicked account ->
            case RellmServers.rellmServerWebPushPublicKey model.servers account.server of
                Nothing ->
                    -- No `WebPushConfig` on this account's server (see `UI.accountRow`, which
                    -- only shows the button at all when this is `Just _`) -- unreachable in
                    -- practice.
                    ( model, Cmd.none )

                Just publicKey ->
                    ( { model
                        | notificationErrors = Dict.remove (rellmAccountId account) model.notificationErrors
                        , pendingNotificationAccountId = Just (rellmAccountId account)
                      }
                    , Ports.subscribeToPush
                        (Encode.object
                            [ ( "accountId", Encode.string (rellmAccountId account) )
                            , ( "publicKey", Encode.string publicKey )
                            ]
                        )
                    )

        DisableNotificationsClicked account ->
            let
                id : String
                id =
                    rellmAccountId account
            in
            case ( Dict.get id model.pushSubscriptions, RellmServers.rellmServerForHost model.servers account.server |> Maybe.andThen RellmServers.connectionOf ) of
                ( Just endpoint, Just connection ) ->
                    let
                        -- Multiple accounts on the same server share one real browser
                        -- subscription/`endpoint` (see `pushSubscriptions`'s own doc comment) --
                        -- only actually tear it down at the browser level if this was the *last*
                        -- account still relying on it, otherwise every other account sharing it
                        -- would silently stop receiving notifications too. Either way, this
                        -- account's own server-side registration is dropped.
                        lastAccountOnThisEndpoint : Bool
                        lastAccountOnThisEndpoint =
                            model.pushSubscriptions
                                |> Dict.toList
                                |> List.any (\( otherId, otherEndpoint ) -> otherId /= id && otherEndpoint == endpoint)
                                |> not
                    in
                    ( { model
                        | pushSubscriptions = Dict.remove id model.pushSubscriptions
                        , notificationErrors = Dict.remove id model.notificationErrors
                        , pendingNotificationAccountId = Just id
                      }
                    , Cmd.batch
                        [ if lastAccountOnThisEndpoint then
                            Ports.unsubscribeFromPush
                                (Encode.object
                                    [ ( "accountId", Encode.string id )
                                    , ( "endpoint", Encode.string endpoint )
                                    ]
                                )

                          else
                            Cmd.none
                        , RellmAccounts.performWithRellmAccount
                            connection
                            account
                            (\accessToken ->
                                Grpc.new Rellm.unregisterPushSubscription { endpoint = endpoint }
                                    |> Grpc.setHost (RellmServers.connectionUrl connection)
                                    |> RellmServers.withAccessToken (Just accessToken)
                                    |> Grpc.toTask
                            )
                            |> Task.map Tuple.first
                            |> Task.attempt GotUnregisterPushSubscriptionResult
                        , broadcastPushSubscriptionChangeCmd id Nothing
                        ]
                    )

                _ ->
                    -- Not currently tracked as subscribed (or the server's since gone
                    -- disconnected) -- nothing to unregister.
                    ( { model | pushSubscriptions = Dict.remove id model.pushSubscriptions }, Cmd.none )

        PushSubscriptionPortReceived value ->
            case Decode.decodeValue pushSubscriptionPortDecoder value of
                Ok ( id, Ok keys ) ->
                    case
                        model.accounts
                            |> List.filter (\a -> rellmAccountId a == id)
                            |> List.head
                            |> Maybe.andThen (\account -> RellmServers.rellmServerForHost model.servers account.server |> Maybe.andThen RellmServers.connectionOf |> Maybe.map (Tuple.pair account))
                    of
                        Just ( account, connection ) ->
                            ( model
                            , RellmAccounts.performWithRellmAccount
                                connection
                                account
                                (\accessToken ->
                                    Grpc.new Rellm.registerPushSubscription
                                        { endpoint = keys.endpoint, p256dhKey = keys.p256dhKey, authKey = keys.authKey }
                                        |> Grpc.setHost (RellmServers.connectionUrl connection)
                                        |> RellmServers.withAccessToken (Just accessToken)
                                        |> Grpc.toTask
                                )
                                |> Task.attempt GotRegisterPushSubscriptionResult
                            )

                        Nothing ->
                            ( model, Cmd.none )

                -- Permission denied, unsupported browser, subscribe failed, etc. -- surfaced via
                -- `notificationErrors` (see `UI.notificationsButton`) instead of silently no-oping,
                -- so a real failure (e.g. the browser blocking notifications for this site, or iOS
                -- Safari requiring the site be added to the Home Screen first) is actually visible.
                Ok ( id, Err reason ) ->
                    ( { model | notificationErrors = Dict.insert id reason model.notificationErrors }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        GotRegisterPushSubscriptionResult result ->
            case result of
                Ok ( refreshedAccount, pushSubscription ) ->
                    let
                        newModel : Model
                        newModel =
                            { model
                                | accounts = RellmAccounts.upsertRellmAccount refreshedAccount model.accounts

                                -- `Dict.insert`, not `Dict.singleton` -- `Ports.subscribeToPush`'s
                                -- JS side reuses the existing browser subscription when its key
                                -- already matches the one being requested (see its own doc
                                -- comment), which is exactly what happens when a *second* local
                                -- account on the same server enables notifications -- both truly
                                -- do end up sharing one active subscription, so both stay recorded
                                -- here instead of this one evicting the other.
                                , pushSubscriptions = Dict.insert (rellmAccountId refreshedAccount) pushSubscription.endpoint model.pushSubscriptions
                                , notificationErrors = Dict.remove (rellmAccountId refreshedAccount) model.notificationErrors
                            }
                    in
                    ( newModel
                    , Cmd.batch
                        [ persist newModel
                        , broadcastPushSubscriptionChangeCmd (rellmAccountId refreshedAccount) (Just pushSubscription.endpoint)
                        ]
                    )

                Err error ->
                    case model.pendingNotificationAccountId of
                        Just id ->
                            ( { model | notificationErrors = Dict.insert id (grpcErrorToString error) model.notificationErrors }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

        GotUnregisterPushSubscriptionResult result ->
            case result of
                Ok refreshedAccount ->
                    let
                        newModel : Model
                        newModel =
                            { model | accounts = RellmAccounts.upsertRellmAccount refreshedAccount model.accounts }
                    in
                    ( newModel, persist newModel )

                Err _ ->
                    ( model, Cmd.none )

        PushSubscriptionCheckReceived value ->
            ( { model | pendingPushSubscriptionCheck = Decode.decodeValue pushSubscriptionCheckDecoder value |> Result.withDefault Nothing }
            , Cmd.none
            )

        GotPushSubscriptionStatusResult endpoint result ->
            case result of
                Ok ( refreshedAccount, response ) ->
                    let
                        newModel : Model
                        newModel =
                            { model
                                | accounts = RellmAccounts.upsertRellmAccount refreshedAccount model.accounts
                                , pushSubscriptions =
                                    if response.registered then
                                        Dict.insert (rellmAccountId refreshedAccount) endpoint model.pushSubscriptions

                                    else
                                        model.pushSubscriptions
                            }
                    in
                    ( newModel, Cmd.none )

                Err _ ->
                    -- Best-effort hydration -- if the check itself fails (network blip, an
                    -- unrefreshable expired token, etc.), just leave that account showing as
                    -- disabled; nothing here was user-initiated, so there's no `notificationErrors`
                    -- entry to fill in the way a real click's failure gets one.
                    ( model, Cmd.none )

        PushSubscriptionChangeReceived value ->
            case Decode.decodeValue pushSubscriptionChangeDecoder value of
                Ok ( id, Just endpoint ) ->
                    ( { model
                        | pushSubscriptions = Dict.insert id endpoint model.pushSubscriptions
                        , notificationErrors = Dict.remove id model.notificationErrors
                      }
                    , Cmd.none
                    )

                Ok ( id, Nothing ) ->
                    ( { model | pushSubscriptions = Dict.remove id model.pushSubscriptions }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        DismissFederatedSignInNotice ->
            ( { model | federatedSignInNotice = Nothing }, Cmd.none )

        MastodonConnectClicked instanceHost ->
            let
                appId : String
                appId =
                    mastodonServerFor model instanceHost |> Maybe.map .appId |> Maybe.withDefault ""
            in
            ( { model | mastodonConnectPopupOpen = Just instanceHost }
            , Ports.facebookLoginPopup { provider = "mastodon", appId = appId, instanceHost = instanceHost }
            )

        GotMastodonLoginResult value ->
            case model.mastodonConnectPopupOpen of
                Nothing ->
                    -- Not our popup (see `Ports.facebookLoginResult`'s own doc on this port fanning
                    -- out to every subscriber) -- unreachable in practice, since nothing else in
                    -- this module ever sets `mastodonConnectPopupOpen`, but harmless either way.
                    ( model, Cmd.none )

                Just instanceHost ->
                    case MastodonAccounts.mastodonLoginResultDecoder value of
                        Ok loginResult ->
                            ( model
                            , Task.attempt (GotMastodonVerifyCredentialsResult instanceHost loginResult)
                                (MastodonAccounts.verifyMastodonCredentialsTask instanceHost loginResult.accessToken)
                            )

                        Err _ ->
                            ( { model | mastodonConnectPopupOpen = Nothing }, Cmd.none )

        GotMastodonVerifyCredentialsResult instanceHost loginResult (Ok username) ->
            let
                -- A reconnect (`ReconnectMastodonAccountClicked`'s own use of this same
                -- `MastodonConnectClicked` popup, see `UI.mastodonAccountRow`'s reauth button) lands
                -- back here as a brand new OAuth result for an instance/username that may already
                -- have a (now-stale) entry -- replace it in place rather than prepending a duplicate.
                account : MastodonAccounts.MastodonAccount
                account =
                    { instanceHost = instanceHost
                    , accessToken = loginResult.accessToken
                    , refreshToken = loginResult.refreshToken
                    , clientId = loginResult.clientId
                    , username = username
                    , sortOrder = nextFrontAccountSortOrder model
                    , needsReauth = False
                    }

                newModel : Model
                newModel =
                    { model
                        | mastodonConnectPopupOpen = Nothing
                        , mastodonAccounts =
                            account
                                :: List.filter
                                    (\a -> not (a.instanceHost == instanceHost && a.username == username))
                                    model.mastodonAccounts
                    }
            in
            ( newModel, Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel) )

        GotMastodonVerifyCredentialsResult _ _ (Err _) ->
            ( { model | mastodonConnectPopupOpen = Nothing }, Cmd.none )

        MastodonAccountRefreshed refreshedAccount ->
            -- `MastodonAccounts.performWithMastodonAccount` rotated `refreshedAccount`'s tokens (see
            -- its own doc) while resolving some other request -- persisted here the same way
            -- `BlueskyAccountRefreshed` persists a rotated Bluesky token pair.
            let
                newModel : Model
                newModel =
                    { model
                        | mastodonAccounts =
                            List.map
                                (\a ->
                                    if a.instanceHost == refreshedAccount.instanceHost && a.username == refreshedAccount.username then
                                        refreshedAccount

                                    else
                                        a
                                )
                                model.mastodonAccounts
                    }
            in
            ( newModel, Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel) )

        MarkMastodonAccountNeedsReauth instanceHost ->
            -- Sent once `MastodonAccounts.performWithMastodonAccount`'s own refresh-and-retry has
            -- been exhausted (see `MastodonAccounts.isReauthError`) -- mirrors
            -- `MarkBlueskyAccountNeedsReauth` exactly. There's no remove/disconnect UI for a Mastodon
            -- account yet (see `Model.mastodonAccounts`'s own doc), so this is currently surfaced only
            -- via `UI.mastodonAccountRow`'s own reauth affordance, with no automated recovery path.
            let
                newModel : Model
                newModel =
                    { model
                        | mastodonAccounts =
                            List.map
                                (\a ->
                                    if a.instanceHost == instanceHost then
                                        { a | needsReauth = True }

                                    else
                                        a
                                )
                                model.mastodonAccounts
                    }
            in
            ( newModel, Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel) )

        BlueskyHandleChanged handle ->
            ( { model | blueskyConnectForm = (\form -> { form | handle = handle }) model.blueskyConnectForm }, Cmd.none )

        BlueskyAppPasswordChanged appPassword ->
            ( { model | blueskyConnectForm = (\form -> { form | appPassword = appPassword }) model.blueskyConnectForm }, Cmd.none )

        BlueskyConnectClicked ->
            let
                form : BlueskyConnectForm
                form =
                    model.blueskyConnectForm
            in
            ( { model | blueskyConnectForm = { form | status = Submitting } }
            , Task.attempt GotBlueskyConnectResult (BlueskyAccounts.createSessionTask form.handle form.appPassword)
            )

        GotBlueskyConnectResult (Ok connectedAccount) ->
            let
                account : BlueskyAccount
                account =
                    { connectedAccount | sortOrder = nextFrontAccountSortOrder model }

                -- `account.enabled` is always `True` fresh out of `createSessionTask` -- disables
                -- every previously-connected Bluesky account so this new one becomes the sole
                -- enabled one. See `BlueskyAccounts.disableOtherBlueskyAccounts`'s own doc.
                newAccounts : List BlueskyAccount
                newAccounts =
                    BlueskyAccounts.disableOtherBlueskyAccounts account.handle (account :: model.blueskyAccounts)
            in
            ( { model | blueskyConnectForm = emptyBlueskyConnectForm, blueskyAccounts = newAccounts }
            , Cmd.batch
                [ Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList newAccounts)
                , Task.attempt (GotBlueskyProfileResult account.handle) (BlueskyAccounts.fetchProfileTask account.handle account.accessToken)
                ]
            )

        GotBlueskyConnectResult (Err err) ->
            ( { model | blueskyConnectForm = (\form -> { form | status = Errored (BlueskyAccounts.errorMessage err) }) model.blueskyConnectForm }
            , Cmd.none
            )

        GotBlueskyProfileResult _ (Err _) ->
            -- No avatar/name to show -- `UI.blueskyAccountRow` already falls back gracefully for
            -- `avatarUrl`/`displayName == Nothing`, so there's nothing more to do here.
            ( model, Cmd.none )

        GotBlueskyProfileResult handle (Ok profile) ->
            let
                newAccounts : List BlueskyAccount
                newAccounts =
                    List.map
                        (\a ->
                            if a.handle == handle then
                                { a | avatarUrl = profile.avatarUrl, displayName = profile.displayName }

                            else
                                a
                        )
                        model.blueskyAccounts
            in
            ( { model | blueskyAccounts = newAccounts }, Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList newAccounts) )

        RemoveBlueskyAccountClicked handle ->
            -- Same "fade first, actually remove once that finishes" deferral as
            -- `RemoveAccountClicked` -- see `accountAnimations`.
            let
                key : String
                key =
                    "bluesky:" ++ handle

                currentState : UI.Flip.State Msg
                currentState =
                    Dict.get key model.accountAnimations |> Maybe.withDefault UI.Flip.restingState
            in
            ( { model | accountAnimations = Dict.insert key (UI.Flip.remove (FinishRemoveBlueskyAccount handle) currentState) model.accountAnimations }
            , Cmd.none
            )

        FinishRemoveBlueskyAccount handle ->
            let
                newAccounts : List BlueskyAccount
                newAccounts =
                    List.filter (\a -> a.handle /= handle) model.blueskyAccounts
            in
            ( { model | blueskyAccounts = newAccounts, accountAnimations = Dict.remove ("bluesky:" ++ handle) model.accountAnimations }
            , Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList newAccounts)
            )

        ToggleBlueskyAccountEnabled handle ->
            let
                toggledAccounts : List BlueskyAccount
                toggledAccounts =
                    List.map
                        (\a ->
                            if a.handle == handle then
                                { a | enabled = not a.enabled }

                            else
                                a
                        )
                        model.blueskyAccounts

                justEnabled : Bool
                justEnabled =
                    toggledAccounts |> List.any (\a -> a.handle == handle && a.enabled)

                -- Only one Bluesky account may be enabled at a time -- enabling this one disables
                -- every other. See `BlueskyAccounts.disableOtherBlueskyAccounts`'s own doc.
                newAccounts : List BlueskyAccount
                newAccounts =
                    if justEnabled then
                        BlueskyAccounts.disableOtherBlueskyAccounts handle toggledAccounts

                    else
                        toggledAccounts
            in
            ( { model | blueskyAccounts = newAccounts }, Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList newAccounts) )

        BlueskyAccountRefreshed refreshedAccount ->
            -- `BlueskyAccounts.performWithBlueskyAccount` rotated `refreshedAccount`'s tokens (see
            -- its own doc) while resolving some other request (a post fetch, a profile refresh) --
            -- whichever caller reached that point sends this back so the rotated tokens actually get
            -- persisted; a stale, no-longer-working `accessToken`/`refreshToken` pair left in
            -- `blueskyAccounts` would otherwise force every subsequent request through a refresh of
            -- its own, and eventually fail outright once the old `refreshToken` itself gets rejected.
            let
                newAccounts : List BlueskyAccount
                newAccounts =
                    List.map
                        (\a ->
                            if a.handle == refreshedAccount.handle then
                                refreshedAccount

                            else
                                a
                        )
                        model.blueskyAccounts
            in
            ( { model | blueskyAccounts = newAccounts }, Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList newAccounts) )

        MarkBlueskyAccountNeedsReauth handle ->
            -- Sent once `BlueskyAccounts.performWithBlueskyAccount`'s own refresh-and-retry has been
            -- exhausted (see `BlueskyAccounts.isReauthError`) -- `handle`'s refresh token itself is no
            -- longer valid, so there's no automatic recovery left; `UI.blueskyAccountRow` shows a
            -- "Reconnect" button (`ReconnectBlueskyAccountClicked`) for any account in this state,
            -- mirroring `RellmAccount.needsPassword`'s own "Reauthentication Required" button.
            let
                newAccounts : List BlueskyAccount
                newAccounts =
                    List.map
                        (\a ->
                            if a.handle == handle then
                                { a | needsReauth = True }

                            else
                                a
                        )
                        model.blueskyAccounts
            in
            ( { model | blueskyAccounts = newAccounts }, Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList newAccounts) )

        ReconnectBlueskyAccountClicked handle ->
            -- Opens the same Bluesky tab/form `BlueskyConnectClicked` submits, pre-filled with
            -- `handle` -- there's no way to "refresh" past a fully revoked/expired refresh token
            -- short of a brand new `createSessionTask` call with a fresh App Password, same as
            -- disconnecting and reconnecting from scratch. `GotBlueskyConnectResult`'s own handling
            -- doesn't special-case this: a successful reconnect just prepends a new `BlueskyAccount`
            -- (see that handler), so the caller is expected to remove the old, now-redundant entry
            -- via `RemoveBlueskyAccountClicked` themselves if they don't want both.
            ( { model
                | addAccountServerFormType = Just BlueskyAccountFormType
                , blueskyConnectForm = { emptyBlueskyConnectForm | handle = handle }
              }
            , Cmd.none
            )

        BrowseMastodonInstanceInputChanged text ->
            ( { model | browseMastodonInstanceInput = text }, Cmd.none )

        BrowseMastodonInstanceClicked ->
            addBrowsedMastodonInstance { model | browseMastodonInstanceInput = "" } (String.trim model.browseMastodonInstanceInput)

        RecommendedMastodonServerClicked host ->
            addBrowsedMastodonInstance model host

        GotMastodonInstanceInfoResult _ (Err _) ->
            -- No logo/name to show -- `mastodonServerFeedChip` already falls back gracefully for
            -- `logoUrl`/`displayName == Nothing`, so there's nothing more to do here.
            ( model, Cmd.none )

        GotMastodonInstanceInfoResult host (Ok info) ->
            let
                newModel : Model
                newModel =
                    { model
                        | browsedMastodonInstances =
                            List.map
                                (\i ->
                                    if i.host == host then
                                        { i | logoUrl = info.logoUrl, displayName = info.displayName }

                                    else
                                        i
                                )
                                model.browsedMastodonInstances
                    }
            in
            ( newModel, Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel) )

        RemoveBrowsedMastodonInstanceClicked host ->
            -- Same "fade first, actually remove once that finishes" deferral as
            -- `RemoveServerClicked` -- see `serverAnimations`.
            let
                key : String
                key =
                    "mastodon:" ++ host

                currentState : UI.Flip.State Msg
                currentState =
                    Dict.get key model.serverAnimations |> Maybe.withDefault UI.Flip.restingState
            in
            ( { model | serverAnimations = Dict.insert key (UI.Flip.remove (FinishRemoveBrowsedMastodonInstance host) currentState) model.serverAnimations }
            , Cmd.none
            )

        FinishRemoveBrowsedMastodonInstance host ->
            let
                newModel : Model
                newModel =
                    { model
                        | browsedMastodonInstances = List.filter (\i -> i.host /= host) model.browsedMastodonInstances
                        , serverAnimations = Dict.remove ("mastodon:" ++ host) model.serverAnimations
                    }
            in
            ( newModel, Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel) )

        ToggleBrowsedMastodonInstanceEnabled host ->
            let
                newModel : Model
                newModel =
                    { model
                        | browsedMastodonInstances =
                            List.map
                                (\i ->
                                    if i.host == host then
                                        { i | enabled = not i.enabled }

                                    else
                                        i
                                )
                                model.browsedMastodonInstances
                    }
            in
            ( newModel, Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers newModel) )

        NoOp ->
            ( model, Cmd.none )


emptyForm : AccountForm
emptyForm =
    { server = "localhost"
    , username = ""
    , password = ""
    , status = Idle
    , showPasswordAsText = False
    }


emptyAddServerForm : AddServerForm
emptyAddServerForm =
    { status = Idle }


{-| Hosts of accounts we're keeping around but that are currently disconnected
(see `RellmServer.connected`) -- e.g. the server's down, moved, or otherwise
unreachable right now (see `GotReconnectResult`'s `Err` branch, which marks a
failed-to-reconnect server disconnected in place rather than dropping its
accounts). Also includes any host with no `RellmServer` entry at all, though that
should only ever be transient (see `init`'s `missingServerHosts`, which seeds
one for every account's host). Deduplicated, for a "Couldn't reach: host1,
host2" warning below the Servers strip.
-}
unreachableAccountHosts : Model -> List String
unreachableAccountHosts model =
    model.accounts
        |> List.map .server
        |> List.filter
            (\host ->
                model.servers
                    |> List.filter (\s -> s.frontendHost == host)
                    |> List.head
                    |> Maybe.map (\s -> s.connected == Nothing)
                    |> Maybe.withDefault True
            )
        |> Set.fromList
        |> Set.toList


{-| Whether `frontendHost` (trimmed) is a server we're actually connected to --
used by the Account form to decide whether Username/Password/Login/Create
Account should be enabled, or whether "Add Server" should be offered instead
(see `AddServerClicked`, which adds whatever's currently typed into the
(shared) `AccountForm.server` field).
-}
isKnownServer : Model -> String -> Bool
isKnownServer model frontendHost =
    List.any (\s -> s.frontendHost == String.trim frontendHost) model.servers


{-| The `mainFrontendHost` server's own `federation_info.servers` (see
`federation.proto`'s `FederatedServer`) that aren't already in `model.servers`
-- in practice, the ones that weren't `configured_by_default` (see
`GotMainServerResult`), so never got auto-added in the first place. Drives
`UI.recommendedServersStrip`'s "X Recommended Servers..." button; empty (so
that button never shows) once there's no main server yet, the main server has
no federation info, or every federated server it names is already known.
-}
recommendedFederatedServers : Model -> List FederatedServer
recommendedFederatedServers model =
    RellmServers.rellmServerForHost model.servers model.mainFrontendHost
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .federationInfo
        |> Maybe.map .servers
        |> Maybe.withDefault []
        |> List.filter (\fs -> not (isKnownServer model fs.host))


{-| Every admin-registered `MastodonServer` on `mainFrontendHost`'s own `FederationInfo`, regardless
of connection status -- `connectableMastodonServers`/`mastodonServerFor` both build on this.
-}
allMastodonServers : Model -> List MastodonServer
allMastodonServers model =
    RellmServers.rellmServerForHost model.servers model.mainFrontendHost
        |> Maybe.map RellmServers.configurationOf
        |> Maybe.andThen .federationInfo
        |> Maybe.map .mastodonServers
        |> Maybe.withDefault []


{-| Mirrors `recommendedFederatedServers` exactly (same `mainFrontendHost`-config sourcing), against
`federationInfo.mastodonServers` instead of `.servers` -- the Mastodon instances `UI.mastodonConnectButton`
shows for connecting, minus any already in `model.mastodonAccounts`. Unlike `FederatedServer`s, a
`MastodonServer` still shows here (with `UI.mastodonConnectButton`'s alert-icon treatment) even with a
blank `appId` -- there's no admin-configuration UI for the user themselves to fall back to, so
hiding it entirely would just look like the instance was never offered at all.
-}
connectableMastodonServers : Model -> List MastodonServer
connectableMastodonServers model =
    allMastodonServers model
        |> List.filter (\ms -> not (List.any (\a -> a.instanceHost == ms.domain) model.mastodonAccounts))


{-| Mirrors `recommendedFederatedServers` exactly, against `federationInfo.mastodonServers` instead
of `.servers` and `model.browsedMastodonInstances` instead of `model.servers` -- the admin-registered
Mastodon instances that aren't already browsed (see `browsedMastodonInstances`'s own doc on
`configuredByDefault`/`pinnedByDefault` auto-adding some of these already), driving
`UI.recommendedServersStrip`'s Mastodon chips. Distinct from `connectableMastodonServers` (which
filters against `model.mastodonAccounts`, an OAuth-connected _account_, for the separate "Connect a
real account" sub-section) -- clicking one of these just adds a no-login browsed feed, exactly like
`BrowseMastodonInstanceClicked`, so it's gated on `browsedMastodonInstances` instead.
-}
recommendedMastodonServers : Model -> List MastodonServer
recommendedMastodonServers model =
    allMastodonServers model
        |> List.filter (\ms -> not (List.any (\i -> i.host == ms.domain) model.browsedMastodonInstances))


{-| The admin-registered `MastodonServer` entry for `instanceHost`, if one exists -- what
`MastodonConnectClicked` needs to pass the real `appId` through to `Ports.facebookLoginPopup` instead
of dynamically self-registering a throwaway app on every single login (see that port's own
`"mastodon"` provider doc).
-}
mastodonServerFor : Model -> String -> Maybe MastodonServer
mastodonServerFor model instanceHost =
    allMastodonServers model |> List.filter (\ms -> ms.domain == instanceHost) |> List.head


{-| Whether `frontendHost` (trimmed) is this app's own "home" server --
`browsingHost` (the host actually being viewed from) or `mainFrontendHost`
(what that resolves to, once negotiated -- see `mainFrontendHost`'s own doc).
Username/password auth (Login/Create Account) is only ever offered for one of
these -- everywhere else, `signInFromButton`'s cross-server SSO hand-off is
the only way in, unless an admin has flipped
`DebugTab.allowUsernamePasswordForOtherHosts` (`model.debugTab`).
-}
isMainServer : Model -> String -> Bool
isMainServer model frontendHost =
    let
        trimmed : String
        trimmed =
            String.trim frontendHost
    in
    trimmed == model.browsingHost || trimmed == model.mainFrontendHost


{-| Whether the merged Add Account/Server form (see `AccountOrServerFormType`) should be shown
outright, rather than collapsed behind an "Add Account/Server" button -- always true while there are
no accounts yet (there'd be nothing for the button to hide behind), otherwise only once the user's
expanded it (see `ShowAddAccountFormClicked`).
-}
shouldShowAddAccountForm : Model -> Bool
shouldShowAddAccountForm model =
    List.isEmpty model.accounts || model.addAccountServerFormType /= Nothing


{-| `model.addAccountServerFormType`, falling back to `RellmServerFormType` when it's `Nothing` but
the form is showing anyway (the unconditional case above -- there'd be no tab selected yet). Mirrors
`UI.activeTab`'s own "fall back to a sane default" pattern for the outer Accounts Panel tabs.
-}
activeAddAccountServerFormType : Model -> AccountOrServerFormType
activeAddAccountServerFormType model =
    Maybe.withDefault RellmServerFormType model.addAccountServerFormType


{-| Whether the user has unsaved progress in the Add Account/Server form that
would be surprising to lose by auto-collapsing it back behind the button --
the Rellm tab has typed something into Username/Password, or its typed-in Server
names a host we're not connected to yet (so "Add Server" is the button
actually showing, rather than Login/Create Account); the Mastodon tab has a
typed-in instance to browse; the Bluesky tab has a typed handle or App
Password. Shared by `ToggleAccountsPanel` and `CloseAccountsPanel`, the panel's
two ways of closing -- see `collapseAddAccountFormIfIdle`.
-}
hasInProgressAddAccountInput : Model -> Bool
hasInProgressAddAccountInput model =
    let
        form : AccountForm
        form =
            model.accountForm
    in
    (String.trim form.username /= "")
        || (String.trim form.password /= "")
        || (model.newAccountType /= Nothing)
        || not (isKnownServer model form.server)
        || (String.trim model.browseMastodonInstanceInput /= "")
        || (String.trim model.blueskyConnectForm.handle /= "")
        || (String.trim model.blueskyConnectForm.appPassword /= "")


{-| Collapses the Add Account/Server form back behind its button when the
Accounts Panel closes, unless `hasInProgressAddAccountInput` says there's
progress worth keeping visible.
-}
collapseAddAccountFormIfIdle : Model -> Model
collapseAddAccountFormIfIdle model =
    if hasInProgressAddAccountInput model then
        model

    else
        { model | addAccountServerFormType = Nothing }


{-| Servers whose data should be included when aggregating across all of
them -- e.g. the Home page's recent-posts feed. Excludes disabled servers, as
well as ones that are currently disconnected (see `RellmServer.connected`) --
there's nothing to aggregate from a server that can't be reached right now.
-}
enabledServers : Model -> List RellmServer
enabledServers model =
    List.filter (\s -> s.enabled && s.connected /= Nothing) model.servers


updateAddServerForm : (AddServerForm -> AddServerForm) -> Model -> Model
updateAddServerForm fn model =
    { model | addServerForm = fn model.addServerForm }


updateForm : (AccountForm -> AccountForm) -> Model -> Model
updateForm fn model =
    { model | accountForm = fn model.accountForm }


{-| The `id` of the Create Account confirmation modal's scrolling policy-text
body -- shared between `Dom.getViewportOf` (see `GotCreateAccountServerInfo`)
and the `id` attribute `UI.createAccountConfirmationModal` puts on that same
element, so the two can't drift out of sync.
-}
createAccountModalBodyId : String
createAccountModalBodyId =
    "create-account-modal-body"


{-| Marks the pending Create Account confirmation (if any -- a no-op once the
user's already confirmed/canceled it away) as having had its policy text
fully read, per `GotCreateAccountModalViewport`/`CreateAccountModalScrolled`.
-}
markCreateAccountBottomReached : Model -> Model
markCreateAccountBottomReached model =
    { model
        | createAccountConfirmation =
            Maybe.map (\pending -> { pending | reachedBottom = True }) model.createAccountConfirmation
    }


{-| Resets an `Errored` status back to `Idle`, leaving `Submitting`/`Idle`
alone -- used to drop a stale error from the _other_ form (login vs. add-server)
sharing the Server field, without clobbering a submission that's actually
in flight (see `ServerChanged`, `LoginClicked`, `CreateAccountClicked`,
`AddServerClicked`).
-}
clearErrored : FormStatus -> FormStatus
clearErrored status =
    case status of
        Errored _ ->
            Idle

        other ->
            other


{-| Sets the (shared) Server field and clears any stale error left over from
either form -- both `AccountForm.status` and `AddServerForm.status` render
into the same message below the field (see `UI.elm`'s `formView`), so an old
error (a failed login, "That server is already in your list.", etc.) needs
clearing whenever the field changes for _any_ reason: typing
(`ServerChanged`), tapping a known server's chip (`ServerChipClicked`), or
picking a new main server (`MainServerSelected`). Also resets
`newAccountType`/`createAccountConfirmation`/`acceptedCreateAccount` back to
the Username-only step -- a Login/Create Account choice (or policy
confirmation) made for whatever server was previously named no longer
applies.
-}
setServerField : String -> Model -> Model
setServerField server model =
    { model | newAccountType = Nothing, createAccountConfirmation = Nothing, acceptedCreateAccount = Nothing }
        |> updateForm (\form -> { form | server = server, status = clearErrored form.status })
        |> updateAddServerForm (\f -> { f | status = clearErrored f.status })


{-| Repopulates the Server field with `mainFrontendHost` if it's blank -- e.g.
left cleared via the field's own "clear" button before the panel was last
closed. Called whenever the Accounts Panel reopens (`ToggleAccountsPanel`), so
a blanked-out Server field doesn't persist across a close/reopen cycle.
-}
repopulateBlankServerField : Model -> Model
repopulateBlankServerField model =
    if String.trim model.accountForm.server == "" then
        setServerField model.mainFrontendHost model

    else
        model


{-| Re-verifies a persisted `MastodonAccount`'s credentials once, at app startup (see `init`'s own
`Cmd.batch`) -- the only point today `mastodonAccounts` ever gets checked at all, since nothing else
in the app currently makes an authenticated request with one (see `Model.mastodonAccounts`'s own doc
on the "no remove/disconnect UI yet" first-pass limitation). Goes through
`MastodonAccounts.performWithMastodonAccount` so an access token that's since expired gets one
refresh-and-retry (see that function's own doc) before this gives up -- a bare `verifyMastodonCredentialsTask`
call would otherwise report a perfectly recoverable account as broken. `account.username` is
refreshed from the response too (not just assumed unchanged), same as the original connect flow --
a `MastodonAccountRefreshed`/`MarkMastodonAccountNeedsReauth` either way, so a stale or now-invalid
account doesn't just sit there silently until some future feature tries to use it.
-}
healthCheckMastodonAccountCmd : MastodonAccounts.MastodonAccount -> Cmd Msg
healthCheckMastodonAccountCmd account =
    MastodonAccounts.performWithMastodonAccount account (MastodonAccounts.verifyMastodonCredentialsTask account.instanceHost)
        |> Task.map (\( refreshedAccount, username ) -> MastodonAccountRefreshed { refreshedAccount | username = username })
        |> Task.onError
            (\err ->
                if MastodonAccounts.isReauthError err then
                    Task.succeed (MarkMastodonAccountNeedsReauth account.instanceHost)

                else
                    Task.succeed NoOp
            )
        |> Task.perform identity


{-| Refreshes a single account's permissions -- fired when it's individually
(re-)enabled (`ToggleAccountEnabled`), so permissions granted/revoked
elsewhere stay current without the user doing anything. See
`refreshPermissionsForServer` for the whole-server, startup-time equivalent.
-}
refreshPermissions : RellmServer -> RellmAccount -> Cmd Msg
refreshPermissions server account =
    RellmAccounts.refreshPermissionsTask server account
        |> Task.attempt (GotPermissionsRefresh (rellmAccountId account))


{-| `RellmAccounts.refreshPermissionsTask` for every account on the given server that isn't
already known to need a password -- not just enabled (signed-in) ones, so a
disabled account's access token is refreshed (and `needsPassword` discovered)
right along with everyone else's, rather than only once the user re-enables
it.

Skips accounts already flagged `needsPassword` -- their refresh token is
already known to be dead, and retrying it on every single reconnect (app
startup/reload, this same function's own other callers) would just fail the
exact same way every time while persisting/broadcasting a no-op change --
effectively a boot loop on every future load. The only way out of
`needsPassword` is a fresh login (`PasswordNeededClicked` -> `GotAuthResult`),
which doesn't go through here at all.

Runs every account's refresh as one batch, settling into a single
`GotServerPermissionsRefresh` once _all_ of them finish, rather than each
independently dispatching (and persisting the result of) its own
`GotPermissionsRefresh` -- so a server with several accounts produces one
`persist` (and cross-tab broadcast -- see `Ports.persistAccountsAndServers`)
instead of one per account. Two tabs both reconnecting to the same servers at
startup would otherwise each re-broadcast every single account's result as it
trickles in, each broadcast in turn nudging the _other_ tab's own
`AccountsAndServersBroadcastReceived` -- see `Model.accessTokenRefreshChecked`,
which defers this even further, into one `persist` for the whole startup
sweep.

-}
refreshPermissionsForServer : RellmServer -> List RellmAccount -> Cmd Msg
refreshPermissionsForServer server accounts =
    accounts
        |> List.filter (\a -> a.server == server.frontendHost && not a.needsPassword)
        |> List.map
            (\account ->
                RellmAccounts.refreshPermissionsTask server account
                    |> Task.map Ok
                    |> Task.onError (Err >> Task.succeed)
                    |> Task.map (Tuple.pair (rellmAccountId account))
            )
        |> Task.sequence
        |> Task.perform GotServerPermissionsRefresh


{-| How long `federatedSignInNotice` stays up before `DismissFederatedSignInNotice` auto-fires --
see that field's own doc.
-}
federatedSignInNoticeDuration : Float
federatedSignInNoticeDuration =
    5000


{-| Sets which frontend (`/`, `/flutter`, or `/elm`) `server` serves at its
root, via `ConfigureServer`, authenticated as `account` (refreshing its access
token first if needed -- see `Shared.MaybeAccountRequest`). Only ever invoked
for accounts with `ADMIN` on `server` (see `UI.elm`'s admin account panel);
the server itself also validates that permission.

`ConfigureServer` replaces the whole configuration rather than merging one
field, so this starts from the server's actual last-known `configuration`
(not any locally-edited-but-unsaved form state elsewhere) and only changes
`webUserInterface` within it.

-}
setWebUserInterface : RellmServer -> RellmAccount -> WebUserInterface -> Cmd Msg
setWebUserInterface server account ui =
    case ( RellmServers.connectionOf server, server.connected ) of
        ( Just connection, Just { configuration } ) ->
            let
                info : ServerInfo
                info =
                    Maybe.withDefault Proto.Rellm.defaultServerInfo configuration.serverInfo

                newConfig : ServerConfiguration
                newConfig =
                    { configuration | serverInfo = Just { info | webUserInterface = Just ui } }
            in
            RellmAccounts.performWithRellmAccount
                connection
                account
                (\accessToken ->
                    Grpc.new Rellm.configureServer newConfig
                        |> Grpc.setHost (RellmServers.connectionUrl connection)
                        |> RellmServers.withAccessToken (Just accessToken)
                        |> Grpc.toTask
                )
                |> Task.attempt GotSetWebUserInterfaceResult

        -- `server` is disconnected (see `RellmServer.connected`) -- callers only ever
        -- reach this for a server the account panel shows as connected, so
        -- this is unreachable in practice.
        _ ->
            Cmd.none


{-| Sets `server`'s display name via `ConfigureServer`, authenticated as
`account` -- same convention as `setWebUserInterface` just above (only ever
invoked for accounts with `ADMIN` on `server`, see
`Pages.RellmServer.ServerIdentifier_`'s rename button; the server itself also
validates that permission). Unlike `setWebUserInterface`, this re-fetches the
server's configuration fresh (`GetServerConfiguration`) right before writing
it back, rather than starting from `server.configuration` (this page's own
possibly-stale cache) -- same reasoning as `Components.Posts.updatePost`'s
own fetch-then-update -- so a config change made elsewhere (another tab, the
Tamagui app, another admin) in between isn't clobbered by this one only
changing `serverInfo.name`.
-}
renameServer : RellmServer -> RellmAccount -> String -> Cmd Msg
renameServer server account newName =
    case RellmServers.connectionOf server of
        -- `server` is disconnected (see `RellmServer.connected`) -- callers only ever
        -- reach this for a server the account panel shows as connected, so
        -- this is unreachable in practice.
        Nothing ->
            Cmd.none

        Just connection ->
            RellmAccounts.performWithRellmAccount
                connection
                account
                (\accessToken ->
                    Grpc.new Rellm.getServerConfiguration {}
                        |> Grpc.setHost (RellmServers.connectionUrl connection)
                        |> RellmServers.withAccessToken (Just accessToken)
                        |> Grpc.toTask
                        |> Task.andThen
                            (\freshConfig ->
                                let
                                    info : ServerInfo
                                    info =
                                        Maybe.withDefault Proto.Rellm.defaultServerInfo freshConfig.serverInfo

                                    newConfig : ServerConfiguration
                                    newConfig =
                                        { freshConfig | serverInfo = Just { info | name = Just newName } }
                                in
                                Grpc.new Rellm.configureServer newConfig
                                    |> Grpc.setHost (RellmServers.connectionUrl connection)
                                    |> RellmServers.withAccessToken (Just accessToken)
                                    |> Grpc.toTask
                            )
                )
                |> Task.attempt GotRenameServerResult


{-| Sets `server`'s short name (`ServerInfo.short_name`) via `ConfigureServer`, authenticated as
`account` -- same fetch-then-overlay-then-write shape as `renameServer` just above (only `name`
vs. `shortName` differs), for the same reason: don't clobber a config change made elsewhere in
between. A blank `newShortName` clears the field back to unset rather than saving an empty string,
so `Components.Pages.ServerInformationPage.AboutTab`'s display falls back to "Not set." instead of
showing nothing.
-}
changeServerShortName : RellmServer -> RellmAccount -> String -> Cmd Msg
changeServerShortName server account newShortName =
    case RellmServers.connectionOf server of
        -- `server` is disconnected (see `RellmServer.connected`) -- callers only ever
        -- reach this for a server the account panel shows as connected, so
        -- this is unreachable in practice.
        Nothing ->
            Cmd.none

        Just connection ->
            RellmAccounts.performWithRellmAccount
                connection
                account
                (\accessToken ->
                    Grpc.new Rellm.getServerConfiguration {}
                        |> Grpc.setHost (RellmServers.connectionUrl connection)
                        |> RellmServers.withAccessToken (Just accessToken)
                        |> Grpc.toTask
                        |> Task.andThen
                            (\freshConfig ->
                                let
                                    info : ServerInfo
                                    info =
                                        Maybe.withDefault Proto.Rellm.defaultServerInfo freshConfig.serverInfo

                                    trimmedShortName : Maybe String
                                    trimmedShortName =
                                        case String.trim newShortName of
                                            "" ->
                                                Nothing

                                            trimmed ->
                                                Just trimmed

                                    newConfig : ServerConfiguration
                                    newConfig =
                                        { freshConfig | serverInfo = Just { info | shortName = trimmedShortName } }
                                in
                                Grpc.new Rellm.configureServer newConfig
                                    |> Grpc.setHost (RellmServers.connectionUrl connection)
                                    |> RellmServers.withAccessToken (Just accessToken)
                                    |> Grpc.toTask
                            )
                )
                |> Task.attempt GotChangeServerShortNameResult


{-| Re-fetches `maybeAccountServer`'s server configuration fresh
(`GetServerConfiguration`) and writes back whatever `updateFn` makes of it
(via `ConfigureServer`) -- the same "reload, then write" dance
`Components.Users.updateUser`/`Shared.MarkdownPanel.saveServerInfoField` use
for a `User`/`ServerInfo` field, generalized here to the whole
`ServerConfiguration` since callers like
`Components.Pages.ServerInformationPage`'s permissions editors change a
top-level field (`anonymousUserPermissions`/`defaultUserPermissions`/
`basicUserPermissions`), not one nested in `serverInfo`. Returns a `Msg` to
dispatch if a token refresh happened, alongside the newly written
`ServerConfiguration` -- callers should patch it into `model.servers`
themselves via `GotServerConfigSaveResult`, same as a rename or `serverInfo`
field save.
-}
updateServerConfig :
    Model
    -> MaybeAccountServer
    -> (ServerConfiguration -> ServerConfiguration)
    -> Task Grpc.Error ( Maybe Msg, ServerConfiguration )
updateServerConfig accountsPanelModel maybeAccountServer updateFn =
    performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.getServerConfiguration {}
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> RellmServers.withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.andThen
                    (\freshConfig ->
                        Grpc.new Rellm.configureServer (updateFn freshConfig)
                            |> Grpc.setHost (RellmServers.rellmServerUrl server)
                            |> RellmServers.withAccessToken (Just token)
                            |> Grpc.toTask
                    )
        )



-- CONNECTING


grpcErrorToString : Grpc.Error -> String
grpcErrorToString err =
    case err of
        Grpc.BadUrl url ->
            "Invalid server address: " ++ url

        Grpc.Timeout ->
            "The request to the server timed out."

        Grpc.NetworkError ->
            "Couldn't reach the server. Check the address and your connection."

        Grpc.BadStatus { errMessage } ->
            case errMessage of
                "" ->
                    "The server rejected the request."

                -- Facebook's "confirm your identity" checkpoint (`facebook_sync::graph_request`'s
                -- own doc) -- there's nothing Rellm can do server-side, only the Page admin,
                -- via the Facebook app/website.
                "facebook_identity_verification_required" ->
                    "Facebook needs you to verify your identity before this can be posted. Open the Facebook app or facebook.com, confirm the prompt, then try again."

                "facebook_token_expired" ->
                    "This destination's Facebook connection has expired. Reconnect it from your Sync Destinations settings, then try again."

                _ ->
                    errMessage

        Grpc.BadBody _ ->
            "Received an unreadable response from the server."

        Grpc.UnknownGrpcStatus status ->
            "Unknown server error: " ++ status



-- PERSISTENCE
-- Tokens are stored with their expiration (if any), so an access token that's
-- expired (or about to) while the app was closed is refreshed on next use
-- rather than trusted as-is -- see `Shared.MaybeAccountRequest`.
-- Servers are persisted as just their frontendHost + enabled flag: backendHost/
-- port/tls/configuration are all rediscovered by reconnecting each session
-- rather than trusted from a (possibly stale) previous one.


{-| No-ops until `init`'s startup sweep has fully settled (see
`accessTokenRefreshChecked`/`finishStartupUnit`) -- otherwise every
individual reconnect/account-refresh that happens to land before then would
each write (and broadcast to every other open tab) their own sliver of
still-converging state, rather than the one coherent snapshot this waits for.
Anything that changes in the meantime (a user actually doing something in the
brief window before the sweep settles, vs. the sweep's own churn) still shows
up on screen immediately either way -- `model` itself is never gated, only
writing it out -- and gets swept up into that same first `persist` once
`finishStartupUnit` fires it.
-}
persist : Model -> Cmd Msg
persist model =
    if model.accessTokenRefreshChecked then
        Ports.persistAccountsAndServers (encodeState model)

    else
        Cmd.none


{-| Same as `persist`, plus the two other account/server-list ports -- for a mutation that can touch
any of the five lists a `CombinedServerFeedItem`/`CombinedAccountItem` might belong to (a cross-list
reorder swaps `sortOrder` values that can land in any pairing within either combined space) and so
can't tell in general which one(s) actually changed. Simpler and just as correct to always write out
all three ports together (covering all five lists between them) than to track that -- used by both
`GotPreMoveServerFeedItemPositions`/`GotPreMoveAccountItemPositions`, since either one's swap can
touch any of the five.
-}
persistCombinedItemOrder : Model -> Cmd Msg
persistCombinedItemOrder model =
    Cmd.batch
        [ persist model
        , Ports.persistBlueskyAccounts (BlueskyAccounts.encodeList model.blueskyAccounts)
        , Ports.persistMastodonAccountsAndServers (encodeMastodonAccountsAndServers model)
        ]


{-| Marks one "unit" of `init`'s startup sweep as finished -- one server
either failing to reconnect at all, or fully reconnecting and having every
one of its accounts' access tokens checked/refreshed (see
`refreshPermissionsForServer`/`GotServerPermissionsRefresh`). Once every unit
from `pendingServerChecks` has finished, flips `accessTokenRefreshChecked`.
Doesn't persist itself -- see `settleStartupUnit`, every call site's actual
entry point, which pairs this with the one `persist` call that actually needs
to happen. No-ops (returns `model` unchanged) once already checked.
-}
finishStartupUnit : Model -> Model
finishStartupUnit model =
    if model.accessTokenRefreshChecked then
        model

    else
        let
            stillPending : Int
            stillPending =
                model.pendingServerChecks - 1
        in
        { model | pendingServerChecks = stillPending, accessTokenRefreshChecked = stillPending <= 0 }


{-| `finishStartupUnit`, then `persist`s -- but only when that'll actually
write anything: either this unit is the one that just finished the _whole_
sweep (flipping `accessTokenRefreshChecked` from `False` to `True`), so
`persist` now finally goes through, capturing every server/account change
accumulated during the sweep in one write (see `persist`'s own doc); or the
sweep was already long done (ordinary steady-state operation -- e.g. a server
added well after startup, via `AccountsAndServersBroadcastReceived` or the Add
Server form), where `persist` behaves exactly as it always has, once per
call. Only skips persisting in between those two: this unit finished, but
others are still pending, so `persist` would just no-op anyway (see
`persist`) -- no need to call it.
-}
settleStartupUnit : Model -> ( Model, Cmd Msg )
settleStartupUnit model =
    let
        newModel : Model
        newModel =
            finishStartupUnit model
    in
    if newModel.accessTokenRefreshChecked then
        ( newModel, persist newModel )

    else
        ( newModel, Cmd.none )


encodeState : Model -> Encode.Value
encodeState model =
    Encode.object
        [ ( "accounts", Encode.list RellmAccounts.encodeRellmAccount model.accounts )
        , ( "servers", Encode.list RellmServers.encodePersistedRellmServer model.servers )
        ]


emptyPersistedState : PersistedState
emptyPersistedState =
    { accounts = [], servers = [] }


{-| Bundles `model.mastodonAccounts`/`model.browsedMastodonInstances` into
`Ports.persistMastodonAccountsAndServers`'s wire format -- see `MastodonAccountsAndServers`'s own
doc.
-}
encodeMastodonAccountsAndServers : Model -> Encode.Value
encodeMastodonAccountsAndServers model =
    Encode.object
        [ ( "accounts", Encode.list MastodonAccounts.encodeMastodonAccount model.mastodonAccounts )
        , ( "browsedInstances", Encode.list MastodonServers.encodeBrowsedMastodonInstance model.browsedMastodonInstances )
        ]


{-| Assigns fresh, sequential `sortOrder` values (see `assignMissingSortOrders`) to every server/
browsed-Mastodon-instance still carrying `missingSortOrderSentinel` -- i.e. essentially every one of
them, the first time a client loads a version of the app that has `sortOrder` at all. Doesn't touch
`blueskyAccounts` -- unlike a server or a browsed instance, a connected Bluesky account belongs to
the _account_ item space now (see `CombinedAccountItem`), migrated separately by
`migrateAccountItemSortOrders`.
-}
migrateServerFeedItemSortOrders : List PersistedRellmServer -> List BrowsedMastodonInstance -> ( List PersistedRellmServer, List BrowsedMastodonInstance )
migrateServerFeedItemSortOrders servers instances =
    let
        start : Int
        start =
            SortOrder.nextMigratedSortOrderStart [ List.map .sortOrder servers, List.map .sortOrder instances ]

        ( afterServers, migratedServers ) =
            SortOrder.assignMissingSortOrders start servers

        ( _, migratedInstances ) =
            SortOrder.assignMissingSortOrders afterServers instances
    in
    ( migratedServers, migratedInstances )


{-| Same idea as `migrateServerFeedItemSortOrders`, one level down (see `CombinedAccountItem`'s own
doc): assigns fresh `sortOrder` values to every Rellm account/connected Mastodon account/connected
Bluesky account still carrying `missingSortOrderSentinel`. `accounts`/`mastodonAccounts` are brand
new fields, so this is essentially every one of them the first time a client loads a version of the
app that has account `sortOrder` at all; `blueskyAccounts`' own `sortOrder` already existed (from
when it briefly meant a position in the _server_ feed space instead -- see `CombinedServerFeedItem`'s
own doc) so real values there are left as-is, reinterpreted in this now-shared account item space,
and only ever backfilled here for the rare pre-`sortOrder` straggler.
-}
migrateAccountItemSortOrders : List RellmAccount -> List MastodonAccount -> List BlueskyAccount -> ( List RellmAccount, List MastodonAccount, List BlueskyAccount )
migrateAccountItemSortOrders accounts mastodonAccounts blueskyAccounts =
    let
        start : Int
        start =
            SortOrder.nextMigratedSortOrderStart [ List.map .sortOrder accounts, List.map .sortOrder mastodonAccounts, List.map .sortOrder blueskyAccounts ]

        ( afterAccounts, migratedAccounts ) =
            SortOrder.assignMissingSortOrders start accounts

        ( afterMastodonAccounts, migratedMastodonAccounts ) =
            SortOrder.assignMissingSortOrders afterAccounts mastodonAccounts

        ( _, migratedBlueskyAccounts ) =
            SortOrder.assignMissingSortOrders afterMastodonAccounts blueskyAccounts
    in
    ( migratedAccounts, migratedMastodonAccounts, migratedBlueskyAccounts )


{-| The `PushManager.subscribe()` result Ports.pushSubscribed's JS side hands back on success --
see `RegisterPushSubscriptionRequest`, which this maps directly onto.
-}
type alias PushSubscriptionKeys =
    { endpoint : String
    , p256dhKey : String
    , authKey : String
    }


{-| Decodes `Ports.pushSubscribed`'s payload: `{ rellmAccountId, ok, endpoint, p256dhKey, authKey }` on
success, or `{ rellmAccountId, ok, error }` (`ok = False`) on failure -- see that port's own doc
comment. `rellmAccountId` comes back either way, so `PushSubscriptionPortReceived` can always tell which
account's `subscribeToPush` call this answers.
-}
pushSubscriptionPortDecoder : Decoder ( String, Result String PushSubscriptionKeys )
pushSubscriptionPortDecoder =
    Decode.field "accountId" Decode.string
        |> Decode.andThen
            (\id ->
                Decode.field "ok" Decode.bool
                    |> Decode.andThen
                        (\ok ->
                            if ok then
                                Decode.map3 PushSubscriptionKeys
                                    (Decode.field "endpoint" Decode.string)
                                    (Decode.field "p256dhKey" Decode.string)
                                    (Decode.field "authKey" Decode.string)
                                    |> Decode.map (\keys -> ( id, Ok keys ))

                            else
                                Decode.field "error" Decode.string
                                    |> Decode.map (\error -> ( id, Err error ))
                        )
            )


{-| `Ports.pushSubscriptionChecked`'s payload when the browser has an active Web Push subscription
-- see that port's own doc comment for why `publicKey` (not an `rellmAccountId`, which the Push API has
no concept of) is what identifies which account it belongs to.
-}
type alias PushSubscriptionCheck =
    { endpoint : String
    , publicKey : String
    }


{-| Decodes `Ports.pushSubscriptionChecked`'s payload: `null`, or `{ endpoint, publicKey }`.
-}
pushSubscriptionCheckDecoder : Decoder (Maybe PushSubscriptionCheck)
pushSubscriptionCheckDecoder =
    Decode.nullable
        (Decode.map2 PushSubscriptionCheck
            (Decode.field "endpoint" Decode.string)
            (Decode.field "publicKey" Decode.string)
        )


{-| Decodes `Ports.broadcastPushSubscriptionChange`/`pushSubscriptionChangeReceived`'s payload:
`{ rellmAccountId, endpoint }`, `endpoint` being the account's new endpoint (just enabled) or `null`
(just disabled).
-}
pushSubscriptionChangeDecoder : Decoder ( String, Maybe String )
pushSubscriptionChangeDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "accountId" Decode.string)
        (Decode.field "endpoint" (Decode.nullable Decode.string))


{-| Tells every other open tab on this origin that `id`'s own `pushSubscriptions` entry just
changed -- `Just endpoint` for an Enable, `Nothing` for a Disable -- so they immediately reflect it
instead of only picking it up on their own next reload. See `Ports.broadcastPushSubscriptionChange`'s
own doc comment for why this doesn't also persist anything.
-}
broadcastPushSubscriptionChangeCmd : String -> Maybe String -> Cmd Msg
broadcastPushSubscriptionChangeCmd id endpoint =
    Ports.broadcastPushSubscriptionChange
        (Encode.object
            [ ( "accountId", Encode.string id )
            , ( "endpoint", endpoint |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
            ]
        )


persistedStateDecoder : Decoder PersistedState
persistedStateDecoder =
    Decode.map2 PersistedState
        (Decode.field "accounts" (Decode.list RellmAccounts.rellmAccountDecoder))
        (Decode.field "servers" (Decode.list RellmServers.persistedRellmServerDecoder))


resolveAccountServer : Model -> MaybeAccountServer -> Maybe ( Maybe RellmAccount, RellmServer )
resolveAccountServer model ( maybeUserId, host ) =
    RellmServers.rellmServerForHost model.servers host
        |> Maybe.andThen
            (\server ->
                -- A known-but-disconnected server (see `RellmServer.connected`) can't
                -- actually be reached, so treat it the same as `host` not being a
                -- known server at all -- both end up failing with
                -- `Grpc.NetworkError` in `performWithAccountServer`/
                -- `performWithOptionalAccountServer`.
                if server.connected == Nothing then
                    Nothing

                else
                    Just
                        ( maybeUserId
                            |> Maybe.andThen (\userId -> model.accounts |> List.filter (\a -> a.userId == userId && a.server == host) |> List.head)
                        , server
                        )
            )


{-| Like `RellmAccounts.performWithRellmAccount`, but takes a `MaybeAccountServer` (resolved
fresh against `model`) instead of a live `RellmAccount`, and requires that it
resolve to one -- fails with `Grpc.NetworkError` if `host` isn't a known
server, or if no matching account is found (both meaning the caller
shouldn't have gotten this far; see e.g. `Shared.MarkdownPanel.resolve`'s
own pre-flight, user-facing gating). `req` gets the resolved `RellmServer` (for
`Grpc.setHost`) and access token string. Returns an already-built `Msg` to
dispatch (via whatever out-msg/`Effect` mechanism the caller already uses
for e.g. `Shared.AccountsPanelMsg`) if a token refresh happened, `Nothing`
otherwise -- callers never see the raw `AccessTokenResponse`.
-}
performWithAccountServer :
    Model
    -> MaybeAccountServer
    -> (RellmServer -> String -> Task Grpc.Error b)
    -> Task Grpc.Error ( Maybe Msg, b )
performWithAccountServer model maybeAccountServer req =
    case resolveAccountServer model maybeAccountServer of
        Just ( Just account, server ) ->
            case RellmServers.connectionOf server of
                -- `resolveAccountServer` only ever resolves to a connected `RellmServer`
                -- (see `RellmServer.connected`), so this is unreachable in practice.
                Nothing ->
                    Task.fail Grpc.NetworkError

                Just connection ->
                    RellmAccounts.performWithRellmAccountNotifying connection account (req server)
                        |> Task.map
                            (\( refreshedAccount, maybeResponse, result ) ->
                                ( Maybe.map (AccessTokenResponseReceived refreshedAccount) maybeResponse, result )
                            )

        _ ->
            Task.fail Grpc.NetworkError


{-| Like `performWithAccountServer`, but the account is optional: with a
`MaybeAccountServer` that resolves to a known account, authenticates
(refreshing first if needed) exactly like `performWithAccountServer`; with
`( Nothing, host )` (or a `userId` that doesn't resolve to an account),
performs `req` anonymously (no authorization header). Fails with
`Grpc.NetworkError` only if `host` itself isn't a known server.
-}
performWithOptionalAccountServer :
    Model
    -> MaybeAccountServer
    -> (RellmServer -> Maybe String -> Task Grpc.Error b)
    -> Task Grpc.Error ( Maybe Msg, b )
performWithOptionalAccountServer model maybeAccountServer req =
    case resolveAccountServer model maybeAccountServer of
        Just ( Just account, server ) ->
            case RellmServers.connectionOf server of
                -- `resolveAccountServer` only ever resolves to a connected `RellmServer`
                -- (see `RellmServer.connected`), so this is unreachable in practice.
                Nothing ->
                    Task.fail Grpc.NetworkError

                Just connection ->
                    RellmAccounts.performWithRellmAccountNotifying connection account (Just >> req server)
                        |> Task.map
                            (\( refreshedAccount, maybeResponse, result ) ->
                                ( Maybe.map (AccessTokenResponseReceived refreshedAccount) maybeResponse, result )
                            )

        Just ( Nothing, server ) ->
            req server Nothing |> Task.map (Tuple.pair Nothing)

        Nothing ->
            Task.fail Grpc.NetworkError
