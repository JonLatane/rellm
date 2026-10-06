module CustomCssStylesheetTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import UI.CustomCssStylesheet exposing (stylesheet)


suite : Test
suite =
    describe "UI.CustomCssStylesheet.stylesheet"
        [ test "defines 1-based --custom-media-N vars before the CSS" <|
            \_ ->
                stylesheet (\id -> Just ("https://example.com/media/" ++ id))
                    { mediaIds = [ "abc", "def" ], customCss = "body { color: red; }" }
                    |> Expect.equal
                        (":root {\n  --custom-media-1: url(\"https://example.com/media/abc\");\n  --custom-media-2: url(\"https://example.com/media/def\");\n}\nbody { color: red; }")
        , test "with no media, is just the CSS" <|
            \_ ->
                stylesheet (\_ -> Nothing) { mediaIds = [], customCss = "a {}" }
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
                    { mediaIds = [ "gone", "ok" ], customCss = "" }
                    |> Expect.equal ":root {\n  --custom-media-2: url(\"/media/ok\");\n}\n"
        ]
