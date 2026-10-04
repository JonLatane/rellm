module StarredPanelDragTests exposing (suite)

{-| The pure parts of drag-to-reorder in `Shared.StarredPanel`: which slot a pointer position maps to
(`dragTargetOrder`) and decoding the transform-free `layoutY`s (`layoutYs`) that let a new move start
while an earlier slide is still running. The pointer events/animation themselves are DOM-bound; check
those in a browser (see the run-elm skill).
-}

import Dict
import Expect
import Json.Decode as Decode
import Shared.StarredPanel as StarredPanel
import Test exposing (Test, describe, test)
import UI.Flip


{-| Four 50px-tall rows stacked from y = 100: midlines at 125, 175, 225, 275.
-}
rects : Dict.Dict String UI.Flip.Rect
rects =
    [ "a", "b", "c", "d" ]
        |> List.indexedMap (\i key -> ( key, { x = 0, y = 100 + 50 * toFloat i, width = 300, height = 50 } ))
        |> Dict.fromList


order : List String
order =
    [ "a", "b", "c", "d" ]


suite : Test
suite =
    describe "Shared.StarredPanel drag-to-reorder"
        [ describe "dragTargetOrder"
            [ test "pointer still over its own row is a no-op" <|
                \_ ->
                    StarredPanel.dragTargetOrder "b" 170 rects Dict.empty order
                        |> Expect.equal order
            , test "dragging down past several midlines jumps several slots" <|
                \_ ->
                    StarredPanel.dragTargetOrder "a" 240 rects Dict.empty order
                        |> Expect.equal [ "b", "c", "a", "d" ]
            , test "dragging below the last row moves to the end" <|
                \_ ->
                    StarredPanel.dragTargetOrder "a" 900 rects Dict.empty order
                        |> Expect.equal [ "b", "c", "d", "a" ]
            , test "dragging up past several midlines jumps several slots" <|
                \_ ->
                    StarredPanel.dragTargetOrder "d" 130 rects Dict.empty order
                        |> Expect.equal [ "a", "d", "b", "c" ]
            , test "dragging above the first row moves to the front" <|
                \_ ->
                    StarredPanel.dragTargetOrder "c" -50 rects Dict.empty order
                        |> Expect.equal [ "c", "a", "b", "d" ]
            , test "pointer just short of a neighbor's midline doesn't pass it" <|
                \_ ->
                    StarredPanel.dragTargetOrder "a" 174 rects Dict.empty order
                        |> Expect.equal order
            , test "layout y wins over the (possibly mid-slide) measured y" <|
                \_ ->
                    -- `b` is visibly mid-slide down at y = 400, but its layout slot is still y = 150.
                    StarredPanel.dragTargetOrder "a"
                        200
                        (Dict.insert "b" { x = 0, y = 400, width = 300, height = 50 } rects)
                        (Dict.fromList [ ( "b", 150 ) ])
                        order
                        |> Expect.equal [ "b", "a", "c", "d" ]
            , test "rows missing from the measurement are never passed" <|
                \_ ->
                    StarredPanel.dragTargetOrder "a" 900 (Dict.remove "c" rects) Dict.empty order
                        |> Expect.equal [ "b", "c", "a", "d" ]
            ]
        , describe "layoutYs"
            [ test "reads each measured row's layoutY by key" <|
                \_ ->
                    Decode.decodeString Decode.value
                        """[{"key":"a","x":0,"y":10,"layoutY":4,"width":1,"height":1},{"key":"b","x":0,"y":20,"layoutY":20,"width":1,"height":1}]"""
                        |> Result.map StarredPanel.layoutYs
                        |> Expect.equal (Ok (Dict.fromList [ ( "a", 4 ), ( "b", 20 ) ]))
            , test "falls back to empty when the field is absent" <|
                \_ ->
                    Decode.decodeString Decode.value """[{"key":"a","x":0,"y":10,"width":1,"height":1}]"""
                        |> Result.map StarredPanel.layoutYs
                        |> Expect.equal (Ok Dict.empty)
            ]
        ]
