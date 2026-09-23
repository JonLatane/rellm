module Shared.AccountsPanel.RellmAccounts exposing
    ( EmailEdit
    , PhoneEdit
    , PhoneVerification
    , RellmAccount
    , RellmAccountAuthTokens
    , RellmContactMethods
    , SubmitStatus(..)
    , Token
    , applyPermissionsRefreshResult
    , canUseAIModels
    , canUseSyncDestinations
    , canUseSyncSources
    , contactMethodDisplayValue
    , contactMethodEditValue
    , contactMethodVisibilities
    , contactMethodVisibilityFromText
    , contactMethodVisibilityText
    , disableOtherRellmAccountsOnServer
    , emptyRellmContactMethods
    , enabledRellmAccountForServer
    , encodeRellmAccount
    , encodeRellmAccountAuthTokens
    , isAdmin
    , performWithRellmAccount
    , performWithRellmAccountNotifying
    , refreshPermissionsTask
    , rellmAccountAuthTokensDecoder
    , rellmAccountAvatarUrl
    , rellmAccountDecoder
    , rellmAccountDisplayName
    , rellmAccountId
    , rellmServerHasRellmAccounts
    , resolveFederatedRellmAccountTokens
    , tokenFromExpirable
    , upsertRellmAccount
    )

{-| Everything about a Rellm `RellmAccount` that doesn't need `Shared.AccountsPanel.Model` itself to
make sense: the type and its close relatives (`RellmAccountAuthTokens`, `Token`), its encode/decode,
and every pure/plain-`Task` piece of "authenticate as this account" logic (access-token refresh,
`GetCurrentUser` permission refresh, `RellmAccount` list upserts). Imports `RellmServers` (its own
dependency root -- see that module's own doc) for `Connection`/`RellmServer` wherever an operation
needs to know which server it's authenticating against.

What's deliberately *not* here, and stays in `Shared.AccountsPanel` itself: the `Model` field this
lives in (`accounts`), and every `Msg`/`Cmd Msg`-constructing operation (`refreshPermissions`,
`refreshPermissionsForServer`, `setWebUserInterface`, `renameServer`, `changeServerShortName`,
`performWithAccountServer`, `performWithOptionalAccountServer`, and the plain `enabledAccounts`/
`hasAdminAccount`/etc. lookups that take the whole `Model`) -- those are `Shared.AccountsPanel.update`'s
own coordinating logic.

-}

import Grpc
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Proto.Rellm exposing (AccessTokenResponse, AIModel, ContactMethod, ExpirableToken, MarketSubscription, SyncDestination, SyncSource, User)
import Proto.Rellm.Permission exposing (Permission(..), fieldNumbersPermission)
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.AccountsPanel.RellmServers as RellmServers exposing (Connection, RellmServer)
import Shared.AccountsPanel.SortOrder exposing (sortOrderDecoder)
import Shared.Conversions exposing (int64ToInt, timestampToPosix)
import Task exposing (Task)
import Time


{-| A signed-into account on a server (identified by its `frontendHost`, e.g.
"jonline.io" -- see `RellmServer`). `enabled` is a lightweight, non-destructive
"signed in/out" toggle: disabling an account keeps its tokens around so it can
be re-enabled without logging in again. Fully forgetting an account
(`Shared.AccountsPanel.RemoveAccountClicked`) is the "traditional" sign out.

`permissions` is refreshed via `GetCurrentUser` whenever the account's server
reconnects (app startup/reload, or the account being re-enabled) -- see
`Shared.AccountsPanel.refreshPermissions` -- so it's usually current, though it can still lag
between those refreshes if permissions change server-side. That same refresh
is what discovers a `refreshToken` no longer works (revoked, expired past its
own grace period) -- see `Shared.AccountsPanel.GotPermissionsRefresh` -- setting `needsPassword`
so the account shows as needing to be signed back into with a password rather
than silently failing every request.

-}
type alias RellmAccount =
    { server : String
    , userId : String
    , username : String
    , refreshToken : Token
    , accessToken : Token
    , enabled : Bool
    , avatarMediaId : Maybe String
    , permissions : List Permission
    , realName : String
    , needsPassword : Bool
    , sortOrder : Int

    -- The signed-in user's own linked SyncDestinations/SyncSources/AIModels (see
    -- `Proto.Rellm.User`'s own doc on each field) -- refreshed alongside `permissions`/etc by
    -- `refreshPermissionsTask`. Login/CreateAccount (`GotAuthResult`) can't populate them either
    -- (same backend restriction), so they start empty there and only appear once the first
    -- refresh lands.
    , syncDestinations : List SyncDestination
    , syncSources : List SyncSource
    , aiModels : List AIModel
    , marketSubscriptions : List MarketSubscription

    -- Refreshed alongside `permissions`/etc (see `applyPermissionsRefreshResult`) from
    -- `User.mediaStorageBytesUsed`/`.mediaStorageLimitBytes` -- see those fields' own proto doc.
    -- `Nothing` limit means unlimited.
    , mediaStorageBytesUsed : Int
    , mediaStorageLimitBytes : Maybe Int

    -- The signed-in user's own Phone/Email `ContactMethod`s (see `Proto.Rellm.User`'s own doc on
    -- each field), same "refreshed alongside `permissions`/etc, unavailable until the first
    -- refresh lands" story as `syncDestinations`/etc above -- drives `UI.accountAvatarMenuView`'s
    -- own "Contact Methods" item/its nested edit UI (`Shared.AccountsPanel`'s `ContactMethod*`
    -- `Msg`s/`Model` fields).
    , phone : Maybe ContactMethod
    , email : Maybe ContactMethod
    }


{-| Status of an in-flight (or most recently failed) contact-method-related request -- `PhoneEdit`/
`EmailEdit`/`PhoneVerification`'s own status fields, plus `Shared.AccountsPanel.Model`'s
`focusedAccountPhoneConsentStatus`/`focusedAccountEmailConsentStatus`. Lives here (rather than
reusing `Shared.AccountsPanel.FormStatus`, which is `Idle`/`Submitting`/`Errored String`, the same
shape) so this whole contact-methods-editing cluster of types stays self-contained and portable --
originally ported from `Components.Pages.UserProfilePage.SubmitStatus`, matching name deliberately
kept, so that page's own copy can eventually just import this one instead.
-}
type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Live only while `Model.focusedAccount`'s Phone field (see
`Shared.AccountsPanel.Model.focusedAccountPhoneEdit`) is being edited -- ported from
`Components.Pages.UserProfilePage.PhoneEdit`, unchanged. `input` holds just the raw phone number,
with the `tel:` scheme stripped back off -- re-added on save.
-}
type alias PhoneEdit =
    { input : String
    , visibility : Visibility
    , status : SubmitStatus
    }


{-| Live only while `Model.focusedAccount`'s Email field (see
`Shared.AccountsPanel.Model.focusedAccountEmailEdit`) is being edited -- mirrors `PhoneEdit`
exactly, just for the `mailto:` scheme instead of `tel:`.
-}
type alias EmailEdit =
    { input : String
    , visibility : Visibility
    , status : SubmitStatus
    }


{-| Live once phone verification has been started for `Model.focusedAccount` (see
`RellmContactMethods.phoneVerification`) -- ported from
`Components.Pages.UserProfilePage.PhoneVerification`, unchanged; see that type's own doc for the
field-by-field reasoning.
-}
type alias PhoneVerification =
    { sendStatus : SubmitStatus
    , code : String
    , verifyStatus : SubmitStatus
    , cooldownActive : Bool
    }


{-| `Model.focusedAccount`'s own nested "Contact Methods" item state (see
`UI.accountAvatarMenuView`'s "Contact Methods" item/`UI.contactMethodsMenuItem`) -- whether that
sub-item is itself expanded, the edit/consent-checkbox/History-sub-section state for each of Phone/
Email, and the SMS verification flow, all bundled into one record rather than eight separate
`Shared.AccountsPanel.Model` fields (each of which would otherwise need its own `focusedAccount`-
prefixed name to make clear it belongs to whichever account is focused). Lives here, not in
`Shared.AccountsPanel` itself, for the same "keep this whole contact-methods-editing cluster
self-contained" reason `SubmitStatus`/`PhoneEdit`/etc. do -- see `SubmitStatus`'s own doc.

`Shared.AccountsPanel.Model.focusedAccountContactMethods` wraps this in a `Maybe` that's kept in
lockstep with `focusedAccount` itself (`Just emptyRellmContactMethods` whenever `focusedAccount` is
`Just _`, `Nothing` whenever it's `Nothing`) -- see that field's own doc.
-}
type alias RellmContactMethods =
    { phoneEdit : Maybe PhoneEdit
    , emailEdit : Maybe EmailEdit
    , contactMethodsExpanded : Bool
    , phoneConsentStatus : SubmitStatus
    , phoneHistoryExpanded : Bool
    , phoneVerification : Maybe PhoneVerification
    , emailConsentStatus : SubmitStatus
    , emailHistoryExpanded : Bool
    }


{-| `RellmContactMethods`'s all-defaults starting point -- what `focusedAccountContactMethods`
becomes (wrapped in `Just`) the moment a `focusedAccount` is chosen, and what it's reset back to
(this time unwrapped, folded into a fresh edit/etc field) by any individual `ContactMethod*`
`Msg` that only touches one field of it.
-}
emptyRellmContactMethods : RellmContactMethods
emptyRellmContactMethods =
    { phoneEdit = Nothing
    , emailEdit = Nothing
    , contactMethodsExpanded = False
    , phoneConsentStatus = Idle
    , phoneHistoryExpanded = False
    , phoneVerification = Nothing
    , emailConsentStatus = Idle
    , emailHistoryExpanded = False
    }


{-| The visibility options a contact method's own visibility `<select>` offers -- ported from
`Components.Pages.UserProfilePage.contactMethodVisibilities`, see that value's own doc for why it's
narrower than `Components.Posts.allVisibilities`.
-}
contactMethodVisibilities : List Visibility
contactMethodVisibilities =
    [ PRIVATE, SERVERPUBLIC, GLOBALPUBLIC ]


{-| Display text for a `contactMethodVisibilities` value -- deliberately the exact same strings
`Components.Posts.visibilityText`/`Components.Users.visibilityText` already produce for these three
constructors, so a contact method's visibility reads identically wherever it's shown, without this
leaf module having to import either (see this module's own doc on why it can't).
-}
contactMethodVisibilityText : Visibility -> String
contactMethodVisibilityText visibility =
    case visibility of
        SERVERPUBLIC ->
            "Server Public"

        GLOBALPUBLIC ->
            "Global Public"

        _ ->
            "Private"


{-| The reverse of `contactMethodVisibilityText`, for round-tripping a visibility `<select>`'s
`onInput` text back into a `Visibility` -- mirrors `Components.Posts.visibilityFromText`, narrowed
to `contactMethodVisibilities`.
-}
contactMethodVisibilityFromText : String -> Maybe Visibility
contactMethodVisibilityFromText text =
    contactMethodVisibilities |> List.filter (\v -> contactMethodVisibilityText v == text) |> List.head


{-| A `ContactMethod`'s `value` with its `tel:`/`mailto:` scheme stripped back off, `"—"` when
unset -- ported from `Components.Pages.UserProfilePage.contactMethodDisplayValue`, unchanged.
-}
contactMethodDisplayValue : String -> Maybe ContactMethod -> String
contactMethodDisplayValue prefix maybeContactMethod =
    maybeContactMethod
        |> Maybe.andThen .value
        |> Maybe.map (stripContactMethodPrefix prefix)
        |> Maybe.withDefault "—"


{-| `contactMethodDisplayValue`'s edit-mode counterpart -- same, but defaults to `""` (an editable
blank) rather than `"—"` (a display-only placeholder) when unset. Ported from
`Components.Pages.UserProfilePage.contactMethodEditValue`, unchanged.
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


{-| The payload that actually crosses the wire in the cross-server SSO hand-off (see
`Shared.FederatedAuth`/`Pages.Auth.To.Key_`/`Pages.Auth.From.EncryptedAccountAuthTokens_`): just enough
to let the receiving origin authenticate as this account itself, via `resolveFederatedRellmAccountTokens`
below -- everything else an `RellmAccount` needs (`userId`, `username`, `permissions`, etc.) is hydrated
straight from the receiving side's own `GetCurrentUser` call rather than trusted from this payload.
-}
type alias RellmAccountAuthTokens =
    { server : String
    , refreshToken : Token
    , accessToken : Token
    }


{-| An access/refresh token, alongside its own expiration (if the server declared one -- see
`isExpired`).
-}
type alias Token =
    { token : String
    , expiresAt : Maybe Time.Posix
    }


{-| A stable identifier for an account: a user's id is only unique per-server.
-}
rellmAccountId : RellmAccount -> String
rellmAccountId account =
    account.server ++ "|" ++ account.userId


{-| Whether an account has the `ADMIN` permission.
-}
isAdmin : RellmAccount -> Bool
isAdmin account =
    List.member ADMIN account.permissions


{-| Whether `account` holds any permission that lets it create/manage `SyncSource`s (iCal/RSS/Atom
subscriptions) -- gates whether the account avatar menu's "Sync Sources" item shows at all
(see `UI.accountAvatarMenuView`). Mirrors `Components.Pages.UserProfilePage.canUseSyncSources`'s
own any-of-N-permissions-or-ADMIN gate; kept as a separate, `Maybe`-free copy here rather than
imported from there, since that module itself depends on `AccountsPanel` (which this module is
part of) and so can't be imported back into it.
-}
canUseSyncSources : RellmAccount -> Bool
canUseSyncSources account =
    List.member ADMIN account.permissions
        || List.member SYNCEVENTSFROMICS account.permissions
        || List.member SYNCPOSTSFROMRSS account.permissions
        || List.member SYNCPOSTSFROMATOM account.permissions


{-| Whether `account` holds any permission that lets it create/manage a `SyncDestination` (cross-
posting to Facebook/Instagram/Mastodon/Bluesky/X/Threads) -- gates the popover's "Sync Destinations"
item. See `canUseSyncSources`'s own doc for why this is a separate copy of
`Components.Pages.UserProfilePage.canUseSyncDestinations`'s same any-of-N-permissions-or-ADMIN gate.
-}
canUseSyncDestinations : RellmAccount -> Bool
canUseSyncDestinations account =
    List.member ADMIN account.permissions
        || List.member SYNCEVENTSTOFACEBOOK account.permissions
        || List.member SYNCPOSTSTOFACEBOOK account.permissions
        || List.member SYNCEVENTSTOINSTAGRAM account.permissions
        || List.member SYNCPOSTSTOINSTAGRAM account.permissions
        || List.member SYNCEVENTSTOMASTODON account.permissions
        || List.member SYNCPOSTSTOMASTODON account.permissions
        || List.member SYNCEVENTSTOBLUESKY account.permissions
        || List.member SYNCPOSTSTOBLUESKY account.permissions
        || List.member SYNCEVENTSTOXTWITTER account.permissions
        || List.member SYNCPOSTSTOXTWITTER account.permissions
        || List.member SYNCEVENTSTOTHREADS account.permissions
        || List.member SYNCPOSTSTOTHREADS account.permissions


{-| Whether `account` holds `CREATE_AI_PROVIDERS` (or `ADMIN`) -- gates the popover's "AI Models"
item, same any-of-N-permissions-or-ADMIN shape as `canUseSyncSources`/`canUseSyncDestinations` even
though there's only one permission to check here.
-}
canUseAIModels : RellmAccount -> Bool
canUseAIModels account =
    List.member ADMIN account.permissions || List.member CREATEAIPROVIDERS account.permissions


{-| A username display enriched with the account's Real Name, if it has one --
e.g. "Jon Latane (jon)" rather than just "jon". Falls back to the bare
username when `realName` is empty (unset).
-}
rellmAccountDisplayName : RellmAccount -> String
rellmAccountDisplayName account =
    if String.isEmpty (String.trim account.realName) then
        account.username

    else
        account.realName ++ " (" ++ account.username ++ ")"


{-| The URL for an account's avatar, authorized with its own access token
(avatars can be visibility-restricted, but an account can always see its own).
-}
rellmAccountAvatarUrl : List RellmServer -> RellmAccount -> Maybe String
rellmAccountAvatarUrl servers account =
    account.avatarMediaId
        |> Maybe.andThen
            (\id ->
                servers
                    |> List.filter (\s -> s.frontendHost == account.server)
                    |> List.head
                    |> Maybe.andThen (\s -> RellmServers.mediaUrl s id)
                    |> Maybe.map (\url -> url ++ "?authorization=" ++ account.accessToken.token)
            )


{-| A server that has any associated accounts can't be removed (only disabled),
since removing it would orphan those accounts' stored credentials.
-}
rellmServerHasRellmAccounts : List RellmAccount -> String -> Bool
rellmServerHasRellmAccounts accounts frontendHost =
    List.any (\a -> a.server == frontendHost) accounts


{-| The signed-in account to use for `frontendHost`, if there is one --
picking the first enabled account on that server. Used wherever content needs
to be fetched "as whichever account, if any, is currently signed into this
server" (see `Components.Posts`), rather than any one specific account.
-}
enabledRellmAccountForServer : List RellmAccount -> String -> Maybe RellmAccount
enabledRellmAccountForServer accounts frontendHost =
    accounts
        |> List.filter (\a -> a.server == frontendHost && a.enabled)
        |> List.head


{-| Disables every other account on `server` besides `keepEnabledId` -- only one
account per server may be signed in (enabled) at a time, since aggregated
feeds/permissions assume a single identity per server. Called whenever an
account becomes enabled, whether by toggling it on or by a fresh sign-in.
-}
disableOtherRellmAccountsOnServer : String -> String -> List RellmAccount -> List RellmAccount
disableOtherRellmAccountsOnServer keepEnabledId server accounts =
    List.map
        (\a ->
            if a.server == server && rellmAccountId a /= keepEnabledId then
                { a | enabled = False }

            else
                a
        )
        accounts


{-| Adds/updates `account` in `accounts` by `rellmAccountId`, keeping an existing entry's own
`sortOrder` rather than the fresh one its caller (`GotAuthResult`/`FederatedAccountReceived`)
proposed -- same reasoning as `RellmServers.upsertRellmServerWith`'s own doc: a re-login/SSO hand-off
for an account already known here shouldn't undo the user's own manual reordering of it.
-}
upsertRellmAccount : RellmAccount -> List RellmAccount -> List RellmAccount
upsertRellmAccount account accounts =
    case List.filter (\a -> rellmAccountId a == rellmAccountId account) accounts |> List.head of
        Just existing ->
            List.map
                (\a ->
                    if rellmAccountId a == rellmAccountId account then
                        { account | sortOrder = existing.sortOrder }

                    else
                        a
                )
                accounts

        Nothing ->
            -- Physical list position no longer drives render order at all (see
            -- `Shared.AccountsPanel.combinedAccountItems`, which re-derives it from `sortOrder`) --
            -- prepending here just keeps `encodeState`'s own on-disk ordering roughly newest-first,
            -- which stays cosmetic.
            account :: accounts


{-| The bare `Task` behind `Shared.AccountsPanel.refreshPermissions`/`refreshPermissionsForServer` --
refreshes an account's `permissions` (and `username`, in case it changed
server-side), plus `syncDestinations`/`syncSources`/`aiModels`
(see `RellmAccount`'s own doc), via `GetCurrentUser` (always a self-view, so the
backend populates all of these -- see `attach_own_advanced_data` on the
backend), refreshing its access token first if needed -- see
`performWithRellmAccount`.
-}
refreshPermissionsTask : RellmServer -> RellmAccount -> Task Grpc.Error ( RellmAccount, User )
refreshPermissionsTask server account =
    case RellmServers.connectionOf server of
        -- `server` is disconnected (see `RellmServer.connected`) -- nothing to refresh
        -- against right now; callers (e.g. `ToggleAccountEnabled` re-enabling an
        -- account on a server that's since gone unreachable) just leave the
        -- account's existing permissions/token alone.
        Nothing ->
            Task.fail Grpc.NetworkError

        Just connection ->
            performWithRellmAccount
                connection
                account
                (\accessToken ->
                    Grpc.new Rellm.getCurrentUser {}
                        |> Grpc.setHost (RellmServers.connectionUrl connection)
                        |> RellmServers.withAccessToken (Just accessToken)
                        |> Grpc.toTask
                )


{-| Folds one account's `GetCurrentUser`/access-token-refresh result (see
`refreshPermissionsTask`) into `accounts` -- shared by `Shared.AccountsPanel.GotPermissionsRefresh`
(a single account, e.g. `ToggleAccountEnabled`) and `GotServerPermissionsRefresh`
(a whole server's worth at once, see `Shared.AccountsPanel.refreshPermissionsForServer`) so both
apply the exact same rules:

  - On success, merges the refreshed `username`/`permissions`/`avatarMediaId`/
    `realName` and clears `needsPassword`.
  - On an `Unauthenticated` failure, the refresh token itself was rejected
    (revoked, expired past its own grace period) -- unlike a network blip,
    retrying later won't fix this; the account needs a fresh password (see
    `UI.accountRow`'s "password required" badge, and `PasswordNeededClicked`).
    Also disabled -- it's not actually signed in anymore (every request would
    fail the same way), so it shouldn't keep counting as such for aggregated
    feeds/permissions until the user signs back in.
  - Any other failure (network blip, server unreachable, etc.) leaves the
    account as it was; it'll be retried on the next reconnect/enable.

-}
applyPermissionsRefreshResult : String -> Result Grpc.Error ( RellmAccount, User ) -> List RellmAccount -> List RellmAccount
applyPermissionsRefreshResult accId result accounts =
    case result of
        Ok ( refreshedAccount, user ) ->
            upsertRellmAccount
                { refreshedAccount
                    | username = user.username
                    , permissions = user.permissions
                    , avatarMediaId = Maybe.map .id user.avatar
                    , realName = user.realName
                    , needsPassword = False
                    , syncDestinations = user.syncDestinations
                    , syncSources = user.syncSources
                    , aiModels = user.aiModels
                    , marketSubscriptions = user.marketSubscriptions
                    , mediaStorageBytesUsed = int64ToInt user.mediaStorageBytesUsed
                    , mediaStorageLimitBytes = Maybe.map int64ToInt user.mediaStorageLimitBytes
                    , phone = user.phone
                    , email = user.email
                }
                accounts

        Err (Grpc.BadStatus { status }) ->
            if status == Grpc.Unauthenticated then
                List.map
                    (\a ->
                        if rellmAccountId a == accId then
                            { a | needsPassword = True, enabled = False }

                        else
                            a
                    )
                    accounts

            else
                accounts

        Err _ ->
            accounts


{-| The network step behind `Pages.Auth.From.EncryptedAccountAuthTokens_`'s auto-accept: resolves
`tokens.server`'s connection (reusing an already-connected one if this browser already knows it,
otherwise negotiating fresh -- see `RellmServers.negotiateRellmServerConfig`), then calls
`GetCurrentUser` with `tokens.accessToken` to hydrate everything else. The page uses the resulting
`User` to build a full `RellmAccount` itself (`tokens.server`/`tokens.refreshToken`/
`tokens.accessToken` plus `user`'s fields) and hand it to
`Shared.AccountsPanel.FederatedAccountReceived`, same as any other freshly-signed-in account --
which, for a server this browser didn't already have connected, means `negotiateRellmServerConfig`
effectively runs twice (once here, once inside that handler's own reconnect). Not worth optimizing
away: it only happens in the background, after this page has already redirected the user onward.
-}
resolveFederatedRellmAccountTokens : Bool -> List RellmServer -> RellmAccountAuthTokens -> Task Grpc.Error User
resolveFederatedRellmAccountTokens pageIsSecure servers tokens =
    let
        getCurrentUser : Connection -> Task Grpc.Error User
        getCurrentUser connection =
            Grpc.new Rellm.getCurrentUser {}
                |> Grpc.setHost (RellmServers.connectionUrl connection)
                |> RellmServers.withAccessToken (Just tokens.accessToken.token)
                |> Grpc.toTask
    in
    case servers |> List.filter (\s -> s.frontendHost == tokens.server && s.connected /= Nothing) |> List.head |> Maybe.andThen RellmServers.connectionOf of
        Just connection ->
            getCurrentUser connection

        Nothing ->
            RellmServers.negotiateRellmServerConfig pageIsSecure tokens.server
                |> Task.andThen (\( connection, _ ) -> getCurrentUser connection)


{-| Ensures `account`'s access token is valid as of now (refreshing it first
if needed), then performs `req` with it. `req` is given just the access token
string, ready to pass to `RellmServers.withAccessToken`. Returns the account
as it ended up (with refreshed tokens if a refresh happened, unchanged
otherwise) alongside `req`'s result, so the caller can persist any refreshed
tokens. `Shared.AccountsPanel.performWithAccountServer`/`performWithOptionalAccountServer`
resolve a fresh `RellmAccount`/`RellmServer` from a `MaybeAccountServer` instead of holding one of
their own, then call this underneath.
-}
performWithRellmAccount :
    Connection
    -> RellmAccount
    -> (String -> Task Grpc.Error b)
    -> Task Grpc.Error ( RellmAccount, b )
performWithRellmAccount connection account req =
    performWithRellmAccountNotifying connection account req
        |> Task.map (\( refreshedAccount, _, result ) -> ( refreshedAccount, result ))


{-| Like `performWithRellmAccount`, but also surfaces the raw `AccessTokenResponse`
if a refresh happened (`Nothing` otherwise).
-}
performWithRellmAccountNotifying :
    Connection
    -> RellmAccount
    -> (String -> Task Grpc.Error b)
    -> Task Grpc.Error ( RellmAccount, Maybe AccessTokenResponse, b )
performWithRellmAccountNotifying connection account req =
    Time.now
        |> Task.andThen (\now -> refreshIfNeeded connection now account)
        |> Task.andThen
            (\( refreshedAccount, refreshResponse ) ->
                req refreshedAccount.accessToken.token
                    |> Task.map (\result -> ( refreshedAccount, refreshResponse, result ))
            )


refreshIfNeeded :
    Connection
    -> Time.Posix
    -> RellmAccount
    -> Task Grpc.Error ( RellmAccount, Maybe AccessTokenResponse )
refreshIfNeeded connection now account =
    if not (isExpired now account.accessToken) then
        Task.succeed ( account, Nothing )

    else
        Grpc.new Rellm.accessToken { refreshToken = account.refreshToken.token, expiresAt = Nothing }
            |> Grpc.setHost (RellmServers.connectionUrl connection)
            |> Grpc.toTask
            |> Task.andThen
                (\resp ->
                    case resp.accessToken of
                        Just accessToken ->
                            Task.succeed
                                ( { account
                                    | accessToken = tokenFromExpirable accessToken
                                    , refreshToken =
                                        resp.refreshToken
                                            |> Maybe.map tokenFromExpirable
                                            |> Maybe.withDefault account.refreshToken
                                  }
                                , Just resp
                                )

                        Nothing ->
                            Task.fail Grpc.NetworkError
                )


tokenFromExpirable : ExpirableToken -> Token
tokenFromExpirable expirable =
    { token = expirable.token
    , expiresAt = Maybe.map timestampToPosix expirable.expiresAt
    }


{-| Whether a token is expired, or expiring within the next minute (enough
margin that it shouldn't expire mid-request). A token with no expiration
(`expiresAt == Nothing`, the default unless a server was asked for one)
never expires.
-}
isExpired : Time.Posix -> Token -> Bool
isExpired now token =
    case token.expiresAt of
        Nothing ->
            False

        Just expiresAt ->
            Time.posixToMillis now + 60000 >= Time.posixToMillis expiresAt



-- ENCODE/DECODE


{-| Deliberately omits `syncDestinations`/`syncSources`/`aiModels`/`marketSubscriptions`/`phone`/
`email` -- they're nested-proto-shaped, can be sizeable, and change often, so persisting them to
`localStorage` (and writing the JSON codecs for their `oneof`s) isn't worth it when
`refreshPermissionsTask` already refetches them on every reconnect/enable. See
`rellmAccountDecoder`'s own doc for the decode side.
-}
encodeRellmAccount : RellmAccount -> Encode.Value
encodeRellmAccount account =
    Encode.object
        [ ( "server", Encode.string account.server )
        , ( "userId", Encode.string account.userId )
        , ( "username", Encode.string account.username )
        , ( "refreshToken", encodeToken account.refreshToken )
        , ( "accessToken", encodeToken account.accessToken )
        , ( "enabled", Encode.bool account.enabled )
        , ( "avatarMediaId", account.avatarMediaId |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "permissions", Encode.list (fieldNumbersPermission >> Encode.int) account.permissions )
        , ( "realName", Encode.string account.realName )
        , ( "needsPassword", Encode.bool account.needsPassword )
        , ( "sortOrder", Encode.int account.sortOrder )
        , ( "mediaStorageBytesUsed", Encode.int account.mediaStorageBytesUsed )
        , ( "mediaStorageLimitBytes", account.mediaStorageLimitBytes |> Maybe.map Encode.int |> Maybe.withDefault Encode.null )
        ]


{-| The cross-server SSO hand-off's wire format (see `RellmAccountAuthTokens`'s own doc) --
deliberately just these three fields, unlike `encodeRellmAccount`'s full persisted shape.
-}
encodeRellmAccountAuthTokens : RellmAccountAuthTokens -> Encode.Value
encodeRellmAccountAuthTokens tokens =
    Encode.object
        [ ( "server", Encode.string tokens.server )
        , ( "refreshToken", encodeToken tokens.refreshToken )
        , ( "accessToken", encodeToken tokens.accessToken )
        ]


encodeToken : Token -> Encode.Value
encodeToken token =
    Encode.object
        [ ( "token", Encode.string token.token )
        , ( "expiresAt", token.expiresAt |> Maybe.map (Time.posixToMillis >> Encode.int) |> Maybe.withDefault Encode.null )
        ]


{-| `elm/json` only provides `map8`, but `RellmAccount` now has 19 fields -- so this
decodes the first 8 into a partially-applied `RellmAccount` constructor, then
applies `realName`, `needsPassword`, `sortOrder`, `mediaStorageBytesUsed`, and
`mediaStorageLimitBytes` on top of that. The 4 in between
(`syncDestinations`/`syncSources`/`aiModels`/`marketSubscriptions`) and the 2 at the very end
(`phone`/`email`) are deliberately never persisted at all -- see `encodeRellmAccount`'s own doc --
so they always decode to `[]`/`Nothing` here regardless of what's in storage; the very next
`refreshPermissionsTask` (fired on every reconnect/enable) fills them back in.
-}
rellmAccountDecoder : Decoder RellmAccount
rellmAccountDecoder =
    Decode.map6
        (\partial realName needsPassword sortOrder mediaStorageBytesUsed mediaStorageLimitBytes ->
            partial realName needsPassword sortOrder [] [] [] [] mediaStorageBytesUsed mediaStorageLimitBytes Nothing Nothing
        )
        (Decode.map8 RellmAccount
            (Decode.field "server" Decode.string)
            (Decode.field "userId" Decode.string)
            (Decode.field "username" Decode.string)
            (Decode.field "refreshToken" tokenDecoder)
            (Decode.field "accessToken" tokenDecoder)
            (Decode.field "enabled" Decode.bool)
            (optionalString "avatarMediaId")
            permissionsDecoder
        )
        realNameDecoder
        needsPasswordDecoder
        sortOrderDecoder
        mediaStorageBytesUsedDecoder
        mediaStorageLimitBytesDecoder


{-| Decodes `encodeRellmAccountAuthTokens`'s wire format -- see `RellmAccountAuthTokens`'s own doc.
-}
rellmAccountAuthTokensDecoder : Decoder RellmAccountAuthTokens
rellmAccountAuthTokensDecoder =
    Decode.map3 RellmAccountAuthTokens
        (Decode.field "server" Decode.string)
        (Decode.field "refreshToken" tokenDecoder)
        (Decode.field "accessToken" tokenDecoder)


{-| Defaults to "" if the key is missing entirely (older persisted state),
without failing the rest of the decode.
-}
realNameDecoder : Decoder String
realNameDecoder =
    Decode.oneOf
        [ Decode.field "realName" Decode.string
        , Decode.succeed ""
        ]


{-| Defaults to 0 if the key is missing entirely (older persisted state, from before this field
existed) -- same reasoning as `realNameDecoder`.
-}
mediaStorageBytesUsedDecoder : Decoder Int
mediaStorageBytesUsedDecoder =
    Decode.oneOf
        [ Decode.field "mediaStorageBytesUsed" Decode.int
        , Decode.succeed 0
        ]


{-| Defaults to `Nothing` (unlimited) if the key is missing entirely (older persisted state).
-}
mediaStorageLimitBytesDecoder : Decoder (Maybe Int)
mediaStorageLimitBytesDecoder =
    Decode.oneOf
        [ Decode.field "mediaStorageLimitBytes" (Decode.nullable Decode.int)
        , Decode.succeed Nothing
        ]


{-| Defaults to `False` if the key is missing entirely (older persisted
state, or a freshly-logged-in account -- see `GotAuthResult`), without
failing the rest of the decode.
-}
needsPasswordDecoder : Decoder Bool
needsPasswordDecoder =
    Decode.oneOf
        [ Decode.field "needsPassword" Decode.bool
        , Decode.succeed False
        ]


{-| Defaults to no permissions if the key is missing entirely (older
persisted state), without failing the rest of the decode.
-}
permissionsDecoder : Decoder (List Permission)
permissionsDecoder =
    Decode.oneOf
        [ Decode.field "permissions" (Decode.list (Decode.map permissionFromInt Decode.int))
        , Decode.succeed []
        ]


permissionFromInt : Int -> Permission
permissionFromInt n =
    case n of
        0 ->
            PERMISSIONUNKNOWN

        1 ->
            VIEWUSERS

        2 ->
            PUBLISHUSERSLOCALLY

        3 ->
            PUBLISHUSERSGLOBALLY

        4 ->
            MODERATEUSERS

        5 ->
            FOLLOWUSERS

        6 ->
            GRANTBASICPERMISSIONS

        10 ->
            VIEWGROUPS

        11 ->
            CREATEGROUPS

        12 ->
            PUBLISHGROUPSLOCALLY

        13 ->
            PUBLISHGROUPSGLOBALLY

        14 ->
            MODERATEGROUPS

        15 ->
            JOINGROUPS

        16 ->
            INVITEGROUPMEMBERS

        20 ->
            VIEWPOSTS

        21 ->
            CREATEPOSTS

        22 ->
            PUBLISHPOSTSLOCALLY

        23 ->
            PUBLISHPOSTSGLOBALLY

        24 ->
            MODERATEPOSTS

        25 ->
            REPLYTOPOSTS

        26 ->
            EDITPOSTTITLESANDLINKS

        30 ->
            VIEWEVENTS

        31 ->
            CREATEEVENTS

        32 ->
            PUBLISHEVENTSLOCALLY

        33 ->
            PUBLISHEVENTSGLOBALLY

        34 ->
            MODERATEEVENTS

        35 ->
            RSVPTOEVENTS

        40 ->
            VIEWMEDIA

        41 ->
            CREATEMEDIA

        42 ->
            PUBLISHMEDIALOCALLY

        43 ->
            PUBLISHMEDIAGLOBALLY

        44 ->
            MODERATEMEDIA

        50 ->
            READPERSONALMESSAGES

        51 ->
            READALLSYSTEMMESSAGES

        60 ->
            CREATEAIPROVIDERS

        700 ->
            SYNCEVENTSFROMICS

        701 ->
            SYNCPOSTSFROMRSS

        702 ->
            SYNCPOSTSFROMATOM

        1000 ->
            SYNCEVENTSTOFACEBOOK

        1001 ->
            SYNCPOSTSTOFACEBOOK

        1010 ->
            SYNCEVENTSTOINSTAGRAM

        1011 ->
            SYNCPOSTSTOINSTAGRAM

        1020 ->
            SYNCEVENTSTOMASTODON

        1021 ->
            SYNCPOSTSTOMASTODON

        1030 ->
            SYNCEVENTSTOBLUESKY

        1031 ->
            SYNCPOSTSTOBLUESKY

        1040 ->
            SYNCEVENTSTOXTWITTER

        1041 ->
            SYNCPOSTSTOXTWITTER

        1050 ->
            SYNCEVENTSTOTHREADS

        1051 ->
            SYNCPOSTSTOTHREADS

        9998 ->
            BUSINESS

        9999 ->
            RUNBOTS

        10000 ->
            ADMIN

        10001 ->
            VIEWPRIVATECONTACTMETHODS

        10002 ->
            EDITCLUSTERSETTINGS

        other ->
            PermissionUnrecognized_ other


{-| Accepts both the current `{token, expiresAt}` shape and the older
bare-string shape (from before tokens tracked expiration), so existing
persisted accounts aren't invalidated by this change.
-}
tokenDecoder : Decoder Token
tokenDecoder =
    Decode.oneOf
        [ Decode.map2 Token
            (Decode.field "token" Decode.string)
            (Decode.maybe (Decode.field "expiresAt" (Decode.nullable Decode.int))
                |> Decode.map (Maybe.andThen identity >> Maybe.map Time.millisToPosix)
            )
        , Decode.map (\token -> { token = token, expiresAt = Nothing }) Decode.string
        ]


optionalString : String -> Decoder (Maybe String)
optionalString field =
    Decode.maybe (Decode.field field (Decode.nullable Decode.string))
        |> Decode.map (Maybe.andThen identity)
