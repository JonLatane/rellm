module Shared.AccountsPanel.RellmServers exposing
    ( Branding
    , ConnectedServer
    , Connection
    , LastConnection
    , PersistedRellmServer
    , RellmServer
    , ServerLogoSize(..)
    , brandingFor
    , brandingOf
    , configurationOf
    , connectToRellmServer
    , connectionOf
    , connectionUrl
    , disconnectedRellmServer
    , enableRellmServerFor
    , encodePersistedRellmServer
    , initialLetter
    , candidatePorts
    , isLocalNetworkHost
    , isLocalhost
    , elmPrefix
    , returnHost
    , isSecure
    , unsecureLocalhostAuthEnabled
    , knownConnectedRellmServer
    , mediaBaseUrl
    , mediaUrl
    , negotiateRellmServerConfig
    , negotiateRellmServerConfigWith
    , persistedRellmServerDecoder
    , previewOf
    , rellmServerForHost
    , rellmServerFrom
    , rellmServerInfoOf
    , rellmServerNameAndLogo
    , rellmServerThemeOf
    , rellmServerUrl
    , rellmServerWebPushPublicKey
    , resolveHost
    , resolvedFrontendHost
    , sharesPushKeyWithAnchor
    , updateRellmServerConfiguration
    , upsertRellmServer
    , upsertRellmServerAppend
    , withAccessToken
    )

{-| Everything about a Rellm `RellmServer` that doesn't need `Shared.AccountsPanel.Model` itself to
make sense: the type and its close relatives (`ConnectedServer`, `Connection`, `Branding`,
`PersistedRellmServer`), its encode/decode, and every pure/plain-`Task` piece of "connect to and
represent a server" logic (branding/theme/logo resolution, connection negotiation over candidate
ports, `RellmServer` list upserts). This is the dependency root of the `Shared.AccountsPanel.*`
account/server family -- `RellmAccounts` (and `MastodonAccounts`/`MastodonServers`/`BlueskyAccounts`,
indirectly, wherever they need to resolve a Rellm connection) import this, never the other way
around.

What's deliberately _not_ here, and stays in `Shared.AccountsPanel` itself: the `Model` field this
lives in (`servers`), and every `Msg`/`Cmd Msg`-constructing operation (`setWebUserInterface`,
`renameServer`, `changeServerShortName`, `updateServerConfig`, and the plain `serverForHost`/
`isKnownServer`/`isMainServer`/`enabledServers`/etc. lookups that take the whole `Model`) -- those are
`Shared.AccountsPanel.update`'s own coordinating logic.

-}

import Dict exposing (Dict)
import Grpc
import Html exposing (Html, div, img, text)
import Html.Attributes exposing (alt, class, src, title)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Proto.Rellm exposing (ServerConfiguration, ServerInfo)
import Proto.Rellm.Rellm as Rellm
import Request
import Shared.AccountsPanel.SortOrder exposing (sortOrderDecoder)
import Task exposing (Task)
import UI.ServerTheme
import Url


{-| A server the app knows about -- either from a persisted server list entry
or an account signed into it. `frontendHost` is the server's public identity,
e.g. "jonline.io" -- what a user types in and what accounts are keyed by.

`enabled` controls whether the server's (eventually public) data is included
when aggregating data across servers. It's tracked here (rather than only on
`connected`) because it's meaningful -- and persisted (see
`encodePersistedRellmServer`) -- even while disconnected.

`connected` is everything that's only known once we've actually negotiated
with the server (see `Shared.AccountsPanel.negotiateServerConfig`): `Nothing` for a server that's
currently unreachable (down, moved, or just not tried yet this session) --
see `disconnectedRellmServer`/`Shared.AccountsPanel.ReconnectServerClicked`. A server keeps its place in
`Model.servers` (and so its position in the persisted list/UI) whether or not
it's currently connected -- only `Shared.AccountsPanel.FinishRemoveServer` (an explicit user
delete) removes an entry outright.

-}
type alias RellmServer =
    { frontendHost : String
    , enabled : Bool
    , connected : Maybe ConnectedServer
    , sortOrder : Int
    }


{-| Everything about a `RellmServer` that's only known once we've actually connected to it.
-}
type alias ConnectedServer =
    { backendHost : String
    , port_ : Int
    , tls : Bool
    , configuration : ServerConfiguration
    , branding : Branding
    }


{-| A server's resolved display identity: name, logo, and primary/nav theme colors -- derived from
its `ServerConfiguration` (see `brandingFromConfig`), or a neutral fallback for one that's
unreachable/unknown (see `defaultBranding`).
-}
type alias Branding =
    { name : String
    , logoUrl : Maybe String
    , primary : UI.ServerTheme.ColorMeta
    , nav : UI.ServerTheme.ColorMeta
    }


{-| Just enough to actually reach a server: its public identity (`frontendHost`) plus where/how to
connect to it (`backendHost`/`port_`/`tls`) -- see `connectionUrl`.
-}
type alias Connection =
    { frontendHost : String
    , backendHost : String
    , port_ : Int
    , tls : Bool
    }


{-| The two fields of a `RellmServer` that actually get persisted -- `frontendHost`/`enabled` --
plus its `sortOrder`. Everything else (`connected`) is re-derived fresh every session via a
reconnect.
-}
type alias PersistedRellmServer =
    { frontendHost : String
    , enabled : Bool
    , sortOrder : Int

    -- How this server was last successfully reached, so the next visit can try that first instead of
    -- re-running port detection from scratch -- see `negotiateRellmServerConfigWith`.
    , lastConnection : Maybe LastConnection
    }


{-| The part of a `Connection` worth remembering between visits: where the gRPC API actually was (its
`backendHost`, `port_` and `tls`) the last time `negotiateRellmServerConfig` found it.
-}
type alias LastConnection =
    { backendHost : String
    , port_ : Int
    , tls : Bool
    }


connectionUrl : Connection -> String
connectionUrl connection =
    (if connection.tls then
        "https://"

     else
        "http://"
    )
        ++ connection.backendHost
        ++ ":"
        ++ String.fromInt connection.port_


{-| Media (avatars, server logos) is served over plain HTTP(S) on the standard
web port -- not the gRPC(-web) port a `Connection` was negotiated against for
actual API calls -- so this omits the port entirely (the browser defaults to
80/443 per scheme). Uses `frontendHost` (the server's branded domain, e.g.
`ato.band` standing in for the literal `ato.band.getj.online` host actual API
calls connect to -- see `resolvedFrontendHost`), not `backendHost`, since a
server declaring an `ExternalCdnConfig` is fully reverse-proxying that
branded domain through to the backend, `/media` included -- unlike
`connectionUrl`, which stays on `backendHost` for gRPC(-web) calls
specifically, since that's the host `candidatePorts` actually negotiated a
working connection against.
-}
mediaBaseUrl : Connection -> String
mediaBaseUrl connection =
    (if connection.tls then
        "https://"

     else
        "http://"
    )
        ++ connection.frontendHost


{-| A server's raw `ServerInfo` (name, description, privacy/media policy
text, etc.), defaulted the same way `brandingFromConfig` does -- for callers
that need fields `Branding` doesn't carry, e.g. `UI.createAccountConfirmationModal`
showing the description/privacy policy/media policy during account creation.
-}
rellmServerInfoOf : RellmServer -> ServerInfo
rellmServerInfoOf server =
    server.connected
        |> Maybe.andThen (\connected -> connected.configuration.serverInfo)
        |> Maybe.withDefault Proto.Rellm.defaultServerInfo


{-| A server's raw `ServerConfiguration`, falling back to
`Proto.Rellm.defaultServerConfiguration` while disconnected (see
`RellmServer.connected`) -- for callers (e.g. `Components.Pages.ServerInformationPage`)
that need more of it than `rellmServerInfoOf`'s `ServerInfo` carries.
-}
configurationOf : RellmServer -> ServerConfiguration
configurationOf server =
    server.connected
        |> Maybe.map .configuration
        |> Maybe.withDefault Proto.Rellm.defaultServerConfiguration


brandingFromConfig : Connection -> ServerConfiguration -> Branding
brandingFromConfig connection config =
    let
        info : ServerInfo
        info =
            Maybe.withDefault Proto.Rellm.defaultServerInfo config.serverInfo

        name : String
        name =
            info.name
                |> Maybe.andThen ifNonEmpty
                |> Maybe.withDefault connection.frontendHost

        logoUrl : Maybe String
        logoUrl =
            info.logo
                |> Maybe.andThen .squareMediaId
                |> Maybe.map (\id -> mediaBaseUrl connection ++ "/media/" ++ id)

        primaryArgb : Int
        primaryArgb =
            info.colors |> Maybe.andThen .primary |> Maybe.withDefault 0x00424242

        navArgb : Int
        navArgb =
            info.colors |> Maybe.andThen .navigation |> Maybe.withDefault 0x00FFFFFF
    in
    { name = name
    , logoUrl = logoUrl
    , primary = UI.ServerTheme.colorMetaFromArgb primaryArgb
    , nav = UI.ServerTheme.colorMetaFromArgb navArgb
    }


ifNonEmpty : String -> Maybe String
ifNonEmpty s =
    if String.isEmpty s then
        Nothing

    else
        Just s


{-| The (unauthorized) base URL for a piece of media by `id` on `server` --
e.g. avatars belonging to some other user (see `Components.Users.avatarUrl`),
which the caller may still need to append its own `?authorization=` to if
that media turns out to be visibility-restricted. `Nothing` if `server` is
currently disconnected -- there's no host to fetch it from.
-}
mediaUrl : RellmServer -> String -> Maybe String
mediaUrl server id =
    connectionOf server
        |> Maybe.map (\connection -> mediaBaseUrl connection ++ "/media/" ++ id)


{-| A server's branding, looked up by its `frontendHost` (for e.g. an
account's `server` field, cross-referenced against the server list), falling
back to the bare hostname and neutral colors if that server isn't known, or
is known but currently disconnected (see `RellmServer.connected`).
-}
brandingFor : List RellmServer -> String -> Branding
brandingFor servers frontendHost =
    servers
        |> List.filter (\s -> s.frontendHost == frontendHost)
        |> List.head
        |> Maybe.map brandingOf
        |> Maybe.withDefault (defaultBranding frontendHost)


defaultBranding : String -> Branding
defaultBranding frontendHost =
    { name = frontendHost
    , logoUrl = Nothing
    , primary = UI.ServerTheme.neutralColorMeta
    , nav = UI.ServerTheme.neutralColorMeta
    }


{-| A `RellmServer`'s branding, falling back to the bare hostname and neutral
colors while it's disconnected (see `RellmServer.connected`) -- `brandingFor`'s
same fallback, for callers that already have the `RellmServer` in hand rather
than just its `frontendHost`.
-}
brandingOf : RellmServer -> Branding
brandingOf server =
    server.connected
        |> Maybe.map .branding
        |> Maybe.withDefault (defaultBranding server.frontendHost)


{-| The full color theme for a server, combining its cached `branding` with
the app's current dark/light mode (`Shared.effectiveDarkMode`). Cheap -- fine
to call on every render.
-}
rellmServerThemeOf : Bool -> RellmServer -> UI.ServerTheme.ServerTheme
rellmServerThemeOf darkMode server =
    let
        branding : Branding
        branding =
            brandingOf server
    in
    UI.ServerTheme.fromColorMetas darkMode branding.primary branding.nav



-- SERVER NAME + LOGO
-- Port of the React app's `server_name_and_logo.tsx`: server names often
-- encode a short "badge" name before a `|` or the name's first emoji, with a
-- fuller name after it (e.g. "jonline.io | Jon's Cool Server 🎉"). This pulls
-- that apart and picks a logo (the server's square image, its emoji, or an
-- initial-letter placeholder, in that preference order) and font sizes so the
-- short badge name doesn't look tiny next to a long full one.


{-| `CompactServerLogo` is a single-line horizontal glyph+name, for tight
spaces like the nav bar; `RegularServerLogo` stacks a larger glyph above a
(possibly two-line) name, for the Accounts Panel's server chips.
`HorizontalServerLogo` is `RegularServerLogo`'s same larger glyph/(possibly
two-line) name, just laid out in a row (glyph left of the name) with the name
left-aligned instead of stacked/centered -- for contexts with more width to
spare than the nav bar but where a centered stack still reads oddly, e.g.
`Shared.Breadcrumbs`' server overview panel.
-}
type ServerLogoSize
    = RegularServerLogo
    | HorizontalServerLogo


rellmServerNameAndLogo : RellmServer -> ServerLogoSize -> Html msg
rellmServerNameAndLogo server size =
    let
        branding : Branding
        branding =
            brandingOf server

        ( namePrefix, emoji, nameSuffix ) =
            splitOnFirstEmoji True branding.name

        largeName : Bool
        largeName =
            String.length namePrefix < 10 && (nameSuffix == Nothing || nameSuffix == Just "")

        logo : Html msg
        logo =
            case branding.logoUrl of
                Just url ->
                    img [ class "server-logo-image", src url, alt branding.name ] []

                Nothing ->
                    let
                        hasEmoji : Bool
                        hasEmoji =
                            case emoji of
                                Just e ->
                                    e /= "" && e /= "|"

                                Nothing ->
                                    False
                    in
                    if hasEmoji then
                        div [ class "server-logo-emoji" ] [ text (Maybe.withDefault "" emoji) ]

                    else
                        div [ class "server-logo-placeholder" ] [ text (initialLetter branding.name) ]

        -- The emoji never gets folded into the primary line, even when it's
        -- not already standing in as the logo above (i.e. there's a real
        -- image logo) -- appending it as text throws off the browser's width
        -- measurement for the nav's ellipsis-truncated name (emoji glyphs
        -- need font-fallback shaping that the intrinsic-sizing pass
        -- under-measures vs. their actual painted width), causing the name
        -- to truncate early even with plenty of room on screen.
        primaryLine : String
        primaryLine =
            namePrefix

        -- `RegularServerLogo` and `HorizontalServerLogo` share the same
        -- larger glyph size and "large" primary-line/secondary-line logic --
        -- they differ only in layout (stacked+centered vs. row+left-aligned,
        -- both via `sizeClass` below), not sizing.
        isBig : Bool
        isBig =
            True

        primaryClasses : List String
        primaryClasses =
            "server-name-primary"
                :: (if isBig && largeName then
                        [ "large" ]

                    else
                        []
                   )

        showSecondary : Bool
        showSecondary =
            case nameSuffix of
                Just suffix ->
                    isBig && not largeName && suffix /= ""

                Nothing ->
                    False

        secondaryLine : Html msg
        secondaryLine =
            if showSecondary then
                div [ class "server-name-secondary" ] [ text (Maybe.withDefault "" nameSuffix) ]

            else
                text ""

        -- Mirrors exactly what's visually rendered below (one line, or two
        -- when `secondaryLine` is showing), so the native tooltip never says
        -- more or less than what's on screen.
        breakdownTitle : String
        breakdownTitle =
            if showSecondary then
                String.join "\n" [ primaryLine, Maybe.withDefault "" nameSuffix ]

            else
                primaryLine

        sizeClass : String
        sizeClass =
            case size of
                RegularServerLogo ->
                    "regular"

                HorizontalServerLogo ->
                    "horizontal"
    in
    div [ class ("server-name-and-logo " ++ sizeClass) ]
        [ logo
        , div [ class "server-name-breakdown", title breakdownTitle ]
            [ div [ class (String.join " " primaryClasses) ] [ text primaryLine ]
            , secondaryLine
            ]
        ]


{-| First letter of a name, upper-cased, for use as an avatar/logo placeholder
-- see `UI.imageOrInitial`. Not itself specific to `RellmServer` (every
account/instance avatar placeholder -- Rellm, Mastodon, Bluesky alike --
falls back to this too), but lives here since `rellmServerNameAndLogo` is its
original/primary consumer.
-}
initialLetter : String -> String
initialLetter fullName =
    fullName
        |> String.trim
        |> String.uncons
        |> Maybe.map (Tuple.first >> Char.toUpper >> String.fromChar)
        |> Maybe.withDefault "?"


{-| Splits a server's raw display name into `(badge, emoji, fullName)`: `badge` is everything
before the first `|` or emoji (whichever comes first), `emoji` is that separator itself (if any --
`Just "|"` when it was a pipe, `Just "🎉"` when it was an emoji run, `Nothing` if there was neither),
and `fullName` is everything after it, trimmed (`Nothing` if that's blank). A name with no `|` and
no emoji at all comes back as `( wholeTrimmedName, Nothing, Nothing )`. `supportPipe` gates the
`|`-detection half -- `False` skips straight to looking for an emoji only.
-}
splitOnFirstEmoji : Bool -> String -> ( String, Maybe String, Maybe String )
splitOnFirstEmoji supportPipe fullText =
    let
        chars : List Char
        chars =
            String.toList fullText

        isSplitChar : Char -> Bool
        isSplitChar c =
            isPictographic c || (supportPipe && c == '|')
    in
    case findIndex isSplitChar chars of
        Nothing ->
            ( fullText, Nothing, Nothing )

        Just idx ->
            let
                before : String
                before =
                    List.take idx chars |> String.fromList |> String.trim

                atSplit : List Char
                atSplit =
                    List.drop idx chars
            in
            case atSplit of
                '|' :: rest ->
                    ( before, Just "|", ifNonEmpty (String.trim (String.fromList rest)) )

                _ ->
                    let
                        ( emojiChars, rest ) =
                            takeEmojiRun atSplit
                    in
                    ( before, Just (String.fromList emojiChars), ifNonEmpty (String.trim (String.fromList rest)) )


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex pred list =
    list
        |> List.indexedMap Tuple.pair
        |> List.filter (Tuple.second >> pred)
        |> List.head
        |> Maybe.map Tuple.first


{-| Takes one whole emoji "run" starting at the head of `chars` (already known
to start with a pictographic code point): the base pictographic character,
plus any immediately-following continuation code points (variation
selectors, zero-width joiners + another pictographic, skin-tone modifiers,
regional indicators) that extend it into one visual glyph (e.g. a ZWJ
sequence like family emoji, or a flag's two regional indicators) -- see
`spanEmojiContinuation`.
-}
takeEmojiRun : List Char -> ( List Char, List Char )
takeEmojiRun chars =
    case chars of
        [] ->
            ( [], [] )

        first :: rest ->
            let
                ( continuation, remaining ) =
                    spanEmojiContinuation rest
            in
            ( first :: continuation, remaining )


spanEmojiContinuation : List Char -> ( List Char, List Char )
spanEmojiContinuation chars =
    case chars of
        [] ->
            ( [], [] )

        c :: rest ->
            if isEmojiContinuation c then
                let
                    ( more, remaining ) =
                        spanEmojiContinuation rest
                in
                ( c :: more, remaining )

            else
                ( [], chars )


isEmojiContinuation : Char -> Bool
isEmojiContinuation c =
    isPictographic c || isVariationSelector c || isZeroWidthJoiner c || isSkinToneModifier c


isVariationSelector : Char -> Bool
isVariationSelector c =
    Char.toCode c == 0xFE0F


isZeroWidthJoiner : Char -> Bool
isZeroWidthJoiner c =
    Char.toCode c == 0x200D


isSkinToneModifier : Char -> Bool
isSkinToneModifier c =
    let
        code : Int
        code =
            Char.toCode c
    in
    code >= 0x0001F3FB && code <= 0x0001F3FF


isRegionalIndicator : Char -> Bool
isRegionalIndicator c =
    let
        code : Int
        code =
            Char.toCode c
    in
    code >= 0x0001F1E6 && code <= 0x0001F1FF


{-| Whether `c` is a pictographic (emoji-capable) code point -- covers the
main emoji blocks plus symbol/dingbat ranges that browsers still render as
emoji-style glyphs (misc symbols, dingbats, transport/map symbols, misc
symbols/arrows). Not exhaustive of every Unicode emoji range, but covers
the vast majority of emoji actually used in server names.
-}
isPictographic : Char -> Bool
isPictographic c =
    let
        code : Int
        code =
            Char.toCode c
    in
    (code >= 0x0001F300 && code <= 0x0001FAFF)
        || (code >= 0x2600 && code <= 0x27BF)
        || (code >= 0x2300 && code <= 0x23FF)
        || (code >= 0x2B00 && code <= 0x2BFF)
        || isRegionalIndicator c


{-| Looks up a known server by its `frontendHost` -- e.g. for a route param
naming a specific server (see `Components.ServerDependentView`), or an
account's `server` field.
-}
rellmServerForHost : List RellmServer -> String -> Maybe RellmServer
rellmServerForHost servers frontendHost =
    servers |> List.filter (\s -> s.frontendHost == frontendHost) |> List.head


{-| The `RellmServer` to show `host`'s name/colors/logo off of, wherever the UI mentions a server by
host (a button offering to add or enable it, a federated-server chip, ...): the user's own server for
`host`, if it's known and connected; otherwise its preview in `previews` (`AccountsPanel.recommendedServerConnections`,
loaded by `AccountsPanel.EnsureServerPreviews` -- the same loader behind the recommended-servers strip); otherwise
whatever bare placeholder is left (the known-but-unreachable server, or a synthetic one), whose
`brandingOf` falls back to the host string alone -- so it's always safe to render, and gets better as
the preview resolves.
-}
previewOf : List RellmServer -> Dict String RellmServer -> String -> RellmServer
previewOf servers previews host =
    case rellmServerForHost servers host of
        Just known ->
            if known.connected == Nothing then
                Dict.get host previews |> Maybe.withDefault known

            else
                known

        Nothing ->
            Dict.get host previews
                |> Maybe.withDefault (disconnectedRellmServer { frontendHost = host, enabled = False, sortOrder = 0, lastConnection = Nothing })


{-| The VAPID public key `frontendHost`'s server would want a `RegisterPushSubscription` call
signed with -- `Nothing` if the server isn't connected, or is connected but has no `WebPushConfig`
(the admin hasn't set one up), either of which means there's nothing to actually push
notifications with. `UI.pushNotificationsMenuItem` only shows its toggle when this is `Just _` (and, via
`sharesPushKeyWithAnchor`, matches the app's own server's key).
-}
rellmServerWebPushPublicKey : List RellmServer -> String -> Maybe String
rellmServerWebPushPublicKey servers frontendHost =
    rellmServerForHost servers frontendHost
        |> Maybe.andThen .connected
        |> Maybe.andThen (\connected -> connected.configuration.webPushConfig)
        |> Maybe.map .publicVapidKey


{-| Whether `frontendHost`'s server can ride the same browser Web Push subscription as the app's
own server -- i.e. both advertise the same `WebPushConfig.publicVapidKey`. A browser holds one push
subscription per service worker, bound to one VAPID public key, but the subscription itself is just
an endpoint any server holding the matching private key can push to -- so an admin who pastes the
same keypair into several instances lets one subscription be registered with all of them.

`anchorHosts` are the hosts the service worker could be scoped to, tried in order until one has a
connected server with a key (`Shared.AccountsPanel.canUsePushNotifications` passes `browsingHost`
then `mainFrontendHost`, since the latter replaces the former when browsing via a CDN host). `False`
if no anchor has a key at all, or `frontendHost`'s server is unknown/disconnected/has no key.
-}
sharesPushKeyWithAnchor : List RellmServer -> List String -> String -> Bool
sharesPushKeyWithAnchor servers anchorHosts frontendHost =
    case
        ( anchorHosts |> List.filterMap (rellmServerWebPushPublicKey servers) |> List.head
        , rellmServerWebPushPublicKey servers frontendHost
        )
    of
        ( Just anchorKey, Just key ) ->
            anchorKey == key

        _ ->
            False


{-| `rellmServerForHost`, but only if that entry is both known _and_ actually
connected -- a known-but-disconnected entry (see `RellmServer.connected`) is
treated the same as not known at all. `Shared.AccountsPanel.init` seeds every persisted server
disconnected before its own reconnect attempt resolves (see that module's own
doc), so a route-driven fetch gated on plain server lookup alone can fire
against that placeholder the instant the app boots, before there's an actual
connection to fetch from -- failing immediately, and (since these fetches are
typically only attempted once) staying failed even after the real reconnect
lands moments later. Callers that need to fetch from a specific route-named
host (`Pages.Event.PostId_`, `Pages.Post.PostId_`,
`Components.Users.Resolver`) should gate on this instead of a plain lookup
directly.
-}
knownConnectedRellmServer : List RellmServer -> String -> Maybe RellmServer
knownConnectedRellmServer servers frontendHost =
    rellmServerForHost servers frontendHost
        |> Maybe.andThen
            (\server ->
                if server.connected /= Nothing then
                    Just server

                else
                    Nothing
            )


{-| A server's full base URL, for making requests against it directly (e.g.
`Components.Posts`' `GetPosts` calls) without needing to build a `Connection`.
-}
rellmServerUrl : RellmServer -> String
rellmServerUrl server =
    -- Every caller reaches `server` via account/server resolution that only ever hands back a
    -- connected `RellmServer` -- see `RellmServer.connected`. The empty-string fallback is
    -- unreachable in practice; this stays total rather than pushing a `Maybe` onto the many call
    -- sites that already know they're on solid ground.
    connectionOf server
        |> Maybe.map connectionUrl
        |> Maybe.withDefault ""


{-| Whether the page itself was loaded over TLS -- if so, `negotiateRellmServerConfig`/`resolveHost`
only ever try TLS candidates for a new host, since a secure page can't make plaintext requests (mixed
content). Only an insecure (e.g. local dev) page falls back to trying plaintext ports too.

Generic over `params` (rather than any one page's own `Request`) so any page can pass its own
`Request.With Params` straight in -- see `connectToRellmServer`'s own `pageIsSecure` parameter, which
every caller ultimately derives from this.

-}
isSecure : Request.With params -> Bool
isSecure req =
    req.url.protocol == Url.Https


{-| Whether `host` (a `frontendHost`, optionally with a `:port`) is `localhost` -- the one host
cross-server auth is ever allowed to talk to over plain `http://` (see `unsecureLocalhostAuthEnabled`).
-}
isLocalhost : String -> Bool
isLocalhost host =
    (String.split ":" host |> List.head |> Maybe.withDefault "" |> String.toLower) == "localhost"


{-| The host (plus `:port`, when served on a non-default one) a federated sign-in should return
to -- lets sessions on different ports (e.g. local Elm dev server vs. Rust server) each get sent
back to the one they came from.
-}
returnHost : String -> Maybe Int -> String
returnHost host port_ =
    case port_ of
        Just p ->
            host ++ ":" ++ String.fromInt p

        Nothing ->
            host


{-| The path prefix of the Elm app at `host[:port]`: the Elm dev server (port 1234) serves it at
the root, everything else (the Rust server) under `/elm`.
-}
elmPrefix : String -> String
elmPrefix host =
    if String.endsWith ":1234" host then
        ""

    else
        "/elm"


{-| Whether `config`'s server has opted in (`FederationInfo.unsecure_localhost_federated_auth_enabled`)
to handing federated-auth tokens to a plaintext `http://localhost` frontend. Servers that predate the
field (or leave it unset) read as `False`. Only a frontend-side guard: the server itself can't stop a
client from doing this.
-}
unsecureLocalhostAuthEnabled : ServerConfiguration -> Bool
unsecureLocalhostAuthEnabled config =
    config.federationInfo
        |> Maybe.andThen .unsecureLocalhostFederatedAuthEnabled
        |> Maybe.withDefault False


{-| Connects to a server given only its hostname, same as adding one via the
Account form's "Add Server" button -- but as a plain `Task`, for callers
outside the Accounts Panel that need to connect to a specific server
themselves (see `Components.ServerDependentView`) and decide what to do with
the result (typically dispatching `Shared.AccountsPanel.ServerConnected` once
it resolves, then proceeding with whatever they actually wanted the server
for).
-}
connectToRellmServer : Bool -> String -> Task Grpc.Error RellmServer
connectToRellmServer pageIsSecure frontendHost =
    negotiateRellmServerConfig pageIsSecure frontendHost
        |> Task.map (\( connection, config ) -> rellmServerFrom connection True config)


{-| Signing in/re-enabling an account whose server is still marked disabled
would leave it silently excluded from aggregated data anyway -- bring the
server along, mirroring what `Shared.AccountsPanel.ToggleServerEnabled` does for its accounts when
the server itself is disabled. Used by every path that force-enables an
account (`GotAuthResult`, `FederatedAccountReceived`, `ToggleAccountEnabled`).
-}
enableRellmServerFor : String -> List RellmServer -> List RellmServer
enableRellmServerFor frontendHost servers =
    List.map
        (\server ->
            if server.frontendHost == frontendHost then
                { server | enabled = True }

            else
                server
        )
        servers


{-| `sortOrder` is always `0` here -- irrelevant for a server that's just passing through as display
data (`GotCreateAccountServerInfo`'s confirmation modal, `recommendedServerConnections`) and,
whenever this actually lands in `model.servers`, always overwritten anyway: by `existing.sortOrder`
if `upsertRellmServerWith` finds this host already known, or by the caller's own `newSortOrder` if not --
see that function's own doc.
-}
rellmServerFrom : Connection -> Bool -> ServerConfiguration -> RellmServer
rellmServerFrom connection enabled config =
    { frontendHost = connection.frontendHost
    , enabled = enabled
    , connected =
        Just
            { backendHost = connection.backendHost
            , port_ = connection.port_
            , tls = connection.tls
            , configuration = config
            , branding = brandingFromConfig connection config
            }
    , sortOrder = 0
    }


{-| A server known only from a persisted server-list entry (or an account
signed into it), not yet (re)connected this session -- see `RellmServer.connected`.
Keeps `frontendHost`/`enabled` (the only two fields that get persisted) so it
still has its place in `Model.servers`, and so its `PersistedRellmServer` entry
survives a failed/never-attempted reconnect (see `GotReconnectResult`'s `Err`
branch) exactly as it would if nothing had gone wrong.
-}
disconnectedRellmServer : PersistedRellmServer -> RellmServer
disconnectedRellmServer persisted =
    { frontendHost = persisted.frontendHost
    , enabled = persisted.enabled
    , connected = Nothing
    , sortOrder = persisted.sortOrder
    }


{-| Adds/updates `server` in `servers` by `frontendHost`, keeping its existing
`sortOrder` (and existing `enabled` flag, if any -- see below) rather than
moving it to the front/back -- the reordering (`MoveServerFeedItemLeftClicked`/
`RightClicked`) or disconnection (`GotReconnectResult`'s `Err` branch)
already applied to that slot shouldn't be undone just because a fresh
connection/login/rename came in for it. For a genuinely new host, `newSortOrder`
places it (see `Shared.AccountsPanel.nextFrontSortOrder`/`nextBackSortOrder`) and it's prepended to
`servers` -- see `upsertRellmServerAppend` for the append-at-end variant used for
servers discovered via federation at first-setup time (list position no longer
drives render order at all, but still matters for `encodeState`'s own on-disk
ordering, which stays cosmetic).

Deliberately keeps the _existing_ entry's `enabled`/`sortOrder` over `server`'s
own -- `enabled` is a persisted user preference, independent of whether we're
currently connected, so a fresh reconnect (whose caller may only know the
`enabled` its host had at the _start_ of `init`'s startup sweep) should never
clobber a more recent in-session toggle applied to the same host's
placeholder while that reconnect was still in flight -- and the same
reconnect obviously shouldn't reset a user's own reordering either.

-}
upsertRellmServer : Int -> RellmServer -> List RellmServer -> List RellmServer
upsertRellmServer newSortOrder =
    upsertRellmServerWith (::) newSortOrder


{-| Same as `upsertRellmServer`, but for a genuinely new host appends it to the
_end_ of `servers` instead of prepending it. Used only for servers
discovered via `GotMainServerResult`'s `federatedServerCmds` at first-setup
time, so the base host's own federation recommendations land after any
servers the user already knew about, rather than jumping ahead of them.
-}
upsertRellmServerAppend : Int -> RellmServer -> List RellmServer -> List RellmServer
upsertRellmServerAppend newSortOrder =
    upsertRellmServerWith (\server servers -> servers ++ [ server ]) newSortOrder


upsertRellmServerWith : (RellmServer -> List RellmServer -> List RellmServer) -> Int -> RellmServer -> List RellmServer -> List RellmServer
upsertRellmServerWith insertNew newSortOrder server servers =
    case List.filter (\s -> s.frontendHost == server.frontendHost) servers |> List.head of
        Just existing ->
            List.map
                (\s ->
                    if s.frontendHost == server.frontendHost then
                        { server | enabled = existing.enabled, sortOrder = existing.sortOrder }

                    else
                        s
                )
                servers

        Nothing ->
            insertNew { server | sortOrder = newSortOrder } servers


{-| Patches a server's cached `configuration` (and re-derives `branding` from
it) in place after a config-changing RPC succeeds (rename, web-UI toggle,
settings save) -- shared by `GotSetWebUserInterfaceResult`/
`GotRenameServerResult`/`GotServerConfigSaveResult`. A no-op if `server` is
currently disconnected (see `RellmServer.connected`) -- unreachable in practice,
since all three only fire after an RPC that itself required a live
connection.
-}
updateRellmServerConfiguration : ServerConfiguration -> RellmServer -> RellmServer
updateRellmServerConfiguration newConfig server =
    case connectionOf server of
        Nothing ->
            server

        Just connection ->
            { server
                | connected =
                    Maybe.map
                        (\c -> { c | configuration = newConfig, branding = brandingFromConfig connection newConfig })
                        server.connected
            }


connectionOf : RellmServer -> Maybe Connection
connectionOf server =
    server.connected
        |> Maybe.map
            (\c -> { frontendHost = server.frontendHost, backendHost = c.backendHost, port_ = c.port_, tls = c.tls })


{-| A server's configuration can declare (via `externalCdnConfig`) that it's
really meant to be reached at a different public `frontendHost` than the one
we just connected to -- e.g. we're on jonline.io.getj.online, a CDN's backend
host, when it's actually configured to look like jonline.io. Falls back to
the host we connected to if there's no such declaration.
-}
resolvedFrontendHost : String -> ServerConfiguration -> String
resolvedFrontendHost connectedHost config =
    config.externalCdnConfig
        |> Maybe.map .frontendHost
        |> Maybe.andThen ifNonEmpty
        |> Maybe.withDefault connectedHost



-- CONNECTING


{-| Whether `host` (a `frontendHost`, optionally with a `:port`) is a development / local-network machine rather
than a public server: `localhost`, a single-label name (`armothy`), an mDNS / home-network name (`*.local`,
`*.lan`, `*.home.arpa`), a private or loopback IPv4 address (10/8, 172.16/12, 192.168/16, 127/8, 169.254/16),
or an IPv6 literal. Port detection treats these differently: they're never behind a CDN, plaintext is the norm,
and a wrong guess should fail fast (see `candidatePorts` and `negotiateRellmServerConfigWith`).
-}
isLocalNetworkHost : String -> Bool
isLocalNetworkHost host =
    let
        bare : String
        bare =
            if String.startsWith "[" host then
                host

            else
                host |> String.split ":" |> List.head |> Maybe.withDefault "" |> String.toLower

        octets : List Int
        octets =
            bare |> String.split "." |> List.filterMap String.toInt

        isPrivateIpv4 : Bool
        isPrivateIpv4 =
            case ( List.length (String.split "." bare) == 4, octets ) of
                ( True, [ a, b, _, _ ] ) ->
                    a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 169 && b == 254)

                _ ->
                    False
    in
    String.startsWith "[" bare
        || bare == "localhost"
        || not (String.contains "." bare)
        || List.any (\suffix -> String.endsWith suffix bare) [ ".local", ".lan", ".home.arpa" ]
        || isPrivateIpv4


{-| Candidate (port, tls) combinations to try, in order, against a server's backend host, once we know it. A
page loaded over TLS can only use TLS ones (a secure page can't make plaintext requests): the standard gRPC
port, then the standard HTTPS port. An insecure page also tries plaintext on the gRPC port, then 80, then 8000
-- and *which comes first* depends on the host: for a public server a plaintext connection is the unlikely
case, so TLS goes first; for a local / LAN development machine (`isLocalNetworkHost`) it's the other way
around -- plaintext gRPC (27707) is what a dev backend serves, so it's tried first and a dev server connects
on the first guess, instead of only after two TLS ones that, on some networks and devices, don't fail fast.
-}
candidatePorts : Bool -> String -> List ( Int, Bool )
candidatePorts pageIsSecure host =
    if pageIsSecure then
        [ ( 27707, True ), ( 443, True ) ]

    else if isLocalNetworkHost host then
        [ ( 27707, False ), ( 80, False ), ( 8000, False ), ( 27707, True ), ( 443, True ) ]

    else
        [ ( 27707, True ), ( 443, True ), ( 27707, False ), ( 80, False ), ( 8000, False ) ]


{-| Reuses an already-connected server's known-good connection and cached
configuration if we have one; otherwise negotiates a fresh connection.
-}
resolveHost : Bool -> List RellmServer -> String -> Task Grpc.Error ( Connection, ServerConfiguration )
resolveHost pageIsSecure servers frontendHost =
    case rellmServerForHost servers frontendHost |> Maybe.andThen .connected of
        Just connected ->
            Task.succeed ( { frontendHost = frontendHost, backendHost = connected.backendHost, port_ = connected.port_, tls = connected.tls }, connected.configuration )

        -- Not known, or known but currently disconnected (see `RellmServer.connected`)
        -- -- either way, there's no cached connection to reuse.
        Nothing ->
            negotiateRellmServerConfig pageIsSecure frontendHost


{-| Connects to a server given only its public (`frontendHost`) identity -- `negotiateRellmServerConfigWith`
without a remembered connection.
-}
negotiateRellmServerConfig : Bool -> String -> Task Grpc.Error ( Connection, ServerConfiguration )
negotiateRellmServerConfig =
    negotiateRellmServerConfigWith Nothing


{-| Connects to a server given only its public (`frontendHost`) identity, as cheaply as it can.

If we remember how this server was last reached (`hint`, persisted per server -- see
`PersistedRellmServer.lastConnection`), that exact connection is tried first, alone: the common case (the
server hasn't moved) is then a single request, and no port guessing at all. (A plaintext hint is ignored on a
secure page, which couldn't use it.) Only if that fails -- or there's no hint -- does the full detection run:
first discover the server's real backend host in case it's behind a CDN (`discoverBackendHost` -- skipped for
local / LAN hosts, which never are), then try each `candidatePorts` combination in turn, stopping at the
first that successfully returns server configuration, which doubles as the connectivity check ("can we talk
to a server here at all?") and a useful result (its configuration) at the same time.

Every request gets `Grpc.setTimeout` (`attemptTimeoutMillis`), because a wrong `(port_, tls)` doesn't always
fail fast -- a refused port is quick, but e.g. TLS against a plaintext-only port can leave the browser's own
connect/handshake timeout to eventually give up, which is far longer (tens of seconds) -- and the candidates
are tried one after another, so without a cap those waits add up. On a local / LAN host the cap is short,
since a wrong guess there is a mistake, not a slow link.

-}
negotiateRellmServerConfigWith : Maybe LastConnection -> Bool -> String -> Task Grpc.Error ( Connection, ServerConfiguration )
negotiateRellmServerConfigWith hint pageIsSecure frontendHost =
    let
        probe : Connection -> Task Grpc.Error ( Connection, ServerConfiguration )
        probe connection =
            Grpc.new Rellm.getServerConfiguration {}
                |> Grpc.setHost (connectionUrl connection)
                |> Grpc.setTimeout (attemptTimeoutMillis frontendHost)
                |> Grpc.toTask
                |> Task.map (\config -> ( connection, config ))

        tryPorts : String -> List ( Int, Bool ) -> Task Grpc.Error ( Connection, ServerConfiguration )
        tryPorts backendHost candidates =
            case candidates of
                [] ->
                    Task.fail Grpc.NetworkError

                ( port_, tls ) :: rest ->
                    probe { frontendHost = frontendHost, backendHost = backendHost, port_ = port_, tls = tls }
                        |> Task.onError (\_ -> tryPorts backendHost rest)

        detect : Task Grpc.Error ( Connection, ServerConfiguration )
        detect =
            discoverBackendHost pageIsSecure frontendHost
                |> Task.andThen (\backendHost -> tryPorts backendHost (candidatePorts pageIsSecure frontendHost))
    in
    case hint of
        Just last ->
            if pageIsSecure && not last.tls then
                detect

            else
                probe { frontendHost = frontendHost, backendHost = last.backendHost, port_ = last.port_, tls = last.tls }
                    |> Task.onError (\_ -> detect)

        Nothing ->
            detect


{-| How long each port-detection request may take before it counts as failed: 5 seconds for a public server
(slow links and CDNs happen), but only 1.5 for a local / LAN host (`isLocalNetworkHost`), whose round trip is
milliseconds -- so if its answer hasn't come by then, that guess was wrong.
-}
attemptTimeoutMillis : String -> Float
attemptTimeoutMillis frontendHost =
    if isLocalNetworkHost frontendHost then
        1500

    else
        5000


{-| A server's public "frontend" host may just be serving a web app that
points browsers at a different "backend" host for the actual gRPC API (e.g.
to sit behind a CDN that can't proxy gRPC-web) -- discoverable via a plain
`GET {frontendHost}/backend_host`, tried over HTTPS/443 then (only when this
page itself isn't secure) HTTP/80. Falls back to `frontendHost` itself
(meaning "no redirection") if that fails or comes back empty; never fails.
-}
discoverBackendHost : Bool -> String -> Task x String
discoverBackendHost pageIsSecure frontendHost =
    if isLocalNetworkHost frontendHost then
        -- A local / LAN development server is never fronted by a CDN: nothing to discover, and not a request
        -- (or, on a flaky network, two) spent finding that out.
        Task.succeed frontendHost

    else
        discoverBackendHostFor pageIsSecure frontendHost


discoverBackendHostFor : Bool -> String -> Task x String
discoverBackendHostFor pageIsSecure frontendHost =
    let
        tryTls : List Bool -> Task x String
        tryTls tlsFlags =
            case tlsFlags of
                [] ->
                    Task.succeed frontendHost

                tls :: rest ->
                    Http.task
                        { method = "GET"
                        , headers = []
                        , url =
                            (if tls then
                                "https://"

                             else
                                "http://"
                            )
                                ++ frontendHost
                                ++ "/backend_host"
                        , body = Http.emptyBody
                        , resolver =
                            Http.stringResolver
                                (\response ->
                                    case response of
                                        Http.GoodStatus_ _ body ->
                                            Ok body

                                        _ ->
                                            Err ()
                                )
                        , timeout = Just (attemptTimeoutMillis frontendHost)
                        }
                        |> Task.map
                            (\body ->
                                case String.trim body of
                                    "" ->
                                        frontendHost

                                    backendHost ->
                                        backendHost
                            )
                        |> Task.onError (\_ -> tryTls rest)
    in
    tryTls
        (if pageIsSecure then
            [ True ]

         else
            [ True, False ]
        )
        |> Task.onError (\_ -> Task.succeed frontendHost)


encodePersistedRellmServer : RellmServer -> Encode.Value
encodePersistedRellmServer server =
    Encode.object
        [ ( "frontendHost", Encode.string server.frontendHost )
        , ( "enabled", Encode.bool server.enabled )
        , ( "sortOrder", Encode.int server.sortOrder )

        -- Only a connected server knows where it was reached; a disconnected placeholder just omits it (so
        -- the next visit does a full detection, like any server it has no hint for).
        , ( "lastConnection"
          , case server.connected of
                Just connected ->
                    Encode.object
                        [ ( "backendHost", Encode.string connected.backendHost )
                        , ( "port", Encode.int connected.port_ )
                        , ( "tls", Encode.bool connected.tls )
                        ]

                Nothing ->
                    Encode.null
          )
        ]


persistedRellmServerDecoder : Decoder PersistedRellmServer
persistedRellmServerDecoder =
    Decode.map4 PersistedRellmServer
        (Decode.field "frontendHost" Decode.string)
        (Decode.field "enabled" Decode.bool)
        sortOrderDecoder
        -- Absent in anything persisted before this existed, and `null` for a server that wasn't connected.
        (Decode.oneOf
            [ Decode.field "lastConnection"
                (Decode.nullable
                    (Decode.map3 LastConnection
                        (Decode.field "backendHost" Decode.string)
                        (Decode.field "port" Decode.int)
                        (Decode.field "tls" Decode.bool)
                    )
                )
            , Decode.succeed Nothing
            ]
        )


withAccessToken : Maybe String -> Grpc.RpcRequest req res -> Grpc.RpcRequest req res
withAccessToken maybeToken req =
    case maybeToken of
        Just token ->
            Grpc.addHeader "authorization" token req

        Nothing ->
            req
