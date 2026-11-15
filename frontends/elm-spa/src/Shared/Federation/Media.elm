module Shared.Federation.Media exposing
    ( Item
    , Kind(..)
    , collect
    , itemsOf
    , plainTitle
    , thumbnailFor
    )

{-| The video and audio of Mastodon/Bluesky _posts_, for the Video and Audio pages (`Components.MediaFeed`):
unlike a Rellm server, neither network has a media library to list, so these pages search/scan posts and keep
the ones that carry a video or an audio file (`itemsOf`). An `Item` is one such attachment together with the
`Post` it came in, which is where its author, text, date and link live.

Neither network can be asked for "only posts with video/audio" directly (Mastodon's `only_media` includes
images; Bluesky's search has no media filter at all), so `collect` pages through a source until it has found
enough of what it was asked for, or has run out of patience (`maxPages`).

-}

import Http
import Proto.Rellm exposing (MediaReference, Post)
import Shared.Federation.Common exposing (sensitiveMediaHiddenId)
import Task exposing (Task)


type Kind
    = VideoKind
    | AudioKind


{-| One video or audio attachment. `host` is the `"mastodon:" ++ instance` / `"bluesky:" ++ ...` tag its feed
is keyed by (what every card treats as its server). `id` is unique across the feed (`post.id ++ "/" ++
media.id`), unlike `media.id` alone, which a quote or repost could repeat.
-}
type alias Item =
    { host : String
    , id : String
    , kind : Kind
    , media : MediaReference
    , post : Post
    , thumbnailUrl : Maybe String
    }


{-| How many matching items `collect` tries to gather before it stops paging.
-}
wanted : Int
wanted =
    12


{-| The most source pages one `collect` will read -- a source with very little video/audio mustn't be scanned
forever for one load.
-}
maxPages : Int
maxPages =
    5


{-| Every `kind` attachment in `posts`, newest post first as given. Pure so it's unit-testable.
-}
itemsOf : Kind -> String -> List Post -> List Item
itemsOf kind host posts =
    posts
        |> List.concatMap
            (\post ->
                post.media
                    |> List.filter (\media -> media.id /= sensitiveMediaHiddenId && kindOf media == Just kind)
                    |> List.map
                        (\media ->
                            { host = host
                            , id = post.id ++ "/" ++ media.id
                            , kind = kind
                            , media = media
                            , post = post
                            , thumbnailUrl = thumbnailFor host media
                            }
                        )
            )


{-| Whether `media` is a video or an audio file, by the content type (`video/*`, `audio/*`) its first size
carries -- see `Shared.Federation.Mastodon.toMediaReference`/`Bluesky.toVideoMediaReference`.
-}
kindOf : MediaReference -> Maybe Kind
kindOf media =
    case media.sizes |> List.head |> Maybe.map .contentType of
        Just contentType ->
            if String.startsWith "video/" contentType then
                Just VideoKind

            else if String.startsWith "audio/" contentType then
                Just AudioKind

            else
                Nothing

        Nothing ->
            Nothing


{-| A still for a video, where one can be derived: Bluesky's video CDN serves `thumbnail.jpg` next to each
`playlist.m3u8`. Mastodon's attachments carry their preview separately (not kept in a `MediaReference`),
so those have none and the card shows a placeholder.
-}
thumbnailFor : String -> MediaReference -> Maybe String
thumbnailFor host media =
    case media.url of
        Just url ->
            if String.startsWith "bluesky:" host && String.endsWith "/playlist.m3u8" url then
                -- 13 is the length of "playlist.m3u8".
                Just (String.dropRight 13 url ++ "thumbnail.jpg")

            else
                Nothing

        Nothing ->
            Nothing


{-| Pages through `fetchPage` (a source's posts, with the cursor for the page after) from `cursor`, gathering
`kind` items until there are `wanted` of them, the source runs out, or `maxPages` pages have been read.
Resolves to what it found and the cursor to continue from (`Nothing` once the source has run out).
-}
collect : Kind -> String -> (Maybe String -> Task Http.Error ( List Post, Maybe String )) -> Maybe String -> Task Http.Error ( List Item, Maybe String )
collect kind host fetchPage cursor =
    collectHelp kind host fetchPage maxPages cursor []


collectHelp : Kind -> String -> (Maybe String -> Task Http.Error ( List Post, Maybe String )) -> Int -> Maybe String -> List Item -> Task Http.Error ( List Item, Maybe String )
collectHelp kind host fetchPage pagesLeft cursor found =
    fetchPage cursor
        |> Task.andThen
            (\( posts, next ) ->
                let
                    items : List Item
                    items =
                        found ++ itemsOf kind host posts
                in
                if List.length items >= wanted || next == Nothing || pagesLeft <= 1 then
                    Task.succeed ( items, next )

                else
                    collectHelp kind host fetchPage (pagesLeft - 1) next items
            )


{-| A card title from a post's text: tags dropped (Mastodon's `content` is HTML), whitespace collapsed,
cut to about `limit` characters. Blank if there's no text.
-}
plainTitle : Int -> String -> String
plainTitle limit content =
    let
        stripped : String
        stripped =
            stripTags content

        collapsed : String
        collapsed =
            stripped |> String.words |> String.join " "
    in
    if String.length collapsed > limit then
        String.left limit collapsed ++ "…"

    else
        collapsed


stripTags : String -> String
stripTags html =
    String.foldl
        (\char ( inTag, acc ) ->
            if char == '<' then
                ( True, acc ++ " " )

            else if char == '>' then
                ( False, acc )

            else if inTag then
                ( inTag, acc )

            else
                ( inTag, acc ++ String.fromChar char )
        )
        ( False, "" )
        html
        |> Tuple.second
