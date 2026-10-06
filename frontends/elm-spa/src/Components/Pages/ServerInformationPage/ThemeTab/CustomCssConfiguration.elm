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

The "Apply Template" dropdown (see `Components.Pages.ServerInformationPage.ThemeTab.CustomCssTemplates`)
replaces the CSS text with a starter stylesheet -- "Undo template" puts back what was there -- and reminds
the admin to choose as many images as the template uses.

"Preview" (only offered while editing the page's own server's CSS, `canPreview`) applies the draft to this
very page through `AccountsPanel.customCssPreview`: the saved stylesheet is switched off for the duration
(see `Ports.setCustomCssStylesheet`) so the draft *replaces* it rather than layering on top, and while it's
on, every further edit to the CSS or media (`draftPreviewEffect`) re-applies. It's deliberately an explicit
toggle, not automatic -- a half-typed rule can make the page unusable. Stop Preview, Cancel, Save, or
navigating away all end it; a reload does too, since nothing persists it. A successful Save hands the saved
config to `AccountsPanel.CustomCssSaved`, which reloads the stylesheet so the change shows immediately.

-}

import Components.Markdown as Markdown
import Components.Pages.ServerInformationPage.Common as Common
import Effect exposing (Effect)
import Grpc
import Components.Pages.ServerInformationPage.ThemeTab.CustomCssTemplates as CustomCssTemplates
import Html exposing (Html, button, code, div, h3, img, option, p, span, text, textarea)
import Html.Attributes exposing (attribute, class, disabled, placeholder, rows, selected, spellcheck, src, style, title, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
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

    -- "Force light/dark theme" -- at most one is ever on (turning one on turns the other off; the server
    -- rejects both too).
    , forceLight : Bool
    , forceDark : Bool
    , pickingMedia : Bool
    , status : AccountsPanel.FormStatus

    -- Whether "Preview" is on -- see this module's doc.
    , previewing : Bool

    -- The CSS and forced theme from before the last template was applied, for "Undo template".
    , previous : Maybe Snapshot
    }


{-| What "Undo template" puts back: a template replaces the CSS *and* sets the forced theme to its own.
-}
type alias Snapshot =
    { css : String
    , forceLight : Bool
    , forceDark : Bool
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
    | ForceLightToggled
    | ForceDarkToggled
    | TemplateSelected String
    | UndoTemplateClicked
    | PreviewClicked


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
    ( newModel, Effect.batch [ effect, draftPreviewEffect model newModel ] )


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
                    ( { model
                        | edit =
                            Just
                                { mediaIds = config.mediaIds
                                , css = Maybe.withDefault "" config.customCss
                                , forceLight = config.forceLightTheme
                                , forceDark = config.forceDarkTheme
                                , pickingMedia = False
                                , status = AccountsPanel.Idle
                                , previewing = False
                                , previous = Nothing
                                }
                      }
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
                        , if edit.previewing then
                            setPreview Nothing

                          else
                            Effect.none
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
                            draftConfig edit
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
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg

                -- Updates this server's cached configuration (so a forced theme takes effect now) and, if it's
                -- the page's own server, reloads its stylesheet and ends any preview.
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.CustomCssSaved targetHost config))
                ]
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

        ForceLightToggled ->
            ( mapEdit (\e -> { e | forceLight = not e.forceLight, forceDark = e.forceDark && e.forceLight }) model, Effect.none )

        ForceDarkToggled ->
            ( mapEdit (\e -> { e | forceDark = not e.forceDark, forceLight = e.forceLight && e.forceDark }) model, Effect.none )

        TemplateSelected name ->
            ( mapEdit
                (\e ->
                    case CustomCssTemplates.all |> List.filter (\t -> t.name == name) |> List.head of
                        Just chosen ->
                            { e
                                | css = chosen.css
                                , forceLight = chosen.forceLightTheme
                                , forceDark = chosen.forceDarkTheme
                                , previous =
                                    if e.css == chosen.css && e.forceLight == chosen.forceLightTheme && e.forceDark == chosen.forceDarkTheme then
                                        e.previous

                                    else
                                        Just { css = e.css, forceLight = e.forceLight, forceDark = e.forceDark }
                            }

                        Nothing ->
                            e
                )
                model
            , Effect.none
            )

        UndoTemplateClicked ->
            ( mapEdit
                (\e ->
                    case e.previous of
                        Just previous ->
                            { e | css = previous.css, forceLight = previous.forceLight, forceDark = previous.forceDark, previous = Nothing }

                        Nothing ->
                            e
                )
                model
            , Effect.none
            )

        PreviewClicked ->
            case model.edit of
                Just edit ->
                    if edit.previewing then
                        ( mapEdit (\e -> { e | previewing = False }) model, setPreview Nothing )

                    else
                        ( mapEdit (\e -> { e | previewing = True }) model
                        , setPreview (Just (draftConfig edit))
                        )

                Nothing ->
                    ( model, Effect.none )

        RemoveMediaClicked mediaId ->
            ( mapEdit (\e -> { e | mediaIds = List.filter (\id -> id /= mediaId) e.mediaIds }) model, Effect.none )


setPreview : Maybe CustomCSSConfiguration -> Effect msg
setPreview maybeConfig =
    Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.SetCustomCssPreview maybeConfig))


{-| The editor's draft as the `CustomCSSConfiguration` that Save sends and Preview applies.
-}
draftConfig : Edit -> CustomCSSConfiguration
draftConfig edit =
    { mediaIds = edit.mediaIds
    , customCss = Just edit.css
    , forceLightTheme = edit.forceLight
    , forceDarkTheme = edit.forceDark
    }


{-| While "Preview" is on, re-applies the draft whenever its media, CSS or forced theme differ between `before` and
`after`. Run after every `update`, and by `ServerInformationPage` after a forwarded `Shared.Msg`
(`applySharedMsg` is pure, so a picked-media change can't emit it itself).
-}
draftPreviewEffect : Model -> Model -> Effect msg
draftPreviewEffect before after =
    case ( before.edit, after.edit ) of
        ( Just b, Just a ) ->
            if a.previewing && b.previewing && draftConfig b /= draftConfig a then
                setPreview (Just (draftConfig a))

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


view : Bool -> RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view canPreview server maybeAdminAccount model =
    div [ class "server-details-custom-css" ]
        [ h3 [ class "section-title" ] [ text "Custom CSS" ]
        , variablesNote server
        , case ( model.edit, model.saved ) of
            ( Just edit, _ ) ->
                editorView canPreview server edit

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


{-| The CSS variables custom CSS can use, shown in both modes: `--primary-color` and `--nav-color` (this server's
configured colors -- current values shown, with a swatch) and the `--custom-media-N` ones for the media chosen
below. Mirrors what the stylesheet itself defines (`backend/src/logic/custom_css.rs`, `UI.CustomCssStylesheet`).
-}
variablesNote : RellmServer -> Html Msg
variablesNote server =
    let
        branding : RellmServers.Branding
        branding =
            RellmServers.brandingOf server

        colorVar : String -> String -> Html Msg
        colorVar name color =
            span []
                [ code [] [ text name ]
                , text " "
                , span [ class "custom-css-color-swatch", style "background-color" color, title color ] []
                , text (" " ++ color)
                ]
    in
    p [ class "server-details-feature-settings-note custom-css-variables" ]
        [ text "CSS variables available to your custom CSS: "
        , colorVar "--primary-color" branding.primary.color
        , text " and "
        , colorVar "--nav-color" branding.nav.color
        , text " (this server's primary and navigation colors), plus "
        , code [] [ text "--custom-media-1" ]
        , text ", "
        , code [] [ text "--custom-media-2" ]
        , text ", … for the media chosen below, in order -- each a full "
        , code [] [ text "url(…)" ]
        , text ", so e.g. "
        , code [] [ text "background: var(--custom-media-1) center / cover;" ]
        , text " works."
        ]


displayView : RellmServer -> CustomCSSConfiguration -> Html Msg
displayView server config =
    if List.isEmpty config.mediaIds && String.isEmpty (Maybe.withDefault "" config.customCss) && not config.forceLightTheme && not config.forceDarkTheme then
        p [ class "server-details-feature-settings-note" ] [ text "No custom CSS." ]

    else
        let
            css : String
            css =
                Maybe.withDefault "" config.customCss
        in
        div [ class "custom-css-section" ]
            [ if config.forceLightTheme || config.forceDarkTheme then
                p [ class "server-details-feature-settings-note" ]
                    [ text
                        (if config.forceLightTheme then
                            "Forces the light theme for everyone."

                         else
                            "Forces the dark theme for everyone."
                        )
                    ]

              else
                text ""
            , mediaListView server Nothing config.mediaIds
            , if String.isEmpty css then
                text ""

              else
                div [ class "custom-css-scroll" ] [ Markdown.view [ class "custom-css-highlighted" ] (cssFence css) ]
            ]


editorView : Bool -> RellmServer -> Edit -> Html Msg
editorView canPreview server edit =
    div [ class "custom-css-section" ]
        [ templateRow canPreview edit
        , templateImageNote edit
        , forceThemeRows edit
        , mediaListView server (Just RemoveMediaClicked) edit.mediaIds
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
            , placeholder "/* Appended to the default CSS. Variables: var(--primary-color), var(--nav-color), and var(--custom-media-1) etc. for the media above. */"
            , value edit.css
            , onInput CssChanged
            ]
            []
        , div [ class "server-details-permissions-actions" ]
            [ Common.editSaveButton SaveClicked edit.status
            , Common.editCancelButton CancelClicked edit.status
            ]
        , Common.editErrorView edit.status
        ]


{-| "Apply Template" (a dropdown of `CustomCssTemplates.all`), "Undo template" once one's been applied, and "Preview" just to the dropdown's
right (only when `canPreview`).
-}
templateRow : Bool -> Edit -> Html Msg
templateRow canPreview edit =
    let
        -- The template currently "applied": the one whose CSS is exactly what's in the box. Derived from the
        -- text itself, so it can never get out of step with it -- editing the CSS un-applies the template (the
        -- dropdown goes back to "Apply Template"), and so does Undo.
        applied : Maybe String
        applied =
            CustomCssTemplates.matching edit.css |> Maybe.map .name
    in
    div [ class "custom-css-template-row" ]
        [ -- Keyed by the applied template, so the `<select>` is remounted -- showing the right option -- whenever
          -- that changes, rather than relying on Elm to patch `selected` onto the right `<option>`.
          Html.Keyed.node "span"
            []
            [ ( "template-select-" ++ Maybe.withDefault "" applied
              , Html.select [ class "custom-css-template-select", onInput TemplateSelected ]
                    (option [ value "", selected (applied == Nothing), disabled True ] [ text CustomCssTemplates.placeholder ]
                        :: List.map
                            (\( group, templates ) ->
                                Html.optgroup [ attribute "label" group ]
                                    (List.map (\t -> option [ value t.name, selected (applied == Just t.name) ] [ text t.name ]) templates)
                            )
                            CustomCssTemplates.grouped
                    )
              )
            ]
        , if canPreview then
            button
                [ class "server-details-rename-button"
                , onClick PreviewClicked
                , title "Show the CSS below on this page (instead of the saved stylesheet) without saving it"
                ]
                [ text
                    (if edit.previewing then
                        "Stop Preview"

                     else
                        "Preview"
                    )
                ]

          else
            text ""
        , case edit.previous of
            Just _ ->
                button [ class "server-details-rename-cancel", onClick UndoTemplateClicked ] [ text "Undo template" ]

            Nothing ->
                text ""
        ]


{-| "Force light theme" / "Force dark theme" switches -- at most one on (see `Edit.forceLight`).
-}
forceThemeRows : Edit -> Html Msg
forceThemeRows edit =
    div [ class "custom-css-force-theme" ]
        [ Common.settingsRow "Force light theme" (Common.flagSwitch edit.forceLight ForceLightToggled)
        , Common.settingsRow "Force dark theme" (Common.flagSwitch edit.forceDark ForceDarkToggled)
        , Common.settingsNote "Locks everyone's appearance to that theme and disables the theme toggles. For stylesheets that only work on a light (or dark) background -- the colors derived from the server's brand are chosen to contrast with it. Only one can be on."
        ]


{-| Right after a template is applied (its CSS still unedited) that uses more images than are chosen, says
which `--custom-media-N` slots are still empty.
-}
templateImageNote : Edit -> Html Msg
templateImageNote edit =
    case CustomCssTemplates.matching edit.css of
        Just applied ->
            if applied.imageCount > List.length edit.mediaIds then
                p [ class "server-details-feature-settings-note" ]
                    [ text
                        ("\""
                            ++ applied.name
                            ++ "\" uses "
                            ++ String.fromInt applied.imageCount
                            ++ (if applied.imageCount == 1 then
                                    " image"

                                else
                                    " images"
                               )
                            ++ " -- choose media below, in order (--custom-media-1 first). It still renders without them."
                        )
                    ]

            else
                text ""

        Nothing ->
            text ""


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
