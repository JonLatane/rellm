module RecurrenceTests exposing (suite)

{-| Tests for `Shared.Time.addRecurrence` (the "Add More" recurrence math used by
`Components.Pages.EventPage`) and `Shared.Time.nthWeekdayLabel`, including the
`MonthlyNthWeekday` ("2nd Tuesdays") unit.
-}

import Expect
import Shared.Time as SharedTime exposing (RecurrenceUnit(..))
import Test exposing (Test, describe, test)
import Time


{-| `"2026-10-13T18:00"` -> `Posix`, in `zone`.
-}
at : Time.Zone -> String -> Time.Posix
at zone raw =
    SharedTime.posixFromDateTimeLocalInput zone raw
        |> Maybe.withDefault (Time.millisToPosix 0)


{-| `addRecurrence` result, rendered back as the same `datetime-local` string.
-}
recur : Time.Zone -> RecurrenceUnit -> Int -> String -> String
recur zone unit n raw =
    SharedTime.addRecurrence zone unit n (at zone raw)
        |> SharedTime.formatDateTimeLocalInput zone


suite : Test
suite =
    describe "Shared.Time recurrence"
        [ describe "addRecurrence"
            [ test "Daily adds whole days across a month boundary" <|
                \_ -> recur Time.utc Daily 3 "2026-10-30T18:00" |> Expect.equal "2026-11-02T18:00"
            , test "Weekly adds 7-day steps" <|
                \_ -> recur Time.utc Weekly 2 "2026-10-13T18:00" |> Expect.equal "2026-10-27T18:00"
            , test "Monthly keeps the day of month" <|
                \_ -> recur Time.utc Monthly 1 "2026-10-13T18:00" |> Expect.equal "2026-11-13T18:00"
            , test "Monthly clamps to the end of a shorter month" <|
                \_ -> recur Time.utc Monthly 1 "2026-01-31T18:00" |> Expect.equal "2026-02-28T18:00"
            , test "Monthly rolls over the year" <|
                \_ -> recur Time.utc Monthly 3 "2026-11-15T18:00" |> Expect.equal "2027-02-15T18:00"
            ]
        , describe "addRecurrence MonthlyNthWeekday"
            [ test "2nd Tuesday -> next month's 2nd Tuesday" <|
                \_ -> recur Time.utc MonthlyNthWeekday 1 "2026-10-13T18:00" |> Expect.equal "2026-11-10T18:00"
            , test "2nd Tuesday, two months out" <|
                \_ -> recur Time.utc MonthlyNthWeekday 2 "2026-10-13T18:00" |> Expect.equal "2026-12-08T18:00"
            , test "rolls over the year" <|
                \_ -> recur Time.utc MonthlyNthWeekday 3 "2026-10-13T18:00" |> Expect.equal "2027-01-12T18:00"
            , test "1st Thursday lands on the 1st when the month starts on a Thursday" <|
                \_ -> recur Time.utc MonthlyNthWeekday 11 "2026-10-01T18:00" |> Expect.equal "2027-09-02T18:00"
            , test "5th Thursday falls back to the last Thursday when the month has only 4" <|
                \_ -> recur Time.utc MonthlyNthWeekday 1 "2026-10-29T18:00" |> Expect.equal "2026-11-26T18:00"
            , test "5th Thursday stays a 5th Thursday when the month has one" <|
                \_ -> recur Time.utc MonthlyNthWeekday 2 "2026-10-29T18:00" |> Expect.equal "2026-12-31T18:00"
            , test "keeps the local time of day" <|
                \_ -> recur Time.utc MonthlyNthWeekday 1 "2026-10-13T06:45" |> Expect.equal "2026-11-10T06:45"
            , test "uses the weekday in the given zone, not UTC" <|
                \_ ->
                    -- 2026-10-14T02:00Z is Tuesday Oct 13, 9PM in UTC-5.
                    let
                        zone : Time.Zone
                        zone =
                            Time.customZone (-5 * 60) []
                    in
                    recur zone MonthlyNthWeekday 1 "2026-10-13T21:00" |> Expect.equal "2026-11-10T21:00"
            ]
        , describe "nthWeekdayLabel"
            [ test "1st" <|
                \_ -> SharedTime.nthWeekdayLabel Time.utc (at Time.utc "2026-10-01T18:00") |> Expect.equal "1st Thursday"
            , test "2nd" <|
                \_ -> SharedTime.nthWeekdayLabel Time.utc (at Time.utc "2026-10-13T18:00") |> Expect.equal "2nd Tuesday"
            , test "3rd" <|
                \_ -> SharedTime.nthWeekdayLabel Time.utc (at Time.utc "2026-10-21T18:00") |> Expect.equal "3rd Wednesday"
            , test "4th" <|
                \_ -> SharedTime.nthWeekdayLabel Time.utc (at Time.utc "2026-10-22T18:00") |> Expect.equal "4th Thursday"
            , test "5th" <|
                \_ -> SharedTime.nthWeekdayLabel Time.utc (at Time.utc "2026-10-29T18:00") |> Expect.equal "5th Thursday"
            , test "is computed in the given zone" <|
                \_ ->
                    -- 2026-10-14T02:00Z: Wednesday in UTC, but Tuesday Oct 13 in UTC-5.
                    let
                        posix : Time.Posix
                        posix =
                            Time.millisToPosix 1791943200000
                    in
                    Expect.equal
                        [ SharedTime.nthWeekdayLabel Time.utc posix
                        , SharedTime.nthWeekdayLabel (Time.customZone (-5 * 60) []) posix
                        ]
                        [ "2nd Wednesday", "2nd Tuesday" ]
            ]
        ]
