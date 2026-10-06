module CustomCssStylesheetTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Proto.Rellm exposing (CustomCSSConfiguration)
import UI.CustomCssStylesheet exposing (stylesheet)


{-| A config with just media and CSS set (no forced theme).
-}
config : List String -> String -> CustomCSSConfiguration
config mediaIds css =
    { mediaIds = mediaIds, customCss = Just css, forceLightTheme = False, forceDarkTheme = False }


suite : Test
suite =
    describe "UI.CustomCssStylesheet.stylesheet"
        [ test "defines 1-based --custom-media-N vars before the CSS" <|
            \_ ->
                stylesheet (\id -> Just ("https://example.com/media/" ++ id))
                    (config [ "abc", "def" ] "body { color: red; }")
                    |> Expect.equal
                        (":root {\n  --custom-media-1: url(\"https://example.com/media/abc\");\n  --custom-media-2: url(\"https://example.com/media/def\");\n}\nbody { color: red; }")
        , test "with no media, is just the CSS" <|
            \_ ->
                stylesheet (\_ -> Nothing) (config [] "a {}")
                    |> Expect.equal "a {}"
        , test "a media id with no URL is skipped but keeps its number" <|
            \_ ->
                stylesheet
                    (\id ->
                        if id == "gone" then
                            Nothing

                        else
                            Just ("/media/" ++ id)
                    )
                    (config [ "gone", "ok" ] "")
                    |> Expect.equal ":root {\n  --custom-media-2: url(\"/media/ok\");\n}\n"
        ]
