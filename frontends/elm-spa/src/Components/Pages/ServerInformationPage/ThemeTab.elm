module Components.Pages.ServerInformationPage.ThemeTab exposing (Model, Msg, applySharedMsg, init, subscriptions, update, view)

{-| The Theme tab of `Components.Pages.ServerInformationPage` -- the server's square logo and its
Primary/Navigation colors (editable by an admin, via `AccountsPanel.updateServerConfig`'s own
"fetch fresh copy, then write" dance), the Default Web UI picker, which directly reuses
`UI.webUiToggleRow` -- the same control shown per-admin-account in the Accounts Panel's own
`UI.adminAccountPanel` -- rather than duplicating it, plus (at the bottom) the "Navigation Tabs"
section, wired in as a sub-component -- see `Components.Pages.ServerInformationPage.ThemeTab.CustomTabsConfiguration`'s
own module doc for why that one's split out.

`author`/`admin`/`moderator` (the other three `ServerColors` fields) aren't shown at all -- this
page has no UI for them yet, same as before this tab supported any editing.

-}

import Components.Pages.ServerInformationPage.Common as Common
import Components.Pages.ServerInformationPage.ThemeTab.CustomTabsConfiguration as CustomTabsConfiguration
import Effect exposing (Effect)
import Grpc
import Html exposing (Html, div, h3, img, input, p, span, text)
import Html.Attributes exposing (class, disabled, src, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (ServerConfiguration, defaultMediaReference, defaultServerColors, defaultServerInfo, defaultServerLogo)
import Proto.Rellm.WebUserInterface exposing (WebUserInterface(..))
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.MyMediaPanel as MyMediaPanel
import Task
import UI
import UI.Classes exposing (classes, openClosedClass)
import UI.ServerTheme as ServerTheme



-- MODEL


type alias Model =
    { logoEdit : Maybe LogoEdit
    , primaryColorEdit : Maybe ColorEdit
    , navigationColorEdit : Maybe ColorEdit
    , colorMetaExpanded : Bool
    , customTabsConfig : CustomTabsConfiguration.Model
    }


type Msg
    = LogoEditClicked
    | LogoRemoveClicked
    | LogoCancelClicked
    | LogoSaveClicked
    | GotLogoSaveResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | ColorEditClicked ServerColorField
    | ColorChanged ServerColorField String
    | ColorCancelClicked ServerColorField
    | ColorSaveClicked ServerColorField
    | GotColorSaveResult ServerColorField (Result Grpc.Error ( Maybe AccountsPanel.Msg, ServerConfiguration ))
    | ColorMetaExpandedToggled
    | SharedMsg Shared.Msg
    | CustomTabsConfigurationMsg CustomTabsConfiguration.Msg


{-| What `LogoSaveClicked` should do to `serverInfo.logo.squareMediaId` -- mirrors
`Components.Pages.UserProfilePage`'s `AvatarChoice`/`AvatarEdit` exactly, just over the server's own
square logo (a bare `Maybe String` media id, unlike a `User`'s `avatar` `MediaReference`) instead of
a `User`'s avatar. `LogoUnchanged` is the default (entering edit mode without having picked
anything new yet), `LogoChosen mediaId` is set by `Shared.MyMediaPanel`'s `SingleSelect` picker (see
`applySharedMsg`), and `LogoRemoved` (the "Remove" button) clears it entirely.
-}
type LogoChoice
    = LogoUnchanged
    | LogoChosen String
    | LogoRemoved


{-| Live only while the server's square logo is being edited by an admin -- mirrors
`Common`-style edit records (a `pending`-style `choice` plus `status`).
-}
type alias LogoEdit =
    { choice : LogoChoice
    , status : AccountsPanel.FormStatus
    }


{-| Which of `ServerColors`' two user-facing color fields a `colorEditorRow`/`ColorEdit` is for --
lets `view` reuse the same editing machinery for both (Primary/Navigation) rather than duplicating
it.
-}
type ServerColorField
    = PrimaryColor
    | NavigationColor


{-| Live only while one of the two server colors (see `ServerColorField`) is being edited by an
admin -- `pending` is the in-progress `<input type="color">` value (a `#rrggbb` hex string),
independent of the actual saved color until `ColorSaveClicked` succeeds.
-}
type alias ColorEdit =
    { pending : String
    , status : AccountsPanel.FormStatus
    }


init : Model
init =
    { logoEdit = Nothing
    , primaryColorEdit = Nothing
    , navigationColorEdit = Nothing
    , colorMetaExpanded = False
    , customTabsConfig = CustomTabsConfiguration.init
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map CustomTabsConfigurationMsg (CustomTabsConfiguration.subscriptions model.customTabsConfig)



-- UPDATE


update : Shared.Model -> String -> Maybe RellmServer -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost maybeServer msg model =
    case msg of
        LogoEditClicked ->
            case maybeServer of
                Just server ->
                    let
                        squareMediaId : Maybe String
                        squareMediaId =
                            (RellmServers.configurationOf server).serverInfo |> Maybe.andThen .logo |> Maybe.andThen .squareMediaId
                    in
                    ( { model
                        | logoEdit =
                            -- Preserves an already-in-progress `choice`/`status` rather than
                            -- resetting it -- this same message doubles as "re-open the picker"
                            -- (see `logoEditorView`'s "Choose Image" button, shown even while
                            -- already editing), which shouldn't discard whatever's already been
                            -- picked. Mirrors `UserProfilePage.AvatarEditClicked`.
                            case model.logoEdit of
                                Just edit ->
                                    Just edit

                                Nothing ->
                                    Just { choice = LogoUnchanged, status = AccountsPanel.Idle }
                      }
                    , Effect.fromShared
                        (Shared.MyMediaPanelMsg
                            (MyMediaPanel.Open
                                (Just (MyMediaPanel.SingleSelect { imagesOnly = True, initialSelection = squareMediaId |> Maybe.map (\id -> { defaultMediaReference | id = id }) }))
                                targetHost
                            )
                        )
                    )

                Nothing ->
                    ( model, Effect.none )

        LogoRemoveClicked ->
            ( { model | logoEdit = model.logoEdit |> Maybe.map (\edit -> { edit | choice = LogoRemoved }) }, Effect.none )

        LogoCancelClicked ->
            ( { model | logoEdit = Nothing }, Effect.fromShared (Shared.MyMediaPanelMsg MyMediaPanel.CloseClicked) )

        LogoSaveClicked ->
            case ( model.logoEdit, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( { model | logoEdit = Just { edit | status = AccountsPanel.Submitting } }
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyLogoChoice edit.choice)
                        |> Task.attempt GotLogoSaveResult
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotLogoSaveResult (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( { model | logoEdit = Nothing }
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotLogoSaveResult (Err err) ->
            ( { model | logoEdit = model.logoEdit |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }) }
            , Effect.none
            )

        ColorEditClicked field ->
            case maybeServer of
                Just server ->
                    let
                        pending : String
                        pending =
                            colorArgbFor field (RellmServers.configurationOf server)
                                |> Maybe.map ServerTheme.colorMetaFromArgb
                                |> Maybe.withDefault ServerTheme.neutralColorMeta
                                |> .color
                    in
                    ( setColorEditFor field (Just { pending = pending, status = AccountsPanel.Idle }) model, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        ColorChanged field hex ->
            ( setColorEditFor field (colorEditFor field model |> Maybe.map (\edit -> { edit | pending = hex })) model, Effect.none )

        ColorCancelClicked field ->
            ( setColorEditFor field Nothing model, Effect.none )

        ColorSaveClicked field ->
            case ( colorEditFor field model, Common.adminAccountFor shared targetHost ) of
                ( Just edit, Just account ) ->
                    ( setColorEditFor field (Just { edit | status = AccountsPanel.Submitting }) model
                    , AccountsPanel.updateServerConfig shared.accounts ( Just account.userId, targetHost ) (applyColorFor field (ServerTheme.argbFromHex edit.pending))
                        |> Task.attempt (GotColorSaveResult field)
                        |> Effect.fromCmd
                    )

                _ ->
                    ( model, Effect.none )

        GotColorSaveResult field (Ok ( maybeAccountsPanelMsg, newConfig )) ->
            ( setColorEditFor field Nothing model
            , Effect.batch
                [ Common.accountsPanelEffect maybeAccountsPanelMsg
                , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.GotServerConfigSaveResult targetHost newConfig))
                ]
            )

        GotColorSaveResult field (Err err) ->
            ( setColorEditFor field
                (colorEditFor field model |> Maybe.map (\edit -> { edit | status = AccountsPanel.Errored (AccountsPanel.grpcErrorToString err) }))
                model
            , Effect.none
            )

        ColorMetaExpandedToggled ->
            ( { model | colorMetaExpanded = not model.colorMetaExpanded }, Effect.none )

        SharedMsg subMsg ->
            ( model, Effect.fromShared subMsg )

        CustomTabsConfigurationMsg subMsg ->
            CustomTabsConfiguration.update shared targetHost maybeServer subMsg model.customTabsConfig
                |> Tuple.mapFirst (\customTabsConfig -> { model | customTabsConfig = customTabsConfig })
                |> Tuple.mapSecond (Effect.map CustomTabsConfigurationMsg)


{-| Reacts to a `Shared.Msg` forwarded through by the parent's own `SharedMsg` branch -- the shared
`Shared.MyMediaPanel` chooser reporting a tap matters both here (opened by `LogoEditClicked`; see
`Shared.MyMediaPanel`'s own module doc on why this forwarded `Shared.Msg`, not some
closure/callback, is what delivers the pick back here) and, forwarded on, to
`CustomTabsConfiguration.applySharedMsg` (opened by its own `CustomTabChooseImageClicked`) -- each
gated on its own `logoEdit`/`customTabsEdit.editingIconFor` already being `Just` so an unrelated
Browse-mode tap (e.g. from the Accounts Panel) elsewhere can't be mistaken for either's own pick,
and the two are never both mid-pick at once in practice (`Shared.MyMediaPanel` is a single shared
chooser). Mirrors `UserProfilePage`'s own `MediaItemClicked` handling.
-}
applySharedMsg : Shared.Msg -> Model -> Model
applySharedMsg subMsg model =
    { model
        | logoEdit =
            case subMsg of
                Shared.MyMediaPanelMsg (MyMediaPanel.MediaItemClicked mediaId) ->
                    model.logoEdit |> Maybe.map (\edit -> { edit | choice = LogoChosen mediaId })

                _ ->
                    model.logoEdit
        , customTabsConfig = CustomTabsConfiguration.applySharedMsg subMsg model.customTabsConfig
    }


{-| `LogoSaveClicked`'s transform, passed to `AccountsPanel.updateServerConfig` the same way every
other editor's transform is -- overlays just the change `choice` describes onto a freshly
re-fetched `ServerConfiguration`'s `serverInfo.logo.squareMediaId`, leaving every other field
(including the other three `ServerLogo` variants, none of which this page edits) untouched. Mirrors
`Components.Pages.UserProfilePage.applyAvatarChoice`.
-}
applyLogoChoice : LogoChoice -> ServerConfiguration -> ServerConfiguration
applyLogoChoice choice config =
    let
        info : Proto.Rellm.ServerInfo
        info =
            Maybe.withDefault defaultServerInfo config.serverInfo

        logo : Proto.Rellm.ServerLogo
        logo =
            Maybe.withDefault defaultServerLogo info.logo

        setSquareMediaId : Maybe String -> ServerConfiguration
        setSquareMediaId squareMediaId =
            { config | serverInfo = Just { info | logo = Just { logo | squareMediaId = squareMediaId } } }
    in
    case choice of
        LogoUnchanged ->
            config

        LogoChosen mediaId ->
            setSquareMediaId (Just mediaId)

        LogoRemoved ->
            setSquareMediaId Nothing


{-| One `ServerColorField`'s current ARGB value out of a `ServerConfiguration`, alongside its
writer `applyColorFor` just below.
-}
colorArgbFor : ServerColorField -> ServerConfiguration -> Maybe Int
colorArgbFor field config =
    let
        colors : Maybe Proto.Rellm.ServerColors
        colors =
            config.serverInfo |> Maybe.andThen .colors
    in
    case field of
        PrimaryColor ->
            colors |> Maybe.andThen .primary

        NavigationColor ->
            colors |> Maybe.andThen .navigation


applyColorFor : ServerColorField -> Int -> ServerConfiguration -> ServerConfiguration
applyColorFor field argb config =
    let
        info : Proto.Rellm.ServerInfo
        info =
            Maybe.withDefault defaultServerInfo config.serverInfo

        colors : Proto.Rellm.ServerColors
        colors =
            Maybe.withDefault defaultServerColors info.colors

        newColors : Proto.Rellm.ServerColors
        newColors =
            case field of
                PrimaryColor ->
                    { colors | primary = Just argb }

                NavigationColor ->
                    { colors | navigation = Just argb }
    in
    { config | serverInfo = Just { info | colors = Just newColors } }


{-| `model`'s in-progress `ColorEdit` for one `ServerColorField`, alongside its setter
`setColorEditFor` just below.
-}
colorEditFor : ServerColorField -> Model -> Maybe ColorEdit
colorEditFor field model =
    case field of
        PrimaryColor ->
            model.primaryColorEdit

        NavigationColor ->
            model.navigationColorEdit


setColorEditFor : ServerColorField -> Maybe ColorEdit -> Model -> Model
setColorEditFor field edit model =
    case field of
        PrimaryColor ->
            { model | primaryColorEdit = edit }

        NavigationColor ->
            { model | navigationColorEdit = edit }



-- VIEW


view : Shared.Model -> RellmServer -> Maybe RellmAccount -> Model -> Html Msg
view shared server maybeAdminAccount model =
    let
        info : Proto.Rellm.ServerInfo
        info =
            RellmServers.rellmServerInfoOf server

        config : ServerConfiguration
        config =
            RellmServers.configurationOf server

        webUi : WebUserInterface
        webUi =
            config.serverInfo |> Maybe.andThen .webUserInterface |> Maybe.withDefault FLUTTERWEB
    in
    div [ class "server-details-tab-content server-details-theme" ]
        [ logoEditorView maybeAdminAccount model.logoEdit server (info.logo |> Maybe.andThen .squareMediaId)
        , colorEditorRow PrimaryColor "Primary Color" maybeAdminAccount model.primaryColorEdit (info.colors |> Maybe.andThen .primary)
        , colorEditorRow NavigationColor "Navigation Color" maybeAdminAccount model.navigationColorEdit (info.colors |> Maybe.andThen .navigation)
        , accentColorPreviewRow model info
        , colorMetaSection shared model info
        , div [ class "server-details-setting" ]
            [ h3 [] [ text "Default Web UI" ]
            , case maybeAdminAccount of
                Just account ->
                    Html.map SharedMsg (UI.webUiToggleRow (RellmAccounts.rellmAccountId account) server.frontendHost webUi)

                Nothing ->
                    p [] [ text (webUserInterfaceText webUi) ]
            ]
        , Html.map CustomTabsConfigurationMsg (CustomTabsConfiguration.view server maybeAdminAccount model.customTabsConfig)
        ]


webUserInterfaceText : WebUserInterface -> String
webUserInterfaceText ui =
    case ui of
        FLUTTERWEB ->
            "Flutter (legacy)"

        HANDLEBARSTEMPLATES ->
            "Handlebars Templates (deprecated)"

        REACTTAMAGUI ->
            "React (Tamagui)"

        ELMSPA ->
            "Elm"

        WebUserInterfaceUnrecognized_ _ ->
            "Unknown"


{-| One `ServerColorField`'s row: the plain swatch/hex (plus an Edit button, for an admin) when it
has no in-progress `ColorEdit`, or an `<input type="color">` (native, no picker library -- see
`UI.ServerTheme.argbFromHex`'s own doc) bound to `edit.pending` plus Save/Cancel while being edited.
-}
colorEditorRow : ServerColorField -> String -> Maybe RellmAccount -> Maybe ColorEdit -> Maybe Int -> Html Msg
colorEditorRow field label_ maybeAdminAccount maybeEdit argb =
    case maybeEdit of
        Just edit ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ input [ type_ "color", value edit.pending, onInput (ColorChanged field) ] []
                , span [ class "server-details-color-label" ] [ text label_ ]
                , span [ class "server-details-color-hex" ] [ text edit.pending ]
                , Common.editSaveButton (ColorSaveClicked field) edit.status
                , Common.editCancelButton (ColorCancelClicked field) edit.status
                , Common.editErrorView edit.status
                ]

        Nothing ->
            let
                colorMeta : ServerTheme.ColorMeta
                colorMeta =
                    argb |> Maybe.map ServerTheme.colorMetaFromArgb |> Maybe.withDefault ServerTheme.neutralColorMeta
            in
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-swatch", style "background-color" colorMeta.color ] []
                , span [ class "server-details-color-label" ] [ text label_ ]
                , span [ class "server-details-color-hex" ] [ text colorMeta.color ]
                , case maybeAdminAccount of
                    Just _ ->
                        Html.button [ class "server-details-rename-button", Html.Events.onClick (ColorEditClicked field) ] [ text "Edit" ]

                    Nothing ->
                        text ""
                ]


{-| A read-only preview of `UI.ServerTheme.accentColor` -- whichever of Primary/Navigation is more
vibrant -- kept live against whichever of those two is currently being edited (via `effectiveColorMeta`, falling
back to the saved value otherwise), so toggling between two colors in the editor updates this
row immediately rather than only after Save.
-}
accentColorPreviewRow : Model -> Proto.Rellm.ServerInfo -> Html Msg
accentColorPreviewRow model info =
    let
        primaryMeta : ServerTheme.ColorMeta
        primaryMeta =
            effectiveColorMeta model.primaryColorEdit (info.colors |> Maybe.andThen .primary)

        navMeta : ServerTheme.ColorMeta
        navMeta =
            effectiveColorMeta model.navigationColorEdit (info.colors |> Maybe.andThen .navigation)

        accentColor : String
        accentColor =
            (ServerTheme.fromColorMetas False primaryMeta navMeta).accentColor
    in
    div [ class "server-details-color-row" ]
        [ span [ class "server-details-color-label" ] [ text "Calculated Accent Color" ]
        , span [ class "server-details-color-swatch", style "background-color" accentColor ] []
        , span [ class "server-details-color-hex" ] [ text accentColor ]
        ]


{-| An expandable "Calculated Color Meta" section revealing every derived `ServerTheme` field (see
`ServerTheme.fromColorMetas`) that `colorEditorRow`/`accentColorPreviewRow` above don't already show
-- i.e. everything except the plain `primaryColor`/`navColor`/`accentColor` hexes themselves. Lets an
admin see exactly how a color choice propagates (its text/dark/light/bg/anchor/contrast variants,
luma, saturation) without cluttering the tab by default. Collapsed by default (`Model.colorMetaExpanded`),
toggled by `ColorMetaExpandedToggled`, following `UserProfilePage.expandableProfileSection`'s own
conventions (just inlined here, since there's only one such section on this tab): the body
(`expandable-section-content`/`-content-inner`) is always mounted rather than appearing/disappearing
outright, so `profiles.css`'s `grid-template-rows` 0fr/1fr trick can animate it open/closed, and the
arrow is a single static "▼" rotated via `.expandable-section-arrow.is-open` instead of a glyph swap
between "▸"/"▾". Kept live against in-progress edits the same way `accentColorPreviewRow` is, via
`effectiveColorMeta`. The header row also carries `UI.themeToggle` (the same 3-way Auto/Light/Dark
control shown in the Accounts Panel's own tab bar) at its far right -- pinned there rather than nested
inside the clickable `h3` itself, so tapping it doesn't also bubble into `ColorMetaExpandedToggled` --
and, like `expandableProfileSection`'s own `maybeHeaderAction`, always mounted and faded via
`openClosedClass` rather than conditionally rendered, so it never pops in/out mid-animation.
-}
colorMetaSection : Shared.Model -> Model -> Proto.Rellm.ServerInfo -> Html Msg
colorMetaSection shared model info =
    let
        expanded : Bool
        expanded =
            model.colorMetaExpanded

        primaryMeta : ServerTheme.ColorMeta
        primaryMeta =
            effectiveColorMeta model.primaryColorEdit (info.colors |> Maybe.andThen .primary)

        navMeta : ServerTheme.ColorMeta
        navMeta =
            effectiveColorMeta model.navigationColorEdit (info.colors |> Maybe.andThen .navigation)

        theme : ServerTheme.ServerTheme
        theme =
            ServerTheme.fromColorMetas False primaryMeta navMeta
    in
    div [ class "server-details-color-meta" ]
        [ div [ class "server-details-color-meta-header" ]
            [ h3
                [ classes [ "section-title", "expandable-section-title" ]
                , onClick ColorMetaExpandedToggled
                ]
                [ span [ classes [ "expandable-section-arrow", openClosedClass expanded ] ] [ text "▼" ]
                , text "Calculated Color Meta"
                ]
            , div [ classes [ "server-details-color-meta-toggle", openClosedClass expanded ] ]
                [ Html.map SharedMsg (UI.themeToggle shared) ]
            ]
        , div
            [ classes [ "expandable-section-content", openClosedClass expanded, "border-color-primary-anchor-50" ] ]
            [ div [ class "expandable-section-content-inner" ]
                [ colorMetaColorRow "Primary Text Color" theme.primaryTextColor
                , colorMetaColorRow "Primary Dark Color" theme.primaryDarkColor
                , colorMetaColorRow "Primary Light Color" theme.primaryLightColor
                , colorMetaColorRow "Primary Background Color" theme.primaryBgColor
                , colorMetaColorRow "Primary Anchor Color" theme.primaryAnchorColor
                , colorMetaValueRow "Primary Luma" (formatColorMetaFloat theme.primaryLuma)
                , colorMetaValueRow "Primary Saturation" (formatColorMetaFloat theme.primarySaturation)
                , colorMetaColorRow "Primary Contrast Color" theme.primaryContrastColor
                , colorMetaColorRow "Nav Text Color" theme.navTextColor
                , colorMetaColorRow "Nav Dark Color" theme.navDarkColor
                , colorMetaColorRow "Nav Light Color" theme.navLightColor
                , colorMetaColorRow "Nav Background Color" theme.navBgColor
                , colorMetaColorRow "Nav Anchor Color" theme.navAnchorColor
                , colorMetaValueRow "Nav Luma" (formatColorMetaFloat theme.navLuma)
                , colorMetaValueRow "Nav Saturation" (formatColorMetaFloat theme.navSaturation)
                , colorMetaColorRow "Nav Contrast Color" theme.navContrastColor
                , colorMetaColorRow "Accent Text Color" theme.accentTextColor
                , colorMetaColorRow "Accent Dark Color" theme.accentDarkColor
                , colorMetaColorRow "Accent Light Color" theme.accentLightColor
                , colorMetaColorRow "Accent Background Color" theme.accentBgColor
                , colorMetaColorRow "Accent Anchor Color" theme.accentAnchorColor
                , colorMetaValueRow "Accent Luma" (formatColorMetaFloat theme.accentLuma)
                , colorMetaValueRow "Accent Saturation" (formatColorMetaFloat theme.accentSaturation)
                , colorMetaColorRow "Accent Contrast Color" theme.accentContrastColor
                , colorMetaColorRow "Text Color" theme.textColor
                , colorMetaColorRow "Background Color" theme.backgroundColor
                , colorMetaColorRow "Transparent Background Color" theme.transparentBackgroundColor
                , colorMetaColorRow "Transparent Primary Color" theme.transparentPrimaryColor
                , colorMetaColorRow "Barely Transparent Background Color" theme.barelyTransparentBackgroundColor
                , colorMetaColorRow "Warning Anchor Color" theme.warningAnchorColor
                ]
            ]
        ]


{-| One `colorMetaSection` color row: left label, right swatch + hex -- same structure as
`accentColorPreviewRow`'s own row.
-}
colorMetaColorRow : String -> String -> Html Msg
colorMetaColorRow label_ color =
    div [ class "server-details-color-row" ]
        [ span [ class "server-details-color-label" ] [ text label_ ]
        , span [ class "server-details-color-swatch", style "background-color" color ] []
        , span [ class "server-details-color-hex" ] [ text color ]
        ]


{-| One `colorMetaSection` non-color row (luma/saturation/`darkMode`) -- left label, right
monospaced value (`.server-details-color-hex` is already monospace), no swatch.
-}
colorMetaValueRow : String -> String -> Html Msg
colorMetaValueRow label_ value_ =
    div [ class "server-details-color-row" ]
        [ span [ class "server-details-color-label" ] [ text label_ ]
        , span [ class "server-details-color-hex" ] [ text value_ ]
        ]


{-| Formats a `ColorMeta`/`ServerTheme` luma/saturation `Float` (both always `[0, 1]`) to 3 decimal
places for display -- `String.fromFloat` alone can print long floating-point tails (e.g.
`0.30000000000000004`) that aren't useful to an admin reading this diagnostic panel.
-}
formatColorMetaFloat : Float -> String
formatColorMetaFloat value =
    String.fromFloat (toFloat (round (value * 1000)) / 1000)


{-| One `ServerColorField`'s effective `ColorMeta` right now: its in-progress edited hex if it's
being edited, otherwise its saved `argb` (or `neutralColorMeta` if unset) -- same fallback
`colorEditorRow`'s own swatch uses, factored out so `accentColorPreviewRow` can apply it to both
colors independently.
-}
effectiveColorMeta : Maybe ColorEdit -> Maybe Int -> ServerTheme.ColorMeta
effectiveColorMeta maybeEdit argb =
    case maybeEdit of
        Just edit ->
            ServerTheme.colorMetaFromArgb (ServerTheme.argbFromHex edit.pending)

        Nothing ->
            argb |> Maybe.map ServerTheme.colorMetaFromArgb |> Maybe.withDefault ServerTheme.neutralColorMeta


{-| The square logo, plus (only for an admin, and only once `logoEdit` is started) a
`MyMediaPanel`-backed picker: "Choose Image" (re)opens `Shared.MyMediaPanel` in `SingleSelect` mode
(see `LogoEditClicked`), "Remove" clears the pick entirely, and Save/Cancel commit or discard it.
The image itself previews `edit.choice` (see `logoPreviewUrl`) rather than `currentSquareMediaId`
once editing's started, mirroring `Components.Pages.UserProfilePage.avatarPreviewUrl`'s own
"preview the pending choice, not the saved value" behavior.
-}
logoEditorView : Maybe RellmAccount -> Maybe LogoEdit -> RellmServer -> Maybe String -> Html Msg
logoEditorView maybeAdminAccount maybeEdit server currentSquareMediaId =
    div [ class "server-details-logo" ]
        [ h3 [] [ text "Server Image" ]
        , case maybeEdit of
            Just edit ->
                div [ class "server-details-logo-edit" ]
                    [ case logoPreviewUrl server edit.choice currentSquareMediaId of
                        Just url ->
                            img [ class "server-details-logo-image", src url ] []

                        Nothing ->
                            p [ class "server-details-policy-unset" ] [ text "No server image set." ]
                    , div [ class "server-details-logo-edit-actions" ]
                        [ Html.button
                            [ class "server-details-rename-button", Html.Events.onClick LogoEditClicked, disabled (edit.status == AccountsPanel.Submitting) ]
                            [ text "Choose Image" ]
                        , Html.button
                            [ class "server-details-rename-cancel", Html.Events.onClick LogoRemoveClicked, disabled (edit.status == AccountsPanel.Submitting) ]
                            [ text "Remove" ]
                        ]
                    , div [ class "server-details-logo-edit-actions" ]
                        [ Common.editSaveButton LogoSaveClicked edit.status
                        , Common.editCancelButton LogoCancelClicked edit.status
                        ]
                    , Common.editErrorView edit.status
                    ]

            Nothing ->
                div []
                    [ case currentSquareMediaId |> Maybe.andThen (RellmServers.mediaUrl server) of
                        Just url ->
                            img [ class "server-details-logo-image", src url ] []

                        Nothing ->
                            p [] [ text "No server image set." ]
                    , case maybeAdminAccount of
                        Just _ ->
                            Html.button [ class "server-details-rename-button", Html.Events.onClick LogoEditClicked ] [ text "Edit" ]

                        Nothing ->
                            text ""
                    ]
        ]


{-| The logo URL `logoEditorView` should actually preview -- mirrors
`Components.Pages.UserProfilePage.avatarPreviewUrl` exactly, just over `LogoChoice` instead of
`AvatarChoice` (and with no initial-letter placeholder fallback to drop to, since a server has no
analogous "username" -- `Nothing` just shows the "No server image set." text, same as the
non-editing case).
-}
logoPreviewUrl : RellmServer -> LogoChoice -> Maybe String -> Maybe String
logoPreviewUrl server choice currentSquareMediaId =
    case choice of
        LogoUnchanged ->
            currentSquareMediaId |> Maybe.andThen (RellmServers.mediaUrl server)

        LogoChosen mediaId ->
            RellmServers.mediaUrl server mediaId

        LogoRemoved ->
            Nothing
