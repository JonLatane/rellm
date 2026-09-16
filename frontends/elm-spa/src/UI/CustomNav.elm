module UI.CustomNav exposing
    ( CustomTab
    , CustomTabIcon(..)
    , CustomTabTarget(..)
    , HomePageConfig
    , TargetKind(..)
    , allCalendarDisplayModes
    , allNavigationTabStyles
    , calendarDisplayModeFromText
    , calendarDisplayModeText
    , defaultHomePageConfig
    , defaultPathFor
    , effectiveTabStyle
    , effectiveTabs
    , homeConfig
    , homeTargetKindFromText
    , iconView
    , navLinkView
    , navigationTabStyleClass
    , navigationTabStyleFromText
    , navigationTabStyleText
    , resolvedTitle
    , selectableHomeTargetKinds
    , selectableTargetKinds
    , targetKind
    , targetKindFromText
    , targetKindText
    , toProtoHomeConfig
    , toProtoTab
    )

{-| Elm-land counterparts of `CustomNavigationTab`'s two `oneof`s (`target`/`icon`, see
`protos/server_configuration.proto`), plus the rendering/routing logic shared by the real top nav
(`UI.headerNav`, once `Shared.AccountsPanel.Model.mainFrontendHost`'s `ServerConfiguration` has a
`customTabs` set) and `Components.Pages.ServerInformationPage.SettingsTab`'s preview/editor of that
same `CustomNavigationTabSet`.

`CustomTabTarget`/`CustomTabIcon` exist because the generated `oneof` types
(`Proto.Rellm.CustomNavigationTab.Target.Target`/`...Icon.Icon`) are generic in both branches'
payload type (`Target a0 a1`/`Icon a0 a1`) -- fine for the wire format, but awkward to pattern-match
on directly everywhere this is used. `fromProtoTab`/`toProtoTab` round-trip a `CustomNavigationTab`
to/from this module's own `CustomTab`, `Nothing` only for a malformed proto value (`target`/`icon`
unset -- shouldn't happen for anything this app itself ever saves, but is possible for a
hand-edited/future-versioned config).
-}

import Gen.Route as Route exposing (Route)
import Html exposing (Html, a, img, span, text)
import Html.Attributes exposing (alt, attribute, class, href, src, title)
import Proto.Rellm exposing (CustomHomePage, CustomNavigationTab, CustomNavigationTabSet)
import Proto.Rellm.CalendarDisplayMode exposing (CalendarDisplayMode(..))
import Proto.Rellm.CustomHomePage.Target as ProtoHomeTarget
import Proto.Rellm.CustomNavigationTab.Icon as ProtoIcon
import Proto.Rellm.CustomNavigationTab.Target as ProtoTarget
import Proto.Rellm.NavigationTab exposing (NavigationTab(..))
import Proto.Rellm.NavigationTabStyle exposing (NavigationTabStyle(..), defaultNavigationTabStyle)
import Shared
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import UI.Classes exposing (classes, hostnameToCSSClass)


{-| Elm-land mirror of `CustomNavigationTab`'s `target` `oneof` -- one of the app's own predefined
tabs (`NavigationTab`), a specific Post (e.g. a custom business site's page), or a user profile
(`TargetProfile`, from the proto's `is_profile` branch) -- unlike the other two, that branch carries
no payload of its own on the wire (just `bool`), so which profile is entirely determined by the
enclosing `CustomNavigationTab.path` (see `CustomTab.path`'s own doc) -- the tab's url *is* that
username's own `/:username` route, just also featured as a styled nav tab.
-}
type CustomTabTarget
    = TargetTab NavigationTab
    | TargetPost String
    | TargetProfile


{-| Elm-land mirror of `CustomNavigationTab`'s `icon` `oneof` -- an emoji glyph, or a `Media` id
(rendered via `RellmServers.mediaUrl`, see `iconView`).
-}
type CustomTabIcon
    = EmojiIcon String
    | MediaIcon String


{-| Elm-land mirror of `CustomNavigationTab` -- `target`/`icon` are always present (unlike the
proto's own `Maybe`-wrapped `oneof`s), since `fromProtoTab` already filters out anything missing
either. `title` stays `Maybe String`, same meaning as the proto's own field ("defaults to the
predefined tab's/Post's title if unset" -- see `resolvedTitle`). `path` is admin-editable (see
`CustomTabsConfiguration.customTabEditChip`'s own Path `<input>`) and is what `Pages.UsernameOrCustomTab_`
actually matches a request's url segment against (`customTabFor`) -- see `navLinkView`'s own doc.
-}
type alias CustomTab =
    { target : CustomTabTarget
    , icon : CustomTabIcon
    , title : Maybe String
    , path : String
    }


fromProtoTarget : ProtoTarget.Target NavigationTab String Bool -> CustomTabTarget
fromProtoTarget target =
    case target of
        ProtoTarget.Tab navTab ->
            TargetTab navTab

        ProtoTarget.PostId postId ->
            TargetPost postId

        -- The payload itself is ignored -- selecting this `oneof` branch at all is what means
        -- "this is a profile tab" (see `CustomTabTarget`'s own doc); there's no reason this
        -- would ever actually be saved as `false`.
        ProtoTarget.IsProfile _ ->
            TargetProfile


toProtoTarget : CustomTabTarget -> ProtoTarget.Target NavigationTab String Bool
toProtoTarget target =
    case target of
        TargetTab navTab ->
            ProtoTarget.Tab navTab

        TargetPost postId ->
            ProtoTarget.PostId postId

        TargetProfile ->
            ProtoTarget.IsProfile True


fromProtoIcon : ProtoIcon.Icon String String -> CustomTabIcon
fromProtoIcon icon =
    case icon of
        ProtoIcon.EmojiIcon emoji ->
            EmojiIcon emoji

        ProtoIcon.IconMediaId mediaId ->
            MediaIcon mediaId


toProtoIcon : CustomTabIcon -> ProtoIcon.Icon String String
toProtoIcon icon =
    case icon of
        EmojiIcon emoji ->
            ProtoIcon.EmojiIcon emoji

        MediaIcon mediaId ->
            ProtoIcon.IconMediaId mediaId


fromProtoTab : CustomNavigationTab -> Maybe CustomTab
fromProtoTab proto =
    Maybe.map2
        (\target icon -> { target = fromProtoTarget target, icon = fromProtoIcon icon, title = proto.title, path = proto.path })
        proto.target
        proto.icon


toProtoTab : CustomTab -> CustomNavigationTab
toProtoTab tab =
    { target = Just (toProtoTarget tab.target)
    , icon = Just (toProtoIcon tab.icon)
    , title = tab.title
    , path = tab.path
    }


{-| Elm-land mirror of `CustomHomePage` -- `target` resolves down to a `CustomTabTarget` the same
way a regular `CustomTab.target` does (`homeConfig`'s own doc covers the `TargetProfile`-can't-
happen distinction), and the four `*EventsStrip*`-ish fields carry straight across unchanged.
Always a concrete record (never `Maybe`), same reasoning as `CustomTab` itself: `homeConfig` already
resolves an unset `customTabs`/`home` down to `defaultHomePageConfig`.
-}
type alias HomePageConfig =
    { target : CustomTabTarget
    , pinnedPostIds : List String
    , showEventsStrip : Bool
    , defaultEventsStripToRow : Bool
    , defaultEventsStripCalendarDisplayMode : CalendarDisplayMode
    }


{-| The all-default `HomePageConfig` -- `TargetTab HOMETAB` (the ordinary combined Events+Posts
feed), no pinned posts, no events strip override. `homeConfig`'s own fallback for an unset
`customTabs`/`home`, and `toProtoHomeConfig`'s own "nothing to save" check.
-}
defaultHomePageConfig : HomePageConfig
defaultHomePageConfig =
    { target = TargetTab HOMETAB
    , pinnedPostIds = []
    , showEventsStrip = False
    , defaultEventsStripToRow = False
    , defaultEventsStripCalendarDisplayMode = CALENDARDISPLAYWEEK
    }


{-| Every `CalendarDisplayMode` `CustomTabsConfiguration.homeEditChip`'s own "Default Events Strip
Calendar Display Mode" `<select>` offers -- mirrors `SettingsTab.allCalendarDisplayModes`'
identical list (kept here too, rather than exposed from `SettingsTab`, so this module doesn't need
to reach into a sibling editor just for an enum's own UI labels).
-}
allCalendarDisplayModes : List CalendarDisplayMode
allCalendarDisplayModes =
    [ CALENDARDISPLAYWEEK, CALENDARDISPLAYMONTH, CALENDARDISPLAYDAY ]


{-| Short UI labels for `CalendarDisplayMode` -- mirrors `SettingsTab.calendarDisplayModeText`
exactly (see that function's own doc for why "Week"/"Month"/"Day" rather than the enum's own verbose
protobuf names).
-}
calendarDisplayModeText : CalendarDisplayMode -> String
calendarDisplayModeText mode =
    case mode of
        CALENDARDISPLAYWEEK ->
            "Week"

        CALENDARDISPLAYMONTH ->
            "Month"

        CALENDARDISPLAYDAY ->
            "Day"

        CalendarDisplayModeUnrecognized_ _ ->
            "Week"


calendarDisplayModeFromText : String -> Maybe CalendarDisplayMode
calendarDisplayModeFromText text =
    allCalendarDisplayModes |> List.filter (\mode -> calendarDisplayModeText mode == text) |> List.head


fromProtoHomeTarget : ProtoHomeTarget.Target NavigationTab String -> CustomTabTarget
fromProtoHomeTarget target =
    case target of
        ProtoHomeTarget.Tab navTab ->
            TargetTab navTab

        ProtoHomeTarget.PostId postId ->
            TargetPost postId


{-| `fromProtoHomeTarget`'s inverse -- `Nothing` for `TargetTab HOMETAB` (the default, matching
`CustomHomePage.target`'s own unset-means-Home convention) and, since `CustomHomePage.target`'s
`oneof` has no `IsProfile`-equivalent branch to construct at all, also for `TargetProfile` (a
malformed/hand-edited config, or `homeConfig`'s own decode fallback landing back here on
`toProtoHomeConfig` -- either way, "no representable override" collapses to the same "no override"
`Home_.elm` already treats an unset `target` as, same as `TargetTab HOMETAB` itself). Never actually
reached for `TargetProfile` in practice -- `CustomTabsConfiguration.homeTargetSelect` only ever
offers `selectableHomeTargetKinds`, which excludes it.
-}
toProtoHomeTarget : CustomTabTarget -> Maybe (ProtoHomeTarget.Target NavigationTab String)
toProtoHomeTarget target =
    case target of
        TargetTab HOMETAB ->
            Nothing

        TargetTab navTab ->
            Just (ProtoHomeTarget.Tab navTab)

        TargetPost postId ->
            Just (ProtoHomeTarget.PostId postId)

        TargetProfile ->
            Nothing


{-| `CustomNavigationTabSet.home`, resolved down to a concrete `HomePageConfig` -- `defaultHomePageConfig`
for either an unset `customTabs`/`home`, or a `home` explicitly saved back to every default value
(the two are indistinguishable, and don't need to be). `home.target`'s own proto doc restricts it to
`HOME_TAB`/`EVENTS_TAB`/`POSTS_TAB` or a `post_id` -- unlike the old `CustomNavigationTab`-typed
`home` this replaces, `CustomHomePage.target`'s `oneof` has no `IsProfile` branch to even construct,
so there's no malformed-`TargetProfile` case left to guard against here (see `toProtoHomeTarget`'s
own doc for the analogous encode-side non-issue). Used by `Pages.Home_` (to render the matching
top-level Events/Posts page or Post instead of the normal combined feed, and to apply the events-strip
overrides above it) and `Components.Pages.PostsPage.customNavPostIds` (to exclude a `TargetPost`
override's own Post, and every `pinnedPostIds` entry, from the generic listing, the same way a
regular `TargetPost` tab's own Post already is).
-}
homeConfig : Maybe CustomNavigationTabSet -> HomePageConfig
homeConfig maybeSet =
    case maybeSet |> Maybe.andThen .home of
        Nothing ->
            defaultHomePageConfig

        Just home ->
            { target = home.target |> Maybe.map fromProtoHomeTarget |> Maybe.withDefault (TargetTab HOMETAB)
            , pinnedPostIds = home.pinnedPostIds
            , showEventsStrip = home.showEventsStrip
            , defaultEventsStripToRow = home.defaultEventsStripToRow
            , defaultEventsStripCalendarDisplayMode = home.defaultEventsStripCalendarDisplayMode
            }


{-| `homeConfig`'s inverse -- `Nothing` (the default, unset `home`) when every field is still
`defaultHomePageConfig`'s own value, otherwise a `CustomHomePage` carrying all four fields straight
across (not just `target`, unlike the old `toProtoHome` this replaces -- e.g. `pinnedPostIds` set
while `target` is still the default `TargetTab HOMETAB` must still round-trip, not get silently
dropped). `CustomTabsConfiguration.applyCustomTabs` is the only caller.
-}
toProtoHomeConfig : HomePageConfig -> Maybe CustomHomePage
toProtoHomeConfig config =
    if config == defaultHomePageConfig then
        Nothing

    else
        Just
            { target = toProtoHomeTarget config.target
            , pinnedPostIds = config.pinnedPostIds
            , showEventsStrip = config.showEventsStrip
            , defaultEventsStripToRow = config.defaultEventsStripToRow
            , defaultEventsStripCalendarDisplayMode = config.defaultEventsStripCalendarDisplayMode
            }


{-| The four tabs Rellm shows today (`Events`/`Posts`/`People`/`About`, see `UI.eventsLink`/etc.)
recast as `CustomTab`s -- both `effectiveTabs`' fallback for an unset `CustomNavigationTabSet.tabs`,
and `SettingsTab`'s starting point for a freshly-opened editor. Each one's `path` is just
`defaultPathFor`'s own slug for its `target` -- see that function's own doc.
-}
defaultTabs : List CustomTab
defaultTabs =
    [ { target = TargetTab EVENTSTAB, icon = EmojiIcon "📅", title = Nothing, path = defaultPathFor (TargetTab EVENTSTAB) }
    , { target = TargetTab POSTSTAB, icon = EmojiIcon "📝", title = Nothing, path = defaultPathFor (TargetTab POSTSTAB) }
    , { target = TargetTab PEOPLETAB, icon = EmojiIcon "👥", title = Nothing, path = defaultPathFor (TargetTab PEOPLETAB) }
    , { target = TargetTab ABOUTTAB, icon = EmojiIcon "i", title = Nothing, path = defaultPathFor (TargetTab ABOUTTAB) }
    ]


{-| A `ServerConfiguration.customTabs`' `tabs` list, or `defaultTabs` if `customTabs` itself is
unset entirely -- an explicitly-saved empty `tabs` list (an admin who's deliberately removed every
tab) is respected as "no tabs," not coerced back to the defaults. Malformed entries (`customTab`
unset, or its own `target`/`icon` unset -- see `fromProtoTab`) are silently skipped.
-}
effectiveTabs : Maybe CustomNavigationTabSet -> List CustomTab
effectiveTabs maybeSet =
    case maybeSet of
        Nothing ->
            defaultTabs

        Just set ->
            set.tabs |> List.filterMap fromProtoTab


{-| `CustomNavigationTabSet.tabStyle`, or `defaultNavigationTabStyle` (icon-only, matching the
proto's own zero value) if `customTabs` itself is unset -- mirrors `effectiveTabs`' identical
unset-means-default fallback. Drives both the real nav (`UI.headerNav`'s own `.nav-links` class,
see `navigationTabStyleClass`) and `CustomTabsConfiguration`'s "Tab Style" picker.
-}
effectiveTabStyle : Maybe CustomNavigationTabSet -> NavigationTabStyle
effectiveTabStyle maybeSet =
    maybeSet |> Maybe.map .tabStyle |> Maybe.withDefault defaultNavigationTabStyle


{-| Every `NavigationTabStyle` `CustomTabsConfiguration`'s "Tab Style" `<select>` offers, in the
order shown there.
-}
allNavigationTabStyles : List NavigationTabStyle
allNavigationTabStyles =
    [ NAVIGATIONTABICONONLY, NAVIGATIONTABTEXTONLY, NAVIGATIONTABICONANDTEXTBELOW, NAVIGATIONTABICONANDTEXTRIGHT ]


{-| A `NavigationTabStyle`'s `<select>` option text/label -- also `CustomTabsConfiguration`'s
read-only display text when no admin edit is in progress.
-}
navigationTabStyleText : NavigationTabStyle -> String
navigationTabStyleText style =
    case style of
        NAVIGATIONTABICONONLY ->
            "Icon Only"

        NAVIGATIONTABTEXTONLY ->
            "Text Only"

        NAVIGATIONTABICONANDTEXTBELOW ->
            "Icon + Text (Below)"

        NAVIGATIONTABICONANDTEXTRIGHT ->
            "Icon + Text (Right)"

        NavigationTabStyleUnrecognized_ _ ->
            "Icon Only"


navigationTabStyleFromText : String -> Maybe NavigationTabStyle
navigationTabStyleFromText text =
    allNavigationTabStyles |> List.filter (\style -> navigationTabStyleText style == text) |> List.head


{-| The class `UI.headerNav` stamps on `.nav-links` for the current `NavigationTabStyle` -- nav.css's
`.tab-style-*` rules key off this to lay each `.nav-link:not(.nav-link-home)` out accordingly (a
`display: none`/`flex-direction` switch on `.nav-link-icon`/`.nav-link-label`, both of which
`navLinkView`/`UI.eventsLink`/etc. always render regardless of style -- see their own docs). No rule
is needed for `NAVIGATIONTABICONONLY` itself: it's `.nav-link`'s existing base look (icon only,
label hidden), so this is purely an additive hook for the other three.
-}
navigationTabStyleClass : NavigationTabStyle -> String
navigationTabStyleClass style =
    case style of
        NAVIGATIONTABICONONLY ->
            "tab-style-icon-only"

        NAVIGATIONTABTEXTONLY ->
            "tab-style-text-only"

        NAVIGATIONTABICONANDTEXTBELOW ->
            "tab-style-icon-and-text-below"

        NAVIGATIONTABICONANDTEXTRIGHT ->
            "tab-style-icon-and-text-right"

        NavigationTabStyleUnrecognized_ _ ->
            "tab-style-icon-only"


navigationTabLabel : NavigationTab -> String
navigationTabLabel navTab =
    case navTab of
        HOMETAB ->
            "Home"

        EVENTSTAB ->
            "Events"

        POSTSTAB ->
            "Posts"

        PEOPLETAB ->
            "People"

        ABOUTTAB ->
            "About"

        MARKETTAB ->
            "Market"

        NavigationTabUnrecognized_ _ ->
            "Tab"


targetLabel : CustomTabTarget -> String
targetLabel target =
    case target of
        TargetTab navTab ->
            navigationTabLabel navTab

        TargetPost _ ->
            "Post"

        TargetProfile ->
            "Profile"


{-| A tab's shown title -- its own `title` if set, otherwise the predefined tab's name (or "Post"
for a Post target, since resolving an actual Post's title would mean an extra fetch this preview/nav
doesn't do -- see this module's own doc). Mirrors the proto field's own doc ("defaults to the
predefined tab's/Post's title if unset").
-}
resolvedTitle : CustomTab -> String
resolvedTitle tab =
    tab.title |> Maybe.withDefault (targetLabel tab.target)


{-| `CustomTab.path`'s starting value for a freshly-added tab (`SettingsTab.CustomTabAddClicked`) or
one of `defaultTabs` -- once a tab exists, its `path` is admin-editable (see `SettingsTab.customTabEditChip`'s
Path `<input>`) and no longer re-derived from this. The backend's own `validate_configuration` (see
`backend/src/rpcs/validations/configuration_validation.rs`) rejects anything that isn't `[a-z_]+` for
every target *except* `TargetProfile` -- notably *not* a real href (no leading `/`, no digits, no
hyphens), which a Post's own id would violate -- so this is just a lowercase, underscore-only
starting slug the admin's expected to customize (e.g. to `gigs` or `weddings`); for `TargetProfile`
it's really a placeholder username instead (see `CustomTabTarget`'s own doc), not actually reachable
from `SettingsTab.CustomTabTargetKindChanged` (which leaves an existing `path` alone across a kind
switch), but still a safe, valid starting value if this is ever called for one directly.
-}
defaultPathFor : CustomTabTarget -> String
defaultPathFor target =
    case target of
        TargetTab navTab ->
            case navTab of
                HOMETAB ->
                    "home"

                EVENTSTAB ->
                    "events"

                POSTSTAB ->
                    "posts"

                PEOPLETAB ->
                    "people"

                ABOUTTAB ->
                    "about"

                MARKETTAB ->
                    "market"

                NavigationTabUnrecognized_ _ ->
                    "home"

        TargetPost _ ->
            "post"

        TargetProfile ->
            "profile"


{-| A `CustomTabTarget`'s kind, ignoring a `TargetPost`'s specific id -- what `SettingsTab`'s "type
of tab" `<select>` actually offers a choice between (see `selectableTargetKinds`), since a `TargetPost`'s
id is its own separate `<input>`, not part of the `<select>`. `KindTab` deliberately never wraps
`HOMETAB` -- that's not a selectable choice for a regular tab (see `selectableTargetKinds`).
-}
type TargetKind
    = KindTab NavigationTab
    | KindPost
    | KindProfile


targetKind : CustomTabTarget -> TargetKind
targetKind target =
    case target of
        TargetTab navTab ->
            KindTab navTab

        TargetPost _ ->
            KindPost

        TargetProfile ->
            KindProfile


{-| A `TargetKind`'s `<select>` option text -- `KindTab`'s own is suffixed "Page" (e.g. "Events
Page," distinct from `navigationTabLabel`'s bare "Events", which is a live, user-facing fallback
title elsewhere -- see `targetLabel`'s own doc) purely to disambiguate, in this settings UI, "the
Events tab itself" from "a tab/Home pointed at the Events page." Shared by both
`SettingsTab.customTabTargetSelect` (regular tabs, `selectableTargetKinds`) and
`SettingsTab.homeTargetSelect` (`selectableHomeTargetKinds`) -- no other rendering path reads this.
-}
targetKindText : TargetKind -> String
targetKindText kind =
    case kind of
        KindTab navTab ->
            case navTab of
                HOMETAB ->
                    "Home Page"

                EVENTSTAB ->
                    "Events Page"

                POSTSTAB ->
                    "Posts Page"

                PEOPLETAB ->
                    "People Page"

                ABOUTTAB ->
                    "About Page"

                MARKETTAB ->
                    "Market Page"

                NavigationTabUnrecognized_ _ ->
                    "Tab"

        KindPost ->
            "Custom Post"

        KindProfile ->
            "Profile"


{-| Every `TargetKind` `SettingsTab`'s "type of tab" `<select>` offers -- the four non-Home
predefined tabs, plus Custom Post and Profile. Mirrors `SettingsTab.allowedDefaultModerations`' own
"the full enum has more values than are actually choosable here" reasoning.
-}
selectableTargetKinds : List TargetKind
selectableTargetKinds =
    [ KindTab EVENTSTAB, KindTab POSTSTAB, KindTab PEOPLETAB, KindTab ABOUTTAB, KindTab MARKETTAB, KindPost, KindProfile ]


targetKindFromText : String -> Maybe TargetKind
targetKindFromText text =
    selectableTargetKinds |> List.filter (\kind -> targetKindText kind == text) |> List.head


{-| Every `TargetKind` `SettingsTab.homeTargetSelect` offers -- unlike `selectableTargetKinds`,
`KindTab HOMETAB` _is_ included here (it's `home`'s own default, "no override" choice, see
`homeConfig`'s own doc), and only `EVENTSTAB`/`POSTSTAB` join it among the predefined tabs --
`home`'s own proto doc doesn't extend to People/About/Profile.
-}
selectableHomeTargetKinds : List TargetKind
selectableHomeTargetKinds =
    [ KindTab HOMETAB, KindTab EVENTSTAB, KindTab POSTSTAB, KindPost ]


homeTargetKindFromText : String -> Maybe TargetKind
homeTargetKindFromText text =
    selectableHomeTargetKinds |> List.filter (\kind -> targetKindText kind == text) |> List.head


{-| A `CustomTabIcon`'s content -- an emoji is wrapped in a `[data-glyph=<emoji>]` `span` (rather
than a bare text node) so CSS can single out specific glyphs for their own treatment without this
module having to know about it -- today that's just `nav.css`'s `[data-glyph="i"]` rule (the same
serif-italic look `UI.aboutLink`'s own hard-coded `.info-button` class gives its "i", for the
default About tab's glyph -- but once a tab's rendered generically through here, whether that's
`ABOUTTAB` isn't available to key off of the way it is there, so this keys off the glyph itself
instead, which is the one thing still true either way). A `MediaIcon` renders an `<img>` resolved
against `server`'s own media (via `RellmServers.mediaUrl`, the same helper the server logo/avatar
pickers use), falling back to a placeholder glyph if that id doesn't resolve to a URL (e.g. a media
item deleted out from under a still-configured tab).
-}
iconView : RellmServer -> CustomTabIcon -> Html msg
iconView server icon =
    case icon of
        EmojiIcon emoji ->
            span [ attribute "data-glyph" emoji ] [ text emoji ]

        MediaIcon mediaId ->
            case RellmServers.mediaUrl server mediaId of
                Just url ->
                    img [ Html.Attributes.class "custom-nav-tab-icon-image", src url, alt "" ] []

                Nothing ->
                    text "🖼️"


{-| One custom tab's actual top-nav link -- same `.nav-link`/`background-color-nav`-when-current
treatment as `UI.eventsLink`/`UI.postsLink`/`UI.peopleLink`/`UI.aboutLink`, just generic over any
`CustomTab` instead of one hard-coded route/glyph each. `server` is whichever server's
`ServerConfiguration` this `CustomTab` came from (always `UI.mainServer shared` for the real nav,
but `SettingsTab`'s preview reuses this for whichever server is being viewed/edited). Generic in
`msg` (no `Shared.Msg`-specific click handling, unlike `UI.navLink`'s own Home link) since a plain
`href` is all routing here needs -- elm-spa's own link interception handles the rest.

Links to `tab.path` itself (via `Route.UsernameOrCustomTab_`), not `tab.target`'s own canonical
route -- `Pages.UsernameOrCustomTab_` is what actually resolves that path back to `target` at
request time (see its own `customTabFor`), so this always matches whatever url a visitor would
land on, e.g. a `path` of `gigs` links to `/gigs`, not `/events`, even though `target` is
`EVENTSTAB`. `isCurrent`, though, checks *both* that path route and `target`'s own canonical one
(`canonicalRoute`) -- the proto's own doc is explicit that `/events`/`/posts/`/`/people`/`/about`
stay reachable and unmodified regardless of any custom path pointed at the same `target`, so a
visitor who lands on plain `/events` (an old link, a bookmark, `Gen.Route.routes`' own static entry)
should still see the "Events" tab (now living at `/gigs`) highlighted as current, not dark. Not
relevant for `TargetPost`/`TargetProfile`, whose only route *is* their own `path` either way.
-}
navLinkView : Shared.Model -> Route -> RellmServer -> CustomTab -> Html msg
navLinkView shared currentRoute server tab =
    let
        route : Route
        route =
            Route.UsernameOrCustomTab_ { usernameOrCustomTab = tab.path }

        canonicalRoute : Route
        canonicalRoute =
            case tab.target of
                TargetTab HOMETAB ->
                    Route.Home_

                TargetTab EVENTSTAB ->
                    Route.Events

                TargetTab POSTSTAB ->
                    Route.Posts

                TargetTab PEOPLETAB ->
                    Route.People

                TargetTab ABOUTTAB ->
                    Route.About

                TargetTab MARKETTAB ->
                    Route.Market

                TargetTab (NavigationTabUnrecognized_ _) ->
                    route

                TargetPost postId ->
                    Route.Post__PostId_ { postId = postId }

                TargetProfile ->
                    route

        isCurrent : Bool
        isCurrent =
            currentRoute == route || currentRoute == canonicalRoute
    in
    a
        [ href (shared.basePath ++ Route.toHref route)
        , classes
            ("nav-link"
                :: (if isCurrent then
                        [ hostnameToCSSClass shared.accounts.mainFrontendHost, "background-color-nav" ]

                    else
                        []
                   )
            )
        , title (resolvedTitle tab)
        ]
        [ span [ class "nav-link-icon" ] [ iconView server tab.icon ]
        , span [ class "nav-link-label" ] [ text (resolvedTitle tab) ]
        ]
