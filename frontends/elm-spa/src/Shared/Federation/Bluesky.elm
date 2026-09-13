module Shared.Federation.Bluesky exposing
    ( ActorProfile
    , FeedPost
    , decoder
    , fetchActorProfile
    , fetchAuthorFeed
    , fetchFollowers
    , fetchFollows
    , fetchPost
    , fetchPosts
    , searchActors
    , searchPosts
    , toPost
    )

{-| Translates Bluesky's (AT Protocol) API into Rellm's `Post` shape, entirely client-side -- see
`Shared.BlueskyAccount`'s own doc for the connection side this feeds off of. Unlike
Mastodon, there's no meaningful *unauthenticated* equivalent: a bare "public timeline" isn't a
concept AT Proto's federated network has (every PDS only ever serves its own users' own posts/feeds,
not a "local instance timeline" the way a Mastodon server does), so `fetchPosts` is a connected
account's own home timeline; `searchPosts`/`fetchPost` are both exceptions -- real endpoints that
read the wider public network rather than just the connected account's own timeline, still requiring
the same auth (there's no anonymous access to anything on Bluesky, unlike Mastodon). See
`Components.Pages.PostsPage.fetchFeedSource`'s `BlueskyFeed` case (`fetchPosts`/`searchPosts`) and
`Components.Pages.PostPage.init` (`fetchPost`, when a route's post id parses as
`Components.Posts.BlueskyPostId`) for how each gets wired into a real page.

`ActorProfile`/`fetchActorProfile`/`fetchAuthorFeed`/`fetchFollowers`/`fetchFollows` back
`Components.Pages.BlueskyUserProfilePage`/`BlueskyUsersPage` -- resolving one specific actor's own
profile/authored-posts/followers/follows, rather than the connected account's own home timeline.
Every one of these still needs a connected account's `accessToken` to authenticate with (there's no
anonymous AT Proto access at all, same as everything else in this module), but works against *any*
handle, not just that account's own -- same "any connected token works" reasoning `fetchPost`'s own
doc already covers for reading someone else's public post.
-}

import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Proto.Rellm exposing (Author, Post, defaultAuthor, defaultMediaReference, defaultPost, wrapMediaReference)
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Conversions exposing (posixToTimestamp)
import Shared.Federation.Common exposing (jsonResolver, nonEmpty)
import Task exposing (Task)
import Time
import Url


{-| Just the fields of one `app.bsky.feed.defs#feedViewPost` (one element of
`GET /xrpc/app.bsky.feed.getTimeline`'s `feed` array) that `toPost` actually needs -- see
<https://docs.bsky.app/docs/api/app-bsky-feed-get-timeline>. `uri` is the post's `at://` URI
(`at://{did}/app.bsky.feed.post/{rkey}`), used both as this post's own identity and (via `webUrl`)
to build a real `https://bsky.app/...` link a browser can actually open.
-}
type alias FeedPost =
    { uri : String
    , text : String
    , createdAt : Time.Posix
    , isReply : Bool
    , authorHandle : String
    , authorDisplayName : Maybe String
    , authorAvatarUrl : Maybe String
    }


decoder : Decoder FeedPost
decoder =
    Decode.map7 FeedPost
        (Decode.at [ "post", "uri" ] Decode.string)
        (Decode.at [ "post", "record", "text" ] Decode.string)
        (Decode.at [ "post", "record", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.field "reply" Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "post", "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "post", "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "post", "author", "avatar" ] Decode.string))


{-| A `FeedPost`'s translation into a Rellm `Post` -- `id` is just the bare `feedPost.uri` (an
`at://` URI, already globally unique on its own -- it embeds the author's DID), *not* further
prefixed with `"bluesky:"` the way it briefly was, mirroring `Shared.Federation.Mastodon.toPost`'s
own bare `status.id` -- see that function's own doc on why (a federated post's `id` is never used
without its synthetic host alongside it, which already carries the `"bluesky:"` tag). `link` is a
real `https://bsky.app/...` URL (see `webUrl`) built from the `at://` URI, since that's meaningless
to a browser directly. `visibility` is always `GLOBALPUBLIC`: everything in a Bluesky timeline is
already public (AT Protocol has no private-post concept at all). `author.avatar` uses
`MediaReference.url`, same reasoning as Mastodon's own translation.
-}
toPost : FeedPost -> Post
toPost feedPost =
    { defaultPost
        | id = feedPost.uri
        , author = Just (toAuthor feedPost)
        , content = Just feedPost.text
        , link = Just (webUrl feedPost)
        , context =
            if feedPost.isReply then
                REPLY

            else
                POST
        , visibility = GLOBALPUBLIC
        , createdAt = Just (posixToTimestamp feedPost.createdAt)
        , lastActivityAt = Just (posixToTimestamp feedPost.createdAt)
    }


{-| `GET /xrpc/app.bsky.feed.getTimeline` against `bsky.social` (see `BlueskyAccount`'s own doc on
that fixed-PDS limitation), authenticated with `accessToken`, already translated via `toPost` -- the
connected account's own algorithmic home timeline (reverse-chronological-following, by default), the
AT Protocol equivalent of `ALL_ACCESSIBLE_POSTS`.
-}
fetchPosts : String -> Task Http.Error (List Post)
fetchPosts accessToken =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "feed" (Decode.list decoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


{-| `GET /xrpc/app.bsky.feed.searchPosts` -- Bluesky's real search endpoint, searching the whole
public network (not just the connected account's own timeline/follows) -- see
<https://docs.bsky.app/docs/api/app-bsky-feed-search-posts>. Requires auth despite that broad scope
(confirmed empirically: an unauthenticated request gets a clean `AuthMissing` JSON error, not a
network/CORS failure), so this is only ever called for an already-connected `BlueskyAccount` -- see
`Components.Pages.PostsPage.fetchFeedSource`'s `BlueskyFeed` case, which switches to this instead of
`fetchPosts` whenever `model.searchText` isn't blank, mirroring how a real `GetPosts` request switches
to `TEXTSEARCH`. Unlike `getTimeline`'s `feed` array (each entry wrapping a `post` alongside separate
`reply` context), each entry here is a bare `app.bsky.feed.defs#postView` directly, so `searchDecoder`
reads its fields one level shallower than `decoder` does, and detects a reply via the post's own
`record.reply` field being present (the same information `getTimeline`'s sibling `reply` field
carries, just nested differently here) rather than a sibling key.
-}
searchPosts : String -> String -> Task Http.Error (List Post)
searchPosts accessToken query =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.feed.searchPosts?q=" ++ Url.percentEncode query ++ "&limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "posts" (Decode.list searchDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


searchDecoder : Decoder FeedPost
searchDecoder =
    Decode.map7 FeedPost
        (Decode.field "uri" Decode.string)
        (Decode.at [ "record", "text" ] Decode.string)
        (Decode.at [ "record", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.at [ "record", "reply" ] Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "author", "avatar" ] Decode.string))


{-| `GET /xrpc/app.bsky.feed.getPosts` for a single `uri` -- a real single-post lookup by AT URI,
authenticated the same way `searchPosts` is (any connected account's token works; this reads public
data regardless of whose token it is). A batch API in general (`uris` takes a comma-separated list),
but always called here with exactly one, so `Decode.field "posts"` is expected to come back with
either one element or none (deleted/never-existed) -- the latter fails the whole decode, surfacing as
an `Http.Error` the same as any other not-found. Response items are the same bare
`app.bsky.feed.defs#postView` shape `searchPosts` gets, so this reuses `searchDecoder` too.
-}
fetchPost : String -> String -> Task Http.Error Post
fetchPost accessToken uri =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.feed.getPosts?uris=" ++ Url.percentEncode uri
        , body = Http.emptyBody
        , resolver =
            jsonResolver
                (Decode.field "posts" (Decode.list searchDecoder)
                    |> Decode.andThen
                        (\posts ->
                            case posts of
                                first :: _ ->
                                    Decode.succeed first

                                [] ->
                                    Decode.fail "post not found"
                        )
                )
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map toPost


{-| `at://{did}/app.bsky.feed.post/{rkey}` -> `https://bsky.app/profile/{handle}/post/{rkey}` --
the `rkey` (record key) is always the URI's last `/`-separated segment, regardless of the
collection/DID that precede it.
-}
webUrl : FeedPost -> String
webUrl feedPost =
    "https://bsky.app/profile/"
        ++ feedPost.authorHandle
        ++ "/post/"
        ++ (feedPost.uri |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault "")


toAuthor : FeedPost -> Author
toAuthor feedPost =
    { defaultAuthor
        | userId = "bluesky:" ++ feedPost.authorHandle
        , username = Just feedPost.authorHandle
        , realName = feedPost.authorDisplayName
        , avatar = feedPost.authorAvatarUrl |> Maybe.map (\url -> wrapMediaReference { defaultMediaReference | url = Just url })
    }


{-| Just the fields of AT Proto's `app.bsky.actor.defs#profileView`/`#profileViewDetailed` that
`BlueskyUserProfilePage`/`BlueskyUsersPage` need -- see
<https://docs.bsky.app/docs/api/app-bsky-actor-get-profile>. `followersCount`/`followsCount`/
`postsCount` are only present on the "detailed" shape `getProfile` itself returns (a bare
`profileView`, e.g. from `getFollowers`/`getFollows`, omits them) -- defaulted to `0` rather than
failing the decode, since `BlueskyUsersPage`'s own follower/following rows don't display counts at
all (only `BlueskyUserProfilePage`'s single `getProfile` call ever needs them to be real).
-}
type alias ActorProfile =
    { handle : String
    , displayName : Maybe String
    , avatarUrl : Maybe String
    , description : Maybe String
    , followersCount : Int
    , followsCount : Int
    , postsCount : Int
    }


actorProfileDecoder : Decoder ActorProfile
actorProfileDecoder =
    Decode.map7 ActorProfile
        (Decode.field "handle" Decode.string)
        (Decode.maybe (Decode.field "displayName" Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.field "avatar" Decode.string))
        (Decode.maybe (Decode.field "description" Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.oneOf [ Decode.field "followersCount" Decode.int, Decode.succeed 0 ])
        (Decode.oneOf [ Decode.field "followsCount" Decode.int, Decode.succeed 0 ])
        (Decode.oneOf [ Decode.field "postsCount" Decode.int, Decode.succeed 0 ])


{-| `GET /xrpc/app.bsky.actor.getProfile` for `handle` -- a fuller profile than
`Shared.AccountsPanel.BlueskyAccounts.fetchProfileTask`'s own (bio, follower/following/post counts,
not just avatar/display name), for `BlueskyUserProfilePage`'s own header. Kept here rather than
extending that module's narrower `BlueskyProfile` -- this is "view anyone's public profile," that one
is specifically "the account that was just connected via `createSessionTask`," a different concern
even though both happen to hit the same endpoint.
-}
fetchActorProfile : String -> String -> Task Http.Error ActorProfile
fetchActorProfile accessToken handle =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.actor.getProfile?actor=" ++ Url.percentEncode handle
        , body = Http.emptyBody
        , resolver = jsonResolver actorProfileDecoder (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /xrpc/app.bsky.feed.getAuthorFeed` for `handle` -- that specific actor's own authored posts
(replies/reposts included, same as Mastodon's `fetchAccountStatuses` -- AT Proto has no
`exclude_replies`-style filter on this endpoint), already translated via `toPost`. Unlike
`fetchPosts`' home timeline (the connected account's own follows), this is any one actor's own feed
regardless of who's authenticating the request -- exactly what `BlueskyUserProfilePage`'s embedded
`Components.Pages.PostsPage` needs (see that module's own `BlueskyAuthorFeed` `FeedSource`).
-}
fetchAuthorFeed : String -> String -> Task Http.Error (List Post)
fetchAuthorFeed accessToken handle =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.feed.getAuthorFeed?actor=" ++ Url.percentEncode handle ++ "&limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "feed" (Decode.list decoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


{-| `GET /xrpc/app.bsky.graph.getFollowers` -- up to 40 of `handle`'s followers. No pagination beyond
that first page -- see `Components.Pages.BlueskyUsersPage`'s own doc on why that's an accepted
first-pass limitation, mirroring `Shared.Federation.Mastodon.fetchFollowers`'s identical choice.
-}
fetchFollowers : String -> String -> Task Http.Error (List ActorProfile)
fetchFollowers accessToken handle =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.graph.getFollowers?actor=" ++ Url.percentEncode handle ++ "&limit=40"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "followers" (Decode.list actorProfileDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /xrpc/app.bsky.graph.getFollows` -- `fetchFollowers`'s own doc, just the other direction
(AT Proto's own "follows" naming for what Mastodon/Rellm call "following").
-}
fetchFollows : String -> String -> Task Http.Error (List ActorProfile)
fetchFollows accessToken handle =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.graph.getFollows?actor=" ++ Url.percentEncode handle ++ "&limit=40"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "follows" (Decode.list actorProfileDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /xrpc/app.bsky.actor.searchActors` -- AT Proto's own global actor search (by handle or
display name, network-wide, not scoped to the authenticating account's own follows). Backs
`Components.Pages.UsersPage`'s own unfiltered listing once a search is typed in, same "any connected
account's token works" reasoning `searchPosts`'s own doc already covers.
-}
searchActors : String -> String -> Task Http.Error (List ActorProfile)
searchActors accessToken query =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.actor.searchActors?q=" ++ Url.percentEncode query ++ "&limit=25"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "actors" (Decode.list actorProfileDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
