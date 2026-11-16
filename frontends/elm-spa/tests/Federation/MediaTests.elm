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
        , describe "thumbnails"
            [ test "a video item's thumbnail is its poster, found from its URL (Bluesky and Mastodon)" <|
                \_ ->
                    [ post "p1" [ reference "a" "video/*" (Just "https://video.bsky.app/watch/did:plc:abc/bafy123/playlist.m3u8") ]
                    , post "p2" [ reference "b" "video/*" (Just "https://m.example/media_attachments/files/1/2/original/clip.mp4") ]
                    , post "p3" [ reference "c" "video/*" (Just "https://example.social/video.mp4") ]
                    , post "p4" [ reference "d" "video/*" (Just "https://video.bsky.app/watch/did:plc:abc/bafy456/playlist.m3u8?token=abc") ]
                    ]
                        |> Media.itemsOf VideoKind "mixed"
                        |> List.map .thumbnailUrl
                        |> Expect.equal
                            [ Just "https://video.bsky.app/watch/did:plc:abc/bafy123/thumbnail.jpg"
                            , Just "https://m.example/media_attachments/files/1/2/small/clip.png"
                            , Nothing
                            , Just "https://video.bsky.app/watch/did:plc:abc/bafy456/thumbnail.jpg"
                            ]
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
