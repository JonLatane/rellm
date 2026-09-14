module Components.MediaRenderer exposing (MediaSize(..), SizeConstraint(..), contentTypeOf, view, viewAutoplay)

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

-}

import Html exposing (Html, a, div, img, object, text, video)
import Html.Attributes exposing (alt, attribute, class, controls, href, property, src, style, target, type_)
import Html.Events exposing (onClick)
import Json.Encode as Encode
import Proto.Rellm as Rellm exposing (MediaReference)
import Proto.Rellm.MediaConversion exposing (MediaConversion(..))
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Conversions exposing (int64ToInt)


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


view : MediaSize -> SizeConstraint -> RellmServer -> Maybe RellmAccount -> (String -> msg) -> MediaReference -> Html msg
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
viewAutoplay : MediaSize -> SizeConstraint -> RellmServer -> Maybe RellmAccount -> (String -> msg) -> MediaReference -> Html msg
viewAutoplay =
    viewHelper True


viewHelper : Bool -> MediaSize -> SizeConstraint -> RellmServer -> Maybe RellmAccount -> (String -> msg) -> MediaReference -> Html msg
viewHelper autoplay mediaSize sizeConstraint server maybeAccount onImageClicked media =
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

        _ ->
            object [ class ("media-renderer-object " ++ sizeClass), attribute "data" mediaUrl, type_ (contentTypeOf media) ]
                [ div [ class "media-renderer-fallback" ]
                    [ text ("Can't preview " ++ contentTypeOf media ++ " here. ")
                    , a [ href mediaUrl, target "_blank" ] [ text "Download it instead." ]
                    ]
                ]


{-| `autoplay`/`muted`/`playsinline` for `viewHelper`'s `True` (i.e.
`viewAutoplay`) branch -- see its own doc for why each is needed. `muted` has
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
        base : String
        base =
            RellmServers.mediaUrl server media.id |> Maybe.withDefault ""

        sizeParam : List String
        sizeParam =
            case mediaSize of
                Natural ->
                    [ "size=large" ]

                Small ->
                    []

                ExtraSmall ->
                    []

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
