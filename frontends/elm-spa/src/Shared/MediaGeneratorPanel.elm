module Shared.MediaGeneratorPanel exposing
    ( Model
    , Msg(..)
    , Target(..)
    , init
    , update
    , view
    )

{-| A single, app-wide AI image generation panel -- opened contextually (a Post/Event's own
"Generate Media…" button, next to its existing "Edit Media…" -- see `Components.Posts.postDetail`/
`Pages.Event.PostId_`), the same "one shared occasion, `Nothing`/`""` means closed" convention
`Shared.MarkdownPanel`/`Shared.MyMediaPanel` already use. Shaped like `MarkdownPanel` (a prompt to
edit, Save/Cancel below), but with three inputs instead of one: which of the caller's
`AIModel`s to call (`modelChooserView`), the editable prompt (`promptView`), and a set of
reference media (`mediaSectionView`) -- reusing `Shared.MyMediaPanel`'s own `MultiSelect` chooser
for the last, the same picker Post/Event editing already uses for their own `media`, rather than
building a second one.

In terms of z-axis (see `media_generator_panel.css`), this sits just *below* `Shared.MyMediaPanel`
-- deliberately, since `EditMediaClicked` (below) opens that panel over this one to pick reference
media, and it should visibly win that overlap the same way every other "panel opens a picker over
itself" pair in this app does (`Shared.CreateNewPanel`'s own Edit Media button, `Pages.Post.PostId_`'s).
That reuse means this panel can't consume `MyMediaPanel`'s `SaveMediaClicked`/`CloseClicked`
directly the way a *page* would (via its own `SharedMsg`/`fromShared`, gated on a page-level
"am I mid-edit" flag) -- since this panel itself lives in `Shared.Model`, not a page, that
gating instead happens one level up, in `Shared.update`'s own `MyMediaPanelMsg` case, mirroring
exactly how it already lets `Shared.CreateNewPanel` do the same (see `MediaSaved`/`MediaEditClosed`
below, and `Shared.update`'s own doc on why).

Once generation succeeds, this panel closes itself and the resulting `GotGenerateResult` is left to
bubble up as an ordinary `Shared.Msg` -- `Main.notifyPageOfSharedMsg` already forwards every
`Shared.Msg` to whichever page is current regardless of who opened this panel, so the page that
opened it (`Components.Pages.PostPage`/`Pages.Event.PostId_`) just matches on this exact message in
its own `SharedMsg` handling, gated on its own "did I open this" flag (mirrors `mediaEditActive`), to
refetch and pick up the newly attached `Media` -- see those modules' own `GenerateMediaClicked`/
`SharedMsg` handling.

-}

import Components.AIProviders as AIProviders
import Components.Events as Events
import Components.MediaRenderer as MediaRenderer
import Components.Posts as Posts
import Grpc
import Html exposing (Html, button, div, option, select, span, text, textarea)
import Html.Attributes exposing (class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Proto.Rellm exposing (AIModel, Event, Occasion, Media, MediaReference, Post, defaultGenerateMediaRequest)
import Proto.Rellm.GenerateMediaRequest.Target as GenerateMediaRequestTarget
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers exposing (RellmServer)
import Shared.Conversions as Conversions
import Shared.MyMediaPanel as MyMediaPanel
import Shared.Time as SharedTime
import Task exposing (Task)
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)


type alias Model =
    { -- `""` means closed -- same convention `Shared.MyMediaPanel.targetHost` uses (unlike
      -- `MarkdownPanel.target`, `target` below can legitimately be `Nothing` while this panel is
      -- open -- see `Target`'s own doc -- so it can't double as the "is this open" flag itself).
      targetHost : String

    -- Which `frontendHost`-relative base path to build a target's card preview link with (see
    -- `targetCardView`) -- threaded through from whichever page's `Effect.fromShared` opened this,
    -- same reasoning `Shared.Breadcrumbs.basePath` is threaded for its own preview panel.
    , basePath : String
    , target : Maybe Target
    , selectedModel : Maybe AIModel
    , prompt : String
    , media : List MediaReference

    -- Whether `Shared.MyMediaPanel` is currently open *for this panel's own* `EditMediaClicked` --
    -- see the module doc on why this (not a page-level field) is what `Shared.update`'s own
    -- `MyMediaPanelMsg` case gates `MediaSaved`/`MediaEditClosed` on.
    , mediaEditActive : Bool

    -- Whether the target indicator's popover (`targetIndicatorView`) is currently showing.
    , targetPreviewOpen : Bool
    , status : SubmitStatus
    }


{-| What this panel is generating media *for* -- `Nothing` (see `Model.target`) just generates and
stores the image in the current user's own Media (as `MyMediaPanel` then shows it), without
attaching it to anything. `TargetEvent` carries both the `Event` and the specific `Occasion`
being viewed (`Pages.Event.PostId_`'s own `occasion`) purely so `targetCardView` can render the
same `Components.Events.eventCard` that page already shows elsewhere -- generation itself only ever
targets the Event's own Post (see `ai_providers.proto`'s own doc on `GenerateMediaRequest.target`),
never a particular occasion.
-}
type Target
    = TargetPost Post
    | TargetEvent Event Occasion


type SubmitStatus
    = Idle
    | Submitting
    | SubmitFailed String


type Msg
    = Open (Maybe Target) String String
    | PromptChanged String
    | ModelSelected String
    | EditMediaClicked
      -- Fired by `Shared.update`'s own `MyMediaPanelMsg` case once `MyMediaPanel.SaveMediaClicked`
      -- lands while this panel is the one that opened it (`mediaEditActive`) -- see the module doc.
    | MediaSaved (List MediaReference)
      -- Same, for `MyMediaPanel.CloseClicked` -- a cancel, `model.media` is left untouched.
    | MediaEditClosed
    | TargetPreviewToggled
    | CancelClicked
    | GenerateClicked
    | GotGenerateResult (Result Grpc.Error ( Maybe AccountsPanel.Msg, Media ))
    | NoOp


type alias Resolved =
    { server : RellmServer
    , account : RellmAccount
    }


init : Model
init =
    { targetHost = ""
    , basePath = ""
    , target = Nothing
    , selectedModel = Nothing
    , prompt = ""
    , media = []
    , mediaEditActive = False
    , targetPreviewOpen = False
    , status = Idle
    }


isOpen : Model -> Bool
isOpen model =
    model.targetHost /= ""


{-| Needs `AccountsPanel.Model` for the same reasons `Shared.MarkdownPanel.update` does --
resolving `targetHost` to the signed-in `Account` to submit as (`resolve`), and (here) also to look
up `Account.aiModels` for `ModelSelected`/`Open`'s own default pick. The extra
`Maybe MyMediaPanel.Msg` mirrors `Shared.CreateNewPanel.update`'s own `EditMediaClicked` request --
this panel can't dispatch `MyMediaPanel.Open` directly without importing `Shared`, which would
cycle, so `Shared.update` does it on this panel's behalf (see module doc).
-}
update : AccountsPanel.Model -> Msg -> Model -> ( Model, Cmd Msg, ( Maybe AccountsPanel.Msg, Maybe MyMediaPanel.Msg ) )
update accountsPanelModel msg model =
    case msg of
        Open target host basePath ->
            let
                media : List MediaReference
                media =
                    defaultMedia target
            in
            ( { init
                | targetHost = host
                , basePath = basePath
                , target = target
                , media = media
                , prompt = defaultPrompt target
                , selectedModel = List.head (availableModelsFor accountsPanelModel host media)
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        PromptChanged prompt ->
            ( { model | prompt = prompt }, Cmd.none, ( Nothing, Nothing ) )

        ModelSelected key ->
            let
                availableModels : List AIModel
                availableModels =
                    availableModelsFor accountsPanelModel model.targetHost model.media
            in
            ( { model | selectedModel = List.filter (\m -> aiModelKey m == key) availableModels |> List.head }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        EditMediaClicked ->
            ( { model | mediaEditActive = True }
            , Cmd.none
            , ( Nothing, Just (MyMediaPanel.Open (Just (MyMediaPanel.MultiSelect { initialSelection = model.media })) model.targetHost) )
            )

        MediaSaved media ->
            -- Picking/clearing reference media can flip which capability is required (see
            -- `availableModelsFor`'s own doc) -- `reselectIfInvalid` keeps `selectedModel` valid
            -- for the new `media`, so the model chooser (`view`) and this panel's own `selectedModel`
            -- never disagree about what's actually selected.
            ( { model
                | media = media
                , mediaEditActive = False
                , selectedModel = reselectIfInvalid (availableModelsFor accountsPanelModel model.targetHost media) model.selectedModel
              }
            , Cmd.none
            , ( Nothing, Nothing )
            )

        MediaEditClosed ->
            ( { model | mediaEditActive = False }, Cmd.none, ( Nothing, Nothing ) )

        TargetPreviewToggled ->
            ( { model | targetPreviewOpen = not model.targetPreviewOpen }, Cmd.none, ( Nothing, Nothing ) )

        CancelClicked ->
            ( init, Cmd.none, ( Nothing, Nothing ) )

        GenerateClicked ->
            case ( model.selectedModel, resolve accountsPanelModel model.targetHost ) of
                ( Just selectedModel, Ok resolved ) ->
                    ( { model | status = Submitting }
                    , generateTask accountsPanelModel resolved model.targetHost selectedModel model.prompt model.media model.target
                        |> Task.attempt GotGenerateResult
                    , ( Nothing, Nothing )
                    )

                ( Nothing, _ ) ->
                    ( { model | status = SubmitFailed "Choose a model." }, Cmd.none, ( Nothing, Nothing ) )

                ( _, Err err ) ->
                    ( { model | status = SubmitFailed err }, Cmd.none, ( Nothing, Nothing ) )

        GotGenerateResult (Ok ( maybeAccountsPanelMsg, _ )) ->
            ( init, Cmd.none, ( maybeAccountsPanelMsg, Nothing ) )

        GotGenerateResult (Err err) ->
            ( { model | status = SubmitFailed (AccountsPanel.grpcErrorToString err) }, Cmd.none, ( Nothing, Nothing ) )

        NoOp ->
            ( model, Cmd.none, ( Nothing, Nothing ) )


{-| The target's own current media, prepopulating `model.media` (still freely editable via
`EditMediaClicked` afterward) -- for an Event, the union of its own Post's media and the specific
`Occasion`'s own Post's media, Event-first, mirroring
`backend/src/rpcs/events/sync_occasion.rs`'s `combine_media` (an occasion-level Post rarely
carries its own media override, so without the Event's own this would often come up empty).
-}
defaultMedia : Maybe Target -> List MediaReference
defaultMedia target =
    case target of
        Just (TargetPost post) ->
            post.media

        Just (TargetEvent event occasion) ->
            let
                eventMedia : List MediaReference
                eventMedia =
                    event.post |> Maybe.map .media |> Maybe.withDefault []

                eventMediaIds : List String
                eventMediaIds =
                    List.map .id eventMedia

                occasionMedia : List MediaReference
                occasionMedia =
                    occasion.post
                        |> Maybe.map .media
                        |> Maybe.withDefault []
                        |> List.filter (\m -> not (List.member m.id eventMediaIds))
            in
            eventMedia ++ occasionMedia

        Nothing ->
            []


defaultPrompt : Maybe Target -> String
defaultPrompt target =
    case target of
        Just (TargetPost _) ->
            "Please generate a square headline image for the following post. I've attached other media that may be useful for reference."

        Just (TargetEvent _ _) ->
            "Please generate a square headline poster for the following event. I've attached other media that may be useful for reference."

        Nothing ->
            ""


{-| The `AIModel`s actually selectable right now -- editing-capable
(`AIProviders.hasImageEditingCapability`) once `media` is non-empty (`GenerateMedia` requires
`AI_MODEL_CAPABILITY_IMAGE_EDITING` whenever there are reference images to edit with), otherwise
generation-capable (`hasImageGenerationCapability`) -- which also includes every editing-capable
model, since this session's catalog (`ai_model_catalog.rs`) always pairs the two, but is checked
explicitly rather than assumed. Reused by `Open`/`ModelSelected`/`MediaSaved`/`view` so the model
chooser, `selectedModel`, and what `GenerateClicked` can actually submit all stay in lockstep as
`media` changes -- see `reselectIfInvalid`, the other half of that.
-}
availableModelsFor : AccountsPanel.Model -> String -> List MediaReference -> List AIModel
availableModelsFor accountsPanelModel host media =
    let
        account : Maybe RellmAccount
        account =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host

        capable : AIModel -> Bool
        capable =
            if List.isEmpty media then
                AIProviders.hasImageGenerationCapability

            else
                AIProviders.hasImageEditingCapability
    in
    account |> Maybe.map .aiModels |> Maybe.withDefault [] |> List.filter capable


{-| Keeps `current` if it's still in `validModels` (compared by `aiModelKey`, not `==`,
same reasoning `modelChooserView`'s own `selected` check has), otherwise falls back to
`List.head validModels` (`Nothing` if that's empty too -- see `view`'s own "no valid model" message
for that case). Used by `MediaSaved` -- picking/clearing reference media can flip which capability
`availableModelsFor` requires, and a `selectedModel` that was valid before that flip might not be
anymore.
-}
reselectIfInvalid : List AIModel -> Maybe AIModel -> Maybe AIModel
reselectIfInvalid validModels current =
    case current of
        Just selected ->
            if List.any (\m -> aiModelKey m == aiModelKey selected) validModels then
                current

            else
                List.head validModels

        Nothing ->
            List.head validModels


{-| A composite key identifying one `AIModel` in the model chooser `<select>` -- neither
`modelName` nor `provider.id` alone is unique (the same model name can appear once per grant on
different providers), but the pair always is. Mirrors `Components.Pages.UserProfilePage.aiProviderGrantKey`'s
own reasoning for the same underlying data.
-}
aiModelKey : AIModel -> String
aiModelKey model =
    (model.provider |> Maybe.map .id |> Maybe.withDefault "") ++ "|" ++ model.modelName


{-| "modelName (N tokens left) — via username", trimmed to whichever parts actually apply -- the
tokens suffix only for a granted (not owned) model, the "via" suffix only when the provider's owner
isn't the viewer themselves. See `AIModel`'s own doc (`ai_providers.proto`) for why a
`grant`/no-`grant` `AIModel` means "granted"/"owned outright".
-}
aiModelLabel : Maybe String -> AIModel -> String
aiModelLabel viewerUsername available =
    let
        ownerUsername : Maybe String
        ownerUsername =
            case available.provider of
                Just provider ->
                    provider.owner |> Maybe.andThen .username

                Nothing ->
                    Nothing

        ownerSuffix : String
        ownerSuffix =
            case ownerUsername of
                Just owner ->
                    if Just owner /= viewerUsername then
                        " — via " ++ owner

                    else
                        ""

                Nothing ->
                    ""

        tokensSuffix : String
        tokensSuffix =
            case available.grant of
                Just grant ->
                    if Conversions.int64ToInt grant.overage > 0 then
                        " (" ++ String.fromInt (Conversions.int64ToInt grant.overage) ++ " over budget)"

                    else
                        " (" ++ String.fromInt (Conversions.int64ToInt grant.tokensRemaining) ++ " tokens left)"

                Nothing ->
                    ""
    in
    available.modelName ++ tokensSuffix ++ ownerSuffix



-- VIEW


view : SharedTime.Model -> AccountsPanel.Model -> Model -> Html Msg
view time accountsPanelModel model =
    let
        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost

        availableModels : List AIModel
        availableModels =
            availableModelsFor accountsPanelModel model.targetHost model.media

        canGenerate : Bool
        canGenerate =
            model.selectedModel /= Nothing && model.status /= Submitting
    in
    div [ classes [ "media-generator-panel", "nav-panel", openClosedClass (isOpen model), hostnameToCSSClass model.targetHost ] ]
        [ div [ class "media-generator-panel-header" ]
            [ span [ class "media-generator-panel-title" ] [ text "Generate Media" ]
            , button [ class "media-generator-panel-close", onClick CancelClicked ] [ text "✕" ]
            ]
        , div [ class "media-generator-panel-body" ]
            [ targetIndicatorView time accountsPanelModel model
            , modelChooserView (maybeAccount |> Maybe.map .username) availableModels model
            , promptView model
            , mediaSectionView accountsPanelModel model
            ]
        , case model.status of
            SubmitFailed err ->
                div [ class "media-generator-panel-error" ] [ text err ]

            _ ->
                text ""
        , div [ class "media-generator-panel-actions" ]
            [ button
                [ class "media-generator-panel-cancel"
                , onClick CancelClicked
                , disabled (model.status == Submitting)
                ]
                [ text "Cancel" ]
            , button
                [ classes [ "media-generator-panel-generate", model.targetHost, "background-color-primary" ]
                , onClick GenerateClicked
                , disabled (not canGenerate)
                ]
                [ text
                    (if model.status == Submitting then
                        "Generating…"

                     else
                        "Generate"
                    )
                ]
            ]
        ]


{-| The "for Post: <title>"/"for Event: <title>" indicator -- tapping it toggles a popover (built on
`ui/popover.css`'s generic `.popover-anchor`/`.popover-toggle`/`.popover`/`.popover-backdrop`, the
same way `Components.Pages.EventsPage.exportButtonView` does for its own Export popover) showing the
same `Posts.postCard`/`Events.eventCard` that target's own page renders it with -- read-only here
(every optional callback is a no-op/`False`), same convention `Shared.StarredPanel` uses to show
those same cards outside their native page. Renders nothing at all for `Target.Nothing` (bare
generate-and-store, with nothing to show a card for).
-}
targetIndicatorView : SharedTime.Model -> AccountsPanel.Model -> Model -> Html Msg
targetIndicatorView time accountsPanelModel model =
    case model.target of
        Nothing ->
            text ""

        Just target ->
            let
                label : String
                label =
                    case target of
                        TargetPost post ->
                            "for Post: " ++ Posts.postTitleText post

                        TargetEvent event _ ->
                            "for Event: " ++ (event.post |> Maybe.map Posts.postTitleText |> Maybe.withDefault "Untitled Event")
            in
            div [ classes [ "media-generator-panel-target", "popover-anchor" ] ]
                [ button
                    [ classes [ "media-generator-panel-target-toggle", "popover-toggle", openClosedClass model.targetPreviewOpen ]
                    , type_ "button"
                    , onClick TargetPreviewToggled
                    ]
                    [ text label ]
                , div [ classes [ "popover-backdrop", openClosedClass model.targetPreviewOpen ], onClick TargetPreviewToggled ] []
                , div [ classes [ "media-generator-panel-target-popover", "popover", openClosedClass model.targetPreviewOpen ] ]
                    [ targetCardView time accountsPanelModel model.basePath model.targetHost target ]
                ]


targetCardView : SharedTime.Model -> AccountsPanel.Model -> String -> String -> Target -> Html Msg
targetCardView time accountsPanelModel basePath host target =
    let
        maybeServer : Maybe RellmServer
        maybeServer =
            RellmServers.rellmServerForHost accountsPanelModel.servers host

        maybeAccount : Maybe RellmAccount
        maybeAccount =
            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts host
    in
    case target of
        TargetPost post ->
            Posts.postCard time basePath accountsPanelModel.mainFrontendHost host maybeServer maybeAccount (\_ -> NoOp) MediaRenderer.init (\_ -> NoOp) True False False Nothing False Nothing (\_ -> False) (\_ -> Nothing) (\_ -> NoOp) (\_ _ -> NoOp) post

        TargetEvent event occasion ->
            Events.eventCard time basePath accountsPanelModel.mainFrontendHost host maybeServer maybeAccount (\_ -> NoOp) MediaRenderer.init (\_ -> NoOp) MediaRenderer.ExtraSmall False Nothing False False False Nothing (\_ -> False) (\_ -> Nothing) (\_ -> NoOp) (\_ _ -> NoOp) event occasion


modelChooserView : Maybe String -> List AIModel -> Model -> Html Msg
modelChooserView viewerUsername availableModels model =
    div [ class "media-generator-panel-field" ]
        [ span [ class "media-generator-panel-label" ] [ text "Model" ]
        , if List.isEmpty availableModels then
            div [ class "media-generator-panel-no-models" ]
                [ text
                    (if List.isEmpty model.media then
                        "No AI models available."

                     else
                        "No image-editing AI models available -- remove reference media to generate from a prompt alone instead."
                    )
                ]

          else
            select [ class "media-generator-panel-model-select", onInput ModelSelected ]
                (availableModels
                    |> List.map
                        (\available ->
                            option
                                [ value (aiModelKey available)
                                , selected (Just (aiModelKey available) == Maybe.map aiModelKey model.selectedModel)
                                ]
                                [ text (aiModelLabel viewerUsername available) ]
                        )
                )
        ]


promptView : Model -> Html Msg
promptView model =
    div [ class "media-generator-panel-field" ]
        [ span [ class "media-generator-panel-label" ] [ text "Prompt" ]
        , textarea
            [ class "media-generator-panel-prompt"
            , value model.prompt
            , onInput PromptChanged
            , placeholder "Describe what to generate…"
            ]
            []
        ]


mediaSectionView : AccountsPanel.Model -> Model -> Html Msg
mediaSectionView accountsPanelModel model =
    div [ class "media-generator-panel-field" ]
        [ span [ class "media-generator-panel-label" ] [ text "Reference Media" ]
        , case RellmServers.rellmServerForHost accountsPanelModel.servers model.targetHost of
            Just server ->
                if List.isEmpty model.media then
                    div [ class "media-generator-panel-media-empty" ] [ text "No media selected." ]

                else
                    let
                        maybeAccount : Maybe RellmAccount
                        maybeAccount =
                            RellmAccounts.enabledRellmAccountForServer accountsPanelModel.accounts model.targetHost
                    in
                    div [ class "media-generator-panel-media-strip" ]
                        (List.map
                            (\mediaRef -> MediaRenderer.view MediaRenderer.ExtraSmall MediaRenderer.ToWidthAndHeight server maybeAccount True MediaRenderer.init (\_ -> NoOp) (\_ -> NoOp) mediaRef)
                            model.media
                        )

            Nothing ->
                text ""
        , button [ type_ "button", class "media-generator-panel-edit-media", onClick EditMediaClicked ] [ text "Edit Media…" ]
        ]


{-| Verifies `host` is actually usable right now -- resolves to a known, currently-enabled `Server`
with a signed-in `Account` -- mirrors `Shared.MarkdownPanel.resolve`/`Shared.MyMediaPanel.resolve`
exactly (no per-`Target` permission branching needed here, unlike `MarkdownPanel`'s own `resolve`:
this panel's targets have no client-checkable permission beyond "signed in on that server", the
actual author-or-Admin/owner-or-grantee checks all happen server-side, in `GenerateMedia` itself).
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


generateTask :
    AccountsPanel.Model
    -> Resolved
    -> String
    -> AIModel
    -> String
    -> List MediaReference
    -> Maybe Target
    -> Task Grpc.Error ( Maybe AccountsPanel.Msg, Media )
generateTask accountsPanelModel resolved host selectedModel prompt media target =
    let
        targetField : Maybe (GenerateMediaRequestTarget.Target String String)
        targetField =
            case target of
                Just (TargetPost post) ->
                    Just (GenerateMediaRequestTarget.PostId post.id)

                Just (TargetEvent _ occasion) ->
                    Just (GenerateMediaRequestTarget.OccasionId (occasion.post |> Maybe.map .id |> Maybe.withDefault ""))

                Nothing ->
                    Nothing
    in
    AIProviders.generateMedia
        accountsPanelModel
        ( Just resolved.account.userId, host )
        { defaultGenerateMediaRequest
            | model = Just selectedModel
            , userPrompt = prompt
            , mediaIds = List.map .id media
            , target = targetField
        }
