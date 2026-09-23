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

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Shared.AccountsPanel.SortOrder exposing (sortOrderDecoder)
import Shared.Federation.Common exposing (jsonResolver, nonEmpty)
import Task exposing (Task)


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
    Decode.list accountDecoder


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
                (\metadata body -> Http.BadBody (errorBody body |> Maybe.withDefault ("HTTP " ++ String.fromInt metadata.statusCode)))
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


{-| Ensures `account`'s access token still works around performing `req`: tries `req` with the
current `accessToken` first, and only attempts a refresh (see `refreshSessionTask`) if that comes
back `Http.BadStatus _` -- AT Proto's exact status code/error-body shape for "this token is
expired" (historically inconsistent across its own endpoints) isn't worth depending on precisely
here, so _any_ bad-status response is treated as a "maybe expired, worth one refresh-and-retry"
signal. If the refresh itself fails (refresh token revoked/expired past its own, much longer
lifetime, or a network error), this surfaces the _original_ `req` failure rather than the refresh's
own -- callers should treat a final `Http.BadStatus _` here as "this account needs
`needsReauth = True`" (see `isReauthError`), same shape `RellmAccounts.applyPermissionsRefreshResult`
already uses for `RellmAccount.needsPassword`. On a successful refresh, retries `req` exactly once
with the new access token and returns the _updated_ `account` alongside whatever it resolves to
(or that retry's own failure, uninterrupted, if it fails for an unrelated reason) -- either way,
callers should persist the returned account whenever this succeeds, since its tokens may have
rotated even though the caller never asked for that explicitly.
-}
performWithBlueskyAccount : BlueskyAccount -> (String -> Task Http.Error a) -> Task Http.Error ( BlueskyAccount, a )
performWithBlueskyAccount account req =
    req account.accessToken
        |> Task.map (\result -> ( account, result ))
        |> Task.onError
            (\originalError ->
                case originalError of
                    Http.BadStatus _ ->
                        refreshSessionTask account
                            |> Task.mapError (\_ -> originalError)
                            |> Task.andThen
                                (\refreshedAccount ->
                                    req refreshedAccount.accessToken
                                        |> Task.map (\result -> ( refreshedAccount, result ))
                                )

                    _ ->
                        Task.fail originalError
            )


{-| Whether an `Http.Error` (from `performWithBlueskyAccount`, once every refresh-and-retry
possibility is exhausted) means this account needs a fresh App Password rather than being some
unrelated/transient failure -- mirrors `Grpc.Unauthenticated`'s own role in
`RellmAccounts.applyPermissionsRefreshResult`. Deliberately as broad as `performWithBlueskyAccount`'s
own retry trigger (any `Http.BadStatus _`), for the same reason: a more specific check would need to
depend on AT Proto's own not-fully-consistent error body shape across endpoints.
-}
isReauthError : Http.Error -> Bool
isReauthError err =
    case err of
        Http.BadStatus _ ->
            True

        _ ->
            False


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
