module Shared.BrowserInfo exposing (Browser(..), fromUserAgent, name)

{-| Minimal user-agent sniffing -- just enough to name the browser in user-facing copy (e.g.
`UI.pushNotificationsMenuItem`'s "Chrome notifications are enabled"). Not for feature
detection; nothing should branch on this beyond display text.

Order matters in `fromUserAgent`: nearly every Chromium-based browser's user agent also contains
"Chrome/" and "Safari/", and Chrome's contains "Safari/", so the more specific tokens are checked
first.

-}


type Browser
    = Edge
    | Opera
    | SamsungInternet
    | Firefox
    | Chrome
    | Safari
    | UnknownBrowser


fromUserAgent : String -> Browser
fromUserAgent userAgent =
    let
        has : String -> Bool
        has token =
            String.contains token userAgent
    in
    if has "Edg/" || has "EdgA/" || has "EdgiOS/" then
        Edge

    else if has "OPR/" || has "OPT/" || has "Opera" then
        Opera

    else if has "SamsungBrowser/" then
        SamsungInternet

    else if has "Firefox/" || has "FxiOS/" then
        Firefox

    else if has "Chrome/" || has "CriOS/" then
        Chrome

    else if has "Safari/" then
        Safari

    else
        UnknownBrowser


{-| Display name; the generic "Browser" for `UnknownBrowser`, so it reads naturally in
"<name> notifications are enabled".
-}
name : Browser -> String
name browser =
    case browser of
        Edge ->
            "Edge"

        Opera ->
            "Opera"

        SamsungInternet ->
            "Samsung Internet"

        Firefox ->
            "Firefox"

        Chrome ->
            "Chrome"

        Safari ->
            "Safari"

        UnknownBrowser ->
            "Browser"
