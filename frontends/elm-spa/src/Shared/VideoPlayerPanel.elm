module Shared.VideoPlayerPanel exposing
    ( MiniVideo
    , Model
    , Msg(..)
    , Report
    , decoder
    , init
    , reportDecoder
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

The panel renders its own `<rellm-video>` playing if the page's was: the player takes over with `data-miniplayer-panel`
(no miniplayer button of its own), `data-start-at` and `data-resume`. It is one element that `public/rellm-video.js`
moves: in a corner of the window, or -- when a view puts a `[data-video-stage]` placeholder on screen -- exactly over that
placeholder, gliding between the two. The stages are the expanded player (`Shared.AudioPlayerPanel`, with the queue pane
beside it when that is open) and the media viewer, whose videos play here too (`Shared.viewerVideoSync`), so every video not
playing inline on a page or in My Media is controlled from this one player. In the corner it has a queue button, which is the audio bar's own (it expands the player, which has the queue; previous and
next are in the bar), a close button (top-right), and its own "open in the viewer" button beside fullscreen, which opens
`Shared.MediaViewerPanel` on this video. On a stage, CSS hides the queue and close buttons and the viewer button; the stage's
view has its own.

Streams (HLS, `.m3u8`) work the same way: `public/index.html` attaches hls.js to any `<video>` with such a `src`.

-}

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class, style)
import Html.Events exposing (on, onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Ports
import Shared.AudioPlayerPanel as AudioPlayerPanel


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
    , mediaId : Maybe String
    , host : String
    , downloads : List String
    }


{-| What the panel is showing.
-}
type alias Model =
    { video : Maybe MiniVideo
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
    | QueueClicked
      -- The corner player's close button: closes the queue's player (and so this).
    | CloseClicked
      -- The player's "open in the viewer" button: `Shared.update` opens `Shared.MediaViewerPanel` on this video.
    | EnlargeClicked
      -- The same player's "shrink to the miniplayer" button, which it has while it is in the media viewer: `Shared.update` closes the viewer.
    | ShrinkClicked
    | NoOp


init : Model
init =
    { video = Nothing }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Show video ->
            { model | video = Just video }

        Hide ->
            { model | video = Nothing }

        -- Everything else is the queue's business (`Shared.update`).
        _ ->
            model


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
    Decode.map8 MiniVideo
        (Decode.field "src" Decode.string |> Decode.andThen nonEmptySrc)
        (optional "poster")
        (optional "title")
        (Decode.field "time" Decode.float |> Decode.map (max 0))
        (Decode.field "playing" Decode.bool)
        (Decode.oneOf [ Decode.field "aspectRatio" Decode.float, Decode.succeed (16 / 9) ] |> Decode.map (clamp 0.4 3))
        (Decode.field "returnUrl" Decode.string)
        (optional "mediaId")
        |> Decode.map2 (|>) (optional "host" |> Decode.map (Maybe.withDefault ""))
        |> Decode.map2 (|>)
            (optional "downloads"
                |> Decode.map (Maybe.map (String.split "," >> List.filter ((/=) "")) >> Maybe.withDefault [])
            )


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
                [ ( video.src ++ "@" ++ String.fromFloat video.startAt, playerView video ) ]


playerView : MiniVideo -> Html Msg
playerView video =
    div [ class "video-player-panel-body" ]
        [ Html.node "rellm-video"
            (List.filterMap identity
                [ Just (class "media-renderer-video-frame video-player-panel-frame")
                , Just (attribute "data-media-size" "natural")
                , Just (attribute "data-miniplayer-panel" "")
                , Just (attribute "data-start-at" (String.fromFloat video.startAt))
                , Maybe.map (attribute "data-media-id") video.mediaId
                , Just (on "rellm-video-enlarge" (Decode.succeed EnlargeClicked))
                , Just (on "rellm-video-shrink" (Decode.succeed ShrinkClicked))
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

        -- The queue button (second row, left, under fullscreen: it expands the player, which has the queue and the rest of the controls -- previous/next are
        -- the bar's) and the close button (top-right); `public/rellm-video.js` draws the rest (fullscreen and "open in the viewer"
        -- top-left, volume under the close button). On a stage (the expanded player, the media viewer) CSS hides these two, since
        -- the stage's view has its own.
        , div [ class "video-player-panel-queue-controls" ]
            [ button
                [ class "audio-player-button video-player-panel-transport"
                , onClick QueueClicked
                , attribute "aria-label" "Show the queue"
                , attribute "title" "Queue"
                ]
                [ AudioPlayerPanel.queueIcon ]
            ]
        , button
            [ class "video-player-panel-close"
            , onClick CloseClicked
            , attribute "aria-label" "Close the player"
            , attribute "title" "Close"
            ]
            [ text "\u{2715}" ]
        ]
