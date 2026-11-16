module Federation.VideoPosterTests exposing (suite)

{-| `Shared.Federation.VideoPoster.posterUrl`: a Bluesky or Mastodon video's thumbnail, found from the video's own URL.
-}

import Expect
import Shared.Federation.VideoPoster as VideoPoster
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Shared.Federation.VideoPoster.posterUrl"
        [ test "a Bluesky HLS playlist's thumbnail is next to it" <|
            \_ ->
                VideoPoster.posterUrl "https://video.bsky.app/watch/did%3Aplc%3Aabc/bafk/playlist.m3u8"
                    |> Expect.equal (Just "https://video.bsky.app/watch/did%3Aplc%3Aabc/bafk/thumbnail.jpg")
        , test "a Bluesky playlist with a query string still finds its thumbnail" <|
            \_ ->
                VideoPoster.posterUrl "https://video.bsky.app/watch/did%3Aplc%3Aabc/bafk/playlist.m3u8?token=abc"
                    |> Expect.equal (Just "https://video.bsky.app/watch/did%3Aplc%3Aabc/bafk/thumbnail.jpg")
        , test "a Mastodon video's thumbnail is its small/ copy as a png, keeping the query" <|
            \_ ->
                VideoPoster.posterUrl "https://s3.example.com/mastodonworld/cache/media_attachments/files/117/554/560/original/1eb5c8d5.mp4?X=1"
                    |> Expect.equal (Just "https://s3.example.com/mastodonworld/cache/media_attachments/files/117/554/560/small/1eb5c8d5.png?X=1")
        , test "a video that isn't laid out either way has none" <|
            \_ ->
                [ "https://example.com/uploads/original/clip.mp4"
                , "https://example.com/media_attachments/files/1/clip.mp4"
                , "https://example.com/media_attachments/files/1/original/clip.txt"
                ]
                    |> List.map VideoPoster.posterUrl
                    |> Expect.equal [ Nothing, Nothing, Nothing ]
        ]
