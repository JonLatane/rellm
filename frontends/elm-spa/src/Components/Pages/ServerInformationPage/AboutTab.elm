module Components.Pages.ServerInformationPage.AboutTab exposing (AdminsStatus(..), Model, Msg, VersionStatus(..), applySharedMsg, init, update, view)

{-| The About tab of `Components.Pages.ServerInformationPage` -- the server's name (renameable by
an admin, via `Shared.AccountsPanel.RenameServerClicked` so the app's cached `Server` list stays in
sync), its description/privacy policy/media policy (each editable in place through the shared
`Shared.MarkdownPanel` panel, same edit-in-panel/Save flow as post content on `Pages.Post.PostId_`),
its version, and its admin list.

`AdminsStatus`/`VersionStatus` are fetched by the parent module (as soon as a server's known,
regardless of which tab is active -- see `ServerInformationPage.fetchAdmins`/`fetchVersion`), not
here; this module only owns how they're _displayed_, exposing the two types so the parent's own
`Model`/`Msg` can hold/produce them without a circular import.

-}

import Components.Markdown as Markdown
import Components.Pages.ServerInformationPage.Common as Common
import Components.Users as Users
import Effect exposing (Effect)
import Html exposing (Html, button, div, h2, h3, input, p, span, text)
import Html.Attributes exposing (class, disabled, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (User)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.MarkdownPanel as MarkdownPanel



-- MODEL


type alias Model =
    { renameStatus : RenameStatus
    , shortNameStatus : RenameStatus
    }


type Msg
    = RenameClicked String
    | RenameChanged String
    | RenameCancelClicked
    | RenameSaveClicked
    | ShortNameEditClicked String
    | ShortNameChanged String
    | ShortNameCancelClicked
    | ShortNameSaveClicked
    | EditDescriptionClicked RellmServer
    | EditPrivacyPolicyClicked RellmServer
    | EditMediaPolicyClicked RellmServer


{-| Live only while the server's name (or, via `Model.shortNameStatus`, its short name) is being
edited by an admin -- `pending` is the in-progress `<input>` value, independent of the actual
field until the corresponding `*SaveClicked` succeeds. Mirrors `Pages.Post.PostId_`'s
`VisibilityEdit`.
-}
type RenameStatus
    = NotRenaming
    | Renaming String AccountsPanel.FormStatus


type AdminsStatus
    = AdminsNotLoaded
    | LoadingAdmins
    | AdminsLoaded (List User)
    | AdminsFailed


type VersionStatus
    = VersionNotLoaded
    | LoadingVersion
    | VersionLoaded String
    | VersionFailed


init : Model
init =
    { renameStatus = NotRenaming, shortNameStatus = NotRenaming }



-- UPDATE


update : Shared.Model -> String -> Msg -> Model -> ( Model, Effect Msg )
update shared targetHost msg model =
    case msg of
        RenameClicked currentName ->
            ( { model | renameStatus = Renaming currentName AccountsPanel.Idle }, Effect.none )

        RenameChanged newText ->
            ( { model
                | renameStatus =
                    case model.renameStatus of
                        Renaming _ status ->
                            Renaming newText status

                        NotRenaming ->
                            NotRenaming
              }
            , Effect.none
            )

        RenameCancelClicked ->
            ( { model | renameStatus = NotRenaming }, Effect.none )

        RenameSaveClicked ->
            case ( model.renameStatus, Common.adminAccountFor shared targetHost ) of
                ( Renaming pendingName _, Just account ) ->
                    ( { model | renameStatus = Renaming pendingName AccountsPanel.Submitting }
                    , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.RenameServerClicked (RellmAccounts.rellmAccountId account) pendingName))
                    )

                _ ->
                    ( model, Effect.none )

        ShortNameEditClicked currentShortName ->
            ( { model | shortNameStatus = Renaming currentShortName AccountsPanel.Idle }, Effect.none )

        ShortNameChanged newText ->
            ( { model
                | shortNameStatus =
                    case model.shortNameStatus of
                        Renaming _ status ->
                            Renaming newText status

                        NotRenaming ->
                            NotRenaming
              }
            , Effect.none
            )

        ShortNameCancelClicked ->
            ( { model | shortNameStatus = NotRenaming }, Effect.none )

        ShortNameSaveClicked ->
            case ( model.shortNameStatus, Common.adminAccountFor shared targetHost ) of
                ( Renaming pendingShortName _, Just account ) ->
                    ( { model | shortNameStatus = Renaming pendingShortName AccountsPanel.Submitting }
                    , Effect.fromShared (Shared.AccountsPanelMsg (AccountsPanel.ChangeServerShortNameClicked (RellmAccounts.rellmAccountId account) pendingShortName))
                    )

                _ ->
                    ( model, Effect.none )

        EditDescriptionClicked server ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.ServerDescription server) targetHost)) )

        EditPrivacyPolicyClicked server ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.ServerPrivacyPolicy server) targetHost)) )

        EditMediaPolicyClicked server ->
            ( model, Effect.fromShared (Shared.MarkdownPanelMsg (MarkdownPanel.Open (MarkdownPanel.ServerMediaPolicy server) targetHost)) )


{-| Reacts to a `Shared.Msg` forwarded through by the parent's own `SharedMsg` branch --
`AccountsPanel.GotRenameServerResult` (the Rename save's own result) and
`AccountsPanel.GotChangeServerShortNameResult` (the Short Name save's own result) are the only
ones that matter here; everything else leaves both fields' status untouched.
-}
applySharedMsg : Shared.Msg -> Model -> Model
applySharedMsg subMsg model =
    { model
        | renameStatus =
            case subMsg of
                Shared.AccountsPanelMsg (AccountsPanel.GotRenameServerResult (Ok _)) ->
                    NotRenaming

                Shared.AccountsPanelMsg (AccountsPanel.GotRenameServerResult (Err err)) ->
                    case model.renameStatus of
                        Renaming pending _ ->
                            Renaming pending (AccountsPanel.Errored (AccountsPanel.grpcErrorToString err))

                        NotRenaming ->
                            NotRenaming

                _ ->
                    model.renameStatus
        , shortNameStatus =
            case subMsg of
                Shared.AccountsPanelMsg (AccountsPanel.GotChangeServerShortNameResult (Ok _)) ->
                    NotRenaming

                Shared.AccountsPanelMsg (AccountsPanel.GotChangeServerShortNameResult (Err err)) ->
                    case model.shortNameStatus of
                        Renaming pending _ ->
                            Renaming pending (AccountsPanel.Errored (AccountsPanel.grpcErrorToString err))

                        NotRenaming ->
                            NotRenaming

                _ ->
                    model.shortNameStatus
    }



-- VIEW


view : Shared.Model -> RellmServer -> Maybe RellmAccount -> AdminsStatus -> VersionStatus -> Model -> Html Msg
view shared server maybeAdminAccount adminsStatus versionStatus model =
    let
        info : Proto.Rellm.ServerInfo
        info =
            RellmServers.rellmServerInfoOf server

        name : String
        name =
            Maybe.withDefault server.frontendHost info.name
    in
    div [ class "server-details-tab-content server-details-about" ]
        [ h2 [ class "server-details-name" ] (nameView name model.renameStatus maybeAdminAccount)
        , shortNameView info.shortName model.shortNameStatus maybeAdminAccount
        , versionView versionStatus
        , policySectionView "server-details-description" Nothing (EditDescriptionClicked server) maybeAdminAccount info.description
        , policySectionView "server-details-policy" (Just "Privacy Policy") (EditPrivacyPolicyClicked server) maybeAdminAccount info.privacyPolicy
        , policySectionView "server-details-policy" (Just "Media Policy") (EditMediaPolicyClicked server) maybeAdminAccount info.mediaPolicy
        , adminsView shared server adminsStatus
        ]


{-| One about-tab Markdown field backed by `Shared.MarkdownPanel` -- `description` (`heading =
Nothing`) or `privacyPolicy`/`mediaPolicy` (each headed). Renders nothing for a non-admin viewer
when the field's unset, same as before this page supported editing it; an admin sees an "Edit"
button either way -- even when unset, so they can set it for the first time, not just change
existing text -- mirroring `nameView`'s Rename button.
-}
policySectionView : String -> Maybe String -> Msg -> Maybe RellmAccount -> Maybe String -> Html Msg
policySectionView sectionClass heading editClicked maybeAdminAccount content =
    case ( content, maybeAdminAccount ) of
        ( Nothing, Nothing ) ->
            text ""

        _ ->
            div [ class sectionClass ]
                [ case heading of
                    Just headingText ->
                        h3 [] [ text headingText ]

                    Nothing ->
                        text ""
                , case content of
                    Just markdown ->
                        Markdown.view [] markdown

                    Nothing ->
                        p [ class "server-details-policy-unset" ] [ text "Not set." ]
                , case maybeAdminAccount of
                    Just _ ->
                        let
                            buttonText : String
                            buttonText =
                                "Edit "
                                    ++ (case heading of
                                            Just headingText ->
                                                headingText

                                            _ ->
                                                "Description"
                                       )
                        in
                        button [ class "server-details-rename-button", onClick editClicked ] [ text buttonText ]

                    Nothing ->
                        text ""
                ]


nameView : String -> RenameStatus -> Maybe RellmAccount -> List (Html Msg)
nameView name renameStatus maybeAdminAccount =
    case ( renameStatus, maybeAdminAccount ) of
        ( Renaming pendingName status, Just _ ) ->
            [ input
                [ class "server-details-rename-input"
                , value pendingName
                , onInput RenameChanged
                , disabled (status == AccountsPanel.Submitting)
                ]
                []
            , Common.editSaveButton RenameSaveClicked status
            , Common.editCancelButton RenameCancelClicked status
            , Common.editErrorView status
            ]

        _ ->
            [ text name
            , case maybeAdminAccount of
                Just _ ->
                    button [ class "server-details-rename-button", onClick (RenameClicked name) ] [ text "Rename" ]

                Nothing ->
                    text ""
            ]


{-| The server's short name, editable in place by an admin -- unlike `nameView` (an `h2`'s own
children), this is a full label-left/value-right row, styled like
`Components.Pages.ServerInformationPage.FederationTab`'s `facebookAppIdRow` (`.server-details-color-row`
et al, not `Common.settingsRow` -- that helper's shared Save/Cancel doesn't fit a single
self-contained field like this one). Renders nothing for a non-admin viewer when unset, same as
`policySectionView`.
-}
shortNameView : Maybe String -> RenameStatus -> Maybe RellmAccount -> Html Msg
shortNameView maybeShortName shortNameStatus maybeAdminAccount =
    case ( shortNameStatus, maybeAdminAccount ) of
        ( Renaming pendingShortName status, Just _ ) ->
            div [ class "server-details-color-row server-details-color-row-edit" ]
                [ span [ class "server-details-color-label" ] [ text "Short Name" ]
                , input
                    [ class "server-details-rename-input"
                    , value pendingShortName
                    , onInput ShortNameChanged
                    , disabled (status == AccountsPanel.Submitting)
                    ]
                    []
                , Common.editSaveButton ShortNameSaveClicked status
                , Common.editCancelButton ShortNameCancelClicked status
                , Common.editErrorView status
                ]

        ( NotRenaming, Nothing ) ->
            case maybeShortName of
                Just shortName ->
                    div [ class "server-details-color-row" ]
                        [ span [ class "server-details-color-label" ] [ text "Short Name" ]
                        , span [ class "server-details-color-hex" ] [ text shortName ]
                        ]

                Nothing ->
                    text ""

        ( NotRenaming, Just _ ) ->
            div [ class "server-details-color-row" ]
                [ span [ class "server-details-color-label" ] [ text "Short Name" ]
                , span [ class "server-details-color-hex" ] [ text (Maybe.withDefault "Not set." maybeShortName) ]
                , button
                    [ class "server-details-rename-button"
                    , onClick (ShortNameEditClicked (Maybe.withDefault "" maybeShortName))
                    ]
                    [ text "Edit Short Name" ]
                ]

        -- `Renaming` with no admin account is unreachable in practice -- only
        -- `ShortNameEditClicked` (gated on `maybeAdminAccount` being `Just` at its
        -- own call site above) ever enters `Renaming` to begin with.
        ( Renaming _ _, Nothing ) ->
            text ""


versionView : VersionStatus -> Html Msg
versionView status =
    case status of
        VersionNotLoaded ->
            text ""

        LoadingVersion ->
            text ""

        VersionLoaded version ->
            p [ class "server-details-version" ] [ text ("v" ++ version) ]

        VersionFailed ->
            text ""


adminsView : Shared.Model -> RellmServer -> AdminsStatus -> Html Msg
adminsView shared server status =
    div [ class "server-details-admins" ]
        [ h3 [] [ text "Admins" ]
        , case status of
            AdminsNotLoaded ->
                text ""

            LoadingAdmins ->
                p [] [ text "Loading admins…" ]

            AdminsFailed ->
                p [] [ text "Couldn't load admins." ]

            AdminsLoaded [] ->
                p [] [ text "No admins found." ]

            AdminsLoaded admins ->
                div [ class "users-list" ] (List.map (adminCardView shared server) admins)
        ]


{-| One admin's `Users.userCard` -- links to that admin's profile (same card used by
`Components.Pages.UsersPage`'s People/Following/Followers/Friends listings), with no
follow-status/button slot (`text ""`) since this page is otherwise entirely read-only (see the
module doc) and doesn't track any per-card `FollowStatusAndButton.Model` state to back one.
-}
adminCardView : Shared.Model -> RellmServer -> User -> Html Msg
adminCardView shared server user =
    Users.userCard shared.basePath
        shared.accounts.mainFrontendHost
        server
        (RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts server.frontendHost)
        (text "")
        user
