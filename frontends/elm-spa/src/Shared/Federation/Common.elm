module Shared.Federation.Common exposing (BlueskyAuth, Thread, anonymousBlueskyAuth, anonymousSearchHost, blueskyAuthFor, emptyThread, jsonResolver, jsonResolverWithHeaders, maxServerStarPages, maxServerStars, nonEmpty, publicBlueskyAppViewHost, sensitiveMediaHiddenId)

{-| Small helpers shared across Rellm's federation-protocol integrations -- currently
`Shared.Federation.Mastodon`/`Bluesky`'s own post-fetching, and `Shared.AccountsPanel`'s Mastodon/
Bluesky account-connection tasks. Not meant to grow into a general-purpose utils module, just a home
for the bits those would otherwise each duplicate.
-}

import Dict exposing (Dict)
import Http
import Json.Decode as Decode
import Proto.Rellm exposing (Post)


{-| Where (and as whom) a Bluesky/AT Protocol XRPC read or write is sent -- `host` is the bare hostname
of whichever server speaks `app.bsky.*` to this caller, and `accessToken` the bearer token to send it
(`""` for none). For a connected account that is the account's own PDS (see
`Shared.AccountsPanel.BlueskyAccounts.BlueskyAccount.pdsHost` -- the PDS logs the account in and proxies
`app.bsky.*` reads on to an AppView on its behalf); for anonymous browsing it is an AppView directly
(`publicBlueskyAppViewHost`, or whichever other `BlueskyServer` host), with no token.
-}
type alias BlueskyAuth =
    { host : String
    , accessToken : String
    }


{-| Bluesky PBC's public AppView -- serves public posts/threads/profiles/feeds with no auth at all, and
with CORS enabled for browsers. Shown to users as just "bsky.app".
-}
publicBlueskyAppViewHost : String
publicBlueskyAppViewHost =
    "public.api.bsky.app"


{-| The host to send an anonymous `app.bsky.feed.searchPosts` to for the AppView at `host`. Bluesky PBC's
public AppView (`public.api.bsky.app`) answers everything else anonymously but rejects search with a
403; the same AppView's other front door, `api.bsky.app`, serves search with no login (and CORS enabled),
so search goes there. Any other AppView is assumed to search at its own host.
-}
anonymousSearchHost : String -> String
anonymousSearchHost host =
    if host == publicBlueskyAppViewHost then
        "api.bsky.app"

    else
        host


{-| Reads anonymously from `publicBlueskyAppViewHost`.
-}
anonymousBlueskyAuth : BlueskyAuth
anonymousBlueskyAuth =
    { host = publicBlueskyAppViewHost, accessToken = "" }


{-| Reads anonymously from the given AppView `host` (a `BlueskyServer.host`).
-}
blueskyAuthFor : String -> BlueskyAuth
blueskyAuthFor host =
    { host = host, accessToken = "" }


{-| A reserved `MediaReference.id` (never a real Rellm media id, which is always a UUID) that
`Mastodon.toPostWith`/`Bluesky.toPostWith` put as `Post.media`'s one placeholder entry whenever a
`sensitive`-flagged federated post's real media was stripped (see either's own doc) but the post did
have media -- `Components.Posts.hasHiddenSensitiveMedia` looks for it to show a "This post contains
sensitive media" notice in `postCard`/`replyCard` instead of silently rendering nothing, without
Rellm's `Post`/`MediaReference` protos needing a real field for a concept (federated NSFW flagging)
that has no equivalent for a native Rellm post at all. Kept here, rather than in either federation
module, so `Components.Posts` (which knows about neither Mastodon nor Bluesky specifically) can check
for it without importing either.
-}
sensitiveMediaHiddenId : String
sensitiveMediaHiddenId =
    "sensitive-media-hidden"


{-| A federated post's surrounding conversation, already translated into Rellm `Post`s: `ancestors`
is the chain of posts it replies to (oldest first), `replies` its direct replies, each carrying its own
nested replies in `Post.replies` (see `Shared.Federation.Mastodon.fetchThread`/
`Shared.Federation.Bluesky.fetchThread` for how each service's own thread shape is folded into this).
Rendered by `Components.FederatedThread`.
-}
type alias Thread =
    { ancestors : List Post
    , replies : List Post
    }


emptyThread : Thread
emptyThread =
    { ancestors = [], replies = [] }


{-| `""` -> `Nothing`, anything else -> `Just` itself -- several third-party APIs (Mastodon's
`display_name`, when unset) use a blank string rather than a missing/null field as their own
"nothing set" convention.
-}
nonEmpty : String -> Maybe String
nonEmpty s =
    if String.isEmpty s then
        Nothing

    else
        Just s


{-| The most server-side stars (Bluesky likes, Mastodon favourites) the Starred panel's Server tab loads per
account. Neither service says how many there are in total -- Bluesky's profile has follower/follow/post counts but no
likes count, `describeRepo` only lists collection names, and both lists page by cursor (`Link` header on
Mastodon) -- so the only way to count is to follow the pages; this is where it stops (the tab then shows
"300+"). Every row is a mounted card, so it can't be unbounded.
-}
maxServerStars : Int
maxServerStars =
    300


{-| A hard stop on pages followed for one list, whatever they hold: a page can come back short or even empty
(posts that were deleted or blocked are dropped) while still handing out a cursor, so counting posts alone
couldn't bound the loop.
-}
maxServerStarPages : Int
maxServerStarPages =
    10


{-| `jsonResolver` that also hands back the response's headers (names lowercased, as `Http.Metadata` gives
them) -- for a paged list whose next page is named in a `Link` header.
-}
jsonResolverWithHeaders : Decode.Decoder a -> (Http.Metadata -> String -> Http.Error) -> Http.Resolver Http.Error ( a, Dict String String )
jsonResolverWithHeaders decoder onBadStatus =
    Http.stringResolver
        (\response ->
            case response of
                Http.GoodStatus_ metadata body ->
                    case Decode.decodeString decoder body of
                        Ok value ->
                            Ok ( value, metadata.headers )

                        Err err ->
                            Err (Http.BadBody (Decode.errorToString err))

                Http.BadStatus_ metadata body ->
                    Err (onBadStatus metadata body)

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)
        )


{-| Builds an `Http.task`'s `resolver` for a JSON API: decodes `decoder` out of a `GoodStatus_`
body (`Http.BadBody` on a decode failure), maps `NetworkError_`/`Timeout_`/`BadUrl_` onto their own
`Http.Error` constructors, and hands a `BadStatus_`'s metadata/body to `onBadStatus` to build
whatever `Http.Error` is most useful for that specific API's own error shape -- e.g.
`Shared.AccountsPanel.MastodonAccountAndServers.verifyCredentialsTask`'s just uses the bare status
code, while `Shared.AccountsPanel.BlueskyAccounts.createSessionTask`'s tries to pull a
human-readable `message` out of the body first. Shared
by every caller so this `GoodStatus_`/`NetworkError_`/`Timeout_`/`BadUrl_` boilerplate isn't
duplicated across them.
-}
jsonResolver : Decode.Decoder a -> (Http.Metadata -> String -> Http.Error) -> Http.Resolver Http.Error a
jsonResolver decoder onBadStatus =
    Http.stringResolver
        (\response ->
            case response of
                Http.GoodStatus_ _ body ->
                    case Decode.decodeString decoder body of
                        Ok value ->
                            Ok value

                        Err err ->
                            Err (Http.BadBody (Decode.errorToString err))

                Http.BadStatus_ metadata body ->
                    Err (onBadStatus metadata body)

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.BadUrl_ url ->
                    Err (Http.BadUrl url)
        )
