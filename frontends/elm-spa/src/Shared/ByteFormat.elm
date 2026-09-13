module Shared.ByteFormat exposing (ByteUnit(..), byteUnitBytes, byteUnitText, bytesToUnit, formatBytes, parseBytes)

{-| Human-friendly byte-count formatting/parsing, shared by anything displaying or editing a
`Media`/`User` storage size -- `Shared.MyMediaPanel`'s used/available readout,
`Components.Pages.UserProfilePage`'s storage quota editor, and `Shared.MediaViewerPanel`'s
per-size delete buttons.

-}


{-| A unit `formatBytes`/`parseBytes` can round-trip a byte count through -- deliberately just
these 4 (not KiB/MiB/GiB or anything past GB): every quota/media size this app deals with is well
under a TB, and matching `du`/most OSes' decimal (1000-based, not 1024-based) convention avoids
the "why doesn't this add up" confusion binary units cause for anyone not already expecting them.
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


byteUnitBytes : ByteUnit -> Int
byteUnitBytes unit =
    case unit of
        Bytes ->
            1

        KB ->
            1000

        MB ->
            1000000

        GB ->
            1000000000


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
