module UI.Drag exposing
    ( Config
    , Msg
    , Output(..)
    , State
    , applySlides
    , handleAttrs
    , init
    , isDragging
    , onClick
    , onClickStoppingPropagation
    , overlay
    , reorderByKeys
    , slotRange
    , subscriptions
    , targetOrder
    , update
    )

{-| Touch/mouse drag-to-reorder for the reorder-arrow areas of `UI.Flip`'s reorderable lists
(Starred posts, Accounts, Servers, custom nav tabs, federated/Mastodon server editors). Press and drag
on a list item's ▲/▼ (or ◀/▶) arrows to carry it to any slot -- however many positions away -- while a
plain tap on an arrow still moves the item one slot, same as before.


## How a list uses it

1.  Keep a `UI.Drag.State` in the list's model, plus a `Msg` wrapper (`DragMsg UI.Drag.Msg`) that
    routes to `update`. Pass `subscriptions` through too.
2.  Add `handleAttrs` to each arrow button (or a wrapper around the arrow pair), and render `overlay`
    once somewhere in the list's view.
3.  Build a `Config` from the list's current order on every `update` call, and apply each `Output`:
    `Reordered` (the new key order -- write it to wherever the order really lives, and persist) then
    `Slide` (per-item FLIP offsets -- feed to `applySlides`, using the list's own `MoveState` dict, the
    same one the tap-an-arrow path fills via `UI.Flip.applyReorder`).
4.  Wrap each arrow's click with `onClick`, so the tap a browser may send at the end of a drag is dropped.


## How it works

Pointer events (not mouse/touch events) drive everything -- touch drags need the handle to have
`touch-action: none` (see `drag.css`), and a touch's events keep targeting the element it started on,
while a _mouse_ drag quickly leaves the small handle, so `overlay` (a transparent full-screen catcher,
only mounted while a drag is live) takes over receiving its events.

Every pointer move that arrives while no measurement is in flight measures every item (one
`Ports.measureElements` round trip), decides which slot the pointer is over (`targetOrder`), and if
that differs from the current order emits `Reordered`, waits one frame for the DOM to catch up, measures
again, and emits `Slide`s (old visible position vs. new layout position) -- the same measure/reorder/
measure FLIP recipe `UI.Flip.measureElementsCmd` documents. It never waits for earlier slides to
finish: a row's _layout_ position (`layoutX`/`layoutY` in the measurement -- its measured position with
any in-flight FLIP translate taken back out) decides where the pointer lands, and the new slide starts
from where the row visibly is, so a fresh jump interrupts a running one cleanly.

The list is assumed to run along one axis (a single column, or a single row of chips) -- the pointer is
only compared along `Config.axis`.

-}

import Browser.Dom as Dom
import Dict exposing (Dict)
import Html exposing (Attribute, Html, div)
import Html.Attributes exposing (class)
import Html.Events
import Json.Decode as Decode
import Ports
import Process
import Task
import UI.Flip exposing (Axis(..), MoveState)


{-| A drag in progress, plus the bookkeeping for its measurement round trips.
-}
type alias State =
    { press : Maybe Press
    , phase : Phase
    , suppressClick : Bool

    -- The pointer coordinates (`( low, high ]`) over which the dragged item's target slot is known to
    -- be where it already is -- so a pointer held (or wiggled) inside it needs no measuring at all.
    -- See `slotRange`; `Nothing` until measured, and again while a reorder's layout is in flux.
    , slot : Maybe ( Float, Float )
    }


{-| `pointer` is the pointer's latest page coordinate along the list's axis (`pageY` for `Vertical`,
`pageX` for `Horizontal` -- the same coordinate space `Ports.measureElements` reports in). `active`
turns on once it's moved a few pixels from `start`, so a plain tap on an arrow is just a click.
-}
type alias Press =
    { key : String
    , start : Float
    , pointer : Float
    , active : Bool
    }


type Phase
    = Idle
      -- Every item's current position is in flight; carries the dragged key and pointer position the
      -- request was made for.
    | AwaitingCurrentRects String Float
      -- The reorder has been emitted; waiting out one frame, then for the "after" measurement.
      -- Carries the visible ("before") rects.
    | AwaitingNewRects (Dict String UI.Flip.Rect)


init : State
init =
    { press = Nothing, phase = Idle, suppressClick = False, slot = Nothing }


type Msg
    = PointerDown String Float
    | PointerMoved Float
    | PointerEnded
    | ClearClickGuard
    | GotMeasured Decode.Value
    | ReadyToMeasureNew


{-| What the list should do with a drag's result -- in this order within one `update` call.
-}
type Output
    = -- The full new order of `Config.keys`; write it back (and persist).
      Reordered (List String)
      -- Per-key `( dx, dy )` FLIP "invert" offsets (see `UI.Flip.startMove`); feed to `applySlides`.
    | Slide (Dict String ( Float, Float ))


{-| Everything `update` needs to know about the list _right now_ -- rebuild it from the model on
every call.

  - `axis`: which way the list runs.
  - `owner`: a name unique to this list, tagging its measurements (see `UI.Flip.measure`).
  - `domId`: the DOM id an item (by key) is rendered with -- the same one a tap-to-move uses.
  - `keys`: every item, in current display order.
  - `groupOf`: items only ever move among others with the same group id (e.g. the pinned main server
    gets its own, so nothing can be dragged past it); `\_ -> ""` for one free-for-all list.

-}
type alias Config =
    { axis : Axis
    , owner : String
    , domId : String -> String
    , keys : List String
    , groupOf : String -> String
    }


measureOwner : Config -> String
measureOwner config =
    "drag:" ++ config.owner


{-| `Sub` for the measurement replies -- only while one is expected.
-}
subscriptions : State -> Sub Msg
subscriptions state =
    case state.phase of
        Idle ->
            Sub.none

        _ ->
            Ports.elementsMeasured GotMeasured


update : Config -> Msg -> State -> ( State, Cmd Msg, List Output )
update config msg state =
    case msg of
        PointerDown key coordinate ->
            ( { state | press = Just { key = key, start = coordinate, pointer = coordinate, active = False }, slot = Nothing }
            , Cmd.none
            , []
            )

        PointerMoved coordinate ->
            case state.press of
                Nothing ->
                    ( state, Cmd.none, [] )

                Just press ->
                    let
                        moved : State
                        moved =
                            { state
                                | press =
                                    Just
                                        { press
                                            | pointer = coordinate
                                            , active = press.active || abs (coordinate - press.start) > 4
                                        }
                            }

                        ( checked, cmd ) =
                            checkPointer config moved
                    in
                    ( checked, cmd, [] )

        PointerEnded ->
            case state.press of
                Just { active } ->
                    if active then
                        -- The browser's `click` (if any) follows the pointer-up right away; `onClick` drops it.
                        ( { state | press = Nothing, suppressClick = True }
                        , Process.sleep 100 |> Task.perform (\_ -> ClearClickGuard)
                        , []
                        )

                    else
                        ( { state | press = Nothing }, Cmd.none, [] )

                Nothing ->
                    ( state, Cmd.none, [] )

        ClearClickGuard ->
            ( { state | suppressClick = False }, Cmd.none, [] )

        ReadyToMeasureNew ->
            case state.phase of
                AwaitingNewRects oldRects ->
                    ( state
                    , UI.Flip.measureElementsCmd (measureOwner config) config.domId (Dict.keys oldRects)
                    , []
                    )

                _ ->
                    ( state, Cmd.none, [] )

        GotMeasured value ->
            case UI.Flip.measuredResults (measureOwner config) value of
                Nothing ->
                    -- Some other component's measurement.
                    ( state, Cmd.none, [] )

                Just results ->
                    case ( Decode.decodeValue UI.Flip.rectsDecoder results, state.phase ) of
                        ( Ok rects, AwaitingCurrentRects key pointer ) ->
                            let
                                newKeys : List String
                                newKeys =
                                    if state.press == Nothing then
                                        config.keys

                                    else
                                        let
                                            layouts : Dict String Float
                                            layouts =
                                                layoutPositions config.axis results
                                        in
                                        targetOrder config.axis config.groupOf key pointer rects layouts config.keys
                            in
                            if newKeys == config.keys then
                                -- Nothing to do until the pointer leaves this slot -- and not measuring
                                -- again meanwhile is what keeps a held drag (and the slide it may still be
                                -- running) smooth, however long it lingers.
                                let
                                    ( checked, cmd ) =
                                        checkPointer config
                                            { state
                                                | phase = Idle
                                                , slot = Just (slotRange config.axis config.groupOf key pointer rects (layoutPositions config.axis results) config.keys)
                                            }
                                in
                                ( checked, cmd, [] )

                            else
                                ( { state | phase = AwaitingNewRects rects, slot = Nothing }
                                , Task.attempt (\_ -> ReadyToMeasureNew) Dom.getViewport
                                , [ Reordered newKeys ]
                                )

                        ( Ok newRects, AwaitingNewRects oldRects ) ->
                            let
                                layouts : Dict String Float
                                layouts =
                                    layoutPositions config.axis results

                                slides : Dict String ( Float, Float )
                                slides =
                                    Dict.foldl
                                        (\key oldRect acc ->
                                            case Dict.get key newRects of
                                                Just newRect ->
                                                    let
                                                        ( newX, newY ) =
                                                            case config.axis of
                                                                Vertical ->
                                                                    ( newRect.x, Dict.get key layouts |> Maybe.withDefault newRect.y )

                                                                Horizontal ->
                                                                    ( Dict.get key layouts |> Maybe.withDefault newRect.x, newRect.y )
                                                    in
                                                    Dict.insert key ( oldRect.x - newX, oldRect.y - newY ) acc

                                                Nothing ->
                                                    acc
                                        )
                                        Dict.empty
                                        oldRects

                                -- The item's new slot, in the new layout.
                                slot : Maybe ( Float, Float )
                                slot =
                                    state.press
                                        |> Maybe.map (\press -> slotRange config.axis config.groupOf press.key press.pointer newRects layouts config.keys)

                                -- A held drag may owe another jump by now (moves that left the old slot
                                -- mid-round-trip were dropped).
                                ( checked, cmd ) =
                                    checkPointer config { state | phase = Idle, slot = slot }
                            in
                            ( checked, cmd, [ Slide slides ] )

                        ( Err _, _ ) ->
                            ( { state | phase = Idle }, Cmd.none, [] )

                        _ ->
                            -- A stray result with nothing pending.
                            ( state, Cmd.none, [] )


{-| Kicks off the "where's the pointer?" measurement if a drag is live and nothing's already measuring.
-}
checkPointer : Config -> State -> ( State, Cmd Msg )
checkPointer config state =
    case ( state.press, state.phase ) of
        ( Just press, Idle ) ->
            if press.active && not (inSlot state press.pointer) then
                ( { state | phase = AwaitingCurrentRects press.key press.pointer }
                , UI.Flip.measureElementsCmd (measureOwner config) config.domId config.keys
                )

            else
                ( state, Cmd.none )

        _ ->
            ( state, Cmd.none )


inSlot : State -> Float -> Bool
inSlot state coordinate =
    case state.slot of
        Just ( low, high ) ->
            coordinate > low && coordinate <= high

        Nothing ->
            False


{-| Each measured item's transform-free position along `axis` (`layoutY`/`layoutX` in
`Ports.measureElements`' results -- measured position minus any in-flight FLIP translate), keyed like
`rectsDecoder`'s.
-}
layoutPositions : Axis -> Decode.Value -> Dict String Float
layoutPositions axis results =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.field
            (case axis of
                Vertical ->
                    "layoutY"

                Horizontal ->
                    "layoutX"
            )
            Decode.float
        )
        |> Decode.list
        |> Decode.map Dict.fromList
        |> (\decoder -> Decode.decodeValue decoder results)
        |> Result.withDefault Dict.empty


{-| `keys` with `key` moved to wherever `pointer` falls among the other items of its own `groupOf` group
(compared against each one's midpoint along `axis`; `layouts` -- if it has an entry for an item --
overrides that item's measured position, so an item mid-slide counts as sitting where it's headed).
Items of other groups never move; the group's items just get reshuffled among the slots the group already
occupies.
-}
targetOrder : Axis -> (String -> String) -> String -> Float -> Dict String UI.Flip.Rect -> Dict String Float -> List String -> List String
targetOrder axis groupOf key pointer rects layouts keys =
    let
        group : String
        group =
            groupOf key

        groupKeys : List String
        groupKeys =
            List.filter (\k -> groupOf k == group) keys
    in
    if not (List.member key groupKeys) then
        keys

    else
        let
            others : List String
            others =
                List.filter ((/=) key) groupKeys

            passed : Int
            passed =
                others
                    |> List.filter (\other -> midpointOf axis rects layouts other |> Maybe.map (\mid -> mid < pointer) |> Maybe.withDefault False)
                    |> List.length

            newGroupOrder : List String
            newGroupOrder =
                List.take passed others ++ key :: List.drop passed others
        in
        -- Write the group's new order back into the slots the group occupied.
        List.foldl
            (\k ( remaining, acc ) ->
                if groupOf k == group then
                    case remaining of
                        next :: rest ->
                            ( rest, next :: acc )

                        [] ->
                            ( [], k :: acc )

                else
                    ( remaining, k :: acc )
            )
            ( newGroupOrder, [] )
            keys
            |> Tuple.second
            |> List.reverse


midpointOf : Axis -> Dict String UI.Flip.Rect -> Dict String Float -> String -> Maybe Float
midpointOf axis rects layouts key =
    Dict.get key rects
        |> Maybe.map
            (\rect ->
                case axis of
                    Vertical ->
                        (Dict.get key layouts |> Maybe.withDefault rect.y) + rect.height / 2

                    Horizontal ->
                        (Dict.get key layouts |> Maybe.withDefault rect.x) + rect.width / 2
            )


{-| The pointer coordinates `( low, high ]` that `targetOrder` would keep `key`'s slot the same for:
between the midpoints of the group neighbors it currently sits between (open-ended at either end of
the group). Lets a held drag skip all measuring while the pointer stays inside it.
-}
slotRange : Axis -> (String -> String) -> String -> Float -> Dict String UI.Flip.Rect -> Dict String Float -> List String -> ( Float, Float )
slotRange axis groupOf key pointer rects layouts keys =
    let
        group : String
        group =
            groupOf key

        midpoints : List Float
        midpoints =
            keys
                |> List.filter (\k -> k /= key && groupOf k == group)
                |> List.filterMap (midpointOf axis rects layouts)
                |> List.sort

        passed : Int
        passed =
            midpoints |> List.filter (\mid -> mid < pointer) |> List.length
    in
    ( if passed == 0 then
        -(1 / 0)

      else
        List.drop (passed - 1) midpoints |> List.head |> Maybe.withDefault -(1 / 0)
    , List.drop passed midpoints |> List.head |> Maybe.withDefault (1 / 0)
    )


{-| `items` sorted into `order` (by `keyOf`); items `order` doesn't mention keep their relative order,
after the rest.
-}
reorderByKeys : (a -> String) -> List String -> List a -> List a
reorderByKeys keyOf order items =
    let
        rank : Dict String Int
        rank =
            order |> List.indexedMap (\i k -> ( k, i )) |> Dict.fromList
    in
    List.sortBy (\item -> Dict.get (keyOf item) rank |> Maybe.withDefault (List.length order)) items


{-| Starts (or interrupts and restarts) each `Slide`'s FLIP animation -- `settled` is the same
settle-notification `msg` builder `UI.Flip.applyReorder` takes.
-}
applySlides : (String -> msg) -> Dict String ( Float, Float ) -> Dict String (MoveState msg) -> Dict String (MoveState msg)
applySlides settled slides animations =
    Dict.foldl
        (\key delta acc ->
            Dict.insert key (UI.Flip.startMove (settled key) delta (Dict.get key acc |> Maybe.withDefault UI.Flip.atRest)) acc
        )
        animations
        slides


{-| Is `key` the item being carried right now (past the tap threshold)? For a "lifted" row style.
-}
isDragging : State -> String -> Bool
isDragging state key =
    case state.press of
        Just press ->
            press.active && press.key == key

        Nothing ->
            False


{-| Pointer handlers making an element -- an arrow button, or a wrapper around an arrow pair -- a drag
handle for `key`. Pointerdown starts the press, move/up/cancel carry it on (a touch's events keep
targeting its starting element; `overlay` covers a mouse's once the drag is under way). Doesn't prevent
default, so a tap still clicks.
-}
handleAttrs : (Msg -> msg) -> Axis -> String -> State -> List (Attribute msg)
handleAttrs toMsg axis key state =
    class "drag-handle"
        :: Html.Events.on "pointerdown"
            (Decode.map2 Tuple.pair (Decode.field "isPrimary" Decode.bool) (Decode.field "button" Decode.int)
                |> Decode.andThen
                    (\( primary, button ) ->
                        if primary && button == 0 then
                            Decode.map (PointerDown key >> toMsg) (pointerCoordinate axis)

                        else
                            Decode.fail "not a primary press"
                    )
            )
        :: pointerAttrs toMsg axis state


{-| Always attached (not only once a press is under way): a fast drag can leave a small arrow before
the re-render that would attach them lands. `buttons > 0` keeps plain hovering from sending messages,
and a move that stays inside the item's current slot (`State.slot`) sends none either, so a drag
lingering in place costs `update` nothing. `update` ignores moves with no press.
-}
pointerAttrs : (Msg -> msg) -> Axis -> State -> List (Attribute msg)
pointerAttrs toMsg axis state =
    [ Html.Events.on "pointermove"
        (Decode.field "buttons" Decode.int
            |> Decode.andThen
                (\buttons ->
                    if buttons > 0 then
                        pointerCoordinate axis
                            |> Decode.andThen
                                (\coordinate ->
                                    if inSlot state coordinate then
                                        -- Still over the slot the item's already in: nothing for `update` to do.
                                        Decode.fail "same slot"

                                    else
                                        Decode.succeed (toMsg (PointerMoved coordinate))
                                )

                    else
                        Decode.fail "not pressed"
                )
        )
    , Html.Events.on "pointerup" (Decode.succeed (toMsg PointerEnded))
    , Html.Events.on "pointercancel" (Decode.succeed (toMsg PointerEnded))
    ]


pointerCoordinate : Axis -> Decode.Decoder Float
pointerCoordinate axis =
    case axis of
        Vertical ->
            Decode.field "pageY" Decode.float

        Horizontal ->
            Decode.field "pageX" Decode.float


{-| Full-screen transparent catcher, mounted only while a drag is live (past the tap threshold), so a
mouse drag keeps receiving pointer events wherever it goes. See `handleAttrs`.
-}
overlay : (Msg -> msg) -> Axis -> State -> List (Html msg)
overlay toMsg axis state =
    case state.press of
        Just { active } ->
            if active then
                [ div (class "drag-overlay" :: pointerAttrs toMsg axis state) [] ]

            else
                []

        Nothing ->
            []


{-| A click handler (for an arrow's tap-to-move) that stays silent for the click a browser can send
right after a drag ends -- use it in place of `Html.Events.onClick`/an equivalent `stopPropagationOn`
decoder where the arrow's `msg` is built.
-}
onClick : State -> msg -> Attribute msg
onClick state msg =
    Html.Events.on "click"
        (if state.suppressClick then
            Decode.fail "just dragged"

         else
            Decode.succeed msg
        )


{-| `onClick`, but also stops the click from bubbling -- for an arrow that sits inside some other
clickable element (a server chip's own "select this" target), so tapping it doesn't also trigger that.
-}
onClickStoppingPropagation : State -> msg -> Attribute msg
onClickStoppingPropagation state msg =
    Html.Events.stopPropagationOn "click"
        (if state.suppressClick then
            Decode.fail "just dragged"

         else
            Decode.succeed ( msg, True )
        )
