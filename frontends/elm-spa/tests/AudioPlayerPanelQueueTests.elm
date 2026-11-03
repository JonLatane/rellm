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
    { src = src, poster = Nothing, aspectRatio = 16 / 9, returnUrl = "https://rellm.org/post/p1", mediaId = Nothing, host = "", downloads = [] }


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
        , describe "the media viewer's videos (OpenViewerVideo / LeaveViewerVideo)"
            [ test "paging off a viewer video closes the miniplayer when nothing video was current before" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenViewerVideo (clip "https://v/1") Nothing 0 True True)
                        |> play AudioPlayerPanel.LeaveViewerVideo
                        |> Expect.all
                            [ AudioPlayerPanel.currentVideo >> Expect.equal Nothing
                            , .playing >> Expect.equal False
                            , .currentId >> Expect.equal Nothing
                            ]
            , test "a video that was current before the viewer took over comes back, paused, where it was" <|
                \_ ->
                    let
                        withPlayingVideo : AudioPlayerPanel.Model
                        withPlayingVideo =
                            play (AudioPlayerPanel.OpenVideo (clip "https://v/old") Nothing 0 True) withTracks
                                |> play (AudioPlayerPanel.VideoState True 42000 90000)
                    in
                    withPlayingVideo
                        |> play (AudioPlayerPanel.OpenViewerVideo (clip "https://v/1") Nothing 0 True True)
                        |> play AudioPlayerPanel.LeaveViewerVideo
                        |> AudioPlayerPanel.currentVideo
                        |> Maybe.map (\v -> ( v.video.src, v.startAt, v.resume ))
                        |> Expect.equal (Just ( "https://v/old", 42, False ))
            , test "paging from one viewer video to the next keeps the video from before the viewer" <|
                \_ ->
                    play (AudioPlayerPanel.OpenVideo (clip "https://v/old") Nothing 0 True) withTracks
                        |> play (AudioPlayerPanel.OpenViewerVideo (clip "https://v/1") Nothing 0 True True)
                        |> play (AudioPlayerPanel.OpenViewerVideo (clip "https://v/2") Nothing 0 True False)
                        |> play AudioPlayerPanel.LeaveViewerVideo
                        |> AudioPlayerPanel.currentVideo
                        |> Maybe.map (.video >> .src)
                        |> Expect.equal (Just "https://v/old")
            , test "the same video the viewer opens on (enlarged from the miniplayer) is not 'a different video'" <|
                \_ ->
                    play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) withTracks
                        |> play (AudioPlayerPanel.OpenViewerVideo (clip "https://v/1") Nothing 0 True True)
                        |> play AudioPlayerPanel.LeaveViewerVideo
                        |> AudioPlayerPanel.currentVideo
                        |> Expect.equal Nothing
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
        , describe "a handoff waiting on a fetch"
            [ test "its pending seek doesn't carry over to a different track that begins first" <|
                \_ ->
                    withTracks
                        |> play (AudioPlayerPanel.OpenAt [ track "h" ] "h" "rellm.org" 61500 True)
                        |> Expect.all
                            [ .pendingSeekMs >> Expect.equal (Just 61500)
                            , play (AudioPlayerPanel.Open [ track "x" ] "x" "rellm.org") >> .pendingSeekMs >> Expect.equal Nothing
                            ]
            , test "something else becoming current, or the player closing, changes the selection generation" <|
                \_ ->
                    let
                        generation : AudioPlayerPanel.Model -> Int
                        generation =
                            .selectionGeneration
                    in
                    Expect.all
                        [ \m -> play (AudioPlayerPanel.Open [ track "x" ] "x" "rellm.org") m |> generation |> Expect.notEqual (generation m)
                        , \m -> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) m |> generation |> Expect.notEqual (generation m)
                        , \m -> play AudioPlayerPanel.Close m |> generation |> Expect.notEqual (generation m)
                        , \m -> play AudioPlayerPanel.TogglePlay m |> generation |> Expect.equal (generation m)
                        , \m -> play (AudioPlayerPanel.VideoState True 1 2) m |> generation |> Expect.equal (generation m)
                        ]
                        withTracks
            ]
        , describe "#video- links (a video on one of our servers, like #track- for a track)"
            [ test "parse like track links, and are not track links" <|
                \_ ->
                    Expect.all
                        [ \_ -> AudioPlayerPanel.videoLinkFromFragment (Just "video-abc") |> Expect.equal (Just { id = "abc", host = Nothing })
                        , \_ -> AudioPlayerPanel.videoLinkFromFragment (Just "video-abc@other.example") |> Expect.equal (Just { id = "abc", host = Just "other.example" })
                        , \_ -> AudioPlayerPanel.videoLinkFromFragment (Just "video-") |> Expect.equal Nothing
                        , \_ -> AudioPlayerPanel.videoLinkFromFragment (Just "track-abc") |> Expect.equal Nothing
                        , \_ -> AudioPlayerPanel.trackLinkFromFragment (Just "video-abc") |> Expect.equal Nothing
                        , \_ -> AudioPlayerPanel.videoLinkFromFragment Nothing |> Expect.equal Nothing
                        , \_ -> AudioPlayerPanel.isLinkFragment (Just "video-abc") |> Expect.equal True
                        , \_ -> AudioPlayerPanel.isLinkFragment (Just "track-abc") |> Expect.equal True
                        , \_ -> AudioPlayerPanel.isLinkFragment (Just "comments") |> Expect.equal False
                        ]
                        ()
            , test "videoFragment names the server only when it isn't the one the app was opened on" <|
                \_ ->
                    ( AudioPlayerPanel.videoFragment "rellm.org" "rellm.org" "abc", AudioPlayerPanel.videoFragment "rellm.org" "other.example" "abc" )
                        |> Expect.equal ( "video-abc", "video-abc@other.example" )
            , test "linkFragment: a video on one of our servers links to itself, a URL-only video has no link, a track keeps #track-" <|
                \_ ->
                    let
                        ours : VideoItem
                        ours =
                            { src = "https://other.example/media/v1?authorization=x", poster = Nothing, aspectRatio = 1, returnUrl = "", mediaId = Just "v1", host = "other.example", downloads = [ "original" ] }
                    in
                    Expect.all
                        [ \_ -> play (AudioPlayerPanel.OpenVideo ours Nothing 0 True) AudioPlayerPanel.init |> AudioPlayerPanel.linkFragment "rellm.org" |> Expect.equal (Just "video-v1@other.example")
                        , \_ -> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) AudioPlayerPanel.init |> AudioPlayerPanel.linkFragment "rellm.org" |> Expect.equal Nothing
                        , \_ -> AudioPlayerPanel.linkFragment "rellm.org" AudioPlayerPanel.init |> Expect.equal Nothing
                        , \_ -> play (AudioPlayerPanel.Open [ track "a" ] "a" "rellm.org") AudioPlayerPanel.init |> AudioPlayerPanel.linkFragment "rellm.org" |> Expect.equal (Just "track-a")
                        ]
                        ()
            , test "enlarging a Rellm video (the viewer is handed just its URL) keeps its server and download sizes from the queue's entry" <|
                \_ ->
                    let
                        ours : VideoItem
                        ours =
                            { src = "https://other.example/media/v1?authorization=x", poster = Nothing, aspectRatio = 1, returnUrl = "", mediaId = Just "v1", host = "other.example", downloads = [ "small", "original" ] }

                        playing : AudioPlayerPanel.Model
                        playing =
                            play (AudioPlayerPanel.OpenVideo ours Nothing 0 True) AudioPlayerPanel.init

                        bare : VideoItem
                        bare =
                            { ours | host = "", downloads = [] }
                    in
                    Expect.all
                        [ \_ -> AudioPlayerPanel.inheritLinkData playing bare |> Expect.equal ours
                        , \_ -> AudioPlayerPanel.inheritLinkData playing { bare | src = "https://elsewhere/v2" } |> Expect.equal { bare | src = "https://elsewhere/v2" }
                        , \_ -> AudioPlayerPanel.inheritLinkData AudioPlayerPanel.init bare |> Expect.equal bare
                        , \_ -> AudioPlayerPanel.inheritLinkData playing { ours | host = "mine.example" } |> Expect.equal { ours | host = "mine.example" }
                        ]
                        ()
            , test "a link still waiting for its server is dropped when the user starts something else or closes the player" <|
                \_ ->
                    let
                        waiting : AudioPlayerPanel.Model
                        waiting =
                            let
                                base : AudioPlayerPanel.Model
                                base =
                                    AudioPlayerPanel.init
                            in
                            { base | pendingTrackLink = Just { id = "t", host = Nothing }, pendingVideoLink = Just { id = "v", host = Nothing } }

                        pending : AudioPlayerPanel.Model -> ( Bool, Bool )
                        pending m =
                            ( m.pendingTrackLink /= Nothing, m.pendingVideoLink /= Nothing )
                    in
                    Expect.all
                        [ \_ -> pending waiting |> Expect.equal ( True, True )
                        , \_ -> play (AudioPlayerPanel.Open [ track "x" ] "x" "rellm.org") waiting |> pending |> Expect.equal ( False, False )
                        , \_ -> play (AudioPlayerPanel.OpenVideo (clip "https://v/1") Nothing 0 True) waiting |> pending |> Expect.equal ( False, False )
                        , \_ -> play AudioPlayerPanel.Close waiting |> pending |> Expect.equal ( False, False )
                        ]
                        ()
            , test "pendingLink says which kind of link is waiting, and the prompt's dismiss forgets it" <|
                \_ ->
                    let
                        base : AudioPlayerPanel.Model
                        base =
                            AudioPlayerPanel.init

                        link : { id : String, host : Maybe String }
                        link =
                            { id = "x", host = Just "other.example" }
                    in
                    Expect.all
                        [ \_ -> AudioPlayerPanel.pendingLink base |> Expect.equal Nothing
                        , \_ -> AudioPlayerPanel.pendingLink { base | pendingTrackLink = Just link } |> Expect.equal (Just ( "track", link ))
                        , \_ -> AudioPlayerPanel.pendingLink { base | pendingVideoLink = Just link } |> Expect.equal (Just ( "video", link ))
                        , \_ -> play AudioPlayerPanel.LinkPromptDismissed { base | pendingVideoLink = Just link } |> AudioPlayerPanel.pendingLink |> Expect.equal Nothing
                        ]
                        ()
            , test "LoadVideo makes it the current video, paused, with the player expanded" <|
                \_ ->
                    let
                        loaded : AudioPlayerPanel.Model
                        loaded =
                            play (AudioPlayerPanel.LoadVideo (clip "https://v/1") (Just "A clip")) withTracks
                    in
                    Expect.all
                        [ .currentId >> Expect.equal (Just "https://v/1")
                        , .expanded >> Expect.equal True
                        , .playing >> Expect.equal False
                        , \m -> AudioPlayerPanel.currentVideo m |> Maybe.map (\c -> c.resume) |> Expect.equal (Just False)
                        , queued >> List.head >> Expect.equal (Just "https://v/1")
                        ]
                        loaded
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
