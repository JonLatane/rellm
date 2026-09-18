module Components.MediaRenderer exposing (MediaSize(..), Model, Msg(..), SizeConstraint(..), contentTypeOf, init, update, view, viewAutoplay)

{-| Renders a single `Proto.Rellm.MediaReference` -- an image, a video, or
(for anything else, e.g. a PDF) a browser-native `<object>` embed with a
download-link fallback for content types the browser can't render inline.

Takes a `Sizing` telling it how big to allow itself to get (see
`.media-renderer-*` in `media.css`) -- either way the media keeps its own
intrinsic aspect ratio (portrait, landscape, square, whatever); nothing here
ever stretches or crops it into a fixed box:

  - `Natural` caps it by the container's own width and a generous viewport-relative
    height (used for a post's single "focus" media item).
  - `Compact` instead caps both width and height to the same small square,
    so it ends up as narrow or as short as its own ratio calls for (used for
    every thumbnail in `Components.MultiMediaRenderer`'s scrolling strip and
    its `preview`).
  - `ExtraSmall` is the same width cap as `Compact`, just half its height --
    for contexts even tighter on vertical space than an ordinary preview
    (used by `Shared.StarredPanel`'s post rows, see
    `Components.MultiMediaRenderer.previewExtraSmall`).

Mirrors the Tamagui app's `media_renderer.tsx`, minus its social embed
providers (Twitter/Instagram/etc. -- those key off `Post.link`, not
`MediaReference`, and are handled one level up by the Tamagui
`PostMediaRenderer`; not ported here) and its `ReactPlayer` dependency for
video -- a plain HTML5 `<video controls>` covers the same MIME types Rellm
actually serves media as.

`onImageClicked` fires (with `media.id`) only for images -- videos keep their
existing native-`controls` click behavior untouched (see `Shared.MediaViewerPanel`,
the only caller today: tapping an image opens it fullscreen there; tapping a
video just plays/pauses/scrubs it in place, same as before that panel
existed).

`viewAutoplay` is the same rendering, just with a video's `autoplay`/`muted`/
`playsinline` set -- see its own doc.


## Click-to-play video previews

`view`/`viewAutoplay` also take `preloadVideo : Bool` and a play-clicked state (`Model`, read via
`isPlaying`/dispatched via `onPlayClicked`): when `preloadVideo` is `False` and video-only
`VIDEO_PREVIEW_THUMBNAIL_*` poster sizes exist for `media` (see `MediaConversion`'s own doc in
`media.proto`), a video renders as that poster `<img>` with a play button overlaid instead of a
live `<video>` element -- until `onPlayClicked` fires (from tapping the button) and the caller's
`Model` records `media.id` as playing, at which point it renders as a real (autoplaying, since a
click just asked for it) `<video>` from then on. This exists so a feed with several video posts
doesn't mount/preload several `<video>` elements at once -- see `Components.MultiMediaRenderer`'s
own doc for how `preloadVideo` gets decided (`True` only for the first media item of a given
Post/Event). `preloadVideo = True` (or no thumbnail available yet, e.g. not `processed`) skips all
of this and renders a live `<video>` immediately, same as before this existed.

`Model`/`Msg`/`update` are deliberately just a thin `Set String` of "clicked to play" media ids --
a single instance lives in `Shared.Model` (`Shared.Msg.MediaRendererMsg`, mirroring
`Shared.StarredPanel`/`Shared.MediaViewerPanel`'s own single-shared-instance panels), so every
caller reads/dispatches through it rather than owning a duplicate copy, and a video already
clicked-to-play in one place (e.g. a pinned post) shows as playing anywhere else it's also
rendered.

-}

import Html exposing (Html, a, button, div, img, object, text, video)
import Html.Attributes exposing (alt, attribute, class, controls, href, property, src, style, target, type_)
import Html.Events exposing (onClick)
import Json.Encode as Encode
import Proto.Rellm as Rellm exposing (MediaReference)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Set exposing (Set)
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Conversions exposing (int64ToInt)


{-| Which media ids have been clicked to play -- see the module doc's "Click-to-play video
previews" section. Deliberately opaque (not a bare `Set String` alias) so callers can't reach in
and mutate it directly, same reasoning as `Shared.StarredPanel.Model` etc.
-}
type Model
    = Model (Set String)


init : Model
init =
    Model Set.empty


type Msg
    = PlayClicked String


update : Msg -> Model -> Model
update msg (Model playing) =
    case msg of
        PlayClicked id ->
            Model (Set.insert id playing)


isPlaying : String -> Model -> Bool
isPlaying id (Model playing) =
    Set.member id playing


{-| The `MEDIACONVERSIONORIGINAL` entry of `media.sizes`, if present -- generic over any record
carrying a `sizes` field (both `Proto.Rellm.Media` and `MediaReference` do), so it works for
either. Every `Media`/`MediaReference` this frontend ever renders should have one (the original
upload itself), but a `Nothing` here (e.g. `url`-only, externally-hosted media, once that's
actually populated) just falls back to an empty content type / no aspect ratio below.
-}
originalSize : { a | sizes : List Rellm.MediaSize } -> Maybe Rellm.MediaSize
originalSize media =
    media.sizes
        |> List.filter (\size -> size.conversion == MEDIACONVERSIONORIGINAL)
        |> List.head


{-| The original upload's MIME content type -- replaces the old flat `Media.contentType`/
`MediaReference.contentType` fields, now tracked per-size (see `Proto.Rellm.MediaSize`).
-}
contentTypeOf : { a | sizes : List Rellm.MediaSize } -> String
contentTypeOf media =
    originalSize media
        |> Maybe.map .contentType
        |> Maybe.withDefault ""


{-| The original upload's aspect ratio (width / height) -- replaces the old flat
`MediaReference.aspectRatio` field, now tracked per-size (see `Proto.Rellm.MediaSize`).
-}
aspectRatioOf : { a | sizes : List Rellm.MediaSize } -> Maybe Float
aspectRatioOf media =
    originalSize media |> Maybe.andThen .aspectRatio


type MediaSize
    = Natural
    | Small
    | ExtraSmall


{-| Which of an image/video's two dimensions (see `.media-renderer-to-*` in
`media.css`) gets scaled to its `Sizing`'s bound, with the other left free to
whatever its own aspect ratio calls for -- `ToWidthAndHeight` (the default
everywhere except `Components.MultiMediaRenderer`'s scrolling strip) instead
bounds both, same as before this type existed.
-}
type SizeConstraint
    = ToHeight
    | ToWidthAndHeight


view : MediaSize -> SizeConstraint -> RellmServer -> Maybe RellmAccount -> Bool -> Model -> (String -> msg) -> (String -> msg) -> MediaReference -> Html msg
view =
    viewHelper False


{-| Same as `view`, except a video renders with `autoplay`/`muted`/`playsinline`
set, so it starts playing (silently) as soon as it's mounted, rather than
waiting for a tap on its native controls -- used by `Shared.MediaViewerPanel`
for whichever media is actually on stage (never its own hidden preload
elements -- an invisible video isn't something the user is watching, so
starting playback -- and burning bandwidth -- on one would be pure waste).
`muted` is required for `autoplay` to actually take effect at all in every
browser tested (Chrome/Safari both silently ignore unmuted autoplay unless
it's the direct, synchronous result of a user gesture, which a virtual-dom-
inserted element never counts as, even from a click handler) -- the "tap
controls to unmute" affordance this leaves in place mirrors how e.g.
Twitter/Instagram's own feed autoplay behaves. `playsinline` is iOS Safari's
own opt-out from its default of forcing fullscreen for `autoplay` video,
without which it wouldn't play in this panel's own frame at all. `muted`
isn't in `elm/html`'s own `Html.Attributes` (unlike `autoplay`/`controls`),
and needs setting via `property` rather than `attribute` regardless -- see
`autoplayAttributes`'s own doc.
-}
viewAutoplay : MediaSize -> SizeConstraint -> RellmServer -> Maybe RellmAccount -> Bool -> Model -> (String -> msg) -> (String -> msg) -> MediaReference -> Html msg
viewAutoplay =
    viewHelper True


viewHelper : Bool -> MediaSize -> SizeConstraint -> RellmServer -> Maybe RellmAccount -> Bool -> Model -> (String -> msg) -> (String -> msg) -> MediaReference -> Html msg
viewHelper forceAutoplay mediaSize sizeConstraint server maybeAccount preloadVideo playState onPlayClicked onImageClicked media =
    let
        mediaUrl : String
        mediaUrl =
            url mediaSize server maybeAccount media

        sizeClass : String
        sizeClass =
            mediaSizeClass mediaSize ++ " " ++ sizeConstraintClass sizeConstraint
    in
    case String.split "/" (contentTypeOf media) |> List.head |> Maybe.withDefault "" of
        "image" ->
            img
                (List.filterMap identity
                    [ Just (class ("media-renderer-image " ++ sizeClass))
                    , Just (src mediaUrl)
                    , Just (alt (Maybe.withDefault "" media.name))
                    , Just (onClick (onImageClicked media.id))
                    , Just (attribute "loading" "lazy")
                    , aspectRatioStyle media
                    ]
                )
                []

        "video" ->
            let
                -- The `VIDEO_PREVIEW_THUMBNAIL_*` conversion matching `mediaSize`, if `media`
                -- actually has one (see `MediaConversion`'s own doc for why every video gets all 3
                -- tiers together, or none at all).
                hasPreviewThumbnail : Bool
                hasPreviewThumbnail =
                    media.sizes |> List.any (\size -> size.conversion == previewThumbnailConversion mediaSize)

                clickedToPlay : Bool
                clickedToPlay =
                    isPlaying media.id playState

                -- A live `<video>` renders whenever the caller asked for one up front
                -- (`preloadVideo`), there's no poster to show instead (a not-yet-`processed` video,
                -- or one uploaded before this feature existed), or the user already tapped the play
                -- button on this exact item.
                showAsVideo : Bool
                showAsVideo =
                    preloadVideo || not hasPreviewThumbnail || clickedToPlay
            in
            if showAsVideo then
                let
                    -- A just-clicked-to-play video always autoplays (muted, same trick
                    -- `viewAutoplay` already relies on -- see its own doc), even under plain
                    -- `view`, so tapping the play button actually starts playback rather than
                    -- swapping in a paused `<video>` the user has to tap `controls` on again.
                    -- `viewAutoplay`'s own `forceAutoplay` behaves as before regardless.
                    autoplay : Bool
                    autoplay =
                        forceAutoplay || (not preloadVideo && clickedToPlay)
                in
                video
                    (List.filterMap identity
                        [ Just (class ("media-renderer-video " ++ sizeClass))
                        , Just (controls True)
                        , Just (attribute "preload" (if autoplay then "auto" else "metadata"))
                        , Just (src (mediaUrl ++ previewTimeFragment media))
                        , aspectRatioStyle media
                        ]
                        ++ (if autoplay then
                                autoplayAttributes

                            else
                                []
                           )
                    )
                    [ text "Your browser doesn't support embedded video." ]

            else
                div [ class "media-renderer-video-preview" ]
                    [ img
                        (List.filterMap identity
                            [ Just (class ("media-renderer-image media-renderer-video-preview-image " ++ sizeClass))
                            , Just (src (thumbnailUrl mediaSize server maybeAccount media))
                            , Just (alt (Maybe.withDefault "" media.name))
                            , Just (onClick (onPlayClicked media.id))
                            , Just (attribute "loading" "lazy")
                            , aspectRatioStyle media
                            ]
                        )
                        []
                    , button
                        [ class "media-renderer-play-button"
                        , onClick (onPlayClicked media.id)
                        , attribute "aria-label" "Play video"
                        ]
                        [ text "▶" ]
                    ]

        _ ->
            object [ class ("media-renderer-object " ++ sizeClass), attribute "data" mediaUrl, type_ (contentTypeOf media) ]
                [ div [ class "media-renderer-fallback" ]
                    [ text ("Can't preview " ++ contentTypeOf media ++ " here. ")
                    , a [ href mediaUrl, target "_blank" ] [ text "Download it instead." ]
                    ]
                ]


{-| `autoplay`/`muted`/`playsinline` for `viewHelper`'s autoplaying branches (`viewAutoplay`, and
any `view` item just clicked to play -- see `viewHelper`'s own `autoplay` binding) -- see
`viewAutoplay`'s own doc for why each is needed. `muted` has
to be `property`, not `attribute`: the `muted` *content* attribute only sets
a `<video>`'s default muted state as parsed from literal HTML source: setting
it via `setAttribute` (what `Html.Attributes.attribute` boils down to) on an
already-constructed element -- exactly how virtual-dom always creates this
one -- does nothing, in every browser tested; only the `.muted` *IDL
property* (what `Html.Attributes.property`/`boolProperty` -- see `autoplay`'s
own elm/html source -- assign instead) actually mutes an existing element.
`elm/html` doesn't expose `muted` itself the way it does `autoplay`/
`controls`/`loop`, so it's built here directly.
-}
autoplayAttributes : List (Html.Attribute msg)
autoplayAttributes =
    [ Html.Attributes.autoplay True
    , property "muted" (Encode.bool True)
    , attribute "playsinline" "true"
    ]


mediaSizeClass : MediaSize -> String
mediaSizeClass mediaSize =
    case mediaSize of
        Natural ->
            "media-renderer-natural"

        Small ->
            "media-renderer-small"

        ExtraSmall ->
            "media-renderer-extra-small"


sizeConstraintClass : SizeConstraint -> String
sizeConstraintClass sizeConstraint =
    case sizeConstraint of
        ToHeight ->
            "media-renderer-to-height"

        ToWidthAndHeight ->
            "media-renderer-to-width-and-height"


{-| The CSS `aspect-ratio` for `media`, from `MediaReference.aspectRatio` (width / height, set by
the backend's `convert_media_sizes` job once it's read the media's actual dimensions -- see
`protos/media.proto`). Reserves the right amount of space for an image/video whose own
`width`/`height` are left `auto` by `media.css`, so the page doesn't jump once it finishes loading
and the browser learns its real intrinsic size. `Nothing` (not yet processed, or a content type
the job doesn't inspect) just leaves sizing to load as before.
-}
aspectRatioStyle : MediaReference -> Maybe (Html.Attribute msg)
aspectRatioStyle media =
    aspectRatioOf media
        |> Maybe.map (\ratio -> style "aspect-ratio" (String.fromFloat ratio))


{-| A Media Fragments URI (`#t=<seconds>`) selecting the timestamp a `<video>` should show as its
preview/poster frame, per `media.metadata.videoPreviewTimeMs` -- empty (no fragment) if unset,
which leaves the browser's default first-frame preview in place. `npt-sec` (the fragment's time
format) is specified in whole-or-decimal seconds, so milliseconds are rendered as a fraction of a
second (1456ms -> "#t=1.456") rather than truncated to whole seconds. `videoPreviewTimeMs` is a
protobuf `uint64` (`Protobuf.Types.Int64.Int64` in Elm) -- `int64ToInt` unpacks it, safe here since
a video preview timestamp never approaches the 32-bit-until-2038 ceiling that caveat is about.
-}
previewTimeFragment : MediaReference -> String
previewTimeFragment media =
    media.metadata
        |> Maybe.andThen .videoPreviewTimeMs
        |> Maybe.map (\ms -> "#t=" ++ String.fromFloat (toFloat (int64ToInt ms) / 1000))
        |> Maybe.withDefault ""


{-| Authorized URL for `media`, mirroring `Components.Users.mediaReferenceUrl`
-- media may be visibility-restricted, so this may still 403 for a
`maybeAccount` (or anonymous request) that isn't allowed to see it. `Natural`
sizing requests the server's larger rendition (`?size=large`) since it's used
for a post's single "focus" media item, rather than the server's default
size.
-}
url : MediaSize -> RellmServer -> Maybe RellmAccount -> MediaReference -> String
url mediaSize server maybeAccount media =
    let
        sizeParam : List String
        sizeParam =
            case mediaSize of
                Natural ->
                    [ "size=large" ]

                Small ->
                    []

                ExtraSmall ->
                    []
    in
    authorizedUrl sizeParam server maybeAccount media


{-| Authorized URL for `media`'s `VIDEO_PREVIEW_THUMBNAIL_*` poster frame matching `mediaSize` --
the `view mediaSize` a caller would otherwise get, but a still `image/jpeg` instead of the video
itself (see `MediaConversion`'s own doc, and `backend/src/web/media.rs`'s `resolve_media_size` for
the `video_preview_small`/`_medium`/`_large` query values this requests). Only ever called once
`viewHelper` has already confirmed (via `previewThumbnailConversion`/`hasPreviewThumbnail`) that
size actually exists on `media` -- unlike `url`'s ordinary sizes, there's no sensible default/
fallback tier to request blindly, since an unrecognized `size` value resolves server-side to
`MEDIA_CONVERSION_MEDIUM`, which for a video is a differently-*sized video*, not a poster image.
-}
thumbnailUrl : MediaSize -> RellmServer -> Maybe RellmAccount -> MediaReference -> String
thumbnailUrl mediaSize server maybeAccount media =
    let
        sizeParam : List String
        sizeParam =
            case mediaSize of
                Natural ->
                    [ "size=video_preview_large" ]

                Small ->
                    [ "size=video_preview_medium" ]

                ExtraSmall ->
                    [ "size=video_preview_small" ]
    in
    authorizedUrl sizeParam server maybeAccount media


{-| Shared by `url`/`thumbnailUrl` -- `media`'s base `/media/{id}` URL plus `sizeParam` and (if
`maybeAccount` is signed in) an `authorization` query param. `media.url` (set by federated media --
`Shared.Federation.Mastodon`/`Bluesky`'s own `toPost`, see that field's own doc in
`protos/media.proto`) is used as-is instead whenever present: it's already a full, foreign URL, so
neither `server`'s own `/media/{id}` path nor a Rellm `authorization` token (meaningless to a
non-Rellm host) apply to it, and `sizeParam` has no federated-side equivalent to request either.
-}
authorizedUrl : List String -> RellmServer -> Maybe RellmAccount -> MediaReference -> String
authorizedUrl sizeParam server maybeAccount media =
    case media.url of
        Just externalUrl ->
            externalUrl

        Nothing ->
            let
                base : String
                base =
                    RellmServers.mediaUrl server media.id |> Maybe.withDefault ""

                authParam : List String
                authParam =
                    case maybeAccount of
                        Just account ->
                            [ "authorization=" ++ account.accessToken.token ]

                        Nothing ->
                            []
            in
            case sizeParam ++ authParam of
                [] ->
                    base

                params ->
                    base ++ "?" ++ String.join "&" params


{-| The `VIDEO_PREVIEW_THUMBNAIL_*` conversion matching `mediaSize`'s own tier -- `Natural`'s
`large`/`Small`'s `medium`/`ExtraSmall`'s `small`, same tiers `url`/`mediaSizeClass` already use.
-}
previewThumbnailConversion : MediaSize -> MediaConversion
previewThumbnailConversion mediaSize =
    case mediaSize of
        Natural ->
            VIDEOPREVIEWTHUMBNAILLARGE

        Small ->
            VIDEOPREVIEWTHUMBNAILMEDIUM

        ExtraSmall ->
            VIDEOPREVIEWTHUMBNAILSMALL
