module Shared.Time exposing
    ( BrowserTimeZone
    , Model
    , RecurrenceUnit(..)
    , addRecurrence
    , formatDate
    , formatDateRange
    , formatDateTime
    , formatDateTimeLocalInput
    , formatMoment
    , formatRange
    , posixFromDateTimeLocalInput
    )

import Shared.Conversions as Conversions
import Time


{-| The app-wide notion of "when is it right now", from the viewer's own
point of view -- see `Shared.Model.time`.

`browserTimeZone` is used everywhere a `Post`/`User` timestamp is displayed
(see `formatDate`/`formatDateTime`/`formatMoment`/etc. below) so those
render in the viewer's own local time rather than the server's UTC.

`now` is captured once via `Time.now` in `Shared.init` (mirrors
`browserTimeZone.zone`'s own `getBrowserZone` capture exactly, including the
`Time.millisToPosix 0` placeholder until it resolves) -- the single app-wide
"now" every page that used to capture its own (`Pages.Event.PostId_`'s
date-picker strip categorizing `Occasion`s as upcoming/past,
`Components.Events.eventCard`/`instanceWhenText`'s "is this date in the
viewer's current year" check) reads instead, rather than each independently
re-running `Task.perform ... Time.now`. Deliberately _not_ kept live via a
`Time.every` tick -- every current use only needs "roughly what day/year is
it" for the length of a single page view, not a ticking clock, the same
tolerance `Pages.Event.PostId_.Model.now`'s own doc already accepted before
this moved here. `Components.Pages.EventsPage.Model.endsAfter`/
`Components.Pages.PostsPage.Model.publishedBefore` are deliberately
untouched by this -- those are live request cursors (polled and
user-editable), not a display "what time is it", and already document why
they're their own thing.

Bundled into one type, rather than `browserTimeZone`/`now` staying separate
`Shared.Model` fields, since almost every call site that needs one needs the
other too -- see `formatMoment`/`formatRange`/`formatDateRange` below, each
of which takes the pair together rather than as two separate arguments.
`formatDate`/`formatDateTime` (which only ever need `browserTimeZone`, not
`now`) keep taking `BrowserTimeZone`/`Time.Zone` alone rather than a full
`Model`, so callers that only have the timezone half (there are none today,
but nothing here should force one into existing) aren't forced to fabricate
a `now`.

-}
type alias Model =
    { browserTimeZone : BrowserTimeZone
    , now : Time.Posix
    }


{-| The browser's local timezone, plus its short display name (e.g. "EDT",
"GMT+2") and whether its locale renders a time of day in 24-hour form.
Bundled together since every call site that needs one of these tends to need
the others too -- see `Model.browserTimeZone`.

`zone`/`name` are both resolved via `Shared.getBrowserZone` once
`Shared.init`'s `Cmd` runs -- `Time.utc`/`""` until then (never visibly wrong
for long: the `Task` resolves on the same frame the app first renders).
Unlike plain `Time.here`, `getBrowserZone` is DST-aware (backed by
`justinmimbs/timezone-data`), so a timestamp far from "now" -- e.g. a
recurring `Occasion` on the other side of a DST transition -- still
converts with the offset that actually applied on _its_ date, not today's.
`name` is the actual IANA zone name (e.g. "America/New\_York") `zone` itself
was looked up by -- kept alongside it so a timezone _selector_
(`Shared.CreateNewPanel`/`Components.Pages.EventPage`'s `Occasion.timezone`
field) has a sensible default to preselect, since `Time.Zone` alone is just a
raw offset table with no name of its own. `""` if `elm/time`'s
`Time.getZoneName` couldn't read one (falls back to plain `Time.here`, which
has no name at all). `abbreviation`/`uses24Hour` both come from a different
source: unlike `zone`/`name`, `elm/time` has no way to derive either (again,
just a raw offset table, with no notion of a locale's formatting
conventions), so both are read once at startup from the browser's own `Intl`
API as plain flags (see `index.html`) rather than a port round-trip -- they
only matter at the instant a timestamp renders, same as `zone`, and aren't
worth keeping live across a session. `abbreviation` is `""` (never shown),
`uses24Hour` is `False`, if their respective `Intl` lookups fail for any
reason.

-}
type alias BrowserTimeZone =
    { zone : Time.Zone
    , name : String
    , abbreviation : String
    , uses24Hour : Bool
    }


{-| "Today"/"Yesterday"/"Tomorrow" -- the three relative-day labels
`dateLabel`/`rangeDateLabels` can prefix a date with.
-}
type RelativeDay
    = Today
    | Yesterday
    | Tomorrow


{-| A plain `YYYY-MM-DD` rendering of a timestamp in `zone` -- e.g. a
profile's "Joined" date. No existing date-formatting helper/locale
infrastructure exists in this app yet, so this keeps things simple rather
than introducing one. Takes a bare `Time.Zone` rather than a full
`BrowserTimeZone` since, unlike `formatDateTime`, it has no time-of-day
component for `abbreviation` to disambiguate.
-}
formatDate : Time.Zone -> Time.Posix -> String
formatDate zone time =
    let
        pad2 : Int -> String
        pad2 n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    String.fromInt (Time.toYear zone time)
        ++ "-"
        ++ pad2 (monthNumber (Time.toMonth zone time))
        ++ "-"
        ++ pad2 (Time.toDay zone time)


{-| `formatDate` plus an `HH:mm` (24-hour) suffix, both in `browserTimeZone`'s
`zone`, plus a trailing `abbreviation` (e.g. "EDT", `""` omits it) so the
reader can tell which zone `HH:mm` is in without guessing -- for timestamps
where the time of day actually matters but a human-friendly `formatMoment`
would be overkill (e.g. `Components.Pages.UserProfilePage`'s Sync Source last-synced time),
unlike a profile's plain "Joined" date.
-}
formatDateTime : BrowserTimeZone -> Time.Posix -> String
formatDateTime browserTimeZone time =
    let
        pad2 : Int -> String
        pad2 n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    formatDate browserTimeZone.zone time
        ++ " "
        ++ pad2 (Time.toHour browserTimeZone.zone time)
        ++ ":"
        ++ pad2 (Time.toMinute browserTimeZone.zone time)
        ++ (if browserTimeZone.abbreviation == "" then
                ""

            else
                " " ++ browserTimeZone.abbreviation
           )


{-| A human-friendly single point in time, e.g. "August 1, 6PM", "Today,
August 1, 6PM" (see `dateLabel`), or (24-hour) "August 1, 18:00" -- `time.now`
supplies the viewer's own "current year"/"current day", so `dateLabel` can
drop a redundant year or add a "Today"/"Yesterday"/"Tomorrow" prefix (see
its own doc). Used by `Components.Events.instanceWhenText` for an
`Occasion` with only a `startsAt` or only an `endsAt` (unusual --
normally both are set, see `formatRange`), and by `Components.Posts.whenText`
for a `Post`'s created/updated/published timestamps.
-}
formatMoment : Model -> Time.Posix -> String
formatMoment time moment =
    dateLabel time moment
        ++ ", "
        ++ timeOfDayLabel time.browserTimeZone moment


{-| A human-friendly span between two points in time -- the building block
behind `Components.Events.instanceWhenText`'s "August 1, 6-7PM" /
"June 1, 10PM - June 8, 3AM" / "December 31, 2025, 9PM - January 1, 2AM"
formatting (see that function's own doc for the full set of examples this is
designed against). `time.now` supplies the viewer's own "current year"/"current
day" so `dateLabel` can drop a redundant year, or add a
"Today"/"Yesterday"/"Tomorrow" prefix, on either side (see its own doc) --
except when that would print both "Today" and "Yesterday", or both "Today"
and "Tomorrow" (e.g. an overnight range from yesterday into today, or today
into tomorrow): since `start` is never later than `end`, those are the only
two relative-day pairings a two-sided range can ever produce, and stating
both is redundant once one side is already anchored as "Today" -- so the
non-"Today" side falls back to its plain `dateLabel` (see `rangeDateLabels`).

Same calendar day (in `time.browserTimeZone.zone`): a single `dateLabel`
followed by both times, merged onto one `-`-joined range (see
`timeRangeLabel`) -- e.g. "August 1, 6-7PM". Different days: each side gets
its own full `dateLabel`, e.g. "June 1, 10PM - June 8, 3AM" -- never merged,
since "August 1, 6 - September 2, 7PM" reads as if `7PM` alone told you
anything about `August 1`'s own time.

-}
formatRange : Model -> Time.Posix -> Time.Posix -> String
formatRange time start end =
    let
        zone : Time.Zone
        zone =
            time.browserTimeZone.zone

        sameDay : Bool
        sameDay =
            ( Time.toYear zone start, Time.toMonth zone start, Time.toDay zone start )
                == ( Time.toYear zone end, Time.toMonth zone end, Time.toDay zone end )
    in
    if sameDay then
        dateLabel time start
            ++ ", "
            ++ timeRangeLabel time.browserTimeZone start end

    else
        let
            ( startLabel, endLabel ) =
                rangeDateLabels time start end
        in
        startLabel
            ++ ", "
            ++ timeOfDayLabel time.browserTimeZone start
            ++ " - "
            ++ endLabel
            ++ ", "
            ++ timeOfDayLabel time.browserTimeZone end


{-| Like `formatRange`, but omits the time-of-day entirely -- just the
date(s), e.g. "August 1" (same day) or "June 1 - June 8" (different days).
Used by `Components.Events.siblingInstanceWhenText` to drop a redundant time
when a sibling `Occasion` shares its current instance's own
time-of-day (e.g. a weekly meetup that's always 6-7PM) -- only the date(s)
then distinguish one instance from another. Same "Today"/"Yesterday"/"Tomorrow"
handling (including the same-side suppression) as `formatRange` -- see its
own doc.
-}
formatDateRange : Model -> Time.Posix -> Time.Posix -> String
formatDateRange time start end =
    let
        zone : Time.Zone
        zone =
            time.browserTimeZone.zone

        sameDay : Bool
        sameDay =
            ( Time.toYear zone start, Time.toMonth zone start, Time.toDay zone start )
                == ( Time.toYear zone end, Time.toMonth zone end, Time.toDay zone end )
    in
    if sameDay then
        dateLabel time start

    else
        let
            ( startLabel, endLabel ) =
                rangeDateLabels time start end
        in
        startLabel ++ " - " ++ endLabel


{-| "MonthName Day", e.g. "August 1" -- plus a trailing ", Year" whenever
`moment`'s own year (in `time.browserTimeZone.zone`) isn't `time.now`'s (the
viewer's own "current year"), so a date within the viewer's current year
never carries the visual noise of a year nobody needs telling, while one
that isn't (a past event, or a New Year's Eve party's other end) still says
so plainly. Also prefixed "Today, "/"Yesterday, "/"Tomorrow, " (see
`relativeDay`) whenever `moment` falls on one of those three days relative
to `time.now` -- purely additive, e.g. "Today, August 3, 2026" rather than
replacing the date -- via `withRelativeDayPrefix`.
-}
dateLabel : Model -> Time.Posix -> String
dateLabel time moment =
    withRelativeDayPrefix (relativeDay time moment) (dateLabelBase time moment)


{-| `dateLabel` minus its "Today"/"Yesterday"/"Tomorrow" prefix -- split out
so `rangeDateLabels` can attach its own (possibly suppressed) relative-day
label instead of the one `moment` would get on its own.
-}
dateLabelBase : Model -> Time.Posix -> String
dateLabelBase time moment =
    let
        zone : Time.Zone
        zone =
            time.browserTimeZone.zone

        year : Int
        year =
            Time.toYear zone moment

        currentYear : Int
        currentYear =
            Time.toYear zone time.now

        base : String
        base =
            monthName (Time.toMonth zone moment) ++ " " ++ String.fromInt (Time.toDay zone moment)
    in
    if year == currentYear then
        base

    else
        base ++ ", " ++ String.fromInt year


relativeDayText : RelativeDay -> String
relativeDayText day =
    case day of
        Today ->
            "Today"

        Yesterday ->
            "Yesterday"

        Tomorrow ->
            "Tomorrow"


{-| Prepends `"Today, "`/`"Yesterday, "`/`"Tomorrow, "` to `base` (a
`dateLabelBase` result) for `Just` a `RelativeDay`, unchanged for `Nothing`.
-}
withRelativeDayPrefix : Maybe RelativeDay -> String -> String
withRelativeDayPrefix maybeRelativeDay base =
    case maybeRelativeDay of
        Just day ->
            relativeDayText day ++ ", " ++ base

        Nothing ->
            base


{-| `start`/`end`'s time-of-day, same calendar day, merged onto one range --
e.g. "6-7PM"/"8-10:30PM" (both sides share an AM/PM, so only `end` states it)
or "11:30AM-2PM" (they don't, so both state their own). 24-hour locales have
no AM/PM to (de)duplicate in the first place, so `uses24Hour` always shows
both sides in full, e.g. "18:00-19:00".
-}
timeRangeLabel : BrowserTimeZone -> Time.Posix -> Time.Posix -> String
timeRangeLabel browserTimeZone start end =
    let
        zone : Time.Zone
        zone =
            browserTimeZone.zone
    in
    if browserTimeZone.uses24Hour then
        time24 zone start ++ "-" ++ time24 zone end

    else
        let
            startHour : Int
            startHour =
                Time.toHour zone start

            endHour : Int
            endHour =
                Time.toHour zone end
        in
        if period startHour == period endHour then
            bareTime12 zone start ++ "-" ++ timeWithPeriod zone end

        else
            timeWithPeriod zone start ++ "-" ++ timeWithPeriod zone end


{-| A single point in time's time-of-day only, honoring `uses24Hour` -- e.g.
"6PM"/"10:30PM" (12-hour, minutes omitted on the hour) or "18:00"/"22:30"
(24-hour, minutes always shown, the usual convention for that clock).
-}
timeOfDayLabel : BrowserTimeZone -> Time.Posix -> String
timeOfDayLabel browserTimeZone time =
    if browserTimeZone.uses24Hour then
        time24 browserTimeZone.zone time

    else
        timeWithPeriod browserTimeZone.zone time


{-| `"AM"`/`"PM"` for a 24-hour `hour` (`0`-`23`).
-}
period : Int -> String
period hour =
    if hour < 12 then
        "AM"

    else
        "PM"


{-| `time`'s time-of-day, 12-hour, with no AM/PM suffix and no leading zero
-- e.g. "6", "10:30" -- minutes omitted entirely on the hour. The bare half
of `timeRangeLabel`'s "6-7PM"-style merge; `timeWithPeriod` is the version
with the suffix attached.
-}
bareTime12 : Time.Zone -> Time.Posix -> String
bareTime12 zone time =
    let
        minute : Int
        minute =
            Time.toMinute zone time
    in
    String.fromInt (hour12 (Time.toHour zone time))
        ++ (if minute == 0 then
                ""

            else
                ":" ++ String.padLeft 2 '0' (String.fromInt minute)
           )


{-| `bareTime12` plus its own `AM`/`PM` suffix, e.g. "6PM", "10:30PM".
-}
timeWithPeriod : Time.Zone -> Time.Posix -> String
timeWithPeriod zone time =
    bareTime12 zone time ++ period (Time.toHour zone time)


{-| `time`'s time-of-day, 24-hour, always `HH:mm` (e.g. "18:00", "02:30") --
the usual convention for a 24-hour clock, unlike `bareTime12`'s on-the-hour
minute omission.
-}
time24 : Time.Zone -> Time.Posix -> String
time24 zone time =
    String.padLeft 2 '0' (String.fromInt (Time.toHour zone time))
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt (Time.toMinute zone time))


{-| Full month name, e.g. "August" -- for `dateLabelBase`'s human-friendly
rendering rather than a zero-padded numeric date (see `monthNumber`).
-}
monthName : Time.Month -> String
monthName month =
    case month of
        Time.Jan ->
            "January"

        Time.Feb ->
            "February"

        Time.Mar ->
            "March"

        Time.Apr ->
            "April"

        Time.May ->
            "May"

        Time.Jun ->
            "June"

        Time.Jul ->
            "July"

        Time.Aug ->
            "August"

        Time.Sep ->
            "September"

        Time.Oct ->
            "October"

        Time.Nov ->
            "November"

        Time.Dec ->
            "December"


{-| `YYYY-MM-DDTHH:mm` in `zone` -- the exact format an `<input
type="datetime-local">` element's `value` attribute expects, so a date/time
picker (e.g. `Components.Pages.EventsPage`'s "Events After <date>" tab)
can be a plain controlled input: this formats a `Time.Posix` to populate it,
and `posixFromDateTimeLocalInput` parses back whatever the user (or the
browser's own native picker widget) sets it to.
-}
formatDateTimeLocalInput : Time.Zone -> Time.Posix -> String
formatDateTimeLocalInput zone time =
    let
        pad2 : Int -> String
        pad2 n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    formatDate zone time
        ++ "T"
        ++ pad2 (Time.toHour zone time)
        ++ ":"
        ++ pad2 (Time.toMinute zone time)


{-| `start`/`end`'s own `dateLabel`s, for `formatRange`/`formatDateRange`'s
different-day branches -- normally just `dateLabel time start`/`... end`
each, except the "Today"+"Yesterday"/"Today"+"Tomorrow" suppression
described on `formatRange`: since `start` never comes after `end`,
"Yesterday" can only pair with a `start` that's "Today"'s eve (so `end` is
"Today"), and "Tomorrow" can only pair with an `end` the day after a "Today"
`start` -- no other combination collides, so every other pairing (including
"Yesterday" and "Tomorrow" together, spanning today itself) keeps both
sides' own relative-day prefix untouched.
-}
rangeDateLabels : Model -> Time.Posix -> Time.Posix -> ( String, String )
rangeDateLabels time start end =
    let
        startRelativeDay : Maybe RelativeDay
        startRelativeDay =
            relativeDay time start

        endRelativeDay : Maybe RelativeDay
        endRelativeDay =
            relativeDay time end

        ( adjustedStartRelativeDay, adjustedEndRelativeDay ) =
            case ( startRelativeDay, endRelativeDay ) of
                ( Just Yesterday, Just Today ) ->
                    ( Nothing, Just Today )

                ( Just Today, Just Tomorrow ) ->
                    ( Just Today, Nothing )

                _ ->
                    ( startRelativeDay, endRelativeDay )
    in
    ( withRelativeDayPrefix adjustedStartRelativeDay (dateLabelBase time start)
    , withRelativeDayPrefix adjustedEndRelativeDay (dateLabelBase time end)
    )


{-| `Just Today`/`Just Yesterday`/`Just Tomorrow` if `moment`'s calendar date
(in `time.browserTimeZone.zone`) is respectively the same as, one before, or
one after `time.now`'s own calendar date -- `Nothing` otherwise (including
whenever `now` itself hasn't resolved yet, i.e. everywhere still using the
`Time.millisToPosix 0`/`Time.utc` placeholders from before `Shared.init`'s
`Cmd`s resolve, since `now` and `moment` would only spuriously agree there
already). Compares whole calendar days via `Shared.Conversions.daysFromCivil`
(a plain day-count) rather than subtracting `Time.posixToMillis`, since a
`moment` just under 24h from `now` can still be "Yesterday" (e.g. 11:58PM to
12:02AM) while one just over 24h apart can still be "Today" (e.g. an
all-nighter's 1AM to the next day's 11PM) -- only the calendar date matters,
not elapsed duration.
-}
relativeDay : Model -> Time.Posix -> Maybe RelativeDay
relativeDay time moment =
    let
        zone : Time.Zone
        zone =
            time.browserTimeZone.zone

        dayNumber : Time.Posix -> Int
        dayNumber t =
            Conversions.daysFromCivil (Time.toYear zone t) (Conversions.monthToNumber (Time.toMonth zone t)) (Time.toDay zone t)

        dayDiff : Int
        dayDiff =
            dayNumber moment - dayNumber time.now
    in
    if dayDiff == 0 then
        Just Today

    else if dayDiff == -1 then
        Just Yesterday

    else if dayDiff == 1 then
        Just Tomorrow

    else
        Nothing


{-| A 24-hour `hour` (`0`-`23`) as its 12-hour clock face number (`1`-`12`) --
`0` and `12` both read as `12` (midnight/noon), same as any analog clock.
-}
hour12 : Int -> Int
hour12 hour =
    case modBy 12 hour of
        0 ->
            12

        h ->
            h


{-| `Time.Month` as its zero-padded numeric position (`1`-`12`), for
`formatDate`'s `YYYY-MM-DD` rendering.
-}
monthNumber : Time.Month -> Int
monthNumber month =
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


{-| The inverse of `formatDateTimeLocalInput` -- parses an `<input
type="datetime-local">`'s value string (`YYYY-MM-DDTHH:mm`, always the
viewer's own local wall-clock time, with no timezone of its own) back into
the absolute `Time.Posix` it represents in `zone`.

`elm/time`'s `Time.Zone` only goes one direction (instant -> local wall
clock, via `Time.toHour`/etc.) -- there's no built-in inverse. This gets
there by guessing (treating the input's Y/M/D/H/M as if they were already
UTC, via `Shared.Conversions.daysFromCivil`), reading back what `zone` says
the wall-clock is at that guess, and correcting by the difference --
re-derived from the _original_ guess a second time (not chained onto the
already-corrected candidate, which would double-count a stable offset
instead of converging) so a guess landing right on a DST boundary still
converges (this app's own use, picking a cutoff date for an events filter,
doesn't need sub-minute precision across a boundary, but there's no reason
not to get it right).

-}
posixFromDateTimeLocalInput : Time.Zone -> String -> Maybe Time.Posix
posixFromDateTimeLocalInput zone raw =
    let
        offsetMinutesAt : Time.Posix -> Int
        offsetMinutesAt posix =
            let
                localAsUtcMillis : Int
                localAsUtcMillis =
                    (Conversions.daysFromCivil (Time.toYear zone posix) (Conversions.monthToNumber (Time.toMonth zone posix)) (Time.toDay zone posix)
                        * 86400
                        + Time.toHour zone posix
                        * 3600
                        + Time.toMinute zone posix
                        * 60
                    )
                        * 1000
            in
            (localAsUtcMillis - Time.posixToMillis posix) // 60000
    in
    case String.split "T" raw of
        [ datePart, timePart ] ->
            Maybe.map2
                (\( year, month, day ) ( hour, minute, _ ) ->
                    let
                        guessMillis : Int
                        guessMillis =
                            (Conversions.daysFromCivil year month day * 86400 + hour * 3600 + minute * 60) * 1000

                        correctFromGuess : Int -> Int
                        correctFromGuess offset =
                            guessMillis - offset * 60000

                        candidate1 : Int
                        candidate1 =
                            correctFromGuess (offsetMinutesAt (Time.millisToPosix guessMillis))

                        candidate2 : Int
                        candidate2 =
                            correctFromGuess (offsetMinutesAt (Time.millisToPosix candidate1))
                    in
                    Time.millisToPosix candidate2
                )
                (Conversions.parseDateParts datePart)
                (Conversions.parseTimeParts timePart)

        _ ->
            Nothing


{-| How far apart `Pages.Event.PostId_`'s "Add More" recurrence menu spaces
each newly-created `Occasion` from the one before it -- `Daily`/`Weekly`
step by a fixed number of days (`1`/`7`), `Monthly` steps the calendar month
itself (clamping the day-of-month down when the target month is shorter,
e.g. Jan 31 + 1 month -> Feb 28/29), all via `addRecurrence`.
-}
type RecurrenceUnit
    = Daily
    | Weekly
    | Monthly


{-| `posix`'s own wall-clock time-of-day (in `zone`), `n` `unit`s later on the
calendar -- e.g. `addRecurrence zone Weekly 3 posix` is "3 weeks from
`posix`, same local time of day". Always re-resolves the result against
`zone`'s real DST transition history (via `posixFromDateTimeLocalInput`,
same as every other wall-clock -> `Posix` conversion in this module), so a
weekly 6-7PM series that crosses a DST change is still 6-7PM local time on
the other side of it, not 6-7PM's UTC-equivalent hour drifted by the
transition -- the same guarantee `formatRange`'s own doc describes for
`instanceWhenText`, just in the create direction instead of display.

`Daily`/`Weekly` add a fixed number of whole days (`n`/`n * 7`) to `posix`'s
own wall-clock date, letting month/year rollover happen naturally (adding
milliseconds to a UTC-as-if-local naive timestamp and reading the calendar
fields back off it, the same trick `posixFromDateTimeLocalInput` itself
uses internally). `Monthly` instead adds `n` to the month/year pair
directly, so "Jan 31 + 1 month" lands on the last day of February rather
than overflowing into March -- `daysInMonth` clamps the day-of-month down to
whatever the target month actually has.

-}
addRecurrence : Time.Zone -> RecurrenceUnit -> Int -> Time.Posix -> Time.Posix
addRecurrence zone unit n posix =
    let
        year : Int
        year =
            Time.toYear zone posix

        month : Int
        month =
            Conversions.monthToNumber (Time.toMonth zone posix)

        day : Int
        day =
            Time.toDay zone posix

        hour : Int
        hour =
            Time.toHour zone posix

        minute : Int
        minute =
            Time.toMinute zone posix

        naiveMillisAt : Int -> Int -> Int -> Int
        naiveMillisAt y m d =
            (Conversions.daysFromCivil y m d * 86400 + hour * 3600 + minute * 60) * 1000

        newNaiveMillis : Int
        newNaiveMillis =
            case unit of
                Daily ->
                    naiveMillisAt year month day + n * 86400000

                Weekly ->
                    naiveMillisAt year month day + n * 7 * 86400000

                Monthly ->
                    let
                        totalMonths : Int
                        totalMonths =
                            year * 12 + (month - 1) + n

                        newYear : Int
                        newYear =
                            totalMonths // 12

                        newMonth : Int
                        newMonth =
                            modBy 12 totalMonths + 1
                    in
                    naiveMillisAt newYear newMonth (min day (daysInMonth newYear newMonth))

        naiveUtc : Time.Posix
        naiveUtc =
            Time.millisToPosix newNaiveMillis

        pad2 : Int -> String
        pad2 v =
            String.padLeft 2 '0' (String.fromInt v)

        raw : String
        raw =
            String.padLeft 4 '0' (String.fromInt (Time.toYear Time.utc naiveUtc))
                ++ "-"
                ++ pad2 (Conversions.monthToNumber (Time.toMonth Time.utc naiveUtc))
                ++ "-"
                ++ pad2 (Time.toDay Time.utc naiveUtc)
                ++ "T"
                ++ pad2 (Time.toHour Time.utc naiveUtc)
                ++ ":"
                ++ pad2 (Time.toMinute Time.utc naiveUtc)
    in
    posixFromDateTimeLocalInput zone raw |> Maybe.withDefault posix


{-| The number of days in `month` (`1`-`12`) of `year`, Gregorian leap years
included -- the clamp `addRecurrence`'s `Monthly` case needs so "Jan 31 + 1
month" lands on Feb 28/29 rather than overflowing into March.
-}
daysInMonth : Int -> Int -> Int
daysInMonth year month =
    case month of
        1 ->
            31

        2 ->
            if isLeapYear year then
                29

            else
                28

        3 ->
            31

        4 ->
            30

        5 ->
            31

        6 ->
            30

        7 ->
            31

        8 ->
            31

        9 ->
            30

        10 ->
            31

        11 ->
            30

        _ ->
            31


isLeapYear : Int -> Bool
isLeapYear year =
    (modBy 4 year == 0 && modBy 100 year /= 0) || modBy 400 year == 0
