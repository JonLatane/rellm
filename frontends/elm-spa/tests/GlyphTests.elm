module GlyphTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import UI.Glyph as Glyph


suite : Test
suite =
    describe "UI.Glyph"
        [ test "each glyph is its character followed by the text-presentation selector (U+FE0E), so iOS never draws it as an emoji" <|
            \_ ->
                [ Glyph.externalLink, Glyph.left, Glyph.right, Glyph.play ]
                    |> List.map String.toList
                    |> List.map (List.map Char.toCode)
                    |> Expect.equal [ [ 0x2197, 0xFE0E ], [ 0x25C0, 0xFE0E ], [ 0x25B6, 0xFE0E ], [ 0x25B6, 0xFE0E ] ]
        , test "textPresentation just appends the selector" <|
            \_ ->
                Glyph.textPresentation "↩"
                    |> String.toList
                    |> List.map Char.toCode
                    |> Expect.equal [ 0x21A9, 0xFE0E ]
        ]
