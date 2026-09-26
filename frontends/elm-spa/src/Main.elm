module Main exposing (main)

{-| Customized from `elm-spa`'s generated default (see `.elm-spa/defaults/Main.elm`,
which this was copied from and now overrides -- `.elm-spa/` itself is
gitignored/regenerated, so this is the only place changes here persist).

Four changes from the default:

1.  This app can be served from `/` or from `/elm` (see
    `backend/src/web/elm_web.rs`), so every `Url` gotten from the browser is
    normalized (`Shared.normalizeUrl`) before it's handed to
    `Gen.Route.fromUrl`/`Request.create`/`Pages.init`, stripping that mount's
    `basePath` so routing always sees an app-relative path. `basePath` itself is
    detected once, from the very first `Url` (immutable for the session, same as
    `Shared.AccountsPanel`'s `browsingHost`), and threaded into `Shared.init` so
    view code (`UI.navLink`) can prepend it back onto outgoing hrefs.

2.  `Page pageMsg` applies any `Shared.Msg`s a page's `update` forwarded (via
    `Effect.fromShared`) to `Shared.update` immediately, in this same call --
    see `Effect.partitionShared`. The default routes them through `Effect.toCmd`
    instead, which defers them to a `Task.perform` on a later `update`/`view`
    cycle; that's invisible for most effects, but the Accounts Panel's login form
    lives in `Shared.Model` (it's shown from every page's header, via
    `UI.layout`), so every keystroke is a `Shared.Msg` forwarded this way. The
    deferred version meant `view` ran once per keystroke with the stale
    pre-keystroke model -- snapping a mid-edit cursor to the end of the old text
    -- and then again with the correct model, snapping it again.

3.  `Shared sharedMsg` (a top-level `Shared.Msg`, e.g. `GotReconnectResult`
    firing from a `Cmd` kicked off in `Shared.init`) additionally forwards that
    same message into the currently active page via `notifyPageOfSharedMsg`, for
    pages that expose a `fromShared` hook (see `Pages.Home_`, `Pages.Post.PostId_`).
    The default only ever routes messages page -> shared (via `Page pageMsg`,
    change 2 above); without this, a page has no way to notice state that changes
    outside of its own `update` -- e.g. a persisted server finishing its
    reconnect at startup -- short of polling for it.

4.  `ChangedUrl` fires `Shared.ShowScrollPreserver` (see `UI.scrollPreserver`)
    when, and only when, the navigation was the browser's own back button rather
    than an in-app link click, redirect, or typed/bookmarked url -- those always
    land on a fresh page starting at scroll top, but stepping back restores the
    browser's remembered scroll offset against a page whose content may still be
    loading (and so shorter than it was when that offset was recorded), which
    would otherwise visibly yank the scroll position while it fills back in. Elm
    has no built-in way to ask "was this `ChangedUrl` a back-button nav", so
    `Model.backStack` shadows the browser's own back-stack by hand: every
    `ClickedLink (Browser.Internal url)` pushes the url being left onto it, and
    `ChangedUrl` treats landing back on its top entry as a back-nav (popping it),
    leaving any other url change untouched.

5.  `ChangedUrl` special-cases one path change: `Pages.Event.PostId_` clicking
    from one `Occasion` to a sibling one of the very same `Event` (see
    `occasionSwitchMsg`). The default always reruns the newly-matched page's own
    `init` on any path change at all, which for that transition meant a visible
    full clear-and-reload plus a redundant `GetEvents` fetch for data the page
    had already loaded (every one of an `Event`'s `Occasion`s comes back in a
    single fetch -- see `Components.Pages.EventPage`'s own module doc). Detected
    generically (old and new routes both `Route.Event__PostId_`, whatever
    `postId` each carries) rather than by comparing full urls, since the whole
    point is that the `postId` segment differs.

-}

import Browser
import Browser.Navigation as Nav exposing (Key)
import Effect
import Gen.Model
import Gen.Msg
import Gen.Pages as Pages
import Gen.Route as Route
import Html exposing (Html)
import Html.Attributes
import Pages.About
import Pages.Event.PostId_
import Pages.Events
import Pages.Home_
import Pages.Market
import Pages.Market.Fulfillment
import Pages.Market.Product.ProductId_
import Pages.Messages
import Pages.People
import Pages.Post.PostId_
import Pages.Posts
import Pages.Server.ServerIdentifier_
import Pages.User.UserId_
import Pages.User.UserId_.Events
import Pages.User.UserId_.Followers
import Pages.User.UserId_.Following
import Pages.User.UserId_.Friends
import Pages.User.UserId_.Posts
import Pages.UsernameOrCustomTab_
import Pages.UsernameOrCustomTab_.Events
import Pages.UsernameOrCustomTab_.Followers
import Pages.UsernameOrCustomTab_.Following
import Pages.UsernameOrCustomTab_.Friends
import Pages.UsernameOrCustomTab_.Posts
import Request
import Shared
import Url exposing (Url)
import View


main : Program Shared.Flags Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlChange = ChangedUrl
        , onUrlRequest = ClickedLink
        }


type alias Model =
    { url : Url
    , key : Key
    , shared : Shared.Model
    , page : Pages.Model

    -- Detected once from the raw URL `init` was given -- see the module doc.
    , basePath : String

    -- Urls navigated away from via an in-app link click, most-recently-left
    -- first -- see change 4 in the module doc.
    , backStack : List Url
    }


type Msg
    = ChangedUrl Url
    | ClickedLink Browser.UrlRequest
    | Shared Shared.Msg
    | Page Pages.Msg



-- INIT


init : Shared.Flags -> Url -> Key -> ( Model, Cmd Msg )
init flags url key =
    let
        basePath : String
        basePath =
            Shared.basePathFromPath url.path

        normalizedUrl : Url
        normalizedUrl =
            Shared.normalizeUrl basePath url

        ( shared, sharedCmd ) =
            Shared.init basePath (Request.create () normalizedUrl key) flags

        ( page, effect ) =
            Pages.init (Route.fromUrl normalizedUrl) shared normalizedUrl key
    in
    ( Model normalizedUrl key shared page basePath []
    , Cmd.batch
        [ Cmd.map Shared sharedCmd
        , Effect.toCmd ( Shared, Page ) effect
        ]
    )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Pages.subscriptions model.page model.shared model.url model.key |> Sub.map Page
        , Shared.subscriptions model.shared |> Sub.map Shared
        ]



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ClickedLink (Browser.Internal url) ->
            ( { model | backStack = model.url :: model.backStack }
            , Nav.pushUrl model.key (Url.toString url)
            )

        ClickedLink (Browser.External url) ->
            ( model
            , Nav.load url
            )

        ChangedUrl rawUrl ->
            let
                url : Url
                url =
                    Shared.normalizeUrl model.basePath rawUrl
            in
            if url.path /= model.url.path then
                case occasionSwitchMsg model.page (Route.fromUrl url) of
                    -- Same page, just a sibling `Occasion`'s own `postId` (see
                    -- `occasionSwitchMsg`'s own doc, change 5 below) -- deliver straight
                    -- into the already-running page via `Pages.update` rather than
                    -- `Pages.init`, so it can reuse the `Event` it's already loaded instead
                    -- of clearing itself and re-fetching. Nothing here needs the
                    -- back-nav/`ShowScrollPreserver` handling below either: unlike a full
                    -- remount, this never clears the page's own content in the first place,
                    -- so there's nothing whose scroll position needs preserving.
                    Just occasionMsg ->
                        let
                            ( page, effect ) =
                                Pages.update occasionMsg model.page model.shared url model.key
                        in
                        ( { model | url = url, page = page }
                        , Effect.toCmd ( Shared, Page ) effect
                        )

                    Nothing ->
                        let
                            ( page, effect ) =
                                Pages.init (Route.fromUrl url) model.shared url model.key

                            isBackNav : Bool
                            isBackNav =
                                List.head model.backStack == Just url

                            backStack : List Url
                            backStack =
                                if isBackNav then
                                    List.drop 1 model.backStack

                                else
                                    model.backStack

                            ( shared, sharedCmd ) =
                                if isBackNav then
                                    Shared.update (Request.create () url model.key) Shared.ShowScrollPreserver model.shared

                                else
                                    ( model.shared, Cmd.none )
                        in
                        ( { model | url = url, page = page, shared = shared, backStack = backStack }
                        , Cmd.batch
                            [ Effect.toCmd ( Shared, Page ) effect
                            , Cmd.map Shared sharedCmd
                            ]
                        )

            else
                ( { model | url = url }, Cmd.none )

        Shared sharedMsg ->
            let
                ( shared, sharedCmd ) =
                    Shared.update (Request.create () model.url model.key) sharedMsg model.shared

                ( redirectPage, redirectEffect ) =
                    Pages.init (Route.fromUrl model.url) shared model.url model.key
            in
            if redirectPage == Gen.Model.Redirecting_ then
                ( { model | shared = shared, page = redirectPage }
                , Cmd.batch
                    [ Cmd.map Shared sharedCmd
                    , Effect.toCmd ( Shared, Page ) redirectEffect
                    ]
                )

            else
                let
                    ( page, notifyCmd ) =
                        notifyPageOfSharedMsg sharedMsg shared model.page model.url model.key
                in
                ( { model | shared = shared, page = page }
                , Cmd.batch [ Cmd.map Shared sharedCmd, notifyCmd ]
                )

        Page pageMsg ->
            let
                ( page, effect ) =
                    Pages.update pageMsg model.page model.shared model.url model.key

                ( sharedMsgs, remainingEffect ) =
                    Effect.partitionShared effect

                ( shared, sharedCmd ) =
                    List.foldl applySharedMsg ( model.shared, Cmd.none ) sharedMsgs

                applySharedMsg : Shared.Msg -> ( Shared.Model, Cmd Msg ) -> ( Shared.Model, Cmd Msg )
                applySharedMsg sharedMsg ( accShared, accCmd ) =
                    let
                        ( newShared, cmd ) =
                            Shared.update (Request.create () model.url model.key) sharedMsg accShared
                    in
                    ( newShared, Cmd.batch [ accCmd, Cmd.map Shared cmd ] )

                -- The page itself was just updated against `model.shared` -- the state as it
                -- stood *before* the `sharedMsgs` it forwarded were applied above, so any
                -- `fromShared` handler that reads shared state (e.g. `Pages.Home_`'s
                -- `fetchNewServers`, keying off `AccountsPanel.enabledServers`) sees last
                -- message's state, not this one's. Re-notify the page with the now-updated
                -- `shared`, exactly as `notifyPageOfSharedMsg` already does for Shared.Msgs
                -- that originate outside any page -- see its doc for why re-emitted
                -- Shared.Msgs from this second pass are safe to drop.
                ( notifiedPage, notifyCmd ) =
                    List.foldl
                        (\sharedMsg ( accPage, accCmd ) ->
                            let
                                ( newPage, cmd ) =
                                    notifyPageOfSharedMsg sharedMsg shared accPage model.url model.key
                            in
                            ( newPage, Cmd.batch [ accCmd, cmd ] )
                        )
                        ( page, Cmd.none )
                        sharedMsgs
            in
            ( { model | page = notifiedPage, shared = shared }
            , Cmd.batch [ sharedCmd, notifyCmd, Effect.toCmd ( Shared, Page ) remainingEffect ]
            )


{-| `ChangedUrl`'s own change 5 (see the module doc) -- `Just` only when both
`page` (whatever's currently running) and `newRoute` (the just-navigated-to
url's own route) are `Route.Event__PostId_`, in which case this is a same-page
"switched to a sibling `Occasion`" navigation (see `occasionChipView`'s own
href, `Components.Pages.EventPage.occasionUrlChanged`'s doc) rather than a
genuinely different page needing a fresh `init`. Built from `newRoute`'s own
`postId`, whatever it is -- `Pages.Event.PostId_.occasionUrlChanged` itself
sorts out whether that's actually one of the current `Event`'s own sibling
`Occasion`s (falling back to a real fetch if not, e.g. a bookmarked/typed url
for an unrelated `Event`).
-}
occasionSwitchMsg : Gen.Model.Model -> Route.Route -> Maybe Gen.Msg.Msg
occasionSwitchMsg page newRoute =
    case ( page, newRoute ) of
        ( Gen.Model.Event__PostId_ _ _, Route.Event__PostId_ params ) ->
            Just (Gen.Msg.Event__PostId_ (Pages.Event.PostId_.occasionUrlChanged params.postId))

        _ ->
            Nothing


{-| The `Gen.Msg.Msg` that delivers `sharedMsg` to `page` via its `fromShared`
hook, for whichever page is currently active. `Nothing` for pages with no
such hook (e.g. `About`, `NotFound`) -- see `Pages.Home_.fromShared`,
`Pages.Post.PostId_.fromShared`.
-}
sharedMsgForPage : Shared.Msg -> Gen.Model.Model -> Maybe Gen.Msg.Msg
sharedMsgForPage sharedMsg page =
    case page of
        Gen.Model.About _ _ ->
            Just (Gen.Msg.About (Pages.About.fromShared sharedMsg))

        Gen.Model.Home_ _ _ ->
            Just (Gen.Msg.Home_ (Pages.Home_.fromShared sharedMsg))

        Gen.Model.Posts _ _ ->
            Just (Gen.Msg.Posts (Pages.Posts.fromShared sharedMsg))

        Gen.Model.Events _ _ ->
            Just (Gen.Msg.Events (Pages.Events.fromShared sharedMsg))

        Gen.Model.Post__PostId_ _ _ ->
            Just (Gen.Msg.Post__PostId_ (Pages.Post.PostId_.fromShared sharedMsg))

        Gen.Model.Event__PostId_ _ _ ->
            Just (Gen.Msg.Event__PostId_ (Pages.Event.PostId_.fromShared sharedMsg))

        Gen.Model.Server__ServerIdentifier_ _ _ ->
            Just (Gen.Msg.Server__ServerIdentifier_ (Pages.Server.ServerIdentifier_.fromShared sharedMsg))

        Gen.Model.User__UserId_ _ _ ->
            Just (Gen.Msg.User__UserId_ (Pages.User.UserId_.fromShared sharedMsg))

        Gen.Model.User__UserId___Posts _ _ ->
            Just (Gen.Msg.User__UserId___Posts (Pages.User.UserId_.Posts.fromShared sharedMsg))

        Gen.Model.User__UserId___Events _ _ ->
            Just (Gen.Msg.User__UserId___Events (Pages.User.UserId_.Events.fromShared sharedMsg))

        Gen.Model.User__UserId___Following _ _ ->
            Just (Gen.Msg.User__UserId___Following (Pages.User.UserId_.Following.fromShared sharedMsg))

        Gen.Model.User__UserId___Followers _ _ ->
            Just (Gen.Msg.User__UserId___Followers (Pages.User.UserId_.Followers.fromShared sharedMsg))

        Gen.Model.User__UserId___Friends _ _ ->
            Just (Gen.Msg.User__UserId___Friends (Pages.User.UserId_.Friends.fromShared sharedMsg))

        Gen.Model.UsernameOrCustomTab_ _ _ ->
            Just (Gen.Msg.UsernameOrCustomTab_ (Pages.UsernameOrCustomTab_.fromShared sharedMsg))

        Gen.Model.UsernameOrCustomTab___Posts _ _ ->
            Just (Gen.Msg.UsernameOrCustomTab___Posts (Pages.UsernameOrCustomTab_.Posts.fromShared sharedMsg))

        Gen.Model.UsernameOrCustomTab___Events _ _ ->
            Just (Gen.Msg.UsernameOrCustomTab___Events (Pages.UsernameOrCustomTab_.Events.fromShared sharedMsg))

        Gen.Model.UsernameOrCustomTab___Following _ _ ->
            Just (Gen.Msg.UsernameOrCustomTab___Following (Pages.UsernameOrCustomTab_.Following.fromShared sharedMsg))

        Gen.Model.UsernameOrCustomTab___Followers _ _ ->
            Just (Gen.Msg.UsernameOrCustomTab___Followers (Pages.UsernameOrCustomTab_.Followers.fromShared sharedMsg))

        Gen.Model.UsernameOrCustomTab___Friends _ _ ->
            Just (Gen.Msg.UsernameOrCustomTab___Friends (Pages.UsernameOrCustomTab_.Friends.fromShared sharedMsg))

        Gen.Model.People _ _ ->
            Just (Gen.Msg.People (Pages.People.fromShared sharedMsg))

        Gen.Model.Messages _ _ ->
            Just (Gen.Msg.Messages (Pages.Messages.fromShared sharedMsg))

        Gen.Model.Market _ _ ->
            Just (Gen.Msg.Market (Pages.Market.fromShared sharedMsg))

        Gen.Model.Market__Product__ProductId_ _ _ ->
            Just (Gen.Msg.Market__Product__ProductId_ (Pages.Market.Product.ProductId_.fromShared sharedMsg))

        Gen.Model.Market__Fulfillment _ _ ->
            Just (Gen.Msg.Market__Fulfillment (Pages.Market.Fulfillment.fromShared sharedMsg))

        _ ->
            Nothing


{-| Forwards a `Shared.Msg` that originated outside any page's `update` --
e.g. `GotReconnectResult`, fired from a `Cmd` kicked off in `Shared.init` when
reconnecting persisted servers at startup -- into the currently active page,
so pages that react to it via their own `SharedMsg` case (see `Pages.Home_`,
`Pages.Post.PostId_`) notice immediately instead of relying on a poll to
eventually catch up.

Any `Shared.Msg`s the page's own `update` forwards back out in response (via
`Effect.fromShared`) are dropped rather than reapplied to `Shared.update` --
a page's `SharedMsg` handler only ever echoes back the very message it was
just given here, and `sharedMsg` has already been applied by the caller, so
reapplying it would double up a state change that's already been made.

-}
notifyPageOfSharedMsg : Shared.Msg -> Shared.Model -> Gen.Model.Model -> Url -> Key -> ( Gen.Model.Model, Cmd Msg )
notifyPageOfSharedMsg sharedMsg shared page url key =
    case sharedMsgForPage sharedMsg page of
        Nothing ->
            ( page, Cmd.none )

        Just msg ->
            let
                ( newPage, effect ) =
                    Pages.update msg page shared url key

                ( _, remainingEffect ) =
                    Effect.partitionShared effect
            in
            ( newPage, Effect.toCmd ( Shared, Page ) remainingEffect )



-- VIEW


{-| `index.html`'s `#splash` overlay covers the app until `elm.js` loads and
this first `view` runs -- but `Browser.application` takes ownership of
`<body>`'s contents on every render (see `init`'s own module doc, change 1),
wiping out anything written there that Elm doesn't itself know about. So this
prepends an Elm-rendered `#splash`/`<img>` node, identical in appearance, onto
every `body` this produces from here on -- seamless the moment this first
render replaces the static one, and stable afterwards since Elm's vdom only
ever diffs attributes _this_ code declares on it (never a `class`), letting
`Ports.hideSplash` (see `Shared.splashHiddenCmd`) add/remove `.hidden` by hand
without Elm ever fighting or resetting that change on a later render.

Everything (including `splashOverlay` itself) is nested one level deeper than it used to be, inside
a single `Shared.appScrollDomId` div -- see that constant's own doc, and `main.css`'s matching
`#app-scroll` rule, for why: it's the one and only element that actually scrolls now, working
around an iOS 27 bug that painted a system blur over the top of the page whenever the *document*
itself was what scrolled. Every genuinely `position: fixed` node already in `doc.body` (modals,
the Accounts/Starred/etc. panels, `.shared-backdrop`, `splashOverlay` itself) stays positioned
relative to the real viewport regardless of this new wrapper -- `#app-scroll` sets `position` and
`overflow` but never a `transform`/`filter`, so it doesn't become a new containing block for them.
-}
view : Model -> Browser.Document Msg
view model =
    let
        doc : Browser.Document Msg
        doc =
            Pages.view model.page model.shared model.url model.key
                |> View.map Page
                |> View.toBrowserDocument
    in
    { doc
        | body =
            [ Html.div [ Html.Attributes.id Shared.appScrollDomId ]
                (splashOverlay :: doc.body)
            ]
    }


splashOverlay : Html Msg
splashOverlay =
    Html.div [ Html.Attributes.id "splash" ]
        [ Html.img
            [ Html.Attributes.src "/favicon.png"
            , Html.Attributes.alt ""

            -- See `public/index.html`'s matching `<img>` doc comment: `/favicon.png`
            -- is generated on the fly by the Rust backend, so it never actually
            -- decodes as an image when this SPA is served standalone (e.g.
            -- `elm-spa`'s own dev server) -- the CSS starts it transparent, and this
            -- fades it in only on a real successful load, covering both a plain
            -- 404 and that dev server's own SPA-fallback 200. Note this deliberately
            -- never declares a `class` here, same reasoning as `#splash`'s own
            -- `hidden` class above -- Elm's vdom must never contest a class this
            -- inline handler adds by hand.
            , Html.Attributes.attribute "onload" "this.classList.add('loaded');"
            ]
            []
        ]
