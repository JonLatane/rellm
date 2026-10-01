module MediaPagesTests exposing (suite)

import Components.MediaFeed as MediaFeed
import Components.Pages.MediaPage as MediaPage
import Dict
import Expect
import Proto.Rellm exposing (GetMediaRequest, Media, MediaMetadata, defaultMedia, defaultMediaMetadata, defaultMediaReference)
import Proto.Rellm.NavigationTab exposing (NavigationTab(..))
import Proto.Rellm.Visibility exposing (Visibility(..))
import Protobuf.Types.Int64 as Int64
import Shared.MediaViewerPanel as MediaViewerPanel
import Test exposing (Test, describe, test)
import UI.CustomNav as CustomNav


suite : Test
suite =
    describe "media pages"
        [ describe "MediaFeed.requestFor"
            [ test "videos use a video/* wildcard and no user_id (server-wide)" <|
                \_ ->
                    let
                        request : GetMediaRequest
                        request =
                            MediaFeed.requestFor MediaFeed.Videos "" 0
                    in
                    Expect.equal ( Just "video/*", Nothing, Nothing ) ( request.contentType, request.userId, request.searchText )
            , test "audio uses audio/*, trims search text and carries the page" <|
                \_ ->
                    let
                        request : GetMediaRequest
                        request =
                            MediaFeed.requestFor MediaFeed.Audio "  coltrane " 3
                    in
                    Expect.equal ( Just "audio/*", Just "coltrane", 3 ) ( request.contentType, request.searchText, request.page )
            , test "blank search text means no search" <|
                \_ ->
                    (MediaFeed.requestFor MediaFeed.Audio "   " 0).searchText |> Expect.equal Nothing
            ]
        , describe "MediaFeed.mergeByRecency"
            [ test "merges servers newest-first, keeping each item's host" <|
                \_ ->
                    let
                        at : Int -> Media
                        at seconds =
                            { defaultMedia | id = String.fromInt seconds, createdAt = Just { seconds = Int64.fromInts 0 seconds, nanos = 0 } }
                    in
                    MediaFeed.mergeByRecency [ ( "a.com", at 10 ), ( "b.com", at 30 ), ( "a.com", at 20 ) ]
                        |> List.map (\( host, media ) -> host ++ ":" ++ media.id)
                        |> Expect.equal [ "b.com:30", "a.com:20", "a.com:10" ]
            ]
        , describe "MediaFeed.creditsLine"
            [ test "audio shows artist and album" <|
                \_ ->
                    MediaFeed.creditsLine MediaFeed.Audio { defaultMediaMetadata | artist = Just "Miles Davis", album = Just "Kind of Blue", director = Just "ignored" }
                        |> Expect.equal "Miles Davis · Kind of Blue"
            , test "video shows director and starring, skipping blanks" <|
                \_ ->
                    MediaFeed.creditsLine MediaFeed.Videos { defaultMediaMetadata | director = Just "  ", starring = Just "Someone" }
                        |> Expect.equal "Someone"
            ]
        , describe "MediaPage tabs"
            [ test "?tab= round-trips, defaulting to video" <|
                \_ ->
                    [ MediaPage.VideoTab, MediaPage.AudioTab, MediaPage.MyMediaTab ]
                        |> List.map
                            (\tab ->
                                MediaPage.tabQueryValue tab
                                    |> Maybe.map (\v -> Dict.fromList [ ( "tab", v ) ])
                                    |> Maybe.withDefault Dict.empty
                                    |> MediaPage.tabFromQuery
                            )
                        |> Expect.equal [ MediaPage.VideoTab, MediaPage.AudioTab, MediaPage.MyMediaTab ]
            , test "an unknown ?tab= is video" <|
                \_ ->
                    MediaPage.tabFromQuery (Dict.fromList [ ( "tab", "nope" ) ]) |> Expect.equal MediaPage.VideoTab
            ]
        , describe "MediaViewerPanel.formatMs"
            [ test "formats minutes, seconds and tenths" <|
                \_ ->
                    List.map MediaViewerPanel.formatMs [ 0, 1500, 61200, 3599900 ]
                        |> Expect.equal [ "0:00.0", "0:01.5", "1:01.2", "59:59.9" ]
            ]
        , describe "MediaViewerPanel.metadataWithEdits"
            [ test "blank credits save as null, set ones are trimmed" <|
                \_ ->
                    let
                        edit : MediaViewerPanel.MediaEdit
                        edit =
                            blankEdit
                                |> (\e -> { e | credits = Dict.fromList [ ( "Artist", " Miles " ), ( "Album", "   " ) ] })

                        result : MediaMetadata
                        result =
                            MediaViewerPanel.metadataWithEdits True False edit { defaultMediaMetadata | album = Just "Old Album" }
                    in
                    Expect.equal ( Just "Miles", Nothing ) ( result.artist, result.album )
            , test "preview bounds are dropped for non-audio/video media" <|
                \_ ->
                    let
                        edit : MediaViewerPanel.MediaEdit
                        edit =
                            { blankEdit | unlicensedPreviewStartMs = Just 1000 }
                    in
                    (MediaViewerPanel.metadataWithEdits False False edit defaultMediaMetadata).unlicensedPreviewStartMs
                        |> Expect.equal Nothing
            , test "audio/video keep their preview bounds" <|
                \_ ->
                    let
                        result : MediaMetadata
                        result =
                            MediaViewerPanel.metadataWithEdits True True { blankEdit | unlicensedPreviewStartMs = Just 1000, unlicensedPreviewEndMs = Just 5000, videoPreviewTimeMs = Just 2500 } defaultMediaMetadata
                    in
                    Expect.equal ( Just 1000, Just 5000, Just 2500 )
                        ( Maybe.map Int64.toInts result.unlicensedPreviewStartMs |> Maybe.map Tuple.second
                        , Maybe.map Int64.toInts result.unlicensedPreviewEndMs |> Maybe.map Tuple.second
                        , Maybe.map Int64.toInts result.videoPreviewTimeMs |> Maybe.map Tuple.second
                        )
            ]
        , describe "MediaViewerPanel.freshEdit"
            [ test "seeds credits and visibility from the media, leaving unset credits out" <|
                \_ ->
                    let
                        edit : MediaViewerPanel.MediaEdit
                        edit =
                            MediaViewerPanel.freshEdit
                                { defaultMediaReference
                                    | visibility = LICENSED
                                    , metadata = Just { defaultMediaMetadata | artist = Just "Miles Davis" }
                                }
                    in
                    Expect.equal ( LICENSED, Dict.fromList [ ( "Artist", "Miles Davis" ) ], Nothing ) ( edit.visibility, edit.credits, edit.openBlankCredit )
            ]
        , describe "CustomNav tab kinds"
            [ test "Video, Audio and Media pages are offered after Posts and before People, in that order" <|
                \_ ->
                    CustomNav.selectableTargetKinds
                        |> List.take 6
                        |> List.map CustomNav.targetKindText
                        |> Expect.equal [ "Events Page", "Posts Page", "Video Page", "Audio Page", "Media Page", "People Page" ]
            , test "default paths" <|
                \_ ->
                    [ MEDIATAB, VIDEOTAB, AUDIOTAB ]
                        |> List.map (CustomNav.TargetTab >> CustomNav.defaultPathFor)
                        |> Expect.equal [ "media", "video", "audio" ]
            ]
        ]


blankEdit : MediaViewerPanel.MediaEdit
blankEdit =
    MediaViewerPanel.freshEdit defaultMediaReference
