module ConversionsTests exposing (suite)

{-| Regression tests for `Shared.Conversions.int64FromInt`/`int64ToInt` -- specifically the
multi-gigabyte-scale round trip that used to silently wrap (see `int64FromInt`'s own doc for the
bug this guards against: a naive `Int64.fromInts 0 value` truncates any value at or above 2^32).
-}

import Expect
import Shared.Conversions exposing (int64FromInt, int64ToInt)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Shared.Conversions.int64FromInt / int64ToInt"
        [ test "round-trips a small value (well under 2^32)" <|
            \_ ->
                (1024 * 1024)
                    |> int64FromInt
                    |> int64ToInt
                    |> Expect.equal (1024 * 1024)
        , test "round-trips exactly 4GB (2^32, the boundary the bug wrapped at)" <|
            \_ ->
                (1024 * 1024 * 1024 * 4)
                    |> int64FromInt
                    |> int64ToInt
                    |> Expect.equal (1024 * 1024 * 1024 * 4)
        , test "round-trips 5GB (previously silently became 1GB)" <|
            \_ ->
                (1024 * 1024 * 1024 * 5)
                    |> int64FromInt
                    |> int64ToInt
                    |> Expect.equal (1024 * 1024 * 1024 * 5)
        , test "round-trips 100GB (a plausible real Rellm-hosting DB/object storage allocation)" <|
            \_ ->
                (1024 * 1024 * 1024 * 100)
                    |> int64FromInt
                    |> int64ToInt
                    |> Expect.equal (1024 * 1024 * 1024 * 100)
        ]
