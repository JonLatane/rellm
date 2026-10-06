module UI.CustomCssStylesheet exposing (stylesheet, view)

{-| A `<style>` tag with the page's own server's Custom CSS (`CustomCSSConfiguration`: `--custom-media-N`
vars for its `media_ids`, then the admin's CSS), rendered by Elm -- only while
`Shared.AccountsPanel.Model.customCssOverride` is set. Normally the server's stylesheet reaches the
page through `index.html`'s `<link>` to `/custom_css.css` (see `backend/src/web/custom_css.rs`), and
this renders nothing; it exists for the cases that `<link>` can't cover:

  - the Elm dev server, which has no Rust server behind that `<link>` (see `AccountsPanel.devCustomCssCmd`);
  - the Theme tab's Custom CSS editor, previewing an unsaved draft live, and showing a just-saved one
    without a page reload (see `ThemeTab.CustomCssConfiguration`).

It's rendered right after `UI.EmittedStylesheet` -- later in the document than `index.html`'s `<link>`s --
so, at equal specificity, it overrides them, the same "appended to the default CSS" order the real
stylesheet has. The media vars are absolute URLs on the server (`RellmServers.mediaUrl`), since this
page may not be served from the same origin as the media (the dev server isn't).

-}

import Html exposing (Html, node, text)
import Html.Attributes exposing (id)
import Proto.Rellm exposing (CustomCSSConfiguration)
import Shared
import Shared.AccountsPanel.RellmServers as RellmServers


view : Shared.Model -> Html msg
view shared =
    case shared.accounts.customCssOverride of
        Just config ->
            let
                maybeServer : Maybe RellmServers.RellmServer
                maybeServer =
                    shared.accounts.servers
                        |> List.filter (\server -> server.frontendHost == shared.accounts.mainFrontendHost)
                        |> List.head
            in
            node "style" [ id "custom-css-stylesheet" ] [ text (stylesheet (\mediaId -> maybeServer |> Maybe.andThen (\server -> RellmServers.mediaUrl server mediaId)) config) ]

        Nothing ->
            text ""


{-| Mirrors the backend's `custom_css_stylesheet`: a `:root` block with `--custom-media-N` (1-based, in
`media_ids` order) as `url("...")`, then the CSS verbatim. A media id with no resolvable URL (server
disconnected) is skipped but still occupies its number, like the backend skips an unsafe id.
-}
stylesheet : (String -> Maybe String) -> CustomCSSConfiguration -> String
stylesheet mediaUrl config =
    let
        vars : List String
        vars =
            config.mediaIds
                |> List.indexedMap
                    (\index mediaId ->
                        mediaUrl mediaId
                            |> Maybe.map (\url -> "  --custom-media-" ++ String.fromInt (index + 1) ++ ": url(\"" ++ url ++ "\");\n")
                    )
                |> List.filterMap identity
    in
    (if List.isEmpty vars then
        ""

     else
        ":root {\n" ++ String.concat vars ++ "}\n"
    )
        ++ config.customCss
