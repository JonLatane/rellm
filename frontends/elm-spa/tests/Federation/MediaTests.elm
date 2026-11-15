module Federation.MediaTests exposing (suite)

{-| `Shared.Federation.Media`'s pure parts: picking the video/audio attachments out of posts, deriving a
Bluesky video's still, and shortening a post's text into a card title.
-}

import Expect
import Proto.Rellm exposing (MediaReference, Post, defaultMediaReference, defaultMediaSize, defaultPost)
import Shared.Federation.Media as Media exposing (Kind(..))
import Test exposing (Test, describe, test)


reference : String -> String -> Maybe String -> MediaReference
reference id contentType url =
    { defaultMediaReference | id = id, url = url, sizes = [ { defaultMediaSize | contentType = contentType } ] }


post : String -> List MediaReference -> Post
post id media =
    { defaultPost | id = id, media = media }


suite : Test
suite =
    describe "Shared.Federation.Media"
        [ describe "itemsOf"
            [ test "keeps only the requested kind, tagged with the host and a post-scoped id" <|
                \_ ->
                    [ post "p1" [ reference "m1" "video/*" Nothing, reference "m2" "image/*" Nothing, reference "m3" "audio/*" Nothing ]
                    , post "p2" [ reference "m4" "video/*" Nothing ]
                    ]
                        |> Media.itemsOf VideoKind "mastodon:example.social"
                        |> List.map (\item -> ( item.host, item.id ))
                        |> Expect.equal [ ( "mastodon:example.social", "p1/m1" ), ( "mastodon:example.social", "p2/m4" ) ]
            , test "audio is picked the same way" <|
                \_ ->
                    [ post "p1" [ reference "m1" "video/*" Nothing, reference "m3" "audio/*" Nothing ] ]
                        |> Media.itemsOf AudioKind "mastodon:example.social"
                        |> List.map .id
                        |> Expect.equal [ "p1/m3" ]
            , test "posts without video or audio contribute nothing" <|
                \_ ->
                    [ post "p1" [], post "p2" [ reference "m1" "image/*" Nothing ] ]
                        |> Media.itemsOf VideoKind "bluesky:bsky.app"
                        |> Expect.equal []
            ]
        , describe "thumbnailFor"
            [ test "a Bluesky playlist has a thumbnail next to it" <|
                \_ ->
                    Media.thumbnailFor "bluesky:bsky.app" (reference "x" "video/*" (Just "https://video.bsky.app/watch/did:plc:abc/bafy123/playlist.m3u8"))
                        |> Expect.equal (Just "https://video.bsky.app/watch/did:plc:abc/bafy123/thumbnail.jpg")
            , test "a Mastodon video has none" <|
                \_ ->
                    Media.thumbnailFor "mastodon:example.social" (reference "x" "video/*" (Just "https://example.social/video.mp4"))
                        |> Expect.equal Nothing
            ]
        , describe "plainTitle"
            [ test "drops HTML tags and collapses whitespace" <|
                \_ ->
                    Media.plainTitle 90 "<p>Hello   <a href=\"https://x\">world</a></p>"
                        |> Expect.equal "Hello world"
            , test "cuts long text with an ellipsis" <|
                \_ ->
                    Media.plainTitle 5 "abcdefghij"
                        |> Expect.equal "abcde…"
            ]
        ]
