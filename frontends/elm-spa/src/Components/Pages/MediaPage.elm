module Components.Pages.MediaPage exposing (Mode(..), Model, Msg, Tab(..), fromShared, init, subscriptions, tabFromQuery, tabQueryValue, update, view)

{-| `/media`, `/video`/`/videos` and `/audio` -- the server-wide media pages built on
`GetMedia` (see `Components.MediaFeed`). One component backs all three routes (and their
`UsernameOrCustomTab_` embeddings, see `Pages.UsernameOrCustomTab_`), told which by `Mode`:

  - `VideoOnly` -- `/video`, `/videos`: a YouTube-alike grid of videos.
  - `AudioOnly` -- `/audio`: an iTunes/Spotify-alike track list.
  - `ImagesOnly` -- `/images`: a photo-gallery grid of images.
  - `Tabbed` -- `/media`: top tabs of the above three, plus a "My Media" tab (signed-in users only)
    that renders `Shared.MyMediaPanel`'s own UI inline via `MyMediaPanel.viewEmbedded` -- the same
    "page-level reuse of a panel" idea as `Shared.MessagingPanel`/`Pages.Messages`, except here the
    page owns a _separate_ `MyMediaPanel.Model` instance (the global panel's `DeleteConfirmation`
    plumbing is wired to the shared instance only, so deleting from this one asks via the small
    inline bar in `view` instead -- see `pendingDelete`).

The selected `Tabbed` tab lives in the URL (`?tab=audio`/`?tab=my`, none meaning Video) via
`Browser.Navigation.replaceUrl`, so reloads/links land on the same tab.

The Video/Audio feeds are multi-server (every server enabled in the Accounts Panel -- see
`Components.MediaFeed`). The My Media tab shows an account selector (federated-profile-style chips,
see `accountChipsView`) above the panel, since `Shared.MyMediaPanel` is scoped to one account's
server at a time.

-}

import Browser.Navigation
import Components.MediaFeed as MediaFeed
import Dict exposing (Dict)
import Effect exposing (Effect)
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (class, classList, title)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (Media)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AccountsPanel.RellmAccounts as RellmAccounts exposing (RellmAccount)
import Shared.AccountsPanel.RellmServers as RellmServers
import Shared.Breadcrumbs as Breadcrumbs
import Shared.MyMediaPanel as MyMediaPanel
import UI
import UI.Classes exposing (classes, hostnameToCSSClass)


type Mode
    = Tabbed
    | VideoOnly
    | AudioOnly
    | ImagesOnly


type Tab
    = VideoTab
    | AudioTab
    | ImagesTab
    | MyMediaTab


type alias Model =
    { mode : Mode
    , tab : Tab
    , navKey : Browser.Navigation.Key
    , path : String

    -- `?search_text=` -- seeds the search box of whichever feed tab is entered first.
    , initialSearch : String

    -- Each is created lazily by `enterTab`, the first time its tab is shown, so e.g. landing on
    -- the Video tab never fetches audio.
    , video : Maybe MediaFeed.Model
    , audio : Maybe MediaFeed.Model
    , images : Maybe MediaFeed.Model
    , myMedia : MyMediaPanel.Model

    -- The server (`frontendHost`) of the account whose media the My Media tab shows -- `Nothing`
    -- until one is chosen (`enterTab` defaults to the first signed-in account).
    , myMediaHost : Maybe String

    -- A media item the My Media tab's Delete button asked to delete, awaiting this page's own
    -- inline confirmation (see module doc).
    , pendingDelete : Maybe Media
    }


type Msg
    = VideoMsg MediaFeed.Msg
    | AudioMsg MediaFeed.Msg
    | ImagesMsg MediaFeed.Msg
    | MyMediaMsg MyMediaPanel.Msg
    | TabClicked Tab
    | AccountSelected String
    | DeleteConfirmed
    | DeleteCancelled
    | SharedMsgReceived Shared.Msg


{-| `?tab=` -> `Tab`; anything else (including none) is Video.
-}
tabFromQuery : Dict String String -> Tab
tabFromQuery query =
    case Dict.get "tab" query of
        Just "audio" ->
            AudioTab

        Just "images" ->
            ImagesTab

        Just "my" ->
            MyMediaTab

        _ ->
            VideoTab


{-| The `?tab=` value for `tab` -- `Nothing` for Video, the default.
-}
tabQueryValue : Tab -> Maybe String
tabQueryValue tab =
    case tab of
        VideoTab ->
            Nothing

        AudioTab ->
            Just "audio"

        ImagesTab ->
            Just "images"

        MyMediaTab ->
            Just "my"


init : Shared.Model -> Mode -> Browser.Navigation.Key -> String -> Dict String String -> ( Model, Effect Msg )
init shared mode navKey path query =
    let
        tab : Tab
        tab =
            case mode of
                Tabbed ->
                    tabFromQuery query

                VideoOnly ->
                    VideoTab

                AudioOnly ->
                    AudioTab

                ImagesOnly ->
                    ImagesTab

        ( model, tabEffect ) =
            enterTab shared
                { mode = mode
                , tab = tab
                , navKey = navKey
                , path = path
                , initialSearch = Dict.get "search_text" query |> Maybe.withDefault ""
                , video = Nothing
                , audio = Nothing
                , images = Nothing
                , myMedia = MyMediaPanel.init
                , myMediaHost = Nothing
                , pendingDelete = Nothing
                }
    in
    ( model
    , Effect.batch
        [ tabEffect
        , Effect.fromShared (Shared.BreadcrumbsMsg (Breadcrumbs.SetRoot (Breadcrumbs.FromServerHost shared.accounts.browsingHost) shared.accounts.browsingHost []))
        ]
    )


{-| Makes sure the (already-selected) `model.tab`'s own state exists and has started loading.
-}
enterTab : Shared.Model -> Model -> ( Model, Effect Msg )
enterTab shared model =
    case model.tab of
        VideoTab ->
            case model.video of
                Just _ ->
                    ( model, Effect.none )

                Nothing ->
                    MediaFeed.init shared MediaFeed.Videos model.initialSearch
                        |> Tuple.mapFirst (\feed -> { model | video = Just feed })
                        |> Tuple.mapSecond (Effect.map VideoMsg)

        AudioTab ->
            case model.audio of
                Just _ ->
                    ( model, Effect.none )

                Nothing ->
                    MediaFeed.init shared MediaFeed.Audio model.initialSearch
                        |> Tuple.mapFirst (\feed -> { model | audio = Just feed })
                        |> Tuple.mapSecond (Effect.map AudioMsg)

        ImagesTab ->
            case model.images of
                Just _ ->
                    ( model, Effect.none )

                Nothing ->
                    MediaFeed.init shared MediaFeed.Images model.initialSearch
                        |> Tuple.mapFirst (\feed -> { model | images = Just feed })
                        |> Tuple.mapSecond (Effect.map ImagesMsg)

        MyMediaTab ->
            let
                accounts : List RellmAccount
                accounts =
                    mediaAccounts shared

                chosenHost : Maybe String
                chosenHost =
                    case model.myMediaHost of
                        Just host ->
                            if List.any (\a -> a.server == host) accounts then
                                Just host

                            else
                                List.head accounts |> Maybe.map .server

                        Nothing ->
                            List.head accounts |> Maybe.map .server
            in
            case chosenHost of
                Just host ->
                    if MyMediaPanel.isOpen model.myMedia && model.myMediaHost == Just host then
                        ( model, Effect.none )

                    else if RellmServers.knownConnectedRellmServer shared.accounts.servers host == Nothing then
                        -- A cold load races `Shared.AccountsPanel.init`'s own reconnect (every
                        -- persisted server starts disconnected -- see
                        -- `RellmServers.knownConnectedRellmServer`), and opening the panel now would
                        -- fail its fetch with "Couldn't reach the server". Remember the choice and
                        -- retry on the next forwarded `Shared.Msg` (`SharedMsgReceived`), which a
                        -- server connecting triggers.
                        ( { model | myMediaHost = Just host }, Effect.none )

                    else
                        updateMyMedia shared (MyMediaPanel.Open Nothing host) { model | myMediaHost = Just host }

                Nothing ->
                    ( model, Effect.none )


{-| The accounts the My Media tab can show: one per enabled server (the account `MyMediaPanel`
itself resolves for that server -- `RellmAccounts.enabledRellmAccountForServer` -- so what's listed
is exactly what selecting it opens), in Accounts Panel order.
-}
mediaAccounts : Shared.Model -> List RellmAccount
mediaAccounts shared =
    AccountsPanel.enabledAccounts shared.accounts
        |> List.filter
            (\account ->
                RellmAccounts.enabledRellmAccountForServer shared.accounts.accounts account.server
                    |> Maybe.map (\effective -> effective.userId == account.userId)
                    |> Maybe.withDefault False
            )


{-| Runs `msg` through `MyMediaPanel.update` and translates its three forwarded outputs: an
`AccountsPanel.Msg` (a token refresh) and a `MediaViewerPanel.Msg` (a tapped tile) go to `Shared`;
a delete request becomes `pendingDelete`.
-}
updateMyMedia : Shared.Model -> MyMediaPanel.Msg -> Model -> ( Model, Effect Msg )
updateMyMedia shared msg model =
    let
        ( newPanel, cmd, ( maybeAccountsPanelMsg, maybeDeleteRequest, maybeViewerMsg ) ) =
            MyMediaPanel.update shared.accounts msg model.myMedia
    in
    ( { model
        | myMedia = newPanel
        , pendingDelete =
            case maybeDeleteRequest of
                Just media ->
                    Just media

                Nothing ->
                    model.pendingDelete
      }
    , Effect.batch
        [ Effect.fromCmd (Cmd.map MyMediaMsg cmd)
        , maybeAccountsPanelMsg |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared) |> Maybe.withDefault Effect.none
        , maybeViewerMsg |> Maybe.map (Shared.MediaViewerPanelMsg >> Effect.fromShared) |> Maybe.withDefault Effect.none
        ]
    )


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg model =
    case msg of
        VideoMsg feedMsg ->
            case model.video of
                Just feed ->
                    MediaFeed.update shared feedMsg feed
                        |> Tuple.mapFirst (\f -> { model | video = Just f })
                        |> Tuple.mapSecond (Effect.map VideoMsg)

                Nothing ->
                    ( model, Effect.none )

        AudioMsg feedMsg ->
            case model.audio of
                Just feed ->
                    MediaFeed.update shared feedMsg feed
                        |> Tuple.mapFirst (\f -> { model | audio = Just f })
                        |> Tuple.mapSecond (Effect.map AudioMsg)

                Nothing ->
                    ( model, Effect.none )

        ImagesMsg feedMsg ->
            case model.images of
                Just feed ->
                    MediaFeed.update shared feedMsg feed
                        |> Tuple.mapFirst (\f -> { model | images = Just f })
                        |> Tuple.mapSecond (Effect.map ImagesMsg)

                Nothing ->
                    ( model, Effect.none )

        MyMediaMsg panelMsg ->
            -- The embedded panel's own Close button isn't rendered (`viewEmbedded`), so a
            -- `CloseClicked` can only come from a `MultiSelect`/`SingleSelect` flow this instance
            -- never enters -- nothing to special-case.
            updateMyMedia shared panelMsg model

        TabClicked tab ->
            let
                ( enteredModel, enterEffect ) =
                    enterTab shared { model | tab = tab }
            in
            ( enteredModel
            , Effect.batch
                [ enterEffect
                , Browser.Navigation.replaceUrl model.navKey
                    (model.path
                        ++ (case tabQueryValue tab of
                                Just value ->
                                    "?tab=" ++ value

                                Nothing ->
                                    ""
                           )
                    )
                    |> Effect.fromCmd
                ]
            )

        AccountSelected host ->
            -- Reopens (`Open` resets the panel's state, including its search text) on the chosen
            -- account's server; any half-finished delete confirmation belonged to the old one.
            updateMyMedia shared (MyMediaPanel.Open Nothing host) { model | myMediaHost = Just host, pendingDelete = Nothing }

        DeleteConfirmed ->
            case model.pendingDelete of
                Just media ->
                    updateMyMedia shared (MyMediaPanel.DeleteConfirmed media) { model | pendingDelete = Nothing }

                Nothing ->
                    ( model, Effect.none )

        DeleteCancelled ->
            ( { model | pendingDelete = Nothing }, Effect.none )

        -- Re-emitted exactly once (see `Pages.Market`'s own doc on why a `fromShared`-forwarded
        -- `Shared.Msg` must be re-emitted, and why only once): a server connecting or an account
        -- signing in is also the cue to start whichever fetch/panel-open couldn't yet.
        SharedMsgReceived subMsg ->
            let
                ( videoModel, videoEffect ) =
                    case model.video of
                        Just feed ->
                            MediaFeed.retryFetch shared feed |> Tuple.mapFirst Just |> Tuple.mapSecond (Effect.map VideoMsg)

                        Nothing ->
                            ( Nothing, Effect.none )

                ( audioModel, audioEffect ) =
                    case model.audio of
                        Just feed ->
                            MediaFeed.retryFetch shared feed |> Tuple.mapFirst Just |> Tuple.mapSecond (Effect.map AudioMsg)

                        Nothing ->
                            ( Nothing, Effect.none )

                ( imagesModel, imagesEffect ) =
                    case model.images of
                        Just feed ->
                            MediaFeed.retryFetch shared feed |> Tuple.mapFirst Just |> Tuple.mapSecond (Effect.map ImagesMsg)

                        Nothing ->
                            ( Nothing, Effect.none )

                ( enteredModel, enterEffect ) =
                    enterTab shared { model | video = videoModel, audio = audioModel, images = imagesModel }
            in
            ( enteredModel, Effect.batch [ Effect.fromShared subMsg, videoEffect, audioEffect, imagesEffect, enterEffect ] )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map MyMediaMsg (MyMediaPanel.subscriptions model.myMedia)


fromShared : Shared.Msg -> Msg
fromShared =
    SharedMsgReceived



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    let
        tabButton : Tab -> String -> Html Msg
        tabButton tab label =
            button
                [ class "media-page-tab"
                , classList [ ( "is-current", model.tab == tab ) ]
                , onClick (TabClicked tab)
                ]
                [ text label ]
    in
    div [ class "media-page" ]
        [ case model.mode of
            Tabbed ->
                div [ class "media-page-tabs" ]
                    ([ tabButton VideoTab "Video", tabButton AudioTab "Audio", tabButton ImagesTab "Images" ]
                        ++ (if not (List.isEmpty (mediaAccounts shared)) then
                                [ tabButton MyMediaTab "My Media" ]

                            else
                                []
                           )
                    )

            _ ->
                text ""
        , case model.tab of
            VideoTab ->
                model.video
                    |> Maybe.map (\feed -> Html.map VideoMsg (MediaFeed.view shared feed))
                    |> Maybe.withDefault (text "")

            AudioTab ->
                model.audio
                    |> Maybe.map (\feed -> Html.map AudioMsg (MediaFeed.view shared feed))
                    |> Maybe.withDefault (text "")

            ImagesTab ->
                model.images
                    |> Maybe.map (\feed -> Html.map ImagesMsg (MediaFeed.view shared feed))
                    |> Maybe.withDefault (text "")

            MyMediaTab ->
                div [ class "media-page-my-media" ]
                    [ accountChipsView shared model
                    , pendingDeleteView model.pendingDelete
                    , Html.map MyMediaMsg (MyMediaPanel.viewEmbedded shared.windowSize.width shared.accounts model.myMedia)
                    ]
        ]


{-| The account selector above the My Media panel -- the same chips as `UserProfilePage`'s Federated
Profiles list (`.profile-federated-link`: avatar, `username@host`, real name, in that server's own
colors), as buttons, with the selected account emphasized. Hidden unless there's a choice to make.
-}
accountChipsView : Shared.Model -> Model -> Html Msg
accountChipsView shared model =
    case mediaAccounts shared of
        [] ->
            text ""

        [ _ ] ->
            text ""

        accounts ->
            div [ class "profile-federated media-page-accounts" ] (List.map (accountChip shared model) accounts)


accountChip : Shared.Model -> Model -> RellmAccount -> Html Msg
accountChip shared model account =
    button
        [ classes
            ([ "profile-federated-link", "media-page-account-chip", hostnameToCSSClass account.server, "background-color-primary" ]
                ++ (if model.myMediaHost == Just account.server then
                        [ "is-selected" ]

                    else
                        []
                   )
            )
        , onClick (AccountSelected account.server)
        , title (account.username ++ "@" ++ account.server)
        ]
        [ UI.imageOrInitial [ "profile-federated-avatar" ] account.username (RellmAccounts.rellmAccountAvatarUrl shared.accounts.servers account)
        , div [ class "profile-federated-names" ]
            [ span [ class "profile-federated-username" ] [ text (account.username ++ "@" ++ account.server) ]
            , if String.isEmpty (String.trim account.realName) then
                text ""

              else
                span [ class "profile-federated-realname" ] [ text account.realName ]
            ]
        ]


pendingDeleteView : Maybe Media -> Html Msg
pendingDeleteView pending =
    case pending of
        Just media ->
            div [ class "media-page-delete-confirm" ]
                [ span [] [ text ("Delete \"" ++ (media.name |> Maybe.withDefault "this media") ++ "\" permanently?") ]
                , button [ class "media-page-delete-confirm-yes", onClick DeleteConfirmed ] [ text "Delete" ]
                , button [ onClick DeleteCancelled ] [ text "Cancel" ]
                ]

        Nothing ->
            text ""
