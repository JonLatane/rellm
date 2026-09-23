module Shared.AccountsPanel.MastodonAccounts exposing
    ( MastodonAccount
    , MastodonLoginResult
    , encodeMastodonAccount
    , isReauthError
    , mastodonAccountDecoder
    , mastodonLoginResultDecoder
    , performWithMastodonAccount
    , verifyMastodonCredentialsTask
    )

{-| Everything about a connected Mastodon account that doesn't need `Shared.AccountsPanel.Model`
itself to make sense: the persisted-list element type (`MastodonAccount`), its encode/decode, and the
plain HTTP tasks/decoders `Shared.AccountsPanel.update` drives to build/refresh it
(`MastodonConnectClicked`'s OAuth popup result, `verify_credentials`, the OAuth2 refresh grant). See
`Shared.AccountsPanel.MastodonServers` for the sibling module covering _browsed_ (not connected)
Mastodon instances -- the two used to be one module (`MastodonAccountAndServers`) since they're
persisted together (see `Ports.persistMastodonAccountsAndServers`), but that bundling is
`Shared.AccountsPanel`'s own coordinating concern (mirrors `PersistedState` bundling `RellmAccount`s
and `RellmServer`s), not something either type needs to know about itself.

What's deliberately _not_ here, and stays in `Shared.AccountsPanel` itself: the `Model` field this
lives in (`mastodonAccounts`), and every `Msg`/`update` case that reacts to user actions and persists
the result.

-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Shared.AccountsPanel.SortOrder exposing (sortOrderDecoder)
import Shared.Federation.Common exposing (jsonResolver)
import Task exposing (Task)
import Url


{-| A Mastodon account connected via `UI.mastodonConnectButton`'s "Connect" button (see
`Shared.AccountsPanel.MastodonConnectClicked`/`GotMastodonLoginResult`) -- `accessToken` came out of
an OAuth popup Elm never directly handled (see `Ports.facebookLoginPopup`'s `"mastodon"` provider:
app registration (the admin-registered `MastodonServer.appId`, looked up via
`Shared.AccountsPanel.mastodonServerFor`, or -- if that instance has none -- a throwaway one
dynamically self-registered on the spot), PKCE, and the code/token exchange all happen in
`public/index.html`'s JS, entirely between the browser and `instanceHost` itself, `app_secret` never
included either way), and `username` is fetched once, right after, via
`GET /api/v1/accounts/verify_credentials` (see `verifyMastodonCredentialsTask`) -- just enough to
display the connection, not a full `RellmAccount`, since a Mastodon account isn't a Rellm one.

`clientId` is whichever `client_id` the popup's own OAuth exchange actually used (the admin-registered
`MastodonServer.appId`, or a self-registered throwaway app's own id -- see `public/index.html`'s
`mastodonClientId`) -- Mastodon's OAuth2 refresh grant needs the _same_ `client_id` that originally
issued the token back again (unlike Bluesky's AT Proto refresh, which only needs the refresh token
itself), so it has to be captured and persisted alongside the tokens rather than re-derived later (an
admin could change/remove a `MastodonServer.appId` after the fact, or the instance's throwaway app
could no longer be the one `mastodonServerFor` would resolve). `refreshToken` is `Nothing` when the
instance's OAuth response carried none at all -- some Mastodon (Doorkeeper) instances issue
non-expiring tokens to third-party apps by default and simply omit `refresh_token`, in which case
there's nothing to refresh and this account just keeps working off `accessToken` indefinitely (or
until revoked, at which point it's a `needsReauth` case with no automatic recovery, same as a refresh
attempt that itself fails -- see `isReauthError`).

-}
type alias MastodonAccount =
    { instanceHost : String
    , accessToken : String
    , refreshToken : Maybe String
    , clientId : String
    , username : String
    , sortOrder : Int
    , needsReauth : Bool
    }


encodeMastodonAccount : MastodonAccount -> Encode.Value
encodeMastodonAccount account =
    Encode.object
        [ ( "instanceHost", Encode.string account.instanceHost )
        , ( "accessToken", Encode.string account.accessToken )
        , ( "refreshToken", account.refreshToken |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
        , ( "clientId", Encode.string account.clientId )
        , ( "username", Encode.string account.username )
        , ( "sortOrder", Encode.int account.sortOrder )
        , ( "needsReauth", Encode.bool account.needsReauth )
        ]


mastodonAccountDecoder : Decoder MastodonAccount
mastodonAccountDecoder =
    Decode.map7 MastodonAccount
        (Decode.field "instanceHost" Decode.string)
        (Decode.field "accessToken" Decode.string)
        (Decode.maybe (Decode.field "refreshToken" Decode.string))
        (Decode.oneOf [ Decode.field "clientId" Decode.string, Decode.succeed "" ])
        (Decode.field "username" Decode.string)
        sortOrderDecoder
        (Decode.oneOf [ Decode.field "needsReauth" Decode.bool, Decode.succeed False ])


{-| `GotMastodonLoginResult`'s decoded payload -- `accessToken` alone is enough to call
`verifyMastodonCredentialsTask` (the next step either way), while `refreshToken`/`clientId` just ride
along for `GotMastodonVerifyCredentialsResult` to stash directly onto the new `MastodonAccount` once
that resolves.
-}
type alias MastodonLoginResult =
    { accessToken : String
    , refreshToken : Maybe String
    , clientId : String
    }


{-| Decodes a `facebookLoginResult` payload for the `"mastodon"` provider specifically -- `{ ok :
True, value : accessToken, refreshToken : String or null, clientId : String }` on success (see
`public/index.html`'s `mastodonExchangeCode`/its `onMessage` handler for where `refreshToken`/
`clientId` get attached, mirroring X Twitter's own `codeVerifier` extra field on the same port), `Err
message` otherwise (including the "cancelled" case, same as every other provider's use of this port).
`clientId` missing/blank despite `ok: True` is treated as a decode failure (shouldn't happen -- the
popup always attaches it alongside a successful token) the same way
`Components.Pages.UserProfilePage.xTwitterLoginResultDecoder` treats a missing `codeVerifier`; a
missing/null `refreshToken` is NOT an error (see `MastodonAccount.refreshToken`'s own doc on why that's
a legitimate, expected outcome for some instances).
-}
mastodonLoginResultDecoder : Decode.Value -> Result String MastodonLoginResult
mastodonLoginResultDecoder rawValue =
    case
        Decode.decodeValue
            (Decode.map4 (\ok v refreshToken clientId -> { ok = ok, value = v, refreshToken = refreshToken, clientId = clientId })
                (Decode.field "ok" Decode.bool)
                (Decode.field "value" Decode.string)
                (Decode.maybe (Decode.field "refreshToken" Decode.string))
                (Decode.maybe (Decode.field "clientId" Decode.string))
            )
            rawValue
    of
        Ok { ok, value, refreshToken, clientId } ->
            case ( ok, clientId ) of
                ( True, Just id ) ->
                    Ok { accessToken = value, refreshToken = refreshToken, clientId = id }

                ( True, Nothing ) ->
                    Err "Mastodon login popup didn't return a client id."

                ( False, _ ) ->
                    Err value

        Err err ->
            Err (Decode.errorToString err)


{-| `GET /api/v1/accounts/verify_credentials` against `instanceHost`, authenticated with the
freshly-minted `accessToken` -- the one Mastodon call `GotMastodonLoginResult` needs before it can
actually add a `MastodonAccount`, since the OAuth result alone is just a bare token with no
identity attached yet. Decodes just `username`, all a `MastodonAccount` needs to display the
connection.
-}
verifyMastodonCredentialsTask : String -> String -> Task Http.Error String
verifyMastodonCredentialsTask instanceHost accessToken =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://" ++ instanceHost ++ "/api/v1/accounts/verify_credentials"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "username" Decode.string) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| Mastodon's (Doorkeeper's) OAuth2 refresh grant -- `POST {instanceHost}/oauth/token` with
`grant_type=refresh_token`, needing only `client_id` and the `refresh_token` itself (no PKCE
`code_verifier`, no `client_secret` -- same "public client" reasoning `public/index.html`'s own
`mastodonExchangeCode` doc already covers for the initial exchange), so unlike that initial exchange
this can run as a pure Elm `Http.task` with no JS/port round trip at all. Doorkeeper rotates the
refresh token on a successful refresh (the response carries a new one), so the returned
`MastodonAccount` may have a different `refreshToken` than `account` did -- same
"always persist what this returns" contract as `Shared.AccountsPanel.BlueskyAccounts.refreshSessionTask`.
Fails outright (a synthetic `Http.BadStatus 400`) if `account.refreshToken` is `Nothing` -- there's
nothing to exchange, so this is treated the same as the server itself rejecting a refresh attempt.
-}
refreshSessionTask : MastodonAccount -> Task Http.Error MastodonAccount
refreshSessionTask account =
    case account.refreshToken of
        Nothing ->
            Task.fail (Http.BadStatus 400)

        Just refreshToken ->
            Http.task
                { method = "POST"
                , headers = []
                , url = "https://" ++ account.instanceHost ++ "/oauth/token"
                , body =
                    Http.stringBody "application/x-www-form-urlencoded"
                        (String.join "&"
                            [ "client_id=" ++ Url.percentEncode account.clientId
                            , "grant_type=refresh_token"
                            , "refresh_token=" ++ Url.percentEncode refreshToken
                            ]
                        )
                , resolver = jsonResolver refreshedTokensDecoder (\metadata _ -> Http.BadStatus metadata.statusCode)
                , timeout = Just 10000
                }
                |> Task.map
                    (\( newAccessToken, newRefreshToken ) ->
                        { account
                            | accessToken = newAccessToken
                            , refreshToken = orElse account.refreshToken newRefreshToken
                            , needsReauth = False
                        }
                    )


{-| `maybe`, if it's `Just`; `fallback` otherwise -- Doorkeeper's refresh response doesn't always
include a new `refresh_token` (some instances keep reusing the same one rather than rotating it), so
a missing one here means "unchanged," not "cleared."
-}
orElse : Maybe a -> Maybe a -> Maybe a
orElse fallback maybe =
    case maybe of
        Just _ ->
            maybe

        Nothing ->
            fallback


refreshedTokensDecoder : Decode.Decoder ( String, Maybe String )
refreshedTokensDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "access_token" Decode.string)
        (Decode.maybe (Decode.field "refresh_token" Decode.string))


{-| Ensures `account`'s access token still works around performing `req`: tries `req` with the
current `accessToken` first, and only attempts a refresh (see `refreshSessionTask`) if that comes
back `Http.BadStatus _`, mirroring `Shared.AccountsPanel.BlueskyAccounts.performWithBlueskyAccount`'s
own reasoning for why a broad "any bad status" check is the right trigger here too (Mastodon's own
error body shape for "token expired/revoked" isn't worth depending on precisely). If `account` has no
`refreshToken` at all (see that field's own doc), `refreshSessionTask` fails immediately, so this
surfaces the _original_ `req` failure unchanged, same outcome as a refresh that's attempted and fails.
On a successful refresh, retries `req` exactly once with the new access token and returns the
_updated_ `account` alongside whatever it resolves to -- callers should persist the returned account
whenever this succeeds, since its tokens may have rotated even without the caller asking for that
explicitly.
-}
performWithMastodonAccount : MastodonAccount -> (String -> Task Http.Error a) -> Task Http.Error ( MastodonAccount, a )
performWithMastodonAccount account req =
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


{-| Whether an `Http.Error` (from `performWithMastodonAccount`, once every refresh-and-retry
possibility is exhausted) means this account needs a full reconnect rather than being some
unrelated/transient failure -- mirrors `Shared.AccountsPanel.BlueskyAccounts.isReauthError` exactly,
for the same reason (no reliably distinct error shape to key off instead).
-}
isReauthError : Http.Error -> Bool
isReauthError err =
    case err of
        Http.BadStatus _ ->
            True

        _ ->
            False
