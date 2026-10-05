module DragTests exposing (suite)

{-| The pure part of `UI.Drag`: which slot a pointer position maps to (`targetOrder`) and sorting a
list into a key order (`reorderByKeys`). The pointer events/animation themselves are DOM-bound; check
those in a browser (see the run-elm skill).
-}

import Dict
import Expect
import Test exposing (Test, describe, test)
import UI.Drag
import UI.Flip exposing (Axis(..))


{-| Four 50px-tall, 100px-wide rows stacked from y = 100 (midlines 125, 175, 225, 275), and the same
four laid out along x from x = 100 (midlines 150, 250, 350, 450).
-}
columnRects : Dict.Dict String UI.Flip.Rect
columnRects =
    [ "a", "b", "c", "d" ]
        |> List.indexedMap (\i key -> ( key, { x = 0, y = 100 + 50 * toFloat i, width = 100, height = 50 } ))
        |> Dict.fromList


rowRects : Dict.Dict String UI.Flip.Rect
rowRects =
    [ "a", "b", "c", "d" ]
        |> List.indexedMap (\i key -> ( key, { x = 100 + 100 * toFloat i, y = 0, width = 100, height = 50 } ))
        |> Dict.fromList


keys : List String
keys =
    [ "a", "b", "c", "d" ]


anyGroup : String -> String
anyGroup _ =
    ""


vertical : String -> Float -> List String
vertical key pointer =
    UI.Drag.targetOrder Vertical anyGroup key pointer columnRects Dict.empty keys


suite : Test
suite =
    describe "UI.Drag"
        [ describe "targetOrder (vertical)"
            [ test "pointer still over its own row is a no-op" <|
                \_ -> vertical "b" 170 |> Expect.equal keys
            , test "dragging down past several midlines jumps several slots" <|
                \_ -> vertical "a" 240 |> Expect.equal [ "b", "c", "a", "d" ]
            , test "dragging below the last row moves to the end" <|
                \_ -> vertical "a" 900 |> Expect.equal [ "b", "c", "d", "a" ]
            , test "dragging up past several midlines jumps several slots" <|
                \_ -> vertical "d" 130 |> Expect.equal [ "a", "d", "b", "c" ]
            , test "dragging above the first row moves to the front" <|
                \_ -> vertical "c" -50 |> Expect.equal [ "c", "a", "b", "d" ]
            , test "pointer just short of a neighbor's midline doesn't pass it" <|
                \_ -> vertical "a" 174 |> Expect.equal keys
            , test "layout position wins over the (possibly mid-slide) measured one" <|
                \_ ->
                    -- `b` is visibly mid-slide down at y = 400, but its layout slot is still y = 150.
                    UI.Drag.targetOrder Vertical
                        anyGroup
                        "a"
                        200
                        (Dict.insert "b" { x = 0, y = 400, width = 100, height = 50 } columnRects)
                        (Dict.fromList [ ( "b", 150 ) ])
                        keys
                        |> Expect.equal [ "b", "a", "c", "d" ]
            , test "rows missing from the measurement are never passed" <|
                \_ ->
                    UI.Drag.targetOrder Vertical anyGroup "a" 900 (Dict.remove "c" columnRects) Dict.empty keys
                        |> Expect.equal [ "b", "c", "a", "d" ]
            , test "an unknown key leaves the order alone" <|
                \_ -> vertical "zzz" 900 |> Expect.equal keys
            ]
        , describe "targetOrder (horizontal)"
            [ test "compares the pointer's x against midlines along x" <|
                \_ ->
                    UI.Drag.targetOrder Horizontal anyGroup "a" 360 rowRects Dict.empty keys
                        |> Expect.equal [ "b", "c", "a", "d" ]
            , test "y position is irrelevant" <|
                \_ ->
                    UI.Drag.targetOrder Horizontal anyGroup "d" 120 columnRects Dict.empty keys
                        |> Expect.equal keys
            ]
        , describe "targetOrder (groups)"
            [ test "an item never passes members of another group" <|
                \_ ->
                    -- `a` is pinned (its own group); `b`, `c`, `d` are movable. Dragging `b` above `a`'s
                    -- midline can't put it ahead of `a`.
                    UI.Drag.targetOrder Vertical pinnedA "b" -50 columnRects Dict.empty keys
                        |> Expect.equal keys
            , test "movable items still reshuffle among their own slots" <|
                \_ ->
                    UI.Drag.targetOrder Vertical pinnedA "b" 900 columnRects Dict.empty keys
                        |> Expect.equal [ "a", "c", "d", "b" ]
            , test "a group's slots can be interleaved with other groups' items" <|
                \_ ->
                    -- Groups x,y,x,y: dragging the first x to the end swaps it with the other x only.
                    UI.Drag.targetOrder Vertical
                        (\k ->
                            if k == "a" || k == "c" then
                                "x"

                            else
                                "y"
                        )
                        "a"
                        900
                        columnRects
                        Dict.empty
                        keys
                        |> Expect.equal [ "c", "b", "a", "d" ]
            ]
        , describe "slotRange"
            [ test "is the span between the neighbors' midpoints the pointer sits between" <|
                \_ ->
                    -- Column midlines: a 125, b 175, c 225, d 275. Dragging `a` with the pointer at 200 sits
                    -- between b and c.
                    UI.Drag.slotRange Vertical anyGroup "a" 200 columnRects Dict.empty keys
                        |> Expect.equal ( 175, 225 )
            , test "is open-ended before the first and after the last neighbor" <|
                \_ ->
                    ( UI.Drag.slotRange Vertical anyGroup "d" 0 columnRects Dict.empty keys |> Tuple.first |> isInfinite
                    , UI.Drag.slotRange Vertical anyGroup "a" 900 columnRects Dict.empty keys |> Tuple.second |> isInfinite
                    )
                        |> Expect.equal ( True, True )
            , test "agrees with targetOrder: a pointer inside the range leaves the order alone" <|
                \_ ->
                    let
                        ( low, high ) =
                            UI.Drag.slotRange Vertical anyGroup "a" 200 columnRects Dict.empty keys

                        orderAt : Float -> List String
                        orderAt pointer =
                            UI.Drag.targetOrder Vertical anyGroup "a" pointer columnRects Dict.empty [ "b", "a", "c", "d" ]
                    in
                    [ low + 0.5, 200, high ]
                        |> List.map orderAt
                        |> Expect.equal (List.repeat 3 [ "b", "a", "c", "d" ])
            , test "ignores items of other groups" <|
                \_ ->
                    -- `a` is pinned, so `b`'s only neighbors are c (225) and d (275).
                    UI.Drag.slotRange Vertical pinnedA "b" 200 columnRects Dict.empty keys
                        |> Tuple.second
                        |> Expect.equal 225
            ]
        , describe "reorderByKeys"
            [ test "sorts items into the key order" <|
                \_ ->
                    UI.Drag.reorderByKeys identity [ "c", "a", "b" ] [ "a", "b", "c" ]
                        |> Expect.equal [ "c", "a", "b" ]
            , test "items the order doesn't mention keep their relative order, at the end" <|
                \_ ->
                    UI.Drag.reorderByKeys identity [ "c" ] [ "a", "b", "c", "d" ]
                        |> Expect.equal [ "c", "a", "b", "d" ]
            ]
        ]


pinnedA : String -> String
pinnedA k =
    if k == "a" then
        "pinned"

    else
        "free"
