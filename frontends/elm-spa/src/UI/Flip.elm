module UI.Flip exposing
    ( Axis(..)
    , MoveState
    , Rect
    , State
    , animate
    , applyReorder
    , atRest
    , atRestScaled
    , beginReorder
    , enter
    , flipDurationMs
    , itemAttributes
    , measureElementsCmd
    , moveAnimate
    , moveAttributes
    , moveListItemBy
    , moveSubscription
    , reappear
    , rectsDecoder
    , remove
    , reorderButtonPair
    , reorderButtons
    , restingState
    , startMove
    , startMoveScaled
    , subscription
    , syncAnimations
    , syncEnter
    )

{-| Generic FLIP-style ("First, Last, Invert, Play") animation helpers for
items in a keyed, flex list -- extracted from `Pages.Home_`'s original
per-post `PostAnimation` (see its history) so every animated list (recent
posts, Accounts, Servers, future ones -- including a future grid, which is why
everything below is in terms of both axes even where today's callers only
ever move along one) shares one implementation. Pair with
`.flip-animated-column`/`.flip-animated-row`/`.flip-animated-item` in
`flip.css`.

There are two independent things a list item can animate:

  - **Entering/leaving** (`State`) -- fades/scales an item in on arrival, and
    fades/scales+collapses it out on departure while the rest of the list
    slides smoothly to fill the gap.
  - **Moving** (`MoveState`) -- an item that's still present but changed
    position (e.g. a reorder) slides from where it was to where it now is,
    rather than jumping.

A caller wraps one or both of these alongside its own per-item data, e.g.
`{ post : Post, flip : UI.Flip.State Msg }`.

-}

import Animation
import Animation.Messenger
import Browser.Dom as Dom
import Dict exposing (Dict)
import Html exposing (Attribute, Html, button, div, text)
import Html.Attributes exposing (class, classList, disabled, title)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Task


{-| Which way a list lays its items out -- `Vertical` for a column (top to
bottom, e.g. Accounts), `Horizontal` for a row (left to right, e.g. Servers).
A future grid would need a move along both axes at once, which is why
`MoveState`/`startMove` already carry a full `(x, y)` offset rather than one
scalar -- `Axis` only decides which of the two `swapDeltas` actually fills in
for a plain list.
-}
type Axis
    = Vertical
    | Horizontal



-- ENTERING / LEAVING


{-| One item's enter/leave animation state.
-}
type alias State msg =
    { removing : Bool
    , entering : Bool
    , style : Animation.Messenger.State msg
    }


{-| `flip.css`'s own `.flip-animated-item` transition duration (`0.25s`,
`grid-template-rows`/`-columns`) -- `flipEasing` (below) is what keeps the
opacity/scale fade below in lockstep with it.
-}
flipDurationMs : Float
flipDurationMs =
    250


{-| Elm's own copy of CSS's `ease` timing function (`cubic-bezier(0.25, 0.1,
0.25, 1.0)`, the browser default and exactly what `flip.css`'s own
`.flip-animated-item` `transition` declares) -- solved via Newton-Raphson on
the bezier curve's own `x(t)`, the same general technique browsers use
themselves, since `Float -> Float` easing functions in this library are
defined in terms of "given elapsed-time fraction `x`, what's the eased
progress `y`", not the four raw control points a CSS `cubic-bezier()` takes
directly.

`enter`/`remove`/`reappear`'s own opacity/scale fade uses this (paired with
`flipDurationMs`) instead of `Animation.to`'s _default_ interpolation for a
plain numeric property -- a lightly-damped spring (`stiffness = 170, damping
= 26`, see `Animation.Model.defaultInterpolationByProperty`) that, unlike
`flip.css`'s own fixed-duration CSS transition, has no fixed duration at all:
it settles once its position and velocity both drop under a small tolerance,
which for these particular constants takes roughly 400-550ms -- comfortably
_longer_ than the CSS collapse's fixed 250ms. That gap is exactly what
produced the "mostly collapses, then a frozen-looking pause, then suddenly
finishes" artifact reported live (Messages' sidebar/detail panes, but also
PostsPage/UsersPage/StarredPanel turning something off -- every `UI.Flip`
caller, confirming this was never page-specific): the CSS-driven
`grid-template-rows` had already visually collapsed the item to zero height
by 250ms, but the _element itself_ -- and, for any caller whose own container
also declares a `gap` alongside `.flip-animated-column` (`.messages-group-list`,
`.user-picker-list`, `.my-media-panel-grid`/`-selected-strip`, `.events-grid`,
`.occasion-grid`), the resulting empty `gap`-width sliver right where
it used to be -- stuck around for however much longer the spring's own slow,
barely-visible settling tail actually took, since only the spring's own
completion (`Animation.Messenger.send onRemoved`) ever actually deletes the
item from the caller's collection. Matching both animations to the _same_
fixed duration and curve removes that gap entirely -- either both finish at
250ms, or (aesthetically, not the bug fix) neither does.

-}
flipEasing : Animation.Interpolation
flipEasing =
    Animation.easing { duration = flipDurationMs, ease = cssEase }


{-| `cubic-bezier(0.25, 0.1, 0.25, 1.0)` (CSS's `ease`), evaluated at
elapsed-time fraction `x` -- Newton-Raphson on the bezier's own parametric
`x(t)` (8 iterations, converges well past visible precision for a curve this
mild/monotonic) to find `t` such that `bezierX t == x`, then returns `bezierY
t`. `x` itself is already a solid initial guess for `t` on a curve whose own
`x1`/`x2` control points (`0.25`/`0.25`) are both roughly on the identity
line, so this converges in just a few iterations in practice.
-}
cssEase : Float -> Float
cssEase x =
    let
        x1 : Float
        x1 =
            0.25

        y1 : Float
        y1 =
            0.1

        x2 : Float
        x2 =
            0.25

        y2 : Float
        y2 =
            1.0

        bezierComponent : Float -> Float -> Float -> Float
        bezierComponent t p1 p2 =
            let
                mt : Float
                mt =
                    1 - t
            in
            (3 * mt * mt * t * p1) + (3 * mt * t * t * p2) + (t * t * t)

        bezierXDerivative : Float -> Float
        bezierXDerivative t =
            let
                mt : Float
                mt =
                    1 - t
            in
            (3 * mt * mt * x1) + (6 * mt * t * (x2 - x1)) + (3 * t * t * (1 - x2))

        solveT : Float -> Int -> Float
        solveT guess iterations =
            if iterations <= 0 then
                guess

            else
                let
                    derivative : Float
                    derivative =
                        bezierXDerivative guess
                in
                if abs derivative < 1.0e-6 then
                    guess

                else
                    solveT (guess - ((bezierComponent guess x1 x2 - x) / derivative)) (iterations - 1)
    in
    bezierComponent (solveT x 8) y1 y2


{-| A static "already here, nothing animating" state -- the right thing to
default a not-yet-tracked item to, e.g. one that's about to be removed for
the first time and needs a real (visible, settled) state for `remove` to
interrupt/animate away from, unlike `enter`'s hidden/shrunk starting point.
-}
restingState : State msg
restingState =
    { removing = False
    , entering = False
    , style = Animation.style [ Animation.opacity 1, Animation.scale 1 ]
    }


{-| A freshly-seen item: starts invisible/slightly shrunk and immediately
animates in to its natural opacity/scale.
-}
enter : State msg
enter =
    { removing = False
    , entering = True
    , style =
        Animation.style [ Animation.opacity 0, Animation.scale 0.92 ]
            |> Animation.interrupt
                [ Animation.toWith flipEasing [ Animation.opacity 1, Animation.scale 1 ] ]
    }


{-| An item that was mid fade-out reappearing: interrupts whatever fade-out
step was queued (including its trailing removal send, so that `Msg` never
fires) and animates back in.
-}
reappear : State msg -> State msg
reappear state =
    { state
        | removing = False
        , style =
            Animation.interrupt
                [ Animation.toWith flipEasing [ Animation.opacity 1, Animation.scale 1 ] ]
                state.style
    }


{-| Starts an item animating out, then sends `onRemoved` once the fade
finishes -- the caller uses that to actually drop it from its own collection.

A caller's render-order derivation has to keep a `removing` item at its exact
existing rank, never relocate it -- moving a keyed DOM node and changing the
class this flips on (`flip-collapsed`, via `itemAttributes`) in the same patch
silently cancels the CSS collapse transition in every browser tested
(confirmed via a real delete, instrumented headless: no `transitionrun` event
at all, the item's box just snaps straight to its collapsed size). Every
caller in this codebase gets this for free already, via one of two patterns:
`AccountsPanel`'s servers/accounts and `StarredPanel`'s starred posts
keep an item in their own locally-owned order at its original slot until
`onRemoved` actually deletes it (nothing ever reorders a still-present item);
`Components.Pages.PostsPage`/`UsersPage` instead re-sort their whole list
every render, but by a stable per-item property (a post's timestamp, a user's
username) that doesn't change just because an item started removing, so nothing
re-sorts relative to anything else. A caller whose order comes from a server
refetch with no such natural sort key (e.g. `Shared.MyMediaPanel`, before it
switched to sorting by `Media.createdAt`) needs to track its own explicit
order list instead of rederiving one fresh as "current fetch order, plus
whichever removing ids the fetch no longer mentions, tacked on the end" --
that tacking-on is exactly the relocate-on-remove this note warns about.

-}
remove : msg -> State msg -> State msg
remove onRemoved state =
    { state
        | removing = True
        , style =
            Animation.interrupt
                [ Animation.toWith flipEasing [ Animation.opacity 0, Animation.scale 0.92 ]
                , Animation.Messenger.send onRemoved
                ]
                state.style
    }


{-| Steps `style` forward on an `Animation.Msg` tick, and clears `entering`
(it only needs to be `True` for the one frame that gives the browser
something to transition from) -- see `Pages.Home_.update`'s `Animate` case for
how a caller folds this over every live item in one `Dict`.
-}
animate : Animation.Msg -> State msg -> ( State msg, Cmd msg )
animate animMsg state =
    let
        ( newStyle, cmd ) =
            Animation.Messenger.update animMsg state.style
    in
    ( { state | style = newStyle, entering = False }, cmd )


{-| The `Sub` for every live item's enter/leave animation -- caller batches
this in with its own subscriptions, passing `List.map .style` of whatever it's
storing `State` in.
-}
subscription : (Animation.Msg -> msg) -> List (State msg) -> Sub msg
subscription toMsg states =
    Animation.subscription toMsg (List.map .style states)


{-| Attributes for the wrapping `div` -- `.flip-collapsed` (present while
`entering` or `removing`) is what makes `.flip-animated-item` in `flip.css`
grow/shrink this wrapper's own height (`axis = Vertical`, for a
`.flip-animated-column`) or width (`axis = Horizontal`, for a
`.flip-animated-row`), sliding the rest of the list smoothly into the space
this item leaves/needs, on top of its own fade/scale from `style`.

The output's `msg` is a wholly separate type variable from `state`'s own --
`Animation.render` never actually produces a `msg` value (nothing here is an
event handler), so a caller isn't forced to `Html.map` a whole subtree just
because `state`'s own `msg` (e.g. `remove`'s `onRemoved`) belongs to a
different module's `Msg` than the content being wrapped does.

`moving` is a caller-supplied `MoveState.moving` (see its own doc) for
whatever's nested inside this item, and drives a third class, `flip-moving`.
`flip.css`'s `.flip-animated-item > *` carries `overflow: hidden` so the
grid-row-collapse trick above can clip a shrinking/growing item's content --
but that same clip also cuts off a reorder-slide's `moveAttributes` transform
on the item nested inside it, since sliding away from rest visually pokes
past that box without changing its layout size. `flip-moving` only needs to
suspend the clip for the slide's own duration, not disable it outright (a
moved item can still later need the collapse-clip if it's removed), so it's a
separate class rather than folded into `flip-collapsed`.

-}
itemAttributes : Axis -> State state -> Bool -> List (Html.Attribute msg)
itemAttributes axis state moving =
    classList
        [ ( "flip-animated-item", True )
        , ( "horizontal", axis == Horizontal )
        , ( "flip-collapsed", state.entering || state.removing )
        , ( "flip-moving", moving )
        ]
        :: Animation.render state.style


{-| Ensures every item in `items` has a `State` entry in `animations`,
inserting a fresh `enter` for any that don't -- so a caller can call this
after every update to a list of persistent items (accounts, servers, starred
posts, ...) and have newly-appeared ones animate in automatically, without
hunting down every individual "this added a new one" call site by hand.
Leaves existing entries (resting, still entering, or removing) untouched.

Doesn't touch entries for ids no longer in `items` -- those belong to
whatever's mid-remove (see `remove`), which cleans up its own entry once its
fade finishes; nothing here should race that.

A caller whose items already exist before any interactive add/remove (e.g.
persisted accounts/servers reloaded on startup) should pre-seed `animations`
with `restingState` for each of them (rather than starting from `Dict.empty`)
before ever calling this, so this treats them as "already known" rather than
"just appeared" the first time it runs.

-}
syncEnter : (a -> String) -> List a -> Dict String (State msg) -> Dict String (State msg)
syncEnter idOf items animations =
    List.foldl
        (\item acc ->
            let
                key : String
                key =
                    idOf item
            in
            if Dict.member key acc then
                acc

            else
                Dict.insert key enter acc
        )
        animations
        items


{-| Reconciles a caller's own keyed animation dict -- any record shape with at
least a `flip : State msg` field, e.g. `Components.Pages.PostsPage.PostAnimation`/
`UsersPage.UserAnimation`/`Shared.MyMediaPanel.MediaAnimation`, all unchanged --
against a fresh `Dict String data` of whatever's currently present (a page's
own `Loaded` posts/users, a panel's own `Fetched` media, ...): starts a fade-in
(`enter`) for a newly-seen id via `buildEntering`, refreshes an existing
(non-`flip`) fields via `refresh` for one already resting or reappearing
(`reappear`s its `flip` first, same as a still-fading-out item un-interrupted
elsewhere), and fades out (`remove`) any id no longer present. Generalizes
`PostsPage.syncAnimations`/`UsersPage.syncAnimations` (identical apart from
what their own animation record holds) and `MyMediaPanel.syncMediaAnimations`.

`buildEntering`/`refresh` are the only caller-supplied pieces, since this
function has no way to know a caller's other fields (`r`) exist at all, let
alone how to fill them in from `data` -- `buildEntering data` constructs a
whole fresh record (own `flip` included, via `enter`); `refresh data anim`
updates `anim`'s own fields from `data` (its `flip` already handled by the
time this runs, whether staying put or just `reappear`ed).

Doesn't derive render order -- see `remove`'s own doc for why a naive
"currently-present ids, plus whichever removing ids the fetch no longer
mentions, tacked onto the end" would relocate a removing item and silently
cancel its CSS collapse transition; a stable per-item sort key (as
`PostsPage`/`UsersPage`/`MyMediaPanel` all use) or a caller-owned order list
(as `AccountsPanel`/`StarredPanel` effectively do, by never moving a
still-present item at all) is still the caller's own job.

-}
syncAnimations :
    (String -> msg)
    -> (data -> { r | flip : State msg })
    -> (data -> { r | flip : State msg } -> { r | flip : State msg })
    -> Dict String data
    -> Dict String { r | flip : State msg }
    -> Dict String { r | flip : State msg }
syncAnimations onRemoved buildEntering refresh currentItems animations =
    let
        addOrRefresh : String -> data -> Dict String { r | flip : State msg } -> Dict String { r | flip : State msg }
        addOrRefresh id data acc =
            case Dict.get id acc of
                Nothing ->
                    Dict.insert id (buildEntering data) acc

                Just anim ->
                    if anim.flip.removing then
                        Dict.insert id (refresh data { anim | flip = reappear anim.flip }) acc

                    else
                        Dict.insert id (refresh data anim) acc

        withCurrent : Dict String { r | flip : State msg }
        withCurrent =
            Dict.foldl addOrRefresh animations currentItems

        startRemovingIfGone : String -> { r | flip : State msg } -> Dict String { r | flip : State msg } -> Dict String { r | flip : State msg }
        startRemovingIfGone id anim acc =
            if anim.flip.removing || Dict.member id currentItems then
                acc

            else
                Dict.insert id { anim | flip = remove (onRemoved id) anim.flip } acc
    in
    Dict.foldl startRemovingIfGone withCurrent withCurrent



-- MOVING


{-| An item's move animation state: a `translate` plus whether it's currently
mid-slide. Unlike entering/leaving, a move settling back to `translate 0 0`
would be harmless to leave untracked forever -- but `moving` itself still
needs a completion callback (see `startMove`'s `onSettled`) so a caller can
clear it back to `False` once the slide actually finishes, which is what lets
`itemAttributes`' `flip-moving` class (see its own doc) apply only for the
slide's real duration rather than staying stuck on for good the first time an
item ever moves.
-}
type alias MoveState msg =
    { moving : Bool
    , style : Animation.Messenger.State msg
    }


{-| The identity/no-op move state -- an item that hasn't moved.
-}
atRest : MoveState msg
atRest =
    { moving = False
    , style = Animation.style [ Animation.translate (Animation.px 0) (Animation.px 0) ]
    }


{-| Like `atRest`, but also tracks a `scale3d` property from the start (see
`startMoveScaled`) -- a `MoveState` used with `startMoveScaled` needs to
start from this rather than plain `atRest`: `elm-style-animation` tracks a
fixed set of properties for the lifetime of a `State`, seeded by whatever
`Animation.style` it was originally built with, so `scale3d` has to be
present from the very first render, not introduced later by `startMoveScaled`
itself.
-}
atRestScaled : MoveState msg
atRestScaled =
    { moving = False
    , style =
        Animation.style
            [ Animation.translate (Animation.px 0) (Animation.px 0)
            , Animation.scale3d 1 1 1
            ]
    }


{-| Starts (or restarts) a move: `( deltaX, deltaY )` is how far, in px, the
item's _new_ position differs from where it just was along each axis
(`old - new`, so a positive component means it moved backward along that axis
-- up or left -- and should slide forward into place; a negative component
means it moved forward -- down or right -- and should slide backward into
place) -- see `swapDeltas` for how a caller measures that (the "Invert" step
of FLIP) for an adjacent-swap reorder. A plain vertical or horizontal list
only ever needs one non-zero component; a future grid would set both. Pins
the item at its old position via an instant, non-animated `translate`
("Invert"), then animates back to `translate 0 0` ("Play"), so it visually
slides from where it was to where it now is instead of jumping.

`onSettled` fires (see `moveAnimate`) once the "Play" step actually reaches
`translate 0 0` -- a caller stores it keyed the same as this `MoveState` and,
on receipt, sets `moving` back to `False` (mirroring `remove`'s `onRemoved`),
rather than clearing it eagerly the way `entering` is -- since here the whole
point is for `moving` to stay `True` for the slide's real duration.

-}
startMove : msg -> ( Float, Float ) -> MoveState msg -> MoveState msg
startMove onSettled ( deltaX, deltaY ) state =
    { moving = True
    , style =
        Animation.interrupt
            [ Animation.set [ Animation.translate (Animation.px deltaX) (Animation.px deltaY) ]
            , Animation.to [ Animation.translate (Animation.px 0) (Animation.px 0) ]
            , Animation.Messenger.send onSettled
            ]
            state.style
    }


{-| Like `startMove`, but also inverts a size change via `( scaleX, scaleY )`
(the item's _old_ width/height divided by its _new_ ones) alongside the
position delta -- for a caller whose item can change size across the same
transition it's repositioned in (e.g. `Components.Pages.EventsPage`'s cards,
full-width in `VerticalList` but a fixed tile width in `Grid`/`HorizontalList`),
so the item visually grows/shrinks smoothly into its new box instead of
snapping straight to the new size while only its position slides. `state`
must have come from `atRestScaled`, not plain `atRest` -- see that value's
own doc for why. The scaled element itself needs `transform-origin: top
left` (not the CSS default `50% 50%`) for this to combine correctly with the
position delta, since `( deltaX, deltaY )` is measured from each element's
top-left corner (`Browser.Dom.Element.element.x`/`.y`).
-}
startMoveScaled : msg -> ( Float, Float ) -> ( Float, Float ) -> MoveState msg -> MoveState msg
startMoveScaled onSettled ( deltaX, deltaY ) ( scaleX, scaleY ) state =
    { moving = True
    , style =
        Animation.interrupt
            [ Animation.set
                [ Animation.translate (Animation.px deltaX) (Animation.px deltaY)
                , Animation.scale3d scaleX scaleY 1
                ]
            , Animation.to
                [ Animation.translate (Animation.px 0) (Animation.px 0)
                , Animation.scale3d 1 1 1
                ]
            , Animation.Messenger.send onSettled
            ]
            state.style
    }


{-| The post-swap `( deltaX, deltaY )` "Invert" offsets (see `startMove`) for
two _adjacent_ items that just swapped places along `axis` -- e.g. two account
rows in a vertical list, or two server chips in a horizontal strip. Derived
entirely from their _pre-swap_ rects (`Browser.Dom.getElement`), so a caller
can compute this in the very same `update` that performs the swap, without
waiting for a second DOM measurement after the swap re-renders -- since the
item that was "first" along `axis` keeps that position, and the other lands
immediately after it (plus whatever gap was between them), swapping places.

Returns `(movedItemDelta, neighborDelta)`, matching the order `moved`/
`neighbor` were passed in.

-}
swapDeltas : Axis -> Dom.Element -> Dom.Element -> ( ( Float, Float ), ( Float, Float ) )
swapDeltas axis moved neighbor =
    let
        ( ( movedPos, movedSize ), ( neighborPos, neighborSize ) ) =
            case axis of
                Vertical ->
                    ( ( moved.element.y, moved.element.height ), ( neighbor.element.y, neighbor.element.height ) )

                Horizontal ->
                    ( ( moved.element.x, moved.element.width ), ( neighbor.element.x, neighbor.element.width ) )

        ( movedDelta1D, neighborDelta1D ) =
            if movedPos < neighborPos then
                let
                    gap : Float
                    gap =
                        neighborPos - movedPos - movedSize

                    newNeighborPos : Float
                    newNeighborPos =
                        movedPos

                    newMovedPos : Float
                    newMovedPos =
                        newNeighborPos + neighborSize + gap
                in
                ( movedPos - newMovedPos, neighborPos - newNeighborPos )

            else
                let
                    gap : Float
                    gap =
                        movedPos - neighborPos - neighborSize

                    newMovedPos : Float
                    newMovedPos =
                        neighborPos

                    newNeighborPos : Float
                    newNeighborPos =
                        newMovedPos + movedSize + gap
                in
                ( movedPos - newMovedPos, neighborPos - newNeighborPos )

        toXY : Float -> ( Float, Float )
        toXY delta1D =
            case axis of
                Vertical ->
                    ( 0, delta1D )

                Horizontal ->
                    ( delta1D, 0 )
    in
    ( toXY movedDelta1D, toXY neighborDelta1D )


{-| Attributes (just an inline `transform`) for the moving item's own
element.
-}
moveAttributes : MoveState msg -> List (Html.Attribute msg2)
moveAttributes state =
    Animation.render state.style


{-| Steps a `MoveState` forward on an `Animation.Msg` tick, returning any
`Cmd` from its `onSettled` (see `startMove`) firing this tick -- a caller
batches this in alongside its other per-item `Cmd`s the same way
`AnimateItemFlip`-style handlers already do for `animate`.
-}
moveAnimate : Animation.Msg -> MoveState msg -> ( MoveState msg, Cmd msg )
moveAnimate animMsg state =
    let
        ( newStyle, cmd ) =
            Animation.Messenger.update animMsg state.style
    in
    ( { state | style = newStyle }, cmd )


{-| The `Sub` for every live item's move animation.
-}
moveSubscription : (Animation.Msg -> msg2) -> List (MoveState msg) -> Sub msg2
moveSubscription toMsg states =
    Animation.subscription toMsg (List.map .style states)



-- REORDERING A LIST


{-| Moves the item identified by `idOf`/`id` one slot earlier/later in
`items` -- `offset` is always +-1 (adjacent swap, from a pair of move
buttons) -- a no-op if that would walk off either end. Shared by every
reorderable list (Accounts, Servers, Starred, ...).
-}
moveListItemBy : (a -> String) -> Int -> String -> List a -> List a
moveListItemBy idOf offset id items =
    case indexOfListItem idOf id items of
        Nothing ->
            items

        Just i ->
            let
                j : Int
                j =
                    i + offset

                elementAt : Int -> Maybe a
                elementAt idx =
                    List.drop idx items |> List.head
            in
            if j < 0 || j >= List.length items then
                items

            else
                case ( elementAt i, elementAt j ) of
                    ( Just ai, Just aj ) ->
                        List.indexedMap
                            (\idx item ->
                                if idx == i then
                                    aj

                                else if idx == j then
                                    ai

                                else
                                    item
                            )
                            items

                    _ ->
                        items


indexOfListItem : (a -> String) -> String -> List a -> Maybe Int
indexOfListItem idOf id items =
    items
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, item ) -> idOf item == id)
        |> List.head
        |> Maybe.map Tuple.first


{-| Kicks off a reorder move: measures the current (pre-swap) position of the
item at `id` and its `offset` neighbor (the "First" of FLIP) before touching
the list at all, via `toMsg` -- so the resulting message has something to
compare the post-swap position against (see `applyReorder`). A no-op (no
neighbor in that direction) just does nothing.
-}
beginReorder :
    (a -> String)
    -> (String -> String)
    -> (String -> String -> Int -> Result Dom.Error ( Dom.Element, Dom.Element ) -> msg)
    -> Int
    -> String
    -> List a
    -> Cmd msg
beginReorder idOf domId toMsg offset id items =
    case indexOfListItem idOf id items of
        Nothing ->
            Cmd.none

        Just i ->
            case List.drop (i + offset) items |> List.head of
                Nothing ->
                    Cmd.none

                Just neighbor ->
                    let
                        neighborId : String
                        neighborId =
                            idOf neighbor
                    in
                    Task.attempt (toMsg id neighborId offset)
                        (Task.map2 Tuple.pair
                            (Dom.getElement (domId id))
                            (Dom.getElement (domId neighborId))
                        )


{-| Applies a just-measured pre-swap pair (see `beginReorder`) to
`animations`: computes both items' slide deltas (`swapDeltas`) and
starts/restarts each one's `MoveState`. `onSettled` builds each item's
settle-notification `msg` (see `startMove`) from its key.
-}
applyReorder :
    Axis
    -> (String -> msg)
    -> String
    -> String
    -> Dom.Element
    -> Dom.Element
    -> Dict String (MoveState msg)
    -> Dict String (MoveState msg)
applyReorder axis onSettled id neighborId movedEl neighborEl animations =
    let
        ( movedDelta, neighborDelta ) =
            swapDeltas axis movedEl neighborEl

        startOrRestart : String -> ( Float, Float ) -> Dict String (MoveState msg) -> Dict String (MoveState msg)
        startOrRestart key delta anims =
            Dict.insert key (startMove (onSettled key) delta (Dict.get key anims |> Maybe.withDefault atRest)) anims
    in
    animations
        |> startOrRestart id movedDelta
        |> startOrRestart neighborId neighborDelta


{-| A measured element's position/size (page coordinates, matching
`Browser.Dom.Element.element`'s own convention) -- the "First"/"Last"
measurement step of FLIP for an arbitrary (non-adjacent-swap) reorder, e.g.
`Shared.StarredPanel`'s "Group" button. Deliberately not `Browser.Dom.Element`
itself, same reasoning as `measureElementsCmd`'s own doc: this is what
`Ports.measureElements` returns instead.
-}
type alias Rect =
    { x : Float
    , y : Float
    , width : Float
    , height : Float
    }


{-| Decodes `Ports.elementsMeasured`'s payload -- keyed by each entry's own
`key` field (see that port's own doc comment), for `measureElementsCmd`
callers to run in their `elementsMeasured` subscription handler.
-}
rectsDecoder : Decode.Decoder (Dict String Rect)
rectsDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.map4 Rect
            (Decode.field "x" Decode.float)
            (Decode.field "y" Decode.float)
            (Decode.field "width" Decode.float)
            (Decode.field "height" Decode.float)
        )
        |> Decode.list
        |> Decode.map Dict.fromList


{-| Fires `Ports.measureElements` for every one of `keys`, sending each as a
`{ key, id }` pair (`id` via caller-supplied `domId`) so `rectsDecoder`'s
result comes back keyed the same way `keys` itself already is.

A single measured `Browser.Dom.getElement` call (as `beginReorder` above
uses) is enough for an adjacent two-item swap, since the post-swap position
of each is derivable analytically from just their pre-swap rects
(`swapDeltas`) -- no second DOM read needed. An arbitrary reorder (e.g. more
than two items changing position at once) has no such shortcut: it needs a
real "measure before, apply the reorder, measure after" round trip. And that
round trip can't go through `Browser.Dom.getElement` either -- elm/browser's
kernel wraps _every single call_ in its own `requestAnimationFrame`, and
`Task`s compose strictly sequentially, so measuring N elements via
`Task.sequence` over N separate `Dom.getElement` calls costs N whole
animation frames (a highly visible multi-hundred-millisecond gap, confirmed
by instrumenting a real transition in `Components.Pages.EventsPage`, the
first caller that needed this). A single port round-trip measures every
requested id in one JS turn instead, costing the same one turn regardless of
how many ids are given.

Callers still owe one deliberate `requestAnimationFrame` wait (e.g. a
throwaway `Task.attempt (\\_ -> ...) Browser.Dom.getViewport`) between
applying the reorder and firing the second `measureElementsCmd` -- Elm's own
`Browser.application` runtime defers painting a model change to the _next_
rAF rather than doing it synchronously when `update` returns, so measuring
immediately would race ahead of the DOM actually reflecting the new order
yet, silently measuring the _old_ layout twice and animating a zero delta.
See `Components.Pages.EventsPage`'s `DisplayModeChanged`/`GotMeasuredRects`/
`ReadyToMeasureNew` for the full recipe this mirrors.

-}
measureElementsCmd : (String -> String) -> List String -> Cmd msg
measureElementsCmd domId keys =
    keys
        |> Encode.list
            (\key ->
                Encode.object
                    [ ( "key", Encode.string key )
                    , ( "id", Encode.string (domId key) )
                    ]
            )
        |> Ports.measureElements



-- REORDER BUTTONS


{-| One circular move-backward/move-forward pair, shared by every reorderable
list's controls -- glyph/title implied by `axis`. Returns the two buttons
separately (rather than assembling them into one container) since callers
arrange the pair differently: `reorderButtons` below stacks them into one
`.reorder-buttons` element for a vertical list; `UI.serverChip` instead splits
them to either side of a horizontal list's item content. Takes the click
`Attribute` itself (rather than a bare `msg`) so a caller whose pair sits
_inside_ some other clickable element can pass `stopPropagationOn "click" ...`
instead of a plain `onClick`, so tapping an arrow doesn't also trigger that.
-}
reorderButtonPair :
    Axis
    -> { moveBackward : Attribute msg, moveForward : Attribute msg, canMoveBackward : Bool, canMoveForward : Bool }
    -> { backward : Html msg, forward : Html msg }
reorderButtonPair axis { moveBackward, moveForward, canMoveBackward, canMoveForward } =
    let
        ( ( backwardGlyph, backwardTitle ), ( forwardGlyph, forwardTitle ) ) =
            case axis of
                Vertical ->
                    ( ( "▲", "Move up" ), ( "▼", "Move down" ) )

                Horizontal ->
                    ( ( "◀", "Move left" ), ( "▶", "Move right" ) )
    in
    { backward =
        button [ class "reorder-btn", moveBackward, disabled (not canMoveBackward), title backwardTitle ] [ text backwardGlyph ]
    , forward =
        button [ class "reorder-btn", moveForward, disabled (not canMoveForward), title forwardTitle ] [ text forwardGlyph ]
    }


{-| Stacked ▲/▼ pair for a `Vertical` list (Accounts, Starred), just
left of that row's own content.
-}
reorderButtons : { moveUp : msg, moveDown : msg, canMoveUp : Bool, canMoveDown : Bool } -> Html msg
reorderButtons { moveUp, moveDown, canMoveUp, canMoveDown } =
    let
        pair : { backward : Html msg, forward : Html msg }
        pair =
            reorderButtonPair Vertical
                { moveBackward = onClick moveUp
                , moveForward = onClick moveDown
                , canMoveBackward = canMoveUp
                , canMoveForward = canMoveDown
                }
    in
    div [ class "reorder-buttons" ] [ pair.backward, pair.forward ]
