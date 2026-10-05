module MediaViewerPanelTests exposing (suite)

import Dict
import Expect
import Proto.Rellm exposing (defaultMediaReference)
import Shared.MediaViewerPanel as MediaViewerPanel
import Test exposing (Test, describe, test)


{-| Mirrors `backend/src/tests/update_media_tests.rs`'s key/BPM validation specs -- the two must agree.
-}
suite : Test
suite =
    describe "MediaViewerPanel musical metadata validation"
        [ test "isValidKey accepts the documented forms" <|
            \_ ->
                [ "C#m", "DbM", "Db", "F", "Am", "B♭-", "F♯m", "E♭️M", "C＃", "D﹟m", "B", "Bb" ]
                    |> List.filter (not << MediaViewerPanel.isValidKey)
                    |> Expect.equal []
        , test "isValidKey rejects everything else, including double sharps/flats" <|
            \_ ->
                [ "", "H", "am", "db", "C##", "Cbb", "C♮", "A𝄪", "G𝄫m", "Dbb", "F♯♯", "Cmm", "C minor", " C", "C ", "Cx", "H#", "#C", "m", "C#M7" ]
                    |> List.filter MediaViewerPanel.isValidKey
                    |> Expect.equal []
        , test "parseBpm accepts fractions in (0, 999] and nothing else" <|
            \_ ->
                Expect.equal
                    [ Just 127.5, Just 999, Nothing, Nothing, Nothing, Nothing, Nothing ]
                    (List.map MediaViewerPanel.parseBpm [ "127.5", "999", "0", "-5", "1000", "fast", "" ])
        , test "fieldErrors flags a bad key, a bad BPM and min above max; blanks are fine" <|
            \_ ->
                let
                    edit : MediaViewerPanel.MediaEdit
                    edit =
                        MediaViewerPanel.freshEdit defaultMediaReference

                    errorsFor : List ( String, String ) -> List String
                    errorsFor credits =
                        { edit | credits = Dict.fromList credits }
                            |> MediaViewerPanel.fieldErrors
                            |> Dict.keys
                            |> List.sort
                in
                Expect.equal
                    [ [ "Start BPM", "Start Key" ]
                    , []
                    , [ "Min BPM" ]
                    ]
                    [ errorsFor [ ( "Start BPM", "0" ), ( "Start Key", "H" ), ( "End Key", "" ) ]
                    , errorsFor [ ( "Start BPM", " 120 " ), ( "End Key", "F♯m" ), ( "Max BPM", "" ) ]
                    , errorsFor [ ( "Min BPM", "130" ), ( "Max BPM", "120" ) ]
                    ]
        ]
