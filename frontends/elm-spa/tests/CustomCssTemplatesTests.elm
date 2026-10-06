module CustomCssTemplatesTests exposing (suite)

import Components.Pages.ServerInformationPage.ThemeTab.CustomCssTemplates as Templates
import Expect
import Test exposing (Test, describe, test)


{-| The highest `--custom-media-N` a stylesheet mentions (0 if none).
-}
highestMediaVar : String -> Int
highestMediaVar css =
    [ 1, 2, 3, 4 ]
        |> List.filter (\n -> String.contains ("--custom-media-" ++ String.fromInt n) css)
        |> List.maximum
        |> Maybe.withDefault 0


count : String -> String -> Int
count needle haystack =
    List.length (String.indices needle haystack)


suite : Test
suite =
    describe "CustomCssTemplates"
        [ test "has the twelve templates, in the dropdown's order" <|
            \_ ->
                List.map .name Templates.all
                    |> Expect.equal
                        [ "Art Deco"
                        , "Art Deco (1 image)"
                        , "Art Deco (2 images)"
                        , "Bauhaus"
                        , "Bauhaus (1 image)"
                        , "Bauhaus (2 images)"
                        , "Serif Fonts"
                        , "Serif Fonts (1 image)"
                        , "Serif Fonts (2 images)"
                        , "Standard Style"
                        , "Standard Style (1 background image)"
                        , "Standard Style (2 background images)"
                        ]
        , test "each template uses exactly as many --custom-media-N as it declares" <|
            \_ ->
                Templates.all
                    |> List.map (\t -> ( t.name, highestMediaVar t.css, t.imageCount ))
                    |> List.filter (\( _, used, declared ) -> used /= declared)
                    |> Expect.equal []
        , test "every image use has a `none` fallback, so a template still renders before its images are picked" <|
            \_ ->
                Templates.all
                    |> List.filter (\t -> count "var(--custom-media-" t.css /= count "var(--custom-media-1, none)" t.css + count "var(--custom-media-2, none)" t.css)
                    |> List.map .name
                    |> Expect.equal []
        , test "braces and parentheses are balanced" <|
            \_ ->
                Templates.all
                    |> List.filter (\t -> count "{" t.css /= count "}" t.css || count "(" t.css /= count ")" t.css)
                    |> List.map .name
                    |> Expect.equal []
        , test "no template loads anything external" <|
            \_ ->
                Templates.all
                    |> List.filter (\t -> String.contains "@import" t.css || String.contains "http://" t.css || String.contains "https://" t.css)
                    |> List.map .name
                    |> Expect.equal []
        , test "template CSS stays under the server's 64 KiB limit" <|
            \_ ->
                Templates.all
                    |> List.filter (\t -> String.length t.css > 64 * 1024)
                    |> List.map .name
                    |> Expect.equal []
        , test "matching finds a template by its exact CSS, and nothing once it's edited" <|
            \_ ->
                case List.head (List.drop 4 Templates.all) of
                    Just t ->
                        Expect.equal
                            ( Maybe.map .name (Templates.matching t.css), Templates.matching (t.css ++ "\n/* edited */") |> Maybe.map .name )
                            ( Just t.name, Nothing )

                    Nothing ->
                        Expect.fail "expected at least five templates"
        ]
