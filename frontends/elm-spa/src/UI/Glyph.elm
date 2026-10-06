module UI.Glyph exposing (externalLink, left, play, right, textPresentation)

{-| Symbols used as plain UI glyphs (buttons, links), never as emoji.

iOS renders several ordinary Unicode symbols -- `↗`, `◀`, `▶`, and the other arrows and triangles that have an
emoji form (Unicode's `emoji-variation-sequences.txt`) -- as color emoji (the blue-square `▶️`, `↗️`), which is never
wanted for a control. The fix is the text-presentation variation selector, U+FE0E, right after the character, and
that is all `textPresentation` does; the glyphs below have it applied once, so a call site can't forget it.

Use these (or `textPresentation` for another such symbol) instead of typing the bare characters into a `text`.
Characters that have no emoji form at all -- `←` `→` `↑` `↓` `▲` `▼`, `✕`, `✓` -- need nothing. This does *not*
help for characters that are emoji by default (`⏮` `⏸` `⏭` `⬅` `➡`, ...): iOS keeps drawing those as emoji whatever
follows them, which is why `Shared.AudioPlayerPanel` draws its transport icons with CSS shapes instead. And a
real emoji meant as one (`⭐`, `✅`, `🔍`) is of course left alone.

-}


{-| `symbol` forced to its plain text glyph (appends U+FE0E, the text variation selector).
-}
textPresentation : String -> String
textPresentation symbol =
    symbol ++ "\u{FE0E}"


{-| North-east arrow, for "opens elsewhere" links and buttons.
-}
externalLink : String
externalLink =
    textPresentation "↗"


{-| Left-pointing triangle (e.g. "move left").
-}
left : String
left =
    textPresentation "◀"


{-| Right-pointing triangle (e.g. "move right").
-}
right : String
right =
    textPresentation "▶"


{-| Right-pointing triangle as a "play" glyph (the same character as `right`).
-}
play : String
play =
    right
