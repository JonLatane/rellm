module Shared.Federation.Bluesky exposing
    ( ActorProfile
    , BlueskyImage
    , FeedPost
    , decoder
    , fetchActorProfile
    , fetchAuthorFeed
    , fetchFollowers
    , fetchFollows
    , fetchLikes
    , fetchPost
    , fetchPostWithQuotes
    , fetchPosts
    , fetchThread
    , fromRouteId
    , searchActors
    , routeId
    , searchPosts
    , setLike
    , toPost
    , toPostIncludingSensitiveMedia
    )

{-| Translates Bluesky's (AT Protocol) API into Rellm's `Post` shape, entirely client-side -- see
`Shared.BlueskyAccount`'s own doc for the connection side this feeds off of. Unlike
Mastodon, there's no meaningful _unauthenticated_ equivalent: a bare "public timeline" isn't a
concept AT Proto's federated network has (every PDS only ever serves its own users' own posts/feeds,
not a "local instance timeline" the way a Mastodon server does), so `fetchPosts` is a connected
account's own home timeline; `searchPosts`/`fetchPost` are both exceptions -- real endpoints that
read the wider public network rather than just the connected account's own timeline, still requiring
the same auth -- except `fetchPost`/`fetchThread`, which fall back to Bluesky's public AppView with no
account at all (see `readHost`). See
`Components.Pages.PostsPage.fetchFeedSource`'s `BlueskyFeed` case (`fetchPosts`/`searchPosts`) and
`Components.Pages.PostPage.init` (`fetchPost`, when a route's post id parses as
`Components.Posts.BlueskyPostId`) for how each gets wired into a real page.

`ActorProfile`/`fetchActorProfile`/`fetchAuthorFeed`/`fetchFollowers`/`fetchFollows` back
`Components.Bluesky.BlueskyUserProfilePage`/`BlueskyUsersPage` -- resolving one specific actor's own
profile/authored-posts/followers/follows, rather than the connected account's own home timeline.
Every one of these still needs a connected account's `accessToken` to authenticate with (there's no
anonymous AT Proto access at all, same as everything else in this module), but works against _any_
handle, not just that account's own -- same "any connected token works" reasoning `fetchPost`'s own
doc already covers for reading someone else's public post.

-}

import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Proto.Rellm exposing (Author, MediaReference, Post, defaultAuthor, defaultMediaReference, defaultMediaSize, defaultPost, wrapMediaReference, wrapPost)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Conversions exposing (int64FromInt, posixToTimestamp)
import Shared.Federation.Common exposing (Thread, jsonResolver, nonEmpty, sensitiveMediaHiddenId)
import Task exposing (Task)
import Time
import Url


{-| One element of an `app.bsky.embed.images#view`'s `images` array (the only `embed` shape
`toPost` translates -- see `imagesDecoder`'s own doc for `app.bsky.embed.video#view`/
`app.bsky.embed.external#view`, the two it doesn't). `fullsize` (not `thumb`, a low-res placeholder)
is this image's real URL -- same "skip the two-tier fetch" reasoning as
`Shared.Federation.Mastodon.MediaAttachment.url`'s own doc.
-}
type alias BlueskyImage =
    { url : String
    , alt : Maybe String
    , width : Maybe Int
    , height : Maybe Int
    }


{-| Just the fields of one `app.bsky.feed.defs#feedViewPost` (one element of
`GET /xrpc/app.bsky.feed.getTimeline`'s `feed` array) that `toPost` actually needs -- see
<https://docs.bsky.app/docs/api/app-bsky-feed-get-timeline>. `uri` is the post's `at://` URI
(`at://{did}/app.bsky.feed.post/{rkey}`), used both as this post's own identity and (via `webUrl`)
to build a real `https://bsky.app/...` link a browser can actually open. `sensitive` reads
`postView.labels` (AT Proto's own moderation-label array -- e.g. a self-applied `"porn"`/`"sexual"`/
`"nudity"`/`"graphic-media"` value from the adult-content vocab) -- any label present at all is
treated as "hide by default", the same coarse, allow-nothing-through-by-mistake reading
`toPostWith`'s own doc covers for why this only ever gates `images`, never blocks the post text
itself. `likeCount`/`replyCount` are AT Proto's own real, server-aggregated, publicly-visible counts on
every `postView` (present unauthenticated in spirit -- everything in this module still needs a
connected account's own token to ask for it, per this module's own doc, but the counts themselves
aren't gated on being that post's author) -- unlike `Post.unauthenticatedStarCount`, AT Proto doesn't
anonymize these at all (there's even a dedicated `getLikes` endpoint listing who liked a post), so
`toPostWith` maps them straight into the equivalent `Post` fields for display -- see that function's
own doc on why that's read-only: Rellm's own star button still can't actually push a real like to
Bluesky.
-}
type alias FeedPost =
    { uri : String
    , text : String
    , createdAt : Time.Posix
    , isReply : Bool
    , authorHandle : String
    , authorDisplayName : Maybe String
    , authorAvatarUrl : Maybe String
    , images : List BlueskyImage
    , sensitive : Bool
    , likeCount : Int
    , replyCount : Int
    , quote : Maybe Quote
    }


{-| The post `FeedPost.quote`s (an `app.bsky.embed.record`/`recordWithMedia` embed) -- `uri` is always
known, `post` only if AT Proto's own hydration already inlined it (one level of quote-of-quote at
most, see `viewRecordDecoder`; Bluesky's own UI doesn't surface even that). `fetchPostWithQuotes` fills
in the rest by fetching each missing `uri` itself. A custom type rather than a plain record field since
`FeedPost` and its own quote are mutually recursive.
-}
type Quote
    = Quote { uri : String, post : Maybe FeedPost }


{-| How many levels of quotes a single post's own page (`fetchPostWithQuotes`) resolves -- a post
quoting a post quoting a post ... up to this many deep. A feed/card context (`toPost`) only ever shows
the first, see `toPostWith`.
-}
maxPageQuoteDepth : Int
maxPageQuoteDepth =
    5


{-| `Decode.map8` is already at `elm/json`'s own arity ceiling, so `sensitive`/`likeCount`/
`replyCount` (the 9th-11th fields) are threaded through via `andThen` instead, mirroring
`Shared.Federation.Mastodon.decoder`'s identical trick for its own 9th-12th fields.
-}
decoder : Decoder FeedPost
decoder =
    Decode.map8
        (\uri text createdAt isReply authorHandle authorDisplayName authorAvatarUrl images ->
            \sensitive likeCount replyCount quote ->
                { uri = uri
                , text = text
                , createdAt = createdAt
                , isReply = isReply
                , authorHandle = authorHandle
                , authorDisplayName = authorDisplayName
                , authorAvatarUrl = authorAvatarUrl
                , images = images
                , sensitive = sensitive
                , likeCount = likeCount
                , replyCount = replyCount
                , quote = quote
                }
        )
        (Decode.at [ "post", "uri" ] Decode.string)
        (Decode.at [ "post", "record", "text" ] Decode.string)
        (Decode.at [ "post", "record", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.field "reply" Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "post", "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "post", "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "post", "author", "avatar" ] Decode.string))
        (imagesDecoder [ "post", "embed", "images" ])
        |> Decode.andThen (\f -> Decode.map f (sensitiveDecoder [ "post", "labels" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "post", "likeCount" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "post", "replyCount" ]))
        |> Decode.andThen (\f -> Decode.map f (quoteDecoder [ "post", "record" ] (Decode.maybe (Decode.at [ "post", "embed" ] embedViewQuoteDecoder))))


{-| `embedPath ++ [ "images" ]` (e.g. `[ "post", "embed", "images" ]` for `decoder`'s nested
`feedViewPost` shape, `[ "embed", "images" ]` for `searchDecoder`'s flatter one) if that path exists
and is actually an `app.bsky.embed.images#view` (i.e. carries an `images` array at all) --
`Decode.oneOf`'s fallback to `[]` covers every other case in one go: no `embed` at all (a plain text
post), or an `embed` that's really an `app.bsky.embed.video#view` (a single video, keyed `video`, not
`images`) or `app.bsky.embed.external#view` (a link-card thumbnail, keyed `thumb`, not real post
media -- rendering a target site's own preview image as if the author had attached it would be
misleading) -- neither translated here, an accepted gap mirroring
`Shared.Federation.Mastodon.MediaAttachment` only handling attachments with a real `url`.
-}
imagesDecoder : List String -> Decoder (List BlueskyImage)
imagesDecoder embedPath =
    Decode.oneOf
        [ Decode.at embedPath (Decode.list blueskyImageDecoder)

        -- An `app.bsky.embed.recordWithMedia#view` (a quote post with its own images attached)
        -- nests the images view under `media` instead.
        , Decode.at (List.take (List.length embedPath - 1) embedPath ++ [ "media", "images" ]) (Decode.list blueskyImageDecoder)
        , Decode.succeed []
        ]


blueskyImageDecoder : Decoder BlueskyImage
blueskyImageDecoder =
    Decode.map4 BlueskyImage
        (Decode.field "fullsize" Decode.string)
        (Decode.field "alt" Decode.string |> Decode.map nonEmpty)
        (Decode.maybe (Decode.at [ "aspectRatio", "width" ] Decode.int))
        (Decode.maybe (Decode.at [ "aspectRatio", "height" ] Decode.int))


{-| `labelsPath` (`[ "post", "labels" ]` for `decoder`'s nested shape, `[ "labels" ]` for
`searchDecoder`'s flatter one -- same path-depth split `imagesDecoder` already has) is "sensitive"
whenever it exists and isn't empty -- absent entirely (most posts), `null`, or `[]` all read as
`False` via the same `Decode.oneOf` catch-all `imagesDecoder` uses.
-}
sensitiveDecoder : List String -> Decoder Bool
sensitiveDecoder labelsPath =
    Decode.oneOf
        [ Decode.at labelsPath (Decode.list Decode.value) |> Decode.map (not << List.isEmpty)
        , Decode.succeed False
        ]


{-| `likeCount`/`replyCount`'s own path-parameterized reader (`countPath` is `[ "post", "likeCount" ]`
for `decoder`'s nested shape, `[ "likeCount" ]` for `searchDecoder`'s flatter one, same split
`imagesDecoder`/`sensitiveDecoder` already have) -- defaults to `0` rather than failing the decode if
somehow absent, same defensive convention `actorProfileDecoder`'s own counts use below.
-}
countDecoder : List String -> Decoder Int
countDecoder countPath =
    Decode.oneOf [ Decode.at countPath Decode.int, Decode.succeed 0 ]


{-| A post's `quote`, from two sources. `recordPath` is the post's own raw record (`[ "record" ]` for a
`postView`, `[ "value" ]` for a `viewRecord`), whose `embed` always names what's quoted by `uri` even
when the AppView didn't hydrate it; `inline` is that hydrated `viewRecord`, if present. No quote at all
(or a deleted/blocked/detached one, which has a `uri` but no hydrated `viewRecord` and so reads as a
dangling `uri` that `fetchPostWithQuotes` then fails to resolve) is `Nothing` only when neither exists.
-}
quoteDecoder : List String -> Decoder (Maybe FeedPost) -> Decoder (Maybe Quote)
quoteDecoder recordPath inline =
    Decode.map2
        (\rawUri hydrated ->
            case hydrated of
                Just post ->
                    Just (Quote { uri = post.uri, post = Just post })

                Nothing ->
                    Maybe.map (\uri -> Quote { uri = uri, post = Nothing }) rawUri
        )
        (Decode.maybe
            (Decode.oneOf
                [ Decode.at (recordPath ++ [ "embed", "record", "uri" ]) Decode.string
                , Decode.at (recordPath ++ [ "embed", "record", "record", "uri" ]) Decode.string
                ]
            )
        )
        inline


{-| An `app.bsky.embed.record#view` (`record` is the `viewRecord`) or `recordWithMedia#view` (`record`
is a wrapper whose own `record` is) -- decodes the hydrated quoted post, failing for
`viewNotFound`/`viewBlocked`/`viewDetached` (no `value`).
-}
embedViewQuoteDecoder : Decoder FeedPost
embedViewQuoteDecoder =
    Decode.oneOf
        [ Decode.field "record" (Decode.lazy (\_ -> viewRecordDecoder))
        , Decode.at [ "record", "record" ] (Decode.lazy (\_ -> viewRecordDecoder))
        ]


{-| `app.bsky.embed.record#viewRecord` -- a quoted post, a subtly different shape from `postView`:
the raw record is `value` (not `record`), and embeds are an `embeds` array (not a single `embed`).
-}
viewRecordDecoder : Decoder FeedPost
viewRecordDecoder =
    Decode.map8
        (\uri text createdAt isReply authorHandle authorDisplayName authorAvatarUrl images ->
            \sensitive likeCount replyCount quote ->
                { uri = uri
                , text = text
                , createdAt = createdAt
                , isReply = isReply
                , authorHandle = authorHandle
                , authorDisplayName = authorDisplayName
                , authorAvatarUrl = authorAvatarUrl
                , images = images
                , sensitive = sensitive
                , likeCount = likeCount
                , replyCount = replyCount
                , quote = quote
                }
        )
        (Decode.field "uri" Decode.string)
        (Decode.at [ "value", "text" ] Decode.string)
        (Decode.at [ "value", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.at [ "value", "reply" ] Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "author", "avatar" ] Decode.string))
        (Decode.oneOf
            [ Decode.field "embeds" (Decode.list (imagesDecoder [ "images" ])) |> Decode.map List.concat
            , Decode.succeed []
            ]
        )
        |> Decode.andThen (\f -> Decode.map f (sensitiveDecoder [ "labels" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "likeCount" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "replyCount" ]))
        |> Decode.andThen
            (\f ->
                Decode.map f
                    (quoteDecoder [ "value" ]
                        (Decode.oneOf
                            [ Decode.field "embeds" (Decode.list (Decode.maybe embedViewQuoteDecoder))
                                |> Decode.map (List.filterMap identity >> List.head)
                            , Decode.succeed Nothing
                            ]
                        )
                    )
            )


{-| A `FeedPost`'s translation into a Rellm `Post` -- `id` is just the bare `feedPost.uri` (an
`at://` URI, already globally unique on its own -- it embeds the author's DID), _not_ further
prefixed with `"bluesky:"` the way it briefly was, mirroring `Shared.Federation.Mastodon.toPost`'s
own bare `status.id` -- see that function's own doc on why (a federated post's `id` is never used
without its synthetic host alongside it, which already carries the `"bluesky:"` tag). `link` is a
real `https://bsky.app/...` URL (see `webUrl`) built from the `at://` URI, since that's meaningless
to a browser directly. `visibility` is always `GLOBALPUBLIC`: everything in a Bluesky timeline is
already public (AT Protocol has no private-post concept at all). `author.avatar` uses
`MediaReference.url`, same reasoning as Mastodon's own translation. `media` uses the same `.url`
approach, via `toMediaReference` -- see `toPostWith`'s own doc for why it's sometimes left empty
regardless of `feedPost.images`.
-}
toPost : FeedPost -> Post
toPost =
    toPostWith { includeSensitiveMedia = False, quoteDepth = 1 }


{-| `fetchPost`'s own translation, unlike `toPost` -- see that function's own doc on why a single
post's own page, unlike a feed/card, is allowed to actually show media AT Proto flagged `sensitive`.
-}
toPostIncludingSensitiveMedia : FeedPost -> Post
toPostIncludingSensitiveMedia =
    toPostWith { includeSensitiveMedia = True, quoteDepth = 1 }


{-| `toPost`'s real implementation -- mirrors `Shared.Federation.Mastodon.toPostWith`'s own doc
exactly, including the `sensitiveMediaHiddenPlaceholder` sentinel: `media` is left `[]` for a
`feedPost.sensitive` post unless `includeSensitiveMedia` says otherwise, rather than rendering it
blurred/behind a reveal button -- Rellm has no NSFW-filtering concept of its own for a `sensitive`
flag to hook into, so a flagged post's images either never reach `Post.media` at all (every feed/card
context -- `toPost`, used by `fetchPosts`/`searchPosts`/`fetchAuthorFeed`) or the viewer already
explicitly opened this exact post (`includeSensitiveMedia`, `Components.Bluesky.BlueskyPostPage`'s own
`init`, via `fetchPost`). When media actually was stripped this way, `media` becomes
`[ sensitiveMediaHiddenPlaceholder ]` rather than plain `[]`, so `Components.Posts.hasHiddenSensitiveMedia`
can tell "hidden sensitive media" apart from "no media at all" -- see `sensitiveMediaHiddenId`'s own
doc.

`quoteDepth` is how many levels of `feedPost.quote` to carry into `Post.quotedPost` (a card is 1, a post's
own page `maxPageQuoteDepth`, see `fetchPostWithQuotes`) -- each quoted post is itself translated as
`includeSensitiveMedia = False`, since it's only ever shown as an embedded card whose own link leads to
a page where that media can actually be revealed.
-}
toPostWith : { includeSensitiveMedia : Bool, quoteDepth : Int } -> FeedPost -> Post
toPostWith { includeSensitiveMedia, quoteDepth } feedPost =
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
        , media =
            if feedPost.sensitive && not includeSensitiveMedia then
                if List.isEmpty feedPost.images then
                    []

                else
                    [ sensitiveMediaHiddenPlaceholder ]

            else
                List.map toMediaReference feedPost.images
        , createdAt = Just (posixToTimestamp feedPost.createdAt)
        , lastActivityAt = Just (posixToTimestamp feedPost.createdAt)
        , unauthenticatedStarCount = int64FromInt feedPost.likeCount

        -- No separate "direct replies" vs. "whole nested thread" distinction AT Proto's own
        -- `replyCount` could split across (unlike a real Rellm post's `replyCount`/
        -- `responseCount`) -- setting both the same makes `Components.Posts.commentCountText`
        -- show it as a single number rather than a misleading "x/x".
        , replyCount = feedPost.replyCount
        , responseCount = feedPost.replyCount
        , quotedPost =
            case feedPost.quote of
                Just (Quote quote) ->
                    if quoteDepth > 0 then
                        Maybe.map (toPostWith { includeSensitiveMedia = False, quoteDepth = quoteDepth - 1 } >> wrapPost) quote.post

                    else
                        Nothing

                Nothing ->
                    Nothing
    }


sensitiveMediaHiddenPlaceholder : MediaReference
sensitiveMediaHiddenPlaceholder =
    { defaultMediaReference | id = sensitiveMediaHiddenId }


{-| A `BlueskyImage`'s translation into a `MediaReference` -- see
`Shared.Federation.Mastodon.toMediaReference`'s own doc, same reasoning throughout (`url`/`name`
carry the real content, `sizes` is a single synthetic `MEDIACONVERSIONORIGINAL` entry just so
`MediaRenderer.contentTypeOf`/`aspectRatioOf` have something to read). `contentType` is a bare
`"image/*"`, not coarsened from anything AT Proto provides -- `app.bsky.embed.images#view` (the only
embed shape `imagesDecoder` reads) is images-only by construction, unlike Mastodon's single
mixed-type `media_attachments` array. `id` borrows `image.url` itself (AT Proto's `#viewImage` has no
id field of its own, unlike Mastodon's real per-attachment id) -- still a genuinely distinct value
per image within one post's own `images` list, which is all `Shared.MediaViewerPanel`'s
open-by-id/page-by-id/`Html.Keyed` logic actually needs (see `Mastodon.toMediaReference`'s own doc on
why that has to be non-blank at all).
-}
toMediaReference : BlueskyImage -> MediaReference
toMediaReference image =
    { defaultMediaReference
        | id = image.url
        , url = Just image.url
        , name = image.alt
        , sizes =
            [ { defaultMediaSize
                | conversion = MEDIACONVERSIONORIGINAL
                , contentType = "image/*"
                , aspectRatio = Maybe.map2 (\w h -> toFloat w / toFloat h) image.width image.height
              }
            ]
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
    Decode.map8
        (\uri text createdAt isReply authorHandle authorDisplayName authorAvatarUrl images ->
            \sensitive likeCount replyCount quote ->
                { uri = uri
                , text = text
                , createdAt = createdAt
                , isReply = isReply
                , authorHandle = authorHandle
                , authorDisplayName = authorDisplayName
                , authorAvatarUrl = authorAvatarUrl
                , images = images
                , sensitive = sensitive
                , likeCount = likeCount
                , replyCount = replyCount
                , quote = quote
                }
        )
        (Decode.field "uri" Decode.string)
        (Decode.at [ "record", "text" ] Decode.string)
        (Decode.at [ "record", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.at [ "record", "reply" ] Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "author", "avatar" ] Decode.string))
        (imagesDecoder [ "embed", "images" ])
        |> Decode.andThen (\f -> Decode.map f (sensitiveDecoder [ "labels" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "likeCount" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "replyCount" ]))
        |> Decode.andThen (\f -> Decode.map f (quoteDecoder [ "record" ] (Decode.maybe (Decode.field "embed" embedViewQuoteDecoder))))


{-| For `fetchPost`/`fetchThread` only (public, read-only data): an empty `accessToken` means "no
connected account" and reads anonymously from Bluesky's public AppView (`public.api.bsky.app`, which
unlike the `bsky.social` PDS entryway every other call here uses serves public posts/threads with no
auth at all); anything else is the usual authenticated `bsky.social` read.
-}
readHost : String -> String
readHost accessToken =
    if accessToken == "" then
        "https://public.api.bsky.app"

    else
        "https://bsky.social"


readHeaders : String -> List Http.Header
readHeaders accessToken =
    if accessToken == "" then
        []

    else
        [ Http.header "Authorization" ("Bearer " ++ accessToken) ]


{-| `GET /xrpc/app.bsky.feed.getPosts` for a single `uri` -- a real single-post lookup by AT URI,
authenticated the same way `searchPosts` is (any connected account's token works; this reads public
data regardless of whose token it is). A batch API in general (`uris` takes a comma-separated list),
but always called here with exactly one, so `Decode.field "posts"` is expected to come back with
either one element or none (deleted/never-existed) -- the latter fails the whole decode, surfacing as
an `Http.Error` the same as any other not-found. Response items are the same bare
`app.bsky.feed.defs#postView` shape `searchPosts` gets, so this reuses `searchDecoder` too. Uses
`toPostIncludingSensitiveMedia`, unlike every other fetch here -- see that function's own doc on why
this, alone, doesn't strip a `sensitive` post's media. The `Bool` alongside `Post` is
`feedPost.sensitive` itself -- see `Shared.Federation.Mastodon.fetchStatus`'s own doc on why that's
still needed even though `toPostIncludingSensitiveMedia` already includes the media unconditionally
(`Components.Bluesky.BlueskyPostPage`'s own `sensitiveMediaRevealed`).
-}
fetchPost : String -> String -> Task Http.Error ( Post, Bool )
fetchPost accessToken uri =
    fetchFeedPost accessToken uri
        |> Task.map (\feedPost -> ( toPostIncludingSensitiveMedia feedPost, feedPost.sensitive ))


{-| `fetchPost`, but also resolving the post's chain of quotes (a post quoting a post quoting a post
...) up to `maxPageQuoteDepth` deep into `Post.quotedPost`, for a post's own page. AT Proto's own
hydration inlines only the first quoted post (and not even its own quote, see `viewRecordDecoder`), so
each further level is a separate `getPosts` -- sequential, since each needs the previous one's quote
`uri`. A quote that can't be fetched (deleted, blocked, a network error) just ends the chain there
rather than failing the whole post.
-}
fetchPostWithQuotes : String -> String -> Task Http.Error ( Post, Bool )
fetchPostWithQuotes accessToken uri =
    fetchFeedPost accessToken uri
        |> Task.andThen (expandQuotes accessToken maxPageQuoteDepth)
        |> Task.map
            (\feedPost ->
                ( toPostWith { includeSensitiveMedia = True, quoteDepth = maxPageQuoteDepth } feedPost
                , feedPost.sensitive
                )
            )


expandQuotes : String -> Int -> FeedPost -> Task Http.Error FeedPost
expandQuotes accessToken depth feedPost =
    case feedPost.quote of
        Just (Quote quote) ->
            if depth <= 0 then
                Task.succeed feedPost

            else
                (case quote.post of
                    Just hydrated ->
                        Task.succeed (Just hydrated)

                    Nothing ->
                        fetchFeedPost accessToken quote.uri
                            |> Task.map Just
                            |> Task.onError (\_ -> Task.succeed Nothing)
                )
                    |> Task.andThen
                        (\maybeQuoted ->
                            case maybeQuoted of
                                Just quoted ->
                                    expandQuotes accessToken (depth - 1) quoted
                                        |> Task.map (\expanded -> { feedPost | quote = Just (Quote { quote | post = Just expanded }) })

                                Nothing ->
                                    Task.succeed feedPost
                        )

        Nothing ->
            Task.succeed feedPost


fetchFeedPost : String -> String -> Task Http.Error FeedPost
fetchFeedPost accessToken uri =
    Http.task
        { method = "GET"
        , headers = readHeaders accessToken
        , url = readHost accessToken ++ "/xrpc/app.bsky.feed.getPosts?uris=" ++ Url.percentEncode uri
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


{-| One node of `app.bsky.feed.getPostThread`'s nested `thread` -- a post and its (recursively
nested) replies. Replies that are `#notFoundPost`/`#blockedPost` (no `post` field) are dropped
by `threadNodeDecoder`.
-}
type ThreadNode
    = ThreadNode FeedPost (List ThreadNode)


threadNodeDecoder : Decoder ThreadNode
threadNodeDecoder =
    Decode.map2 ThreadNode
        (Decode.field "post" searchDecoder)
        (Decode.oneOf
            [ Decode.field "replies"
                (Decode.list (Decode.oneOf [ Decode.lazy (\_ -> threadNodeDecoder) |> Decode.map Just, Decode.succeed Nothing ])
                    |> Decode.map (List.filterMap identity)
                )
            , Decode.succeed []
            ]
        )


{-| The chain of `parent`s above a thread node (each itself a node with its own `parent`), oldest
first -- `[]` once there's no further (visible) `parent`.
-}
parentChainDecoder : Decoder (List FeedPost)
parentChainDecoder =
    Decode.oneOf
        [ Decode.field "parent"
            (Decode.oneOf
                [ Decode.map2 (\post above -> above ++ [ post ])
                    (Decode.field "post" searchDecoder)
                    (Decode.lazy (\_ -> parentChainDecoder))
                , Decode.succeed []
                ]
            )
        , Decode.succeed []
        ]


threadNodeToPost : ThreadNode -> Post
threadNodeToPost (ThreadNode feedPost children) =
    let
        post : Post
        post =
            toPost feedPost
    in
    { post | replies = List.map (threadNodeToPost >> wrapPost) children }


{-| `GET /xrpc/app.bsky.feed.getPostThread` for `uri` -- AT Proto already nests replies, so unlike
`Shared.Federation.Mastodon.fetchThread` there's no tree-building here, just translation. Same auth
as every other fetch in this module. `depth=10` replies deep, `parentHeight=20` ancestors up.
-}
fetchThread : String -> String -> Task Http.Error Thread
fetchThread accessToken uri =
    Http.task
        { method = "GET"
        , headers = readHeaders accessToken
        , url = readHost accessToken ++ "/xrpc/app.bsky.feed.getPostThread?depth=10&parentHeight=20&uri=" ++ Url.percentEncode uri
        , body = Http.emptyBody
        , resolver =
            jsonResolver
                (Decode.field "thread"
                    (Decode.map2 Tuple.pair
                        parentChainDecoder
                        (Decode.oneOf
                            [ Decode.field "replies"
                                (Decode.list (Decode.oneOf [ threadNodeDecoder |> Decode.map Just, Decode.succeed Nothing ])
                                    |> Decode.map (List.filterMap identity)
                                )
                            , Decode.succeed []
                            ]
                        )
                    )
                )
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map
            (\( ancestors, replies ) ->
                { ancestors = List.map toPost ancestors
                , replies = List.map threadNodeToPost replies
                }
            )


{-| `app.bsky.feed.getActorLikes` for `actor` (the connected account's own handle -- AT Proto only
serves this for the authenticated account itself) -- its own server-side likes, newest first, as
`Post`s (see `Shared.StarredPanel`'s "Server" tab).
-}
fetchLikes : String -> String -> Task Http.Error (List Post)
fetchLikes accessToken actor =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.feed.getActorLikes?limit=50&actor=" ++ Url.percentEncode actor
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "feed" (Decode.list decoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


{-| A post's `cid` (needed to reference it in a like record) and, if the authenticated viewer has
already liked it, that like record's own `at://` URI (needed to delete it again) -- both from
`app.bsky.feed.getPosts`' `postView`.
-}
type alias PostRef =
    { cid : String
    , viewerLike : Maybe String
    }


fetchPostRef : String -> String -> Task Http.Error PostRef
fetchPostRef accessToken uri =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/app.bsky.feed.getPosts?uris=" ++ Url.percentEncode uri
        , body = Http.emptyBody
        , resolver =
            jsonResolver
                (Decode.field "posts"
                    (Decode.list
                        (Decode.map2 PostRef
                            (Decode.field "cid" Decode.string)
                            (Decode.maybe (Decode.at [ "viewer", "like" ] Decode.string))
                        )
                    )
                    |> Decode.andThen
                        (\refs ->
                            case refs of
                                first :: _ ->
                                    Decode.succeed first

                                [] ->
                                    Decode.fail "post not found"
                        )
                )
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| Likes (`like = True`) or un-likes the post at `uri` as `repo` (the connected account's own handle
-- `com.atproto.repo.*` accepts a handle or DID there). Likes create an `app.bsky.feed.like` record
via `com.atproto.repo.createRecord`; un-likes look up the existing like record's URI from the post's
own `viewer.like` and `deleteRecord` its `rkey`. Both are no-ops if the post is already in the
requested state. Needs an App Password with default (non-read-only) access, which is what Rellm's
connect form always asks for.
-}
setLike : Bool -> String -> String -> String -> Task Http.Error ()
setLike like repo accessToken uri =
    fetchPostRef accessToken uri
        |> Task.andThen
            (\ref ->
                case ( like, ref.viewerLike ) of
                    ( True, Nothing ) ->
                        Time.now
                            |> Task.andThen
                                (\now ->
                                    repoWrite accessToken
                                        "createRecord"
                                        (Encode.object
                                            [ ( "repo", Encode.string repo )
                                            , ( "collection", Encode.string "app.bsky.feed.like" )
                                            , ( "record"
                                              , Encode.object
                                                    [ ( "$type", Encode.string "app.bsky.feed.like" )
                                                    , ( "subject", Encode.object [ ( "uri", Encode.string uri ), ( "cid", Encode.string ref.cid ) ] )
                                                    , ( "createdAt", Encode.string (Iso8601.fromTime now) )
                                                    ]
                                              )
                                            ]
                                        )
                                )

                    ( False, Just likeUri ) ->
                        repoWrite accessToken
                            "deleteRecord"
                            (Encode.object
                                [ ( "repo", Encode.string repo )
                                , ( "collection", Encode.string "app.bsky.feed.like" )
                                , ( "rkey", Encode.string (likeUri |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault "") )
                                ]
                            )

                    _ ->
                        Task.succeed ()
            )


repoWrite : String -> String -> Encode.Value -> Task Http.Error ()
repoWrite accessToken method body =
    Http.task
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = "https://bsky.social/xrpc/com.atproto.repo." ++ method
        , body = Http.jsonBody body
        , resolver = jsonResolver (Decode.succeed ()) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| A Bluesky post's `at://{did}/app.bsky.feed.post/{rkey}` URI as the short form `Components.Posts.postHref`
puts in a `/post/:postId` route -- `{did}~{rkey}`. The `at://` scheme and the collection are the same for
every post, and `~` is a safe separator: a DID never contains one. (An rkey _may_, which is why
`fromRouteId` splits on the first.) Anything that isn't exactly that shape (another collection, a DID
with a `%`, which the route's percent-decoding would mangle) falls back to the whole URI,
percent-encoded, which `fromRouteId` also accepts.
-}
routeId : String -> String
routeId uri =
    case String.split "/" uri of
        [ "at:", "", did, "app.bsky.feed.post", rkey ] ->
            if String.startsWith "did:" did && not (String.contains "%" did) && not (String.contains "%" rkey) && not (String.isEmpty rkey) then
                did ++ "~" ++ rkey

            else
                Url.percentEncode uri

        _ ->
            Url.percentEncode uri


{-| `routeId`'s inverse, applied to the already percent-decoded id -- a full `at://` URI (the older, long
route form) passes through unchanged.
-}
fromRouteId : String -> String
fromRouteId id =
    case String.indexes "~" id |> List.head of
        Just separator ->
            let
                did : String
                did =
                    String.left separator id
            in
            if String.startsWith "did:" did then
                "at://" ++ did ++ "/app.bsky.feed.post/" ++ String.dropLeft (separator + 1) id

            else
                id

        Nothing ->
            id


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
