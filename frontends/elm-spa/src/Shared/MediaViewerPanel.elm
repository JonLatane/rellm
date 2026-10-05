module Shared.MediaViewerPanel exposing (CreditField, MediaEdit, Model, Msg(..), canEditMedia, fieldErrors, formatMs, freshEdit, init, isValidKey, mediaToReference, metadataWithEdits, parseBpm, subscriptions, update, view)

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
import Dict exposing (Dict)
import Grpc
import Html exposing (Html, button, div, img, input, option, select, span, text, textarea)
import Html.Attributes exposing (alt, attribute, class, src, style, disabled, placeholder, selected, step, type_, value)
import Html.Events exposing (on, onClick, onInput, preventDefaultOn, stopPropagationOn)
import Html.Keyed
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Process
import Proto.Rellm exposing (Media, MediaMetadata, MediaReference, MediaSize, Post, defaultMedia, defaultMediaMetadata, defaultMediaSize, unwrapAuthor, wrapAuthor)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Proto.Rellm.Rellm as Rellm
import Proto.Rellm.Visibility exposing (Visibility(..))
import Protobuf.Types.Int64
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.ByteFormat as ByteFormat
import Shared.Conversions exposing (int64FromInt, int64ToInt)
import Task
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)


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

    -- Live only while the current item's name/description/sizes are being edited (see
    -- `EditClicked`) -- `Nothing` (the default) elsewhere. Reset to `Nothing` on every `Open`/
    -- `CloseClicked`, and also on `Next`/`Prev`/`SetCurrent` landing on media the account can't
    -- edit (see `canEditMedia`) -- but when it *can*, `update`'s catch-all re-derives a fresh
    -- `MediaEdit` for the new item instead, so paging through a gallery you're editing keeps you
    -- in edit mode rather than bouncing you out on every arrow key/swipe. Either way, an
    -- in-progress *edit* (unsaved name/description text, in-flight size deletions) never carries
    -- over from one item to the next -- only the "am I editing" state can.
    , edit : Maybe MediaEdit

    -- Whether audio/video starts playing on its own when shown (the default). `Open` always resets it
    -- to `True`; `OpenedForEditing` turns it off for that session -- used when `Shared.AudioPlayerPanel`
    -- hands a track over for editing, since that panel is already playing it.
    , autoplay : Bool

    -- Opened just to edit (see `OpenedForEditing`), so there's no view mode to cancel back to: the form
    -- has no Cancel button. `Open` resets it.
    , editOnly : Bool

    -- While the cover art chooser (`Shared.MyMediaPanel`, which sits beneath this panel) is open, this
    -- panel steps aside -- see `ChooseCoverArtClicked`.
    , choosingCoverArt : Bool
    }


{-| Shared by `EditSaveClicked`/`DeleteSizeClicked` -- mirrors
`Components.Pages.UserProfilePage.SubmitStatus`, kept separate since that module isn't imported
here.
-}
type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Live only while the currently-shown item (see `Model.edit`) is being edited by its owner or an
Admin (see `canEdit`) -- `name`/`description` are the in-progress text fields (independent of the
underlying `MediaReference` until `EditSaveClicked` succeeds); `deletingSizes` is which
`MediaConversion`s currently have a `DeleteMediaSizes` request in flight, so their own button can
show "Deleting…"/disable independently of the other sizes and of `status` (which only tracks the
name/description Save).
-}
type alias MediaEdit =
    { name : String
    , description : String
    , visibility : Visibility

    -- `creditLabel`-keyed current text of every credit (see `CreditField`) -- a field with
    -- no entry (or only blank text) is "unset", saved as null by `UpdateMedia`.
    , credits : Dict String String

    -- The one credit currently shown while still blank -- see `AddCreditClicked`'s doc.
    , openBlankCredit : Maybe CreditField

    -- Audio/video only; `Nothing` is "unset" (the backend's own defaults apply, see
    -- `MediaMetadata` in `protos/media.proto`).
    , videoPreviewTimeMs : Maybe Int
    , unlicensedPreviewStartMs : Maybe Int
    , unlicensedPreviewEndMs : Maybe Int

    -- Audio only: the chosen cover art, an image `Media` id (`MediaMetadata.cover_art_media_id`).
    , coverArtMediaId : Maybe String

    -- The playing element's total length, reported back by `Ports.mediaDurationReported` after
    -- `Ports.scrubMedia`'s duration probe -- sliders (see `view`) only render once it's known.
    , durationMs : Maybe Int
    , status : SubmitStatus
    , deletingSizes : List MediaConversion

    -- Whether the stored-versions list (sizes, with Delete buttons) is open; collapsed it's just a
    -- proportional bar graph of the versions -- see `ToggleSizesExpanded`.
    , sizesExpanded : Bool
    , deleteSizeError : Maybe String
    }


{-| The credits `MediaMetadata` carries (artist, album, ...) plus, for audio, its musical `StartBpm`/
`EndBpm`/`MinBpm`/`MaxBpm`/`StartKey`/`EndKey` -- all edited the same way (an "Add X" button reveals
a blank field), in the order they appear between Title and Description when set -- see
`allCreditFields`. The musical ones are validated (`fieldError`) rather than free text.
-}
type CreditField
    = Artist
    | Album
    | Composer
    | Director
    | Producer
    | Starring
    | Cast
    | Crew
    | Narrator
    | Publisher
    | StartBpm
    | EndBpm
    | MinBpm
    | MaxBpm
    | StartKey
    | EndKey


allCreditFields : List CreditField
allCreditFields =
    [ Artist, Album, Composer, Director, Producer, Starring, Cast, Crew, Narrator, Publisher ] ++ musicFields


{-| The audio-only fields among `allCreditFields`.
-}
musicFields : List CreditField
musicFields =
    [ StartBpm, EndBpm, MinBpm, MaxBpm, StartKey, EndKey ]


isMusicField : CreditField -> Bool
isMusicField field =
    List.member field musicFields


isBpmField : CreditField -> Bool
isBpmField field =
    List.member field [ StartBpm, EndBpm, MinBpm, MaxBpm ]


{-| The fields editable for `media`: the musical ones only for audio.
-}
editableFieldsFor : MediaReference -> List CreditField
editableFieldsFor media =
    if isAudio media then
        allCreditFields

    else
        List.filter (not << isMusicField) allCreditFields


creditLabel : CreditField -> String
creditLabel field =
    case field of
        Artist ->
            "Artist"

        Album ->
            "Album"

        Composer ->
            "Composer"

        Director ->
            "Director"

        Producer ->
            "Producer"

        Starring ->
            "Starring"

        Cast ->
            "Cast"

        Crew ->
            "Crew"

        Narrator ->
            "Narrator"

        Publisher ->
            "Publisher"

        StartBpm ->
            "Start BPM"

        EndBpm ->
            "End BPM"

        MinBpm ->
            "Min BPM"

        MaxBpm ->
            "Max BPM"

        StartKey ->
            "Start Key"

        EndKey ->
            "End Key"


creditFromMetadata : CreditField -> MediaMetadata -> Maybe String
creditFromMetadata field metadata =
    case field of
        Artist ->
            metadata.artist

        Album ->
            metadata.album

        Composer ->
            metadata.composer

        Director ->
            metadata.director

        Producer ->
            metadata.producer

        Starring ->
            metadata.starring

        Cast ->
            metadata.cast

        Crew ->
            metadata.crew

        Narrator ->
            metadata.narrator

        Publisher ->
            metadata.publisher

        StartBpm ->
            Maybe.map formatBpm metadata.startBpm

        EndBpm ->
            Maybe.map formatBpm metadata.endBpm

        MinBpm ->
            Maybe.map formatBpm metadata.minBpm

        MaxBpm ->
            Maybe.map formatBpm metadata.maxBpm

        StartKey ->
            metadata.startKey

        EndKey ->
            metadata.endKey


creditIntoMetadata : CreditField -> Maybe String -> MediaMetadata -> MediaMetadata
creditIntoMetadata field value metadata =
    case field of
        Artist ->
            { metadata | artist = value }

        Album ->
            { metadata | album = value }

        Composer ->
            { metadata | composer = value }

        Director ->
            { metadata | director = value }

        Producer ->
            { metadata | producer = value }

        Starring ->
            { metadata | starring = value }

        Cast ->
            { metadata | cast = value }

        Crew ->
            { metadata | crew = value }

        Narrator ->
            { metadata | narrator = value }

        Publisher ->
            { metadata | publisher = value }

        StartBpm ->
            { metadata | startBpm = value |> Maybe.andThen parseBpm }

        EndBpm ->
            { metadata | endBpm = value |> Maybe.andThen parseBpm }

        MinBpm ->
            { metadata | minBpm = value |> Maybe.andThen parseBpm }

        MaxBpm ->
            { metadata | maxBpm = value |> Maybe.andThen parseBpm }

        StartKey ->
            { metadata | startKey = value }

        EndKey ->
            { metadata | endKey = value }


{-| A BPM as shown in its input: the stored `float` (32-bit, so `127.3` comes back as
`127.30000305…`) rounded to 3 places.
-}
formatBpm : Float -> String
formatBpm bpm =
    String.fromFloat (toFloat (round (bpm * 1000)) / 1000)


{-| Mirrors the backend's `models::is_valid_bpm`: a number above 0, at most `maxBpm`.
-}
parseBpm : String -> Maybe Float
parseBpm text =
    String.toFloat (String.trim text)
        |> Maybe.andThen
            (\bpm ->
                if bpm > 0 && bpm <= maxBpm && not (isInfinite bpm) then
                    Just bpm

                else
                    Nothing
            )


maxBpm : Float
maxBpm =
    999


{-| Mirrors the backend's `models::is_valid_musical_key` (documented on `MediaMetadata.start_key` in
`protos/media.proto`) -- keep them in sync: a letter `A`-`G`, then at most one accidental (`#`, `b`,
`♯`, `♭`, `＃`, `﹟`; never double sharps/flats) optionally followed by the emoji variation selector
U+FE0F, then optionally `m`/`-` (minor) or `M` (major). Case matters; `key` isn't trimmed here.
-}
isValidKey : String -> Bool
isValidKey key =
    let
        afterAccidental : List Char -> List Char
        afterAccidental rest =
            case rest of
                '\u{FE0F}' :: more ->
                    more

                _ ->
                    rest

        validAfterTonic : List Char -> Bool
        validAfterTonic rest =
            case rest of
                accidental :: more ->
                    if List.member accidental [ '#', 'b', '♯', '♭', '＃', '﹟' ] then
                        validMode (afterAccidental more)

                    else
                        validMode rest

                [] ->
                    True

        validMode : List Char -> Bool
        validMode rest =
            case rest of
                [] ->
                    True

                [ mode ] ->
                    List.member mode [ 'm', 'M', '-' ]

                _ ->
                    False
    in
    case String.toList key of
        tonic :: rest ->
            List.member tonic [ 'A', 'B', 'C', 'D', 'E', 'F', 'G' ] && validAfterTonic rest

        [] ->
            False


{-| Why `field`'s (trimmed) `text` can't be saved, if it can't; blank is always fine (it clears the field).
-}
fieldError : CreditField -> String -> Maybe String
fieldError field text =
    if isBlank text then
        Nothing

    else if isBpmField field then
        if parseBpm text == Nothing then
            Just "Enter a number above 0, up to 999"

        else
            Nothing

    else if field == StartKey || field == EndKey then
        if isValidKey (String.trim text) then
            Nothing

        else
            Just "A letter A–G, then ♯ or ♭ (or # or b) if needed, then m for minor or M for major (or nothing): F♯m, Bb, C"

    else
        Nothing


{-| Everything keeping `edit` from being saved, keyed by `creditLabel`: each field's own `fieldError`,
plus Min BPM above Max BPM (which the backend rejects too).
-}
fieldErrors : MediaEdit -> Dict String String
fieldErrors edit =
    let
        textOf : CreditField -> String
        textOf field =
            Dict.get (creditLabel field) edit.credits |> Maybe.withDefault ""

        own : List ( String, String )
        own =
            allCreditFields
                |> List.filterMap (\field -> fieldError field (textOf field) |> Maybe.map (Tuple.pair (creditLabel field)))

        range : List ( String, String )
        range =
            case ( parseBpm (textOf MinBpm), parseBpm (textOf MaxBpm) ) of
                ( Just low, Just high ) ->
                    if low > high then
                        [ ( creditLabel MinBpm, "Min BPM can't be above Max BPM" ) ]

                    else
                        []

                _ ->
                    []
    in
    Dict.fromList (range ++ own)


{-| What `UpdateMedia` is sent as `metadata`: `base` (the item's current metadata) with every
credit/preview field replaced by `edit`'s current value -- blank credits become `Nothing` (saved as
null). `UpdateMedia` replaces the whole metadata, which is why this starts from `base` rather than
a default. `isAudioOrVideo`/`isVideo` gate the preview fields, which the backend rejects on anything
else.
-}
metadataWithEdits : Bool -> Bool -> MediaEdit -> MediaMetadata -> MediaMetadata
metadataWithEdits isAudioOrVideo isVideo_ edit base =
    let
        withCredits : MediaMetadata
        withCredits =
            List.foldl
                (\field acc ->
                    creditIntoMetadata field (Dict.get (creditLabel field) edit.credits |> Maybe.andThen nonEmpty |> Maybe.map String.trim) acc
                )
                base
                allCreditFields

        toInt64 : Maybe Int -> Maybe Protobuf.Types.Int64.Int64
        toInt64 =
            Maybe.map int64FromInt
    in
    { withCredits
        | videoPreviewTimeMs =
            if isVideo_ then
                toInt64 edit.videoPreviewTimeMs

            else
                withCredits.videoPreviewTimeMs
        , unlicensedPreviewStartMs =
            if isAudioOrVideo then
                toInt64 edit.unlicensedPreviewStartMs

            else
                Nothing
        , coverArtMediaId =
            if isAudioOrVideo then
                edit.coverArtMediaId

            else
                withCredits.coverArtMediaId
        , unlicensedPreviewEndMs =
            if isAudioOrVideo then
                toInt64 edit.unlicensedPreviewEndMs

            else
                Nothing
    }


{-| `m:ss.s` -- how the preview-time sliders show their current value.
-}
formatMs : Int -> String
formatMs ms =
    let
        totalTenths : Int
        totalTenths =
            ms // 100

        minutes : Int
        minutes =
            totalTenths // 600

        seconds : Int
        seconds =
            modBy 600 totalTenths // 10

        tenths : Int
        tenths =
            modBy 10 totalTenths
    in
    String.fromInt minutes
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt seconds)
        ++ "."
        ++ String.fromInt tenths


visibilityLabel : Visibility -> String
visibilityLabel visibility =
    case visibility of
        PRIVATE ->
            "Private"

        LIMITED ->
            "Limited (followers)"

        SERVERPUBLIC ->
            "Server Public"

        GLOBALPUBLIC ->
            "Global Public"

        LICENSED ->
            "Licensed"

        DIRECT ->
            "Direct"

        VISIBILITYUNKNOWN ->
            "Unknown"

        VisibilityUnrecognized_ _ ->
            "Unknown"


{-| The visibilities `UpdateMedia` accepts (everything but `DIRECT`/unknown).
-}
selectableVisibilities : List Visibility
selectableVisibilities =
    [ PRIVATE, LIMITED, SERVERPUBLIC, GLOBALPUBLIC, LICENSED ]


type
    Msg
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
    | EditClicked
    | EditCancelClicked
    | NoOp
    | -- From `Shared.update` when `Shared.AudioPlayerPanel` hands a track over for editing: no autoplay (that
      -- panel is already playing it) and no Cancel (nothing to go back to).
      OpenedForEditing
      -- Opens `Shared.MyMediaPanel` as a single-image chooser (`Shared.update` does that part) and steps
      -- this panel aside until it closes.
    | ChooseCoverArtClicked
      -- From `Shared.update`, when that chooser picks/closes.
    | CoverArtChosen String
    | CoverArtChooserClosed
    | CoverArtRemoved
    | ToggleSizesExpanded
    | EditNameChanged String
    | EditDescriptionChanged String
    | VisibilityChanged String
      -- "Add Artist"/"Add Album"/... -- shows that credit's field, blank. At most one blank credit
      -- is ever shown (see `Model.edit`'s `openBlankCredit`): adding another replaces it.
    | AddCreditClicked CreditField
    | CreditChanged CreditField String
    | VideoPreviewTimeChanged Int
    | UnlicensedPreviewStartChanged Int
    | UnlicensedPreviewEndChanged Int
      -- From `Ports.mediaDurationReported` -- the playing `<video>`/`<audio>`'s length in ms.
    | MediaDurationReported Float
    | EditSaveClicked
    | GotEditSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Media ))
    | DeleteSizeClicked MediaConversion
    | GotDeleteSizeResult MediaConversion (Result Grpc.Error ( Maybe AccountsPanel.Msg, Media ))


{-| See `Model.direction`'s doc.
-}
type Direction
    = Entering
    | Forward
    | Backward


init : Model
init =
    { media = [], currentMediaReference = Nothing, maybePost = Nothing, targetHost = "", direction = Entering, touchStart = Nothing, preloadFor = Nothing, edit = Nothing, autoplay = True, editOnly = False, choosingCoverArt = False }


{-| Left/right arrow keys page `Prev`/`Next`, same as the toolbar's `‹`/`›`
buttons -- only while the panel's actually open, so the keys behave normally
(e.g. scrolling a `<select>`) everywhere else in the app.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if isOpen model then
        Sub.batch
            [ Browser.Events.onKeyDown keyDecoder
            , if model.edit /= Nothing then
                Ports.mediaDurationReported MediaDurationReported

              else
                Sub.none
            ]

    else
        Sub.none


{-| Handles the edit-related messages (`EditClicked` through `GotDeleteSizeResult`), which need
`AccountsPanel.Model` to make `UpdateMedia`/`DeleteMediaSizes` calls and may return a refreshed
account (see `AccountsPanel.performWithAccountServer`) for the caller to persist -- same
`Maybe AccountsPanel.Msg` convention `Shared.MyMediaPanel.update` uses. Everything else has no RPCs
to make and is delegated to `updatePure`, though the catch-all still uses `AccountsPanel.Model` of
its own afterward -- to decide, per `Model.edit`'s doc, whether a `Next`/`Prev`/`SetCurrent` that
lands on a new item should carry edit mode along with it.
-}
update : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, Maybe AccountsPanel.Msg )
update accountsPanelModel msg model =
    let
        currentMedia : Maybe MediaReference
        currentMedia =
            model.currentMediaReference
                |> Maybe.andThen (\id -> List.filter (\m -> m.id == id) model.media |> List.head)

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost
    in
    case msg of
        EditClicked ->
            case currentMedia of
                Just media ->
                    ( { model | edit = Just (freshEdit media) }, probeDuration media, Nothing )

                Nothing ->
                    ( model, Cmd.none, Nothing )

        EditCancelClicked ->
            ( { model | edit = Nothing }, Cmd.none, Nothing )

        EditNameChanged text ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | name = text }) }, Cmd.none, Nothing )

        EditDescriptionChanged text ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | description = text }) }, Cmd.none, Nothing )

        NoOp ->
            ( model, Cmd.none, Nothing )

        VisibilityChanged raw ->
            case List.filter (\v -> visibilityLabel v == raw) selectableVisibilities |> List.head of
                Just visibility ->
                    ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | visibility = visibility }) }, Cmd.none, Nothing )

                Nothing ->
                    ( model, Cmd.none, Nothing )

        AddCreditClicked field ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | openBlankCredit = Just field }) }, Cmd.none, Nothing )

        CreditChanged field text ->
            ( { model
                | edit =
                    model.edit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | credits = Dict.insert (creditLabel field) text edit.credits

                                    -- Blanking a field leaves it showing (so it doesn't vanish from
                                    -- under the cursor mid-edit) and makes it *the* one blank field,
                                    -- displacing any other that was open.
                                    , openBlankCredit =
                                        if isBlank text then
                                            Just field

                                        else if edit.openBlankCredit == Just field then
                                            Nothing

                                        else
                                            edit.openBlankCredit
                                }
                            )
              }
            , Cmd.none
            , Nothing
            )

        VideoPreviewTimeChanged ms ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | videoPreviewTimeMs = Just ms }) }, scrubTo ms, Nothing )

        UnlicensedPreviewStartChanged ms ->
            ( { model
                | edit =
                    model.edit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | unlicensedPreviewStartMs = Just ms
                                    , unlicensedPreviewEndMs =
                                        -- Keep the range non-empty: dragging start past end pushes end along.
                                        case edit.unlicensedPreviewEndMs of
                                            Just end ->
                                                if end <= ms then
                                                    Just (min (Maybe.withDefault (ms + 1000) edit.durationMs) (ms + 1000))

                                                else
                                                    Just end

                                            Nothing ->
                                                Nothing
                                }
                            )
              }
            , scrubTo ms
            , Nothing
            )

        UnlicensedPreviewEndChanged ms ->
            ( { model
                | edit =
                    model.edit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | unlicensedPreviewEndMs = Just ms
                                    , unlicensedPreviewStartMs =
                                        case edit.unlicensedPreviewStartMs of
                                            Just start ->
                                                if start >= ms then
                                                    Just (max 0 (ms - 1000))

                                                else
                                                    Just start

                                            Nothing ->
                                                Nothing
                                }
                            )
              }
            , scrubTo ms
            , Nothing
            )

        MediaDurationReported durationMs ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | durationMs = Just (round durationMs) }) }, Cmd.none, Nothing )

        EditSaveClicked ->
            case ( currentMedia, model.edit, maybeAccount ) of
                ( Just media, Just edit, Just account ) ->
                    -- The Save button is disabled while `fieldErrors` is non-empty; this is the backstop.
                    if not (Dict.isEmpty (fieldErrors edit)) then
                        ( model, Cmd.none, Nothing )

                    else
                        ( { model | edit = Just { edit | status = Submitting } }
                        , updateMediaTask accountsPanelModel
                            account
                            media.id
                            edit.name
                            edit.description
                            edit.visibility
                            (metadataWithEdits (isAudio media || isVideo media) (isVideo media) edit (Maybe.withDefault defaultMediaMetadata media.metadata))
                            |> Task.attempt GotEditSaveResult
                        , Nothing
                        )

                _ ->
                    ( model, Cmd.none, Nothing )

        GotEditSaveResult (Ok ( maybeAccountsPanelMsg, updatedMedia )) ->
            ( { model
                | media =
                    model.media
                        |> List.map
                            (\m ->
                                if m.id == updatedMedia.id then
                                    mediaToReference updatedMedia

                                else
                                    m
                            )
                , edit = Nothing
              }
            , Cmd.none
            , maybeAccountsPanelMsg
            )

        GotEditSaveResult (Err err) ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }) }
            , Cmd.none
            , Nothing
            )

        DeleteSizeClicked conversion ->
            case ( currentMedia, model.edit, maybeAccount ) of
                ( Just media, Just edit, Just account ) ->
                    ( { model | edit = Just { edit | deletingSizes = conversion :: edit.deletingSizes, deleteSizeError = Nothing } }
                    , deleteMediaSizeTask accountsPanelModel account media.id conversion
                        |> Task.attempt (GotDeleteSizeResult conversion)
                    , Nothing
                    )

                _ ->
                    ( model, Cmd.none, Nothing )

        GotDeleteSizeResult conversion (Ok ( maybeAccountsPanelMsg, updatedMedia )) ->
            ( { model
                | media =
                    model.media
                        |> List.map
                            (\m ->
                                if m.id == updatedMedia.id then
                                    mediaToReference updatedMedia

                                else
                                    m
                            )
                , edit =
                    model.edit
                        |> Maybe.map (\edit -> { edit | deletingSizes = List.filter ((/=) conversion) edit.deletingSizes })
              }
            , Cmd.none
            , maybeAccountsPanelMsg
            )

        GotDeleteSizeResult conversion (Err err) ->
            ( { model
                | edit =
                    model.edit
                        |> Maybe.map
                            (\edit ->
                                { edit
                                    | deletingSizes = List.filter ((/=) conversion) edit.deletingSizes
                                    , deleteSizeError = Just (AccountsPanel.grpcErrorToString err)
                                }
                            )
              }
            , Cmd.none
            , Nothing
            )

        _ ->
            let
                ( newModel, cmd ) =
                    updatePure msg model

                newCurrentMedia : Maybe MediaReference
                newCurrentMedia =
                    newModel.currentMediaReference
                        |> Maybe.andThen (\id -> List.filter (\m -> m.id == id) newModel.media |> List.head)

                -- `updatePure` unconditionally resets `edit` to `Nothing` on any `Open`/`Next`/
                -- `Prev`/`SetCurrent` that actually lands on a new `currentMediaReference` (see
                -- its own doc) -- if that's what just happened *and* the account editing the old
                -- item can also edit the new one, re-derive a fresh `MediaEdit` for it instead, so
                -- paging through a gallery mid-edit keeps you in edit mode.
                restoredEdit : Maybe MediaEdit
                restoredEdit =
                    case ( model.edit, newModel.currentMediaReference /= model.currentMediaReference, newCurrentMedia ) of
                        ( Just _, True, Just media ) ->
                            if canEditMedia maybeAccount media then
                                Just (freshEdit media)

                            else
                                Nothing

                        _ ->
                            newModel.edit
            in
            ( { newModel | edit = restoredEdit }
            , Cmd.batch
                [ cmd
                , case ( restoredEdit, newCurrentMedia ) of
                    ( Just _, Just media ) ->
                        if newModel.currentMediaReference /= model.currentMediaReference then
                            probeDuration media

                        else
                            Cmd.none

                    _ ->
                        Cmd.none
                ]
            , Nothing
            )


{-| The `Media` `UpdateMedia`/`DeleteMediaSizes` respond with, folded back into `model.media` in
place of the (now possibly stale) `MediaReference` that was there -- both RPCs only ever change
`name`/`description`/`sizes`, but this replaces the whole entry so nothing here has to track which
of those actually changed. See `Shared.MyMediaPanel.toMediaReference` -- not reused directly,
since importing it back from here would be circular (`MyMediaPanel` already imports this module to
open it from its own Browse-mode grid).
-}
mediaToReference : Media -> MediaReference
mediaToReference media =
    { id = media.id
    , author = Maybe.map wrapAuthor media.author
    , name = media.name
    , generated = media.generated
    , metadata = media.metadata
    , sizes = media.sizes
    , url = media.url
    , description = media.description
    , visibility = media.visibility
    }


{-| `None` if `s` (trimmed) is empty -- e.g. an admin clearing the name/description field means
"this media has none" (matches `Media.name`/`.description`'s own `optional` semantics), not
"send an empty string".
-}
nonEmpty : String -> Maybe String
nonEmpty s =
    if String.isEmpty (String.trim s) then
        Nothing

    else
        Just s


{-| `UpdateMedia` applies `name`/`description`/`visibility`/`metadata` (see `update_media.rs`) -- every
other field on the request `Media` is ignored, so `defaultMedia` fills in the rest with placeholders
nothing on the backend reads. `metadata` replaces the item's whole metadata (see `metadataWithEdits`).
-}
updateMediaTask : AccountsPanel.Model -> RellmAccount -> String -> String -> String -> Visibility -> MediaMetadata -> Task.Task Grpc.Error ( Maybe AccountsPanel.Msg, Media )
updateMediaTask accountsPanelModel account mediaId name description visibility metadata =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        ( Just account.userId, account.server )
        (\server token ->
            Grpc.new Rellm.updateMedia
                { defaultMedia
                    | id = mediaId
                    , name = nonEmpty name
                    , description = nonEmpty description
                    , visibility = visibility
                    , metadata = Just metadata
                }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| `DeleteMediaSizes` only ever looks at `sizes`' `conversion`s (see `delete_media_sizes.rs`) --
every other field on the request `Media`, including the `MediaSize`s' own `sizeBytes`/
`contentType`/`aspectRatio`, is ignored.
-}
deleteMediaSizeTask : AccountsPanel.Model -> RellmAccount -> String -> MediaConversion -> Task.Task Grpc.Error ( Maybe AccountsPanel.Msg, Media )
deleteMediaSizeTask accountsPanelModel account mediaId conversion =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        ( Just account.userId, account.server )
        (\server token ->
            Grpc.new Rellm.deleteMediaSizes
                { defaultMedia | id = mediaId, sizes = [ { defaultMediaSize | conversion = conversion } ] }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| A brand-new `MediaEdit` for `media` -- `name`/`description` seeded from its current values
(`Nothing` becomes `""`, the empty text field), `status`/`deletingSizes`/`deleteSizeError` all at
their idle defaults. Used both by `EditClicked` (entering edit mode) and by `update`'s catch-all
(re-deriving edit mode's state for a new item after `Next`/`Prev`/`SetCurrent` -- see `Model.edit`'s
doc).
-}
freshEdit : MediaReference -> MediaEdit
freshEdit media =
    let
        metadata : MediaMetadata
        metadata =
            Maybe.withDefault defaultMediaMetadata media.metadata

        toMs : Maybe Protobuf.Types.Int64.Int64 -> Maybe Int
        toMs =
            Maybe.map int64ToInt
    in
    { name = Maybe.withDefault "" media.name
    , description = Maybe.withDefault "" media.description
    , visibility = media.visibility
    , credits =
        allCreditFields
            |> List.filterMap (\field -> creditFromMetadata field metadata |> Maybe.map (Tuple.pair (creditLabel field)))
            |> Dict.fromList
    , openBlankCredit = Nothing
    , videoPreviewTimeMs = toMs metadata.videoPreviewTimeMs
    , unlicensedPreviewStartMs = toMs metadata.unlicensedPreviewStartMs
    , unlicensedPreviewEndMs = toMs metadata.unlicensedPreviewEndMs
    , coverArtMediaId = metadata.coverArtMediaId
    , durationMs = Nothing
    , status = Idle
    , deletingSizes = []
    , sizesExpanded = False
    , deleteSizeError = Nothing
    }


isBlank : String -> Bool
isBlank text =
    String.isEmpty (String.trim text)


{-| Asks `public/index.html` to report the playing media element's duration back via
`Ports.mediaDurationReported` (no seeking) -- the preview sliders need it for their max.
-}
probeDuration : MediaReference -> Cmd msg
probeDuration media =
    if isAudio media || isVideo media then
        Ports.scrubMedia (Encode.object [ ( "timeMs", Encode.null ) ])

    else
        Cmd.none


{-| Seeks the playing `<video>`/`<audio>` to `ms`, pausing it first if it was playing -- after 5s
with no further scrubs, `public/index.html` resumes it from where it was before scrubbing began
(only if it was playing then). See `Ports.scrubMedia`.
-}
scrubTo : Int -> Cmd msg
scrubTo ms =
    Ports.scrubMedia (Encode.object [ ( "timeMs", Encode.int ms ) ])


{-| Whether `maybeAccount` may edit `media`'s name/description/sizes -- its owner, or an Admin.
Gates `view`'s Edit button -- `Nothing` (signed out) never can.
-}
canEditMedia : Maybe RellmAccount -> MediaReference -> Bool
canEditMedia maybeAccount media =
    case maybeAccount of
        Just account ->
            (media.author |> Maybe.map (unwrapAuthor >> .userId)) == Just account.userId || RellmAccounts.isAdmin account

        Nothing ->
            False


updatePure : Msg -> Model -> ( Model, Cmd Msg )
updatePure msg model =
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
              , edit = Nothing
              , autoplay = True
              , editOnly = False
              , choosingCoverArt = False
              }
            , schedulePreload newCurrent
            )

        OpenedForEditing ->
            ( { model | autoplay = False, editOnly = True }, Cmd.none )

        ChooseCoverArtClicked ->
            ( { model | choosingCoverArt = True }, Cmd.none )

        CoverArtChosen mediaId ->
            ( { model
                | choosingCoverArt = False
                , edit = model.edit |> Maybe.map (\edit -> { edit | coverArtMediaId = Just mediaId })
              }
            , Cmd.none
            )

        CoverArtChooserClosed ->
            ( { model | choosingCoverArt = False }, Cmd.none )

        ToggleSizesExpanded ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | sizesExpanded = not edit.sizesExpanded }) }, Cmd.none )

        CoverArtRemoved ->
            ( { model | edit = model.edit |> Maybe.map (\edit -> { edit | coverArtMediaId = Nothing }) }, Cmd.none )

        SetCurrent id ->
            case validCurrent model.media id of
                Just validId ->
                    ( { model | currentMediaReference = Just validId, preloadFor = Nothing, edit = Nothing }, schedulePreload (Just validId) )

                Nothing ->
                    ( model, Cmd.none )

        Next ->
            case adjacent 1 model of
                Just nextMedia ->
                    ( { model | currentMediaReference = Just nextMedia.id, direction = Forward, preloadFor = Nothing, edit = Nothing }, schedulePreload (Just nextMedia.id) )

                Nothing ->
                    ( model, Cmd.none )

        Prev ->
            case adjacent -1 model of
                Just prevMedia ->
                    ( { model | currentMediaReference = Just prevMedia.id, direction = Backward, preloadFor = Nothing, edit = Nothing }, schedulePreload (Just prevMedia.id) )

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

        -- The edit-related messages are all handled directly by `update` -- never reaches here in
        -- practice, but `updatePure` still needs to be exhaustive over the full `Msg` type.
        _ ->
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
            updatePure Next model

        else if dx >= swipeThreshold then
            updatePure Prev model

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
            Posts.mediaServer (RellmServers.rellmServerForHost accountsPanelModel.servers model.targetHost) model.targetHost

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
                            [ MediaRenderer.view MediaRenderer.Natural MediaRenderer.ToWidthAndHeight server maybeAccount True MediaRenderer.init SetCurrent SetCurrent media ]
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

        conversionLabel : MediaConversion -> String
        conversionLabel conversion =
            case conversion of
                MEDIACONVERSIONORIGINAL ->
                    "Original"

                MEDIACONVERSIONSMALL ->
                    "Small"

                MEDIACONVERSIONMEDIUM ->
                    "Medium"

                MEDIACONVERSIONLARGE ->
                    "Large"

                VIDEOPREVIEWTHUMBNAILSMALL ->
                    "Video Preview (Small)"

                VIDEOPREVIEWTHUMBNAILMEDIUM ->
                    "Video Preview (Medium)"

                VIDEOPREVIEWTHUMBNAILLARGE ->
                    "Video Preview (Large)"

                AUDIOPREVIEWTHUMBNAILSMALL ->
                    "Audio Waveform (Small)"

                AUDIOPREVIEWTHUMBNAILMEDIUM ->
                    "Audio Waveform (Medium)"

                AUDIOPREVIEWTHUMBNAILLARGE ->
                    "Audio Waveform (Large)"

                AUDIOCOVERARTSMALL ->
                    "Cover Art (Small)"

                AUDIOCOVERARTMEDIUM ->
                    "Cover Art (Medium)"

                AUDIOCOVERARTLARGE ->
                    "Cover Art (Large)"

                UNLICENSEDPREVIEWMEDIUM ->
                    "Unlicensed Preview (Medium)"

                MediaConversionUnrecognized_ _ ->
                    "Unknown"

        sizeDeleteButton : MediaEdit -> MediaSize -> Html Msg
        sizeDeleteButton edit size =
            let
                deleting : Bool
                deleting =
                    List.member size.conversion edit.deletingSizes
            in
            div [ class "media-viewer-panel-edit-size" ]
                [ span [ class "media-viewer-panel-edit-size-label" ]
                    [ text (conversionLabel size.conversion ++ " (" ++ ByteFormat.formatBytes (int64ToInt size.sizeBytes) ++ ")") ]
                , button
                    [ class "media-viewer-panel-edit-size-delete"
                    , stopClick (DeleteSizeClicked size.conversion)
                    , disabled deleting
                    ]
                    [ text
                        (if deleting then
                            "Deleting…"

                         else
                            "Delete"
                        )
                    ]
                ]

        -- The stored versions of the item, largest first: collapsed, just the total size over a labelless
        -- bar graph (segments proportional to size, alternating the server's primary/nav colors) that
        -- doubles as the expand button; expanded, a vertical list with each version's size and a Delete button.
        sizesSection : MediaEdit -> MediaReference -> Html Msg
        sizesSection edit media =
            let
                sorted : List MediaSize
                sorted =
                    media.sizes |> List.sortBy (\size -> negate (int64ToInt size.sizeBytes))
            in
            div [ class "media-viewer-panel-edit-sizes" ]
                (button
                    [ classes [ "media-viewer-panel-edit-sizes-toggle", hostnameToCSSClass model.targetHost ]
                    , attribute "aria-expanded"
                        (if edit.sizesExpanded then
                            "true"

                         else
                            "false"
                        )
                    , attribute "aria-label" "Stored versions"
                    , stopClick ToggleSizesExpanded
                    ]
                    [ -- Over the bar: the total of the original and every conversion.
                      div [ class "media-viewer-panel-edit-sizes-header" ]
                        [ span [] [ text (ByteFormat.formatBytes (List.sum (List.map (\size -> int64ToInt size.sizeBytes) sorted))) ]
                        , span [ class "media-viewer-panel-edit-sizes-chevron" ] []
                        ]
                    , div [ class "media-viewer-panel-edit-sizes-bar" ]
                        (sorted
                            |> List.indexedMap
                                (\index size ->
                                    div
                                        [ classes
                                            [ "media-viewer-panel-edit-sizes-segment"
                                            , if modBy 2 index == 0 then
                                                "background-color-primary"

                                              else
                                                "background-color-nav"
                                            ]
                                        , style "flex" (String.fromInt (max 1 (int64ToInt size.sizeBytes)) ++ " 1 0")
                                        ]
                                        []
                                )
                        )
                    ]
                    :: (if edit.sizesExpanded then
                            [ div [ class "media-viewer-panel-edit-sizes-list" ] (sorted |> List.map (sizeDeleteButton edit)) ]

                        else
                            []
                       )
                )

        -- The chosen cover art (or the embedded one/placeholder), with Choose/Remove -- same chooser
        -- convention as a profile's avatar.
        coverArtRow : MediaEdit -> Html Msg
        coverArtRow edit =
            div [ class "media-viewer-panel-edit-field media-viewer-panel-edit-cover-art" ]
                [ text "Cover art"
                , div [ class "media-viewer-panel-edit-cover-art-controls" ]
                    [ case ( edit.coverArtMediaId, maybeServer ) of
                        ( Just coverArtId, Just server ) ->
                            img [ class "media-viewer-panel-edit-cover-art-preview", src (MediaRenderer.coverArtUrl server maybeAccount coverArtId), alt "" ] []

                        _ ->
                            div [ classes [ "media-viewer-panel-edit-cover-art-preview", "placeholder" ] ] [ text "🎵" ]
                    , button [ class "media-viewer-panel-edit-cover-art-choose", onClick ChooseCoverArtClicked ] [ text "Choose…" ]
                    , if edit.coverArtMediaId /= Nothing then
                        button [ class "media-viewer-panel-edit-cover-art-remove", onClick CoverArtRemoved ] [ text "Remove" ]

                      else
                        text ""
                    ]
                ]

        creditField : MediaEdit -> CreditField -> Maybe (Html Msg)
        creditField edit field =
            let
                current : String
                current =
                    Dict.get (creditLabel field) edit.credits |> Maybe.withDefault ""
            in
            if not (isBlank current) || edit.openBlankCredit == Just field then
                let
                    inputAttributes : List (Html.Attribute Msg)
                    inputAttributes =
                        if isBpmField field then
                            [ type_ "number", Html.Attributes.min "0", Html.Attributes.max (String.fromFloat maxBpm), step "any", attribute "inputmode" "decimal", placeholder "BPM" ]

                        else if isMusicField field then
                            [ placeholder "e.g. F♯m", attribute "autocapitalize" "characters", attribute "spellcheck" "false" ]

                        else
                            [ placeholder (creditLabel field) ]
                in
                Just
                    (div [ class "media-viewer-panel-edit-field media-viewer-panel-edit-credit" ]
                        (text (creditLabel field)
                            :: input (value current :: onInput (CreditChanged field) :: inputAttributes) []
                            :: (case Dict.get (creditLabel field) (fieldErrors edit) of
                                    Just err ->
                                        [ div [ class "media-viewer-panel-edit-error" ] [ text err ] ]

                                    Nothing ->
                                        []
                               )
                        )
                    )

            else
                Nothing

        -- A credit's "Add X" button only exists while its value is blank and it isn't already the
        -- one open blank field (see `AddCreditClicked`).
        addCreditButton : MediaEdit -> CreditField -> Maybe (Html Msg)
        addCreditButton edit field =
            if creditField edit field == Nothing then
                Just (button [ class "media-viewer-panel-edit-add-credit", stopClick (AddCreditClicked field) ] [ text ("Add " ++ creditLabel field) ])

            else
                Nothing

        timeSlider : String -> Int -> Int -> (Int -> Msg) -> Html Msg
        timeSlider label maxMs current toMsg =
            div [ class "media-viewer-panel-edit-field media-viewer-panel-edit-slider" ]
                [ div [ class "media-viewer-panel-edit-slider-label" ]
                    [ text label, span [ class "media-viewer-panel-edit-slider-time" ] [ text (formatMs current) ] ]
                , input
                    [ type_ "range"
                    , Html.Attributes.min "0"
                    , Html.Attributes.max (String.fromInt maxMs)
                    , step "100"
                    , value (String.fromInt current)
                    , onInput (\raw -> toMsg (String.toInt raw |> Maybe.withDefault current))
                    ]
                    []
                ]

        previewSliders : MediaReference -> MediaEdit -> List (Html Msg)
        previewSliders media edit =
            case edit.durationMs of
                Just durationMs ->
                    let
                        start : Int
                        start =
                            Maybe.withDefault 0 edit.unlicensedPreviewStartMs
                    in
                    (if isVideo media then
                        [ timeSlider "Video preview frame" durationMs (Maybe.withDefault (min 1000 (durationMs // 2)) edit.videoPreviewTimeMs) VideoPreviewTimeChanged ]

                     else
                        []
                    )
                        ++ [ timeSlider "Unlicensed preview start" durationMs start UnlicensedPreviewStartChanged
                           , timeSlider "Unlicensed preview end"
                                durationMs
                                (Maybe.withDefault (min durationMs (start + 30000)) edit.unlicensedPreviewEndMs)
                                UnlicensedPreviewEndChanged
                           ]

                Nothing ->
                    []

        editView : MediaReference -> Html Msg
        editView media =
            case model.edit of
                Nothing ->
                    text ""

                Just edit ->
                    div [ class "media-viewer-panel-edit", stopClick NoOp ]
                        (div [ class "media-viewer-panel-edit-field" ]
                            [ text "Name"
                            , input [ value edit.name, onInput EditNameChanged, placeholder "Untitled" ] []
                            ]
                            :: List.filterMap (creditField edit) (editableFieldsFor media)
                            ++ [ div [ class "media-viewer-panel-edit-field" ]
                                    [ text "Description"
                                    , textarea [ value edit.description, onInput EditDescriptionChanged ] []
                                    ]
                               , div [ class "media-viewer-panel-edit-field" ]
                                    [ text "Visibility"
                                    , select [ onInput VisibilityChanged ]
                                        (selectableVisibilities
                                            |> List.map
                                                (\visibility ->
                                                    option [ value (visibilityLabel visibility), selected (visibility == edit.visibility) ]
                                                        [ text (visibilityLabel visibility) ]
                                                )
                                        )
                                    ]
                               ]
                            ++ (if isAudio media || isVideo media then
                                    previewSliders media edit

                                else
                                    []
                               )
                            ++ (if isAudio media then
                                    [ coverArtRow edit ]

                                else
                                    []
                               )
                            ++ [ div [ class "media-viewer-panel-edit-add-credits" ] (List.filterMap (addCreditButton edit) (editableFieldsFor media))
                               , div [ class "media-viewer-panel-edit-actions" ]
                                    [ button
                                        [ -- Tinted with the track's server's brand color (see `UI.EmittedStylesheet`'s
                                          -- utility classes; this panel isn't inside the nav, so it names the host itself).
                                          classes [ "media-viewer-panel-edit-save", hostnameToCSSClass model.targetHost, "background-color-primary" ]
                                        , onClick EditSaveClicked
                                        , disabled (edit.status == Submitting || not (Dict.isEmpty (fieldErrors edit)))
                                        ]
                                        [ text
                                            (if edit.status == Submitting then
                                                "Saving…"

                                             else
                                                "Save"
                                            )
                                        ]
                                    , -- No Cancel when this panel was opened just to edit (from the audio player's Edit
                                      -- button): there's no view mode to go back to -- tap outside to dismiss.
                                      if model.editOnly then
                                        text ""

                                      else
                                        button [ class "media-viewer-panel-edit-cancel", onClick EditCancelClicked ] [ text "Cancel" ]
                                    ]
                               , case edit.status of
                                    SubmitFailed err ->
                                        div [ class "media-viewer-panel-edit-error" ] [ text err ]

                                    _ ->
                                        text ""
                               , sizesSection edit media
                               , case edit.deleteSizeError of
                                    Just err ->
                                        div [ class "media-viewer-panel-edit-error" ] [ text err ]

                                    Nothing ->
                                        text ""
                               ]
                        )
    in
    div
        [ classes
            ([ "media-viewer-panel", "nav-panel", openClosedClass (isOpen model) ]
                ++ (if model.choosingCoverArt then
                        -- Steps aside for `Shared.MyMediaPanel`, which sits beneath this panel.
                        [ "is-yielding" ]

                    else
                        []
                   )
            )
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
                                [ (if model.autoplay then
                                    MediaRenderer.viewAutoplay

                                   else
                                    MediaRenderer.view
                                  )
                                    MediaRenderer.Natural
                                    MediaRenderer.ToWidthAndHeight
                                    server
                                    maybeAccount
                                    True
                                    MediaRenderer.init
                                    SetCurrent
                                    SetCurrent
                                    media
                                ]
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
            , case currentMedia of
                Just media ->
                    -- Not while already editing (e.g. opened from the audio player's Edit button): the form
                    -- has its own Save/Cancel, and tapping this again would just discard in-progress edits.
                    if model.edit == Nothing && canEditMedia maybeAccount media then
                        button [ class "media-viewer-panel-edit-toggle", stopClick EditClicked ] [ text "Edit" ]

                    else
                        text ""

                Nothing ->
                    text ""
            , button [ class "media-viewer-panel-close", stopClick CloseClicked ] [ text "✕" ]
            ]
        , case currentMedia of
            Just media ->
                editView media

            Nothing ->
                text ""
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


{-| Whether `media` is audio -- see `isImage`.
-}
isAudio : MediaReference -> Bool
isAudio media =
    (String.split "/" (MediaRenderer.contentTypeOf media) |> List.head) == Just "audio"


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
