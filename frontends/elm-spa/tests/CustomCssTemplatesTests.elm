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
        [ test "has a hundred and eleven templates -- thirty-seven styles in 0/1/2 image versions -- in the dropdown's order" <|
            \_ ->
                List.map .name Templates.all
                    |> Expect.equal
                        (List.concatMap
                            (\( style, noun ) -> [ style, style ++ " (1 " ++ noun ++ ")", style ++ " (2 " ++ noun ++ "s)" ])
                            [ ( "Art Deco", "image" )
                            , ( "Bauhaus", "image" )
                            , ( "Serif Fonts", "image" )
                            , ( "Standard Style", "background image" )
                            , ( "Standard Side Navigation", "background image" )
                            , ( "High Contrast", "image" )
                            , ( "Terminal", "image" )
                            , ( "Newspaper", "image" )
                            , ( "Synthwave", "image" )
                            , ( "Midcentury Modern", "image" )
                            , ( "Polaroid", "image" )
                            , ( "Concert Poster", "image" )
                            , ( "Fiesta", "image" )
                            , ( "Calm", "image" )
                            , ( "Town Square", "image" )
                            , ( "Blueprint", "image" )
                            , ( "Disco", "image" )
                            , ( "Psychedelic Poster", "image" )
                            , ( "Cinematic", "image" )
                            , ( "Haunted Mansion", "image" )
                            , ( "Dyslexia-Friendly", "image" )
                            , ( "Field Guide", "image" )
                            , ( "Pirate Map", "image" )
                            , ( "Y2K Aero", "image" )
                            , ( "Mac Classic", "image" )
                            , ( "OS X (Original)", "image" )
                            , ( "Material Design", "image" )
                            , ( "Neuro Zoogle", "image" )
                            , ( "Liquid Glass", "image" )
                            , ( "Candy Shop", "image" )
                            , ( "Retro Desktop", "image" )
                            , ( "Zine", "image" )
                            , ( "Comic Book", "image" )
                            , ( "Wabi-sabi", "image" )
                            , ( "Ocean", "image" )
                            , ( "Forest", "image" )
                            , ( "Deep Space", "image" )
                            ]
                        )
        , test "styles with an always-dark backdrop force the dark theme, always-light ones force light, the rest force nothing" <|
            \_ ->
                let
                    forcing : (Templates.Template -> Bool) -> List String
                    forcing flag =
                        Templates.grouped |> List.filter (\( _, ts ) -> List.all flag ts) |> List.map Tuple.first
                in
                Expect.equal
                    ( forcing .forceDarkTheme, forcing .forceLightTheme )
                    ( [ "Terminal", "Synthwave", "Blueprint", "Disco", "Psychedelic Poster", "Cinematic", "Haunted Mansion", "Neuro Zoogle", "Deep Space" ]
                    , [ "Polaroid", "Fiesta", "Pirate Map", "Y2K Aero", "Mac Classic", "OS X (Original)", "Candy Shop", "Retro Desktop", "Zine", "Comic Book" ]
                    )
        , test "a template never forces both themes, and a style forces the same theme in all three of its versions" <|
            \_ ->
                Templates.grouped
                    |> List.filter
                        (\( _, ts ) ->
                            List.any (\t -> t.forceLightTheme && t.forceDarkTheme) ts
                                || notIn [ 0, 3 ] (List.length (List.filter .forceLightTheme ts))
                                || notIn [ 0, 3 ] (List.length (List.filter .forceDarkTheme ts))
                        )
                    |> List.map Tuple.first
                    |> Expect.equal []
        , test "every use of --primary-color / --nav-color has a fallback, so a template still renders without them" <|
            \_ ->
                Templates.all
                    |> List.filter
                        (\t ->
                            count "var(--primary-color" t.css /= count "var(--primary-color," t.css
                                || count "var(--nav-color" t.css /= count "var(--nav-color," t.css
                        )
                    |> List.map .name
                    |> Expect.equal []
        , test "the styles meant to wear the server's colors do, in every version" <|
            \_ ->
                Templates.grouped
                    |> List.filter (\( _, ts ) -> List.all (\t -> String.contains "var(--primary-color" t.css) ts)
                    |> List.map Tuple.first
                    |> Expect.equal [ "Bauhaus", "Serif Fonts", "Standard Style", "Standard Side Navigation", "Concert Poster", "Town Square", "Material Design", "Retro Desktop", "Zine", "Comic Book", "Wabi-sabi" ]
        , test "adjacent steps to the neighbouring style at the same image count, wrapping around" <|
            \_ ->
                let
                    named : String -> Maybe Templates.Template
                    named name =
                        Templates.all |> List.filter (\x -> x.name == name) |> List.head

                    step : Int -> String -> Maybe String
                    step direction from =
                        Templates.adjacent direction 0 (named from) |> Maybe.map .name
                in
                Expect.equal
                    [ step 1 "Bauhaus (1 image)"
                    , step -1 "Bauhaus (1 image)"
                    , step 1 "Art Deco (2 images)"
                    , step -1 "Art Deco (2 images)"
                    , step 1 "Deep Space"
                    , step -1 "Standard Style (1 background image)"
                    ]
                    [ Just "Serif Fonts (1 image)"
                    , Just "Art Deco (1 image)"
                    , Just "Bauhaus (2 images)"
                    , Just "Deep Space (2 images)"
                    , Just "Art Deco"
                    , Just "Serif Fonts (1 image)"
                    ]
        , test "adjacent with nothing applied starts from the first style (next) or the last (previous), at the given image count" <|
            \_ ->
                Expect.equal
                    [ Templates.adjacent 1 1 Nothing |> Maybe.map .name
                    , Templates.adjacent -1 2 Nothing |> Maybe.map .name
                    , Templates.adjacent 1 0 Nothing |> Maybe.map .name
                    ]
                    [ Just "Art Deco (1 image)", Just "Deep Space (2 images)", Just "Art Deco" ]
        , test "every template gives dropdowns an inset chevron instead of the browser's cramped arrow" <|
            \_ ->
                Templates.all
                    |> List.filter (\t -> not (String.contains "appearance: none" t.css && String.contains "select.custom-css-template-select" t.css))
                    |> List.map .name
                    |> Expect.equal []
        , test "grouped has one group per style, three templates each, covering every template" <|
            \_ ->
                Expect.equal
                    ( List.length Templates.grouped, List.all (\( _, ts ) -> List.length ts == 3) Templates.grouped, List.concatMap Tuple.second Templates.grouped )
                    ( 37, True, Templates.all )
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


notIn : List Int -> Int -> Bool
notIn allowed n =
    not (List.member n allowed)
