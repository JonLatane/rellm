module Components.FederatedMyMedia exposing (Kind(..), Model, Msg, init, itemsOf, update, view)

{-| "My Media" for a connected Mastodon or Bluesky account -- `Shared.MyMediaPanel`'s counterpart, shown in
the Media page's My Media tab (`Components.Pages.MediaPage`) when such an account is the one picked.

Neither network has a media library: an upload only exists attached to a post. So "your media" here is your own
posts that carry images, video or audio (`Actions.fetchOwnMediaPosts`), each attachment a tile that opens in the
same viewer (images, video) or bottom player (audio) the rest of Rellm uses, with a "View post" link to the post's
page in the Rellm UI; and "uploading" makes a post for you carrying the file (`Actions.uploadAsPost`), which the
form says in a warning above it. Deleting a tile deletes its post (confirmed first), since that is the only way to
remove an attachment.

Bluesky takes images only here (its video goes through a separate upload service this doesn't use), and has no
audio at all.

-}

import Components.Posts as Posts
import Dict
import Effect exposing (Effect)
import File exposing (File)
import File.Select
import Html exposing (Html, a, button, div, img, input, option, select, span, text, textarea)
import Html.Attributes exposing (attribute, class, href, placeholder, selected, src, value)
import Html.Events exposing (onClick, onInput)
import Http
import Proto.Rellm exposing (MediaReference, Post)
import Shared
import Shared.AccountsPanel as AccountsPanel
import Shared.AudioPlayerPanel as AudioPlayerPanel
import Shared.Federation.Actions as Actions exposing (ServerAccount(..))
import Shared.Federation.Common exposing (sensitiveMediaHiddenId)
import Shared.Federation.Mastodon as Mastodon exposing (MastodonVisibility(..))
import Shared.Federation.Media as FedMedia
import Shared.Federation.VideoPoster as VideoPoster
import Shared.MediaViewerPanel as MediaViewerPanel
import Task
import UI.Classes exposing (classes)
import UI.Glyph as Glyph


type Kind
    = ImageKind
    | VideoKind
    | AudioKind


{-| One attachment of one of the account's posts. `id` is unique in the list (`post.id ++ "/" ++ media.id`).
-}
type alias Item =
    { id : String
    , kind : Kind
    , media : MediaReference
    , post : Post
    }


type Status
    = Loading
    | Loaded
    | Failed String


type Upload
    = Idle
    | Uploading
    | UploadFailed String


type alias Model =
    { account : ServerAccount
    , items : List Item
    , status : Status

    -- The cursor for the next page of posts, `Nothing` once they've run out.
    , next : Maybe String
    , loadingMore : Bool

    -- Stamps the newest fetch, so an older response is dropped.
    , requestId : Int

    -- The post the next upload will create: its text, the media's alt text, and (Mastodon) who can see it.
    , caption : String
    , description : String
    , visibility : MastodonVisibility
    , upload : Upload

    -- The post id a Delete button is asking to confirm, and whether that delete is under way.
    , confirmingDelete : Maybe String
    , deleting : Bool
    , actionError : Maybe String
    }


type Msg
    = -- Every async reply carries the `Actions.accountId` of the account it was made as: a reply that lands after
      -- another account was picked is dropped (see `update`), so one account's media never shows under another.
      GotPage String Int Bool (Result Http.Error ( Maybe AccountsPanel.Msg, List Post, Maybe String ))
    | LoadMoreClicked
    | CaptionChanged String
    | DescriptionChanged String
    | VisibilityChanged String
    | UploadClicked
    | GotFile File
    | GotUploadResult String (Result Http.Error (Maybe AccountsPanel.Msg))
    | ItemClicked String
    | DeleteClicked String
    | DeleteCancelled
    | DeleteConfirmed
    | GotDeleteResult String String (Result Http.Error (Maybe AccountsPanel.Msg))


init : ServerAccount -> ( Model, Effect Msg )
init account =
    ( { account = account
      , items = []
      , status = Loading
      , next = Nothing
      , loadingMore = False
      , requestId = 1
      , caption = ""
      , description = ""

      -- Not public by default: an upload shouldn't broadcast itself by surprise.
      , visibility = MastodonUnlisted
      , upload = Idle
      , confirmingDelete = Nothing
      , deleting = False
      , actionError = Nothing
      }
    , fetchPage account 1 False Nothing
    )


fetchPage : ServerAccount -> Int -> Bool -> Maybe String -> Effect Msg
fetchPage account requestId append cursor =
    Actions.fetchOwnMediaPosts account cursor
        |> Task.attempt (GotPage (Actions.accountId account) requestId append)
        |> Effect.fromCmd


{-| Every image, video and audio attachment in `posts`, in order. Pure so it's unit-testable.
-}
itemsOf : List Post -> List Item
itemsOf posts =
    posts
        |> List.concatMap
            (\post ->
                post.media
                    |> List.filter (\media -> media.id /= sensitiveMediaHiddenId)
                    |> List.filterMap
                        (\media ->
                            kindOf media |> Maybe.map (\kind -> { id = post.id ++ "/" ++ media.id, kind = kind, media = media, post = post })
                        )
            )


kindOf : MediaReference -> Maybe Kind
kindOf media =
    case media.sizes |> List.head |> Maybe.map .contentType of
        Just contentType ->
            if String.startsWith "image/" contentType then
                Just ImageKind

            else if String.startsWith "video/" contentType then
                Just VideoKind

            else if String.startsWith "audio/" contentType then
                Just AudioKind

            else
                Nothing

        Nothing ->
            Nothing


{-| The file types the picker offers: everything Mastodon takes; images only for Bluesky.
-}
pickerTypes : ServerAccount -> List String
pickerTypes account =
    case account of
        MastodonServerAccount _ ->
            [ "image/*", "video/*", "audio/*" ]

        BlueskyServerAccount _ ->
            [ "image/*" ]


forwardRotated : Maybe AccountsPanel.Msg -> Effect Msg
forwardRotated maybeAccountsPanelMsg =
    maybeAccountsPanelMsg
        |> Maybe.map (Shared.AccountsPanelMsg >> Effect.fromShared)
        |> Maybe.withDefault Effect.none


{-| `model.account` as the Accounts Panel has it now: a request that refreshed an expired token (Bluesky rotates its
refresh token) leaves the panel with the new one, and a later request made with this component's older copy would
be rejected -- so every update starts from the latest.
-}
withLatestAccount : Shared.Model -> Model -> Model
withLatestAccount shared model =
    case Actions.usableAccounts shared.accounts |> List.filter (\account -> Actions.accountId account == Actions.accountId model.account) |> List.head of
        Just latest ->
            { model | account = latest }

        Nothing ->
            model


{-| Takes up the account a request refreshed (`Just` when its token was rotated on the way) right away: the
Accounts Panel only gets it with the forwarded message, which lands after whatever this update starts next -- the
refetch after an upload, say -- so that request would otherwise go out with the pre-refresh token.
-}
withRotation : Maybe AccountsPanel.Msg -> Model -> Model
withRotation maybeAccountsPanelMsg model =
    case maybeAccountsPanelMsg of
        Just (AccountsPanel.MastodonAccountRefreshed refreshed) ->
            { model | account = MastodonServerAccount refreshed }

        Just (AccountsPanel.BlueskyAccountRefreshed refreshed) ->
            { model | account = BlueskyServerAccount refreshed }

        _ ->
            model


update : Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update shared msg unrefreshed =
    let
        model : Model
        model =
            withLatestAccount shared unrefreshed

        isCurrent : String -> Bool
        isCurrent accountKey =
            accountKey == Actions.accountId model.account
    in
    case msg of
        GotPage accountKey requestId append result ->
            if not (isCurrent accountKey) || requestId /= model.requestId then
                ( model
                , case result of
                    Ok ( maybeAccountsPanelMsg, _, _ ) ->
                        forwardRotated maybeAccountsPanelMsg

                    Err _ ->
                        Effect.none
                )

            else
                case result of
                    Ok ( maybeAccountsPanelMsg, posts, next ) ->
                        let
                            newItems : List Item
                            newItems =
                                itemsOf posts
                        in
                        ( { model
                            | account = (withRotation maybeAccountsPanelMsg model).account
                            , items =
                                if append then
                                    model.items ++ List.filter (\item -> not (List.any (\existing -> existing.id == item.id) model.items)) newItems

                                else
                                    newItems
                            , status = Loaded
                            , next = next
                            , loadingMore = False
                          }
                        , forwardRotated maybeAccountsPanelMsg
                        )

                    Err err ->
                        ( { model | status = Failed (Actions.writeErrorText err), loadingMore = False }, Effect.none )

        LoadMoreClicked ->
            case model.next of
                Just cursor ->
                    ( { model | loadingMore = True, requestId = model.requestId + 1 }
                    , fetchPage model.account (model.requestId + 1) True (Just cursor)
                    )

                Nothing ->
                    ( model, Effect.none )

        CaptionChanged newCaption ->
            ( { model | caption = newCaption }, Effect.none )

        DescriptionChanged newDescription ->
            ( { model | description = newDescription }, Effect.none )

        VisibilityChanged label ->
            ( { model | visibility = Mastodon.allVisibilities |> List.filter (\visibility -> Mastodon.visibilityLabel visibility == label) |> List.head |> Maybe.withDefault model.visibility }
            , Effect.none
            )

        UploadClicked ->
            ( model, File.Select.file (pickerTypes model.account) GotFile |> Effect.fromCmd )

        GotFile file ->
            ( { model | upload = Uploading, actionError = Nothing }
            , Actions.uploadAsPost model.account model.visibility file model.caption model.description
                |> Task.attempt (GotUploadResult (Actions.accountId model.account))
                |> Effect.fromCmd
            )

        GotUploadResult accountKey (Ok maybeAccountsPanelMsg) ->
            if not (isCurrent accountKey) then
                ( model, forwardRotated maybeAccountsPanelMsg )

            else
                -- The new post is the newest one: refetch from the top so it shows.
                let
                    rotated : Model
                    rotated =
                        withRotation maybeAccountsPanelMsg model
                in
                ( { rotated | upload = Idle, caption = "", description = "", requestId = model.requestId + 1 }
                , Effect.batch [ forwardRotated maybeAccountsPanelMsg, fetchPage rotated.account (model.requestId + 1) False Nothing ]
                )

        GotUploadResult accountKey (Err err) ->
            if not (isCurrent accountKey) then
                ( model, Effect.none )

            else
                ( { model
                    | upload =
                        UploadFailed
                            (case err of
                                Http.BadBody "unsupported-media-type" ->
                                    "Bluesky takes images only here."

                                _ ->
                                    Actions.writeErrorText err
                            )
                  }
                , Effect.none
                )

        ItemClicked itemId ->
            case List.filter (\item -> item.id == itemId) model.items |> List.head of
                Just clicked ->
                    let
                        host : String
                        host =
                            Actions.hostOf model.account

                        link : Item -> String
                        link item =
                            Posts.postHref shared.basePath shared.accounts.mainFrontendHost host item.post

                        playable : List Item
                        playable =
                            List.filter (\item -> (item.kind == AudioKind) == (clicked.kind == AudioKind)) model.items
                    in
                    ( model
                    , if clicked.kind == AudioKind then
                        Effect.batch
                            (Effect.fromShared (Shared.AudioPlayerPanelMsg (AudioPlayerPanel.Open (List.map .media playable) clicked.media.id host))
                                :: List.map
                                    (\item -> Effect.fromShared (Shared.AudioPlayerPanelMsg (AudioPlayerPanel.AttachPostUrl item.media.id host (Just (link item)))))
                                    playable
                            )

                      else
                        Effect.fromShared
                            (Shared.MediaViewerPanelMsg
                                (MediaViewerPanel.OpenWithPostLinks
                                    (List.map .media playable)
                                    (playable |> List.map (\item -> ( item.media.id, link item )) |> Dict.fromList)
                                    clicked.media.id
                                    host
                                )
                            )
                    )

                Nothing ->
                    ( model, Effect.none )

        DeleteClicked postId ->
            ( { model | confirmingDelete = Just postId, actionError = Nothing }, Effect.none )

        DeleteCancelled ->
            ( { model | confirmingDelete = Nothing }, Effect.none )

        DeleteConfirmed ->
            case model.confirmingDelete |> Maybe.andThen (\postId -> List.filter (\item -> item.post.id == postId) model.items |> List.head) of
                Just item ->
                    ( { model | deleting = True, actionError = Nothing }
                    , Actions.deletePost model.account item.post
                        |> Task.attempt (GotDeleteResult (Actions.accountId model.account) item.post.id)
                        |> Effect.fromCmd
                    )

                Nothing ->
                    ( { model | confirmingDelete = Nothing }, Effect.none )

        GotDeleteResult accountKey postId (Ok maybeAccountsPanelMsg) ->
            if not (isCurrent accountKey) then
                ( model, forwardRotated maybeAccountsPanelMsg )

            else
                ( { model
                    | account = (withRotation maybeAccountsPanelMsg model).account
                    , items = List.filter (\item -> item.post.id /= postId) model.items
                    , confirmingDelete = Nothing
                    , deleting = False
                  }
                , forwardRotated maybeAccountsPanelMsg
                )

        GotDeleteResult accountKey _ (Err err) ->
            if not (isCurrent accountKey) then
                ( model, Effect.none )

            else
                ( { model | confirmingDelete = Nothing, deleting = False, actionError = Just (Actions.writeErrorText err) }, Effect.none )



-- VIEW


view : Shared.Model -> Model -> Html Msg
view shared model =
    let
        platform : String
        platform =
            case model.account of
                MastodonServerAccount account ->
                    account.instanceHost

                BlueskyServerAccount _ ->
                    "Bluesky"
    in
    div [ class "federated-my-media" ]
        [ div [ class "federated-my-media-warning", attribute "role" "note" ]
            [ text
                (case model.account of
                    MastodonServerAccount _ ->
                        "Uploading here creates a post for you on " ++ platform ++ ". Mastodon only keeps media attached to a post, so its caption becomes the post's text and the visibility below applies."

                    BlueskyServerAccount _ ->
                        "Uploading here creates a post for you on Bluesky (public, like all Bluesky posts). Bluesky only keeps media attached to a post, so its caption becomes the post's text. Images only for now."
                )
            ]
        , uploadForm model
        , case model.actionError of
            Just err ->
                div [ class "media-feed-message media-feed-error" ] [ text err ]

            Nothing ->
                text ""
        , case model.status of
            Loading ->
                if List.isEmpty model.items then
                    div [ class "media-feed-message" ] [ text "Loading…" ]

                else
                    grid shared model

            Failed err ->
                div [ class "media-feed-message media-feed-error" ] [ text (platform ++ ": " ++ err) ]

            Loaded ->
                if List.isEmpty model.items then
                    div [ class "media-feed-message" ] [ text ("None of your posts on " ++ platform ++ " have media yet.") ]

                else
                    grid shared model
        , if model.next /= Nothing then
            button [ class "media-feed-load-more", onClick LoadMoreClicked, Html.Attributes.disabled model.loadingMore ]
                [ text
                    (if model.loadingMore then
                        "Loading…"

                     else
                        "Load more"
                    )
                ]

          else
            text ""
        ]


uploadForm : Model -> Html Msg
uploadForm model =
    div [ class "federated-my-media-upload" ]
        [ textarea
            [ class "server-details-rename-input"
            , placeholder "Caption (the post's text)"
            , value model.caption
            , onInput CaptionChanged
            , Html.Attributes.rows 2
            ]
            []
        , input
            [ class "server-details-rename-input"
            , placeholder "Description of the media (alt text)"
            , value model.description
            , onInput DescriptionChanged
            ]
            []
        , div [ class "federated-my-media-upload-actions" ]
            [ case model.account of
                MastodonServerAccount _ ->
                    select [ class "server-details-rename-input", onInput VisibilityChanged, attribute "aria-label" "Who can see the post" ]
                        (Mastodon.allVisibilities
                            |> List.map
                                (\visibility ->
                                    option
                                        [ value (Mastodon.visibilityLabel visibility), selected (visibility == model.visibility) ]
                                        [ text (Mastodon.visibilityLabel visibility) ]
                                )
                        )

                BlueskyServerAccount _ ->
                    text ""
            , button
                [ classes [ "server-details-rename-save", "background-color-primary" ]
                , onClick UploadClicked
                , Html.Attributes.disabled (model.upload == Uploading)
                ]
                [ text
                    (if model.upload == Uploading then
                        "Uploading…"

                     else
                        "Upload & post"
                    )
                ]
            ]
        , case model.upload of
            UploadFailed err ->
                div [ class "server-details-rename-error" ] [ text err ]

            _ ->
                text ""
        ]


grid : Shared.Model -> Model -> Html Msg
grid shared model =
    div [ class "federated-my-media-grid" ] (List.map (tile shared model) model.items)


tile : Shared.Model -> Model -> Item -> Html Msg
tile shared model item =
    let
        host : String
        host =
            Actions.hostOf model.account

        title : String
        title =
            case item.media.name |> Maybe.map (FedMedia.plainTitle 60) |> Maybe.andThen nonBlank of
                Just name ->
                    name

                Nothing ->
                    item.post.content
                        |> Maybe.map (FedMedia.plainTitle 60)
                        |> Maybe.andThen nonBlank
                        |> Maybe.withDefault "Untitled"

        confirming : Bool
        confirming =
            model.confirmingDelete == Just item.post.id
    in
    div [ class "federated-my-media-tile" ]
        [ button [ class "federated-my-media-thumb", onClick (ItemClicked item.id), attribute "aria-label" ("Open " ++ title) ]
            [ case ( item.kind, item.media.url ) of
                ( ImageKind, Just url ) ->
                    img [ src url, attribute "alt" title, attribute "loading" "lazy" ] []

                ( VideoKind, _ ) ->
                    case item.media.url |> Maybe.andThen VideoPoster.posterUrl of
                        Just url ->
                            img [ src url, attribute "alt" "", attribute "loading" "lazy" ] []

                        Nothing ->
                            span [ class "media-card-thumb-placeholder" ] [ text "🎬" ]

                ( AudioKind, _ ) ->
                    span [ class "media-card-thumb-placeholder" ] [ text "🎵" ]

                _ ->
                    span [ class "media-card-thumb-placeholder" ] [ text "🖼️" ]
            , if item.kind == ImageKind then
                text ""

              else
                span [ class "media-card-play" ] [ text Glyph.play ]
            ]
        , div [ class "federated-my-media-caption" ]
            [ span [ class "federated-my-media-title" ] [ text title ]
            , div [ class "federated-my-media-actions" ]
                [ a [ class "federated-my-media-link", href (Posts.postHref shared.basePath shared.accounts.mainFrontendHost host item.post) ] [ text "View post" ]
                , if confirming then
                    span []
                        [ text "Delete this post? "
                        , button [ class "media-page-delete-confirm-yes", onClick DeleteConfirmed, Html.Attributes.disabled model.deleting ] [ text "Delete" ]
                        , button [ onClick DeleteCancelled ] [ text "Cancel" ]
                        ]

                  else
                    button [ class "federated-my-media-delete", onClick (DeleteClicked item.post.id), attribute "title" "Deletes the whole post" ] [ text "Delete" ]
                ]
            ]
        ]


nonBlank : String -> Maybe String
nonBlank s =
    if String.isEmpty (String.trim s) then
        Nothing

    else
        Just (String.trim s)
