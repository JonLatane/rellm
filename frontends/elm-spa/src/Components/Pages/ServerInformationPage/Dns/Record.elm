module Components.Pages.ServerInformationPage.Dns.Record exposing
    ( DnsRecord
    , HintPart(..)
    , copyText
    , relativeHint
    , parseFixHint
    , parseRecordLine
    )

{-| The pure side of showing DNS records on the Sign In & Contact and CDN tabs: a `DnsRecord` (type /
name / value -- the three things any DNS dashboard asks for) and the parser for the server's
`StatusCheck.fix_hint` strings.

A fix hint is a short explanatory sentence followed by zero or more exact-record lines, each on its own
line as `TYPE name value`, e.g.

    Add a DMARC record so receivers know what to do with forged mail.
    TXT _dmarc v=DMARC1; p=none; rua=mailto:postmaster@example.com

`TYPE` is `TXT`, `CNAME` or `MX`, `name` is a single token holding the *fully-qualified* name exactly as it
should be created (no trailing dot; an apex record is the bare domain, e.g. `_dmarc.example.com`,
`s1._domainkey.example.com`, `example.com`), and `value` is the rest of the line (it may contain spaces and
semicolons). Names are always shown as given -- never re-expanded under some other domain. `parseFixHint` splits a hint into ordered `HintPart`s --
`HintText` for anything that isn't a record line (rendered as plain text), `HintRecord` for a line that
is -- so a malformed line degrades to text instead of being lost.

-}


type alias DnsRecord =
    { recordType : String
    , name : String
    , value : String
    }


type HintPart
    = HintText String
    | HintRecord DnsRecord


recordTypes : List String
recordTypes =
    [ "TXT", "CNAME", "MX" ]


{-| `TYPE name value` -> a record; anything else (unknown type, missing name or value) -> `Nothing`.
Runs of spaces between the three parts are fine; the value keeps its own inner spacing.
-}
parseRecordLine : String -> Maybe DnsRecord
parseRecordLine line =
    let
        ( recordType, afterType ) =
            splitWord (String.trim line)

        ( name, value ) =
            splitWord afterType
    in
    if List.member recordType recordTypes && not (String.isEmpty name) && not (String.isEmpty value) then
        Just { recordType = recordType, name = name, value = value }

    else
        Nothing


{-| The first whitespace-delimited word and the (left-trimmed) rest.
-}
splitWord : String -> ( String, String )
splitWord text =
    case String.words text of
        [] ->
            ( "", "" )

        word :: _ ->
            ( word, String.dropLeft (String.length word) text |> String.trimLeft )


{-| Splits a fix hint into its explanatory text and record lines, in order. Blank lines are dropped;
consecutive text lines stay separate parts.
-}
parseFixHint : String -> List HintPart
parseFixHint hint =
    hint
        |> String.lines
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)
        |> List.map
            (\line ->
                case parseRecordLine line of
                    Just record ->
                        HintRecord record

                    Nothing ->
                        HintText line
            )


{-| One-line `TYPE name value` form, for "copy the whole record".
-}
copyText : DnsRecord -> String
copyText record =
    record.recordType ++ " " ++ record.name ++ " " ++ record.value


{-| For a record `name` that sits under `domain` or one of its parent domains (`mg.example.com` -> also
`example.com`), the part before that suffix -- what a DNS host that adds the zone automatically wants
typed -- e.g. `_dmarc.example.com` under `mail.example.com` gives `_dmarc`. `Nothing` when the name isn't
under any of them (or is exactly a domain, which has no prefix); nothing is ever invented.
-}
relativeHint : String -> String -> Maybe String
relativeHint domain name =
    domainAndParents domain
        |> List.filterMap
            (\candidate ->
                if String.endsWith ("." ++ candidate) name then
                    Just (String.dropRight (String.length candidate + 1) name)

                else
                    Nothing
            )
        |> List.head


{-| `a.b.example.com` -> `[ a.b.example.com, b.example.com, example.com ]` (always at least two labels).
-}
domainAndParents : String -> List String
domainAndParents domain =
    case String.split "." domain of
        _ :: rest ->
            if List.length rest >= 2 then
                domain :: domainAndParents (String.join "." rest)

            else
                [ domain ]

        [] ->
            []
