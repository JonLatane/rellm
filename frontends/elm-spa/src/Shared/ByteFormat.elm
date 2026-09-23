module Shared.ByteFormat exposing (ByteUnit(..), byteUnitBytes, byteUnitFromText, byteUnitText, bytesToUnit, formatBytes, humanizeBytes, parseBytes)

{-| Human-friendly byte-count formatting/parsing/conversion -- the one place in the Elm frontend
that knows a `ByteUnit`'s size, shared by everything that displays or edits a byte size:
`Shared.MyMediaPanel`'s used/available readout, `Components.Pages.UserProfilePage`'s storage quota
editor, `Shared.MediaViewerPanel`'s per-size delete buttons, and
`Components.Pages.ServerInformationPage.SettingsTab`'s default media allocation editor (all four via
`formatBytes`/`parseBytes`, "12.4 MB"-style); and `Components.Market`'s product blurbs (via
`humanizeBytes`, "12.4MB"-style, mirroring `backend/src/logic/market_summary.rs`'s `humanize_bytes`)
and `Components.Pages.MarketPage`'s product form (via `ByteUnit`/`byteUnitBytes`/`parseBytes`/
`byteUnitFromText` directly, same as everything else -- only the *display* string differs per call
site, never the underlying conversion).
-}


{-| A unit `formatBytes`/`humanizeBytes`/`parseBytes` can round-trip a byte count through --
deliberately just these 4 (not past GB): every byte size this app deals with is well under a TB.
`KB`/`MB`/`GB` are binary (1024-based, i.e. actually KiB/MiB/GiB) rather than decimal, matching
`backend/src/logic/market_summary.rs`'s `humanize_bytes` and how the backend itself computes
byte-size defaults (e.g. `MediaSettings`'s own `default_media_allocation_bytes`, `15 * 1024 * 1024`)
-- every "MB"/"GB" elsewhere in this app already means MiB/GiB, so this module matches rather than
introducing a second, decimal meaning for the same labels.
-}
type ByteUnit
    = Bytes
    | KB
    | MB
    | GB


byteUnitText : ByteUnit -> String
byteUnitText unit =
    case unit of
        Bytes ->
            "B"

        KB ->
            "KB"

        MB ->
            "MB"

        GB ->
            "GB"


{-| The inverse of `byteUnitText` -- `Nothing` for anything that isn't one of the 4 unit labels it
produces, so a `<select onInput>` handler can fall back to the previous unit on garbage input.
-}
byteUnitFromText : String -> Maybe ByteUnit
byteUnitFromText text =
    case text of
        "B" ->
            Just Bytes

        "KB" ->
            Just KB

        "MB" ->
            Just MB

        "GB" ->
            Just GB

        _ ->
            Nothing


byteUnitBytes : ByteUnit -> Int
byteUnitBytes unit =
    case unit of
        Bytes ->
            1

        KB ->
            1024

        MB ->
            1024 * 1024

        GB ->
            1024 * 1024 * 1024


{-| The largest unit `n` is at least 1 whole one of -- what `formatBytes` picks to display `n` in,
and a sensible starting unit for a fresh edit of `n` (see `Components.Pages.UserProfilePage`'s
storage quota editor).
-}
bytesToUnit : Int -> ByteUnit
bytesToUnit n =
    if n >= byteUnitBytes GB then
        GB

    else if n >= byteUnitBytes MB then
        MB

    else if n >= byteUnitBytes KB then
        KB

    else
        Bytes


{-| A compact human-readable byte count -- "512 B", "12.4 MB", "1.3 GB". Rounds to 1 decimal place
above bytes; not locale-aware (not worth it for this small a label).
-}
formatBytes : Int -> String
formatBytes bytes =
    let
        unit : ByteUnit
        unit =
            bytesToUnit bytes
    in
    (if unit == Bytes then
        String.fromInt bytes

     else
        String.fromFloat (toFloat (round (toFloat bytes / toFloat (byteUnitBytes unit) * 10)) / 10)
    )
        ++ " "
        ++ byteUnitText unit


{-| Parses a plain (possibly decimal) number in the given unit back to a byte count, rounded to
the nearest byte -- the inverse of picking a friendly `ByteUnit` for entry (`bytesToUnit`).
`Nothing` if `input` isn't a valid number.
-}
parseBytes : ByteUnit -> String -> Maybe Int
parseBytes unit input =
    String.toFloat (String.trim input)
        |> Maybe.map (\n -> round (n * toFloat (byteUnitBytes unit)))


{-| A byte count -> "1.5GB"/"100MB"/"512KB"/"3B" -- no space and a trailing-zero-trimmed decimal
(vs. `formatBytes`'s "1.3 GB"/"512 B"), mirroring `backend/src/logic/market_summary.rs`'s
`humanize_bytes` exactly. Used for `Components.Market`'s product blurbs (e.g. "5GB Media Storage"),
where that terser, space-free style reads better inline than `formatBytes`'s own -- both otherwise
share the same underlying `ByteUnit`/`bytesToUnit`/`byteUnitBytes`.
-}
humanizeBytes : Int -> String
humanizeBytes bytes =
    let
        unit : ByteUnit
        unit =
            bytesToUnit bytes
    in
    (if unit == Bytes then
        String.fromInt bytes

     else
        formatTrimmedDecimal (toFloat bytes / toFloat (byteUnitBytes unit))
    )
        ++ byteUnitText unit


{-| One decimal place, trailing ".0" dropped ("1.0" -> "1", "1.5" -> "1.5") -- `humanizeBytes`'s own
rounding step, kept separate from `formatBytes`'s `String.fromFloat`-based one since the two
functions' output styles (no space vs a space before the unit) are otherwise unrelated.
-}
formatTrimmedDecimal : Float -> String
formatTrimmedDecimal value =
    let
        rounded : Float
        rounded =
            toFloat (round (value * 10)) / 10

        whole : Int
        whole =
            floor rounded

        tenths : Int
        tenths =
            round ((rounded - toFloat whole) * 10)
    in
    if tenths == 0 then
        String.fromInt whole

    else
        String.fromInt whole ++ "." ++ String.fromInt tenths
