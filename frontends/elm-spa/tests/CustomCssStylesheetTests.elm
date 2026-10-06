module CustomCssStylesheetTests exposing (suite)

import Expect
import Proto.Rellm exposing (CustomCSSConfiguration, defaultCustomCSSConfiguration)
import Test exposing (Test, describe, test)
import UI.CustomCssStylesheet exposing (stylesheet)


{-| A config with just media and CSS set (no forced theme).
-}
config : List String -> String -> CustomCSSConfiguration
config mediaIds css =
    { mediaIds = mediaIds, customCss = Just css, forceLightTheme = False, forceDarkTheme = False }


colors : { primaryColor : String, navColor : String }
colors =
    { primaryColor = "#07edde", navColor = "#ffbfa5" }


{-| What every stylesheet starts with.
-}
colorVars : String
colorVars =
    "  --primary-color: #07edde;\n  --nav-color: #ffbfa5;\n"


suite : Test
suite =
    describe "UI.CustomCssStylesheet.stylesheet"
        [ test "defines --primary-color and --nav-color, then 1-based --custom-media-N vars, before the CSS" <|
            \_ ->
                stylesheet colors
                    (\id -> Just ("https://example.com/media/" ++ id))
                    (config [ "abc", "def" ] "body { color: red; }")
                    |> Expect.equal
                        (":root {\n"
                            ++ colorVars
                            ++ "  --custom-media-1: url(\"https://example.com/media/abc\");\n  --custom-media-2: url(\"https://example.com/media/def\");\n}\nbody { color: red; }"
                        )
        , test "with no media, is the color variables then the CSS" <|
            \_ ->
                stylesheet colors (\_ -> Nothing) (config [] "a {}")
                    |> Expect.equal (":root {\n" ++ colorVars ++ "}\na {}")
        , test "with no custom CSS at all, is just the color variables" <|
            \_ ->
                stylesheet colors (\_ -> Nothing) defaultCustomCSSConfiguration
                    |> Expect.equal (":root {\n" ++ colorVars ++ "}\n")
        , test "a media id with no URL is skipped but keeps its number" <|
            \_ ->
                stylesheet colors
                    (\id ->
                        if id == "gone" then
                            Nothing

                        else
                            Just ("/media/" ++ id)
                    )
                    (config [ "gone", "ok" ] "")
                    |> Expect.equal (":root {\n" ++ colorVars ++ "  --custom-media-2: url(\"/media/ok\");\n}\n")
        ]
