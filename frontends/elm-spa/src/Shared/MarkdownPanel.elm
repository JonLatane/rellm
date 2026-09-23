module Shared.MarkdownPanel exposing (Model, Msg(..), TargetType(..), ViewMode, init, subscriptions, update, view)

{-| A single, app-wide Markdown editor: a plain monospace `<textarea>` and a
live `Components.Markdown.view` preview of the same text, with "Save"/
"Cancel" actions below. Shown side by side, or either alone, per `ViewMode`
(a 3-position slider in the header lets the user pick -- see `modeSlider`),
since a 50/50 split doesn't leave enough room for either half on a
phone-width screen. Wired into `Shared.Model`/`UI.elm` the same way
`Shared.AccountsPanel`/`Shared.StarredPanel` are -- one shared instance,
opened from wherever it's needed (see `TargetType`) rather than each caller
owning its own editor state.

Knows how to edit/submit a `Proto.Rellm.Post`'s `content` (via `TargetType`)
-- editing a `Post` already in hand (`PostContent`), or composing a brand new
reply to one (`NewReply`) -- or a `Proto.Rellm.User`'s `bio` (`UserBio`, see
`Components.UserProfilePage`). More `TargetType` constructors can be added
later without touching callers that only care about the ones they use.

-}

import Browser.Dom as Dom
import Components.Markdown as Markdown
import Components.Posts as Posts
import Components.UserPicker as UserPicker
import Components.Users as Users
import Grpc
import Html exposing (Html, button, div, img, label, option, select, span, text, textarea)
import Html.Attributes exposing (alt, attribute, class, disabled, id, placeholder, selected, spellcheck, src, title, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn)
import Json.Decode as Decode
import Proto.Rellm exposing (Author, Message, Post, ServerInfo, User, defaultGetPostsRequest, defaultPost, defaultSendMessageRequest, defaultServerInfo)
import Proto.Rellm.Permission exposing (Permission(..))
import Proto.Rellm.PostContext exposing (PostContext(..))
import Proto.Rellm.Rellm as Rellm
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer, withAccessToken)
import Task exposing (Task)
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)


type alias Model =
    { target : Maybe TargetType

    -- The `frontendHost` of the server `target`'s Post lives on -- needed to
    -- resolve the `RellmServer`/signed-in `Account` to submit as,
    -- and to verify (see `resolve`) that server's still enabled and that
    -- account still has the relevant permission, right before submitting.
    -- For `SendNewMessage`, this doubles as "who I'm sending as" -- see
    -- `PostingAsChanged`.
    , targetHost : String
    , content : String
    , status : SubmitStatus

    -- Deliberately *not* reset back to `Split` by `CancelClicked`/a
    -- successful save (see `update`) -- it's a standing display preference,
    -- not part of the in-progress edit, so it should carry over the next
    -- time this panel's opened.
    , viewMode : ViewMode

    -- `SendNewMessage`-only draft state, unused (and left at its `init`
    -- default) by every other `TargetType` -- see `extraFieldsView`.
    -- `messageRecipients`' own `host` always tracks `targetHost` (see
    -- `PostingAsChanged`), since a message's recipients all have to live on
    -- the same server as whoever's sending it.
    , messageSubject : String
    , messageRecipients : UserPicker.Model

    -- Whether the Subject field (`extraFieldsView`) is showing -- hidden by
    -- default behind the "…" toggle just left of the "To" label, since most
    -- messages don't need one; `SubjectToggleClicked` flips it,
    -- `messageSubject` itself is untouched either way.
    , messageSubjectExpanded : Bool
    }


type Msg
    = Open TargetType String
    | ContentChanged String
    | ViewModeSelected ViewMode
      -- The "Cancel" button -- doesn't discard anything itself. Only bubbles
      -- a request up through `update`'s own extra return value (for
      -- `Shared.update` to turn into a `Shared.RequestDelete
      -- ConfirmMarkdownEditingDataLost`, the same shared "are you sure?" flow
      -- `Shared.MyMediaPanel.DeleteClicked` uses -- see `Shared.DeleteConfirmation`)
      -- when `model.content` actually differs from `initialContent model.target`
      -- -- i.e. there's actually something to lose. Otherwise (nothing typed
      -- yet for a blank-start target like `NewReply`, or an existing target's
      -- content untouched from what it was opened with) closes immediately,
      -- same as `CancelConfirmed`, since there's nothing the user could
      -- accidentally discard.
    | CancelClicked
      -- Fired back from `Shared.update`'s `ConfirmDelete` once the user's
      -- confirmed the dialog `CancelClicked` requested -- this is what
      -- actually discards `model.content` back to `init`.
    | CancelConfirmed
    | SaveClicked
    | GotSaveResult (Result Grpc.Error (Maybe AccountsPanel.Msg))
      -- `SendNewMessage`'s own save result -- a separate constructor from
      -- `GotSaveResult` (rather than folding into it) because it's the one
      -- save that produces an entity any caller actually needs back: the
      -- freshly created `Message` itself (id + `messagingGroup`, needed to
      -- navigate/scroll to it -- see `Components.Pages.MessagesPage.MessageSent`)
      -- plus the host it was sent from (not recoverable from `Message` alone,
      -- see `sendMessageTask`'s own doc). Forwarded verbatim as part of
      -- `Shared.Msg` to whichever page is mounted (`Main.notifyPageOfSharedMsg`),
      -- so `Pages.Messages` can read it straight off the pattern match --
      -- no extra `Model` field needed just to shuttle it there.
    | GotSendMessageResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, String, Message ))
    | PostingAsChanged String
    | MessageSubjectChanged String
    | SubjectToggleClicked
    | UserPickerMsg UserPicker.Msg
      -- Discards a `Browser.Dom.focus` result -- see `focusCmdFor` -- same
      -- "focusing is best-effort" convention `Shared.AccountsPanel.NoOp`
      -- already follows (there's nothing useful to do if the target's
      -- vanished from the DOM already).
    | NoOp


{-| What a save should do once the user's done editing: `PostContent post`
overwrites `post`'s own content (via `UpdatePost`, re-fetching `post` fresh
first -- see `saveTask` -- so a stale in-hand copy can't clobber any of its
other fields, e.g. `visibility`, that changed server-side since this panel was
opened); `NewReply post` creates a brand new reply to `post` (via `CreatePost`,
`reply_to_post_id = post.id`), copying `post`'s own `visibility` for the new
reply; `UserBio user` overwrites `user`'s own `bio` (via `Users.updateUser`,
which does the same re-fetch-then-overwrite dance as `PostContent`).
`ServerDescription`/`ServerPrivacyPolicy`/`ServerMediaPolicy server` overwrite
just that one field of `server`'s `ServerInfo` (via `ConfigureServer`,
re-fetching the server's configuration fresh first -- see `saveTask` --
same reasoning as `PostContent`, and the same pattern
`Shared.AccountsPanel.renameServer` already uses for `name`). Only ever
opened for a signed-in account with `ADMIN` on that server (see `resolve`).

`SendNewMessage` composes a brand new `Message` (via `SendMessage`, see
`sendMessageTask` -- deliberately _not_ routed through `saveTask`/`resolve`'s
shared per-target dispatch, since it's the one target needing more than
`model.content` to submit). Its own extra draft state (who to send as, who to
send to) doesn't fit in a bare `content : String` either, so it lives in
`Model.messageSubject`/`.messageRecipients` instead, and its own chrome
replaces the plain `accountRow`/adds a fields block below it -- see
`accountRowFor`/`extraFieldsView`, the two extension points any future
`TargetType` needing its own top-chrome beyond the text/preview editor should
hook into, rather than special-casing `view` itself further. Its own payload
(unlike every other `TargetType`, which either carries no payload or an
existing entity to overwrite) is the recipients to pre-seed
`messageRecipients` with when this panel opens (`Open`, below) -- `[]` for a
fresh compose (`Pages.Messages`' own "Send Message" button), or a messaging
group's current members, minus whoever's sending, for "Reply"
(`MessagesPage.ReplyClicked`) -- either way just the _initial_ selection,
freely changed from the picker afterward like any other.

-}
type TargetType
    = PostContent Post
    | NewReply Post
    | NewPostContent String
    | UserBio User
    | ServerDescription RellmServer
    | ServerPrivacyPolicy RellmServer
    | ServerMediaPolicy RellmServer
    | SendNewMessage (List Author)


type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


{-| Which half(s) of `markdown-panel-split` to actually render -- `Split`
(the default) is the original editor+preview side by side; `TextOnly`/
`MarkdownOnly` give the full width to just one, which is what actually makes
this panel usable on a phone-width screen (see the mode slider in `view`).
-}
type ViewMode
    = TextOnly
    | Split
    | MarkdownOnly


type alias Resolved =
    { server : RellmServer
    , account : RellmAccount
    }


init : Model
init =
    { target = Nothing
    , targetHost = ""
    , content = ""
    , status = Idle
    , viewMode = Split
    , messageSubject = ""
    , messageRecipients = UserPicker.empty ""
    , messageSubjectExpanded = False
    }


{-| Needs `AccountsPanel.Model` (to resolve `targetHost` to a connected
`Server`/signed-in `Account` to submit as, and to verify -- see `resolve` --
that they're actually usable) and can itself surface an `AccountsPanel.Msg` it
needs forwarded on its behalf -- an `AccessTokenResponseReceived`, if
`saveTask` had to refresh the account's token, that `AccountsPanel.performWithAccountServer`
already builds -- for `Shared.update` to actually dispatch, same convention as
`Shared.StarredPanel.update` -- paired, in that same third-tuple-slot
convention, with a `Bool` that's `True` only right after a `saveTask`-driven
save succeeds (`GotSaveResult`, never `GotSendMessageResult`, see that
branch's own doc): `Shared.update` fires `Shared.ShowScrollPreserver` on it,
since the edited Post's re-fetched content (see `saveTask`) can change its
rendered height once this panel closes and the page under it catches up,
same yank `Shared.ShowScrollPreserver` already guards against on back
navigation -- and a third `Bool`, `True` only right after `CancelClicked`, for
`Shared.update` to turn into a `Shared.RequestDelete ConfirmMarkdownEditingDataLost`
(see `Msg`'s own doc on `CancelClicked`/`CancelConfirmed`).
-}
update : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Bool, Bool ) )
update accountsPanelModel msg model =
    case msg of
        Open target host ->
            let
                -- `SendNewMessage`'s own recipients fetch, kicked off
                -- immediately against `host` (the initially-resolved "send
                -- as" server -- see `Pages.Messages`' own default-host
                -- pick) -- no other `TargetType` has anything to fetch at
                -- `Open` time. `initialRecipients` (`SendNewMessage`'s own
                -- payload -- see its doc) is overlaid onto the freshly
                -- `init`ed picker's own (empty) `selected` afterward -- it's
                -- only ever non-empty for "Reply" (`MessagesPage.ReplyClicked`),
                -- pre-populating the picker rather than making the user
                -- re-pick everyone already in the thread.
                ( messageRecipients, recipientsCmd ) =
                    case target of
                        SendNewMessage initialRecipients ->
                            let
                                ( picker, cmd ) =
                                    UserPicker.init host
                            in
                            ( UserPicker.withInitialSelection initialRecipients picker, cmd )

                        _ ->
                            ( UserPicker.empty "", Cmd.none )
            in
            ( { model
                | target = Just target
                , targetHost = host
                , content = initialContent target
                , status = Idle
                , messageSubject = ""
                , messageRecipients = messageRecipients
                , messageSubjectExpanded = False
              }
            , Cmd.batch [ Cmd.map UserPickerMsg recipientsCmd, focusCmdFor target ]
            , ( Nothing, False, False )
            )

        ContentChanged content ->
            ( { model | content = content }, Cmd.none, ( Nothing, False, False ) )

        ViewModeSelected viewMode ->
            ( { model | viewMode = viewMode }, Cmd.none, ( Nothing, False, False ) )

        CancelClicked ->
            let
                hasUnsavedChanges : Bool
                hasUnsavedChanges =
                    case model.target of
                        Just target ->
                            model.content /= initialContent target

                        Nothing ->
                            False
            in
            if hasUnsavedChanges then
                ( model, Cmd.none, ( Nothing, False, True ) )

            else
                ( { init | viewMode = model.viewMode }, Cmd.none, ( Nothing, False, False ) )

        CancelConfirmed ->
            ( { init | viewMode = model.viewMode }, Cmd.none, ( Nothing, False, False ) )

        -- `SendNewMessage`-only -- switches which signed-in account (i.e.
        -- which server, since `AccountsPanel.enabledAccounts` never has more
        -- than one per host) to send as. A different server means a wholly
        -- different user pool, so recipients picked against the old one
        -- can't carry over -- swaps in a fresh `UserPicker` for the new host
        -- (discarding the old selection) exactly when the host actually
        -- changes, rather than clearing it on every selection.
        PostingAsChanged accountId ->
            case AccountsPanel.enabledAccounts accountsPanelModel |> List.filter (\account -> RellmAccounts.rellmAccountId account == accountId) |> List.head of
                Just account ->
                    if account.server == model.targetHost then
                        ( model, Cmd.none, ( Nothing, False, False ) )

                    else
                        let
                            ( messageRecipients, recipientsCmd ) =
                                UserPicker.init account.server
                        in
                        ( { model | targetHost = account.server, messageRecipients = messageRecipients }
                        , Cmd.map UserPickerMsg recipientsCmd
                        , ( Nothing, False, False )
                        )

                Nothing ->
                    ( model, Cmd.none, ( Nothing, False, False ) )

        MessageSubjectChanged subject ->
            ( { model | messageSubject = subject }, Cmd.none, ( Nothing, False, False ) )

        SubjectToggleClicked ->
            ( { model | messageSubjectExpanded = not model.messageSubjectExpanded }, Cmd.none, ( Nothing, False, False ) )

        UserPickerMsg subMsg ->
            let
                ( newRecipients, cmd, ( maybeAccountsPanelMsg, justPickedRecipient ) ) =
                    UserPicker.update accountsPanelModel subMsg model.messageRecipients

                -- A just-picked recipient's own search input has already
                -- been cleared (`UserPicker.update`'s `ToggleSelected`
                -- branch) -- refocus it so the next name can be typed
                -- straight away, same `Dom.focus`/`NoOp` convention
                -- `focusCmdFor` uses for this same id.
                refocusCmd : Cmd Msg
                refocusCmd =
                    if justPickedRecipient then
                        Task.attempt (\_ -> NoOp) (Dom.focus "user-picker-search-input")

                    else
                        Cmd.none
            in
            ( { model | messageRecipients = newRecipients }
            , Cmd.batch [ Cmd.map UserPickerMsg cmd, refocusCmd ]
            , ( maybeAccountsPanelMsg, False, False )
            )

        SaveClicked ->
            case model.target of
                -- No RPC to make -- there's no Post yet (see `TargetType`'s
                -- own doc on `NewPostContent`). `Shared.update`'s own
                -- `MarkdownPanelMsg` branch is what actually hands
                -- `model.content` back to `Shared.NewPostPanel`, reading it
                -- off this exact `SaveClicked` before `update` (here) resets
                -- it back to `init` below.
                Just (NewPostContent _) ->
                    ( { init | viewMode = model.viewMode }, Cmd.none, ( Nothing, False, False ) )

                -- Routed through `sendMessageTask` directly, not
                -- `resolve`/`saveTask`'s shared dispatch -- see
                -- `TargetType`'s own doc on why.
                Just ((SendNewMessage _) as sendTarget) ->
                    case resolve accountsPanelModel sendTarget model.targetHost of
                        Err err ->
                            ( { model | status = SubmitFailed err }, Cmd.none, ( Nothing, False, False ) )

                        Ok resolved ->
                            case sendNewMessageProblem model of
                                Just err ->
                                    ( { model | status = SubmitFailed err }, Cmd.none, ( Nothing, False, False ) )

                                Nothing ->
                                    ( { model | status = Submitting }
                                    , sendMessageTask
                                        accountsPanelModel
                                        ( Just resolved.account.userId, resolved.server.frontendHost )
                                        (UserPicker.selectedUsers model.messageRecipients |> List.map .id)
                                        model.messageSubject
                                        model.content
                                        |> Task.attempt GotSendMessageResult
                                    , ( Nothing, False, False )
                                    )

                Just target ->
                    case resolve accountsPanelModel target model.targetHost of
                        Ok resolved ->
                            ( { model | status = Submitting }
                            , saveTask accountsPanelModel ( Just resolved.account.userId, resolved.server.frontendHost ) target model.content
                                |> Task.attempt GotSaveResult
                            , ( Nothing, False, False )
                            )

                        Err err ->
                            ( { model | status = SubmitFailed err }, Cmd.none, ( Nothing, False, False ) )

                Nothing ->
                    ( model, Cmd.none, ( Nothing, False, False ) )

        GotSaveResult (Ok maybeAccountsPanelMsg) ->
            ( { init | viewMode = model.viewMode }, Cmd.none, ( maybeAccountsPanelMsg, True, False ) )

        GotSaveResult (Err err) ->
            ( { model | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Cmd.none, ( Nothing, False, False ) )

        -- `False`, unlike `GotSaveResult`'s own `Ok` branch above -- a sent
        -- message isn't reshaping any content already on screen the way a
        -- `saveTask`-driven edit can (see `update`'s own doc), and
        -- `MessagesPage.MessageSent` (what `Pages.Messages`' own
        -- `SharedMsg` handling of this exact `Ok` dispatches) already drives
        -- its own explicit scroll to the new message -- `ShowScrollPreserver`'s
        -- spacer would just be a spurious flash of empty space underneath
        -- that, not a jump it's actually preventing.
        GotSendMessageResult (Ok ( maybeAccountsPanelMsg, _, _ )) ->
            ( { init | viewMode = model.viewMode }, Cmd.none, ( maybeAccountsPanelMsg, False, False ) )

        GotSendMessageResult (Err err) ->
            ( { model | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Cmd.none, ( Nothing, False, False ) )

        NoOp ->
            ( model, Cmd.none, ( Nothing, False, False ) )


{-| Only `SendNewMessage`'s embedded `UserPicker` has anything to subscribe
to (its own FLIP animations) -- every other `TargetType` (and `Nothing`)
subscribes to nothing.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    case model.target of
        Just (SendNewMessage _) ->
            Sub.map UserPickerMsg (UserPicker.subscriptions model.messageRecipients)

        _ ->
            Sub.none


{-| Always rendered (even "closed"), same as `UI.elm`'s Accounts/Starred
panels, so opening/closing is a plain CSS transition -- see `openClosedClass`.
Needs `AccountsPanel.Model` for the same reason `update` does -- resolving
`targetHost` to show who's actually about to post/edit (`accountRow`), and any
problem with that (`resolve`) inline, before the user even taps Save.
-}



-- VIEW


view : AccountsPanel.Model -> Model -> Html Msg
view accountsPanelModel model =
    let
        resolution : Maybe (Result String Resolved)
        resolution =
            model.target |> Maybe.map (\target -> resolve accountsPanelModel target model.targetHost)

        -- `SendNewMessage`-only extra validation (recipients/content) that
        -- doesn't fit `resolve`'s per-target host/account signature -- see
        -- `sendNewMessageProblem`'s own doc.
        sendMessageProblem : Maybe String
        sendMessageProblem =
            case model.target of
                Just (SendNewMessage _) ->
                    sendNewMessageProblem model

                _ ->
                    Nothing

        canSave : Bool
        canSave =
            case ( resolution, sendMessageProblem ) of
                ( Just (Ok _), Nothing ) ->
                    True

                _ ->
                    False

        errorMessage : Maybe String
        errorMessage =
            case model.status of
                SubmitFailed err ->
                    Just err

                _ ->
                    case resolution of
                        Just (Err err) ->
                            Just err

                        _ ->
                            sendMessageProblem
    in
    div
        (classes [ "markdown-panel", "nav-panel", openClosedClass (model.target /= Nothing), hostnameToCSSClass model.targetHost ]
            :: saveShortcutAttrs model
        )
        [ div [ class "markdown-panel-header" ]
            [ modeSlider model.targetHost model.viewMode
            , accountRowFor accountsPanelModel model
            ]
        , extraFieldsView accountsPanelModel model
        , div [ classes [ "markdown-panel-split", viewModeClass model.viewMode ] ]
            (case model.viewMode of
                TextOnly ->
                    [ editorView model ]

                Split ->
                    [ editorView model, previewView model ]

                MarkdownOnly ->
                    [ previewView model ]
            )
        , case errorMessage of
            Just err ->
                div [ class "markdown-panel-error" ] [ text err ]

            Nothing ->
                text ""
        , div [ class "markdown-panel-actions" ]
            [ button
                [ class "markdown-panel-cancel"
                , onClick CancelClicked
                , disabled (model.status == Submitting)
                ]
                [ text "Cancel" ]
            , button
                [ classes [ "markdown-panel-save", model.targetHost, "background-color-primary" ]
                , onClick SaveClicked
                , disabled (model.status == Submitting || not canSave)
                ]
                [ text (saveButtonText model.target model.status) ]
            ]
        ]


{-| Cmd+S (Mac)/Ctrl+S (elsewhere) submits, same as clicking `Save`; Escape
requests the same "are you sure?" confirmation as clicking `Cancel` (see
`CancelClicked`'s own doc). `preventDefaultOn`, not a `Browser.Events.onKeyDown`
subscription (compare `Shared.MediaViewerPanel.subscriptions`'s arrow keys),
since only an event handler on the DOM can stop the browser's own "Save Page
As" from popping up on Cmd/Ctrl+S; attached to the panel's own root div
(always rendered -- see `view`'s own doc comment -- so this works whether the
keypress bubbles up from the `textarea` or from a button) rather than
globally, so neither shortcut fires unless this panel's actually open
(`model.target /= Nothing`) and only one save/cancel at a time
(`model.status /= Submitting`) -- mirrors the `Save`/`Cancel` buttons' own
`disabled` condition in spirit, though it doesn't re-check `canSave`/`resolve`
here since `SaveClicked` (see `update`) already re-checks that itself and
surfaces any problem as `errorMessage`.
-}
saveShortcutAttrs : Model -> List (Html.Attribute Msg)
saveShortcutAttrs model =
    if model.target /= Nothing && model.status /= Submitting then
        [ preventDefaultOn "keydown" panelKeyDecoder ]

    else
        []


panelKeyDecoder : Decode.Decoder ( Msg, Bool )
panelKeyDecoder =
    Decode.map3 (\key ctrlKey metaKey -> ( String.toLower key, ctrlKey || metaKey ))
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        |> Decode.andThen
            (\( key, isModifierDown ) ->
                if isModifierDown && key == "s" then
                    Decode.succeed ( SaveClicked, True )

                else if key == "escape" then
                    Decode.succeed ( CancelClicked, True )

                else
                    Decode.fail "not Cmd/Ctrl+S or Escape"
            )


{-| What `Open` should focus, if anything, once this panel's actually on
screen -- today, just `SendNewMessage`'s two distinct entry points
(`Pages.Messages`' "Compose"/`MessagesPage.ReplyClicked`'s "Reply"), which
`initialRecipients` already tells apart (see `Open`'s own doc: empty only for
a fresh compose, never for a reply -- `ReplyClicked` always seeds at least the
other thread participants). A fresh compose has no recipients chosen yet, so
focus the picker's own search input; a reply already has its recipients
pre-filled, so focus the content editor instead, since that's the only thing
left to fill in. Every other `TargetType` leaves focus wherever the browser
already put it (typically whatever button was clicked to open this panel).
-}
focusCmdFor : TargetType -> Cmd Msg
focusCmdFor target =
    case target of
        SendNewMessage [] ->
            Task.attempt (\_ -> NoOp) (Dom.focus "user-picker-search-input")

        SendNewMessage (_ :: _) ->
            Task.attempt (\_ -> NoOp) (Dom.focus "markdown-panel-editor")

        _ ->
            Cmd.none


editorView : Model -> Html Msg
editorView model =
    textarea
        [ id "markdown-panel-editor"
        , class "markdown-panel-editor"
        , value model.content
        , onInput ContentChanged
        , spellcheck False
        , placeholder "Write some Markdown…"
        ]
        []


previewView : Model -> Html Msg
previewView model =
    Markdown.view [ class "markdown-panel-preview" ] model.content


{-| A single sliding 3-position control -- Text / Split / Markdown -- rather
than three separate buttons, so the "which one's active" state reads as one
moving thumb (`markdown-panel-mode-thumb`, positioned purely in CSS off
`viewModeClass`) instead of three independently-highlighted pills. Small
enough to sit centered under the title/account row on a phone-width screen
(see markdown\_panel.css).
-}
modeSlider : String -> ViewMode -> Html Msg
modeSlider targetHost mode =
    div [ classes [ "markdown-panel-mode-slider", viewModeClass mode ] ]
        [ div [ classes [ "markdown-panel-mode-thumb", targetHost, "background-color-primary" ] ] []
        , modeOption mode TextOnly "Text"
        , modeOption mode Split "Split"
        , modeOption mode MarkdownOnly "Preview"
        ]


modeOption : ViewMode -> ViewMode -> String -> Html Msg
modeOption current target label =
    button
        [ classes
            ("markdown-panel-mode-option"
                :: (if current == target then
                        [ "selected" ]

                    else
                        []
                   )
            )
        , onClick (ViewModeSelected target)
        ]
        [ text label ]


{-| The header row's account chrome -- dispatches per `model.target`, same
extension point `extraFieldsView` below is, for any future `TargetType`
needing its own top chrome: `SendNewMessage` swaps the plain `accountRow`
(read-only "who's about to act") out for an interactive picker (`AccountsPanel.enabledAccounts`
is the whole point -- there's a real choice of who to send as, unlike every
other target where `targetHost` was already resolved by whoever opened this
panel); every other target keeps today's plain `accountRow`.
-}
accountRowFor : AccountsPanel.Model -> Model -> Html Msg
accountRowFor accountsPanelModel model =
    case model.target of
        Just (SendNewMessage _) ->
            sendMessagePostingAsRow accountsPanelModel model

        _ ->
            accountRow accountsPanelModel model


{-| "Editing as <avatar> username" / "Posting as <avatar> username" -- no
link, just enough to make clear which signed-in account (of possibly several
on this server) is about to make the edit/reply. Blank if `targetHost` has no
signed-in account at all -- `resolve`'s own "You're not signed in on that
server" error (see `errorMessage`) already covers that case.
-}
accountRow : AccountsPanel.Model -> Model -> Html Msg
accountRow accountsPanelModel model =
    case RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost of
        Just account ->
            div [ class "markdown-panel-account" ]
                [ text (verbFor model.target)
                , accountAvatar accountsPanelModel.servers account
                , span [ class "markdown-panel-account-name" ] [ text account.username ]
                ]

        Nothing ->
            text ""


{-| `accountRowFor`'s `SendNewMessage` case -- "Sending as <avatar> username"
alone when there's only one enabled account anywhere (no point offering a
one-item dropdown, mirrors `Shared.CreateNewPanel.postingAsSelector`'s own
single-account case), otherwise a `<select>` of every enabled account
(`AccountsPanel.enabledAccounts`, never more than one per host) -- picking one
fires `PostingAsChanged`, which resets `messageRecipients` if it's actually a
different host (see that branch's own doc). Blank if there's no enabled
account at all -- `resolve`'s "You're not signed in on that server" error
already covers that case (`Pages.Messages`' Send Message button is also
hidden entirely then, but this panel can't assume it was only ever opened
from there).
-}
sendMessagePostingAsRow : AccountsPanel.Model -> Model -> Html Msg
sendMessagePostingAsRow accountsPanelModel model =
    case AccountsPanel.enabledAccounts accountsPanelModel of
        [] ->
            text ""

        [ onlyAccount ] ->
            div [ class "markdown-panel-account" ]
                [ text "Sending as "
                , accountAvatar accountsPanelModel.servers onlyAccount
                , span [ class "markdown-panel-account-name" ] [ text onlyAccount.username ]
                ]

        accounts ->
            div [ class "markdown-panel-account" ]
                [ case RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost of
                    Just account ->
                        accountAvatar accountsPanelModel.servers account

                    Nothing ->
                        text ""
                , select [ class "markdown-panel-account-select", onInput PostingAsChanged ]
                    (List.map
                        (\account ->
                            option
                                [ value (RellmAccounts.rellmAccountId account)
                                , selected (account.server == model.targetHost)
                                ]
                                [ text (account.username ++ " on " ++ account.server) ]
                        )
                        accounts
                    )
                ]


accountAvatar : List RellmServer -> RellmAccount -> Html msg
accountAvatar servers account =
    case RellmAccounts.rellmAccountAvatarUrl servers account of
        Just url ->
            img [ class "markdown-panel-account-avatar", src url, alt account.username, attribute "loading" "lazy" ] []

        Nothing ->
            div [ classes [ "markdown-panel-account-avatar", "placeholder" ] ] [ text (RellmServers.initialLetter account.username) ]


{-| The second extension point (alongside `accountRowFor`) for a
`TargetType`'s own top chrome -- rendered between the header row and the
text/preview split. `SendNewMessage` is the only target using it today (a
Subject field plus the recipients `Components.UserPicker`); every other
target renders nothing here.

The Subject field itself is hidden behind a "…" toggle
(`subjectToggleButton`) just left of the "To" label rather than shown
outright -- most messages don't need one, and burying it saves the vertical
space `markdown-panel-message-fields`'s own `max-height` (markdown\_panel.css)
has to share with the recipients picker below it. `SubjectToggleClicked`
flips `model.messageSubjectExpanded`; the subject text itself
(`model.messageSubject`) is untouched by hiding it again, so toggling back
and forth doesn't lose anything already typed.

-}
extraFieldsView : AccountsPanel.Model -> Model -> Html Msg
extraFieldsView accountsPanelModel model =
    case model.target of
        Just (SendNewMessage _) ->
            div [ class "markdown-panel-message-fields" ]
                [ if model.messageSubjectExpanded then
                    div [ class "markdown-panel-field" ]
                        [ label [ class "markdown-panel-label" ] [ text "Subject" ]
                        , Html.input
                            [ type_ "text"
                            , class "markdown-panel-subject-input"
                            , value model.messageSubject
                            , onInput MessageSubjectChanged
                            , placeholder "Subject (optional)"
                            ]
                            []
                        ]

                  else
                    text ""
                , div [ class "markdown-panel-field" ]
                    [ div [ class "markdown-panel-label-row" ]
                        [ subjectToggleButton model.messageSubjectExpanded
                        , label [ class "markdown-panel-label" ] [ text "To" ]
                        ]
                    , Html.map UserPickerMsg (UserPicker.view accountsPanelModel model.messageRecipients)
                    ]
                ]

        _ ->
            text ""


subjectToggleButton : Bool -> Html Msg
subjectToggleButton expanded =
    button
        [ type_ "button"
        , classes
            ("markdown-panel-subject-toggle"
                :: (if expanded then
                        [ "expanded" ]

                    else
                        []
                   )
            )
        , onClick SubjectToggleClicked
        , title
            (if expanded then
                "Hide subject"

             else
                "Add a subject"
            )
        ]
        [ text "…" ]


initialContent : TargetType -> String
initialContent target =
    case target of
        PostContent post ->
            Maybe.withDefault "" post.content

        NewReply _ ->
            ""

        NewPostContent content ->
            content

        UserBio user ->
            user.bio

        ServerDescription server ->
            Maybe.withDefault "" (RellmServers.rellmServerInfoOf server).description

        ServerPrivacyPolicy server ->
            Maybe.withDefault "" (RellmServers.rellmServerInfoOf server).privacyPolicy

        ServerMediaPolicy server ->
            Maybe.withDefault "" (RellmServers.rellmServerInfoOf server).mediaPolicy

        SendNewMessage _ ->
            ""


viewModeClass : ViewMode -> String
viewModeClass mode =
    case mode of
        TextOnly ->
            "mode-text"

        Split ->
            "mode-split"

        MarkdownOnly ->
            "mode-markdown"


verbFor : Maybe TargetType -> String
verbFor target =
    case target of
        Just (NewReply _) ->
            "Posting as "

        Just (NewPostContent _) ->
            "Writing as "

        _ ->
            "Editing as "


{-| "Save"/"Saving…" for every other target, "Send"/"Sending…" for
`SendNewMessage` -- this is the one target that isn't editing/saving
anything, it's dispatching a brand new `Message`, so the button should read
accordingly.
-}
saveButtonText : Maybe TargetType -> SubmitStatus -> String
saveButtonText target status =
    case ( target, status == Submitting ) of
        ( Just (SendNewMessage _), True ) ->
            "Sending…"

        ( Just (SendNewMessage _), False ) ->
            "Send"

        ( _, True ) ->
            "Saving…"

        ( _, False ) ->
            "Save"


{-| Verifies `host`/`target` are actually usable right now, right before a
save: (1) `host` resolves to a known `Server` that's currently enabled (a
disabled server shouldn't be posted/edited to just because this panel was
opened before it was disabled), and (2) the account signed into that server
has the relevant permission for `target` -- the post's own author for
`PostContent` (matching `backend/src/rpcs/posts/update_post.rs`'s
`self_update` check), `REPLYTOPOSTS` for `NewReply`, or the user themself/an
`ADMIN` for `UserBio` (matching `backend/src/rpcs/users/update_user.rs`'s own
`self_update || admin` check). Used both by `SaveClicked` (to actually gate
the RPC) and by `view` (to show the same problem inline, and disable Save,
before the user even tries).
-}
resolve : AccountsPanel.Model -> TargetType -> String -> Result String Resolved
resolve accountsPanelModel target host =
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
                        case target of
                            PostContent post ->
                                if Posts.isAuthor account post then
                                    Ok { server = server, account = account }

                                else
                                    Err "You can only edit your own posts."

                            NewReply _ ->
                                if List.member REPLYTOPOSTS account.permissions then
                                    Ok { server = server, account = account }

                                else
                                    Err "You don't have permission to reply."

                            NewPostContent _ ->
                                if List.member CREATEPOSTS account.permissions || RellmAccounts.isAdmin account then
                                    Ok { server = server, account = account }

                                else
                                    Err "You don't have permission to create posts."

                            UserBio user ->
                                if account.userId == user.id || List.member ADMIN account.permissions then
                                    Ok { server = server, account = account }

                                else
                                    Err "You can only edit your own bio."

                            ServerDescription _ ->
                                if RellmAccounts.isAdmin account then
                                    Ok { server = server, account = account }

                                else
                                    Err "You must be an admin to edit this."

                            ServerPrivacyPolicy _ ->
                                if RellmAccounts.isAdmin account then
                                    Ok { server = server, account = account }

                                else
                                    Err "You must be an admin to edit this."

                            ServerMediaPolicy _ ->
                                if RellmAccounts.isAdmin account then
                                    Ok { server = server, account = account }

                                else
                                    Err "You must be an admin to edit this."

                            -- No special permission -- `send_message.rs`
                            -- never calls `validate_permission` at all (it
                            -- even supports a fully anonymous sender). Just
                            -- needing a signed-in account on `host` (already
                            -- established above) is this UI's own,
                            -- stricter-than-the-backend choice, matching
                            -- "choose among any of the users I'm currently
                            -- logged in as" -- see `sendMessagePostingAsRow`.
                            SendNewMessage _ ->
                                Ok { server = server, account = account }


{-| `SendNewMessage`-only validation `resolve` can't do itself -- it only
sees `TargetType`/`host`, not the rest of `Model` (`messageRecipients`'
current selection, `content`), both required by `send_message.rs`
(`to_user_ids_required`/`body_text_required`). Checked alongside `resolve`
by both `view` (`errorMessage`/`canSave`) and `SaveClicked`, same
"validate again right before the RPC, not just when Save was disabled"
belt-and-suspenders `resolve` itself already follows.
-}
sendNewMessageProblem : Model -> Maybe String
sendNewMessageProblem model =
    if List.isEmpty (UserPicker.selectedUsers model.messageRecipients) then
        Just "Choose at least one recipient."

    else if String.isEmpty (String.trim model.content) then
        Just "Write a message."

    else
        Nothing


{-| `PostContent` re-fetches its Post fresh (via `GetPosts`) before submitting
`UpdatePost` -- only `content` from `model.content` is overlaid onto that fresh
copy, so any of its other fields (`visibility`, `media`, ...) that changed
server-side since this panel opened aren't clobbered by a stale in-hand
snapshot (`UpdatePost` takes -- and unconditionally applies -- a whole `Post`,
see `backend/src/rpcs/posts/update_post.rs`). `NewReply` has no such race to
guard against -- it's creating a brand new Post, not overwriting an existing
one -- so it submits straight from the `post` it was opened with. `UserBio`
does the same re-fetch-then-overwrite dance as `PostContent`, via
`Users.updateUser`. Only a `Msg` to dispatch (if a token refresh happened) is
returned -- none of these three cases' updated entities are used by any
caller (see `Pages.Post.PostId_`/`Components.UserProfilePage`'s
`GotSaveResult` handling, which just refetches their own copy on success).
-}
saveTask : AccountsPanel.Model -> AccountsPanel.MaybeAccountServer -> TargetType -> String -> Task Grpc.Error (Maybe AccountsPanel.Msg)
saveTask accountsPanelModel maybeAccountServer target content =
    case target of
        PostContent post ->
            AccountsPanel.performWithAccountServer
                accountsPanelModel
                maybeAccountServer
                (\server token ->
                    Grpc.new Rellm.getPosts { defaultGetPostsRequest | postId = Just post.id }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                        |> Task.andThen
                            (\response ->
                                case List.head response.posts of
                                    Just freshPost ->
                                        Grpc.new Rellm.updatePost { freshPost | content = Just content }
                                            |> Grpc.setHost (RellmServers.rellmServerUrl server)
                                            |> withAccessToken (Just token)
                                            |> Grpc.toTask

                                    Nothing ->
                                        Task.fail Grpc.NetworkError
                            )
                )
                |> Task.map Tuple.first

        NewReply post ->
            AccountsPanel.performWithAccountServer
                accountsPanelModel
                maybeAccountServer
                (\server token ->
                    Grpc.new Rellm.createPost
                        { defaultPost
                            | replyToPostId = Just post.id
                            , content = Just content
                            , context = REPLY
                            , visibility = post.visibility
                        }
                        |> Grpc.setHost (RellmServers.rellmServerUrl server)
                        |> withAccessToken (Just token)
                        |> Grpc.toTask
                )
                |> Task.map Tuple.first

        -- Unreachable in practice -- `SaveClicked` (see its own doc) never
        -- calls `saveTask` at all for this target, short-circuiting straight
        -- back to `init` instead. Still needs a branch here for exhaustiveness.
        NewPostContent _ ->
            Task.fail Grpc.NetworkError

        UserBio user ->
            Users.updateUser accountsPanelModel maybeAccountServer user.id (\freshUser -> { freshUser | bio = content })
                |> Task.map Tuple.first

        ServerDescription server ->
            saveServerInfoField accountsPanelModel maybeAccountServer server (\info -> { info | description = Just content })

        ServerPrivacyPolicy server ->
            saveServerInfoField accountsPanelModel maybeAccountServer server (\info -> { info | privacyPolicy = Just content })

        ServerMediaPolicy server ->
            saveServerInfoField accountsPanelModel maybeAccountServer server (\info -> { info | mediaPolicy = Just content })

        -- Unreachable in practice -- `SaveClicked` routes `SendNewMessage`
        -- straight to `sendMessageTask` instead (see `TargetType`'s own
        -- doc on why), never through this shared `target`+`content`
        -- dispatch. Still needs a branch here for exhaustiveness, same as
        -- `NewPostContent` above.
        SendNewMessage _ ->
            Task.fail Grpc.NetworkError


{-| `SendNewMessage`'s own save -- unlike every `saveTask` branch above, needs
more than `target`+`content` (`recipientUserIds`, `subject`), so it isn't one
of those; `SaveClicked` calls this directly instead. No re-fetch-then-overlay
dance (unlike `PostContent`/`UserBio`) -- there's nothing existing to
overwrite, this always creates a brand new `Message`. Unlike every `saveTask`
branch (which discard their own RPC's response, `Task.map Tuple.first`ing it
away), this keeps both the response `Message` itself _and_ `server.frontendHost`
-- `SendMessage` is the one save whose caller (`Components.Pages.MessagesPage`,
via `GotSendMessageResult`) needs to know exactly what got created and where,
to navigate/scroll to it; `Message` has no host of its own to recover that
from afterward (it's purely an Elm-side routing concept), so it has to be
captured here, at the one point this task actually knows which server it
talked to.
-}
sendMessageTask :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> List String
    -> String
    -> String
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, String, Message )
sendMessageTask accountsPanelModel maybeAccountServer recipientUserIds subject bodyText =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\server token ->
            Grpc.new Rellm.sendMessage
                { defaultSendMessageRequest
                    | toUserIds = recipientUserIds
                    , subject =
                        if String.isEmpty (String.trim subject) then
                            Nothing

                        else
                            Just (String.trim subject)
                    , bodyText = Just bodyText
                }
                |> Grpc.setHost (RellmServers.rellmServerUrl server)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.map (\message -> ( server.frontendHost, message ))
        )
        |> Task.map (\( maybeAccountsPanelMsg, ( host, message ) ) -> ( maybeAccountsPanelMsg, host, message ))


{-| Shared by `ServerDescription`/`ServerPrivacyPolicy`/`ServerMediaPolicy` --
re-fetches `server`'s configuration fresh (`GetServerConfiguration`) and
overlays just `updateInfo`'s change onto its `serverInfo` before writing the
whole thing back (`ConfigureServer`), same fetch-then-overlay-then-write
pattern (and the same reasoning -- not clobbering a concurrent config change
made elsewhere) as `Shared.AccountsPanel.renameServer`. Unlike the other
`saveTask` cases, the resulting `Msg` isn't just a possible token refresh --
it's `AccountsPanel.GotServerConfigSaveResult`, which patches the freshly
written `ServerConfiguration` straight into `Shared.AccountsPanel.Model.servers`
(keyed by `server.frontendHost`) so `Components.Pages.ServerInformationPage`'s
view picks up the change without a separate refetch of its own. A token
refresh happening during this exact save (rare -- see `performWithAccountServer`)
is deliberately not separately propagated here; the next authenticated request
on this server just refreshes again.
-}
saveServerInfoField :
    AccountsPanel.Model
    -> AccountsPanel.MaybeAccountServer
    -> RellmServer
    -> (ServerInfo -> ServerInfo)
    -> Task Grpc.Error (Maybe AccountsPanel.Msg)
saveServerInfoField accountsPanelModel maybeAccountServer server updateInfo =
    AccountsPanel.performWithAccountServer
        accountsPanelModel
        maybeAccountServer
        (\resolvedServer token ->
            Grpc.new Rellm.getServerConfiguration {}
                |> Grpc.setHost (RellmServers.rellmServerUrl resolvedServer)
                |> withAccessToken (Just token)
                |> Grpc.toTask
                |> Task.andThen
                    (\freshConfig ->
                        let
                            info : ServerInfo
                            info =
                                Maybe.withDefault defaultServerInfo freshConfig.serverInfo
                        in
                        Grpc.new Rellm.configureServer { freshConfig | serverInfo = Just (updateInfo info) }
                            |> Grpc.setHost (RellmServers.rellmServerUrl resolvedServer)
                            |> withAccessToken (Just token)
                            |> Grpc.toTask
                    )
        )
        |> Task.map (\( _, newConfig ) -> Just (AccountsPanel.GotServerConfigSaveResult server.frontendHost newConfig))
