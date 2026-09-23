module Pages.UsernameOrCustomTab_ exposing (Model, Msg, fromShared, page)

{-| `/:usernameOrCustomTab[@host]` -- a user profile looked up by (impermanent) username, a short
Post/Event URL, or a custom tab, on `mainFrontendHost` or (with an `@host` suffix, username lookups
only) some other federated server. Three checks run in order:

1.  A check against `mainFrontendHost`'s own `ServerConfiguration.customTabs.tabs` (see
    `UI.CustomNav`) for a tab whose own `path` matches this segment -- letting an admin mount
    `Events`/`Posts`/`People`/`About`/a specific `Post` at a custom URL (e.g. a band's `/weddings`
    pointing at a Post about their wedding offerings), per `CustomNavigationTab.path`'s own doc
    (`customTabFor`). A configured custom path always wins over a same-named user or short URL.
2.  If no custom tab matched, and the segment starts with a character no username/custom tab path
    could ever legally start with (`Components.Users.startsWithReservedShortUrlCharacter`), it's
    tried as a short Post/Event URL instead (`Components.Pages.PostOrEventPage`) -- see
    `rellm.proto`'s own `### /[-._~:/?[]@!$&'()*+,;%=]{postId}: Short Post/Event URLs` routing
    doc. Unlike `customTabFor`, this check is a pure string test with no async server config to wait
    on, so it's decided once at `init` and never needs re-checking.
3.  Otherwise, the ordinary username fallback below.

The top-level catch-all this implies means any username (or un-embeddable custom path) colliding
with this app's own routes (or the `/user`/`/post` prefixes) can never be reached this way -- see
`Components.Users.isReservedUsername`, checked here before `Components.UserProfilePage` (which does
the actual fetching/rendering, same as `Pages.User.UserId_`) is ever involved. Those usernames are
still reachable via `/user/:id[@host]`. Note `/events`/`/posts/`/`/people`/`/about` themselves are
never actually reachable _as_ a custom path either way -- `Gen.Route.routes`' own `Parser.oneOf`
tries those literal static routes first, so this file's `init` never even runs for them.

-}

import Browser.Navigation
import Components.Pages.BlueskyUserProfilePage as BlueskyUserProfilePage
import Components.Pages.EventsPage as EventsPage
import Components.Pages.MarketPage as MarketPage
import Components.Pages.MastodonUserProfilePage as MastodonUserProfilePage
import Components.Pages.PostOrEventPage as PostOrEventPage
import Components.Pages.PostPage as PostPage
import Components.Pages.PostsPage as PostsPage
import Components.Pages.ServerInformationPage as ServerInformationPage
import Components.Pages.UserProfilePage as UserProfilePage
import Components.Pages.UsersPage as UsersPage
import Components.Users as Users
import Components.Users.Resolver as Resolver
import Effect exposing (Effect)
import Gen.Params.UsernameOrCustomTab_ exposing (Params)
import Gen.Route as Route exposing (Route)
import Html exposing (p, text)
import Html.Attributes exposing (class)
import Page
import Proto.Rellm.NavigationTab exposing (NavigationTab(..))
import Request
import Shared
import Shared.AccountsPanel.RellmServers as RellmServers
import UI
import UI.CustomNav as CustomNav
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared req
        , update = update shared req
        , view = view shared req
        , subscriptions = subscriptions
        }


{-| `Reserved` short-circuits straight to a "not a user" message, without ever constructing a
`UserProfilePage.Model` (and thus without ever attempting a fetch) -- see the module doc.
`Embedded*` mount whichever `Components.Pages.*` a matched custom tab's `target` calls for, exactly
the same components `Pages.Events`/`Pages.Posts`/`Pages.People`/`Pages.About`/`Pages.Market`/
`Pages.Post.PostId_` themselves wrap -- see `initEmbedded`, and that module's own doc for why a `Post` target is
genuinely indistinguishable from visiting `/post/:id` directly (down to the same `Components.Pages.PostPage`
being mounted either way). `EmbeddedProfile` is `TargetProfile`'s own -- deliberately a _separate_
variant from the plain-username-fallback `Profile` below even though both just wrap a
`UserProfilePage.Model`: `update`'s `SharedMsg` handling for `Reserved`/`Profile` re-checks
`customTabFor` on every incoming message (see its own doc, for the "config wasn't loaded yet at
init" race), and once a tab's actually matched that re-check would keep matching forever, restarting
`UserProfilePage.init` (and thus its fetch) on every single `Shared.Msg` -- an infinite reinit loop,
not just a wasted re-check. Keeping `EmbeddedProfile` a distinct variant routes it through the same
plain "forward via `fromShared`, don't re-examine" handling every other `Embedded*` already gets.
`Redirecting` covers `HOMETAB` alone (not normally reachable from the admin editor -- see
`UI.CustomNav.selectableTargetKinds`' own doc -- but not excluded at the type level either): unlike
the other five, `Pages.Home_`'s Events+Posts composite isn't factored into a separately-reusable
`Components.Pages.*` module (it's a deliberately-duplicated composite, per its own doc), so
redirecting to `/` gets a visitor to the right content without duplicating it wholesale just for
this. `Redirecting` renders nothing itself, since its own `Effect` fires a real navigation in `init`
that replaces this page before `view` would otherwise matter.
-}
type Model
    = Reserved String
    | Profile UserProfilePage.Model
    | MastodonProfile MastodonUserProfilePage.Model
    | BlueskyProfile BlueskyUserProfilePage.Model
    | EmbeddedEvents EventsPage.Model
    | EmbeddedPosts PostsPage.Model
    | EmbeddedPeople UsersPage.Model
    | EmbeddedAbout ServerInformationPage.Model
    | EmbeddedMarket MarketPage.Model
    | EmbeddedPost PostPage.Model
    | EmbeddedProfile UserProfilePage.Model
    | EmbeddedPostOrEvent PostOrEventPage.Model
    | Redirecting


{-| `SharedMsg` (rather than always wrapping a forwarded `Shared.Msg` as, say, `ProfileMsg`) exists
because `fromShared` (below) has no way to know which `Embedded*`/`Profile` variant is actually
active when it's called -- `elm-spa`'s own `fromShared : Shared.Msg -> Msg` signature is model-blind
by design. Routing on the _current_ `model` instead happens in `update`'s own `SharedMsg` branches,
each re-dispatching via that embedded module's own `fromShared`, mirroring `Pages.Home_.update`'s
identical reasoning for forwarding one incoming `Shared.Msg` to more than one possible destination.
-}
type Msg
    = ProfileMsg UserProfilePage.Msg
    | MastodonProfileMsg MastodonUserProfilePage.Msg
    | BlueskyProfileMsg BlueskyUserProfilePage.Msg
    | EventsMsg EventsPage.Msg
    | PostsMsg PostsPage.Msg
    | PeopleMsg UsersPage.Msg
    | AboutMsg ServerInformationPage.Msg
    | MarketMsg MarketPage.Msg
    | EmbeddedPostMsg PostPage.Msg
    | EmbeddedProfileMsg UserProfilePage.Msg
    | EmbeddedPostOrEventMsg PostOrEventPage.Msg
    | SharedMsg Shared.Msg


init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    case customTabFor shared req.params.usernameOrCustomTab of
        Just tab ->
            initEmbedded shared req tab

        Nothing ->
            if Users.startsWithReservedShortUrlCharacter req.params.usernameOrCustomTab then
                PostOrEventPage.init shared (RellmServers.isSecure req) req.params.usernameOrCustomTab req.key
                    |> Tuple.mapFirst EmbeddedPostOrEvent
                    |> Tuple.mapSecond (Effect.map EmbeddedPostOrEventMsg)

            else
                initProfile shared req


{-| `mainFrontendHost`'s own `CustomNavigationTabSet.tabs` entry (if any, and if that server's
`ServerConfiguration` is even known yet) whose `path` matches `path` exactly -- deliberately built
off `CustomNav.effectiveTabs (Just customTabs)`, not `RellmServers.configurationOf server |> .customTabs
|> CustomNav.effectiveTabs` directly, so an _unset_ `customTabs` (the common case) never falls back to
`CustomNav.defaultTabs`' own paths here -- those are harmless if matched (see the module doc on why
they're unreachable anyway), but "no config" should mean "no custom routing," not "pretend the
defaults were explicitly configured."
-}
customTabFor : Shared.Model -> String -> Maybe CustomNav.CustomTab
customTabFor shared path =
    RellmServers.rellmServerForHost shared.accounts.servers shared.accounts.mainFrontendHost
        |> Maybe.andThen (\server -> (RellmServers.configurationOf server).customTabs)
        |> Maybe.andThen (\customTabs -> CustomNav.effectiveTabs (Just customTabs) |> List.filter (\tab -> tab.path == path) |> List.head)


{-| Mounts whichever page a matched custom tab's `target` calls for. `EVENTSTAB`/`POSTSTAB`/`PEOPLETAB`/
`ABOUTTAB`/`MARKETTAB` embed inline (each call mirrors `Pages.Events`/`Pages.Posts`/`Pages.People`/
`Pages.About`/`Pages.Market`'s own `init` exactly, just wrapped in this module's `Embedded*` instead
of their own bare `Model`), so
the custom path itself stays in the address bar with that page's content rendered at it -- the actual
point of a vanity URL. `TargetPost` mounts `Components.Pages.PostPage` exactly the same way
`Pages.Post.PostId_` itself does, so e.g. a band's `/weddings` renders indistinguishably from
`/post/:id` for the Post it's configured to point at -- same fetch, same edit/reply/delete/moderation
UI, same everything, just a friendlier url. `TargetProfile` mounts the same `Components.Pages.UserProfilePage`
the ordinary username fallback does, just as its own `EmbeddedProfile` (see `Model`'s own doc on why
that's a distinct variant, not just `Profile` again) -- the only real difference is where the
username comes from (`tab.path` instead of the route segment itself), since `UI.CustomNav.CustomTabTarget`'s
own doc explains a profile tab's url _is_ that user's own `/:username` route either way. `HOMETAB`
instead redirects to `/` (see `Model`'s own doc on why that one's not embedded the same way). A
malformed/future `NavigationTabUnrecognized_` target falls back to the ordinary username lookup,
same as if this path hadn't matched a tab at all.
-}
initEmbedded : Shared.Model -> Request.With Params -> CustomNav.CustomTab -> ( Model, Effect Msg )
initEmbedded shared req tab =
    case tab.target of
        CustomNav.TargetTab EVENTSTAB ->
            EventsPage.init shared Nothing req.key req.url.path req.query req.url.fragment False True Nothing Nothing False
                |> Tuple.mapFirst EmbeddedEvents
                |> Tuple.mapSecond (Effect.map EventsMsg)

        CustomNav.TargetTab POSTSTAB ->
            PostsPage.init shared Nothing req.key req.url.path req.query False Nothing Nothing
                |> Tuple.mapFirst EmbeddedPosts
                |> Tuple.mapSecond (Effect.map PostsMsg)

        CustomNav.TargetTab PEOPLETAB ->
            UsersPage.init shared Nothing Nothing req.key req.url.path req.query
                |> Tuple.mapFirst EmbeddedPeople
                |> Tuple.mapSecond (Effect.map PeopleMsg)

        CustomNav.TargetTab ABOUTTAB ->
            ServerInformationPage.init shared (RellmServers.isSecure req) shared.accounts.mainFrontendHost req.key req.url.path req.query
                |> Tuple.mapFirst EmbeddedAbout
                |> Tuple.mapSecond (Effect.map AboutMsg)

        CustomNav.TargetTab MARKETTAB ->
            MarketPage.init shared shared.accounts.browsingHost
                |> Tuple.mapFirst EmbeddedMarket
                |> Tuple.mapSecond (Effect.map MarketMsg)

        CustomNav.TargetTab HOMETAB ->
            ( Redirecting, redirectTo req.key Route.Home_ )

        CustomNav.TargetTab (NavigationTabUnrecognized_ _) ->
            initProfile shared req

        CustomNav.TargetPost postId ->
            PostPage.init shared (RellmServers.isSecure req) postId req.key
                |> Tuple.mapFirst EmbeddedPost
                |> Tuple.mapSecond (Effect.map EmbeddedPostMsg)

        CustomNav.TargetProfile ->
            let
                ( username, targetHost ) =
                    Users.parseUserRouteId shared.accounts.mainFrontendHost tab.path
            in
            UserProfilePage.init shared (RellmServers.isSecure req) targetHost (Resolver.ByUsername username) req.key req.url.path req.query req.url.fragment
                |> Tuple.mapFirst EmbeddedProfile
                |> Tuple.mapSecond (Effect.map EmbeddedProfileMsg)


{-| `replaceUrl`, not `pushUrl` -- a vanity path like `/gigs` should read as if `/events` were the
url all along, so the back button (from wherever the redirect lands) skips over it rather than
bouncing back into another redirect.
-}
redirectTo : Browser.Navigation.Key -> Route -> Effect Msg
redirectTo key route =
    Browser.Navigation.replaceUrl key (Route.toHref route) |> Effect.fromCmd


initProfile : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
initProfile shared req =
    let
        ( username, targetHost ) =
            Users.parseUserRouteId shared.accounts.mainFrontendHost req.params.usernameOrCustomTab
    in
    case Users.parseFederatedUserId username targetHost of
        Just (Users.MastodonUserId mastodonUser) ->
            MastodonUserProfilePage.init mastodonUser.instanceHost mastodonUser.username req.key req.url.path req.query
                |> Tuple.mapFirst MastodonProfile
                |> Tuple.mapSecond (Effect.map MastodonProfileMsg)

        Just (Users.BlueskyUserId { handle }) ->
            BlueskyUserProfilePage.init shared handle req.key req.url.path req.query
                |> Tuple.mapFirst BlueskyProfile
                |> Tuple.mapSecond (Effect.map BlueskyProfileMsg)

        Nothing ->
            if Users.isReservedUsername username then
                ( Reserved username
                , Effect.none
                )

            else
                UserProfilePage.init shared (RellmServers.isSecure req) targetHost (Resolver.ByUsername username) req.key req.url.path req.query req.url.fragment
                    |> Tuple.mapFirst Profile
                    |> Tuple.mapSecond (Effect.map ProfileMsg)


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Profile subModel ->
            Sub.map ProfileMsg (UserProfilePage.subscriptions subModel)

        MastodonProfile subModel ->
            Sub.map MastodonProfileMsg (MastodonUserProfilePage.subscriptions subModel)

        BlueskyProfile subModel ->
            Sub.map BlueskyProfileMsg (BlueskyUserProfilePage.subscriptions subModel)

        EmbeddedEvents subModel ->
            Sub.map EventsMsg (EventsPage.subscriptions subModel)

        EmbeddedPosts subModel ->
            Sub.map PostsMsg (PostsPage.subscriptions subModel)

        EmbeddedPeople subModel ->
            Sub.map PeopleMsg (UsersPage.subscriptions subModel)

        EmbeddedAbout subModel ->
            Sub.map AboutMsg (ServerInformationPage.subscriptions subModel)

        EmbeddedMarket subModel ->
            Sub.map MarketMsg (MarketPage.subscriptions subModel)

        EmbeddedPost subModel ->
            Sub.map EmbeddedPostMsg (PostPage.subscriptions subModel)

        EmbeddedProfile subModel ->
            Sub.map EmbeddedProfileMsg (UserProfilePage.subscriptions subModel)

        EmbeddedPostOrEvent subModel ->
            Sub.map EmbeddedPostOrEventMsg (PostOrEventPage.subscriptions subModel)

        Reserved _ ->
            Sub.none

        Redirecting ->
            Sub.none


update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case ( msg, model ) of
        ( ProfileMsg subMsg, Profile subModel ) ->
            UserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst Profile
                |> Tuple.mapSecond (Effect.map ProfileMsg)

        ( MastodonProfileMsg subMsg, MastodonProfile subModel ) ->
            MastodonUserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst MastodonProfile
                |> Tuple.mapSecond (Effect.map MastodonProfileMsg)

        ( BlueskyProfileMsg subMsg, BlueskyProfile subModel ) ->
            BlueskyUserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst BlueskyProfile
                |> Tuple.mapSecond (Effect.map BlueskyProfileMsg)

        ( EventsMsg subMsg, EmbeddedEvents subModel ) ->
            EventsPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedEvents
                |> Tuple.mapSecond (Effect.map EventsMsg)

        ( PostsMsg subMsg, EmbeddedPosts subModel ) ->
            PostsPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedPosts
                |> Tuple.mapSecond (Effect.map PostsMsg)

        ( PeopleMsg subMsg, EmbeddedPeople subModel ) ->
            UsersPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedPeople
                |> Tuple.mapSecond (Effect.map PeopleMsg)

        ( AboutMsg subMsg, EmbeddedAbout subModel ) ->
            ServerInformationPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedAbout
                |> Tuple.mapSecond (Effect.map AboutMsg)

        ( MarketMsg subMsg, EmbeddedMarket subModel ) ->
            MarketPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedMarket
                |> Tuple.mapSecond (Effect.map MarketMsg)

        ( EmbeddedPostMsg subMsg, EmbeddedPost subModel ) ->
            PostPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedPost
                |> Tuple.mapSecond (Effect.map EmbeddedPostMsg)

        ( EmbeddedProfileMsg subMsg, EmbeddedProfile subModel ) ->
            UserProfilePage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedProfile
                |> Tuple.mapSecond (Effect.map EmbeddedProfileMsg)

        ( EmbeddedPostOrEventMsg subMsg, EmbeddedPostOrEvent subModel ) ->
            PostOrEventPage.update shared subMsg subModel
                |> Tuple.mapFirst EmbeddedPostOrEvent
                |> Tuple.mapSecond (Effect.map EmbeddedPostOrEventMsg)

        -- `Reserved`/`Profile` are re-examined (via `customTabFor`) on every incoming
        -- `Shared.Msg` first -- covers `init` having run before `mainFrontendHost`'s own
        -- `ServerConfiguration.customTabs` was known yet (the common case on a fresh
        -- load/reload of a custom-tab path: that server hasn't finished connecting when this
        -- page's `init` first runs, so `customTabFor` sees no config and falls through to
        -- `initProfile`, same as an actual unknown user would). Once a match is found this way,
        -- it wins outright -- whatever `Profile` fetch was in flight is simply abandoned.
        ( SharedMsg _, Reserved username ) ->
            case customTabFor shared req.params.usernameOrCustomTab of
                Just tab ->
                    initEmbedded shared req tab

                Nothing ->
                    ( Reserved username, Effect.none )

        -- See `Msg`'s own doc -- routes one incoming `Shared.Msg` to whichever
        -- embedded module is actually live right now, re-entering through that
        -- module's own `fromShared` (same as if `Main` had called it directly).
        ( SharedMsg subMsg, Profile subModel ) ->
            case customTabFor shared req.params.usernameOrCustomTab of
                Just tab ->
                    initEmbedded shared req tab

                Nothing ->
                    UserProfilePage.update shared (UserProfilePage.fromShared subMsg) subModel
                        |> Tuple.mapFirst Profile
                        |> Tuple.mapSecond (Effect.map ProfileMsg)

        -- `MastodonProfile`/`BlueskyProfile` don't need the same `customTabFor` re-check `Profile`
        -- does: `Users.parseFederatedUserId` is a pure function of the route's own params (unlike
        -- `customTabFor`, which depends on server config that might not have loaded yet at `init`),
        -- so its result can never change over this page's lifetime -- just forward straight into
        -- the resolved page's own `fromShared`.
        ( SharedMsg subMsg, MastodonProfile subModel ) ->
            MastodonUserProfilePage.update shared (MastodonUserProfilePage.fromShared subMsg) subModel
                |> Tuple.mapFirst MastodonProfile
                |> Tuple.mapSecond (Effect.map MastodonProfileMsg)

        ( SharedMsg subMsg, BlueskyProfile subModel ) ->
            BlueskyUserProfilePage.update shared (BlueskyUserProfilePage.fromShared subMsg) subModel
                |> Tuple.mapFirst BlueskyProfile
                |> Tuple.mapSecond (Effect.map BlueskyProfileMsg)

        ( SharedMsg subMsg, EmbeddedEvents subModel ) ->
            EventsPage.update shared (EventsPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedEvents
                |> Tuple.mapSecond (Effect.map EventsMsg)

        ( SharedMsg subMsg, EmbeddedPosts subModel ) ->
            PostsPage.update shared (PostsPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedPosts
                |> Tuple.mapSecond (Effect.map PostsMsg)

        ( SharedMsg subMsg, EmbeddedPeople subModel ) ->
            UsersPage.update shared (UsersPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedPeople
                |> Tuple.mapSecond (Effect.map PeopleMsg)

        ( SharedMsg subMsg, EmbeddedAbout subModel ) ->
            ServerInformationPage.update shared (ServerInformationPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedAbout
                |> Tuple.mapSecond (Effect.map AboutMsg)

        ( SharedMsg subMsg, EmbeddedMarket subModel ) ->
            MarketPage.update shared (MarketPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedMarket
                |> Tuple.mapSecond (Effect.map MarketMsg)

        ( SharedMsg subMsg, EmbeddedPost subModel ) ->
            PostPage.update shared (PostPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedPost
                |> Tuple.mapSecond (Effect.map EmbeddedPostMsg)

        ( SharedMsg subMsg, EmbeddedProfile subModel ) ->
            UserProfilePage.update shared (UserProfilePage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedProfile
                |> Tuple.mapSecond (Effect.map EmbeddedProfileMsg)

        ( SharedMsg subMsg, EmbeddedPostOrEvent subModel ) ->
            PostOrEventPage.update shared (PostOrEventPage.fromShared subMsg) subModel
                |> Tuple.mapFirst EmbeddedPostOrEvent
                |> Tuple.mapSecond (Effect.map EmbeddedPostOrEventMsg)

        _ ->
            ( model, Effect.none )


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared (titleFor shared req model)
    , body =
        UI.layout shared
            req.route
            fromShared
            [ case model of
                Profile subModel ->
                    Html.map ProfileMsg (UserProfilePage.view shared subModel)

                MastodonProfile subModel ->
                    Html.map MastodonProfileMsg (MastodonUserProfilePage.view shared subModel)

                BlueskyProfile subModel ->
                    Html.map BlueskyProfileMsg (BlueskyUserProfilePage.view shared subModel)

                EmbeddedEvents subModel ->
                    Html.map EventsMsg (EventsPage.view shared True subModel)

                EmbeddedPosts subModel ->
                    Html.map PostsMsg (PostsPage.view shared True True subModel)

                EmbeddedPeople subModel ->
                    Html.map PeopleMsg (UsersPage.view shared subModel)

                EmbeddedAbout subModel ->
                    Html.map AboutMsg (ServerInformationPage.view shared subModel)

                EmbeddedMarket subModel ->
                    Html.map MarketMsg (MarketPage.view shared True subModel)

                EmbeddedPost subModel ->
                    Html.map EmbeddedPostMsg (PostPage.view shared subModel)

                EmbeddedProfile subModel ->
                    Html.map EmbeddedProfileMsg (UserProfilePage.view shared subModel)

                EmbeddedPostOrEvent subModel ->
                    Html.map EmbeddedPostOrEventMsg (PostOrEventPage.view shared subModel)

                Reserved username ->
                    p [ class "profile-error" ] [ text ("\"" ++ username ++ "\" isn't a user.") ]

                Redirecting ->
                    text ""
            ]
    }


{-| A matched custom tab's own `title` (see `CustomNavigationTab.title`'s proto doc, "defaults to
the predefined tab's/Post's title if unset") wins over every one of `model`'s own default titles
below, including a fetched Post's real title -- so e.g. a `/see_us_live` tab titled "See Us Live"
reads as "See Us Live | <server name>" instead of "Events | <server name>", matching the nav
tooltip `CustomNav.resolvedTitle` already shows for the same tab.
-}
titleFor : Shared.Model -> Request.With Params -> Model -> List String
titleFor shared req model =
    case customTabFor shared req.params.usernameOrCustomTab |> Maybe.andThen .title of
        Just title ->
            [ title ]

        Nothing ->
            case model of
                Profile subModel ->
                    [ UserProfilePage.titleFor subModel ]

                MastodonProfile subModel ->
                    [ MastodonUserProfilePage.title subModel ]

                BlueskyProfile subModel ->
                    [ BlueskyUserProfilePage.title subModel ]

                EmbeddedEvents _ ->
                    []

                EmbeddedPosts _ ->
                    [ "Posts" ]

                EmbeddedPeople _ ->
                    [ "People" ]

                EmbeddedAbout _ ->
                    [ "About" ]

                EmbeddedMarket _ ->
                    [ "Market" ]

                EmbeddedPost subModel ->
                    [ PostPage.titleFor subModel ]

                EmbeddedProfile subModel ->
                    [ UserProfilePage.titleFor subModel ]

                EmbeddedPostOrEvent subModel ->
                    [ PostOrEventPage.titleFor subModel ]

                Reserved _ ->
                    [ "Not Found" ]

                Redirecting ->
                    []


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page -- see `Msg`'s own doc
on why this always wraps as `SharedMsg` rather than picking one embedded module's wrapper up front.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg
