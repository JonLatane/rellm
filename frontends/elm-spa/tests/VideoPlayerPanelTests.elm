module VideoPlayerPanelTests exposing (suite)

{-| `Shared.VideoPlayerPanel`: what `<rellm-video>` hands it over `Ports.miniVideoRequested` / `Ports.miniVideoState`, and the
floating player it renders for the queue's current video.
-}

import Expect
import Html.Attributes
import Json.Decode as Decode
import Json.Encode
import Shared.VideoPlayerPanel as VideoPlayerPanel exposing (MiniVideo)
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector


payload : String
payload =
    """{"src":"https://rellm.org/media/m1","poster":"https://rellm.org/media/m1?size=video_preview_medium","title":"A post","time":12.5,"playing":true,"aspectRatio":1.7778,"returnUrl":"https://rellm.org/post/p1"}"""


video : MiniVideo
video =
    { src = "https://rellm.org/media/m1"
    , poster = Nothing
    , title = Just "A post"
    , startAt = 12.5
    , resume = True
    , aspectRatio = 16 / 9
    , returnUrl = "https://rellm.org/post/p1"
    , mediaId = Nothing
    , host = ""
    , downloads = []
    }


showing : VideoPlayerPanel.Model
showing =
    VideoPlayerPanel.update (VideoPlayerPanel.Show video) VideoPlayerPanel.init


suite : Test
suite =
    describe "Shared.VideoPlayerPanel"
        [ describe "decoder"
            [ test "reads what the player sends" <|
                \_ ->
                    Decode.decodeString VideoPlayerPanel.decoder payload
                        |> Expect.equal
                            (Ok
                                { src = "https://rellm.org/media/m1"
                                , poster = Just "https://rellm.org/media/m1?size=video_preview_medium"
                                , title = Just "A post"
                                , startAt = 12.5
                                , resume = True
                                , aspectRatio = 1.7778
                                , returnUrl = "https://rellm.org/post/p1"
                                , mediaId = Nothing
                                , host = ""
                                , downloads = []
                                }
                            )
            , test "a null, blank or missing poster or title is none" <|
                \_ ->
                    [ """{"src":"s","poster":null,"title":"  ","time":0,"playing":false,"aspectRatio":1,"returnUrl":"u"}"""
                    , """{"src":"s","time":0,"playing":false,"aspectRatio":1,"returnUrl":"u"}"""
                    ]
                        |> List.map (Decode.decodeString VideoPlayerPanel.decoder >> Result.map (\v -> ( v.poster, v.title )))
                        |> Expect.equal [ Ok ( Nothing, Nothing ), Ok ( Nothing, Nothing ) ]
            , test "a stream that hasn't reported its size yet is 16:9, and odd shapes are kept within reason" <|
                \_ ->
                    let
                        ratioOf : String -> Result Decode.Error Float
                        ratioOf aspect =
                            Decode.decodeString VideoPlayerPanel.decoder
                                ("{\"src\":\"s\",\"time\":0,\"playing\":false,\"returnUrl\":\"u\"" ++ aspect ++ "}")
                                |> Result.map .aspectRatio
                    in
                    [ ratioOf "", ratioOf ",\"aspectRatio\":100", ratioOf ",\"aspectRatio\":0.01" ]
                        |> Expect.equal [ Ok (16 / 9), Ok 3, Ok 0.4 ]
            , test "a negative time starts at the beginning" <|
                \_ ->
                    Decode.decodeString VideoPlayerPanel.decoder """{"src":"s","time":-3,"playing":false,"aspectRatio":1,"returnUrl":"u"}"""
                        |> Result.map .startAt
                        |> Expect.equal (Ok 0)
            , test "no video src, or no page to return to, is nothing to show" <|
                \_ ->
                    [ """{"src":"  ","time":0,"playing":false,"aspectRatio":1,"returnUrl":"u"}"""
                    , """{"src":"s","time":0,"playing":false,"aspectRatio":1}"""
                    ]
                        |> List.map (Decode.decodeString VideoPlayerPanel.decoder >> Result.toMaybe)
                        |> Expect.equal [ Nothing, Nothing ]
            ]
        , describe "decoder's media id"
            [ test "is optional" <|
                \_ ->
                    Decode.decodeString VideoPlayerPanel.decoder """{"src":"s","time":0,"playing":false,"aspectRatio":1,"returnUrl":"u","mediaId":"m7"}"""
                        |> Result.map (\v -> ( v.mediaId, v.host, v.downloads ))
                        |> Expect.equal (Ok ( Just "m7", "", [] ))
            , test "a video on one of our servers names it and its download sizes" <|
                \_ ->
                    Decode.decodeString VideoPlayerPanel.decoder """{"src":"s","time":0,"playing":false,"aspectRatio":1,"returnUrl":"u","mediaId":"m7","host":"rellm.org","downloads":"small,large,original"}"""
                        |> Result.map (\v -> ( v.host, v.downloads ))
                        |> Expect.equal (Ok ( "rellm.org", [ "small", "large", "original" ] ))
            ]
        , describe "reportDecoder"
            [ test "reads the player's state" <|
                \_ ->
                    Decode.decodeString VideoPlayerPanel.reportDecoder """{"playing":true,"positionMs":4200,"durationMs":47740,"ended":false}"""
                        |> Expect.equal (Ok { playing = True, positionMs = 4200, durationMs = 47740, ended = False })
            , test "an unknown duration (a stream still loading) is 0" <|
                \_ ->
                    Decode.decodeString VideoPlayerPanel.reportDecoder """{"playing":false,"positionMs":0,"durationMs":0,"ended":true}"""
                        |> Result.map (\r -> ( r.durationMs, r.ended ))
                        |> Expect.equal (Ok ( 0, True ))
            ]
        , describe "update"
            [ test "Show displays the queue's current video, Hide clears it" <|
                \_ ->
                    showing
                        |> Expect.all
                            [ .video >> Expect.equal (Just video)
                            , VideoPlayerPanel.update VideoPlayerPanel.Hide >> .video >> Expect.equal Nothing
                            ]
            , test "what the queue decides (a request, a report, prev/next) leaves the panel alone" <|
                \_ ->
                    [ VideoPlayerPanel.Requested video
                    , VideoPlayerPanel.Reported { playing = True, positionMs = 1, durationMs = 2, ended = False }
                    , VideoPlayerPanel.PrevClicked
                    , VideoPlayerPanel.NextClicked
                    , VideoPlayerPanel.QueueClicked
                    , VideoPlayerPanel.EnlargeClicked
                    , VideoPlayerPanel.NoOp
                    ]
                        |> List.map (\msg -> VideoPlayerPanel.update msg showing)
                        |> List.all ((==) showing)
                        |> Expect.equal True
            , test "setNavigation follows the queue" <|
                \_ ->
                    VideoPlayerPanel.setNavigation { hasPrevious = True, hasNext = False } showing
                        |> (\model -> ( model.hasPrevious, model.hasNext ))
                        |> Expect.equal ( True, False )
            ]
        , describe "view"
            [ test "renders nothing without a video" <|
                \_ ->
                    VideoPlayerPanel.view VideoPlayerPanel.init
                        |> Query.fromHtml
                        |> Query.hasNot [ Selector.tag "rellm-video" ]
            , test "plays the video in a <rellm-video> that knows it's the miniplayer, where the page's left off" <|
                \_ ->
                    VideoPlayerPanel.view showing
                        |> Query.fromHtml
                        |> Query.find [ Selector.tag "rellm-video" ]
                        |> Expect.all
                            [ Query.has [ Selector.attribute (Html.Attributes.attribute "data-miniplayer-panel" "") ]
                            , Query.has [ Selector.attribute (Html.Attributes.attribute "data-start-at" "12.5") ]
                            , Query.has [ Selector.attribute (Html.Attributes.attribute "data-resume" "") ]
                            , Query.find [ Selector.tag "video" ] >> Query.has [ Selector.attribute (Html.Attributes.attribute "src" "https://rellm.org/media/m1") ]
                            ]
            , test "a video that was paused isn't told to resume" <|
                \_ ->
                    VideoPlayerPanel.view (VideoPlayerPanel.update (VideoPlayerPanel.Show { video | resume = False }) VideoPlayerPanel.init)
                        |> Query.fromHtml
                        |> Query.find [ Selector.tag "rellm-video" ]
                        |> Query.hasNot [ Selector.attribute (Html.Attributes.attribute "data-resume" "") ]
            , test "a video that is Rellm media says which, so a thumbnail's position can carry over to it" <|
                \_ ->
                    VideoPlayerPanel.view (VideoPlayerPanel.update (VideoPlayerPanel.Show { video | mediaId = Just "m1" }) VideoPlayerPanel.init)
                        |> Query.fromHtml
                        |> Query.find [ Selector.tag "rellm-video" ]
                        |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-media-id" "m1") ]
            , test "the queue buttons are the audio bar's own transport and queue glyphs" <|
                \_ ->
                    VideoPlayerPanel.view showing
                        |> Query.fromHtml
                        |> Query.find [ Selector.class "video-player-panel-queue-controls" ]
                        |> Expect.all
                            [ Query.has [ Selector.class "audio-player-icon-prev" ]
                            , Query.has [ Selector.class "audio-player-icon-next" ]
                            , Query.has [ Selector.class "audio-player-icon-queue" ]
                            , Query.findAll [ Selector.tag "button" ] >> Query.each (Query.has [ Selector.class "audio-player-button" ])
                            ]
            , test "has no back or close button (the expanded player has the close), and the player's viewer button opens the viewer" <|
                \_ ->
                    VideoPlayerPanel.view showing
                        |> Query.fromHtml
                        |> Expect.all
                            [ Query.hasNot [ Selector.class "video-player-panel-expand" ]
                            , Query.hasNot [ Selector.class "video-player-panel-close" ]
                            , Query.find [ Selector.tag "rellm-video" ]
                                >> Event.simulate (Event.custom "rellm-video-enlarge" (Json.Encode.object []))
                                >> Event.expect VideoPlayerPanel.EnlargeClicked
                            ]
            , test "previous / next buttons drive the queue, and are disabled where the queue has nothing" <|
                \_ ->
                    let
                        buttons : VideoPlayerPanel.Model -> Query.Multiple VideoPlayerPanel.Msg
                        buttons model =
                            VideoPlayerPanel.view model
                                |> Query.fromHtml
                                |> Query.find [ Selector.class "video-player-panel-queue-controls" ]
                                |> Query.findAll [ Selector.tag "button" ]
                    in
                    Expect.all
                        [ \_ -> buttons showing |> Query.index 0 |> Query.has [ Selector.disabled True ]
                        , \_ -> buttons showing |> Query.index 1 |> Query.has [ Selector.disabled True ]
                        , \_ ->
                            buttons (VideoPlayerPanel.setNavigation { hasPrevious = True, hasNext = True } showing)
                                |> Expect.all
                                    [ Query.index 0 >> Event.simulate Event.click >> Event.expect VideoPlayerPanel.PrevClicked
                                    , Query.index 1 >> Event.simulate Event.click >> Event.expect VideoPlayerPanel.NextClicked
                                    , Query.index 2 >> Event.simulate Event.click >> Event.expect VideoPlayerPanel.QueueClicked
                                    ]
                        ]
                        ()
            ]
        ]
