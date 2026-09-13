module Shared.MyMediaPanel exposing (Model, Msg(..), SelectionType(..), init, isOpen, subscriptions, update, view)

{-| A single, app-wide "My Media" panel -- always scoped to one specific
server (`targetHost`, same "resolve on demand rather than cache a live
`Server`/`Account`" convention `Shared.MarkdownPanel` uses for its own
`targetHost`), opened today from a signed-in Account chip in the Accounts
Panel (see `UI.accountRow`'s new media button) to browse that account's own
uploaded media, fetched via `GetMedia` (`protos/media.proto`) and rendered as
a grid of small previews (`Components.MediaRenderer`, `ExtraSmall` sizing)
alongside each item's filename/content type.

`SelectionType` is what lets this same panel double as a single-/multi-select
"media chooser" input (for a `User`'s avatar today -- see
`Components.Pages.UserProfilePage.AvatarEditClicked` -- a post's media,
later) instead of just plain browsing: `model.selectionType == Nothing` is
today's original "just browse/manage your media" mode (opened via
`Shared.MyMediaPanelOpenForAccount`), while `Just (SingleSelect _)` swaps the
header to "Select Media" and turns a tap on a grid item (`MediaItemClicked`,
see `update`) into a selection that immediately closes the panel rather than
a no-op. There's deliberately no callback closure carried on `SingleSelect`
-- `Shared.MyMediaPanelMsg (MyMediaPanel.MediaItemClicked mediaId)` is a top-
level `Shared.Msg` (this panel's `view` is `Html.map`-wrapped once, globally,
by `UI.myMediaPanel`), so `Main.elm`'s `notifyPageOfSharedMsg` already
forwards it verbatim to whichever page is current -- the opening page just
matches on it in its own `SharedMsg`/`fromShared` case (mirrors how
`Shared.MarkdownPanel.GotSaveResult` is picked up), gated on its own
"am I mid-edit" state so an unrelated Browse-mode tap elsewhere can't be
mistaken for a selection. `MultiSelect` is a stub for a future multi-select
flow -- not wired to anything yet.

The header's "Add" button doubles as this panel's upload trigger (`AddClicked`
opens the OS file picker via `File.Select.file`), and the whole panel is also
a drop target (`view`'s root `on "drop"`) -- both funnel into the same
`uploadStatus`/`startUpload`. Rellm's media upload isn't a gRPC RPC at all
(see `protos/media.proto`'s doc comment on `Media`) -- it's a plain
`POST {backendHost}/media` with the raw file bytes as the body, an
`Authorization` header, and an optional `Filename` header, returning the new
media's ID as a plaintext body on success. This mirrors
`frontends/tamagui`'s `media_uploader.tsx`, minus the client-side image
downscaling (`resize_media.ts`) and upload-progress bar (elm/http's
`Http.task` has no progress-event equivalent short of a `Cmd`+subscription
pair, not worth the added complexity here).

-}

import Animation
import Browser.Dom as Dom
import Bytes.Encode
import Components.MediaRenderer as MediaRenderer
import Dict exposing (Dict)
import File exposing (File)
import File.Select
import Grpc
import Html exposing (Html, button, div, img, input, span, text)
import Html.Attributes exposing (alt, attribute, class, classList, disabled, id, src, step, style, title, type_, value)
import Html.Events exposing (on, onClick, onInput, preventDefaultOn, stopPropagationOn)
import Html.Keyed
import Http
import Json.Decode as Decode
import Proto.Rellm exposing (GetMediaResponse, Media, MediaReference, defaultGetMediaRequest, defaultMedia, wrapAuthor)
import Proto.Rellm.Rellm as Rellm
import Set exposing (Set)
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Shared.ByteFormat as ByteFormat
import Shared.Conversions exposing (timestampToPosix)
import Shared.MediaViewerPanel as MediaViewerPanel
import Task exposing (Task)
import Time
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)
import UI.Flip


type alias Model =
    { -- The `frontendHost` of the server this panel's browsing -- resolved
      -- fresh (see `resolve`) against `AccountsPanel.Model` whenever needed,
      -- same "don't cache a live Account/Server" reasoning as
      -- `MarkdownPanel.targetHost`. `""` means "not open" (see `isOpen`).
      targetHost : String

    -- `Nothing` is plain Browse/manage mode (today's original behavior,
    -- unaffected below); `Just` turns this panel into a media chooser -- see
    -- `SelectionType`.
    , selectionType : Maybe SelectionType
    , status : FetchStatus
    , uploadStatus : UploadStatus

    -- Whether a drag is currently hovering anywhere over this panel -- see
    -- `view`'s `on "dragenter"`/`"dragleave"`. Purely a CSS hook
    -- (`is-dragging-over`); doesn't gate `Drop` itself.
    , isDraggingOver : Bool

    -- Media IDs with a `DeleteMedia` request currently in flight -- a `Set`
    -- (not a single `Maybe`, unlike `uploadStatus`) since nothing stops the
    -- user confirming a second item's delete while the first is still
    -- in-flight. Drives disabling that item's delete button and showing
    -- "Deleting…" in its place (see `mediaItemView`).
    , deletingIds : Set String

    -- Set by the most recent failed `DeleteMedia` -- shown next to
    -- `uploadStatus` in the header (see `uploadStatusView`'s counterpart,
    -- `deleteStatusView`) until the next delete attempt or panel close.
    , deleteError : Maybe String

    -- The slider-controlled pixel size of each grid item's long edge (see
    -- `zoomSliderView`) -- carried forward across `Open`/`CloseClicked`
    -- (unlike the rest of this record, which those reset) so the user's
    -- preferred preview size sticks across panel sessions. 238 matches
    -- `ExtraSmall`'s own fixed CSS cap (`media.css`), so the slider's
    -- default looks identical to before this existed.
    , zoom : Float

    -- Each tile's enter/leave `UI.Flip.State`, keyed by `Media.id`, synced
    -- (see `syncMediaAnimations`) against `status`'s own `Fetched` list
    -- every time it changes -- newly-seen media (a fresh `Open`, or a just
    -- uploaded item once its post-upload refetch lands) fades in, and media
    -- that dropped out (a just-deleted item, once *its* refetch lands)
    -- fades/collapses out instead of disappearing outright. Mirrors
    -- `Components.Pages.UsersPage.userAnimations` -- see its own doc.
    , mediaAnimations : Dict String MediaAnimation

    -- `MultiSelect`'s own picked-media list, in display order -- a plain,
    -- caller-owned order (like `AccountsPanel.servers`/`.accounts`, not
    -- resorted by any property of the `MediaReference`s themselves), so a
    -- reorder/prepend just edits this list directly rather than deriving
    -- order from a timestamp the way `mediaAnimations`' own grid does.
    -- Seeded from `MultiSelect.initialSelection` by `Open`; empty in every
    -- other `selectionType`.
    , selectedMedia : List MediaReference

    -- `selectedMedia`'s own enter/leave fade, keyed by `MediaReference.id` --
    -- mirrors `accountAnimations`/`serverAnimations` (bare `UI.Flip.State`,
    -- not wrapped in a per-item record) rather than `mediaAnimations`'
    -- `MediaAnimation`, since `selectedMedia` already carries each item's own
    -- data -- there's nothing else worth stashing alongside the flip state.
    -- `RemoveSelectedMediaClicked` starts a removing-fade here *without*
    -- touching `selectedMedia` itself (same "keep a removing item at its
    -- exact existing slot" reasoning `UI.Flip.remove` documents) --
    -- `RemoveSelectedMediaAnimation` is what actually drops it from both once
    -- the fade finishes.
    , selectedMediaAnimations : Dict String (UI.Flip.State Msg)

    -- In-flight/settling FLIP slide animations for `selectedMedia` items just
    -- reordered via `MoveSelectedMediaLeftClicked`/`MoveSelectedMediaRightClicked`
    -- -- mirrors `AccountsPanel.serverMoveAnimations` exactly, just scoped to
    -- this panel's own selected-media strip instead of the Servers strip.
    , selectedMediaMoveAnimations : Dict String (UI.Flip.MoveState Msg)

    -- The id of a just-uploaded item awaiting its post-upload refetch, while
    -- `selectionType` is `Just (MultiSelect _)` -- `GotUploadResult` stashes
    -- it here (there's nothing else to key it by, `POST /media`'s response is
    -- just a plaintext id, not a full `Media`/`MediaReference` `view` could
    -- render), and `GotMediaResult` consumes it once the refetch actually
    -- lands (with the full `Media` this id refers to), prepending it to
    -- `selectedMedia` the same as a tapped grid item. `Nothing` the rest of
    -- the time, including every upload outside `MultiSelect`.
    , pendingUploadSelection : Maybe String
    }


type Msg
    = Open (Maybe SelectionType) String
    | CloseClicked
    | GotMediaResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse ))
      -- Fired when a media item's preview is tapped -- a no-op in Browse mode
      -- (`model.selectionType == Nothing`); while `Just (SingleSelect _)`,
      -- `update` closes the panel instead (see its own doc on why that alone
      -- is enough to deliver the selection to whichever page opened this).
      -- Required regardless, since `Components.MediaRenderer.view` always
      -- needs an `onImageClicked : String -> msg` to attach.
    | MediaItemClicked String
      -- The header's "Add" button -- opens the OS file picker; the file it
      -- comes back with (`GotFile`) is uploaded the same way a `Drop` is.
    | AddClicked
    | GotFile File
      -- Every file dropped anywhere on this panel (see `view`) -- only the
      -- first is actually uploaded (one at a time, same as `AddClicked`'s own
      -- picker), the rest are silently ignored rather than queued.
    | Drop (List File)
    | DragEnter
    | DragLeave
    | GotUploadResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, String ))
      -- The delete button on a grid item (see `mediaItemView`) -- doesn't
      -- delete anything itself, just bubbles `media` up through `update`'s
      -- own extra return value for `Shared.update` to turn into a
      -- `Shared.RequestDelete`, the same shared "are you sure?" flow
      -- `UI.serverChip`/`UI.accountRow` use (see `Shared.DeleteConfirmation`).
    | DeleteClicked Media
      -- Fired back from `Shared.update`'s `ConfirmDelete` once the user's
      -- confirmed the dialog `DeleteClicked` requested -- this is what
      -- actually calls `DeleteMedia`.
    | DeleteConfirmed Media
    | GotDeleteResult Media (Result Grpc.Error ( Maybe AccountsPanel.Msg, () ))
      -- Steps every tile's enter/leave fade (`mediaAnimations`) forward on
      -- an animation-frame tick -- mirrors `AccountsPanel.AnimateItemFlip`.
    | AnimateItemFlip Animation.Msg
      -- Fired once a removing tile's fade-out finishes (see
      -- `UI.Flip.remove`) -- actually drops it from `mediaAnimations` for
      -- good.
    | RemoveMediaAnimation String
      -- The bottom-right zoom slider (see `zoomSliderView`) -- `Float` since
      -- that's what an `input[type=range]`'s value parses as.
    | ZoomChanged Float
      -- `MoveSelectedMediaLeftClicked`/`-RightClicked` (see
      -- `selectedMediaItemView`'s reorder buttons) kick off a reorder slide
      -- for `selectedMedia`, exactly mirroring
      -- `AccountsPanel.MoveFeedItemLeftClicked`/`-RightClicked`'s own
      -- `beginReorder`/`GotPreMoveFeedItemPositions`/`applyReorder`/
      -- `FeedItemMoveSettled` chain -- see that module for the full FLIP
      -- reorder story, just scoped to this panel's own `selectedMedia`/
      -- `selectedMediaMoveAnimations` in place of its `servers`/
      -- `serverMoveAnimations`.
    | MoveSelectedMediaLeftClicked String
    | MoveSelectedMediaRightClicked String
    | GotPreMoveSelectedMediaPositions String String Int (Result Dom.Error ( Dom.Element, Dom.Element ))
    | AnimateSelectedMediaMove Animation.Msg
    | SelectedMediaMoveSettled String
      -- The delete button on a selected-media strip item (see
      -- `selectedMediaItemView`) -- unlike the browse grid's own
      -- `DeleteClicked`, this doesn't call `DeleteMedia` at all (it's only
      -- dropping this item from *this post's* selection, not deleting the
      -- underlying media from the account), so it needs no confirmation and
      -- starts its removing-fade immediately.
    | RemoveSelectedMediaClicked String
      -- Fired once a removed selected-media item's fade-out finishes (see
      -- `UI.Flip.remove`) -- actually drops it from `selectedMedia`/
      -- `selectedMediaAnimations`/`selectedMediaMoveAnimations` for good.
    | RemoveSelectedMediaAnimation String
      -- The bottom "Save Media"/"Cancel" row shown only while `selectionType`
      -- is `Just (MultiSelect _)` (see `multiSelectActionsView`) --
      -- "Cancel" is just `CloseClicked` itself, reused as-is. The final,
      -- in-order `List MediaReference` is built by the view (from
      -- `selectedMedia`, filtering out anything still mid removing-fade) and
      -- carried on the message itself, not re-read from `model` -- by the
      -- time whichever page opened this panel gets to react to the very same
      -- `Shared.Msg` value (see module doc's note on `MediaItemClicked`'s own
      -- delivery), this panel may already have reset itself back to `init`.
    | SaveMediaClicked (List MediaReference)
      -- The selected-media strip's own thumbnail (see `selectedMediaItemView`)
      -- needs an `onImageClicked` for `Components.MediaRenderer.view` to
      -- attach (same as every other caller), but tapping an already-selected
      -- item's image isn't a meaningful action here -- reordering/removing
      -- each have their own explicit button instead.
    | NoOp


{-| What a `Just` `Model.selectionType` turns this panel into -- see module
doc. `SingleSelect`'s `imagesOnly` restricts the grid to image media only
(hiding videos/PDFs/etc that couldn't be tapped-to-select anyway --
`Components.MediaRenderer.view` only ever attaches `onImageClicked` for
images in the first place, see its own doc) -- `False` for a future chooser
that's fine picking any media type. Its `initialSelection` (e.g.
`Components.Pages.UserProfilePage`'s `user.avatar`) seeds `Model.selectedMedia`
(see `Open`) purely so the grid item it matches renders pre-highlighted (see
`mediaItemView`'s `selected`) -- `SingleSelect` never adds to/reorders that
list the way `MultiSelect` does, tapping a grid item still just closes the
panel outright (see `MediaItemClicked`).

`MultiSelect`'s own `initialSelection` seeds the same `Model.selectedMedia` --
e.g. a `Post`'s current `media`, so re-opening the picker to edit an
already-published post's media starts from what's already there rather than
empty. Tapping a grid item while this is the active `selectionType` doesn't
close the panel like `SingleSelect` does -- it prepends to `selectedMedia`
instead (see `MediaItemClicked`), which the top "selected media" strip (see
`selectedMediaStripView`) renders reorderably; `SaveMediaClicked`/`CloseClicked`
are this mode's own Save/Cancel, at the bottom of `view`.

-}
type SelectionType
    = SingleSelect { imagesOnly : Bool, initialSelection : Maybe MediaReference }
    | MultiSelect { initialSelection : List MediaReference }


type FetchStatus
    = NotFetched
    | Fetching
    | FetchFailed String
    | Fetched (List Media)


{-| What the "Add" button/drag-and-drop upload is currently doing -- separate
from `FetchStatus` since browsing the existing grid and uploading a new item
into it are independent (an upload failure shouldn't blank out an
already-loaded grid, and vice versa). `File` is carried along in `Uploading`/
`UploadFailed` purely so `view` can keep showing its name (`File.name`)
without a separate field for it.
-}
type UploadStatus
    = NotUploading
    | Uploading File
    | UploadFailed File String


{-| One grid tile's enter/leave fade state, paired with the `Media` it was
last rendered with -- mirrors `Components.Pages.UsersPage.UserAnimation` (see
its own doc): keeping `media` here, not just relying on `status`'s own
`Fetched` list, lets a just-deleted tile keep rendering its last-known
preview/name for the length of its fade-out, rather than needing to somehow
survive in `Fetched` itself once it's gone from the server.
-}
type alias MediaAnimation =
    { media : Media
    , flip : UI.Flip.State Msg
    }


type alias Resolved =
    { server : RellmServer
    , account : RellmAccount
    }


init : Model
init =
    { targetHost = ""
    , selectionType = Nothing
    , status = NotFetched
    , uploadStatus = NotUploading
    , isDraggingOver = False
    , deletingIds = Set.empty
    , deleteError = Nothing
    , zoom = 238
    , mediaAnimations = Dict.empty
    , selectedMedia = []
    , selectedMediaAnimations = Dict.empty
    , selectedMediaMoveAnimations = Dict.empty
    , pendingUploadSelection = Nothing
    }


{-| Whether the panel is currently open -- drives `openClosedClass` and
`UI.elm`'s `sharedBackdrop`, same `targetHost /= ""` convention
`MarkdownPanel` uses via its own `target /= Nothing`.
-}
isOpen : Model -> Bool
isOpen model =
    model.targetHost /= ""


{-| The `Sub` driving every tile's enter/leave fade -- gated on `isOpen`
(unlike e.g. `Shared.StarredPanel.subscriptions`' own `AnimateItemFlip`
sub, this panel's tiles only ever render while it's open, so nothing outside
`view` could still be mid-animation once it's closed).
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if isOpen model then
        Sub.batch
            [ UI.Flip.subscription AnimateItemFlip
                (List.map .flip (Dict.values model.mediaAnimations) ++ Dict.values model.selectedMediaAnimations)
            , UI.Flip.moveSubscription AnimateSelectedMediaMove (Dict.values model.selectedMediaMoveAnimations)
            ]

    else
        Sub.none


{-| Wraps `sendUpdate` to also compute a `Maybe MediaViewerPanel.Msg` --
`MediaItemClicked` while Browse mode (`model.selectionType == Nothing`)
doesn't touch this panel's own state at all (see `sendUpdate`'s `Nothing`
branch), it just needs `Shared.update` to open `Shared.MediaViewerPanel` on
this tile's whole grid, same forwarding convention
`Shared.StarredPanel.update` uses for its own `Maybe MediaViewerPanel.Msg`
(computed directly from `msg`/`model` here too, rather than from
`sendUpdate`'s result, since -- same as there -- no `Model` state is
involved). `browseMediaReferences model`, not `model.status`'s raw `Fetched`
list, so the viewer's own paging order (and its item count) matches the grid
exactly -- see that function's own doc.
-}
update : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Maybe Media, Maybe MediaViewerPanel.Msg ) )
update accountsPanelModel msg model =
    let
        ( newModel, cmd, ( maybeAccountsPanelMsg, maybeDeleteRequest ) ) =
            sendUpdate accountsPanelModel msg model

        maybeMediaViewerPanelMsg : Maybe MediaViewerPanel.Msg
        maybeMediaViewerPanelMsg =
            case ( msg, model.selectionType ) of
                ( MediaItemClicked mediaId, Nothing ) ->
                    Just (MediaViewerPanel.Open (browseMediaReferences model) Nothing mediaId model.targetHost)

                _ ->
                    Nothing
    in
    ( newModel, cmd, ( maybeAccountsPanelMsg, maybeDeleteRequest, maybeMediaViewerPanelMsg ) )


{-| Needs `AccountsPanel.Model` (to resolve `targetHost` to a connected
`Server`/signed-in `Account` to fetch/upload as -- see `resolve`) and can
itself surface an `AccountsPanel.Msg` it needs forwarded on its behalf (an
`AccessTokenResponseReceived`, if fetching/uploading had to refresh the
account's token first -- see `AccountsPanel.performWithAccountServer`) for
`Shared.update` to actually dispatch, same convention as
`Shared.MarkdownPanel.update`. The extra `Maybe Media` alongside it is
`DeleteClicked`'s own request for `Shared.update` to open the shared delete
confirmation dialog for -- same "second forwarded value" convention
`Shared.StarredPanel.update` uses for its own `Maybe MediaViewerPanel.Msg`
(this module's own `update`, above, adds a third forwarded value on top of
this function's pair, for that exact `MediaViewerPanel.Msg`).
-}
sendUpdate : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Maybe Media ) )
sendUpdate accountsPanelModel msg model =
    case msg of
        Open selectionType host ->
            let
                initialSelection : List MediaReference
                initialSelection =
                    case selectionType of
                        Just (MultiSelect multiSelect) ->
                            multiSelect.initialSelection

                        Just (SingleSelect singleSelect) ->
                            singleSelect.initialSelection
                                |> Maybe.map List.singleton
                                |> Maybe.withDefault []

                        Nothing ->
                            []

                opened : Model
                opened =
                    { targetHost = host
                    , selectionType = selectionType
                    , status = Fetching
                    , uploadStatus = NotUploading
                    , isDraggingOver = False
                    , deletingIds = Set.empty
                    , deleteError = Nothing
                    , zoom = model.zoom
                    , mediaAnimations = Dict.empty
                    , selectedMedia = initialSelection

                    -- `restingState`, not `enter` -- these are already-there
                    -- (a Post's already-published media), not freshly
                    -- picked, so they shouldn't replay an entrance animation
                    -- every time the picker's reopened. Mirrors `init`'s own
                    -- reasoning for why a caller with pre-existing persisted
                    -- items pre-seeds `restingState` rather than starting
                    -- from empty -- see `UI.Flip.syncEnter`'s doc.
                    , selectedMediaAnimations =
                        initialSelection
                            |> List.map (\media -> ( media.id, UI.Flip.restingState ))
                            |> Dict.fromList
                    , selectedMediaMoveAnimations = Dict.empty
                    , pendingUploadSelection = Nothing
                    }
            in
            case resolve accountsPanelModel host of
                Ok resolved ->
                    ( opened
                    , fetchTask accountsPanelModel resolved.account
                        |> Task.attempt GotMediaResult
                    , ( Nothing, Nothing )
                    )

                Err err ->
                    ( { opened | status = FetchFailed err }, Cmd.none, ( Nothing, Nothing ) )

        CloseClicked ->
            ( { init | zoom = model.zoom }, Cmd.none, ( Nothing, Nothing ) )

        GotMediaResult (Ok ( maybeAccountsPanelMsg, response )) ->
            -- `GotUploadResult`/`GotDeleteResult` both re-run `fetchTask`
            -- (see their own docs) *without* first bouncing `status` back to
            -- `Fetching` -- so it's still `Fetched <previous list>` right up
            -- until this replaces it with the fresh one, and `contentView`
            -- keeps rendering the (still-accurate-enough) grid the entire
            -- time instead of swapping to "Loading…" and back around it.
            -- That matters here specifically because `syncMediaAnimations`
            -- (below) is what starts a just-gone tile's removing-fade -- if
            -- the grid had been unmounted in between, that tile would have
            -- no prior on-screen frame to fade *from*, and would just appear
            -- already-collapsed instead of animating.
            --
            -- `pendingUploadSelection`, if set (a just-uploaded item, see
            -- `GotUploadResult`), is consumed here too: this is the first
            -- point this panel actually has the full `Media` (name/content
            -- type) that id refers to, needed to prepend it to
            -- `selectedMedia` the same as a tapped grid item.
            let
                syncedModel : Model
                syncedModel =
                    syncMediaAnimations { model | status = Fetched response.media }

                selectedModel : Model
                selectedModel =
                    case syncedModel.pendingUploadSelection of
                        Just uploadedId ->
                            let
                                withoutPending : Model
                                withoutPending =
                                    { syncedModel | pendingUploadSelection = Nothing }
                            in
                            case List.filter (\media -> media.id == uploadedId) response.media |> List.head of
                                Just media ->
                                    addSelectedMedia (toMediaReference media) withoutPending

                                Nothing ->
                                    withoutPending

                        Nothing ->
                            syncedModel
            in
            ( selectedModel, Cmd.none, ( maybeAccountsPanelMsg, Nothing ) )

        GotMediaResult (Err err) ->
            ( { model | status = FetchFailed (AccountsPanel.grpcErrorToString err) }, Cmd.none, ( Nothing, Nothing ) )

        MediaItemClicked mediaId ->
            case model.selectionType of
                Just (SingleSelect _) ->
                    -- The tapped id itself isn't needed here -- `Main.elm`
                    -- forwards this same `MediaItemClicked` verbatim to
                    -- whichever page opened this panel (see module doc), so
                    -- all this needs to do is close the panel as the visible
                    -- "selection made" feedback.
                    ( { init | zoom = model.zoom }, Cmd.none, ( Nothing, Nothing ) )

                Just (MultiSelect _) ->
                    case Dict.get mediaId model.mediaAnimations of
                        Just anim ->
                            ( addSelectedMedia (toMediaReference anim.media) model, Cmd.none, ( Nothing, Nothing ) )

                        Nothing ->
                            ( model, Cmd.none, ( Nothing, Nothing ) )

                Nothing ->
                    ( model, Cmd.none, ( Nothing, Nothing ) )

        AddClicked ->
            ( model, File.Select.file acceptedMimeTypes GotFile, ( Nothing, Nothing ) )

        GotFile file ->
            startUpload accountsPanelModel model file

        Drop files ->
            case List.head files of
                Just file ->
                    startUpload accountsPanelModel { model | isDraggingOver = False } file

                Nothing ->
                    ( { model | isDraggingOver = False }, Cmd.none, ( Nothing, Nothing ) )

        DragEnter ->
            ( { model | isDraggingOver = True }, Cmd.none, ( Nothing, Nothing ) )

        DragLeave ->
            ( { model | isDraggingOver = False }, Cmd.none, ( Nothing, Nothing ) )

        GotUploadResult (Ok ( maybeAccountsPanelMsg, uploadedMediaId )) ->
            -- Re-fetch to show the new item -- cheaper to just re-run the
            -- same `GetMedia` `Open` already does than to splice a new `Media`
            -- into `Fetched`'s list, since `POST /media`'s response is just a
            -- plaintext ID, not the full `Media` `GetMedia` would return.
            -- Deliberately leaves `status` (and so the still-`Fetched` grid
            -- `contentView` renders from it) alone rather than bouncing it
            -- through `Fetching` -- see `GotMediaResult`'s own doc on why.
            --
            -- While `MultiSelect`, stashes `uploadedMediaId` in
            -- `pendingUploadSelection` for `GotMediaResult` (below, once the
            -- refetch it kicks off here actually lands) to prepend to
            -- `selectedMedia` -- a freshly-uploaded item should land in the
            -- selection the same as tapping an already-there grid item would.
            let
                pendingUploadSelection : Maybe String
                pendingUploadSelection =
                    case model.selectionType of
                        Just (MultiSelect _) ->
                            Just uploadedMediaId

                        _ ->
                            Nothing
            in
            case resolve accountsPanelModel model.targetHost of
                Ok resolved ->
                    ( { model | uploadStatus = NotUploading, pendingUploadSelection = pendingUploadSelection }
                    , fetchTask accountsPanelModel resolved.account |> Task.attempt GotMediaResult
                    , ( maybeAccountsPanelMsg, Nothing )
                    )

                Err _ ->
                    ( { model | uploadStatus = NotUploading, pendingUploadSelection = pendingUploadSelection }, Cmd.none, ( maybeAccountsPanelMsg, Nothing ) )

        GotUploadResult (Err err) ->
            case model.uploadStatus of
                Uploading file ->
                    ( { model | uploadStatus = UploadFailed file (AccountsPanel.grpcErrorToString err) }, Cmd.none, ( Nothing, Nothing ) )

                _ ->
                    ( model, Cmd.none, ( Nothing, Nothing ) )

        DeleteClicked media ->
            ( model, Cmd.none, ( Nothing, Just media ) )

        DeleteConfirmed media ->
            case resolve accountsPanelModel model.targetHost of
                Ok resolved ->
                    ( { model | deletingIds = Set.insert media.id model.deletingIds, deleteError = Nothing }
                    , deleteTask accountsPanelModel resolved.account media
                        |> Task.attempt (GotDeleteResult media)
                    , ( Nothing, Nothing )
                    )

                Err err ->
                    ( { model | deleteError = Just err }, Cmd.none, ( Nothing, Nothing ) )

        GotDeleteResult media (Ok ( maybeAccountsPanelMsg, _ )) ->
            -- Re-fetch rather than just filtering `media` out of `Fetched`'s
            -- own list locally -- same reasoning `GotUploadResult` gives for
            -- doing the same after an upload. Also leaves `status` alone
            -- (see that same comment) -- deliberately so, since it's what
            -- lets the just-deleted tile's own removing-fade actually play
            -- (see `GotMediaResult`'s doc) instead of the whole grid
            -- unmounting to "Loading…" and back around it.
            let
                clearedModel : Model
                clearedModel =
                    { model | deletingIds = Set.remove media.id model.deletingIds }
            in
            case resolve accountsPanelModel model.targetHost of
                Ok resolved ->
                    ( { clearedModel | status = Fetching }
                    , fetchTask accountsPanelModel resolved.account |> Task.attempt GotMediaResult
                    , ( maybeAccountsPanelMsg, Nothing )
                    )

                Err _ ->
                    ( clearedModel, Cmd.none, ( maybeAccountsPanelMsg, Nothing ) )

        GotDeleteResult media (Err err) ->
            ( { model
                | deletingIds = Set.remove media.id model.deletingIds
                , deleteError = Just (AccountsPanel.grpcErrorToString err)
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        AnimateItemFlip animMsg ->
            let
                step : String -> MediaAnimation -> ( Dict String MediaAnimation, List (Cmd Msg) ) -> ( Dict String MediaAnimation, List (Cmd Msg) )
                step id anim ( animations, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg anim.flip
                    in
                    ( Dict.insert id { anim | flip = newFlip } animations, cmd :: accCmds )

                ( newMediaAnimations, mediaCmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.mediaAnimations

                -- Steps `selectedMediaAnimations` forward in the same pass --
                -- mirrors `AccountsPanel.AnimateItemFlip` stepping both
                -- `accountAnimations` and `serverAnimations` off one `Sub`.
                stepFlip : String -> UI.Flip.State Msg -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.State Msg), List (Cmd Msg) )
                stepFlip id flip ( flips, accCmds ) =
                    let
                        ( newFlip, cmd ) =
                            UI.Flip.animate animMsg flip
                    in
                    ( Dict.insert id newFlip flips, cmd :: accCmds )

                ( newSelectedMediaAnimations, selectedCmds ) =
                    Dict.foldl stepFlip ( Dict.empty, [] ) model.selectedMediaAnimations
            in
            ( { model | mediaAnimations = newMediaAnimations, selectedMediaAnimations = newSelectedMediaAnimations }
            , Cmd.batch (mediaCmds ++ selectedCmds)
            , ( Nothing, Nothing )
            )

        RemoveMediaAnimation id ->
            ( { model | mediaAnimations = Dict.remove id model.mediaAnimations }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        ZoomChanged zoom ->
            ( { model | zoom = zoom }, Cmd.none, ( Nothing, Nothing ) )

        MoveSelectedMediaLeftClicked mediaId ->
            ( model
            , UI.Flip.beginReorder .id selectedMediaDomId GotPreMoveSelectedMediaPositions -1 mediaId model.selectedMedia
            , ( Nothing, Nothing )
            )

        MoveSelectedMediaRightClicked mediaId ->
            ( model
            , UI.Flip.beginReorder .id selectedMediaDomId GotPreMoveSelectedMediaPositions 1 mediaId model.selectedMedia
            , ( Nothing, Nothing )
            )

        GotPreMoveSelectedMediaPositions mediaId _ offset (Err _) ->
            ( { model | selectedMedia = UI.Flip.moveListItemBy .id offset mediaId model.selectedMedia }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        GotPreMoveSelectedMediaPositions mediaId neighborId offset (Ok ( movedEl, neighborEl )) ->
            let
                newModel : Model
                newModel =
                    { model | selectedMedia = UI.Flip.moveListItemBy .id offset mediaId model.selectedMedia }
            in
            ( { newModel
                | selectedMediaMoveAnimations =
                    UI.Flip.applyReorder UI.Flip.Horizontal SelectedMediaMoveSettled mediaId neighborId movedEl neighborEl newModel.selectedMediaMoveAnimations
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        AnimateSelectedMediaMove animMsg ->
            let
                step : String -> UI.Flip.MoveState Msg -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) ) -> ( Dict String (UI.Flip.MoveState Msg), List (Cmd Msg) )
                step key state ( states, accCmds ) =
                    let
                        ( newState, cmd ) =
                            UI.Flip.moveAnimate animMsg state
                    in
                    ( Dict.insert key newState states, cmd :: accCmds )

                ( newSelectedMediaMoveAnimations, cmds ) =
                    Dict.foldl step ( Dict.empty, [] ) model.selectedMediaMoveAnimations
            in
            ( { model | selectedMediaMoveAnimations = newSelectedMediaMoveAnimations }, Cmd.batch cmds, ( Nothing, Nothing ) )

        SelectedMediaMoveSettled mediaId ->
            ( { model
                | selectedMediaMoveAnimations =
                    Dict.update mediaId (Maybe.map (\state -> { state | moving = False })) model.selectedMediaMoveAnimations
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        RemoveSelectedMediaClicked mediaId ->
            ( { model
                | selectedMediaAnimations =
                    Dict.update mediaId (Maybe.map (UI.Flip.remove (RemoveSelectedMediaAnimation mediaId))) model.selectedMediaAnimations
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        RemoveSelectedMediaAnimation mediaId ->
            ( { model
                | selectedMedia = List.filter (\media -> media.id /= mediaId) model.selectedMedia
                , selectedMediaAnimations = Dict.remove mediaId model.selectedMediaAnimations
                , selectedMediaMoveAnimations = Dict.remove mediaId model.selectedMediaMoveAnimations
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        SaveMediaClicked _ ->
            -- The saved `List MediaReference` travels on the message itself
            -- (see its own doc) -- nothing here needs it, this just closes
            -- the panel as the visible "saved" feedback, same as
            -- `MediaItemClicked`'s `SingleSelect` branch above.
            ( { init | zoom = model.zoom }, Cmd.none, ( Nothing, Nothing ) )

        NoOp ->
            ( model, Cmd.none, ( Nothing, Nothing ) )


{-| Prepends `mediaRef` to `model.selectedMedia` (seeding a fresh `enter` fade
for it in `selectedMediaAnimations`) -- shared by `MediaItemClicked`'s
`MultiSelect` branch (a tapped grid item) and `GotMediaResult`'s
`pendingUploadSelection` consumption (a just-uploaded item). A no-op if
`mediaRef` is already selected -- re-tapping an already-picked grid item (or,
in principle, re-uploading the exact same already-there id, which can't
actually happen) shouldn't duplicate it in the strip.
-}
addSelectedMedia : MediaReference -> Model -> Model
addSelectedMedia mediaRef model =
    if List.any (\selected -> selected.id == mediaRef.id) model.selectedMedia then
        model

    else
        { model
            | selectedMedia = mediaRef :: model.selectedMedia
            , selectedMediaAnimations = Dict.insert mediaRef.id UI.Flip.enter model.selectedMediaAnimations
        }


{-| DOM id for a selected-media strip item (see `selectedMediaItemView`) --
what `UI.Flip.beginReorder`/`applyReorder` measure pre-swap rects against,
mirroring `AccountsPanel.feedItemChipDomId`.
-}
selectedMediaDomId : String -> String
selectedMediaDomId mediaId =
    "my-media-panel-selected-" ++ mediaId


{-| Reconciles `mediaAnimations` with `status`'s current `Fetched` list:
starts a fade-in for newly-seen media (a fresh `Open`, or a just-uploaded
item once its post-upload refetch lands), a fade-out for media no longer
present (a just-deleted item, once _its_ refetch lands), and un-interrupts a
still-fading-out item that reappeared. Only ever called from `GotMediaResult`
-- deliberately _not_ whenever `status` merely passes through `Fetching`
(e.g. `GotUploadResult`/`GotDeleteResult` kicking off their own refetch),
since that's a transient state with no real `Fetched` list of its own to
reconcile against -- calling this then would read every currently-tracked
tile as "gone" and fade the whole grid out for the length of every refetch.
Mirrors `Components.Pages.UsersPage.syncAnimations` -- see its own doc --
keyed by `Media.id` instead. See `UI.Flip.syncAnimations` for the shared
reconciliation logic this hands its own `MediaAnimation` shape to.
-}
syncMediaAnimations : Model -> Model
syncMediaAnimations model =
    let
        currentMedia : Dict String Media
        currentMedia =
            case model.status of
                Fetched media ->
                    media |> List.map (\m -> ( m.id, m )) |> Dict.fromList

                _ ->
                    Dict.empty
    in
    { model
        | mediaAnimations =
            UI.Flip.syncAnimations
                RemoveMediaAnimation
                (\media -> { media = media, flip = UI.Flip.enter })
                (\media anim -> { anim | media = media })
                currentMedia
                model.mediaAnimations
    }


{-| Shared by `GotFile`/`Drop` -- resolves `targetHost` again (same check
`Open` makes) since either can land well after the account this panel was
opened for stopped being usable (signed out mid-pick, server disabled, ...).
-}
startUpload : AccountsPanel.Model -> Model -> File -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Maybe Media ) )
startUpload accountsPanelModel model file =
    case resolve accountsPanelModel model.targetHost of
        Ok resolved ->
            ( { model | uploadStatus = Uploading file }
            , uploadTask accountsPanelModel resolved model.targetHost file
                |> Task.attempt GotUploadResult
            , ( Nothing, Nothing )
            )

        Err err ->
            ( { model | uploadStatus = UploadFailed file err }, Cmd.none, ( Nothing, Nothing ) )


{-| By extension, same allowlist `frontends/tamagui`'s `media_uploader.tsx`
passes its `<FileUploader>` -- purely a hint to the OS file picker's own
filter, not enforced server-side (and not consulted by `Drop` at all, same as
the React version).
-}
acceptedMimeTypes : List String
acceptedMimeTypes =
    [ "image/jpeg", "image/png", "image/svg+xml", "image/webp", "image/gif", "application/pdf", "video/mp4", "video/quicktime", "video/webm", "audio/mpeg", "audio/ogg" ]


{-| Verifies `host` is actually usable right now -- it resolves to a known,
currently-enabled `Server`, and there's a signed-in `Account` on it (the
account whose media is being browsed/uploaded to). Used by `update`'s `Open`
(to gate the fetch), `startUpload` (to gate an upload), and by `view` (to show
the same problem inline instead of a silent empty panel).
-}
resolve : AccountsPanel.Model -> String -> Result String Resolved
resolve accountsPanelModel host =
    case RellmServers.rellmServerForHost accountsPanelModel.servers host of
        Nothing ->
            Err "That server isn't connected."

        Just server ->
            if not server.enabled then
                Err (server.frontendHost ++ " is disabled.")

            else
                case RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host of
                    Nothing ->
                        Err "You're not signed in on that server."

                    Just account ->
                        Ok { server = server, account = account }


{-| `user_id` is required by `GetMediaRequest` whenever `media_id` isn't set
(`backend/src/rpcs/media/get_media.rs` errors otherwise) -- passing
`account.userId` explicitly, rather than leaving it unset and relying on the
backend's "no user\_id means the caller's own media" fallback, keeps this
request meaningful even though today it only ever runs for the signed-in
account's own chip.
-}
fetchTask : AccountsPanel.Model -> RellmAccount -> Task Grpc.Error ( Maybe AccountsPanel.Msg, GetMediaResponse )
fetchTask accountsPanelModel account =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        ( Just account.userId, account.server )
        (\server token ->
            Grpc.new Rellm.getMedia { defaultGetMediaRequest | userId = Just account.userId }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
        )


{-| The `DeleteMedia` RPC (`protos/rellm.proto`) takes a `Media`, but
`backend/src/rpcs/media/delete_media.rs` only ever looks at its `id` --
`defaultMedia` fills in the rest with placeholders nothing on the backend
reads. Its response is `google.protobuf.Empty`; mapped away to `()` here
purely so `GotDeleteResult` doesn't need its own import of that type.
-}
deleteTask : AccountsPanel.Model -> RellmAccount -> Media -> Task Grpc.Error ( Maybe AccountsPanel.Msg, () )
deleteTask accountsPanelModel account media =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        ( Just account.userId, account.server )
        (\server token ->
            Grpc.new Rellm.deleteMedia { defaultMedia | id = media.id }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (always ())
        )


{-| `user_id` is passed explicitly for the same reason `fetchTask` does --
keeps `performWithAccountServer`'s resolution meaningful even though this only
ever runs for the account this panel was opened for.
-}
uploadTask : AccountsPanel.Model -> Resolved -> String -> File -> Task Grpc.Error ( Maybe AccountsPanel.Msg, String )
uploadTask accountsPanelModel resolved host file =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        ( Just resolved.account.userId, host )
        (\server token -> postMediaTask server token file)


{-| The actual `POST {backendHost}/media` -- see the module doc. `Http.fileBody`
sets `Content-Type` from `file`'s own MIME type, so only `Authorization`/
`Filename` need to be added as headers.
-}
postMediaTask : RellmServer -> String -> File -> Task Grpc.Error String
postMediaTask server token file =
    case RellmServers.connectionOf server of
        -- `server` is reached via `performWithAccountServer`, which only ever
        -- resolves to a connected server -- unreachable in practice.
        Nothing ->
            Task.fail Grpc.NetworkError

        Just connection ->
            Http.task
                { method = "POST"
                , headers =
                    [ Http.header "Authorization" token
                    , Http.header "Filename" (File.name file)
                    ]
                , url = RellmServers.mediaBaseUrl connection ++ "/media"
                , body = Http.fileBody file
                , resolver = Http.stringResolver toGrpcResult
                , timeout = Nothing
                }


{-| Recast as a `Grpc.Error` (rather than `Http.Error`) purely so `update` can
reuse `AccountsPanel.grpcErrorToString` for a user-facing message, same as
`GotMediaResult`'s own error path -- this isn't a real gRPC call, so
`BadStatus`'s `status`/`response` fields are filled with placeholders nothing
here actually inspects.
-}
toGrpcResult : Http.Response String -> Result Grpc.Error String
toGrpcResult response =
    case response of
        Http.BadUrl_ url ->
            Err (Grpc.BadUrl url)

        Http.Timeout_ ->
            Err Grpc.Timeout

        Http.NetworkError_ ->
            Err Grpc.NetworkError

        Http.BadStatus_ metadata body ->
            Err
                (Grpc.BadStatus
                    { metadata = metadata
                    , response = Bytes.Encode.encode (Bytes.Encode.string body)
                    , errMessage = ifNonEmpty body |> Maybe.withDefault metadata.statusText
                    , status = Grpc.Unknown
                    }
                )

        Http.GoodStatus_ _ body ->
            Ok (String.trim body)


ifNonEmpty : String -> Maybe String
ifNonEmpty s =
    if String.isEmpty (String.trim s) then
        Nothing

    else
        Just (String.trim s)


{-| `Components.MediaRenderer.view` renders a `MediaReference`, not the fuller
`Media` `GetMedia` actually returns -- just the fields it shares with
`MediaReference` are needed to preview it.
-}
toMediaReference : Media -> MediaReference
toMediaReference media =
    { id = media.id, author = Maybe.map wrapAuthor media.author, name = media.name, generated = media.generated, metadata = media.metadata, sizes = media.sizes, url = media.url, description = media.description }


{-| Every item Browse mode's grid is currently actually showing, converted to
`MediaReference` and in the exact same order `contentView`'s grid renders
them in -- so `Shared.MediaViewerPanel.Open`'s own left/right paging (see
`update`'s `MediaItemClicked` branch) lines up with the tap the user just
made, and lands on the same neighbors a swipe from that tile would visually
suggest. Reuses `mediaAnimationsInOrder`/`mediaAllowed` rather than
`model.status`'s raw `Fetched` list for exactly the reasoning
`contentView`'s own `orderedAnimations` gives -- a stable sort that doesn't
reshuffle a tile mid removing-fade, and (here, incidentally) one that also
naturally excludes a just-deleted tile's stale id from ever being paged to.
-}
browseMediaReferences : Model -> List MediaReference
browseMediaReferences model =
    mediaAnimationsInOrder model
        |> List.filter (\( _, anim ) -> mediaAllowed model.selectionType anim.media)
        |> List.map (\( _, anim ) -> toMediaReference anim.media)



-- VIEW


{-| Always rendered (even "closed"), same as `UI.elm`'s other panels, so
opening/closing is a plain CSS transition -- see `openClosedClass`. Needs
`AccountsPanel.Model` for the same reason `update` does -- resolving
`targetHost` to the `Server`/`Account` needed to render each media item's URL
and to show `resolve`'s error inline if either's no longer usable.

The whole panel (this root node) is a drop target -- `dragenter`/`dragover`
toggle `is-dragging-over` (a pure CSS hook, see my\_media\_panel.css) and
`drop` hands the dropped files to `Drop`. `dragover` needs its own
`preventDefault` (not just `dragenter`'s) -- browsers refuse to fire `drop` at
all on an element that didn't call `preventDefault` on the _last_ `dragover`
before the drop, not just the first `dragenter`. `dragleave` firing whenever
the pointer crosses from this panel onto one of its own children (not just
when it actually leaves the panel) means `is-dragging-over` can flicker off
briefly while dragging over a media item -- a cosmetic rough edge, not
something `Drop`'s own correctness depends on.

-}
view : Int -> AccountsPanel.Model -> Model -> Html Msg
view windowWidth accountsPanelModel model =
    div
        (classes
            ([ "my-media-panel", "nav-panel", openClosedClass (isOpen model) ]
                ++ (if model.isDraggingOver then
                        [ "is-dragging-over" ]

                    else
                        []
                   )
            )
            :: dropTargetAttributes
        )
        [ div [ class "my-media-panel-header" ]
            [ span [ class "my-media-panel-title" ] [ text (headerTitle model.selectionType) ]
            , div [ class "my-media-panel-header-right" ]
                [ uploadStatusView model.uploadStatus
                , deleteStatusView model.deleteError
                , storageUsageView accountsPanelModel model
                , accountBadge accountsPanelModel model
                , button
                    [ class "my-media-panel-add"
                    , onClick AddClicked
                    , disabled (isUploading model.uploadStatus)
                    ]
                    [ text "+ Add" ]
                , button [ class "my-media-panel-close", onClick CloseClicked ] [ text "✕" ]
                ]
            ]
        , selectedMediaStripView accountsPanelModel model
        , div [ class "my-media-panel-content" ] (contentView accountsPanelModel model)
        , if hasMedia model then
            zoomSliderView windowWidth model

          else
            text ""
        , multiSelectActionsView model
        ]


{-| Whether `contentView` currently has a non-empty grid worth zooming --
gates `zoomSliderView` (see `view`), which would otherwise float uselessly
over "Loading…"/"No media yet."/error text. Reads `mediaAnimations` rather
than `status` directly so the slider stays put through a last remaining
tile's own delete fade-out, instead of vanishing out from under the user's
cursor the instant `status` itself goes empty.
-}
hasMedia : Model -> Bool
hasMedia model =
    not (Dict.isEmpty model.mediaAnimations)


{-| "My Media" in plain Browse mode, "Select Media" while `selectionType` is
`Just` anything -- see module doc.
-}
headerTitle : Maybe SelectionType -> String
headerTitle selectionType =
    case selectionType of
        Just _ ->
            "Select Media"

        Nothing ->
            "My Media"


{-| Whether `media` belongs in the grid at all under `selectionType` -- only
`SingleSelect`'s `imagesOnly` ever excludes anything (any media type is fine
in Browse mode or under a future `imagesOnly = False` chooser); mirrors
`Components.MediaRenderer.view`'s own content-type switch, which already
only ever attaches a click handler to images in the first place.
-}
mediaAllowed : Maybe SelectionType -> Media -> Bool
mediaAllowed selectionType media =
    case selectionType of
        Just (SingleSelect { imagesOnly }) ->
            not imagesOnly || String.startsWith "image/" (MediaRenderer.contentTypeOf media)

        Just (MultiSelect _) ->
            True

        Nothing ->
            True


isUploading : UploadStatus -> Bool
isUploading status =
    case status of
        Uploading _ ->
            True

        _ ->
            False


dropTargetAttributes : List (Html.Attribute Msg)
dropTargetAttributes =
    [ preventDefaultOn "dragover" (Decode.succeed ( DragEnter, True ))
    , on "dragenter" (Decode.succeed DragEnter)
    , on "dragleave" (Decode.succeed DragLeave)
    , preventDefaultOn "drop" (Decode.map (\files -> ( Drop files, True )) droppedFilesDecoder)
    ]


{-| Per `File.decoder`'s own doc example.
-}
droppedFilesDecoder : Decode.Decoder (List File)
droppedFilesDecoder =
    Decode.field "dataTransfer" (Decode.field "files" (Decode.list File.decoder))


uploadStatusView : UploadStatus -> Html Msg
uploadStatusView status =
    case status of
        NotUploading ->
            text ""

        Uploading file ->
            span [ class "my-media-panel-upload-status" ] [ text ("Uploading " ++ File.name file ++ "…") ]

        UploadFailed file err ->
            span [ classes [ "my-media-panel-upload-status", "my-media-panel-upload-error" ] ]
                [ text ("Couldn't upload " ++ File.name file ++ ": " ++ err) ]


{-| `uploadStatusView`'s counterpart for `deleteError` -- deletes don't have
an in-progress message of their own here (that's shown inline on the item
itself, see `mediaItemView`'s "Deleting…"), only a failure.
-}
deleteStatusView : Maybe String -> Html Msg
deleteStatusView deleteError =
    case deleteError of
        Nothing ->
            text ""

        Just err ->
            span [ classes [ "my-media-panel-upload-status", "my-media-panel-upload-error" ] ]
                [ text ("Couldn't delete: " ++ err) ]


{-| The account whose media this panel is browsing, shown as an avatar +
username between the title and close button so it's clear whose media is on
screen -- resolves the same way `contentView` does, but renders nothing if
`resolve` fails (that error's already shown in the content area below, no
need to duplicate it up here).
-}
accountBadge : AccountsPanel.Model -> Model -> Html Msg
accountBadge accountsPanelModel model =
    case resolve accountsPanelModel model.targetHost of
        Err _ ->
            text ""

        Ok resolved ->
            div [ class "my-media-panel-account" ]
                [ avatarOrInitial accountsPanelModel.servers resolved.account
                , span [ class "my-media-panel-username" ] [ text (RellmAccounts.rellmAccountDisplayName resolved.account) ]
                ]


{-| A minimal "X of Y used" (or just "X used" if unlimited) readout of the resolved account's
Media storage, shown next to `accountBadge` in the header -- see `User.mediaStorageBytesUsed`/
`.mediaStorageLimitBytes`'s own proto doc. `text ""` (nothing shown) if the panel isn't resolved
to a live account, matching `accountBadge`'s own fallback.
-}
storageUsageView : AccountsPanel.Model -> Model -> Html Msg
storageUsageView accountsPanelModel model =
    case resolve accountsPanelModel model.targetHost of
        Err _ ->
            text ""

        Ok resolved ->
            span [ class "my-media-panel-storage-usage" ]
                [ text
                    (case resolved.account.mediaStorageLimitBytes of
                        Just limit ->
                            ByteFormat.formatBytes resolved.account.mediaStorageBytesUsed ++ " / " ++ ByteFormat.formatBytes limit ++ " used"

                        Nothing ->
                            ByteFormat.formatBytes resolved.account.mediaStorageBytesUsed ++ " used"
                    )
                ]


{-| A trimmed-down copy of `UI.imageOrInitial`, scoped to this panel's own
avatar -- `UI` itself imports this module (to embed `MyMediaPanel.view`), so
importing it back here to reuse that helper would be a circular import.
-}
avatarOrInitial : List RellmServer -> RellmAccount -> Html msg
avatarOrInitial servers account =
    case RellmAccounts.rellmAccountAvatarUrl servers account of
        Just url ->
            img [ class "my-media-panel-avatar", src url, alt account.username, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes [ "my-media-panel-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter account.username) ]


contentView : AccountsPanel.Model -> Model -> List (Html Msg)
contentView accountsPanelModel model =
    case resolve accountsPanelModel model.targetHost of
        Err err ->
            [ div [ class "my-media-panel-message" ] [ text err ] ]

        Ok resolved ->
            let
                orderedAnimations : List ( String, MediaAnimation )
                orderedAnimations =
                    mediaAnimationsInOrder model
                        |> List.filter (\( _, anim ) -> mediaAllowed model.selectionType anim.media)
            in
            if not (List.isEmpty orderedAnimations) then
                -- Keeps the grid itself mounted (so already-there tiles keep
                -- their DOM nodes, key for key) through a *re*-fetch's own
                -- transient `Fetching` -- `GotUploadResult`/`GotDeleteResult`
                -- both set `status` back to `Fetching` while their own
                -- refetch is in flight (see `update`). Swapping the whole
                -- grid out for a "Loading…" message and back, as a plain
                -- `case model.status of` would, unmounts and remounts every
                -- tile in between -- a freshly-mounted node has no prior
                -- frame to transition *from*, so `syncMediaAnimations`
                -- marking a just-deleted tile `removing` right as it
                -- remounts would just render it already-collapsed instead of
                -- animating the collapse. `status` still gates *which*
                -- `Fetching`/`FetchFailed`/`NotFetched` message to show
                -- below -- just only once there's nothing left to show in
                -- its place.
                [ Html.Keyed.node "div"
                    [ classes [ "my-media-panel-grid", "flip-animated-grid" ]

                    -- Read by `my_media_panel.css`'s own override of
                    -- `.media-renderer-extra-small`'s fixed max-width/
                    -- height (see `media.css`) -- letting `zoomSliderView`
                    -- resize every item without `MediaRenderer` itself
                    -- needing a third, continuously-sized `Sizing`.
                    --
                    -- This has to go through `attribute "style"` (a raw
                    -- style-attribute *string*, parsed by the browser's
                    -- own CSS parser) rather than `Html.Attributes.style`
                    -- -- elm/virtual-dom applies the latter as
                    -- `domNode.style[key] = value` (plain bracket
                    -- assignment), which silently no-ops for a custom
                    -- property (`--*`) key: the DOM only picks up custom
                    -- properties set via `style.setProperty` or, as here,
                    -- parsed from the attribute string. A named property
                    -- like `color` works with either, which is why this
                    -- doesn't show up anywhere else in this codebase.
                    , attribute "style" ("--my-media-zoom-size: " ++ String.fromFloat model.zoom ++ "px;")
                    ]
                    (List.map (mediaAnimationView resolved.server resolved.account model) orderedAnimations)
                ]

            else
                case model.status of
                    NotFetched ->
                        []

                    Fetching ->
                        [ div [ class "my-media-panel-message" ] [ text "Loading…" ] ]

                    FetchFailed err ->
                        [ div [ class "my-media-panel-message" ] [ text err ] ]

                    Fetched _ ->
                        [ div [ class "my-media-panel-message" ] [ text "No media yet." ] ]


{-| `mediaAnimations` in display order -- sorted newest-first by each tile's
own `media.createdAt`, mirroring `Components.Pages.PostsPage.postAnimationView`
call site's `List.sortBy (Posts.postTimestamp ...)` and
`Components.Pages.UsersPage.usersListView`'s sort by username exactly: a
stable sort on a value that never changes for an item already being displayed
(unlike "current fetch order, plus whichever ids are mid removing-fade tacked
on separately") means a tile that starts removing keeps its exact rank
relative to every other tile without moving -- which matters here more than
it's just tidy: reordering a keyed DOM node and changing the class that
starts its remove-fade in the same patch silently cancels the CSS collapse
transition in every browser tested (confirmed via a real delete, instrumented
headless -- no `transitionrun` event at all, the tile's width just snaps
straight to its collapsed value). A still-removing tile whose id has already
dropped out of `status`'s own `Fetched` list keeps rendering here purely
because it's still in `mediaAnimations` at all (see `syncMediaAnimations`) --
its `createdAt` came along for the ride in `MediaAnimation.media`.
-}
mediaAnimationsInOrder : Model -> List ( String, MediaAnimation )
mediaAnimationsInOrder model =
    model.mediaAnimations
        |> Dict.toList
        |> List.sortBy (\( _, anim ) -> -(Time.posixToMillis (mediaTimestamp anim.media)))


{-| A media item's "recency" sort key -- mirrors `Components.Posts.postTimestamp`
exactly, just falling straight back to `Time.millisToPosix 0` since `Media`
(unlike `Post`) has no separate `publishedAt` to prefer first.
-}
mediaTimestamp : Media -> Time.Posix
mediaTimestamp media =
    case media.createdAt of
        Just ts ->
            timestampToPosix ts

        Nothing ->
            Time.millisToPosix 0


{-| Wraps `mediaItemView` in a fading/scaling/collapsing animated outer `div`
(entering when freshly uploaded/loaded, removing when deleted -- see
`mediaAnimations`) -- the `UI.Flip.Horizontal` axis matches the grid's own
left-to-right, wrap-to-next-row flow (see `flip.css`'s `.flip-animated-grid`
doc). Mirrors `UI.serverChipFlip` -- see its own doc.
-}
mediaAnimationView : RellmServer -> RellmAccount -> Model -> ( String, MediaAnimation ) -> ( String, Html Msg )
mediaAnimationView server account model ( mediaId, anim ) =
    let
        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if anim.flip.removing then
                [ style "pointer-events" "none" ]

            else
                []

        selected : Bool
        selected =
            List.any (\m -> m.id == mediaId) model.selectedMedia
    in
    ( mediaId
    , div (UI.Flip.itemAttributes UI.Flip.Horizontal anim.flip False)
        [ div pointerEventsAttr [ mediaItemView server account model.targetHost model.deletingIds selected anim.media ] ]
    )


{-| `selected` (true while this grid item's id is currently in
`model.selectedMedia`, i.e. `MultiSelect` mode's own picked list -- always
`False` outside that mode, nothing else ever sets it) tints the tile with
`background-color-primary` (the same utility class `serverChip`'s own
selected-state and `postCardView`'s `current` card use for "this one's
picked/active") so a glance at the grid shows what's already in the strip
above without needing to scan it -- picking the same already-selected item
again is a no-op (see `MediaItemClicked`'s `MultiSelect` branch), so this is
purely a "you already have this" signal, not a toggle indicator. That utility
class is per-server (see `UI.EmittedStylesheet`), so it only takes effect
paired with `targetHost`'s own `hostnameToCSSClass` on the very same element
-- omitted entirely while `not selected`, rather than always present, so this
tile doesn't pick up any of that server's _other_ `hostnameToCSSClass`-scoped
rules (e.g. anchor-colored links) it has no reason to.

The whole tile is clickable (`onClick`, below) -- not just `MediaRenderer.view`'s
own image click, which alone would leave the name/type text and the tile's own
thin padding (`my_media_panel.css`) dead to the touch. Firing the same
`MediaItemClicked` from both is harmless: `update`'s `MultiSelect` branch
already no-ops re-adding an already-selected id, and `SingleSelect` already
closes the panel on the first of the two, making the second (bubbled) dispatch
land back in `selectionType == Nothing` -- also a no-op. The delete button
still needs `stopPropagationOn` -- without it, a click there would bubble up
into this same handler and select/re-add the very item just deleted.

-}
mediaItemView : RellmServer -> RellmAccount -> String -> Set String -> Bool -> Media -> Html Msg
mediaItemView server account targetHost deletingIds selected media =
    let
        deleting : Bool
        deleting =
            Set.member media.id deletingIds

        itemClasses : List String
        itemClasses =
            "my-media-panel-item"
                :: (if selected then
                        [ hostnameToCSSClass targetHost, "background-color-primary" ]

                    else
                        []
                   )
    in
    div [ classes itemClasses, onClick (MediaItemClicked media.id) ]
        [ div [ class "my-media-panel-item-preview" ]
            [ MediaRenderer.view MediaRenderer.ExtraSmall MediaRenderer.ToWidthAndHeight server (Just account) MediaItemClicked (toMediaReference media)
            , button
                [ classes [ "remove-btn", "my-media-panel-item-delete" ]
                , stopPropagationOn "click" (Decode.succeed ( DeleteClicked media, True ))
                , disabled deleting
                , title "Delete this media"
                ]
                [ text "╳" ]
            ]
        , div [ class "my-media-panel-item-name" ] [ text (Maybe.withDefault "Untitled" media.name) ]
        , div [ class "my-media-panel-item-type" ]
            [ text
                (if deleting then
                    "Deleting…"

                 else
                    MediaRenderer.contentTypeOf media
                )
            ]
        ]



-- SELECTED MEDIA (MultiSelect)


{-| The top "selected media" strip -- only rendered while `selectionType` is
`Just (MultiSelect _)` (`text ""` otherwise, same as `multiSelectActionsView`
below), and only once `resolve` succeeds (needed to render each item's own
`MediaRenderer.view`, same requirement `contentView`'s grid has). Left to
right in `model.selectedMedia`'s own order (see its own doc on why that's a
plain, caller-owned list rather than something re-derived/sorted) via
`Html.Keyed`, same `.flip-animated-row` layout `UI.serversStrip` uses for the
Servers strip.
-}
selectedMediaStripView : AccountsPanel.Model -> Model -> Html Msg
selectedMediaStripView accountsPanelModel model =
    case ( model.selectionType, resolve accountsPanelModel model.targetHost ) of
        ( Just (MultiSelect _), Ok resolved ) ->
            let
                count : Int
                count =
                    List.length model.selectedMedia
            in
            Html.Keyed.node "div"
                [ classes [ "my-media-panel-selected-strip", "flip-animated-row" ] ]
                (List.indexedMap
                    (\index media -> ( media.id, selectedMediaItemFlip resolved.server resolved.account model count index media ))
                    model.selectedMedia
                )

        _ ->
            text ""


{-| Wraps `selectedMediaItemView` in a fading/scaling/collapsing animated
outer `div` (entering when freshly added, removing when its own Delete button
is clicked) plus its independent reorder-slide -- exactly mirrors
`UI.serverChipFlip`/`serverChip`'s own two-layer split (see its doc for the
full reasoning), `UI.Flip.Horizontal` to match this strip's own left-to-right
flow.
-}
selectedMediaItemFlip : RellmServer -> RellmAccount -> Model -> Int -> Int -> MediaReference -> Html Msg
selectedMediaItemFlip server account model count index media =
    let
        flipState : UI.Flip.State Msg
        flipState =
            Dict.get media.id model.selectedMediaAnimations |> Maybe.withDefault UI.Flip.restingState

        isMoving : Bool
        isMoving =
            Dict.get media.id model.selectedMediaMoveAnimations |> Maybe.map .moving |> Maybe.withDefault False

        pointerEventsAttr : List (Html.Attribute Msg)
        pointerEventsAttr =
            if flipState.removing then
                [ style "pointer-events" "none" ]

            else
                []
    in
    div (UI.Flip.itemAttributes UI.Flip.Horizontal flipState isMoving)
        [ div pointerEventsAttr [ selectedMediaItemView server account model.selectedMediaMoveAnimations count index media ] ]


{-| One selected-media strip item: an `ExtraSmall` preview (tapping it is a
no-op, see `NoOp`'s own doc), flanked by a ◀/▶ reorder pair (mirroring
`serverChip`'s own, disabled/hidden at whichever end `index` can't move
past -- there's no fixed "main" item pinning one end the way Servers' main
server does, so unlike `serverChip` both ends are only ever gated by
`index`/`count`) and a `Delete` button that removes this item from the
selection outright (`RemoveSelectedMediaClicked`) -- no confirmation, see
that message's own doc for why.
-}
selectedMediaItemView : RellmServer -> RellmAccount -> Dict String (UI.Flip.MoveState Msg) -> Int -> Int -> MediaReference -> Html Msg
selectedMediaItemView server account moveAnimations count index media =
    let
        moveAttrs : List (Html.Attribute Msg)
        moveAttrs =
            moveAnimations |> Dict.get media.id |> Maybe.map UI.Flip.moveAttributes |> Maybe.withDefault []

        canMoveBackward : Bool
        canMoveBackward =
            index > 0

        canMoveForward : Bool
        canMoveForward =
            index < count - 1

        reorderPair : { backward : Html Msg, forward : Html Msg }
        reorderPair =
            UI.Flip.reorderButtonPair UI.Flip.Horizontal
                { moveBackward = onClick (MoveSelectedMediaLeftClicked media.id)
                , moveForward = onClick (MoveSelectedMediaRightClicked media.id)
                , canMoveBackward = canMoveBackward
                , canMoveForward = canMoveForward
                }
    in
    div
        (id (selectedMediaDomId media.id) :: class "my-media-panel-selected-item" :: moveAttrs)
        [ div [ class "my-media-panel-selected-item-preview" ]
            [ MediaRenderer.view MediaRenderer.ExtraSmall MediaRenderer.ToWidthAndHeight server (Just account) (\_ -> NoOp) media ]
        , div [ class "my-media-panel-selected-item-controls" ]
            [ div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not canMoveBackward ) ] ] [ reorderPair.backward ]
            , button
                [ classes [ "remove-btn", "my-media-panel-selected-item-delete" ]
                , onClick (RemoveSelectedMediaClicked media.id)
                , title "Remove from selection"
                ]
                [ text "╳" ]
            , div [ classList [ ( "reorder-arrow", True ), ( "reorder-arrow-hidden", not canMoveForward ) ] ] [ reorderPair.forward ]
            ]
        ]


{-| `model.selectedMedia`, minus anything still mid removing-fade (see
`RemoveSelectedMediaClicked`'s own doc) -- what `multiSelectActionsView`'s
Save button actually sends on `SaveMediaClicked`, so a fast double-click
right after removing an item can't resurrect it in the saved result just
because its fade hadn't finished yet.
-}
currentSelectedMedia : Model -> List MediaReference
currentSelectedMedia model =
    model.selectedMedia
        |> List.filter
            (\media ->
                Dict.get media.id model.selectedMediaAnimations
                    |> Maybe.map (\flip -> not flip.removing)
                    |> Maybe.withDefault True
            )


{-| The bottom "Cancel"/"Save Media" row, shown only while `selectionType` is
`Just (MultiSelect _)` -- "Cancel" is just `CloseClicked` reused as-is (same
as the header's own ✕), "Save Media" fires `SaveMediaClicked` carrying
`currentSelectedMedia`'s own in-order list. See `SaveMediaClicked`'s own doc
for why the list travels on the message rather than being re-read from
`model` by whichever page picks this up.
-}
multiSelectActionsView : Model -> Html Msg
multiSelectActionsView model =
    case model.selectionType of
        Just (MultiSelect _) ->
            div [ class "my-media-panel-multi-select-actions" ]
                [ button [ class "my-media-panel-cancel", onClick CloseClicked ] [ text "Cancel" ]
                , button
                    [ classes [ "my-media-panel-save", "background-color-primary" ]
                    , onClick (SaveMediaClicked (currentSelectedMedia model))
                    ]
                    [ text "Save Media" ]
                ]

        _ ->
            text ""


{-| Floats over `.my-media-panel-content`'s own scrolling (see
`my_media_panel.css`'s `.my-media-panel-zoom`, `position: absolute` within
this panel's `position: fixed` root) rather than sitting inline in the
header/content flow, so it stays reachable at a constant spot regardless of
how far the grid's scrolled -- a plain sibling of `.my-media-panel-content`,
deliberately not nested inside it: nesting it there would make it scroll away
with that content instead of staying put, since `position: absolute` is
relative to (and scrolls along with) the nearest positioned _scrolling_
ancestor, not just the nearest positioned one outright. `my_media_panel.css`
shifts it up clear of `multiSelectActionsView`'s row once that exists, purely
via a `:has()` sibling selector -- no Elm-side state needed for that. Drives
every item's size via a CSS custom property rather than each `input` event
re-rendering the whole grid through `Sizing` -- see `contentView`'s `Fetched`
branch.
-}
zoomSliderView : Int -> Model -> Html Msg
zoomSliderView windowWidth model =
    div [ class "my-media-panel-zoom" ]
        [ span [ class "my-media-panel-zoom-icon" ] [ text "🔍" ]
        , input
            [ type_ "range"
            , Html.Attributes.min "42"
            , Html.Attributes.max (String.fromFloat (min 800 (0.9 * toFloat windowWidth)))
            , step "8"
            , value (String.fromFloat model.zoom)
            , onInput (\v -> ZoomChanged (String.toFloat v |> Maybe.withDefault model.zoom))
            , title "Preview size"
            ]
            []
        ]
