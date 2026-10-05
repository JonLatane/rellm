module Shared.AudioPlayerPanel exposing (Model, Msg(..), currentMedia, init, subscriptions, update, view)

{-| A persistent, app-wide audio player -- the companion to `Shared.MediaViewerPanel`. Where the viewer is a
fullscreen, view-blocking carousel (with editing), this is a "now playing" bar docked to the bottom of the
page that keeps playing across route changes: prev / play-pause / next on the left, the track's waveform
(click to seek, with a progress tint) in the middle, and an expand arrow on the right. Expanded, it grows up
to 60% of the viewport height and shows the cover art (or a placeholder), title and artist -- plus an Edit button for the
item's owner/an Admin, which hands off to `Shared.MediaViewerPanel`'s own editor (see `Shared.update`).

Audio only for now (see `Components.MediaFeed`'s `MediaClicked`, the only opener). The one real `<audio>`
element lives in `view` and is never unmounted, so playback survives navigation and autoplay permission
granted by the first tap carries over to every later track; its events feed `TimeUpdated`/
`PlayStateChanged`/`Ended`, and imperative commands (toggle, seek) go out through `Ports.controlAudioPlayer`.
The neighboring tracks of the queue are fetched ahead of time with hidden `preload` elements.

-}

import Components.MediaRenderer as MediaRenderer exposing (ResolutionTier(..))
import Components.Posts as Posts
import Browser.Events
import Html exposing (Html, audio, button, div, img, option, select, span, text)
import Html.Attributes exposing (alt, attribute, class, selected, src, style, value)
import Html.Events exposing (on, onClick, onInput, stopPropagationOn)
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Proto.Rellm exposing (MediaMetadata, MediaReference, defaultMediaMetadata)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.ByteFormat as ByteFormat
import Shared.Conversions exposing (int64ToInt)
import Shared.MediaViewerPanel as MediaViewerPanel
import UI.Classes exposing (classes, openClosedClass)


{-| Which stored copy of a track to stream -- the audio `small`/`medium`/`large` AAC tiers the conversion job
makes (see `convert_media`), or the untouched original. A tier a given track lacks (e.g. `High` for a file
whose own bitrate is already under 256 kbps) falls back to the original, same as the server does.
-}
type Quality
    = High
    | Medium
    | Low
    | OriginalQuality


{-| Two `<audio>` elements ("slots") take turns being the one that's playing. To change quality (or to
ratchet up after starting low) without losing the user's place, the *other* slot loads the target copy in
the background, seeks to the playback point and buffers ahead; once `public/index.html` reports it has
enough buffered there (`CandidateReady`), playback is handed over to it at the exact current position and
the old slot is released.
-}
type Slot
    = SlotA
    | SlotB


{-| What a slot has loaded: a track at a quality. `Nothing` slots are empty. `requireFull` marks a background
slot that may only take over once its copy is *completely* downloaded (the automatic start-low-then-upgrade
ratchet); without it (the user explicitly picked a quality), ~15s buffered at the playback point is enough.
-}
type alias Source =
    { mediaId : String, quality : Quality, requireFull : Bool }


type alias Model =
    { -- The tracks on the list the user started playback from, in display order.
      queue : List MediaReference
    , currentId : Maybe String

    -- Same convention as `Shared.MediaViewerPanel.Model.targetHost`: resolves to the `Server`/`Account`
    -- the queue's media belongs to.
    , targetHost : String
    , expanded : Bool

    -- Mirrors the `<audio>` element, via its events.
    , playing : Bool
    , positionMs : Float
    , durationMs : Float

    -- The quality the user wants (kept across tracks). Tracks *start* one tier lower than a `High`
    -- preference (smaller, faster to get going) and are upgraded in the background -- see `Slot`.
    , quality : Quality
    , activeSlot : Slot
    , slotA : Maybe Source
    , slotB : Maybe Source

    -- A freshly loaded track should start playing once its active slot can (`CanPlay`).
    , autoStart : Bool
    }


type Msg
    = -- queue, id to start playing, host
      Open (List MediaReference) String String
    | Next
    | Prev
    | TogglePlay
    | ToggleExpanded
    | Close
      -- 0..1 through the track
    | SeekToFraction Float
    | TimeUpdated Slot Float Float
    | PlayStateChanged Slot Bool
    | Ended Slot
    | CanPlay Slot
    | CandidateReady Slot
    | QualityChanged String
    | EditClicked
      -- Like `EditClicked`, but then goes straight to choosing the track's cover art (see `Shared.update`).
    | EditCoverArtClicked
    | NoOp


init : Model
init =
    { queue = [], currentId = Nothing, targetHost = "", expanded = False, playing = False, positionMs = 0, durationMs = 0, quality = High, activeSlot = SlotA, slotA = Nothing, slotB = Nothing, autoStart = False }


{-| The track being played, if any.
-}
currentMedia : Model -> Maybe MediaReference
currentMedia model =
    model.currentId
        |> Maybe.andThen (\id -> List.filter (\m -> m.id == id) model.queue |> List.head)


adjacent : Int -> Model -> Maybe MediaReference
adjacent offset model =
    model.queue
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, m ) -> Just m.id == model.currentId)
        |> List.head
        |> Maybe.map (\( i, _ ) -> i + offset)
        |> Maybe.andThen
            (\target ->
                if target < 0 then
                    Nothing

                else
                    model.queue |> List.drop target |> List.head
            )


has : MediaConversion -> MediaReference -> Bool
has conversion media =
    List.any (\size -> size.conversion == conversion) media.sizes


{-| What `quality` actually resolves to for `media`: the tier itself if the conversion job stored it, else the
original (which is also what the server falls back to).
-}
resolve : MediaReference -> Quality -> Quality
resolve media quality =
    let
        stored : MediaConversion -> Quality
        stored conversion =
            if has conversion media then
                quality

            else
                OriginalQuality
    in
    case quality of
        High ->
            stored MEDIACONVERSIONLARGE

        Medium ->
            stored MEDIACONVERSIONMEDIUM

        Low ->
            stored MEDIACONVERSIONSMALL

        OriginalQuality ->
            OriginalQuality


{-| Where playback of `media` begins for a `desired` preference: one tier below `High` (when the track has it),
else the desired quality itself.
-}
startQuality : MediaReference -> Quality -> Quality
startQuality media desired =
    case resolve media desired of
        High ->
            case resolve media Medium of
                OriginalQuality ->
                    High

                medium ->
                    medium

        other ->
            other


{-| The stream URL for `media` at `quality` (a tier the track lacks is served as the original by the server).
-}
urlFor : RellmServer -> Maybe RellmAccount -> MediaReference -> Quality -> String
urlFor server maybeAccount media quality =
    case quality of
        High ->
            MediaRenderer.url TierLarge server maybeAccount media

        Medium ->
            MediaRenderer.url TierMedium server maybeAccount media

        Low ->
            MediaRenderer.url TierSmall server maybeAccount media

        OriginalQuality ->
            MediaRenderer.authorizedUrl [ "size=original" ] server maybeAccount media


slotSource : Slot -> Model -> Maybe Source
slotSource slot model =
    case slot of
        SlotA ->
            model.slotA

        SlotB ->
            model.slotB


setSlot : Slot -> Maybe Source -> Model -> Model
setSlot slot source model =
    case slot of
        SlotA ->
            { model | slotA = source }

        SlotB ->
            { model | slotB = source }


otherSlot : Slot -> Slot
otherSlot slot =
    case slot of
        SlotA ->
            SlotB

        SlotB ->
            SlotA


slotName : Slot -> String
slotName slot =
    case slot of
        SlotA ->
            "a"

        SlotB ->
            "b"


{-| Starts `media`: the active slot loads it at `startQuality`, and, if that's below what's wanted, the other
slot starts loading the wanted quality right away to take over once it's buffered. (A slot is only
released -- `Cmd`ed to drop its media -- when it goes from loaded to empty.)
-}
beginTrack : MediaReference -> Model -> ( Model, Cmd Msg )
beginTrack media model =
    let
        wanted : Quality
        wanted =
            resolve media model.quality

        start : Quality
        start =
            startQuality media model.quality

        startSource : Source
        startSource =
            { mediaId = media.id, quality = start, requireFull = False }

        sameAsLoaded : Bool
        sameAsLoaded =
            slotSource model.activeSlot model == Just startSource

        withTrack : Model
        withTrack =
            { model | currentId = Just media.id, positionMs = 0, durationMs = 0, playing = True, autoStart = not sameAsLoaded }
                |> setSlot model.activeSlot (Just startSource)
                |> setSlot (otherSlot model.activeSlot)
                    (if wanted /= start then
                        Just { mediaId = media.id, quality = wanted, requireFull = True }

                     else
                        Nothing
                    )
    in
    ( withTrack
    , Cmd.batch
        [ releaseIfEmptied (otherSlot model.activeSlot) model withTrack
        , if sameAsLoaded then
            -- Already loaded (the same track chosen again): just restart it.
            Cmd.batch [ command "seek" (Just 0), command "play" Nothing ]

          else
            Cmd.none
        ]
    )


{-| Releases `slot`'s `<audio>` if `after` emptied it (it held something `before`).
-}
releaseIfEmptied : Slot -> Model -> Model -> Cmd msg
releaseIfEmptied slot before after =
    if slotSource slot before /= Nothing && slotSource slot after == Nothing then
        releaseSlot slot

    else
        Cmd.none


releaseSlot : Slot -> Cmd msg
releaseSlot slot =
    Ports.controlAudioPlayer (Encode.object [ ( "action", Encode.string "release" ), ( "slot", Encode.string (slotName slot) ) ])


{-| While expanded: Space plays/pauses, Left/Right go to the previous/next track. Not while typing in (or
operating) a text field or `<select>`. `public/index.html` suppresses the keys' default effects (page
scroll, button activation) -- a `Browser.Events` subscription can't.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.expanded && model.currentId /= Nothing then
        Browser.Events.onKeyDown keyDecoder

    else
        Sub.none


keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.at [ "target", "tagName" ] Decode.string |> Decode.maybe)
        |> Decode.andThen
            (\( key, maybeTag ) ->
                if List.member (Maybe.withDefault "" maybeTag) [ "INPUT", "TEXTAREA", "SELECT" ] then
                    Decode.fail "typing"

                else
                    case key of
                        " " ->
                            Decode.succeed TogglePlay

                        "ArrowRight" ->
                            Decode.succeed Next

                        "ArrowLeft" ->
                            Decode.succeed Prev

                        _ ->
                            Decode.fail "unhandled key"
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Open queue id host ->
            case queue |> List.filter (\m -> m.id == id) |> List.head of
                Just media ->
                    beginTrack media { model | queue = queue, targetHost = host }

                Nothing ->
                    ( model, Cmd.none )

        Next ->
            case adjacent 1 model of
                Just media ->
                    beginTrack media model

                Nothing ->
                    ( model, Cmd.none )

        Prev ->
            -- Like most players: past the first few seconds, "previous" restarts the track.
            case ( model.positionMs > 3000, adjacent -1 model ) of
                ( False, Just media ) ->
                    beginTrack media model

                _ ->
                    ( model, command "seek" (Just 0) )

        TogglePlay ->
            ( model, command "toggle" Nothing )

        ToggleExpanded ->
            ( { model | expanded = not model.expanded }, Cmd.none )

        Close ->
            ( { model | queue = [], currentId = Nothing, expanded = False, playing = False, positionMs = 0, durationMs = 0, slotA = Nothing, slotB = Nothing, autoStart = False }
            , Cmd.batch [ releaseSlot SlotA, releaseSlot SlotB ]
            )

        SeekToFraction fraction ->
            ( model, command "seek" (Just (clamp 0 1 fraction * model.durationMs)) )

        TimeUpdated slot positionMs durationMs ->
            if slot == model.activeSlot then
                ( { model | positionMs = positionMs, durationMs = durationMs }, Cmd.none )

            else
                ( model, Cmd.none )

        PlayStateChanged slot playing ->
            if slot == model.activeSlot then
                ( { model | playing = playing }, Cmd.none )

            else
                ( model, Cmd.none )

        Ended slot ->
            if slot /= model.activeSlot then
                ( model, Cmd.none )

            else
                case adjacent 1 model of
                    Just next ->
                        beginTrack next model

                    Nothing ->
                        ( { model | playing = False }, Cmd.none )

        CanPlay slot ->
            if slot == model.activeSlot && model.autoStart then
                ( { model | autoStart = False }, command "play" Nothing )

            else
                ( model, Cmd.none )

        CandidateReady slot ->
            -- The background slot has enough buffered at the playback point: hand playback over to it.
            if slot /= model.activeSlot && slotSource slot model /= Nothing then
                ( { model | activeSlot = slot } |> setSlot (otherSlot slot) Nothing
                , command "handoff" Nothing
                )

            else
                ( model, Cmd.none )

        QualityChanged raw ->
            let
                quality : Quality
                quality =
                    qualityFromValue raw
            in
            case ( currentMedia model, slotSource model.activeSlot model ) of
                ( Just media, Just playingSource ) ->
                    let
                        wanted : Quality
                        wanted =
                            resolve media quality

                        candidate : Maybe Source
                        candidate =
                            if wanted == playingSource.quality then
                                Nothing

                            else
                                Just { mediaId = media.id, quality = wanted, requireFull = False }

                        updated : Model
                        updated =
                            { model | quality = quality } |> setSlot (otherSlot model.activeSlot) candidate
                    in
                    ( updated, releaseIfEmptied (otherSlot model.activeSlot) model updated )

                _ ->
                    ( { model | quality = quality }, Cmd.none )

        EditClicked ->
            -- Handled by `Shared.update` (it needs `Shared.MediaViewerPanel`'s model too).
            ( model, Cmd.none )

        EditCoverArtClicked ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


{-| See `Ports.controlAudioPlayer`.
-}
command : String -> Maybe Float -> Cmd msg
command action maybeMs =
    Ports.controlAudioPlayer
        (Encode.object
            (( "action", Encode.string action )
                :: (case maybeMs of
                        Just ms ->
                            [ ( "timeMs", Encode.float ms ) ]

                        Nothing ->
                            []
                   )
            )
        )


view : AccountsPanel.Model -> Model -> Html Msg
view accountsPanelModel model =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            Posts.mediaServer (RellmServers.rellmServerForHost accountsPanelModel.servers model.targetHost) model.targetHost

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost

        maybeMedia : Maybe MediaReference
        maybeMedia =
            currentMedia model

        sourceUrl : Source -> String
        sourceUrl source =
            case ( maybeServer, model.queue |> List.filter (\m -> m.id == source.mediaId) |> List.head ) of
                ( Just server, Just media ) ->
                    urlFor server maybeAccount media source.quality

                _ ->
                    ""

        isOpen : Bool
        isOpen =
            maybeMedia /= Nothing

        fraction : Float
        fraction =
            if model.durationMs > 0 then
                clamp 0 1 (model.positionMs / model.durationMs)

            else
                0

        -- The waveform image (when generated) with a progress tint over it; clicking anywhere on it
        -- seeks. With no waveform it's a plain progress track, so seeking always works.
        seekTrack : String -> MediaReference -> Html Msg
        seekTrack extraClass media =
            div [ classes [ "audio-player-seek", extraClass ] ]
                [ case ( maybeServer, has AUDIOPREVIEWTHUMBNAILMEDIUM media ) of
                    ( Just server, True ) ->
                        img [ class "audio-player-waveform", src (MediaRenderer.thumbnailUrl "audio" TierMedium server maybeAccount media), alt "" ] []

                    _ ->
                        text ""
                , div [ class "audio-player-buffered" ]
                    (List.map (\name -> div [ class ("audio-player-buffered-band audio-player-buffered-" ++ name) ] [])
                        [ "low", "medium", "high", "original" ]
                    )
                , -- A plain `width`, not a CSS variable: Elm's `style` can't set custom properties.
                  div [ class "audio-player-progress", style "width" (String.fromFloat (fraction * 100) ++ "%") ] []
                , div [ class "audio-player-seek-hit", on "click" seekDecoder ] []
                ]

        transport : Html Msg
        transport =
            div [ class "audio-player-transport" ]
                [ button [ class "audio-player-button", attribute "aria-label" "Previous track", onClick Prev ] [ prevIcon ]
                , button
                    [ classes [ "audio-player-button", "audio-player-play" ]
                    , attribute "aria-label"
                        (if model.playing then
                            "Pause"

                         else
                            "Play"
                        )
                    , onClick TogglePlay
                    ]
                    [ if model.playing then
                        pauseIcon

                      else
                        text "▶"
                    ]
                , button
                    [ class "audio-player-button"
                    , attribute "aria-label" "Next track"
                    , onClick Next
                    ]
                    [ nextIcon ]
                ]

        -- The cover art picked for the track (`MediaMetadata.cover_art_media_id`) wins over the art embedded in
        -- the file, then the placeholder.
        coverArt : MediaReference -> Html Msg
        coverArt media =
            case ( maybeServer, media.metadata |> Maybe.andThen .coverArtMediaId, has AUDIOCOVERARTMEDIUM media ) of
                ( Just server, Just coverArtId, _ ) ->
                    img [ class "audio-player-cover", src (MediaRenderer.coverArtUrl server maybeAccount coverArtId), alt "" ] []

                ( Just server, Nothing, True ) ->
                    img [ class "audio-player-cover", src (MediaRenderer.authorizedUrl [ "size=audio_cover_art_medium" ] server maybeAccount media), alt "" ] []

                _ ->
                    div [ classes [ "audio-player-cover", "placeholder" ] ] [ text "🎵" ]

        -- The art, with (for someone who can edit the track) an "Edit Cover Art" button to its right.
        coverArtRow : MediaReference -> Html Msg
        coverArtRow media =
            div [ class "audio-player-cover-row" ]
                [ coverArt media
                , if MediaViewerPanel.canEditMedia maybeAccount media then
                    button [ class "audio-player-text-button audio-player-edit-cover-art", onClick EditCoverArtClicked ] [ text "Edit Cover Art" ]

                  else
                    text ""
                ]

        -- The qualities this track actually has stored (always the original). The selection shown is the
        -- chosen one if available, else the original -- which is what the server falls back to.
        qualityOptions : MediaReference -> List ( Quality, String )
        qualityOptions media =
            List.filterMap identity
                [ if has MEDIACONVERSIONLARGE media then
                    Just ( High, "High - AAC 256 kbps" )

                  else
                    Nothing
                , if has MEDIACONVERSIONMEDIUM media then
                    Just ( Medium, "Medium - AAC 128 kbps" )

                  else
                    Nothing
                , if has MEDIACONVERSIONSMALL media then
                    Just ( Low, "Low - AAC 64 kbps" )

                  else
                    Nothing
                , Just
                    ( OriginalQuality
                    , "Original -- "
                        ++ formatName (MediaRenderer.contentTypeOf media)
                        ++ (media.sizes
                                |> List.filter (\size -> size.conversion == MEDIACONVERSIONORIGINAL)
                                |> List.head
                                |> Maybe.map (\size -> ", " ++ ByteFormat.formatBytes (int64ToInt size.sizeBytes))
                                |> Maybe.withDefault ""
                           )
                    )
                ]

        qualitySelect : MediaReference -> Html Msg
        qualitySelect media =
            let
                options : List ( Quality, String )
                options =
                    qualityOptions media

                shown : Quality
                shown =
                    resolve media model.quality

                label : Quality -> String
                label quality =
                    options |> List.filter (\( q, _ ) -> q == quality) |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault ""

                playingQuality : Maybe Quality
                playingQuality =
                    slotSource model.activeSlot model |> Maybe.map .quality

                loadingQuality : Maybe Quality
                loadingQuality =
                    slotSource (otherSlot model.activeSlot) model |> Maybe.map .quality
            in
            div [ class "audio-player-quality" ]
                [ text "Quality "
                , select [ onInput QualityChanged, attribute "aria-label" "Playback quality" ]
                    (options
                        |> List.map
                            (\( quality, optionLabel ) ->
                                option [ value (qualityValue quality), selected (quality == shown) ] [ text optionLabel ]
                            )
                    )
                , div [ class "audio-player-quality-status" ]
                    [ text
                        (case ( playingQuality, loadingQuality ) of
                            ( Just playing, Just loading ) ->
                                "Playing " ++ label playing ++ ". Buffering " ++ label loading ++ "."

                            ( Just playing, Nothing ) ->
                                "Playing " ++ label playing

                            _ ->
                                ""
                        )
                    ]
                ]

        title : MediaReference -> String
        title media =
            media.name |> Maybe.map String.trim |> Maybe.andThen nonEmpty |> Maybe.withDefault "Untitled"

        artist : MediaReference -> String
        artist media =
            (Maybe.withDefault defaultMediaMetadata media.metadata).artist |> Maybe.withDefault ""

        -- Small title / "artist · album" text between the transport buttons and the seek track.
        nowPlaying : MediaReference -> Html Msg
        nowPlaying media =
            let
                metadata : MediaMetadata
                metadata =
                    Maybe.withDefault defaultMediaMetadata media.metadata

                credits : String
                credits =
                    [ metadata.artist, metadata.album ]
                        |> List.filterMap (Maybe.andThen (String.trim >> nonEmpty))
                        |> String.join " · "
            in
            div
                [ class "audio-player-now-playing"
                , attribute "role" "button"
                , -- Same as the arrow button on the right: expands, or collapses once expanded.
                  onClick ToggleExpanded
                ]
                [ div [ class "audio-player-now-playing-title" ] [ text (title media) ]
                , if credits == "" then
                    text ""

                  else
                    div [ class "audio-player-now-playing-credits" ] [ text credits ]
                ]

        bar : MediaReference -> Html Msg
        bar media =
            div [ class "audio-player-bar" ]
                [ transport
                , nowPlaying media
                , seekTrack "audio-player-seek-bar" media
                , button
                    [ class "audio-player-button audio-player-expand"
                    , attribute "aria-label"
                        (if model.expanded then
                            "Collapse player"

                         else
                            "Expand player"
                        )
                    , onClick ToggleExpanded
                    ]
                    [ text "⌃" ]
                ]

        expandedContent : MediaReference -> Html Msg
        expandedContent media =
            div [ class "audio-player-expanded" ]
                [ -- Circular glyph buttons in the panel's top corners: edit (left, for whoever can edit the
                  -- track) and close player (right, red).
                  if MediaViewerPanel.canEditMedia maybeAccount media then
                    button
                        [ classes [ "audio-player-button", "audio-player-corner-button", "audio-player-corner-left" ]
                        , attribute "aria-label" "Edit track"
                        , attribute "title" "Edit track"
                        , onClick EditClicked
                        ]
                        [ text "✎" ]

                  else
                    text ""
                , button
                    [ classes [ "audio-player-button", "audio-player-corner-button", "audio-player-corner-right", "audio-player-close" ]
                    , attribute "aria-label" "Close player"
                    , attribute "title" "Close player"
                    , onClick Close
                    ]
                    [ text "✕" ]
                , coverArtRow media
                , div [ class "audio-player-title" ] [ text (title media) ]
                , if artist media == "" then
                    text ""

                  else
                    div [ class "audio-player-artist" ] [ text (artist media) ]
                , seekTrack "audio-player-seek-large" media
                , qualitySelect media
                , div [ class "audio-player-times" ]
                    [ span [] [ text (formatTime model.positionMs) ]
                    , span [] [ text (formatTime model.durationMs) ]
                    ]
                ]

        -- Neighboring tracks, fetched ahead so Next/Prev (and the end of a track) start instantly. Only
        -- the next track gets a full `auto` preload; the previous one just its metadata -- every preloading
        -- element holds a connection open, and over HTTP/1.1 (6 per host) too many of them starve the
        -- track that's actually playing.
        preloads : List (Html Msg)
        preloads =
            [ ( adjacent -1 model, "metadata" ), ( adjacent 1 model, "auto" ) ]
                |> List.filterMap (\( maybeMedia_, preload ) -> maybeMedia_ |> Maybe.map (\media -> ( media, preload )))
                |> List.map
                    (\( media, preload ) ->
                        audio
                            [ class "audio-player-preload"
                            , attribute "preload" preload
                            , src (sourceUrl { mediaId = media.id, quality = startQuality media model.quality, requireFull = False })
                            ]
                            []
                    )

        -- One of the two slot `<audio>`s -- see `Slot`. Only the active one's events drive the UI; the
        -- other loads its copy in the background and reports `rellmcandidateready` (a custom event
        -- from index.html) once it's buffered enough at the playback point.
        slotAudio : Slot -> Html Msg
        slotAudio slot =
            audio
                ([ classes
                    [ "audio-player-audio"
                    , if slot == model.activeSlot then
                        "audio-player-audio-active"

                      else
                        "audio-player-audio-candidate"
                    ]
                 , attribute "data-slot" (slotName slot)
                 , attribute "preload" "auto"
                 , attribute "data-require-full"
                    (if slotSource slot model |> Maybe.map .requireFull |> Maybe.withDefault False then
                        "true"

                     else
                        "false"
                    )
                 , on "timeupdate" (timeDecoder slot)
                 , on "durationchange" (timeDecoder slot)
                 , on "play" (Decode.succeed (PlayStateChanged slot True))
                 , on "pause" (Decode.succeed (PlayStateChanged slot False))
                 , on "ended" (Decode.succeed (Ended slot))
                 , on "canplay" (Decode.succeed (CanPlay slot))
                 , on "rellmcandidateready" (Decode.succeed (CandidateReady slot))
                 ]
                    ++ (slotSource slot model |> Maybe.map (\source -> [ src (sourceUrl source) ]) |> Maybe.withDefault [])
                )
                []
    in
    div
        [ classes
            [ "audio-player-panel"
            , openClosedClass isOpen
            , if model.expanded then
                "is-expanded"

              else
                "is-collapsed"
            ]
        , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
        ]
        (slotAudio SlotA
            :: slotAudio SlotB
            :: preloads
            ++ (case maybeMedia of
                    Just media ->
                        [ expandedContent media, bar media ]

                    Nothing ->
                        []
               )
        )


{-| Transport glyphs drawn with CSS shapes (see `audio_player_panel.css`): iOS renders the Unicode ⏮ ⏸ ⏭ as
color emoji, which no text-variation selector reliably fixes. (▶ is left as text -- it renders as a plain glyph
everywhere.) They size with the button's font size and take its text color.
-}
prevIcon : Html msg
prevIcon =
    span [ class "audio-player-icon audio-player-icon-prev", attribute "aria-hidden" "true" ] []


nextIcon : Html msg
nextIcon =
    span [ class "audio-player-icon audio-player-icon-next", attribute "aria-hidden" "true" ] []


pauseIcon : Html msg
pauseIcon =
    span [ class "audio-player-icon audio-player-icon-pause", attribute "aria-hidden" "true" ] []


timeDecoder : Slot -> Decode.Decoder Msg
timeDecoder slot =
    Decode.map2 (\position duration -> TimeUpdated slot (finiteOrZero position * 1000) (finiteOrZero duration * 1000))
        (Decode.at [ "target", "currentTime" ] Decode.float)
        (Decode.at [ "target", "duration" ] Decode.float)


finiteOrZero : Float -> Float
finiteOrZero x =
    if isNaN x || isInfinite x then
        0

    else
        x


{-| Click position along `.audio-player-seek-hit`, as a fraction of its width.
-}
seekDecoder : Decode.Decoder Msg
seekDecoder =
    Decode.map2 (\x width -> SeekToFraction (x / max 1 width))
        (Decode.field "offsetX" Decode.float)
        (Decode.at [ "target", "clientWidth" ] Decode.float)


qualityValue : Quality -> String
qualityValue quality =
    case quality of
        High ->
            "high"

        Medium ->
            "medium"

        Low ->
            "low"

        OriginalQuality ->
            "original"


qualityFromValue : String -> Quality
qualityFromValue raw =
    case raw of
        "medium" ->
            Medium

        "low" ->
            Low

        "original" ->
            OriginalQuality

        _ ->
            High


formatName : String -> String
formatName contentType =
    case contentType of
        "audio/mpeg" ->
            "MP3"

        "audio/ogg" ->
            "Ogg Vorbis"

        "audio/flac" ->
            "FLAC"

        "audio/x-flac" ->
            "FLAC"

        "audio/mp4" ->
            "AAC"

        other ->
            if String.contains "wav" other then
                "WAV"

            else
                other


nonEmpty : String -> Maybe String
nonEmpty s =
    if String.isEmpty s then
        Nothing

    else
        Just s


{-| `m:ss`.
-}
formatTime : Float -> String
formatTime ms =
    let
        totalSeconds : Int
        totalSeconds =
            floor (ms / 1000)

        seconds : Int
        seconds =
            modBy 60 totalSeconds
    in
    String.fromInt (totalSeconds // 60)
        ++ ":"
        ++ (if seconds < 10 then
                "0"

            else
                ""
           )
        ++ String.fromInt seconds
