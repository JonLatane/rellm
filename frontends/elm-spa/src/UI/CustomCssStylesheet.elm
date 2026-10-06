module UI.CustomCssStylesheet exposing (stylesheet, view)

{-| A `<style>` tag with the page's own server's custom CSS variables and, while one is set, its Custom CSS
(`CustomCSSConfiguration`), rendered by Elm. It always defines `--primary-color` and `--nav-color` -- the
server's primary and navigation colors, live from `Shared.AccountsPanel.mainServerTheme`, so editing a color on
the Theme tab shows up in custom CSS immediately. (The backend's `/custom_css.css` defines the same two, from the
same configured colors, so they're there on first paint, before Elm has booted.)

Beyond that it renders the stylesheet itself -- `--custom-media-N` vars for the `media_ids`, then the admin's CSS
-- only while `Shared.AccountsPanel.Model.customCssPreview` or `customCssOverride` is set. Normally the server's
stylesheet reaches the page through `index.html`'s `<link>` to `/custom_css.css` (see
`backend/src/web/custom_css.rs`); the rest exists for the cases that `<link>` can't cover:

  - the Elm dev server, which has no Rust server behind that `<link>` (see `AccountsPanel.devCustomCssCmd`);
  - the Theme tab's Custom CSS editor: "Preview" renders an unsaved draft here *instead of* the saved
    stylesheet (`customCssPreview` -- the `<link>` is switched off meanwhile, see `Ports.setCustomCssStylesheet`),
    and a just-saved config covers the gap until the `<link>` reloads (`customCssOverride`, see
    `ThemeTab.CustomCssConfiguration`).

It's rendered right after `UI.EmittedStylesheet` -- later in the document than `index.html`'s `<link>`s --
so, at equal specificity, it overrides them, the same "appended to the default CSS" order the real
stylesheet has. The media vars are absolute URLs on the server (`RellmServers.mediaUrl`), since this
page may not be served from the same origin as the media (the dev server isn't).

-}

import Html exposing (Html, node, text)
import Html.Attributes exposing (id)
import Proto.Rellm exposing (CustomCSSConfiguration, defaultCustomCSSConfiguration)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers
import UI.ServerTheme


view : Shared.Model -> Html msg
view shared =
    let
        theme : UI.ServerTheme.ServerTheme
        theme =
            AccountsPanel.mainServerTheme (Shared.effectiveDarkMode shared) shared.accounts

        maybeServer : Maybe RellmServers.RellmServer
        maybeServer =
            shared.accounts.servers
                |> List.filter (\server -> server.frontendHost == shared.accounts.mainFrontendHost)
                |> List.head

        mediaUrl : String -> Maybe String
        mediaUrl mediaId =
            maybeServer |> Maybe.andThen (\server -> RellmServers.mediaUrl server mediaId)

        -- A preview, when there is one, is the only custom stylesheet; with neither, just the color variables.
        config : CustomCSSConfiguration
        config =
            case ( shared.accounts.customCssPreview, shared.accounts.customCssOverride ) of
                ( Just preview, _ ) ->
                    preview

                ( Nothing, Just override ) ->
                    override

                ( Nothing, Nothing ) ->
                    defaultCustomCSSConfiguration
    in
    node "style"
        [ id "custom-css-stylesheet" ]
        [ text (stylesheet { primaryColor = theme.primaryColor, navColor = theme.navColor } mediaUrl config) ]


{-| Mirrors the backend's `custom_css_stylesheet`: one `:root` block defining `--primary-color` and `--nav-color`
(given as `#rrggbb`) and `--custom-media-N` (1-based, in `media_ids` order) as `url("...")`, then the CSS
verbatim. A media id with no resolvable URL (server disconnected) is skipped but still occupies its number,
like the backend skips an unsafe id.
-}
stylesheet : { primaryColor : String, navColor : String } -> (String -> Maybe String) -> CustomCSSConfiguration -> String
stylesheet colors mediaUrl config =
    let
        mediaVars : List String
        mediaVars =
            config.mediaIds
                |> List.indexedMap
                    (\index mediaId ->
                        mediaUrl mediaId
                            |> Maybe.map (\url -> "  --custom-media-" ++ String.fromInt (index + 1) ++ ": url(\"" ++ url ++ "\");\n")
                    )
                |> List.filterMap identity
    in
    ":root {\n  --primary-color: "
        ++ colors.primaryColor
        ++ ";\n  --nav-color: "
        ++ colors.navColor
        ++ ";\n"
        ++ String.concat mediaVars
        ++ "}\n"
        ++ Maybe.withDefault "" config.customCss
