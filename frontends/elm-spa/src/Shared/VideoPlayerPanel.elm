module Shared.VideoPlayerPanel exposing
    ( MiniVideo
    , Model
    , Msg(..)
    , Report
    , decoder
    , init
    , reportDecoder
    , setNavigation
    , subscriptions
    , update
    , view
    )

{-| The floating miniplayer: a video that carries on playing while you browse, like YouTube's. It lives in
`Shared.Model`, not on any page, so it survives navigation -- the page's own `<video>` is torn down with the
page, which is the whole reason this exists.

It's the *view* of the app's one queue (`Shared.AudioPlayerPanel`'s -- audio and video entries together): whenever the
queue's current entry is a video, `Shared.update` `Show`s it here, and hides this when it isn't. So a video gets here from
`<rellm-video>` (`public/rellm-video.js`) -- its miniplayer button, the `i` key, or a video someone was playing when its
page was navigated away from -- as a `Requested` (a `rellm-miniplayer` window event, forwarded by `public/index.html` over
`Ports.miniVideoRequested`; see `decoder`), which `Shared.update` turns into the queue's `OpenVideo`: the video becomes
the current entry and the existing queue follows it. Likewise the player's own events (`Ports.miniVideoState`, see
`reportDecoder`) go back to the queue -- its position for the bar, its end for "next".

The panel renders its own `<rellm-video>` at the same position, playing if the page's was: the player takes over with
`data-miniplayer-panel` (no miniplayer/enlarge buttons of its own), `data-start-at` and `data-resume`. Over it: close,
a back arrow (returns to the page the video was on and closes the miniplayer -- a real `<a href>` wouldn't do: Elm routes
its click to the app's URL handling, never to an `onClick`), and the queue's previous / next / show-queue buttons.

Streams (HLS, `.m3u8`) work the same way: `public/index.html` attaches hls.js to any `<video>` with such a `src`.

-}

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class, disabled, style)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Ports


{-| What the page's player hands over. `startAt` is in seconds; `resume` is whether it was playing; `returnUrl` is the
page it was on (the full URL); `aspectRatio` is width over height, so the panel is the video's own shape; `title` is
what the queue calls it.
-}
type alias MiniVideo =
    { src : String
    , poster : Maybe String
    , title : Maybe String
    , startAt : Float
    , resume : Bool
    , aspectRatio : Float
    , returnUrl : String
    }


{-| `hasPrevious`/`hasNext` mirror the queue (see `setNavigation`), for the buttons.
-}
type alias Model =
    { video : Maybe MiniVideo
    , hasPrevious : Bool
    , hasNext : Bool
    }


{-| What the miniplayer's video reports as it plays (`public/rellm-video.js`'s `rellm-miniplayer-state`).
-}
type alias Report =
    { playing : Bool
    , positionMs : Float
    , durationMs : Float
    , ended : Bool
    }


type Msg
    = -- A video someone chose to carry on in the miniplayer; `Shared.update` makes it the queue's current entry.
      Requested MiniVideo
      -- The queue's current entry is this video / isn't a video: shown / hidden (by `Shared.update`).
    | Show MiniVideo
    | Hide
    | Reported Report
    | PrevClicked
    | NextClicked
    | QueueClicked
      -- Close the miniplayer (and the queue's player with it), or go back to the page the video was on (`Shared.update`
      -- also navigates there, as it holds the navigation key).
    | Close
    | ExpandClicked
    | NoOp


init : Model
init =
    { video = Nothing, hasPrevious = False, hasNext = False }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Show video ->
            { model | video = Just video }

        Hide ->
            { model | video = Nothing }

        Close ->
            { model | video = Nothing }

        ExpandClicked ->
            { model | video = Nothing }

        -- Everything else is the queue's business (`Shared.update`).
        _ ->
            model


{-| Whether the queue has an entry before/after the current one.
-}
setNavigation : { hasPrevious : Bool, hasNext : Bool } -> Model -> Model
setNavigation navigation model =
    { model | hasPrevious = navigation.hasPrevious, hasNext = navigation.hasNext }


subscriptions : Sub Msg
subscriptions =
    Sub.batch
        [ Ports.miniVideoRequested
            (\value ->
                case Decode.decodeValue decoder value of
                    Ok video ->
                        Requested video

                    Err _ ->
                        NoOp
            )
        , Ports.miniVideoState
            (\value ->
                case Decode.decodeValue reportDecoder value of
                    Ok report ->
                        Reported report

                    Err _ ->
                        NoOp
            )
        ]


{-| The `detail` of `public/rellm-video.js`'s `rellm-miniplayer` event. An empty `src` is no video at all, and the shape is
kept within what a corner of the screen can sensibly show (a stream that hasn't reported its size yet is 16:9).
-}
decoder : Decoder MiniVideo
decoder =
    Decode.map7 MiniVideo
        (Decode.field "src" Decode.string |> Decode.andThen nonEmptySrc)
        (optional "poster")
        (optional "title")
        (Decode.field "time" Decode.float |> Decode.map (max 0))
        (Decode.field "playing" Decode.bool)
        (Decode.oneOf [ Decode.field "aspectRatio" Decode.float, Decode.succeed (16 / 9) ] |> Decode.map (clamp 0.4 3))
        (Decode.field "returnUrl" Decode.string)


{-| A string field that may be null or missing, and means nothing when blank.
-}
optional : String -> Decoder (Maybe String)
optional name =
    Decode.oneOf [ Decode.field name (Decode.nullable Decode.string), Decode.succeed Nothing ]
        |> Decode.map (Maybe.andThen (\value -> if String.isEmpty (String.trim value) then Nothing else Just value))


nonEmptySrc : String -> Decoder String
nonEmptySrc src =
    if String.isEmpty (String.trim src) then
        Decode.fail "no video src"

    else
        Decode.succeed src


{-| The `detail` of `public/rellm-video.js`'s `rellm-miniplayer-state` event.
-}
reportDecoder : Decoder Report
reportDecoder =
    Decode.map4 Report
        (Decode.field "playing" Decode.bool)
        (Decode.field "positionMs" Decode.float |> Decode.map (max 0))
        (Decode.field "durationMs" Decode.float |> Decode.map (\ms -> if isNaN ms || isInfinite ms then 0 else max 0 ms))
        (Decode.field "ended" Decode.bool)


view : Model -> Html Msg
view model =
    case model.video of
        Nothing ->
            text ""

        Just video ->
            -- Keyed by what's being shown, so handing over a different video (or the same one again, at another
            -- position) starts a fresh player rather than patching the old one's `<video>`.
            Html.Keyed.node "div"
                [ class "video-player-panel"
                , style "--video-ratio" (String.fromFloat video.aspectRatio)
                ]
                [ ( video.src ++ "@" ++ String.fromFloat video.startAt, playerView model video ) ]


playerView : Model -> MiniVideo -> Html Msg
playerView model video =
    div
        [ class "video-player-panel-body"
        , style "aspect-ratio" (String.fromFloat video.aspectRatio)
        ]
        [ Html.node "rellm-video"
            (List.filterMap identity
                [ Just (class "media-renderer-video-frame video-player-panel-frame")
                , Just (attribute "data-media-size" "natural")
                , Just (attribute "data-miniplayer-panel" "")
                , Just (attribute "data-start-at" (String.fromFloat video.startAt))
                , if video.resume then
                    Just (attribute "data-resume" "")

                  else
                    Nothing
                ]
            )
            [ Html.video
                (List.filterMap identity
                    [ Just (class "media-renderer-video video-player-panel-video")
                    , Just (attribute "src" video.src)
                    , Just (attribute "preload" "auto")
                    , Just (attribute "playsinline" "true")
                    , Maybe.map (attribute "poster") video.poster
                    ]
                )
                []
            ]
        , button
            [ class "video-player-panel-button video-player-panel-expand"
            , onClick ExpandClicked
            , attribute "aria-label" "Back to the page"
            , attribute "title" "Back to the page"
            ]
            [ text "\u{2190}" ]
        , button
            [ class "video-player-panel-button video-player-panel-close"
            , onClick Close
            , attribute "aria-label" "Close miniplayer"
            , attribute "title" "Close miniplayer"
            ]
            [ text "\u{2715}" ]
        , div [ class "video-player-panel-queue-controls" ]
            [ button
                [ class "video-player-panel-button"
                , onClick PrevClicked
                , disabled (not model.hasPrevious)
                , attribute "aria-label" "Previous in the queue"
                , attribute "title" "Previous"
                ]
                [ text "\u{00AB}" ]
            , button
                [ class "video-player-panel-button"
                , onClick NextClicked
                , disabled (not model.hasNext)
                , attribute "aria-label" "Next in the queue"
                , attribute "title" "Next"
                ]
                [ text "\u{00BB}" ]
            , button
                [ class "video-player-panel-button"
                , onClick QueueClicked
                , attribute "aria-label" "Show the queue"
                , attribute "title" "Queue"
                ]
                [ text "\u{2630}" ]
            ]
        ]
