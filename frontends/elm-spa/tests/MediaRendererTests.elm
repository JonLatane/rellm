module MediaRendererTests exposing (suite)

{-| `Components.MediaRenderer`'s video rendering: every video -- Rellm's own, Bluesky's HLS stream, Mastodon's -- sits
inside `<rellm-video>`, whose playback controls (`public/index.html`) replace the browser's native `controls`.
-}

import Components.MediaRenderer as MediaRenderer
import Expect
import Html
import Html.Attributes
import Proto.Rellm exposing (MediaReference, defaultMediaReference, defaultMediaSize)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Support.RellmServerFactory as RellmServerFactory
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


media : String -> String -> MediaReference
media contentType url =
    { defaultMediaReference
        | id = "m1"
        , url = Just url
        , sizes = [ { defaultMediaSize | conversion = MEDIACONVERSIONORIGINAL, contentType = contentType } ]
    }


render : MediaReference -> Query.Single ()
render mediaReference =
    Html.div
        []
        [ MediaRenderer.view MediaRenderer.Natural
            MediaRenderer.ToWidthAndHeight
            (RellmServerFactory.connected "rellm.org")
            Nothing
            True
            MediaRenderer.init
            (\_ -> ())
            (\_ -> ())
            mediaReference
        ]
        |> Query.fromHtml
        |> Query.children []
        |> Query.first


suite : Test
suite =
    describe "Components.MediaRenderer"
        [ describe "video"
            [ test "is wrapped in <rellm-video>, which draws the playback controls" <|
                \_ ->
                    render (media "video/mp4" "https://rellm.org/media/m1")
                        |> Expect.all
                            [ Query.has [ Selector.tag "rellm-video" ]
                            , Query.find [ Selector.tag "video" ] >> Query.has [ Selector.attribute (Html.Attributes.src "https://rellm.org/media/m1") ]
                            ]
            , test "doesn't also turn on the browser's native controls" <|
                \_ ->
                    render (media "video/mp4" "https://rellm.org/media/m1")
                        |> Query.find [ Selector.tag "video" ]
                        |> Query.hasNot [ Selector.attribute (Html.Attributes.controls True) ]
            , test "a Mastodon video (a bare video/* type) gets the same wrapper" <|
                \_ ->
                    render (media "video/*" "https://mastodon.social/system/media_attachments/1/original.mp4")
                        |> Query.has [ Selector.tag "rellm-video" ]
            , test "a Bluesky HLS playlist gets the wrapper and its thumbnail as the poster" <|
                \_ ->
                    render (media "video/*" "https://video.bsky.app/watch/did%3Aplc%3Aabc/bafk/playlist.m3u8")
                        |> Expect.all
                            [ Query.has [ Selector.tag "rellm-video" ]
                            , Query.find [ Selector.tag "video" ]
                                >> Query.has [ Selector.attribute (Html.Attributes.attribute "poster" "https://video.bsky.app/watch/did%3Aplc%3Aabc/bafk/thumbnail.jpg") ]
                            ]
            , test "tells <rellm-video> its MediaSize, so only thumbnails get the enlarge button" <|
                \_ ->
                    let
                        sizeOf : MediaRenderer.MediaSize -> Query.Single ()
                        sizeOf mediaSize =
                            Html.div []
                                [ MediaRenderer.view mediaSize
                                    MediaRenderer.ToWidthAndHeight
                                    (RellmServerFactory.connected "rellm.org")
                                    Nothing
                                    True
                                    MediaRenderer.init
                                    (\_ -> ())
                                    (\_ -> ())
                                    (media "video/mp4" "https://rellm.org/media/m1")
                                ]
                                |> Query.fromHtml
                                |> Query.find [ Selector.tag "rellm-video" ]
                    in
                    Expect.all
                        [ \_ -> sizeOf MediaRenderer.Natural |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-media-size" "natural") ]
                        , \_ -> sizeOf MediaRenderer.Small |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-media-size" "small") ]
                        , \_ -> sizeOf MediaRenderer.ExtraSmall |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-media-size" "extra-small") ]
                        ]
                        ()
            , test "a video someone pressed play on is marked as theirs (it autoplays muted), a preview isn't" <|
                \_ ->
                    let
                        viewWith : MediaRenderer.Model -> Query.Single ()
                        viewWith playState =
                            Html.div []
                                [ MediaRenderer.view MediaRenderer.Small
                                    MediaRenderer.ToWidthAndHeight
                                    (RellmServerFactory.connected "rellm.org")
                                    Nothing
                                    False
                                    playState
                                    (\_ -> ())
                                    (\_ -> ())
                                    (media "video/mp4" "https://rellm.org/media/m1")
                                ]
                                |> Query.fromHtml
                    in
                    -- Without a preview thumbnail the video renders live either way, so what tells them apart is the click.
                    Expect.all
                        [ \_ -> viewWith MediaRenderer.init |> Query.find [ Selector.tag "rellm-video" ] |> Query.hasNot [ Selector.attribute (Html.Attributes.attribute "data-user-started" "") ]
                        , \_ ->
                            viewWith (MediaRenderer.update (MediaRenderer.PlayClicked "m1") MediaRenderer.init)
                                |> Query.find [ Selector.tag "rellm-video" ]
                                |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-user-started" "") ]
                        ]
                        ()
            , test "an ordinary video has no poster of its own" <|
                \_ ->
                    render (media "video/mp4" "https://rellm.org/media/m1")
                        |> Query.find [ Selector.tag "video" ]
                        |> Query.hasNot [ Selector.attribute (Html.Attributes.attribute "poster" "") ]
            ]
        , test "an image isn't wrapped" <|
            \_ ->
                render (media "image/jpeg" "https://rellm.org/media/m2")
                    |> Query.hasNot [ Selector.tag "rellm-video" ]
        ]
