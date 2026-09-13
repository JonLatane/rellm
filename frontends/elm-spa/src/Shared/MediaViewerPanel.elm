module Shared.MediaViewerPanel exposing (Model, Msg(..), init, subscriptions, update, view)

{-| A single, app-wide fullscreen image/video viewer -- an alternate,
"big"/fullscreen rendering of a `Post`'s `media` (compare
`Components.MultiMediaRenderer`'s compact card/detail previews), with a
"current" item the user can page through, like a carousel. One shared
instance, opened from wherever a `Post`'s media is tapped (`Pages.Home_`,
`Pages.Post.PostId_`, `Shared.StarredPanel`) rather than each caller
owning its own viewer state, same reasoning as `Shared.MarkdownPanel`. Also
opened, with no backing `Post` at all, from `Shared.MyMediaPanel`'s own
Browse-mode grid -- see `Msg`'s own doc on `Open`.

Doesn't need `AccountsPanel.Model` in `update` (no RPCs to make, nothing to
forward -- see `Shared.AccountsPanel.DebugTab` for the same minimal shape); `view` still
takes it, to resolve `targetHost` into the `Server`/`Account` needed to build
each media item's URL, the same way `Components.MultiMediaRenderer`'s callers
do.

-}

import Browser.Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (class)
import Html.Events exposing (on, onClick, preventDefaultOn, stopPropagationOn)
import Html.Keyed
import Json.Decode as Decode
import Process
import Proto.Rellm exposing (MediaReference, Post)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Task
import UI.Classes exposing (classes, openClosedClass)


type alias Model =
    { media : List MediaReference
    , currentMediaReference : Maybe String

    -- The Post this media came from -- every caller opens this panel from a
    -- Post today (see `Open`), and its title is shown in the bottom toolbar
    -- (see `view`).
    , maybePost : Maybe Post

    -- Needed to resolve `view`'s `AccountsPanel.Model` down to the actual
    -- `Server`/`Account` the tapped Post's media belongs to -- same
    -- `targetHost` convention `Shared.MarkdownPanel` uses.
    , targetHost : String

    -- Which way the *last* `Next`/`Prev` paged, purely to pick a slide
    -- direction in `view` (see `directionClass`) -- has no bearing on
    -- `currentMediaReference` itself. Reset to `Entering` on every fresh
    -- `Open`, so the first image of a newly-opened post just fades in rather
    -- than sliding in from whatever direction the previous post's viewing
    -- happened to leave behind.
    , direction : Direction

    -- Where an in-progress swipe (see `TouchStart`) began, in viewport
    -- coordinates -- `Nothing` when no touch is currently down on the media.
    -- Consumed by `TouchEnd`, which diffs it against the touch's ending point
    -- to decide whether the gesture was a swipe at all and, if so, which one
    -- (see `applySwipe`).
    , touchStart : Maybe ( Float, Float )

    -- Debounces the neighbor-preload elements (see `view`'s `preloadMedia`)
    -- behind `preloadDelayMs` of no further paging: every `Open`/`Next`/
    -- `Prev`/`SetCurrent` that lands on a new `currentMediaReference` clears
    -- this back to `Nothing` and schedules a fresh `PreloadReady` for that
    -- id (see `schedulePreload`) -- `view` only actually renders the hidden
    -- preload elements once this equals `currentMediaReference` again, i.e.
    -- once the *last* scheduled timer has actually landed without a further
    -- page superseding it first. A fast flick through several items in a
    -- row -- or a fast double-tap of `Next` -- never preloads anything for
    -- the items flown past, only whichever one the user actually stops on.
    , preloadFor : Maybe String
    }


type Msg
      -- `Open media maybePost initialId host` -- `media` is the full
      -- paging list (a `Post`'s own `.media`, or, from `Shared.MyMediaPanel`'s
      -- Browse mode, every currently-shown grid item converted to
      -- `MediaReference`); `maybePost` is `Just` only in the `Post`-backed
      -- case, purely so `view`'s toolbar can show that post's title --
      -- `Nothing` renders no title at all, same as before this panel could
      -- be opened any other way.
    = Open (List MediaReference) (Maybe Post) String String
    | SetCurrent String
    | Next
    | Prev
    | CloseClicked
    | TouchStart Float Float
    | TouchMove
    | TouchEnd Float Float
      -- Fired `preloadDelayMs` after landing on a new `currentMediaReference`
      -- -- see `Model.preloadFor`'s own doc. Carries the id it was scheduled
      -- for so a stale timer (superseded by further paging before it fired)
      -- can tell itself apart from the live one.
    | PreloadReady String


{-| See `Model.direction`'s doc.
-}
type Direction
    = Entering
    | Forward
    | Backward


init : Model
init =
    { media = [], currentMediaReference = Nothing, maybePost = Nothing, targetHost = "", direction = Entering, touchStart = Nothing, preloadFor = Nothing }


{-| Left/right arrow keys page `Prev`/`Next`, same as the toolbar's `‹`/`›`
buttons -- only while the panel's actually open, so the keys behave normally
(e.g. scrolling a `<select>`) everywhere else in the app.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if isOpen model then
        Browser.Events.onKeyDown keyDecoder

    else
        Sub.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Open media maybePost initialId host ->
            let
                newCurrent : Maybe String
                newCurrent =
                    validCurrent media initialId
            in
            ( { media = media
              , currentMediaReference = newCurrent
              , maybePost = maybePost
              , targetHost = host
              , direction = Entering
              , touchStart = Nothing
              , preloadFor = Nothing
              }
            , schedulePreload newCurrent
            )

        SetCurrent id ->
            case validCurrent model.media id of
                Just validId ->
                    ( { model | currentMediaReference = Just validId, preloadFor = Nothing }, schedulePreload (Just validId) )

                Nothing ->
                    ( model, Cmd.none )

        Next ->
            case adjacent 1 model of
                Just nextMedia ->
                    ( { model | currentMediaReference = Just nextMedia.id, direction = Forward, preloadFor = Nothing }, schedulePreload (Just nextMedia.id) )

                Nothing ->
                    ( model, Cmd.none )

        Prev ->
            case adjacent -1 model of
                Just prevMedia ->
                    ( { model | currentMediaReference = Just prevMedia.id, direction = Backward, preloadFor = Nothing }, schedulePreload (Just prevMedia.id) )

                Nothing ->
                    ( model, Cmd.none )

        CloseClicked ->
            ( init, Cmd.none )

        TouchStart x y ->
            ( { model | touchStart = Just ( x, y ) }, Cmd.none )

        -- No-op on the model -- exists only so `view` has a `Msg` to attach
        -- `preventDefaultOn` to (see there), stopping iOS Safari from
        -- treating an in-progress swipe as a page scroll/bounce or an
        -- edge-swipe-back gesture before `TouchEnd` gets a chance to fire.
        TouchMove ->
            ( model, Cmd.none )

        TouchEnd x y ->
            case model.touchStart of
                Just start ->
                    applySwipe start ( x, y ) { model | touchStart = Nothing }

                Nothing ->
                    ( model, Cmd.none )

        -- See `Model.preloadFor`'s own doc -- only actually starts
        -- preloading if `id` is still what's current; a stale timer that
        -- lost the race to a further page is silently dropped.
        PreloadReady id ->
            if model.currentMediaReference == Just id then
                ( { model | preloadFor = Just id }, Cmd.none )

            else
                ( model, Cmd.none )


{-| Schedules `PreloadReady maybeId` (a no-op if `maybeId` is `Nothing` --
`Open`'s own initial id can fail `validCurrent`) `preloadDelayMs` from now --
see `Model.preloadFor`'s own doc for why every `currentMediaReference` change
calls this.
-}
schedulePreload : Maybe String -> Cmd Msg
schedulePreload maybeId =
    case maybeId of
        Just id ->
            Process.sleep preloadDelayMs |> Task.perform (\_ -> PreloadReady id)

        Nothing ->
            Cmd.none


{-| How long `view`'s neighbor-preload elements (`preloadMedia`) wait, with no
further `Open`/`Next`/`Prev`/`SetCurrent`, before actually starting -- long
enough that a user flicking rapidly through a gallery (arrow keys held down,
or several fast swipes) never fires off a preload fetch for every item flown
past, only the one they actually stop on.
-}
preloadDelayMs : Float
preloadDelayMs =
    1500


{-| What a completed swipe gesture (see `TouchStart`/`TouchEnd`) amounts to,
based on whichever axis moved further between the touch's start and end
points -- horizontal swipes page `Next`/`Prev` (left mirrors the toolbar's
`›`, right its `‹`, i.e. swiping toward where the next/previous image is
about to slide in from), vertical swipes close the panel, same as tapping
the backdrop. Below `swipeThreshold` in both axes, nothing happens.
-}
applySwipe : ( Float, Float ) -> ( Float, Float ) -> Model -> ( Model, Cmd Msg )
applySwipe ( startX, startY ) ( endX, endY ) model =
    let
        dx : Float
        dx =
            endX - startX

        dy : Float
        dy =
            endY - startY
    in
    if abs dx >= abs dy then
        if dx <= -swipeThreshold then
            update Next model

        else if dx >= swipeThreshold then
            update Prev model

        else
            ( model, Cmd.none )

    else if abs dy >= swipeThreshold then
        ( init, Cmd.none )

    else
        ( model, Cmd.none )


view : AccountsPanel.Model -> Model -> Html Msg
view accountsPanelModel model =
    let
        currentMedia : Maybe MediaReference
        currentMedia =
            model.currentMediaReference
                |> Maybe.andThen (\id -> List.filter (\m -> m.id == id) model.media |> List.head)

        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost accountsPanelModel.servers model.targetHost

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost

        -- The would-be `Prev`/`Next` targets, once `model.preloadFor` (see
        -- its own doc) confirms the user's actually settled on
        -- `currentMediaReference` rather than mid-flick through several in a
        -- row -- `[]` the entire time before that, so nothing renders (and
        -- so nothing fetches) until then. Images/videos only: a hidden
        -- `<object>` (PDF/etc, see `Components.MediaRenderer.view`) would
        -- start an eager download with no matching payoff -- unlike an
        -- image/video, landing on it doesn't get any snappier from having
        -- pre-fetched a plugin embed nobody's looked at yet.
        preloadMedia : List ( String, MediaReference )
        preloadMedia =
            if model.preloadFor == model.currentMediaReference then
                [ ( "preload-prev", adjacent -1 model ), ( "preload-next", adjacent 1 model ) ]
                    |> List.filterMap (\( key, maybeMedia ) -> maybeMedia |> Maybe.map (Tuple.pair key))
                    |> List.filter (\( _, media ) -> isImage media || isVideo media)

            else
                []

        -- Same `MediaRenderer.view` call the currently-shown media itself
        -- uses (`Natural`/`ToWidthAndHeight`, same `server`/`maybeAccount`)
        -- so the URL it requests is byte-for-byte what paging to this item
        -- will actually render -- a mismatched URL (e.g. a different size
        -- param) would just be a second, wasted fetch instead of a cache
        -- hit. `media_viewer_panel.css`'s own `.media-viewer-panel-preload`
        -- hides these visually (`opacity: 0`, not `display: none`) and takes
        -- them out of interaction (`pointer-events: none`) while still
        -- keeping them laid out on-screen -- `MediaRenderer.view`'s own
        -- `loading="lazy"` on the `<img>` case only defers a fetch while an
        -- element is far from the viewport; an on-screen-but-invisible one
        -- (as opposed to `display: none`, which many browsers just never
        -- schedule a lazy fetch for at all) loads immediately, same as a
        -- visible one would.
        preloadView : RellmServer -> List ( String, Html Msg )
        preloadView server =
            preloadMedia
                |> List.map
                    (\( key, media ) ->
                        ( key
                        , div [ class "media-viewer-panel-preload" ]
                            [ MediaRenderer.view MediaRenderer.Natural MediaRenderer.ToWidthAndHeight server maybeAccount SetCurrent media ]
                        )
                    )

        indexLabel : List (Html Msg)
        indexLabel =
            case ( model.currentMediaReference |> Maybe.andThen (\id -> indexOf id model.media), List.length model.media ) of
                ( Just index, count ) ->
                    if count > 1 then
                        [ span [ class "media-viewer-panel-index" ] [ text (String.fromInt (index + 1) ++ " / " ++ String.fromInt count) ] ]

                    else
                        []

                _ ->
                    []

        -- This panel's own root below carries the background-tap-to-close
        -- `onClick` (it's its own backdrop -- see media_viewer_panel.css's
        -- doc comment), so every *real* control needs to stop a click from
        -- bubbling back up to it -- otherwise paging/closing via a button, or
        -- just tapping the media itself, would also immediately re-close the
        -- whole panel. `stopClick` is `onClick` plus that guard.
        stopClick : Msg -> Html.Attribute Msg
        stopClick msg =
            stopPropagationOn "click" (Decode.succeed ( msg, True ))

        -- `changedTouches` (not `touches`) for `touchend`: by the time it
        -- fires, the lifted finger is no longer in `touches`, only in
        -- `changedTouches` -- see MDN's TouchEvent docs.
        touchPoint : String -> (Float -> Float -> Msg) -> Decode.Decoder Msg
        touchPoint touchList toMsg =
            Decode.map2 toMsg
                (Decode.at [ touchList, "0", "clientX" ] Decode.float)
                (Decode.at [ touchList, "0", "clientY" ] Decode.float)

        navButton : List String -> Msg -> String -> Html Msg
        navButton classNames msg label =
            button [ classes ("media-viewer-panel-nav" :: classNames), stopClick msg ] [ text label ]
    in
    div
        [ classes [ "media-viewer-panel", "nav-panel", openClosedClass (isOpen model) ]
        , onClick CloseClicked
        ]
        [ div [ class "media-viewer-panel-header" ] indexLabel
        , div [ class "media-viewer-panel-content" ]
            [ case ( currentMedia, maybeServer ) of
                ( Just media, Just server ) ->
                    -- Keyed on `media.id` so paging to a different item swaps
                    -- in a brand-new DOM node rather than patching the old
                    -- `<img>`/`<video>`'s attributes in place -- that fresh
                    -- insertion is what lets `directionClass`'s CSS animation
                    -- (media_viewer_panel.css) actually play on every page,
                    -- the same trick `Shared.StarredPanel`'s
                    -- `Html.Keyed` list uses for its own enter animation.
                    Html.Keyed.node "div"
                        [ class "media-viewer-panel-media-stage" ]
                        [ ( media.id
                          , div
                                [ classes [ "media-viewer-panel-media", directionClass model.direction ]
                                , -- Images have no in-place interaction worth
                                  -- preserving, so tapping one closes the
                                  -- panel like tapping the backdrop would --
                                  -- videos still need the tap to reach their
                                  -- native `controls` (play/pause/scrub), so
                                  -- those keep the old stop-and-no-op.
                                  stopClick
                                    (if isImage media then
                                        CloseClicked

                                     else
                                        SetCurrent media.id
                                    )
                                , on "touchstart" (touchPoint "touches" TouchStart)
                                , preventDefaultOn "touchmove" (Decode.succeed ( TouchMove, model.touchStart /= Nothing ))
                                , on "touchend" (touchPoint "changedTouches" TouchEnd)
                                ]
                                [ MediaRenderer.viewAutoplay MediaRenderer.Natural MediaRenderer.ToWidthAndHeight server maybeAccount SetCurrent media ]
                          )
                        ]

                _ ->
                    text ""
            , case maybeServer of
                Just server ->
                    Html.Keyed.node "div" [ class "media-viewer-panel-preload-stage" ] (preloadView server)

                Nothing ->
                    text ""
            ]
        , div [ class "media-viewer-panel-toolbar" ]
            [ case adjacent -1 model of
                Just _ ->
                    navButton [ "media-viewer-panel-prev" ] Prev "‹"

                Nothing ->
                    text ""
            , div [ class "media-viewer-panel-post-title", stopClick CloseClicked ]
                [ text (model.maybePost |> Maybe.map Posts.postTitleText |> Maybe.withDefault "") ]
            , case adjacent 1 model of
                Just _ ->
                    navButton [ "media-viewer-panel-next" ] Next "›"

                Nothing ->
                    text ""
            , button [ class "media-viewer-panel-close", stopClick CloseClicked ] [ text "✕" ]
            ]
        ]


{-| CSS animation to play for the media stage's freshly-keyed node (see
`view`) -- a directional slide for `Next`/`Prev`, a plain fade for a fresh
`Open`. Matched to `.media-viewer-panel-media-*` in media\_viewer\_panel.css.
-}
directionClass : Direction -> String
directionClass direction =
    case direction of
        Entering ->
            "media-viewer-panel-media-entering"

        Forward ->
            "media-viewer-panel-media-forward"

        Backward ->
            "media-viewer-panel-media-backward"


{-| Whether the panel is currently open -- driving `openClosedClass` and
`UI.elm`'s `sharedBackdrop`, same as `MarkdownPanel`'s `target /= Nothing`.
-}
isOpen : Model -> Bool
isOpen model =
    model.currentMediaReference /= Nothing


{-| A `MediaReference.id` from `media`, if it's actually in `media` -- refuses
any id that isn't, so `currentMediaReference` can never point at an item the
panel wasn't given (a stale id left over from `SetCurrent`, or a caller
passing the wrong list/id pair to `Open`).
-}
validCurrent : List MediaReference -> String -> Maybe String
validCurrent media id =
    if List.any (\m -> m.id == id) media then
        Just id

    else
        Nothing


{-| Below this many pixels of travel on both axes, a completed touch is just
a tap (left to `MediaRenderer`'s own `onClick`/`SetCurrent`), not a swipe.
-}
swipeThreshold : Float
swipeThreshold =
    50


indexOf : String -> List MediaReference -> Maybe Int
indexOf id media =
    media
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, m ) -> m.id == id)
        |> List.head
        |> Maybe.map Tuple.first


getAt : Int -> List MediaReference -> Maybe MediaReference
getAt index media =
    media |> List.drop index |> List.head


keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "ArrowLeft" ->
                        Decode.succeed Prev

                    "ArrowRight" ->
                        Decode.succeed Next

                    _ ->
                        Decode.fail "not an arrow key"
            )


{-| Whether `media` is an image, by its MIME type's top-level part -- mirrors
`Components.MediaRenderer.view`'s own `contentType` branch. Used by `view` to
decide whether tapping the media itself should close the panel (images have
no in-place interaction to preserve) or not (videos need the tap to reach
their native `controls`, same as before this behavior existed).
-}
isImage : MediaReference -> Bool
isImage media =
    (String.split "/" (MediaRenderer.contentTypeOf media) |> List.head) == Just "image"


{-| Whether `media` is a video, by its MIME type's top-level part -- mirrors
`isImage` (see its own doc), just for `view`'s `preloadMedia`, which -- unlike
`isImage`'s own callers -- needs to tell both playable media types apart from
everything else `Components.MediaRenderer.view` falls back to (`Media.object`,
e.g. a PDF).
-}
isVideo : MediaReference -> Bool
isVideo media =
    (String.split "/" (MediaRenderer.contentTypeOf media) |> List.head) == Just "video"


{-| The item before/after the current one in `media`, wrapping around --
`Nothing` if `media` has one item or fewer (nothing to page to).
-}
adjacent : Int -> Model -> Maybe MediaReference
adjacent offset model =
    let
        count : Int
        count =
            List.length model.media
    in
    if count < 2 then
        Nothing

    else
        model.currentMediaReference
            |> Maybe.andThen (\id -> indexOf id model.media)
            |> Maybe.andThen (\index -> getAt (modBy count (index + offset)) model.media)
