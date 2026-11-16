module Shared.Federation.VideoPoster exposing (posterUrl)

{-| The poster frame (still image) of a Mastodon or Bluesky video, worked out from the video's own URL.

A `MediaReference` has no field to carry the thumbnail a network's API gives next to a video (Mastodon's
`preview_url`, Bluesky's `app.bsky.embed.video#view.thumbnail`), and neither network needs one: both keep the
thumbnail next to the video at a predictable path. So wherever a federated video is shown -- a post's media
(`Components.MediaRenderer`), the Video page's cards, My Media's tiles (`Components.FederatedMyMedia`) --
`posterUrl` finds it from the URL alone, rather than the proto growing a field.

-}


{-| The poster frame a video shows before it is played, if its URL tells where one is: a Bluesky video's (`hlsPosterUrl`) or a
Mastodon video's (`mastodonPosterUrl`).
-}
posterUrl : String -> Maybe String
posterUrl videoUrl =
    case hlsPosterUrl videoUrl of
        Just poster ->
            Just poster

        Nothing ->
            mastodonPosterUrl videoUrl


{-| The poster frame of a Mastodon video (or gifv), if `videoUrl` is where Mastodon keeps the file. Mastodon stores a video as
`.../media_attachments/files/<id>/original/<name>.mp4` and its thumbnail -- the `preview_url` its API gives -- next to it as
`.../small/<name>.png`, on the same host and with the same query string, whichever server cached it. `MediaReference` has no field
to carry that `preview_url`, so (like `hlsPosterUrl`) it is re-derived from the path. A server that lays its files out some other
way just gets no poster, which is how every Mastodon video looked before.
-}
mastodonPosterUrl : String -> Maybe String
mastodonPosterUrl videoUrl =
    let
        ( path, query ) =
            case String.split "?" videoUrl of
                head :: rest ->
                    ( head, rest |> String.join "?" |> (\q -> if q == "" then "" else "?" ++ q) )

                [] ->
                    ( videoUrl, "" )

        videoExtensions : List String
        videoExtensions =
            [ ".mp4", ".webm", ".mov", ".m4v", ".mkv", ".ogv" ]

        extensionOf : String -> Maybe String
        extensionOf name =
            videoExtensions |> List.filter (\extension -> String.endsWith extension (String.toLower name)) |> List.head
    in
    if String.contains "/media_attachments/files/" path && String.contains "/original/" path then
        case ( String.split "/original/" path |> List.reverse, extensionOf path ) of
            ( name :: before :: more, Just extension ) ->
                Just
                    (String.join "/original/" (List.reverse (before :: more))
                        ++ "/small/"
                        ++ String.dropRight (String.length extension) name
                        ++ ".png"
                        ++ query
                    )

            _ ->
                Nothing

    else
        Nothing


{-| The poster frame of a Bluesky video, if `videoUrl` is one of its HLS playlists
(`.../{did}/{cid}/playlist.m3u8`) -- Bluesky's video CDN serves the thumbnail alongside it at
`.../thumbnail.jpg`, which is also what `app.bsky.embed.video#view.thumbnail` says. `MediaReference`
has no field to carry that decoded thumbnail, so it's re-derived from the playlist's path (any
host, any query string) rather than adding one to the proto. Such a video has no
`VIDEO_PREVIEW_THUMBNAIL_*` conversions to show instead (see `viewHelper`), so a live `<video>`
renders right away with this as its `poster`. (Playback itself is hls.js's job, see
`public/index.html`.)
-}
hlsPosterUrl : String -> Maybe String
hlsPosterUrl videoUrl =
    let
        path : String
        path =
            videoUrl |> String.split "?" |> List.head |> Maybe.withDefault videoUrl
    in
    if String.endsWith "/playlist.m3u8" path then
        -- 13 = length of "playlist.m3u8"
        Just (String.dropRight 13 path ++ "thumbnail.jpg")

    else
        Nothing
