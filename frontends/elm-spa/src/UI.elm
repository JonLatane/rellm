module UI exposing (imageOrInitial, layout, pageTitle, themeToggle, webUiToggleRow)

import Components.Events as Events
import Components.Markdown as Markdown
import Components.Posts as Posts
import Components.SyncSources as SyncSources
import Components.Users as Users
import Dict
import Gen.Route as Route exposing (Route)
import Html exposing (Attribute, Html, a, button, div, header, img, input, label, li, main_, nav, option, p, select, span, text, ul)
import Html.Attributes exposing (alt, attribute, checked, class, classList, disabled, href, id, name, novalidate, placeholder, selected, spellcheck, src, style, target, title, type_, value)
import Html.Events exposing (on, onClick, onInput, onSubmit, preventDefaultOn, stopPropagationOn)
import Html.Keyed
import Json.Decode as Decode
import Proto.Rellm exposing (ContactConsentChange, ContactMethod, FederatedServer, MastodonServer)
import Proto.Rellm.ContactConsentState exposing (ContactConsentState(..))
import Proto.Rellm.NavigationTabStyle exposing (NavigationTabStyle)
import Proto.Rellm.SyncSource.Configuration as Configuration
import Proto.Rellm.Visibility exposing (Visibility)
import Proto.Rellm.WebUserInterface exposing (WebUserInterface(..))
import Set
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.AdminTab as AdminTab
import Shared.AccountsPanel.BlueskyAccounts exposing (BlueskyAccount)
import Shared.AccountsPanel.DebugTab as DebugTab
import Shared.AccountsPanel.MastodonAccounts exposing (MastodonAccount)
import Shared.AccountsPanel.MastodonServers exposing (BrowsedMastodonInstance)
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (Branding, RellmServer)
import Shared.Breadcrumbs as Breadcrumbs
import Shared.ByteFormat as ByteFormat
import Shared.Conversions exposing (timestampToPosix)
import Shared.CreateNewPanel as CreateNewPanel
import Shared.FederatedAuth as FederatedAuth
import Shared.MarkdownPanel as MarkdownPanel
import Shared.MediaGeneratorPanel as MediaGeneratorPanel
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.MessagingPanel as MessagingPanel
import Shared.MyMediaPanel as MyMediaPanel
import Shared.StarredPanel as StarredPanel
import Shared.Time as SharedTime
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.CustomNav as CustomNav
import UI.EmittedStylesheet as EmittedStylesheet
import UI.Flip
import UI.HtmlEvents exposing (stopPropagationAndPreventDefaultOnClick)
import UI.Modal
import Url


{-| The nav (`header`) is a full-width, sticky band tinted with
`mainFrontendHost`'s `primaryColor` (see `UI.EmittedStylesheet`'s
`background-color-primary` utility class) -- its own `.navbar-inner` wrapper
keeps its content lined up with the (narrower) page content below. `main` gets
its own `.container` so it's centered independently of the nav.

Generic in `msg` (via `toMsg`) so pages with their own `Model`/`Msg` -- rather
than just `page`'s no-local-state pages -- can embed this nav/login chrome
too, mapping its `Shared.Msg` clicks into their own `Msg` type. See
`Pages.Home_`/`Pages.Post.PostId_`.

-}
layout : Shared.Model -> Route -> (Shared.Msg -> msg) -> List (Html msg) -> List (Html msg)
layout shared currentRoute toMsg children =
    [ Html.map toMsg (EmittedStylesheet.view shared)
    , Html.map toMsg (sharedBackdrop shared)
    , Html.map toMsg (headerNav shared currentRoute)
    , Html.map toMsg (createAccountConfirmationBackdrop shared)
    , Html.map toMsg (createAccountConfirmationModal shared)
    , Html.map toMsg (deleteConfirmationBackdrop shared)
    , Html.map toMsg (deleteConfirmationModal shared)
    , Html.map toMsg (createNewPanel shared)
    , Html.map toMsg (markdownPanel shared)
    , Html.map toMsg (mediaGeneratorPanel shared)
    , Html.map toMsg (myMediaPanel shared)
    , Html.map toMsg (mediaViewerPanel shared)
    , Html.map toMsg (federatedSignInNoticeView shared)
    , div [ classes [ "container", hostnameToCSSClass shared.accounts.mainFrontendHost ] ] [ main_ [] (children ++ [ scrollPreserver shared ]) ]
    ]


{-| A brief "Signed in as ..." toast for `AccountsPanel.Model.federatedSignInNotice` -- see that
field's own doc. Reuses `avatarOrPlaceholder`/`RellmAccounts.rellmAccountDisplayName`, the same building blocks
`accountRow` itself uses, so it reads as the same account identity the Accounts Panel would show.
Dismissible early by clicking it; otherwise `AccountsPanel.federatedSignInNoticeDuration` clears it on
its own.
-}
federatedSignInNoticeView : Shared.Model -> Html Shared.Msg
federatedSignInNoticeView shared =
    case shared.accounts.federatedSignInNotice of
        Nothing ->
            text ""

        Just account ->
            div
                [ classes [ "federated-sign-in-notice", hostnameToCSSClass account.server, "background-color-primary" ]
                , onClick (Shared.AccountsPanelMsg AccountsPanel.DismissFederatedSignInNotice)
                ]
                [ avatarOrPlaceholder shared.accounts.servers account
                , div [ class "federated-sign-in-notice-text" ]
                    [ div [ class "federated-sign-in-notice-title" ] [ text "Signed in as" ]
                    , div [ class "federated-sign-in-notice-name" ] [ text (RellmAccounts.rellmAccountDisplayName account) ]
                    , div [ class "federated-sign-in-notice-server" ] [ text account.server ]
                    ]
                ]


{-| A tall, empty spacer at the bottom of `main_`'s content -- shown (see
`Shared.Model.scrollPreserverVisible`) for the first 2s after navigating back
to a page (browser back button only, not a fresh link click -- see change 4 in
`Main.elm`'s module doc), so that page's content, which can still be shorter
than it was when the browser recorded the scroll offset it's now restoring,
doesn't get its scroll position yanked around while it fills back in. Always
rendered, like `sharedBackdrop`'s `is-open`/`is-closed` -- see
`UI.Classes.openClosedClass` -- rather than added/removed outright, so the
`height` change (see `main.css`) is a plain CSS transition.
-}
scrollPreserver : Shared.Model -> Html msg
scrollPreserver shared =
    div [ classes [ "scroll-preserver", openClosedClass shared.scrollPreserverVisible ] ] []


{-| Tapping the navbar anywhere outside the Home link, the Starred
toggle/panel, or the Accounts menu/panel scrolls the page to top -- same
`Shared.ScrollToTop` that re-tapping Home while already on it fires (see
`navLink`'s doc). Those three carve themselves out of this via
`stopPropagationOn "click"` on their own root elements (`navLink`,
`starredPostsToggle`, `accountsMenu`'s `.accounts-menu` div) rather than
`onClick`, so a tap on any of them (or their own dropdowns/menus) never
bubbles up to this handler; `starredPanel` isn't itself one of those
three roots (it's rendered as its own `.navbar` child, not nested under
`starredPostsToggle` -- see the comment below), so it gets its own wrapper
here instead.
-}
headerNav : Shared.Model -> Route -> Html Shared.Msg
headerNav shared currentRoute =
    header
        [ classes [ "navbar", hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-primary" ]
        , onClick Shared.ScrollToTop
        ]
        [ div [ class "navbar-inner" ]
            [ nav [ classes [ "nav-links", CustomNav.navigationTabStyleClass (currentTabStyle shared) ] ]
                [ navLink shared currentRoute (homeLinkContent shared) Route.Home_
                , div [ class "nav-links-scroll", on "scroll" navLinksScrollDecoder ]
                    ([ if Set.isEmpty shared.panels.starredPanel.starredPostIds then
                        text ""

                       else
                        starredPostsToggle shared
                     , if MessagingPanel.hasEligibleAccount shared.accounts then
                        messagingToggle shared currentRoute

                       else
                        text ""
                     , if CreateNewPanel.hasEligibleAccount shared.accounts then
                        newPostToggle shared

                       else
                        text ""
                     ]
                        ++ customTabLinks shared currentRoute
                    )
                ]
            , div [ class "nav-right" ] [ accountsMenu shared currentRoute ]
            ]

        -- A direct child of `.navbar` itself (a positioned ancestor spanning
        -- the full viewport width), not of `.starred-menu` (the toggle's own
        -- narrow wrapper, off to one side) -- so `.starred-panel`'s
        -- `left: 0` in starred_panel.css hugs the actual screen edge instead of just
        -- the toggle's left edge. See `starredPanel`.
        --
        -- Wrapped in its own `stopPropagationOn`-bearing `div` (a plain,
        -- unpositioned element, so it doesn't disturb the `left`/`top` math
        -- above -- that's all resolved against `.navbar` itself, the nearest
        -- *positioned* ancestor, not the immediate parent) so taps inside the
        -- open panel don't also bubble up to this `Shared.ScrollToTop`
        -- tap-anywhere handler.
        , if Set.isEmpty shared.panels.starredPanel.starredPostIds then
            text ""

          else
            div [ stopPropagationOn "click" (Decode.succeed ( Shared.NoOp, True )) ]
                [ starredPanel shared currentRoute ]

        -- Mirrors `starredPanel`'s own mount just above -- a `.navbar`
        -- direct child (not `messagingToggle`'s own narrow wrapper) for the
        -- same "hug the actual screen edge" reason.
        , if MessagingPanel.hasEligibleAccount shared.accounts then
            div [ stopPropagationOn "click" (Decode.succeed ( Shared.NoOp, True )) ]
                [ messagingPanel shared ]

          else
            text ""

        -- Sits below `.navbar-inner`, at the very bottom of `.navbar` itself
        -- -- see `breadcrumbsBar`.
        , breadcrumbsBar shared

        -- A direct child of `.navbar` too (not just `breadcrumbsBar`'s own
        -- wrapper), same reasoning as `starredPanel` above -- so it's
        -- anchored to the full-width `.navbar`'s own bottom edge (which
        -- includes `breadcrumbsBar`'s row) rather than just some narrower
        -- element's. See `breadcrumbsReplyPanel`.
        , breadcrumbsReplyPanel shared
        ]


{-| Reads `.nav-links-scroll`'s `scrollLeft`/`scrollWidth`/`clientWidth` off
its own `scroll` event target, fired into `Shared.NavLinksScrolled` -- see
`Shared.NavAnimationState`'s own doc, and `navLink`/`Shared.navLinkHomeMaxWidth`,
its consumer.
-}
navLinksScrollDecoder : Decode.Decoder Shared.Msg
navLinksScrollDecoder =
    Decode.map3 (\scrollLeft scrollWidth clientWidth -> { scrollLeft = scrollLeft, scrollWidth = scrollWidth, clientWidth = clientWidth })
        (Decode.at [ "target", "scrollLeft" ] Decode.float)
        (Decode.at [ "target", "scrollWidth" ] Decode.float)
        (Decode.at [ "target", "clientWidth" ] Decode.float)
        |> Decode.map Shared.NavLinksScrolled


{-| One entry in `sharedBackdrop`'s priority list: whether this panel is
currently open, the message that closes just this panel, and whether its
being open should blur/tint the shared backdrop (the Accounts Panel and the
Markdown panel both block interaction with the rest of the page like that --
see `sharedBackdrop`).
-}
type alias BackdropPanel =
    { isOpen : Bool
    , closeMsg : Shared.Msg
    , blurs : Bool
    }


{-| Covers everything except the top nav (which sits in its own, higher
stacking context -- see `.navbar` in nav.css) for every panel that closes
via a background tap -- currently the Starred panel, the Accounts
Panel, the Breadcrumbs reply viewer, the Markdown panel and the New Post
panel, with more expected to join this list later. Always rendered, like the panels
themselves, so opening/closing (and the blur) is a plain CSS transition
rather than the element appearing/disappearing outright, and only receives
clicks (`pointer-events`) while at least one listed panel is open.

The Media Viewer panel is deliberately not one of these -- unlike the others,
its own box already spans the whole viewport rather than a small, anchored
dropdown, and it sits above `.navbar` itself (see media\_viewer\_panel.css), so
it can't rely on this backdrop (below `.navbar`, see nav.css) for its own
dimming/click-to-close anyway. It owns both outright instead: its own
background _is_ the dimmed/blurred overlay, and its own root `onClick` is
the background-tap-to-close, both self-contained in
`Shared.MediaViewerPanel`/media\_viewer\_panel.css -- see their own doc
comments.

Listed nearest-first: when several panels are open at once, a background tap
closes only the first one in this list (see `topmostOpenPanel`) -- one tap per
panel to peel them off in order, front-to-back, rather than closing everything
at once. Right now that means tapping the background closes the My Media panel
first, then the Markdown panel, then the New Post panel, then the Starred
Posts panel, then the Accounts Panel, then (on a sixth tap) the Breadcrumbs
reply viewer behind all five -- matching the actual paint order.
`.my-media-panel` (31, see my\_media\_panel.css), `.markdown-panel` (30, see
markdown\_panel.css) and `.create-new-panel` (29, see create\_new\_panel.css)
are all `.navbar` _siblings_ with a higher z-index than `.navbar`'s own (28),
so all three render above the whole thing -- `.navbar` and every one of its
descendants (`.breadcrumb-reply-panel`, the Accounts/Starred panels)
alike, regardless of their own individual z-indices -- in that relative order
(31 > 30 > 29): both the Markdown and My Media panels can be opened _from_
the New Post panel (`CreateNewPanel.EditContentClicked`/`EditMediaClicked`),
and should win over it while open. _Within_ `.navbar`, `.breadcrumb-reply-panel`'s
lower z-index (see nav.css) is what keeps it under the Accounts/Starred
panels specifically. Swap their order here to change any of this priority.
Only blurs/tints the page while a panel with `blurs = True` is open (currently
every one of these except the Starred panel, which doesn't block
interaction with the rest of the page since starring/unstarring posts while
it's open is an expected, encouraged interaction rather than something to
block).

-}
sharedBackdrop : Shared.Model -> Html Shared.Msg
sharedBackdrop shared =
    let
        panels : List BackdropPanel
        panels =
            [ { isOpen = MyMediaPanel.isOpen shared.panels.myMediaPanel
              , closeMsg = Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked
              , blurs = True
              }
            , { isOpen = shared.panels.markdownPanel.target /= Nothing
              , closeMsg = Shared.MarkdownPanelMsg MarkdownPanel.CancelClicked
              , blurs = True
              }

            -- Both `MarkdownPanel`/`MyMediaPanel` above can be opened *from*
            -- this panel (`CreateNewPanel.EditContentClicked`/
            -- `EditMediaClicked`), and must render on top of it while they
            -- are (see create_new_panel.css's own z-index comment), so a
            -- background tap while either's open should close that one
            -- first, not this one underneath it.
            , { isOpen = CreateNewPanel.isOpen shared.panels.createNewPanel
              , closeMsg = Shared.CreateNewPanelMsg CreateNewPanel.CloseClicked
              , blurs = True
              }
            , { isOpen = shared.panels.starredPanel.showStarredPanel
              , closeMsg = Shared.StarredPanelMsg StarredPanel.ToggleStarredPanel
              , blurs = False
              }

            -- Same non-blocking browsing reasoning as the Starred panel just
            -- above -- slotted right next to it since both are equally
            -- "peripheral" nav dropdowns.
            , { isOpen = MessagingPanel.isOpen shared.panels.messagingPanel
              , closeMsg = Shared.MessagingPanelMsg MessagingPanel.ToggleOpen
              , blurs = False
              }
            , { isOpen = shared.accounts.showAccountsPanel
              , closeMsg = Shared.AccountsPanelMsg AccountsPanel.ToggleAccountsPanel
              , blurs = True
              }
            , { isOpen = shared.breadcrumbs.viewingPost /= Nothing || shared.breadcrumbs.viewingHost
              , closeMsg = Shared.BreadcrumbsMsg Breadcrumbs.CloseViewer
              , blurs = True
              }
            ]

        topmostOpenPanel : Maybe BackdropPanel
        topmostOpenPanel =
            List.filter .isOpen panels |> List.head
    in
    div
        [ classes
            ([ "shared-backdrop", openClosedClass (topmostOpenPanel /= Nothing) ]
                ++ (if List.any (\panel -> panel.isOpen && panel.blurs) panels then
                        [ "blurred" ]

                    else
                        []
                   )
            )
        , onClick
            (topmostOpenPanel
                |> Maybe.map .closeMsg
                |> Maybe.withDefault (Shared.AccountsPanelMsg AccountsPanel.ToggleAccountsPanel)
            )
        ]
        []


{-| Fires `msg` (and suppresses the key's default effect, e.g. inserting a
newline) when Enter is pressed in a text input -- used to chain focus through
the login form and to trigger "Add Server"/"Login" the same way clicking
their buttons would.
-}
onEnter : msg -> Attribute msg
onEnter msg =
    preventDefaultOn "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "Not the Enter key"
                )
        )


{-| A nav link styled as a button: the current page's link additionally gets
`mainFrontendHost`'s `background-color-nav` utility class, tinting it with
`navColor`/`navTextColor` so it stands out against the `primaryColor`-tinted
navbar around it; other links just inherit that surrounding primary color/text
color by not overriding them. The Home link also gets its own `nav-link-home`
class (regardless of `isCurrent`) so `nav.css` can give its bigger,
stacked `RegularServerLogo` content (see `homeLinkContent`) the same
negative-margin overflow treatment as the Accounts Panel toggle, and its own
`onClick` (`Shared.HomeLinkClicked`) closing the Starred panel and,
when `isCurrent` (tapping Home while already on it), firing
`Shared.ScrollToTop` -- unlike the Accounts Panel (see `UI.page`'s doc
comment on why that one closes on a destination page's `init` instead),
there's no dedicated "just navigated Home" hook to close it or scroll from,
since `Pages.Home_` keeps its own `Model` alive across a same-route re-click
that no `init`/`ChangedUrl` would rerun for -- so this is the only place
that reliably still fires every time. Uses `stopPropagationOn`, not plain
`onClick`, so this doesn't also trigger `headerNav`'s own tap-anywhere
`Shared.ScrollToTop` (redundant when `isCurrent` already fires it above, and
undesired when navigating away instead).
-}
navLink : Shared.Model -> Route -> Html Shared.Msg -> Route -> Html Shared.Msg
navLink shared currentRoute content linkRoute =
    let
        isCurrent : Bool
        isCurrent =
            linkRoute == currentRoute

        isHome : Bool
        isHome =
            linkRoute == Route.Home_

        isHomeWithLogo : Bool
        isHomeWithLogo =
            isHome && mainServer shared /= Nothing
    in
    a
        ([ href (shared.basePath ++ Route.toHref linkRoute)
         , classes
            ("nav-link"
                :: (if isHomeWithLogo then
                        [ "nav-link-home" ]

                    else
                        []
                   )
                ++ (if isCurrent then
                        [ hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-nav" ]

                    else
                        []
                   )
            )
         ]
            -- Directly overrides nav.css's own (transitioned) `max-width` on
            -- `.nav-link-home` as `.nav-links-scroll` scrolls -- see
            -- `Shared.navLinkHomeMaxWidth`.
            ++ (if isHomeWithLogo && shared.navAnimationState.homeCollapsed then
                    [ style "max-width" "64px" ]

                else
                    []
               )
            ++ (if isHome then
                    [ stopPropagationOn "click" (Decode.succeed ( Shared.HomeLinkClicked isCurrent, True )) ]

                else
                    []
               )
        )
        [ content ]


{-| The Home link's content is normally the browsing server's own
logo/name (via `RellmServers.rellmServerNameAndLogo`), same `RegularServerLogo`
(stacked glyph-above-multi-line-name) style as the server chips in the
Accounts Panel -- just bigger, per `.nav-link-home` in `nav.css` -- falling
back to the literal text "Home" only for the brief window before
`mainFrontendHost` has actually finished connecting (see
`AccountsPanel.init`/`GotMainServerResult`), when it isn't in `servers` yet.
-}
homeLinkContent : Shared.Model -> Html msg
homeLinkContent shared =
    case mainServer shared of
        Just server ->
            RellmServers.rellmServerNameAndLogo server RellmServers.RegularServerLogo

        Nothing ->
            text "🏠"


{-| A circular icon nav link to the People page (`/people`), sitting between
the Home link and the Starred toggle -- same `.nav-menu-toggle.circular`
button styling `starredPostsToggle` uses for its own ⭐, but a plain route
link (highlighted via `background-color-nav` when `currentRoute` is already
`Route.People`, mirroring `navLink`'s `isCurrent` handling) rather than a
panel toggle.
-}
peopleLink : Shared.Model -> Route -> Html Shared.Msg
peopleLink shared currentRoute =
    let
        isCurrent : Bool
        isCurrent =
            currentRoute == Route.People
    in
    a
        [ href (shared.basePath ++ Route.toHref Route.People)
        , classes
            ("nav-link"
                :: (if isCurrent then
                        [ hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-nav" ]

                    else
                        []
                   )
            )
        , title "People"
        ]
        [ span [ class "nav-link-icon" ] [ text "👥" ]
        , span [ class "nav-link-label" ] [ text "People" ]
        ]


{-| A circular icon nav link to the Events page (`/events`), sitting right
next to `peopleLink` -- same styling/highlighting convention, just routed to
`Route.Events` with a 📅 glyph.
-}
eventsLink : Shared.Model -> Route -> Html Shared.Msg
eventsLink shared currentRoute =
    let
        isCurrent : Bool
        isCurrent =
            currentRoute == Route.Events
    in
    a
        [ href (shared.basePath ++ Route.toHref Route.Events)
        , classes
            ("nav-link"
                :: (if isCurrent then
                        [ hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-nav" ]

                    else
                        []
                   )
            )
        , title "Events"
        ]
        [ span [ class "nav-link-icon" ] [ text "📅" ]
        , span [ class "nav-link-label" ] [ text "Events" ]
        ]


{-| A circular icon nav link to the Posts page (`/posts`), sitting between
`eventsLink` and `peopleLink` -- same styling/highlighting convention, just
routed to `Route.Posts` with a 📝 glyph.
-}
postsLink : Shared.Model -> Route -> Html Shared.Msg
postsLink shared currentRoute =
    let
        isCurrent : Bool
        isCurrent =
            currentRoute == Route.Posts
    in
    a
        [ href (shared.basePath ++ Route.toHref Route.Posts)
        , classes
            ("nav-link"
                :: (if isCurrent then
                        [ hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-nav" ]

                    else
                        []
                   )
            )
        , title "Posts"
        ]
        [ span [ class "nav-link-icon" ] [ text "📝" ]
        , span [ class "nav-link-label" ] [ text "Posts" ]
        ]


{-| Looks up a known server by `frontendHost` -- a thin wrapper around
`RellmServers.rellmServerForHost` for callers that already have a `Shared.Model`
in scope rather than the bare `List RellmServer`.
-}
findServer : Shared.Model -> String -> Maybe RellmServer
findServer shared frontendHost =
    RellmServers.rellmServerForHost shared.accounts.servers frontendHost


mainServer : Shared.Model -> Maybe RellmServer
mainServer shared =
    findServer shared shared.accounts.mainFrontendHost


{-| `mainServer`'s effective `NavigationTabStyle` (icon-only, `CustomNav.effectiveTabStyle`'s own
default, whenever `mainServer` itself isn't resolved yet or `customTabs` is unset) -- `headerNav`'s
own `.nav-links` class (`CustomNav.navigationTabStyleClass`) is what actually lays `eventsLink`/
`postsLink`/`peopleLink`/`aboutLink`/`CustomNav.navLinkView`'s shared `.nav-link-icon`/`.nav-link-label`
content out per this, in nav.css.
-}
currentTabStyle : Shared.Model -> NavigationTabStyle
currentTabStyle shared =
    CustomNav.effectiveTabStyle (mainServer shared |> Maybe.andThen (\server -> (RellmServers.configurationOf server).customTabs))


{-| `eventsLink`/`postsLink`/`peopleLink`/`aboutLink`, or (once `mainServer`'s own
`ServerConfiguration.customTabs` is set -- see `Components.Pages.ServerInformationPage.SettingsTab`'s
editor) `UI.CustomNav.navLinkView` for each of `CustomNavigationTabSet.tabs` instead, in that admin-
configured order/icon/title. Falls back to the original four (unchanged, not routed through
`CustomNav.defaultTabs`) whenever `mainServer` itself isn't resolved yet or `customTabs` is unset,
so the everyday, unconfigured case can never regress from this module's own long-standing look.
-}
customTabLinks : Shared.Model -> Route -> List (Html Shared.Msg)
customTabLinks shared currentRoute =
    case mainServer shared |> Maybe.andThen (\server -> (RellmServers.configurationOf server).customTabs |> Maybe.map (Tuple.pair server)) of
        Just ( server, customTabs ) ->
            CustomNav.effectiveTabs (Just customTabs) |> List.map (CustomNav.navLinkView shared currentRoute server)

        Nothing ->
            [ eventsLink shared currentRoute
            , postsLink shared currentRoute
            , peopleLink shared currentRoute
            , aboutLink shared currentRoute
            ]


{-| Every page's browser tab title, built from `segments` (most-specific
first, e.g. a post's title, or -- once posts/profiles can belong to one --
that title _and_ its Group's name) followed by `mainFrontendHost`'s own
branding name, e.g. `"My Post | My Server"`. An empty `segments` (the Home
page) is just the server name on its own, with no leading `" | "`.

Centralizing this means every page's title updates together if the format
ever changes, and a future segment (like that Group name) is just another
list entry for the page to prepend -- not a new format to invent.

-}
pageTitle : Shared.Model -> List String -> String
pageTitle shared segments =
    String.join " | " (segments ++ [ serverName shared ])


{-| `mainFrontendHost`'s branding name, falling back to the bare hostname for
the brief window before that server's finished connecting (see `mainServer`).
-}
serverName : Shared.Model -> String
serverName shared =
    mainServer shared
        |> Maybe.map (RellmServers.brandingOf >> .name)
        |> Maybe.withDefault shared.accounts.mainFrontendHost


{-| A circular icon nav link to the About page (`/about`), sitting alongside
`peopleLink`/`eventsLink`/`postsLink` -- same styling/highlighting
convention, just routed to `Route.About` with an "i" glyph. The glyph itself
carries `[data-glyph="i"]` (matching `CustomNav.iconView`'s own convention for
an `EmojiIcon "i"`) rather than the old `info-button` class on the `<a>`
itself, so accounts\_panel.css's serif-italic "i" styling lands on just the
icon, not the visible label a non-icon-only `NavigationTabStyle` also shows
here (see `nav.css`'s `.tab-style-*` rules).
-}
aboutLink : Shared.Model -> Route -> Html Shared.Msg
aboutLink shared currentRoute =
    let
        isCurrent : Bool
        isCurrent =
            currentRoute == Route.About
    in
    a
        [ href (shared.basePath ++ Route.toHref Route.About)
        , classes
            ("nav-link"
                :: (if isCurrent then
                        [ hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-nav" ]

                    else
                        []
                   )
            )
        , title "About"
        ]
        [ span [ class "nav-link-icon", attribute "data-glyph" "i" ] [ text "i" ]
        , span [ class "nav-link-label" ] [ text "About" ]
        ]


{-| `aboutLink`'s counterpart for one `serverChip` -- links to
`Pages.Server.ServerIdentifier_` for that specific server (rather than
`Route.About`, which is always `mainFrontendHost`) so a chip for any known
server can be inspected the same way.
-}
serverInfoButton : Shared.Model -> RellmServer -> Html Shared.Msg
serverInfoButton shared server =
    let
        -- Disconnected servers (see `RellmServer.connected`) default to
        -- `https:` -- `ServerInformationPage`'s own probe re-negotiates anyway.
        serverIdentifier : String
        serverIdentifier =
            (if server.connected |> Maybe.map .tls |> Maybe.withDefault True then
                "https:"

             else
                "http:"
            )
                ++ server.frontendHost
    in
    a
        [ classes [ "panel-icon-button", "info-button", "server-chip-info-button" ]
        , href (shared.basePath ++ Route.toHref (Route.Server__ServerIdentifier_ { serverIdentifier = serverIdentifier }))
        , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg AccountsPanel.CloseAccountsPanel)
        , title ("About " ++ server.frontendHost)
        ]
        [ text "i" ]


{-| Cycles Auto -> Light -> Dark -> Auto. "Auto" follows the OS preference
(and reacts live if it changes); "Light"/"Dark" force it.
-}
themeToggle : Shared.Model -> Html Shared.Msg
themeToggle shared =
    let
        icon : String
        icon =
            case shared.theme.preference of
                Shared.ThemeAuto ->
                    "🌓"

                Shared.ThemeLight ->
                    "☀️"

                Shared.ThemeDark ->
                    "🌙"
    in
    button
        [ classes [ "panel-icon-button", "theme-toggle" ]
        , onClick Shared.ThemePreferenceClicked
        , title ("Appearance: " ++ Shared.themePreferenceLabel shared.theme.preference ++ " (click to change)")
        ]
        [ text icon ]



-- ACCOUNTS MENU


accountsMenu : Shared.Model -> Route -> Html Shared.Msg
accountsMenu shared currentRoute =
    let
        enabledAccounts : List RellmAccount
        enabledAccounts =
            AccountsPanel.enabledAccounts shared.accounts

        -- Signed into exactly one account on exactly one enabled server --
        -- since only one account per server can be enabled at a time (see
        -- `AccountsPanel.ToggleAccountEnabled`), this is the "single user"
        -- case: there's no second avatar to stack and no server count worth
        -- a subtitle, so the toggle becomes one larger avatar circle instead
        -- of the usual pill (see `.accounts-menu-toggle.single-avatar`).
        singleAccountSingleServer : Bool
        singleAccountSingleServer =
            case ( AccountsPanel.enabledServers shared.accounts, enabledAccounts ) of
                ( [ _ ], [ _ ] ) ->
                    True

                _ ->
                    False

        toggleClasses : List String
        toggleClasses =
            "accounts-menu-toggle"
                :: openClosedClass shared.accounts.showAccountsPanel
                :: (if List.isEmpty enabledAccounts then
                        []

                    else
                        [ "has-avatars" ]
                   )
                ++ (if singleAccountSingleServer then
                        [ "single-avatar" ]

                    else
                        []
                   )
    in
    div
        [ class "accounts-menu"

        -- Stops both the toggle and everything in the dropdown it wraps
        -- (`accountsPanel`, below) from also bubbling up into `headerNav`'s
        -- own tap-anywhere `Shared.ScrollToTop`.
        , stopPropagationOn "click" (Decode.succeed ( Shared.NoOp, True ))
        ]
        [ div [ class "accounts-menu-row" ]
            [ button
                [ classes toggleClasses
                , onClick (Shared.AccountsPanelMsg AccountsPanel.ToggleAccountsPanel)
                ]
                (if singleAccountSingleServer then
                    [ accountsMenuButtonContent shared enabledAccounts ]

                 else
                    [ accountsMenuButtonContent shared enabledAccounts
                    , accountsMenuServerSummary shared.accounts
                    ]
                )
            , hostMismatchWarning shared
            ]
        , accountsPanel shared currentRoute
        ]


{-| The accounts-menu toggle button's content: "Login" with nobody signed in,
otherwise a small avatar/placeholder per signed-in account (see
`accountsMenuAvatar`) in place of any username/count text.
-}
accountsMenuButtonContent : Shared.Model -> List RellmAccount -> Html Shared.Msg
accountsMenuButtonContent shared enabledAccounts =
    case enabledAccounts of
        [] ->
            text "Login"

        accounts ->
            div [ class "accounts-menu-avatars" ] (List.map (accountsMenuAvatar shared) accounts)


{-| A small-font subtitle under the accounts-menu toggle button's "Login" text/
avatars, summarizing how many servers are currently enabled: nothing for the
common single-server case where that server is `mainFrontendHost` (and there's no
federated source contributing either), that server's branding name when it's the
lone enabled server but not `mainFrontendHost` (so it's clear which server is
actually being browsed), "N servers" for any other count, or "No servers ⚠️" when
nothing at all is contributing. If any account's server is currently unreachable
(see `AccountsPanel.unreachableAccountHosts`, surfaced below as "Couldn't reach:
..."), the count is always shown -- even "1 server" -- with its own ⚠️, so
that warning isn't silently hidden behind the usual single-server blank
state. Recomputed on every render (so it updates live as servers are
toggled/reconnected) directly off `AccountsPanel.enabledServers` and
`AccountsPanel.unreachableAccountHosts`.

`N` counts every enabled Rellm server, every Mastodon instance actually contributing to the
combined feed (OAuth-connected accounts, which have no enable/disable toggle of their own, plus
browsed instances that are `.enabled` -- mirrors `Components.Pages.PostsPage.mastodonHostsToFetch`'s
own dedup), and every enabled Bluesky account. A trailing " \*" appears only if more than one Bluesky
account is enabled at once -- see `AccountsPanel.ToggleBlueskyAccountEnabled`'s own doc on why that's
now prevented at the source (only ever a leftover-state indicator for an account enabled before that
restriction existed, not something a fresh toggle can produce).

-}
accountsMenuServerSummary : AccountsPanel.Model -> Html Shared.Msg
accountsMenuServerSummary accountsPanelModel =
    let
        servers : List RellmServer
        servers =
            AccountsPanel.enabledServers accountsPanelModel

        mastodonHosts : List String
        mastodonHosts =
            (List.map .instanceHost accountsPanelModel.mastodonAccounts
                ++ (accountsPanelModel.browsedMastodonInstances |> List.filter .enabled |> List.map .host)
            )
                |> Set.fromList
                |> Set.toList

        enabledBlueskyAccounts : List BlueskyAccount
        enabledBlueskyAccounts =
            accountsPanelModel.blueskyAccounts |> List.filter .enabled

        count : Int
        count =
            List.length servers + List.length mastodonHosts + List.length enabledBlueskyAccounts

        hasUnreachableServers : Bool
        hasUnreachableServers =
            not (List.isEmpty (AccountsPanel.unreachableAccountHosts accountsPanelModel))

        serversText : String
        serversText =
            String.fromInt count
                ++ " server"
                ++ (if count == 1 then
                        ""

                    else
                        "s"
                   )
                ++ (if List.length enabledBlueskyAccounts > 1 then
                        " *"

                    else
                        ""
                   )
                ++ (if hasUnreachableServers then
                        " ⚠️"

                    else
                        ""
                   )
    in
    case ( servers, mastodonHosts, enabledBlueskyAccounts ) of
        ( [], [], [] ) ->
            div [ class "accounts-menu-server-summary" ] [ text "No servers ⚠️" ]

        ( [ singleServer ], [], [] ) ->
            if hasUnreachableServers || (singleServer.frontendHost /= accountsPanelModel.mainFrontendHost) then
                div [ class "accounts-menu-server-summary" ] [ text serversText ]

            else
                text ""

        _ ->
            div [ class "accounts-menu-server-summary" ] [ text serversText ]


{-| A small avatar/placeholder for the accounts-menu toggle button, bordered
with the account's server's `primaryColor` (via `border-color-primary`, see
`UI.EmittedStylesheet`) -- but only for accounts on a server other than
`mainFrontendHost`, so the common case (only signed into the main server)
doesn't show a border at all.
-}
accountsMenuAvatar : Shared.Model -> RellmAccount -> Html Shared.Msg
accountsMenuAvatar shared account =
    let
        accountsPanelModel : AccountsPanel.Model
        accountsPanelModel =
            shared.accounts

        avatarClasses : List String
        avatarClasses =
            "accounts-menu-avatar"
                :: (if account.server /= accountsPanelModel.mainFrontendHost then
                        [ hostnameToCSSClass account.server, "border-color-primary" ]

                    else
                        []
                   )
    in
    imageOrInitial avatarClasses account.username (RellmAccounts.rellmAccountAvatarUrl accountsPanelModel.servers account)


{-| `browsingHost` and `mainFrontendHost` differ when the host we're actually
being viewed from turns out to be a backend-only host with a different public
identity (see `Shared.AccountsPanel`'s `resolvedFrontendHost`) -- worth
flagging, since the user probably has the "wrong" (if working) URL open.
Clicking it force-resets `mainFrontendHost` back to `browsingHost`
(`ResetMainFrontendHost`) rather than navigating anywhere.

Always shown next to the Accounts Panel toggle (regardless of whether an admin
account is signed in -- the Admin Panel now lives inside the Accounts Panel
itself as a tab, see `adminTab`), rather than being folded into it.

-}
hostMismatchWarning : Shared.Model -> Html Shared.Msg
hostMismatchWarning shared =
    if hostMismatch shared then
        let
            accountsPanelModel : AccountsPanel.Model
            accountsPanelModel =
                shared.accounts
        in
        span
            [ class "host-mismatch-warning"
            , onClick (Shared.AccountsPanelMsg AccountsPanel.ResetMainFrontendHost)
            , title
                ("You're browsing from "
                    ++ accountsPanelModel.browsingHost
                    ++ ", but it's configured to look like "
                    ++ accountsPanelModel.mainFrontendHost
                    ++ ". Click to browse from "
                    ++ accountsPanelModel.browsingHost
                    ++ " instead."
                )
            ]
            [ text "⚠️" ]

    else
        text ""


{-| True when `browsingHost` and `mainFrontendHost` differ -- see
`hostMismatchWarning`.
-}
hostMismatch : Shared.Model -> Bool
hostMismatch shared =
    shared.accounts.browsingHost /= shared.accounts.mainFrontendHost


{-| Servers scroll horizontally in a short strip (there are usually few, and it
keeps them visually distinct from the taller, vertically-scrolling account
list below), which itself scrolls vertically since accounts are the thing
you'll accumulate the most of.

Always rendered (even "closed"), so opening/closing can be a plain CSS
transition (fade + slide) rather than the panel just appearing/disappearing
outright -- see `.nav-panel`/`.nav-panel.is-closed` in main.css.

-}
accountsPanel : Shared.Model -> Route -> Html Shared.Msg
accountsPanel shared currentRoute =
    let
        accountsPanelModel : AccountsPanel.Model
        accountsPanelModel =
            shared.accounts
    in
    div [ classes [ "accounts-panel", "nav-panel", openClosedClass accountsPanelModel.showAccountsPanel ] ]
        [ accountsPanelTabBar shared
        , case activeTab shared of
            AccountsPanel.TabAccountsAndServers ->
                accountsAndServersTab shared currentRoute

            AccountsPanel.TabDebug ->
                debugTab shared

            AccountsPanel.TabAdmin ->
                adminTab shared
        ]


{-| The tab bar itself: the "Accounts and Servers"/Settings/Admin tabs (see
`accountsPanelTab`) on the left, the brightness toggle -- now alone since the
"About" info button moved out to the header nav (see `aboutLink`) -- on the
right.
-}
accountsPanelTabBar : Shared.Model -> Html Shared.Msg
accountsPanelTabBar shared =
    div [ class "accounts-panel-tab-bar" ]
        [ div [ class "accounts-panel-tabs" ]
            (List.filterMap identity
                [ Just (accountsPanelTab shared AccountsPanel.TabAccountsAndServers "Accounts & Servers" False)
                , if debugCount shared > 0 then
                    Just (accountsPanelTab shared AccountsPanel.TabDebug "🐛" True)

                  else
                    Nothing
                , if AccountsPanel.hasAdminAccount shared.accounts then
                    Just (accountsPanelTab shared AccountsPanel.TabAdmin "🛡️" True)

                  else
                    Nothing
                ]
            )
        , div [ class "panel-icon-row" ] [ themeToggle shared ]
        ]


accountsPanelTab : Shared.Model -> AccountsPanel.Tab -> String -> Bool -> Html Shared.Msg
accountsPanelTab shared tab label isNarrow =
    button
        [ classes
            ("accounts-panel-tab"
                :: (if isNarrow then
                        [ "narrow" ]

                    else
                        []
                   )
                ++ (if activeTab shared == tab then
                        [ "selected" ]

                    else
                        []
                   )
            )
        , onClick (Shared.AccountsPanelMsg (AccountsPanel.TabSelected tab))
        ]
        [ text label ]


{-| How many debug settings the Debug tab currently holds -- the "switch main
server by tapping servers", "Sign into other hosts with username/password",
and "Show all event layouts" toggles (all admin-only) for now, but tracked as
a count rather than a bare `Bool` so the tab can grow more (non-admin-gated)
settings later without changing how its visibility is decided.
-}
debugCount : Shared.Model -> Int
debugCount shared =
    if AccountsPanel.hasAdminAccount shared.accounts then
        3

    else
        0


{-| `shared.accounts.activeTab`, falling back to `TabAccountsAndServers`
whenever the selected tab isn't actually visible right now (e.g. the signed-in
admin account was just removed while the Admin tab was showing) -- so the
panel never ends up rendering a tab's content with no matching tab button
selected.
-}
activeTab : Shared.Model -> AccountsPanel.Tab
activeTab shared =
    case shared.accounts.activeTab of
        AccountsPanel.TabDebug ->
            if debugCount shared > 0 then
                AccountsPanel.TabDebug

            else
                AccountsPanel.TabAccountsAndServers

        AccountsPanel.TabAdmin ->
            if AccountsPanel.hasAdminAccount shared.accounts then
                AccountsPanel.TabAdmin

            else
                AccountsPanel.TabAccountsAndServers

        AccountsPanel.TabAccountsAndServers ->
            AccountsPanel.TabAccountsAndServers


{-| The current UI of the Accounts Panel, minus the info/brightness buttons
(now in `accountsPanelTabBar` instead). Always shows, for everyone.
-}
accountsAndServersTab : Shared.Model -> Route -> Html Shared.Msg
accountsAndServersTab shared currentRoute =
    div [ class "accounts-panel-tab-content" ]
        [ combinedServerFeedItemsStrip shared
        , unreachableServersWarning shared
        , recommendedServersStrip shared
        , div [ class "panel-divider" ] []
        , accountsList shared
        , div [ class "panel-divider" ] []
        , formView shared currentRoute
        ]


{-| The "switch main server by tapping servers" (see `serverChip`), "Sign
into other hosts with username/password" (see `rellmAddAccountServerForm`), "Show
all event layouts" (see `Components.Pages.EventsPage.modeButtonsView`), and
"Show Posts linked to Custom Tabs" (see `Components.Pages.PostsPage.customNavPostIds`)
toggles -- only shown (via `debugCount`) while an admin account is signed
in.
-}
debugTab : Shared.Model -> Html Shared.Msg
debugTab shared =
    div [ class "accounts-panel-tab-content" ]
        [ label [ class "admin-switch-row" ]
            [ switchInput shared.accounts.debugTab.allowMainServerSwitch False (Shared.AccountsPanelMsg (AccountsPanel.DebugTabMsg DebugTab.ToggleAllowMainServerSwitch))
            , span [] [ text "Switch main server by tapping servers" ]
            ]
        , div [ class "debug-tab-note" ]
            [ text ("Market pages are always based off the host being browsed from, " ++ shared.accounts.browsingHost ++ ".") ]
        , label [ class "admin-switch-row" ]
            [ switchInput shared.accounts.debugTab.allowUsernamePasswordForOtherHosts False (Shared.AccountsPanelMsg (AccountsPanel.DebugTabMsg DebugTab.ToggleAllowUsernamePasswordForOtherHosts))
            , span [] [ text "Sign into other hosts with username/password" ]
            ]
        , label [ class "admin-switch-row" ]
            [ switchInput shared.accounts.debugTab.showAllEventLayouts False (Shared.AccountsPanelMsg (AccountsPanel.DebugTabMsg DebugTab.ToggleShowAllEventLayouts))
            , span [] [ text "Show all event layouts" ]
            ]
        , label [ class "admin-switch-row" ]
            [ switchInput shared.accounts.debugTab.showCustomNavPosts False (Shared.AccountsPanelMsg (AccountsPanel.DebugTabMsg DebugTab.ToggleShowCustomNavPosts))
            , span [] [ text "Show Posts linked to Custom Tabs" ]
            ]
        ]


{-| The per-admin-Account sections (see `adminAccountPanel`) from the old
standalone Admin Panel.
-}
adminTab : Shared.Model -> Html Shared.Msg
adminTab shared =
    let
        adminAccounts : List RellmAccount
        adminAccounts =
            List.filter RellmAccounts.isAdmin shared.accounts.accounts
    in
    div [ class "accounts-panel-tab-content" ]
        [ if List.isEmpty adminAccounts then
            text ""

          else
            div [ class "admin-accounts-list" ] (List.map (adminAccountPanel shared) adminAccounts)
        ]



-- SERVERS


{-| The one combined, reorderable chip strip for every `AccountsPanel.CombinedServerFeedItem` -- Rellm
servers, browsed Mastodon instances, and connected Bluesky accounts together, in `sortOrder`
(the `mainFrontendHost` server always first, unmovable) -- replaces the former separate
`serversStrip` and the chip portion of `federatedFeedsSection` (which now holds only the
"+ Bluesky Account"/"+ Mastodon Server" add-buttons and their forms).
-}
combinedServerFeedItemsStrip : Shared.Model -> Html Shared.Msg
combinedServerFeedItemsStrip shared =
    let
        items : List AccountsPanel.CombinedServerFeedItem
        items =
            AccountsPanel.combinedServerFeedItems shared.accounts

        count : Int
        count =
            List.length items
    in
    Html.Keyed.node "div"
        [ classes [ "servers-strip", "flip-animated-row" ] ]
        (List.indexedMap
            (\index item -> ( AccountsPanel.combinedServerFeedItemKey item, combinedServerFeedItemChipFlip shared count index item ))
            items
        )


{-| Wraps one `CombinedServerFeedItem`'s chip (`serverChip`/`mastodonServerFeedChip`)
in a fading/scaling/collapsing animated outer `div` (entering when freshly added, removing when
deleted -- see `AccountsPanel.serverAnimations`/`UI.Flip`) -- the `UI.Flip.Horizontal` counterpart of
`accountRowFlip`, whose doc covers the two-layer reasoning (fade/collapse here vs. each chip's own,
independent reorder-slide) in full.
-}
combinedServerFeedItemChipFlip : Shared.Model -> Int -> Int -> AccountsPanel.CombinedServerFeedItem -> Html Shared.Msg
combinedServerFeedItemChipFlip shared count index item =
    let
        key : String
        key =
            AccountsPanel.combinedServerFeedItemKey item

        flipState : UI.Flip.State AccountsPanel.Msg
        flipState =
            Dict.get key shared.accounts.serverAnimations
                |> Maybe.withDefault UI.Flip.restingState

        isMoving : Bool
        isMoving =
            Dict.get key shared.accounts.serverMoveAnimations
                |> Maybe.map .moving
                |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Shared.Msg)
        pointerEventsAttr =
            if flipState.removing then
                [ style "pointer-events" "none" ]

            else
                []

        chip : Html Shared.Msg
        chip =
            case item of
                AccountsPanel.CombinedRellmServer server ->
                    serverChip shared count index server

                AccountsPanel.CombinedMastodonInstance instance ->
                    mastodonServerFeedChip shared count index instance
    in
    div (UI.Flip.itemAttributes UI.Flip.Horizontal flipState isMoving)
        [ div pointerEventsAttr [ chip ] ]


{-| The reorder-arrow pair, `moveAttrs` (reorder-slide transform), and whether each arrow is
interactive, shared by every `CombinedServerFeedItem` chip (`serverChip`/`mastodonServerFeedChip`) --
see `AccountsPanel.combinedServerFeedItems`'s own doc for the ordering this reasons about.

The main server (always `index == 0`) is pinned in place and isn't reorderable at all, so neither of
its arrows is interactive. The item right after it can't move left into the main server's fixed
slot, so its left arrow isn't interactive either; the last item can't move right past the end, so
its right arrow isn't. Both conditions naturally leave a lone non-main item (`count == 2`) with
neither arrow interactive. Non-interactive arrows still render (`reorder-arrow-hidden` just
fades/no-ops them) rather than disappearing, so a chip's width/layout doesn't jump around depending
on position.

-}
feedItemReorderInfo :
    Shared.Model
    -> Int
    -> Int
    -> String
    ->
        { moveAttrs : List (Html.Attribute Shared.Msg)
        , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
        , showBackward : Bool
        , showForward : Bool
        }
feedItemReorderInfo shared count index key =
    let
        moveAttrs : List (Html.Attribute Shared.Msg)
        moveAttrs =
            shared.accounts.serverMoveAnimations
                |> Dict.get key
                |> Maybe.map UI.Flip.moveAttributes
                |> Maybe.withDefault []

        -- `stopPropagationOn`, not `onClick` -- these two buttons sit inside a chip's own "select
        -- this item"/switch-input click targets, so a plain `onClick` here would also fire those.
        stopClick : Shared.Msg -> Attribute Shared.Msg
        stopClick msg =
            stopPropagationOn "click" (Decode.succeed ( msg, True ))

        showBackward : Bool
        showBackward =
            index > 1

        showForward : Bool
        showForward =
            index > 0 && index < count - 1

        reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
        reorderPair =
            UI.Flip.reorderButtonPair UI.Flip.Horizontal
                { moveBackward = stopClick (Shared.AccountsPanelMsg (AccountsPanel.MoveServerFeedItemLeftClicked key))
                , moveForward = stopClick (Shared.AccountsPanelMsg (AccountsPanel.MoveServerFeedItemRightClicked key))
                , canMoveBackward = showBackward
                , canMoveForward = showForward
                }
    in
    { moveAttrs = moveAttrs, reorderPair = reorderPair, showBackward = showBackward, showForward = showForward }


{-| Top portion (logo/name/host) gets that server's `background-color-primary`
utility classes (see `UI.EmittedStylesheet`); the enable switch, an external
link (opening the server's own `https://` site in a new tab -- omitted for
whichever server we're actually `browsingHost`-ing from, since that one's
already open here), and the delete button sit in a bottom portion using
`background-color-nav` instead.

The top portion is always clickable: tapping it fills the Account form's
Server field with this server's `frontendHost` (`ServerChipClicked`), so
switching which known server you're logging into/adding an account on is a
single tap. When the Settings tab's "switch main server" toggle is also
on (see `Shared.AccountsPanel.DebugTab`), that tap additionally sets this server as
`mainFrontendHost` (`MainServerSelected`, which fills the Server field too --
see its handler in `Shared.AccountsPanel`) instead of just filling the field.

-}
serverChip : Shared.Model -> Int -> Int -> RellmServer -> Html Shared.Msg
serverChip shared count index server =
    let
        accountsPanelModel : AccountsPanel.Model
        accountsPanelModel =
            shared.accounts

        isMainServer : Bool
        isMainServer =
            server.frontendHost == accountsPanelModel.mainFrontendHost

        isDisconnected : Bool
        isDisconnected =
            server.connected == Nothing

        hasAccounts : Bool
        hasAccounts =
            RellmAccounts.rellmServerHasRellmAccounts accountsPanelModel.accounts server.frontendHost

        removable : Bool
        removable =
            not hasAccounts && not isMainServer

        canSelectMain : Bool
        canSelectMain =
            shared.accounts.debugTab.allowMainServerSwitch

        topClasses : List String
        topClasses =
            [ "server-chip-top", "selectable", hostnameToCSSClass server.frontendHost, "background-color-primary" ]

        topAttrs : List (Html.Attribute Shared.Msg)
        topAttrs =
            [ classes topClasses
            , onClick
                (Shared.AccountsPanelMsg
                    (if canSelectMain then
                        AccountsPanel.MainServerSelected server.frontendHost

                     else
                        AccountsPanel.ServerChipClicked server.frontendHost
                    )
                )
            , title
                (if canSelectMain then
                    "Set as main server"

                 else
                    "Use this server in the login form"
                )
            ]

        reorderInfo :
            { moveAttrs : List (Html.Attribute Shared.Msg)
            , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
            , showBackward : Bool
            , showForward : Bool
            }
        reorderInfo =
            feedItemReorderInfo shared count index ("server:" ++ server.frontendHost)

        showBackward : Bool
        showBackward =
            reorderInfo.showBackward

        showForward : Bool
        showForward =
            reorderInfo.showForward

        reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
        reorderPair =
            reorderInfo.reorderPair
    in
    div
        (id (AccountsPanel.serverFeedItemChipDomId ("server:" ++ server.frontendHost))
            :: classList [ ( "server-chip", True ), ( "server-chip-disconnected", isDisconnected ) ]
            :: reorderInfo.moveAttrs
        )
        [ div topAttrs
            [ div [ class "server-chip-logo-row" ]
                [ div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showBackward ) ] ] [ reorderPair.backward ]
                , RellmServers.rellmServerNameAndLogo server RellmServers.RegularServerLogo
                , div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not showForward ) ] ] [ reorderPair.forward ]
                ]
            , div [ class "server-chip-host-row" ]
                [ div [ class "server-chip-host" ] [ text server.frontendHost ]
                , serverInfoButton shared server
                ]
            , if isDisconnected then
                div [ class "server-chip-disconnected-badge" ] [ text "Disconnected" ]

              else
                text ""

            -- , if isMainServer then
            --     div [ class "server-chip-main-badge" ] [ text "★ Main" ]
            --   else
            --     text ""
            ]
        , div [ classes [ "server-chip-bottom", hostnameToCSSClass server.frontendHost, "background-color-nav" ] ]
            [ switchInput server.enabled False (Shared.AccountsPanelMsg (AccountsPanel.ToggleServerEnabled server.frontendHost))
            , if isDisconnected then
                button
                    [ class "reconnect-btn"
                    , onClick (Shared.AccountsPanelMsg (AccountsPanel.ReconnectServerClicked server.frontendHost))
                    , title ("Try reconnecting to " ++ server.frontendHost)
                    ]
                    [ text "⟳ Reconnect" ]

              else if server.frontendHost /= accountsPanelModel.browsingHost then
                a
                    [ class "external-link-btn"
                    , href ("https://" ++ server.frontendHost)
                    , target "_blank"
                    , title ("Open " ++ server.frontendHost ++ " in a new tab")
                    ]
                    [ text "↗" ]

              else
                text ""
            , button
                [ class "remove-btn"
                , onClick (Shared.RequestDelete (Shared.ConfirmServerDelete server))
                , disabled (not removable)
                , title
                    (if isMainServer then
                        "Can't remove the server you're currently browsing from"

                     else if hasAccounts then
                        "Can't remove a server with accounts on it"

                     else
                        "Remove server"
                    )
                ]
                [ text "╳" ]
            ]
        ]


{-| An `img` if `maybeUrl` is present, otherwise a `div` showing the first
letter of `name`, upper-cased (via `RellmServers.initialLetter`) -- shared by
every avatar/logo that falls back to an initial when there's no image: account
avatars (`avatarOrPlaceholder`, `accountsMenuAvatar`) and server logos
(`logoOrPlaceholder`). `baseClasses` names the element itself (e.g.
"account-avatar"); the placeholder `div` additionally gets a "placeholder"
class alongside it.
-}
imageOrInitial : List String -> String -> Maybe String -> Html msg
imageOrInitial baseClasses name maybeUrl =
    case maybeUrl of
        Just url ->
            img [ classes baseClasses, src url, alt name, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes ("placeholder" :: baseClasses) ] [ text (RellmServers.initialLetter name) ]


{-| Accounts are kept around even when their server currently has no `Server`
entry (down, moved, unreachable -- see `AccountsPanel.unreachableAccountHosts`),
so they wouldn't otherwise show up anywhere in `serversStrip`. Surfaced here as
a plain-text note of just their hosts, rather than a full chip, since there's
nothing (name/logo/theme) to render for a server we can't currently reach.
-}
unreachableServersWarning : Shared.Model -> Html msg
unreachableServersWarning shared =
    let
        hosts : List String
        hosts =
            AccountsPanel.unreachableAccountHosts shared.accounts
    in
    if List.isEmpty hosts then
        text ""

    else
        div [ class "servers-unreachable-warning" ]
            [ text ("Couldn't reach: " ++ String.join ", " hosts) ]


{-| The main server's federated-but-not-yet-added servers (see
`AccountsPanel.recommendedFederatedServers`) plus its admin-registered-but-not-yet-browsed
Mastodon servers (`AccountsPanel.recommendedMastodonServers`), tucked behind a single "X
Recommended Servers..." button rather than shown outright -- collapsed by
default, and re-collapsed every time the Accounts Panel closes (see
`AccountsPanel.recommendedServersExpanded`'s own doc), so it doesn't compete
with `serversStrip` for a first-time visitor's attention. Its own
`panel-divider` sits above it, packaged into this same `Bool`-gated block so
it only shows up alongside the section itself -- `accountsAndServersTab`'s
own (unconditional) divider right after this one already serves as this
section's _bottom_ divider, whether or not this one renders anything above
it. Renders nothing at all once there's nothing left to recommend.
-}
recommendedServersStrip : Shared.Model -> Html Shared.Msg
recommendedServersStrip shared =
    let
        recommendedRellmServers : List FederatedServer
        recommendedRellmServers =
            AccountsPanel.recommendedFederatedServers shared.accounts

        recommendedMastodonServers : List MastodonServer
        recommendedMastodonServers =
            AccountsPanel.recommendedMastodonServers shared.accounts

        totalCount : Int
        totalCount =
            List.length recommendedRellmServers + List.length recommendedMastodonServers
    in
    if totalCount == 0 then
        text ""

    else
        div [ class "recommended-servers-section" ]
            [ div [ class "panel-divider" ] []
            , if not shared.accounts.recommendedServersExpanded then
                button
                    [ class "recommended-servers-toggle"
                    , onClick (Shared.AccountsPanelMsg AccountsPanel.ToggleRecommendedServersExpanded)
                    ]
                    [ text (String.fromInt totalCount ++ " Recommended Servers...")
                    ]

              else
                div [ class "recommended-servers-strip" ]
                    (List.map (recommendedServerChip shared) recommendedRellmServers
                        ++ List.map recommendedMastodonServerChip recommendedMastodonServers
                    )
            ]


{-| A single recommended-server button -- visually the same "logo/name over
host, tinted with that server's own brand color" top portion as `serverChip`,
just without any of its reorder/enable/remove controls, since the whole chip
is instead one big "add this server" button (`RecommendedServerClicked`).
Branding comes from `AccountsPanel.recommendedServerConnections`, fetched
on-demand by `ToggleRecommendedServersExpanded` -- falls back to a bare,
disconnected-looking placeholder for the brief window before that fetch
resolves (or if it hasn't been kicked off yet at all).
-}
recommendedServerChip : Shared.Model -> FederatedServer -> Html Shared.Msg
recommendedServerChip shared federatedServer =
    let
        host : String
        host =
            federatedServer.host

        server : RellmServer
        server =
            Dict.get host shared.accounts.recommendedServerConnections
                |> Maybe.withDefault { frontendHost = host, enabled = False, connected = Nothing, sortOrder = 0 }

        isDisconnected : Bool
        isDisconnected =
            server.connected == Nothing
    in
    button
        [ classList [ ( "server-chip", True ), ( "recommended-server-chip", True ), ( "server-chip-disconnected", isDisconnected ), ( hostnameToCSSClass host, True ) ]
        , onClick (Shared.AccountsPanelMsg (AccountsPanel.RecommendedServerClicked host))
        , title ("Add " ++ host)
        ]
        [ div [ classes [ "server-chip-top", hostnameToCSSClass host, "background-color-primary" ] ]
            [ div [ class "server-chip-logo-row" ] [ RellmServers.rellmServerNameAndLogo server RellmServers.RegularServerLogo ]
            , div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text host ] ]
            ]
        , div [ classes [ "server-chip-bottom", "recommended-server-add-row", hostnameToCSSClass host, "background-color-nav" ] ]
            [ text "+ Add" ]
        ]


{-| A recommended-server chip for one of `mainFrontendHost`'s admin-registered `MastodonServer`s
(see `AccountsPanel.recommendedMastodonServers`) -- mirrors `recommendedServerChip`'s shape, but
there's no `RellmServer`/branding to fetch here (a `MastodonServer` already carries everything it
needs), and clicking it just adds a no-login browsed feed for it
(`AccountsPanel.RecommendedMastodonServerClicked`), exactly like typing its domain into
`BrowseMastodonInstanceClicked`'s own form -- unrelated to `mastodonConnectButton`'s OAuth "Connect
Account" flow, so there's no `appId` to gate on here.
-}
recommendedMastodonServerChip : MastodonServer -> Html Shared.Msg
recommendedMastodonServerChip mastodonServer =
    let
        domain : String
        domain =
            mastodonServer.domain
    in
    button
        [ classList [ ( "server-chip", True ), ( "recommended-server-chip", True ), ( hostnameToCSSClass domain, True ) ]
        , onClick (Shared.AccountsPanelMsg (AccountsPanel.RecommendedMastodonServerClicked domain))
        , title ("Add " ++ domain)
        ]
        [ div [ classes [ "server-chip-top", hostnameToCSSClass domain, "background-color-primary" ] ]
            [ div [ class "server-chip-logo-row" ]
                [ div [ class "server-name-and-logo regular" ]
                    [ div [ class "server-logo-placeholder" ] [ text (RellmServers.initialLetter domain) ]
                    , div [ class "server-name-breakdown" ]
                        [ div [ class "server-name-primary" ] [ text "Mastodon" ] ]
                    ]
                ]
            , div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text domain ] ]
            ]
        , div [ classes [ "server-chip-bottom", "recommended-server-add-row", hostnameToCSSClass domain, "background-color-nav" ] ]
            [ text "+ Add" ]
        ]


{-| The Mastodon tab's "connect a real account" sub-section, in `addAccountServerForm` -- one button
per Mastodon instance `browsingHost`'s own admin has listed (`FederationInfo.mastodonServers`) that
isn't already connected (`AccountsPanel.mastodonAccounts`, see `AccountsPanel.connectableMastodonServers`).
Nothing rendered at all if there's nothing connectable. Each button opens the OAuth popup
(`AccountsPanel.MastodonConnectClicked`) -- never automatically, only on this explicit click --
disabled (and shows "Connecting…") while `AccountsPanel.mastodonConnectPopupOpen` names this same
instance, so a slow/stuck popup can't be double-triggered. A server with no `appId` configured (per
`MastodonServer.appId`'s own doc on that being admin-optional) shows its button disabled, with a
small, dimmed "Auth Unavailable" notice alongside it.
-}
mastodonConnectSection : Shared.Model -> Html Shared.Msg
mastodonConnectSection shared =
    let
        connectable : List MastodonServer
        connectable =
            AccountsPanel.connectableMastodonServers shared.accounts
    in
    if List.isEmpty connectable then
        text ""

    else
        div [ class "mastodon-connect-account-list" ] (List.map (mastodonConnectButton shared) connectable)


{-| The "Auth Unavailable" notice for an admin-registered instance with no `appId` now lives on that
instance's own `mastodonServerFeedChip` (if it's also being browsed), not here -- see that
function's own doc.
-}
mastodonConnectButton : Shared.Model -> MastodonServer -> Html Shared.Msg
mastodonConnectButton shared mastodonServer =
    let
        domain : String
        domain =
            mastodonServer.domain

        connecting : Bool
        connecting =
            shared.accounts.mastodonConnectPopupOpen == Just domain

        hasAppId : Bool
        hasAppId =
            not (String.isEmpty mastodonServer.appId)

        isDisabled : Bool
        isDisabled =
            not hasAppId || connecting
    in
    button
        [ type_ "button"
        , classes
            [ "mastodon-connect-account-button"
            , hostnameToCSSClass domain
            , if isDisabled then
                ""

              else
                "background-color-primary"
            ]
        , onClick (Shared.AccountsPanelMsg (AccountsPanel.MastodonConnectClicked domain))
        , disabled isDisabled
        , title
            (if hasAppId then
                "Connect an account on " ++ domain

             else
                domain ++ " hasn't been configured for Mastodon sign-in by this server's admin yet."
            )
        ]
        [ text
            (if connecting then
                "Connecting to " ++ domain ++ "…"

             else
                "Connect Account on " ++ domain
            )
        ]


{-| The small avatar/logo image in a `mastodonServerFeedChip`'s label row --
`text ""` (nothing rendered) until the account/instance's own async fetch resolves one (see
`BlueskyAccount.avatarUrl`/`BrowsedMastodonInstance.logoUrl`'s own doc). Reuses
`serverNameAndLogo`'s own `.server-logo-image` sizing/fit (32px, `object-fit: cover`) -- `circular`
adds `.server-logo-image-circular` on top of that (Bluesky avatars) to override its default 6px
corner rounding with a full circle; Mastodon instance logos stay un-rounded, matching how a real
`serverChip`'s own logo looks.
-}
federatedFeedLogoImage : Bool -> String -> Maybe String -> Html msg
federatedFeedLogoImage circular altText maybeUrl =
    case maybeUrl of
        Just url ->
            img
                [ classList [ ( "server-logo-image", True ), ( "server-logo-image-circular", circular ) ]
                , src url
                , alt altText
                ]
                []

        Nothing ->
            text ""


{-| One Mastodon instance being browsed -- mirrors `serverChip`'s own shape as closely as it can
without a real `Server`/`ServerTheme` behind it, with its two-tone coloring deliberately _inverted_
(`background-color-nav` top / `background-color-primary` bottom, vs. `serverChip`'s own
primary-top/nav-bottom) as a quick visual "this one's different" cue, `mainFrontendHost`-scoped
either way -- see `UI.EmittedStylesheet`'s own doc on why: it's not a real `Server` with its own
registered theme, so there's no per-instance color to draw on the way `serverChip`/
`recommendedServerChip` do. The top section's own logo row flanks the logo with the reorder arrows,
same as `serverChip`'s own `serverNameAndLogo` row does -- then a "⇄ Mastodon" label on its own
full-width row below (unconstrained by the arrows, unlike the logo), then the fetched display name
if one resolved, then the host itself -- and the bottom section holds every action as one button
strip, same as `serverChip`'s own bottom. `border-color-accent` (same `mainFrontendHost` scoping)
gives it a recognizable border. Differs from `mastodonConnectSection`'s admin-registered,
OAuth-connectable kind in that there's no `MastodonAccount` behind it, just a string, and no "Connect"
affordance either, since browsing and connecting are independent actions -- a browsed instance
doesn't invite upgrading itself into a connected account here.
-}
mastodonServerFeedChip : Shared.Model -> Int -> Int -> BrowsedMastodonInstance -> Html Shared.Msg
mastodonServerFeedChip shared count index instance =
    let
        mainHostClass : String
        mainHostClass =
            hostnameToCSSClass shared.accounts.mainFrontendHost

        key : String
        key =
            "mastodon:" ++ instance.host

        reorderInfo :
            { moveAttrs : List (Html.Attribute Shared.Msg)
            , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
            , showBackward : Bool
            , showForward : Bool
            }
        reorderInfo =
            feedItemReorderInfo shared count index key

        -- Hidden when the instance's own fetched name is just the generic "Mastodon" (a common
        -- default many instances' `/api/v1/instance` never customizes) -- it'd be pure noise
        -- directly under the "⇄ Mastodon" label already saying the same thing.
        nameRow : List (Html Shared.Msg)
        nameRow =
            case instance.displayName of
                Just name ->
                    if String.trim name == "Mastodon" then
                        []

                    else
                        [ div [ class "server-chip-host-row" ] [ div [ class "server-name-primary" ] [ text name ] ] ]

                Nothing ->
                    []

        -- Only shown when this browsed instance is *also* one `mainFrontendHost`'s admin has
        -- registered for OAuth sign-in (see `AccountsPanel.mastodonServerFor`) but hasn't set an
        -- `appId` on -- mirrors `mastodonConnectButton`'s own `hasAppId` gate, moved here (see that
        -- function's own doc) since a chip for an instance nobody registered at all has nothing to
        -- report either way.
        authUnavailableRow : List (Html Shared.Msg)
        authUnavailableRow =
            case AccountsPanel.mastodonServerFor shared.accounts instance.host of
                Just mastodonServer ->
                    if String.isEmpty mastodonServer.appId then
                        [ div [ class "server-chip-host-row" ] [ span [ class "mastodon-connect-account-unavailable" ] [ text "Auth Unavailable" ] ] ]

                    else
                        []

                Nothing ->
                    []
    in
    div
        (id (AccountsPanel.serverFeedItemChipDomId key)
            :: classes [ "server-chip", mainHostClass, "border-color-accent" ]
            :: reorderInfo.moveAttrs
        )
        [ div [ classes [ "server-chip-top", mainHostClass, "background-color-nav" ] ]
            ([ div [ class "server-chip-logo-row" ]
                [ div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.showBackward ) ] ] [ reorderInfo.reorderPair.backward ]
                , federatedFeedLogoImage False (instance.host ++ " logo") instance.logoUrl
                , div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.showForward ) ] ] [ reorderInfo.reorderPair.forward ]
                ]
             , div [ class "server-chip-host-row" ] [ div [ class "federated-feed-service-label" ] [ text "⇄ Mastodon" ] ]
             ]
                ++ nameRow
                ++ [ div [ class "server-chip-host-row" ] [ div [ class "server-chip-host" ] [ text instance.host ] ] ]
                ++ authUnavailableRow
            )
        , div [ classes [ "server-chip-bottom", mainHostClass, "background-color-primary" ] ]
            [ switchInput instance.enabled False (Shared.AccountsPanelMsg (AccountsPanel.ToggleBrowsedMastodonInstanceEnabled instance.host))
            , a
                [ class "external-link-btn"
                , href ("https://" ++ instance.host)
                , target "_blank"
                , title ("Open " ++ instance.host ++ " in a new tab")
                ]
                [ text "↗" ]
            , button
                [ class "remove-btn"
                , onClick (Shared.AccountsPanelMsg (AccountsPanel.RemoveBrowsedMastodonInstanceClicked instance.host))
                , title ("Stop browsing " ++ instance.host)
                ]
                [ text "╳" ]
            ]
        ]


{-| The Mastodon tab's "browse an instance" `<input>` + submit button -- mirrors
`blueskyConnectFormView`'s own `<form>`-with-`onSubmit` shape (so Enter submits it), just with the
one plain host input `browseMastodonInstanceInput` needs instead of a whole record. No "Cancel"
button of its own -- `addAccountServerFormTabBar`'s shared "←" collapses the whole tabbed form.
-}
mastodonServerFormView : Shared.Model -> Html Shared.Msg
mastodonServerFormView shared =
    Html.form
        [ class "server-details-federation-add", onSubmit (Shared.AccountsPanelMsg AccountsPanel.BrowseMastodonInstanceClicked) ]
        [ input
            [ type_ "text"
            , attribute "autocapitalize" "none"
            , attribute "autocorrect" "off"
            , spellcheck False
            , placeholder "mastodon.world"
            , value shared.accounts.browseMastodonInstanceInput
            , onInput (Shared.AccountsPanelMsg << AccountsPanel.BrowseMastodonInstanceInputChanged)
            ]
            []
        , button
            [ disabled (String.isEmpty (String.trim shared.accounts.browseMastodonInstanceInput)) ]
            [ text "+ Browse Instance" ]
        ]


{-| The Bluesky tab's handle/App Password inputs plus Connect button -- a real `<form>` (not a
`button` `onClick`), same `onSubmit`-not-button-click reasoning `Pages.Auth.To.Key_`'s own login form
uses (see its own doc), so Enter submits it and password managers recognize it as a login form worth
offering to fill. No "Cancel" button of its own -- `addAccountServerFormTabBar`'s shared "←"
collapses the whole tabbed form.
-}
blueskyConnectFormView : AccountsPanel.BlueskyConnectForm -> Html Shared.Msg
blueskyConnectFormView form =
    let
        submitting : Bool
        submitting =
            form.status == AccountsPanel.Submitting
    in
    Html.form
        [ class "server-details-federation-add", onSubmit (Shared.AccountsPanelMsg AccountsPanel.BlueskyConnectClicked) ]
        [ input
            [ type_ "text"
            , name "username"
            , attribute "autocomplete" "username"
            , attribute "autocapitalize" "none"
            , attribute "autocorrect" "off"
            , spellcheck False
            , placeholder "handle.bsky.social"
            , value form.handle
            , onInput (Shared.AccountsPanelMsg << AccountsPanel.BlueskyHandleChanged)
            , disabled submitting
            ]
            []
        , input
            [ type_ "password"
            , name "current-password"
            , attribute "autocomplete" "current-password"
            , placeholder "App Password"
            , value form.appPassword
            , onInput (Shared.AccountsPanelMsg << AccountsPanel.BlueskyAppPasswordChanged)
            , disabled submitting
            ]
            []
        , button
            [ disabled (submitting || String.isEmpty form.handle || String.isEmpty form.appPassword) ]
            [ text
                (if submitting then
                    "Connecting…"

                 else
                    "Connect"
                )
            ]
        , case form.status of
            AccountsPanel.Errored err ->
                div [ class "auth-error" ] [ text err ]

            _ ->
                text ""
        ]



-- ACCOUNTS


accountsList : Shared.Model -> Html Shared.Msg
accountsList shared =
    let
        items : List AccountsPanel.CombinedAccountItem
        items =
            AccountsPanel.combinedAccountItems shared.accounts
    in
    if List.isEmpty items then
        div [ class "accounts-empty" ] [ text "No accounts yet." ]

    else
        let
            count : Int
            count =
                List.length items

            -- Accounts on the main server always sort to the front (see
            -- `AccountsPanel.combinedAccountItems`), so they're exactly the
            -- leading `mainCount` items here -- `accountItemReorderInfo` uses
            -- this to hide any arrow that would cross that group boundary.
            mainCount : Int
            mainCount =
                shared.accounts.accounts
                    |> List.filter (\a -> a.server == shared.accounts.mainFrontendHost)
                    |> List.length
        in
        Html.Keyed.node "div"
            [ classes [ "accounts-list", "flip-animated-column" ] ]
            (List.indexedMap
                (\index item -> ( AccountsPanel.combinedAccountItemKey item, combinedAccountItemRowFlip shared count mainCount index item ))
                items
            )


{-| Whether the New Account/Login flow (`Password Required` included -- see
`AccountsPanel.ReauthenticateButtonClicked`) is currently active --
`accountRowFlip`/`accountRow` use this to collapse every account row out of
the way except whichever one `accountMatchesForm` says the Server/Username
fields are actually naming, so the account list doesn't crowd out that flow
with rows unrelated to it.
-}
newAccountFlowActive : Shared.Model -> Bool
newAccountFlowActive shared =
    shared.accounts.newAccountType /= Nothing


{-| Whether `account` is the one the Server/Username fields (see
`AccountsPanel.AccountForm`) currently name -- the one row `newAccountFlowActive`
leaves visible.
-}
accountMatchesForm : Shared.Model -> RellmAccount -> Bool
accountMatchesForm shared account =
    let
        form : AccountsPanel.AccountForm
        form =
            shared.accounts.accountForm
    in
    String.trim form.server == account.server && String.trim form.username == account.username


{-| Wraps one `CombinedAccountItem`'s row (`accountRow`/`mastodonAccountRow`/`blueskyAccountRow`) in
a fading/scaling/collapsing animated outer `div` (entering when freshly added, removing when deleted
-- see `AccountsPanel.accountAnimations`/`UI.Flip`), mirroring `Pages.Home_`'s `postAnimationView`.
The inner clip-layer `div` (same reasoning as there) holds the FLIP-collapse's own `padding-bottom`
spacing; the row itself -- with its _own_, independent reorder-slide `moveAttrs` -- lives one layer
further in, so the two animations (fade/collapse vs. reorder-slide) apply to different elements and
never fight over the same `transform`.

Also collapsed (same `flip-collapsed` FLIP treatment as a real removal, via
`newAccountFlowActive`/`accountMatchesForm`) for every item other than the Rellm account the New
Account/Login flow's Server/Username fields currently name, while that flow is active -- every
Mastodon/Bluesky item included, since neither is what that flow could ever be naming -- reusing the
same collapsing-grid-track CSS transition rather than a separate ad hoc show/hide animation.

-}
combinedAccountItemRowFlip : Shared.Model -> Int -> Int -> Int -> AccountsPanel.CombinedAccountItem -> Html Shared.Msg
combinedAccountItemRowFlip shared count mainCount index item =
    let
        key : String
        key =
            AccountsPanel.combinedAccountItemKey item

        flipState : UI.Flip.State AccountsPanel.Msg
        flipState =
            Dict.get key shared.accounts.accountAnimations
                |> Maybe.withDefault UI.Flip.restingState

        hiddenByNewAccountFlow : Bool
        hiddenByNewAccountFlow =
            newAccountFlowActive shared
                && (case item of
                        AccountsPanel.CombinedRellmAccount account ->
                            not (accountMatchesForm shared account)

                        _ ->
                            True
                   )

        effectiveFlipState : UI.Flip.State AccountsPanel.Msg
        effectiveFlipState =
            { flipState | removing = flipState.removing || hiddenByNewAccountFlow }

        isMoving : Bool
        isMoving =
            Dict.get key shared.accounts.moveAnimations
                |> Maybe.map .moving
                |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Shared.Msg)
        pointerEventsAttr =
            if effectiveFlipState.removing then
                [ style "pointer-events" "none" ]

            else
                []

        row : Html Shared.Msg
        row =
            case item of
                AccountsPanel.CombinedRellmAccount account ->
                    accountRow shared count mainCount index account

                AccountsPanel.CombinedMastodonAccount account ->
                    mastodonAccountRow shared count mainCount index account

                AccountsPanel.CombinedBlueskyAccount account ->
                    blueskyAccountRow shared count mainCount index account
    in
    div (UI.Flip.itemAttributes UI.Flip.Vertical effectiveFlipState isMoving)
        [ div pointerEventsAttr [ row ] ]


{-| The reorder-arrow pair, `moveAttrs` (reorder-slide transform), and whether each arrow is
interactive, shared by every `CombinedAccountItem` row (`accountRow`/`mastodonAccountRow`/
`blueskyAccountRow`) -- see `AccountsPanel.combinedAccountItems`'s own doc for the ordering this
reasons about.

`mainCount` (see `accountsList`) is how many leading items belong to accounts on the main server --
an arrow that would cross that group boundary (moving a main-group item out of it, or a non-main one
into it) is hidden rather than merely disabled, same as `feedItemReorderInfo`'s own main-server-chip
boundary, just generalized to a main _group_ of arbitrary size instead of always exactly one item at
index `0` (there can be more than one account on the main server).

-}
accountItemReorderInfo :
    Shared.Model
    -> Int
    -> Int
    -> Int
    -> String
    ->
        { moveAttrs : List (Html.Attribute Shared.Msg)
        , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
        , canMoveUp : Bool
        , canMoveDown : Bool
        }
accountItemReorderInfo shared count mainCount index key =
    let
        moveAttrs : List (Html.Attribute Shared.Msg)
        moveAttrs =
            shared.accounts.moveAnimations
                |> Dict.get key
                |> Maybe.map UI.Flip.moveAttributes
                |> Maybe.withDefault []

        -- Move buttons are hidden (not just disabled) for every row while the New Account/Login
        -- flow is active (see `newAccountFlowActive`) -- reordering a list that's mostly collapsed
        -- down to one row makes no sense, and the still-visible matching row shouldn't invite a
        -- reorder mid-flow either.
        showMoveButtons : Bool
        showMoveButtons =
            not (newAccountFlowActive shared)

        canMoveUp : Bool
        canMoveUp =
            showMoveButtons && index > 0 && index /= mainCount

        canMoveDown : Bool
        canMoveDown =
            showMoveButtons && index < count - 1 && index /= mainCount - 1

        reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
        reorderPair =
            UI.Flip.reorderButtonPair UI.Flip.Vertical
                { moveBackward = onClick (Shared.AccountsPanelMsg (AccountsPanel.MoveAccountItemUpClicked key))
                , moveForward = onClick (Shared.AccountsPanelMsg (AccountsPanel.MoveAccountItemDownClicked key))
                , canMoveBackward = canMoveUp
                , canMoveForward = canMoveDown
                }
    in
    { moveAttrs = moveAttrs, reorderPair = reorderPair, canMoveUp = canMoveUp, canMoveDown = canMoveDown }


{-| The avatar button that toggles `accountAvatarMenuView` (see `AccountsPanel.Model.focusedAccount`)
-- plain `button.media-btn`, same as before this menu existed, just with its click now toggling the
menu instead of jumping straight to `MyMediaPanel`. Nested inside `accountRow`'s own
`a.account-row-profile-link`, so its click still needs to stop propagation -- same reasoning as
`accountAvatarMenuView`'s own items.

An account that `needsPassword` gets no menu at all -- same "sign in to view media" gate the old
button used, since none of the four items make sense for an account that isn't actually signed in.

-}
accountAvatarToggle : Shared.Model -> RellmAccount -> Html Shared.Msg
accountAvatarToggle shared account =
    if account.needsPassword then
        button [ class "media-btn", title "Sign in to view media" ]
            [ avatarOrPlaceholder shared.accounts.servers account ]

    else
        button
            [ classes [ "media-btn", openClosedClass (AccountsPanel.isFocusedAccount shared.accounts account) ]
            , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg (AccountsPanel.AccountAvatarClicked account))
            ]
            [ avatarOrPlaceholder shared.accounts.servers account ]


{-| A second, collapsible line in `accountRow` (see that function's own doc) holding "Contact
Methods"/"Media"/"Sync Sources"/"Sync Destinations"/"AI Models" for this account -- expands the row
itself open when `accountAvatarToggle` is clicked (`AccountsPanel.Model.focusedAccount`), rather
than floating a popover on top of neighboring rows: ordinary in-flow content, so it just grows the
row's own height (which the outer `.flip-animated-item` -- see `combinedAccountItemRowFlip` --
already sizes itself to fit) with no z-index/overflow-clip/scrollable-region workarounds needed.
Always rendered (`Nothing` account excluded via `needsPassword` below), collapsed to zero height via
`ui/accounts_panel.css`'s `.account-avatar-menu` -- the same `grid-template-rows` 1fr/0fr trick
`flip.css`'s own `.flip-animated-item` uses -- so opening/closing is a smooth height transition (a
"for free" FLIP-like animation, without needing this menu to track its own `UI.Flip.State`).

"Contact Methods" (see `contactMethodsMenuItem`) is a nested expandable *within* this already-
expandable menu, rather than a link out to the profile page like the other four -- its own edit/
consent/verification flow is ported from `Components.Pages.UserProfilePage`'s
`contactMethodsSection` into `Shared.AccountsPanel.Model`/`Shared.Msg` (see `contactMethodsMenuItem`'s
own doc on why the split). "Media" opens `MyMediaPanel` directly (same `Shared.MyMediaPanelOpenForAccount`
the old avatar button fired, which now also collapses this menu back closed -- see that handler's own
doc); the other three navigate to the account's own profile page, where their actual management UI
already lives (`Components.Pages.UserProfilePage`'s `syncSourcesSection`/`syncDestinationsSection`/
`aiProvidersSection`) -- same link + `CloseAccountsPanel` pattern `accountRow`'s own profile link uses.
Each of the three is shown only if `account` actually holds a permission that would let it use that
feature at all (`RellmAccounts.canUseSyncSources`/`canUseSyncDestinations`/`canUseAIModels`) -- an
account with no sync-from/sync-to/AI-provider permissions at all sees just "Contact Methods"/"Media".

-}
accountAvatarMenuView : Shared.Model -> RellmAccount -> Html Shared.Msg
accountAvatarMenuView shared account =
    if account.needsPassword then
        text ""

    else
        let
            profileHref : String
            profileHref =
                Users.profileHref shared.basePath shared.accounts.mainFrontendHost account.server { userId = account.userId, username = account.username }

            -- Unlike `navigateAndClose` (a plain `href` click, left to elm/browser's
            -- own SPA link interception), this fires `Shared.ProfileSectionLinkClicked`
            -- instead -- see that message's own doc on why a bare link can't expand +
            -- scroll an already-open `UserProfilePage` to `sectionId` when the click
            -- doesn't change the URL's path (only its fragment). The `href` stays on
            -- each of these items regardless, purely for right-click/middle-click
            -- "open in new tab"/hover-preview -- this handler still `preventDefault`s
            -- an ordinary left click the same way `navigateAndClose` does.
            sectionLinkClicked : String -> Html.Attribute Shared.Msg
            sectionLinkClicked sectionId =
                stopPropagationAndPreventDefaultOnClick (Shared.ProfileSectionLinkClicked account sectionId)

            configuredCountOrEmpty : String -> List a -> String
            configuredCountOrEmpty emptyText items =
                if List.isEmpty items then
                    emptyText

                else
                    String.fromInt (List.length items) ++ " configured"

            itemContent : String -> String -> List (Html Shared.Msg)
            itemContent label detail =
                [ span [ class "account-avatar-menu-item-label" ] [ text label ]
                , span [ class "account-avatar-menu-item-detail" ] [ text detail ]
                ]
        in
        div [ classes [ "account-avatar-menu", openClosedClass (AccountsPanel.isFocusedAccount shared.accounts account) ] ]
            [ div [ class "account-avatar-menu-list" ]
                [ contactMethodsMenuItem shared account
                , button
                    [ class "account-avatar-menu-item"
                    , stopPropagationAndPreventDefaultOnClick (Shared.MyMediaPanelOpenForAccount account)
                    ]
                    (itemContent "Media"
                        (ByteFormat.formatBytes account.mediaStorageBytesUsed
                            ++ " used / "
                            ++ (case account.mediaStorageLimitBytes of
                                    Just limit ->
                                        ByteFormat.formatBytes limit

                                    Nothing ->
                                        "no limit"
                               )
                        )
                    )
                , if RellmAccounts.canUseSyncSources account then
                    a
                        [ class "account-avatar-menu-item", href (profileHref ++ "#sync-sources"), sectionLinkClicked "sync-sources" ]
                        (itemContent "Sync Sources" (configuredCountOrEmpty "No sync sources configured." account.syncSources))

                  else
                    text ""
                , if RellmAccounts.canUseSyncDestinations account then
                    a
                        [ class "account-avatar-menu-item", href (profileHref ++ "#sync-destinations"), sectionLinkClicked "sync-destinations" ]
                        (itemContent "Sync Destinations" (configuredCountOrEmpty "No sync destinations configured." account.syncDestinations))

                  else
                    text ""
                , if RellmAccounts.canUseAIModels account then
                    a
                        [ class "account-avatar-menu-item", href (profileHref ++ "#ai-models"), sectionLinkClicked "ai-models" ]
                        (itemContent "AI Models" (configuredCountOrEmpty "No AI models configured." account.aiModels))

                  else
                    text ""
                , a
                    [ class "account-avatar-menu-item", href (profileHref ++ "#subscriptions"), sectionLinkClicked "subscriptions" ]
                    (itemContent "Subscriptions" (configuredCountOrEmpty "No subscriptions." account.marketSubscriptions))
                ]
            ]


{-| The "Contact Methods" item in `accountAvatarMenuView` -- a nested expandable *within* that
already-expandable menu (`AccountsPanel.Model.focusedAccountContactMethods`), rather than the plain
`itemContent` button/link the other four items use, since Phone/Email editing, the SMS consent
checkbox + History sub-section, and phone verification all need real interactive content here, not
just a link out to the profile page. Its header reuses `profiles.css`'s `.expandable-section-arrow`
chevron -- the same rotate-on-`.is-open` animation `Components.Pages.UserProfilePage.
expandableProfileSection` uses for every one of its own collapsible sections -- placed beside just
the "Contact Methods" label itself (`.account-avatar-menu-contact-methods-header-top`, `align-items:
center`, full opacity to match that label rather than the arrow's own muted default) with the
subheader (`contactMethodsSummary`) on its own full-width line underneath both. The body below it
reuses `.expandable-section-content`'s own `grid-template-rows` open/close animation for the same
reason.

Ported from `Components.Pages.UserProfilePage.contactMethodsSection` (see that function's own doc)
into `Shared.AccountsPanel.Model`/`Shared.Msg` instead, so it works from any page the Accounts Panel
is open on, not just the profile page -- see `Shared.Msg.ContactMethodPhoneSaveClicked`'s own doc on
why the network-calling half specifically had to move to `Shared.elm` rather than living in
`Shared.AccountsPanel.update` alongside the rest of this feature's `Msg` handling.

`contactMethods` reads `AccountsPanel.currentFocusedAccountContactMethods` only when `account` is
actually the focused one -- every other account's (CSS-hidden) copy of this same item gets
`RellmAccounts.emptyRellmContactMethods` instead, both so an unfocused row never renders another
row's in-progress edit and so the nested History sub-section's own DOM `id` (below) doesn't collide
across rows.
-}
contactMethodsMenuItem : Shared.Model -> RellmAccount -> Html Shared.Msg
contactMethodsMenuItem shared account =
    let
        isFocused : Bool
        isFocused =
            AccountsPanel.isFocusedAccount shared.accounts account

        contactMethods : RellmAccounts.RellmContactMethods
        contactMethods =
            if isFocused then
                AccountsPanel.currentFocusedAccountContactMethods shared.accounts

            else
                RellmAccounts.emptyRellmContactMethods

        expanded : Bool
        expanded =
            isFocused && contactMethods.contactMethodsExpanded
    in
    div [ class "account-avatar-menu-contact-methods" ]
        [ div
            [ class "account-avatar-menu-contact-methods-header"
            , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg AccountsPanel.ContactMethodsMenuToggled)
            ]
            [ div [ class "account-avatar-menu-contact-methods-header-top" ]
                [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
                , span [ class "account-avatar-menu-item-label" ] [ text "Contact Methods" ]
                ]
            , span [ class "account-avatar-menu-item-detail" ] (contactMethodsSummary account)
            ]
        , div
            [ classes [ "expandable-section-content", "account-avatar-menu-contact-methods-content", "base-colors-half", "border-color-primary-anchor-50", openClosedClass expanded ] ]
            [ div [ class "expandable-section-content-inner" ]
                [ contactMethodPhoneView account contactMethods
                , contactMethodConsentView shared
                    ("account-avatar-menu-phone-history-" ++ RellmAccounts.rellmAccountId account)
                    "SMS"
                    contactMethods.phoneConsentStatus
                    contactMethods.phoneHistoryExpanded
                    Shared.ContactMethodPhoneConsentToggled
                    (Shared.AccountsPanelMsg AccountsPanel.ContactMethodPhoneHistoryToggled)
                    account.phone
                , contactMethodPhoneVerificationView contactMethods account.phone
                , contactMethodEmailView account contactMethods
                , contactMethodConsentView shared
                    ("account-avatar-menu-email-history-" ++ RellmAccounts.rellmAccountId account)
                    "email"
                    contactMethods.emailConsentStatus
                    contactMethods.emailHistoryExpanded
                    Shared.ContactMethodEmailConsentToggled
                    (Shared.AccountsPanelMsg AccountsPanel.ContactMethodEmailHistoryToggled)
                    account.email
                ]
            ]
        ]


{-| `contactMethodsMenuItem`'s collapsed-state subheader -- "📱 <phone> ✓" and "✉️ <email> ✓" (the
"✓" only if verified), each side `RellmAccounts.contactMethodDisplayValue`'s usual "—" placeholder
when unset, so a glance at the still-collapsed item shows both values (and verification status)
without expanding it. Each returned as its own `.account-avatar-menu-contact-methods-summary-unit`
(`white-space: nowrap`, `ui/accounts_panel.css`) rather than one joined string, so a narrow row wraps
*between* "📱 …"/"✉️ …" rather than splitting an emoji away from its own value/checkmark.
-}
contactMethodsSummary : RellmAccount -> List (Html msg)
contactMethodsSummary account =
    [ contactMethodsSummaryUnit "📱" "tel:" account.phone
    , contactMethodsSummaryUnit "✉️" "mailto:" account.email
    ]


contactMethodsSummaryUnit : String -> String -> Maybe ContactMethod -> Html msg
contactMethodsSummaryUnit emoji prefix maybeContactMethod =
    span [ class "account-avatar-menu-contact-methods-summary-unit" ]
        [ text
            (emoji
                ++ " "
                ++ RellmAccounts.contactMethodDisplayValue prefix maybeContactMethod
                ++ (if (maybeContactMethod |> Maybe.andThen .verifiedAt) /= Nothing then
                        " ✅"

                    else
                        ""
                   )
            )
        ]


{-| The Phone line -- ported from `Components.Pages.UserProfilePage.phoneView`, unchanged apart from
firing `Shared.AccountsPanelMsg`s instead of that page's own local `Msg`s, and always showing the
Edit button (this only ever renders inside the signed-in account's own menu, so there's no
`canEdit`/other-viewer distinction to gate it on the way the profile page's copy needs).
-}
contactMethodPhoneView : RellmAccount -> RellmAccounts.RellmContactMethods -> Html Shared.Msg
contactMethodPhoneView account contactMethods =
    case contactMethods.phoneEdit of
        Just edit ->
            div [ class "profile-contact-method-edit" ]
                [ span [ class "profile-contact-method-label" ] [ text "Phone" ]
                , input
                    [ class "profile-real-name-input"
                    , value edit.input
                    , onInput (\text_ -> Shared.AccountsPanelMsg (AccountsPanel.ContactMethodPhoneInputChanged text_))
                    , placeholder "+15555550100"
                    ]
                    []
                , contactMethodVisibilitySelector (\text_ -> Shared.AccountsPanelMsg (AccountsPanel.ContactMethodPhoneVisibilityChanged text_)) edit.visibility
                , contactMethodEditSaveButton Shared.ContactMethodPhoneSaveClicked edit.status
                , contactMethodEditCancelButton (Shared.AccountsPanelMsg AccountsPanel.ContactMethodPhoneCancelClicked) edit.status
                , contactMethodEditErrorView edit.status
                ]

        Nothing ->
            div [ class "profile-contact-method-display" ]
                ([ span [ class "profile-contact-method-label" ] [ text "Phone: " ]
                 , span [ class "profile-contact-method-value" ] [ text (RellmAccounts.contactMethodDisplayValue "tel:" account.phone) ]
                 ]
                    ++ (account.phone |> Maybe.map (\cm -> [ contactMethodVerifiedBadge cm, contactMethodVisibilityBadge cm ]) |> Maybe.withDefault [])
                    ++ [ button [ class "profile-edit-button", onClick (Shared.AccountsPanelMsg AccountsPanel.ContactMethodPhoneEditClicked) ] [ text "Edit Phone" ] ]
                )


{-| The Email line -- mirrors `contactMethodPhoneView` exactly, just for the `mailto:` scheme
instead of `tel:`, ported from `Components.Pages.UserProfilePage.emailView`.
-}
contactMethodEmailView : RellmAccount -> RellmAccounts.RellmContactMethods -> Html Shared.Msg
contactMethodEmailView account contactMethods =
    case contactMethods.emailEdit of
        Just edit ->
            div [ class "profile-contact-method-edit" ]
                [ span [ class "profile-contact-method-label" ] [ text "Email" ]
                , input
                    [ class "profile-real-name-input"
                    , value edit.input
                    , onInput (\text_ -> Shared.AccountsPanelMsg (AccountsPanel.ContactMethodEmailInputChanged text_))
                    , placeholder "you@example.com"
                    ]
                    []
                , contactMethodVisibilitySelector (\text_ -> Shared.AccountsPanelMsg (AccountsPanel.ContactMethodEmailVisibilityChanged text_)) edit.visibility
                , contactMethodEditSaveButton Shared.ContactMethodEmailSaveClicked edit.status
                , contactMethodEditCancelButton (Shared.AccountsPanelMsg AccountsPanel.ContactMethodEmailCancelClicked) edit.status
                , contactMethodEditErrorView edit.status
                ]

        Nothing ->
            div [ class "profile-contact-method-display" ]
                ([ span [ class "profile-contact-method-label" ] [ text "Email: " ]
                 , span [ class "profile-contact-method-value" ] [ text (RellmAccounts.contactMethodDisplayValue "mailto:" account.email) ]
                 ]
                    ++ (account.email |> Maybe.map (\cm -> [ contactMethodVerifiedBadge cm, contactMethodVisibilityBadge cm ]) |> Maybe.withDefault [])
                    ++ [ button [ class "profile-edit-button", onClick (Shared.AccountsPanelMsg AccountsPanel.ContactMethodEmailEditClicked) ] [ text "Edit Email" ] ]
                )


{-| The contact-consent checkbox shown under `contactMethodPhoneView`/`contactMethodEmailView`, plus
a nested "History" sub-section (another `.expandable-section-title`/`.expandable-section-content`
pair, same mechanism as `contactMethodsMenuItem`'s own header/body and
`Components.Pages.UserProfilePage.expandableProfileSection` -- no separate Show/Hide button) listing
every `ContactConsentChange` in `contactMethod.consentHistory` (oldest last). `toggleMsg` is a plain
`Shared.Msg` (`ContactMethodPhoneConsentToggled`/`ContactMethodEmailConsentToggled`, since checking
the box calls `UpdateUser`); `historyToggleMsg` is pure state, already wrapped in
`Shared.AccountsPanelMsg` by the caller. Ported from
`Components.Pages.UserProfilePage.contactMethodConsentView`.
-}
contactMethodConsentView :
    Shared.Model
    -> String
    -> String
    -> RellmAccounts.SubmitStatus
    -> Bool
    -> Shared.Msg
    -> Shared.Msg
    -> Maybe ContactMethod
    -> Html Shared.Msg
contactMethodConsentView shared historyDomId methodLabel status historyExpanded toggleMsg historyToggleMsg maybeContactMethod =
    case maybeContactMethod of
        Just contactMethod ->
            div [ class "profile-contact-method-consent" ]
                [ label [ class "profile-contact-method-consent-label" ]
                    [ input
                        [ type_ "checkbox"
                        , checked (contactMethod.consentState == CONTACTCONSENTGRANTED)
                        , disabled (status == RellmAccounts.Submitting)
                        , onClick toggleMsg
                        ]
                        []
                    , text (" Checking this box indicates I consent to be contacted via " ++ methodLabel ++ ".")
                    ]
                , contactMethodEditErrorView status
                , if List.isEmpty contactMethod.consentHistory then
                    text ""

                  else
                    div [ class "profile-contact-method-consent-history", id historyDomId ]
                        [ div
                            [ classes [ "section-title", "expandable-section-title" ]
                            , onClick historyToggleMsg
                            ]
                            [ span [ classes [ "expandable-section-arrow", openClosedClass historyExpanded ] ] [ text "▼" ]
                            , text "History"
                            ]
                        , div
                            [ classes [ "expandable-section-content", openClosedClass historyExpanded, "border-color-primary-anchor-50" ] ]
                            [ div [ class "expandable-section-content-inner" ]
                                [ ul [ class "profile-contact-method-consent-history-list" ]
                                    (contactMethod.consentHistory
                                        |> List.reverse
                                        |> List.map (contactConsentChangeView shared.time.browserTimeZone)
                                    )
                                ]
                            ]
                        ]
                ]

        Nothing ->
            text ""


{-| One `li` in `contactMethodConsentView`'s History list -- "Granted"/"Revoked" plus the
server-timestamped `changedAt`. Ported from
`Components.Pages.UserProfilePage.contactConsentChangeView`.
-}
contactConsentChangeView : SharedTime.BrowserTimeZone -> ContactConsentChange -> Html msg
contactConsentChangeView browserTimeZone change =
    let
        stateLabel : String
        stateLabel =
            if change.state == CONTACTCONSENTGRANTED then
                "Granted"

            else
                "Revoked"

        when : String
        when =
            change.changedAt
                |> Maybe.map (timestampToPosix >> SharedTime.formatDateTime browserTimeZone)
                |> Maybe.withDefault ""
    in
    li [] [ text (stateLabel ++ " " ++ when) ]


{-| The Verified/Not Verified badge next to a displayed contact method -- ported from
`Components.Pages.UserProfilePage.contactMethodVerifiedBadge`, unchanged.
-}
contactMethodVerifiedBadge : ContactMethod -> Html msg
contactMethodVerifiedBadge contactMethod =
    if contactMethod.verifiedAt /= Nothing then
        span [ class "profile-contact-method-verified" ] [ text "✓ Verified" ]

    else
        span [ class "profile-contact-method-not-verified" ] [ text "✕ Not Verified" ]


{-| The visibility badge next to a displayed contact method -- ported from
`Components.Pages.UserProfilePage.contactMethodVisibilityBadge`, just reading
`RellmAccounts.contactMethodVisibilityText` (this leaf module's own copy, see that function's own
doc) instead of `Components.Posts.visibilityText`.
-}
contactMethodVisibilityBadge : ContactMethod -> Html msg
contactMethodVisibilityBadge contactMethod =
    span [ class "profile-contact-method-visibility" ] [ text (RellmAccounts.contactMethodVisibilityText contactMethod.visibility) ]


{-| The visibility `<select>` shown alongside `contactMethodPhoneView`/`contactMethodEmailView`'s
input while editing -- ported from `Components.Pages.UserProfilePage.contactMethodVisibilitySelector`,
reading `RellmAccounts.contactMethodVisibilities`/`contactMethodVisibilityText` in place of that
page's own `contactMethodVisibilities`/`Components.Posts.visibilityText`.
-}
contactMethodVisibilitySelector : (String -> Shared.Msg) -> Visibility -> Html Shared.Msg
contactMethodVisibilitySelector onChange currentVisibility =
    select [ onInput onChange ]
        (RellmAccounts.contactMethodVisibilities
            |> List.map
                (\visibility ->
                    option
                        [ value (RellmAccounts.contactMethodVisibilityText visibility)
                        , selected (visibility == currentVisibility)
                        ]
                        [ text (RellmAccounts.contactMethodVisibilityText visibility) ]
                )
        )


{-| Ported from `Components.Pages.UserProfilePage.editSaveButton`, unchanged apart from
`RellmAccounts.SubmitStatus` in place of that page's own `SubmitStatus`.
-}
contactMethodEditSaveButton : Shared.Msg -> RellmAccounts.SubmitStatus -> Html Shared.Msg
contactMethodEditSaveButton onSave status =
    button
        [ classes [ "profile-edit-save", "background-color-primary" ]
        , onClick onSave
        , disabled (status == RellmAccounts.Submitting)
        ]
        [ text
            (if status == RellmAccounts.Submitting then
                "Saving…"

             else
                "Save"
            )
        ]


{-| Ported from `Components.Pages.UserProfilePage.editCancelButton`, unchanged apart from
`RellmAccounts.SubmitStatus`.
-}
contactMethodEditCancelButton : Shared.Msg -> RellmAccounts.SubmitStatus -> Html Shared.Msg
contactMethodEditCancelButton onCancel status =
    button [ class "profile-edit-cancel", onClick onCancel, disabled (status == RellmAccounts.Submitting) ] [ text "Cancel" ]


{-| Ported from `Components.Pages.UserProfilePage.editErrorView`, unchanged apart from
`RellmAccounts.SubmitStatus`.
-}
contactMethodEditErrorView : RellmAccounts.SubmitStatus -> Html msg
contactMethodEditErrorView status =
    case status of
        RellmAccounts.SubmitFailed err ->
            div [ class "profile-edit-error" ] [ text err ]

        _ ->
            text ""


{-| The phone-only SMS verification flow, shown under `contactMethodPhoneView`/
`contactMethodConsentView` -- ported from `Components.Pages.UserProfilePage.phoneVerificationView`,
see that function's own doc for the gating/consent reasoning (unchanged). Always for the signed-in
account itself (this only ever renders inside that account's own menu), so there's no
`isOwn`-equivalent gate to check the way the profile page's copy needs.
-}
contactMethodPhoneVerificationView : RellmAccounts.RellmContactMethods -> Maybe ContactMethod -> Html Shared.Msg
contactMethodPhoneVerificationView contactMethods maybePhone =
    let
        eligibleToVerify : Bool
        eligibleToVerify =
            maybePhone
                |> Maybe.map (\cm -> cm.supportedByServer && cm.verifiedAt == Nothing)
                |> Maybe.withDefault False
    in
    if not eligibleToVerify then
        text ""

    else
        let
            consentGranted : Bool
            consentGranted =
                maybePhone
                    |> Maybe.map (\cm -> cm.consentState == CONTACTCONSENTGRANTED)
                    |> Maybe.withDefault False
        in
        if not consentGranted then
            p [ class "profile-contact-method-verify-disclaimer" ]
                [ text "Grant SMS consent above to verify your phone number -- the verification code itself is sent by SMS." ]

        else
            case contactMethods.phoneVerification of
                Nothing ->
                    div [ class "profile-contact-method-verify" ]
                        [ button [ class "profile-edit-button", onClick Shared.ContactMethodStartPhoneVerificationClicked ] [ text "Start Verification" ] ]

                Just pv ->
                    div [ class "profile-contact-method-verify" ]
                        [ if pv.sendStatus == RellmAccounts.Submitting then
                            span [ class "profile-contact-method-verify-status" ] [ text "Sending code…" ]

                          else
                            div [ class "profile-contact-method-verify-code" ]
                                [ input
                                    [ class "profile-real-name-input"
                                    , placeholder "Enter code"
                                    , value pv.code
                                    , onInput (\code -> Shared.AccountsPanelMsg (AccountsPanel.ContactMethodPhoneVerificationCodeChanged code))
                                    , disabled (pv.verifyStatus == RellmAccounts.Submitting)
                                    ]
                                    []
                                , button
                                    [ class "profile-edit-save"
                                    , onClick Shared.ContactMethodVerifyPhoneCodeClicked
                                    , disabled (pv.verifyStatus == RellmAccounts.Submitting || String.isEmpty pv.code)
                                    ]
                                    [ text
                                        (if pv.verifyStatus == RellmAccounts.Submitting then
                                            "Verifying…"

                                         else
                                            "Verify"
                                        )
                                    ]
                                , button
                                    [ class "profile-edit-cancel"
                                    , onClick Shared.ContactMethodStartPhoneVerificationClicked
                                    , disabled pv.cooldownActive
                                    ]
                                    [ text "Resend" ]
                                ]
                        , contactMethodEditErrorView pv.sendStatus
                        , contactMethodEditErrorView pv.verifyStatus
                        ]


{-| The whole row is tinted with the account's server's `background-color-primary`
(background = `primaryColor`, text = `primaryTextColor`, inherited by the
username); the "host | server name" badge underneath it uses
`background-color-nav` instead, layered on top as a normal (not
absolutely-positioned) element now that the row isn't split into bands.

The row's own DOM `id` (`AccountsPanel.accountRowDomId`) is what lets `AccountsPanel.update`
measure its position before/after a reorder to drive its reorder-slide (see
`accountItemReorderInfo`'s own `moveAttrs`).

-}
accountRow : Shared.Model -> Int -> Int -> Int -> RellmAccount -> Html Shared.Msg
accountRow shared count mainCount index account =
    let
        accId : String
        accId =
            RellmAccounts.rellmAccountId account

        key : String
        key =
            AccountsPanel.combinedAccountItemKey (AccountsPanel.CombinedRellmAccount account)

        branding : Branding
        branding =
            RellmServers.brandingFor shared.accounts.servers account.server

        reorderInfo :
            { moveAttrs : List (Html.Attribute Shared.Msg)
            , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
            , canMoveUp : Bool
            , canMoveDown : Bool
            }
        reorderInfo =
            accountItemReorderInfo shared count mainCount index key
    in
    div
        (id (AccountsPanel.accountRowDomId key)
            :: classes [ "account-row", hostnameToCSSClass account.server, "background-color-primary" ]
            :: reorderInfo.moveAttrs
        )
        [ div [ class "account-row-main" ]
            [ div [ class "reorder-buttons" ]
                [ div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.canMoveUp ) ] ] [ reorderInfo.reorderPair.backward ]
                , div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.canMoveDown ) ] ] [ reorderInfo.reorderPair.forward ]
                ]
            , switchInput account.enabled account.needsPassword (Shared.AccountsPanelMsg (AccountsPanel.ToggleAccountEnabled accId))
            , a
                [ class "account-row-profile-link"
                , href (Users.profileHref shared.basePath shared.accounts.mainFrontendHost account.server { userId = account.userId, username = account.username })
                , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg AccountsPanel.CloseAccountsPanel)
                ]
                [ accountAvatarToggle shared account
                , div [ class "account-row-label" ]
                    [ div [ class "account-row-username" ]
                        [ text (RellmAccounts.rellmAccountDisplayName account)
                        , if RellmAccounts.isAdmin account then
                            span [ class "account-admin-badge", title "Admin on this server" ] [ text "🛡️" ]

                          else
                            text ""
                        ]
                    , div [ classes [ "account-row-server-badge", account.server, "background-color-nav" ] ]
                        [ text (account.server ++ " | " ++ branding.name) ]
                    ]
                ]
            , notificationsButton shared account
            , button
                [ class "remove-btn"
                , onClick (Shared.RequestDelete (Shared.ConfirmAccountDelete account))
                ]
                [ text "╳" ]
            ]
        , accountRowAlerts shared account
        , accountAvatarMenuView shared account
        ]


{-| A connected Mastodon account's row -- see `accountRow`'s own doc for the shared row shape/
reasoning. Read-only for now, same as `connectedMastodonAccountChip` before it (no remove/disconnect
button, no enable switch -- see `AccountsPanel.mastodonAccounts`'s own doc on that being a first-pass
limitation), just reorderable alongside every other account item.
-}
mastodonAccountRow : Shared.Model -> Int -> Int -> Int -> MastodonAccount -> Html Shared.Msg
mastodonAccountRow shared count mainCount index mastodonAccount =
    let
        mainHostClass : String
        mainHostClass =
            hostnameToCSSClass shared.accounts.mainFrontendHost

        key : String
        key =
            AccountsPanel.combinedAccountItemKey (AccountsPanel.CombinedMastodonAccount mastodonAccount)

        reorderInfo :
            { moveAttrs : List (Html.Attribute Shared.Msg)
            , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
            , canMoveUp : Bool
            , canMoveDown : Bool
            }
        reorderInfo =
            accountItemReorderInfo shared count mainCount index key
    in
    div
        (id (AccountsPanel.accountRowDomId key)
            :: classes [ "account-row", "federated-account-row", mainHostClass, "background-color-nav", "border-color-accent" ]
            :: reorderInfo.moveAttrs
        )
        [ div [ class "account-row-main" ]
            [ div [ class "reorder-buttons" ]
                [ div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.canMoveUp ) ] ] [ reorderInfo.reorderPair.backward ]
                , div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.canMoveDown ) ] ] [ reorderInfo.reorderPair.forward ]
                ]
            , imageOrInitial [ "account-avatar" ] mastodonAccount.username Nothing
            , div [ class "account-row-label" ]
                [ div [ class "account-row-username" ] [ text ("⇄ @" ++ mastodonAccount.username) ]
                , div [ classes [ "account-row-server-badge", mainHostClass, "background-color-primary" ] ]
                    [ text mastodonAccount.instanceHost ]
                ]
            ]
        , if mastodonAccount.needsReauth then
            div [ class "account-row-alerts" ]
                [ button
                    [ type_ "button"
                    , class "account-needs-password"
                    , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg (AccountsPanel.MastodonConnectClicked mastodonAccount.instanceHost))
                    ]
                    [ text "Reconnect" ]
                ]

          else
            text ""
        ]


{-| A connected Bluesky account's row -- see `accountRow`'s own doc for the shared row shape/
reasoning. Reuses the same enable switch/remove button the former `blueskyAccountChip` had as a
horizontal `CombinedServerFeedItem` chip, since a Bluesky account moved to `CombinedAccountItem` (see that
type's own doc) without losing either capability.
-}
blueskyAccountRow : Shared.Model -> Int -> Int -> Int -> BlueskyAccount -> Html Shared.Msg
blueskyAccountRow shared count mainCount index blueskyAccount =
    let
        mainHostClass : String
        mainHostClass =
            hostnameToCSSClass shared.accounts.mainFrontendHost

        key : String
        key =
            AccountsPanel.combinedAccountItemKey (AccountsPanel.CombinedBlueskyAccount blueskyAccount)

        reorderInfo :
            { moveAttrs : List (Html.Attribute Shared.Msg)
            , reorderPair : { backward : Html Shared.Msg, forward : Html Shared.Msg }
            , canMoveUp : Bool
            , canMoveDown : Bool
            }
        reorderInfo =
            accountItemReorderInfo shared count mainCount index key

        label : String
        label =
            blueskyAccount.displayName |> Maybe.withDefault ("@" ++ blueskyAccount.handle)
    in
    div
        (id (AccountsPanel.accountRowDomId key)
            :: classes [ "account-row", "federated-account-row", mainHostClass, "background-color-nav", "border-color-accent" ]
            :: reorderInfo.moveAttrs
        )
        [ div [ class "account-row-main" ]
            [ div [ class "reorder-buttons" ]
                [ div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.canMoveUp ) ] ] [ reorderInfo.reorderPair.backward ]
                , div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not reorderInfo.canMoveDown ) ] ] [ reorderInfo.reorderPair.forward ]
                ]
            , switchInput blueskyAccount.enabled False (Shared.AccountsPanelMsg (AccountsPanel.ToggleBlueskyAccountEnabled blueskyAccount.handle))
            , a
                [ class "account-row-profile-link"
                , href ("https://bsky.app/profile/" ++ blueskyAccount.handle)
                , target "_blank"
                ]
                [ imageOrInitial [ "account-avatar" ] blueskyAccount.handle blueskyAccount.avatarUrl
                , div [ class "account-row-label" ]
                    [ div [ class "account-row-username" ] [ text ("⇄ " ++ label) ]
                    , div [ classes [ "account-row-server-badge", mainHostClass, "background-color-primary" ] ]
                        [ text ("@" ++ blueskyAccount.handle) ]
                    ]
                ]
            , button
                [ class "remove-btn"
                , onClick (Shared.AccountsPanelMsg (AccountsPanel.RemoveBlueskyAccountClicked blueskyAccount.handle))
                , title ("Disconnect " ++ blueskyAccount.handle)
                ]
                [ text "╳" ]
            ]
        , if blueskyAccount.needsReauth then
            div [ class "account-row-alerts" ]
                [ button
                    [ type_ "button"
                    , class "account-needs-password"
                    , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg (AccountsPanel.ReconnectBlueskyAccountClicked blueskyAccount.handle))
                    ]
                    [ text "Reconnect" ]
                ]

          else
            text ""
        ]


{-| Second row of `accountRow`, below `.account-row-main` -- the reauth button and/or push
notification error, if either applies to `account`. Renders nothing (not even an empty div) when
neither applies, so rows with nothing to report stay single-row.
-}
accountRowAlerts : Shared.Model -> RellmAccount -> Html Shared.Msg
accountRowAlerts shared account =
    let
        hasNotificationError : Bool
        hasNotificationError =
            Dict.member (RellmAccounts.rellmAccountId account) shared.accounts.notificationErrors
    in
    if not account.needsPassword && not hasNotificationError then
        text ""

    else
        div [ class "account-row-alerts" ]
            [ if account.needsPassword then
                let
                    -- "reauthentication" (not "password") when this account isn't on the
                    -- server we're actually browsing from -- clicking it still routes
                    -- through `PasswordNeededClicked`, but the wording makes clear it's
                    -- logging back into a different server, not this one.
                    needsPasswordLabel : String
                    needsPasswordLabel =
                        if account.server /= shared.accounts.browsingHost then
                            "Reauthentication Required"

                        else
                            "Password Required"
                in
                button
                    [ type_ "button"
                    , class "account-needs-password"
                    , stopPropagationAndPreventDefaultOnClick (Shared.AccountsPanelMsg (AccountsPanel.ReauthenticateButtonClicked account))
                    ]
                    [ text needsPasswordLabel ]

              else
                text ""
            , notificationError shared account
            ]


{-| "Enable notifications"/"🔔" toggle for `account`'s row (see `AccountsPanel.EnableNotificationsClicked`/
`DisableNotificationsClicked`) -- only rendered at all if `account.server` is both connected and
has a `WebPushConfig` (`RellmServers.rellmServerWebPushPublicKey`), i.e. there's actually something to
subscribe to; disabled (like the rest of the row's actions) while the account itself
`needsPassword`, since registering a subscription needs a working access/refresh token.

Also only rendered for an account whose `server` is `shared.accounts.browsingHost` -- the browser
holds at most one Web Push subscription today (see `AccountsPanel.pushSubscriptions`'s own doc
comment), tied to whichever single server's VAPID key it was created with, and that's always
`browsingHost`'s (the one server this tab's service worker/subscription could ever meaningfully be
scoped to). Offering the toggle for a federated-in account on some _other_ server would just
silently fail or steal the slot from `browsingHost`'s own account the moment it's clicked -- there's
no way to make it actually work without each server getting its own independently-scoped
subscription (a real, not-yet-built feature; see this button's own git history for the
investigation).

-}
notificationsButton : Shared.Model -> RellmAccount -> Html Shared.Msg
notificationsButton shared account =
    if account.server /= shared.accounts.browsingHost then
        text ""

    else
        case RellmServers.rellmServerWebPushPublicKey shared.accounts.servers account.server of
            Nothing ->
                text ""

            Just _ ->
                let
                    id : String
                    id =
                        RellmAccounts.rellmAccountId account

                    enabled : Bool
                    enabled =
                        Dict.member id shared.accounts.pushSubscriptions

                    error : Maybe String
                    error =
                        Dict.get id shared.accounts.notificationErrors
                in
                button
                    [ classList [ ( "notifications-btn", True ), ( "notifications-btn-enabled", enabled ), ( "notifications-btn-errored", error /= Nothing ) ]
                    , disabled account.needsPassword
                    , title
                        (case error of
                            Just reason ->
                                reason

                            Nothing ->
                                if enabled then
                                    "Disable browser notifications for this account"

                                else
                                    "Enable browser notifications for this account"
                        )
                    , stopPropagationAndPreventDefaultOnClick
                        (Shared.AccountsPanelMsg
                            (if enabled then
                                AccountsPanel.DisableNotificationsClicked account

                             else
                                AccountsPanel.EnableNotificationsClicked account
                            )
                        )
                    ]
                    [ text
                        (if enabled then
                            "🔔"

                         else if error /= Nothing then
                            "⚠️"

                         else
                            "🔕"
                        )
                    ]


{-| The actual text of `notificationsButton`'s last failure, if any (see `AccountsPanel.notificationErrors`) --
shown in-flow in `accountRowAlerts`, `account`'s row's second line (alongside the
`account-needs-password` badge), rather than as a tooltip or a floating bubble anchored to the
button itself: the button lives inside `.nav-panel`, which sets its own `overflow-y: auto` (and,
per the CSS spec, therefore also computes `overflow-x` to `auto`), so anything positioned to poke
outside the button just gets silently clipped instead of actually being readable.
-}
notificationError : Shared.Model -> RellmAccount -> Html msg
notificationError shared account =
    case Dict.get (RellmAccounts.rellmAccountId account) shared.accounts.notificationErrors of
        Just reason ->
            div [ class "account-notification-error" ] [ text reason ]

        Nothing ->
            text ""


avatarOrPlaceholder : List RellmServer -> RellmAccount -> Html msg
avatarOrPlaceholder servers account =
    imageOrInitial [ "account-avatar" ] account.username (RellmAccounts.rellmAccountAvatarUrl servers account)


{-| A checkbox styled as a toggle switch.
-}
switchInput : Bool -> Bool -> Shared.Msg -> Html Shared.Msg
switchInput isChecked isDisabled toggleMsg =
    label [ classList [ ( "switch", True ), ( "disabled", isDisabled ) ] ]
        [ input
            [ type_ "checkbox"
            , checked isChecked
            , disabled isDisabled
            , onClick toggleMsg
            ]
            []
        , span [ class "slider" ] []
        ]



-- LOGIN FORM


{-| The Server field is shared between logging in/creating an account and
adding a new server (see `AccountsPanel.AddServerClicked`): as soon as it names
a server we're not already connected to, Username/Password/Login/Create
Account are disabled and a full-width "Add Server" button appears right below
it instead. Once that succeeds (or the field already named a known server),
those re-enable, themed with _that_ server's colors rather than
`mainFrontendHost`'s -- see `AccountsPanel.GotNewServerResult` for the focus
handoff to Username that completes the "type a host, Enter, type a username,
Enter, type a password" flow.
-}
formView : Shared.Model -> Route -> Html Shared.Msg
formView shared currentRoute =
    div [ class "account-form" ]
        [ addAccountServerHeaderRow shared
        , addAccountServerFormBody shared currentRoute
        ]


{-| The merged "Add Account/Server" area's header row: the collapsed "Add Account/Server..." button
and the expanded "←" + Rellm/Mastodon/Bluesky tabs (see `AccountsPanel.AccountOrServerFormType`)
share one row, animated between the two via a per-item `max-width` transition
(`.add-account-server-header-row`/`.is-open`, see that CSS's own doc for why a shared grid-column
track didn't work here) rather than either being mounted/unmounted outright -- both are always
rendered, in the fixed order [button, "←", Rellm, Mastodon, Bluesky]; only which side's `max-width`
is open changes. `hideAddAccountFormButton` rendering nothing while there are no accounts yet (see
its own doc) needs no special-casing here -- an empty flex item just takes zero width on its own,
letting the tabs' `flex-grow` claim that space same as if it were never there.
-}
addAccountServerHeaderRow : Shared.Model -> Html Shared.Msg
addAccountServerHeaderRow shared =
    let
        activeType : AccountsPanel.AccountOrServerFormType
        activeType =
            AccountsPanel.activeAddAccountServerFormType shared.accounts
    in
    div [ classes [ "add-account-server-header-row", openClosedClass (AccountsPanel.shouldShowAddAccountForm shared.accounts) ] ]
        [ button
            [ classes [ "show-add-account-form-button", hostnameToCSSClass <| formThemeHost shared.accounts, "background-color-primary" ]
            , onClick (Shared.AccountsPanelMsg AccountsPanel.ShowAddAccountFormClicked)
            ]
            [ span [ class "header-row-chip" ] [ text "Add Account/Server..." ] ]
        , hideAddAccountFormButton shared (addAccountServerFormBusy shared activeType)
        , addAccountServerFormTabButton activeType AccountsPanel.RellmServerFormType "Rellm"
        , addAccountServerFormTabButton activeType AccountsPanel.MastodonServerFormType "Mastodon"
        , addAccountServerFormTabButton activeType AccountsPanel.BlueskyAccountFormType "Bluesky"
        ]


{-| The merged "Add Account/Server" area's lower part -- whichever tab's own fields
(`rellmAddAccountServerForm`/`mastodonServerFormView`+`mastodonConnectSection`/`blueskyConnectFormView`,
see `AccountsPanel.AccountOrServerFormType`) -- collapsed to zero height via the same
`grid-template-rows` 1fr/0fr trick `.account-avatar-menu` uses (`.add-account-server-form-body`/
`.is-open`) in step with `addAccountServerHeaderRow`'s own horizontal collapse, rather than appearing/
disappearing outright. Always renders the _active_ tab's fields (never all three at once) -- switching
tabs while already open just reflows the row's own natural height, with no separate animation of its
own.
-}
addAccountServerFormBody : Shared.Model -> Route -> Html Shared.Msg
addAccountServerFormBody shared currentRoute =
    div [ classes [ "add-account-server-form-body", openClosedClass (AccountsPanel.shouldShowAddAccountForm shared.accounts) ] ]
        [ case AccountsPanel.activeAddAccountServerFormType shared.accounts of
            AccountsPanel.RellmServerFormType ->
                rellmAddAccountServerForm shared currentRoute

            AccountsPanel.MastodonServerFormType ->
                div [ class "account-form" ]
                    [ mastodonServerFormView shared
                    , mastodonConnectSection shared
                    ]

            AccountsPanel.BlueskyAccountFormType ->
                blueskyConnectFormView shared.accounts.blueskyConnectForm
        ]


addAccountServerFormTabButton : AccountsPanel.AccountOrServerFormType -> AccountsPanel.AccountOrServerFormType -> String -> Html Shared.Msg
addAccountServerFormTabButton activeType tabType label =
    button
        [ type_ "button"
        , classList [ ( "accounts-panel-tab", True ), ( "selected", activeType == tabType ) ]
        , onClick (Shared.AccountsPanelMsg (AccountsPanel.AddAccountServerFormTypeSelected tabType))
        ]
        [ span [ class "header-row-chip" ] [ text label ] ]


{-| Whether the currently-active tab has a submission in flight -- used only to disable the shared
"←" collapse button while that's true, same as it was already disabled mid-submit before this was a
tabbed form.
-}
addAccountServerFormBusy : Shared.Model -> AccountsPanel.AccountOrServerFormType -> Bool
addAccountServerFormBusy shared activeType =
    case activeType of
        AccountsPanel.RellmServerFormType ->
            (shared.accounts.accountForm.status == AccountsPanel.Submitting)
                || (shared.accounts.addServerForm.status == AccountsPanel.Submitting)

        AccountsPanel.MastodonServerFormType ->
            shared.accounts.mastodonConnectPopupOpen /= Nothing

        AccountsPanel.BlueskyAccountFormType ->
            shared.accounts.blueskyConnectForm.status == AccountsPanel.Submitting


{-| The server whose theme the form's own controls (Login/Create Account,
and the collapsed "Add Account/Server..." button) should be tinted with: the
Server field's own host once it names a server we're connected to, falling
back to `mainFrontendHost` otherwise (e.g. the field is empty, still being
typed, or naming an unknown host -- see `AccountsPanel.AddServerClicked`).
-}
formThemeHost : AccountsPanel.Model -> String
formThemeHost accountsPanelModel =
    let
        form : AccountsPanel.AccountForm
        form =
            accountsPanelModel.accountForm
    in
    if AccountsPanel.isKnownServer accountsPanelModel form.server then
        String.trim form.server

    else
        accountsPanelModel.mainFrontendHost


{-| Square "←" button that collapses the Add Account/Server form back behind
its "Add Account/Server..." button (`AccountsPanel.HideAddAccountFormClicked`)
-- the same thing closing and reopening the Accounts Panel already does once
the form's idle (`AccountsPanel.collapseAddAccountFormIfIdle`), just reachable
without doing that. Shown to the left of the Login/Create Account buttons,
and (via `signInFromButton`) to the left of the SSO hand-off button -- the two
places offering a choice before either flow's actually been picked. Never
shown once there are no accounts yet (`AccountsPanel.shouldShowAddAccountForm`
is unconditionally `True` then -- there'd be no button to collapse back to).
-}
hideAddAccountFormButton : Shared.Model -> Bool -> Html Shared.Msg
hideAddAccountFormButton shared accountFieldsDisabled =
    if List.isEmpty shared.accounts.accounts then
        text ""

    else
        button
            [ type_ "button"
            , onClick (Shared.AccountsPanelMsg AccountsPanel.HideAddAccountFormClicked)
            , disabled accountFieldsDisabled
            , class "hide-add-account-form-button"
            , title "Back"
            ]
            [ span [ class "header-row-chip" ] [ text "←" ] ]


rellmAddAccountServerForm : Shared.Model -> Route -> Html Shared.Msg
rellmAddAccountServerForm shared currentRoute =
    let
        accountsPanelModel : AccountsPanel.Model
        accountsPanelModel =
            shared.accounts

        form : AccountsPanel.AccountForm
        form =
            accountsPanelModel.accountForm

        addForm : AccountsPanel.AddServerForm
        addForm =
            accountsPanelModel.addServerForm

        knownServer : Bool
        knownServer =
            AccountsPanel.isKnownServer accountsPanelModel form.server

        submitting : Bool
        submitting =
            form.status == AccountsPanel.Submitting

        accountFieldsDisabled : Bool
        accountFieldsDisabled =
            not knownServer || submitting

        -- Username/password auth is only ever offered for our own main
        -- server, unless an admin has flipped
        -- `DebugTab.allowUsernamePasswordForOtherHosts` -- see
        -- `AccountsPanel.isMainServer`.
        showUsernamePasswordFields : Bool
        showUsernamePasswordFields =
            AccountsPanel.isMainServer accountsPanelModel form.server
                || shared.accounts.debugTab.allowUsernamePasswordForOtherHosts

        serverEnterMsg : AccountsPanel.Msg
        serverEnterMsg =
            if not knownServer then
                AccountsPanel.AddServerClicked

            else if showUsernamePasswordFields then
                AccountsPanel.FocusInput "account-form-username"

            else
                AccountsPanel.NoOp

        -- `Nothing` at the Username-only step. Set the moment "Log In" is
        -- picked (`AccountsPanel.ChooseLoginClicked`); for "Create Account"
        -- (`ChooseCreateAccountClicked`), only once the policy confirmation
        -- modal's been accepted (`AccountsPanel.ConfirmCreateAccountClicked`)
        -- -- either way, this is also when the Password field first renders --
        -- see `AccountsPanel.Model.newAccountType`.
        newAccountType : Maybe AccountsPanel.NewAccountType
        newAccountType =
            accountsPanelModel.newAccountType

        -- Submitting for real (rather than just picking a flow) is the same
        -- message either way -- it's what the one visible button (alongside
        -- "<- Back") now does once `newAccountType` is set.
        submitMsg : AccountsPanel.Msg
        submitMsg =
            if newAccountType == Just AccountsPanel.CreateNewAccount then
                AccountsPanel.CreateAccountClicked

            else
                AccountsPanel.LoginClicked
    in
    Html.form
        [ class "account-form"

        -- The Server field is `type_ "url"` for its mobile keyboard (`/`,
        -- `.`, no space bar) -- but the browser's own URL constraint
        -- validation rejects plain hostnames like "localhost" (no scheme),
        -- which now matters once there's a real `type_ "submit"` button
        -- below: without this, clicking it never gets as far as firing
        -- `submit` at all, just a native "Enter a URL." bubble. We already
        -- do our own validation/error surfacing (`FormStatus.Errored`), so
        -- the browser's is only ever in the way here.
        , novalidate True

        -- Real `<form>` (rather than `div`) so Safari/Chrome/password
        -- managers recognize `account-form-username`/`account-form-password`
        -- as a credential pair worth offering to fill/save. Every button
        -- here is `type_ "button"` -- inert to native submission -- *except*
        -- the one that actually submits the password (Log In/Create
        -- Account, once `newAccountType` is set): that one's deliberately
        -- `type_ "submit"`, so clicking it fires a real `submit` event on
        -- this form rather than only an Elm `onClick`. That's the signal
        -- Chrome/Safari's own "Save password?" prompt is watching for in a
        -- JS-driven SPA with no page navigation -- an `onClick`-only button
        -- never triggers it, no matter how correct the field markup is.
        -- `Html.Events.onSubmit` always calls `preventDefault` (blocking the
        -- page reload a native submit would otherwise cause), so this is
        -- safe to let through for real rather than treating it as a stray
        -- event to swallow.
        , onSubmit
            (Shared.AccountsPanelMsg
                (if newAccountType == Nothing then
                    AccountsPanel.NoOp

                 else
                    submitMsg
                )
            )
        ]
        [ div [ class "account-form-field" ]
            [ input
                [ id "account-form-server"
                , type_ "url"
                , attribute "autocapitalize" "none"
                , attribute "autocorrect" "off"
                , spellcheck False
                , placeholder "Server"
                , value form.server
                , onInput (AccountsPanel.ServerChanged >> Shared.AccountsPanelMsg)
                , onEnter (Shared.AccountsPanelMsg serverEnterMsg)
                ]
                []
            , fieldClearButton submitting
                (not (String.isEmpty form.server))
                "account-form-server"
                (AccountsPanel.ServerChanged "")
                "Clear server"
            ]
        , if knownServer then
            text ""

          else
            let
                addingServer : Bool
                addingServer =
                    addForm.status == AccountsPanel.Submitting
            in
            button
                [ type_ "button"
                , onClick (Shared.AccountsPanelMsg AccountsPanel.AddServerClicked)
                , disabled (addingServer || String.isEmpty (String.trim form.server))
                , classes [ "add-server-button", accountsPanelModel.mainFrontendHost, "background-color-nav" ]
                ]
                [ text
                    (if addingServer then
                        "Checking…"

                     else
                        "Add Server"
                    )
                ]
        , if showUsernamePasswordFields then
            div [ class "account-form-field" ]
                [ input
                    [ id "account-form-username"
                    , type_ "text"
                    , name "username"
                    , attribute "autocapitalize" "none"
                    , attribute "autocorrect" "off"
                    , attribute "autocomplete" "username"
                    , spellcheck False
                    , placeholder "Username"
                    , value form.username
                    , onInput (AccountsPanel.UsernameChanged >> Shared.AccountsPanelMsg)

                    -- Enter here defaults to the Log In path (see
                    -- `ChooseLoginClicked`) -- the more common case, per the
                    -- Password field's own `autocomplete` choice below.
                    , onEnter (Shared.AccountsPanelMsg AccountsPanel.ChooseLoginClicked)
                    , disabled accountFieldsDisabled
                    ]
                    []
                , fieldClearButton accountFieldsDisabled
                    (not (String.isEmpty form.username))
                    "account-form-username"
                    (AccountsPanel.UsernameChanged "")
                    "Clear username"
                ]

          else
            text ""
        , if showUsernamePasswordFields then
            case newAccountType of
                Just accountType ->
                    div [ class "account-form-field password-field" ]
                        [ input
                            [ id "account-form-password"
                            , type_
                                (if form.showPasswordAsText then
                                    "text"

                                 else
                                    "password"
                                )
                            , name
                                (if accountType == AccountsPanel.CreateNewAccount then
                                    "new-password"

                                 else
                                    "current-password"
                                )

                            -- "new-password" for Create Account (offers a
                            -- browser-generated password, and won't try to
                            -- match this against an existing saved one);
                            -- "current-password" for Log In (offers the
                            -- matching saved password, if any). Only knowable
                            -- once `newAccountType` says which flow this is --
                            -- see its own doc.
                            , attribute "autocomplete"
                                (if accountType == AccountsPanel.CreateNewAccount then
                                    "new-password"

                                 else
                                    "current-password"
                                )
                            , placeholder "Password"
                            , value form.password
                            , onInput (AccountsPanel.PasswordChanged >> Shared.AccountsPanelMsg)
                            , onEnter (Shared.AccountsPanelMsg submitMsg)
                            , disabled accountFieldsDisabled
                            ]
                            []
                        , if String.isEmpty form.password then
                            text ""

                          else
                            button
                                [ type_ "button"
                                , classList
                                    [ ( "password-toggle-button", True )
                                    , ( "revealed", form.showPasswordAsText )
                                    ]
                                , onClick (Shared.AccountsPanelMsg AccountsPanel.PasswordVisibilityToggled)
                                , disabled accountFieldsDisabled
                                , title
                                    (if form.showPasswordAsText then
                                        "Hide password"

                                     else
                                        "Show password"
                                    )
                                ]
                                [ text "👁" ]
                        , fieldClearButton accountFieldsDisabled
                            (not (String.isEmpty form.password))
                            "account-form-password"
                            (AccountsPanel.PasswordChanged "")
                            "Clear password"
                        ]

                Nothing ->
                    text ""

          else
            text ""
        , if showUsernamePasswordFields then
            div [ class "account-form-buttons" ]
                (case newAccountType of
                    Nothing ->
                        [ button
                            [ type_ "button"
                            , onClick (Shared.AccountsPanelMsg AccountsPanel.ChooseLoginClicked)
                            , disabled accountFieldsDisabled
                            , classes [ hostnameToCSSClass <| formThemeHost shared.accounts, "background-color-primary" ]
                            ]
                            [ text "Login" ]
                        , button
                            [ type_ "button"
                            , onClick (Shared.AccountsPanelMsg AccountsPanel.ChooseCreateAccountClicked)
                            , disabled accountFieldsDisabled
                            , classes [ hostnameToCSSClass <| formThemeHost shared.accounts, "background-color-nav" ]
                            ]
                            [ text "Create Account" ]
                        ]

                    Just accountType ->
                        [ button
                            [ type_ "button"
                            , onClick (Shared.AccountsPanelMsg AccountsPanel.NewAccountBackClicked)
                            , disabled accountFieldsDisabled

                            -- Deliberately untinted (unlike the submit
                            -- button next to it) -- a plain, neutral grey
                            -- so it doesn't read as another server-themed
                            -- call to action, same as the Create Account
                            -- confirmation modal's "Cancel" button.
                            --
                            -- `back-button` itself just narrows it to a
                            -- third of the row (see accounts_panel.css) --
                            -- it's the less important of the two.
                            , class "back-button"
                            ]
                            [ text "← Back" ]
                        , button
                            [ -- `type_ "submit"` (not `"button"`, unlike every other
                              -- button in this form) -- deliberately the one control
                              -- that fires this `<form>`'s native `submit` event (see
                              -- the form's own `onSubmit` for why), rather than
                              -- dispatching `submitMsg` itself via `onClick` -- doing
                              -- both would submit twice per click.
                              type_ "submit"
                            , disabled accountFieldsDisabled
                            , classes
                                [ hostnameToCSSClass <| formThemeHost shared.accounts
                                , if accountType == AccountsPanel.CreateNewAccount then
                                    "background-color-nav"

                                  else
                                    "background-color-primary"
                                ]
                            ]
                            [ text
                                (if accountType == AccountsPanel.CreateNewAccount then
                                    "Create Account"

                                 else
                                    "Login"
                                )
                            ]
                        ]
                )

          else
            text ""
        , signInFromButton shared currentRoute accountFieldsDisabled
        , case ( form.status, addForm.status ) of
            ( AccountsPanel.Errored err, _ ) ->
                div [ class "auth-error" ] [ text err ]

            ( _, AccountsPanel.Errored err ) ->
                div [ class "auth-error" ] [ text err ]

            _ ->
                text ""
        ]


{-| A small circular "×" button overlaid on a field (see `rellmAddAccountServerForm`'s
server/username/password fields) that clears it in one click and refocuses
it (via `AccountsPanel.ClearFieldClicked`) -- shown only once there's
something typed in to clear.
-}
fieldClearButton : Bool -> Bool -> String -> AccountsPanel.Msg -> String -> Html Shared.Msg
fieldClearButton fieldDisabled visible domId clearMsg titleText =
    if visible then
        button
            [ type_ "button"
            , class "field-clear-button"
            , onClick (Shared.AccountsPanelMsg (AccountsPanel.ClearFieldClicked domId clearMsg))
            , disabled fieldDisabled
            , title titleText
            ]
            [ text "╳" ]

    else
        text ""


{-| Cross-server SSO hand-off (see `Shared.FederatedAuth`): lets someone who's
already signed into the Server field's host, elsewhere, sign in here without
retyping that host's password into this origin. Sends this origin's public
key (once generated -- near-instant after app load) to
`https://{form.server}/elm/auth/to/{publicKey}@{browsingHost}`, which is
`Pages.Auth.To.Key_` on that host -- a plain cross-origin `<a>` is enough,
`Main.elm`'s `onUrlRequest` already falls through to a full page load for it.

Only shown once the Server field names a host other than our own
(`AccountsPanel.isMainServer`) -- username/password auth (see
`rellmAddAccountServerForm`'s `showUsernamePasswordFields`) is the only way into our own
server, and this SSO hand-off is (ordinarily) the only way into anywhere
else. `DebugTab.allowUsernamePasswordForOtherHosts` can additionally enable
username/password for other hosts too, but never suppresses this button for
`browsingHost`/`mainFrontendHost` themselves.

-}
signInFromButton : Shared.Model -> Route -> Bool -> Html Shared.Msg
signInFromButton shared currentRoute accountFieldsDisabled =
    let
        accountsPanelModel : AccountsPanel.Model
        accountsPanelModel =
            shared.accounts

        server : String
        server =
            String.trim accountsPanelModel.accountForm.server
    in
    case ( shared.panels.federatedAuth.publicKey, not (String.isEmpty server) && not (AccountsPanel.isMainServer accountsPanelModel server) ) of
        ( Just publicKey, True ) ->
            div [ class "sign-in-from-row" ]
                [ --hideAddAccountFormButton shared accountFieldsDisabled
                  button
                    [ type_ "button"
                    , onClick
                        (Shared.NavigateExternal
                            ("https://"
                                ++ server
                                ++ "/elm/auth/to/"
                                ++ FederatedAuth.publicKeyToUrlString publicKey
                                ++ "@"
                                ++ accountsPanelModel.browsingHost
                                ++ "?start_path="
                                ++ Url.percentEncode (Route.toHref currentRoute)
                            )
                        )
                    , disabled accountFieldsDisabled
                    , classes [ "sign-in-from-button", hostnameToCSSClass <| formThemeHost accountsPanelModel, "background-color-primary" ]
                    ]
                    [ text ("Sign in from " ++ server ++ "…") ]
                ]

        _ ->
            text ""



-- CREATE ACCOUNT CONFIRMATION


{-| Covers the whole page (including the Accounts Panel) while the Create
Account confirmation step is up -- higher `z-index` than `sharedBackdrop`
since it can appear on top of the (already open) Accounts Panel. Always
rendered, like the other backdrops, so opening/closing is a CSS transition.
-}
createAccountConfirmationBackdrop : Shared.Model -> Html Shared.Msg
createAccountConfirmationBackdrop shared =
    UI.Modal.backdrop
        (shared.accounts.createAccountConfirmation /= Nothing)
        (Shared.AccountsPanelMsg AccountsPanel.CancelCreateAccountClicked)


{-| The confirmation step shown after clicking "Create Account" at the
Username-only step (`AccountsPanel.ChooseCreateAccountClicked`), before the
Password field even renders: the target server's identity (the same
glyph+name as `homeLinkContent`, per the "home button style" this was asked
to reuse) plus its description/privacy policy/media policy from `ServerInfo`
-- fields the Elm frontend otherwise never surfaces, despite being meant for
exactly this per their proto doc comments -- so the user can see what
they're signing up for before entering a password at all. "Accept and
Continue" (`AccountsPanel.ConfirmCreateAccountClicked`) doesn't create the
account itself -- it just records acceptance and reveals the Password field;
the actual `CreateAccount` RPC fires once that's submitted.

A centered dialog (unlike the edge-anchored Accounts/Starred panels)
since it interrupts a specific action rather than being an ambient panel.
Always rendered (empty when closed) so the backdrop's fade isn't paired with
the dialog itself just popping in/out.

-}
createAccountConfirmationModal : Shared.Model -> Html Shared.Msg
createAccountConfirmationModal shared =
    case shared.accounts.createAccountConfirmation of
        Nothing ->
            UI.Modal.view
                { class = "create-account-modal", isOpen = False, header = text "", bodyAttrs = [], body = [], buttons = [] }

        Just pending ->
            let
                info : Proto.Rellm.ServerInfo
                info =
                    RellmServers.rellmServerInfoOf pending.server
            in
            UI.Modal.view
                { class = "create-account-modal"
                , isOpen = True
                , header = RellmServers.rellmServerNameAndLogo pending.server RellmServers.RegularServerLogo
                , bodyAttrs =
                    [ id AccountsPanel.createAccountModalBodyId
                    , on "scroll" (Decode.map (AccountsPanel.CreateAccountModalScrolled >> Shared.AccountsPanelMsg) scrolledToBottomDecoder)
                    ]
                , body =
                    [ policyMarkdown "" info.description
                    , policyMarkdown "Privacy Policy" info.privacyPolicy
                    , policyMarkdown "Media Policy" info.mediaPolicy
                    ]
                , buttons =
                    [ button
                        [ onClick (Shared.AccountsPanelMsg AccountsPanel.CancelCreateAccountClicked) ]
                        [ text "Cancel" ]
                    , button
                        [ onClick (Shared.AccountsPanelMsg AccountsPanel.ConfirmCreateAccountClicked)
                        , disabled (not pending.reachedBottom)
                        , classes [ hostnameToCSSClass pending.server.frontendHost, "background-color-primary" ]
                        , title
                            (if pending.reachedBottom then
                                ""

                             else
                                "Please scroll down to read the rest first"
                            )
                        ]
                        [ text "Accept and Continue" ]
                    ]
                }



-- DELETE CONFIRMATION


{-| Covers the whole page while a delete confirmation is up -- same reasoning
as `createAccountConfirmationBackdrop`, and the two never appear at once (both
only ever come from actions inside the Accounts Panel, which can only have one
such step in flight).
-}
deleteConfirmationBackdrop : Shared.Model -> Html Shared.Msg
deleteConfirmationBackdrop shared =
    UI.Modal.backdrop (shared.panels.confirmingDeleteFor /= Nothing) Shared.CancelDelete


{-| The shared "are you sure you want to delete this?" dialog for every kind
of delete in the app (currently Accounts and Servers -- see
`Shared.DeleteConfirmation`) -- built on `UI.Modal` the same way
`createAccountConfirmationModal` is, so a future Post delete (etc.) needs only
a new `DeleteConfirmation` constructor and a case here, not a whole new dialog.
-}
deleteConfirmationModal : Shared.Model -> Html Shared.Msg
deleteConfirmationModal shared =
    case shared.panels.confirmingDeleteFor of
        Nothing ->
            UI.Modal.view
                { class = "confirm-delete-modal", isOpen = False, header = text "", bodyAttrs = [], body = [], buttons = [] }

        Just confirmation ->
            let
                ( heading, message, deleteButtonText ) =
                    case confirmation of
                        Shared.ConfirmAccountDelete account ->
                            ( "Remove Account?"
                            , "Remove "
                                ++ RellmAccounts.rellmAccountDisplayName account
                                ++ " ("
                                ++ account.server
                                ++ ")? You'll need to log in again to use it."
                            , "Delete"
                            )

                        Shared.ConfirmServerDelete server ->
                            ( "Remove Server?"
                            , "Remove " ++ server.frontendHost ++ " from your server list?"
                            , "Delete"
                            )

                        Shared.ConfirmMediaDelete media ->
                            ( "Delete Media?"
                            , "Delete " ++ Maybe.withDefault "this media item" media.name ++ "? This can't be undone."
                            , "Delete"
                            )

                        Shared.ConfirmMarkdownEditingDataLost ->
                            ( "Delete Markdown Edits?"
                            , "Discard your unsaved changes? This can't be undone."
                            , "Delete Changes"
                            )

                        Shared.ConfirmSyncSourceDelete source deleteSyncedEvents _ ->
                            let
                                sourceLabel : String
                                sourceLabel =
                                    case source.configuration of
                                        Just (Configuration.IcsSubscriptionUrl url) ->
                                            url

                                        Just (Configuration.RssSubscriptionUrl url) ->
                                            url

                                        Just (Configuration.AtomSubscriptionUrl url) ->
                                            url

                                        Nothing ->
                                            "this source"
                            in
                            ( "Delete Sync Source?"
                            , if deleteSyncedEvents then
                                "Stop syncing from "
                                    ++ sourceLabel
                                    ++ ", deleting the "
                                    ++ SyncSources.syncedCountsLabel source
                                    ++ " it synced? This can't be undone."

                              else
                                "Stop syncing from "
                                    ++ sourceLabel
                                    ++ "? This will leave the "
                                    ++ SyncSources.syncedCountsLabel source
                                    ++ " it synced on your profile, no longer associated with a source."
                            , "Delete"
                            )

                        Shared.ConfirmPostDelete post _ ->
                            ( "Delete Post?"
                            , "Delete \"" ++ Posts.postTitleText post ++ "\"? This can't be undone."
                            , "Delete"
                            )

                        Shared.ConfirmEventDelete event _ ->
                            let
                                occasionCount : Int
                                occasionCount =
                                    List.length event.occasions
                            in
                            ( "Delete Event?"
                            , "Delete \""
                                ++ (event.post |> Maybe.map Posts.postTitleText |> Maybe.withDefault "this event")
                                ++ "\""
                                ++ (if occasionCount > 1 then
                                        " and all " ++ String.fromInt occasionCount ++ " of its dates"

                                    else
                                        ""
                                   )
                                ++ "? This can't be undone."
                            , "Delete"
                            )

                        Shared.ConfirmOccasionDelete occasion event _ ->
                            ( "Delete This Date?"
                            , "Delete "
                                ++ Events.occasionWhenText shared.time occasion
                                ++ " from \""
                                ++ (event.post |> Maybe.map Posts.postTitleText |> Maybe.withDefault "this event")
                                ++ "\"? This can't be undone."
                            , "Delete"
                            )

                        Shared.ConfirmUserDelete user _ ->
                            ( "Delete User?"
                            , "Delete "
                                ++ Users.titleName user
                                ++ "'s account? This can't be undone."
                            , "Delete"
                            )

                        Shared.ConfirmOccasionSyncDestinationDelete _ _ destinationLabel _ ->
                            ( "Delete Sync?"
                            , "Stop syncing this event to "
                                ++ destinationLabel
                                ++ "? This won't delete the post already made there."
                            , "Delete"
                            )

                        Shared.ConfirmPostSyncDestinationDelete _ _ destinationLabel _ ->
                            ( "Delete Sync?"
                            , "Stop syncing this post to "
                                ++ destinationLabel
                                ++ "? This won't delete the post already made there."
                            , "Delete"
                            )
            in
            UI.Modal.view
                { class = "confirm-delete-modal"
                , isOpen = True
                , header = text heading
                , bodyAttrs = []
                , body = [ p [ class "confirm-delete-message" ] [ text message ] ]
                , buttons =
                    [ button [ onClick Shared.CancelDelete ] [ text "Cancel" ]
                    , button [ onClick Shared.ConfirmDelete, class "confirm-delete-button" ] [ text deleteButtonText ]
                    ]
                }


{-| Reads a `scroll` event's target `scrollTop`/`clientHeight`/`scrollHeight`
to decide whether it's scrolled (near enough) to the bottom -- used to gate
the Create Account confirmation modal's submit button on the user having
actually scrolled through its policy text (see `createAccountConfirmationModal`).
A couple pixels of slack absorbs sub-pixel layout rounding some browsers
produce, which would otherwise leave the true bottom permanently
unreachable.
-}
scrolledToBottomDecoder : Decode.Decoder Bool
scrolledToBottomDecoder =
    Decode.map3 (\scrollTop clientHeight scrollHeight -> scrollTop + clientHeight >= scrollHeight - 2)
        (Decode.at [ "target", "scrollTop" ] Decode.float)
        (Decode.at [ "target", "clientHeight" ] Decode.float)
        (Decode.at [ "target", "scrollHeight" ] Decode.float)


{-| One optional block of server-supplied policy Markdown (rendered via
`Components.Markdown.view`, same as post content), omitted entirely when
blank (most servers won't set all of description/privacy policy/media
policy). An empty `heading` is used for the plain description, which gets no
heading of its own.
-}
policyMarkdown : String -> Maybe String -> Html msg
policyMarkdown heading maybeText =
    case Maybe.map String.trim maybeText of
        Just body ->
            if body == "" then
                text ""

            else
                div [ class "create-account-policy" ]
                    [ if heading == "" then
                        text ""

                      else
                        div [ class "create-account-policy-heading" ] [ text heading ]
                    , Markdown.view [ classes [ "post-detail-content", "create-account-policy-body" ] ] body
                    ]

        Nothing ->
            text ""



-- NEW POST TOGGLE


{-| Opens `Shared.CreateNewPanel` -- only shown at all once at least one
signed-in account is actually eligible to create a Post (see
`CreateNewPanel.hasEligibleAccount`), same "no point showing chrome for
something nobody here could use" reasoning as the Starred toggle's own
gate below. Styled exactly like that toggle (`.nav-menu-toggle.circular`,
accounts\_panel.css) -- same fixed circular size, and the same
`transition: border-radius` on `openClosedClass` squaring its bottom corners
off while its panel is open -- rather than `.nav-link`'s route-highlight
look, since this is a plain panel toggle with nowhere to navigate to, not a
page link. `stopPropagationOn`, not plain `onClick`, for the same reason
`starredPostsToggle` uses it -- tapping it shouldn't also trigger
`headerNav`'s own tap-anywhere `Shared.ScrollToTop`.
-}
newPostToggle : Shared.Model -> Html Shared.Msg
newPostToggle shared =
    button
        [ classes [ "nav-menu-toggle", "circular", openClosedClass (CreateNewPanel.isOpen shared.panels.createNewPanel) ]
        , stopPropagationOn "click" (Decode.succeed ( Shared.CreateNewPanelMsg CreateNewPanel.ToggleOpen, True ))
        , title "Create New"
        ]
        [ text "+" ]



-- STARRED POSTS TOGGLE


{-| Only shown at all once at least one Post has been starred (see
`Shared.StarredPanel.starKey`) -- only show the nav icon once there's
something behind it. Just the toggle button -- unlike `accountsMenu`, its
panel (`starredPanel`) is rendered separately, as a direct child of
`.navbar` itself rather than of this button's own `.starred-menu` wrapper, so it
can hug the actual screen edge (see `.starred-panel` in starred\_posts\_panel.css).
Uses `stopPropagationOn`, not plain `onClick`, so tapping it doesn't also
trigger `headerNav`'s own tap-anywhere `Shared.ScrollToTop`.
-}
starredPostsToggle : Shared.Model -> Html Shared.Msg
starredPostsToggle shared =
    div [ class "starred-menu" ]
        [ button
            [ classes [ "nav-menu-toggle", "circular", openClosedClass shared.panels.starredPanel.showStarredPanel ]
            , stopPropagationOn "click" (Decode.succeed ( Shared.StarredPanelMsg StarredPanel.ToggleStarredPanel, True ))
            , title "Starred"
            ]
            [ text "⭐"
            , span
                [ classes
                    [ "starred-count-badge"
                    , hostnameToCSSClass shared.accounts.mainFrontendHost
                    , "background-color-nav"
                    , "border-color-primary-text"
                    ]
                ]
                [ text (String.fromInt (Set.size shared.panels.starredPanel.starredPostIds)) ]
            ]
        ]


{-| The Starred panel's content -- see `starredPostsToggle` for why this
is separate from (and rendered outside) the toggle button. Its own content is
`StarredPanel.view` -- it returns `Html StarredPanel.Msg` rather
than `Html Shared.Msg` (unlike the rest of this module's panels), since
`Shared.StarredPanel` can't itself import `Shared` (that'd be a cycle --
`Shared` already imports it for `Shared.Model`'s `starredPanel` field),
so it's mapped into `Shared.Msg` here instead.
-}
starredPanel : Shared.Model -> Route -> Html Shared.Msg
starredPanel shared currentRoute =
    Html.map Shared.StarredPanelMsg
        (StarredPanel.view
            shared.time
            shared.basePath
            shared.accounts
            (currentStarredPostKey shared currentRoute)
            (currentStarredOccasionKey shared currentRoute)
            shared.panels.starredPanel
            shared.mediaRenderer
        )


{-| The `starKey` of the Post currently being viewed (see
`Pages.Post.PostId_`), if `currentRoute` is that page -- lets
`Shared.StarredPanel.view` highlight the matching entry, if any, with
its server's colors. `params.postId` is either a bare id (a post on
`mainFrontendHost`) or `id@host` -- see `Components.Posts.parsePostRouteId`.
-}
currentStarredPostKey : Shared.Model -> Route -> Maybe String
currentStarredPostKey shared currentRoute =
    case currentRoute of
        Route.Post__PostId_ params ->
            let
                ( postId, host ) =
                    Posts.parsePostRouteId shared.accounts.mainFrontendHost params.postId
            in
            Just (StarredPanel.rawKey postId host)

        _ ->
            Nothing


{-| The currently-viewed `Occasion`'s own `Post` id (see
`Pages.Event.PostId_`), if `currentRoute` is that page -- mirrors
`currentStarredPostKey` exactly, just for `Shared.StarredPanel`'s Event
highlighting (see `Components.Events.eventCard`'s own `current` param).
-}
currentStarredOccasionKey : Shared.Model -> Route -> Maybe String
currentStarredOccasionKey shared currentRoute =
    case currentRoute of
        Route.Event__PostId_ params ->
            let
                ( occasionPostId, _ ) =
                    Events.parseEventRouteId shared.accounts.mainFrontendHost params.postId
            in
            Just occasionPostId

        _ ->
            Nothing


{-| Only shown at all once `MessagingPanel.hasEligibleAccount` (a signed-in
account with `READ_PERSONAL_MESSAGES`/`READ_ALL_SYSTEM_MESSAGES`/`ADMIN`) --
mirrors `starredPostsToggle`'s own "only show once there's something behind
it" gating and `.starred-menu`/separately-mounted-panel structure (see
`messagingPanel`, mounted as a `.navbar` direct child in `headerNav`, same
reasoning as `starredPanel`). The unread badge (`MessagingPanel.totalUnreadCount`,
styled exactly like `starredPostsToggle`'s own `.starred-count-badge`) is
hidden at `0` rather than shown as a literal "0" -- unlike Starred's count,
which is always known from boot (`starredPostIds` persists locally), this one
only reflects whatever's actually been fetched so far (see that function's
own doc caveat), so a `0` here is ambiguous between "genuinely caught up" and
"haven't checked yet" -- hiding it in both cases reads better than a
misleadingly confident zero.
-}
messagingToggle : Shared.Model -> Route -> Html Shared.Msg
messagingToggle shared currentRoute =
    let
        unreadCount : Int
        unreadCount =
            MessagingPanel.totalUnreadCount shared.panels.messagingPanel

        -- Highlighted the same way `postsLink`/`eventsLink`/etc. highlight
        -- themselves for their own `currentRoute` -- just `background-color-nav`
        -- alone (no paired `hostnameToCSSClass` the way those add) since this
        -- button's already a `.navbar` descendant, which carries that class
        -- itself (see `headerNav`); `withDescendants` (`UI.EmittedStylesheet`)
        -- emits `background-color-nav`'s color rule for *either* form.
        currentPageClasses : List String
        currentPageClasses =
            if currentRoute == Route.Messages then
                [ "background-color-nav-contrast" ]

            else
                []
    in
    div [ class "messaging-menu" ]
        [ button
            [ classes ([ "nav-menu-toggle", "circular", openClosedClass (MessagingPanel.isOpen shared.panels.messagingPanel) ] ++ currentPageClasses)
            , stopPropagationOn "click" (Decode.succeed ( Shared.MessagingPanelMsg MessagingPanel.ToggleOpen, True ))
            , title "Messages"
            ]
            [ text "✉️"
            , if unreadCount <= 0 then
                text ""

              else
                span
                    [ classes
                        [ "starred-count-badge"
                        , hostnameToCSSClass shared.accounts.mainFrontendHost
                        , "background-color-nav"
                        , "border-color-primary-text"
                        ]
                    ]
                    [ text (String.fromInt unreadCount) ]
            ]
        ]


{-| The Messaging panel's content -- see `messagingToggle` for why this is
separate from (and rendered outside) the toggle button. `MessagesPage.view`
returns `Html MessagesPage.Msg`, doubly-mapped here through
`Shared.MessagingPanel.Msg` (which can't itself import `Shared`, same
cycle-avoidance reasoning as `Shared.StarredPanel`) into `Shared.Msg`.
-}
messagingPanel : Shared.Model -> Html Shared.Msg
messagingPanel shared =
    Html.map Shared.MessagingPanelMsg (MessagingPanel.view shared.time shared.accounts shared.panels.messagingPanel)


{-| A collapsible panel, one per admin-capable signed-in account, for setting
which frontend (Flutter/React/Elm) that account's server serves at its root
(`ServerInfo.webUserInterface`, via `AccountsPanel.SetWebUserInterfaceClicked`).
Shows that account's server (hostname + name) above its username/avatar so
it's clear which admin identity a change would be made as, since the RPC is
authenticated per-account rather than "whichever account is currently
active".
-}
adminAccountPanel : Shared.Model -> RellmAccount -> Html Shared.Msg
adminAccountPanel shared account =
    let
        id : String
        id =
            RellmAccounts.rellmAccountId account

        isOpen : Bool
        isOpen =
            AdminTab.isAccountPanelOpen id shared.accounts.adminTab

        adminServer : Maybe RellmServer
        adminServer =
            findServer shared account.server

        adminServerName : String
        adminServerName =
            adminServer
                |> Maybe.map (RellmServers.brandingOf >> .name)
                |> Maybe.withDefault ""

        adminServerLogo : Html Shared.Msg
        adminServerLogo =
            case adminServer of
                Just s ->
                    let
                        branding : Branding
                        branding =
                            RellmServers.brandingOf s
                    in
                    imageOrInitial [ "admin-account-server-logo" ] branding.name branding.logoUrl

                Nothing ->
                    text ""
    in
    div [ class "admin-account-panel" ]
        [ button
            [ class "admin-account-toggle"
            , onClick (Shared.AccountsPanelMsg (AccountsPanel.AdminTabMsg (AdminTab.ToggleAccountPanel id)))
            ]
            [ div [ class "admin-account-toggle-content" ]
                [ div [ class "admin-account-server-row" ]
                    [ adminServerLogo
                    , span [ class "admin-account-server-host" ] [ text account.server ]
                    , span [ class "admin-account-server-name" ] [ text adminServerName ]
                    ]
                , div [ class "admin-account-identity-row" ]
                    [ accountsMenuAvatar shared account
                    , span [ class "admin-account-username" ] [ text (RellmAccounts.rellmAccountDisplayName account) ]
                    ]
                ]
            , span
                [ classes
                    ("admin-account-chevron"
                        :: (if isOpen then
                                [ "open" ]

                            else
                                []
                           )
                    )
                ]
                [ text "▾" ]
            ]
        , if isOpen then
            let
                currentUi : WebUserInterface
                currentUi =
                    adminServer
                        |> Maybe.map RellmServers.rellmServerInfoOf
                        |> Maybe.andThen .webUserInterface
                        |> Maybe.withDefault REACTTAMAGUI
            in
            webUiToggleRow id account.server currentUi

          else
            text ""
        ]


{-| The "New Post" composer (see `Shared.CreateNewPanel`) -- toggled from its
own nav icon (`newPostToggle`, below), like the Accounts/Starred panels,
rather than opened contextually. Mounted directly in `layout` (not inside
`headerNav`) since -- unlike those two -- it opens from just under the top nav
as a `.navbar` _sibling_ rather than one of its dropdowns (see
`create_new_panel.css`'s own `top` comment for why), so it needs its own
z-index above `.navbar` to avoid `.navbar` painting over it, yet still below
both `markdownPanel`/`myMediaPanel` below since either can be opened _from_
it (see `create_new_panel.css`'s own z-index comment).
-}
createNewPanel : Shared.Model -> Html Shared.Msg
createNewPanel shared =
    Html.map Shared.CreateNewPanelMsg (CreateNewPanel.view shared.time.browserTimeZone shared.accounts shared.panels.createNewPanel)


{-| The app-wide Markdown editor (see `Shared.MarkdownPanel`) -- unlike the
Accounts/Starred panels, it isn't toggled from a nav icon of its own;
it's opened contextually (e.g. `Pages.Post.PostId_`'s Edit/Reply buttons, or
`CreateNewPanel`'s own Edit button) via
`Shared.MarkdownPanelMsg (MarkdownPanel.Open ...)`, so it's mounted directly in
`layout` rather than inside `headerNav`. Above `createNewPanel` and `.navbar`
itself (and, with it, the Accounts/Starred panels -- see
`markdown_panel.css`'s own z-index comment) but below `myMediaPanel`/the
Media Viewer panel -- if a post's Edit button is used while either of those
also happens to be open, they still layer above it rather than being hidden
behind it.
-}
markdownPanel : Shared.Model -> Html Shared.Msg
markdownPanel shared =
    Html.map Shared.MarkdownPanelMsg (MarkdownPanel.view shared.accounts shared.panels.markdownPanel)


{-| The AI image generation panel (see `Shared.MediaGeneratorPanel`) -- opened contextually (a
Post's/Event's own "Generate Media…" button, next to its "Edit Media…"), so it's mounted directly in
`layout` too, same as `markdownPanel`. Sits just below `myMediaPanel` (see
`media_generator_panel.css`'s own z-index comment) -- this panel opens that one, in `MultiSelect`
mode, to pick its own reference media, and it should visibly win that overlap rather than getting
buried behind it.
-}
mediaGeneratorPanel : Shared.Model -> Html Shared.Msg
mediaGeneratorPanel shared =
    Html.map Shared.MediaGeneratorPanelMsg (MediaGeneratorPanel.view shared.time shared.accounts shared.panels.mediaGeneratorPanel)


{-| The "My Media" panel (see `Shared.MyMediaPanel`) -- opened from a
signed-in Account chip's media button (`accountRow`, below), not a nav icon,
so it's mounted directly in `layout` too, same as `markdownPanel`. Sits above
the Markdown/New Post/Media Generator panels and `.navbar` itself -- and, with
it, the Accounts/Starred panels (see `my_media_panel.css`'s z-index) --
browsing your own media reasonably wins over a stale editor/composer/generator
left open behind it, and should cover the very Accounts Panel it was opened
from rather than getting buried behind it. Still below the Media Viewer panel
and `.modal`, though.
-}
myMediaPanel : Shared.Model -> Html Shared.Msg
myMediaPanel shared =
    Html.map Shared.MyMediaPanelMsg (MyMediaPanel.view shared.windowSize.width shared.accounts shared.panels.myMediaPanel)


{-| The breadcrumb trail (see `Shared.Breadcrumbs`) at the bottom of `.navbar`
-- unlike the Starred toggle/panel, there's no nav icon of its own;
whichever page has a chain to show (currently just `Pages.Post.PostId_`) sets
it directly via `Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot ...)`, so this just
renders whatever's currently there (empty if nothing is).
-}
breadcrumbsBar : Shared.Model -> Html Shared.Msg
breadcrumbsBar shared =
    Html.map Shared.BreadcrumbsMsg (Breadcrumbs.bar shared.accounts shared.breadcrumbs)


{-| The popup opened by tapping a breadcrumb segment (see
`Shared.Breadcrumbs.replyPanel`), anchored just under `breadcrumbsBar`'s own
row -- mounted as a `.navbar` descendant (see `headerNav`), not directly in
`layout` like `markdownPanel` above, so its positioning (`position: absolute`,
see nav.css) resolves against `.navbar` itself.
-}
breadcrumbsReplyPanel : Shared.Model -> Html Shared.Msg
breadcrumbsReplyPanel shared =
    Html.map Shared.BreadcrumbsMsg (Breadcrumbs.previewPanel shared.basePath shared.accounts shared.breadcrumbs)


{-| The app-wide fullscreen image/video viewer (see `Shared.MediaViewerPanel`)
-- opened contextually, same as `markdownPanel` above, by tapping a Post's
media (`Components.PostCard`'s `onMediaClicked`), not from a nav icon, so it's
mounted directly in `layout` too. Sits above the New Post/Markdown/My Media
panels and the Accounts/Starred panels alike (see
`media_viewer_panel.css`'s z-index) -- a fullscreen image reasonably wins over
a stale editor/composer left open behind it, and stays on top even if the
nav's own dropdowns are then opened over it.
-}
mediaViewerPanel : Shared.Model -> Html Shared.Msg
mediaViewerPanel shared =
    Html.map Shared.MediaViewerPanelMsg (MediaViewerPanel.view shared.accounts shared.panels.mediaViewerPanel)


{-| Flutter is included for parity with the other two, but permanently
disabled -- see `WebUserInterface`'s doc comment: it's badly behind React/Elm
and not meant to be chosen going forward.
-}
webUiToggleRow : String -> String -> WebUserInterface -> Html Shared.Msg
webUiToggleRow id serverHost currentUi =
    div [ class "web-ui-toggle-row" ]
        [ webUiButton "Elm" False (currentUi == ELMSPA) serverHost (AccountsPanel.SetWebUserInterfaceClicked id ELMSPA)
        , webUiButton "React" False (currentUi == REACTTAMAGUI) serverHost (AccountsPanel.SetWebUserInterfaceClicked id REACTTAMAGUI)
        , webUiButton "Flutter" True (currentUi == FLUTTERWEB) serverHost (AccountsPanel.SetWebUserInterfaceClicked id FLUTTERWEB)
        ]


{-| When selected, tinted with `serverHost`'s own `background-color-primary`
(see `UI.EmittedStylesheet`) -- this button is per-account, so it should
reflect that account's server, not `mainFrontendHost`.
-}
webUiButton : String -> Bool -> Bool -> String -> AccountsPanel.Msg -> Html Shared.Msg
webUiButton label_ isDisabled isSelected serverHost msg =
    button
        [ classes
            ("web-ui-button"
                :: (if isSelected then
                        [ serverHost, "background-color-primary" ]

                    else
                        []
                   )
            )
        , disabled isDisabled
        , onClick (Shared.AccountsPanelMsg msg)
        ]
        [ text label_ ]
