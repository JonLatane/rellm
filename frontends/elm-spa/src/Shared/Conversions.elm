module Shared.Conversions exposing (daysFromCivil, int64FromInt, int64ToInt, isoUtcString, monthToNumber, parseDateParts, parseTimeParts, posixFromIsoUtcString, posixToTimestamp, timestampToPosix)

import Protobuf.Types.Int64 as Int64
import Time


{-| Converts a protobuf `Timestamp` (seconds + nanos) to `Time.Posix` --
usable for any protobuf timestamp field (e.g. `ExpirableToken.expiresAt`,
`Post.publishedAt`/`.createdAt`), not just token expirations.
-}
timestampToPosix : { seconds : Int64.Int64, nanos : Int } -> Time.Posix
timestampToPosix timestamp =
    Time.millisToPosix (int64ToInt timestamp.seconds * 1000 + timestamp.nanos // 1000000)


{-| The inverse of `timestampToPosix` -- needed to send a `Time.Posix` (e.g.
`Time.now`) back out as a protobuf `Timestamp` field, like
`Components.Events.fetchEvents`' `TimeFilter.endsAfter`. `Int64.fromInts 0 seconds`
is safe until the seconds count itself overflows a 32-bit int (year 2038),
the same limitation `int64ToInt` already has on the decode side.
-}
posixToTimestamp : Time.Posix -> { seconds : Int64.Int64, nanos : Int }
posixToTimestamp posix =
    { seconds = Int64.fromInts 0 (Time.posixToMillis posix // 1000), nanos = 0 }


{-| The inverse of `int64ToInt` -- correct for any non-negative value up to Elm's own `Int`
precision limit (2^53, since `Int` is a JS float under the hood -- vastly more than any real
64-bit protobuf field this app builds one from needs, e.g. `Components.Market`'s byte/token counts
or `Components.Pages.UserProfilePage`'s Sync Source `syncIntervalSeconds`). Splits `value` into
`Int64`'s two signed-32-bit halves the same way `int64ToInt` recombines them (`high * 2^32 +
unsignedLow`) -- unlike a naive `Int64.fromInts 0 value`, which silently wraps (not errors) for
any `value` at or above 2^32 (4GB), since `Int64.fromInts`'s low half is only ever guaranteed to
hold `-2^31 .. 2^31 - 1`. Caught by a real `productSummary` test case (a 5GB Rellm-hosting object
storage allocation silently became 1GB) -- exactly the scale of value this function is actually fed today.
-}
int64FromInt : Int -> Int64.Int64
int64FromInt value =
    let
        high : Int
        high =
            value // 4294967296

        unsignedLow : Int
        unsignedLow =
            value - high * 4294967296

        low : Int
        low =
            if unsignedLow >= 2147483648 then
                unsignedLow - 4294967296

            else
                unsignedLow
    in
    Int64.fromInts high low


int64ToInt : Int64.Int64 -> Int
int64ToInt value =
    let
        ( high, low ) =
            Int64.toInts value

        unsignedLow : Int
        unsignedLow =
            if low < 0 then
                low + 4294967296

            else
                low
    in
    high * 4294967296 + unsignedLow



-- CALENDAR MATH


{-| Gregorian proleptic day count since 1970-01-01 for a given `(year, month
1-12, day)` -- Howard Hinnant's well-known `days_from_civil` algorithm,
correct (including negative/BC years and leap years) without needing a full
calendar library. The building block both `isoUtcString`'s inverse
(`posixFromIsoUtcString`) and `Shared.Time.posixFromDateTimeLocalInput`
need: `elm/time` only goes the other direction (a `Posix` instant to its
calendar components, via `Time.toYear`/etc.), with no built-in inverse.
-}
daysFromCivil : Int -> Int -> Int -> Int
daysFromCivil year month day =
    let
        y : Int
        y =
            if month <= 2 then
                year - 1

            else
                year

        era : Int
        era =
            (if y >= 0 then
                y

             else
                y - 399
            )
                // 400

        yoe : Int
        yoe =
            y - era * 400

        doy : Int
        doy =
            (153
                * (if month > 2 then
                    month - 3

                   else
                    month + 9
                  )
                + 2
            )
                // 5
                + day
                - 1

        doe : Int
        doe =
            yoe * 365 + yoe // 4 - yoe // 100 + doy
    in
    era * 146097 + doe - 719468


monthToNumber : Time.Month -> Int
monthToNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12


{-| `( year, month 1-12, day )`, from a `"YYYY-MM-DD"` string -- shared by
`posixFromIsoUtcString` and `Shared.Time.posixFromDateTimeLocalInput`,
both of which only differ in what follows the `"T"`.
-}
parseDateParts : String -> Maybe ( Int, Int, Int )
parseDateParts datePart =
    case String.split "-" datePart |> List.map String.toInt of
        [ Just y, Just m, Just d ] ->
            Just ( y, m, d )

        _ ->
            Nothing


{-| `( hour, minute, second )`, from a `"HH:mm"` or `"HH:mm:ss"` string
(seconds default to `0`) -- shared the same way `parseDateParts` is.
-}
parseTimeParts : String -> Maybe ( Int, Int, Int )
parseTimeParts timePart =
    case String.split ":" timePart |> List.map String.toInt of
        [ Just h, Just mi ] ->
            Just ( h, mi, 0 )

        [ Just h, Just mi, Just s ] ->
            Just ( h, mi, s )

        _ ->
            Nothing


{-| `YYYY-MM-DDTHH:mm:ssZ`, always UTC -- the URL-safe, timezone-independent
"standard ISO date" `Components.Pages.EventsPage`'s `ends_after` query param
uses (unlike `Shared.Time`'s local-datetime-input helpers, this
never needs a `Time.Zone` at all, since UTC's own offset is always zero, so
`daysFromCivil`'s result needs no correction).
-}
isoUtcString : Time.Posix -> String
isoUtcString time =
    let
        pad : Int -> Int -> String
        pad n width =
            String.padLeft width '0' (String.fromInt n)
    in
    pad (Time.toYear Time.utc time) 4
        ++ "-"
        ++ pad (monthToNumber (Time.toMonth Time.utc time)) 2
        ++ "-"
        ++ pad (Time.toDay Time.utc time) 2
        ++ "T"
        ++ pad (Time.toHour Time.utc time) 2
        ++ ":"
        ++ pad (Time.toMinute Time.utc time) 2
        ++ ":"
        ++ pad (Time.toSecond Time.utc time) 2
        ++ "Z"


{-| The inverse of `isoUtcString` -- parses `YYYY-MM-DDTHH:mm:ssZ` (the
trailing `Z` and the seconds both optional, so a hand-edited/shortened URL
still round-trips) back to a `Time.Posix`. `Nothing` for anything else --
this intentionally isn't a general ISO 8601 parser (no non-UTC offsets, no
fractional seconds), just enough for what this app's own `isoUtcString`
produces.
-}
posixFromIsoUtcString : String -> Maybe Time.Posix
posixFromIsoUtcString raw =
    let
        stripped : String
        stripped =
            if String.endsWith "Z" raw then
                String.dropRight 1 raw

            else
                raw
    in
    case String.split "T" stripped of
        [ datePart, timePart ] ->
            Maybe.map2
                (\( year, month, day ) ( hour, minute, second ) ->
                    Time.millisToPosix ((daysFromCivil year month day * 86400 + hour * 3600 + minute * 60 + second) * 1000)
                )
                (parseDateParts datePart)
                (parseTimeParts timePart)

        _ ->
            Nothing
