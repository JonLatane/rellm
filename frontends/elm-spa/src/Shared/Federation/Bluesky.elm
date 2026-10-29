module Shared.Federation.Bluesky exposing
    ( ActorProfile
    , BlueskyImage
    , BlueskyVideo
    , FeedPost
    , createPost
    , createReply
    , decoder
    , deletePost
    , editPost
    , richText
    , fetchActorProfile
    , graphemeCount
    , fetchAuthorFeed
    , fetchFollowers
    , fetchFollows
    , fetchLikes
    , fetchEmbeddedPost
    , fetchPost
    , fetchPostWithQuotes
    , fetchPosts
    , fetchLatestPosts
    , fetchWhatsHot
    , fetchThread
    , fromRouteId
    , resolveHandle
    , searchActors
    , routeId
    , searchPosts
    , SearchSort(..)
    , setLike
    , toPost
    , toPostIncludingSensitiveMedia
    )

{-| Translates Bluesky's (AT Protocol) API into Rellm's `Post` shape, entirely client-side -- see
`Shared.AccountsPanel.BlueskyAccounts`' own doc for the connection side this feeds off of. AT Protocol
splits "a server" into a PDS (hosts an account, handles its login) and an AppView (serves the read side
for the whole network), so there are two ways to read, both expressed as a `BlueskyAuth`: as a connected
_account_ (its own PDS host + token -- the PDS proxies reads to an AppView, and adds personalization),
or _anonymously_ straight from an AppView (`public.api.bsky.app` by default), which serves public data
with no login. What only an account gets: `fetchPosts` (its personalized home timeline), and anything that writes (`setLike`) or reads the account's own state
(`fetchLikes`). What anyone gets: `fetchLatestPosts` (the newest posts on the network, the closest thing to a
"public timeline"), `searchPosts` (via `anonymousSearchHost`), `fetchPost`/`fetchThread`, and every `ActorProfile`/`fetchAuthorFeed`-style actor read.
See `Components.Pages.PostsPage.fetchFeedSource`'s `BlueskyFeed`/`BlueskyAppViewFeed` cases and
`Components.Pages.PostPage.init` (`fetchPost`, when a route's post id parses as
`Components.Posts.BlueskyPostId`) for how each gets wired into a real page.

`ActorProfile`/`fetchActorProfile`/`fetchAuthorFeed`/`fetchFollowers`/`fetchFollows` back
`Components.Bluesky.BlueskyUserProfilePage`/`BlueskyUsersPage` -- resolving one specific actor's own
profile/authored-posts/followers/follows, rather than the connected account's own home timeline.
Every one of these takes a `BlueskyAuth`: a connected account's (PDS host + token), or an anonymous one
(`Shared.Federation.Common.anonymousBlueskyAuth`/`blueskyAuthFor`, reading straight from an AppView, which
serves all of this public data with no login). They work against _any_ handle, not just the connected
account's own.

-}

import Dict
import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Proto.Rellm exposing (Author, MediaReference, Post, defaultAuthor, defaultMediaReference, defaultMediaSize, defaultPost, wrapMediaReference, wrapPost)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Shared.Conversions exposing (int64FromInt, posixToTimestamp)
import Shared.Federation.Common exposing (BlueskyAuth, Thread, anonymousBlueskyAuth, jsonResolver, nonEmpty, sensitiveMediaHiddenId)
import SocialMediaEmbed
import Task exposing (Task)
import Time
import Url


{-| One element of an `app.bsky.embed.images#view`'s `images` array (with
`BlueskyVideo`, one of the two `embed` shapes `toPost` translates -- see `imagesDecoder`'s own doc for
`app.bsky.embed.external#view`, the one it doesn't). `fullsize` (not `thumb`, a low-res placeholder)
is this image's real URL -- same "skip the two-tier fetch" reasoning as
`Shared.Federation.Mastodon.MediaAttachment.url`'s own doc.
-}
type alias BlueskyImage =
    { url : String
    , alt : Maybe String
    , width : Maybe Int
    , height : Maybe Int
    }


{-| An `app.bsky.embed.video#view` -- a single video, which AT Proto serves as an HLS stream rather
than a file: `playlist` is its `.m3u8` manifest (`https://video.bsky.app/watch/{did}/{cid}/playlist.m3u8`),
which `toMediaReference` hands to `Components.MediaRenderer` like any other video URL (it
attaches hls.js on browsers with no native HLS, see `public/index.html`). `thumbnail` is the poster frame.
-}
type alias BlueskyVideo =
    { playlist : String
    , thumbnail : Maybe String
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
    , video : Maybe BlueskyVideo
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
            \video sensitive likeCount replyCount quote ->
                { uri = uri
                , text = text
                , createdAt = createdAt
                , isReply = isReply
                , authorHandle = authorHandle
                , authorDisplayName = authorDisplayName
                , authorAvatarUrl = authorAvatarUrl
                , images = images
                , video = video
                , sensitive = sensitive
                , likeCount = likeCount
                , replyCount = replyCount
                , quote = quote
                }
        )
        (Decode.at [ "post", "uri" ] Decode.string)
        (textDecoder [ "post", "record" ])
        (Decode.at [ "post", "record", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.field "reply" Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "post", "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "post", "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "post", "author", "avatar" ] Decode.string))
        (imagesDecoder [ "post", "embed", "images" ])
        |> Decode.andThen (\f -> Decode.map f (videoDecoder [ "post", "embed" ]))
        |> Decode.andThen (\f -> Decode.map f (sensitiveDecoder [ "post", "labels" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "post", "likeCount" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "post", "replyCount" ]))
        |> Decode.andThen (\f -> Decode.map f (quoteDecoder [ "post", "record" ] (Decode.maybe (Decode.at [ "post", "embed" ] embedViewQuoteDecoder))))


{-| A post record's `text` with its `facets` (`recordPath` is the record, as for `quoteDecoder`) turned
into Markdown, which is how `Post.content` is rendered. AT Proto keeps rich text out of the string itself:
a facet marks a UTF-8 byte range of `text` as a `#link` (the full `uri` -- the visible text is
often a truncated `youtube.com/watch?v=abc...`), or a `#tag`. Without this, hashtags are
plain text and a shortened link points nowhere (or at a prefix of the real URL). Tags link to
`bsky.app/hashtag/...` (the AppView's own hashtag page). `#mention` facets are deliberately ignored: `@handle` text
is linked to Rellm's own profile page by `markdown.js`.
Facets that are out of range, overlap an earlier one or have no known feature are skipped; a record
with no `facets` is just its `text`. A link card (`appendCard`) whose URL the text doesn't link is appended.
-}
textDecoder : List String -> Decoder String
textDecoder recordPath =
    Decode.map3 (\text facets card -> applyFacets text facets |> appendCard card)
        (Decode.at (recordPath ++ [ "text" ]) Decode.string)
        (Decode.oneOf
            [ Decode.at (recordPath ++ [ "facets" ]) (Decode.list (Decode.maybe facetDecoder))
                |> Decode.map (List.filterMap identity)
            , Decode.succeed []
            ]
        )
        (Decode.maybe
            (Decode.oneOf
                [ Decode.at (recordPath ++ [ "embed", "external" ]) cardDecoder

                -- `app.bsky.embed.recordWithMedia`: the card is the `media`.
                , Decode.at (recordPath ++ [ "embed", "media", "external" ]) cardDecoder
                ]
            )
        )


{-| An `app.bsky.embed.external`'s link card: `uri`, and `title` (may be empty). -}
type alias Card =
    { uri : String
    , title : String
    }


cardDecoder : Decoder Card
cardDecoder =
    Decode.map2 Card
        (Decode.field "uri" Decode.string)
        (Decode.oneOf [ Decode.field "title" Decode.string, Decode.succeed "" ])


{-| The post's link card as a Markdown link on its own line after `text`, unless `text` already links
that URL (Bluesky's composer adds a link facet for it, so that's the usual case). Some clients and
crossposters attach a card without putting the link in the text; this keeps those posts' link visible,
and findable by `Components.Bluesky.BlueskyPostPage.socialEmbedView`.
-}
appendCard : Maybe Card -> String -> String
appendCard maybeCard text =
    case maybeCard of
        Just card ->
            if
                (String.startsWith "https://" card.uri || String.startsWith "http://" card.uri)
                    && not (String.contains ("](" ++ escapeHref card.uri ++ ")") text)
            then
                let
                    link : String
                    link =
                        markdownLink
                            (if String.isEmpty (String.trim card.title) then
                                card.uri

                             else
                                card.title
                            )
                            card.uri
                in
                if String.isEmpty (String.trim text) then
                    link

                else
                    String.trimRight text ++ "\n\n" ++ link

            else
                text

        Nothing ->
            text


type alias Facet =
    { byteStart : Int
    , byteEnd : Int
    , href : String
    }


facetDecoder : Decoder Facet
facetDecoder =
    Decode.map3 Facet
        (Decode.at [ "index", "byteStart" ] Decode.int)
        (Decode.at [ "index", "byteEnd" ] Decode.int)
        (Decode.field "features" (Decode.list (Decode.maybe featureHrefDecoder))
            |> Decode.andThen
                (\features ->
                    case List.filterMap identity features of
                        href :: _ ->
                            Decode.succeed href

                        [] ->
                            Decode.fail "no supported facet feature"
                )
        )


featureHrefDecoder : Decoder String
featureHrefDecoder =
    Decode.field "$type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "app.bsky.richtext.facet#link" ->
                        Decode.field "uri" Decode.string

                    "app.bsky.richtext.facet#tag" ->
                        Decode.field "tag" Decode.string
                            |> Decode.map (\tag -> "https://bsky.app/hashtag/" ++ Url.percentEncode tag)

                    -- No `#mention` case on purpose: its text is the plain `@handle`, which `markdown.js`
                    -- turns into a link to Rellm's own profile page (`/handle@bluesky`); a facet link
                    -- would send it to bsky.app instead.
                    _ ->
                        Decode.fail "unsupported facet feature"
            )


{-| `text` with each facet's byte range replaced by `[range](href)`. Walks code points (Elm's
`String.toList`), counting each one's UTF-8 length to stay aligned with the facets' byte offsets.
-}
applyFacets : String -> List Facet -> String
applyFacets text facets =
    if List.isEmpty facets then
        text

    else
        applyFacetsHelp (List.sortBy .byteStart facets) 0 (String.toList text) [] ""


applyFacetsHelp : List Facet -> Int -> List Char -> List Char -> String -> String
applyFacetsHelp facets offset chars labelChars out =
    case chars of
        [] ->
            -- A facet that ran past the end of `text` is dropped; flush what it had collected as plain text.
            out ++ String.fromList (List.reverse labelChars)

        char :: rest ->
            case facets of
                facet :: laterFacets ->
                    if offset >= facet.byteStart && offset < facet.byteEnd then
                        let
                            nextOffset : Int
                            nextOffset =
                                offset + utf8Length char

                            collected : List Char
                            collected =
                                char :: labelChars
                        in
                        if nextOffset >= facet.byteEnd then
                            -- Drop facets that start inside this one, so a partial overlap can't attach its URL to other text.
                            applyFacetsHelp
                                (List.filter (\later -> later.byteStart >= nextOffset) laterFacets)
                                nextOffset
                                rest
                                []
                                (withLinkAfter out (markdownLink (String.fromList (List.reverse collected)) facet.href))

                        else
                            applyFacetsHelp facets nextOffset rest collected out

                    else if offset >= facet.byteEnd || facet.byteEnd <= facet.byteStart then
                        -- Overlaps the previous facet or is empty: skip it.
                        applyFacetsHelp laterFacets offset chars labelChars out

                    else
                        applyFacetsHelp facets (offset + utf8Length char) rest labelChars (out ++ String.fromChar char)

                [] ->
                    applyFacetsHelp [] (offset + utf8Length char) rest labelChars (out ++ String.fromChar char)


{-| `out ++ link`, escaping a trailing `!` of `out` so Markdown doesn't read `![label](href)` as an image. -}
withLinkAfter : String -> String -> String
withLinkAfter out link =
    if String.endsWith "!" out then
        String.dropRight 1 out ++ "\\!" ++ link

    else
        out ++ link


utf8Length : Char -> Int
utf8Length char =
    let
        code : Int
        code =
            Char.toCode char
    in
    if code < 0x80 then
        1

    else if code < 0x0800 then
        2

    else if code < 0x00010000 then
        3

    else
        4


markdownLink : String -> String -> String
markdownLink label href =
    "["
        ++ (label |> String.replace "[" "\\[" |> String.replace "]" "\\]")
        ++ "]("
        ++ escapeHref href
        ++ ")"


escapeHref : String -> String
escapeHref href =
    href |> String.replace " " "%20" |> String.replace "(" "%28" |> String.replace ")" "%29"


{-| `embedPath ++ [ "images" ]` (e.g. `[ "post", "embed", "images" ]` for `decoder`'s nested
`feedViewPost` shape, `[ "embed", "images" ]` for `searchDecoder`'s flatter one) if that path exists
and is actually an `app.bsky.embed.images#view` (i.e. carries an `images` array at all) --
`Decode.oneOf`'s fallback to `[]` covers every other case in one go: no `embed` at all (a plain text
post), or an `embed` that's really an `app.bsky.embed.video#view` (a single video, not `images` --
see `videoDecoder`) or `app.bsky.embed.external#view` (a link-card thumbnail, keyed `thumb`, not real
post media -- rendering a target site's own preview image as if the author had attached it would be
misleading) -- not translated here, the latter an accepted gap mirroring
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


{-| The `app.bsky.embed.video#view` at `embedPath` (`[ "post", "embed" ]`, `[ "embed" ]`; `[]` for an
element of a `viewRecord`'s `embeds` array), or nested under `media` for a `recordWithMedia#view` (a
quote post with its own video). `Nothing` for every other embed shape (including images), since the
`playlist` field only exists on a video view.
-}
videoDecoder : List String -> Decoder (Maybe BlueskyVideo)
videoDecoder embedPath =
    Decode.oneOf
        [ Decode.at embedPath blueskyVideoDecoder |> Decode.map Just
        , Decode.at (embedPath ++ [ "media" ]) blueskyVideoDecoder |> Decode.map Just
        , Decode.succeed Nothing
        ]


blueskyVideoDecoder : Decoder BlueskyVideo
blueskyVideoDecoder =
    Decode.map5 BlueskyVideo
        (Decode.field "playlist" Decode.string)
        (Decode.maybe (Decode.field "thumbnail" Decode.string))
        (Decode.maybe (Decode.field "alt" Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "aspectRatio", "width" ] Decode.int))
        (Decode.maybe (Decode.at [ "aspectRatio", "height" ] Decode.int))


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
            \video sensitive likeCount replyCount quote ->
                { uri = uri
                , text = text
                , createdAt = createdAt
                , isReply = isReply
                , authorHandle = authorHandle
                , authorDisplayName = authorDisplayName
                , authorAvatarUrl = authorAvatarUrl
                , images = images
                , video = video
                , sensitive = sensitive
                , likeCount = likeCount
                , replyCount = replyCount
                , quote = quote
                }
        )
        (Decode.field "uri" Decode.string)
        (textDecoder [ "value" ])
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
        |> Decode.andThen
            (\f ->
                Decode.map f
                    (Decode.oneOf
                        [ Decode.field "embeds" (Decode.list (videoDecoder []))
                            |> Decode.map (List.filterMap identity >> List.head)
                        , Decode.succeed Nothing
                        ]
                    )
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
                -- A sensitive post that only has a social embed (a video link) is hidden just like one with images.
                if List.isEmpty feedPost.images && feedPost.video == Nothing && List.isEmpty (SocialMediaEmbed.fromMarkdown feedPost.text) then
                    []

                else
                    [ sensitiveMediaHiddenPlaceholder ]

            else
                List.map toMediaReference feedPost.images
                    ++ (feedPost.video |> Maybe.map (toVideoMediaReference >> List.singleton) |> Maybe.withDefault [])
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


{-| A `BlueskyVideo`'s translation into a `MediaReference`, mirroring `toMediaReference`: `url` is the
HLS playlist, which `Components.MediaRenderer` plays in a plain `<video>` (see `BlueskyVideo`). The
`video/*` content type is what routes it down `MediaRenderer`'s video branch.
-}
toVideoMediaReference : BlueskyVideo -> MediaReference
toVideoMediaReference video =
    { defaultMediaReference
        | id = video.playlist
        , url = Just video.playlist
        , name = video.alt
        , sizes =
            [ { defaultMediaSize
                | conversion = MEDIACONVERSIONORIGINAL
                , contentType = "video/*"
                , aspectRatio = Maybe.map2 (\w h -> toFloat w / toFloat h) video.width video.height
              }
            ]
    }


{-| `GET /xrpc/app.bsky.feed.getTimeline` against the account's own PDS (see `BlueskyAuth`), authenticated
with its token, already translated via `toPost` -- the
connected account's own home timeline (reverse-chronological, following), the AT Protocol equivalent of
`FOLLOWING_POSTS` (`Components.Pages.PostsPage`'s "Following" sort). `before`, if given, keeps only posts older than it (`Components.Pages.PostsPage`'s
"Posts Before" tab) -- see the filtering note below.
-}
fetchPosts : Maybe Time.Posix -> BlueskyAuth -> Task Http.Error (List Post)
fetchPosts before auth =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url =
            readHost auth
                ++ "/xrpc/app.bsky.feed.getTimeline?algorithm=reverse-chronological&limit="
                ++ (if before == Nothing then
                        "20"

                    else
                        "100"
                   )
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "feed" (Decode.list decoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map
            (\feed ->
                case before of
                    Nothing ->
                        List.map toPost feed

                    Just cutoff ->
                        -- `getTimeline` has no "before" parameter, so ask for a bigger page and drop everything
                        -- posted after `cutoff`: a cutoff much further back than the page reaches (the last
                        -- 100 posts of the account's following) shows little or nothing.
                        feed
                            |> List.filter (\feedPost -> Time.posixToMillis feedPost.createdAt < Time.posixToMillis cutoff)
                            |> List.take 20
                            |> List.map toPost
            )


{-| The newest posts on the whole network -- what a browsed AppView (`BlueskyAppViewFeed`) or a connected
account (`BlueskyFeed`) shows for "Recent Posts" when there's no search text, so it reads newest-first
like a Mastodon instance's public timeline and a real server's `ALL_ACCESSIBLE_POSTS`, with a connected
account's home timeline (`fetchPosts`) left to "Following". AT Protocol has no anonymous global timeline, but
`searchPosts` with `sort=latest` and the match-everything query `*` is one: its results trail the live
firehose by seconds. With a `before` cutoff (the "Posts Before" tab) it searches the common word `a`
instead, with `until`, since `*` can't be combined with that. (The curated "What's Hot" feed generator this replaced was hours behind.) Anonymous callers
should send it to `Shared.Federation.Common.anonymousSearchHost`, since the public AppView's other host
403s search.
-}
fetchLatestPosts : Maybe Time.Posix -> BlueskyAuth -> Task Http.Error (List Post)
fetchLatestPosts before auth =
    case before of
        Nothing ->
            searchPosts SearchLatest Nothing auth "*"

        Just cutoff ->
            -- Bluesky rejects `q=*` together with `until` (HTTP 400), so a "before" listing needs a real
            -- term. `a` is a common word in several of the network's biggest languages (a sample of its
            -- results was about half English, with Spanish, French and Portuguese) -- an approximation
            -- of "every post", and the best anonymous one there is.
            searchPosts SearchLatest (Just cutoff) auth "a"


{-| `GET /xrpc/app.bsky.feed.getFeed` for Bluesky's "What's Hot" feed generator -- its own "what's popular
lately" ranking (an algorithmic feed, so hours behind the live firehose). Works anonymously against an
AppView or as a connected account (via its PDS); `Components.Pages.PostsPage`'s "Recently Popular Posts"
sort uses it in place of `fetchLatestPosts`/`fetchPosts`. Same `{ feed : [ { post, reply? } ] }` shape
as `getTimeline`, so it shares `decoder`.
-}
fetchWhatsHot : BlueskyAuth -> Task Http.Error (List Post)
fetchWhatsHot auth =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getFeed?limit=20&feed=" ++ Url.percentEncode whatsHotFeedUri
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "feed" (Decode.list decoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


{-| The AT URI of Bluesky's "What's Hot" feed generator.
-}
whatsHotFeedUri : String
whatsHotFeedUri =
    "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"


{-| How `searchPosts` orders its matches: Bluesky's own relevance/engagement ranking (`SearchTop`, what a
text search wants), or newest first (`SearchLatest`, what `fetchLatestPosts` wants).
-}
type SearchSort
    = SearchTop
    | SearchLatest


{-| `GET /xrpc/app.bsky.feed.searchPosts` -- Bluesky's real search endpoint, searching the whole
public network (not just the connected account's own timeline/follows) -- see
<https://docs.bsky.app/docs/api/app-bsky-feed-search-posts>. Works as a connected account (its PDS
proxies it) or anonymously -- but not against `public.api.bsky.app`, which 403s it; anonymous callers
use `Shared.Federation.Common.anonymousSearchHost`. See `Components.Pages.PostsPage.fetchFeedSource`'s
`BlueskyFeed`/`BlueskyAppViewFeed` cases, which switch to this instead of `fetchPosts`/`fetchLatestPosts`
whenever `model.searchText` isn't blank, mirroring how a real `GetPosts` request switches to
`TEXTSEARCH`. `until`, if given, keeps only posts before it (the "Posts Before" tab's cutoff). Unlike `getTimeline`'s `feed` array (each entry wrapping a `post` alongside separate
`reply` context), each entry here is a bare `app.bsky.feed.defs#postView` directly, so `searchDecoder`
reads its fields one level shallower than `decoder` does, and detects a reply via the post's own
`record.reply` field being present (the same information `getTimeline`'s sibling `reply` field
carries, just nested differently here) rather than a sibling key.
-}
searchPosts : SearchSort -> Maybe Time.Posix -> BlueskyAuth -> String -> Task Http.Error (List Post)
searchPosts sort until auth query =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.searchPosts?q=" ++ Url.percentEncode query
                ++ "&sort="
                ++ (case sort of
                        SearchTop ->
                            "top"

                        SearchLatest ->
                            "latest"
                   )
                ++ (until |> Maybe.map (\cutoff -> "&until=" ++ Url.percentEncode (Iso8601.fromTime cutoff)) |> Maybe.withDefault "")
                ++ "&limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "posts" (Decode.list searchDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


searchDecoder : Decoder FeedPost
searchDecoder =
    Decode.map8
        (\uri text createdAt isReply authorHandle authorDisplayName authorAvatarUrl images ->
            \video sensitive likeCount replyCount quote ->
                { uri = uri
                , text = text
                , createdAt = createdAt
                , isReply = isReply
                , authorHandle = authorHandle
                , authorDisplayName = authorDisplayName
                , authorAvatarUrl = authorAvatarUrl
                , images = images
                , video = video
                , sensitive = sensitive
                , likeCount = likeCount
                , replyCount = replyCount
                , quote = quote
                }
        )
        (Decode.field "uri" Decode.string)
        (textDecoder [ "record" ])
        (Decode.at [ "record", "createdAt" ] Iso8601.decoder)
        (Decode.maybe (Decode.at [ "record", "reply" ] Decode.value) |> Decode.map ((/=) Nothing))
        (Decode.at [ "author", "handle" ] Decode.string)
        (Decode.maybe (Decode.at [ "author", "displayName" ] Decode.string) |> Decode.map (Maybe.andThen nonEmpty))
        (Decode.maybe (Decode.at [ "author", "avatar" ] Decode.string))
        (imagesDecoder [ "embed", "images" ])
        |> Decode.andThen (\f -> Decode.map f (videoDecoder [ "embed" ]))
        |> Decode.andThen (\f -> Decode.map f (sensitiveDecoder [ "labels" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "likeCount" ]))
        |> Decode.andThen (\f -> Decode.map f (countDecoder [ "replyCount" ]))
        |> Decode.andThen (\f -> Decode.map f (quoteDecoder [ "record" ] (Decode.maybe (Decode.field "embed" embedViewQuoteDecoder))))


{-| The base URL every call in this module goes to -- `auth.host`, which is the connected account's own
PDS (that PDS logs the account in, and proxies `app.bsky.*` reads on to an AppView for it) or, for
anonymous browsing, an AppView directly (see `Shared.Federation.Common.BlueskyAuth`).
-}
readHost : BlueskyAuth -> String
readHost auth =
    "https://" ++ auth.host


{-| No `Authorization` header at all for an anonymous (`accessToken == ""`) read, which AppViews such as
`public.api.bsky.app` require (they reject a bogus bearer token rather than ignoring it).
-}
readHeaders : BlueskyAuth -> List Http.Header
readHeaders auth =
    if auth.accessToken == "" then
        []

    else
        [ Http.header "Authorization" ("Bearer " ++ auth.accessToken) ]


{-| `GET /xrpc/app.bsky.feed.getPosts` for a single `uri` -- a real single-post lookup by AT URI,
reads through whichever `BlueskyAuth` it's given (a connected account's, or anonymous from an AppView -- this reads public
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
fetchPost : BlueskyAuth -> String -> Task Http.Error ( Post, Bool )
fetchPost auth uri =
    fetchFeedPost auth uri
        |> Task.map (\feedPost -> ( toPostIncludingSensitiveMedia feedPost, feedPost.sensitive ))


{-| A post to embed as a quote card (`Components.QuotedLink`): read anonymously from the public AppView -- no
connected account needed, and no token rotation to race -- and translated like a feed card (`toPost`:
sensitive media stays hidden, the first quote carried along).
-}
fetchEmbeddedPost : String -> Task Http.Error Post
fetchEmbeddedPost uri =
    fetchFeedPost anonymousBlueskyAuth uri |> Task.map toPost


{-| `GET /xrpc/com.atproto.identity.resolveHandle` -- the DID behind a handle, for a link like
`bsky.app/profile/alice.bsky.social/post/…` (`getPosts` only takes DID-based `at://` URIs). Public, no auth.
-}
resolveHandle : String -> Task Http.Error String
resolveHandle handle =
    Http.task
        { method = "GET"
        , headers = []
        , url = "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=" ++ Url.percentEncode handle
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "did" Decode.string) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `fetchPost`, but also resolving the post's chain of quotes (a post quoting a post quoting a post
...) up to `maxPageQuoteDepth` deep into `Post.quotedPost`, for a post's own page. AT Proto's own
hydration inlines only the first quoted post (and not even its own quote, see `viewRecordDecoder`), so
each further level is a separate `getPosts` -- sequential, since each needs the previous one's quote
`uri`. A quote that can't be fetched (deleted, blocked, a network error) just ends the chain there
rather than failing the whole post.
-}
fetchPostWithQuotes : BlueskyAuth -> String -> Task Http.Error ( Post, Bool )
fetchPostWithQuotes auth uri =
    fetchFeedPost auth uri
        |> Task.andThen (expandQuotes auth maxPageQuoteDepth)
        |> Task.map
            (\feedPost ->
                ( toPostWith { includeSensitiveMedia = True, quoteDepth = maxPageQuoteDepth } feedPost
                , feedPost.sensitive
                )
            )


expandQuotes : BlueskyAuth -> Int -> FeedPost -> Task Http.Error FeedPost
expandQuotes auth depth feedPost =
    case feedPost.quote of
        Just (Quote quote) ->
            if depth <= 0 then
                Task.succeed feedPost

            else
                (case quote.post of
                    Just hydrated ->
                        Task.succeed (Just hydrated)

                    Nothing ->
                        fetchFeedPost auth quote.uri
                            |> Task.map Just
                            |> Task.onError (\_ -> Task.succeed Nothing)
                )
                    |> Task.andThen
                        (\maybeQuoted ->
                            case maybeQuoted of
                                Just quoted ->
                                    expandQuotes auth (depth - 1) quoted
                                        |> Task.map (\expanded -> { feedPost | quote = Just (Quote { quote | post = Just expanded }) })

                                Nothing ->
                                    Task.succeed feedPost
                        )

        Nothing ->
            Task.succeed feedPost


fetchFeedPost : BlueskyAuth -> String -> Task Http.Error FeedPost
fetchFeedPost auth uri =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getPosts?uris=" ++ Url.percentEncode uri
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
fetchThread : BlueskyAuth -> String -> Task Http.Error Thread
fetchThread auth uri =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getPostThread?depth=10&parentHeight=20&uri=" ++ Url.percentEncode uri
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
fetchLikes : BlueskyAuth -> String -> Task Http.Error (List Post)
fetchLikes auth actor =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getActorLikes?limit=50&actor=" ++ Url.percentEncode actor
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


fetchPostRef : BlueskyAuth -> String -> Task Http.Error PostRef
fetchPostRef auth uri =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getPosts?uris=" ++ Url.percentEncode uri
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
setLike : Bool -> String -> BlueskyAuth -> String -> Task Http.Error ()
setLike like repo auth uri =
    fetchPostRef auth uri
        |> Task.andThen
            (\ref ->
                case ( like, ref.viewerLike ) of
                    ( True, Nothing ) ->
                        Time.now
                            |> Task.andThen
                                (\now ->
                                    repoWrite auth
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
                        repoWrite auth
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


repoWrite : BlueskyAuth -> String -> Encode.Value -> Task Http.Error ()
repoWrite auth method body =
    Http.task
        { method = "POST"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/com.atproto.repo." ++ method
        , body = Http.jsonBody body
        , resolver = jsonResolver (Decode.succeed ()) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| A Bluesky post's `at://{did}/app.bsky.feed.post/{rkey}` URI as the short form `Components.Posts.postHref`
puts in a `/post/:postId` route -- `{did}~{rkey}`. The `at://` scheme and the collection are the same for
every post, and `~` is a safe separator: a DID never contains one. (An rkey _may_, which is why
`fromRouteId` splits on the first.) Anything that isn't exactly that shape is returned as-is; every
Bluesky post Rellm links to is a post record, so that never matters in practice.
-}
routeId : String -> String
routeId uri =
    case String.split "/" uri of
        [ "at:", "", did, "app.bsky.feed.post", rkey ] ->
            did ++ "~" ++ rkey

        _ ->
            uri


{-| `routeId`'s inverse, applied to the already percent-decoded id. An id that isn't `{did}~{rkey}` passes
through unchanged.
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
fetchActorProfile : BlueskyAuth -> String -> Task Http.Error ActorProfile
fetchActorProfile auth handle =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.actor.getProfile?actor=" ++ Url.percentEncode handle
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
fetchAuthorFeed : BlueskyAuth -> String -> Task Http.Error (List Post)
fetchAuthorFeed auth handle =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getAuthorFeed?actor=" ++ Url.percentEncode handle ++ "&limit=20"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "feed" (Decode.list decoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.map (List.map toPost)


{-| `GET /xrpc/app.bsky.graph.getFollowers` -- up to 40 of `handle`'s followers. No pagination beyond
that first page -- see `Components.Pages.BlueskyUsersPage`'s own doc on why that's an accepted
first-pass limitation, mirroring `Shared.Federation.Mastodon.fetchFollowers`'s identical choice.
-}
fetchFollowers : BlueskyAuth -> String -> Task Http.Error (List ActorProfile)
fetchFollowers auth handle =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.graph.getFollowers?actor=" ++ Url.percentEncode handle ++ "&limit=40"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "followers" (Decode.list actorProfileDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /xrpc/app.bsky.graph.getFollows` -- `fetchFollowers`'s own doc, just the other direction
(AT Proto's own "follows" naming for what Mastodon/Rellm call "following").
-}
fetchFollows : BlueskyAuth -> String -> Task Http.Error (List ActorProfile)
fetchFollows auth handle =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.graph.getFollows?actor=" ++ Url.percentEncode handle ++ "&limit=40"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "follows" (Decode.list actorProfileDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| `GET /xrpc/app.bsky.actor.searchActors` -- AT Proto's own global actor search (by handle or
display name, network-wide, not scoped to the authenticating account's own follows). Backs
`Components.Pages.UsersPage`'s own unfiltered listing once a search is typed in, same "any connected
account's token works" reasoning `searchPosts`'s own doc already covers.
-}
searchActors : BlueskyAuth -> String -> Task Http.Error (List ActorProfile)
searchActors auth query =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.actor.searchActors?q=" ++ Url.percentEncode query ++ "&limit=25"
        , body = Http.emptyBody
        , resolver = jsonResolver (Decode.field "actors" (Decode.list actorProfileDecoder)) (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| A post's text and `app.bsky.richtext.facet`s, from the Markdown Rellm's editor works in (and
`Post.content` is rendered from -- see `applyFacets`, which this inverts). AT Proto has no Markdown: a link is
a facet over a UTF-8 byte range of plain text. So `[label](https://...)` becomes `label` plus a link facet,
`[#tag](https://bsky.app/hashtag/tag)` a tag facet, and a bare `http(s)://` URL gets a link facet over itself
(Bluesky's own apps detect those client-side, the network doesn't). Anything else is left as typed --
including `@handle`, which stays plain text rather than a (notifying) mention facet.
-}
richText : String -> { text : String, facets : List Encode.Value }
richText markdown =
    richTextHelp markdown "" []


richTextHelp : String -> String -> List Encode.Value -> { text : String, facets : List Encode.Value }
richTextHelp remaining text facets =
    case String.uncons remaining of
        Nothing ->
            { text = text, facets = List.reverse facets }

        Just ( first, rest ) ->
            case markdownLinkAt remaining of
                Just ( label, url, afterLink ) ->
                    richTextHelp afterLink (text ++ label) (facetFor text label (linkFeature label url) :: facets)

                _ ->
                    if String.startsWith "http://" remaining || String.startsWith "https://" remaining then
                        let
                            raw : String
                            raw =
                                remaining |> String.split " " |> List.head |> Maybe.withDefault "" |> String.split "\n" |> List.head |> Maybe.withDefault ""

                            url : String
                            url =
                                dropTrailingPunctuation raw
                        in
                        richTextHelp (String.dropLeft (String.length url) remaining) (text ++ url) (facetFor text url (linkFeature url url) :: facets)

                    else
                        richTextHelp rest (text ++ String.fromChar first) facets


{-| `[label](url)` at the very start of `s` -- the label and the url (which must be `http(s)`) and what's left after.
-}
markdownLinkAt : String -> Maybe ( String, String, String )
markdownLinkAt s =
    case ( String.startsWith "[" s, String.indexes "](" s |> List.head ) of
        ( False, _ ) ->
            Nothing

        ( True, Nothing ) ->
            Nothing

        ( True, Just closeLabel ) ->
            let
                afterParen : String
                afterParen =
                    String.dropLeft (closeLabel + 2) s
            in
            case String.indexes ")" afterParen |> List.head of
                Just closeUrl ->
                    let
                        label : String
                        label =
                            String.slice 1 closeLabel s

                        url : String
                        url =
                            String.left closeUrl afterParen
                    in
                    if label /= "" && not (String.contains "[" label) && not (String.contains "\n" label) && (String.startsWith "http://" url || String.startsWith "https://" url) && not (String.contains " " url) then
                        Just ( label, url, String.dropLeft (closeUrl + 1) afterParen )

                    else
                        Nothing

                Nothing ->
                    Nothing


dropTrailingPunctuation : String -> String
dropTrailingPunctuation url =
    if String.endsWith "." url || String.endsWith "," url || String.endsWith ";" url || String.endsWith ":" url || String.endsWith "!" url || String.endsWith "?" url || String.endsWith ")" url then
        dropTrailingPunctuation (String.dropRight 1 url)

    else
        url


linkFeature : String -> String -> Encode.Value
linkFeature label url =
    case ( String.startsWith "#" label, String.startsWith "https://bsky.app/hashtag/" url ) of
        ( True, True ) ->
            Encode.object [ ( "$type", Encode.string "app.bsky.richtext.facet#tag" ), ( "tag", Encode.string (String.dropLeft 1 label) ) ]

        _ ->
            Encode.object [ ( "$type", Encode.string "app.bsky.richtext.facet#link" ), ( "uri", Encode.string url ) ]


facetFor : String -> String -> Encode.Value -> Encode.Value
facetFor before covered feature =
    let
        start : Int
        start =
            utf8StringLength before
    in
    Encode.object
        [ ( "index", Encode.object [ ( "byteStart", Encode.int start ), ( "byteEnd", Encode.int (start + utf8StringLength covered) ) ] )
        , ( "features", Encode.list identity [ feature ] )
        ]


utf8StringLength : String -> Int
utf8StringLength =
    String.foldl (\char total -> total + utf8Length char) 0


type alias StrongRef =
    { uri : String, cid : String }


encodeStrongRef : StrongRef -> Encode.Value
encodeStrongRef ref =
    Encode.object [ ( "uri", Encode.string ref.uri ), ( "cid", Encode.string ref.cid ) ]


{-| The parent's own ref and the thread root's (the parent itself, unless it's a reply too) -- what a reply
record's `reply` field needs.
-}
fetchReplyRefs : BlueskyAuth -> String -> Task Http.Error ( StrongRef, StrongRef )
fetchReplyRefs auth parentUri =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url = readHost auth ++ "/xrpc/app.bsky.feed.getPosts?uris=" ++ Url.percentEncode parentUri
        , body = Http.emptyBody
        , resolver =
            jsonResolver
                (Decode.field "posts"
                    (Decode.index 0
                        (Decode.map2
                            (\parentCid maybeRoot ->
                                let
                                    parent : StrongRef
                                    parent =
                                        { uri = parentUri, cid = parentCid }
                                in
                                ( parent, Maybe.withDefault parent maybeRoot )
                            )
                            (Decode.field "cid" Decode.string)
                            (Decode.maybe
                                (Decode.at [ "record", "reply", "root" ]
                                    (Decode.map2 StrongRef (Decode.field "uri" Decode.string) (Decode.field "cid" Decode.string))
                                )
                            )
                        )
                    )
                )
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }


{-| Replies to the post at `parentUri` as `repo` (the connected account's handle), `markdown` being turned
into text + facets by `richText`.
-}
createReply : String -> BlueskyAuth -> String -> String -> Task Http.Error ()
createReply repo auth parentUri markdown =
    fetchReplyRefs auth parentUri
        |> Task.andThen (\( parent, root ) -> createPostRecord repo auth (Just ( parent, root )) markdown)
        |> Task.map (\_ -> ())


{-| A new top-level post as `repo` -- `markdown` becomes text + facets via `richText`. Resolves to the new
record's `at://` URI.
-}
createPost : String -> BlueskyAuth -> String -> Task Http.Error String
createPost repo auth markdown =
    createPostRecord repo auth Nothing markdown


{-| `com.atproto.repo.createRecord` for an `app.bsky.feed.post`, a reply when `replyRefs` (parent, root) is given.
-}
createPostRecord : String -> BlueskyAuth -> Maybe ( StrongRef, StrongRef ) -> String -> Task Http.Error String
createPostRecord repo auth replyRefs markdown =
    Time.now
        |> Task.andThen
            (\now ->
                let
                    rich : { text : String, facets : List Encode.Value }
                    rich =
                        richText markdown

                    replyField : List ( String, Encode.Value )
                    replyField =
                        case replyRefs of
                            Just ( parent, root ) ->
                                [ ( "reply", Encode.object [ ( "root", encodeStrongRef root ), ( "parent", encodeStrongRef parent ) ] ) ]

                            Nothing ->
                                []
                in
                Http.task
                    { method = "POST"
                    , headers = readHeaders auth
                    , url = readHost auth ++ "/xrpc/com.atproto.repo.createRecord"
                    , body =
                        Http.jsonBody
                            (Encode.object
                                [ ( "repo", Encode.string repo )
                                , ( "collection", Encode.string "app.bsky.feed.post" )
                                , ( "record"
                                  , Encode.object
                                        ([ ( "$type", Encode.string "app.bsky.feed.post" )
                                         , ( "text", Encode.string rich.text )
                                         , ( "facets", Encode.list identity rich.facets )
                                         , ( "createdAt", Encode.string (Iso8601.fromTime now) )
                                         ]
                                            ++ replyField
                                        )
                                  )
                                ]
                            )
                    , resolver = jsonResolver (Decode.field "uri" Decode.string) (\metadata _ -> Http.BadStatus metadata.statusCode)
                    , timeout = Just 10000
                    }
            )


recordKey : String -> String
recordKey uri =
    uri |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault ""


{-| Rewrites the text (and facets) of the post record at `uri`, keeping every other field of the record
(reply refs, embeds, languages, `createdAt`) as it is: `getRecord`, then `putRecord` guarded by the record's
`cid` so a concurrent edit isn't clobbered. Bluesky's own app can't edit posts, but the protocol allows it.
-}
editPost : String -> BlueskyAuth -> String -> String -> Task Http.Error ()
editPost repo auth uri markdown =
    Http.task
        { method = "GET"
        , headers = readHeaders auth
        , url =
            readHost auth
                ++ "/xrpc/com.atproto.repo.getRecord?repo="
                ++ Url.percentEncode repo
                ++ "&collection=app.bsky.feed.post&rkey="
                ++ Url.percentEncode (recordKey uri)
        , body = Http.emptyBody
        , resolver =
            jsonResolver
                (Decode.map2 Tuple.pair (Decode.field "cid" Decode.string) (Decode.field "value" (Decode.dict Decode.value)))
                (\metadata _ -> Http.BadStatus metadata.statusCode)
        , timeout = Just 10000
        }
        |> Task.andThen
            (\( cid, record ) ->
                let
                    rich : { text : String, facets : List Encode.Value }
                    rich =
                        richText markdown

                    updated : Encode.Value
                    updated =
                        record
                            |> Dict.insert "text" (Encode.string rich.text)
                            |> Dict.insert "facets" (Encode.list identity rich.facets)
                            |> Dict.toList
                            |> Encode.object
                in
                repoWrite auth
                    "putRecord"
                    (Encode.object
                        [ ( "repo", Encode.string repo )
                        , ( "collection", Encode.string "app.bsky.feed.post" )
                        , ( "rkey", Encode.string (recordKey uri) )
                        , ( "record", updated )
                        , ( "swapRecord", Encode.string cid )
                        ]
                    )
            )


{-| Deletes the post record at `uri` -- only works for `repo`'s own.
-}
deletePost : String -> BlueskyAuth -> String -> Task Http.Error ()
deletePost repo auth uri =
    repoWrite auth
        "deleteRecord"
        (Encode.object
            [ ( "repo", Encode.string repo )
            , ( "collection", Encode.string "app.bsky.feed.post" )
            , ( "rkey", Encode.string (recordKey uri) )
            ]
        )


{-| About how many user-perceived characters (grapheme clusters) `text` has -- what Bluesky's 300-character limit
counts (`String.length` counts UTF-16 units, so two per emoji). Elm has no segmenter, so this folds the common
multi-code-point cases into one: combining marks, variation selectors, skin-tone modifiers and tag characters add
nothing, a zero-width joiner glues the next character to the previous one (a family emoji is one), and a pair of
regional indicators (a flag) is one. Errs towards undercounting -- the server has the final say. (One directly self-recursive helper, so Elm compiles
it to a loop: a long pasted document can't overflow the stack.)
-}
graphemeCount : String -> Int
graphemeCount text =
    graphemeCountHelp (String.toList text) False 0


graphemeCountHelp : List Char -> Bool -> Int -> Int
graphemeCountHelp chars afterJoiner count =
    case chars of
        [] ->
            count

        char :: rest ->
            if afterJoiner then
                -- Glued onto whatever the joiner followed.
                graphemeCountHelp rest False count

            else if Char.toCode char == 0x200D then
                graphemeCountHelp rest True count

            else if isCombining (Char.toCode char) then
                graphemeCountHelp rest False count

            else if isRegionalIndicator char then
                -- A flag is a pair of regional indicators.
                case rest of
                    second :: afterPair ->
                        if isRegionalIndicator second then
                            graphemeCountHelp afterPair False (count + 1)

                        else
                            graphemeCountHelp rest False (count + 1)

                    [] ->
                        count + 1

            else
                graphemeCountHelp rest False (count + 1)


isRegionalIndicator : Char -> Bool
isRegionalIndicator char =
    Char.toCode char >= 0x0001F1E6 && Char.toCode char <= 0x0001F1FF


isCombining : Int -> Bool
isCombining code =
    (code >= 0x0300 && code <= 0x036F)
        || (code >= 0x20D0 && code <= 0x20FF)
        || (code >= 0xFE00 && code <= 0xFE0F)
        || (code >= 0x0001F3FB && code <= 0x0001F3FF)
        || (code >= 0x000E0020 && code <= 0x000E007F)
