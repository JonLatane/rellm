module Pages.Home_ exposing (Model, Msg, fromShared, page)

{-| `/` -- upcoming events plus recent posts from every enabled server (the `Feed` variant), unless
`mainFrontendHost`'s own `ServerConfiguration.customTabs.home` overrides Home (`UI.CustomNav.homeConfig`,
whose `target` is restricted to `HOME_TAB`/`EVENTS_TAB`/`POSTS_TAB` or a bare `post_id` -- see that
field's own proto doc), in which case this instead renders: a top-level `Components.Pages.EventsPage`
(`HomeEvents`, target `EVENTS_TAB`) or `Components.Pages.PostsPage` (`HomePosts`, target `POSTS_TAB`)
-- exactly `Pages.Events`/`Pages.Posts` themselves render, not `Feed`'s own compact embedded copies
(see those two variants' own docs) -- or a specific Post (`HomePost`, target a `post_id`), exactly
the way `Pages.UsernameOrCustomTab_.EmbeddedPost` renders a regular custom tab's own `TargetPost`
(same `Components.Pages.PostPage`, same fetch, same edit/reply/delete/moderation UI). When a
`post_id` target also has `show_events_strip` set, `HomePostWithEvents` instead pairs that same Post
with an `EventsPage` strip above it (mirroring `Feed`'s own Events-strip-above-feed shape, just over
a single fixed Post instead of `PostsPage`'s own listing) -- its own `EventsPage` copy passes
`embeddedPage = True` (same as `Feed`'s, for the same compact, non-interactive "Upcoming Events"
heading/layout -- see `EventsPage.tabsView`'s own doc) but `embeddingPageSearchesPosts = False`
(unlike `Feed`'s), so its search box reads "Search events…" rather than "Search posts and events…":
there's no Posts search happening alongside it, just the one fixed Post. `home`'s
`default_events_strip_to_row`/`default_events_strip_calendar_display_mode` govern this strip's own
initial layout/calendar-granularity defaults exactly the same way they govern `Feed`'s own strip --
see `withEventsStripDisplayOverride`/`eventsStripCalendarDisplayModeOverride`.

`Feed` is a thin wrapper around `Components.Pages.EventsPage`/`Components.Pages.PostsPage`, which do
all the actual work -- mirrors `Pages.User.UserId_`/`Pages.UsernameOrCustomTab_.Posts`' own use of
`PostsPage` for the posts half, except this page adds its own "Recent Posts"/"Recent Replies"
heading (see `heading`, which tracks `PostsPage`'s own POST/REPLY context chooser), renders an
`EventsPage` above that (defaulted to `HorizontalList` mode -- via `EventsPage.init`'s own
`embeddedPage = True` argument, passed below -- rather than `EventsPage.init`'s ordinary
`VerticalList` default, so the home page's events read as a single row rather than competing with
the posts feed below for vertical space; `model.embeddedPage` also hides its List/Grid/Row mode
buttons entirely -- see `EventsPage.modeButtonsView`'s own doc for the full visibility rules,
including the "Show all event layouts" admin override), and passes `authorUserId = Nothing`/
`author = Nothing` to both (an unfiltered feed, rather than one user's own posts/events).

Both `PostsPage.init`/`EventsPage.init` are also passed `embeddedPage = True`
above, which keeps each from independently asserting its own
`Shared.Breadcrumbs` root on every `update` (see their own
`setBreadcrumbsRoot` docs) -- this page owns that instead, unlike the other
`PostsPage`/`EventsPage` callers, which each own their own page's root
directly. See `setBreadcrumbsHost` for why: two embedded copies each
asserting a root of their own turned out to fight a third, actually-different
root on `Components.Pages.UserProfilePage` (which embeds the same two
modules), a continuous flicker during animation. `HomeEvents`/`HomePosts`/`HomePost`/`HomePostWithEvents`
all instead leave breadcrumbs alone entirely: `HomeEvents`/`HomePosts` pass `embeddedPage = False`
(own their own root the same as `Pages.Events`/`Pages.Posts` do); `PostPage.init`/`.update` (`HomePost`,
and `HomePostWithEvents`' own `.post`) own their own breadcrumb root already, the same as
`Pages.Post.PostId_`/`Pages.UsernameOrCustomTab_.EmbeddedPost` -- so `HomePostWithEvents`' own
`.events` copy passes `embeddedPage = True` precisely so it *doesn't* also assert a root of its own
alongside `.post`'s (the same flicker this whole scheme exists to avoid, just between two halves of
one `Model` instead of two top-level pages). `setBreadcrumbsHost` only ever fires for `Feed` (see
`setBreadcrumbsEffect`).

There's only one visible search box in `Feed` (`EventsPage`'s -- `PostsPage.view`
is called with `showSearchRow = False`, hiding its own box and POST/REPLY
chooser entirely, since a second, independent search box for the same page
would be redundant/confusing). Typing in it still filters _both_ feeds: see
`updateInner`'s `PostsMsg`/`EventsMsg` branches, which relay a changed
`searchText` into the other page's model via
`PostsPage.searchTextChanged`/`EventsPage.searchTextChanged` -- each side
keeps its own independent debounce timer (see those modules' own
`SearchTextChanged`/`SearchDebounceElapsed`), so this doesn't add any new
debounce logic here, it just keeps both `model.posts.searchText`/
`model.events.searchText` in sync going forward. The `PostsMsg` half of that
relay is effectively unreachable with the box hidden, but is kept for
robustness/symmetry (e.g. a future `?search_text=` URL param divergence).

`home.pinnedPostIds` sits above all five variants above, rendered by `Components.PinnedPosts`
(`model.pinnedPosts`) regardless of `home.target` -- pinned posts are an overlay, not a target, so
they show the same way whether Home is the ordinary `Feed`, a full `HomeEvents`/`HomePosts` tab, or a
fixed `HomePost`/`HomePostWithEvents`. Unlike `content` (the five-variant union below, entirely
replaced whenever `home.target` newly resolves to something else -- see `initForTarget`'s own doc),
`model.pinnedPosts` is a single, independent `Model` that's only ever reconciled in place
(`PinnedPosts.syncIds`, on every incoming `SharedMsg` -- same trigger, and the same "config might
still be arriving" reasoning, as `content`'s own `homeConfigFor` recheck), never rebuilt from
scratch.

-}

import Components.MediaRenderer as MediaRenderer
import Components.PinnedPosts as PinnedPosts
import Components.Pages.EventsPage as EventsPage
import Components.Pages.PostPage as PostPage
import Components.Pages.PostsPage as PostsPage
import Dict exposing (Dict)
import Effect exposing (Effect)
import Gen.Params.Home_ exposing (Params)
import Html exposing (Html, div, h3, text)
import Html.Attributes exposing (class)
import Page
import Proto.Rellm.CalendarDisplayMode exposing (CalendarDisplayMode)
import Proto.Rellm.NavigationTab exposing (NavigationTab(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Request
import Shared
import Shared.AccountsPanel.RellmAccounts as RellmAccounts
import Shared.AccountsPanel.RellmServers as RellmServers
import Shared.Breadcrumbs as Breadcrumbs
import Shared.MediaViewerPanel as MediaViewerPanel
import Shared.StarredPanel as StarredPanel
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


{-| `pinnedPosts` (see the module doc) is independent of, and rendered above, `content` -- the actual
`home.target`-driven page below it, one of five variants. `Feed` is the ordinary Events+Posts
composite (see the module doc); `HomeEvents`/`HomePosts`/`HomePost`/`HomePostWithEvents` are distinct
variants (not, say, folded into `Feed` as a `Maybe`) for the same reason
`Pages.UsernameOrCustomTab_.EmbeddedProfile` is kept separate from its own `Profile` -- once
`updateInner`'s `SharedMsg` handling (below) has matched a `home` override and switched away from
`Feed`, it must stop re-deriving `homeConfigFor` on every subsequent `Shared.Msg`, or a still-live
`EventsPage`/`PostsPage`/`PostPage.Model` would be discarded and re-`init`ed (re-fetching) on every
single message.
-}
type alias Model =
    { pinnedPosts : PinnedPosts.Model
    , content : Content
    }


type Content
    = Feed FeedModel
    | HomeEvents EventsPage.Model
    | HomePosts PostsPage.Model
    | HomePost PostPage.Model
    | HomePostWithEvents PostWithEventsModel


type alias FeedModel =
    { posts : PostsPage.Model
    , events : EventsPage.Model
    }


{-| `HomePostWithEvents`' own pair -- a fixed `home.target`'s `TargetPost` alongside an Events strip
above it (`home.showEventsStrip`, see the module doc). Mirrors `FeedModel`'s shape, just over
`PostPage` instead of `PostsPage`.
-}
type alias PostWithEventsModel =
    { events : EventsPage.Model
    , post : PostPage.Model
    }


type Msg
    = PostsMsg PostsPage.Msg
    | EventsMsg EventsPage.Msg
    | HomeEventsMsg EventsPage.Msg
    | HomePostsMsg PostsPage.Msg
    | HomePostMsg PostPage.Msg
    | HomePostEventsMsg EventsPage.Msg
    | PinnedPostsMsg PinnedPosts.Msg
    | SharedMsg Shared.Msg
      -- `Posts.postCard`'s/`Events.eventCard`'s own `onPush`/`onDelete` for a pinned post -- always
      -- unreachable (see `pinnedPostsConfig`'s own doc), same convention as `Shared.StarredPanel.NoOp`.
    | NoOp


{-| Builds both halves of `Model` -- `pinnedPosts` (from `home.pinnedPostIds`, see the module doc) and
`content` (from `home.target`, see `initForTarget`) -- off one shared `home` read, so they can't
observe two different (e.g. mid-load-then-arrived) copies of `mainFrontendHost`'s config on the very
first render.
-}
init : Shared.Model -> Request.With Params -> ( Model, Effect Msg )
init shared req =
    let
        home : CustomNav.HomePageConfig
        home =
            homeConfigFor shared

        ( content, contentEffect ) =
            case initForTarget shared req home of
                Just result ->
                    result

                Nothing ->
                    initFeed shared req home

        ( pinnedPosts, pinnedEffect ) =
            PinnedPosts.init shared home.pinnedPostIds
    in
    ( { pinnedPosts = pinnedPosts, content = content }
    , Effect.batch [ contentEffect, Effect.map PinnedPostsMsg pinnedEffect ]
    )


initFeed : Shared.Model -> Request.With Params -> CustomNav.HomePageConfig -> ( Content, Effect Msg )
initFeed shared req home =
    let
        ( postsModel, postsEffect ) =
            PostsPage.init shared Nothing req.key req.url.path req.query True Nothing Nothing

        ( eventsModel, eventsEffect ) =
            EventsPage.init shared
                Nothing
                req.key
                req.url.path
                (withEventsStripDisplayOverride home req.query)
                req.url.fragment
                True
                True
                Nothing
                (eventsStripCalendarDisplayModeOverride home)
                True
    in
    ( Feed { posts = postsModel, events = eventsModel }
    , Effect.batch [ Effect.map PostsMsg postsEffect, Effect.map EventsMsg eventsEffect, setBreadcrumbsHost shared, Effect.fromShared Shared.UncollapseHome ]
    )


{-| `home`'s own non-default init, if it has one -- `Nothing` for `TargetTab HOMETAB` (and any other
value `homeConfigFor` shouldn't ever actually produce, e.g. a stray `TargetProfile`), meaning "fall
back to `initFeed`." Factored out of `init` so `updateInner`'s `SharedMsg`/`Feed` branch (which
re-checks `homeConfigFor` on every incoming `Shared.Msg`, see `homeConfigFor`'s own doc) can reuse
the exact same switch without duplicating it. `TargetPost`'s own `home.showEventsStrip` picks between
the plain `HomePost` and the paired `HomePostWithEvents` (see the module doc) -- `home.pinnedPostIds`
isn't read here at all, since it isn't a *target* to render, just an overlay `PostsPage`/`Feed`'s own
generic listing already excludes via `PostsPage.customNavPostIds` (not relevant for a `TargetPost`/
`TargetTab EVENTSTAB`/`TargetTab POSTSTAB` home either way, none of which show that listing).
-}
initForTarget : Shared.Model -> Request.With Params -> CustomNav.HomePageConfig -> Maybe ( Content, Effect Msg )
initForTarget shared req home =
    case home.target of
        CustomNav.TargetTab EVENTSTAB ->
            EventsPage.init shared Nothing req.key req.url.path req.query req.url.fragment False True Nothing Nothing False
                |> Tuple.mapFirst HomeEvents
                |> Tuple.mapSecond (Effect.map HomeEventsMsg)
                |> Just

        CustomNav.TargetTab POSTSTAB ->
            PostsPage.init shared Nothing req.key req.url.path req.query False Nothing Nothing
                |> Tuple.mapFirst HomePosts
                |> Tuple.mapSecond (Effect.map HomePostsMsg)
                |> Just

        CustomNav.TargetPost postId ->
            if home.showEventsStrip then
                let
                    ( eventsModel, eventsEffect ) =
                        EventsPage.init shared
                            Nothing
                            req.key
                            req.url.path
                            (withEventsStripDisplayOverride home req.query)
                            req.url.fragment
                            True
                            False
                            Nothing
                            (eventsStripCalendarDisplayModeOverride home)
                            False

                    ( postModel, postEffect ) =
                        PostPage.init shared (RellmServers.isSecure req) postId req.key
                in
                Just
                    ( HomePostWithEvents { events = eventsModel, post = postModel }
                    , Effect.batch [ Effect.map HomePostEventsMsg eventsEffect, Effect.map HomePostMsg postEffect ]
                    )

            else
                PostPage.init shared (RellmServers.isSecure req) postId req.key
                    |> Tuple.mapFirst HomePost
                    |> Tuple.mapSecond (Effect.map HomePostMsg)
                    |> Just

        _ ->
            Nothing


{-| `mainFrontendHost`'s own `customTabs.home` override, resolved via `UI.CustomNav.homeConfig` --
that function's own `Nothing`/unset-config fallback to `defaultHomePageConfig` covers both "no
override configured" and "`mainFrontendHost`'s `ServerConfiguration` hasn't loaded yet" identically
(see `Pages.UsernameOrCustomTab_.customTabFor`'s identical reasoning for why that's the right
fallback, not an error), which is exactly why `init` alone isn't enough: `updateInner`'s `SharedMsg`
handling re-checks this on every incoming `Shared.Msg` while still in `Feed`, so a `home` override
that arrives moments after `init` (the common case for a first visit, before `mainFrontendHost`'s
config has finished connecting) still takes effect.
-}
homeConfigFor : Shared.Model -> CustomNav.HomePageConfig
homeConfigFor shared =
    RellmServers.rellmServerForHost shared.accounts.servers shared.accounts.mainFrontendHost
        |> Maybe.andThen (\server -> (RellmServers.configurationOf server).customTabs)
        |> CustomNav.homeConfig


{-| Seeds an Events strip's initial row-vs-calendar layout from `home.defaultEventsStripToRow`, via
the same `?display=row`/`?display=calendar` mechanism `EventsPage.init` already gives top priority
to (see its own `displayModeFromParam` handling) -- reused here rather than teaching `EventsPage` a
second, parallel override, and consistent with an actual incoming `?display=` link (checked first,
and left untouched) being the more specific request. Left alone entirely -- not even checking
`defaultEventsStripToRow` -- when `home` is still `CustomNav.defaultHomePageConfig` (nothing
configured), so an ordinary, unconfigured server keeps exactly today's behavior: `EventsPage`'s own
`embeddedPage` fallback to `HorizontalList` (`Feed`'s strip) rather than silently starting to default
to `Calendar` (this field's own unset-value meaning) the moment *any* unrelated `home` field gets
configured.
-}
withEventsStripDisplayOverride : CustomNav.HomePageConfig -> Dict String String -> Dict String String
withEventsStripDisplayOverride home query =
    if home == CustomNav.defaultHomePageConfig || Dict.member "display" query then
        query

    else
        Dict.insert "display"
            (if home.defaultEventsStripToRow then
                "row"

             else
                "calendar"
            )
            query


{-| `EventsPage.init`'s own `calendarDisplayModeOverride` argument for an Events strip governed by
`home` -- `Just home.defaultEventsStripCalendarDisplayMode` once *any* `home` field is configured
(see `withEventsStripDisplayOverride`'s own doc for why that's the right threshold, not just
`showEventsStrip`/a non-default `target`), `Nothing` (defer to the server-wide
`EventSettings.default_calendar_display_mode`, `EventsPage.calendarDisplayMode`'s own default) for a
wholly unconfigured `home`.
-}
eventsStripCalendarDisplayModeOverride : CustomNav.HomePageConfig -> Maybe CalendarDisplayMode
eventsStripCalendarDisplayModeOverride home =
    if home == CustomNav.defaultHomePageConfig then
        Nothing

    else
        Just home.defaultEventsStripCalendarDisplayMode


{-| `pinnedPosts` needs no subscriptions of its own -- no polling/animations, see the module doc for
`Components.PinnedPosts`. -}
subscriptions : Model -> Sub Msg
subscriptions model =
    contentSubscriptions model.content


contentSubscriptions : Content -> Sub Msg
contentSubscriptions content =
    case content of
        Feed feed ->
            Sub.batch
                [ Sub.map PostsMsg (PostsPage.subscriptions feed.posts)
                , Sub.map EventsMsg (EventsPage.subscriptions feed.events)
                ]

        HomeEvents subModel ->
            Sub.map HomeEventsMsg (EventsPage.subscriptions subModel)

        HomePosts subModel ->
            Sub.map HomePostsMsg (PostsPage.subscriptions subModel)

        HomePost subModel ->
            Sub.map HomePostMsg (PostPage.subscriptions subModel)

        HomePostWithEvents subModel ->
            Sub.batch
                [ Sub.map HomePostEventsMsg (EventsPage.subscriptions subModel.events)
                , Sub.map HomePostMsg (PostPage.subscriptions subModel.post)
                ]


{-| Handles `PinnedPostsMsg`/`NoOp` directly (neither touches `content`), then delegates everything
else to `updateInner` for `model.content` -- also re-syncing `model.pinnedPosts` against a freshly
re-read `home.pinnedPostIds` on every `SharedMsg`, the same trigger (and "config might still be
arriving" reasoning) `updateInner`'s own `SharedMsg`/`Feed` branch already uses to recheck
`home.target`. Finishes by reissuing `setBreadcrumbsEffect` after every `content` update -- mirrors
`Components.Pages.UserProfilePage.update`'s identical wrapper.
-}
update : Shared.Model -> Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update shared req msg model =
    case msg of
        PinnedPostsMsg subMsg ->
            let
                ( newPinnedPosts, effect ) =
                    PinnedPosts.update shared subMsg model.pinnedPosts
            in
            ( { model | pinnedPosts = newPinnedPosts }, Effect.map PinnedPostsMsg effect )

        NoOp ->
            ( model, Effect.none )

        _ ->
            let
                ( newContent, contentEffect ) =
                    updateInner shared req msg model.content

                ( newPinnedPosts, pinnedEffect ) =
                    case msg of
                        SharedMsg _ ->
                            PinnedPosts.syncIds shared (homeConfigFor shared).pinnedPostIds model.pinnedPosts

                        _ ->
                            ( model.pinnedPosts, Effect.none )
            in
            ( { model | content = newContent, pinnedPosts = newPinnedPosts }
            , Effect.batch [ contentEffect, Effect.map PinnedPostsMsg pinnedEffect, setBreadcrumbsEffect shared newContent ]
            )


updateInner : Shared.Model -> Request.With Params -> Msg -> Content -> ( Content, Effect Msg )
updateInner shared req msg content =
    case ( msg, content ) of
        ( PostsMsg subMsg, Feed feed ) ->
            let
                ( newPosts, postsEffect ) =
                    PostsPage.update shared subMsg feed.posts

                ( syncedEvents, syncEffect ) =
                    if newPosts.searchText /= feed.events.searchText then
                        EventsPage.update shared (EventsPage.searchTextChanged newPosts.searchText) feed.events

                    else
                        ( feed.events, Effect.none )
            in
            ( Feed { feed | posts = newPosts, events = syncedEvents }
            , Effect.batch [ Effect.map PostsMsg postsEffect, Effect.map EventsMsg syncEffect ]
            )

        ( EventsMsg subMsg, Feed feed ) ->
            let
                ( newEvents, eventsEffect ) =
                    EventsPage.update shared subMsg feed.events

                ( syncedPosts, syncEffect ) =
                    if newEvents.searchText /= feed.posts.searchText then
                        PostsPage.update shared (PostsPage.searchTextChanged newEvents.searchText) feed.posts

                    else
                        ( feed.posts, Effect.none )
            in
            ( Feed { feed | events = newEvents, posts = syncedPosts }
            , Effect.batch [ Effect.map EventsMsg eventsEffect, Effect.map PostsMsg syncEffect ]
            )

        ( HomeEventsMsg subMsg, HomeEvents subModel ) ->
            EventsPage.update shared subMsg subModel
                |> Tuple.mapFirst HomeEvents
                |> Tuple.mapSecond (Effect.map HomeEventsMsg)

        ( HomePostsMsg subMsg, HomePosts subModel ) ->
            PostsPage.update shared subMsg subModel
                |> Tuple.mapFirst HomePosts
                |> Tuple.mapSecond (Effect.map HomePostsMsg)

        ( HomePostMsg subMsg, HomePost subModel ) ->
            PostPage.update shared subMsg subModel
                |> Tuple.mapFirst HomePost
                |> Tuple.mapSecond (Effect.map HomePostMsg)

        ( HomePostEventsMsg subMsg, HomePostWithEvents subModel ) ->
            EventsPage.update shared subMsg subModel.events
                |> Tuple.mapFirst (\newEvents -> HomePostWithEvents { subModel | events = newEvents })
                |> Tuple.mapSecond (Effect.map HomePostEventsMsg)

        ( HomePostMsg subMsg, HomePostWithEvents subModel ) ->
            PostPage.update shared subMsg subModel.post
                |> Tuple.mapFirst (\newPost -> HomePostWithEvents { subModel | post = newPost })
                |> Tuple.mapSecond (Effect.map HomePostMsg)

        -- Re-checked (via `homeConfigFor`) on every incoming `Shared.Msg` while still in `Feed` --
        -- covers `init` having run before `mainFrontendHost`'s own `ServerConfiguration.customTabs`
        -- was known yet (see `homeConfigFor`'s own doc). Once matched, this switches straight to
        -- the matching fresh variant (abandoning whatever `Feed` fetches were in flight, same as
        -- `Pages.UsernameOrCustomTab_`'s identical `Profile` handling) rather than forwarding
        -- `subMsg` into it.
        ( SharedMsg subMsg, Feed feed ) ->
            case initForTarget shared req (homeConfigFor shared) of
                Just result ->
                    result

                Nothing ->
                    let
                        ( newPosts, postsEffect ) =
                            PostsPage.update shared (PostsPage.fromShared subMsg) feed.posts

                        ( newEvents, eventsEffectRaw ) =
                            EventsPage.update shared (EventsPage.fromShared subMsg) feed.events

                        -- `PostsPage.update`/`EventsPage.update`'s own `SharedMsg`
                        -- branches each unconditionally re-emit `Effect.fromShared
                        -- subMsg` (see their own docs) -- that's what actually
                        -- applies an incoming `Shared.Msg` (e.g. toggling the
                        -- Accounts Panel or Starred panel, both built with
                        -- `Shared.Msg` in `UI.layout`'s header and only reaching
                        -- either page via `fromShared`) back to `Shared.update`,
                        -- correct when only one feed is handling it. Both would fire
                        -- it here, for the exact same `subMsg` -- `Effect.partitionShared`
                        -- (in `Main.elm`) would then apply it to `Shared.update`
                        -- *twice* in the same pass. Harmless for an idempotent
                        -- message, but for a toggle that flips it on then right back
                        -- off again -- net zero, every time, which is exactly the
                        -- "can't open the Accounts/Starred panel" bug this
                        -- fixes. `postsEffect` is kept as the one copy that actually
                        -- re-broadcasts `subMsg`; `eventsEffectRaw`'s own copy is
                        -- dropped via `Effect.partitionShared` (keeping its other
                        -- effects, e.g. `fetchNewServers`'s own fetch, intact).
                        ( _, eventsEffect ) =
                            Effect.partitionShared eventsEffectRaw
                    in
                    ( Feed { feed | posts = newPosts, events = newEvents }
                    , Effect.batch [ Effect.map PostsMsg postsEffect, Effect.map EventsMsg eventsEffect ]
                    )

        ( SharedMsg subMsg, HomeEvents subModel ) ->
            EventsPage.update shared (EventsPage.fromShared subMsg) subModel
                |> Tuple.mapFirst HomeEvents
                |> Tuple.mapSecond (Effect.map HomeEventsMsg)

        ( SharedMsg subMsg, HomePosts subModel ) ->
            PostsPage.update shared (PostsPage.fromShared subMsg) subModel
                |> Tuple.mapFirst HomePosts
                |> Tuple.mapSecond (Effect.map HomePostsMsg)

        ( SharedMsg subMsg, HomePost subModel ) ->
            PostPage.update shared (PostPage.fromShared subMsg) subModel
                |> Tuple.mapFirst HomePost
                |> Tuple.mapSecond (Effect.map HomePostMsg)

        -- Same `Effect.partitionShared` dedup as the `Feed` branch above (`PostPage.update`'s own
        -- `SharedMsg` handling re-broadcasts `subMsg` unconditionally too, same as `PostsPage`'s) --
        -- `postEffect` is kept as the one copy that actually re-broadcasts it.
        ( SharedMsg subMsg, HomePostWithEvents subModel ) ->
            let
                ( newPost, postEffect ) =
                    PostPage.update shared (PostPage.fromShared subMsg) subModel.post

                ( newEvents, eventsEffectRaw ) =
                    EventsPage.update shared (EventsPage.fromShared subMsg) subModel.events

                ( _, eventsEffect ) =
                    Effect.partitionShared eventsEffectRaw
            in
            ( HomePostWithEvents { events = newEvents, post = newPost }
            , Effect.batch [ Effect.map HomePostMsg postEffect, Effect.map HomePostEventsMsg eventsEffect ]
            )

        _ ->
            ( content, Effect.none )


{-| Keeps `Shared.Breadcrumbs` pointed at `mainFrontendHost`, but only for `Feed` -- this feed isn't
scoped to any one server for a breadcrumb trail to identify the way a Post's own reply chain is.
The one owner of `Shared.Breadcrumbs` for `Feed`: the embedded `PostsPage`/`EventsPage` copies above
both leave breadcrumbs alone entirely (`model.embeddedPage`, see their own `setBreadcrumbsRoot`
docs) rather than each independently asserting a root of its own -- `Components.Pages.UserProfilePage`
embeds the same two modules the same way, and used to let each of them (plus its own
`setBreadcrumbsHost`) independently assert a root on every `update`, including every animation tick;
whichever root won only lasted until the next tick reasserted the other, a continuous flicker
between them. `HomeEvents`/`HomePosts`/`HomePost`/`HomePostWithEvents` are all left alone entirely --
the former two own their own breadcrumb root the same as `Pages.Events`/`Pages.Posts` (`embeddedPage
= False`), and `PostPage.init`/`.update` (the latter two, `HomePostWithEvents`' own `.post` included)
already own theirs, the same as `Pages.Post.PostId_`/`Pages.UsernameOrCustomTab_.EmbeddedPost`.
-}
setBreadcrumbsEffect : Shared.Model -> Content -> Effect Msg
setBreadcrumbsEffect shared content =
    case content of
        Feed _ ->
            setBreadcrumbsHost shared

        HomeEvents _ ->
            Effect.none

        HomePosts _ ->
            Effect.none

        HomePost _ ->
            Effect.none

        HomePostWithEvents _ ->
            Effect.none


setBreadcrumbsHost : Shared.Model -> Effect Msg
setBreadcrumbsHost shared =
    let
        host : String
        host =
            shared.accounts.mainFrontendHost
    in
    if shared.breadcrumbs.root == Just (Breadcrumbs.FromServerHost host) then
        Effect.none

    else
        Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost host) host []))


view : Shared.Model -> Request.With Params -> Model -> View Msg
view shared req model =
    { title = UI.pageTitle shared (titleFor model.content)
    , body =
        UI.layout shared
            req.route
            fromShared
            (pinnedPostsView shared model.pinnedPosts :: contentView shared model.content)
    }


contentView : Shared.Model -> Content -> List (Html Msg)
contentView shared content =
    case content of
        Feed feed ->
            [ Html.map EventsMsg (EventsPage.view shared True feed.events)
            , div [ class "posts-embedded-heading-row" ]
                [ h3 [] [ text (heading feed.posts.context) ]
                , Html.map PostsMsg (PostsPage.exportButtonView shared feed.posts)
                ]
            , Html.map PostsMsg (PostsPage.view shared False True feed.posts)
            ]

        HomeEvents subModel ->
            [ Html.map HomeEventsMsg (EventsPage.view shared True subModel) ]

        HomePosts subModel ->
            [ Html.map HomePostsMsg (PostsPage.view shared True True subModel) ]

        HomePost subModel ->
            [ Html.map HomePostMsg (PostPage.view shared subModel) ]

        HomePostWithEvents subModel ->
            [ Html.map HomePostEventsMsg (EventsPage.view shared True subModel.events)
            , Html.map HomePostMsg (PostPage.view shared subModel.post)
            ]


{-| Builds `Components.PinnedPosts.view`'s config off `shared` -- every field mirrors the same
closures `Components.Pages.PostsPage.postCardView` already builds for its own feed's post cards (star
toggling/media-viewer opening routed through `Shared.StarredPanelMsg`/`Shared.MediaViewerPanelMsg`,
`StarredPanel.freshestPost` overlaid so a just-toggled star's count shows immediately) -- so a pinned
post behaves identically to any other post card in the app. `pinnedPostIds` is always on
`mainFrontendHost` (see the module doc for `Components.PinnedPosts`), so every field below is looked
up against that one host.
-}
pinnedPostsView : Shared.Model -> PinnedPosts.Model -> Html Msg
pinnedPostsView shared pinnedPosts =
    let
        host : String
        host =
            shared.accounts.mainFrontendHost
    in
    PinnedPosts.view
        { time = shared.time
        , basePath = shared.basePath
        , viewingServerHost = host
        , maybeServer = RellmServers.rellmServerForHost shared.accounts.servers host
        , maybeAccount = RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts host
        , isStarred = \post -> StarredPanel.isStarred host post shared.panels.starredPanel
        , onStarClicked = \post -> StarredPanel.toggleStarMsg shared.accounts host post |> Maybe.map (Shared.StarredPanelMsg >> SharedMsg)
        , onMediaClicked = \post mediaId -> SharedMsg (Shared.MediaViewerPanelMsg (MediaViewerPanel.Open post.media (Just post) mediaId host))
        , mediaPlayState = shared.mediaRenderer
        , onMediaPlayClicked = \mediaId -> SharedMsg (Shared.MediaRendererMsg (MediaRenderer.PlayClicked mediaId))
        , freshenPost = \post -> StarredPanel.freshestPost host post shared.panels.starredPanel
        , noOp = NoOp
        , toMsg = PinnedPostsMsg
        }
        pinnedPosts


{-| `Feed` has no title of its own (matching this page's pre-existing behavior); `HomeEvents` mirrors
`Pages.Events`' own (none -- its own "Upcoming Events"/"Events After <date>" tabs already say what
the listing is); `HomePosts` mirrors `Pages.Posts`' own ("Posts"); `HomePost`/`HomePostWithEvents`
use the featured Post's own title, same as `Pages.Post.PostId_`/`Pages.UsernameOrCustomTab_.titleFor`'s
`EmbeddedPost` case. Pinned posts never contribute a title -- they're an overlay above whichever of
these actually renders, not something a page title should describe.
-}
titleFor : Content -> List String
titleFor content =
    case content of
        Feed _ ->
            []

        HomeEvents _ ->
            []

        HomePosts _ ->
            [ "Posts" ]

        HomePost subModel ->
            [ PostPage.titleFor subModel ]

        HomePostWithEvents subModel ->
            [ PostPage.titleFor subModel.post ]


{-| "Recent Posts"/"Recent Replies", matching `model.context` -- always "Recent Posts" in
practice here, since `PostsPage.view`'s `showSearchRow = False` above hides the only control
(`PostsPage.searchRowView`'s POST/REPLY chooser) that could ever change `model.posts.context`
away from its `POST` default.
-}
heading : PostContext -> String
heading context =
    case context of
        REPLY ->
            "Recent Replies"

        _ ->
            "Recent Posts"


{-| Lets `Main` forward a `Shared.Msg` that didn't originate from this page --
see `Components.Pages.PostsPage.fromShared`/`Components.Pages.EventsPage.fromShared`,
both of which `SharedMsg` forwards to above.
-}
fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsg
