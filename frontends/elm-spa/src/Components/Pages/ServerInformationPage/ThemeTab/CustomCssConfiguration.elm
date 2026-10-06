module Components.Pages.ServerInformationPage.ThemeTab.CustomCssConfiguration exposing (Model, Msg, applySharedMsg, draftPreviewEffect, fetch, init, update, view)

{-| The "Custom CSS" section of `Components.Pages.ServerInformationPage.ThemeTab` -- the server's
`CustomCSSConfiguration` (an ordered list of `media_ids`, exposed to the stylesheet as the CSS vars
`--custom-media-1`, `--custom-media-2`, ..., plus the CSS text itself), editable by an admin with
the same Edit/Save/Cancel flow as every other section here.

Unlike every other section on this page, this one isn't part of `ServerConfiguration` at all (see
`CustomCSSConfiguration`'s own proto doc): it's read with its own public `GetCustomCSS` (fired by
`ServerInformationPage` alongside its other on-load fetches, see `fetch`) and written with its own
admin-only `ConfigureCustomCSS` -- so there's no `AccountsPanel.updateServerConfig` "re-fetch the
whole config, overlay one change" dance here; `ConfigureCustomCSS` replaces the whole (small)
`CustomCSSConfiguration` and the backend carries every other setting forward itself.

Display mode renders the CSS through `Components.Markdown` as a fenced `css` block, so it picks up
the same syntax highlighting post content gets; both modes cap the section's height to roughly the
viewport (see `.custom-css-scroll` in `servers.css`) with the CSS itself scrolling inside.

Media is picked with `Shared.MyMediaPanel`'s `MultiSelect` (same picker Posts use) -- the panel
reports back through a forwarded `Shared.Msg` (`applySharedMsg`), gated on `pickingMedia` so an
unrelated Save from some other use of the panel can't be mistaken for this one's pick.

While editing the page's own server's CSS (`targetHost == mainFrontendHost`), the draft is applied live
as a preview via `AccountsPanel.customCssOverride` (see `UI.CustomCssStylesheet`): every draft change
sets it (`draftPreviewEffect`), Cancel puts back whatever it was before the edit (`Edit.restoreTo`), and
a successful Save installs the saved config, so the change shows without a reload.

-}

import Components.Markdown as Markdown
import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, button, div, h3, img, p, span, text, textarea)
import Html.Attributes exposing (class, placeholder, rows, spellcheck, src, title, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (CustomCSSConfiguration, defaultMediaReference)
import Proto.Rellm.Rellm as Rellm
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.MyMediaPanel as MyMediaPanel
import Task
import UI.Classes exposing (classes)



-- MODEL


type alias Model =
    { saved : SavedStatus
    , edit : Maybe Edit
    }


{-| The server's current `CustomCSSConfiguration`, as last fetched/saved.
-}
type SavedStatus
    = NotLoaded
    | Loaded CustomCSSConfiguration
    | LoadFailed String


{-| Live only while an admin is editing -- independent of `saved` until `SaveClicked` succeeds.
`pickingMedia` is true from `ChooseMediaClicked` until `Shared.MyMediaPanel` reports back.
-}
type alias Edit =
    { mediaIds : List String
    , css : String
    , pickingMedia : Bool
    , status : AccountsPanel.FormStatus

    -- `AccountsPanel.customCssOverride` as of `EditClicked`, restored on Cancel.
    , restoreTo : Maybe CustomCSSConfiguration
    }


type Msg
    = GotCustomCss (Result Grpc.Error CustomCSSConfiguration)
    | EditClicked
    | CancelClicked
    | SaveClicked
    | GotSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, CustomCSSConfiguration ))
    | CssChanged String
    | ChooseMediaClicked
    | RemoveMediaClicked String


init : Model
init =
    { saved = NotLoaded, edit = Nothing }


{-| `GetCustomCSS` against `server` -- public, so no account needed.
-}
fetch : RellmServer -> Effect Msg
fetch server =
    Grpc.new Rellm.getCustomCSS {}
        |> Grpc.setHost (RellmServers.rellmServerUrl server)
        |> Grpc.toTask
        |> Task.attempt GotCustomCss
        |> Effect.fromCmd



-- UPDATE


update : Shared.Model -> String -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost msg model =
    let
        ( newModel, effect ) =
            updateInner shared targetHost msg model
    in
    ( newModel, Effect.batch [ effect, draftPreviewEffect shared targetHost model newModel ] )


updateInner : Shared.Model -> String -> Msg -> Model -> ( Model, Effect Msg )
updateInner shared targetHost msg model =
    case msg of
        GotCustomCss (Ok config) ->
            ( { model | saved = Loaded config }, Effect.none )

        GotCustomCss (Err err) ->
            ( { model | saved = LoadFailed (AccountsPanel.grpcErrorToString err) }, Effect.none )

        EditClicked ->
            case model.saved of
                Loaded config ->
                    ( { model | edit = Just { mediaIds = config.mediaIds, css = config.customCss, pickingMedia = False, status = AccountsPanel.Idle, restoreTo = shared.accounts.customCssOverride } }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        CancelClicked ->
            ( { model | edit = Nothing }
            , case model.edit of
                Just edit ->
                    Effect.batch
                        [ if edit.pickingMedia then
                            Effect.fromShared (Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked)

                          else
                            Effect.none
                        , setOverride shared targetHost edit.restoreTo
                        ]

                Nothing ->
                    Effect.none
            )

        SaveClicked ->
            case ( model.edit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    let
                        request : CustomCSSConfiguration
                        request =
                            { mediaIds = edit.mediaIds, customCss = edit.css }
                    in
                    ( mapEdit (\e -> { e | status = AccountsPanel.Submitting }) model
                    , AccountsPanel.performWithAccountServer shared.accounts
                        ( Just account.userId, targetHost )
                        (\server token ->
                            Grpc.new Rellm.configureCustomCSS request
                                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                                |> RellmServers.withAccessToken (Just token)
                                |> Grpc.toTask
                        )
                        |> Task.attempt GotSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotSaveResult (Ok ( maybeAccountsPanelMsg, config )) ->
            ( { model | saved = Loaded config, edit = Nothing }
            , Effect.batch [ Common.accountsPanelEffect maybeAccountsPanelMsg, setOverride shared targetHost (Just config) ]
            )

        GotSaveResult (Err err) ->
            ( mapEdit (\e -> { e | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) model
            , Effect.none
            )

        CssChanged css ->
            ( mapEdit (\e -> { e | css = css }) model, Effect.none )

        ChooseMediaClicked ->
            case model.edit of
                Just edit ->
                    ( mapEdit (\e -> { e | pickingMedia = True }) model
                    , Effect.fromShared
                        (Shared.MyMediaPanelMsg
                            (MyMediaPanel.Open
                                (Just (MyMediaPanel.MultiSelect { initialSelection = List.map (\id -> { defaultMediaReference | id = id }) edit.mediaIds }))
                                targetHost
                            )
                        )
                    )

                Nothing ->
                    ( model, Effect.none )

        RemoveMediaClicked mediaId ->
            ( mapEdit (\e -> { e | mediaIds = List.filter (\id -> id /= mediaId) e.mediaIds }) model, Effect.none )


{-| Sets `AccountsPanel.customCssOverride`, but only when `targetHost` is the page's own server -- another
server's Custom CSS has no business styling this page.
-}
setOverride : Shared.Model -> String -> Maybe CustomCSSConfiguration -> Effect msg
setOverride shared targetHost maybeConfig =
    if targetHost == shared.accounts.mainFrontendHost then
        Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.SetCustomCssOverride maybeConfig))

    else
        Effect.none


{-| The live preview: whenever the draft's media or CSS differ between `before` and `after`, applies
the draft as `customCssOverride`. Run after every `update`, and by `ServerInformationPage` after a
forwarded `Shared.Msg` (`applySharedMsg` is pure, so a picked-media change can't emit it itself).
-}
draftPreviewEffect : Shared.Model -> String -> Model -> Model -> Effect msg
draftPreviewEffect shared targetHost before after =
    case ( before.edit, after.edit ) of
        ( Just b, Just a ) ->
            if b.mediaIds /= a.mediaIds || b.css /= a.css then
                setOverride shared targetHost (Just { mediaIds = a.mediaIds, customCss = a.css })

            else
                Effect.none

        _ ->
            Effect.none


mapEdit : (Edit -> Edit) -> Model -> Model
mapEdit f model =
    { model | edit = Maybe.map f model.edit }


{-| Reacts to a `Shared.Msg` forwarded through `ThemeTab`'s own `SharedMsg` branch -- the
`MultiSelect` picker's Save (`SaveMediaClicked`, carrying the final ordered selection) or
cancel (`CloseClicked`), each gated on `pickingMedia` (see this module's doc).
-}
applySharedMsg : Shared.Msg -> Model -> Model
applySharedMsg subMsg model =
    case subMsg of
        Shared.MyMediaPanelMsg (MyMediaPanel.SaveMediaClicked mediaRefs) ->
            mapPicking (\e -> { e | mediaIds = List.map .id mediaRefs, pickingMedia = False }) model

        Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked ->
            mapPicking (\e -> { e | pickingMedia = False }) model

        _ ->
            model


mapPicking : (Edit -> Edit) -> Model -> Model
mapPicking f model =
    mapEdit
        (\e ->
            if e.pickingMedia then
                f e

            else
                e
        )
        model



-- VIEW


view : RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view server maybeAdminAccount model =
    div [ class "server-details-custom-css" ]
        [ h3 [ class "section-title" ] [ text "Custom CSS" ]
        , case ( model.edit, model.saved ) of
            ( Just edit, _ ) ->
                editorView server edit

            ( Nothing, Loaded config ) ->
                div []
                    [ displayView server config
                    , case maybeAdminAccount of
                        Just _ ->
                            button [ class "server-details-rename-button", onClick EditClicked ] [ text "Edit Custom CSS" ]

                        Nothing ->
                            text ""
                    ]

            ( Nothing, NotLoaded ) ->
                p [ class "server-details-feature-settings-note" ] [ text "Loading…" ]

            ( Nothing, LoadFailed err ) ->
                p [ class "server-details-rename-error" ] [ text err ]
        ]


displayView : RellmServer -> CustomCSSConfiguration -> Html Msg
displayView server config =
    if List.isEmpty config.mediaIds && String.isEmpty config.customCss then
        p [ class "server-details-feature-settings-note" ] [ text "No custom CSS." ]

    else
        div [ class "custom-css-section" ]
            [ mediaListView server Nothing config.mediaIds
            , if String.isEmpty config.customCss then
                text ""

              else
                div [ class "custom-css-scroll" ] [ Markdown.view [ class "custom-css-highlighted" ] (cssFence config.customCss) ]
            ]


editorView : RellmServer -> Edit -> Html Msg
editorView server edit =
    div [ class "custom-css-section" ]
        [ mediaListView server (Just RemoveMediaClicked) edit.mediaIds
        , button [ class "server-details-rename-button", onClick ChooseMediaClicked ]
            [ text
                (if List.isEmpty edit.mediaIds then
                    "Choose Media"

                 else
                    "Change Media"
                )
            ]
        , textarea
            [ class "custom-css-textarea"
            , rows 16
            , spellcheck False
            , placeholder "/* Appended to the default CSS. Use var(--custom-media-1) etc. for the media above. */"
            , value edit.css
            , onInput CssChanged
            ]
            []
        , div [ class "server-details-rename-actions" ]
            [ Common.editSaveButton SaveClicked edit.status
            , Common.editCancelButton CancelClicked edit.status
            , Common.editErrorView edit.status
            ]
        ]


{-| One thumbnail per media id, labelled with the CSS var it becomes (`--custom-media-N`, 1-based, in
list order -- same numbering the backend's `custom_css_stylesheet` emits). `onRemove` adds a ✕ button
(editor only).
-}
mediaListView : RellmServer -> Maybe (String -> Msg) -> List String -> Html Msg
mediaListView server onRemove mediaIds =
    if List.isEmpty mediaIds then
        text ""

    else
        div [ class "custom-css-media-list" ]
            (mediaIds
                |> List.indexedMap
                    (\index mediaId ->
                        div [ class "custom-css-media-item" ]
                            [ case RellmServers.mediaUrl server mediaId of
                                Just url ->
                                    img [ class "custom-css-media-thumb", src url ] []

                                Nothing ->
                                    text ""
                            , span [ class "custom-css-media-var" ] [ text ("--custom-media-" ++ String.fromInt (index + 1)) ]
                            , case onRemove of
                                Just remove ->
                                    button [ classes [ "remove-btn" ], title "Remove this media", onClick (remove mediaId) ] [ text "╳" ]

                                Nothing ->
                                    text ""
                            ]
                    )
            )


{-| `css` as a fenced ```css block for `Components.Markdown` -- the fence is lengthened until it's
longer than any run of backticks in `css`, so stylesheet content can't close it early.
-}
cssFence : String -> String
cssFence css =
    let
        fence : String -> String
        fence candidate =
            if String.contains candidate css then
                fence (candidate ++ "`")

            else
                candidate

        ticks : String
        ticks =
            fence "```"
    in
    ticks ++ "css\n" ++ css ++ "\n" ++ ticks
