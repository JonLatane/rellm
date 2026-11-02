module PostsPagePagingTests exposing (suite)

{-| Tests for `Components.Pages.PostsPage.Paging` -- which loaded posts are safe to show while some source
still has pages to load, and the rendered window over them (growing at the bottom, dropping from the top
past `maxRendered`, coming back at the top).
-}

import Components.Pages.PostsPage.Paging as Paging exposing (Entry, Order(..), Window)
import Expect
import Test exposing (Test, describe, test)


entry : String -> Float -> Int -> Entry {}
entry key rank millis =
    { key = key, rank = rank, millis = millis }


{-| `n` keys "p0".."p(n-1)" -- stand-ins for the safe posts, in display order.
-}
keysOf : Int -> List String
keysOf n =
    List.range 0 (n - 1) |> List.map (\i -> "p" ++ String.fromInt i)


suite : Test
suite =
    describe "Components.Pages.PostsPage.Paging"
        [ ordering
        , safety
        , windowing
        ]


ordering : Test
ordering =
    describe "sortEntries"
        [ test "ByRecency is newest first" <|
            \_ ->
                [ entry "old" 0 100, entry "new" 5 300, entry "mid" 1 200 ]
                    |> Paging.sortEntries ByRecency
                    |> List.map .key
                    |> Expect.equal [ "new", "mid", "old" ]
        , test "ByRank is by rank, newest breaking ties" <|
            \_ ->
                [ entry "b" 0.5 100, entry "a-old" 0 100, entry "a-new" 0 900 ]
                    |> Paging.sortEntries ByRank
                    |> List.map .key
                    |> Expect.equal [ "a-new", "a-old", "b" ]
        ]


safety : Test
safety =
    let
        -- Newest first: two servers interleaved, "x" ones from one and "y" from the other.
        recent : List (Entry {})
        recent =
            [ entry "x1" 0 1000, entry "y1" 0 900, entry "x2" 0.5 800, entry "y2" 0.5 300, entry "x3" 1 100 ]
    in
    describe "safeEntries"
        [ test "everything is safe when no source has more to give" <|
            \_ ->
                Paging.safeEntries ByRecency [] recent
                    |> List.map .key
                    |> Expect.equal [ "x1", "y1", "x2", "y2", "x3" ]
        , test "by recency, nothing older than a source that has more pages is shown" <|
            \_ ->
                -- "y" has more, and its oldest loaded post is at 300: it may still owe posts at 250, so
                -- "x3" (100) must wait.
                Paging.safeEntries ByRecency [ { rank = 0.5, millis = 300 } ] recent
                    |> List.map .key
                    |> Expect.equal [ "x1", "y1", "x2", "y2" ]
        , test "by recency, the source that reaches least far decides" <|
            \_ ->
                -- Two unfinished sources, reaching back to 300 and 800: the newer bound (800) holds the list.
                Paging.safeEntries ByRecency [ { rank = 0, millis = 300 }, { rank = 0, millis = 800 } ] recent
                    |> List.map .key
                    |> Expect.equal [ "x1", "y1", "x2" ]
        , test "by rank, nothing ranked below a source that has more pages is shown" <|
            \_ ->
                Paging.safeEntries ByRank [ { rank = 0.5, millis = 0 }, { rank = 1, millis = 0 } ] recent
                    |> List.map .key
                    |> Expect.equal [ "x1", "y1", "x2", "y2" ]
        , test "frontierOf is the last post a source handed over, either way it is read" <|
            \_ ->
                Paging.frontierOf [ entry "a" 0 500, entry "b" 0.4 200, entry "c" 0.2 350 ]
                    |> Expect.equal (Just { rank = 0.4, millis = 200 })
        , test "a source with nothing loaded has no frontier" <|
            \_ ->
                Paging.frontierOf [] |> Expect.equal Nothing
        , test "only the source that holds the list back is binding" <|
            \_ ->
                let
                    reachesFar : Paging.Frontier
                    reachesFar =
                        { rank = 0.2, millis = 100 }

                    reachesLittle : Paging.Frontier
                    reachesLittle =
                        { rank = 0.9, millis = 800 }

                    frontiers : List Paging.Frontier
                    frontiers =
                        [ reachesFar, reachesLittle ]
                in
                [ Paging.isBinding ByRecency frontiers reachesLittle
                , Paging.isBinding ByRecency frontiers reachesFar
                , Paging.isBinding ByRank frontiers reachesFar
                , Paging.isBinding ByRank frontiers reachesLittle
                ]
                    |> Expect.equal [ True, False, True, False ]
        , test "nothing is binding when no source has more" <|
            \_ ->
                Paging.isBinding ByRecency [] { rank = 0, millis = 1 } |> Expect.equal False
        ]


windowing : Test
windowing =
    let
        window : Maybe String -> Int -> Window
        window start shown =
            { start = start, shown = shown }
    in
    describe "Window"
        [ test "starts at the top with a page's worth" <|
            \_ ->
                Paging.visible identity Paging.initialWindow (keysOf 80)
                    |> Expect.equal (keysOf Paging.revealStep)
        , test "revealing below shows another step" <|
            \_ ->
                Paging.visible identity (Paging.revealBelow Paging.initialWindow) (keysOf 80)
                    |> List.length
                    |> Expect.equal (2 * Paging.revealStep)
        , test "a wish bigger than what is loaded just shows what there is" <|
            \_ ->
                Paging.visible identity (window Nothing 90) (keysOf 30)
                    |> List.length
                    |> Expect.equal 30
        , test "how many are left below the window" <|
            \_ ->
                ( Paging.remainingBelow (keysOf 80) Paging.initialWindow
                , Paging.hasMoreBelow (keysOf 25) Paging.initialWindow
                , Paging.hasMoreBelow (keysOf 26) Paging.initialWindow
                )
                    |> Expect.equal ( 55, False, True )
        , test "under the cap, normalize changes nothing" <|
            \_ ->
                Paging.normalize (keysOf 200) (window Nothing Paging.maxRendered)
                    |> Expect.equal (window Nothing Paging.maxRendered)
        , test "past the cap, normalize drops the surplus from the top" <|
            \_ ->
                -- 125 wanted from the top: 25 too many, so it starts at p25 and shows 100.
                Paging.normalize (keysOf 200) (window Nothing 125)
                    |> Expect.equal (window (Just "p25") 100)
        , test "dropping from the top keeps going from where the window already starts" <|
            \_ ->
                Paging.normalize (keysOf 300) (window (Just "p25") 125)
                    |> Expect.equal (window (Just "p50") 100)
        , test "a wish that outruns the loaded posts does not trim until they arrive" <|
            \_ ->
                -- Only 100 loaded: 125 wanted, but nothing beyond 100 is rendered yet.
                Paging.normalize (keysOf 100) (window Nothing 125)
                    |> Expect.equal (window Nothing 125)
        , test "...and trims once they do" <|
            \_ ->
                Paging.normalize (keysOf 125) (window Nothing 125)
                    |> Expect.equal (window (Just "p25") 100)
        , test "the rendered posts follow the start post when new posts arrive above it" <|
            \_ ->
                let
                    before : List String
                    before =
                        keysOf 200

                    after : List String
                    after =
                        "new" :: before

                    w : Window
                    w =
                        window (Just "p25") 100
                in
                ( Paging.visible identity w before |> List.head
                , Paging.visible identity w after |> List.head
                )
                    |> Expect.equal ( Just "p25", Just "p25" )
        , test "a start post that has left the list starts the window over from the top" <|
            \_ ->
                Paging.normalize (keysOf 50) (window (Just "gone") 25)
                    |> Expect.equal (window Nothing 25)
        , test "scrolling up brings back a step of posts" <|
            \_ ->
                -- Starting at p50, 100 shown: back up to p25, and 125 would be on screen -- capped to 100.
                Paging.revealAbove (keysOf 300) (window (Just "p50") 100)
                    |> Expect.equal (window (Just "p25") 100)
        , test "...but only as many as were dropped" <|
            \_ ->
                Paging.revealAbove (keysOf 300) (window (Just "p10") 60)
                    |> Expect.equal (window Nothing 70)
        , test "whether anything is above" <|
            \_ ->
                ( Paging.hasHiddenAbove (keysOf 100) Paging.initialWindow
                , Paging.hasHiddenAbove (keysOf 100) (window (Just "p25") 50)
                )
                    |> Expect.equal ( False, True )
        , test "dropping then restoring gets the same posts back" <|
            \_ ->
                let
                    keys : List String
                    keys =
                        keysOf 300

                    down : Window
                    down =
                        Paging.normalize keys (window Nothing 125)

                    back : Window
                    back =
                        Paging.revealAbove keys down
                in
                ( Paging.visible identity down keys |> List.head
                , Paging.visible identity back keys |> List.head
                )
                    |> Expect.equal ( Just "p25", Just "p0" )
        ]
