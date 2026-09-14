module Components.MultiMediaRenderer exposing (preview, previewExtraSmall, view)

{-| Renders a `Post`'s `media`. A single item (the common case) is the
"focus" of the post, so it's rendered big -- at its own inherent aspect
ratio (portrait, landscape, square, whatever), capped by reasonable bounds
rather than squashed into a fixed box (`.multi-media-single`/
`.multi-media-single-item` in `media.css`, `Components.MediaRenderer`'s
`Natural` sizing). Multiple items otherwise follow the post's own
`PostMediaLayout` (see `Components.Posts.mediaLayoutSelector`): the standard
`MEDIALAYOUTSTANDARD` layout is a horizontally-scrolling strip
(`.multi-media-strip`/`.multi-media-item`, the same horizontal-scroll pattern
as the Accounts Panel's `.servers-strip`) of thumbnails, each still at its
own aspect ratio, just capped to a small square (`Components.MediaRenderer`'s
`Compact` sizing) rather than stretched/cropped to a fixed size;
`MEDIALAYOUTDYNAMICVERTICALSCROLL` instead renders every item at the same big
`Natural` sizing as the single-item case, wrapping into a `space-around` grid
of rows (`.multi-media-gallery`/`.multi-media-gallery-item` in `media.css`,
which also breaks the grid out past the page's usual 800px column on wide
viewports) that scrolls vertically once it has more rows than fit -- a nicer
fit for a post that's meant to showcase several full-size images rather than
treat all-but-the-first as thumbnails. Only `view` (the full, non-preview
rendering used by `Components.Posts.postDetail`) honors the layout choice --
`preview`/`previewExtraSmall` (`Components.PostCard`'s compact cards,
`Shared.StarredPanel`'s rows) always use the standard strip regardless, since
a card's fixed-height layout has no room for a tall image gallery. Mirrors
the Tamagui app's `post_media_renderer.tsx`, minus its embed-link
(Twitter/Instagram/etc., which key off `Post.link` rather than `Post.media`)
handling.

`playState`/`onPlayClicked` are `Components.MediaRenderer`'s own click-to-play state/action,
threaded straight through -- see its module doc (`playState` is read internally by
`MediaRenderer.view` itself, not consulted here). `preloadVideo` isn't a parameter here: only the
*first* item of `media` (by list position -- `media[0]`, the same "focus" item the single-item case
above already treats specially) ever gets it, so a Post/Event with several videos never preloads
more than one at a time; every other item gets a play-button-overlaid poster instead (when one's
available). This holds across `view`/`preview`/`previewExtraSmall` alike -- the small strip
thumbnails skip preloading exactly the same way the full gallery does.

-}

import Components.MediaRenderer as MediaRenderer
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Proto.Rellm exposing (MediaReference)
import Proto.Rellm.PostMediaLayout exposing (PostMediaLayout(..))
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers exposing (RellmServer)
import UI.Classes exposing (classes)


view : PostMediaLayout -> RellmServer -> Maybe RellmAccount -> MediaRenderer.Model -> (String -> msg) -> (String -> msg) -> List MediaReference -> Html msg
view layout server maybeAccount playState onPlayClicked onImageClicked media =
    render layout Nothing server maybeAccount playState onPlayClicked onImageClicked media


{-| Same single-item-vs-scrolling-strip layout as `view`, just tighter
margins to fit in the middle of `Components.PostCard.postCard`'s compact
rendering (see `.multi-media-preview` in `media.css`, layered onto
`.multi-media-single`/`.multi-media-strip`'s own classes) -- and, for the
single-item case, `Compact` rather than `Natural` sizing (same as every
strip thumbnail already gets), since a post's full-size "focus" media would
dominate the card.

Left `pointer-events: auto` (see `.multi-media-preview`'s own doc comment) so
a video preview's native `controls` are directly clickable/playable rather
than falling through to `postCard`'s `.post-card-link-overlay` like
`.post-card-meta`'s plain text does.

-}
preview : RellmServer -> Maybe RellmAccount -> MediaRenderer.Model -> (String -> msg) -> (String -> msg) -> List MediaReference -> Html msg
preview server maybeAccount playState onPlayClicked onImageClicked media =
    render MEDIALAYOUTSTANDARD (Just MediaRenderer.Small) server maybeAccount playState onPlayClicked onImageClicked media


{-| Same as `preview`, just with `MediaRenderer.ExtraSmall` sizing (half the
height of `preview`'s usual `Small`) -- for contexts even tighter on vertical
space than an ordinary post card, e.g. `Shared.StarredPanel`'s post rows.
-}
previewExtraSmall : RellmServer -> Maybe RellmAccount -> MediaRenderer.Model -> (String -> msg) -> (String -> msg) -> List MediaReference -> Html msg
previewExtraSmall server maybeAccount playState onPlayClicked onImageClicked media =
    render MEDIALAYOUTSTANDARD (Just MediaRenderer.ExtraSmall) server maybeAccount playState onPlayClicked onImageClicked media


{-| `Nothing` renders full-size (`view`); `Just sizing` renders as a preview
(`.multi-media-preview` layout) at `sizing`, used for both the single-item
case and every thumbnail in the scrolling strip -- `layout` is only ever
consulted in the `Nothing`/multi-item combination (see `view`'s own doc for
why `preview`/`previewExtraSmall` always pass `MEDIALAYOUTSTANDARD`
regardless of the post's actual choice). `onImageClicked` (fired with
a tapped image's `media.id`, see `Components.MediaRenderer`) is threaded
through unconditionally -- opening `Shared.MediaViewerPanel` on tap is the
same behavior everywhere a `Post`'s media renders, single item, strip, or
gallery.

The single-item case (and every item of a `MEDIALAYOUTDYNAMICVERTICALSCROLL`
gallery) uses `MediaRenderer.ToWidthAndHeight` (the usual default), but the
strip forces `MediaRenderer.ToWidth` instead -- every thumbnail in
`.multi-media-strip` ends up the same width regardless of its own aspect
ratio, rather than each capped independently and so varying in width across
the strip.

-}
render : PostMediaLayout -> Maybe MediaRenderer.MediaSize -> RellmServer -> Maybe RellmAccount -> MediaRenderer.Model -> (String -> msg) -> (String -> msg) -> List MediaReference -> Html msg
render layout previewSizing server maybeAccount playState onPlayClicked onImageClicked media =
    let
        previewClasses : List String
        previewClasses =
            case previewSizing of
                Just _ ->
                    [ "multi-media-preview" ]

                Nothing ->
                    []
    in
    case media of
        [] ->
            text ""

        [ single ] ->
            let
                singleSizing : MediaRenderer.MediaSize
                singleSizing =
                    Maybe.withDefault MediaRenderer.Natural previewSizing
            in
            div [ classes ("multi-media-single" :: previewClasses) ]
                [ div [ class "multi-media-single-item" ]
                    [ MediaRenderer.view singleSizing MediaRenderer.ToWidthAndHeight server maybeAccount True playState onPlayClicked onImageClicked single ]
                ]

        _ ->
            case ( layout, previewSizing ) of
                ( MEDIALAYOUTDYNAMICVERTICALSCROLL, Nothing ) ->
                    div [ classes ("multi-media-gallery" :: previewClasses) ]
                        (media
                            |> List.indexedMap
                                (\index mediaRef ->
                                    div [ class "multi-media-gallery-item" ]
                                        [ MediaRenderer.view MediaRenderer.Natural MediaRenderer.ToWidthAndHeight server maybeAccount (index == 0) playState onPlayClicked onImageClicked mediaRef ]
                                )
                        )

                _ ->
                    let
                        stripSizing : MediaRenderer.MediaSize
                        stripSizing =
                            Maybe.withDefault MediaRenderer.Small previewSizing
                    in
                    div [ classes ("multi-media-strip" :: previewClasses) ]
                        (media
                            |> List.indexedMap
                                (\index mediaRef ->
                                    div [ class "multi-media-item" ]
                                        [ MediaRenderer.view stripSizing MediaRenderer.ToHeight server maybeAccount (index == 0) playState onPlayClicked onImageClicked mediaRef ]
                                )
                        )
