module Shared.AccountsPanel.BlueskyAccounts exposing
    ( BlueskyAccount
    , BlueskyProfile
    , createSessionTask
    , decoder
    , disableOtherBlueskyAccounts
    , encodeList
    , errorMessage
    , fetchProfileTask
    , isReauthError
    , performWithBlueskyAccount
    )

{-| Everything about a connected Bluesky account that doesn't need `Shared.AccountsPanel.Model`
itself to make sense: the persisted-list element type (`BlueskyAccount`), its encode/decode
(`Ports.persistBlueskyAccounts`'s wire format), and the plain HTTP tasks/decoders
`Shared.AccountsPanel.update` drives to build/refresh it (`com.atproto.server.createSession`,
`com.atproto.server.refreshSession`, `app.bsky.actor.getProfile`).

What's deliberately _not_ here, and stays in `Shared.AccountsPanel` itself: the `Model` fields this
lives in, `BlueskyConnectForm` (the handle/App Password form itself -- tightly coupled to
`Shared.AccountsPanel`'s own per-keystroke `Msg`s and `FormStatus`), and the `Msg`s/`update` cases
that react to user actions and persist the result.

-}

import Base64
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Shared.AccountsPanel.SortOrder exposing (sortOrderDecoder)
import Shared.Federation.Common exposing (jsonResolver, nonEmpty)
import Task exposing (Task)
import Time


{-| A Bluesky (AT Protocol) account connected via `UI.blueskyConnectSection`'s form -- unlike
Mastodon, there's no OAuth popup at all: `com.atproto.server.createSession` (see
`createSessionTask`) takes a handle and App Password directly, the same "plain form" shape
`Pages.Auth.To.Key_` already uses for Rellm's own Login RPC (and is itself the identity check --
the session response already carries `handle`, so there's no separate verify-credentials round trip
the way Mastodon's OAuth `code` needs). Known first-pass limitation: always calls `bsky.social`
directly rather than resolving `handle` to its actual PDS first (see `createSessionTask`'s own
doc), so a self-hosted-PDS account won't connect yet -- the overwhelming majority of Bluesky accounts
are hosted there by default, so this covers the common case. `enabled` mirrors `RellmServer.enabled` --
see `Shared.AccountsPanel.MastodonServers.BrowsedMastodonInstance`'s own doc. `avatarUrl`/
`displayName` both start `Nothing` (the `createSession` response this is built from carries no
profile info at all) and are filled in shortly after, if they resolve, by a follow-up
`fetchProfileTask` call -- see `GotBlueskyProfileResult`.

`refreshToken` (AT Proto's own `refreshJwt`) is single-use/rotating -- every successful
`com.atproto.server.refreshSession` call (see `performWithBlueskyAccount`) returns a _new_ one,
which replaces this field entirely; the old one stops working the moment a new one's issued, so
holding onto a stale copy anywhere (e.g. a second browser tab that hasn't yet seen the rotated
value) would itself start failing on its next refresh attempt. `needsReauth` mirrors
`RellmAccount.needsPassword`: set once a refresh itself fails (revoked/expired past AT Proto's own
refresh-token lifetime, typically much longer than the access token's own short one), meaning the
only way back in is disconnecting and reconnecting with a fresh App Password -- there's no
`RellmAccount`-style partial state to recover from short of that.

-}
type alias BlueskyAccount =
    { handle : String
    , accessToken : String
    , refreshToken : String
    , enabled : Bool
    , avatarUrl : Maybe String
    , displayName : Maybe String
    , sortOrder : Int
    , needsReauth : Bool
    }


encodeList : List BlueskyAccount -> Encode.Value
encodeList accounts =
    Encode.list encodeAccount accounts


encodeAccount : BlueskyAccount -> Encode.Value
encodeAccount account =
    Encode.object
        [ ( "handle", Encode.string account.handle )
        , ( "accessToken", Encode.string account.accessToken )
        , ( "refreshToken", Encode.string account.refreshToken )
        , ( "enabled", Encode.bool account.enabled )
        , ( "avatarUrl", account.avatarUrl |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "displayName", account.displayName |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "sortOrder", Encode.int account.sortOrder )
        , ( "needsReauth", Encode.bool account.needsReauth )
        ]


{-| Disables every other Bluesky account besides `keepEnabledHandle` -- only one Bluesky account
may be enabled (contributing to the combined feed/`UI.accountsMenuServerSummary`'s own count) at a
time, mirroring `Shared.AccountsPanel.RellmAccounts.disableOtherRellmAccountsOnServer`'s identical
"one signed-in identity" reasoning, just account-wide rather than per-server (there's no separate
Bluesky "server" to scope by -- every connected account shares the one `bsky.social` PDS). Called
whenever an account becomes enabled, whether by toggling it on (`ToggleBlueskyAccountEnabled`) or by
a fresh connect (`GotBlueskyConnectResult`, whose `BlueskyAccounts.createSessionTask` result always
starts `enabled = True`).
-}
disableOtherBlueskyAccounts : String -> List BlueskyAccount -> List BlueskyAccount
disableOtherBlueskyAccounts keepEnabledHandle accounts =
    List.map
        (\a ->
            if a.handle /= keepEnabledHandle then
                { a | enabled = False }

            else
                a
        )
        accounts


decoder : Decoder (List BlueskyAccount)
decoder =
    Decode.list accountDecoder |> Decode.map dedupeByHandle


{-| One account per handle (case-insensitive), in order of first appearance -- cleans up the
duplicates an earlier version of reconnecting left behind (a reconnect used to add a second entry
instead of replacing the first). Of duplicates, prefers one not flagged `needsReauth`, else the first.
-}
dedupeByHandle : List BlueskyAccount -> List BlueskyAccount
dedupeByHandle accounts =
    let
        handleKey : BlueskyAccount -> String
        handleKey a =
            String.toLower a.handle

        best : BlueskyAccount -> BlueskyAccount
        best first =
            accounts
                |> List.filter (\a -> handleKey a == handleKey first && not a.needsReauth)
                |> List.head
                |> Maybe.withDefault first
    in
    List.foldl
        (\a seen ->
            if List.any (\b -> handleKey b == handleKey a) seen then
                seen

            else
                seen ++ [ best a ]
        )
        []
        accounts


accountDecoder : Decoder BlueskyAccount
accountDecoder =
    Decode.map8 BlueskyAccount
        (Decode.field "handle" Decode.string)
        (Decode.field "accessToken" Decode.string)
        refreshTokenDecoder
        (Decode.field "enabled" Decode.bool)
        (Decode.maybe (Decode.field "avatarUrl" Decode.string))
        (Decode.maybe (Decode.field "displayName" Decode.string))
        sortOrderDecoder
        needsReauthDecoder


{-| Defaults to `""` if the key is missing entirely -- an account persisted before `refreshToken`
existed. That empty string will simply fail as a bearer token on this account's next refresh
attempt (see `performWithBlueskyAccount`), which is exactly what should happen: there's no real
refresh token to recover, so the account correctly ends up `needsReauth` and the user reconnects
with a fresh App Password, same one-time migration cost `RellmAccounts.realNameDecoder`'s own kind
of default pays elsewhere.
-}
refreshTokenDecoder : Decoder String
refreshTokenDecoder =
    Decode.oneOf
        [ Decode.field "refreshToken" Decode.string
        , Decode.succeed ""
        ]


{-| Defaults to `False` if the key is missing entirely (older persisted state, or a freshly
connected account -- see `sessionDecoder`).
-}
needsReauthDecoder : Decoder Bool
needsReauthDecoder =
    Decode.oneOf
        [ Decode.field "needsReauth" Decode.bool
        , Decode.succeed False
        ]


{-| `com.atproto.server.createSession` -- Bluesky's own login RPC, taking a handle and App Password
directly (see `BlueskyAccount`'s own doc on why there's no OAuth popup here, and the known
`bsky.social`-only limitation). Decodes `handle`/`accessJwt`/`refreshJwt`, all a `BlueskyAccount`
needs.
-}
createSessionTask : String -> String -> Task Http.Error BlueskyAccount
createSessionTask handle appPassword =
    Http.task
        { method = "POST"
        , headers = []
        , url = "https://bsky.social/xrpc/com.atproto.server.createSession"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "identifier", Encode.string handle )
                    , ( "password", Encode.string appPassword )
                    ]
                )
        , resolver =
            jsonResolver sessionDecoder
                (\metadata body -> Http.BadBody (errorBody body |> Maybe.withDefault ("HTTP " ++ String.fromInt metadata.statusCode)))
        , timeout = Just 10000
        }


sessionDecoder : Decode.Decoder BlueskyAccount
sessionDecoder =
    Decode.map8 BlueskyAccount
        (Decode.field "handle" Decode.string)
        (Decode.field "accessJwt" Decode.string)
        (Decode.field "refreshJwt" Decode.string)
        (Decode.succeed True)
        (Decode.succeed Nothing)
        (Decode.succeed Nothing)
        -- Overwritten by `Shared.AccountsPanel.GotBlueskyConnectResult` with
        -- `nextFrontAccountSortOrder model` before this ever reaches `model.blueskyAccounts` --
        -- see that handler.
        (Decode.succeed 0)
        (Decode.succeed False)


{-| `com.atproto.server.refreshSession` -- exchanges `account`'s `refreshToken` for a fresh
`accessToken`/`refreshToken` pair, authenticated with the refresh token itself as the bearer token
(not the presumably-expired access token). AT Proto rotates the refresh token on every use, so the
old one in `account` stops working the instant this succeeds -- the returned `BlueskyAccount`
(same `handle`/`enabled`/`avatarUrl`/`displayName`/`sortOrder`, fresh tokens, `needsReauth = False`)
is what has to actually replace `account` wherever it's stored, not just get read from once. See
`performWithBlueskyAccount` for what actually calls this, and when.
-}
refreshSessionTask : BlueskyAccount -> Task Http.Error BlueskyAccount
refreshSessionTask account =
    Http.task
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ account.refreshToken) ]
        , url = "https://bsky.social/xrpc/com.atproto.server.refreshSession"
        , body = Http.emptyBody
        , resolver =
            jsonResolver refreshedTokensDecoder
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map
            (\( newAccessToken, newRefreshToken ) ->
                { account | accessToken = newAccessToken, refreshToken = newRefreshToken, needsReauth = False }
            )


refreshedTokensDecoder : Decode.Decoder ( String, String )
refreshedTokensDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "accessJwt" Decode.string)
        (Decode.field "refreshJwt" Decode.string)


{-| Ensures `account`'s access token works around performing `req`. Two layers:

  - **Proactive**: the access token is a JWT, so its own `exp` claim says when it dies (see
    `accessTokenExpiring`) -- if that's within a minute (or it's unreadable), refresh _before_
    sending `req` rather than burning a failed request first. This keeps the refresh token's
    single-use rotation from being exercised in a flurry of concurrent reactive retries.
  - **Reactive**: if `req` still comes back `Http.BadStatus 400`/`401` (AT Proto's "ExpiredToken"/
    "InvalidToken" statuses -- the body isn't visible from here, so a 400 for some unrelated reason
    costs one needless refresh), refresh once (unless the proactive step just did) and retry `req`
    once. Other statuses (404, 429, 5xx) are real answers and pass through untouched.

If a refresh is rejected with a 400/401 (the refresh token itself is revoked/expired/already
rotated), this fails with `reauthRequiredError`, the only error `isReauthError` recognizes. Any other
refresh failure (network, 5xx, rate limit) just surfaces the original `req` failure -- the session may
well be fine. Callers should persist the returned account whenever this succeeds, since its tokens
may have rotated.

-}
performWithBlueskyAccount : BlueskyAccount -> (String -> Task Http.Error a) -> Task Http.Error ( BlueskyAccount, a )
performWithBlueskyAccount account req =
    let
        run : Bool -> BlueskyAccount -> Task Http.Error ( BlueskyAccount, a )
        run justRefreshed current =
            req current.accessToken
                |> Task.map (\result -> ( current, result ))
                |> Task.onError
                    (\originalError ->
                        if justRefreshed || not (isExpiredTokenStatus originalError) then
                            Task.fail originalError

                        else
                            refreshOrFail current
                                |> Task.mapError
                                    (\refreshError ->
                                        if isReauthError refreshError then
                                            refreshError

                                        else
                                            originalError
                                    )
                                |> Task.andThen
                                    (\refreshedAccount ->
                                        req refreshedAccount.accessToken
                                            |> Task.map (\result -> ( refreshedAccount, result ))
                                    )
                    )
    in
    Time.now
        |> Task.andThen
            (\now ->
                if accessTokenExpiring now account.accessToken then
                    refreshOrFail account
                        |> Task.map (\refreshed -> ( True, refreshed ))
                        |> Task.onError
                            (\err ->
                                if isReauthError err then
                                    Task.fail err

                                else
                                    -- Transient refresh failure: the old token may still work.
                                    Task.succeed ( False, account )
                            )
                        |> Task.andThen (\( justRefreshed, current ) -> run justRefreshed current)

                else
                    run False account
            )


isExpiredTokenStatus : Http.Error -> Bool
isExpiredTokenStatus err =
    case err of
        Http.BadStatus status ->
            status == 400 || status == 401

        _ ->
            False


{-| `refreshSessionTask`, but a 400/401 rejection (the refresh token itself is dead) becomes
`reauthRequiredError`; anything else is passed through as-is.
-}
refreshOrFail : BlueskyAccount -> Task Http.Error BlueskyAccount
refreshOrFail account =
    refreshSessionTask account
        |> Task.mapError
            (\err ->
                if isExpiredTokenStatus err then
                    reauthRequiredError

                else
                    err
            )


reauthRequiredError : Http.Error
reauthRequiredError =
    Http.BadBody "bluesky-reauth-required"


{-| Whether `token` (an access JWT) expires within the next minute -- or can't be read at all, in
which case refreshing is the safe call.
-}
accessTokenExpiring : Time.Posix -> String -> Bool
accessTokenExpiring now token =
    case jwtExpiry token of
        Just expSeconds ->
            expSeconds * 1000 - Time.posixToMillis now < 60 * 1000

        Nothing ->
            True


{-| The `exp` claim (seconds since the epoch) of a JWT -- its middle, base64url-encoded segment is
plain JSON. Signature isn't checked; this only schedules a refresh.
-}
jwtExpiry : String -> Maybe Int
jwtExpiry token =
    case String.split "." token of
        [ _, payload, _ ] ->
            let
                standard : String
                standard =
                    payload |> String.replace "-" "+" |> String.replace "_" "/"
            in
            String.padRight (4 * ceiling (toFloat (String.length standard) / 4)) '=' standard
                |> Base64.toString
                |> Maybe.andThen (Decode.decodeString (Decode.field "exp" Decode.int) >> Result.toMaybe)

        _ ->
            Nothing


{-| Whether an `Http.Error` (from `performWithBlueskyAccount`) means this account's refresh token
was rejected, so it needs a fresh App Password rather than hitting some unrelated/transient failure.
Only `reauthRequiredError` -- i.e. a 400/401 from `refreshSession` itself -- counts; an ordinary 404/
429/5xx from a feed request does not. Callers send the refresh token they used alongside it (see
`Shared.AccountsPanel.MarkBlueskyAccountNeedsReauth`) so a stale failure can't clobber a session
another request already successfully rotated.
-}
isReauthError : Http.Error -> Bool
isReauthError err =
    err == reauthRequiredError


{-| `com.atproto.server.createSession`'s error responses are `{ error : String, message : String }`
(e.g. `{"error":"AuthenticationRequired","message":"Invalid identifier or password"}`) -- extracts
`message` when present, so `BlueskyConnectForm.status`'s `Errored` shows something more useful than
a bare status code.
-}
errorBody : String -> Maybe String
errorBody body =
    Decode.decodeString (Decode.field "message" Decode.string) body |> Result.toMaybe


{-| `fetchProfileTask`'s result -- `avatarUrl`/`displayName` both `Nothing` if unset, the same
as `Shared.AccountsPanel.MastodonServers.MastodonInstanceInfo`'s own convention.
-}
type alias BlueskyProfile =
    { avatarUrl : Maybe String
    , displayName : Maybe String
    }


{-| `app.bsky.actor.getProfile` for `handle`, authenticated with the just-connected account's own
`accessToken` -- fetched once right after `createSessionTask` succeeds (see
`GotBlueskyConnectResult`/`GotBlueskyProfileResult`), since the session response itself carries no
profile info.
-}
fetchProfileTask : String -> String -> Task Http.Error BlueskyProfile
fetchProfileTask handle accessToken =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.actor.getProfile?actor=" ++ handle
        , body = Http.emptyBody
        , resolver =
            jsonResolver profileDecoder
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


profileDecoder : Decode.Decoder BlueskyProfile
profileDecoder =
    Decode.map2 BlueskyProfile
        (Decode.maybe (Decode.field "avatar" Decode.string))
        (Decode.maybe (Decode.field "displayName" Decode.string) |> Decode.map (Maybe.andThen nonEmpty))


{-| `GotBlueskyConnectResult`'s error-to-display-string projection -- `Http.BadBody` here always
carries `createSessionTask`'s own already-human-readable message (either the server's own
`message`, or a bare status code fallback -- see `errorBody`), so it's shown as-is; every
other `Http.Error` variant gets a generic message, same as this codebase's `grpcErrorToString`
doesn't try to describe network/timeout errors in detail either.
-}
errorMessage : Http.Error -> String
errorMessage err =
    case err of
        Http.BadBody message ->
            message

        Http.BadUrl _ ->
            "Couldn't connect to Bluesky."

        Http.Timeout ->
            "Bluesky didn't respond in time."

        Http.NetworkError ->
            "Couldn't reach Bluesky."

        Http.BadStatus code ->
            "Bluesky returned an error (" ++ String.fromInt code ++ ")."
