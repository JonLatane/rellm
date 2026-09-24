module UI.EmittedStylesheet exposing (view)

{-| A `<style>` tag, computed fresh from the current `Shared.Model` on every
render (so it updates automatically any time a server is added/removed, or
the current server/dark-light mode changes): `mainFrontendServerRules` (root
element rules -- `a`, switches, buttons -- driven by `mainFrontendHost`'s
theme, standing in for what used to be the static `--accent` CSS var), plus,
for each known server -- `shared.accounts.servers`, plus (so
`UI.recommendedServerChip` can tint itself with its own brand color before
it's actually been added) `shared.accounts.recommendedServerConnections`
-- a handful of color "utility class" pairs so any element can be given that
server's colors just by adding two classes -- e.g.
`class="jonline-io background-color-primary"` -- rather than needing that
server's `ServerTheme` threaded in as a view-function argument.

  - `<host> background-color-primary` -- `primaryColor` / `primaryTextColor`
  - `<host> background-color-nav` -- `navColor` / `navTextColor`
  - `<host> background-color-primary-background` -- `primaryBgColor` / `textColor`
  - `<host> border-color-primary` -- `primaryColor` (border-color only)
  - `<host> border-color-primary-anchor` -- `primaryAnchorColor` (border-color only; unused so far, but establishes the naming convention below)
  - `<host> border-color-primary-anchor-50` -- `primaryAnchorColor` at 50% opacity (border-color only)
  - `<host> hover-border-color-primary-anchor` -- `primaryAnchorColor` (border-color only), applied only on `:hover` -- pair with `border-color-primary-anchor-50` (or similar) for a border that "fills in" on hover; add `transition: border-color` yourself if you want that to animate, since this class alone is just the `:hover` color rule.
  - `<host> list-item-bordered-color-primary` -- `primaryColor` (border-left + border-bottom + border-radius only), for a list item with a colored left stripe and bottom edge, but no background color (see `Components.Pages.UserProfilePage`'s `sync-source-row`).
  - `<host> border-left-thick-color-primary` -- `primaryColor`, but (unlike the plain `border-color-*` classes above, which only ever set `border-color` and rely on some other rule to have already given the element a border width+style to color) sets `border-left` itself (`4px solid`), so a plain element gets a colored left "stripe" just by adding this one class -- see `Components.Pages.UserProfilePage`'s `sync-source-row`.
  - `<host> post-star.starred` -- `primaryAnchorColor` (text color only), used by `Components.Posts`' star button to fill in once a Post is starred (see `Shared.StarredPanel`); `.post-star`'s own `transition` (in `posts.css`) is what animates it. `mainFrontendServerRules` also emits a bare, unscoped `.post-star.starred` rule (`mainFrontendHost`'s own `primaryAnchorColor`) as this class pair's fallback -- a Mastodon/Bluesky post's `postServerHost` (`"mastodon:"`/`"bluesky:"`-tagged, see `Components.Posts.isFederatedHost`) never matches a real `RellmServer`'s own `<host>` class below, so without this it'd only ever get `.post-star.starred`'s plain CSS-transition scale-up (`posts.css`), never a color to transition to. A real server's own `<host> post-star.starred` rule still wins over this one regardless of emission order (a class-scoped selector is more specific than a bare one).
  - `<host> post-card-current .post-star` -- `backgroundColor` at 50% opacity (background-color only) -- backs the star button of a `Components.Posts.postCard` marked `current` (see `Shared.StarredPanel.view`) with the app's own light/dark background, since its usual `primaryAnchorColor` text doesn't reliably contrast against that same card's `primaryColor` fill; semi-transparent (same "-50" convention as `border-color-primary-anchor-50`) so it reads as a tint rather than a flat patch. The pill shape itself is `posts.css`'s `.post-card-current .post-star`.
  - `<host> event-card-current .post-star` -- same rule as `post-card-current .post-star` just above, for `Components.Events.eventCard`'s own `current` marker instead of `postCard`'s.

This is cheap to regenerate (it's just string-building); the actual expensive
color math is already cached in `Shared.Branding`.

-}

import Dict
import Html exposing (Html, node, text)
import Html.Attributes exposing (id)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmServers as RellmServers exposing (Branding, RellmServer)
import UI.Classes exposing (hostnameToCSSClass)
import UI.ServerTheme


view : Shared.Model -> Html msg
view shared =
    node "style" [ id "emitted-stylesheet" ] [ text (css shared) ]


css : Shared.Model -> String
css shared =
    let
        darkMode : Bool
        darkMode =
            Shared.effectiveDarkMode shared

        mainTheme : UI.ServerTheme.ServerTheme
        mainTheme =
            AccountsPanel.mainServerTheme darkMode shared.accounts
    in
    mainFrontendServerRules mainTheme shared.accounts
        ++ String.concat
            (List.map (serverRules darkMode mainTheme shared.accounts.mainFrontendHost)
                (shared.accounts.servers ++ Dict.values shared.accounts.recommendedServerConnections)
            )


{-| Root-element rules driven by `mainFrontendHost`'s theme -- these apply
app-wide (not scoped to a per-server class) since they stand in for what used
to be the single, static `--accent` CSS var: every link's color, and the
"on" color of every toggle switch. (A selected `web-ui-button` is tinted with
its own account's server, via the per-server `background-color-primary`
utility class below -- see `UI.elm`'s `webUiButton`.)

The one exception is contrast against a switch's own row: an `account-row`
for an account on `mainFrontendHost` itself is already tinted with that
host's `primaryColor` (see `UI.elm`'s `accountRow`), so `primaryAnchorColor`
(derived from that same `primaryColor`) wouldn't read as well there as
`navAnchorColor` does. The `.account-row` rule's selector is more specific
than the plain switch rule above, so it wins there regardless of rule
order. Other accounts' rows aren't tinted with `mainFrontendHost`'s colors
at all, so they don't need (or get) this override.

-}
mainFrontendServerRules : UI.ServerTheme.ServerTheme -> AccountsPanel.Model -> String
mainFrontendServerRules theme accountsPanel =
    let
        mainHostSelector : String
        mainHostSelector =
            "." ++ hostnameToCSSClass accountsPanel.mainFrontendHost
    in
    String.concat
        [ "a { color: " ++ theme.primaryAnchorColor ++ "; }\n"
        , textColorRule ".post-star.starred" theme.primaryAnchorColor
        , ".switch input:checked + .slider { background: " ++ theme.primaryAnchorColor ++ "; }\n"
        , ".account-row" ++ mainHostSelector ++ " .switch input:checked + .slider { background: " ++ theme.navAnchorColor ++ "; }\n"
        , ".nav-link:hover { background-color:" ++ theme.navColor ++ "88; }\n"
        , colorRule ".events-calendar .fc .fc-button-primary:not(:disabled).fc-button-active" theme.accentColor theme.accentTextColor
        , borderColorRule ".events-calendar .fc .fc-button-primary:not(:disabled).fc-button-active" theme.accentColor
        , ":root { --calendar-accent: " ++ theme.navColor ++ "; }\n"
        , ".events-list:not(:has(>* .events-calendar)), .events-strip, .events-calendar { background-color:" ++ theme.backgroundColor ++ "BB; backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px); }"
        , ".base-colors-half { background-color: " ++ theme.backgroundColor ++ "BB; color: " ++ theme.textColor ++ "; }\n"
        ]


serverRules : Bool -> UI.ServerTheme.ServerTheme -> String -> RellmServer -> String
serverRules darkMode mainTheme mainFrontendHost server =
    let
        theme : UI.ServerTheme.ServerTheme
        theme =
            RellmServers.rellmServerThemeOf darkMode server

        branding : Branding
        branding =
            RellmServers.brandingOf server

        selector : String
        selector =
            "." ++ hostnameToCSSClass server.frontendHost

        -- The server chip's enable switch sits on a `background-color-nav`
        -- (this server's own navColor) tile, so its "on" color needs to
        -- contrast against *that* rather than the generic switch rule's
        -- mainFrontendHost.primaryAnchorColor (see `mainFrontendServerRules`)
        -- -- same idea as that rule's `.account-row` override, but keyed off
        -- this server's navColor lightness instead of darkMode.
        switchOnColor : String
        switchOnColor =
            if branding.nav.isDark then
                mainTheme.primaryDarkColor

            else
                mainTheme.primaryLightColor

        accountRowSwitchRule : String
        accountRowSwitchRule =
            if server.frontendHost == mainFrontendHost then
                ""

            else
                let
                    -- Same idea for an account row's switch, keyed off this server's
                    -- primaryColor lightness (what `account-row` is tinted with) instead
                    -- of navColor. Skipped for mainFrontendHost -- its account rows are
                    -- already handled by `mainFrontendServerRules`' own `.account-row`
                    -- override, which uses navAnchorColor rather than this
                    -- light/dark-of-primaryColor logic.
                    accountSwitchOnColor : String
                    accountSwitchOnColor =
                        if branding.primary.isDark then
                            mainTheme.primaryDarkColor

                        else
                            mainTheme.primaryLightColor
                in
                ".account-row" ++ selector ++ " .switch input:checked + .slider { background: " ++ accountSwitchOnColor ++ "; }\n"

        listItemColorRule : String
        listItemColorRule =
            withDescendants selector ".list-item-bordered-color-primary" ++ " { border-left: 4px solid " ++ theme.primaryAnchorColor ++ "; border-bottom: 2px solid " ++ theme.primaryAnchorColor ++ "; border-top: 1px solid " ++ theme.navAnchorColor ++ "88; border-right: 1px solid " ++ theme.navAnchorColor ++ "88; border-radius: 4px; }\n"
    in
    String.concat
        [ colorRule (withDescendants selector ".background-color-primary") theme.primaryColor theme.primaryTextColor
        , textColorRule (selector ++ ".background-color-primary:not(.navbar, .account-row) a") <|
            if theme.primaryLuma > 0.55 then
                theme.navDarkColor

            else
                theme.navLightColor
        , colorRule (withDescendants selector ".background-color-primary-5") (theme.primaryColor ++ "05") theme.textColor
        , colorRule (withDescendants selector ".background-color-primary-10") (theme.primaryColor ++ "10") theme.textColor
        , colorRule (withDescendants selector ".background-color-primary-25") (theme.primaryColor ++ "40") theme.textColor
        , colorRule (withDescendants selector ".background-color-primary-50") (theme.primaryColor ++ "80") theme.textColor
        , colorRule (withDescendants selector ".background-color-nav") theme.navColor theme.navTextColor
        , colorRule (withDescendants selector ".background-color-nav-contrast") theme.navContrastColor theme.backgroundColor
        , colorRule (withDescendants selector ".background-color-accent") theme.accentColor theme.accentTextColor
        , colorRule (withDescendants selector ".background-color-accent-5") (theme.accentColor ++ "08") theme.textColor
        , colorRule (withDescendants selector ".background-color-accent-10") (theme.accentColor ++ "10") theme.textColor
        , colorRule (withDescendants selector ".background-color-accent-anchor") theme.accentAnchorColor theme.backgroundColor
        , colorRule (withDescendants selector ".background-color-primary-background") theme.primaryBgColor theme.textColor
        , borderColorRule (withDescendants selector ".border-color-primary") theme.primaryColor
        , borderColorRule (withDescendants selector ".border-color-nav") theme.navColor
        , borderColorRule (withDescendants selector ".border-color-accent") theme.accentColor
        , borderColorRule (withDescendants selector ".border-color-primary-text") theme.primaryTextColor
        , borderColorRule (withDescendants selector ".border-color-primary-anchor") theme.primaryAnchorColor
        , borderColorRule (withDescendants selector ".border-color-primary-anchor-50") (theme.primaryAnchorColor ++ "80")
        , borderColorRule (withDescendants selector ".border-color-nav-text") theme.navTextColor
        , borderColorRule (withDescendants selector ".hover-border-color-primary-anchor:hover") theme.primaryAnchorColor
        , listItemColorRule
        , borderLeftThickColorRule (withDescendants selector ".border-left-thick-color-primary") theme.primaryColor
        , textColorRule (selector ++ ".post-star.starred") theme.primaryAnchorColor
        , backgroundOnlyColorRule (selector ++ ".post-card-current .post-star") (theme.backgroundColor ++ "80")
        , backgroundOnlyColorRule (selector ++ ".event-card-current .post-star") (theme.backgroundColor ++ "80")
        , ".server-chip-bottom" ++ selector ++ " .switch input:checked + .slider { background: " ++ switchOnColor ++ "; }\n"
        , textColorRule (withDescendants selector ".text-color-primary-anchor") theme.primaryAnchorColor
        , textColorRule ("a" ++ selector) theme.primaryAnchorColor
        , accountRowSwitchRule
        ]


withDescendants : String -> String -> String
withDescendants selector subselector =
    selector ++ subselector ++ ", " ++ selector ++ " " ++ subselector


colorRule : String -> String -> String -> String
colorRule selector backgroundColor foregroundColor =
    selector ++ " { background-color: " ++ backgroundColor ++ "; color: " ++ foregroundColor ++ "; }\n"


backgroundOnlyColorRule : String -> String -> String
backgroundOnlyColorRule selector backgroundColor =
    selector ++ " { background-color: " ++ backgroundColor ++ "; }\n"


borderColorRule : String -> String -> String
borderColorRule selector borderColor =
    selector ++ " { border-color: " ++ borderColor ++ "; }\n"


borderLeftThickColorRule : String -> String -> String
borderLeftThickColorRule selector borderColor =
    selector ++ " { border-left: 4px solid " ++ borderColor ++ "; }\n"


textColorRule : String -> String -> String
textColorRule selector color =
    selector ++ " { color: " ++ color ++ "; }\n"
