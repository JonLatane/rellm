module AudioPlayerPanelQueueTests exposing (suite)

{-| `Shared.AudioPlayerPanel`'s queue, which is the app's one queue for audio *and* video: starting something makes it the
current entry and puts the existing queue after it; Next/Prev and the end of an entry move through it, handing playback
between the bar (tracks) and the miniplayer (videos) as the kinds change.
-}

import Expect
import Json.Decode as Decode
import Proto.Rellm exposing (MediaReference, defaultMediaReference)
import Shared.AudioPlayerPanel as AudioPlayerPanel exposing (VideoItem)
import Test exposing (Test, describe, test)


track : String -> MediaReference
track id =
    { defaultMediaReference | id = id, name = Just ("Track " ++ id) }


clip : String -> VideoItem
clip src =
    { src = src, poster = Nothing, aspectRatio = 16 / 9, returnUrl = "https://rellm.org/post/p1" }


{-| What's queued, in order, as media ids (a video's id is its `src`).
-}
queued : AudioPlayerPanel.Model -> List String
queued model =
    List.map (\item -> item.media.id) model.queue


play : AudioPlayerPanel.Msg -> AudioPlayerPanel.Model -> AudioPlayerPanel.Model
play msg model =
    AudioPlayerPanel.update msg model |> Tuple.first


{-| a, b, c queued from the Audio page, a playing.
-}
withTracks : AudioPlayerPanel.Model
withTracks =
    play (AudioPlayerPanel.Open [ track "a", track "b", track "c" ] "a" "rellm.org") AudioPlayerPanel.init


current : AudioPlayerPanel.Model -> Maybe String
current model =
    model.currentId


suite : Test
suite =
    describe "Shared.AudioPlayerPanel (the shared queue)"
        [ describe "starting something puts the existing queue after it"
            [ test "a track chosen from a list plays, then the rest of that list, then what was already queued" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.Enqueue AudioPlayerPanel.PlayLast (track "q") "rellm.org")
                        |> play (AudioPlayerPanel.Open [ track "x", track "y", track "z" ] "y" "rellm.org")
                        |> queued
                        |> Expect.equal [ "y", "z", "a", "b", "c", "q" ]
            , test "starting a video from a page: it's current, the existing queue follows it" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") (Just "A clip") 12.5 True)
                        |> Expect.all
                            [ queued >> Expect.equal [ "https://v/1", "a", "b", "c" ]
                            , current >> Expect.equal (Just "https://v/1")
                            ]
            , test "a post card's audio handed over: it's current, the existing queue follows it, each entry once" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenAt [ track "b" ] "b" "rellm.org" 5000 True)
                        |> queued
                        |> Expect.equal [ "b", "a", "c" ]
            ]
        , describe "video entries"
            [ test "the current video says where the miniplayer is to start" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") (Just "A clip") 12.5 True)
                        |> AudioPlayerPanel.currentVideo
                        |> Maybe.map (\c -> { src = c.video.src, title = c.title, startAt = c.startAt, resume = c.resume })
                        |> Expect.equal (Just { src = "https://v/1", title = "A clip", startAt = 12.5, resume = True })
            , test "a track isn't a video" <|
                \_ ->
                    AudioPlayerPanel.currentVideo withTracks |> Expect.equal Nothing
            , test "beginning a video again changes its generation (so the miniplayer restarts)" <|
                \_ ->
                    let
                        generationAfter : AudioPlayerPanel.Model -> Maybe Int
                        generationAfter =
                            AudioPlayerPanel.currentVideo >> Maybe.map .generation

                        first : AudioPlayerPanel.Model
                        first =
                            play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) withTracks
                    in
                    play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 30 True) first
                        |> generationAfter
                        |> Expect.notEqual (generationAfter first)
            , test "an untitled video is called Video" <|
                \_ ->
                    play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) AudioPlayerPanel.init
                        |> AudioPlayerPanel.currentVideo
                        |> Maybe.map .title
                        |> Expect.equal (Just "Video")
            , test "the miniplayer's reports move the bar's position, but only while a video is current" <|
                \_ ->
                    let
                        withVideo : AudioPlayerPanel.Model
                        withVideo =
                            play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) withTracks
                    in
                    Expect.all
                        [ \_ ->
                            play (AudioPlayerPanel.VideoState False 4200 47740) withVideo
                                |> (\m -> ( m.playing, m.positionMs, m.durationMs ))
                                |> Expect.equal ( False, 4200, 47740 )
                        , \_ ->
                            play (AudioPlayerPanel.VideoState False 4200 47740) withTracks
                                |> .positionMs
                                |> Expect.equal withTracks.positionMs
                        ]
                        ()
            ]
        , describe "moving through the queue switches between the bar and the miniplayer"
            [ test "Next from a track to a video hands over to the miniplayer, starting it from the top" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True)
                        |> play (AudioPlayerPanel.Open [ track "a" ] "a" "rellm.org")
                        |> play AudioPlayerPanel.Next
                        |> AudioPlayerPanel.currentVideo
                        |> Maybe.map (\c -> { src = c.video.src, startAt = c.startAt, resume = c.resume })
                        |> Expect.equal (Just { src = "https://v/1", startAt = 0, resume = True })
            , test "Next from a video to a track hands back to the bar" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True)
                        |> Expect.all
                            [ play AudioPlayerPanel.Next >> current >> Expect.equal (Just "a")
                            , play AudioPlayerPanel.Next >> AudioPlayerPanel.currentVideo >> Expect.equal Nothing
                            ]
            , test "a video ending moves on to the next entry; the last one just stops" <|
                \_ ->
                    let
                        onVideo : AudioPlayerPanel.Model
                        onVideo =
                            play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) withTracks
                    in
                    Expect.all
                        [ \_ -> play AudioPlayerPanel.VideoEnded onVideo |> current |> Expect.equal (Just "a")
                        , \_ ->
                            play (AudioPlayerPanel.OpenVideo (clip "https://v/9") Nothing 0 True) AudioPlayerPanel.init
                                |> play AudioPlayerPanel.VideoEnded
                                |> (\m -> ( current m, m.playing ))
                                |> Expect.equal ( Just "https://v/9", False )
                        ]
                        ()
            , test "previous / next availability follows the queue" <|
                \_ ->
                    let
                        onVideo : AudioPlayerPanel.Model
                        onVideo =
                            play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) withTracks
                    in
                    ( ( AudioPlayerPanel.hasPrevious onVideo, AudioPlayerPanel.hasNext onVideo )
                    , ( AudioPlayerPanel.hasPrevious (play AudioPlayerPanel.Next onVideo), AudioPlayerPanel.hasNext (play AudioPlayerPanel.Next onVideo) )
                    )
                        |> Expect.equal ( ( False, True ), ( True, True ) )
            , test "closing the player clears the queue and the current video" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True)
                        |> play AudioPlayerPanel.Close
                        |> Expect.all
                            [ queued >> Expect.equal []
                            , AudioPlayerPanel.currentVideo >> Expect.equal Nothing
                            ]
            , test "the miniplayer's queue button expands the bar to the queue" <|
                \_ ->
                    play AudioPlayerPanel.ShowQueue withTracks
                        |> (\m -> ( m.expanded, m.queueOpen ))
                        |> Expect.equal ( True, True )
            ]
        , describe "handoffDecoder (a post card's audio moving to the bar)"
            [ test "reads the track, its server and where it had got to" <|
                \_ ->
                    Decode.decodeString AudioPlayerPanel.handoffDecoder """{"id":"t1","host":"rellm.org","positionMs":61500,"playing":true}"""
                        |> Expect.equal (Ok { id = "t1", host = "rellm.org", positionMs = 61500, playing = True })
            , test "a blank id or host is nothing to open, and a negative position starts at the top" <|
                \_ ->
                    [ """{"id":" ","host":"rellm.org","positionMs":0,"playing":true}"""
                    , """{"id":"t1","host":"","positionMs":0,"playing":true}"""
                    ]
                        |> List.map (Decode.decodeString AudioPlayerPanel.handoffDecoder >> Result.toMaybe)
                        |> Expect.equal [ Nothing, Nothing ]
            ]
        ]
